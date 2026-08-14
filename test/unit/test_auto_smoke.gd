# test/unit/test_auto_smoke.gd
# T3（2026-08-14）：AutoTraversal 状态机端到端冒烟测试（TDD，先 RED 后 GREEN）。
# 装配同 probe_navmesh 流程 + test_auto_command 的 Player 实例化：
#   MapGreybox + NavigationRegion3D(navmesh.res) + 54 NavigationLink3D（snap）+
#   Player.tscn + AutoTraversal（先于 Player add_child，命令先行树序）。
# 测试 1 目标限定 ["WestTowerBox", "WestClusterN_Box", "AltarPlatform", "UmbrellaN"]：
#   WestTowerBox=跳跃链接目标（TowerBox_W Δh0.9）；WestClusterN_Box=brief 逃生
#   条款的等价跳跃目标（Crate_WN Δh0.9）；AltarPlatform=步行目标——面心被基座+
#   四斜板密封成导航孤岛，验证 2026-08-14 拍板的目标点回退（面中心→四角/边中点）
#   后经偏点可达（verdict ≠ "no_path"）；UmbrellaN=不可达面——验证 no_path 记录
#   且 plan 字段为空（审查 Minor 1 修复验证）。
# 测试 2：30 分钟会话超时暂停 + restart_session 恢复（注入 0.5s 超时）。
# 断点：done 或 success≥2 或 90s 超时（超时即失败，防 CI 挂死）。
# T3 唯一允许的慢测试（物理秒 30-60s）；其余逻辑测试保持毫秒级。
extends GutTest

const TMP_DIR := "user://test_auto_smoke_tmp"

const LAYOUT := preload("res://Levels/M2_TDM/map_layout_v3.gd")
const NAV_PATH := "res://Levels/M2_TDM/navmesh.res"
const AT := preload("res://Levels/M2_TDM/auto_traversal.gd")

const MAX_SECONDS := 90.0


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

	# 3. 等待导航同步 → 端点 snap（同 probe_navmesh 流程）→ 再等同步
	await wait_physics_frames(10)
	var map_rid := get_viewport().get_world_3d().navigation_map
	for lk in links:
		var nav_link := lk as NavigationLink3D
		nav_link.start_position = NavigationServer3D.map_get_closest_point(
				map_rid, nav_link.start_position)
		nav_link.end_position = NavigationServer3D.map_get_closest_point(
				map_rid, nav_link.end_position)
	await wait_physics_frames(5)

	# 4. AutoTraversal 先于 Player add_child（命令先行树序）
	var autopilot := AT.new()
	add_child_autofree(autopilot)

	var player: MovementController = load("res://Player/Player.tscn").instantiate()
	player.position = LAYOUT.player_spawn()
	add_child_autofree(player)

	# 5. 记录器（临时目录 + 当前布局哈希）
	var record := AutoTraversalRecord.new()
	var hash_str: String = JumpRecordCore.map_hash(
			LAYOUT.all_solids(), MovementController.MOVEMENT_REV)
	record.setup(hash_str, TMP_DIR)
	record.set_target_faces(160)
	return {"autopilot": autopilot, "player": player, "record": record,
			"hash": hash_str}


func test_full_traversal() -> void:
	var a := await _assemble()
	var autopilot: AutoTraversal = a["autopilot"]
	var record: AutoTraversalRecord = a["record"]
	var hash_str: String = a["hash"]

	# 6-7. 装配 + 限定目标 + 启动
	autopilot.setup(a["player"], record, Callable())
	# WestTowerBox=跳跃链接目标（TowerBox_W Δh0.9）；WestClusterN_Box=brief 逃生
	# 条款的等价跳跃目标（Crate_WN Δh0.9）；AltarPlatform=步行目标（面心被基座+
	# 四斜板密封成导航孤岛——验证 2026-08-14 拍板的目标点回退后经偏点可达）；
	# UmbrellaN=不可达面（probe_navmesh 不可能清单）——验证 no_path 记录 + 审查
	# Minor 1 修复：no_path 的 plan 字段为空（不带上一目标旧数据）。
	autopilot.set_target_faces(
			["WestTowerBox", "WestClusterN_Box", "AltarPlatform", "UmbrellaN"])
	autopilot.start()

	# 8. 驱动循环至 done / 90s 超时（三目标全部处理完才 done——success 提前
	# 断点会跳过 AltarPlatform 的偏点回退验证）
	var max_frames := int(MAX_SECONDS * 60.0)
	var frames := 0
	while frames < max_frames and not autopilot.done:
		await wait_physics_frames(1)
		frames += 1
	print("SMOKE frames=", frames,
			" done=", autopilot.done,
			" summary=", record.summary_dict())

	# 9. 断言（超时即失败）
	assert_true(autopilot.done, "遍历应在 %.0fs 内完成（超时即失败）" % MAX_SECONDS)
	var s: Dictionary = record.summary_dict()
	assert_gt(int(s["counters"]["success"]), 0, "至少 1 个目标面到达成功")
	var pf: Dictionary = s["per_face"]
	assert_true(pf.has("WestTowerBox"), "WestTowerBox 应有 attempt 记录")
	assert_eq(pf["WestTowerBox"]["verdict"], "success",
			"跳跃链接目标 WestTowerBox 应成功")
	assert_ne(pf["WestTowerBox"]["link"], "",
			"WestTowerBox 的 attempt 应经跳跃链接执行")
	# 目标点回退验证：AltarPlatform 面心为导航孤岛，经偏点回退后不得判 no_path
	assert_true(pf.has("AltarPlatform"), "AltarPlatform 应有 attempt 记录")
	assert_ne(pf["AltarPlatform"]["verdict"], "no_path",
			"AltarPlatform 应经目标点回退（面中心→四角/边中点）可达，非 no_path")
	# 不可达面 + 审查 Minor 1 修复：no_path 的 plan 字段为空（不带上一目标旧数据）
	assert_true(pf.has("UmbrellaN"), "UmbrellaN 应有 attempt 记录")
	assert_eq(pf["UmbrellaN"]["verdict"], "no_path", "伞顶不可达 → no_path")
	var umbrel_plan_empty := false
	var adir0 := DirAccess.open(TMP_DIR.path_join("attempts"))
	if adir0 != null:
		for f in adir0.get_files():
			var head0: Dictionary = JSON.parse_string(
					FileAccess.get_file_as_string(TMP_DIR.path_join("attempts").path_join(f)).split("\n")[0])
			if head0.get("face", "") == "UmbrellaN":
				umbrel_plan_empty = head0.get("plan", "X") == {}
	assert_true(umbrel_plan_empty, "no_path 的 plan 字段应为空 {}（T6 数据质量）")

	var adir := DirAccess.open(TMP_DIR.path_join("attempts"))
	assert_true(adir != null and adir.get_files().size() > 0,
			"临时目录 attempts 下应有文件")
	var manifest: Dictionary = JSON.parse_string(
			FileAccess.get_file_as_string(TMP_DIR.path_join("manifest.json")))
	assert_eq(manifest["map_hash"], hash_str,
			"manifest.map_hash == 当前布局哈希")
	assert_gte(record.attempt_count(), 2, "attempt_count ≥ 2")


# 会话超时暂停 + 重启（2026-08-14 用户拍板：单次自动运行 ≤30 分钟——注入 0.5s 验证）
func test_session_timeout_pause_and_restart() -> void:
	var a := await _assemble()
	var autopilot: AutoTraversal = a["autopilot"]
	var record: AutoTraversalRecord = a["record"]

	var hud_states: Array = []
	var got_signal := [false]
	autopilot.setup(a["player"], record, func(p: Dictionary) -> void:
		hud_states.append(str(p.get("state", ""))))
	autopilot.timeout_paused.connect(func() -> void: got_signal[0] = true)
	autopilot.set_session_timeout(0.5)
	autopilot.set_target_faces(["WestClusterN_Box"])
	autopilot.start()

	# 等 timeout_paused（≤10s 防挂）
	var frames := 0
	while frames < 600 and not got_signal[0]:
		await wait_physics_frames(1)
		frames += 1
	assert_true(got_signal[0], "超时到点应触发 timeout_paused 信号（实际 %d 帧）" % frames)
	assert_eq(autopilot.session_state, "paused_timeout", "状态应为 paused_timeout")
	assert_false(autopilot.active, "暂停后 active=false")
	var paused_seen := false
	for st in hud_states:
		if String(st).contains("已暂停"):
			paused_seen = true
	assert_true(paused_seen, "hud 回调状态应含「已暂停」")

	# 重启：清暂停、计时归零、进度从 summary 继续（aborted 面重试）
	autopilot.restart_session()
	assert_true(autopilot.active, "restart_session 后 active=true")
	assert_eq(autopilot.session_state, "active", "restart_session 后状态 active")

	# 计时已归零：再跑 0.5s 又触发一次 timeout_paused
	got_signal[0] = false
	frames = 0
	while frames < 600 and not got_signal[0]:
		await wait_physics_frames(1)
		frames += 1
	assert_true(got_signal[0],
			"重启后计时归零——再 0.5s 又触发 timeout_paused（实际 %d 帧）" % frames)
	assert_eq(autopilot.session_state, "paused_timeout", "二次暂停状态 paused_timeout")

	# aborted 收尾落盘验证
	var aborted_seen := false
	var adir := DirAccess.open(TMP_DIR.path_join("attempts"))
	if adir != null:
		for f in adir.get_files():
			var head: Dictionary = JSON.parse_string(
					FileAccess.get_file_as_string(TMP_DIR.path_join("attempts").path_join(f)).split("\n")[0])
			if head.get("verdict", "") == "aborted":
				aborted_seen = true
	assert_true(aborted_seen, "暂停时进行中的 attempt 应按 aborted 收尾落盘")


# ---- 工具（独立实现——测试不依赖被测代码） ----

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
