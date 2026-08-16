# 计划：M3.3 决策层（BotBrain 七状态 + 策略选择器 4 策略 + 武器决策 + 前置修正）

> 日期：2026-08-17。分支 feat/m1-assets，单目录（勿建 worktree）。
> 设计：`docs/superpowers/specs/2026-08-16-m3-ai-foundation-design.md`（§4.3 策略 / §4.4 决策）。
> 前置：M3.1 移动层（407/407）+ M3.2 感知层（T10 后 432/432）。
> 修改文件：`Levels/M2_TDM/bot_locomotion.gd`（仅 T11 前置修正）、
> `Levels/M2_TDM/event_board.gd`（仅 T15 槽位扩展：strategy_slots）、
> 新生产 `Levels/M2_TDM/tactical_points.gd`、`Levels/M2_TDM/bot_strategy.gd`、
> `Levels/M2_TDM/bot_brain.gd`（均 +.uid）、`Levels/M2_TDM/L_M2.gd`（仅 M3.3 冒烟装配，T18）、
> 新测试 ×6（T11-T16 各一 + T17/T18 合并冒烟）。
> 参考已拍板全部参数：反应 0.3-0.6s / 追击上限 30m / 掩体 8-15m 难度≤中等 / 权重
> 1.0/0.7/0.35/0.15 / 策略四目录（触发/偏置/裁决/冷却全参数化）/ 武器决策四规则。

## 全局约束（逐字复制进每个任务 brief）

- 允许改动文件仅限上文清单。**禁止改动** MovementController.gd / Enemy.gd / 布局 / navmesh /
  jump_solver.gd / jump_edges.gd / 数据集 / bot_perception.gd / event_board.gd /
  bot_blackboard.gd（只读调用）/ Weapon 系列（T16 仅读资源与调 WeaponManager 接口）。
- TDD 全程；每任务后全量 GUT 全绿（基线 432 + 新增）；既有断言不得改（T11 授权改
  bot_locomotion.gd 的行为断言除外——按 T11 brief 逐条授权）。
- 串行派发；注释口径「(2026-08-17 M3.3 Tn)」；浮点容差 1e-4；60Hz tick 铁律；
  集成装配 L_M2 后 queue_free JumpRecorder。
- **M3.3 期间 bot 不开枪**（M3.4 战斗集成）——BotBrain 仅发射击意图信号
  （fire_intent 等，M3.4 接线），M3.3 冒烟不涉伤害。
- **决策层消费感知铁律**：Brain 只读黑板/感知信号/事件板查询，不反向写感知状态；
  感知不决策、决策不感知（企划书铁律 + 项目 CLAUDE.md 技术陷阱 6）。

## 任务表

| 任务 | 内容 | 新增测试数（约） |
|------|------|------------------|
| T11 | 前置修正：反向链接方向性 + 触发位置约束 + landing_zone 方向感知（bot_locomotion.gd） | 6 |
| T12 | 战术点库（tactical_points.gd：面表派生 + tier 权重 + 距离成本） | 5 |
| T13 | BotBrain HSM 骨架（七状态转移表 + 黑板/感知接线 + MovementCommand 输出 + 反应时间） | 7 |
| T14 | 目标选择与巡逻（IDLE/PATROL/ALERT/CHASE 30m 上限 + 掩体重选 8-15m） | 6 |
| T15 | 策略选择器（4 策略：触发纯函数/偏置参数包/优先级裁决/冷却/占用上限） | 8 |
| T16 | 武器决策（切刀赶路/弹尽切手枪/集群扔雷/近身刀人/弹药箱寻路） | 6 |
| T17+T18 | 装配 + 集成冒烟（5 敌 bot 全流程：出生→巡逻→感知→接敌意图→追击） | 3 |

---

## T11：前置修正——反向链接方向性 + 触发位置约束 + landing_zone 方向感知

### 接口块（精确签名）

```gdscript
# bot_locomotion.gd 修改（M3.1 收官清单三条）：
# 1) 反向链接方向性：_enter_jump 读取 edge 参数时按路径方向翻转——
#    段方向 = (seg.to - seg.from) 与链接注册正向 (link.to - link.from) 的
#    水平点积 < 0 则为反向穿越：
#       delta_h = -edge.delta_h（反向时取负）
#       human_p50：反向无正向校准数据 → 走无真实回退链（v_req×1.15）
#       （数据集 human 为正向校准，反向 p50 无效——T5 审查结论）
# 2) 触发位置约束：TRIGGER 增加起飞位置窗——起跳点必须落在链接 takeoff_zone
#    （数据集条目 takeoff_zone center/size，膨胀 0.5）水平投影内才允许触发；
#    无数据集条目 → 回退当前位置距 seg.from 水平距 ≤ JUMP_ARRIVE(0.8) 圆盘
# 3) landing_zone 方向感知：_landed_ok 落点判定用方向感知的 landing_zone——
#    反向穿越时 landing_zone 取链接 from 侧（正向 to 侧）；判定沿用
#    navmesh 双锚口径（T3 修复轮 2：to.y − closest(落点).y ≤ HEIGHT_GATE）
#    加水平 zone 包含（zone center/size 膨胀 0.5，无条目回退 LAND_TOLERANCE 1.5）
```

### 测试规格（test/unit/test_bot_jump_reverse.gd，TDD；既有跳跃测试不得回归）

1. `test_reverse_delta_h_negated`：反向穿越 TowerToRim_W（dh 0.5）→ _enter_jump 内
   消费的 delta_h == −0.5（纯函数化断言或注入探测——实现者自选最简可测方案，
   必要时把"方向翻转参数计算"抽 static 纯函数 `static func directed_edge_params(edge, forward: bool) -> Dictionary`）
2. `test_reverse_p50_fallback`：反向 → pick 消费走 v_req×1.15 档（断言 directed_edge_params
   返回 human_p50=NAN/augmented=false）
3. `test_trigger_position_window`：takeoff_zone 外位置不触发（速度/锥满足也不触发）；
   zone 内触发（集成或纯判定函数断言）
4. `test_landing_zone_direction_aware`：反向落地判定用 from 侧 zone——反向成功落
   from 侧 → _landed_ok true；落正向 to 侧 → false（纯判定函数断言）
5. `test_reverse_jump_integration`（集成）：T5 冒烟路径同款（西长墙 M 顶→塔顶反向跳）→
   仍到达（反向参数修正后不再靠 LAND_TOLERANCE 侥幸——vy>3 且 jf=0）
6. `test_forward_jump_regression`（集成）：T3 测试 7 路径（RampTopToCorridor_W 正向）→
   仍到达（正向参数不回归）

---

## T12：战术点库（新文件 Levels/M2_TDM/tactical_points.gd）

### 接口块（精确签名，照抄）

```gdscript
class_name TacticalPoints
extends RefCounted

const TIER_WEIGHT := {"simple": 1.0, "medium": 0.7, "hard": 0.35, "extreme": 0.15}
# 面级分析报告 tier 映射：简单→simple / 中等→medium / 困难→hard / 高难→extreme

var _points: Array = []   # [{face, center: Vector3, tier: String, weight: float}]

static func build_from_faces(faces: Array) -> TacticalPoints
# faces = JumpEdges.faces()；过滤「导航不可达」面（Tier 标注由 face_analysis 快照
# 传入或按名查报告表——M3.3 首版用内嵌 tier 快照表（160 面名→tier，从
# docs/reports/2026-08-16-face-analysis.md 分档清单提取，注释注明快照日期与来源），
# 「导航不可达」面排除（报告清单中的导航不可达条目）

func weighted_pick(pos: Vector3, rng_seed: int = 0) -> Dictionary
# 目标选择：候选 = 距 pos 8m 外的点；score = weight / (1.0 + dist * 0.1)
# （权重仅影响同等成本比较——设计 §三 决策 3/§4.4 口径；不硬禁除导航不可达）
# rng_seed > 0 时确定性（测试）；0 = 真随机

func nearest(pos: Vector3, tier_max: String = "extreme") -> Dictionary
# 掩体/战术点查询：返回距 pos 最近且 tier 不高于 tier_max 的点（tier 序
# simple < medium < hard < extreme）
```

### 测试规格（test/unit/test_tactical_points.gd，TDD）

1. `test_build_counts`：160 面 → 排除导航不可达后点数 = 160 − N（N 按快照表）
2. `test_tier_weights`：四档权重映射正确；导航不可达面不在候选
3. `test_weighted_pick_seed_deterministic`：同 seed 同 pos 两次 pick 相同
4. `test_weighted_pick_prefers_near_easy`：构造小点集（近简单点 vs 远简单点）→
   近点得分高（多次 seed 采样统计或直接断言 score 排序函数——实现者抽
   `static func score(weight, dist) -> float` 纯函数单测）
5. `test_nearest_tier_filter`：最近点 tier 超限 → 返回次近合规点

---

## T13：BotBrain HSM 骨架（新文件 Levels/M2_TDM/bot_brain.gd）

### 接口块（精确签名，照抄）

```gdscript
class_name BotBrain
extends Node

signal state_changed(from: String, to: String)
signal fire_intent(target: Node)      # 开火意图（M3.4 接线）
signal switch_intent(slot: int)       # 切枪意图（M3.4 接线；0=AK 1=Glock 2=刀 3=雷）
signal throw_intent(target_pos: Vector3)  # 扔雷意图（M3.4 接线）

enum State { IDLE, PATROL, ALERT, ENGAGE, CHASE, RELOAD, RETREAT }

const REACTION_MIN := 0.3   # s：看到→开枪延迟下限（随机区间）
const REACTION_MAX := 0.6
const CHASE_LIMIT := 30.0   # m：追击上限（自接敌位置）
const COVER_MIN := 8.0      # m：掩体距敌下限
const COVER_MAX := 15.0     # m：掩体距敌上限
const COVER_TIER_MAX := "medium"  # 掩体难度上限（难度≤中等）

var body: Enemy                    # 宿主（faction/位置）
var perception: BotPerception      # 只读（last_known_pos/invisible_time/信号）
var blackboard: BotBlackboard      # 输入存储（只读 + 标准键写）
var locomotion: BotLocomotion      # 移动输出（set_target）
var tactical: TacticalPoints        # 战术点库
var strategy: BotStrategy           # 策略选择器（T15 装配；T13 可为 null 默认 roam）

var state := State.IDLE
var current_target: Node = null     # 当前敌对目标（接敌后 = 玩家 LKP/实体）

func setup(b: Enemy, perc: BotPerception, bb: BotBlackboard, loco: BotLocomotion,
        tac: TacticalPoints) -> void
func tick(delta: float) -> void   # 每物理帧（Enemy._physics_process 链）
static func reaction_delay(rng_seed: int = 0) -> float   # [REACTION_MIN, REACTION_MAX]
```

### 语义规格

1. **状态转移表**（唯一权威，实现者照抄；进入状态即发 state_changed）：
   ```
   IDLE   --出生保护结束--> PATROL
   PATROL --听觉事件--> ALERT；--视线内敌对--> ENGAGE；--策略偏置巡逻点切换--> PATROL(目标换点)
   ALERT  --视线内敌对--> ENGAGE；--到 LKP 无发现且超 5s--> PATROL
   ENGAGE --失视--> CHASE；--低血量(<30)或弹尽--> RETREAT；--弹匣<30%--> RELOAD
   CHASE  --视线内--> ENGAGE；--超 30m 上限或 LKP 过期--> ALERT
   RELOAD --完成--> ENGAGE（接敌仍在）或 PATROL
   RETREAT --掩体到达或超 8s--> PATROL
   死亡（Enemy.died）→ Brain 停止（M3.5 复活新实例自然重置）
   ```
2. **感知接线**：`perception.hostile_visible` → 目标缓存 + 进入 ENGAGE 候选（目标 =
   玩家或敌对实体）；`hostile_lost` → 目标转 LKP 追迹（CHASE）；`heard_event` →
   ALERT 触发（PATROL/IDLE 时）+ LKP 更新为事件位置（ALERT 前往）。
3. **反应时间**：ENGAGE 进入时 `_reaction_t = reaction_delay()`；倒计时归零前不发
   fire_intent（M3.3 无伤害但意图信号时序照发——M3.4 接线射击）。
4. **MovementCommand 输出**：Brain 每帧经 locomotion 驱动（PATROL/CHASE/ALERT 调
   set_target 战术点/LKP；ENGAGE 移动中朝向目标 + 意图信号）。
5. **黑板标准键**（写入）：`state`/`target`/`target_lkp`；读出感知已写键
   （`hostiles`/`heard`/`lkp` 由装配方在 M3.3 冒烟/T18 接线）。
6. T13 仅骨架 + 状态机；目标选择/掩体（T14）、策略（T15）、武器（T16）留空接口
   （虚调或策略空实现），不允许占位假行为——未实现部分以默认行为（巡逻最近点/
   无切枪）运行且注释注明「Tn 实现」。

### 测试规格（test/unit/test_bot_brain_hsm.gd，TDD）

1. `test_initial_state_idle`：setup 后 state == IDLE
2. `test_idle_to_patrol`：出生保护计时结束（注入 elapsed）→ PATROL + state_changed
3. `test_patrol_to_engage_on_visible`：注入 hostile_visible → ENGAGE
4. `test_engage_to_chase_on_lost`：ENGAGE 中 hostile_lost → CHASE
5. `test_chase_limit_returns_alert`：CHASE 超 30m 上限（注入距离）→ ALERT
6. `test_engage_to_reload_low_mag`：注入弹匣 <30% → RELOAD（M3.3 无真实弹匣——
   黑板键 `mag` 注入）
7. `test_reaction_delay_range`：多次 seed 采样 ∈ [0.3, 0.6]；同 seed 相同
8. `test_retreat_on_low_hp`：黑板键 `hp` 注入 <30 → RETREAT

---

## T14：目标选择与巡逻（bot_brain.gd 扩展）

### 语义规格

1. **PATROL**：无目标时按策略偏置选战术点（默认 roam：全图 weighted_pick；
   Hold 策略：半场过滤——T15 接口）→ locomotion.set_target；到达 → 驻点 2-4s
   （随机）→ 换点。
2. **ALERT**：听觉事件位置 → set_target(LKP) 前往警戒；到达无发现超 5s → PATROL。
3. **CHASE**：目标 = 最后可见敌对（实体或 LKP）；追至 30m 上限（自接敌位置累计
   路径距离）或 LKP 过期（8s）→ ALERT。
4. **ENGAGE 掩体重选**：每 3-6s（随机）重选——候选 = tactical.nearest(自身, 
   COVER_TIER_MAX) 中距敌 ∈ [COVER_MIN, COVER_MAX] 且有 LOS 断点（视线阻断判定
   复用 perception.los_blocked 静态函数——掩体点与敌之间被挡）→ set_target 走位；
   无候选保持原位。
5. **目标选择**（接敌时）：视线内敌对直接为目标；多目标取最近；目标死亡 → 清空
   + 回 PATROL（LKP 过期同理）。

### 测试规格（test/unit/test_bot_brain_targeting.gd，TDD）

1. `test_patrol_picks_tactical_point`：PATROL 后 locomotion 目标非空且 ∈ 战术点集
2. `test_alert_goes_to_lkp`：heard_event(pos) → set_target(pos)（或最近导航点）
3. `test_chase_tracks_target`：视线内目标移动 → CHASE 目标位置随动（LKP 刷新）
4. `test_chase_limit_alert`：路径距离超 30m → ALERT（注入累计）
5. `test_cover_reselection_range`：掩体重选候选距敌 ∈ [8,15] 且 tier ≤ medium 且有
   LOS 断点（构造小点集 + 假墙断言）
6. `test_target_death_returns_patrol`：目标 died → PATROL

---

## T15：策略选择器（新文件 Levels/M2_TDM/bot_strategy.gd）

### 接口块（精确签名，照抄）

```gdscript
class_name BotStrategy
extends Node

enum Strategy { ROAM, HUNTER, FLANKER, HOLD }   # 优先级：HUNTER > FLANKER > HOLD > ROAM

const DEATH_WINDOW := 15.0    # s：阵亡统计窗口（Hunter/Hold 触发）
const CLUSTER_RADIUS := 10.0  # m：阵亡簇判定（质心间最大距离）
const HUNTER_RADIUS := 25.0   # m：簇 C 半径内目标权重 ×3
const HUNTER_GUN_DRAW := 30.0 # m：进入 C 30m 切回主枪
const GRENADE_RANGE := 20.0   # m：雷程（突入前 LKP 在雷程内扔雷开路）
const HUNTER_LIFETIME := 45.0 # s
const HUNTER_QUIT_DIST := 20.0  # m：目标离开 C 区 >20s 判定（连续计时）
const HUNTER_MAX := 2         # 同阵营同时 Hunter 上限（先到先得）
const FLANKER_MIN_DIST := 15.0   # m：目标直线距下限
const FLANKER_PATH_RATIO := 1.5  # 路径长/直线长 阈值
const HOLD_TIMEOUT := 30.0    # s
const COOLDOWN := 20.0        # s：同策略结束后冷却（防振荡）
const LOS_PATH_WEIGHT := 2.0  # Flanker 路径 LOS 段加权系数（成本语义预留，M3.3 实为
                              # 路线选择偏置：对目标有 LOS 的途经点方向加转向惩罚）

signal strategy_changed(from: int, to: int)

var faction: String            # 阵营（己方阵亡统计口径）
var board: EventBoard          # 死亡事件源（recent_deaths 查询）
var blackboard: BotBlackboard  # 广播策略占用（Hunter 先到先得）

func setup(f: String, b: EventBoard, bb: BotBlackboard) -> void
func tick(delta: float) -> void
func current() -> int           # Strategy 枚举
func params() -> Dictionary     # 当前策略参数包（BotBrain 各决策点读取）

# static 纯函数（可单测，触发条件全量化）
static func death_cluster(deaths: Array, window: float, radius: float) -> Dictionary
# 输入 recent_deaths(own_faction, window)；输出 {clustered: bool, centroid: Vector3,
# max_pair_dist: float}——≥2 死亡且质心间最大距离 ≤ radius 即簇
static func hunt_target_bias(strategy_params: Dictionary, target_pos: Vector3,
        pos: Vector3) -> float   # Hunter：目标在 C 25m 内 → 3.0，否则 1.0
static func flanker_eligible(body_pos: Vector3, target_pos: Vector3,
        path_len: float) -> bool  # 直线 ≥15 且 path/直线 > 1.5
static func hold_eligible(alive_own: int, alive_enemy: int, deaths_15s: int,
        clustered: bool) -> bool  # 存活少 + 15s 内 ≥2 阵亡且非簇
```

### 语义规格

1. **触发**（tick 每物理帧评估；全部条件纯函数）：
   - Hunter：`death_cluster(recent_deaths(faction, 15), 15, 10).clustered` 且
     当前非 Hunter 且冷却过 → 申请占用（黑板键 `hunter_slots`：写前读，
     先到先得，已 ≥HUNTER_MAX 则降级 Flanker 评估）
   - Flanker：`flanker_eligible(body, 目标, 路径长)`（目标 = 黑板 target/LKP）
   - Hold：`hold_eligible(存活数对比, 15s 内阵亡 ≥2, 非簇)`——簇 → Hunter 优先
   - 默认 roam 恒真兜底
2. **裁决**：优先级 HUNTER > FLANKER > HOLD > ROAM；**直接威胁优先铁律**——黑板
   state==ENGAGE/CHASE 时策略不切换（只在 PATROL/ALERT 评估）；切换仅当新策略
   优先级高于当前（防横跳）；同策略结束后 COOLDOWN 20s 内不重复触发。
3. **生命周期**：Hunter 45s 或目标离开 C 区连续 20s 或目标死亡 → 回 roam + 释放
   占用；Flanker 一次接敌（进入目标 30m 或开火意图）结束；Hold 30s 或存活持平。
4. **参数包**（params() 返回，BotBrain 消费）：{type, hunt_centroid, hunt_radius,
   target_bias_fn 语义（数值/回调二选一——实现者选数值字段 + Brain 侧公式）、
   half_map_filter（Hold：z 侧过滤谓词数据）、patrol_bias、grenade_open（Hunter
   突入前扔雷开路 true）}——Brain 各决策点读包做偏置，策略不直接驱动行为。
5. **策略占用广播**：黑板键 `hunter_slots`（int）由获得占用的 bot 写 +1、释放 −1
   （T18 装配时同一阵营 bot 共享黑板？——否：每 bot 独立黑板！占用改为**事件板
   扩展键**：EventBoard 增 `strategy_slots: Dictionary`（strategy_name → count）
   与方法 `acquire_slot(name, cap) -> bool` / `release_slot(name)`——阵营共享板
   （T9 产出），实现者按此扩展 event_board.gd（授权范围，T15 内）。

### 测试规格（test/unit/test_bot_strategy.gd，TDD）

1. `test_death_cluster_positive`：3 死亡质心间距 ≤10 → clustered + centroid 正确
2. `test_death_cluster_negative`：间距 >10 或 <2 死亡 → 非簇
3. `test_hunt_bias_in_radius`：目标在 C 25m 内 → 3.0；外 → 1.0
4. `test_flanker_eligible_boundary`：直线 15 且 path/直线 1.5 边界两侧
5. `test_hold_eligible_conditions`：存活少 + ≥2 阵亡非簇 → true；簇 → false
6. `test_priority_arbitration`：当前 HUNTER 遇 FLANKER 候选 → 不切换；当前 ROAM 遇
   HOLD 候选 → 切换
7. `test_cooldown_blocks_retrigger`：策略结束后 20s 内同策略不触发
8. `test_slot_cap_two`：3 个 bot 同时申请 Hunter → 仅 2 成功（事件板槽位计数）
9. `test_hunter_lifetime`：45s 超时回 roam + 槽位释放

---

## T16：武器决策（bot_brain.gd 扩展）

### 接口块（精确签名）

```gdscript
# bot_brain.gd 扩展：
const KNIFE_RUN_DIST := 8.0      # m：切刀赶路阈值（目标导航剩余路程）
const KNIFE_SAFE_DIST := 15.0    # m：切刀安全距离（最近已知敌对 > 此值才切刀）
const PISTOL_MAG_THRESHOLD := 0.2  # 弹匣 ≤20% 触发切手枪评估
const COVER_DIST_MAX := 5.0      # m：无掩体判定（最近掩体 > 此值 → 切手枪续战）
const MELEE_RANGE := 2.0         # m：近身刀人
const GRENADE_CLUSTER_DIST := 10.0  # m：≥2 敌间距 < 此值 = 集群
signal switch_intent(slot: int)      # 0=AK 1=Glock 2=刀 3=雷（T13 声明，本任务起发）
signal throw_intent(target_pos: Vector3)
signal melee_intent(target: Node)    # 新增（近身刀人意图，M3.4 接线近战）

# 黑板标准键（Brain 写）：weapon_slot / mag_frac / reserve / grenade_left /
# ammo_box_target（寻路弹药箱时的目标点）
```

### 语义规格（全部拍板规则的精确实现）

1. **赶路切刀**：PATROL/CHASE/ALERT 移动状态且目标导航剩余路程 > KNIFE_RUN_DIST 且
   最近已知敌对 > KNIFE_SAFE_DIST → `switch_intent(2)`；进入敌对 15m 内 →
   `switch_intent(0)`（AK 主枪）。ENGAGE 状态不切刀。
2. **弹尽切手枪**：ENGAGE 中弹匣 ≤ PISTOL_MAG_THRESHOLD 且（无掩体或最近掩体 >
   COVER_DIST_MAX）→ `switch_intent(1)`；有掩体 → 退掩体（RELOAD 状态路径）；
   Glock 亦空（黑板 mag_frac 双槽）→ 强制 RELOAD。
3. **集群扔雷**：ENGAGE/ALERT 中 ≥2 敌对已知位置（视线/LKP）间距 <
   GRENADE_CLUSTER_DIST → `throw_intent(质心)`（质心在 GRENADE_RANGE 内才扔）；
   Hunter 策略突入前（params().grenade_open）→ 朝 C 区 LKP 扔雷开路（同雷程门控）。
   扔雷后切回主枪（M3.4 接线；M3.3 发意图 + 黑板记录 grenade_left 减一语义）。
4. **近身刀人**：敌对 < MELEE_RANGE → `melee_intent(target)`（连击语义 M3.4 接线；
   M3.3 发意图）。
5. **弹药箱寻路**：黑板 reserve==0 或 grenade_left==0 → 最近弹药箱点
   （LAYOUT.ammo_box_points() 位置表）→ set_target + ammo_box_target 黑板键；
   到达后 M3.4 拾取接线（M3.3 仅寻路 + 到达清空键）。
6. 全部决策在 tick 内按状态门控执行；意图信号幂等（状态不变不重发——发前比较
   黑板键目标意图）。

### 测试规格（test/unit/test_bot_weapon_logic.gd，TDD）

1. `test_knife_rush_on_long_patrol`：PATROL 目标路程 >8m 且无近敌 → switch_intent(2)
2. `test_knife_back_to_rifle_near_enemy`：敌对进入 15m → switch_intent(0)
3. `test_pistol_on_low_mag_no_cover`：ENGAGE + mag_frac ≤0.2 + 掩体 >5m →
   switch_intent(1)
4. `test_cluster_grenade`：两敌对间距 <10m 且在雷程内 → throw_intent(质心)
5. `test_melee_close_range`：敌对 <2m → melee_intent
6. `test_ammo_box_routing`：reserve 0 → set_target(最近弹药箱) + ammo_box_target 键

---

## T17+T18：装配 + 集成冒烟（L_M2 最小侵入 + 新测试）

### 语义规格

1. **L_M2 装配**（最小侵入）：`_setup_tdm` 后对 5 敌 bot 各挂 Brain 装配链
   （Enemy → BotPerception setup（faction="enemy", player_target=_player）+
   FootstepEmitter（玩家侧挂 + 敌 bot 侧挂）→ BotBlackboard → BotLocomotion setup
   （body, map_rid）→ TacticalPoints（shared 单实例）→ BotStrategy setup（board）→
   BotBrain setup；tick 链：Enemy._physics_process 已调 super——**Brain tick 挂
   Enemy 的 _physics_process 链**：实现方式 = L_M2 中 `_physics_process` 遍历 5 敌
   调 brain.tick（或 Brain 自己挂 body 的 physics_frame 信号——实现者自选最简且
   与 60Hz 铁律一致）。噪音总线接线：玩家 shot_fired → noise_bus（T7 契约）。
   出生保护结束 → Brain IDLE→PATROL 自然开始（Enemy.spawn_protection 计时共享）。
2. **冒烟测试**（test/unit/test_bot_brain_smoke.gd，TDD）：
   - `test_five_bots_patrol_after_spawn`：装配 L_M2 → 5 敌 bot 出生保护后进入
     PATROL（state_changed 记录）且各自 set_target 非空
   - `test_bot_alerts_on_gunshot`：玩家开火（噪音总线注入）→ 30m 内敌 bot 进入
     ALERT 并朝 LKP 移动
   - `test_bot_engages_on_sight`：玩家走到敌 bot 视线内 → 敌 bot ENGAGE +
     fire_intent 发射（反应时间后）
3. **验收**：5 敌 bot 全流程「出生→巡逻→感知→接敌意图→追击」无卡死无报错；
   既有对局行为零回归（bot 不开枪不伤玩家——M3.4 前 TDM 可玩性不变）。

---

## 验收（M3.3）

- GUT 全量绿（432 + 约 41 新增）；L_M2 冒烟零报错
- 集成证据：5 敌 bot 自主巡逻、听觉警戒、视线接敌、意图信号、策略触发
  （Hunter/Flanker/Hold 各自可注入触发）
- M3.4 就绪：fire_intent/switch_intent/throw_intent/melee_intent 四意图 +
  黑板全键 + 策略参数包齐备
