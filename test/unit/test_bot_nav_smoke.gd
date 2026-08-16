# test/unit/test_bot_nav_smoke.gd
# M3.1 T5（2026-08-17）：冒烟——bot 自主走完跳跃链接链登西塔顶。
# 目标：BotLocomotion（T2-T4 全部能力）从起点沿跳跃链接链到达 WestTower 顶面。
# 起点选型（路径探查实证，2026-08-17）：
#   南营出生点 → 路径含 PavToSpur_W（dh 1.8，bot 胶囊底球 r=0.31 抓边带需升程
#     1.49 vs 峰值 1.5133 近不可达，实测 jump_failed 坠地）——brief 铁律禁止；
#     TDD RED 已实证本测试在南营起点下正确失败（失败链接 ["PavToSpur_W"]）。
#   北营出生点 → 塔顶路径零跳跃段（坡道顶↔塔顶 navmesh x≈−18.9 邻接直通纯步行，
#     T3 修复轮 1 已证）——不满足「确认含链」，弃用。
#   西长墙 M 段顶面（WestWall_M，y=3.0）起点 → 路径含 TowerToLongWall_W 反向下跳
#     （dh −0.5，人类 p50 5.631）——含链且全链 bot 可达，3/3 实证到达
#     （brief「其它起点」授权口径）。
# 断言锚修正：塔顶面中心 (-18.5, 2.5, 0) 在塔顶箱侵蚀洞内（烘焙将 0.8×0.8 箱
#   放大 1.2×1.2 + agent 侵蚀 0.25 → 洞半宽 0.85）——非导航点，
#   map_get_closest_point 投影到洞缘（实测 -18.62, 2.8, -0.72），bot 停驻距面中心
#   1.24 > 1.0。断言锚改用运行时投影点（水平距 < 1.0，到达弹点半径 0.8 内恒成立）
#   + 最终位置落在 WestTower 面矩形内（登塔顶语义保持）。
# 驱动循环铁律（T3 审查教训）：每物理帧 tick（wait_physics_frames(1) +
#   loco.tick(1.0/60.0)，生产口径 60Hz）；到达/失败即提前退出。
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


# ── 测试辅助（T2 测试 7 / T3/T4 同口径）──

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
## 物理空间）；25 帧落定后再 set_target（brief 口径）。T5 起点 = 西长墙 M 段顶面
## （WestWall_M 中心 (-23, 1.5, 0) 尺寸 (1,3,11) → 顶面 y=3.0，z∈[-5.5,5.5] 与
## TowerToLongWall_W 起跳点 (-23, 3.0, 1.4) 同段，南向助跑后反向下跳入塔顶）。
func _spawn_bot_at(pos: Vector3) -> Enemy:
	var enemy := Enemy.new()
	enemy.position = pos
	add_child_autofree(enemy)
	await wait_physics_frames(25)  # 落定后再 set_target（brief 口径）
	return enemy


## 西塔顶面矩形查询（faces() 的 WestTower 条目 center/size——断言锚）。
func _west_tower_face() -> Dictionary:
	for f0 in JUMP_EDGES.faces():
		var f: Dictionary = f0
		if f["name"] == "WestTower":
			return f
	return {}


# ── T5-1（集成）：出生点走跳跃链接链登西塔顶——arrived + 停驻在塔顶面 ──
func test_bot_reaches_tower_top() -> void:
	var l2 := await _assemble_l2()
	var map_rid: RID = l2.get_world_3d().navigation_map
	var enemy := await _spawn_bot_at(Vector3(-23.0, 3.0, 3.0))  # 西长墙 M 段顶面
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
			float(face["center"].y))  # 塔顶面中心
	loco.set_target(target)
	# 路径探查（brief：确认含链）——含 ≥1 跳跃段防路由漂移假绿
	var jump_links: Array = []
	for s0 in loco._segments:
		var s: Dictionary = s0
		if s["type"] == "JUMP":
			jump_links.append(str(s["link_name"]))
	assert_false(jump_links.is_empty(),
			"起点→塔顶路径应含跳跃链接段（实际 %s）" % str(loco._segments))
	var snapped := NavigationServer3D.map_get_closest_point(map_rid, target)
	var frames := 0
	var max_vy := 0.0
	while frames < 5400 and _arrived_count == 0 and _jump_failed_count == 0:
		loco.tick(1.0 / 60.0)  # 生产口径：每物理帧 tick（60Hz，T3 审查教训）
		max_vy = maxf(max_vy, enemy.velocity.y)
		await wait_physics_frames(1)
		frames += 1
	assert_gt(_arrived_count, 0,
			"≤5400 物理帧内应走完跳跃链接链登塔顶（实际 %d 帧未到达，bot %s，失败链接 %s，段 %s）"
			% [frames, enemy.global_position, str(_failed_links), str(loco._segments)])
	assert_gt(max_vy, 3.0,
			"驱动期间应真实起跳（velocity.y 峰值 %.2f > 3——纯步行假绿防护）" % max_vy)
	# 到达停驻断言：距目标投影点水平距 < 1.0 + 落在 WestTower 面矩形内（面中心在
	# 塔顶箱侵蚀洞内非导航点，见文件头锚修正注释）
	var d_final := Vector2(enemy.global_position.x - snapped.x,
			enemy.global_position.z - snapped.z).length()
	assert_lt(d_final, 1.0, "到达时距目标投影点水平距 < 1.0（实际 %.3f）" % d_final)
	var c: Vector2 = face["center"]
	var s: Vector2 = face["size"]
	assert_true(absf(enemy.global_position.x - c.x) <= s.x * 0.5 \
			and absf(enemy.global_position.z - c.y) <= s.y * 0.5,
			"到达时应在 WestTower 顶面矩形内（bot %s）" % enemy.global_position)


# ── T5-2（集成）：链接链一次成功率——全程 jump_failed 计数 == 0 ──
func test_no_jump_failure_on_chain() -> void:
	var l2 := await _assemble_l2()
	var map_rid: RID = l2.get_world_3d().navigation_map
	var enemy := await _spawn_bot_at(Vector3(-23.0, 3.0, 3.0))  # 西长墙 M 段顶面
	var loco := BotLocomotion.new()
	add_child_autofree(loco)
	loco.setup(enemy, map_rid)
	_arrived_count = 0
	_jump_failed_count = 0
	_failed_links.clear()
	loco.arrived.connect(_on_arrived)
	loco.jump_failed.connect(_on_jump_failed)
	var face: Dictionary = _west_tower_face()
	var target := Vector3(float(face["center"].x), float(face["top_y"]),
			float(face["center"].y))
	loco.set_target(target)
	var jump_links: Array = []
	for s0 in loco._segments:
		var s: Dictionary = s0
		if s["type"] == "JUMP":
			jump_links.append(str(s["link_name"]))
	assert_false(jump_links.is_empty(),
			"起点→塔顶路径应含跳跃链接段（实际 %s）" % str(loco._segments))
	var frames := 0
	while frames < 5400 and _arrived_count == 0 and _jump_failed_count == 0:
		loco.tick(1.0 / 60.0)  # 生产口径：每物理帧 tick（60Hz，T3 审查教训）
		await wait_physics_frames(1)
		frames += 1
	assert_eq(_jump_failed_count, 0,
			"链接链一次成功率：全程 jump_failed 应零次（实际 %s，bot %s，%d 帧）"
			% [str(_failed_links), enemy.global_position, frames])
	assert_gt(_arrived_count, 0,
			"jump_failed 零次应与到达同证（实际 %d 帧未到达，失败链接 %s，bot %s）"
			% [frames, str(_failed_links), enemy.global_position])
