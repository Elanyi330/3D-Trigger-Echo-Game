# test/unit/test_auto_smoke.gd
# T3（2026-08-14）：AutoTraversal 状态机端到端冒烟测试（TDD，先 RED 后 GREEN）。
# 装配同 probe_navmesh 流程 + test_auto_command 的 Player 实例化：
#   MapGreybox + NavigationRegion3D(navmesh.res) + 54 NavigationLink3D（snap）+
#   Player.tscn + AutoTraversal（先于 Player add_child，命令先行树序）。
# 目标限定 ["WestTowerBox", "WestClusterN_Box"]（两个跳跃链接目标 Δh0.9；
# brief 原文 AltarPlatform 步行目标实测导航孤岛阻断、EastPavilion 实测楔角卡死，
# 按 brief 逃生条款换等价跳跃目标 WestClusterN_Box）。
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


func test_full_traversal() -> void:
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

	# 6-7. 装配 + 限定目标 + 启动
	autopilot.setup(player, record, Callable())
	# 两个跳跃链接目标（brief 逃生条款：WestClusterN_Box 为 brief 原文建议的等价
	# 跳跃目标，Crate_WN 链接 Δh0.9 人类 p50=4.012）。原步行目标 AltarPlatform 实测
	# 意外阻断：祭坛面心 (0,0.6,0) 被基座+四斜板面接触密封成导航孤岛（path 末端距
	# 目标 2.38m > 0.8 → no_path 判据命中）；EastPavilion 步道为 台阶+摊阁 直角
	# 楔角几何（贴墙+登台互斥，step-up 净空三连被相邻墙体接触阻断，实测卡死）。
	# 两目标路径均为开阔地行走 + 直坡道 + 跳跃，无楔角几何。
	autopilot.set_target_faces(["WestTowerBox", "WestClusterN_Box"])
	autopilot.start()

	# 8. 驱动循环至 done / success≥2 / 90s 超时
	var max_frames := int(MAX_SECONDS * 60.0)
	var frames := 0
	while frames < max_frames:
		await wait_physics_frames(1)
		frames += 1
		if autopilot.done:
			break
		var counters: Dictionary = record.summary_dict().get("counters", {})
		if int(counters.get("success", 0)) >= 2:
			break
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

	var adir := DirAccess.open(TMP_DIR.path_join("attempts"))
	assert_true(adir != null and adir.get_files().size() > 0,
			"临时目录 attempts 下应有文件")
	var manifest: Dictionary = JSON.parse_string(
			FileAccess.get_file_as_string(TMP_DIR.path_join("manifest.json")))
	assert_eq(manifest["map_hash"], hash_str,
			"manifest.map_hash == 当前布局哈希")
	assert_gte(record.attempt_count(), 2, "attempt_count ≥ 2")


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
