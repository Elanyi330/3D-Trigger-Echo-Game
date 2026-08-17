# Levels/M2_TDM/bot_brain.gd
# M3.3 T13（2026-08-17）：BotBrain 分层状态机（HSM）骨架——M3 AI 决策层心脏。
# 七状态（IDLE/PATROL/ALERT/ENGAGE/CHASE/RELOAD/RETREAT）+ 感知接线 + 四意图信号
# （fire/switch/throw/melee——M3.4 战斗集成接线）。状态转移表以任务简报为唯一权威
# （进入状态即发 state_changed）。
# 决策层消费感知铁律：只读黑板/感知信号/查询，不反向写感知状态；感知不决策、
# 决策不感知（企划书铁律 + 项目 CLAUDE.md 技术陷阱 6）。
# 未实现部分以默认行为运行（注释注明「Tn 实现」，不允许占位假行为）：
#   PATROL 目标 = tactical.nearest（默认行为，T14 换 weighted_pick）；ENGAGE 无走位
#   （T14 掩体重选）；无切枪/无扔雷（T16）；strategy 恒 null（T15 装配）。
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
const CHASE_LIMIT := 30.0   # m：追击上限（自接敌位置）
const COVER_MIN := 8.0      # m：掩体距敌下限（T14 掩体重选消费）
const COVER_MAX := 15.0     # m：掩体距敌上限（T14 掩体重选消费）
const COVER_TIER_MAX := "medium"  # 掩体难度上限（难度≤中等；T13 RETREAT 选点消费）
# ── 实现常量（2026-08-17 M3.3 T13，语义规格值；未列入接口块）──
const FIRE_THROTTLE := 0.2  # s：fire_intent 节流周期（同感知节流 BotPerception.THROTTLE）
const PATROL_DWELL := 3.0   # s：T13 巡逻驻点恒 3s（T14 改随机 2-4s）
const ALERT_WATCH := 5.0    # s：ALERT 到达 LKP 无发现超时 → PATROL
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
var _patrol_hold_t := -1.0          # PATROL 驻点倒计时（<0 = 未驻点）
var _alert_watch_t := -1.0          # ALERT 无发现计时（<0 = 未到达 LKP）
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
func _set_state(to: State) -> void:
	if _dead:
		return  # 死亡后不再转移（Brain 停止）
	var from := state
	state = to
	_arrived = false  # 状态切换清除到达旗（防跨状态泄漏）
	state_changed.emit(State.keys()[from], State.keys()[to])
	_enter_state(to)


## 状态机转移判定（tick 第 2 步）：黑板键注入驱动的转移 + 计时驱动转移
## （计时器归本步骤倒计时——计时即转移机制）。信号驱动转移
## （hostile_visible/hostile_lost/heard_event）在感知信号处理器中即时完成。
## 转移表（简报唯一权威，逐字照抄）：
##   IDLE   --出生保护结束（黑板键 spawn_protection_left ≤0）--> PATROL
##   PATROL --到达巡逻点驻点结束--> PATROL（换点，T14 实现换点，T13 驻点恒 3s）
##   ALERT  --到达 LKP 无发现且超 5s--> PATROL
##   ENGAGE --黑板 hp<30--> RETREAT；--黑板 mag_frac<0.3--> RELOAD
##   CHASE  --追击超限（自接敌位置累计路径 > CHASE_LIMIT）或 LKP 过期--> ALERT
##   RELOAD --黑板 reload_done=true（T16 设）--> ENGAGE（目标仍可见）或 PATROL
##   RETREAT --超 8s--> PATROL（掩体到达在状态行为经 arrived 旗）
func _evaluate_transitions(delta: float) -> void:
	match state:
		State.IDLE:
			if blackboard.get_value("spawn_protection_left", 0.0) <= 0.0:
				_set_state(State.PATROL)
		State.PATROL:
			if _patrol_hold_t > 0.0:
				_patrol_hold_t -= delta
				if _patrol_hold_t <= 0.0:
					_patrol_hold_t = -1.0
					_set_state(State.PATROL)  # 驻点结束换点（重进入重 pick）
		State.ALERT:
			if _alert_watch_t > 0.0:
				_alert_watch_t -= delta
				if _alert_watch_t <= 0.0:
					_alert_watch_t = -1.0
					_set_state(State.PATROL)  # 到达 LKP 无发现超 5s
		State.ENGAGE:
			if blackboard.get_value("hp", 100.0) < 30.0:
				_set_state(State.RETREAT)
			elif blackboard.get_value("mag_frac", 1.0) < 0.3:
				_set_state(State.RELOAD)
		State.CHASE:
			if _chase_limit_exceeded() or _chase_lkp_expired():
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
			pass  # 追击 LKP 进入时已 set_target（T14 细化 LKP 刷新跟踪）
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


## PATROL 进入：选点（T13 默认行为 = 最近点；T14 换 weighted_pick + 策略偏置）
## → locomotion.set_target。驻点计时复位。
func _enter_patrol() -> void:
	_patrol_hold_t = -1.0
	var pick: Dictionary = tactical.nearest(body.global_position)  # T14 换 weighted_pick
	if not pick.is_empty():
		locomotion.set_target(pick["center"])


## PATROL 行为：到达巡逻点 → 驻点倒计时启动（T13 恒 3s；驻点结束换点见转移判定）。
func _tick_patrol() -> void:
	if _arrived:
		_arrived = false
		_patrol_hold_t = PATROL_DWELL


## ALERT 进入：前往听觉事件位置（黑板 alert_pos；T14 细化导航投影，T13 直设）。
func _enter_alert() -> void:
	_alert_watch_t = -1.0
	var pos: Vector3 = blackboard.get_value("alert_pos", body.global_position)
	locomotion.set_target(pos)


## ALERT 行为：到达 LKP → 无发现计时启动（超 5s → PATROL 见转移判定；
## 期间视线内敌对 → hostile_visible 信号转 ENGAGE）。
func _tick_alert() -> void:
	if _arrived:
		_arrived = false
		_alert_watch_t = ALERT_WATCH


## ENGAGE 进入：反应倒计时（0.3-0.6s 随机）+ 节流累计清零 + 站定射击
## （T13 默认无走位；T14 掩体重选接管 ENGAGE 移动）。
func _enter_engage() -> void:
	_reaction_t = reaction_delay(0)
	_fire_t = 0.0
	locomotion.clear_target()


## ENGAGE 行为：反应倒计时归零前不发 fire_intent；归零帧立即首发，此后每
## FIRE_THROTTLE（0.2s，同感知节流）持续发（持续目标持续发——M3.4 射击节流消费）。
func _tick_engage(delta: float) -> void:
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


## CHASE 进入：黑板记接敌位置 chase_origin（追击上限基准）+ 追 LKP
## （进入时一次 set_target；T14 细化：LKP 刷新 >0.5m 重 set_target）。
func _enter_chase() -> void:
	blackboard.set_value("chase_origin", body.global_position)
	var lkp := Vector3.ZERO
	if current_target != null and is_instance_valid(current_target):
		lkp = perception.last_known_pos(current_target)
	if lkp != Vector3.ZERO:
		locomotion.set_target(lkp)


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


## 追击超限判定：自接敌位置（黑板 chase_origin）水平距 > CHASE_LIMIT。
## T13 骨架口径 = 直线水平距（测试经黑板注入 chase_origin 验证）；T14 改
## 「累计路径」口径（body 每帧位移和，chase_origin 仍是基准）。
func _chase_limit_exceeded() -> bool:
	var origin: Vector3 = blackboard.get_value("chase_origin", body.global_position)
	var d := Vector2(body.global_position.x - origin.x, body.global_position.z - origin.z)
	return d.length() > CHASE_LIMIT


## LKP 过期判定：无 LKP 条目（invisible_time < 0——感知遗忘后返回 -1）或
## 目标已释放/无效。
func _chase_lkp_expired() -> bool:
	if current_target == null or not is_instance_valid(current_target):
		return true
	return perception.invisible_time(current_target) < 0.0


## 黑板标准键写（tick 第 5 步）：
## 写键 state（状态字符串名）/target/target_lkp；
## 读键 hp/mag_frac/spawn_protection_left/reload_done/alert_pos/chase_origin
## （T14-T16 共用协议）。
func _write_blackboard() -> void:
	blackboard.set_value("state", State.keys()[state])
	blackboard.set_value("target", current_target)
	var lkp := Vector3.ZERO
	if current_target != null and is_instance_valid(current_target):
		lkp = perception.last_known_pos(current_target)
	blackboard.set_value("target_lkp", lkp)


# ── 感知信号处理器（setup 时接线；信号驱动转移即时完成）──

## hostile_visible：目标缓存 + IDLE/PATROL/ALERT/CHASE 状态转 ENGAGE
## （反应时间随 ENGAGE 进入重置）。
func _on_hostile_visible(target: Node, _pos: Vector3) -> void:
	_seen[target] = true
	current_target = target
	if state == State.IDLE or state == State.PATROL or state == State.ALERT \
			or state == State.CHASE:
		_set_state(State.ENGAGE)


## hostile_lost：可见集合移除；ENGAGE 且目标 == current_target 且无其他可见敌对
## → CHASE（接敌位置记黑板 chase_origin，见 _enter_chase）。
func _on_hostile_lost(target: Node) -> void:
	_seen.erase(target)
	if state == State.ENGAGE and target == current_target and _seen.is_empty():
		_set_state(State.CHASE)


## heard_event：PATROL/IDLE 时 → ALERT + 黑板 alert_pos（ALERT 前往
## = locomotion.set_target(alert_pos)——T14 细化，T13 直设）。
func _on_heard_event(_kind: String, pos: Vector3) -> void:
	if state == State.IDLE or state == State.PATROL:
		blackboard.set_value("alert_pos", pos)
		_set_state(State.ALERT)


## locomotion.arrived：到达旗（PATROL 驻点/ALERT 计时/RETREAT 回巡逻消费）。
func _on_arrived() -> void:
	_arrived = true


## 死亡 → Brain 停止（计划 T13 语义：M3.5 复活新实例自然重置）。
func _on_died() -> void:
	_dead = true
	locomotion.clear_target()
