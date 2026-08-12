# test/unit/test_jump_recorder.gd
# 任务 15：JumpRecorder 场景层——episode 检测/采样/写盘 + 地图哈希重置铁律（TDD）。
# 用户铁律（2026-08-11）：地图每改动一次必须重置全部跳跃记录——
# 启动时布局哈希与 manifest 比对，不符/缺失/损坏 → 递归清空 base_dir 重建。
# 文件级用例通过注入 base_dir="user://test_jump_rec_tmp" 隔离，teardown 清理；
# 缝方法（_begin_episode/_sample_frame/_end_episode/_force_timeout）公开供测试驱动。
extends GutTest

const V3 := preload("res://Levels/M2_TDM/map_layout_v3.gd")
const TMP_DIR := "user://test_jump_rec_tmp"

var recorder: JumpRecorder


func before_each() -> void:
	_clean_tmp()
	recorder = JumpRecorder.new()
	add_child_autofree(recorder)


func after_each() -> void:
	Input.action_release("jump")
	_clean_tmp()


# ================= 1. 空目录 setup → 全新落点 =================
func test_setup_fresh() -> void:
	recorder.setup(null, V3.all_solids(), "回声祭坛v3", TMP_DIR)
	assert_true(FileAccess.file_exists(TMP_DIR + "/manifest.json"),
			"空目录 setup → manifest.json 落盘")
	assert_true(DirAccess.dir_exists_absolute(TMP_DIR + "/episodes"),
			"episodes/ 目录被创建")
	var m: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(TMP_DIR + "/manifest.json"))
	assert_eq(m["map_hash"], JumpRecordCore.map_hash(V3.all_solids()),
			"manifest.map_hash == JumpRecordCore.map_hash(真实布局)")
	assert_eq(int(m["episode_count"]), 0, "全新 manifest episode_count=0")
	assert_eq(recorder.current_hash(), JumpRecordCore.map_hash(V3.all_solids()),
			"current_hash() 与真实布局哈希一致")
	assert_eq(recorder.episode_count(), 0, "episode_count() manifest 读值=0")


# ================= 2. 哈希一致 → 数据保留 =================
func test_setup_same_hash_preserves() -> void:
	DirAccess.make_dir_recursive_absolute(TMP_DIR + "/episodes")
	var h := JumpRecordCore.map_hash(V3.all_solids())
	var f := FileAccess.open(TMP_DIR + "/manifest.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(JumpRecordCore.manifest_dict(h, "回声祭坛v3", 3)))
	f.close()
	var fake := FileAccess.open(TMP_DIR + "/episodes/ep_0002.jsonl", FileAccess.WRITE)
	fake.store_line("{}")
	fake.close()

	recorder.setup(null, V3.all_solids(), "回声祭坛v3", TMP_DIR)

	assert_true(FileAccess.file_exists(TMP_DIR + "/manifest.json"), "manifest 保留")
	assert_true(FileAccess.file_exists(TMP_DIR + "/episodes/ep_0002.jsonl"),
			"哈希一致 → 老 episode 文件保留")
	assert_eq(recorder.episode_count(), 3, "episode_count 沿用 manifest 值")


# ================= 3. 哈希不符 → 递归清空重建 =================
func test_setup_hash_mismatch_resets() -> void:
	DirAccess.make_dir_recursive_absolute(TMP_DIR + "/episodes")
	var f := FileAccess.open(TMP_DIR + "/manifest.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(JumpRecordCore.manifest_dict("f".repeat(64), "旧图", 9)))
	f.close()
	var fake := FileAccess.open(TMP_DIR + "/episodes/ep_0008.jsonl", FileAccess.WRITE)
	fake.store_line("{}")
	fake.close()
	var nested := FileAccess.open(TMP_DIR + "/episodes/stale.tmp", FileAccess.WRITE)
	nested.store_line("stale")
	nested.close()

	recorder.setup(null, V3.all_solids(), "回声祭坛v3", TMP_DIR)

	assert_false(FileAccess.file_exists(TMP_DIR + "/episodes/ep_0008.jsonl"),
			"哈希不符 → 老 episode 文件被清空")
	assert_false(FileAccess.file_exists(TMP_DIR + "/episodes/stale.tmp"),
			"哈希不符 → episodes/ 内杂项文件被清空")
	var m: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(TMP_DIR + "/manifest.json"))
	assert_eq(m["map_hash"], JumpRecordCore.map_hash(V3.all_solids()),
			"重置后 manifest 哈希为新布局值")
	assert_eq(int(m["episode_count"]), 0, "重置后 episode_count 归零")
	assert_true(DirAccess.dir_exists_absolute(TMP_DIR + "/episodes"),
			"重置后 episodes/ 重建")


# ================= 3b. manifest 损坏（非法 JSON）→ 同样重置 =================
func test_setup_corrupt_manifest_resets() -> void:
	DirAccess.make_dir_recursive_absolute(TMP_DIR + "/episodes")
	var f := FileAccess.open(TMP_DIR + "/manifest.json", FileAccess.WRITE)
	f.store_string("{this is not json")
	f.close()
	var fake := FileAccess.open(TMP_DIR + "/episodes/ep_0001.jsonl", FileAccess.WRITE)
	fake.store_line("{}")
	fake.close()

	recorder.setup(null, V3.all_solids(), "回声祭坛v3", TMP_DIR)

	assert_false(FileAccess.file_exists(TMP_DIR + "/episodes/ep_0001.jsonl"),
			"manifest JSON 损坏 → 老记录同样被清空")
	var m: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(TMP_DIR + "/manifest.json"))
	assert_eq(m["map_hash"], recorder.current_hash(), "损坏 manifest 被新 manifest 覆盖")


# ================= 3c. 移动机制 rev 变更 → 重置铁律（X1） =================
# 实证移动机制变更触发重置铁律：布局不变但移动语义变更（step-up/空中控制修订）——
# 旧 rev 哈希 manifest + 假 episode → setup（玩家携带新 MOVEMENT_REV）→ episode 被清、
# manifest 哈希为新 rev 值。
func test_setup_movement_rev_change_resets() -> void:
	var player: MovementController = load("res://Player/MovementController.tscn").instantiate()
	add_child_autofree(player)
	var old_hash := JumpRecordCore.map_hash(V3.all_solids(), "move-r1:legacy")
	DirAccess.make_dir_recursive_absolute(TMP_DIR + "/episodes")
	var f := FileAccess.open(TMP_DIR + "/manifest.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(JumpRecordCore.manifest_dict(old_hash, "回声祭坛v3", 5)))
	f.close()
	var fake := FileAccess.open(TMP_DIR + "/episodes/ep_0004.jsonl", FileAccess.WRITE)
	fake.store_line("{}")
	fake.close()

	recorder.setup(player, V3.all_solids(), "回声祭坛v3", TMP_DIR)

	assert_false(FileAccess.file_exists(TMP_DIR + "/episodes/ep_0004.jsonl"),
			"移动机制 rev 变更 → 老 episode 被清空")
	var m: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(TMP_DIR + "/manifest.json"))
	var new_hash := JumpRecordCore.map_hash(V3.all_solids(), MovementController.MOVEMENT_REV)
	assert_eq(m["map_hash"], new_hash, "重置后 manifest 哈希 = 新 rev 值")
	assert_ne(m["map_hash"], old_hash, "新哈希 ≠ 旧 rev 哈希")
	assert_eq(int(m["episode_count"]), 0, "重置后 episode_count 归零")


# ================= 4. episode 写盘格式（缝驱动，climb 路径） =================
func test_episode_write_format() -> void:
	recorder.setup(null, V3.all_solids(), "回声祭坛v3", TMP_DIR)
	recorder._begin_episode(1.0, "GroundFloor")
	for i in 3:
		recorder._sample_frame(_fake_frame(i))
	recorder._end_episode(1.6, "AltarTop")  # end−start=0.6 ≥ 0.5 → climb

	var path := TMP_DIR + "/episodes/ep_0000.jsonl"
	assert_true(FileAccess.file_exists(path), "episode 落盘 ep_0000.jsonl")
	var lines := _read_lines(path)
	assert_eq(lines.size(), 4, "首行元数据 + 3 帧行")
	var meta: Dictionary = JSON.parse_string(lines[0])
	assert_true(meta.has_all(["episode_id", "map_hash", "map_name", "classification",
			"start_floor_y", "end_floor_y", "start_name", "end_name", "net_rise",
			"frame_count"]), "元数据 10 键齐全")
	assert_eq(meta["classification"], "climb", "净升高 0.6 → climb")
	assert_eq(int(meta["episode_id"]), 0, "首个 episode id=0")
	assert_eq(int(meta["frame_count"]), 3, "frame_count=3")
	assert_almost_eq(meta["net_rise"], 0.6, 0.0001, "net_rise=end−start")
	assert_eq(meta["start_name"], "GroundFloor", "start_name 透传")
	assert_eq(meta["end_name"], "AltarTop", "end_name 透传")
	var fr: Dictionary = JSON.parse_string(lines[1])
	assert_true(fr.has_all(["t_ms", "px", "py", "pz", "vx", "vy", "vz", "yaw", "pitch",
			"ix", "iy", "crouch", "jump_held", "on_floor", "floor_name"]),
			"帧行 15 字段齐全")
	assert_eq(recorder.episode_count(), 1, "写盘后 manifest episode_count=1")


# ================= 5. 超时路径（缝驱动，fail 分类） =================
func test_episode_timeout_path() -> void:
	recorder.setup(null, V3.all_solids(), "回声祭坛v3", TMP_DIR)
	recorder._begin_episode(0.5, "Ground")
	recorder._sample_frame(_fake_frame(0))
	recorder._force_timeout()  # 不落地直接超时收尾 → end=start 值

	var path := TMP_DIR + "/episodes/ep_0000.jsonl"
	assert_true(FileAccess.file_exists(path), "超时路径同样写盘")
	var lines := _read_lines(path)
	var meta: Dictionary = JSON.parse_string(lines[0])
	assert_eq(meta["classification"], "fail", "end=start 同面净升 0 → fail")
	assert_almost_eq(meta["end_floor_y"], meta["start_floor_y"], 0.0001,
			"超时 end_floor_y = start 值")
	assert_eq(meta["end_name"], meta["start_name"], "超时 end_name = start 值")
	assert_eq(recorder.episode_count(), 1, "超时 episode 计入 manifest")


# ================= 6. 物理集成：真实 Player 跳一次 → fail episode 落盘 =================
# 垂直原地跳 → 落回同名地面 → classify fail；帧数覆盖滞空(~46帧)+落地确认(30帧)。
# 依赖实测结论：Godot 4.7 _physics_process 按树序执行（process_priority 对物理无效），
# recorder 最后入树 → 在玩家 move_and_slide 之后读当帧状态。
# 注（终审 M3 地面守卫）：_physics_process 仅在找到法线 y≥_floor_normal_y 的碰撞时才覆盖
# _last_floor_y/_last_floor_name。法线阈值与玩家同源（F2a-P3）：setup 时
# _floor_normal_y = cos(player.floor_max_angle)，与引擎 is_on_floor() 判定一致
# （默认 45° → cos≈0.707），故"on_floor 但无合格碰撞"分支在当前参数下不可达，
# 属防御性守卫，现有用例不单独覆盖。
func test_jump_episode_integration() -> void:
	var floor_body := _make_floor()
	floor_body.name = "IntFloor"
	var player: CharacterBody3D = load("res://Player/Player.tscn").instantiate()
	player.position = Vector3(0, 1.0, 0)
	add_child_autofree(player)
	recorder.setup(player, V3.all_solids(), "回声祭坛v3", TMP_DIR)

	await wait_physics_frames(25)
	assert_true(player.is_on_floor(), "前置：玩家应落在地面上")
	Input.action_press("jump")
	await wait_physics_frames(150)

	var path := TMP_DIR + "/episodes/ep_0000.jsonl"
	assert_true(FileAccess.file_exists(path), "完整跳跃结束后 episode 文件落盘")
	var lines := _read_lines(path)
	var meta: Dictionary = JSON.parse_string(lines[0])
	assert_eq(meta["classification"], "fail", "原地垂直跳落回同面 → fail")
	assert_eq(meta["start_name"], "IntFloor", "起跳踩踏体名 = 地面名")
	assert_eq(meta["end_name"], "IntFloor", "落地踩踏体名 = 地面名")
	assert_gte(int(meta["frame_count"]), 40, "帧数覆盖滞空 + 落地确认时长")
	assert_eq(recorder.episode_count(), 1, "episode 计入 manifest")


# ---- 夹具与工具 ----

## 伪造帧行（缝驱动用）
func _fake_frame(i: int) -> Dictionary:
	return {
		"t_ms": i * 16, "px": 0.0, "py": 1.0 + i * 0.2, "pz": 0.0,
		"vx": 0.0, "vy": 3.0, "vz": 0.0, "yaw": 0.0, "pitch": 0.0,
		"ix": 0.0, "iy": 0.0, "crouch": false, "jump_held": true,
		"on_floor": false, "floor_name": "",
	}


## 读 jsonl 文件全部非空行
func _read_lines(path: String) -> Array:
	return FileAccess.get_file_as_string(path).split("\n", false)


## 物理地面（test_controller.gd 同款：Objects 层，顶面 y=0）
func _make_floor() -> StaticBody3D:
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	floor_body.collision_mask = 0
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(40, 1, 40)
	col.shape = shape
	floor_body.add_child(col)
	floor_body.position = Vector3(0, -0.5, 0)
	add_child_autofree(floor_body)
	return floor_body


## 递归清理 TMP_DIR（独立实现——测试不依赖被测代码）
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
