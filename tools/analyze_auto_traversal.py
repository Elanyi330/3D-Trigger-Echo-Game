#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Trigger Echo 自动遍历三源对照分析工具（纯标准库、确定性输出）。

三源对照：自动遍历实测（auto_traversal 语料） vs 求解器预测（link_audit）
vs 人类语料（jump_edges_dataset edges.human）。

输出：
  1) 终端报告：汇总 / 三源对照表 / 面级执行实测 / 面级清单
  2) /tmp/auto_verification.json（机器可读产物）

用法：
  python3 tools/analyze_auto_traversal.py [语料目录]

语料目录缺省为 ~/Library/Application Support/Godot/app_userdata/Trigger Echo/auto_traversal。
语料目录不存在或 attempts 为空 → 打印提示并退出 0（不误报）。
"""

import json
import math
import os
import sys
import unicodedata

DEFAULT_CORPUS = os.path.expanduser(
    "~/Library/Application Support/Godot/app_userdata/Trigger Echo/auto_traversal")
DATASET_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                            "..", "Levels", "M2_TDM", "jump_edges_dataset.json")
OUT_JSON = "/tmp/auto_verification.json"


# ---------------------------------------------------------------- 通用工具

def p50(vals):
    """p50 分位数：sorted(vals)[len//2]（与 jump_study.py 同口径），保留 2 位小数。"""
    if not vals:
        return None
    s = sorted(vals)
    return round(s[len(s) // 2], 2)


def vis_width(s):
    """终端显示宽度（CJK 全角按 2 计，保证中文对齐）。"""
    w = 0
    for ch in str(s):
        w += 2 if unicodedata.east_asian_width(ch) in ("F", "W") else 1
    return w


def pad(s, width, left=True):
    """按显示宽度补齐：left=True 左对齐（补右空格），否则右对齐（补左空格）。"""
    gap = width - vis_width(s)
    return s + " " * gap if left else " " * gap + s


def fmt_num(x, nd):
    """数值 → 定宽字符串（None → "-"）。"""
    if x is None:
        return "-"
    return ("%." + str(nd) + "f") % x


def _f(d, key):
    """字典安全取 float（缺失/非法 → 0.0）。"""
    try:
        return float(d.get(key, 0.0))
    except (TypeError, ValueError):
        return 0.0


# ---------------------------------------------------------------- 数据加载

def load_json(path):
    if not os.path.isfile(path):
        return None
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def load_attempts(attempts_dir):
    """读取 attempts/ep_*.jsonl（按文件名字典序 = attempt_id 升序）。

    每文件：首行 head（face/link/verdict/failure_reason/plan/params_used/
    teleported/frame_count），其余为帧行（16 键）。head 损坏的文件跳过（stderr 提示）。
    返回 list[dict]，每个 dict 带 "_frames"（帧行列表）。
    """
    out = []
    names = sorted(n for n in os.listdir(attempts_dir) if n.endswith(".jsonl"))
    for name in names:
        path = os.path.join(attempts_dir, name)
        try:
            with open(path, "r", encoding="utf-8") as f:
                lines = f.read().splitlines()
        except OSError:
            continue
        if not lines:
            continue
        try:
            head = json.loads(lines[0])
        except ValueError:
            print("[警告] head 行损坏，跳过 %s" % path, file=sys.stderr)
            continue
        frames = []
        for ln in lines[1:]:
            if not ln:
                continue
            try:
                frames.append(json.loads(ln))
            except ValueError:
                continue
        head["_frames"] = frames
        out.append(head)
    return out


def load_dataset():
    """jump_edges_dataset.json → dict；不可读 → None（求解器/人类列显示 "-"）。"""
    ds = load_json(DATASET_PATH)
    if ds is None:
        print("[警告] 数据集不可读：%s" % DATASET_PATH, file=sys.stderr)
    return ds


def build_lookups(ds):
    """link → link_audit 项 / edge 项 / 人类 p50（每条 link 唯一映射一条 edge）。"""
    audit, edge, human = {}, {}, {}
    if not ds:
        return audit, edge, human
    for la in ds.get("link_audit", []):
        if isinstance(la, dict) and "link" in la:
            audit[la["link"]] = la
    for e in ds.get("edges", []):
        for ln in e.get("link_names", []):
            edge[ln] = e
    for ln, e in edge.items():
        h = e.get("human")
        if h and h.get("takeoff_speed") is not None:
            human[ln] = h["takeoff_speed"].get("p50")
    return audit, edge, human


# ---------------------------------------------------------------- 聚合

def attempt_speed(attempt):
    """首帧水平速率 √(vx²+vz²)（仅 link!="" 的 attempt 有意义）；无帧行 → None。"""
    if not attempt.get("link") or not attempt["_frames"]:
        return None
    fr = attempt["_frames"][0]
    vx = _f(fr, "vx")
    vz = _f(fr, "vz")
    return math.sqrt(vx * vx + vz * vz)


def attempt_on_floor(attempt):
    """on_floor 序列统计 → (on_floor 帧数, 总帧行数)。"""
    n_on = sum(1 for fr in attempt["_frames"] if fr.get("on_floor") is True)
    return n_on, len(attempt["_frames"])


def aggregate(attempts):
    """按 face / link 聚合（attempts 已按 attempt_id 升序，末次即最新）。"""
    total = len(attempts)
    n_success = 0
    per_face = {}
    per_link = {}
    for a in attempts:
        face = a.get("face", "")
        link = a.get("link", "")
        verdict = a.get("verdict", "")
        reason = a.get("failure_reason", "")
        ok = (verdict == "success")
        if ok:
            n_success += 1
        pf = per_face.setdefault(face, {
            "attempts": 0, "success": 0, "verdicts": {},
            "frames": 0, "on_floor": 0, "latest_verdict": "", "latest_reason": "",
        })
        pf["attempts"] += 1
        if ok:
            pf["success"] += 1
        pf["verdicts"][verdict] = pf["verdicts"].get(verdict, 0) + 1
        pf["latest_verdict"] = verdict
        pf["latest_reason"] = reason
        n_on, n_fr = attempt_on_floor(a)
        pf["frames"] += n_fr
        pf["on_floor"] += n_on
        if link:
            pl = per_link.setdefault(link, {
                "attempts": 0, "success": 0, "speeds": [], "failures": {},
            })
            pl["attempts"] += 1
            if ok:
                pl["success"] += 1
            else:
                pl["failures"][reason] = pl["failures"].get(reason, 0) + 1
            sp = attempt_speed(a)
            if sp is not None:
                pl["speeds"].append(sp)
    return {
        "total": total, "n_success": n_success, "n_failed": total - n_success,
        "per_face": per_face, "per_link": per_link,
    }


# ---------------------------------------------------------------- 终端报告

def render_table(header, rows, align_left):
    """中文对齐表格：按显示宽度动态定宽，align_left[i] 为列对齐。"""
    widths = [vis_width(h) for h in header]
    for cells in rows:
        for i, c in enumerate(cells):
            widths[i] = max(widths[i], vis_width(c))
    lines = ["  ".join(pad(h, widths[i], align_left[i]) for i, h in enumerate(header))]
    for cells in rows:
        lines.append("  ".join(
            pad(c, widths[i], align_left[i]) for i, c in enumerate(cells)))
    return lines


def render_report(corpus, manifest, summary, stats, audit_by_link, edge_by_link,
                  human_p50_by_link):
    per_face, per_link = stats["per_face"], stats["per_link"]
    manifest = manifest or {}
    summary = summary or {}
    lines = []
    banner = "=" * 78
    lines.append(banner)
    lines.append("Trigger Echo 自动遍历三源对照报告")
    lines.append("工具: tools/analyze_auto_traversal.py   语料: %s" % corpus)
    lines.append("地图哈希: %s" % (manifest.get("map_hash") or "(manifest 缺失)"))
    lines.append(banner)

    # ---- 一、汇总 ----
    visited = summary.get("visited")
    if visited is None:
        visited = len(per_face)
    total_faces = manifest.get("target_faces") or summary.get("total") or 160
    rate = 100.0 * stats["n_success"] / stats["total"] if stats["total"] else 0.0
    lines.append("")
    lines.append("一、汇总")
    lines.append("  总 attempt 数 : %d" % stats["total"])
    lines.append("  成功 / 失败   : %d / %d" % (stats["n_success"], stats["n_failed"]))
    lines.append("  已处理面数    : %d / %d（summary.visited / target_faces）"
                 % (visited, total_faces))
    lines.append("  成功率        : %.1f%%" % rate)

    # ---- 二、三源对照表 ----
    lines.append("")
    lines.append("二、三源对照表（有实测的 link 边，%d 条）" % len(per_link))
    header = ["link", "Δh", "dist_link", "求解器verdict", "数据集verdict",
              "人类p50", "自动实测p50", "自动成功率"]
    align = [True, False, False, True, True, False, False, False]
    rows = []
    for link in sorted(per_link):
        pl = per_link[link]
        la = audit_by_link.get(link)
        e = edge_by_link.get(link)
        rows.append([
            link,
            fmt_num(la.get("delta_h"), 1) if la else "-",
            fmt_num(la.get("dist_link"), 3) if la else "-",
            la.get("verdict", "-") if la else "-",
            e.get("physics", {}).get("verdict", "-") if e else "-",
            fmt_num(human_p50_by_link.get(link), 2),
            fmt_num(p50(pl["speeds"]), 2),
            "%d/%d" % (pl["success"], pl["attempts"]),
        ])
    if rows:
        lines.extend(render_table(header, rows, align))
    else:
        lines.append("  （无实测 link 边——语料尚无带 link 的 attempt）")

    # ---- 面级执行实测（10 条端点级 infeasible 链接）----
    lines.append("")
    lines.append("  面级执行实测（端点级 infeasible 链接，link_audit.verdict==\"infeasible\"）")
    lines.append("  口径：自动遍历从面级起跳区执行，验证「面级 zone 替代链接端点」的 M4 消费口径")
    infeasible = sorted(
        la["link"] for la in audit_by_link.values() if la.get("verdict") == "infeasible")
    if not infeasible:
        lines.append("  （数据集不可读，无法列出 infeasible 链接清单）")
    else:
        hdr2 = ["link", "attempts", "成功", "成功率", "判定"]
        rows2 = []
        n_ok = n_bad = n_none = 0
        for link in infeasible:
            pl = per_link.get(link)
            n = pl["attempts"] if pl else 0
            s = pl["success"] if pl else 0
            if n == 0:
                judge = "无实测"
                n_none += 1
            elif s > 0:
                judge = "口径成立"
                n_ok += 1
            else:
                judge = "未成立(0/%d)" % n
                n_bad += 1
            rows2.append([link, "%d" % n, "%d" % s,
                          "%.4f" % (s / n) if n else "-", judge])
        lines.extend(render_table(hdr2, rows2, [True, False, False, False, True]))
        for link in infeasible:
            pl = per_link.get(link)
            n = pl["attempts"] if pl else 0
            s = pl["success"] if pl else 0
            if n and s == 0 and pl["failures"]:
                reasons = "; ".join("%s ×%d" % (r, pl["failures"][r])
                                    for r in sorted(pl["failures"]))
                lines.append("     失败原因[%s]: %s" % (link, reasons))
        if n_ok > 0:
            lines.append("  口径结论: 实测成功>0 的链接 %d/%d → 面级 zone 替代链接端点口径成立"
                         % (n_ok, len(infeasible)))
        elif n_bad > 0:
            lines.append("  口径结论: 实测成功>0 的链接 0/%d（已实测 %d 条全败）→ 口径暂未成立"
                         % (len(infeasible), n_bad))
        else:
            lines.append("  口径结论: %d 条均无实测 → 口径待遍历覆盖验证" % len(infeasible))

    # ---- 三、面级清单 ----
    lines.append("")
    lines.append("三、面级清单（已实测 %d 面，按面名字典序）" % len(per_face))
    hdr3 = ["面名", "判词分布", "最新失败原因", "attempts", "成功", "帧数", "on_floor%"]
    rows3 = []
    for face in sorted(per_face):
        pf = per_face[face]
        dist = "; ".join("%s×%d" % (v, pf["verdicts"][v]) for v in sorted(pf["verdicts"]))
        reason = pf["latest_reason"] if pf["latest_verdict"] != "success" else "-"
        ofr = ("%.1f%%" % (100.0 * pf["on_floor"] / pf["frames"])) if pf["frames"] else "-"
        rows3.append([face, dist, reason, "%d" % pf["attempts"], "%d" % pf["success"],
                      "%d" % pf["frames"], ofr])
    lines.extend(render_table(hdr3, rows3, [True, True, True, False, False, False, False]))
    groups = {}
    for face in sorted(per_face):
        pf = per_face[face]
        if pf["latest_verdict"] != "success":
            r = pf["latest_reason"]
            groups[r] = groups.get(r, 0) + 1
    lines.append("失败原因分组（非成功面，按最新失败原因）:")
    if groups:
        for r in sorted(groups):
            lines.append("  %s : %d 面" % (r, groups[r]))
    else:
        lines.append("  （无失败面）")
    lines.append("")
    return "\n".join(lines)


# ---------------------------------------------------------------- JSON 产物

def write_json(manifest, stats, audit_by_link):
    per_face, per_link = stats["per_face"], stats["per_link"]
    manifest = manifest or {}
    out = {
        "meta": {
            "map_hash": manifest.get("map_hash"),
            "generated_by": "tools/analyze_auto_traversal.py",
        },
        "per_face": {},
        "per_link": {},
        "endpoint_infeasible_check": [],
    }
    for face in sorted(per_face):
        pf = per_face[face]
        out["per_face"][face] = {
            "attempts": pf["attempts"],
            "success": pf["success"],
            "verdicts": {v: pf["verdicts"][v] for v in sorted(pf["verdicts"])},
        }
    for link in sorted(per_link):
        pl = per_link[link]
        out["per_link"][link] = {
            "attempts": pl["attempts"],
            "success": pl["success"],
            "speed_p50": p50(pl["speeds"]),
            "failures": {r: pl["failures"][r] for r in sorted(pl["failures"])},
        }
    infeasible = sorted(
        la["link"] for la in audit_by_link.values() if la.get("verdict") == "infeasible")
    for link in infeasible:
        pl = per_link.get(link)
        n = pl["attempts"] if pl else 0
        s = pl["success"] if pl else 0
        out["endpoint_infeasible_check"].append({
            "link": link,
            "attempts": n,
            "success": s,
            "success_rate": round(s / n, 4) if n else 0.0,
        })
    with open(OUT_JSON, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, indent="\t")
        f.write("\n")


# ---------------------------------------------------------------- 入口

def main(argv):
    corpus = argv[1] if len(argv) > 1 else DEFAULT_CORPUS
    if not os.path.isdir(corpus):
        print("[提示] 语料目录不存在：%s（跳过分析，退出 0）" % corpus)
        return 0
    attempts_dir = os.path.join(corpus, "attempts")
    if not os.path.isdir(attempts_dir):
        print("[提示] attempts 目录不存在：%s（跳过分析，退出 0）" % attempts_dir)
        return 0
    attempts = load_attempts(attempts_dir)
    if not attempts:
        print("[提示] attempts 目录为空（无 ep_*.jsonl）：%s（跳过分析，退出 0）" % attempts_dir)
        return 0
    manifest = load_json(os.path.join(corpus, "manifest.json"))
    summary = load_json(os.path.join(corpus, "summary.json"))
    ds = load_dataset()
    audit_by_link, edge_by_link, human_p50_by_link = build_lookups(ds)
    stats = aggregate(attempts)
    print(render_report(corpus, manifest, summary, stats, audit_by_link,
                        edge_by_link, human_p50_by_link))
    write_json(manifest, stats, audit_by_link)
    print("[产物] 已写 %s" % OUT_JSON)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
