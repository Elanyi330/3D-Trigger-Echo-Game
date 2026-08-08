class_name ViewModel
extends Node3D
## First-person viewmodel: a weapon + procedural blocky arms.
##
## Hand-weapon coordination is solved BY CONSTRUCTION: each hand mesh is placed
## exactly at the weapon's GripRight / GripLeft marker (baked into the GLB by
## tools/render/process_weapon.py), and a forearm segment stretches from an
## off-screen shoulder anchor to that hand. Because hand positions are READ from
## the weapon's markers, the hands always grip the weapon — no magic angles.
##
## Usage: add as child of the Camera, call equip(weapon_scene).

## Viewmodel scale (tuned visually; per-weapon override lives in WEAPON_FRAME)
@export var vm_scale := 1.0

## Camera-space offset of the weapon grip (right, down, forward) for hip-fire.
@export var weapon_offset := Vector3(0.28, -0.33, -0.55)
## Extra pitch applied to the weapon (deg about camera X) to drop the stock.
@export var weapon_pitch_deg := 0.0
## Where the invisible shoulders sit (camera space, off-screen bottom).
@export var shoulder_right := Vector3(0.40, -0.58, 0.08)
@export var shoulder_left := Vector3(-0.24, -0.52, 0.02)

## 每件武器的取景（CS 手感）：offset=相机空间握把位 / scale=视图缩放 / rot=持握欧拉角(度)。
## CS 对比校准（agent 评估）：手枪长≈2.3×拳宽、雷体≈屏宽12-18%上移入画、刀上移抬头25-30°。
const WEAPON_FRAME := {
	"AK47_Echo": {"offset": Vector3(0.28, -0.33, -0.55), "scale": 1.0, "rot": Vector3(0, 0, 0)},
	"Glock18_Echo": {"offset": Vector3(0.20, -0.24, -0.46), "scale": 2.0, "rot": Vector3(-7.0, 0, 0)},
	"Knife_Echo": {"offset": Vector3(0.20, -0.20, -0.40), "scale": 1.5, "rot": Vector3(25.0, 30.0, 0.0)},
	"Grenade_M67_Echo": {"offset": Vector3(0.10, -0.18, -0.38), "scale": 2.2, "rot": Vector3(-18.0, 0, 0)},
}

var weapon_mount: Node3D
var arms_root: Node3D
var current_weapon: Node3D = null
# 基础取景（equip 设定），动画在此基础上叠加（WeaponView 读取）
var base_offset := Vector3.ZERO
var base_rotation := Vector3.ZERO

# 动态手臂（每帧追踪握把标记）：肩部固定屏外，手部始终贴在武器握把上——
# 换弹/挥砍/后坐力动武器时，手不脱把、肩不入镜。
var _arms := []  # [{shoulder, grip, upper, fore, hand, is_right}]

# blocky arm colors match Soldier_Echo（与角色本体同色系——第一人称不割裂）
var uniform_mat := _mkmat(Color(0.35, 0.48, 0.32))       # 与角色 UNIFORM 一致（上臂）
var uniform_dark_mat := _mkmat(Color(0.245, 0.336, 0.224))  # 与角色 UNIFORM_DARK 一致（前臂）
var skin_mat := _mkmat(Color(0.85, 0.68, 0.55))          # 与角色 SKIN 一致（手）

static func _mkmat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.75
	return m

func _ready() -> void:
	weapon_mount = Node3D.new()
	weapon_mount.name = "WeaponMount"
	add_child(weapon_mount)
	arms_root = Node3D.new()
	arms_root.name = "Arms"
	add_child(arms_root)

## Find a baked marker node by suffix (e.g. "_Muzzle"), model-agnostic.
static func find_marker(root: Node, suffix: String) -> Node3D:
	for n in root.find_children("*", "Node3D", true, false):
		if n.name.ends_with(suffix):
			return n
	return null

## Equip a weapon scene; rebuild arms to its grip markers.
func equip(weapon_scene: PackedScene) -> Node3D:
	if current_weapon:
		current_weapon.queue_free()
	for c in arms_root.get_children():
		c.queue_free()
	_arms.clear()
	current_weapon = weapon_scene.instantiate()
	weapon_mount.add_child(current_weapon)
	# weapon GLB is real scale; viewmodel scales up. Origin == GripRight.
	current_weapon.transform.origin = Vector3.ZERO
	# 每件武器独立取景（WEAPON_FRAME，按根节点名匹配；无配置用导出默认）
	var frame: Dictionary = WEAPON_FRAME.get(current_weapon.name, {})
	var off: Vector3 = frame.get("offset", weapon_offset)
	var scl: float = frame.get("scale", vm_scale)
	var rot: Vector3 = frame.get("rot", Vector3(weapon_pitch_deg, 0, 0))
	var basis := Basis.from_euler(Vector3(deg_to_rad(rot.x), deg_to_rad(rot.y), deg_to_rad(rot.z)))
	weapon_mount.transform = Transform3D(basis, off)
	weapon_mount.scale = Vector3.ONE * scl
	base_offset = off
	base_rotation = Vector3(deg_to_rad(rot.x), deg_to_rad(rot.y), deg_to_rad(rot.z))
	_build_arms()
	return current_weapon

func _build_arms() -> void:
	if current_weapon == null:
		return
	var grip_r := find_marker(current_weapon, "_GripRight")
	var grip_l := find_marker(current_weapon, "_GripLeft")
	if grip_r:
		_arms.append(_make_arm(shoulder_right, grip_r, true))
	if grip_l:
		_arms.append(_make_arm(shoulder_left, grip_l, false))
	_update_arms()

func _make_arm(shoulder: Vector3, grip: Node3D, is_right: bool) -> Dictionary:
	# 与 Soldier_Echo 手臂同尺寸（x 宽 × y 厚）：上臂 0.11×0.13 / 前臂 0.10×0.11 / 手 0.10×0.11×0.13
	var upper := _new_segment(Vector2(0.11, 0.13), uniform_mat)
	var fore := _new_segment(Vector2(0.10, 0.11), uniform_dark_mat)
	var hand := _new_segment(Vector2(0.10, 0.11), skin_mat)
	(hand.mesh as BoxMesh).size = Vector3(0.10, 0.11, 0.13)
	return {"shoulder": shoulder, "grip": grip, "upper": upper, "fore": fore, "hand": hand, "is_right": is_right}

func _new_segment(cross: Vector2, mat: Material) -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = Vector3(cross.x, cross.y, 1.0)  # z 长度在 _set_limb 设定
	var mi := MeshInstance3D.new()
	mi.mesh = bm
	mi.material_override = mat
	arms_root.add_child(mi)
	return mi

func _physics_process(_delta: float) -> void:
	_update_arms()

func _update_arms() -> void:
	for arm in _arms:
		if not is_instance_valid(arm["grip"]):
			continue
		# 手部目标 = 握把标记在 ViewModel 本地空间的位置（随武器动画实时变化）
		var hand_pos := to_local((arm["grip"] as Node3D).global_position)
		var shoulder: Vector3 = arm["shoulder"]
		var outward := 0.10 if arm["is_right"] else -0.10
		var elbow := (shoulder + hand_pos) * 0.5 + Vector3(outward, -0.06, 0.04)
		_set_limb(arm["upper"], shoulder, elbow)
		_set_limb(arm["fore"], elbow, hand_pos)
		(arm["hand"] as Node3D).position = hand_pos

func _set_limb(mi: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var dir := b - a
	var len := dir.length()
	if len < 1e-4:
		mi.visible = false
		return
	mi.visible = true
	(mi.mesh as BoxMesh).size.z = len
	mi.position = (a + b) * 0.5
	var up := Vector3.UP if abs(dir.normalized().dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	mi.look_at_from_position((a + b) * 0.5, b, up)  # -Z faces b; box spans a..b
