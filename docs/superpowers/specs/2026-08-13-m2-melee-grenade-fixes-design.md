# M2 战斗手感三项修复设计：手雷 LOS 挡伤 + 投掷手感、近战连击窗口/stab 射程分级、`_in_cone` 垂直差上限

> 日期：2026-08-13 · 分支 feat/m1-assets（单目录 /Users/elanyi/Projects/Trigger-Echo）
> 状态：设计待用户批准。用户 2026-08-13 指令：2/3 按已提方案改；第 1 项在 LOS 挡伤之外**增加投掷手感优化**（蓄力抛物线起点 = 右手手雷处，向玩家视角中间目标点延伸，弧线完整可见、落点清晰、实际轨迹与预览一致），实现逻辑参考网上 FPS 投掷系统资料。
> 网上调研：[CS2 手雷指南（swap.gg）](https://swap.gg/id/blog/cs2-grenade-guide-2026)（三种固定投掷力度/准星指向瞄准法）、[Godot 论坛抛物线瞄准辅助讨论](https://forum.godotengine.org/t/parabolic-arc-as-aim-assist/141969/9)、[Godot 论坛手雷轨迹实现帖](https://godotforums.org/d/34759-how-do-i-code-the-trajectory-for-throwing-grenades/4)（未加载成功）。Source 引擎 RadiusDamage LOS 机制 + 视图模型投掷原点为设计依据（自研实现，非复制代码）。

---

## 一、手雷 LOS 墙体挡伤（现穿墙满伤）

**现状**（`Weapons/Grenade.gd` `_apply_blast_damage`）：球形查询半径内全部目标按距离线性衰减吃伤，墙体完全不遮挡。M2 v3 设计 §十二风险4「市集棚顶棚下段雷不进」因无 LOS 至今空转。

**方案**（Source RadiusDamage 每受害者 LOS trace 思路，自研实现）：
1. 每个半径内目标从**爆炸中心**打一条射线到目标**胸口参考点**（`target.global_position + Vector3(0, blast_los_probe_height, 0)`，新 .tres 字段，默认 1.0m）。
2. 射线 mask=1（世界+目标同层）；**exclude 目标自身全部碰撞 RID**——本体 RID（`hit["collider_id"]`）+ 子节点 CollisionObject3D 的 RID（头 hitbox 是独立 body，不排除会**自挡**：Enemy.gd 躯干胶囊与 HeadHitbox 两个独立 collider）。
3. 射线有剩余命中 → 该目标伤害 0（CS 全遮挡语义，无穿透衰减）。
4. **地板假遮挡防御**：探测点必须是胸口高度——贴地射线会打中地板（世界 y=0 也是 layer 1），把贴地爆炸全挡成 0 伤。此点以测试固化（回归重点）。

**v1 简化注记**：其他玩家身体也算遮挡（射线命中即有遮挡，实现简单一致）；若 playtest 反馈队友挡雷破坏体验，改"命中对象有 take_damage 即视为穿透"。

**性能**：每雷 ≤10 条射线，可忽略。

## 二、手雷投掷手感（蓄力抛物线：起点=右手雷处、向视角中心目标点延伸）

**现状**（`Weapons/WeaponManager.gd:272-273/330`）：预览与真实手雷都从**相机位置**沿**视向**以固定 15.0 强度出发——弧线起点在屏幕中心（穿过准星）、前半段出画不可见；预览落点 = 弹道末点**投影 y=0**（长弧时末点仍在空中 → 落点标错浮空）。

**方案（四个子项）：**

### 2.1 投掷原点 = 右手手雷处（视图模型实时位置）
- WeaponManager 增加 `set_weapon_view(view)` 接线（scene glue 已有 WeaponView.setup(manager, ...) 先例）；WeaponView 增加 `get_throw_origin() -> Vector3`：返回 `view_model.weapon_mount` 下第一个 MeshInstance3D 的 `global_position`（手雷网格中心 = 右手雷处；随蓄力后拉/上抬动画实时跟随——WeaponView `_tick_throw` 会动武器位姿）。
- **回退**：未接线（单元测试环境）→ 相机位置（现行为，测试兼容）。
- 真实 Grenade 生成位置同样改为该点（`Grenade.init(origin, ...)`），雷体层 2 不与自己/玩家碰撞，从手中出生安全。

### 2.2 投掷方向 = 向视角中间目标点
- 瞄准点 `aim_point`：从相机沿视向射线打 **mask=1**，上限 **30m**（`throw_aim_max_dist`，WeaponManager export）；无命中（瞄天空）→ `camera + view_dir × 25m`（`throw_aim_fallback_dist` export，方向≈视向，行为连续）。
- 投掷方向 = `(aim_point − throw_origin).normalized()`——**瞄哪打哪**（CS lineup 文化同一原理：准星指向即轨迹参照）。
- 每物理帧重算（转身/移动时预览实时跟随）。强度保持固定 15.0（CS 固定投速同思路；[CS2 三档力度](https://swap.gg/id/blog/cs2-grenade-guide-2026)为参考背景，力度分级不在本轮范围——沿用既有"按住蓄力→松开出手、右键取消"拍板方案）。

### 2.3 预览与实际轨迹一致（单一来源 + 积分同构）
- **单一来源**：`_launch_params() -> {origin, direction}` 同时供 `_trajectory.update_trajectory` 与 `grenade.init` 使用（strength 统一 `throw_strength`）——预览与真实投掷同原点、同方向、同强度。
- **积分同构**：`ThrowTrajectory.STEP_SECONDS` 0.02 → **1/60**（=物理帧长）；`POINT_COUNT` 50 → **200**（3.33s，覆盖垂直上抛 3.06s 全弧）。预览半隐式欧拉与 RigidBody3D 积分器同构、重力同源 `default_gravity`。
- 反弹不预测（预览止于首次触地点，CS 反弹同样不可精确预测）——注记。

### 2.4 弧线完整可见 + 落点清晰
- 起点在画面右下（手雷处）、向屏幕中心延伸——弧线主体留在视野内（起点出画问题根治）。
- **落地判定修正**：逐点检测首次穿越 y≤0，线性插值求精确落点；可见点列**截至穿越点**（不再画入地下）；旧"末点投影 y=0"作废（长弧浮空错标根因）。4s 内不落地兜底：回落末点投影（旧行为）。
- **落点标记增强**：圆环 0.25→0.3 半径 + **竖直落点线**（可见点列末端垂直到落点环）——落点一目了然。

## 三、近战连击窗口严格化 + stab 射程分级（按已批准方案）

**现状**（`MeleeController._light_damage`）：`_combo_secondary` 每次轻击无条件交替——隔 10 秒再挥仍算连击 25；轻/重共用 `melee_range` 2.0m。

**方案**：
1. `melee_combo_window`（新 .tres 字段，默认 **0.8s**）：自**挥击发起帧**计时（与 cooldown 同帧刷新）；`_light_damage` 时窗口已过期 → 重置 `_combo_secondary=false` 回 primary 40。窗口 = 2× 轻击间隔 0.4s，对齐 CS 连斩节奏。
2. `melee_stab_range`（新 .tres 字段，**1.6m**）：权威值 [cs2-weapon-data.md:48](docs/superpowers/reference/cs2-weapon-data.md#L48)「slash 48u≈2.0m / stab 32u≈1.6m」——CS 重刺触及短于斜挥。`_pending_range` 随 `_pending_damage` 挥击时捕获（轻=melee_range / 重=melee_stab_range），`_resolve_swing` → `_in_cone` 传 range 参数。

## 四、`_in_cone` 垂直差上限（按已批准方案）

**现状**：纯水平面（XZ）判定，垂直方向无约束——隔 3m 层高差水平距离够近也能刀中。

**方案**：`melee_vertical_range`（新 .tres 字段，默认 **1.5m**），`_in_cone` 增加 `abs(target_pos.y − origin_pos.y) ≤ melee_vertical_range`（脚部-脚部，origin=眼位）。

**语义验证**：同层 0 ✓；摊阁 1.2m 位差（上打）= |1.2−1.63|=0.43 ✓；祭坛台 0.6m 下打上 = |0−2.23|=2.23 ✗（禁止隔台刀人，眼位基准使"上打容易、下打难"，符合直觉）；望楼 2.5m / 回廊 3.0m ✗。

## 五、.tres 新字段总表（数值唯一来源）

| 字段 | 默认值 | 所属资源 | 用途 |
|---|---|---|---|
| `blast_los_probe_height` | 1.0 | weapon_m67.tres | LOS 探测点高（胸口） |
| `melee_combo_window` | 0.8 | weapon_knife.tres | 连击窗口（s） |
| `melee_stab_range` | 1.6 | weapon_knife.tres | 重刺射程（CS 权威） |
| `melee_vertical_range` | 1.5 | weapon_knife.tres | 近战垂直差上限 |

Weapon_Resource.gd 同步新增属性；投掷手感参数（aim 30/25m）为 WeaponManager export（`throw_strength` 前例，非武器数值）。

## 六、TDD 断言清单（GUT）

**手雷 LOS**：
1. 墙后目标 0 伤（墙在爆心与目标间）
2. 无遮挡 → 距离衰减满值（现测试回归）
3. 贴地爆炸不假遮挡（胸口射线过地板——地板假遮挡回归）
4. 头 hitbox 自挡回归：带 head 子体的目标 LOS 不误判遮挡
5. 矮掩体 0.9 箱不遮挡（射线过顶）/ 高掩体 2.2 遮挡

**投掷手感**：
6. 单一来源：`_launch_params` 输出 == 预览参数 == Grenade.init 参数（测试捕获对比）
7. 瞄点射线：aim_point = 射线命中点；瞄天空 → fallback 点（方向≈视向）
8. 预览积分：STEP=1/60、POINT_COUNT=200、重力同源
9. 落地穿越：45° 上抛落点 ≈ 解析值（同公式派生，容差）；可见点列最后一点 y>0 且无入地点
10. 垂直上抛 3.06s 在 200 点（3.33s）内落地
11. 落点标记：landing_point = 穿越点（非旧"末点投影"）

**近战**：
12. 连击窗口：0.8s 内连击 → 25；隔 0.9s → 40（窗口计时自挥击帧）
13. stab 射程：1.8m 重刺不中 / 1.5m 重刺中；轻击 2.0m 不受影响
14. `_in_cone` 垂直：同层中 / 1.2m 位差中 / 2.5m 位差不中 / 祭坛台 0.6m 下打上不中
15. 既有 276 测试全绿回归（test_melee / test_throw_trajectory / test_damage_dedup 期望按需更新）

## 七、范围外（YAGNI）

- CS2 三档投掷力度（LMB 远投/RMB 低抛/双键中投）——沿用既有拍板（固定强度+右键取消），用户未要求
- 跳投（jump throw bind）
- 预览反弹预测（止于首次触地点）
- 投掷充能变力

## 八、实施顺序预览（供 writing-plans 拆分）

| 任务 | 内容 | 验收 |
|---|---|---|
| T1 | Weapon_Resource + 两 .tres 新字段（机械，数值齐全） | 断言 12-14 红 |
| T2 | MeleeController：连击窗口 + stab 射程 + 垂直差 | 断言 12-14 绿 |
| T3 | Grenade LOS 挡伤 | 断言 1-5 绿 |
| T4 | 投掷手感：_launch_params/瞄点射线/预览积分与落地修正/落点标记 | 断言 6-11 绿 + 实机肉眼验证 |
| T5 | 全量回归 + 门禁 + 文档同步（FEATURES 三项转 🟢 / HANDOFF / PROGRESS / 记忆） | 276+ 全绿 |

**文档同步义务**：FEATURES.md「遗留（M2 前）」三项转 🟢；HANDOFF 运行细节补投掷手感描述（抛物线起自右手、瞄哪打哪）。

---
*依据：网上调研三源 + Source RadiusDamage/视图模型投掷原点机制 + cs2-weapon-data.md 近战权威值；数值全部 .tres 化，TDD 全程。*
