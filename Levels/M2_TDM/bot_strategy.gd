# Levels/M2_TDM/bot_strategy.gd
# M3.3 T15（2026-08-17）：BotStrategy 策略选择器——4 策略目录（默认 roam / 猎手
# Hunter / 侧袭 Flanker / 防守 Hold），触发条件全量化纯函数 + 行为偏置参数包 +
# 优先级裁决 + 冷却 + Hunter 同阵营占用 ≤2（先到先得）。
# 铁律（简报）：
#   1. 策略不驱动行为：只输出参数包（params()），BotBrain 各决策点读包做偏置——
#      策略层内无状态机、无移动/武器调用（不碰 locomotion/Brain 接口），
#      只读写黑板/事件板。
#   2. 直接威胁优先：黑板 state==ENGAGE/CHASE 时冻结触发评估（仅 PATROL/ALERT
#      评估）；生命周期出口照常运行——Flanker「接敌即结束」出口依赖此。
#   3. 时间戳 _elapsed 单调累计（tick 首行 delta 求和——与事件板同源铁律）；
#      tick 由装配方按 60Hz 物理帧驱动（60Hz tick 铁律）。
#   4. Hunter 槽位配对释放：离开 HUNTER 任一出口都 release_slot("hunter")。
class_name BotStrategy
extends Node

signal strategy_changed(from: int, to: int)

enum Strategy { ROAM, HUNTER, FLANKER, HOLD }  # 优先级：HUNTER > FLANKER > HOLD > ROAM

const DEATH_WINDOW := 15.0    # s：阵亡统计窗口（Hunter/Hold 触发）
const CLUSTER_RADIUS := 10.0  # m：阵亡簇判定（质心间最大距离）
const HUNTER_RADIUS := 25.0   # m：簇 C 半径内目标权重 ×3
const HUNTER_GUN_DRAW := 30.0 # m：进入 C 30m 切回主枪（T16 消费）
const GRENADE_RANGE := 20.0   # m：雷程（Hunter 突入前开路判定，T16 消费）
const HUNTER_LIFETIME := 45.0 # s
const HUNTER_QUIT_DIST := 20.0  # m：目标离开 C 区判定
const HUNTER_MAX := 2         # 同阵营 Hunter 占用上限（先到先得）
const FLANKER_MIN_DIST := 15.0   # m：目标直线距下限
const FLANKER_PATH_RATIO := 1.5  # 路径长/直线长阈值
const HOLD_TIMEOUT := 30.0    # s
const COOLDOWN := 20.0        # s：同策略结束后冷却（防振荡）
const LOS_PATH_WEIGHT := 2.0  # Flanker LOS 段加权系数（路径成本语义，M3.3 实为
                              # 路线选择偏置：Brain 选点时对目标有 LOS 的方向加罚）
# ── 实现常量（2026-08-17 M3.3 T15，语义规格值；未列入接口块）──
const HUNTER_QUIT_TIME := 20.0   # s：目标离开 C 区连续计时上限
const FLANKER_END_DIST := 30.0   # m：Flanker 接敌结束判定（目标距 body）
const HUNT_BIAS := 3.0           # Hunter 簇内目标权重（params.bias）

var faction: String            # 己方阵营（"enemy"/"friendly"——阵亡统计口径）
var board: EventBoard          # 死亡事件源 + 槽位（acquire_slot/release_slot）
var blackboard: BotBlackboard  # 读：state/target/target_lkp/alive_own/alive_enemy
var body: CharacterBody3D      # 位置/路径长来源（Flanker 评估）

var _strategy := Strategy.ROAM
var _elapsed := 0.0            # 单调累计（tick 首行 delta 求和——与事件板同源铁律）
var _cooldowns := {}           # Strategy int -> 剩余冷却 s（每策略独立冷却计时）
var _hunter_centroid := Vector3.ZERO
var _hunter_t := 0.0           # HUNTER 已持续
var _hunter_quit_t := 0.0      # 目标离开 C 区连续累计（策略内连续计时）
var _hunter_had_target := false  # 曾持有有效目标（目标死亡出口仅在其后生效）
var _flanker_target := Vector3.ZERO  # Flanker 入口目标位置（LKP 过期后兜底）
var _hold_t := 0.0             # HOLD 已持续


## 装配（tick 前调用）：绑定阵营/事件板/黑板/宿主。body 可为 null（仅 Flanker
## 评估需要位置；无 body 时 Flanker 候选自动跳过）。
func setup(f: String, b: EventBoard, bb: BotBlackboard, bd: CharacterBody3D) -> void:
	faction = f
	board = b
	blackboard = bb
	body = bd


## 每物理帧调用（60Hz tick 铁律——装配方驱动）。顺序：_elapsed 累计（首行铁律）→
## 冷却递减 → 当前策略生命周期出口 → 直接威胁冻结守卫 → 触发评估。
func tick(delta: float) -> void:
	_elapsed += delta          # 首行：单调累计（与事件板同源铁律）
	if blackboard == null or board == null:
		return
	for k in _cooldowns:
		_cooldowns[k] = maxf(_cooldowns[k] - delta, 0.0)
	match _strategy:            # 生命周期出口（冻结期间照常——Flanker 接敌出口依赖）
		Strategy.HUNTER:
			_tick_hunter(delta)
		Strategy.FLANKER:
			_tick_flanker()
		Strategy.HOLD:
			_tick_hold(delta)
	if _state_frozen():         # 直接威胁优先铁律：ENGAGE/CHASE 冻结触发评估
		return
	_evaluate_triggers()


func current() -> int:
	return _strategy


## 当前策略参数包（BotBrain 消费；结构照抄简报）：
##   ROAM:    {type: "roam"}
##   HUNTER:  {type: "hunter", centroid: Vector3, radius: 25.0, bias: 3.0,
##             grenade_open: true}
##   FLANKER: {type: "flanker", los_penalty: 2.0}
##   HOLD:    {type: "hold", half_filter: float}（己方半场 z 界——T14/Brain 消费）
func params() -> Dictionary:
	match _strategy:
		Strategy.HUNTER:
			return {"type": "hunter", "centroid": _hunter_centroid,
					"radius": HUNTER_RADIUS, "bias": HUNT_BIAS, "grenade_open": true}
		Strategy.FLANKER:
			return {"type": "flanker", "los_penalty": LOS_PATH_WEIGHT}
		Strategy.HOLD:
			return {"type": "hold", "half_filter": _half_filter()}
		_:
			return {"type": "roam"}


# ── 触发条件纯函数（static，可单测）──

## 阵亡簇判定（Hunter 触发条件）：输入 recent_deaths(own_faction, window) 的列表；
## 输出 {clustered: bool, centroid: Vector3, max_pair_dist: float}——≥2 死亡且
## 死亡位置两两最大距离 ≤ radius 即簇。window：与 recent_deaths 同口径的时间窗
## （输入预期已按窗过滤；本函数按 t 相对列表内最新死亡再过滤一遍保自包含——
## 缺 t 键的条目不剔除）。centroid = 死亡位置均值；<2 死亡 → clustered=false、
## centroid=ZERO、max_pair_dist=0。
static func death_cluster(deaths: Array, window: float, radius: float) -> Dictionary:
	var pts: Array[Vector3] = []
	var t_latest := -INF
	for d in deaths:
		var t = d.get("t", null)
		if typeof(t) == TYPE_FLOAT:
			t_latest = maxf(t_latest, t)
	for d in deaths:
		var pos = d.get("pos", null)
		if pos == null or not (pos is Vector3):
			continue
		var t = d.get("t", null)
		if typeof(t) == TYPE_FLOAT and t < t_latest - window:
			continue
		pts.append(pos)
	if pts.size() < 2:
		return {"clustered": false, "centroid": Vector3.ZERO, "max_pair_dist": 0.0}
	var centroid := Vector3.ZERO
	for p in pts:
		centroid += p
	centroid /= pts.size()
	var max_pair := 0.0
	for i in pts.size():
		for j in range(i + 1, pts.size()):
			max_pair = maxf(max_pair, _horiz(pts[i], pts[j]))
	return {"clustered": max_pair <= radius, "centroid": centroid,
			"max_pair_dist": max_pair}


## Hunter 目标偏置（参数包消费语义）：目标在 C（params.centroid 半径
## params.radius）内 → params.bias（默认 3.0），否则 1.0。pos = bot 自身位置
## （现口径不参与公式，接口对称预留）。
static func hunt_target_bias(params: Dictionary, target_pos: Vector3,
		pos: Vector3) -> float:
	var centroid: Vector3 = params.get("centroid", Vector3.ZERO)
	var radius: float = params.get("radius", HUNTER_RADIUS)
	var bias: float = params.get("bias", HUNT_BIAS)
	if _horiz(target_pos, centroid) <= radius:
		return bias
	return 1.0


## Flanker 触发条件：目标直线距 ≥ FLANKER_MIN_DIST 且 path_len/直线距 ≥
## FLANKER_PATH_RATIO（存在绕行空间；边界含等值——简报测试口径：恰 1.5 倍 → true）。
static func flanker_eligible(body_pos: Vector3, target_pos: Vector3,
		path_len: float) -> bool:
	var straight := _horiz(body_pos, target_pos)
	if straight < FLANKER_MIN_DIST:
		return false
	return path_len >= straight * FLANKER_PATH_RATIO


## Hold 触发条件：己方存活 < 敌方存活 且 15s 内己方阵亡 ≥2 且非簇（簇 → Hunter
## 优先——HUNTER 触发条件命中即不再评估 HOLD）。
static func hold_eligible(alive_own: int, alive_enemy: int, deaths_15s: int,
		clustered: bool) -> bool:
	return alive_own < alive_enemy and deaths_15s >= 2 and not clustered


# ── 裁决与触发 ──

## 策略优先级（裁决序）：HUNTER 3 > FLANKER 2 > HOLD 1 > ROAM 0。
func _priority(s: int) -> int:
	match s:
		Strategy.HUNTER:
			return 3
		Strategy.FLANKER:
			return 2
		Strategy.HOLD:
			return 1
		_:
			return 0


## 直接威胁优先铁律：黑板 state==ENGAGE/CHASE → 冻结触发评估（仅 PATROL/ALERT 评估）。
func _state_frozen() -> bool:
	var st: String = blackboard.get_value("state", "")
	return st == "ENGAGE" or st == "CHASE"


## 触发评估（每物理帧；条件全部 static 纯函数）。裁决：切换仅当新策略优先级
## 高于当前（防横跳）；同策略结束后 COOLDOWN 内不重复触发（每策略独立冷却）。
## 顺序：HUNTER（簇；槽位失败降级继续评估 FLANKER）→ FLANKER → HOLD（非簇）→
## ROAM 恒真兜底（无更高优先级候选保持现状——更高策略由各自生命周期出口回收）。
func _evaluate_triggers() -> void:
	var deaths: Array = board.recent_deaths(faction, DEATH_WINDOW)
	var cluster: Dictionary = death_cluster(deaths, DEATH_WINDOW, CLUSTER_RADIUS)
	if _strategy != Strategy.HUNTER and _cooldown_ready(Strategy.HUNTER) \
			and cluster["clustered"]:
		if board.acquire_slot("hunter", HUNTER_MAX):
			_enter_hunter(cluster["centroid"])
			return
		# 槽位失败（同阵营已 2 人 Hunter）→ 降级评估 FLANKER（继续向下）
	if _priority(Strategy.FLANKER) > _priority(_strategy) \
			and _cooldown_ready(Strategy.FLANKER):
		var tp := _target_pos()
		if tp != Vector3.ZERO and body != null \
				and flanker_eligible(body.global_position, tp, _path_len(tp)):
			_enter_flanker(tp)
			return
	if not cluster["clustered"] and _priority(Strategy.HOLD) > _priority(_strategy) \
			and _cooldown_ready(Strategy.HOLD):
		var own: int = blackboard.get_value("alive_own", 0)
		var enemy: int = blackboard.get_value("alive_enemy", 0)
		if hold_eligible(own, enemy, deaths.size(), false):
			_enter_hold()
			return
	# ROAM 恒真兜底：无更高优先级候选 → 保持现状（当前已是 ROAM 或更高策略生命周期内）


func _cooldown_ready(s: int) -> bool:
	return _cooldowns.get(s, 0.0) <= 0.0


func _start_cooldown(s: int) -> void:
	_cooldowns[s] = COOLDOWN


func _set_strategy(to: int) -> void:
	if _strategy == to:
		return
	var from := _strategy
	_strategy = to
	strategy_changed.emit(from, to)


## 策略结束（生命周期任一出口共用）：槽位配对释放（仅 HUNTER 持有）+ 冷却启动
## （同策略结束后 COOLDOWN 内不重复触发）+ 回 ROAM。
func _end_strategy() -> void:
	if _strategy == Strategy.HUNTER:
		board.release_slot("hunter")  # 配对释放（离开 HUNTER 任一出口都 release）
	_start_cooldown(_strategy)
	_set_strategy(Strategy.ROAM)


# ── HUNTER ──

## HUNTER 进入：记质心 + 计时清零 + 黑板写 hunt_centroid（槽位在触发时已 acquire）。
func _enter_hunter(centroid: Vector3) -> void:
	_hunter_centroid = centroid
	_hunter_t = 0.0
	_hunter_quit_t = 0.0
	_hunter_had_target = false
	blackboard.set_value("hunt_centroid", centroid)
	_set_strategy(Strategy.HUNTER)


## HUNTER 生命周期（简报）：45s 超时 / 目标离开 C 区（目标位置距 centroid >
## HUNTER_QUIT_DIST 连续 HUNTER_QUIT_TIME——连续计时在策略内）/ 目标死亡 →
## ROAM + release_slot。
func _tick_hunter(delta: float) -> void:
	_hunter_t += delta
	if _hunter_t > HUNTER_LIFETIME:
		_end_strategy()
		return
	var t = blackboard.get_value("target", null)
	var target_alive := t != null and is_instance_valid(t) and not _node_dead(t)
	if target_alive:
		_hunter_had_target = true
	elif _hunter_had_target:
		_end_strategy()  # 目标死亡（曾有效后失效/死亡）→ ROAM
		return
	var tp := _target_pos()
	if tp != Vector3.ZERO:
		if _horiz(tp, _hunter_centroid) > HUNTER_QUIT_DIST:
			_hunter_quit_t += delta
			if _hunter_quit_t > HUNTER_QUIT_TIME:
				_end_strategy()  # 目标离开 C 区连续超 20s → ROAM
				return
		else:
			_hunter_quit_t = 0.0  # 回到 C 区 → 连续计时清零


# ── FLANKER ──

## FLANKER 进入：记入口目标位置（LKP 过期后兜底——保证「一次接敌」出口恒可判定）。
func _enter_flanker(target_pos: Vector3) -> void:
	_flanker_target = target_pos
	_set_strategy(Strategy.FLANKER)


## FLANKER 生命周期（简报）：进入接敌（黑板 state 变 ENGAGE 或目标距 body < 30m）
## → 结束回 ROAM。目标位置失效（LKP 过期清零）→ 用入口位置兜底——防无目标
## 信息永久滞留（2026-08-17 M3.3 T15 实现口径注记）。
func _tick_flanker() -> void:
	if blackboard.get_value("state", "") == "ENGAGE":
		_end_strategy()
		return
	var tp := _target_pos()
	if tp == Vector3.ZERO:
		tp = _flanker_target
	if body != null and tp != Vector3.ZERO \
			and _horiz(body.global_position, tp) < FLANKER_END_DIST:
		_end_strategy()


# ── HOLD ──

func _enter_hold() -> void:
	_hold_t = 0.0
	_set_strategy(Strategy.HOLD)


## HOLD 生命周期（简报）：30s 超时 或 alive_own ≥ alive_enemy → ROAM。
func _tick_hold(delta: float) -> void:
	_hold_t += delta
	var own: int = blackboard.get_value("alive_own", 0)
	var enemy: int = blackboard.get_value("alive_enemy", 0)
	if _hold_t > HOLD_TIMEOUT or own >= enemy:
		_end_strategy()


## HOLD 半场过滤边界（己方半场 z 界）：地图 +Z=north、z=0 中线（map_layout_v3 L8），
## 南营（enemy，z<0）/北营（friendly，z>0）对称 → 边界恒 0.0，保留方向由消费方
## 按阵营取（enemy → 保留 z < half_filter；friendly → 保留 z > half_filter）。
## 偏差注记（2026-08-17 M3.3 T15）：简报括号内「enemy → 南半场 z>0 保留」与
## 本项目 +Z=north 约定符号相反（南半场实为 z<0），值域一致（边界 0.0），
## 以地图几何为准；消费方在 T14+/T17 实现，现无行为依赖。
func _half_filter() -> float:
	return 0.0


# ── 读取辅助 ──

## 目标位置（LKP 优先——简报口径；无 LKP 用有效目标节点位置；均无 → ZERO）。
func _target_pos() -> Vector3:
	var lkp: Vector3 = blackboard.get_value("target_lkp", Vector3.ZERO)
	if lkp != Vector3.ZERO:
		return lkp
	var t = blackboard.get_value("target", null)
	if t != null and is_instance_valid(t):
		var n3 := t as Node3D
		if n3 != null:
			return n3.global_position
	return Vector3.ZERO


## Flanker 路径长：黑板键 path_remaining（Brain 写：locomotion 当前路径剩余 + 已走，
## T17/T18 装配后常态存在）；缺键 → 直线距 ×2 保守估计（2026-08-17 M3.3 T15：
## T14 Brain 未写该键——装配前缺键为常态，×2 使比率恒 ≥1.5、Flanker 倾向触发，
## 保守口径）。
func _path_len(target_pos: Vector3) -> float:
	var pr: Variant = blackboard.get_value("path_remaining", -1.0)
	if typeof(pr) == TYPE_FLOAT or typeof(pr) == TYPE_INT:
		if pr >= 0.0:
			return float(pr)
	return _horiz(body.global_position, target_pos) * 2.0


## 目标死亡判定（BotBrain._target_dead 同口径三式：实例失效/dead 标记/子节点 dead
## 标记——决策层私有故策略自持一份）。
func _node_dead(n: Node) -> bool:
	if n == null or not is_instance_valid(n):
		return true
	if n.get("dead") == true:
		return true
	for c in n.get_children():
		if c.get("dead") == true:
			return true
	return false


## 水平距离（x/z——项目战术距离口径，同 BotBrain）。
static func _horiz(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
