# test/unit/test_bot_brain_hsm.gd
# M3.3 T13（2026-08-17）：BotBrain HSM 骨架测试（TDD，先 RED 后 GREEN）。
# 目标：七状态分层状态机（IDLE/PATROL/ALERT/ENGAGE/CHASE/RELOAD/RETREAT）转移表
#   + 感知接线（hostile_visible/hostile_lost/heard_event）+ 反应时间时序
#   （归零前不发 fire_intent、归零后 0.2s 节流持续发）+ 黑板标准键注入/写出协议。
# 装配（禁止 mock 与反射 hack）：GutTest 场景直建真实 Enemy 观察者/目标 + 真实
#   BotPerception/BotBlackboard/BotLocomotion（map_rid = 测试场景世界导航图，无
#   navmesh 烘焙 → set_target 后路径恒空、不推进物理——最简真实装配口径）+
#   真实 TacticalPoints.build_from_faces。转移测试以黑板键注入为主（hp/mag_frac/
#   spawn_protection_left/chase_origin），感知信号转移（ENGAGE/CHASE）以真实感知
#   轻量装配验证（T8 范式：观察者 + 视线内目标 + 墙体）。
# tick 频率铁律：brain.tick 每物理帧一次（1/60 delta，60Hz 口径）；Brain 为感知/
#   移动的装配驱动方（perception.tick/locomotion.tick 由 Brain.tick 统一驱动）。
# RED 锚：生产类 BotBrain 尚不存在——本脚本引用该类即类加载失败（"Could not find
#   type BotBrain" 类错误，即正确的 RED 失败原因；同 T6/T8 锚口径）。
extends GutTest

const ENEMY_SCRIPT := preload("res://Levels/Enemy/Enemy.gd")
const JE := preload("res://Levels/M2_TDM/jump_edges.gd")

var _state_events: Array = []   # [{from: String, to: String}]（state_changed 记录）
var _fire_log: Array = []       # [{target: Node, tick: int}]（fire_intent 记录 + 发射帧号）
var _tick_count := 0            # 每测试内单调 tick 计数（时序断言基准）


func _on_state_changed(from: String, to: String) -> void:
	_state_events.append({"from": from, "to": to})


func _on_fire(target: Node) -> void:
	_fire_log.append({"target": target, "tick": _tick_count})


## GUT 同脚本实例跨测试复用——事件/计数必须逐测试清零（防跨测试事件泄漏）。
func before_each() -> void:
	_state_events.clear()
	_fire_log.clear()
	_tick_count = 0


# ── 测试辅助 ──

# 盒构造器（同 test_bot_lkp.gd 范式）：BoxShape3D StaticBody（Objects 层 1）
func _make_box(size: Vector3, center: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	body.position = center
	add_child_autofree(body)
	return body


# 物理地面（40×1×40，顶面 y=0）
func _make_floor() -> StaticBody3D:
	return _make_box(Vector3(40, 1, 40), Vector3(0, -0.5, 0))


# Enemy.new() 落定实例——定位先于入树（防陈旧形状注册，同 test_enemy_command_drive.gd）
func _spawn_settled(pos: Vector3, enemy_side: bool) -> Enemy:
	var e: Enemy = ENEMY_SCRIPT.new()
	e.is_enemy = enemy_side
	e.position = pos
	add_child_autofree(e)
	await wait_physics_frames(50)
	return e


## 轻量真实装配：地面 + 观察者（enemy，朝 -Z）+ 目标（friendly，正前 10m 无遮挡）+
## 真实感知/黑板/移动/战术点 + Brain（连 state_changed/fire_intent 记录）。
## 移动层 map_rid = 测试场景世界导航图（无 navmesh——set_target 后路径恒空不推进
## 物理，brief 允许的最简真实装配）；战术点真实 build_from_faces（T12 快照表）。
func _setup_brain() -> Dictionary:
	_make_floor()
	var observer := await _spawn_settled(Vector3(0, 1, 0), true)
	var target := await _spawn_settled(Vector3(0, 1, -10), false)
	observer.rotation.y = 0.0
	var per := BotPerception.new()
	add_child_autofree(per)
	per.setup(observer, observer.get_faction(), null)
	var bb := BotBlackboard.new()
	add_child_autofree(bb)
	# 导航图首次同步等待（同 L_M2 等待口径）：未同步前 map_get_closest_point
	# 报错（"before first map synchronization"）——BotLocomotion.setup 的链接对齐
	# 循环会触发。GUT 场景首测时地图可能尚未完成首次同步，有界轮询直至同步。
	var map_rid: RID = observer.get_world_3d().navigation_map
	var synced := false
	for i in 240:
		if NavigationServer3D.map_get_iteration_id(map_rid) > 0:
			synced = true
			break
		await wait_physics_frames(1)
	assert_true(synced, "前置：导航图应在 240 帧内完成首次同步")
	var loco := BotLocomotion.new()
	add_child_autofree(loco)
	loco.setup(observer, map_rid)
	var tp := TacticalPoints.build_from_faces(JE.faces())
	var brain := BotBrain.new()
	add_child_autofree(brain)
	brain.state_changed.connect(_on_state_changed)
	brain.fire_intent.connect(_on_fire)
	brain.setup(observer, per, bb, loco, tp)
	return {"observer": observer, "target": target, "per": per, "bb": bb,
			"brain": brain, "loco": loco}


## Brain tick 驱动：每物理帧 tick 一次（60Hz 口径），tick 计数单调递增（时序基准）。
func _tick(brain: BotBrain) -> void:
	_tick_count += 1
	brain.tick(1.0 / 60.0)
	await wait_physics_frames(1)


## 固定帧数驱动（tick 频率铁律：≤frames 帧推进）。
func _drive(brain: BotBrain, frames: int) -> void:
	for i in frames:
		await _tick(brain)


func _saw_state_change(from: String, to: String) -> bool:
	for ev in _state_events:
		if ev["from"] == from and ev["to"] == to:
			return true
	return false


# ── T13-1：setup 后 state == IDLE（初始态，未 tick 不发 state_changed）──
func test_initial_state_idle() -> void:
	var h := await _setup_brain()
	var brain: BotBrain = h["brain"]
	assert_eq(brain.state, BotBrain.State.IDLE, "setup 后 state == IDLE")
	assert_eq(_state_events.size(), 0, "初始状态不发 state_changed")
	assert_eq(brain.current_target, null, "初始无目标")


# ── T13-2：出生保护结束（黑板键 spawn_protection_left ≤0）→ PATROL ──
func test_idle_to_patrol() -> void:
	var h := await _setup_brain()
	var brain: BotBrain = h["brain"]
	var bb: BotBlackboard = h["bb"]
	bb.set_value("spawn_protection_left", 0.0)
	await _tick(brain)
	assert_eq(brain.state, BotBrain.State.PATROL, "出生保护结束 → PATROL")
	assert_true(_saw_state_change("IDLE", "PATROL"), "state_changed(IDLE→PATROL)")
	assert_eq(bb.get_value("state"), "PATROL", "黑板写键 state == 状态字符串名")


# ── T13-3：真实感知装配——视线内敌对 → hostile_visible → ENGAGE（+ 反应时序）──
# 观察者敌 bot 正前 10m 友 bot 无遮挡：扫描（0.2s 节流）→ hostile_visible →
# PATROL→ENGAGE。反应时序断言：进入帧 fire_intent 为 0（归零前不发）；首发距进入
# ≥0.3s（REACTION_MIN）；后续每 0.2s 节流（≥12 帧）持续发且目标恒为 current_target。
func test_patrol_to_engage_on_visible() -> void:
	var h := await _setup_brain()
	var brain: BotBrain = h["brain"]
	var target: Enemy = h["target"]
	var bb: BotBlackboard = h["bb"]
	bb.set_value("spawn_protection_left", 0.0)
	var engaged_at := -1
	var seen_engage := false
	for i in range(90):
		await _tick(brain)
		if brain.state == BotBrain.State.ENGAGE and not seen_engage:
			seen_engage = true
			engaged_at = _tick_count
			assert_eq(_fire_log.size(), 0,
					"ENGAGE 进入帧 fire_intent 应为 0（反应倒计时归零前不发）")
	assert_true(seen_engage, "视线内敌对 → hostile_visible → ENGAGE（90 帧驱动）")
	assert_same(brain.current_target, target, "current_target == 视线内目标")
	assert_true(_saw_state_change("PATROL", "ENGAGE"), "state_changed(PATROL→ENGAGE)")
	assert_gte(_fire_log.size(), 2,
			"归零后每 0.2s 节流持续发（1.5s 驱动 ≥2 发，实际 %d 发）" % _fire_log.size())
	var prev := -1
	for f0 in _fire_log:
		var f: Dictionary = f0
		assert_same(f["target"], target, "fire_intent 目标恒为 current_target")
		if prev >= 0:
			assert_gte(int(f["tick"]) - prev, 12, "节流：相邻发帧间隔 ≥0.2s（12 帧）")
		prev = int(f["tick"])
	assert_gte(prev - engaged_at, 18, "首发距 ENGAGE 进入 ≥0.3s（18 帧，REACTION_MIN）")


# ── T13-4：ENGAGE 失视（目标移出视线且无其他可见敌对）→ CHASE ──
func test_engage_to_chase_on_lost() -> void:
	var h := await _setup_brain()
	var brain: BotBrain = h["brain"]
	var target: Enemy = h["target"]
	var observer: Enemy = h["observer"]
	var bb: BotBlackboard = h["bb"]
	bb.set_value("spawn_protection_left", 0.0)
	await _drive(brain, 30)
	assert_eq(brain.state, BotBrain.State.ENGAGE, "前置：视线内 → ENGAGE")
	_make_box(Vector3(4, 3, 1), Vector3(0, 1.5, -5))  # 观察者与目标之间墙体
	await wait_physics_frames(2)  # 墙形状入空间（同帧 raycast 不可见）
	await _drive(brain, 30)  # 丢失相（≥1 节流周期）
	assert_eq(brain.state, BotBrain.State.CHASE, "失视且无其他可见敌对 → CHASE")
	assert_same(brain.current_target, target, "current_target 保持为丢失目标")
	assert_true(_saw_state_change("ENGAGE", "CHASE"), "state_changed(ENGAGE→CHASE)")
	var origin: Vector3 = bb.get_value("chase_origin", Vector3.INF)
	assert_lt(origin.distance_to(observer.global_position), 0.5,
			"chase_origin 记接敌位置（body 位置，容差 0.5）")


# ── T13-5：CHASE 追击超限（黑板 chase_origin 置远 >30m）→ ALERT ──
func test_chase_limit_returns_alert() -> void:
	var h := await _setup_brain()
	var brain: BotBrain = h["brain"]
	var observer: Enemy = h["observer"]
	var bb: BotBlackboard = h["bb"]
	bb.set_value("spawn_protection_left", 0.0)
	await _drive(brain, 30)
	assert_eq(brain.state, BotBrain.State.ENGAGE, "前置：视线内 → ENGAGE")
	_make_box(Vector3(4, 3, 1), Vector3(0, 1.5, -5))
	await wait_physics_frames(2)
	await _drive(brain, 30)
	assert_eq(brain.state, BotBrain.State.CHASE, "前置：失视 → CHASE")
	bb.set_value("chase_origin", observer.global_position + Vector3(31, 0, 0))
	await _tick(brain)
	assert_eq(brain.state, BotBrain.State.ALERT, "追击超限（自接敌位置 >30m）→ ALERT")
	assert_true(_saw_state_change("CHASE", "ALERT"), "state_changed(CHASE→ALERT)")


# ── T13-6：ENGAGE 弹匣 <30%（黑板 mag_frac 注入 0.2）→ RELOAD ──
func test_engage_to_reload_low_mag() -> void:
	var h := await _setup_brain()
	var brain: BotBrain = h["brain"]
	var bb: BotBlackboard = h["bb"]
	bb.set_value("spawn_protection_left", 0.0)
	await _drive(brain, 30)
	assert_eq(brain.state, BotBrain.State.ENGAGE, "前置：视线内 → ENGAGE")
	bb.set_value("mag_frac", 0.2)
	await _tick(brain)
	assert_eq(brain.state, BotBrain.State.RELOAD, "弹匣 <30% → RELOAD")
	assert_true(_saw_state_change("ENGAGE", "RELOAD"), "state_changed(ENGAGE→RELOAD)")


# ── T13-7：reaction_delay——seed 0 采样 ×50 ∈ [0.3,0.6]；seed 7 两次相同 ──
func test_reaction_delay_range() -> void:
	for i in range(50):
		var d := BotBrain.reaction_delay(0)
		assert_between(d, BotBrain.REACTION_MIN, BotBrain.REACTION_MAX,
				"seed 0 随机采样应 ∈ [0.3, 0.6]（第 %d 次 %.4f）" % [i, d])
	var a := BotBrain.reaction_delay(7)
	var b := BotBrain.reaction_delay(7)
	assert_eq(a, b, "seed 7 确定性：两次调用同值")
	assert_between(a, BotBrain.REACTION_MIN, BotBrain.REACTION_MAX,
			"seed 7 定值仍 ∈ [0.3, 0.6]（%.4f）" % a)


# ── T13-8：ENGAGE 血量 <30（黑板 hp 注入 20）→ RETREAT；超 8s → PATROL ──
func test_retreat_on_low_hp() -> void:
	var h := await _setup_brain()
	var brain: BotBrain = h["brain"]
	var bb: BotBlackboard = h["bb"]
	bb.set_value("spawn_protection_left", 0.0)
	await _drive(brain, 30)
	assert_eq(brain.state, BotBrain.State.ENGAGE, "前置：视线内 → ENGAGE")
	bb.set_value("hp", 20.0)
	await _tick(brain)
	assert_eq(brain.state, BotBrain.State.RETREAT, "hp <30 → RETREAT")
	assert_true(_saw_state_change("ENGAGE", "RETREAT"), "state_changed(ENGAGE→RETREAT)")
	# 超时口径：逐帧驱动直至离开 RETREAT（掩体到达在无 navmesh 下不可达 → 必走 8s 超时）
	var frames := 0
	while brain.state == BotBrain.State.RETREAT and frames < 600:
		await _tick(brain)
		frames += 1
	assert_eq(brain.state, BotBrain.State.PATROL, "RETREAT 超 8s → PATROL")
	assert_gte(frames, 480, "回 PATROL 应经 ≥8.0s 超时（实际 %.2fs）" % (frames / 60.0))
	assert_true(_saw_state_change("RETREAT", "PATROL"), "state_changed(RETREAT→PATROL)")
