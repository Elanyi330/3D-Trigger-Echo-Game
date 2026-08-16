#!/usr/bin/env python3
# tools/build_jump_dataset.py — T4 工具2（2026-08-13）
# 从人类跳跃语料反推每条跳跃边的人类起跳参数分布，与几何边（/tmp/jump_edges.json，
# 由 tools/export_jump_edges.gd 先导出）合并，产出 M4 AI 消费的数据集。
#
# 输入：
#   /tmp/jump_edges.json —— 几何面/边组/链接（export_jump_edges.gd 产出）
#   语料目录 user://jump_training（manifest.json + episodes/*.jsonl，只读，绝不写回）
# 输出：Levels/M2_TDM/jump_edges_dataset.json（入库文件，路径不可改）
#
# 铁律（哈希门禁）：语料 manifest.map_hash 必须 == /tmp/jump_edges.json 的
# current_map_hash，否则 stderr 打印差异并 exit 1——老图数据不得进入新数据集。
# 纯标准库、确定性输出（无随机；排序一律 sort 默认）。
#
# 物理常量（与求解器 T3 JumpSolver 同源）：G=19.6、V_JUMP=7.54、DT=1/60、
# SPEED_CAP=6.35、CATCH_BAND=0.5；脚 = py − 0.915。离散闭合式
# rise(n) = n·V_JUMP·DT − G·DT·DT·n·(n−1)/2（n 帧，n≤0 → 0）。

import json
import os
import sys

G = 19.6
V_JUMP = 7.54
DT = 1.0 / 60.0
SPEED_CAP = 6.35
CATCH_BAND = 0.5
FEET_OFFSET = 0.915
MAX_FRAMES = 120  # 扫描上限（JumpSolver 同值：2s > 同高全程 47 帧）

ROT_EPS = 0.05  # 180° 旋转面配对中心容差（面表几何驱动；导出值 snappedf 0.001）

CORPUS_DIR = os.path.expanduser(
    "~/Library/Application Support/Godot/app_userdata/Trigger Echo/jump_training")
EDGES_JSON = "/tmp/jump_edges.json"
OUT_JSON = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "Levels", "M2_TDM", "jump_edges_dataset.json")

# 语料面名 → 实体名别名（与 jump_edges.gd / layout 注释口径一致）
ALIAS = {"Corridor": "CorridorSlab", "Altar": "AltarPlatform"}


def rise(n):
    """离散闭合式位移：rise(n) = n·V_JUMP·DT − G·DT·DT·n·(n−1)/2（n≤0 → 0）。"""
    if n <= 0:
        return 0.0
    return n * V_JUMP * DT - G * DT * DT * n * (n - 1) / 2.0


def catch_window(delta_h):
    """满足 rise(n) ≥ delta_h − CATCH_BAND 的帧区间 [f_min, f_max]；无解 → None。"""
    threshold = delta_h - CATCH_BAND
    f_min = -1
    f_max = -1
    for n in range(0, MAX_FRAMES + 1):
        if rise(n) >= threshold:
            if f_min == -1:
                f_min = n
            f_max = n
    if f_max == -1:
        return None
    return (f_min, f_max)


def feasibility(delta_h, dist):
    """窗口 + 必需速度判定（JumpSolver.feasibility 同公式）。
    无解 → infeasible；dist ≤ 0 → v_req 0、easy；v_req > 6.35 → infeasible；
    margin = 1 − v_req/6.35：≥0.2 easy / ≥0.05 tight / 其余 knife。"""
    w = catch_window(delta_h)
    if w is None:
        return {"v_req": 0.0, "verdict": "infeasible"}
    if dist <= 0.0:
        return {"v_req": 0.0, "verdict": "easy"}
    t_max = w[1] / 60.0
    v_req = dist / t_max
    if v_req > SPEED_CAP:
        return {"v_req": round(v_req, 3), "verdict": "infeasible"}
    margin = 1.0 - v_req / SPEED_CAP
    if margin >= 0.2:
        verdict = "easy"
    elif margin >= 0.05:
        verdict = "tight"
    else:
        verdict = "knife"
    return {"v_req": round(v_req, 3), "verdict": verdict}


def quantile(vals, p):
    """排序取索引：idx = int(p·n/100)（钳到 n−1）。p50 即 s[len//2]，
    与 tools/jump_study.py 的 med() 一致。"""
    s = sorted(vals)
    if not s:
        return 0.0
    idx = min(int(p * len(s) / 100.0), len(s) - 1)
    return s[idx]


def r3(x):
    return round(x, 3)


def rect_dist(za, zb):
    """两矩形（{"center":{"x","z"},"size":{"x","z"}}）水平最短距：
    各分量 |中心差| − 半宽高之和，负归 0 后取模（jump_edges._rect_dist 同公式）。"""
    ca, sa = za["center"], za["size"]
    cb, sb = zb["center"], zb["size"]
    dx = abs(cb["x"] - ca["x"]) - (sa["x"] + sb["x"]) * 0.5
    dz = abs(cb["z"] - ca["z"]) - (sa["z"] + sb["z"]) * 0.5
    return (max(dx, 0.0) ** 2 + max(dz, 0.0) ** 2) ** 0.5


def bbox_rect(pts):
    """样本 (px,pz) 包围盒 → {"x","z","w","h"}。"""
    xs = [p[0] for p in pts]
    zs = [p[1] for p in pts]
    return {"x": r3(min(xs)), "z": r3(min(zs)),
            "w": r3(max(xs) - min(xs)), "h": r3(max(zs) - min(zs))}


# 配对几何容差（尺寸差/顶高差为 0 才算合格配对；0.002 覆盖 0.001 舍入尾差）
PAIR_GEO_TOL = 0.002


def build_rot_map(faces):
    """180° 旋转面配对（面表几何驱动，非字符串替换）：
    rot(center) = (-x, -z)。候选 = 中心距离 ≤ ROT_EPS 的面；候选内按
    (尺寸差, top_y 差, 中心距) 字典序取最优——处理嵌套共心面歧义
    （原点簇 Ground/AltarPlatform/CorridorSlab/Pedestal 四面共心、
    EastTower/EastTowerBox 等塔身/塔上箱共心：naive 最近中心会被同心的
    大面抢占，导致配对非对合。尺寸优先即可消歧）。
    合格候选须尺寸差与 top_y 差 ≤ PAIR_GEO_TOL（180° 旋转对称是设计硬
    约束，配对面几何必须一致——防静默错配）。
    违例情形：无候选 / 并列歧义 / 几何不一致 / 对合失败（rot(rot(f))≠f）。
    返回 (rot_map, violations)；violations 元素 = (面名, 配对或候选, 细节)。
    """
    rot_map = {}
    violations = []
    for f in faces:
        rx, rz = -f["center"]["x"], -f["center"]["z"]
        cands = []
        for g in faces:
            d = ((g["center"]["x"] - rx) ** 2
                 + (g["center"]["z"] - rz) ** 2) ** 0.5
            if d <= ROT_EPS:
                sd = (abs(g["size"]["x"] - f["size"]["x"])
                      + abs(g["size"]["z"] - f["size"]["z"]))
                td = abs(g["top_y"] - f["top_y"])
                cands.append((sd, td, d, g["name"]))
        if not cands:
            violations.append((f["name"], None, "无旋转配对候选"))
            continue
        cands.sort()
        if len(cands) > 1 and cands[0][:3] == cands[1][:3]:
            violations.append(
                (f["name"], [c[3] for c in cands if c[:3] == cands[0][:3]],
                 "并列歧义"))
            continue
        sd, td, d, best = cands[0]
        if sd > PAIR_GEO_TOL or td > PAIR_GEO_TOL:
            violations.append(
                (f["name"], best, "几何不一致 sizeΔ=%.3f top_yΔ=%.3f d=%.3f"
                 % (sd, td, d)))
            continue
        rot_map[f["name"]] = best
    # 对合校验（防映射冲突）
    for f, g in rot_map.items():
        if rot_map.get(g) != f:
            violations.append((f, g, "对合失败 rot(rot(f))≠f"))
    return rot_map, violations


def load_corpus():
    with open(os.path.join(CORPUS_DIR, "manifest.json")) as fh:
        manifest = json.load(fh)
    episodes = []
    ep_dir = os.path.join(CORPUS_DIR, "episodes")
    for name in sorted(os.listdir(ep_dir)):
        if not name.endswith(".jsonl"):
            continue
        with open(os.path.join(ep_dir, name)) as fh:
            head = json.loads(fh.readline())
            frames = [json.loads(line) for line in fh]
        episodes.append((name, head, frames))
    return manifest, episodes


def main():
    # ── 几何输入 ──
    with open(EDGES_JSON) as fh:
        geo = json.load(fh)
    faces = {f["name"]: f for f in geo["faces"]}
    geom_groups = geo["groups"]
    geom_pairs = {(g["from_face"], g["to_face"]) for g in geo["groups"]}

    # ── 语料输入 ──
    manifest, episodes = load_corpus()

    # ── 哈希门禁（铁律）──
    if manifest["map_hash"] != geo["current_map_hash"]:
        sys.stderr.write(
            "哈希门禁失败：语料 manifest.map_hash=%s\n"
            "            ≠ /tmp/jump_edges.json current_map_hash=%s\n"
            "老图数据不得进入新数据集——重建 /tmp/jump_edges.json 或重置语料。\n"
            % (manifest["map_hash"], geo["current_map_hash"]))
        sys.exit(1)

    # ── 180° 旋转面配对 + 对称性门禁（fail-safe）──
    # 违例即跳过全部增强（数据集照常产出、exit 0），但警告必须醒目。
    rot_map, rot_violations = build_rot_map(geo["faces"])
    if rot_violations:
        sys.stderr.write(
            "\n"
            "=" * 72 + "\n"
            "!!! 对称性门禁 FAIL：180° 旋转面配对违例 %d 条 —— 跳过全部增强\n"
            "    数据集照常产出（无 augmented 数据），exit 0。违例明细：\n"
            % len(rot_violations))
        for v in rot_violations:
            sys.stderr.write("    %s\n" % (v,))
        sys.stderr.write("=" * 72 + "\n\n")

    # ── 语料逐 episode 解析 ──
    corpus_groups = {}   # (from,to) -> 聚合桶
    kept_episodes = []   # (head, frames, chain, metrics) 供 calibrated 用
    non_fail_count = 0
    for _name, head, frames in episodes:
        if head["classification"] == "fail":
            continue
        non_fail_count += 1
        s = ALIAS.get(head["start_name"], head["start_name"])
        e = ALIAS.get(head["end_name"], head["end_name"])
        if s.startswith("@") or e.startswith("@"):
            continue  # 运行时动态名噪声
        if not frames:
            continue
        first = frames[0]
        takeoff_speed = (first["vx"] ** 2 + first["vz"] ** 2) ** 0.5
        takeoff_feet_y = first["py"] - FEET_OFFSET
        takeoff_xy = (first["px"], first["pz"])
        # 首个 on_floor==true 帧 = 接触帧（数据实测：无此类帧的 episode 为 0；
        # 兜底取末帧，防极端损坏数据崩溃）
        contact = None
        for fr in frames:
            if fr["on_floor"]:
                contact = fr
                break
        if contact is None:
            contact = frames[-1]
        contact_feet_y = contact["py"] - FEET_OFFSET
        contact_xy = (contact["px"], contact["pz"])
        flight_ms = contact["t_ms"]
        # 链式跳跃：首个 on_floor==true 之后又出现 on_floor==false
        seen_floor = False
        chain = False
        for fr in frames:
            if fr["on_floor"]:
                seen_floor = True
            elif seen_floor:
                chain = True
                break

        g = corpus_groups.setdefault((s, e), {
            "n": 0, "chain_n": 0, "speeds": [], "tf_y": [], "cf_y": [],
            "flight": [], "txy": [], "cxy": [],
        })
        g["n"] += 1
        if chain:
            g["chain_n"] += 1
        g["speeds"].append(takeoff_speed)
        g["tf_y"].append(takeoff_feet_y)
        g["cf_y"].append(contact_feet_y)
        g["flight"].append(flight_ms)
        g["txy"].append(takeoff_xy)
        g["cxy"].append(contact_xy)
        kept_episodes.append((head, chain, takeoff_feet_y, contact_feet_y))

    # ── 语料组 → human 字典（仅匹配几何边组的组；其余进 unlinked 候选）──
    def human_dict(s, e, g):
        to_top = faces[e]["top_y"]
        return {
            "from": s, "to": e,
            "n": g["n"], "chain_n": g["chain_n"],
            "takeoff_speed": {
                "p50": r3(quantile(g["speeds"], 50)),
                "p10": r3(quantile(g["speeds"], 10)),
                "p90": r3(quantile(g["speeds"], 90)),
            },
            "takeoff_feet_y": r3(quantile(g["tf_y"], 50)),
            "contact_feet_y": r3(quantile(g["cf_y"], 50)),
            "catch_depth": {
                "p50": r3(quantile([to_top - v for v in g["cf_y"]], 50)),
                "p90": r3(quantile([to_top - v for v in g["cf_y"]], 90)),
            },
            "flight_ms": r3(quantile(g["flight"], 50)),
            "takeoff_rect": bbox_rect(g["txy"]),
            "landing_rect": bbox_rect(g["cxy"]),
        }

    matched_humans = {}
    for (s, e), g in corpus_groups.items():
        if (s, e) in geom_pairs:
            matched_humans[(s, e)] = human_dict(s, e, g)

    # ── 180° 旋转增强（只填空缺；实数据优先；防增强链）──
    # 源 = 真实 human 边 (s,e)（matched_humans 在增强前只含真实数据）。
    # 其旋转对 (rot(s), rot(e))：必须在 geom_pairs 中、且无真实 human、
    # 且非自旋（rot 对 == 自身时该边必有真实数据，已被前一条排除）——
    # 才生成增强副本。增强副本的 human 字段照常参与 skill 判定
    # （chain_n/catch_depth 等全部复制，判定逻辑不改）。
    # 标量（takeoff_speed 分位/takeoff_feet_y/contact_feet_y/catch_depth/
    # flight_ms/n/chain_n）为旋转不变量，原样复制；
    # takeoff_rect/landing_rect 旋转：新最小角 = 旧最大角取负
    # {"x": -(x+w), "z": -(z+h), "w": w, "h": h}。
    augmented = []  # (s, e, rs, re_)
    if not rot_violations:
        for (s, e) in sorted(matched_humans):
            rs, re_ = rot_map.get(s), rot_map.get(e)
            if rs is None or re_ is None:
                continue
            if (rs, re_) == (s, e):
                continue  # 自旋边（既有真实数据，无需复制）
            if (rs, re_) not in geom_pairs:
                continue
            if (rs, re_) in matched_humans:
                continue  # 旋转对已有真实数据——实数据优先
            src = matched_humans[(s, e)]
            tr = src["takeoff_rect"]
            lr = src["landing_rect"]
            matched_humans[(rs, re_)] = {
                "from": rs, "to": re_,
                "n": src["n"], "chain_n": src["chain_n"],
                "takeoff_speed": dict(src["takeoff_speed"]),
                "takeoff_feet_y": src["takeoff_feet_y"],
                "contact_feet_y": src["contact_feet_y"],
                "catch_depth": dict(src["catch_depth"]),
                "flight_ms": src["flight_ms"],
                "takeoff_rect": {"x": r3(-(tr["x"] + tr["w"])),
                                "z": r3(-(tr["z"] + tr["h"])),
                                "w": tr["w"], "h": tr["h"]},
                "landing_rect": {"x": r3(-(lr["x"] + lr["w"])),
                                "z": r3(-(lr["z"] + lr["h"])),
                                "w": lr["w"], "h": lr["h"]},
                "augmented": True,
                "source_edge": {"from": s, "to": e},
            }
            augmented.append((s, e, rs, re_))
    augmented.sort()
    real_edges_matched = len(matched_humans) - len(augmented)

    # ── 边合并（按 (from_face,to_face) 字典序）──
    edges = []
    for g in sorted(geom_groups, key=lambda x: (x["from_face"], x["to_face"])):
        dist_zone = rect_dist(g["takeoff_zone"], g["landing_zone"])
        human = matched_humans.get((g["from_face"], g["to_face"]))
        physics = feasibility(g["delta_h"], dist_zone)
        verdict = physics["verdict"]
        reasons = []
        if human is not None:
            if verdict in ("knife", "infeasible"):
                reasons.append("物理边缘但人类实证")
            # 链式跳跃多数判据（控制器裁决）：半数及以上 episode 为链式才标 skill
            # （chain_n*2 >= n）；不足半数 → 非 skill，human.chain_n 保留原值供 M4 读。
            if human["chain_n"] * 2 >= human["n"]:
                reasons.append("链式跳跃（多跳合成）")
            if human["catch_depth"]["p90"] > 0.5:
                reasons.append("抓边深度超带")
        edges.append({
            "from_face": g["from_face"],
            "to_face": g["to_face"],
            "delta_h": r3(g["delta_h"]),
            "dist_zone": r3(dist_zone),
            "link_names": g["link_names"],
            # 自包含双区（控制器裁决）：M4 只消费本 JSON，不得依赖 /tmp 中转文件；
            # 两区均为几何边组 zone（Vector2 已由导出侧拆成 {"x","z"}），
            # 键序 takeoff 在前；skill 判定与 dist_zone 口径不变。
            "takeoff_zone": g["takeoff_zone"],
            "landing_zone": g["landing_zone"],
            "human": human,
            "physics": physics,
            "skill": bool(reasons),
            "skill_reasons": reasons,
        })

    # ── link_audit：54 条链接逐条，端点级 feasibility（2026-08-14 白名单收敛后 from_face 恒非空；
    #   suspicious_link 分支保留为"新数据错误即现形"的防御路径）──
    link_audit = []
    for l in geo["links"]:
        item = {
            "link": l["link"], "from_face": l["from_face"], "to_face": l["to_face"],
            "delta_h": r3(l["delta_h"]), "dist_link": r3(l["dist"]), "verdict": "",
        }
        if l["from_face"] == "" or l["to_face"] == "":
            item["verdict"] = "suspicious_link"
        else:
            item["verdict"] = feasibility(l["delta_h"], l["dist"])["verdict"]
        link_audit.append(item)

    # ── 未匹配人类边（未来补链候选，n 降序；名次并列按 (from,to) 字典序定序）──
    unlinked = []
    for (s, e), g in corpus_groups.items():
        if (s, e) not in geom_pairs:
            unlinked.append({"from": s, "to": e, "n": g["n"]})
    unlinked.sort(key=lambda x: (-x["n"], x["from"], x["to"]))

    # ── 校准常量 ──
    # peak_rise：非链 climb（net_rise ≥ 0.5 且 chain==False）的
    # (contact_feet_y − takeoff_feet_y) 全体 p99（对照理论峰值 1.5133）
    peak_rises = [cf - tf for head, chain, tf, cf in kept_episodes
                  if head["net_rise"] >= 0.5 and not chain]
    # catch_depth：全部匹配组样本的 to_top − contact_feet_y 的 p90（对照 CATCH_BAND 0.5）
    catch_depths = []
    for (s, e), g in corpus_groups.items():
        if (s, e) in geom_pairs:
            to_top = faces[e]["top_y"]
            catch_depths.extend(to_top - v for v in g["cf_y"])
    calibrated = {
        "peak_rise_p99": r3(quantile(peak_rises, 99)),
        # 控制器裁决新增：与 p99 同口径（非链 climb 样本全体分位），报告对照用
        # （p99 1.668 超理论 1.513 的解释保留：真实对局坡面滑升/台阶链残留效应）
        "peak_rise_p50": r3(quantile(peak_rises, 50)),
        "catch_depth_p90": r3(quantile(catch_depths, 90)),
        "episodes": len(kept_episodes),
        "groups": len(corpus_groups),
        # 只计真实 human 匹配（增强副本不计入——保持既有口径；增强数见 meta）
        "edges_matched": real_edges_matched,
    }

    meta = {
        "map_hash": manifest["map_hash"],
        "movement_rev": "unknown(嵌入 map_hash 计算)",
        "map_name": manifest["map_name"],
        "corpus_episodes": non_fail_count,
        "calibrated": calibrated,
        "generated_by": "tools/build_jump_dataset.py",
        "source": "user://jump_training",
        # 180° 旋转增强汇总（字典序，按源边 (from,to) 排序）：
        # 每项 = 源边 + 增强边身份（源边在 edge.human.source_edge 亦有记录）
        "augmented_edges": len(augmented),
        "augmented": [
            {"from": s, "to": e, "aug_from": rs, "aug_to": re_}
            for (s, e, rs, re_) in augmented
        ],
    }

    out = {
        "meta": meta,
        "edges": edges,
        "link_audit": link_audit,
        "unlinked_human_edges": unlinked,
        # 面表内嵌（自包含原则：分析工具/M4 只消费本 JSON，不依赖 /tmp 中转；
        # 直接嵌入 geo["faces"]，键口径与导出侧一致）
        "faces": geo["faces"],
    }

    with open(OUT_JSON, "w") as fh:
        json.dump(out, fh, indent=1, ensure_ascii=False)
        fh.write("\n")

    # ── 终端汇总表（人工核对）──
    print("哈希门禁 PASS: manifest.map_hash == current_map_hash == %s"
          % manifest["map_hash"])
    print("语料: 总 %d / 非 fail %d（meta.corpus_episodes）"
          "/ 进入聚合 %d（@ 噪声跳过 %d）"
          % (manifest["episode_count"], non_fail_count, len(kept_episodes),
             non_fail_count - len(kept_episodes)))
    print("校准: peak_rise_p50=%.4f peak_rise_p99=%.4f（理论峰值 1.5133）"
          " catch_depth_p90=%.4f（CATCH_BAND 0.5）" % (
              calibrated["peak_rise_p50"], calibrated["peak_rise_p99"],
              calibrated["catch_depth_p90"]))
    print("边组: 几何 %d / 语料组 %d / 匹配 %d / 未匹配人类边 %d"
          % (len(geom_groups), len(corpus_groups), calibrated["edges_matched"],
             len(unlinked)))
    print("\n汇总表（%d 边）:" % len(edges))
    print("%-24s %-24s %6s %7s %7s %-10s %4s %s" % (
        "from", "to", "dH", "dist", "v_req", "verdict", "n", "skill"))
    for e in edges:
        n = e["human"]["n"] if e["human"] else 0
        chain = ("(chain%d)" % e["human"]["chain_n"]) if (
            e["human"] and e["human"]["chain_n"] > 0) else ""
        aug = "(aug)" if (e["human"] and e["human"].get("augmented")) else ""
        print("%-24s %-24s %+6.2f %7.3f %7.2f %-10s %4d %s%s%s" % (
            e["from_face"], e["to_face"], e["delta_h"], e["dist_zone"],
            e["physics"]["v_req"], e["physics"]["verdict"], n,
            "skill" if e["skill"] else "", chain, aug))
    print("\nlink_audit 异常链接:")
    anomalies = [a for a in link_audit
                 if a["verdict"] in ("suspicious_link", "infeasible")]
    for a in anomalies:
        print("  %-22s %s→%s  dist_link=%.3f  %s" % (
            a["link"], a["from_face"] or "?", a["to_face"] or "?",
            a["dist_link"], a["verdict"]))
    if not rot_violations:
        print("\n对称性门禁 PASS: %d 面 180° 旋转配对无违例，对合校验通过"
              % len(rot_map))
    else:
        print("\n对称性门禁 FAIL: 违例 %d 条（明细见上方 stderr），已跳过全部增强"
              % len(rot_violations))
    print("旋转增强: %d 条（源边 → 增强边）:" % len(augmented))
    for (s, e, rs, re_) in augmented:
        print("  %-24s → %-24s ==> %-24s → %s" % (s, e, rs, re_))
    print("输出: %s" % OUT_JSON)


if __name__ == "__main__":
    main()
