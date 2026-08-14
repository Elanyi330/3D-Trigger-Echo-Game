# M2 边界隐形高墙 + 面级跳跃边四层设计（本轮做 1+2+3 + 量化验证）

> 计划日期：2026-08-13。分支 feat/m1-assets，单目录（勿建 worktree）。
> 用户拍板（HANDOFF §二 待做段）：①地图边界隐形高墙 ②面级跳跃边四层设计。
> 本轮范围：①全部 + ②的 (1) 数据结构 (2) 物理求解器 (3) 语料校准数据集 + 量化验证。
> ②(4) M3/M4 接口设计**不做**（留待下一轮）。

## 一、目标

1. **边界隐形高墙**：地图边界墙外缘 4 面 12m 高碰撞体，仅碰撞无视觉；放 `map_greybox.gd` 独立函数，**不写布局数据**——193 实体数、布局哈希、跳跃记录、扫描/探针/小地图全部不受影响。
2. **面级跳跃边**：54 处点链接升级为面级边（from_face/to_face/Δh/水平距/起跳区/接收区/人类轨迹样本）；抛物线物理求解器（确定性核心）对每条边输出可行性报告；人类语料（577 episodes）校准 → 跳跃边数据集 JSON 供 M4；"技巧边"标注。

## 二、探索发现（设计依据，实现者必读）

### 2.1 真实跳跃物理 ≠ probe_jump 实测 1.388（关键发现）

`MovementController._physics_process` 帧序：跳帧（仍 on_floor 分支）`velocity.y = 7.54` 后**不减重力**直接 move_and_slide（满速位移一帧），下一帧起才 `vy -= 19.6·dt`。60Hz 半隐式欧拉离散模型（精确复刻引擎）：

- `rise(n) = n·7.54/60 − 19.6·n(n−1)/7200`（n = 帧数，n≥1；n=0 为 0）
- **峰值 1.5133m @ n=24**（probe_jump 的 1.388 是其自带积分模型低估——探针跳帧先减重力）
- 同高落地 47 帧 = 0.7833s → 跑速 6.35 全跳远 ≈ 4.97m（probe 4.868 因 0.05 落点容差早停一帧）
- 语料实证：WestTower→WestWall_M episode t=0 时 vy=7.54 且 origin 已升 0.1257 ✓

### 2.2 边缘抓取（edge-catch）：有效 Δh 上限 ≈ 1.513 + 0.5 ≈ 2.0m

玩家胶囊 **radius 0.5**（`Player/MovementController.tscn`，非 AI 的 0.31）、height 1.83、`floor_snap_length 0.5`。身体 origin = 脚 + 0.915（语料实测休息位 origin−面高 = 0.92）。

- 落地条件：底球中心（脚+0.5）**高于**目的地顶面，且水平投影进入顶面覆盖区 → 脚只需 ≥ 顶面 − 0.5，物理滚角+去穿透把身体抬上去。
- 语料实证：翼墙→门梁（Δh 1.9，n=1 用户实测）：接触帧脚 4.785（顶 4.9 下 0.115），身体沿门梁西棱 x=−5.5 滑升（位置被挡、y 继续升、vx 保持 5.45——slide 沿棱角上滚），随后走上门梁顶。
- 摊阁→横脊墙（Δh 1.8，n=3）：起跳脚 1.32、接触脚 2.915（顶 3.0 下 0.085）✓ 同一机制。

### 2.3 求解器模型（确定性核心，常量全部来自现有代码）

| 常量 | 值 | 出处 |
|------|-----|------|
| G | 19.6（9.8×2） | gravity_multiplier 2.0 |
| V_JUMP | 7.54 | jump_height |
| DT | 1/60 | 物理帧 |
| SPEED_CAP | 6.35 | speed（落地钳制=起跳上限） |
| FEET_OFFSET | 0.915 | 胶囊 1.83/2（origin−脚） |
| CATCH_RADIUS | 0.5 | 玩家胶囊半径 |
| BAND | CATCH_RADIUS（脚可低于顶面 0.5 仍可抓边） | 2.2 推导+语料实证 |

- 抓边窗口：`rise(t) ≥ Δh − 0.5` → [t1, t2]（Δh ≤ 0.5 时 t1=0，全飞程前段）
- 必需速度：`v_req = d / t2`；上跳另需 `v ≤ min(cap, d/t1)`（t1>0 时过快会早到撞立面）
- 判定：`infeasible`（v_req>cap 或无窗口）｜`knife`（速率余量 <5%）｜`tight`（<20%）｜`easy`
- 可落区：起跳区矩形按半径 `cap·t2` 膨胀 ∩ 接收面矩形（确定性网格采样算覆盖率）

### 2.4 锚定算例（求解器测试期望值，全部由上述公式手算）

- `peak_rise() = 1.5133333`；`rise(24) = 1.5133`；`rise(47)=0.0206`、`rise(48)=−0.1073`（同高落地 47 帧）
- `catch_window(0.9)` → [4, 43] 帧（脚需 ≥0.4：rise(4)=0.4700 首超、rise(43)=0.4939 末超）
- `catch_window(1.8)` → [15, 32] 帧（rise(15)=1.3133、rise(33)=1.2701 跌破 1.3）
- `required_speed(Δh=0.9, d=0)` → 0（竖直上箱）；`required_speed(0.9, 2.0)` → 2.79 easy
- `feasibility(1.8, 2.62)`（摊阁→横脊墙链接）→ tight（v_req 4.91）
- `feasibility(1.9, 1.58)`（翼墙→门梁人类实际起跳位）→ easy（v_req 3.16，人类 5.45 实测居中）
- `feasibility(1.9, 6.5)`（WingToLintel **链接现状端点**）→ **infeasible**（v_req 13.0 > cap）
- `feasibility(0.0, 4.0)`（rim 街口 4m 同高豁口）→ easy（t2=0.7167s → v_req 5.58）

### 2.5 已发现的数据问题（本轮只报告+建议，不擅自改）

- **PavToSpur_WS / PavToSpur_ES 两条链接疑似数据错误**：水平距 16.8m（Δh 1.8 下单跳物理上限 ~3.4m 的 5 倍），且 from 端点（±16.2, 1.2, ∓9.4）**不在任何面上**（西/东摊阁 x∈[±17.25,±19.75]）。疑似镜像笔误（把"近侧横脊墙"写成了对面远处的）。→ 报告标注 `!!`，建议：删除或改为真旋转对称对（W-Pav→W-SpurS、E-Pav→E-SpurN 已够）。
- **WingToLintel 4 条链接端点可执行性差**：链接 from x=±10.5（翼墙中部）距门梁 6.5m 不可跳；人类实际起跳在翼墙内端（x≈−7，d≈1.6m）✓。→ 面级起跳区（语料簇）修正此问题，这正是"点链接 → 面级边"的价值。

## 三、全局约束

- 单目录 `/Users/elanyi/Projects/Trigger-Echo`，分支 feat/m1-assets，**勿建 worktree**。
- **布局数据（map_layout_v3.gd）一字不动**：193 实体、布局哈希、MOVEMENT_REV（`move-r3:step0.62+chain+firstframe,air-rest3.0/run0.76`）均不变 → 跳跃记录不重置。
- 测试：GUT（`godot --headless --path . -s addons/gut/gut_cmdln.gd`，基线 339/339）；迭代用 `-gselect=test_X`。
- 新 class_name 脚本须先 `godot --headless --path . --import` 重建类缓存再跑测试（历史坑）。
- 文件命名/注释风格随现有代码（中文注释、常量出处注记、教训注记）。
- 语料路径：`~/Library/Application Support/Godot/app_userdata/Trigger Echo/jump_training/`（577 个 episode，manifest.json 带 map_hash——**导出数据集必须随附哈希**，训练管线二次校验，用户铁律）。
- 数据集 JSON 提交入库：`Levels/M2_TDM/jump_edges_dataset.json`（M4 消费）。

## 四、任务分解（每任务独立子代理 + TDD + 审查）

### T1 边界隐形高墙（机械实现，最便宜模型）

**文件**：改 `Levels/M2_TDM/map_greybox.gd`；新建 `test/unit/test_boundary_walls.gd`。

**规格**：
- 新独立函数 `_build_boundary_walls()`，在 `build()` 中 `_spawn_solid` 循环后调用。
- 4 个 StaticBody3D（name/collision_layer 1/collision_mask 0），**只有 CollisionShape3D(BoxShape3D)，绝不加 MeshInstance3D**（仅碰撞无视觉）：
  - `BoundaryWallN`: center (0, 6, 30.5), size (62, 12, 1) → x∈[−31,31], z∈[30,31], y∈[0,12]
  - `BoundaryWallS`: center (0, 6, −30.5), size (62, 12, 1)
  - `BoundaryWallW`: center (−31.5, 6, 0), size (1, 12, 62) → x∈[−32,−31], z∈[−31,31]
  - `BoundaryWallE`: center (31.5, 6, 0), size (1, 12, 62)
- **几何依据注释必写**：可见边界墙外缘实测 x=±31（西/东墙 center ±30.5±0.5）与 z=±30（北/南墙 z∈[29,30]）；用户口径 z=±30.5 为 1m 厚墙中心（内缘恰贴可见墙外缘 z=30）；x 侧内缘贴 x=±31、外延 1m（center ±31.5）。角部由东西墙 z 跨 [−31,31] 覆盖，零缝隙零虚空陷阱；12m > 玩家最高可达 4.9+1.83+1.51≈8.2m 留 ~3.8m 余量。不写进 LAYOUT.all_solids()（保 193/哈希/跳跃记录）。
- `static_bodies()` 自动包含（无需改）。

**测试（先 RED 后 GREEN，test_boundary_walls.gd）**：
1. `MapGreybox.new()` + `build()` → 存在 4 个边界墙子节点，名字/位置/尺寸与规格逐项相等（`assert_almost_eq`）。
2. 每个边界墙：有且仅有一个 CollisionShape3D 子节点，shape 是 BoxShape3D 且 size 正确；**无 MeshInstance3D 后代**（`find_children("*", "MeshInstance3D")` 空）。
3. `static_bodies().size() == 197`（193 布局实体 + 4 边界墙）。
4. `LAYOUT.all_solids().size() == 193`（边界墙不在布局数据）。
5. 布局哈希锁定：`JumpRecordCore.map_hash(LAYOUT.all_solids(), MovementController.MOVEMENT_REV)` 与实现时实测值（先跑一次打出来，贴成常量）相等——锁定"边界墙不触发跳跃记录重置"保证。
6. 边界墙名不与 193 实体名冲突（all_solids 名字集 ∪ 4 边界名 = 197 唯一）。

**验证**：`-gselect=test_boundary_walls` 全绿 + 全量 GUT 339 不变 + `godot --headless --path . -s tools/probe_v3_walk.gd` 仍 79/79（MapGreybox 被实例化，证明边界墙无副作用）。

### T2 JumpEdge 面级数据结构（标准模型）

**文件**：新建 `Levels/M2_TDM/jump_edges.gd`（无 class_name，仿 LAYOUT 用 preload+static func）；新建 `test/unit/test_jump_edges.gd`。

**接口**（精确签名）：
```
static func faces() -> Array
# 每项 {"name": String, "top_y": float, "center": Vector2(xz), "size": Vector2(xz)}
# 规则同 probe_reachability._build_faces（Ground + standable_surfaces 含别名
#   Corridor→CorridorSlab / Altar→AltarPlatform + 实体顶面 kind∈wall/cover/roof
#   且 size.x≥0.4 且 size.z≥0.4，top = center.y + size.y/2）；
# 去重键 (x, top_y, z)。

static func link_face_edges() -> Array
# 每项 {"link": String, "from_face": String, "to_face": String,
#       "delta_h": float, "dist": float}
# 对 LAYOUT.jump_links() 每条：端点 y 与面 top_y 差 ≤0.01 且 xz 在面矩形
# 膨胀 0.3 内 → 归属；无匹配面 → 空串（不抛错，交报告标注）。
# delta_h = to.top_y − from.top_y；dist = 两面矩形水平最短距（同 probe_reachability
# _horiz_dist，差值必须取绝对值——历史教训）。

static func face_edge_groups() -> Array
# 按 (from_face, to_face) 去重合并，每项 {"from_face", "to_face", "delta_h",
# "dist", "link_names": [...], "takeoff_zone": {"center": Vector2, "size": Vector2},
# "landing_zone": {...}}
# zone 兜底 = 该对链接端点在该面上的包围盒 ±0.5 膨胀，钳制在面矩形内
# （语料校准后由数据集 JSON 提供人类簇覆盖，见 T4）。
```

**测试**：
1. `faces()` 含 Ground（top 0, 60×58）且名字去重唯一；面数 = 实现时实测贴常量。
2. 每条 link → from_face/to_face 非空，**除** `PavToSpur_WS`/`PavToSpur_ES`（已知疑似错误链接，白名单断言——发现更多未指派立即失败）。
3. 已知锚：`PavToCluster_W` → WestPavilion→WestClusterS_Panel，Δh=1.0；`WingToLintel_NW` → GateN_WingW→GateN_Lintel，Δh=1.9；`TowerBox_W` → WestTower→WestTowerBox，Δh=0.9；`RimGap_NW` → RimN1→RimN2，Δh=0.0；`Crate_WN` → Ground→WestClusterN_Box，Δh=0.9。
4. `face_edge_groups()` 覆盖全部 54 链接（各组 link_names 合并 = 54 条、无重复、无遗漏）。
5. 每组 zone 矩形 ⊆ 对应面矩形（钳制有效）；Δh 与面表一致。
6. 无未指派面（白名单外）→ 见 2。

**验证**：`-gselect=test_jump_edges` 全绿 + 全量 GUT 不回归。

### T3 抛物线物理求解器（标准模型；数学微妙，spec 为锚）

**文件**：新建 `Levels/M2_TDM/jump_solver.gd`（`class_name JumpSolver`，全 static、无场景依赖）；新建 `test/unit/test_jump_solver.gd`。

**接口**（精确签名，全部基于 §2.3 离散模型）：
```
const G := 19.6
const V_JUMP := 7.54
const DT := 1.0 / 60.0
const SPEED_CAP := 6.35
const CATCH_BAND := 0.5    # 脚可低于顶面 0.5 抓边（底球半径，2.2 语料实证）

static func rise_at(frame: int) -> float
# n≤0 → 0；n≥1 → n*V_JUMP*DT − G*DT*DT*n*(n−1)/2（闭合式，禁逐帧循环）

static func peak_rise() -> float      # 1.5133333（帧序列峰值）
static func catch_window(delta_h: float) -> Dictionary
# {"ok": bool, "t_min": float, "t_max": float, "f_min": int, "f_max": int}
# rise ≥ delta_h − CATCH_BAND 的帧区间；无解 → ok=false

static func required_speed(delta_h: float, dist: float) -> Dictionary
# {"ok", "v_req", "v_hi"} —— v_req = dist/t_max；上跳 t_min>0 时 v_hi = dist/t_min
# （过快早到撞立面），否则 v_hi = INF；dist≤0 → v_req 0

static func feasibility(delta_h: float, dist: float,
        cap: float = SPEED_CAP) -> Dictionary
# {"ok", "verdict": "easy"|"tight"|"knife"|"infeasible", "v_req", "margin"}
# margin = 1 − v_req/cap；≥0.2 easy / ≥0.05 tight / >0 knife / ≤0 或 !ok infeasible

static func landable_zone(takeoff_rect: Rect2, delta_h: float,
        to_rect: Rect2, cap: float = SPEED_CAP, step: float = 0.25) -> Dictionary
# {"ok", "reach_area", "to_area", "coverage"} —— 起跳区矩形膨胀 cap·t_max ∩ 接收矩形，
# 网格 step 采样面积比（确定性，无随机）
```

**测试**（期望值 = §2.4 锚定算例，容差 1e-4）：
1. `rise_at(0)==0`、`rise_at(24)==1.5133`、`rise_at(47)==0.0206`、`rise_at(48)==−0.1073`、`peak_rise()==1.5133333`。
2. `catch_window(0.9)` → ok, f_min=4, f_max=43；`catch_window(1.8)` → [15,32]；`catch_window(2.5)` → !ok（2.5−0.5=2.0 > 峰值 1.5133）。
3. `required_speed(0.9, 0).v_req == 0`；`required_speed(0.9, 2.0).v_req ≈ 2.79`。
4. `feasibility(1.8, 2.62)` → ok + verdict tight（v_req 4.91、margin 0.227→easy？——**实现时以公式为准**：v_req=2.62/(32/60)=4.9125，margin=1−4.9125/6.35=0.2264 ≥0.2 → "easy"；测试断言 verdict=="easy" 且 v_req≈4.91）。
5. `feasibility(1.9, 1.58)` → ok, easy, v_req≈3.16；`feasibility(1.9, 6.5)` → ok=false 或 verdict=="infeasible"（v_req 13.0>cap）。
6. `feasibility(0.0, 4.0)` → ok easy（t_max=43/60=0.7167 → v_req 5.58）。
7. 下降：`feasibility(-1.0, 5.0)` → ok easy（下落窗长）。
8. 确定性：同参数两次调用结果全等（`assert_eq` 整字典）。
9. `landable_zone(Rect2(0,0,2,2), 0.0, Rect2(0,0,4,4))` → coverage>0 且 reach_area≈π·r² 数值锚（r=cap·t_max≈4.55 → 采样面积 ≈65±3）。
10. 上跳可落区：`landable_zone(Rect2(0,0,1,1), 1.0, Rect2(0,0,6,6))` → ok；coverage ∈ (0,1)。

**验证**：`-gselect=test_jump_solver` 全绿 + 全量 GUT 不回归。

### T4 人类语料校准 + 数据集 JSON（标准模型，python）

**文件**：新建 `tools/export_jump_edges.gd`（导出 /tmp/jump_edges.json：faces + face_edge_groups + link_face_edges，供 python 消费）；新建 `tools/build_jump_dataset.py`；产出入库 `Levels/M2_TDM/jump_edges_dataset.json`。

**build_jump_dataset.py 规格**：
- 读 `/tmp/jump_edges.json`（先跑 export 工具）+ 语料 `~/Library/Application Support/Godot/app_userdata/Trigger Echo/jump_training/`（manifest.json + episodes/*.jsonl，共 577）。
- 每 episode（fail 分类跳过）：head 的 start_name/end_name 按别名映射（Corridor→CorridorSlab、Altar→AltarPlatform、@ 开头运行时噪声跳过）匹配面表。
- 按 (start_face, end_face) 聚合，对每组输出：
  - `n`（episode 数）、`chain_n`（中途有 on_floor 帧的链式跳跃数——episode 内落地再跳）、
  - `takeoff_speed`（t=0 帧 |v_xz| 的 p50/p10/p90）、`takeoff_feet_y`（py−0.915）、
  - `contact_feet_y`（首个落地帧 py−0.915）、`catch_depth`（to_top − contact_feet，正=低于顶面）、
  - `flight_ms`、`takeoff_rect`（样本 xz 包围盒）、`landing_rect`。
- 全局校准：`calibrated_peak_rise`（干净单跳样本最大接触升高的 p99）、`catch_depth_p90`（对照 CATCH_BAND 0.5 验证）。
- 边表：与 face_edge_groups 对齐（(from,to) 对），合并校准数据；每条标 `skill` 判定：
  - `"verified_easy"`｜`"verified_tight"`（语料 n≥1 且物理可行）
  - `"skill"`：物理 margin<5% 或链式占比>0 或 catch_depth 超出 CATCH_BAND（**技巧边标注**）
  - `"physics_only"`（无人类样本、物理可行——候选待验证）
  - `"suspicious_link"`：无面指派（PavToSpur_WS/ES 等）——**数据错误标注**
- 输出 JSON 结构：
  ```
  {"meta": {"map_hash": <语料 manifest 的 map_hash>, "movement_rev": <同 manifest 流程>,
    "corpus_episodes": int, "calibrated": {...}, "generated_by": "tools/build_jump_dataset.py"},
   "edges": [{...每组}], "unlinked_human_edges": [{(start,end) 人类跳过但无链接}],
   "link_audit": [{link 级：from_face/to_face/delta_h/dist/端点可执行 verdict}]}
  ```
- **哈希随附铁律**：meta.map_hash 必须等于语料 manifest.json 的 map_hash（用户规则：导出数据哈希随附，训练管线二次校验）；不一致则退出码 1。
- 确定性：输出排序（edges 按 (from,to) 字典序）、无随机。

**验证**：跑通三步（export → build → 检查 JSON 字段/计数）；`python3 -m json.tool` 合法；`n` 总数与语料非 fail 数一致；打印汇总表人工核对。

### T5 量化验证报告工具（标准模型）

**文件**：新建 `tools/probe_jump_edges.gd`（SceneTree headless）。

**规格**：
- 建面表 + 边组（jump_edges.gd）→ 每边求解器 verdict（feasibility(Δh, 边组 zone 间距离) + 链接端点级 feasibility）→ 载入 `res://Levels/M2_TDM/jump_edges_dataset.json` 对照。
- 报告表：每条边 `Δh | dist | v_req | 求解 verdict | 人类 n | 人类起跳速度 p50 | catch_depth p50 | skill 标注 | 一致性 ✓/⚠️/★/✗/!!`。
- 汇总：边组数、54 链接覆盖率、物理可行数、技巧边数、physics_only 数、可疑链接数。
- **退出码门禁**：①链接覆盖 <54 或存在白名单外无面指派链接 → 1 ②数据集 meta.map_hash ≠ 当前布局哈希（JumpRecordCore.map_hash(LAYOUT.all_solids(), MovementController.MOVEMENT_REV)）→ 1（防旧数据集被新布局消费——二次校验落地）③其余报告信息。可疑链接 PavToSpur_WS/ES 打印 `!!` 建议，不阻断退出码（修复待用户拍板）。

**验证**：headless 跑通输出完整报告 + 退出码语义正确（用临时改 hash 测门禁②）。

### T6 文档 + 全量验证 + 审查收尾（控制器 + 最强模型终审）

- 更新 `docs/HANDOFF.md`（待做段 → 完成段：边界墙 + 面级跳跃边 1+2+3 结果、数据集路径、可疑链接发现与建议）。
- 更新记忆 `trigger-echo-m2-tdm-map-progress.md` + 新建 `trigger-echo-jump-edge-dataset.md`（语料校准常量/数据集 JSON/技巧边定义——供 M3/M4 会话）。
- 账本 `docs/superpowers/ledger/2026-08-13-m2-boundary-jumpedges-ledger.md`（任务链、审查记录、发现）。
- **全量验证**：GUT 全绿（339+新增）、probe_v3_walk 79/79、probe_navmesh 全过、scan_gaps_v3 0 窄缝、probe_jump_edges 报告门禁过。git status 干净提交。

## 五、验证门禁汇总（全部通过才声明完成）

| 门禁 | 命令 | 期望 |
|------|------|------|
| GUT | `godot --headless --path . -s addons/gut/gut_cmdln.gd` | 339+新增全绿 |
| 漫游 | `godot --headless --path . -s tools/probe_v3_walk.gd` | 79/79、瞬移≤1 |
| navmesh | `godot --headless --path . -s tools/probe_navmesh.gd` | 全过 |
| 窄缝 | `python3 tools/scan_gaps_v3.py` | 0 处 |
| 跳跃边报告 | `godot --headless --path . -s tools/probe_jump_edges.gd` | 退出 0、覆盖 54/54 |
| 布局不变量 | T1 测试 5/6 | 193 实体、哈希不变（跳跃记录不重置） |

## 附：F 修复轮——4 条链接数据错误修复（2026-08-14 用户拍板）

**用户拍板**：PavToSpur_WS/ES **删除**；ClusterToRim_WS/ES 改端点。

**端点方案（求解器预验证）**：
- 仅改 from 不够（用户口径 from=±10.8 + 原 to=±4.7 → 7.24m、v_req 9.87 INFEASIBLE）——**to 必须跟到 rim 近端**。
- 定稿：WS from (-17.5, 2.20, 10.85) → to (-13.6, 3.00, 9.2)（与 RimToWing_NW from 共享端点，链条顺接）；ES 为 180° 旋转 (17.5, 2.20, -10.85) → (13.6, 3.00, -9.2)。
- 预验证：链接级 dist 4.23、v_req 5.77、margin 0.091（tight ✓）；zone 级 3.10、v_req 4.23（easy ✓）。
- 删除影响：WestSpurN/EastSpurS 顶面失去导航链（原链物理不可执行=假链，M4 无实损）；未来若要 AI 上远侧横脊墙，可补 RimW_T↔WestSpurN 1m 同高链接（另行拍板）。

**收敛动作**：T2 测试白名单 → 空（全部 54 链接必有面归属）；probe_jump_edges 门禁 B → 0 条空面；数据集重建（export→build，52→54 边组、link_audit 56→54、0 suspicious）；jump_edges.gd 注释同步。
**不变量**：jump_links 不属于 all_solids → 布局哈希不变 → **跳跃记录不重置**（577 条保留）；navmesh.res 不需重烘焙（几何未变）。
