# test/unit/test_bot_brain_targeting.gd
# M3.3 T14（2026-08-17）：BotBrain 目标选择与巡逻测试（TDD，先 RED 后 GREEN）。
# 覆盖：PATROL 加权选点/驻点换点（2-4s 随机）、ALERT 前往听觉事件位置/无发现回
#   巡逻/新事件刷新、CHASE LKP 跟踪刷新/累计路径上限、ENGAGE 掩体重选（LOS 断点）、
#   目标死亡清目标回巡逻。
# 装配（禁止 mock 与反射 hack，T13 同口径）：GutTest 场景直建真实 Enemy 观察者/目标
#   + 真实 BotPerception/BotBlackboard/BotLocomotion（map_rid = 测试场景世界导航图，
#   无 navmesh 烘焙 → set_target 后路径恒空、不推进物理——最简真实装配口径）。
#   战术点默认 TacticalPoints.build_from_faces（T12 快照表）；掩体重选测试用构造点集
#   注入 _points——真实 TacticalPoints 实例的测试数据（非 mock）。
# 到达事件以 locomotion.arrived.emit() 真实信号驱动（无 navmesh 下物理到达不可达；
#   arrived 即决策层消费的真实接口）。感知 LKP / Brain 累计注入为测试侧状态注入口径
#   （同 T13 黑板键注入；非 mock 非反射）。
# 60Hz tick 铁律：brain.tick 每物理帧一次（1/60 delta）。
# RED 锚：T14 语义未实现——PATROL 走 nearest（无 patrol_target 黑板键）、ALERT 无
#   target_lkp/新事件刷新、CHASE 无 LKP 跟踪/累计路径、无掩体重选、无死亡清目标。
extends GutTest

const ENEMY_SCRIPT := preload("res://Levels/Enemy/Enemy.gd")
const JE := preload("res://Levels/M2_TDM/jump_edges.gd")

var _state_events: Array = []   # [{from: String, to: String}]（state_changed 记录）
var _tick_count := 0            # 每测试内单调 tick 计数（驻点区间断言基准）


func _on_state_changed(from: String, to: String) -> void:
	_state_events.append({"from": from, "to": to})


## GUT 同脚本实例跨测试复用——事件/计数必须逐测试清零（防跨测试事件泄漏）。
func before_each() -> void:
	_state_events.clear()
	_tick_count = 0


# ── 测试辅助 ──

# 盒构造器（同 test_bot_brain_hsm.gd 范式）：BoxShape3D StaticBody（Objects 层 1）
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


## 轻量真实装配：地面 + 观察者（enemy，朝 -Z）+ 可选视线内目标（friendly，正前
## 10m 无遮挡；visible=false 不生成目标——巡逻/警戒测试需无敌对可见）+
## 真实感知/黑板/移动 + 战术点（默认真实 build_from_faces；custom_points 非空时
## 构造点集注入真实 TacticalPoints 实例——掩体重选测试用）。
## 移动层 map_rid = 测试场景世界导航图（无 navmesh——set_target 后路径恒空不推进
## 物理，brief 允许的最简真实装配）；导航图首次同步等待同 T13 口径。
func _setup_brain(visible: bool = true, custom_points: Array = []) -> Dictionary:
	_make_floor()
	var observer := await _spawn_settled(Vector3(0, 1, 0), true)
	var target: Enemy = null
	if visible:
		target = await _spawn_settled(Vector3(0, 1, -10), false)
	observer.rotation.y = 0.0
	var per := BotPerception.new()
	add_child_autofree(per)
	per.setup(observer, observer.get_faction(), null)
	var bb := BotBlackboard.new()
	add_child_autofree(bb)
	# 导航图首次同步等待（同 L_M2 等待口径）：未同步前 map_get_closest_point
	# 报错（"before first map synchronization"）——BotLocomotion.setup 的链接对齐
	# 循环会触发。有界轮询直至同步。
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
	var tp: TacticalPoints
	if custom_points.is_empty():
		tp = TacticalPoints.build_from_faces(JE.faces())
	else:
		tp = TacticalPoints.new()
		tp._points = custom_points  # 真实实例测试数据注入（非 mock）
	var brain := BotBrain.new()
	add_child_autofree(brain)
	brain.state_changed.connect(_on_state_changed)
	brain.setup(observer, per, bb, loco, tp)
	return {"observer": observer, "target": target, "per": per, "bb": bb,
			"brain": brain, "loco": loco, "tp": tp}


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


# ── T14-1：PATROL 加权选点（weighted_pick）——locomotion 有目标且黑板
#    patrol_target.face 非空（目标 ∈ 战术点集）──
func test_patrol_picks_tactical_point() -> void:
	var h := await _setup_brain(false)
	var brain: BotBrain = h["brain"]
	var bb: BotBlackboard = h["bb"]
	var tp: TacticalPoints = h["tp"]
	var loco: BotLocomotion = h["loco"]
	bb.set_value("spawn_protection_left", 0.0)
	await _tick(brain)
	assert_eq(brain.state, BotBrain.State.PATROL, "出生保护结束 → PATROL")
	var pt: Variant = bb.get_value("patrol_target")
	if not (pt is Dictionary) or (pt as Dictionary).is_empty():
		fail_test("黑板 patrol_target 非空（PATROL 选点写键）")
		return
	var face: String = str((pt as Dictionary)["face"])
	var center: Vector3 = (pt as Dictionary)["center"]
	assert_ne(face, "", "patrol_target.face 非空")
	var found := false
	for p0 in tp._points:
		var p: Dictionary = p0
		if str(p["face"]) == face:
			found = true
			assert_eq(p["center"], center, "点目标 ∈ 战术点集（center 一致）")
			break
	assert_true(found, "patrol_target.face ∈ 战术点集")
	assert_eq(loco._target, center,
			"locomotion.set_target(点 center)——_target 直读真实实例状态")


# ── T14-2：到达 → 驻点 2-4s（随机）→ 换点（新点距旧点 ≥8m）──
func test_patrol_hold_and_reselect() -> void:
	var h := await _setup_brain(false)
	var brain: BotBrain = h["brain"]
	var bb: BotBlackboard = h["bb"]
	var observer: Enemy = h["observer"]
	var loco: BotLocomotion = h["loco"]
	bb.set_value("spawn_protection_left", 0.0)
	await _tick(brain)
	assert_eq(brain.state, BotBrain.State.PATROL, "前置：PATROL")
	var old_pt_v: Variant = bb.get_value("patrol_target")
	if not (old_pt_v is Dictionary) or (old_pt_v as Dictionary).is_empty():
		fail_test("前置：patrol_target 已写")
		return
	var old_pt: Dictionary = old_pt_v
	var old_face: String = str(old_pt["face"])
	var old_center: Vector3 = old_pt["center"]
	loco.arrived.emit()  # 真实信号驱动到达（无 navmesh 下物理到达不可达）
	observer.global_position = old_center  # 机体移至旧点（生产语义：到达即站在点上）
	await _tick(brain)  # 消费到达 → 驻点倒计时启动
	var hold_start := _tick_count
	var changed_at := -1
	var new_pt := {}
	for i in range(300):
		await _tick(brain)
		var pt: Dictionary = bb.get_value("patrol_target")
		if str(pt["face"]) != old_face:
			changed_at = _tick_count
			new_pt = pt
			break
	assert_gte(changed_at, 0, "驻点结束应换点")
	assert_between(changed_at - hold_start, 118, 244,
			"驻点时长 ∈ [2s, 4s]（120-240 帧，±缓冲）")
	assert_ne(str(new_pt["face"]), old_face, "新点 != 旧点（重 pick 排除当前点）")
	var d := Vector2((new_pt["center"] as Vector3).x - old_center.x,
			(new_pt["center"] as Vector3).z - old_center.z).length()
	assert_gte(d, 8.0 - 1e-4, "新点距旧点 ≥8m（weighted_pick MIN_PICK_DIST 过滤）")


# ── T14-3：heard_event(pos) → PATROL→ALERT + set_target ≈ pos（容差 <2.0）──
func test_alert_goes_to_lkp() -> void:
	var h := await _setup_brain(false)
	var brain: BotBrain = h["brain"]
	var bb: BotBlackboard = h["bb"]
	var per: BotPerception = h["per"]
	var loco: BotLocomotion = h["loco"]
	bb.set_value("spawn_protection_left", 0.0)
	await _tick(brain)
	assert_eq(brain.state, BotBrain.State.PATROL, "前置：PATROL")
	var pos := Vector3(10, 0, -10)
	per._push_noise_event("gunshot", pos, 50.0)
	await _tick(brain)
	assert_eq(brain.state, BotBrain.State.ALERT, "heard_event → ALERT")
	assert_true(_saw_state_change("PATROL", "ALERT"), "state_changed(PATROL→ALERT)")
	assert_eq(bb.get_value("alert_pos"), pos, "黑板 alert_pos == 事件位置")
	assert_lt(loco._target.distance_to(pos), 2.0,
			"set_target ≈ 事件位置（导航投影容差 <2.0）")
	assert_lt((bb.get_value("target_lkp") as Vector3).distance_to(pos), 2.0,
			"黑板 target_lkp == 前往位置（容差 <2.0）")


# ── T14-4：ALERT 到达无新事件 5s 超时 → PATROL；期间新事件 → 刷新位置 + 计时清零 ──
func test_alert_no_find_returns_patrol() -> void:
	var h := await _setup_brain(false)
	var brain: BotBrain = h["brain"]
	var bb: BotBlackboard = h["bb"]
	var per: BotPerception = h["per"]
	var loco: BotLocomotion = h["loco"]
	bb.set_value("spawn_protection_left", 0.0)
	await _tick(brain)
	per._push_noise_event("gunshot", Vector3(10, 0, -10), 50.0)
	await _tick(brain)
	assert_eq(brain.state, BotBrain.State.ALERT, "前置：ALERT")
	loco.arrived.emit()
	await _tick(brain)  # 消费到达 → 无发现计时启动
	await _drive(brain, 150)  # 2.5s（未超 5s）
	assert_eq(brain.state, BotBrain.State.ALERT, "2.5s 无新事件 → 仍 ALERT")
	# ALERT 中新事件：刷新 _alert_pos + 重 set_target + 计时清零
	var pos2 := Vector3(10, 0, 10)
	per._push_noise_event("gunshot", pos2, 50.0)
	await _tick(brain)
	assert_eq(brain.state, BotBrain.State.ALERT, "新事件不改变状态")
	assert_lt(loco._target.distance_to(pos2), 2.0, "新事件 → set_target 刷新（容差 <2.0）")
	loco.arrived.emit()
	await _tick(brain)  # 重新到达 → 计时重启
	await _drive(brain, 299)
	assert_eq(brain.state, BotBrain.State.ALERT,
			"计时清零后 299 帧（≈4.98s）未超 5s → 仍 ALERT")
	await _drive(brain, 20)
	assert_eq(brain.state, BotBrain.State.PATROL, "超 5s 无新事件 → PATROL")
	assert_true(_saw_state_change("ALERT", "PATROL"), "state_changed(ALERT→PATROL)")


# ── T14-5：CHASE 中 LKP 变化 >0.5m → set_target 刷新（跟踪目标最后位置）──
func test_chase_tracks_lkp() -> void:
	var h := await _setup_brain(true)
	var brain: BotBrain = h["brain"]
	var target: Enemy = h["target"]
	var per: BotPerception = h["per"]
	var loco: BotLocomotion = h["loco"]
	var bb: BotBlackboard = h["bb"]
	bb.set_value("spawn_protection_left", 0.0)
	await _drive(brain, 30)
	assert_eq(brain.state, BotBrain.State.ENGAGE, "前置：视线内 → ENGAGE")
	_make_box(Vector3(4, 3, 1), Vector3(0, 1.5, -5))  # 观察者与目标之间墙体
	await wait_physics_frames(2)  # 墙形状入空间（同帧 raycast 不可见）
	await _drive(brain, 30)  # 丢失相（≥1 节流周期）
	assert_eq(brain.state, BotBrain.State.CHASE, "前置：失视 → CHASE")
	assert_lt(loco._target.distance_to(target.global_position), 2.0,
			"CHASE 进入 set_target(进入时 LKP)")
	var new_lkp := Vector3(15, 0, -25)
	per._lkp[target] = {"pos": new_lkp, "invisible_t": 0.0}  # 测试侧感知状态注入（非 mock）
	await _tick(brain)
	assert_eq(brain.state, BotBrain.State.CHASE, "LKP 刷新不改变状态")
	assert_eq(loco._target, new_lkp, "LKP 变化 >0.5m → set_target 刷新")


# ── T14-6：追击上限（累计路径）——chase_origin 注入远处（直线 <30m）+
#    位移累计 >30 → ALERT（chase_origin 清空）──
func test_chase_limit_alert() -> void:
	var h := await _setup_brain(true)
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
	bb.set_value("chase_origin", observer.global_position + Vector3(20, 0, 0))
	brain._chase_distance = 31.0  # 测试侧累计注入（同 T13 黑板注入口径）
	await _tick(brain)
	assert_eq(brain.state, BotBrain.State.ALERT, "累计路径 >30m → ALERT")
	assert_true(_saw_state_change("CHASE", "ALERT"), "state_changed(CHASE→ALERT)")
	assert_eq(bb.get_value("chase_origin", Vector3.INF), Vector3.ZERO,
			"chase_origin 清空（CHASE 退出清理）")


# ── T14-7：ENGAGE 掩体重选——候选 ∈[8,15] + tier ≤ medium + 对敌 LOS 断点 →
#    取最近（墙隔断点胜出，开阔点/近点/高难点落选）──
func test_cover_reselection() -> void:
	# 构造点集（真实 TacticalPoints 实例测试数据，非 mock）：
	#   CoverA：距敌 9m + 墙隔断 → 合格（最近）
	#   CoverB：距敌 9m 开阔 → LOS 无断点，不合格
	#   CoverC：距敌 5m → 距离过滤，不合格
	#   CoverD：距敌 13.45m tier hard → tier 过滤，不合格
	#   CoverE：距敌 9.22m + 墙隔断 → 合格但更远（验证取最近）
	var pts := [
		{"face": "CoverA", "center": Vector3(9, 0, -10), "tier": "simple", "weight": 1.0},
		{"face": "CoverB", "center": Vector3(-9, 0, -10), "tier": "simple", "weight": 1.0},
		{"face": "CoverC", "center": Vector3(0, 0, -5), "tier": "simple", "weight": 1.0},
		{"face": "CoverD", "center": Vector3(9, 0, -20), "tier": "hard", "weight": 0.35},
		{"face": "CoverE", "center": Vector3(-9, 0, -12), "tier": "simple", "weight": 1.0},
	]
	var h := await _setup_brain(true, pts)
	var brain: BotBrain = h["brain"]
	var bb: BotBlackboard = h["bb"]
	var loco: BotLocomotion = h["loco"]
	# 掩体点与敌之间的隔断墙（x=±4.5 轴外，不挡观察者→目标视线（x=0 轴））
	_make_box(Vector3(0.5, 3, 4), Vector3(4.5, 1.5, -10))   # CoverA ↔ 敌
	_make_box(Vector3(0.5, 3, 4), Vector3(-4.5, 1.5, -11))  # CoverE ↔ 敌
	await wait_physics_frames(2)  # 墙形状入空间
	bb.set_value("spawn_protection_left", 0.0)
	await _drive(brain, 30)
	assert_eq(brain.state, BotBrain.State.ENGAGE, "前置：视线内 → ENGAGE")
	await _drive(brain, 380)  # ≥1 个掩体重选周期（3-6s，覆盖上限 6s）
	assert_eq(brain.state, BotBrain.State.ENGAGE, "目标持续可见 → 保持 ENGAGE")
	var cover: Variant = bb.get_value("cover_target")
	if not (cover is Dictionary) or (cover as Dictionary).is_empty():
		fail_test("重选应落在合格掩体点（黑板 cover_target 非空）")
		return
	assert_eq(str((cover as Dictionary)["face"]), "CoverA",
			"取最近合格点：有 LOS 断点且距敌 ∈[8,15]（开阔点/近点/高难点落选）")
	assert_eq(loco._target, pts[0]["center"], "set_target(掩体 center)")


# ── T14-8：目标死亡 → current_target 清空 → PATROL ──
func test_target_death_returns_patrol() -> void:
	var h := await _setup_brain(true)
	var brain: BotBrain = h["brain"]
	var target: Enemy = h["target"]
	var bb: BotBlackboard = h["bb"]
	bb.set_value("spawn_protection_left", 0.0)
	await _drive(brain, 30)
	assert_eq(brain.state, BotBrain.State.ENGAGE, "前置：视线内 → ENGAGE")
	assert_same(brain.current_target, target, "前置：current_target == 视线内目标")
	target.dead = true
	await _tick(brain)
	assert_eq(brain.current_target, null, "目标死亡 → current_target 清空")
	assert_eq(brain.state, BotBrain.State.PATROL, "目标死亡 → PATROL")
	assert_true(_saw_state_change("ENGAGE", "PATROL") or _saw_state_change("CHASE", "PATROL"),
			"state_changed(ENGAGE|CHASE→PATROL)（同帧失视可能先行 CHASE）")
