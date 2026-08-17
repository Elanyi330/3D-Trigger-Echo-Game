# test/unit/test_bot_jump_reverse.gd
# M3.3 T11（2026-08-17）：前置修正三件测试（TDD，先 RED 后 GREEN）——
#   反向链接方向性（directed_edge_params：反向 delta_h 取负 + human p50 失效）
#   触发位置约束（trigger_zone_ok：方向感知起飞区 + 无条目回退圆盘）
#   landing_zone 方向感知（landed_zone_ok：反向落区 = takeoff_zone 侧）
#   + 两条集成回归（测试 5 = T5 冒烟反向路径、测试 6 = T3 测试 7 正向路径）。
# RED 锚：directed_edge_params / trigger_zone_ok / landed_zone_ok 尚不存在——
#   调用即运行时错误（Nonexistent function），即正确 RED 失败原因（测试 1-4）。
#   集成测试 5/6 的 RED 由测试 1-4 承担（T3 测试 7 RED 同口径——修复前旧逻辑下
#   反向跳靠 LAND_TOLERANCE 侥幸仍可到达，无法单靠行为断言造 RED）。
# 回归锚（GREEN 后）：T5 冒烟反向跳修复后参数正确（不再靠 LAND_TOLERANCE 侥幸——
#   方向感知落区 zone 参与判定）；T3 正向跳不受影响（LAND_TOLERANCE 回退口径保留）。
extends GutTest

const JUMP_EDGES := preload("res://Levels/M2_TDM/jump_edges.gd")

# arrived/jump_failed 信号计数（成员变量 + 方法连接——GDScript lambda 按值捕获
# 局部变量不传播，T2 测试实测教训）
var _arrived_count := 0
var _jump_failed_count := 0
var _failed_links: Array = []


func _on_arrived() -> void:
	_arrived_count += 1


func _on_jump_failed(link_name: String) -> void:
	_jump_failed_count += 1
	_failed_links.append(link_name)


# ── 测试辅助（T3/T5 同口径）──

## 装配 L_M2 场景 + 立即 queue_free 场景内 JumpRecorder（防测试帧污染
##   user://jump_training 人类语料——项目铁律）+ 等导航两轮迭代（迭代 id ≥ 基值 +2）
##   + 再等 60 物理帧（54 链接注册余量，call_deferred 异步链，L_M2 F4 教训）。
func _assemble_l2() -> Node3D:
	var l2: Node3D = load("res://Levels/M2_TDM/L_M2.tscn").instantiate()
	add_child_autofree(l2)
	var recorder: Node = l2.get_node_or_null("JumpRecorder")
	assert_not_null(recorder, "前置：L_M2._ready 应创建 JumpRecorder 子节点")
	if recorder:
		recorder.queue_free()
	var map_rid: RID = l2.get_world_3d().navigation_map
	var base_iter := NavigationServer3D.map_get_iteration_id(map_rid)
	var synced := false
	for i in 120:
		await wait_physics_frames(1)
		if NavigationServer3D.map_get_iteration_id(map_rid) >= base_iter + 2:
			synced = true
			break
	assert_true(synced, "导航地图应在 120 帧内完成两轮迭代")
	await wait_physics_frames(60)
	return l2


## 定点生成落定 Enemy：定位先于入树（T0 教训：入树后再设会陈旧形状一帧注册进
## 物理空间）；25 帧落定后返回（brief 口径）。
func _spawn_bot_at(pos: Vector3) -> Enemy:
	var enemy := Enemy.new()
	enemy.position = pos
	add_child_autofree(enemy)
	await wait_physics_frames(25)  # 落定后再 set_target（brief 口径）
	return enemy


## 西塔顶面矩形查询（faces() 的 WestTower 条目 center/top_y——测试 5 目标锚，
## T5 冒烟同口径）。
func _west_tower_face() -> Dictionary:
	for f0 in JUMP_EDGES.faces():
		var f: Dictionary = f0
		if f["name"] == "WestTower":
			return f
	return {}


# ── T11-1：反向穿越 delta_h 取负（真实数据集条目 TowerToRim_W，dh 0.5）──
func test_reverse_delta_h_negated() -> void:
	var edge: Dictionary = BotLocomotion._ensure_dataset().get("TowerToRim_W")
	assert_false(edge.is_empty(), "前置：数据集应含 TowerToRim_W 条目（dh 0.5）")
	var rev: Dictionary = BotLocomotion.directed_edge_params(edge, false)
	assert_almost_eq(float(rev["delta_h"]), -0.5, 1e-4,
			"反向穿越 delta_h 应取负（实际 %.4f）" % float(rev["delta_h"]))
	var fwd: Dictionary = BotLocomotion.directed_edge_params(edge, true)
	assert_almost_eq(float(fwd["delta_h"]), 0.5, 1e-4,
			"正向穿越 delta_h 应取原值（实际 %.4f）" % float(fwd["delta_h"]))


# ── T11-2：反向 human p50 失效——NAN + augmented=false（T5 审查结论）──
func test_reverse_p50_fallback() -> void:
	var edge: Dictionary = BotLocomotion._ensure_dataset().get("TowerToRim_W")
	var rev: Dictionary = BotLocomotion.directed_edge_params(edge, false)
	assert_true(is_nan(float(rev["human_p50"])),
			"反向 human_p50 应为 NAN（数据集 human 为正向校准，反向 p50 无效——T5 审查结论）")
	assert_false(bool(rev["augmented"]),
			"反向 augmented 应恒 false（走无真实回退链 v_req×1.15）")
	var fwd: Dictionary = BotLocomotion.directed_edge_params(edge, true)
	assert_false(is_nan(float(fwd["human_p50"])),
			"正向 human_p50 应保留（实际 %s）" % str(fwd["human_p50"]))
	assert_almost_eq(float(fwd["human_p50"]), 4.919, 1e-4,
			"正向 p50 原值 4.919（数据集锚，实际 %.4f）" % float(fwd["human_p50"]))


# ── T11-3：触发位置窗——zone 内（膨胀 0.5）允许 / zone 外拒绝 / 反向取
#   landing_zone 侧 / 无条目回退距 seg.from 水平距 ≤ JUMP_ARRIVE(0.8) 圆盘 ──
func test_trigger_zone_gate() -> void:
	var edge := {"takeoff_zone": {"center": {"x": 0.0, "z": 0.0},
			"size": {"x": 1.0, "z": 1.0}},
			"landing_zone": {"center": {"x": 10.0, "z": 0.0},
			"size": {"x": 1.0, "z": 1.0}}}
	var seg_from := Vector3(0, 0, 0)
	assert_true(BotLocomotion.trigger_zone_ok(edge, true, Vector3(0.9, 0, 0.9), seg_from),
			"zone 内点（膨胀 0.5 内）应允许触发")
	assert_false(BotLocomotion.trigger_zone_ok(edge, true, Vector3(1.2, 0, 0), seg_from),
			"zone 外点（膨胀 0.5 外，x 超界）应拒绝触发")
	assert_false(BotLocomotion.trigger_zone_ok(edge, true, Vector3(0, 0, -1.2), seg_from),
			"zone 外点（z 超界）应拒绝触发")
	assert_true(BotLocomotion.trigger_zone_ok(edge, false, Vector3(10.4, 0, 0), seg_from),
			"反向穿越起飞侧 = landing_zone（方向感知取 zone）")
	var from := Vector3(5, 0, 0)
	assert_true(BotLocomotion.trigger_zone_ok({}, true, Vector3(5.79, 0, 0), from),
			"无条目回退：距 seg.from 水平距 0.79 ≤ 0.8 应允许")
	assert_false(BotLocomotion.trigger_zone_ok({}, true, Vector3(5.81, 0, 0), from),
			"无条目回退：距 seg.from 水平距 0.81 > 0.8 应拒绝")


# ── T11-4：landing_zone 方向感知——正向落 landing_zone / 反向落 takeoff_zone ──
# 合成小 zone 边条目（两 zone 不重叠）：forward=true → landing_zone 侧；
# forward=false → takeoff_zone 侧（反向穿越落点 = 注册 from 侧）。
func test_landing_zone_direction_aware() -> void:
	var edge := {"takeoff_zone": {"center": {"x": 0.0, "z": 0.0},
			"size": {"x": 1.0, "z": 1.0}},
			"landing_zone": {"center": {"x": 10.0, "z": 0.0},
			"size": {"x": 1.0, "z": 1.0}}}
	assert_true(BotLocomotion.landed_zone_ok(edge, true, Vector3(10.0, 0, 0.5)),
			"正向落 landing_zone 内 → true")
	assert_false(BotLocomotion.landed_zone_ok(edge, true, Vector3(0.0, 0, 0.0)),
			"正向落 takeoff_zone 内（非落区）→ false")
	assert_true(BotLocomotion.landed_zone_ok(edge, false, Vector3(0.0, 0, 0.0)),
			"反向落 takeoff_zone 内 → true（方向感知）")
	assert_false(BotLocomotion.landed_zone_ok(edge, false, Vector3(10.0, 0, 0.0)),
			"反向落 landing_zone 内 → false（方向感知）")


# ── T11-5（集成）：T5 冒烟同款路径——西长墙 M 顶 (-23,3.0,3.0) → 塔顶反向跳 ──
# 修复前该跳靠 LAND_TOLERANCE 侥幸通过（zone 查错侧恒不匹配）；修复后反向参数
# 正确（dh 取负、p50 走 v_req×1.15 无真实回退链）+ 方向感知落区参与判定。
# 断言：①arrived ②vy 峰值 > 3（真实起跳）③jump_failed 零次（T5 同口径）。
func test_reverse_jump_integration() -> void:
	var l2 := await _assemble_l2()
	var map_rid: RID = l2.get_world_3d().navigation_map
	var enemy := await _spawn_bot_at(Vector3(-23.0, 3.0, 3.0))  # 西长墙 M 段顶面（T5 同款起点）
	var loco := BotLocomotion.new()
	add_child_autofree(loco)
	loco.setup(enemy, map_rid)
	_arrived_count = 0
	_jump_failed_count = 0
	_failed_links.clear()
	loco.arrived.connect(_on_arrived)
	loco.jump_failed.connect(_on_jump_failed)
	var face: Dictionary = _west_tower_face()
	assert_false(face.is_empty(), "前置：faces() 应含 WestTower 面")
	var target := Vector3(float(face["center"].x), float(face["top_y"]),
			float(face["center"].y))  # 塔顶面中心（T5 同款目标）
	loco.set_target(target)
	# 路径应含 TowerToLongWall_W 反向跳（防路由漂移假绿）
	var jump_links: Array = []
	for s0 in loco._segments:
		var s: Dictionary = s0
		if s["type"] == "JUMP":
			jump_links.append(str(s["link_name"]))
	assert_true(jump_links.has("TowerToLongWall_W"),
			"起点→塔顶路径应含 TowerToLongWall_W 反向跳（实际 %s）" % str(jump_links))
	var frames := 0
	var max_vy := 0.0
	while frames < 5400 and _arrived_count == 0 and _jump_failed_count == 0:
		loco.tick(1.0 / 60.0)  # 生产口径：每物理帧 tick（60Hz，T3 审查教训）
		max_vy = maxf(max_vy, enemy.velocity.y)
		await wait_physics_frames(1)
		frames += 1
	assert_gt(_arrived_count, 0,
			"≤5400 物理帧内应反向跳到达塔顶（实际 %d 帧未到达，bot %s，失败 %s，段 %s）"
			% [frames, enemy.global_position, str(_failed_links), str(loco._segments)])
	assert_gt(max_vy, 3.0,
			"驱动期间应真实起跳（velocity.y 峰值 %.2f > 3——纯步行假绿防护）" % max_vy)
	assert_eq(_jump_failed_count, 0,
			"反向参数修正后 jump_failed 零次（实际 %s）" % str(_failed_links))


# ── T11-6（集成）：T3 测试 7 路径——RampTopToCorridor_W 正向跳不回归 ──
# 起点西坡道顶近塔点 → 回廊西南角。正向参数与 T3 原口径一致（dh=0 原值、
# human=null 走 v_req×1.15）；触发位置窗取 takeoff_zone（起点/触发点均在
# zone 内）；落点贴回廊西缘（zone 外）靠 LAND_TOLERANCE 回退口径收敛——
# T3 原口径保留的必要性即此。
func test_forward_jump_regression() -> void:
	var l2 := await _assemble_l2()
	var map_rid: RID = l2.get_world_3d().navigation_map
	var enemy := await _spawn_bot_at(Vector3(-4.5, 3.0, -2.5))  # 西坡道顶近塔点（T3 测试 7 同款）
	var loco := BotLocomotion.new()
	add_child_autofree(loco)
	loco.setup(enemy, map_rid)
	_arrived_count = 0
	_jump_failed_count = 0
	_failed_links.clear()
	loco.arrived.connect(_on_arrived)
	loco.jump_failed.connect(_on_jump_failed)
	var target := Vector3(-2.5, 3.0, -2.0)  # 回廊西南角（RampTopToCorridor_W 落点）
	loco.set_target(target)
	# 路径应含跳跃段（防路由漂移假绿）
	var has_jump := false
	for s0 in loco._segments:
		if s0["type"] == "JUMP":
			has_jump = true
	assert_true(has_jump, "坡道顶→回廊路径应含跳跃段（实际 %s）" % str(loco._segments))
	var frames := 0
	var max_vy := 0.0
	while frames < 900 and _arrived_count == 0 and _jump_failed_count == 0:
		loco.tick(1.0 / 60.0)  # 生产口径：每物理帧 tick（60Hz）
		max_vy = maxf(max_vy, enemy.velocity.y)
		await wait_physics_frames(1)
		frames += 1
	assert_gt(_arrived_count, 0,
			"≤900 物理帧内应正向跳到达回廊（实际 %d 帧未到达，bot %s，失败 %s，段 %s）"
			% [frames, enemy.global_position, str(_failed_links), str(loco._segments)])
	assert_eq(_jump_failed_count, 0,
			"正向跳不回归：jump_failed 零次（实际 %s）" % str(_failed_links))
	assert_gt(max_vy, 3.0,
			"驱动期间应真实起跳（velocity.y 峰值 %.2f > 3——纯步行假绿防护）" % max_vy)
