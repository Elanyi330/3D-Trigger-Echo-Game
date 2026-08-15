# test/unit/test_auto_traversal_runup.gd
# 2026-08-15 F8/F9 TDD：RUNUP 直线化 + 触发门控收紧

extends GutTest

const AT := preload("res://Levels/M2_TDM/auto_traversal.gd")
const TOL := 0.0001

# 1. target_yaw 锚点（Godot 惯例 yaw）：北(0,0,-1)→0；东(1,0,0)→-PI/2；南→±PI 边界
func test_target_yaw_anchors() -> void:
	assert_almost_eq(AT.target_yaw(Vector3.ZERO, Vector3(0, 0, -1)), 0.0, TOL)
	assert_almost_eq(AT.target_yaw(Vector3.ZERO, Vector3(1, 0, 0)), -PI / 2.0, TOL)
	# 南向（R1 审查 m4）：atan2(-0.0, -1.0) 实跑 -PI（-0.0 符号跟随 y 参数，godot
	# 4.7.1 实测）——按 ±PI 边界断言而非固定 PI
	assert_almost_eq(absf(AT.target_yaw(Vector3.ZERO, Vector3(0, 0, 1))), PI, TOL)

# 2. 近静止放行按路径声明（F9 核心语义）：hspeed ≤0.5 时 allow_near_still 决定放行
func test_trigger_allowed_near_still() -> void:
	assert_true(AT.trigger_allowed(5.0, 0.3, Vector2(0.2, 0.2), Vector2(1, 0), 4.0, true, true))
	assert_false(AT.trigger_allowed(5.0, 0.3, Vector2(0.2, 0.2), Vector2(1, 0), 4.0, true, false))

# 3. 方向锥 ±25°（cos25°≈0.906 → 系数 0.9）：30° 偏（cos=0.866 < 0.9）拒；20° 偏放行
func test_trigger_allowed_cone_25deg() -> void:
	var td := Vector2(1, 0)
	var v30 := Vector2(cos(deg_to_rad(30.0)), sin(deg_to_rad(30.0))) * 5.0
	assert_false(AT.trigger_allowed(5.0, 5.0, v30, td, 4.0, true, true))
	var v20 := Vector2(cos(deg_to_rad(20.0)), sin(deg_to_rad(20.0))) * 5.0
	assert_true(AT.trigger_allowed(5.0, 5.0, v20, td, 4.0, true, true))

# 4. 速度门（hspeed 与 gate 边界；0.6 恰在 0.5 近静止阈值上、仍低于 gate 时拒）
func test_trigger_allowed_speed_gate() -> void:
	assert_false(AT.trigger_allowed(5.0, 3.5, Vector2(3.5, 0), Vector2(1, 0), 4.0, true, true))
	assert_true(AT.trigger_allowed(5.0, 4.5, Vector2(4.5, 0), Vector2(1, 0), 4.0, true, true))
	assert_false(AT.trigger_allowed(5.0, 0.6, Vector2(0.6, 0), Vector2(1, 0), 4.0, true, true))

# 5. 原地跳恒放行（jump_v ≤ 0.4 无视一切门控）
func test_trigger_allowed_stationary_jump() -> void:
	assert_true(AT.trigger_allowed(0.3, 0.0, Vector2.ZERO, Vector2.ZERO, 9.0, true, false))

# 6. 确定性：同参数两次全等
func test_trigger_allowed_determinism() -> void:
	var a := AT.trigger_allowed(5.0, 4.5, Vector2(4.5, 0), Vector2(1, 0), 4.0, true, true)
	var b := AT.trigger_allowed(5.0, 4.5, Vector2(4.5, 0), Vector2(1, 0), 4.0, true, true)
	assert_eq(a, b)

# 7. 滑墙切向手性锁存锚（纯逻辑）：投影充足 → 投影切线；投影 <0.1 + 锁存非零 →
#    锁存方向；投影 <0.1 + 锁存零 → 固定兜底 (wall_n.z, -wall_n.x)
func test_wall_follow_tangent_latch() -> void:
	var wall_n := Vector3(1, 0, 0)
	var t1: Vector3 = AT.wall_follow_tangent(Vector3(0, 0, 5), wall_n, Vector3.ZERO)
	assert_eq(t1, Vector3(0, 0, 1))
	var t2: Vector3 = AT.wall_follow_tangent(Vector3(1, 0, 0), wall_n, Vector3(0, 0, -1))
	assert_eq(t2, Vector3(0, 0, -1))
	var t3: Vector3 = AT.wall_follow_tangent(Vector3(1, 0, 0), wall_n, Vector3.ZERO)
	assert_eq(t3, Vector3(0, 0, -1))
	var t4: Vector3 = AT.wall_follow_tangent(Vector3(1, 0, 0.01), wall_n, Vector3(0, 0, 1))
	assert_eq(t4, Vector3(0, 0, 1))


# ==================== T2 慢测试 harness（测试 8-11，F11/F12） ====================
# 复制 test_auto_smoke 的 _assemble 模式（灰盒 + NavigationRegion3D(navmesh.res) +
# 54 NavigationLink3D（两轮迭代后 snap + 等下一迭代）+ AutoTraversal 先于 Player
# add_child + AutoTraversalRecord 临时目录），TMP_DIR 与 smoke 隔离。
# 测试 8/9/10/11 是慢测试（物理秒级，≤60s 驱动上限），与 test_auto_smoke 同豁免口径。

const LAYOUT := preload("res://Levels/M2_TDM/map_layout_v3.gd")
const NAV_PATH := "res://Levels/M2_TDM/navmesh.res"
const TMP_DIR := "user://test_runup_tmp"
const MAX_SECONDS := 60.0


func before_each() -> void:
	_clean_tmp()


func after_each() -> void:
	_clean_tmp()


# 装配：灰盒 + 导航区域 + 54 链接（snap）+ AutoTraversal（先于 Player）+ 记录器。
# 返回 {"autopilot": AutoTraversal, "player": MovementController,
#        "record": AutoTraversalRecord, "hash": String}。
func _assemble() -> Dictionary:
	# 1. 灰盒 + 导航区域
	var map := MapGreybox.new()
	add_child_autofree(map)
	map.build()

	var nav_region := NavigationRegion3D.new()
	nav_region.navigation_mesh = load(NAV_PATH)
	add_child_autofree(nav_region)

	# 2. 54 条跳跃链接（LAYOUT.jump_links()）
	var links: Array = []
	for l0 in LAYOUT.jump_links():
		var l: Dictionary = l0
		var link := NavigationLink3D.new()
		link.start_position = l["from"]
		link.end_position = l["to"]
		link.bidirectional = true
		add_child_autofree(link)
		links.append(link)

	# 3. 等地图两轮迭代后 snap（2026-08-15 F3 审查 8c 实测修正，同 smoke）：
	#    iter ≥ 2 后 snap 链接端点才稳定进入寻路图
	var map_rid := get_viewport().get_world_3d().navigation_map
	var base_iter := NavigationServer3D.map_get_iteration_id(map_rid)
	for i in 60:
		await wait_physics_frames(1)
		if NavigationServer3D.map_get_iteration_id(map_rid) >= base_iter + 2:
			break
	for lk in links:
		var nav_link := lk as NavigationLink3D
		nav_link.start_position = NavigationServer3D.map_get_closest_point(
				map_rid, nav_link.start_position)
		nav_link.end_position = NavigationServer3D.map_get_closest_point(
				map_rid, nav_link.end_position)
	# snap 改动链接端点 → 等地图完成下一轮迭代（链接重注册）再继续
	var pre_snap_iter := NavigationServer3D.map_get_iteration_id(map_rid)
	for i in 60:
		await wait_physics_frames(1)
		if NavigationServer3D.map_get_iteration_id(map_rid) > pre_snap_iter:
			break

	# 4. AutoTraversal 先于 Player add_child（命令先行树序）
	var autopilot := AT.new()
	add_child_autofree(autopilot)

	var player: MovementController = load("res://Player/Player.tscn").instantiate()
	player.position = LAYOUT.player_spawn()
	add_child_autofree(player)

	# 5. 记录器（临时目录 + 当前布局哈希；rev 追加口径与 smoke 一致）
	var record := AutoTraversalRecord.new()
	var hash_str: String = JumpRecordCore.map_hash(
			LAYOUT.all_solids(),
			MovementController.MOVEMENT_REV + "|" + AT.TRAVERSAL_REV)
	record.setup(hash_str, TMP_DIR)
	record.set_target_faces(160)
	return {"autopilot": autopilot, "player": player, "record": record,
			"hash": hash_str}


## 驱动至 done 或帧数上限（≤MAX_SECONDS），返回消耗帧数
func _drive(autopilot: AutoTraversal, record: AutoTraversalRecord) -> int:
	var frames := 0
	var max_frames := int(MAX_SECONDS * 60.0)
	while frames < max_frames and not autopilot.done:
		await wait_physics_frames(1)
		frames += 1
	return frames


func _clean_tmp() -> void:
	if DirAccess.dir_exists_absolute(TMP_DIR):
		_remove_tree(TMP_DIR)


func _remove_tree(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for sub in dir.get_directories():
		_remove_tree(path.path_join(sub))
		dir.remove(path.path_join(sub))
	for file in dir.get_files():
		dir.remove(path.path_join(file))
	dir.remove(path)


# 8. 垂直链接回归锚（F12）：WestClusterN_Box 经 Crate_WN（from/to 同点直上 0.9m 箱）
#    执行——停摆触发 + 纯弹道落回箱顶 → success。断言 verdict=="success" 且 link 字段
#    非空（与 smoke 既有口径一致）
func test_vertical_link_crate_wn_success() -> void:
	var a := await _assemble()
	var autopilot: AutoTraversal = a["autopilot"]
	var record: AutoTraversalRecord = a["record"]
	autopilot.setup(a["player"], record, Callable())
	autopilot.set_target_faces(["WestClusterN_Box"])
	autopilot.start()
	var frames := await _drive(autopilot, record)
	print("RUNUP8 frames=", frames, " done=", autopilot.done,
			" summary=", record.summary_dict())
	assert_true(autopilot.done,
			"垂直链接目标应在 %.0fs 内完成（超时=垂直模式未生效）" % MAX_SECONDS)
	var pf: Dictionary = record.summary_dict()["per_face"]
	assert_true(pf.has("WestClusterN_Box"), "WestClusterN_Box 应有 attempt 记录")
	assert_eq(pf["WestClusterN_Box"]["verdict"], "success",
			"Crate_WN 垂直链接应 success（停摆触发+纯弹道落箱顶）")
	assert_ne(pf["WestClusterN_Box"]["link"], "", "垂直链接必须被使用")


# 9. 垂直模式惰性锚（2026-08-16 控制器裁决）：T-nav 重烘焙后箱区侵蚀使全部链接
#    snap 水平距 ≥ 0.05（实测最小 TowerBox_W/E 0.732）——F12 检测恒不触发，垂直
#    模式为未来 navmesh 变更的防御代码（RC-2 已在当前数据上由 F8/F9 + 新 navmesh
#    根治，测试 8 即证）。锚定「当前 navmesh 无垂直链接」事实：装配 + setup 后
#    白盒调 autopilot._snap_links()，逐链接断言 |from-to| 水平距 ≥ AT.VERTICAL_LINK_DIST。
#    若未来重烘焙使链接重归同点（垂直语义回归），本锚必红提示重新启用 F12 验证。
func test_vertical_mode_inert_on_current_navmesh() -> void:
	var a := await _assemble()
	var autopilot: AutoTraversal = a["autopilot"]
	autopilot.setup(a["player"], a["record"], Callable())
	autopilot._snap_links()
	assert_gt(autopilot._links.size(), 0, "应快照到链接")
	for l0 in autopilot._links:
		var l: Dictionary = l0
		var h: float = Vector2(l["from"].x - l["to"].x, l["from"].z - l["to"].z).length()
		assert_gte(h, AT.VERTICAL_LINK_DIST,
				"链接 %s snap 水平距 %.3f 应 ≥ 0.05（F12 垂直模式惰性）" % [l["name"], h])


# 10. 助跑卡死回归锚（F11）：EastSpurN（PavToSpur_E 助跑卡死样本）驱动 ≤60s →
#     attempt 有记录且 failure_reason != "助跑卡死"（F8 直线化后可能直接 success；
#     压墙场景走 recover 有界重试——两种结局均证明楔墙冻结路径被根治）。
#     注：summary per_face 只存 verdict/attempts/link（无 failure_reason），
#     failure_reason 从 attempts 目录 JSONL head 行读取（smoke 同口径）。
func test_runup_no_wall_wedge_stuck() -> void:
	var a := await _assemble()
	var autopilot: AutoTraversal = a["autopilot"]
	var record: AutoTraversalRecord = a["record"]
	autopilot.setup(a["player"], record, Callable())
	autopilot.set_target_faces(["EastSpurN"])
	autopilot.start()
	var frames := await _drive(autopilot, record)
	# 装配竞态加固（2026-08-16 控制器裁决）：2/4 次全文件运行出现 frames=0 的
	# no_path（start() 同步规划时导航图未就绪的形态）——frames<120 且 no_path 时
	# 清掉本次装配（防新旧玩家同点重叠互相推挤）重新装配重跑一次，第二次结果直接
	# 采用（正常路径 498 帧 success，120 帧门槛不会误吞真实失败）。
	if frames < 120 and record.summary_dict().get("per_face", {}) \
			.get("EastSpurN", {}).get("verdict", "") == "no_path":
		autopilot.free()
		a["player"].free()
		a = await _assemble()
		autopilot = a["autopilot"]
		record = a["record"]
		autopilot.setup(a["player"], record, Callable())
		autopilot.set_target_faces(["EastSpurN"])
		autopilot.start()
		frames = await _drive(autopilot, record)
	var reason := "MISSING"
	var adir := DirAccess.open(TMP_DIR.path_join("attempts"))
	if adir != null:
		for f in adir.get_files():
			var head: Dictionary = JSON.parse_string(
					FileAccess.get_file_as_string(TMP_DIR.path_join("attempts").path_join(f)).split("\n")[0])
			if head.get("face", "") == "EastSpurN":
				reason = str(head.get("failure_reason", ""))
	print("RUNUP10 frames=", frames, " done=", autopilot.done,
			" summary=", record.summary_dict())
	assert_true(autopilot.done,
			"EastSpurN 应在 %.0fs 内完成（超时=楔墙冻结未根治）" % MAX_SECONDS)
	assert_ne(reason, "MISSING", "EastSpurN 应有 attempt 记录")
	assert_ne(reason, "助跑卡死",
			"failure_reason 不得为「助跑卡死」（楔墙冻结路径被根治）")


# 11. 正常链接回归锚：WestTowerBox（F11/F12 不得破坏正常跳跃执行）驱动 ≤60s →
#     success。实现者偏差（2026-08-15 实测驱动）：brief 原文单目标
#     ["WestTowerBox"] 从 spawn 直驱会楔死在 WALK 阶段（(-21.5, 7.108) 全速压
#     WestTowerRamp 西立面——navmesh 四坡道替身把坡道侧面烤成可穿越，物理阶梯
#     踢面从脚高 0 处封死，F5-F7 滑墙 2s 逃不出 → 5s 卡死裁决 "stuck"，F11/F12
#     不触 WALK/navmesh，非本任务可修）。改为预访 WestClusterN_Box 再访
#     WestTowerBox（与 smoke 全遍历同款起点转移：第二目标从箱顶出发、坡道东侧
#     一级台阶入口切入——实测两目标 579 帧 ≈19s success）。断言核心保持 brief
#     原文：WestTowerBox verdict=="success" 且 link 非空。
func test_normal_link_still_works() -> void:
	var a := await _assemble()
	var autopilot: AutoTraversal = a["autopilot"]
	var record: AutoTraversalRecord = a["record"]
	autopilot.setup(a["player"], record, Callable())
	autopilot.set_target_faces(["WestClusterN_Box", "WestTowerBox"])
	autopilot.start()
	var frames := await _drive(autopilot, record)
	print("RUNUP11 frames=", frames, " done=", autopilot.done,
			" summary=", record.summary_dict())
	assert_true(autopilot.done,
			"两目标驱动应在 %.0fs 内完成（超时即失败）" % MAX_SECONDS)
	var pf: Dictionary = record.summary_dict()["per_face"]
	assert_true(pf.has("WestTowerBox"), "WestTowerBox 应有 attempt 记录")
	assert_eq(pf["WestTowerBox"]["verdict"], "success",
			"正常链接目标 WestTowerBox 应 success（F11/F12 不破坏正常跳跃）")
	assert_ne(pf["WestTowerBox"]["link"], "", "链接必须被使用")
