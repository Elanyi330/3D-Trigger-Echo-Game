# Character/GripRig.gd
# M1.75 统一持握 rig（设计：2026-08-10-m175-unified-grip-cs-damage-design.md §3.1）
#
# 目标：玩家/敌人/队友共用同一组件、同一持握数据，对 Soldier_Echo 真骨架做双臂两骨 IK，
# 方块手精确到达武器 _GripRight/_GripLeft 标记位（"构造保证"理念，ViewModel 的升级版）。
#
# 保真度约束（用户拍板）：**不做精致手模**——手 = Soldier_Echo 现有方块手，只摆到握把位，
# 不建模手指/握持细节，不新增手部资产。
#
# 机理（两骨 IK）：
#   - 武器挂在 WeaponMount（角色根空间），位姿取自 GRIP_STYLE（唯一持握数据源）。
#   - 武器原点 = _GripRight（资产约定），故右手 IK 目标 = mount 全局位。
#   - 有 _GripLeft 标记（步枪）则左手 IK 目标 = 该标记全局位（双手据枪）。
#   - 每物理帧重解：mount 动（玩家 sway/后坐/换弹）手自动跟随，不脱把。
#
# 骨骼（Soldier_Echo 18 骨）：Shoulder→UpperArm→Forearm→Hand（_L/_R）。静息手臂垂直下垂(-Y)。
# pose 语义（Godot4）：bone_global = bone_global_rest * pose（父骨在 rest 时），post-multiply 局部 rest 系。
class_name GripRig
extends Node3D

# 型号无关的标记后缀匹配（同 ViewModel.find_marker 逻辑，独立实现以免依赖将被退役的 ViewModel）
static func find_marker(root: Node, suffix: String) -> Node3D:
	if root == null:
		return null
	for n in root.find_children("*", "Node3D", true, false):
		if n.name.ends_with(suffix):
			return n
	return null

# GRIP_STYLE 不再手调：第三人称持握**直接向第一人称看齐**——
# 从 ViewModel.WEAPON_FRAME（第一人称相机空间握把位，已 CS 校准）推导角色空间 mount 位姿。
# 相机空间 (right, up, forward=-Z) → 角色空间：右=−X、上=+Y（眼位基准）、前=−Z。
# 真实尺寸（scale=1，第三人称不放大），保证"眼睛挂相机即复现第一人称握持"。
const VM := preload("res://Assets/Viewmodel/ViewModel.gd")
const EYE_Y := 1.63  # CS 站立眼位 64u≈1.626m
const DEFAULT_OFFSET := Vector3(0.25, -0.30, -0.50)


func _style_for(weapon_name: String) -> Dictionary:
	var f: Dictionary = VM.WEAPON_FRAME.get(weapon_name, {})
	var off: Vector3 = f.get("offset", DEFAULT_OFFSET)
	var rot: Vector3 = f.get("rot", Vector3.ZERO)
	return {"pos": Vector3(-off.x, EYE_Y + off.y, off.z), "rot": rot}

var _skel: Skeleton3D
var _mount: Node3D
var _weapon: Node3D
var _grip_left_marker: Node3D
var _style: Dictionary = {}
# 动画层偏移（玩家手感：reload/swing/throw/ADS 由 WeaponView 每帧写入，叠加在 GRIP_STYLE 基准上）。
# 敌人不写入（恒 ZERO），保证"核心动作不变、玩家仅微调"。
var anim_pos := Vector3.ZERO
var anim_rot := Vector3.ZERO
var _base_pos := Vector3.ZERO
var _base_rot := Vector3.ZERO
# 臂长（setup 时从骨架静息位读取，IK 用）
var _L1 := {"R": 0.0, "L": 0.0}  # 上臂 肩→肘
var _L2 := {"R": 0.0, "L": 0.0}  # 前臂 肘→腕


func setup(skeleton: Skeleton3D) -> void:
	_skel = skeleton
	_measure_arms()


func equip(weapon_scene: PackedScene) -> Node3D:
	unequip()
	if _skel == null:
		return null
	_weapon = weapon_scene.instantiate()
	_mount = Node3D.new()
	_mount.name = "WeaponMount"
	# 挂骨架节点（角色空间，随角色动但不随单根骨头动）
	_skel.add_child(_mount)
	_mount.add_child(_weapon)
	var style: Dictionary = _style_for(_weapon.name)
	_style = style
	_base_pos = style["pos"]
	_base_rot = Vector3(deg_to_rad(style["rot"].x), deg_to_rad(style["rot"].y), deg_to_rad(style["rot"].z))
	_grip_left_marker = find_marker(_weapon, "_GripLeft")
	if _grip_left_marker != null:
		# 双手武器：FP 偏移对真实左臂过远（护木在右前，左肩跨不过去）。
		# 向中线/身体收拢，保证左臂物理可达，同时保持"举枪前指"的第一人称观感。
		_base_pos = Vector3(_base_pos.x * 0.45, _base_pos.y, _base_pos.z * 0.65)
	_apply_mount()
	_pose_arms()
	return _weapon


# 每帧把 mount 位姿 = GRIP_STYLE 基准 + 动画层偏移；再 IK 解手臂（手随武器动，不脱把）。
func _apply_mount() -> void:
	if _mount == null:
		return
	_mount.position = _base_pos + anim_pos
	_mount.rotation = _base_rot + anim_rot


func set_anim_offset(p: Vector3, r: Vector3) -> void:
	anim_pos = p
	anim_rot = r


func unequip() -> void:
	if _weapon != null and is_instance_valid(_weapon):
		_weapon.queue_free()
	if _mount != null and is_instance_valid(_mount):
		_mount.queue_free()
	_weapon = null
	_mount = null
	_grip_left_marker = null


func _physics_process(_delta: float) -> void:
	if _skel != null and _weapon != null:
		_apply_mount()
		_pose_arms()


# ---- 臂长测量（静息全局位） ----
func _measure_arms() -> void:
	for side in ["R", "L"]:
		var ua := _skel.find_bone("UpperArm_" + side)
		var fa := _skel.find_bone("Forearm_" + side)
		var ha := _skel.find_bone("Hand_" + side)
		if ua < 0 or fa < 0 or ha < 0:
			continue
		var S: Vector3 = _skel.get_bone_global_rest(ua).origin
		var E: Vector3 = _skel.get_bone_global_rest(fa).origin
		var W: Vector3 = _skel.get_bone_global_rest(ha).origin
		_L1[side] = S.distance_to(E)
		_L2[side] = E.distance_to(W)


# ---- 每帧姿态解算（统一在骨架局部空间：get_bone_global_rest 为骨架系，角色移动不失配） ----
func _pose_arms() -> void:
	# 右手目标 = mount 位（武器原点=GripRight；mount 为骨架子节点，to_local 转骨架系）
	var right_target := _skel.to_local(_mount.global_position)
	_solve_arm("R", right_target)
	# 左手：有 _GripLeft 标记（步枪）→ 解算到标记；否则回到静息
	if _grip_left_marker != null and is_instance_valid(_grip_left_marker):
		_solve_arm("L", _skel.to_local(_grip_left_marker.global_position))
	else:
		_rest_arm("L")


# 两骨 IK：令 Hand_<side> 腕骨到达 target（骨架局部空间）。
# Godot pose 语义（实测）：set_bone_pose_rotation 设的是**绝对局部旋转**（替换 rest 旋转，非偏移）。
# 骨骼子方向 = 该骨局部 +Y（子骨 rest.origin 沿父骨 +Y）。故 bone_world_basis = parent_world_basis × q。
func _solve_arm(side: String, target: Vector3) -> void:
	var ua := _skel.find_bone("UpperArm_" + side)
	var fa := _skel.find_bone("Forearm_" + side)
	var ha := _skel.find_bone("Hand_" + side)
	if ua < 0 or fa < 0 or ha < 0:
		return
	var S: Vector3 = _skel.get_bone_global_rest(ua).origin  # 肩关节（上臂原点）
	var L1: float = _L1[side]
	var L2: float = _L2[side]
	if L1 <= 0.0 or L2 <= 0.0:
		return
	# --- 余弦定理解肘位 ---
	var to_t := target - S
	var dist := clampf(to_t.length(), 0.0001, L1 + L2 - 0.0001)
	var dir := to_t.normalized()
	var a := (L1 * L1 - L2 * L2 + dist * dist) / (2.0 * dist)
	var h := sqrt(maxf(L1 * L1 - a * a, 0.0))
	# 极向（肘弯方向）：向下 + 向外侧 + 略向后，自然持枪肘姿
	var out_x := -0.35 if side == "R" else 0.35
	var pole_target := S + Vector3(out_x, -0.45, 0.20)
	var pole_vec := pole_target - S
	var perp := pole_vec - dir * pole_vec.dot(dir)
	if perp.length() < 0.0001:
		perp = Vector3(0, -1, 0)
	perp = perp.normalized()
	var elbow := S + dir * a + perp * h
	var D_upper := (elbow - S).normalized()  # 肩→肘 期望方向
	var D_fore := (target - elbow).normalized()  # 肘→腕 期望方向
	# --- 上臂 pose（父=Shoulder，未 pose，用其全局 rest 基）---
	var sh := _skel.get_bone_parent(ua)
	var parent_basis: Basis = _skel.get_bone_global_rest(sh).basis if sh >= 0 else Basis()
	var q_upper := Quaternion(Vector3(0, 1, 0), parent_basis.inverse() * D_upper)
	_skel.set_bone_pose_rotation(ua, q_upper)
	# --- 前臂 pose（父=UpperArm，已被 pose）---
	var upper_world_basis := parent_basis * Basis(q_upper)
	var q_fore := Quaternion(Vector3(0, 1, 0), upper_world_basis.inverse() * D_fore)
	_skel.set_bone_pose_rotation(fa, q_fore)


# 单臂回静息（非持握手）：pose 是绝对旋转，须还原为该骨的 rest 局部旋转（identity≠静息）
func _rest_arm(side: String) -> void:
	for bn in ["UpperArm_" + side, "Forearm_" + side]:
		var idx := _skel.find_bone(bn)
		if idx < 0:
			continue
		var par := _skel.get_bone_parent(idx)
		var par_basis: Basis = _skel.get_bone_global_rest(par).basis if par >= 0 else Basis()
		var rest_local: Basis = par_basis.inverse() * _skel.get_bone_global_rest(idx).basis
		_skel.set_bone_pose_rotation(idx, rest_local.get_rotation_quaternion())
