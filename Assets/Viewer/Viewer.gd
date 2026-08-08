extends Node3D

# 资产查看器：人物 + 四种武器持枪姿态（Godot 代码控制朝向，绕开 Blender 矩阵坑）

var character_scene = preload("res://Assets/Models/Characters/Player/Player.glb")
var weapon_scenes = {
	"AK47": preload("res://Assets/Models/Weapons/AK47/AK47.glb"),
	"Glock18": preload("res://Assets/Models/Weapons/Glock18/Glock18.glb"),
	"Knife": preload("res://Assets/Models/Weapons/Knife/Knife.glb"),
	"Grenade": preload("res://Assets/Models/Weapons/Grenade/Grenade.glb"),
}
var current_weapon := 0
var weapon_names := ["AK47", "Glock18", "Knife", "Grenade"]

# 相机旋转（鼠标拖拽查看）
var cam_yaw := 0.0
var cam_pitch := 0.3
var cam_distance := 4.0

@onready var camera: Camera3D = $Camera
@onready var char_instance: Node3D = $Character
@onready var weapon_root: Node3D = $WeaponRoot
@onready var label: Label = $HUD/Label


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	# 人物实例
	var char_inst: Node3D = character_scene.instantiate()
	char_instance.add_child(char_inst)
	# 人物朝向修正：Blender 面朝 -Y → Godot glTF 导入后面朝 +Z（后方），转 180° 面朝 -Z 前方
	char_instance.rotation.y = PI
	# 初始武器
	equip_weapon(0)
	label.text = "武器: AK47（1/2/3/4 切换）| 鼠标拖拽旋转 | 滚轮缩放"


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		cam_yaw -= event.relative.x * 0.01
		cam_pitch = clamp(cam_pitch - event.relative.y * 0.01, -1.4, 1.4)
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			cam_distance = max(1.5, cam_distance - 0.5)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			cam_distance = min(10.0, cam_distance + 0.5)
		elif event.pressed and event.button_index >= MOUSE_BUTTON_LEFT and event.button_index <= 4:
			var idx = int(event.button_index) - 1
			if idx < 4:
				equip_weapon(idx)


func _process(delta: float) -> void:
	camera.position = Vector3(sin(cam_yaw) * cam_distance, 1.3 + sin(cam_pitch) * cam_distance * 0.6, cos(cam_yaw) * cam_distance)
	camera.look_at(Vector3.ZERO, Vector3.UP)


func equip_weapon(idx: int) -> void:
	# 清除旧武器
	for child in weapon_root.get_children():
		child.queue_free()
	# 实例化新武器
	var weapon: Node3D = weapon_scenes[weapon_names[idx]].instantiate()
	weapon_root.add_child(weapon)
	# 朝向控制（枪口朝前 -Z）：绕 Y 转 -90°（枪口 +X → -Z 前方）
	weapon.rotation = Vector3(0, -1.5708, 0)
	# 位置：胸前双手位
	weapon.position = Vector3(0.3, 1.25, -0.4)
	current_weapon = idx
	# 调整人物手臂骨骼：双手前伸握枪（肘部弯曲）
	_pose_arms()
	label.text = "武器: %s（1/2/3/4 切换）| 鼠标拖拽旋转 | 滚轮缩放" % weapon_names[idx]


func _pose_arms() -> void:
	# 找到人物骨骼，摆出握枪姿势（肩前转 + 肘弯）
	var armature := _find_armature(char_instance)
	if armature == null:
		print("未找到人物骨骼，跳过手臂姿势")
		return
	var skeleton: Skeleton3D = armature
	# 用骨骼 pose 摆姿势（右手握扳机、左手托护木）
	var bone_names := ["ShoulderR", "ElbowR", "ShoulderL", "ElbowL"]
	var rotations := {
		"ShoulderR": Vector3(1.2, 0, -0.3),
		"ElbowR": Vector3(0.8, 0, 0.3),
		"ShoulderL": Vector3(1.2, 0, 0.3),
		"ElbowL": Vector3(0.8, 0, -0.3),
	}
	for bone_name in bone_names:
		var bone_idx := skeleton.find_bone(bone_name)
		if bone_idx != -1:
			# Vector3 欧拉角 → Quaternion
			var quat := Quaternion.from_euler(rotations[bone_name])
			skeleton.set_bone_pose_rotation(bone_idx, quat)
	print("手臂姿势已设置")


func _find_armature(node: Node) -> Skeleton3D:
	for child in node.get_children():
		if child is Skeleton3D:
			return child
		var found := _find_armature(child)
		if found != null:
			return found
	return null
