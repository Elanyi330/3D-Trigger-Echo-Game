# Levels/M2_TDM/bot_brain.gd
# M3.3 T13（2026-08-17）：BotBrain 分层状态机（HSM）骨架——M3 AI 决策层心脏。
# 七状态（IDLE/PATROL/ALERT/ENGAGE/CHASE/RELOAD/RETREAT）+ 感知接线 + 四意图信号
# （fire/switch/throw/melee——M3.4 战斗集成接线）。状态转移表以任务简报为唯一权威
# （进入状态即发 state_changed）。
# M3.3 T14（2026-08-17）：目标选择与巡逻——PATROL weighted_pick 选点 + 2-4s 随机
# 驻点换点、ALERT 前往听觉事件位置（5s 无发现回巡逻、新事件刷新位置与计时）、
# CHASE LKP 跟踪刷新（>0.5m 重 set_target）+ 累计路径 30m 上限、ENGAGE 掩体重选
# （3-6s 周期；候选 ∈[8,15]m + tier ≤ medium + 对敌 LOS 断点 → 取最近）、目标管理
# （接敌取最近可见、死亡/失效清目标回 PATROL）。
# 决策层消费感知铁律：只读黑板/感知信号/查询，不反向写感知状态；感知不决策、
# 决策不感知（企划书铁律 + 项目 CLAUDE.md 技术陷阱 6）。
# 未实现部分以默认行为运行（注释注明「Tn 实现」，不允许占位假行为）：
#   无切枪/无扔雷（T16）；strategy 恒 null（T15 装配）。
# tick 由 Enemy._physics_process 链驱动（60Hz tick 铁律）；Brain 为感知/移动的装配
# 驱动方（perception.tick / locomotion.tick 由本节点统一驱动——T18 装配一次接线）。
# M3.3 bot 不开枪：fire_intent 等仅发信号（M3.4 接线射击），T13 测试断言信号与时序
# 不涉伤害。
class_name BotBrain
extends Node

signal state_changed(from: String, to: String)
signal fire_intent(target: Node)            # M3.4 接线
signal switch_intent(slot: int)             # M3.4 接线（0=AK 1=Glock 2=刀 3=雷）
signal throw_intent(target_pos: Vector3)    # M3.4 接线（T16 起发）
signal melee_intent(target: Node)           # M3.4 接线（T16 起发）

enum State { IDLE, PATROL, ALERT, ENGAGE, CHASE, RELOAD, RETREAT }

const REACTION_MIN := 0.3   # s：看到→开枪延迟下限（随机区间）
const REACTION_MAX := 0.6   # s：上限
const CHASE_LIMIT := 30.0   # m：追击上限（自接敌位置累计路径；直线口径保留见 _chase_limit_exceeded）
const COVER_MIN := 8.0      # m：掩体距敌下限（T14 掩体重选消费）
const COVER_MAX := 15.0     # m：掩体距敌上限（T14 掩体重选消费）
const COVER_TIER_MAX := "medium"  # 掩体难度上限（难度≤中等；T13 RETREAT 选点 + T14 掩体重选消费）
# ── T14 常量（2026-08-17 M3.3 T14，接口块）──
const POST_HOLD_MIN := 2.0        # s：驻点时长下限（随机区间）
const POST_HOLD_MAX := 4.0        # s：驻点时长上限
const ALERT_NO_FIND := 5.0        # s：ALERT 到达 LKP 无发现超时 → PATROL
const COVER_RESELECT_MIN := 3.0   # s：ENGAGE 掩体重选周期下限（随机区间）
const COVER_RESELECT_MAX := 6.0   # s：ENGAGE 掩体重选周期上限
# ── 实现常量（2026-08-17 M3.3 T13，语义规格值；未列入接口块）──
const FIRE_THROTTLE := 0.2  # s：fire_intent 节流周期（同感知节流 BotPerception.THROTTLE）
const RETREAT_TIMEOUT := 8.0  # s：RETREAT 超时 → PATROL

var body: Enemy                    # 宿主（faction/位置）
var perception: BotPerception      # 只读（LKP 查询/信号）
var blackboard: BotBlackboard      # 输入存储（只读 + 标准键写）
var locomotion: BotLocomotion      # 移动输出（set_target）
var tactical: TacticalPoints        # 战术点库
var strategy = null                 # BotStrategy（T15 装配；T13 恒 null 默认 roam 语义）
                                    # 注：BotStrategy 类 T15 才存在，T13 无法声明类型
                                    # （接口块偏差注记——T15 时改类型注解）

var state := State.IDLE
var current_target: Node = null     # 当前敌对目标（接敌后 = 玩家/敌对实体）

var _seen: Dictionary = {}          # target -> true：当前可见敌对集合（hostile_visible/
                                    #   hostile_lost 维护——失视无他敌判定与 RELOAD 出口）
var _reaction_t := 0.0              # ENGAGE 反应倒计时（归零前不发 fire_intent）
var _fire_t := 0.0                  # fire_intent 节流累计（归零后每 FIRE_THROTTLE 一发）
var _arrived := false               # locomotion.arrived 消费旗（状态行为消费；
                                    #   状态切换时清除防跨状态泄漏）
# ── T14 实例状态（2026-08-17 M3.3 T14，接口块）──
var _patrol_target: Dictionary = {}  # 当前巡逻点 {face, center, ...}
var _post_hold_t := 0.0              # PATROL 驻点倒计时（>0 = 驻点中）
var _alert_pos := Vector3.ZERO       # 听觉事件位置（ALERT 前往）
var _alert_t := 0.0                  # ALERT 无发现累计（到达 LKP 后起算）
var _chase_distance := 0.0           # 追击累计路径（自接敌位置 body 每帧位移和）
var _chase_origin := Vector3.ZERO    # 接敌位置（CHASE 上限基准）
var _cover_t := 0.0                  # ENGAGE 掩体重选倒计时（归零评估）
var _cover_target: Dictionary = {}   # 当前掩体点
# ── T14 实现内部状态（未列入接口块）──
var _alert_watching := false         # ALERT 到达 LKP 后开始无发现计时
var _last_chase_pos := Vector3.ZERO  # CHASE 位移累计锚（上一帧 body 位置）
var _last_lkp := Vector3.ZERO        # CHASE 最近一次 set_target 的 LKP（>0.5m 刷新比较基准）
var _retreat_t := 0.0               # RETREAT 计时（自进入累计）
var _dead := false                  # 死亡停止（Enemy.died；M3.5 复活新实例自然重置）


## 装配（tick 前调用）：绑定宿主/感知/黑板/移动/战术点 + 感知信号接线。
## 感知接线在 setup 时 connect（tick 前）——hostile_visible/hostile_lost/heard_event
## 即时喂状态机（信号驱动转移）。
func setup(b: Enemy, perc: BotPerception, bb: BotBlackboard, loco: BotLocomotion,
		tac: TacticalPoints) -> void:
	body = b
	perception = perc
	blackboard = bb
	locomotion = loco
	tactical = tac
	perception.hostile_visible.connect(_on_hostile_visible)
	perception.hostile_lost.connect(_on_hostile_lost)
	perception.heard_event.connect(_on_heard_event)
	locomotion.arrived.connect(_on_arrived)
	if body != null:
		body.died.connect(_on_died)


## 每物理帧调用（Enemy._physics_process 链；60Hz tick 铁律）。
## tick 顺序（简报）：感知先行 → 状态机转移判定 → 移动推进 → 状态行为
## （每状态一个分支）→ 黑板标准键写（state 字符串名/target/target_lkp）。
func tick(delta: float) -> void:
	if body == null or _dead or perception == null or blackboard == null \
			or locomotion == null or tactical == null:
		return
	perception.tick(delta)        # Brain 为感知装配驱动方（信号即时喂状态机）
	_evaluate_transitions(delta)  # 状态机转移判定
	locomotion.tick(delta)        # 移动推进（arrived 信号即入 _arrived 旗，状态行为同 tick 消费）
	_tick_state(delta)            # 状态行为（每状态一个分支）
	_write_blackboard()           # 黑板标准键写


## 反应延迟：rng_seed=0 → randf_range(REACTION_MIN, REACTION_MAX)（真随机）；
## seed>0 → 确定性——seed 构造独立 RandomNumberGenerator 取区间内定值
## （同 seed 恒同值，测试口径；规则 = 引擎确定性伪随机流）。
static func reaction_delay(rng_seed: int = 0) -> float:
	if rng_seed <= 0:
		return randf_range(REACTION_MIN, REACTION_MAX)
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	return rng.randf_range(REACTION_MIN, REACTION_MAX)


## 状态切换：进入状态即发 state_changed；按转移表逐条实现（简报唯一权威）。
## T14 增退出清理：离开 ENGAGE → 掩体状态清零；离开 CHASE → 追击 episode 清空
## （累计/基准/黑板 chase_origin）。
func _set_state(to: State) -> void:
	if _dead:
		return  # 死亡后不再转移（Brain 停止）
	var from := state
	if from == State.ENGAGE and to != State.ENGAGE:
		_clear_cover()  # ENGAGE 退出掩体状态清理（T14 规格 4）
	if from == State.CHASE and to != State.CHASE:
		_chase_distance = 0.0           # 追击 episode 结束：累计/基准/LKP 基准清空
		_chase_origin = Vector3.ZERO
		_last_lkp = Vector3.ZERO
		blackboard.set_value("chase_origin", Vector3.ZERO)  # 黑板 chase_origin 清空（T14 规格 3）
	state = to
	_arrived = false  # 状态切换清除到达旗（防跨状态泄漏）
	state_changed.emit(State.keys()[from], State.keys()[to])
	_enter_state(to)


## 状态机转移判定（tick 第 2 步）：黑板键注入驱动的转移 + 计时驱动转移
## （计时器归本步骤倒计时——计时即转移机制）。信号驱动转移
## （hostile_visible/hostile_lost/heard_event）在感知信号处理器中即时完成。
## 转移表（简报唯一权威，逐字照抄）：
##   IDLE   --出生保护结束（黑板键 spawn_protection_left ≤0）--> PATROL
##   PATROL --驻点 2-4s（随机）结束--> PATROL（换点，weighted_pick 重选）
##   ALERT  --到达 LKP 无发现累计超 5s--> PATROL（新事件刷新位置与计时）
##   ENGAGE --黑板 hp<30--> RETREAT；--黑板 mag_frac<0.3--> RELOAD
##   CHASE  --黑板 hp<30--> RETREAT（T13 审查移交 Minor 1）；--追击超限
##             （累计路径 >CHASE_LIMIT 或直线口径）或 LKP 过期--> ALERT
##   RELOAD --黑板 reload_done=true（T16 设）--> ENGAGE（目标仍可见）或 PATROL
##   RETREAT --超 8s--> PATROL（掩体到达在状态行为经 arrived 旗）
##   目标死亡/失效（任何状态）--> current_target 清空 --> PATROL（T14）
func _evaluate_transitions(delta: float) -> void:
	# (2026-08-17 M3.3 T14) 目标死亡检查先行（任何状态）：目标 died/已释放/dead
	# 标记 → current_target 清空 → PATROL（规格 5）。先于状态分支——同帧失视
	# （CHASE）或其余转移全部让路。
	if current_target != null and _target_dead(current_target):
		var dead_target := current_target
		current_target = null
		_seen.erase(dead_target)
		_set_state(State.PATROL)
		return
	match state:
		State.IDLE:
			# spawn_protection_left 黑板键与 body.spawn_protection 的映射归 T17/T18
			# 装配方（T13 审查移交 Minor 2 口径注记——本任务不碰）。
			if blackboard.get_value("spawn_protection_left", 0.0) <= 0.0:
				_set_state(State.PATROL)
		State.PATROL:
			if _post_hold_t > 0.0:
				_post_hold_t -= delta
				if _post_hold_t <= 0.0:
					_post_hold_t = -1.0
					_set_state(State.PATROL)  # 驻点结束换点（重进入重 pick，T14）
		State.ALERT:
			if _alert_watching:
				_alert_t += delta
				if _alert_t > ALERT_NO_FIND:
					_alert_watching = false
					_alert_t = 0.0
					_set_state(State.PATROL)  # 到达 LKP 无发现超 5s（T14 累计口径）
		State.ENGAGE:
			if blackboard.get_value("hp", 100.0) < 30.0:
				_set_state(State.RETREAT)
			elif blackboard.get_value("mag_frac", 1.0) < 0.3:
				_set_state(State.RELOAD)
		State.CHASE:
			# (2026-08-17 M3.3 T14；hp 判定 = T13 审查移交 Minor 1)：CHASE 中低血
			# 优先撤退——同帧失视+低血时失视先赢（hostile_lost 信号先于本判定完成
			# ENGAGE→CHASE），此处补 hp<30 → RETREAT，低血 bot 不追满 30m。
			if blackboard.get_value("hp", 100.0) < 30.0:
				_set_state(State.RETREAT)
			elif _chase_limit_exceeded() or _chase_lkp_expired():
				_set_state(State.ALERT)
		State.RELOAD:
			if blackboard.get_value("reload_done", false):
				if current_target != null and is_instance_valid(current_target) \
						and _seen.has(current_target):
					_set_state(State.ENGAGE)  # 目标仍可见 → 接敌
				else:
					_set_state(State.PATROL)
		State.RETREAT:
			_retreat_t += delta
			if _retreat_t > RETREAT_TIMEOUT:
				_set_state(State.PATROL)


## 状态行为（tick 第 4 步，每状态一个分支）。
func _tick_state(delta: float) -> void:
	match state:
		State.IDLE:
			pass  # 出生保护站定（无行为）
		State.PATROL:
			_tick_patrol()
		State.ALERT:
			_tick_alert()
		State.ENGAGE:
			_tick_engage(delta)
		State.CHASE:
			_tick_chase(delta)  # T14：LKP 跟踪刷新 + 追击累计（T13 为空占位）
		State.RELOAD:
			pass  # 等待 reload_done（T16 设键 + 真实换弹行为）
		State.RETREAT:
			_tick_retreat()


## 状态进入钩子（进入状态即执行；初始 IDLE 不经此）。
func _enter_state(to: State) -> void:
	match to:
		State.IDLE:
			pass  # 出生保护（初始态，转移表无进入 IDLE 的行）
		State.PATROL:
			_enter_patrol()
		State.ALERT:
			_enter_alert()
		State.ENGAGE:
			_enter_engage()
		State.CHASE:
			_enter_chase()
		State.RELOAD:
			_enter_reload()
		State.RETREAT:
			_enter_retreat()


## PATROL 进入（T14）：选点 = tactical.weighted_pick(body.global_position)
## （T12 加权选点；≥8m 候选过滤内建）→ locomotion.set_target(center)。
## T15 策略偏置接入点：Hold 策略半场过滤 / patrol_bias 在此偏置 weighted_pick 候选
## （T15 实现，现恒默认 roam 全图）。
## 驻点计时复位。
func _enter_patrol() -> void:
	_post_hold_t = 0.0
	_patrol_target = _pick_patrol_point()
	if not _patrol_target.is_empty():
		locomotion.set_target(_patrol_target["center"])


## 巡逻点选择（T14）：tactical.weighted_pick——候选恒 ≥8m（MIN_PICK_DIST 过滤内建；
## 到达时 body 站在点上，重 pick 即天然排除当前点，无需二次 pick）。
func _pick_patrol_point() -> Dictionary:
	return tactical.weighted_pick(body.global_position)


## PATROL 行为（T14）：到达巡逻点 → 驻点倒计时启动（随机 2-4s；驻点结束换点见转移判定）。
func _tick_patrol() -> void:
	if _arrived:
		_arrived = false
		_post_hold_t = randf_range(POST_HOLD_MIN, POST_HOLD_MAX)


## ALERT 进入（T14）：记 _alert_pos（黑板 alert_pos 读）→ set_target 前往警戒；
## 无发现计时复位（到达 LKP 后起算）。
func _enter_alert() -> void:
	_alert_pos = blackboard.get_value("alert_pos", body.global_position)
	_alert_t = 0.0
	_alert_watching = false
	locomotion.set_target(_alert_pos)


## ALERT 行为（T14）：到达 LKP → 无发现计时启动（累计超 ALERT_NO_FIND → PATROL
## 见转移判定；期间视线内敌对 → hostile_visible 信号转 ENGAGE）。
func _tick_alert() -> void:
	if _arrived:
		_arrived = false
		_alert_watching = true
		_alert_t = 0.0


## ENGAGE 进入（T14 扩展）：反应倒计时（0.3-0.6s 随机）+ 节流累计清零 + 站定射击
## 起步 + 掩体重选周期启动（3-6s 随机，归零评估——T14 掩体接管 ENGAGE 移动）。
func _enter_engage() -> void:
	_reaction_t = reaction_delay(0)
	_fire_t = 0.0
	locomotion.clear_target()
	_cover_t = randf_range(COVER_RESELECT_MIN, COVER_RESELECT_MAX)
	_cover_target = {}


## ENGAGE 行为（T14 扩展）：掩体重选倒计时（先于反应处理——每 ENGAGE tick 递减）
## → 反应倒计时归零前不发 fire_intent；归零帧立即首发，此后每 FIRE_THROTTLE
## （0.2s，同感知节流）持续发（持续目标持续发——M3.4 射击节流消费）。
func _tick_engage(delta: float) -> void:
	_cover_t -= delta
	if _cover_t <= 0.0:
		_cover_t = randf_range(COVER_RESELECT_MIN, COVER_RESELECT_MAX)
		_reselect_cover()
	if _reaction_t > 0.0:
		_reaction_t = maxf(_reaction_t - delta, 0.0)
		if _reaction_t > 0.0:
			return
		_emit_fire()  # 归零帧立即首发
		_fire_t = 0.0
		return
	_fire_t += delta
	if _fire_t >= FIRE_THROTTLE:
		_fire_t -= FIRE_THROTTLE
		_emit_fire()


## fire_intent 发射（目标有效性守卫——死亡/已释放目标不发，T14 目标管理细化）。
func _emit_fire() -> void:
	if current_target != null and is_instance_valid(current_target):
		fire_intent.emit(current_target)


## CHASE 进入（T14 扩展）：追击 episode 重置（累计/基准/LKP 刷新基准）+ 黑板记
## 接敌位置 chase_origin（追击上限基准）+ 追 LKP（进入时一次 set_target；
## 每 tick LKP 刷新 >0.5m 重 set_target 见 _tick_chase）。
func _enter_chase() -> void:
	_chase_distance = 0.0
	_chase_origin = body.global_position
	_last_chase_pos = body.global_position
	_last_lkp = Vector3.ZERO
	blackboard.set_value("chase_origin", body.global_position)
	var lkp := Vector3.ZERO
	if current_target != null and is_instance_valid(current_target):
		lkp = perception.last_known_pos(current_target)
	if lkp != Vector3.ZERO:
		locomotion.set_target(lkp)
		_last_lkp = lkp


## CHASE 行为（T14）：追击累计（body 每帧位移和，自接敌位置——累计路径口径）
## + LKP 跟踪刷新（每 tick 读 perception.last_known_pos——有效且与上次 set_target
## 的 LKP 水平差 >0.5m → 重 set_target）。LKP 过期/超限 → ALERT 见转移判定。
func _tick_chase(_delta: float) -> void:
	_chase_distance += body.global_position.distance_to(_last_chase_pos)
	_last_chase_pos = body.global_position
	if current_target == null or not is_instance_valid(current_target):
		return
	var lkp := perception.last_known_pos(current_target)
	if lkp != Vector3.ZERO:
		var d := Vector2(lkp.x - _last_lkp.x, lkp.z - _last_lkp.z).length()
		if d > 0.5:
			locomotion.set_target(lkp)
			_last_lkp = lkp


## RELOAD 进入：站定换弹（T16 真实换弹行为接管；reload_done 键由 T16 设）。
func _enter_reload() -> void:
	locomotion.clear_target()


## RETREAT 进入：计时清零 + 选最近掩体点（难度 ≤ COVER_TIER_MAX）前往
## （掩体到达 → PATROL 经 arrived 旗；选点细节 T14+ 掩体语义细化）。
func _enter_retreat() -> void:
	_retreat_t = 0.0
	var cover: Dictionary = tactical.nearest(body.global_position, COVER_TIER_MAX)
	if not cover.is_empty():
		locomotion.set_target(cover["center"])


## RETREAT 行为：掩体到达 → PATROL（超时出口见转移判定）。
func _tick_retreat() -> void:
	if _arrived:
		_arrived = false
		_set_state(State.PATROL)


## 追击超限判定（2026-08-17 M3.3 T14）：累计路径口径——_chase_distance（body 每帧
## 位移和，_tick_chase 累计）> CHASE_LIMIT。直线水平距口径保留为 OR 支：黑板注入
## chase_origin 的 T13 既有测试断言不得改（生产语义上直线 ≤ 累计路径，绕圈路径由
## 累计支裁决，直线支为注入验证口径与保守兜底）。
func _chase_limit_exceeded() -> bool:
	if _chase_distance > CHASE_LIMIT:
		return true
	var origin: Vector3 = blackboard.get_value("chase_origin", _chase_origin)
	var d := Vector2(body.global_position.x - origin.x, body.global_position.z - origin.z)
	return d.length() > CHASE_LIMIT


## LKP 过期判定：无 LKP 条目（invisible_time < 0——感知遗忘后返回 -1）或
## 目标已释放/无效。
func _chase_lkp_expired() -> bool:
	if current_target == null or not is_instance_valid(current_target):
		return true
	return perception.invisible_time(current_target) < 0.0


## 黑板标准键写（tick 第 5 步）：
## 写键 state（状态字符串名）/target/target_lkp/patrol_target/cover_target
## （T14 增后两键）；
## 读键 hp/mag_frac/spawn_protection_left/reload_done/alert_pos/chase_origin
## （T14-T16 共用协议）。
func _write_blackboard() -> void:
	blackboard.set_value("state", State.keys()[state])
	blackboard.set_value("target", current_target)
	var lkp := Vector3.ZERO
	if current_target != null and is_instance_valid(current_target):
		lkp = perception.last_known_pos(current_target)
	elif state == State.ALERT:
		lkp = _alert_pos  # T14：ALERT 前往目标 = 听觉事件位置（规格 2）
	blackboard.set_value("target_lkp", lkp)
	blackboard.set_value("patrol_target", _patrol_target)  # T14 规格 1
	blackboard.set_value("cover_target", _cover_target)    # T14 规格 4


# ── 感知信号处理器（setup 时接线；信号驱动转移即时完成）──

## hostile_visible（T14 扩展）：目标缓存 + 最近可见优先（多目标取 body 距离最近，
## 规格 5）+ IDLE/PATROL/ALERT/CHASE 状态转 ENGAGE（反应时间随 ENGAGE 进入重置）。
func _on_hostile_visible(target: Node, _pos: Vector3) -> void:
	_seen[target] = true
	current_target = _nearest_seen()
	if state == State.IDLE or state == State.PATROL or state == State.ALERT \
			or state == State.CHASE:
		_set_state(State.ENGAGE)


## hostile_lost（T14 扩展）：可见集合移除；ENGAGE 且目标 == current_target 且无其他
## 可见敌对 → CHASE（接敌位置记黑板 chase_origin，见 _enter_chase）；仍有其他可见
## 敌对 → 换最近目标继续 ENGAGE（规格 5 多目标管理）。
func _on_hostile_lost(target: Node) -> void:
	_seen.erase(target)
	if state == State.ENGAGE and target == current_target:
		if _seen.is_empty():
			_set_state(State.CHASE)
		else:
			current_target = _nearest_seen()


## heard_event（T14 扩展）：PATROL/IDLE 时 → ALERT + 黑板 alert_pos（ALERT 前往
## = locomotion.set_target(alert_pos)）；ALERT 中 → 刷新 _alert_pos + 重 set_target
## + _alert_t 清零（规格 2：新事件刷新警戒，无发现计时归零待重新到达）。
func _on_heard_event(_kind: String, pos: Vector3) -> void:
	if state == State.IDLE or state == State.PATROL:
		blackboard.set_value("alert_pos", pos)
		_set_state(State.ALERT)
	elif state == State.ALERT:
		_alert_pos = pos
		_alert_t = 0.0
		_alert_watching = false
		blackboard.set_value("alert_pos", pos)
		locomotion.set_target(pos)


## locomotion.arrived：到达旗（PATROL 驻点/ALERT 计时/RETREAT 回巡逻消费）。
func _on_arrived() -> void:
	_arrived = true


## 死亡 → Brain 停止（计划 T13 语义：M3.5 复活新实例自然重置）。
func _on_died() -> void:
	_dead = true
	locomotion.clear_target()


# ── T14：目标管理与掩体重选（2026-08-17 M3.3 T14）──

## 可见敌对取最近（规格 5）：_seen 中有效未死者按 body 水平距最近；空集 → null。
func _nearest_seen() -> Node:
	var best: Node = null
	var best_dist := INF
	for t in _seen.keys():
		if not is_instance_valid(t):
			continue
		var n3 := t as Node3D
		if n3 == null or _target_dead(n3):
			continue
		var d := Vector2(n3.global_position.x - body.global_position.x,
				n3.global_position.z - body.global_position.z).length()
		if d < best_dist:
			best = n3
			best_dist = d
	return best


## 目标死亡判定（规格 5 三口径：died 信号/实例失效/Enemy.dead 标记——died 信号由
## 感知侧死目标剔除间接体现，dead 标记 + 实例失效轮询兜底；BotPerception._is_dead
## 同口径，感知私有故决策层自持一份）。
func _target_dead(target: Node) -> bool:
	if target == null or not is_instance_valid(target):
		return true
	if target.get("dead") == true:
		return true
	for c in target.get_children():
		if c.get("dead") == true:
			return true
	return false


## ENGAGE 掩体重选（规格 4）：候选 = tactical._points 中距敌（current_target 优先，
## 无效用 LKP）水平距 ∈ [COVER_MIN, COVER_MAX] 且 tier 序 ≤ COVER_TIER_MAX 且对敌
## 有 LOS 断点（复用 BotPerception.los_blocked 静态：空间 ray 掩码 5，从掩体点
## 胸口高度射向敌胸口——被挡 = 有断点）→ 取距己最近 → set_target + _cover_target；
## 无候选 → 保持原位（_cover_target 清空，不动 locomotion）。
func _reselect_cover() -> void:
	_cover_target = {}
	var enemy_pos := Vector3.ZERO
	var ct := current_target as Node3D
	if ct != null and not _target_dead(ct):
		enemy_pos = ct.global_position
	elif ct != null:
		enemy_pos = perception.last_known_pos(ct)
	if enemy_pos == Vector3.ZERO:
		return  # 无敌位（无目标/无 LKP）→ 保持原位
	var space := body.get_world_3d().direct_space_state
	var enemy_chest := enemy_pos + BotPerception.CHEST_OFFSET
	var tier_max_idx: int = TacticalPoints.TIER_ORDER.find(COVER_TIER_MAX)
	var best := {}
	var best_dist := INF
	for p0 in tactical._points:
		var p: Dictionary = p0
		if TacticalPoints.TIER_ORDER.find(p["tier"]) > tier_max_idx:
			continue
		var c: Vector3 = p["center"]
		var d_enemy := Vector2(c.x - enemy_pos.x, c.z - enemy_pos.z).length()
		if d_enemy < COVER_MIN or d_enemy > COVER_MAX:
			continue
		var from := Vector3(c.x, c.y + BotPerception.CHEST_OFFSET.y, c.z)  # 掩体点胸口高度
		if not BotPerception.los_blocked(space, from, enemy_chest,
				BotPerception.LOS_MASK, _los_exclude_rids(current_target)):
			continue  # 对敌可见（无 LOS 断点）→ 不合格
		var d_self := Vector2(c.x - body.global_position.x,
				c.z - body.global_position.z).length()
		if d_self < best_dist:
			best = p
			best_dist = d_self
	if not best.is_empty():
		_cover_target = best
		locomotion.set_target(best["center"])


## ENGAGE 退出清理（规格 4）：掩体重选状态清零（cover_target 黑板键由
## _write_blackboard 同步空字典）。
func _clear_cover() -> void:
	_cover_target = {}
	_cover_t = 0.0


## LOS 排除集合：自身 + 目标本体/子碰撞体 RID——射线终点在目标躯干胶囊内，不排除
## 则恒被目标本体遮挡（BotPerception._exclude_rids 同口径；感知私有，决策层自持）。
func _los_exclude_rids(target: Node) -> Array[RID]:
	var out: Array[RID] = []
	if body != null:
		out.append(body.get_rid())
		for c in body.get_children():
			if c is CollisionObject3D:
				out.append((c as CollisionObject3D).get_rid())
	if target is CollisionObject3D:
		out.append((target as CollisionObject3D).get_rid())
		for c in target.get_children():
			if c is CollisionObject3D:
				out.append((c as CollisionObject3D).get_rid())
	return out
