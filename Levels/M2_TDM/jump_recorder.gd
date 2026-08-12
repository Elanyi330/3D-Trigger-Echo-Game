# Levels/M2_TDM/jump_recorder.gd
# 任务 15：跳跃记录场景层——episode 检测/采样/写盘 + 地图哈希重置铁律。
#
# 用户铁律（2026-08-11）：记录测试者跳上建筑的操作供未来 AI 学习；
# **地图每改动一次必须重置全部跳跃记录**——setup 时以布局哈希比对 manifest：
# 文件缺失 / JSON 损坏 / 哈希不符 → 递归清空 base_dir 重建，老图数据不留。
#
# 物理帧序说明（Godot 4.7.1 实测）：_physics_process 回调按**树序**执行，
# process_priority 对物理回调无效（仅影响 _process）；PROCESS_PHYSICS_PRIORITY_*
# 常量在 4.7 中不存在。因此"在玩家 move_and_slide 之后读当帧状态"由树序保证：
# 调用方必须在玩家入树之后再 add_child 本节点并 setup（L_M2.gd 已按此装配）。
#
# 缝方法（_begin_episode/_sample_frame/_end_episode/_force_timeout）为测试驱动而公开，
# 文件级单测无需真实玩家即可覆盖写盘/重置/分类逻辑（test/unit/test_jump_recorder.gd）。
class_name JumpRecorder
extends Node

@export var recording_enabled := true
const MAX_EPISODE_TIME := 5.0     # 单 episode 超时（秒）
const LANDING_CONFIRM := 0.5      # 落地稳定确认时长（秒）
# 碰撞法线阈值（F2a-P3）：与玩家 floor_max_angle 同源——setup 时
# _floor_normal_y := cos(player.floor_max_angle)。与 Player/MovementController.gd
# step-up 的法线阈值（同为 cos(floor_max_angle)）保持一致，避免 45° 边界坡度
# 引擎判墙/记录判地的口径分裂。45° 为 CharacterBody3D 默认值（player 缺省兜底）。
var _floor_normal_y := cos(deg_to_rad(45.0))

var _player: CharacterBody3D = null
var _head: Node3D = null
var _map_name := ""
var _base_dir := ""
var _episodes_dir := ""
var _map_hash_str := ""
var _episode_count := 0

# ---- episode 运行时状态 ----
var _episode_active := false
var _start_floor_y := 0.0
var _start_name := ""
var _elapsed := 0.0               # episode 累计时长（秒）
var _landed := 0.0                # 当前连续落地累计（秒）——离地即清零
var _end_floor_y := 0.0
var _end_name := ""
var _frames := PackedStringArray()  # 已序列化帧行（写盘用）
var _was_on_floor := true
var _last_floor_y := 0.0
var _last_floor_name := ""


## 装配入口。必须在 add_child 之后、且玩家已在树中调用（树序=物理序）。
## base_dir 可注入（测试用临时目录）。
func setup(player: CharacterBody3D, layout_solids: Array, map_name: String,
		base_dir: String = "user://jump_training") -> void:
	_player = player
	# F2a-P3：法线阈值从玩家 floor_max_angle 计算（与 MovementController step-up 同源）；
	# player 为 null（文件级测试）沿用 45° 默认兜底
	if player != null:
		_floor_normal_y = cos(player.floor_max_angle)
	_head = player.get_node_or_null("Head") if player else null
	_map_name = map_name
	_base_dir = base_dir
	_episodes_dir = base_dir.path_join("episodes")
	_map_hash_str = JumpRecordCore.map_hash(layout_solids)
	_verify_and_reset()


## 当前累计 episode 数（manifest 读值；文件不可读时回退内存值）
func episode_count() -> int:
	var m: Variant = _read_manifest()
	if m is Dictionary and m.has("episode_count"):
		return int(m["episode_count"])
	return _episode_count


## 当前布局哈希（setup 时计算）
func current_hash() -> String:
	return _map_hash_str


# ================= 重置铁律 =================

## 哈希校验：manifest 缺失/损坏/哈希不符 → 递归清空 base_dir 重建 + 新 manifest；
## 哈希一致 → 保留数据，episode_count 沿用。
func _verify_and_reset() -> void:
	var manifest: Variant = _read_manifest()
	var preserved := manifest is Dictionary \
			and str(manifest.get("map_hash", "")) == _map_hash_str
	if preserved:
		_episode_count = int(manifest.get("episode_count", 0))
		DirAccess.make_dir_recursive_absolute(_episodes_dir)
		return
	# 缺失 / 损坏 / 哈希不符 —— 老图数据不得污染新图：全清重建
	_wipe_dir(_base_dir)
	DirAccess.make_dir_recursive_absolute(_episodes_dir)
	_episode_count = 0
	_write_manifest()
	print("[JumpRecorder] 地图布局已变更，跳跃记录已重置")


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


func _read_manifest() -> Variant:
	var path := _base_dir.path_join("manifest.json")
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var text := f.get_as_text()
	f.close()
	# 用 JSON 实例 parse：非法 JSON 返回错误码而非引擎报错
	# （JSON.parse_string 会推 engine error，GUT 误判为未捕获异常）
	var json := JSON.new()
	if json.parse(text) != OK:
		return null
	return json.data


func _write_manifest() -> void:
	var m := JumpRecordCore.manifest_dict(_map_hash_str, _map_name, _episode_count)
	var f := FileAccess.open(_base_dir.path_join("manifest.json"), FileAccess.WRITE)
	if f == null:
		push_error("[JumpRecorder] 无法写 manifest: %s" % _base_dir)
		return
	f.store_string(JSON.stringify(m, "\t"))
	f.close()


# ================= episode 检测与采样 =================

func _physics_process(delta: float) -> void:
	if not recording_enabled or _player == null:
		return
	var on_floor := _player.is_on_floor()
	var floor_y := 0.0
	var floor_name := ""
	var col := _find_floor_collision()
	if col != null:
		floor_y = col.get_position().y  # 接触点 y = 踩踏面高度
		floor_name = _collider_name(col)
	# 地面信息守卫（终审 M3）：仅当找到法线 y≥_floor_normal_y 的碰撞才覆盖；
	# on_floor 但无合格碰撞的理论分支保留上次地面信息，防 0/"" 误分类。
	if on_floor and col != null:
		_last_floor_y = floor_y
		_last_floor_name = floor_name

	if not _episode_active:
		# 起跳判定：上帧在地面 + 本帧离地 + 向上速度 → 开 episode
		if _was_on_floor and not on_floor and _player.velocity.y > 0.0:
			_begin_episode(_last_floor_y, _last_floor_name)
			_sample_frame(_build_frame(delta))
	else:
		_elapsed += delta
		if on_floor and col != null:
			_landed += delta
			_end_floor_y = floor_y
			_end_name = floor_name
		elif not on_floor:
			_landed = 0.0  # 落地确认中途再次离地 → 重新累计
		_sample_frame(_build_frame(delta))
		if _elapsed >= MAX_EPISODE_TIME:
			_force_timeout()
		elif _landed >= LANDING_CONFIRM:
			_end_episode(_end_floor_y, _end_name)
	_was_on_floor = on_floor


## 遍历当帧滑动碰撞，取法线 y≥_floor_normal_y（=cos(player.floor_max_angle)，
## 与引擎地板判定同源）的碰撞体为踩踏面
func _find_floor_collision() -> KinematicCollision3D:
	if _player == null:
		return null
	for i in _player.get_slide_collision_count():
		var col := _player.get_slide_collision(i)
		if col.get_normal().y >= _floor_normal_y:
			return col
	return null


func _collider_name(col: KinematicCollision3D) -> String:
	var collider := col.get_collider()
	return str(collider.name) if collider else ""


## 组装当帧采样行（生产路径）：字段表见 brief——
## t_ms/px..pz/vx..vz/yaw/pitch/ix,iy/crouch/jump_held/on_floor/floor_name
func _build_frame(_delta: float) -> Dictionary:
	var p := _player.global_position
	var v := _player.velocity
	var axis: Variant = _player.get("input_axis")
	var crouch: Variant = _player.get("is_crouching")
	var floor_name := ""
	var col := _find_floor_collision()
	if col != null:
		floor_name = _collider_name(col)
	return {
		"t_ms": int(round(_elapsed * 1000.0)),
		"px": snappedf(p.x, 0.001), "py": snappedf(p.y, 0.001), "pz": snappedf(p.z, 0.001),
		"vx": snappedf(v.x, 0.001), "vy": snappedf(v.y, 0.001), "vz": snappedf(v.z, 0.001),
		"yaw": snappedf(_player.rotation.y, 0.001),
		"pitch": snappedf(_head.rotation.x, 0.001) if _head else 0.0,
		"ix": snappedf(axis.x, 0.001) if axis is Vector2 else 0.0,
		"iy": snappedf(axis.y, 0.001) if axis is Vector2 else 0.0,
		"crouch": bool(crouch) if crouch != null else false,
		"jump_held": Input.is_action_pressed("jump"),
		"on_floor": _player.is_on_floor(),
		"floor_name": floor_name,
	}


# ================= 缝方法（测试可直驱） =================

## 开 episode：记录起跳踩踏面与计时归零
func _begin_episode(start_floor_y: float, start_name: String) -> void:
	_episode_active = true
	_start_floor_y = start_floor_y
	_start_name = start_name
	_elapsed = 0.0
	_landed = 0.0
	_end_floor_y = start_floor_y
	_end_name = start_name
	_frames = PackedStringArray()


## 采样一帧（frame 为已组装好的帧字典；序列化为一行 JSON 入缓冲）
func _sample_frame(frame: Dictionary) -> void:
	if not _episode_active:
		return
	_frames.append(JSON.stringify(frame))


## 结束 episode：分类 → 写 episodes/ep_%04d.jsonl → manifest 计数 +1 落盘
func _end_episode(end_floor_y: float, end_name: String) -> void:
	if not _episode_active:
		return
	_episode_active = false
	if _base_dir.is_empty():
		return  # 未 setup（测试兜底）：丢弃缓冲不落盘
	var meta := {
		"episode_id": _episode_count,
		"map_hash": _map_hash_str,
		"map_name": _map_name,
		"classification": JumpRecordCore.classify_episode(
				_start_floor_y, end_floor_y, _start_name, end_name),
		"start_floor_y": snappedf(_start_floor_y, 0.001),
		"end_floor_y": snappedf(end_floor_y, 0.001),
		"start_name": _start_name,
		"end_name": end_name,
		"net_rise": snappedf(end_floor_y - _start_floor_y, 0.001),
		"frame_count": _frames.size(),
	}
	var path := _episodes_dir.path_join("ep_%04d.jsonl" % meta["episode_id"])
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("[JumpRecorder] 无法写 episode 文件: %s" % path)
		return
	f.store_line(JSON.stringify(meta))
	for line in _frames:
		f.store_line(line)
	f.close()
	_episode_count += 1
	_write_manifest()
	_frames = PackedStringArray()


## 超时收尾：end 值 = start 值（同面净升 0 → 分类为 fail）
func _force_timeout() -> void:
	_end_episode(_start_floor_y, _start_name)


# ================= 退出保存 =================

## 退出时若有进行中 episode，按超时路径收尾写盘（不丢已采样的帧）
func _exit_tree() -> void:
	if _episode_active:
		_force_timeout()
