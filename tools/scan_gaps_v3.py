#!/usr/bin/env python3
"""Scan map_layout_v3.gd solids for narrow gaps (<1.2m) between blocking components.

任务 9 B 扫描管线：数据源 = tools/dump_v3_solids.gd（headless 打印 all_solids() JSON）。
判定逻辑沿用 tools/scan_gaps.py（v2）：
  blocks()  = 顶面 > 0.95 且 kind ∉ {decor, bigtree}（decor 无碰撞；bigtree 碰撞小且
              允许叠墙，均不参与窄缝判定）；Ground 按名字排除
  垂直重叠  = min(top) - max(bottom) ≥ 0.8（高度重叠不足不会夹人）
  报告条件  = 水平缝 0 < gap < 1.2（面接触 gap==0 合法，≥1.2 可行走）
已知盲区：角部相接夹点（ox≤EPS 且 oz≤EPS 的盒对）不评估——此类夹点由
probe_v3_walk 连通性门禁兜底（2026-08-12 F3 事故后确立）。
用法: python3 tools/scan_gaps_v3.py          # 缺省先自动调用 godot 重新生成 dump
      python3 tools/scan_gaps_v3.py --cached # 直接读已有 /tmp/v3_solids.json
"""
import json
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DUMP = '/tmp/v3_solids.json'

# 浮点容差：判定规则为 缝==0（面接触合法）或 ≥1.2（可通行），
# EPS 把浮点噪声归入合法侧，忠实实现文档规则（判定阈值 0/0.8/1.2 不变）。
# 实体坐标经 Vector3（float32）存储，噪声量级 ~1e-5；EPS=1e-3 留足裕量，
# 远小于任何真实窄缝（本图真实违规均 ≥0.4m）。
EPS = 1e-3


def regen() -> None:
    cmd = ['godot', '--headless', '--no-header', '--path', ROOT,
           '-s', 'tools/dump_v3_solids.gd']
    out = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
    if out.returncode != 0:
        print(f"godot dump 失败 exit={out.returncode}\n{out.stderr}", file=sys.stderr)
        sys.exit(1)
    txt = out.stdout
    i = txt.find('[')  # 防御：剥掉可能残留的引擎头行
    open(DUMP, 'w').write(txt[i:] if i >= 0 else txt)


if '--cached' not in sys.argv:
    regen()

txt = open(DUMP).read()
i = txt.find('[')  # 防御：手动 dump 未加 --no-header 时剥掉引擎头行
entries = json.loads(txt[i:] if i >= 0 else txt)
print(f"实体 {len(entries)}")


def blocks(e):
    # decor 纯视觉无碰撞；bigtree 有碰撞但允许与墙体重叠（用户拍板），碰撞体积小（0.7m），
    # 不参与窄缝判定避免误报（沿用 scan_gaps.py 判定）
    if e.get('kind', '') in ('decor', 'bigtree'):
        return False
    return e['cy'] + e['sy'] * 0.5 > 0.95 and e['name'] != 'Ground'


found = []
boxes = []  # (ax0, ay0, az0, ax1, ay1, az1, entry) 供填充检测用
for e in entries:
    boxes.append((e['cx'] - e['sx'] / 2, e['cy'] - e['sy'] / 2, e['cz'] - e['sz'] / 2,
                  e['cx'] + e['sx'] / 2, e['cy'] + e['sy'] / 2, e['cz'] + e['sz'] / 2, e))


def gap_filled(gx0, gy0, gz0, gx1, gy1, gz1, skip_names):
    """缝盒内是否存在其他阻挡体完整填充（水平相交且纵跨整个缝盒高度）——
    有填充则非通道（如坡道非相邻级之间夹着中间级、坡道末级与台体之间夹着
    相邻级），不构成窄缝。仅擦过缝盒顶部/底部的悬挑体（如回廊板）不算填充。"""
    for (x0, y0, z0, x1, y1, z1, e) in boxes:
        if e['name'] in skip_names or not blocks(e):
            continue
        if x0 + EPS < gx1 and gx0 + EPS < x1 \
           and z0 + EPS < gz1 and gz0 + EPS < z1 \
           and y0 <= gy0 + EPS and y1 >= gy1 - EPS:
            return True
    return False


for i in range(len(entries)):
    for j in range(i + 1, len(entries)):
        a, b = entries[i], entries[j]
        if not (blocks(a) and blocks(b)):
            continue
        ax0, ax1 = a['cx'] - a['sx'] / 2, a['cx'] + a['sx'] / 2
        ay0, ay1 = a['cy'] - a['sy'] / 2, a['cy'] + a['sy'] / 2
        az0, az1 = a['cz'] - a['sz'] / 2, a['cz'] + a['sz'] / 2
        bx0, bx1 = b['cx'] - b['sx'] / 2, b['cx'] + b['sx'] / 2
        by0, by1 = b['cy'] - b['sy'] / 2, b['cy'] + b['sy'] / 2
        bz0, bz1 = b['cz'] - b['sz'] / 2, b['cz'] + b['sz'] / 2
        if min(ay1, by1) - max(ay0, by0) < 0.8:
            continue  # 高度重叠不足，不会夹人
        ox = min(ax1, bx1) - max(ax0, bx0)
        oz = min(az1, bz1) - max(az0, bz0)
        if ox > EPS and oz > EPS:
            continue  # 重叠
        if ox > EPS:
            gap = max(az0, bz0) - min(az1, bz1)
            if EPS < gap < 1.2 - EPS:
                # 缝盒 = 分离轴(z)缝隙区间 × 相交轴(x)投影交叠 × 垂直重叠区间
                if not gap_filled(max(ax0, bx0), max(ay0, by0), min(az1, bz1),
                                  min(ax1, bx1), min(ay1, by1), max(az0, bz0),
                                  {a['name'], b['name']}):
                    found.append((gap, a['name'], b['name'], 'z'))
        elif oz > EPS:
            gap = max(ax0, bx0) - min(ax1, bx1)
            if EPS < gap < 1.2 - EPS:
                if not gap_filled(min(ax1, bx1), max(ay0, by0), max(az0, bz0),
                                  max(ax0, bx0), min(ay1, by1), min(az1, bz1),
                                  {a['name'], b['name']}):
                    found.append((gap, a['name'], b['name'], 'x'))

if found:
    for gap, na, nb, axis in sorted(found):
        print(f"  ⚠️ 窄缝 {gap:.2f}m: {na} <-> {nb}（{axis}轴）")
else:
    print("  无 <1.2m 窄缝 ✓")
print("DONE")
