# test/unit/test_bot_stuck_counter.gd
# M3.1 T4（2026-08-17）：卡顿对策测试（TDD，先 RED 后 GREEN）。
# 目标：滑墙切线轴（slide_axis）/ 踢面正压偏转（kick_turn_axis）/ 进展超时判定
# （progress_stalled）static 纯函数 + 卡死兜底集成（自定义笔墙围死 bot → 重寻路预算
# 耗尽 → clear_target 诚实放弃，arrived 不发、无无限循环）+ 退化跑道近静止放行。
# RED 锚：slide_axis/kick_turn_axis/progress_stalled/DEGEN_RUNWAY 尚不存在——调用即
#   运行时错误（Nonexistent function / Invalid get index），即正确的 RED 失败原因；
#   集成测试 4 在 T2/T3 逻辑下 bot 贴笔墙振荡永不清路（arrived 不发、路径不空）——
#   断言失败；集成测试 5 引用 DEGEN_RUNWAY 常量——RED 阶段同报错。
# 集成测试 tick 频率铁律（T3 审查教训）：驱动循环每物理帧 tick
#   （wait_physics_frames(1) + loco.tick(1.0/60.0)，生产口径 60Hz）。
extends GutTest

const LAYOUT := preload("res://Levels/M2_TDM/map_layout_v3.gd")

# arrived 信号计数（成员变量 + 方法连接——GDScript lambda 按值捕获局部变量不传播，
# T2 测试实测教训）
var _arrived_count := 0


func _on_arrived() -> void:
	_arrived_count += 1


# ── 测试辅助（T2 测试 7 / T3 测试同口径）──

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
## 物理空间）；25 帧落定后返回。
func _spawn_bot_at(pos: Vector3) -> Enemy:
	var enemy := Enemy.new()
	enemy.position = pos
	add_child_autofree(enemy)
	await wait_physics_frames(25)  # 落定后再 set_target（brief 口径）
	return enemy


## 围死笔墙（2026-08-17 M3.1 T4 测试专用）：4 面 3m 高 StaticBody3D 盒围成
## 3×3m 内院（层 1 世界几何、掩码 0）。笔墙在 navmesh 烘焙后运行时创建——
## navmesh 不知其存在 → set_target 路径直线穿墙（路径非空），bot 物理被挡，
## 贴墙振荡永无进展——卡死兜底测试的确定性卡死源（与 brief 例点 (0,0,35) 不同：
## 该点经 map_get_closest_point 投影落在营内开阔地，bot 走到即到达，不构成卡死）。
func _build_pen() -> void:
	var walls := [
		[Vector3(0, 1.5, 21), Vector3(4, 3, 1)],    # 北墙
		[Vector3(0, 1.5, 17), Vector3(4, 3, 1)],    # 南墙
		[Vector3(-2, 1.5, 19), Vector3(1, 3, 4)],   # 西墙
		[Vector3(2, 1.5, 19), Vector3(1, 3, 4)],    # 东墙
	]
	for w0 in walls:
		var w: Array = w0
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = w[1]
		shape.shape = box
		body.add_child(shape)
		body.position = w[0]
		add_child_autofree(body)


# ── T4-1：滑墙切线轴——与墙平行，handedness ±1 输出相反 ──
# 北墙（东-西走向）法向 (0,0,1)：切线 t = (n_z, 0, −n_x) = (1,0,0)（沿 X 与墙平行）。
# yaw=0（朝 −Z，本地前 = −Z）：切线转本地 = (1, 0)（前分量 0、侧分量 ±1）。
func test_slide_axis_parallel_to_wall() -> void:
	var plus: Vector2 = BotLocomotion.slide_axis(0.0, Vector3(0, 0, 1), 1)
	assert_almost_eq(plus.y, 0.0, 1e-4, "滑移轴与墙平行：前分量 ≈ 0（实际 %.4f）" % plus.y)
	assert_gt(absf(plus.x), 0.99, "滑移轴与墙平行：侧分量非零（实际 %.4f）" % plus.x)
	var minus: Vector2 = BotLocomotion.slide_axis(0.0, Vector3(0, 0, 1), -1)
	assert_almost_eq(minus.x, -plus.x, 1e-4,
			"handedness ±1 输出应相反（实际 +1=%.4f / −1=%.4f）" % [plus.x, minus.x])
	assert_almost_eq(minus.y, 0.0, 1e-4, "handedness −1 同样与墙平行（实际 %.4f）" % minus.y)
	# 非零 yaw 右手系投影自检（T3 修正口径：本地前 = (−sin yaw, −cos yaw)）：
	# yaw=π/2（朝 −X）时切线 +X 转本地 = 反向（前分量 −1）
	var yawed: Vector2 = BotLocomotion.slide_axis(PI / 2.0, Vector3(0, 0, 1), 1)
	assert_lt(yawed.y, -0.9, "yaw=π/2 时切线 (+X) 转本地应为反向（实际 %.4f）" % yawed.y)


# ── T4-2：踢面正压——目标正对墙内踢开离墙；平行目标不偏转 ──
# 接触法向用 Godot 口径（指向机体、离墙）：北墙 (0,0,−1)；目标方向 (0,0,1) 正对
# 墙内（n·d=−1 ≤ −0.7）→ 踢开方向 = 法向绕 +Y 向切线侧偏转（π/2 − KICK_NORMAL_TURN
# ≈ 0.37 rad，即偏离墙平面 1.2 rad）：本地前（= −Z = 离北墙）分量 > 0.5 + 侧向偏转。
# 目标方向与墙平行（n·d≈0）→ 不偏转，输出即正常前进（目标 +X → 本地 (1,0)）。
func test_kick_turn_departs_wall() -> void:
	var out: Vector2 = BotLocomotion.kick_turn_axis(
			0.0, Vector3(0, 0, -1), Vector3(0, 0, 1))
	assert_gt(out.y, 0.5,
			"踢开方向应含离墙分量（yaw=0 本地前 = −Z = 离北墙；实际 y %.3f，输出 %s）"
			% [out.y, out])
	assert_gt(absf(out.x), 0.1, "踢开方向应含侧向偏转分量（实际 %.3f）" % out.x)
	var straight: Vector2 = BotLocomotion.kick_turn_axis(
			0.0, Vector3(0, 0, -1), Vector3(1, 0, 0))
	assert_almost_eq(straight.x, 1.0, 1e-4, "平行目标不偏转：右分量 1（实际 %.4f）" % straight.x)
	assert_almost_eq(straight.y, 0.0, 1e-4, "平行目标不偏转：前分量 0（实际 %.4f）" % straight.y)


# ── T4-3：进展超时纯判定——连续无进展 8.1s 超时；中途有进展清零 ──
# progress_stalled(delta, moved, arrived_radius)：moved < 0.2 且距目标 > ARRIVE_RADIUS
# 时累加 delta，否则清零；返回累计 > PROGRESS_TIMEOUT(8.0)。60Hz 口径 8.0s ≈ 480 帧
# （浮点边界 ±1 帧裕量——480×1/60 恰在 8.0 边界）。距目标 ≤ ARRIVE_RADIUS 不累计
# （到达收敛区防误触）。
func test_progress_stalled_pure() -> void:
	var loco := BotLocomotion.new()
	add_child_autofree(loco)
	# 连续 8.1s 每帧 moved=0.1（无进展）且距目标 0.9（> ARRIVE_RADIUS）→ 超时 true
	var first_true := -1
	for i in 490:
		if loco.progress_stalled(1.0 / 60.0, 0.1, 0.9):
			first_true = i
			break
	assert_between(first_true, 478, 489,
			"连续无进展应 ~8.0s 超时（实际第 %d 帧）" % first_true)
	# 中途一帧 moved=0.5（有进展）→ 清零，继续 8.1s 无进展才再次 true
	assert_false(loco.progress_stalled(1.0 / 60.0, 0.5, 0.9),
			"moved=0.5 应清零累计并返回 false")
	first_true = -1
	for i in 490:
		if loco.progress_stalled(1.0 / 60.0, 0.1, 0.9):
			first_true = i
			break
	assert_between(first_true, 478, 489,
			"清零后继续无进展应再过 ~8.0s 才超时（实际第 %d 帧）" % first_true)
	# 距目标 ≤ ARRIVE_RADIUS（到达收敛区）→ 不累计（防近静止误触）
	loco._progress_t = 0.0
	assert_false(loco.progress_stalled(1.0 / 60.0, 0.0, 0.5),
			"距目标 0.5 ≤ 到达半径 → 不累计")


# ── T4-4（集成）：卡死兜底——笔墙围死 → 重寻路预算耗尽 → clear_target ──
# 装配 L_M2（T2 测试 7 口径）→ 北营南侧开阔地建笔墙（navmesh 不知其存在）→ bot
# 置内院中心 → set_target 墙外北侧点（路径直线穿墙非空）→ 推进 ≤900 物理帧
# （60Hz 生产口径，clear_target 即提前退出）：断言 arrived 不发、路径清空（诚实
# 放弃）、重寻路计数达 REPATH_LIMIT、bot 未逃出笔墙（行为佐证）、无无限循环
# （循环强制退出防挂死）。修复前（T2/T3 逻辑）bot 贴墙振荡永不清路——断言失败。
func test_stuck_bailout() -> void:
	var l2 := await _assemble_l2()
	_build_pen()
	var enemy := await _spawn_bot_at(Vector3(0, 0, 19))  # 笔墙内院中心
	var map_rid: RID = l2.get_world_3d().navigation_map
	var loco := BotLocomotion.new()
	add_child_autofree(loco)
	loco.setup(enemy, map_rid)
	_arrived_count = 0
	loco.arrived.connect(_on_arrived)
	loco.set_target(Vector3(0, 0, 24))  # 笔墙外北侧（营门豁口方向，navmesh 可达）
	assert_false(loco._path.is_empty(),
			"前置：笔墙不存在于 navmesh，路径应非空（直线穿墙）——实际 %s" % str(loco._path))
	var frames := 0
	while frames < 900:
		loco.tick(1.0 / 60.0)  # 生产口径：每物理帧 tick（60Hz，T3 审查教训）
		await wait_physics_frames(1)
		frames += 1
		if loco._path.is_empty() and _arrived_count == 0:
			break  # clear_target 已发生（提前退出；arrived 未发才退出）
	assert_eq(_arrived_count, 0,
			"卡死兜底应诚实放弃：arrived 不发（实际 %d 次，%d 帧，bot %s）"
			% [_arrived_count, frames, enemy.global_position])
	assert_true(loco._path.is_empty(),
			"≤900 物理帧内应 clear_target 清空路径（实际 %d 帧仍非空，bot %s）"
			% [frames, enemy.global_position])
	assert_gte(loco._repath_count, BotLocomotion.REPATH_LIMIT,
			"重寻路计数应达 REPATH_LIMIT 后放弃（实际 %d）" % loco._repath_count)
	assert_true(absf(enemy.global_position.x) < 1.8,
			"bot 应仍困于笔墙内院（|x| %.2f < 1.8）" % enemy.global_position.x)
	assert_lt(enemy.global_position.z, 20.9,
			"bot 应仍困于笔墙内院（z %.2f < 20.9）" % enemy.global_position.z)


# ── T4-5（集成）：退化跑道——0.5m 内目标近静止放行，无超时干扰 ──
# 目标水平距 0.5 < DEGEN_RUNWAY(0.6) → 卡顿对策豁免（不触发超时/滑墙），到达判定
# 正常收敛：≤120 物理帧 arrived 发射。修复前（T2/T3 逻辑）本测试引用 DEGEN_RUNWAY
# 常量即报错（RED 锚由 T4-1/2/3 与常量引用共同承担）。
func test_degen_runway_release() -> void:
	var l2 := await _assemble_l2()
	var enemy := await _spawn_bot_at(Vector3(0, 0, 25.5))  # 北营点
	var map_rid: RID = l2.get_world_3d().navigation_map
	var loco := BotLocomotion.new()
	add_child_autofree(loco)
	loco.setup(enemy, map_rid)
	_arrived_count = 0
	loco.arrived.connect(_on_arrived)
	loco.set_target(Vector3(0, 0, 25.0))  # 距 bot 0.5m 地面点
	assert_lt(Vector2(enemy.global_position.x, enemy.global_position.z)
			.distance_to(Vector2(0, 25.0)), BotLocomotion.DEGEN_RUNWAY,
			"前置：目标应落在退化跑道圆盘内（< DEGEN_RUNWAY）")
	var frames := 0
	while frames < 120 and _arrived_count == 0:
		loco.tick(1.0 / 60.0)
		await wait_physics_frames(1)
		frames += 1
	assert_gt(_arrived_count, 0,
			"≤120 物理帧内应到达（退化跑道近静止放行，无超时干扰；实际 %d 帧，bot %s）"
			% [frames, enemy.global_position])
