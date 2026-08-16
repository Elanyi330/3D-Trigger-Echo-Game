# test/unit/test_bot_locomotion_path.gd
# M3.1 T2（2026-08-16）：BotLocomotion 路径跟随测试（TDD，先 RED 后 GREEN）。
# 目标：navmesh 寻路 + 途经点简化 + 前瞻转向 + 高度门 + 到达判定。
#   static 纯函数（simplify_path/approach_point/within_height_gate）脱离场景直接单测；
#   集成测试装配真实 L_M2（导航两轮迭代 + 链接注册链）驱动 bot 走完平地/登台路径。
# RED 锚：生产类 BotLocomotion 尚不存在——本脚本引用该类即编译失败，7 测试全部报错
#   （错误信息 = "Could not find type BotLocomotion" 类加载错误，即正确的 RED 失败原因）。
# 修复轮 1（2026-08-17）追加 T2-8：登台回归（高度门 navmesh 双锚口径）——
#   修复前该测试复现停摆（台面 navmesh y=1.0 对 body 物理 y=0 量出 1.0 > 0.72 误判
#   跳跃段 → 重寻路 ×2 → clear_target 站桩），修复后 GREEN。
extends GutTest

const LAYOUT := preload("res://Levels/M2_TDM/map_layout_v3.gd")

# arrived 信号计数（成员变量 + 方法连接——GDScript lambda 按值捕获局部变量，
# 局部 int 计数在 lambda 内自增不传播，实测假红：信号已发但计数恒 0）
var _arrived_count := 0


func _on_arrived() -> void:
	_arrived_count += 1


# ── 测试辅助 ──

## 装配 L_M2 场景 + 立即 queue_free 场景内 JumpRecorder（防测试帧污染
##   user://jump_training 人类语料——项目铁律）+ 等导航两轮迭代（迭代 id ≥ 基值 +2，
##   同 L_M2._create_nav_links_after_sync 口径）+ 再等 60 物理帧（54 链接注册余量，
##   call_deferred 异步链，L_M2 F4 教训）。返回已同步的场景实例。
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


## 北营地面点生成落定 Enemy：取距静止玩家最远点（玩家 1/10 随机点位，重叠会被去穿透
## 推开；玩家身体可挡 bot 走廊——T4 卡顿对策前取最远点防路径被玩家身体卡死）。
## 定位先于入树（T0 教训：入树后再设会陈旧形状一帧注册进物理空间）；返回时已落定。
func _spawn_bot_at_north_camp(l2: Node3D) -> Enemy:
	var player: Node3D = l2.get_node("Player")
	var spawn := Vector3.ZERO
	var best_d := -1.0
	for p0 in LAYOUT.camp_spawn_points(1):
		var p: Vector3 = p0
		var d := Vector2(p.x - player.global_position.x,
				p.z - player.global_position.z).length()
		if d > best_d:
			best_d = d
			spawn = p
	var enemy := Enemy.new()
	enemy.position = spawn
	add_child_autofree(enemy)
	await wait_physics_frames(25)  # 落定后再 set_target（brief 口径）
	return enemy


## loco 驱动：每 2 物理帧 tick（与生产物理帧节奏同构），≤max_frames 帧，
## arrived 即提前退出。返回 [推进帧数, arrived 计数]。
func _drive(loco: BotLocomotion, max_frames: int) -> Array:
	_arrived_count = 0
	loco.arrived.connect(_on_arrived)
	var frames := 0
	while frames < max_frames and _arrived_count == 0:
		loco.tick(1.0 / 60.0)
		await wait_physics_frames(2)
		frames += 2
	return [frames, _arrived_count]


# ── T2-1：L 形路径简化后保留拐点（拐点=方向变化点，误丢则直线切角穿墙）──
func test_simplify_keeps_corners() -> void:
	var out: PackedVector3Array = BotLocomotion.simplify_path(
			PackedVector3Array([Vector3(0, 0, 0), Vector3(5, 0, 0), Vector3(5, 0, 5)]))
	assert_true(out.has(Vector3(5, 0, 0)),
			"简化后必须保留拐点 (5,0,0)——丢拐点则路径直线切角穿墙（遍历器时代教训）")
	assert_true(out.has(Vector3(0, 0, 0)), "输出含首点")
	assert_true(out.has(Vector3(5, 0, 5)), "输出含尾点")


# ── T2-2：10m 直线 → 简化后相邻输出点间距 ≤ 1.0（稠密插值，含首尾）──
func test_simplify_dense_step() -> void:
	var out: PackedVector3Array = BotLocomotion.simplify_path(
			PackedVector3Array([Vector3(0, 0, 0), Vector3(10, 0, 0)]))
	assert_gt(out.size(), 1, "10m 直线应产出 ≥2 个点")
	for i in range(out.size() - 1):
		assert_lte(out[i].distance_to(out[i + 1]), 1.0 + 1e-4,
				"相邻输出点间距应 ≤ 1.0（点 %d→%d 实际 %.3f）"
				% [i, i + 1, out[i].distance_to(out[i + 1])])
	assert_eq(out[0], Vector3(0, 0, 0), "首点保留")
	assert_eq(out[out.size() - 1], Vector3(10, 0, 0), "尾点保留")


# ── T2-3：平路 + 一点 y 高 0.3 → 该高差点保留（坡道/台阶走面信息不丢）──
# 高差 0.3 ≥ SIMPLIFY_DY(0.2)；水平方向恒 +X 无拐点——保留只能由高差规则驱动。
func test_simplify_keeps_dy() -> void:
	var out: PackedVector3Array = BotLocomotion.simplify_path(
			PackedVector3Array([Vector3(0, 0, 0), Vector3(2, 0.3, 0), Vector3(4, 0, 0)]))
	assert_true(out.has(Vector3(2, 0.3, 0)),
			"y 差 ≥ 0.2 的点必须保留（坡道/台阶走面信息不丢）")


# ── T2-4：yaw=0、基准点在 -Z → 输出 (0, 1)（前分量 1，右分量 0）──
func test_approach_toward_point() -> void:
	var out: Vector2 = BotLocomotion.approach_point(
			Vector3.ZERO, 0.0, Vector3(0, 0, -5), Vector3(0, 0, -5))
	assert_almost_eq(out.x, 0.0, 1e-4, "正前方目标无侧向分量（实际 %.4f）" % out.x)
	assert_almost_eq(out.y, 1.0, 1e-4, "正前方目标前分量 = 1（实际 %.4f）" % out.y)


# ── T2-5：当前点近（水平距 <1.5）+ next_point 在侧面 → 输出含侧向分量 ──
# 前瞻转向（遍历器 fix 8 教训）：提前转向下一途经点，不绕最小转弯圆。
# 无前瞻时基准取当前点 (0,0,-0.5) → 输出 (0,1)；有前瞻时基准取 (-3,0,-0.5) →
# 本地右分量 = -3/√9.25 ≈ -0.99（左侧向）。
func test_approach_lookahead() -> void:
	var out: Vector2 = BotLocomotion.approach_point(
			Vector3.ZERO, 0.0, Vector3(0, 0, -0.5), Vector3(-3, 0, -0.5))
	assert_lt(out.x, -0.3, "前瞻转向：输出应含侧向分量（实际 x %.3f）" % out.x)
	assert_gt(out.y, 0.0, "前瞻转向：仍含前进分量（实际 y %.3f）" % out.y)


# ── T2-9：approach_point 非零 yaw 右手系投影（2026-08-17 M3.1 T3 修复轮 2 钉死）──
# T1 实测锚：yaw=π/2 → 本地前 = −basis.z = −X（yaw=0 → −Z）；由此本地前 =
# (−sin yaw, −cos yaw)，本地右 = basis.x = (cos yaw, −sin yaw)（yaw=π/2 → −Z）。
# 旧公式 fw=(sin yaw, −cos yaw) 仅在 yaw=0 成立——T3 RUNUP 转向暴露反跑后修正。
func test_approach_yaw_pi2_point_negx() -> void:
	var out: Vector2 = BotLocomotion.approach_point(
			Vector3.ZERO, PI / 2.0, Vector3(-5, 0, 0), Vector3(-5, 0, 0))
	assert_almost_eq(out.x, 0.0, 1e-4, "yaw=π/2、基准点 −X 在正前方：右分量 0（实际 %.4f）" % out.x)
	assert_almost_eq(out.y, 1.0, 1e-4, "yaw=π/2、基准点 −X 在正前方：前分量 1（实际 %.4f）" % out.y)


func test_approach_yaw_pi_point_posz() -> void:
	var out: Vector2 = BotLocomotion.approach_point(
			Vector3.ZERO, PI, Vector3(0, 0, 5), Vector3(0, 0, 5))
	assert_almost_eq(out.x, 0.0, 1e-4, "yaw=π、基准点 +Z 在正前方：右分量 0（实际 %.4f）" % out.x)
	assert_almost_eq(out.y, 1.0, 1e-4, "yaw=π、基准点 +Z 在正前方：前分量 1（实际 %.4f）" % out.y)


func test_approach_yaw_pi2_point_negz() -> void:
	var out: Vector2 = BotLocomotion.approach_point(
			Vector3.ZERO, PI / 2.0, Vector3(0, 0, -5), Vector3(0, 0, -5))
	assert_almost_eq(out.x, 1.0, 1e-4, "yaw=π/2、基准点 −Z 在正右方：右分量 1（实际 %.4f）" % out.x)
	assert_almost_eq(out.y, 0.0, 1e-4, "yaw=π/2、基准点 −Z 在正右方：前分量 0（实际 %.4f）" % out.y)


# ── T2-6：高度门边界——升程 0.72 内 true / 0.73 false ──
# T2 建门口径：navmesh 双锚。T3 修复轮 1（2026-08-17）：锚基准改「已消费途经点」
# ——签名参数化 prev_y/point_y（路径点对路径点，同为 navmesh 空间，面缝瞬态消除），
# 断言语义不变（0.72 内放行 / 0.73 触发），调用机械适配。边界断言直测纯函数
# （prev_y=0 基准）。
func test_height_gate_boundary() -> void:
	assert_true(BotLocomotion.within_height_gate(0.0, 0.72),
			"升程 0.72 ≤ HEIGHT_GATE → 门内放行")
	assert_false(BotLocomotion.within_height_gate(0.0, 0.73),
			"升程 0.73 > HEIGHT_GATE → 触发高度门")


# ── T2-7（集成）：真实 L_M2 导航装配 + bot 走完 ~20m 平地路径到达 ──
func test_follow_short_path() -> void:
	var l2 := await _assemble_l2()
	var enemy := await _spawn_bot_at_north_camp(l2)
	var map_rid: RID = l2.get_world_3d().navigation_map
	var loco := BotLocomotion.new()
	add_child_autofree(loco)
	loco.setup(enemy, map_rid)
	# 目标：北营正南 ~20m 平地（rim 北墙豁口绕行，全程地面无跳跃段——T2 只测路径跟随）
	var target := Vector3(0, 0, 5.5)
	loco.set_target(target)
	var drive := await _drive(loco, 600)
	assert_gt(drive[1], 0,
			"≤600 物理帧内应到达并发射 arrived（实际 %d 帧未到达，bot 位置 %s）"
			% [drive[0], enemy.global_position])
	var d_final := Vector2(enemy.global_position.x - target.x,
			enemy.global_position.z - target.z).length()
	assert_lt(d_final, 1.0, "到达时距目标水平距 < 1.0（实际 %.3f）" % d_final)


# ── T2-8（集成回归，修复轮 1）：北营 → 祭坛台面点，地面→台面 0.6 直边登台 ──
# 修复前 RED 锚：台面 navmesh y=1.0（物理 0.6 + 烘焙偏移 0.4）对 body 物理 y=0
# 量出 1.0 > 0.72 → 高度门误判跳跃段 → 重寻路 ×2 → clear_target 站桩，arrived 不发
# （审查者 v4 实证停摆机制）。修复后（navmesh 双锚）1.0−0.4=0.6 ≤ 0.72 放行，
# bot 经 step-up（STEP_MAX 0.62 ≥ 0.6）直边登台到达。
# 目标点选型（实测修正）：台心 (0,0.6,0) 被钟楼基座覆盖不在导航面上（投影 ~2.3m
# 超断言口径）；微台阶线上点 (0,0.6,2.5) 路径先经 0.3+0.3 微台阶面（navmesh 0.7）——
# 旧门在 body 爬升后检查（0.7/1.0 − 0.3/0.6 ≤ 0.72）不触发，RED 不成立（实测假绿）。
# (2.5,0.6,1.5) 在微台阶（x∈[-1,1]）以东：rim 豁口走廊直下直边 0.6，途经点
# 地面面(0.4)→台面(1.0) 无中间面，旧门 1.0−0=1.0 必触发——停摆确定性复现。
func test_follow_to_altar_platform() -> void:
	var l2 := await _assemble_l2()
	var enemy := await _spawn_bot_at_north_camp(l2)
	var map_rid: RID = l2.get_world_3d().navigation_map
	var loco := BotLocomotion.new()
	add_child_autofree(loco)
	loco.setup(enemy, map_rid)
	var target := Vector3(2.5, 0.6, 1.5)  # 祭坛台面（基座/斜板/坡道/微台阶投影外）
	loco.set_target(target)
	var drive := await _drive(loco, 600)
	assert_gt(drive[1], 0,
			"≤600 物理帧内应登台到达并发射 arrived（实际 %d 帧未到达，bot 位置 %s）"
			% [drive[0], enemy.global_position])
	var d_final := Vector2(enemy.global_position.x - target.x,
			enemy.global_position.z - target.z).length()
	assert_lt(d_final, 1.0, "到达时距目标水平距 < 1.0（实际 %.3f）" % d_final)
