#!/usr/bin/env python3
"""Scan map_layout.gd for narrow gaps (<1.2m) between blocking components.

布局质量工具：找出"视觉像通道但玩家(宽1.0m)走不进"的伪通道窄缝。
用法: python3 tools/scan_gaps.py
"""
import re
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = open(os.path.join(ROOT, 'Levels/M2_TDM/map_layout.gd')).read()


def parse_block(txt):
    m = re.search(
        r'\{"name": "(\w+)", "kind": "(\w+)", "center": Vector3\(([-\d.]+), ([-\d.]+), ([-\d.]+)\), "size": Vector3\(([-\d.]+), ([-\d.]+), ([-\d.]+)\)',
        txt, re.S)
    if not m:
        return None
    g = m.groups()
    return {'name': g[0], 'kind': g[1], 'cx': float(g[2]), 'cy': float(g[3]),
            'cz': float(g[4]), 'sx': float(g[5]), 'sy': float(g[6]), 'sz': float(g[7])}

entries = []
for m in re.finditer(r'\{(?:[^{}]|\{[^{}]*\})*\}', SRC):
    e = parse_block(m.group(0))
    if e and e['name'] != 'Ground':
        entries.append(e)
# 生成函数（_corner_walls / _corner_interiors）里的条目
for fn in ['_corner_walls', '_corner_interiors']:
    m = re.search(fn + r'.*?return out', SRC, re.S)
    if m:
        for mm in re.finditer(r'\{(?:[^{}]|\{[^{}]*\})*\}', m.group(0)):
            e = parse_block(mm.group(0))
            if e:
                entries.append(e)

# 去重
seen, uniq = set(), []
for e in entries:
    k = (e['name'], round(e['cx'], 2), round(e['cz'], 2))
    if k not in seen:
        seen.add(k)
        uniq.append(e)
entries = uniq
print(f"实体 {len(entries)}")


def blocks(e):
    # decor（小树）纯视觉无碰撞，不参与窄缝判定；bigtree（大树）有碰撞，参与
    if e.get('kind', '') == 'decor':
        return False
    return e['cy'] + e['sy'] * 0.5 > 0.95 and e['name'] != 'Ground'


found = []
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
        if ox > 0 and oz > 0:
            continue  # 重叠
        if ox > 0:
            gap = max(az0, bz0) - min(az1, bz1)
            if 0 < gap < 1.2:
                found.append((gap, a['name'], b['name'], 'z'))
        elif oz > 0:
            gap = max(ax0, bx0) - min(ax1, bx1)
            if 0 < gap < 1.2:
                found.append((gap, a['name'], b['name'], 'x'))

if found:
    for gap, na, nb, axis in sorted(found):
        print(f"  ⚠️ 窄缝 {gap:.2f}m: {na} <-> {nb}（{axis}轴）")
else:
    print("  无 <1.2m 窄缝 ✓")
print("DONE")
