# test/unit/test_bot_weapon_logic.gd
# M3.3 T16（2026-08-17）：BotBrain 武器决策测试（TDD，先 RED 后 GREEN）。
# 覆盖（简报测试规格 8 条）：赶路切刀（PATROL 长路 + 无近敌 → switch_intent(2)；
#   敌对 LKP 10m → switch_intent(0)）、弹尽切手枪（ENGAGE + mag_frac ≤0.2 + 无掩体
#   + glock_frac>0 → switch_intent(1)；有掩体 → RELOAD 且不发 switch）、集群扔雷
#   （两敌对 LKP 间距 8m + 质心 15m → throw_intent(质心) + grenade_left 减一语义）、
#   近身刀人（敌对 1.5m → melee_intent + switch_intent(2)）、弹药箱寻路（reserve=0
#   → set_target 最近弹药箱 + ammo_box_target 键；到达清键）、意图幂等（同意图连续
#   两 tick 只发一次）。
# 装配（禁止 mock 与反射 hack，同 T13/T14 口径）：GutTest 场景直建真实 Enemy 观察者/
#   目标 + 真实 BotPerception/BotBlackboard/BotLocomotion（map_rid = 测试场景世界
#   导航图，无 navmesh 烘焙 → set_target 后路径恒空、不推进物理）+ 真实
#   TacticalPoints.build_from_faces。意图信号以真实 connect 记录；敌对 LKP 注入经
#   perception.lkp_updated 真实信号（T14 口径：测试侧感知状态注入——非 mock 非反射）；
#   到达事件以 locomotion.arrived.emit() 真实信号驱动（同 T14）。
# 60Hz tick 铁律：brain.tick 每物理帧一次（1/60 delta）。
# RED 锚：T16 语义未实现——无 switch_intent/throw_intent/melee_intent 发射、无
#   intent_* 黑板键、无弹药箱寻路（reserve=0 不改 locomotion 目标）。
extends GutTest

const ENEMY_SCRIPT := preload("res://Levels/Enemy/Enemy.gd")
const JE := preload("res://Levels/M2_TDM/jump_edges.gd")

var _switch_log: Array = []   # [{slot: int, tick: int}]（switch_intent 记录）
var _throw_log: Array = []    # [{pos: Vector3, tick: int}]（throw_intent 记录）
var _melee_log: Array = []    # [{target: Node, tick: int}]（melee_intent 记录）
var _tick_count := 0          # 每测试内单调 tick 计数


func _on_switch(slot: int) -> void:
	_switch_log.append({"slot": slot, "tick": _tick_count})


func _on_throw(pos: Vector3) -> void:
	_throw_log.append({"pos": pos, "tick": _tick_count})


func _on_melee(target: Node) -> void:
	_melee_log.append({"target": target, "tick": _tick_count})


## GUT 同脚本实例跨测试复用——事件/计数必须逐测试清零（防跨测试事件泄漏）。
func before_each() -> void:
	_switch_log.clear()
	_throw_log.clear()
	_melee_log.clear()
	_tick_count = 0


# ── 测试辅助 ──

# 盒构造器（同 test_bot_brain_targeting.gd 范式）：BoxShape3D StaticBody（Objects 层 1）
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
## 真实感知/黑板/移动 + 战术点（真实 build_from_faces）+ Brain（连
## switch_intent/throw_intent/melee_intent 记录）。
## 移动层 map_rid = 测试场景世界导航图（无 navmesh——set_target 后路径恒空不推进
## 物理，brief 允许的最简真实装配）；导航图首次同步等待同 T13/T14 口径。
func _setup_brain(visible: bool = true) -> Dictionary:
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
	var tp := TacticalPoints.build_from_faces(JE.faces())
	var brain := BotBrain.new()
	add_child_autofree(brain)
	brain.switch_intent.connect(_on_switch)
	brain.throw_intent.connect(_on_throw)
	brain.melee_intent.connect(_on_melee)
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


# ── T16-1：赶路切刀——PATROL + path_remaining=20 + 无近敌 → switch_intent(2)
#    发射且黑板 intent_switch==2 ──
func test_knife_rush_on_long_patrol() -> void:
	var h := await _setup_brain(false)
	var brain: BotBrain = h["brain"]
	var bb: BotBlackboard = h["bb"]
	bb.set_value("spawn_protection_left", 0.0)
	bb.set_value("path_remaining", 20.0)
	await _tick(brain)
	assert_eq(brain.state, BotBrain.State.PATROL, "前置：出生保护结束 → PATROL")
	assert_eq(_switch_log.size(), 1, "切刀意图发射一次（实际 %d）" % _switch_log.size())
	if _switch_log.is_empty():
		return
	assert_eq(_switch_log[0]["slot"], 2, "switch_intent(2)（切刀赶路）")
	assert_eq(bb.get_value("intent_switch"), 2, "黑板 intent_switch == 2")
	assert_eq(bb.get_value("weapon_slot"), 2, "黑板 weapon_slot == 2（意图即当前槽记录）")


# ── T16-2：持刀意图后注入敌对 LKP 10m → switch_intent(0)（切回 AK 主枪）──
func test_knife_back_to_rifle_near_enemy() -> void:
	var h := await _setup_brain(false)
	var brain: BotBrain = h["brain"]
	var bb: BotBlackboard = h["bb"]
	var per: BotPerception = h["per"]
	bb.set_value("spawn_protection_left", 0.0)
	bb.set_value("path_remaining", 20.0)
	await _tick(brain)
	assert_eq(_switch_log.size(), 1, "前置：切刀意图已发")
	assert_eq(_switch_log[0]["slot"], 2, "前置：switch_intent(2)")
	var marker := Node3D.new()
	add_child_autofree(marker)
	per.lkp_updated.emit(marker, Vector3(0, 0, -10), false)  # 真实信号注入敌对 LKP（T14 口径）
	await _tick(brain)
	assert_eq(_switch_log.size(), 2, "敌对进入 15m → 再发一次切回（实际 %d）" % _switch_log.size())
	if _switch_log.size() < 2:
		return
	assert_eq(_switch_log[1]["slot"], 0, "switch_intent(0)（切回 AK 主枪）")
	assert_eq(bb.get_value("intent_switch"), 0, "黑板 intent_switch == 0")


# ── T16-3：弹尽切手枪——ENGAGE + mag_frac=0.15 + 无掩体（cover_target 空）+
#    glock_frac=1.0 → switch_intent(1) 且不转 RELOAD ──
func test_pistol_on_low_mag_no_cover() -> void:
	var h := await _setup_brain(true)
	var brain: BotBrain = h["brain"]
	var bb: BotBlackboard = h["bb"]
	bb.set_value("spawn_protection_left", 0.0)
	await _drive(brain, 30)
	assert_eq(brain.state, BotBrain.State.ENGAGE, "前置：视线内 → ENGAGE")
	_switch_log.clear()
	bb.set_value("mag_frac", 0.15)
	bb.set_value("glock_frac", 1.0)
	await _tick(brain)
	assert_eq(brain.state, BotBrain.State.ENGAGE,
			"无掩体低弹匣 → 不转 RELOAD（留 ENGAGE 切手枪续战）")
	assert_eq(_switch_log.size(), 1, "切手枪意图发射一次（实际 %d）" % _switch_log.size())
	if _switch_log.is_empty():
		return
	assert_eq(_switch_log[0]["slot"], 1, "switch_intent(1)（切 Glock 续战）")
	assert_eq(bb.get_value("intent_switch"), 1, "黑板 intent_switch == 1")
	assert_eq(bb.get_value("weapon_slot"), 1, "黑板 weapon_slot == 1")


# ── T16-4：ENGAGE + mag_frac=0.15 + 掩体 3m（cover_target 注入）→ 无
#    switch_intent(1)，走 RELOAD（state 变）──
func test_reload_when_cover_and_low_mag() -> void:
	var h := await _setup_brain(true)
	var brain: BotBrain = h["brain"]
	var bb: BotBlackboard = h["bb"]
	bb.set_value("spawn_protection_left", 0.0)
	await _drive(brain, 30)
	assert_eq(brain.state, BotBrain.State.ENGAGE, "前置：视线内 → ENGAGE")
	brain._cover_target = {"face": "TestCover", "center": Vector3(3, 0, 0),
			"tier": "simple"}  # 测试侧掩体状态注入（T14 口径）
	_switch_log.clear()
	bb.set_value("mag_frac", 0.15)
	bb.set_value("glock_frac", 1.0)
	await _tick(brain)
	assert_eq(brain.state, BotBrain.State.RELOAD, "有掩体（3m 内）低弹匣 → RELOAD")
	assert_eq(_switch_log.size(), 0,
			"有掩体路径不发 switch_intent(1)（实际 %d）" % _switch_log.size())


# ── T16-5：集群扔雷——ALERT + 两敌对 LKP 间距 8m + 质心 15m + grenade_left=1 →
#    throw_intent(质心容差 0.5) + 黑板 intent_throw_pos + grenade_left 减一语义 ──
func test_cluster_grenade() -> void:
	var h := await _setup_brain(false)
	var brain: BotBrain = h["brain"]
	var bb: BotBlackboard = h["bb"]
	var per: BotPerception = h["per"]
	bb.set_value("spawn_protection_left", 0.0)
	await _tick(brain)
	per._push_noise_event("gunshot", Vector3(10, 0, -10), 50.0)
	await _tick(brain)
	assert_eq(brain.state, BotBrain.State.ALERT, "前置：听觉事件 → ALERT")
	var a := Node3D.new()
	var b := Node3D.new()
	add_child_autofree(a)
	add_child_autofree(b)
	bb.set_value("grenade_left", 1)
	per.lkp_updated.emit(a, Vector3(15, 0, -8), false)   # 真实信号注入敌对 LKP ×2
	per.lkp_updated.emit(b, Vector3(15, 0, -16), false)
	await _tick(brain)
	assert_eq(_throw_log.size(), 1, "集群 → throw_intent 一次（实际 %d）" % _throw_log.size())
	if _throw_log.is_empty():
		return
	var centroid := Vector3(15, 0, -12)
	assert_lt((_throw_log[0]["pos"] as Vector3).distance_to(centroid), 0.5,
			"throw_intent(质心)（容差 0.5）")
	assert_eq(bb.get_value("intent_throw_pos"), _throw_log[0]["pos"],
			"黑板 intent_throw_pos == 发射位置")
	assert_eq(bb.get_value("grenade_left"), 0, "M3.3 减一语义：grenade_left 1 → 0")
	assert_eq(bb.get_value("weapon_slot"), 3, "黑板 weapon_slot == 3（雷）")


# ── T16-6：近身刀人——敌对 1.5m → melee_intent(target) + switch_intent(2) ──
func test_melee_close_range() -> void:
	var h := await _setup_brain(true)
	var brain: BotBrain = h["brain"]
	var bb: BotBlackboard = h["bb"]
	var target: Enemy = h["target"]
	bb.set_value("spawn_protection_left", 0.0)
	target.global_position = Vector3(0, 1, -1.5)  # 敌对移至 1.5m（近身）
	await _drive(brain, 30)
	assert_eq(brain.state, BotBrain.State.ENGAGE, "前置：视线内 → ENGAGE")
	assert_eq(_melee_log.size(), 1, "melee_intent 发射一次（实际 %d）" % _melee_log.size())
	if _melee_log.is_empty():
		return
	assert_same(_melee_log[0]["target"], target, "melee_intent(target) == 近身敌对")
	assert_eq(bb.get_value("intent_melee_target"), target, "黑板 intent_melee_target == target")
	assert_true(not _switch_log.is_empty(), "近身刀人伴随 switch_intent 发射")
	assert_eq(_switch_log[-1]["slot"], 2, "switch_intent(2)（切刀语义）")
	assert_eq(bb.get_value("weapon_slot"), 2, "黑板 weapon_slot == 2")


# ── T16-7：弹药箱寻路——PATROL + reserve=0 → set_target(最近弹药箱) +
#    ammo_box_target 非空；到达 → 清键 ──
func test_ammo_box_routing() -> void:
	var h := await _setup_brain(false)
	var brain: BotBrain = h["brain"]
	var bb: BotBlackboard = h["bb"]
	var loco: BotLocomotion = h["loco"]
	bb.set_value("spawn_protection_left", 0.0)
	await _tick(brain)
	assert_eq(brain.state, BotBrain.State.PATROL, "前置：PATROL")
	bb.set_value("reserve", 0)
	await _tick(brain)
	var box: Variant = bb.get_value("ammo_box_target")
	if not (box is Dictionary) or (box as Dictionary).is_empty():
		fail_test("弹药箱寻路：黑板 ammo_box_target 非空")
		return
	assert_eq((box as Dictionary)["pos"], Vector3(2.8, 3.0, 0.0),
			"最近弹药箱 = CorridorE（表序首个最小者——距 body 2.8m 并列最小）")
	assert_eq(loco._target, Vector3(2.8, 3.0, 0.0), "locomotion.set_target(弹药箱点)")
	loco.arrived.emit()  # 真实信号驱动到达（无 navmesh 下物理到达不可达）
	await _tick(brain)
	var box2: Variant = bb.get_value("ammo_box_target")
	assert_true((box2 is Dictionary) and (box2 as Dictionary).is_empty(),
			"到达 → 清 ammo_box_target（M3.4 接线拾取）")


# ── T16-8：意图幂等——同意图连续两 tick 只发一次（信号计数不变）──
func test_intent_idempotent() -> void:
	var h := await _setup_brain(false)
	var brain: BotBrain = h["brain"]
	var bb: BotBlackboard = h["bb"]
	bb.set_value("spawn_protection_left", 0.0)
	bb.set_value("path_remaining", 20.0)
	await _tick(brain)
	await _tick(brain)
	assert_eq(_switch_log.size(), 1,
			"同意图（切刀 2）连续两 tick 只发一次（实际 %d）" % _switch_log.size())
	assert_eq(bb.get_value("intent_switch"), 2, "黑板 intent_switch 保持 2")
