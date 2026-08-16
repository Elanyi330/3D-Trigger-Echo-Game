# 任务简报 AU：180° 旋转数据增强（build_jump_dataset.py）

> 项目：Trigger Echo。分支 feat/m1-assets，单目录 `/Users/elanyi/Projects/Trigger-Echo`。
> 用户拍板（2026-08-16）：未尝试的面通过 180° 旋转对应已有数据的面对称增强——地图
> 180° 旋转对称是设计硬约束（南北旋转对称、F7 同步缩短保对称）。已验证：三无数据面
> （EastTowerBox/WestClusterN_Box/BeltN_CanopyE）的旋转对称面均有数据（WestTower→
> WestTowerBox climb 4、Ground→EastClusterS_Box climb 1、GateS_Lintel→BeltS_CanopyW
> trav 2）；双向对称验证：Ground→WestTower 9 vs Ground→EastTower 5（数量级一致，
> 差异=人类游玩频率偏好）。

## 任务范围

- 生产文件（唯一）：`tools/build_jump_dataset.py`
- 产物：重建 `Levels/M2_TDM/jump_edges_dataset.json`
- **禁止改动**：jump_edges.gd / map_layout_v3.gd / auto_traversal.gd / 测试 / 语料目录（只读）

## 规格

### 1. 旋转映射表（面表几何驱动，非字符串替换）

从 `/tmp/jump_edges.json` 的 `geo["faces"]`（160 面，含 name/center/top_y）构建：

```python
# 180° 旋转映射：rot(center) = (-x, -z)；找 center 距离 ≤ ROT_EPS(0.05) 的面配对。
# 自身匹配（Ground/AltarPlatform 等中心对称面）映射自身；无配对面 → 对称性违例。
def build_rot_map(faces):
    rot_map = {}
    violations = []
    for f in faces:
        rx, rz = -f["center"]["x"], -f["center"]["z"]
        best, best_d = None, 1e9
        for g in faces:
            d = ((g["center"]["x"] - rx) ** 2 + (g["center"]["z"] - rz) ** 2) ** 0.5
            if d < best_d:
                best, best_d = g["name"], d
        if best_d > ROT_EPS:
            violations.append((f["name"], best, best_d))
        else:
            rot_map[f["name"]] = best
    return rot_map, violations
```

### 2. 对称性门禁（fail-safe：违例即跳过增强，绝不静默产出坏数据）

- violations 非空 → stderr 显著警告（列出违例面名与最近距离），**跳过全部增强**，
  数据集照常产出（无 augmented 数据），exit 0——构建保持可用，但警告必须醒目
- violations 空 → 校验 rot 为对合（rot(rot(f)) == f，防映射冲突）——对合不成立同样跳过
- 通过 → 继续增强

### 3. 增强生成（只填空缺，实数据优先）

在 `edges` 列表构建完成后：

```python
# 对每条有真实 human 数据的边 (s,e)：其旋转对 (rot(s), rot(e)) 若在 geom_pairs 中
# 且该边无 human 数据 → 生成增强副本：
#   human 字段复制 + 字段旋转：
#     "from"/"to" → rot 名；takeoff_rect/landing_rect {"x","z","w","h"} →
#     {"x": r3(-(x+w)), "z": r3(-(z+h)), "w": w, "h": h}（矩形旋转：新最小角 = 旧最大角取负）
#   + 标记："augmented": true, "source_edge": {"from": s, "to": e}
#   标量（takeoff_speed 分位/takeoff_feet_y/contact_feet_y/catch_depth/flight_ms/n/chain_n）
#   全部复制不变（旋转不变量）
# 增强边照常参与 skill 判定（chain 等已复制，判定逻辑不改）
# 实数据优先：旋转对已有 human → 不生成；source 是增强边的再增强不生成
#   （只允许真实数据做源——防多跳增强链）
```

### 4. 面表内嵌 + meta 统计

- 数据集输出新增顶层 `"faces"`：`[{"name", "center": {"x","z"}, "size": {"x","z"},
  "top_y"}]`（来自 geo["faces"]，供分析工具/M4 消费——面表自包含原则）
- meta 新增：`"augmented_edges": 数量` + `"augmented": [{"to": s, "from": e}]` 列表
  （字典序）
- 终端汇总打印：增强边数 + 每条「源边 → 增强边」

### 5. 重建流程与验证

1. `godot --headless --path . -s tools/export_jump_edges.gd`（重导 /tmp/jump_edges.json，
   哈希门禁口径与语料 manifest f935ccd7… 一致——布局未动）
2. `python3 tools/build_jump_dataset.py` → 重建数据集
3. 验证清单（全部执行并贴输出）：
   - 三无数据面检查：EastTowerBox/WestClusterN_Box/BeltN_CanopyE 出现于增强边列表
     （打印证据：数据集里对应边的 human.augmented == true + source_edge）
   - 对称性门禁通过（violations 空、对合校验过）
   - 增强边只增不改：git diff 数据集——既有边字段零改动（除 meta/faces 顶层新增）
   - `godot --headless --path . -s tools/probe_jump_edges.gd` → 退出 0（若门禁的
     expect 与新增 human 冲突——报告差异与理由，不擅改 expect）
   - 全量 GUT `godot --headless --path . -s addons/gut/gut_cmdln.gd` → **403/403**

## 报告格式

开头一行 DONE / DONE_WITH_CONCERNS / NEEDS_CONTEXT / BLOCKED + 改动清单 + 增强清单
（源边→增强边 全表）+ 验证证据 + 最终数字。
