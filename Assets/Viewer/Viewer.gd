extends Node3D
# M1 资产验收查看器（重写）：角色 + 武器 转台检视，标记驱动（无魔数）。
#   鼠标拖拽旋转视角 | 滚轮缩放 | 1/2/3/4 切换武器 | 角色恒显
# 武器按 canonical 约定摆放（枪口 -Z 前），并在 Muzzle 标记处画前向射线验证枪口朝向。

const ViewModel := preload("res://Assets/Viewmodel/ViewModel.gd")

const CHARACTER := preload("res://Assets/Models/Characters/Soldier_Echo/Soldier_Echo.glb")
const WEAPONS := [
	["AK47_Echo", preload("res://Assets/Models/Weapons/Rifle/AK47_Echo/AK47_Echo.glb")],
	["Glock18_Echo", preload("res://Assets/Models/Weapons/Pistol/Glock18_Echo/Glock18_Echo.glb")],
	["Knife_Echo", preload("res://Assets/Models/Weapons/Melee/Knife_Echo/Knife_Echo.glb")],
	["Grenade_M67_Echo", preload("res://Assets/Models/Weapons/Throwable/Grenade_M67_Echo/Grenade_M67_Echo.glb")],
]

var _idx := 0
var _weapon: Node3D
var _muzzle_line: MeshInstance3D
var _yaw := 0.6
var _pitch := 0.25
var _dist := 3.2

@onready var _cam: Camera3D = $Camera
@onready var _char_root: Node3D = $Character
@onready var _weapon_root: Node3D = $WeaponRoot
@onready var _label: Label = $HUD/Label


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	# 角色（左）
	var ch := CHARACTER.instantiate()
	ch.position = Vector3(-0.7, 0, 0)
	_char_root.add_child(ch)
	# 武器（右，抬高到便于观察的高度）
	_weapon_root.position = Vector3(0.9, 1.2, 0)
	_equip(0)


func _equip(i: int) -> void:
	_idx = i
	if _weapon:
		_weapon.queue_free()
	_weapon = WEAPONS[i][1].instantiate()
	_weapon_root.add_child(_weapon)
	_draw_muzzle()
	_label.text = "武器: %s（1/2/3/4 切换）| 拖拽旋转 | 滚轮缩放" % WEAPONS[i][0]


func _draw_muzzle() -> void:
	if _muzzle_line:
		_muzzle_line.queue_free()
	_muzzle_line = null
	var muzzle := ViewModel.find_marker(_weapon, "_Muzzle")
	if muzzle == null:
		return
	# 从 Muzzle 沿武器前向（-Z）画一条红色射线 = 子弹出膛方向
	var im := ImmediateMesh.new()
	var from := muzzle.position
	var to := from + Vector3(0, 0, -1.0)  # canonical: 枪口朝 -Z
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	im.surface_add_vertex(from)
	im.surface_add_vertex(to)
	im.surface_end()
	_muzzle_line = MeshInstance3D.new()
	_muzzle_line.mesh = im
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1, 0.1, 0.1)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_muzzle_line.material_override = m
	_weapon.add_child(_muzzle_line)  # 挂武器下，随武器变换


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_yaw -= event.relative.x * 0.01
		_pitch = clamp(_pitch - event.relative.y * 0.01, -1.4, 1.4)
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_dist = max(1.2, _dist - 0.3)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_dist = min(8.0, _dist + 0.3)
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_1: _equip(0)
			KEY_2: _equip(1)
			KEY_3: _equip(2)
			KEY_4: _equip(3)


func _process(_delta: float) -> void:
	# 武器缓慢自转（便于看 ECHO 印记与枪口）
	if _weapon:
		_weapon.rotation.y += 0.4 * _delta
	var target := Vector3(0.1, 0.9, 0)
	_cam.position = target + Vector3(sin(_yaw) * cos(_pitch), sin(_pitch), cos(_yaw) * cos(_pitch)) * _dist
	_cam.look_at(target, Vector3.UP)
