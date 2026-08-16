# 计划：M3.1 移动层（Enemy 改造 + BotLocomotion 路径跟随 + 跳跃参数化执行）

> 日期：2026-08-16。分支 feat/m1-assets，单目录（勿建 worktree）。
> 设计：`docs/superpowers/specs/2026-08-16-m3-ai-foundation-design.md`（§4.1 移动层）。
> 本计划覆盖 M3 六阶段之 **M3.1 移动层**（T0-T5）；M3.2 感知层起另起计划文档（按项目惯例逐阶段）。
> 修改文件：`project.godot`、`Levels/Enemy/Enemy.tscn`、`Levels/Enemy/Enemy.gd`、
> `Player/MovementController.tscn`（仅碰撞掩码）、`Weapons/WeaponCore.gd`（仅掩码行）、
> `Weapons/MeleeController.gd`（仅掩码行）、`Weapons/Grenade.gd`（仅掩码行）、
> 新生产文件 `Levels/M2_TDM/bot_locomotion.gd`、新测试 ×5（T0-T5 各一）。
> 既有测试：`test/unit/test_auto_command.gd`（命令接口测试范式）、`test/unit/test_controller.gd`
> （物理装配范式）、`test/unit/test_enemy.gd`（若存在，Enemy 类型断言需按 T0 brief 授权更新）。

## 全局约束（逐字复制进每个任务 brief）

- 允许改动文件仅限上文清单。**禁止改动** `Player/MovementController.gd`（物理语义零改动 →
  MOVEMENT_REV 不 bump → 跳跃语料 706 条不重置，铁律）、布局 `map_layout_v3.gd`、
  `navmesh.res`、`jump_solver.gd`、`jump_edges.gd`（只读调用）、`jump_edges_dataset.json`（只读加载）。
- TDD：每个任务**先写失败测试跑 RED（确认失败原因正确），再实现跑 GREEN**。禁止先写生产代码。
- 每任务完成后跑全量 GUT：`godot --headless --path . -s addons/gut/gut_cmdln.gd`（基线 369，
  任务新增测试后应 369+N 全绿；既有断言不得改——T0 brief 仅授权 Enemy 类型断言
  StaticBody3D→CharacterBody3D 的机械替换，禁止改行为断言语义，审查者核对）。
- T0-T5 **串行派发**（bot_locomotion.gd 被 T2-T4 共享，上一任务 GREEN + 审查通过后才派下一任务）。
- 注释口径：新代码块注释注明「(2026-08-16 M3.1 Tn)」+ 一句机制说明，与文件既有风格一致
  （中文注释、参考 MovementController 注释密度）。
- 浮点断言容差 1e-4；物理帧驱动断言（集成类）用行为断言（位移/到达/信号计数），不断言精确帧数。
- **M2 行为兼容铁律**：M3.1 期间 bot 无 Brain——站桩不移动不攻击（command_override 恒 ZERO），
  L_M2 对局行为不变；改造后敌人仍可被命中/被玩家碰撞阻挡；友军/敌人死亡倒地淡出同现状。

## 任务表

| 任务 | 内容 | 新增测试数（约） |
|------|------|------------------|
| T0 | 物理层 "Bots" + Enemy 类改造（StaticBody3D→CharacterBody3D+MovementController）+ 武器命中掩码扩展 | 6 |
| T1 | MovementCommand 驱动冒烟（bot 输入语义固化，生产预期零改动） | 4 |
| T2 | BotLocomotion 路径跟随（寻路+途经点简化+前瞻转向+高度门+到达） | 6 |
| T3 | 跳跃段分类 + 参数化执行（pick_jump_speed 消费口径 + 直线助跑执行 + 失败事件） | 8 |
| T4 | 卡顿对策（滑墙/踢面正压/退化跑道/进展超时/卡死兜底） | 5 |
| T5 | 冒烟：bot 从南营出生点走跳跃链接链到塔顶 | 2 |

---

## T0：物理层 Bots + Enemy 类改造 + 命中掩码扩展

### 接口块（精确签名）

```gdscript
# project.godot [layer_names] 追加一行
3d_physics/layer_3="Bots"

# Enemy.gd 变更：
#   extends StaticBody3D  →  extends MovementController
#   _ready() 内新增首行 super._ready()；删除 body_shape 创建块（移入 tscn）；
#   新增：
const BOT_LAYER := 4        # 1<<2：layer_3 "Bots"
#   _ready 中：
collision_layer = BOT_LAYER
collision_mask = 3          # 1|2：世界几何+玩家身体（bot 撞墙撞玩家不穿人；bot 间互不碰撞防拥堵）
command_override = MovementCommand.new()   # 恒设：无 Brain 时站桩，防读玩家真实输入
#   HeadHitbox._ready 中：collision_layer = 4（原 1）
#   _die() 中新增：velocity = Vector3.ZERO   # 死亡帧清零速度（CharacterBody3D 不再是无重力静态体）
```

### 语义规格

1. **Enemy.tscn**：根节点 type `StaticBody3D` → `CharacterBody3D`；新增子节点
   `CollisionShape3D`（CapsuleShape3D：radius 0.31 / height 1.69 / position (0, 0.845, 0)）
   ——修复轮 1 裁决值：底=0 贴地消沉地、顶=1.69 与原命中顶界一致（头 hitbox 1.70 颈缝无缝）。
   形状 scene 声明（MovementController 的 `@onready _col_cached` 在树进入时查找，既有 F2a
   注释已说明缓存安全前提）。
   **⚠️ 消费方陷阱（修复轮 2 裁决记录，T1-T5 必读）**：生产代码全走 `Enemy.new()`
   （L_M2 友军/敌军、L_Main 训练靶），tscn 零引用——形状只放 tscn 会导致 new() 路径无
   碰撞体穿地坠落（审查实测 y=-36.87）。**强制要求**：`Enemy.gd _ready` 必须含懒创建
   兜底——`_find_collision_shape()` 为 null 时按 tscn 同参数代码创建；已取证
   MovementController.gd:254 对 `_col_cached` null 有首次使用再扫兜底，懒创建不影响 step-up。
   T1-T5 凡新建消费 Enemy 的路径一律优先 `Enemy.new()` 并信赖此兜底。
2. **Enemy.gd**：`extends MovementController`（class_name 全局可见）。_ready 顺序：
   `super._ready()`（物理查询缓存）→ 碰撞层/掩码/command_override → **懒创建兜底（见 1）**
   → 视觉 tint/标签/HeadHitbox/随机武器（既有逻辑不动，仅删除 body_shape 创建块）。
   碰撞掩码 **3**（1|2：世界几何 + 玩家身体——bot 撞墙撞玩家不穿人，bot 间互不碰撞防拥堵，
   修复轮 2 裁决；接口块第 57 行注释同步改 3）。
3. **玩家侧**：`Player/MovementController.tscn` 的 collision_mask 3 → **7**（1 Objects | 2 Player | 4 Bots）
   ——玩家身体撞 bot 被挡（现状语义保持：敌人挡路）。
4. **武器命中侧**（bot 换层后 hitscan/近战/爆炸必须仍命中）：mask 1 → **5**（1|4），注释同步：
   - `WeaponCore.gd:257` `query.collision_mask = 1` → `5`（hitscan）
   - `MeleeController.gd:148` `params.collision_mask = 1` → `5`（近战）
   - `Grenade.gd:79` `collision_mask = 1` → `5`、`:102` `query.collision_mask = 1` → `5`、
     `:149` `pq.collision_mask = 1` → `5`（爆炸三处）
5. **torso 组语义不变**：MovementController step-up 查询过滤 torso/head 组（既有）——bot 在
   torso 组 → 玩家登台查询继续忽略 bot（不把 bot 当地形踩）。玩家对 bot 的碰撞阻挡由
   move_and_slide 掩码 7 提供，两条路径互不干扰。
6. **死亡行为**：`_die()` 加 `velocity = Vector3.ZERO`（防 CharacterBody3D 尸体被残余速度
   推离倒地点）；倒地/淡出/queue_free 流程不动。
7. **`_physics_process` 继承链（关键）**：Enemy.gd 既有 `_physics_process`（出生保护白闪/
   死亡动画）**覆盖**了 MovementController 的移动物理——改造后必须改为：
   ```gdscript
   func _physics_process(delta: float) -> void:
       if not dead:
           super._physics_process(delta)   # 移动/重力/step-up 物理（命令接口驱动）
       # 白闪 / 倒地 / 淡出逻辑（既有，不动）
   ```
   漏掉 super 调用 = bot 不响应 command_override（测试 2/3 会 RED 抓住）。
8. 若既有测试存在 `Enemy is StaticBody3D` 类型断言：机械替换为 `CharacterBody3D`
   （brief 授权范围内）；行为断言（take_damage/died/友伤过滤）一律不改。

### 测试规格（test/unit/test_enemy_bot_body.gd 新建，TDD RED 先行）

1. `test_enemy_is_character_body`：`Enemy.new()` 后 `assert_true(enemy is CharacterBody3D)`
   （RED：改造前是 StaticBody3D）。
2. `test_enemy_falls_onto_floor`：Enemy 悬空 (0, 2, 0) 生成 + 地面 → 物理帧推进 60 帧
   → 断言 global_position.y < 1.1（重力落地，改造前静态体悬空不动）。
3. `test_enemy_stands_still_without_brain`：地面 + Enemy → 推进 60 帧 → 水平位移 < 0.1
   （command_override 恒设 ZERO 站桩——RED：改造前无 command_override 概念，此断言绿；
   真正 RED 锚 = 测试 1/2）。
4. `test_player_blocked_by_bot`：Player.tscn + 地面 + bot 站 (0,0,-2) → 玩家 move_axis=(0,1)
   60 帧 → 断言玩家 z 未越过 bot 位置 +0.85（碰撞阻挡；接触距 = 双方胶囊半径和
   0.5+0.31 = 0.81，阈值 +0.04 裕量——修复轮 2 裁决修正，勿照抄早期 0.3 值；改造前
   StaticBody 挡路同语义，掩码 7 保回归）。
5. `test_hitscan_mask_hits_bot`：bot 站地面 → `PhysicsRayQueryParameters3D` 自上方
   `collision_mask = 5` → 断言命中 bot 的 CollisionShape3D（RED：改造前 bot 在层 1，
   mask 5 不含 1 时漏——注意 RED 阶段 mask=5 恰命中旧层 1 bot？**RED 锚取 bot 在层 4**
   ：断言 `enemy.collision_layer == 4` 先行，再断言 mask 5 命中）。
6. `test_dead_bot_velocity_zeroed`：bot 给速度 → `take_damage(999)` → 断言
   `enemy.velocity == Vector3.ZERO`（若 Enemy 无 velocity 属性即 RED——改造前是静态体）。

---

## T1：MovementCommand 驱动冒烟（bot 输入语义固化）

### 接口块

```gdscript
# 无生产代码新增（T0 已备 command_override）。若测试暴露缺口，修复落在 T0 文件范围。
# 测试用接口：
MovementCommand.move_axis: Vector2   # x=左右 / y=前后（角色本地轴）
MovementCommand.jump_pressed: bool   # 单帧边沿（控制器读取后清零）
MovementCommand.crouch: bool         # 预留恒 false
```

### 测试规格（test/unit/test_enemy_command_drive.gd，TDD）

参照 `test_auto_command.gd` 装配范式（真实 Enemy 实例 + `_make_box` 地面 + 物理帧推进）：

1. `test_bot_move_axis_forward`：cmd.move_axis=(0,1) 60 帧 → -Z 位移 > 0.5，X 位移 ≈ 0
2. `test_bot_move_follows_yaw`：`enemy.rotation.y = PI/2` + cmd.move_axis=(0,1) → **-X** 位移 > 0.5
   （Godot 右手系：yaw=+π/2 时 basis.z=+X，本地前进=-basis.z=-X——T1 实现者实测修正，
   勿照抄旧"+X"；z 残差 <0.2 守卫"严格沿朝向轴"）
3. `test_bot_jump_edge_consumed`：cmd.jump_pressed=true 一帧 → 后续 `cmd.jump_pressed == false`
   （读取即清零）+ 起跳后 y 上升 > 0.5（玩家同款跳跃，跳高 1.51±0.05 物理语义不测全量，
   仅断言离地）
4. `test_bot_crouch_reserved_false`：crouch=false 全程 → 高度/速度无 crouch 特征
   （位移与测试 1 同量级）

---

## T2：BotLocomotion 路径跟随（新文件 Levels/M2_TDM/bot_locomotion.gd）

### 接口块（精确签名，实现者照抄）

```gdscript
class_name BotLocomotion
extends Node

signal arrived                    # 到达目标（决策层 M3.3 消费；M3.1 仅冒烟断言）
signal jump_failed(link_name: String)  # 跳跃失败（T3 发出；决策层 M3.3 消费）

const ARRIVE_RADIUS := 0.8        # 到达半径（水平距）
const HEIGHT_GATE := 0.72         # 途经点高差门（> 此值 → 走跳跃执行/重寻路）
const SIMPLIFY_STEP := 1.0        # 途经点简化：1.0m 稠密点
const SIMPLIFY_DY := 0.2          # 途经点简化：0.2 高差保留

var body: CharacterBody3D         # Enemy（读 global_position / rotation.y）
var map_rid: RID                  # 导航地图 RID（L_M2 get_world_3d().navigation_map）
var command: MovementCommand      # 指向 body.command_override（同引用）

func setup(b: CharacterBody3D, m: RID) -> void
func set_target(pos: Vector3) -> void   # 寻路（optimize=false）+ 简化 → 内部 _path
func clear_target() -> void
func tick(delta: float) -> void         # 每物理帧调用（Enemy._physics_process 或 Brain）

# static 纯函数（可单测，实现者照抄语义）：
static func simplify_path(points: PackedVector3Array) -> PackedVector3Array
static func approach_point(body_pos: Vector3, body_yaw: float,
        point: Vector3, next_point: Vector3) -> Vector2
static func within_height_gate(body_pos: Vector3, point: Vector3) -> bool
```

### 语义规格

1. `set_target`：`NavigationServer3D.map_get_path(map_rid, body.global_position, pos, false)`
   → `simplify_path` → `_path`（起点丢弃——含 body 自身点）。
2. `simplify_path`：保留转折点（方向变化）+ 1.0m 稠密点（沿段插值）+ 任意点间 y 差
   ≥0.2 的点必保留（坡道/台阶走面信息不丢——遍历器时代验证参数）。
3. `tick`：
   - `_path` 空 → return
   - **到达弹点优先于高度门**（修复轮 1：终点在高面时先到达后门）：当前途经点水平距 <
     ARRIVE_RADIUS → 弹下一途经点；弹到空 → `arrived.emit()`
   - **高度门（navmesh 空间双锚——修复轮 1 裁决，勿照抄旧"途经点 y − body y"口径）**：
     `point.y − map_get_closest_point(map_rid, body 位置).y > HEIGHT_GATE` → T3 跳跃段路径
     （T2 内：重寻路一次，失败 `arrived` 不发、`jump_failed` 不发——T3 接管此分支）。
     两端同为 navmesh 空间 y，面偏移 +0.3~0.4 天然抵消：微台阶 0.6 ≤ 0.72 放行、链接段
     ≥1.0 触发。旧口径混合坐标系（body 物理 y）会在任何台阶路径误触停摆（审查 v4 实证）。
     亦勿用"途经点间 y 差"——稠密插值摊薄链接段 y 跳变漏检（审查实测）。
   - `approach_point`（前瞻转向，遍历器 fix 8 教训）：朝当前点移动，但转向目标 = 看下段——
     若 next_point 存在且当前点距 body < 1.5，转向基准取 next_point（提前转，不绕最小转弯圆）
   - **到达"越过"规则**（审查接受偏差）：距下一途经点 ≤ 距当前途经点即弹点（循环）——
     纯半径判定在锐角弯切角半径 >0.8 时永不到达转圈卡死
   - 输出：`command.move_axis = approach_point(...)`（y=前后）；无 crouch/jump（T3 接管 jump）
4. `within_height_gate`：navmesh 双锚比较（签名可调整为含 map_rid 或预取 closest 点的
   等价形式——实现者自选最简可单测方案，注释说明）。

### 测试规格（test/unit/test_bot_locomotion_path.gd，TDD）

1. `test_simplify_keeps_corners`：L 形路径点 → 保留拐点
2. `test_simplify_dense_step`：10m 直线 → 简化后相邻点间距 ≤1.0（含端点）
3. `test_simplify_keeps_dy`：平路 + 0.3 高差台阶点 → 台阶点保留
4. `test_approach_toward_point`：yaw=0、目标在 -Z → 输出 (0, 1) 前进
5. `test_approach_lookahead`：当前点近 + next_point 在侧面 → 输出含侧向分量（前瞻修正）
6. `test_height_gate_boundary`：高差 0.72 内 true / 0.73 false（边界断言）
7. `test_follow_short_path`（集成）：装配 L_M2 场景实例 → **立即 queue_free 场景内 JumpRecorder
   子节点**（防测试污染 user://jump_training 人类语料——L_M2._ready 会启动记录器）→ 等导航
   两轮迭代（迭代 id ≥ 基值 +2）+ **再等 60 物理帧**（54 链接注册完成的余量，L_M2 F4 教训：
   链接创建在 call_deferred 异步链上）→ 新建 Enemy 置北营地面点 → BotLocomotion.setup(enemy,
   map_rid) → set_target(20m 内平地可达点) → 推进 ≤600 物理帧断言 arrived 发射 + 距目标 < 1.0
   （到达即提前退出循环，不跑满上限）

---

## T3：跳跃段分类 + 参数化执行（bot_locomotion.gd 扩展）

### 接口块（精确签名）

```gdscript
# 常量（bot_locomotion.gd 常量区）
const RUNUP_TURN_GATE := 0.3      # rad：助跑转向门（遍历器 F8 验证值）
const RUNUP_GATE_SPEED := 4.0     # m/s：触发速度门（遍历器验证值）
const TRIGGER_CONE := 0.9         # 方向锥 cos 系数（±25°，遍历器 F9 验证值）
const JUMP_TIMEOUT := 2.5         # s：起跳→落地判定超时

# static 纯函数（T3 新增）
static func classify_segments(points: PackedVector3Array, links: Array) -> Array
# links = setup 时一次预对齐的端点表 [{name, from:Vector3, to:Vector3}]（LAYOUT.jump_links()
# 端点经 map_get_closest_point 对齐——link 注册即导航点，L_M2 F4 教训；路径点本身即导航点，
# 对齐后可直接比对，分类保持纯函数可单测）
# 返回 [{type:"WALK", from:Vector3, to:Vector3}, {type:"JUMP", from:Vector3,
#         to:Vector3, link_name:String}]——相邻点对与 links 端点双向距离 < 0.5 即 JUMP 段
static func pick_jump_speed(delta_h: float, dist: float, human_p50: float,
        augmented: bool, v_req: float) -> float
# 消费口径（设计 §4.6 拍板哲学）：
#   真实人类 p50（augmented=false 且 human 非空）→ 原值
#   增强样本 p50（augmented=true）→ p50 × 0.9（置信折扣）
#   无人类数据 → 求解器 v_req × 1.15
# 最终钳制：clamp(v, r.v_req, r.v_hi)——r = JumpSolver.required_speed(delta_h, dist)
# （v_hi 可为 INF，GDScript clamp 对 INF 上界安全）；r.ok=false → 返回 v_req×1.15
# 且调用方不触发跳跃（诚实失败路径）。注意：feasibility 返回键为
# {ok, verdict, v_req, margin}（无 v_min/v_max，勿照抄早期计划笔误）。

# 实例方法（T3 新增）
var _jump: Dictionary   # 执行中跳跃状态 {from, to, link_name, t}
signal jump_failed(link_name: String)   # T2 声明，T3 起发出
```

### 语义规格

1. **运行时数据加载**：`_ready` 或首次使用时 `FileAccess` 读
   `res://Levels/M2_TDM/jump_edges_dataset.json` → 静态缓存
   `_dataset_edges: Dictionary`（key = `"from_face|to_face"`）。链接名 → 边组查找：
   `JumpEdges.face_edge_groups()`（link_names 匹配）→ 边组 from_face/to_face →
   dataset 边 → `human.takeoff_speed.p50` / `human.augmented` / `physics.v_req`。
   查找失败（无数据集条目）→ 用 `JumpSolver.required_speed(delta_h, dist)` 的 v_req 走
   v_req×1.15 档。
2. **执行流**（tick 内，当前段为 JUMP 时）：
   - 阶段 RUNUP：朝段起点直线助跑——转向差 ≤ RUNUP_TURN_GATE 才前进（原地转消除
     最小转弯圆，遍历器 F8）；到达起点水平距 < 0.8 进入 TRIGGER
   - 阶段 TRIGGER：`hspeed = 水平速度`；满足 `hspeed ≥ RUNUP_GATE_SPEED` 且
     速度方向·段方向 ≥ TRIGGER_CONE × hspeed → `command.jump_pressed = true`（单帧边沿，
     下一帧控制器自动清零）→ 阶段 AIR
   - 阶段 AIR：微调（保持 move_axis 沿段方向，空中控制 wish_cap RUN 档既有物理）→
     落地检测（body.is_on_floor() 或超时 JUMP_TIMEOUT）→ 判定：落地位置在
     `JumpEdges._in_rect`(landing_zone 膨胀 0.5) 或与段 to 点水平距 < 1.5 → 成功继续
     后续段；否则 `jump_failed.emit(link_name)` → 该链接临时惩罚（内部
     `_penalized_links`）+ `set_target(原目标)` 重寻路一次（重寻路仍含该链接 →
     放弃目标，`clear_target()`——决策层 M3.3 接管换目标，M3.1 仅诚实失败）
3. **classify_segments 匹配口径**：`LAYOUT.jump_links()` 的 from/to 先经
   `NavigationServer3D.map_get_closest_point` 对齐（link 注册即导航点——L_M2 F4 教训），
   再与路径相邻点对双向距离 < 0.5 判定匹配。
4. **pick_jump_speed 钳制带**：`JumpSolver.feasibility(delta_h, dist)` 返回
   `{feasible, v_min, v_max, v_req}`（既有函数，只读调用）——v 钳 [v_min, v_max]，
   infeasible 时返回 v_req×1.15 且调用方不触发跳跃（诚实失败路径）。

### 测试规格（test/unit/test_bot_jump_exec.gd，TDD）

1. `test_pick_human_p50_first`：真实样本（augmented=false）→ 返回 p50 原值
2. `test_pick_augmented_discount`：增强样本 → p50 × 0.9（容差 1e-4）
3. `test_pick_solver_fallback`：无人类 → v_req × 1.15
4. `test_pick_clamps_feasible_band`：p50 超出 [v_min, v_max] → 钳到带内
5. `test_classify_walk_and_jump`：构造路径点含一组 link 端点对 → 分类含 JUMP 段且
   link_name 正确；纯直线点 → 全 WALK
6. `test_classify_endpoint_tolerance`：端点对偏移 0.4 → 仍匹配；偏移 0.6 → 不匹配
7. `test_jump_exec_success`（集成）：L_M2 装配 + 导航同步 → bot 置塔坡道底 →
   set_target 塔顶面（RampW 链第一跳）→ 推进断言到达（arrived）且 `jump_failed` 零次
8. `test_jump_failed_emits`：set_target 空中不可达点（如 (0, 30, 0) 半空）→ 推进断言
   `jump_failed` 发射或诚实放弃（clear_target 后 arrived 不发）

---

## T4：卡顿对策（bot_locomotion.gd 扩展）

### 接口块（精确签名）

```gdscript
# 常量
const WALL_PRESS_TIME := 0.5      # s：压墙判定（持续水平位移 < 0.05 且贴墙）
const WALL_SLIDE_TIME := 2.0      # s：切线滑移时长
const DEGEN_RUNWAY := 0.6         # m：退化跑道圆盘半径（< 此距离近静止放行）
const PROGRESS_TIMEOUT := 8.0     # s：无进展超时（位移 < 0.2 且未到达）
const REPATH_LIMIT := 2           # 次：重寻路上限
const STUCK_TIME := 5.0           # s：卡死判定
const STUCK_DIST := 0.3           # m：卡死位移阈值
const KICK_NORMAL_TURN := 1.2     # rad：踢面正压转向角（碰撞法向偏转后前进）

# 实例状态
var _wall_press_t := 0.0
var _wall_slide_t := 0.0
var _slide_handedness := 0        # 切线滑移手性锁存（每 episode 清零）
var _progress_t := 0.0
var _progress_pos := Vector3.ZERO
var _repath_count := 0
var _stuck_t := 0.0

# static 纯函数（可单测）
static func slide_axis(body_yaw: float, handedness: int) -> Vector2
static func kick_turn_axis(body_yaw: float, contact_normal: Vector3,
        target_dir: Vector3) -> Vector2
```

### 语义规格

1. **滑墙**（遍历器病理 1）：贴墙（`get_slide_collision_count() > 0` 且水平速度 < 0.05）
   累计 WALL_PRESS_TIME → 进入切线滑移 WALL_SLIDE_TIME（`slide_axis`：与墙法向正交的
   移动轴，手性锁存 `_slide_handedness`，每次 set_target 清零）→ 滑移结束恢复前进。
2. **踢面正压**（遍历器病理 2）：贴墙且目标方向与碰撞法向同侧（`pos - contact_normal`
   恒在墙内 → 直接前进无进展）→ `kick_turn_axis`：沿法向偏转 KICK_NORMAL_TURN 转向
   脱离墙（替代直接前进）。
3. **可攀面豁免**：贴墙点前方 0<高差≤0.62（step-up 可走上）→ 不滑墙，压入直走
   （MovementController 自动登台处理）。
4. **退化跑道**：目标点水平距 < DEGEN_RUNWAY → 近静止放行（不触发超时/滑墙），
   到达判定 ARRIVE_RADIUS 正常收敛。
5. **进展超时**：`_progress_t` 累计（位移 < 0.2 且未到达时累加，反之清零）——
   超 PROGRESS_TIMEOUT → `_repath_count < REPATH_LIMIT` 则重寻路 + 计数，超限 →
   `clear_target()`（诚实失败）。
6. **卡死兜底**：5s 内总位移 < STUCK_DIST → 同上重寻路/放弃路径。
7. 全部对策与 T2/T3 正交（tick 内独立守卫，不改变正常路径执行流）。

### 测试规格（test/unit/test_bot_stuck_counter.gd，TDD）

1. `test_slide_axis_orthogonal`：yaw 任意 + 墙法向 (0,0,1)（北墙）→ 输出轴与墙平行
   （x 分量 ≠ 0，y 分量 = 0），手性 ± 一致
2. `test_kick_turn_departs_wall`：目标方向压墙 → 输出轴含离墙分量（dot(normal) > 0）
3. `test_progress_timeout_pure`（static 判定函数化）：构造 8s 无进展序列 → 判定超时；
   中间有位移 → 清零
4. `test_stuck_bailout`（集成）：bot 贴墙目标点（墙后不可达）→ 推进断言 ≤3 次重寻路后
   clear_target（arrived 不发、不无限卡）
5. `test_degen_runway_release`（集成）：目标点 0.5m 内 → 快速到达（无超时触发）

---

## T5：冒烟——出生点走跳跃链接链到塔顶

### 测试规格（test/unit/test_bot_nav_smoke.gd）

装配 L_M2 场景实例（同 T2 测试 7 口径：先 queue_free JumpRecorder、等迭代 +60 帧）→
Enemy 置南营出生点（`LAYOUT.camp_spawn_points(-1)` 任一点）→ BotLocomotion.setup →
`set_target(塔顶面中心)`（WestTower 顶，top_y=2.5，面中心取自
`JumpEdges.faces()` 中 WestTower 条目）→ 推进 ≤5400 物理帧（90s 上限，**到达即提前
退出循环**）断言：

1. `test_bot_reaches_tower_top`：arrived 发射 + 最终位置距目标 < 1.0
2. `test_no_jump_failure_on_chain`：全程 `jump_failed` 计数 == 0（链接链一次成功率）

---

## 验收（M3.1）

- GUT 全量绿：369 + T0-T5 新增（约 31）全过，既有 369 无回归（T0 授权改动除外）
- `godot --path . Levels/M2_TDM/L_M2.tscn` 实机：敌人站桩如常、可被命中、玩家可被
  敌人挡路、无报错——M2 行为零回归
- 冒烟集成（T5）证明 bot 能自主走完跳跃链接链（M3.3 决策层接入前的移动能力证明）
