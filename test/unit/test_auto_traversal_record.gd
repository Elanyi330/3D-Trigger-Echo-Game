# test/unit/test_auto_traversal_record.gd
# T4：AutoTraversalRecord 记录器——attempt 落盘（jsonl head+帧行）/ summary 增量 /
# 地图哈希重置铁律 / 确定性（TDD）。
#
# 与 test_jump_recorder.gd 同模式：base_dir 注入临时目录隔离，after_each 清理；
# 记录器是 RefCounted（无树依赖），无需 add_child_autofree。
# 设计文档：docs/superpowers/specs/2026-08-14-auto-traversal-design.md §5.4。
extends GutTest

const TMP_DIR := "user://test_auto_trav_rec_tmp"

var recorder: AutoTraversalRecord


func before_each() -> void:
	_clean_tmp()
	recorder = AutoTraversalRecord.new()


func after_each() -> void:
	_clean_tmp()


# ================= 1. 哈希不符 → 递归清空重建 =================
func test_setup_wipes_on_hash_mismatch() -> void:
	DirAccess.make_dir_recursive_absolute(TMP_DIR.path_join("attempts"))
	var f := FileAccess.open(TMP_DIR.path_join("manifest.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify({
		"map_hash": "OLD", "created_at": 1, "attempt_count": 9, "target_faces": 160,
	}))
	f.close()
	var fake := FileAccess.open(TMP_DIR.path_join("attempts/ep_0008.jsonl"), FileAccess.WRITE)
	fake.store_line("{}")
	fake.close()

	recorder.setup("NEW", TMP_DIR)

	assert_false(FileAccess.file_exists(TMP_DIR.path_join("attempts/ep_0008.jsonl")),
			"哈希不符 → 老 attempt 文件被清空")
	var m: Dictionary = JSON.parse_string(
			FileAccess.get_file_as_string(TMP_DIR.path_join("manifest.json")))
	assert_eq(m["map_hash"], "NEW", "重置后 manifest.map_hash == NEW")
	assert_eq(int(m["attempt_count"]), 0, "重置后 attempt_count == 0")
	assert_eq(recorder.attempt_count(), 0, "attempt_count() manifest 读值 == 0")
	assert_true(DirAccess.dir_exists_absolute(TMP_DIR.path_join("attempts")),
			"重置后 attempts/ 重建")


# ================= 2. 哈希一致 → 数据保留（跨会话续跑） =================
func test_setup_resumes_on_hash_match() -> void:
	recorder.setup("H", TMP_DIR)
	recorder.begin_attempt("AltarPlatform", "", {"plan": "p1"})
	recorder.sample_frame(0, Vector3.ZERO, Vector3.UP, 0.0, 0.0, Vector2.ZERO,
			false, true, false, "")
	recorder.end_attempt("success", "", false, {"v": 5.0})
	recorder.begin_attempt("AltarPlatform", "", {"plan": "p2"})
	recorder.end_attempt("jump_missed", "x", false, {})
	recorder.set_progress(1, 160)

	var fresh := AutoTraversalRecord.new()
	fresh.setup("H", TMP_DIR)

	assert_eq(fresh.attempt_count(), 2, "哈希一致 → attempt_count 保持")
	assert_true(FileAccess.file_exists(TMP_DIR.path_join("attempts/ep_0001.jsonl")),
			"哈希一致 → 老 attempt 文件保留")
	var s: Dictionary = fresh.summary_dict()
	assert_eq(int(s["counters"]["success"]), 1, "summary counters.success 保留")
	assert_eq(int(s["counters"]["failed"]), 1, "summary counters.failed 保留")
	assert_eq(int(s["visited"]), 1, "summary visited 保留")
	assert_eq(int(s["total"]), 160, "summary total 保留")
	var pf: Dictionary = s["per_face"]
	assert_eq(int(pf["AltarPlatform"]["attempts"]), 2, "per_face attempts 保留")
	assert_eq(pf["AltarPlatform"]["verdict"], "jump_missed", "per_face verdict 保留最新")


# ================= 3. attempt 往返（success 路径） =================
func test_attempt_roundtrip() -> void:
	recorder.setup("H", TMP_DIR)
	var attempt_id := recorder.begin_attempt("AltarPlatform", "", {"plan": {"n": 1}})
	assert_eq(attempt_id, 0, "首个 attempt id == 0")
	recorder.sample_frame(16, Vector3(1, 2, 3), Vector3(0, 5, 0), 0.1, 0.2,
			Vector2(0, 1), false, true, false, "Ground")
	recorder.sample_frame(32, Vector3(1.1, 2.2, 3.3), Vector3(0, 5.1, 0), 0.2, 0.3,
			Vector2(0, 1), false, true, false, "")
	recorder.sample_frame(48, Vector3(2, 3, 4), Vector3.ZERO, 0.3, 0.4,
			Vector2.ZERO, false, false, true, "AltarPlatform")
	recorder.end_attempt("success", "", false, {"v": 5.0})

	var path := TMP_DIR.path_join("attempts/ep_0000.jsonl")
	assert_true(FileAccess.file_exists(path), "attempt 落盘 ep_0000.jsonl")
	var lines := _read_lines(path)
	assert_eq(lines.size(), 4, "head 行 + 3 帧行")
	var head: Dictionary = JSON.parse_string(lines[0])
	assert_eq(int(head["attempt_id"]), 0, "head.attempt_id == 0")
	assert_eq(head["face"], "AltarPlatform", "head.face 透传")
	assert_eq(head["link"], "", "head.link 无链接时空串")
	assert_eq(head["verdict"], "success", "head.verdict 透传")
	assert_eq(head["failure_reason"], "", "head.failure_reason 透传")
	# Godot JSON 解析数字一律为 float（1 → 1.0），往返比较按 float 口径
	assert_eq(head["plan"], {"plan": {"n": 1.0}}, "head.plan 往返一致")
	assert_eq(head["params_used"], {"v": 5.0}, "head.params_used 往返一致")
	assert_eq(head["teleported"], false, "head.teleported 透传")
	assert_eq(int(head["frame_count"]), 3, "head.frame_count == 3")
	var fr: Dictionary = JSON.parse_string(lines[1])
	assert_eq(fr["auto"], true, "帧行含 auto:true")
	var m: Dictionary = JSON.parse_string(
			FileAccess.get_file_as_string(TMP_DIR.path_join("manifest.json")))
	assert_eq(int(m["attempt_count"]), 1, "manifest.attempt_count == 1")
	var s: Dictionary = recorder.summary_dict()
	assert_eq(int(s["counters"]["success"]), 1, "counters.success == 1")
	assert_eq(int(s["counters"]["failed"]), 0, "counters.failed == 0")
	var pf: Dictionary = s["per_face"]
	assert_eq(pf["AltarPlatform"]["verdict"], "success", "per_face verdict == success")
	assert_eq(int(pf["AltarPlatform"]["attempts"]), 1, "per_face attempts == 1")
	assert_eq(pf["AltarPlatform"]["link"], "", "per_face link 透传")


# ================= 4. attempt 往返（failure 路径） =================
func test_failure_roundtrip() -> void:
	recorder.setup("H", TMP_DIR)
	recorder.begin_attempt("AltarPlatform", "AltarToArch", {})
	recorder.sample_frame(0, Vector3.ZERO, Vector3.UP, 0.0, 0.0, Vector2.ZERO,
			false, false, false, "")
	recorder.end_attempt("jump_missed", "落错面", true, {"v": 5.0})

	var lines := _read_lines(TMP_DIR.path_join("attempts/ep_0000.jsonl"))
	assert_eq(lines.size(), 2, "head 行 + 1 帧行")
	var head: Dictionary = JSON.parse_string(lines[0])
	assert_eq(head["verdict"], "jump_missed", "head.verdict == jump_missed")
	assert_eq(head["failure_reason"], "落错面", "head.failure_reason 透传")
	assert_eq(head["link"], "AltarToArch", "head.link 透传")
	assert_eq(head["teleported"], true, "head.teleported == true")
	var s: Dictionary = recorder.summary_dict()
	assert_eq(int(s["counters"]["failed"]), 1, "counters.failed == 1")
	assert_eq(int(s["counters"]["success"]), 0, "counters.success == 0")
	var pf: Dictionary = s["per_face"]
	assert_eq(pf["AltarPlatform"]["verdict"], "jump_missed",
			"per_face verdict == jump_missed")


# ================= 5. frame_line 模式：恰 16 键（15+auto），值三位小数 snapped =================
func test_frame_line_schema() -> void:
	var line := AutoTraversalRecord.frame_line(123, Vector3(1.23456, 2.0, -3.0004),
			Vector3(0.0, 5.6789, -0.004), 0.1234, -0.5678, Vector2(0.5, -1.0),
			true, true, false, "AltarPlatform")
	var fr: Dictionary = JSON.parse_string(line)
	assert_eq(fr.size(), 16, "恰 16 键（15 字段 + auto）")
	assert_true(fr.has_all(["t_ms", "px", "py", "pz", "vx", "vy", "vz", "yaw",
			"pitch", "ix", "iy", "crouch", "jump_held", "on_floor", "floor_name",
			"auto"]), "键名与 JumpRecorder 15 字段 + auto 一致")
	assert_eq(int(fr["t_ms"]), 123, "t_ms 透传")
	assert_almost_eq(fr["px"], 1.235, 0.0001, "px snapped 3 位小数")
	assert_almost_eq(fr["py"], 2.0, 0.0001, "py snapped")
	assert_almost_eq(fr["pz"], -3.0, 0.0001, "pz snapped")
	assert_almost_eq(fr["vx"], 0.0, 0.0001, "vx snapped")
	assert_almost_eq(fr["vy"], 5.679, 0.0001, "vy snapped")
	assert_almost_eq(fr["vz"], -0.004, 0.0001, "vz snapped")
	assert_almost_eq(fr["yaw"], 0.123, 0.0001, "yaw snapped")
	assert_almost_eq(fr["pitch"], -0.568, 0.0001, "pitch snapped")
	assert_almost_eq(fr["ix"], 0.5, 0.0001, "ix snapped")
	assert_almost_eq(fr["iy"], -1.0, 0.0001, "iy snapped")
	assert_eq(fr["crouch"], true, "crouch 透传")
	assert_eq(fr["jump_held"], true, "jump_held 透传")
	assert_eq(fr["on_floor"], false, "on_floor 透传")
	assert_eq(fr["floor_name"], "AltarPlatform", "floor_name 透传")
	assert_eq(fr["auto"], true, "auto == true")


# ================= 6. 进度往返 =================
func test_progress_roundtrip() -> void:
	recorder.setup("H", TMP_DIR)
	recorder.set_progress(3, 160)

	var s: Dictionary = recorder.summary_dict()
	assert_eq(int(s["visited"]), 3, "内存 summary visited == 3")
	assert_eq(int(s["total"]), 160, "内存 summary total == 160")
	var on_disk: Dictionary = JSON.parse_string(
			FileAccess.get_file_as_string(TMP_DIR.path_join("summary.json")))
	assert_eq(int(on_disk["visited"]), 3, "落盘 summary visited == 3")
	assert_eq(int(on_disk["total"]), 160, "落盘 summary total == 160")


# ================= 7. 确定性：同输入两次流程 → attempt 载荷字节一致 =================
func test_determinism() -> void:
	recorder.setup("H", TMP_DIR)
	_run_flow(recorder)
	var first := FileAccess.get_file_as_string(TMP_DIR.path_join("attempts/ep_0000.jsonl"))

	var fresh := AutoTraversalRecord.new()
	fresh.setup("H", TMP_DIR)
	_run_flow(fresh)
	var second := FileAccess.get_file_as_string(TMP_DIR.path_join("attempts/ep_0001.jsonl"))

	var first_lines := first.split("\n", false)
	var second_lines := second.split("\n", false)
	assert_eq(first_lines.size(), second_lines.size(), "两次流程行数一致")
	var h1: Dictionary = JSON.parse_string(first_lines[0])
	var h2: Dictionary = JSON.parse_string(second_lines[0])
	h1.erase("attempt_id")
	h2.erase("attempt_id")
	assert_eq(h1, h2, "head 行除 attempt_id 外逐字段一致")
	for i in range(1, first_lines.size()):
		assert_eq(first_lines[i], second_lines[i], "帧行 %d 字节级一致" % i)


# ---- 夹具与工具 ----

## 同一输入的标准流程（determinism 对照用）
func _run_flow(r: AutoTraversalRecord) -> void:
	r.begin_attempt("AltarPlatform", "L1", {"plan": {"seg": 1}})
	r.sample_frame(16, Vector3(1, 2, 3), Vector3(0, 5, 0), 0.1, 0.2,
			Vector2(0, 1), false, true, false, "Ground")
	r.sample_frame(32, Vector3(1.1, 2.2, 3.3), Vector3(0, 5.1, 0), 0.2, 0.3,
			Vector2(0, 1), false, true, false, "")
	r.end_attempt("success", "", false, {"v": 5.0})


## 读 jsonl 文件全部非空行
func _read_lines(path: String) -> Array:
	return FileAccess.get_file_as_string(path).split("\n", false)


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
