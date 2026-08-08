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

## Viewmodel scale (tuned visually; per-weapon override lives in the weapon resource)
@export var vm_scale := 1.0

## Camera-space offset of the weapon grip (right, down, forward) for hip-fire.
@export var weapon_offset := Vector3(0.28, -0.33, -0.55)
## Extra pitch applied to the weapon (deg about camera X) to drop the stock.
@export var weapon_pitch_deg := 0.0
## Where the invisible shoulders sit (camera space, off-screen bottom).
@export var shoulder_right := Vector3(0.34, -0.52, 0.05)
@export var shoulder_left := Vector3(-0.16, -0.46, 0.02)

var weapon_mount: Node3D
var arms_root: Node3D
var current_weapon: Node3D = null

# blocky arm colors match Soldier_Echo
var uniform_mat := _mkmat(Color(0.35, 0.48, 0.32))
var skin_mat := _mkmat(Color(0.85, 0.68, 0.55))

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
	current_weapon = weapon_scene.instantiate()
	weapon_mount.add_child(current_weapon)
	# weapon GLB is real scale; viewmodel scales up. Origin == GripRight.
	current_weapon.transform.origin = Vector3.ZERO
	var basis := Basis(Vector3.RIGHT, deg_to_rad(weapon_pitch_deg))
	weapon_mount.transform = Transform3D(basis, weapon_offset)
	weapon_mount.scale = Vector3.ONE * vm_scale
	_build_arms()
	return current_weapon

func _build_arms() -> void:
	if current_weapon == null:
		return
	var grip_r := find_marker(current_weapon, "_GripRight")
	var grip_l := find_marker(current_weapon, "_GripLeft")
	# marker positions in ViewModel(camera) space:
	var r_pos := _to_vm(grip_r) if grip_r else weapon_offset
	# Right hand always on the grip (origin of weapon == grip).
	_make_arm(shoulder_right, r_pos, true)
	if grip_l:
		_make_arm(shoulder_left, _to_vm(grip_l), false)

func _to_vm(marker: Node3D) -> Vector3:
	# marker.global is in whatever space; convert to this ViewModel's local space.
	return to_local(marker.global_position)

## Build a two-segment blocky arm (upper + forearm + hand) to a grip point.
func _make_arm(shoulder: Vector3, hand: Vector3, is_right: bool) -> void:
	# elbow: midpoint pushed down+out for a natural bend
	var outward := 0.10 if is_right else -0.10
	var elbow := (shoulder + hand) * 0.5 + Vector3(outward, -0.06, 0.04)
	_add_limb(shoulder, elbow, Vector2(0.085, 0.085), uniform_mat)   # upper arm (sleeve)
	_add_limb(elbow, hand, Vector2(0.075, 0.075), uniform_mat)       # forearm (sleeve)
	_add_box(hand, Vector3(0.10, 0.10, 0.12), skin_mat)              # blocky hand on grip

func _add_limb(a: Vector3, b: Vector3, thick: Vector2, mat: Material) -> void:
	var dir := b - a
	var len := dir.length()
	if len < 1e-4:
		return
	var bm := BoxMesh.new()
	bm.size = Vector3(thick.x, thick.y, len)
	var mi := MeshInstance3D.new()
	mi.mesh = bm
	mi.material_override = mat
	arms_root.add_child(mi)
	mi.position = (a + b) * 0.5
	# orient box +Z along (a->b)
	var up := Vector3.UP if abs(dir.normalized().dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	mi.look_at_from_position((a + b) * 0.5, b, up)  # -Z faces b; box spans a..b (symmetric)

func _add_box(pos: Vector3, size: Vector3, mat: Material) -> void:
	var bm := BoxMesh.new()
	bm.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = bm
	mi.material_override = mat
	arms_root.add_child(mi)
	mi.position = pos
