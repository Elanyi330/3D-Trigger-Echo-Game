# Levels/M2_TDM/auto_traversal_record.gd
# T4：自动遍历记录器——每次 attempt（成功/失败）完整落盘到独立目录
# user://auto_traversal/（与人类语料 jump_training 隔离——用户拍板）。
#
# 用户铁律同 JumpRecorder：manifest.map_hash 必须等于调用方传入的当前布局哈希
# （JumpRecordCore.map_hash(all_solids, MOVEMENT_REV)）——文件缺失/损坏/哈希不符
# → 递归清空 base_dir 重建；哈希一致 → 保留 summary（跨会话续跑）。
# 文件 IO 模式照抄 jump_recorder.gd（_wipe_dir 同款、JSON.new() 解析防 engine
# error、FileAccess 写盘）；序列化确定性：无随机、无时间源依赖（created_at 除外）。
#
# 设计文档：docs/superpowers/specs/2026-08-14-auto-traversal-design.md §5.4。
class_name AutoTraversalRecord
extends RefCounted

const FEET_OFFSET := 0.915   # 与 JumpRecorder 帧口径一致（origin − 脚）

var _map_hash_str := ""
var _base_dir := ""
var _attempts_dir := ""
var _attempt_count := 0
var _target_faces := 0
var _created_at := 0

# ---- summary 内存态（每次 end_attempt/set_progress 后全量重写 summary.json） ----
var _summary: Dictionary = {}

# ---- attempt 运行时状态 ----
var _attempt_active := false
var _attempt_face := ""
var _attempt_link := ""
var _attempt_plan: Dictionary = {}
var _attempt_frames := PackedStringArray()  # 已序列化帧行（写盘用）


## 帧行序列化（15 字段 + "auto": true；与 JumpRecorder._build_frame 同构，
## 浮点 snappedf 3 位小数，保证跨机器/跨运行字节级确定性）
static func frame_line(t_ms: int, p: Vector3, v: Vector3, yaw: float, pitch: float,
		axis: Vector2, crouch: bool, jump_held: bool, on_floor: bool,
		floor_name: String) -> String:
	return JSON.stringify({
		"t_ms": t_ms,
		"px": snappedf(p.x, 0.001), "py": snappedf(p.y, 0.001), "pz": snappedf(p.z, 0.001),
		"vx": snappedf(v.x, 0.001), "vy": snappedf(v.y, 0.001), "vz": snappedf(v.z, 0.001),
		"yaw": snappedf(yaw, 0.001),
		"pitch": snappedf(pitch, 0.001),
		"ix": snappedf(axis.x, 0.001), "iy": snappedf(axis.y, 0.001),
		"crouch": crouch,
		"jump_held": jump_held,
		"on_floor": on_floor,
		"floor_name": floor_name,
		"auto": true,
	})


## 装配：map_hash_str 与 manifest 比对——文件缺失/损坏/哈希不符 → 递归清空
## base_dir 重建（老图/老机制数据不得混存，同 JumpRecorder 铁律）；一致 →
## 保留 attempt_count 与 summary（跨会话续跑）。base_dir 可注入（测试用临时目录）。
func setup(map_hash_str: String, base_dir: String = "user://auto_traversal") -> void:
	_map_hash_str = map_hash_str
	_base_dir = base_dir
	_attempts_dir = base_dir.path_join("attempts")
	_verify_and_reset()


## 写入 manifest 的 target_faces（调用方 setup 后 set_target_faces(160)）
func set_target_faces(n: int) -> void:
	_target_faces = n
	if _base_dir.is_empty():
		return
	_write_manifest()


## 开 attempt（返回 attempt_id；帧缓冲清空）
func begin_attempt(face: String, link: String, plan: Dictionary) -> int:
	_attempt_active = true
	_attempt_face = face
	_attempt_link = link
	_attempt_plan = plan
	_attempt_frames = PackedStringArray()
	return _attempt_count


## 采样一帧（追加帧行入缓冲；无进行中 attempt 时静默丢弃）
func sample_frame(t_ms: int, p: Vector3, v: Vector3, yaw: float, pitch: float,
		axis: Vector2, crouch: bool, jump_held: bool, on_floor: bool,
		floor_name: String) -> void:
	if not _attempt_active:
		return
	_attempt_frames.append(frame_line(t_ms, p, v, yaw, pitch, axis, crouch,
			jump_held, on_floor, floor_name))


## 结束 attempt：写 attempts/ep_%04d.jsonl（head 行 + 帧行）+ summary.json 增量
## 落盘（per_face 取最新 verdict、attempts +1；counters 按 verdict=="success" 计入）
func end_attempt(verdict: String, failure_reason: String, teleported: bool,
		params_used: Dictionary) -> void:
	if not _attempt_active:
		return
	_attempt_active = false
	if _base_dir.is_empty():
		return  # 未 setup（测试兜底）：丢弃缓冲不落盘
	var head := {
		"attempt_id": _attempt_count,
		"face": _attempt_face,
		"link": _attempt_link,
		"verdict": verdict,
		"failure_reason": failure_reason,
		"plan": _attempt_plan,
		"params_used": params_used,
		"teleported": teleported,
		"frame_count": _attempt_frames.size(),
	}
	var path := _attempts_dir.path_join("ep_%04d.jsonl" % _attempt_count)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("[AutoTraversalRecord] 无法写 attempt 文件: %s" % path)
		return
	f.store_line(JSON.stringify(head))
	for line in _attempt_frames:
		f.store_line(line)
	f.close()
	_attempt_count += 1
	# summary 增量：per_face 取最新 verdict、attempts +1；counters 按 success 计入
	var pf: Dictionary = _summary["per_face"]
	var prev: Dictionary = pf.get(_attempt_face, {})
	pf[_attempt_face] = {
		"verdict": verdict,
		"attempts": int(prev.get("attempts", 0)) + 1,
		"link": _attempt_link,
	}
	if verdict == "success":
		_summary["counters"]["success"] = int(_summary["counters"]["success"]) + 1
	else:
		_summary["counters"]["failed"] = int(_summary["counters"]["failed"]) + 1
	_write_summary()
	_write_manifest()
	_attempt_frames = PackedStringArray()


## 进度写 summary（visited/total）
func set_progress(visited: int, total: int) -> void:
	_summary["visited"] = visited
	_summary["total"] = total
	if _base_dir.is_empty():
		return
	_write_summary()


## 当前 summary 内存态
func summary_dict() -> Dictionary:
	return _summary


## 当前累计 attempt 数（manifest 读值；文件不可读时回退内存值）
func attempt_count() -> int:
	var m: Variant = _read_manifest()
	if m is Dictionary and m.has("attempt_count"):
		return int(m["attempt_count"])
	return _attempt_count


# ================= 重置铁律 =================

## 哈希校验：manifest 缺失/损坏/哈希不符 → 递归清空 base_dir 重建 + 新 manifest；
## 哈希一致 → 保留 attempt_count 与 summary。
func _verify_and_reset() -> void:
	var manifest: Variant = _read_manifest()
	var preserved := manifest is Dictionary \
			and str(manifest.get("map_hash", "")) == _map_hash_str
	if preserved:
		_attempt_count = int(manifest.get("attempt_count", 0))
		_target_faces = int(manifest.get("target_faces", 0))
		_created_at = int(manifest.get("created_at", 0))
		_load_summary()
		DirAccess.make_dir_recursive_absolute(_attempts_dir)
		return
	# 缺失 / 损坏 / 哈希不符 —— 老图数据不得污染新图：全清重建
	_wipe_dir(_base_dir)
	DirAccess.make_dir_recursive_absolute(_attempts_dir)
	_attempt_count = 0
	_target_faces = 0
	_created_at = int(Time.get_unix_time_from_system())
	_summary = _fresh_summary()
	_write_manifest()
	print("[AutoTraversalRecord] 地图布局已变更，自动遍历记录已重置")


## 递归清空目录内容（文件 + 子目录）。DirAccess 无递归删除 API：
## 先递归清空子目录内容、再删空子目录，最后删文件。目录不存在则无操作。
static func _wipe_dir(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for sub in dir.get_directories():
		_wipe_dir(path.path_join(sub))
		dir.remove(path.path_join(sub))
	for file in dir.get_files():
		dir.remove(path.path_join(file))


# ================= 文件 IO =================

func _read_manifest() -> Variant:
	return _read_json_file(_base_dir.path_join("manifest.json"))


## JSON.new() 解析防 engine error（JSON.parse_string 会推 engine error，
## GUT 误判为未捕获异常——同 jump_recorder.gd）
func _read_json_file(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var text := f.get_as_text()
	f.close()
	var json := JSON.new()
	if json.parse(text) != OK:
		return null
	return json.data


func _write_manifest() -> void:
	var m := {
		"map_hash": _map_hash_str,
		"created_at": _created_at,
		"attempt_count": _attempt_count,
		"target_faces": _target_faces,
	}
	var f := FileAccess.open(_base_dir.path_join("manifest.json"), FileAccess.WRITE)
	if f == null:
		push_error("[AutoTraversalRecord] 无法写 manifest: %s" % _base_dir)
		return
	f.store_string(JSON.stringify(m, "\t"))
	f.close()


func _fresh_summary() -> Dictionary:
	return {
		"per_face": {},
		"counters": {"success": 0, "failed": 0},
		"visited": 0,
		"total": 0,
	}


## 从 summary.json 恢复内存态（缺失/损坏/缺键 → 默认值兜底）
func _load_summary() -> void:
	_summary = _fresh_summary()
	var data: Variant = _read_json_file(_base_dir.path_join("summary.json"))
	if data is not Dictionary:
		return
	var pf: Variant = data.get("per_face", {})
	if pf is Dictionary:
		_summary["per_face"] = pf
	var counters: Variant = data.get("counters", {})
	if counters is Dictionary:
		for key in ["success", "failed"]:
			if counters.has(key):
				_summary["counters"][key] = int(counters[key])
	_summary["visited"] = int(data.get("visited", 0))
	_summary["total"] = int(data.get("total", 0))


func _write_summary() -> void:
	var f := FileAccess.open(_base_dir.path_join("summary.json"), FileAccess.WRITE)
	if f == null:
		push_error("[AutoTraversalRecord] 无法写 summary: %s" % _base_dir)
		return
	f.store_string(JSON.stringify(_summary, "\t"))
	f.close()
