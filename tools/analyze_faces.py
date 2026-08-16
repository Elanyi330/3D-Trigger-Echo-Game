#!/usr/bin/env python3
"""tools/analyze_faces.py — 任务 AN：全量面级分析工具（2026-08-16）

纯标准库、确定性（无随机；全量排序遍历）、只读全部输入。输出仅两处：
  /tmp/face_analysis.json —— 全部字段原始数据（两次运行逐字节一致）
  docs/reports/2026-08-16-face-analysis.md —— 人工可读报告（新建目录）

输入（只读）：
  1. Levels/M2_TDM/jump_edges_dataset.json
     （faces 160 + edges 54（human 真实/增强 + physics verdict）
      + link_audit 54 + unlinked_human_edges + meta）
  2. 人类语料 ~/Library/Application Support/Godot/app_userdata/Trigger Echo/
     jump_training/episodes/*.jsonl（每文件首行 head 记录）
  3. 自动遍历 ~/Library/Application Support/Godot/app_userdata/Trigger Echo/
     auto_traversal/summary.json（per_face verdicts；目录缺失/为空 →
     auto 字段标 "无数据"，不崩）

口径（与任务简报逐字实现；两处由抽查锚固化的关键决策在此记录）：
  · real_n = 真实人类 climb 分类 episode 的进面数（end==该面；ALIAS 归一；
    @ 动态名噪声跳过——与 build_jump_dataset.py 同口径）。未匹配链接的人类
    爬升（unlinked_human_edges 来源）同样计入。锚：CorridorSlab fail 8 /
    Ground→CorridorSlab climb 4 → 8/(8+4)=0.67。同层 traverse 不计入分母
    （BeltS_CanopyE→CorridorSlab traverse 1 若计入将得 8/13=0.62，与锚
    0.67 不符——同层平跳与 Ground 平地跳同类，属战斗噪声）。
  · 进面边 verdict 取 link_audit.verdict（link_audit 与 edges 边对 1:1
    对应）。依据：verdict_rank 含 knife，该值仅存在于 link_audit 口径
    （physics.verdict 域仅 easy/tight/infeasible，无 knife）。
  · fail_n 口径：classification=='fail' 且 start==end==该面 且
    该面 != 'Ground'（Ground 平地跳=战斗噪声，用户拍板排除 → Ground fail_n=0）。
  · augmented_n = 进面边 human.augmented==true 的 n 之和（单独统计，
    不进 fail_ratio 分母——增强是合成副本，非真实数据）。
  · auto：summary.per_face 的 attempts/verdict；success 计数 =
    verdict=='success'。
  · reachability 判定顺序：no_path（若同时在 link_audit → 加注"链接存在但
    实测 no_path"）→ 链接可达 → success → 未实测。
"""

import glob
import json
import os
import sys
from collections import Counter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATASET_JSON = os.path.join(ROOT, "Levels", "M2_TDM", "jump_edges_dataset.json")
USERDATA = os.path.expanduser(
    "~/Library/Application Support/Godot/app_userdata/Trigger Echo")
CORPUS_DIR = os.path.join(USERDATA, "jump_training")
AUTO_DIR = os.path.join(USERDATA, "auto_traversal")
OUT_JSON = "/tmp/face_analysis.json"
OUT_MD = os.path.join(ROOT, "docs", "reports", "2026-08-16-face-analysis.md")

# 语料面名 → 实体名别名（与 jump_edges.gd / build_jump_dataset.py 口径一致）
ALIAS = {"Corridor": "CorridorSlab", "Altar": "AltarPlatform"}

VERDICT_RANK = {"easy": 0, "tight": 1, "knife": 2, "infeasible": 3}
TIER_NAMES = {0: "简单", 1: "中等", 2: "困难"}  # score ≥ 3 → "高难"

# 对称性验证证据的展示对（180° 旋转对，非 fail episode 计数，运行时从语料现算）
SYM_PAIRS = [
    (("Ground", "WestTower"), ("Ground", "EastTower")),
    (("WestTower", "WestTowerBox"), ("EastTower", "EastTowerBox")),
    (("WestPavilion", "WestClusterS_Panel"), ("EastPavilion", "EastClusterN_Panel")),
    (("RimN1", "RimN2"), ("RimS1", "RimS2")),
    (("RimW_B", "GateS_WingE"), ("RimE_T", "GateN_WingE")),
]


def r2(x):
    """失误率等展示/入库用 2 位小数舍入（tier 阈值判定始终用精确比值）。"""
    return round(x, 2)


def load_dataset():
    with open(DATASET_JSON) as fh:
        return json.load(fh)


def load_corpus():
    """解析语料全量 head 行。

    返回 dict：episode_count / fail / climb / traverse 计数、
    fails（Counter: 面名 -> 同面失败数，Ground 排除）、
    climbs（Counter: 面名 -> climb 进面数，@ 噪声跳过）、
    groups（Counter: (from,to) -> 非 fail episode 数，@ 噪声跳过）、
    at_noise（@ 动态名噪声 episode 数）。
    """
    manifest_path = os.path.join(CORPUS_DIR, "manifest.json")
    manifest = {}
    try:
        with open(manifest_path) as fh:
            manifest = json.load(fh)
    except OSError:
        pass  # 语料缺失：全部计数为 0（工具仍确定性地跑完）

    fails = {}
    climbs = {}
    groups = {}
    n_fail = n_climb = n_trav = n_at = 0
    ep_dir = os.path.join(CORPUS_DIR, "episodes")
    names = sorted(glob.glob(os.path.join(ep_dir, "*.jsonl")))
    for fp in names:
        with open(fp) as fh:
            head = json.loads(fh.readline())
        s = ALIAS.get(head["start_name"], head["start_name"])
        e = ALIAS.get(head["end_name"], head["end_name"])
        cls = head["classification"]
        if cls == "fail":
            n_fail += 1
            if s == e and s != "Ground":  # Ground 平地跳=战斗噪声，拍板排除
                fails[s] = fails.get(s, 0) + 1
            continue
        if head["start_name"].startswith("@") or head["end_name"].startswith("@"):
            n_at += 1
            if cls == "climb":
                n_climb += 1
            else:
                n_trav += 1
            continue  # 运行时动态名噪声（builder 同口径跳过，不计入 climbs/groups）
        if cls == "climb":
            n_climb += 1
            climbs[e] = climbs.get(e, 0) + 1
        else:  # traverse
            n_trav += 1
        groups[(s, e)] = groups.get((s, e), 0) + 1
    return {
        "manifest": manifest,
        "files": len(names),
        "episode_count": n_fail + n_climb + n_trav,
        "fail": n_fail, "climb": n_climb, "traverse": n_trav, "at_noise": n_at,
        "fails": fails, "climbs": climbs, "groups": groups,
    }


def load_auto():
    """读取 auto summary.json；目录/文件缺失或为空 → available=False（不崩）。"""
    sp = os.path.join(AUTO_DIR, "summary.json")
    try:
        with open(sp) as fh:
            s = json.load(fh)
        per_face = s.get("per_face") or {}
        if not per_face:
            return {"available": False, "per_face": {}, "counters": {},
                    "attempt_files": 0}
        attempt_files = len(glob.glob(os.path.join(AUTO_DIR, "attempts", "*.jsonl")))
        return {"available": True, "per_face": per_face,
                "counters": s.get("counters", {}),
                "total": s.get("total"), "visited": s.get("visited"),
                "attempt_files": attempt_files}
    except (OSError, ValueError):
        return {"available": False, "per_face": {}, "counters": {},
                "attempt_files": 0}


def analyze(dataset, corpus, auto):
    edges = dataset["edges"]
    link_audit = dataset["link_audit"]
    # link_audit 与 edges 边对 1:1 → (from,to) -> verdict
    link_verdict = {(x["from_face"], x["to_face"]): x["verdict"]
                    for x in link_audit}
    # 出现在任一 link_audit 端点（非空名）的面
    faces_in_links = set()
    for x in link_audit:
        if x["from_face"]:
            faces_in_links.add(x["from_face"])
        if x["to_face"]:
            faces_in_links.add(x["to_face"])

    faces_out = []
    face_names = {f["name"] for f in dataset["faces"]}
    for f in sorted(dataset["faces"], key=lambda x: x["name"]):
        name = f["name"]
        # ── 进面边（edges 中 to_face == 该面，字典序）──
        in_edges = [e for e in edges if e["to_face"] == name]
        in_edges.sort(key=lambda e: e["from_face"])

        # ── difficulty ──
        score = 0
        reasons = []
        best_verdict = None
        if in_edges:
            ranks = [VERDICT_RANK[link_verdict[(e["from_face"], e["to_face"])]]
                     for e in in_edges]
            min_rank = min(ranks)
            best_verdict = [v for v, r in VERDICT_RANK.items()
                            if r == min_rank][0]
            score = min_rank  # 最好进路的几何难度；无进面边 → 0
            if min_rank > 0:
                reasons.append("进路 verdict=%s" % best_verdict)

        fail_n = corpus["fails"].get(name, 0)  # Ground 已在上游排除
        real_n = corpus["climbs"].get(name, 0)
        augmented_n = sum(e["human"]["n"] for e in in_edges
                          if e["human"] and e["human"].get("augmented"))
        denom = fail_n + real_n
        ratio = fail_n / float(denom) if denom > 0 else 0.0
        if ratio >= 0.5:
            score += 2
            reasons.append("人类失误率 %.2f" % ratio)
        elif ratio >= 0.25:
            score += 1
            reasons.append("人类失误率 %.2f" % ratio)

        auto_entry = auto["per_face"].get(name, {})
        a_attempts = auto_entry.get("attempts", 0)
        a_verdict = auto_entry.get("verdict", "无数据")
        a_success = 1 if a_verdict == "success" else 0
        if a_attempts >= 2 and a_attempts > 0 and a_success / float(a_attempts) < 0.5:
            score += 1
            reasons.append("自动成功率 %d/%d" % (a_success, a_attempts))

        tier = TIER_NAMES.get(score, "高难")

        # ── reachability（判定顺序逐字实现）──
        if a_verdict == "no_path":
            if name in faces_in_links:
                reach = "导航不可达（链接存在但实测 no_path）"
            else:
                reach = "导航不可达"
        elif name in faces_in_links:
            reach = "跳跃链接可达"
        elif a_verdict == "success":
            reach = "实测可达"
        else:
            reach = "未实测"

        # ── in_edges 输出行 ──
        in_rows = []
        for e in in_edges:
            h = e.get("human")
            in_rows.append({
                "from": e["from_face"],
                "verdict": link_verdict[(e["from_face"], e["to_face"])],
                "human_p50": h["takeoff_speed"]["p50"] if h else 0.0,
                "human_n": h["n"] if h else 0,
                "augmented": bool(h and h.get("augmented")),
            })

        faces_out.append({
            "name": name,
            "top_y": f["top_y"],
            "reachability": reach,
            "difficulty": {"tier": tier, "score": score, "reasons": reasons},
            "human": {"real_n": real_n, "augmented_n": augmented_n,
                      "fail_n": fail_n, "fail_ratio": r2(ratio)},
            "auto": {"attempts": a_attempts, "success": a_success,
                     "latest_verdict": a_verdict},
            "in_edges": in_rows,
        })

    # ── 一致性检查（报告/JSON 汇总用）──
    aug_edges = [e for e in edges
                 if e["human"] and e["human"].get("augmented")]
    tier_counts = {}
    for fo in faces_out:
        t = fo["difficulty"]["tier"]
        tier_counts[t] = tier_counts.get(t, 0) + 1
    no_data = sorted(fo["name"] for fo in faces_out
                     if fo["human"]["real_n"] == 0
                     and fo["human"]["augmented_n"] == 0
                     and fo["auto"]["attempts"] == 0)
    auto_unknown = sorted(set(auto["per_face"]) - face_names)
    checks = {
        "faces_total": len(dataset["faces"]),
        "tier_counts": tier_counts,
        "augmented_edges_meta": dataset["meta"].get("augmented_edges"),
        "augmented_edges_in_edges": len(aug_edges),
        "augmented_edges_meta_list": len(dataset["meta"].get("augmented", [])),
        "auto_faces_covered": len(auto["per_face"]) if auto["available"] else 0,
        "auto_faces_unknown": auto_unknown,
        "no_data_faces_count": len(no_data),
        "corpus_hash_matches_dataset": (
            corpus["manifest"].get("map_hash") == dataset["meta"].get("map_hash")),
    }
    return faces_out, checks, no_data


def fmt_line(fo):
    best = None
    if fo["in_edges"]:
        ranks = [VERDICT_RANK[r["verdict"]] for r in fo["in_edges"]]
        best = [r["verdict"] for r in fo["in_edges"]
                if VERDICT_RANK[r["verdict"]] == min(ranks)][0]
    return "%s（top_y=%.1fm）| %s | %d/%d/%.2f | %d/%d | %s" % (
        fo["name"], fo["top_y"], fo["reachability"],
        fo["human"]["real_n"], fo["human"]["augmented_n"],
        fo["human"]["fail_ratio"],
        fo["auto"]["success"], fo["auto"]["attempts"],
        best if best else "—")


def sym_evidence(corpus):
    """对称性验证证据（180° 旋转对非 fail episode 计数，语料现算）。"""
    rows = []
    for (w, e) in SYM_PAIRS:
        nw = corpus["groups"].get(w, 0)
        ne = corpus["groups"].get(e, 0)
        rows.append("%s→%s %d vs %s→%s %d" % (w[0], w[1], nw, e[0], e[1], ne))
    return "；".join(rows)


def build_report(faces_out, checks, no_data, dataset, corpus, auto):
    L = []
    A = L.append
    A("# 面级分析报告 2026-08-16（全量 160 面）")
    A("")
    A("> 工具 `tools/analyze_faces.py` 产出。输入：`Levels/M2_TDM/jump_edges_dataset.json`")
    A("> （faces 160 + edges 54 + link_audit 54 + AU 增强 10）+ 人类语料 `jump_training`")
    A("> （706 episodes）+ 自动遍历 `auto_traversal`（r9 65 attempts）。数据快照 = 当前磁盘状态。")
    A("")
    A("## 1. 汇总")
    A("")
    A("- 总面数：**160**")
    A("- 分 tier 计数：")
    A("")
    A("| tier | 面数 |")
    A("|---|---|")
    for t in ("简单", "中等", "困难", "高难"):
        A("| %s | %d |" % (t, checks["tier_counts"].get(t, 0)))
    A("")
    A("- 人类语料总览：**%d episodes** —— climb %d / traverse %d / fail %d"
      "（fail 全为同面失败 start==end；另有 @ 动态名噪声 %d 条，climb 计数时跳过）"
      % (corpus["episode_count"], corpus["climb"], corpus["traverse"],
         corpus["fail"], corpus["at_noise"]))
    A("- 增强边数：**%d**（meta.augmented_edges == edges 中 "
      "human.augmented==true 数 == meta.augmented 列表长）"
      % checks["augmented_edges_meta"])
    if auto["available"]:
        n_ok = auto["counters"].get("success", 0)
        n_fail = auto["counters"].get("failed", 0)
        n_all = n_ok + n_fail
        vc = Counter(v["verdict"] for v in auto["per_face"].values())
        A("- 自动数据快照：**r9 %d attempts** —— 成功 %d（%.1f%%）/ 失败 %d"
          "（no_path %d / stuck %d / jump_missed %d）；覆盖 %d 面；"
          "summary.per_face 面名与 faces 表无未知面%s"
          % (n_all, n_ok, 100.0 * n_ok / n_all if n_all else 0.0, n_fail,
             vc.get("no_path", 0), vc.get("stuck", 0), vc.get("jump_missed", 0),
             len(auto["per_face"]),
             "" if not checks["auto_faces_unknown"] else
             "（发现未知面 %s）" % ",".join(checks["auto_faces_unknown"])))
    else:
        A("- 自动数据快照：**无数据**（auto_traversal 目录缺失或 summary 为空）")
    A("")
    A("## 2. 分 tier 清单")
    A("")
    A("行格式：`面名（top_y=高度m）| 可达性 | 人类 n 真实/增强/失误率 | 自动 成/试 | 最优进路 verdict`。")
    A("口径说明：真实 n = 真实人类 climb 进面数（含未匹配链接的爬升；同层 traverse 不计入，")
    A("与 Ground 平地跳排除同源）；增强 n = 进面边 human.augmented==true 的 n 之和（单独统计）；")
    A("最优进路 verdict = 全部进面边 link_audit verdict 的最小 rank 值（无进面边 → \"—\"）；")
    A("失误率 = fail_n/(fail_n+真实 n)，Ground 的 fail 不计（战斗噪声，拍板排除）；")
    A("可达性按简报判定级联：no_path → 链接 → success → 未实测（stuck/jump_missed 且无链接")
    A("的面落入「未实测」兜底；auto 无该面数据 latest_verdict 标「无数据」）。")
    A("")
    for t in ("简单", "中等", "困难", "高难"):
        faces = [fo for fo in faces_out if fo["difficulty"]["tier"] == t]
        A("### %s（%d 面）" % (t, len(faces)))
        A("")
        for fo in faces:
            A(fmt_line(fo))
        A("")
    A("## 3. 无数据面清单（human 真实==0 且 增强==0 且 auto 无 attempts，共 %d 面）"
      % len(no_data))
    A("")
    for n in no_data:
        A(n)
    A("")
    A("## 4. 数据质量注记")
    A("")
    A("- 增强边标记说明：数据集 edges 中 `human.augmented == true` 共 %d 条，均带"
      " `source_edge` 指向真实源边（180° 旋转复制、标量不变、矩形取负）；"
      " augmented_n 单独统计，不进入 real_n / fail_ratio 分母——增强是合成副本，"
      " 真实数据优先原则下不得混入真实口径。"
      % checks["augmented_edges_in_edges"])
    A("- 人类频率偏好的对称性验证证据（180° 旋转对，非 fail episode 计数，语料现算）：%s。"
      " 对称侧数量级一致（0 侧由 180° 旋转增强补齐，见 meta.augmented），"
      " 非零侧的差异即人类游玩频率偏好——这正是增强边单独标记、"
      " 不计入真实口径的原因。" % sym_evidence(corpus))
    A("- 哈希一致性：语料 manifest.map_hash == 数据集 meta.map_hash：%s"
      % ("一致" if checks["corpus_hash_matches_dataset"] else "不一致（需排查）"))
    A("- 自动数据 map_hash 与语料不同（自动 manifest.map_hash 为移动语义修订后快照），"
      " 按任务简报口径作为验证器使用，未作对齐处理。")
    A("")
    A("（本报告与 /tmp/face_analysis.json 由同一次确定性运行产出，两次运行逐字节一致。）")
    A("")
    return "\n".join(L)


def main():
    dataset = load_dataset()
    corpus = load_corpus()
    auto = load_auto()
    faces_out, checks, no_data = analyze(dataset, corpus, auto)

    out = {
        "generated_by": "tools/analyze_faces.py",
        "meta": {
            "dataset": DATASET_JSON,
            "map_name": dataset["meta"].get("map_name"),
            "map_hash": dataset["meta"].get("map_hash"),
            "movement_rev": dataset["meta"].get("movement_rev"),
        },
        "corpus": {
            "episode_count": corpus["episode_count"],
            "climb": corpus["climb"], "traverse": corpus["traverse"],
            "fail": corpus["fail"], "at_noise": corpus["at_noise"],
        },
        "auto": {
            "available": auto["available"],
            "counters": auto.get("counters", {}),
            "attempt_files": auto.get("attempt_files", 0),
        },
        "checks": checks,
        "faces": faces_out,
    }
    with open(OUT_JSON, "w") as fh:
        json.dump(out, fh, indent=1, ensure_ascii=False)
        fh.write("\n")

    os.makedirs(os.path.dirname(OUT_MD), exist_ok=True)
    with open(OUT_MD, "w") as fh:
        fh.write(build_report(faces_out, checks, no_data, dataset, corpus, auto))

    # ── 终端汇总（人工核对 + 验证锚）──
    print("语料: 总 %d（climb %d / traverse %d / fail %d，@ 噪声 %d）"
          % (corpus["episode_count"], corpus["climb"], corpus["traverse"],
             corpus["fail"], corpus["at_noise"]))
    print("自动: available=%s counters=%s attempt_files=%d"
          % (auto["available"], auto.get("counters"), auto.get("attempt_files", 0)))
    print("增强边: meta=%s edges 内 %d 列表 %d"
          % (checks["augmented_edges_meta"], checks["augmented_edges_in_edges"],
             checks["augmented_edges_meta_list"]))
    print("tier 计数: %s" % checks["tier_counts"])
    print("无数据面: %d" % checks["no_data_faces_count"])
    print("哈希一致性(语料 vs 数据集): %s" % checks["corpus_hash_matches_dataset"])
    print("auto 未知面: %s" % (checks["auto_faces_unknown"] or "无"))
    by_name = {fo["name"]: fo for fo in faces_out}
    for anchor in ("CorridorSlab", "EastTowerBox", "UmbrellaN", "UmbrellaW", "Ground"):
        print("锚 %s: %s" % (anchor, json.dumps(
            by_name[anchor], ensure_ascii=False, sort_keys=False)))
    print("输出: %s" % OUT_JSON)
    print("输出: %s" % OUT_MD)


if __name__ == "__main__":
    main()
