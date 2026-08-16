# 计划：M3.2 感知层（BotPerception 视线/听觉/LKP + 事件板 + 黑板）

> 日期：2026-08-17。分支 feat/m1-assets，单目录（勿建 worktree）。
> 设计：`docs/superpowers/specs/2026-08-16-m3-ai-foundation-design.md`（§4.2 感知层 + §三 事件板）。
> 修改文件：新生产 `Levels/M2_TDM/bot_perception.gd`、`Levels/M2_TDM/event_board.gd`、
> `Levels/M2_TDM/bot_blackboard.gd`、`Levels/M2_TDM/footstep_emitter.gd`（均 +.uid）、
> `Weapons/Weapon_Resource.gd`（仅新增 @export 字段）、`Weapons/weapon_ak47.tres` /
> `weapon_glock18.tres` / `weapon_knife.tres` / `weapon_m67.tres`（仅新增字段行）、
> `Levels/M2_TDM/L_M2.gd`（仅事件板装配 + 死亡钩子写板 + 脚步发射器装配）、
> 新测试 ×5（T6-T10 各一）。
> 前置：M3.1 移动层（T0-T5，GUT 基线 405+2 冒烟后）。
> 感知与决策分离铁律（企划书 + 设计 §三）：感知层只上报事件/状态，**禁止内嵌状态机**。

## 全局约束（逐字复制进每个任务 brief）

- 允许改动文件仅限上文清单。**禁止改动** MovementController.gd / Enemy.gd / 布局 / navmesh /
  jump_solver.gd / jump_edges.gd / jump_edges_dataset.json / bot_locomotion.gd（只读调用）。
- TDD：每个任务先写失败测试跑 RED（确认失败原因正确），再实现跑 GREEN。禁止先写生产代码。
- 每任务完成后跑全量 GUT：`godot --headless --path . -s addons/gut/gut_cmdln.gd`（基线 =
  M3.1 收官值，任务新增测试后应全绿；既有断言不得改）。
- 任务**串行派发**（L_M2.gd 被 T7/T9 装配共享）。
- 注释口径：新代码块注释注明「(2026-08-17 M3.2 Tn)」+ 一句机制说明，中文。
- 浮点断言容差 1e-4；物理帧驱动断言用行为断言，不断言精确帧数。
- **tick 频率铁律（T3 审查教训）**：凡集成测试驱动循环必须每物理帧 tick（wait_physics_frames(1)，
  生产 60Hz 口径）。
- 集成测试装配 L_M2 后必须**立即 queue_free JumpRecorder**（防人类语料污染）。
- M3.2 期间 bot 无 Brain 站桩——感知层独立运行不影响既有对局行为；L_M2 装配新节点后
  冒烟（--quit-after 300）必须零报错。

## 任务表

| 任务 | 内容 | 新增测试数（约） |
|------|------|------------------|
| T6 | BotPerception 视线（视锥 120°/视距 40m/节流 0.2s/分段采样防穿缝）+ 敌对阵营过滤 | 6 |
| T7 | 听觉事件（枪声噪音半径入 weapon_*.tres + FootstepEmitter 脚步事件 + TTL 衰减） | 6 |
| T8 | LKP 威胁记忆（最后已知位置 + 不可见计时） | 4 |
| T9 | EventBoard 事件板（死亡事件 TTL 30s）+ L_M2 死亡钩子写板 | 5 |
| T10 | 黑板（感知输出存储：目标列表/事件队列/自身状态，信号通知） | 3 |

---

## T6：BotPerception 视线（新文件 Levels/M2_TDM/bot_perception.gd）

### 接口块（精确签名，实现者照抄）

```gdscript
class_name BotPerception
extends Node

signal hostile_visible(target: Node, pos: Vector3)   # 视线内敌对出现（节流周期上报）
signal hostile_lost(target: Node)                    # 目标离开视线（不可见计时起）

const CONE_HALF_ANGLE := deg_to_rad(60.0)  # 半视锥角（全锥 120°）
const VIEW_RANGE := 40.0                   # 视距（m）
const THROTTLE := 0.2                      # s：感知节流间隔
const SEGMENT_SAMPLES := 2                 # 分段采样中间点数（防穿缝）
const EYE_OFFSET := Vector3(0, 1.65, 0)    # 眼睛高度（bot 头 hitbox 1.70 下方）
const CHEST_OFFSET := Vector3(0, 1.2, 0)   # 目标胸部参考点

var body: CharacterBody3D        # 宿主 Enemy
var faction: String              # "enemy" | "friendly"（同 Enemy.get_faction 口径）
var player_target: Node3D        # 玩家节点（torso 组外的显式目标）

func setup(b: CharacterBody3D, f: String, player: Node3D) -> void
func tick(delta: float) -> void  # 每物理帧调用（Enemy._physics_process 或 Brain；内部节流）

# static 纯函数（可单测）
static func in_cone(body_pos: Vector3, body_yaw: float, target_pos: Vector3,
        half_angle: float) -> bool
static func within_range(a: Vector3, b: Vector3, max_range: float) -> bool
static func los_blocked(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3,
        mask: int) -> bool   # 主射线 + SEGMENT_SAMPLES 中间点射线，任一命中即遮挡
static func is_hostile(target: Node, own_faction: String) -> bool
```

### 语义规格

1. `tick`：`_throttle_t` 累计，< THROTTLE 直接 return。节流周期内：
   - 目标枚举：`get_tree().get_nodes_in_group("torso")`（Enemy 类，≤9 个零成本）+
     `player_target`；过滤 `is_hostile`（target.get_faction() ≠ own_faction；玩家
     PlayerLife.get_faction()="friendly"）与 dead 目标（Enemy.dead）
   - 对每个目标：`within_range(body+EYE, target+CHEST, VIEW_RANGE)` → `in_cone`
     （yaw 平面角，忽略俯仰——平面 120° 锥）→ `los_blocked`（物理空间主射线 +
     2 中间点射线，mask=1|4=5 同命中口径；排除自身 RID）
   - 可见 → `hostile_visible.emit(target, target.global_position)`；从可见变不可见 →
     `hostile_lost.emit(target)`（T8 LKP 消费）
2. `in_cone`：目标方向水平投影与 body 前向（−sin yaw, −cos yaw——T3 修正口径）夹角 ≤
   half_angle。
3. `los_blocked`：主射线 from→to 加 1/3、2/3 处中间点各一条射线（防细缝透视线假阳性）；
   任一命中 → 遮挡 true。掩码 5（Objects|Bots，与武器命中同口径）。
4. 感知结果不决策：仅发信号 + 更新内部 `_visible` 集合（T8/T10 读取）。

### 测试规格（test/unit/test_bot_perception_los.gd，TDD）

1. `test_in_cone_forward`：yaw=0、目标正前 -Z → true；侧方 +X → false（120° 边界：60°
   内 true / 61° false）
2. `test_in_cone_yaw_general`：yaw=π/2、目标 -X → true（前向 = -X，T3 修正口径交叉验证）
3. `test_within_range_boundary`：40m 内 true / 40.1m false
4. `test_los_blocked_wall`：静物墙（StaticBody3D 盒）遮挡 → true；无墙 → false
5. `test_los_segment_sampling`：墙中间开细缝（宽 < 0.1m）——主射线穿过但中间点射线
   命中墙 → true（防穿缝假阳性）
6. `test_hostile_filter`：敌 bot/友 bot/玩家三组合按 faction 正确过滤
7. `test_visible_signal`（集成）：装配 L_M2（JumpRecorder 即释/等迭代+60 帧）→ 敌 bot
   （Enemy.new，is_enemy=true）置地面 + 视线内目标（友 bot 或玩家）→ 60Hz 推进断言
   hostile_visible 发射且 target 正确；目标移到墙后 → hostile_lost 发射

---

## T7：听觉事件（weapon_*.tres 噪音半径 + FootstepEmitter + TTL 衰减）

### 接口块（精确签名）

```gdscript
# Weapons/Weapon_Resource.gd 新增（仅字段，不动既有逻辑）：
@export var noise_radius: float = 0.0   # 开火噪音半径（m）；0=静默（刀）

# 各 .tres 新增行（数值唯一来源铁律）：
# weapon_ak47.tres:   noise_radius = 45.0
# weapon_glock18.tres: noise_radius = 30.0
# weapon_knife.tres:  noise_radius = 2.0
# weapon_m67.tres:    noise_radius = 50.0   # 爆炸噪音（扔出 0/炸响 50 由 Grenade.exploded 另行处理）

# Levels/M2_TDM/footstep_emitter.gd（新文件）
class_name FootstepEmitter
extends Node

signal footstep(pos: Vector3, noise_radius: float)   # 脚步事件（敌对 bot 感知消费）

const STRIDE := 2.5          # m：每走 2.5m 发一次事件
const RUN_RADIUS := 20.0     # m：跑动噪音半径（M3.6 参数化 .tres 迁移注记）
const CROUCH_RADIUS := 5.0   # m：蹲行噪音半径
const CROUCH_SPEED_MAX := 3.0  # m/s：≤ 此值视为蹲行（crouch_speed 2.59 上方）

var body: CharacterBody3D

func setup(b: CharacterBody3D) -> void
func tick(delta: float) -> void   # 每物理帧（MovementController 宿主下）

# bot_perception.gd 扩展：
const GUNSHOT_TTL := 3.0     # s：枪声事件衰减
const FOOTSTEP_TTL := 1.5    # s：脚步事件衰减
var _heard_events: Array = []   # [{pos, radius, t, kind}]
signal heard_event(kind: String, pos: Vector3)   # 敌对噪音被听到（距离 ≤ radius）
static func heard_at(ear: Vector3, event_pos: Vector3, radius: float) -> bool  # 纯距离判定
```

### 语义规格

1. **FootstepEmitter**：宿主 body 的 on_floor 且水平速度 > 0.5 时按 STRIDE 累计距离，
   每满 2.5m 发 `footstep(pos, radius)`（速度 ≤ CROUCH_SPEED_MAX → CROUCH_RADIUS，
   否则 RUN_RADIUS）。空中/静止不累计。
2. **枪声事件源**：L_M2 中 WeaponManager 各 core 的 `shot_fired` 信号（既有）→ 广播
   `noise_event(pos, res.noise_radius)`（玩家枪声；bot 枪声 M3.4 接入同源）。
   L_M2 装配一个 NoiseBus（简单 Node 信号中继）或直接由 BotPerception 连接——
   实现者自选最简方案（建议：L_M2 持有一个 noise 信号总线，perception 装配时订阅）。
3. **Grenade.exploded**（既有信号，center 参数）→ 爆炸噪音半径 50。
4. **BotPerception.tick 听觉节**：每个 `_heard_events` 条目按 TTL 衰减剔除（枪声 3s /
   脚步 1.5s）；敌对噪音事件入队时若 `heard_at(ear, pos, radius)` 为 true →
   `heard_event.emit(kind, pos)`（决策层 M3.3 消费；M3.2 仅存队列 + 发信号）。
   阵营过滤：只接收敌对噪音（噪音源带 faction——M3.2 仅玩家源，玩家 = "friendly"，
   敌 bot 听；友 bot 不听玩家枪声）。友 bot 的 perception 无敌对噪音源（M3.2 敌 bot
   不开枪）→ 静默正常。
5. 事件时间戳用物理时间累计（`_elapsed` 单调递增，不用 Time.get_ticks——测试可控）。

### 测试规格（test/unit/test_bot_hearing.gd，TDD）

1. `test_noise_radius_resources`：四把武器 noise_radius 值 = 45/30/2/50（.tres 读取断言）
2. `test_footstep_stride_emits`：FootstepEmitter + 命令驱动 bot 直走 6m → 事件 ≥2 次
   且半径 = RUN_RADIUS
3. `test_footstep_crouch_radius`：慢速（2.0m/s 内）→ 事件半径 = CROUCH_RADIUS
4. `test_heard_at_boundary`：radius 20 内 true / 20.1 外 false
5. `test_ttl_decay`：注入枪声事件 → 推 3.1s 后队列空、footstep 1.6s 后空（纯逻辑注入
   可测性——`_heard_events` 允许测试直接写入或提供 `_push_event` 内部接口）
6. `test_gunshot_event_flow`（集成）：装配 L_M2 → 敌 bot perception 装配 → 玩家在
   30m 内开火（或直接触发 WeaponManager shot_fired 同款信号）→ 断言 heard_event
   ("gunshot") 发射；玩家在 50m 外 → 不发（AK 45 半径边界）

---

## T8：LKP 威胁记忆（bot_perception.gd 扩展）

### 接口块（精确签名）

```gdscript
# bot_perception.gd 扩展：
const LKP_TTL := 8.0      # s：LKP 记忆时长（不可见后遗忘）
signal lkp_updated(target: Node, pos: Vector3, visible: bool)

var _lkp: Dictionary = {}     # target -> {pos: Vector3, invisible_t: float}

func last_known_pos(target: Node) -> Vector3   # 查询（M3.3 决策层消费）
func invisible_time(target: Node) -> float     # 不可见累计（s）
```

### 语义规格

1. 目标可见（hostile_visible 发射时）：`_lkp[target] = {pos, invisible_t: 0}`。
2. 目标不可见（hostile_lost 发射时起）：invisible_t 每 tick 累计；超 LKP_TTL →
   条目删除（遗忘）+ `lkp_updated(target, Vector3.ZERO, false)` 通知。
3. 目标死亡/消失（is_instance_valid false 或 dead）→ 条目即时删除。
4. 位置仅存最后可见位置（**无位置预测外推**——M3.2 范围；外推 M4）。
5. 只读查询接口供 M3.3 决策层（CHASE/ALERT 状态消费）。

### 测试规格（test/unit/test_bot_lkp.gd，TDD）

1. `test_lkp_set_on_visible`：视线内目标 → last_known_pos == 目标实际位置
2. `test_lkp_retained_on_loss`：目标移出视线 → LKP 保持最后位置、invisible_time 增长
3. `test_lkp_expiry`：不可见 8.1s → 条目删除（last_known_pos 返回 ZERO 或 has 查询 false）
4. `test_lkp_clear_on_death`：目标死亡（take_damage 999）→ 条目即时删除

---

## T9：EventBoard 事件板（新文件 Levels/M2_TDM/event_board.gd）

### 接口块（精确签名）

```gdscript
class_name EventBoard
extends Node

signal death_event(faction: String, pos: Vector3, t: float)

const DEATH_TTL := 30.0     # s：死亡事件保留

var _deaths: Array = []     # [{faction, pos, t}]

func record_death(faction: String, pos: Vector3) -> void
func recent_deaths(faction: String, within: float) -> Array   # 时间窗查询（策略层 M3.3 消费）
func tick(delta: float) -> void    # TTL 剔除（每物理帧）

# L_M2.gd 装配 + 死亡钩子（最小侵入）：
#   _ready 中：_board = EventBoard.new(); add_child; 
#   _on_enemy_died(e) 中：_board.record_death("enemy", e.global_position)（现有函数内追加一行）
#   _on_player_died() 中：_board.record_death("friendly", _player.global_position)（追加一行）
#   每物理帧 _board.tick(delta)（挂 _process 或由装配方驱动）
```

### 语义规格

1. `record_death`：追加 {faction, pos, t=当前物理时间}（时间用 `_elapsed` 单调累计，
   测试可控）。
2. `recent_deaths(faction, within)`：返回 faction 的最近 within 秒内事件列表
   （策略层 Hunter/Hold 触发条件消费：15s 内 ≥2 且质心间距 ≤10m 等）。
3. `tick`：超 DEATH_TTL 剔除。
4. **不含击杀者位置**（拍板铁律：死亡源头由 bot 自己感知推导）。
5. 事件板为阵营共享（全局一板，faction 字段区分——两阵营 bot 都读）。

### 测试规格（test/unit/test_event_board.gd，TDD）

1. `test_record_and_query`：record_death ×3（不同 faction/时间）→ recent_deaths 窗口
   过滤正确（faction + within）
2. `test_ttl_expiry`：推 30.1s → 旧事件剔除
3. `test_time_window_semantics`：within=15 → 15s 前事件不含、14s 前含
4. `test_l2_hook_integration`（集成）：装配 L_M2 → 击杀一名敌 bot（take_damage 999）→
   断言 board.recent_deaths("enemy", 30) 含该位置
5. `test_player_death_hook`（集成）：玩家 K 自杀（life.take_damage 999 或直接调
   _on_player_died 路径）→ board 含 "friendly" 事件

---

## T10：黑板（新文件 Levels/M2_TDM/bot_blackboard.gd）

### 接口块（精确签名）

```gdscript
class_name BotBlackboard
extends Node

signal key_changed(key: String)

func set_value(key: String, value: Variant) -> void
func get_value(key: String, default: Variant = null) -> Variant
func has(key: String) -> bool
func clear() -> void
```

### 语义规格

1. 极简键值存储（Dictionary 底层），写时 `key_changed` 信号（M3.3 决策层订阅）。
2. M3.2 装配口径：L_M2 中每 bot 持一个 BotBlackboard（M3.3 Brain 的输入存储）；
   M3.2 仅由感知层写入标准键：`hostiles`（可见敌对列表）、`heard`（近期听觉事件）、
   `lkp`（各目标最后位置）、`deaths`（事件板窗口查询结果——由 Brain 主动查，黑板
   不主动存）。
3. 不实现黑板内逻辑（无状态机、无推理）——纯存储 + 通知。

### 测试规格（test/unit/test_bot_blackboard.gd，TDD）

1. `test_set_get_roundtrip`：任意 Variant 写读一致（Dictionary 嵌套含）
2. `test_key_changed_signal`：写入发信号且 key 正确；同值重写仍发（无去重）
3. `test_has_and_clear`：has 语义 + clear 后全空

---

## 验收（M3.2）

- GUT 全量绿（M3.1 收官基线 + 24 新增全过）
- L_M2 冒烟零报错；M2 行为零回归（bot 站桩、对局可玩）
- 集成证据：敌 bot 能看到视线内目标、听到 30m 内枪声、丢失目标后 LKP 保留 8s 遗忘、
  死亡事件进板可查询——为 M3.3 决策层提供全部输入
