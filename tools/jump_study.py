#!/usr/bin/env python3
# tools/jump_study.py — 阶段0：跳跃数据深度研究（2026-08-13 navmesh 前置）
# 解析 user://jump_training/episodes/*.jsonl 全部 episode，重建：
#   1) 人类验证可达面清单（落点面集合+次数）
#   2) 跳跃边表（start→end + 典型起跳/落点坐标 + 次数）
# 输出 JSON 到 /tmp/jump_study.json（阶段 1/3 消费）。
import json, glob, os, sys
from collections import defaultdict

D = os.path.expanduser("~/Library/Application Support/Godot/app_userdata/Trigger Echo/jump_training/episodes")
eps = []
for f in sorted(glob.glob(D + "/*.jsonl")):
    with open(f) as fh:
        head = json.loads(fh.readline())
        frames = [json.loads(l) for l in fh]
    eps.append((head, frames))

reachable = defaultdict(int)      # end_name -> 次数（climb+traverse 落点面）
edges = defaultdict(lambda: {"n": 0, "starts": [], "ends": []})  # (start,end) -> 数据

for head, frames in eps:
    if head["classification"] == "fail":
        continue  # 起落同名面：无新可达性信息
    end = head["end_name"]
    start = head["start_name"]
    reachable[end] += 1
    if not frames:
        continue
    first, last = frames[0], frames[-1]
    key = (start, end)
    e = edges[key]
    e["n"] += 1
    e["starts"].append((first["px"], first["py"], first["pz"]))
    e["ends"].append((last["px"], last["py"], last["pz"]))

def med(vals, i):
    s = sorted(v[i] for v in vals)
    return round(s[len(s) // 2], 2)

out = {
    "reachable_faces": dict(sorted(reachable.items(), key=lambda kv: -kv[1])),
    "edges": [],
}
for (s, en), e in sorted(edges.items(), key=lambda kv: -kv[1]["n"]):
    out["edges"].append({
        "start": s, "end": en, "n": e["n"],
        "jump_from": [med(e["starts"], 0), med(e["starts"], 1), med(e["starts"], 2)],
        "land_at": [med(e["ends"], 0), med(e["ends"], 1), med(e["ends"], 2)],
    })

with open("/tmp/jump_study.json", "w") as fh:
    json.dump(out, fh, indent=1)
print("可达面数:", len(reachable))
print("跳跃边数:", len(edges))
print("\n人类验证可达面清单（按次数）:")
for k, v in out["reachable_faces"].items():
    print(f"  {k:20s} {v}")
print("\n跳跃边表 Top 25:")
for e in out["edges"][:25]:
    print(f"  {e['start']:18s} -> {e['end']:18s} n={e['n']:3d}  起跳{e['jump_from']}  落点{e['land_at']}")
