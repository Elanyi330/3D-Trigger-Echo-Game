# test/unit/test_grip_rig.gd
# M1.75 统一持握 GripRig 测试（TDD RED 先行）
#
# 行为：对 Soldier_Echo 真骨架双臂两骨 IK，方块手到达武器 _GripRight/_GripLeft 标记位。
#   - 右手腕（Hand_R）到达武器原点（=GripRight）
#   - 有 _GripLeft 的步枪：左腕（Hand_L）到达 GripLeft 标记（双手据枪）
#   - 单手持武器（手枪）：左手回静息（不悬空乱摆）
#   - equip 换武器：旧武器实例释放、新武器挂上
# 手位经 BoneAttachment3D 读取（与游戏内持枪挂接同路径）。
extends GutTest

const CHAR := "res://Assets/Models/Characters/Soldier_Echo/Soldier_Echo.glb"
const AK := "res://Assets/Models/Weapons/Rifle/AK47_Echo/AK47_Echo.glb"
const GLOCK := "res://Assets/Models/Weapons/Pistol/Glock18_Echo/Glock18_Echo.glb"

var char: Node3D
var skel: Skeleton3D
var rig: GripRig


func before_each() -> void:
	char = load(CHAR).instantiate()
	add_child_autofree(char)
	skel = _find_skeleton(char)
	rig = GripRig.new()
	add_child_autofree(rig)
	rig.setup(skel)


func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var r := _find_skeleton(c)
		if r:
			return r
	return null


func _bone_world_pos(bone_name: String) -> Vector3:
	# BoneAttachment 需入树一帧完成 bone_name 绑定，才能同步到骨骼位
	var ba := BoneAttachment3D.new()
	ba.bone_name = bone_name
	skel.add_child(ba)
	await get_tree().process_frame
	ba.force_update_transform()
	var p: Vector3 = ba.global_position
	ba.free()
	return p


func test_right_hand_reaches_grip_rifle() -> void:
	rig.equip(load(AK))
	await wait_physics_frames(3)
	var hand_r := await _bone_world_pos("Hand_R")
	var grip_target: Vector3 = rig._mount.global_position  # 武器原点=GripRight
	assert_lt(hand_r.distance_to(grip_target), 0.04,
			"右手腕到达 AK 右手握把（GripRight）——两骨 IK 命中")


func test_left_hand_reaches_handguard_rifle() -> void:
	rig.equip(load(AK))
	await wait_physics_frames(3)
	var marker := GripRig.find_marker(rig._weapon, "_GripLeft")
	assert_not_null(marker, "前置：AK 有 _GripLeft 护木标记")
	var hand_l := await _bone_world_pos("Hand_L")
	assert_lt(hand_l.distance_to(marker.global_position), 0.05,
			"左手腕到达 AK 护木（GripLeft）——双手据枪")


func test_one_hand_pistol_left_arm_rests() -> void:
	rig.equip(load(GLOCK))
	await wait_physics_frames(3)
	var marker := GripRig.find_marker(rig._weapon, "_GripLeft")
	assert_null(marker, "前置：Glock 无 _GripLeft（单手）")
	# 左手回静息：应接近静息全局位（下垂身侧），而非悬空举起
	var hand_l := await _bone_world_pos("Hand_L")
	var rest_l: Vector3 = skel.get_bone_global_rest(skel.find_bone("Hand_L")).origin
	# 骨架局部系 → 世界系比较
	var rest_world := skel.to_global(rest_l)
	assert_lt(hand_l.distance_to(rest_world), 0.05, "单手持枪：左手回静息位")


func test_equip_replaces_weapon() -> void:
	var first := rig.equip(load(AK))
	await wait_physics_frames(2)
	var second := rig.equip(load(GLOCK))
	await wait_physics_frames(2)
	assert_true(not is_instance_valid(first) or first.is_queued_for_deletion(), "旧武器被释放")
	assert_eq(rig._weapon, second, "当前武器 = 新装备的 Glock")
