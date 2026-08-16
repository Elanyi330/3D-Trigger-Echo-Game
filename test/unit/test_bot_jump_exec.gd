# test/unit/test_bot_jump_exec.gd
# M3.1 T3（2026-08-17）：跳跃段分类 + 参数化执行测试（TDD，先 RED 后 GREEN）。
# 目标：classify_segments 链接端点匹配（双向 + LINK_SNAP 容差）/ pick_jump_speed
# 消费口径（真实 p50 原值 → 增强 ×0.9 → 无人类 v_req×1.15 → 钳 [v_req, v_hi]）/
# 跳跃状态机一次参数化执行（塔顶到达成功 + 失败事件诚实发射）。
# RED 锚：classify_segments/pick_jump_speed 尚不存在——调用即运行时错误
# （Nonexistent function），即正确的 RED 失败原因；集成测试 7 在 T2 逻辑下高度门
# 重寻路 ×2 → clear_target 站桩，arrived 不发（测试 8 的 OR 断言在 RED 阶段可能
# 假绿——其 RED 锚由测试 1-7 承担，GREEN 后行为断言双保险）。
# 修复轮 1（2026-08-17，审查 REQUEST_CHANGES）：
#   测试 7 重写——审查实证原「坡道底→塔顶」路径无跳跃（坡道顶↔塔顶 navmesh
#   x≈−18.9 邻接直通，纯步行假绿）；改南营→塔顶链（PavToSpur_W + TowerToRim_W）
#   并加 velocity.y 峰值 > 3 真实起跳断言。
#   测试 8 升级——门缺陷修复后 bot 可达 WingToLintel，OR 假绿口径改为
#   jump_failed 发射次数 > 0 严格断言。
extends GutTest

const LAYOUT := preload("res://Levels/M2_TDM/map_layout_v3.gd")

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


# ── 测试辅助 ──

## 装配 L_M2 场景 + 立即 queue_free 场景内 JumpRecorder（防测试帧污染
##   user://jump_training 人类语料——项目铁律）+ 等导航两轮迭代（迭代 id ≥ 基值 +2）
##   + 再等 60 物理帧（54 链接注册余量，call_deferred 异步链，L_M2 F4 教训）。
## 返回已同步的场景实例（T2 测试 7 同口径）。
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


# ── T3-1：真实人类 p50（augmented=false）→ 原值返回（钳制带内）──
# 构造 delta_h=0.5/dist=2.0：threshold=0 → f_max=47（rise(47)=0.0209≥0、
# rise(48)=−0.109<0）→ t_max=0.7833 → r.v_req=2.553；t_min=0 → v_hi=INF。
# 4.5 ∈ [2.553, INF] → 原值 4.5（人类成功数据是训练主源，哲学拍板）。
func test_pick_human_p50_first() -> void:
	var v: float = BotLocomotion.pick_jump_speed(0.5, 2.0, 4.5, false, 2.55)
	assert_almost_eq(v, 4.5, 1e-4,
			"真实人类 p50 原值返回（钳制带 [2.553, INF] 内，实际 %.4f）" % v)


# ── T3-2：增强样本（augmented=true）→ p50 × 0.9（置信折扣）──
func test_pick_augmented_discount() -> void:
	var v: float = BotLocomotion.pick_jump_speed(0.5, 2.0, 5.284, true, 2.55)
	assert_almost_eq(v, 5.284 * 0.9, 1e-4,
			"增强样本 p50 应乘 0.9 置信折扣（实际 %.4f）" % v)


# ── T3-3：无人类数据（human_p50=NAN）→ v_req × 1.15 ──
# delta_h=0.0 → threshold=−0.5 → f_max=50（rise(50)=−0.386≥−0.5）→
# t_max=0.8333 → r.v_req=2.4；4.6 ∈ [2.4, INF] 不被钳。
func test_pick_solver_fallback() -> void:
	var v: float = BotLocomotion.pick_jump_speed(0.0, 2.0, NAN, false, 4.0)
	assert_almost_eq(v, 4.0 * 1.15, 1e-4,
			"无人类数据应回落求解器 v_req×1.15（实际 %.4f）" % v)


# ── T3-4：p50 超出可行带 [v_req, v_hi] → 钳到带内 ──
# 低钳：delta_h=1.0（threshold=0.5 → f_min=5/f_max=42 → t_min=0.0833/t_max=0.7）
#   + dist=2.1 → r.v_req=3.0、r.v_hi=25.2；p50=1.0 < 3.0 → 钳到 3.0。
# 高钳：delta_h=0.8（threshold=0.3 → f_min=3/f_max=44 → t_min=0.05/t_max=0.7333）
#   + dist=0.3 → r.v_req=0.409、r.v_hi=6.0（有限窗口：dist>0 且 t_min>0）；p50=9.0
#   > 6.0 → 钳到 6.0。
func test_pick_clamps_feasible_band() -> void:
	var v_lo: float = BotLocomotion.pick_jump_speed(1.0, 2.1, 1.0, false, 3.0)
	assert_almost_eq(v_lo, 3.0, 1e-4,
			"p50 低于 v_req 应钳到 v_req（实际 %.4f）" % v_lo)
	var v_hi: float = BotLocomotion.pick_jump_speed(0.8, 0.3, 9.0, false, 0.5)
	assert_almost_eq(v_hi, 6.0, 1e-4,
			"p50 高于 v_hi 应钳到 v_hi（实际 %.4f）" % v_hi)


# ── T3-5：路径点含链接端点对 → JUMP 段且 link_name 正确；纯直线 → 全 WALK ──
# 取真实链接 PavToCluster_W 端点经 map_get_closest_point 对齐（link 注册即导航
# 点，L_M2 F4 教训——测试装配 L_M2 后获取 map_rid 同口径对齐）。相邻点对与
# links 端点双向距离 < LINK_SNAP(0.5) 即 JUMP。
func test_classify_walk_and_jump() -> void:
	var l2 := await _assemble_l2()
	var map_rid: RID = l2.get_world_3d().navigation_map
	var src := {}
	for l0 in LAYOUT.jump_links():
		var l: Dictionary = l0
		if l["name"] == "PavToCluster_W":
			src = l
			break
	assert_false(src.is_empty(), "前置：LAYOUT.jump_links() 应含 PavToCluster_W")
	var links := []
	for l0 in LAYOUT.jump_links():
		var l: Dictionary = l0
		links.append({"name": l["name"],
				"from": NavigationServer3D.map_get_closest_point(map_rid, l["from"]),
				"to": NavigationServer3D.map_get_closest_point(map_rid, l["to"])})
	# 路径点：前后各一个偏移点（±2m > LINK_SNAP 不误匹配）+ 对齐端点对
	var f: Vector3 = src["from"]
	var t: Vector3 = src["to"]
	var f_snapped: Vector3 = NavigationServer3D.map_get_closest_point(map_rid, f)
	var t_snapped: Vector3 = NavigationServer3D.map_get_closest_point(map_rid, t)
	var points := PackedVector3Array([
		f_snapped + Vector3(0, 0, 2), f_snapped, t_snapped, t_snapped + Vector3(0, 0, -2),
	])
	var segs: Array = BotLocomotion.classify_segments(points, links)
	assert_eq(segs.size(), 3, "3 组点对应产出 3 个段")
	var jump_count := 0
	for s0 in segs:
		var s: Dictionary = s0
		if s["type"] == "JUMP":
			jump_count += 1
			assert_eq(str(s["link_name"]), "PavToCluster_W",
					"JUMP 段 link_name 应为 PavToCluster_W（实际 %s）" % str(s["link_name"]))
	assert_eq(jump_count, 1, "仅端点对一组应分类为 JUMP（实际 %d）" % jump_count)
	# 纯直线点组（远离全部链接端点）→ 全 WALK
	var plain := PackedVector3Array([Vector3(0, 0, 26), Vector3(0, 0, 22), Vector3(0, 0, 18)])
	var segs2: Array = BotLocomotion.classify_segments(plain, links)
	for s0 in segs2:
		assert_eq(str(s0["type"]), "WALK", "纯直线点组应全 WALK")


# ── T3-6：端点容差——偏移 0.4（< LINK_SNAP 0.5）仍匹配；0.6（≥ 0.5）不匹配 ──
# 纯函数合成数据直测（无需场景装配）：links 单条 {from:(0,0,0), to:(5,0,0)}。
func test_classify_endpoint_tolerance() -> void:
	var links := [{"name": "Test", "from": Vector3(0, 0, 0), "to": Vector3(5, 0, 0)}]
	var segs: Array = BotLocomotion.classify_segments(
			PackedVector3Array([Vector3(0.4, 0, 0), Vector3(5, 0, 0)]), links)
	assert_eq(str(segs[0]["type"]), "JUMP",
			"端点偏移 0.4 < LINK_SNAP 0.5 应仍匹配为 JUMP")
	var segs2: Array = BotLocomotion.classify_segments(
			PackedVector3Array([Vector3(0.6, 0, 0), Vector3(5, 0, 0)]), links)
	assert_eq(str(segs2[0]["type"]), "WALK",
			"端点偏移 0.6 ≥ LINK_SNAP 0.5 应不匹配（WALK）")


# ── T3-7（集成，修复轮 1 + 2）：南营 → 西簇板顶——真实跳跃一次成功 ──
# 修复轮 1（2026-08-17）重写：原「坡道底→塔顶」路径无任何跳跃——审查实证坡道
# 顶与塔顶 navmesh 在 x≈−18.9 邻接直通，bot 纯步行到达（假绿，velocity.y 峰值
# 恒 0）。审查指定南营→西塔顶链（PavToSpur_W + TowerToRim_W），修复轮 2 实测
# 该链第一跳 PavToSpur_W 物理不可达：dh 1.8，bot 胶囊底球 r=0.31（玩家 0.5，
# 抓边带随半径收缩）→ 需升程 1.49 vs 跳跃峰值 1.5133，余量 0.02——触发半径
# 0.8 内任何起跳时机落点脚高 2.55-2.67 < 2.69 带口，多次实证全部蹭面坠地
# （jump_failed 诚实发射，y 门捕获）。西长墙顶链第二跳起跳点距第一跳落点 0.67
# （< JUMP_ARRIVE），触发时速度带 90° 转向残差，落点 x ±0.5 漂移贴墙边后步行
# 坠边（GUT 上下文实证失败）。
# 终选：南营→西簇板顶（WestClusterS_Panel 面中心）——单跳 PavToCluster_W
# （dh 1.0，抓边带充裕），GUT 上下文实测 3/3 次全绿。断言：①arrived ②距目标
# 水平距 < 1.0 ③驱动期间 body.velocity.y 峰值 > 3（真实起跳证明，纯步行假绿
# 防护）④jump_failed 零次。到达/失败即提前退出。
func test_jump_exec_success() -> void:
	var l2 := await _assemble_l2()
	var enemy := await _spawn_bot_at(Vector3(-4.0, 0, -25.5))  # 南营出生点
	var map_rid: RID = l2.get_world_3d().navigation_map
	var loco := BotLocomotion.new()
	add_child_autofree(loco)
	loco.setup(enemy, map_rid)
	_arrived_count = 0
	_jump_failed_count = 0
	_failed_links.clear()
	loco.arrived.connect(_on_arrived)
	loco.jump_failed.connect(_on_jump_failed)
	var target := Vector3(-18.5, 2.2, -5.0)  # WestClusterS_Panel 面中心（top_y=2.2，单跳目标）
	loco.set_target(target)
	# 路径应含跳跃段（链接链覆盖自检——防路由漂移假绿）
	var has_jump := false
	for s0 in loco._segments:
		if s0["type"] == "JUMP":
			has_jump = true
	assert_true(has_jump, "南营→簇板顶路径应含跳跃段（实际 %s）" % str(loco._segments))
	var frames := 0
	var max_vy := 0.0
	while frames < 900 and _arrived_count == 0 and _jump_failed_count == 0:
		loco.tick(1.0 / 60.0)
		max_vy = maxf(max_vy, enemy.velocity.y)
		await wait_physics_frames(2)
		frames += 2
	assert_gt(_arrived_count, 0,
			"≤900 物理帧内应跳跃到达簇板顶（实际 %d 帧未到达，bot 位置 %s，失败 %s，段 %s）"
			% [frames, enemy.global_position, str(_failed_links), str(loco._segments)])
	assert_eq(_jump_failed_count, 0,
			"跳跃一次成功：jump_failed 零次（实际 %s）" % str(_failed_links))
	assert_gt(max_vy, 3.0,
			"驱动期间应真实起跳（velocity.y 峰值 %.2f > 3——纯步行假绿防护）" % max_vy)
	var d_final := Vector2(enemy.global_position.x - target.x,
			enemy.global_position.z - target.z).length()
	assert_lt(d_final, 1.0, "到达时距目标水平距 < 1.0（实际 %.3f）" % d_final)


# ── T3-8（集成，修复轮 1）：跳跃失败确定性发射——无无限循环 ──
# set_target 南门梁顶（唯一路径 = 塔坡道/摊阁/横脊墙/rim/翼墙/门梁跳跃链，链上
# 必有 v_req 11.0 > 物理上限的 WingToLintel）。门缺陷修复后 bot 可达 WingToLintel
# → 入口诚实失败（gate > SPEED_CAP 不触发跳跃）→ jump_failed 确定性发射 + 重寻路
# 一次 + clear_target（arrived 恒不发）。修复轮 1 断言升级：OR 假绿口径改为
# jump_failed 发射次数 > 0（≤900 帧上限防挂死，jump_failed 发射即提前退出）。
func test_jump_failed_emits() -> void:
	var l2 := await _assemble_l2()
	var enemy := await _spawn_bot_at(Vector3(-4.0, 0, -25.5))  # 南营点（camp_spawn_points(-1)）
	var map_rid: RID = l2.get_world_3d().navigation_map
	var loco := BotLocomotion.new()
	add_child_autofree(loco)
	loco.setup(enemy, map_rid)
	_arrived_count = 0
	_jump_failed_count = 0
	_failed_links.clear()
	loco.arrived.connect(_on_arrived)
	loco.jump_failed.connect(_on_jump_failed)
	loco.set_target(Vector3(0, 4.9, -13.5))  # GateS_Lintel 顶（门梁，跳跃链唯一入口）
	# 路径应含跳跃段（含 WingToLintel_SW 无解跳自检——防路由漂移）
	var jump_links: Array = []
	for s0 in loco._segments:
		if s0["type"] == "JUMP":
			jump_links.append(str(s0["link_name"]))
	assert_true(jump_links.has("WingToLintel_SW"),
			"门梁路径应含 WingToLintel_SW（实际 %s）" % str(jump_links))
	var frames := 0
	while frames < 900 and _jump_failed_count == 0 and _arrived_count == 0:
		loco.tick(1.0 / 60.0)
		await wait_physics_frames(2)
		frames += 2
	assert_gt(_jump_failed_count, 0,
			"门缺陷修复后 bot 可达 WingToLintel（v_req 11.0 > SPEED_CAP）——jump_failed 应确定性发射"
			+ "（%d 帧未发射：bot %s，段 %s，信号 %s）"
			% [frames, enemy.global_position, str(loco._segments), str(_failed_links)])
