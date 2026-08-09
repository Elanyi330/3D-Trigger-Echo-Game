# Character-with-weapon render harness: pose an arm + attach a weapon to a hand bone, render.
# Iterate arm pose / weapon alignment via CLI. Run windowed:
#   godot --path . tools/render/view_character.tscn -- --weapon=AK47_Echo --armrx=80 --out=<abs.png>
extends Node3D

const CHAR := "res://Assets/Models/Characters/Soldier_Echo/Soldier_Echo.glb"
const WEAPONS := {
	"AK47_Echo": "res://Assets/Models/Weapons/Rifle/AK47_Echo/AK47_Echo.glb",
	"Glock18_Echo": "res://Assets/Models/Weapons/Pistol/Glock18_Echo/Glock18_Echo.glb",
	"Knife_Echo": "res://Assets/Models/Weapons/Melee/Knife_Echo/Knife_Echo.glb",
	"Grenade_M67_Echo": "res://Assets/Models/Weapons/Throwable/Grenade_M67_Echo/Grenade_M67_Echo.glb",
}

var weapon := "AK47_Echo"
# arm pose (bone-local euler deg): upper arm / forearm / hand
var arm_r := Vector3(0, 0, 0)
var fore_r := Vector3(0, 0, 0)
# weapon offset (in hand-bone space) + rotation (euler deg)
var wpos := Vector3(0, 0, 0)
var wrot := Vector3(0, 0, 0)
var yaw := 35.0
var pitch := 8.0
var dist := 2.6
var out := "user://char.png"
var _skel: Skeleton3D

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--weapon="): weapon = a.split("=")[1]
		elif a.begins_with("--armr="): arm_r = _v3(a)
		elif a.begins_with("--forer="): fore_r = _v3(a)
		elif a.begins_with("--wpos="): wpos = _v3(a)
		elif a.begins_with("--wrot="): wrot = _v3(a)
		elif a.begins_with("--yaw="): yaw = float(a.split("=")[1])
		elif a.begins_with("--pitch="): pitch = float(a.split("=")[1])
		elif a.begins_with("--dist="): dist = float(a.split("=")[1])
		elif a.begins_with("--out="): out = a.split("=")[1]
	var char: Node3D = load(CHAR).instantiate()
	add_child(char)
	_skel = _find_skel(char)
	_pose()
	_attach()
	_lights()
	_camera()
	_shoot()

func _v3(a: String) -> Vector3:
	var p := a.split("=")[1].split(",")
	return Vector3(float(p[0]), float(p[1]), float(p[2]))

func _find_skel(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var r := _find_skel(c)
		if r:
			return r
	return null

func _pose() -> void:
	if _skel == null:
		return
	var ua := _skel.find_bone("UpperArm_R")
	var fa := _skel.find_bone("Forearm_R")
	if ua >= 0:
		_skel.set_bone_pose_rotation(ua, Quaternion.from_euler(Vector3(deg_to_rad(arm_r.x), deg_to_rad(arm_r.y), deg_to_rad(arm_r.z))))
	if fa >= 0:
		_skel.set_bone_pose_rotation(fa, Quaternion.from_euler(Vector3(deg_to_rad(fore_r.x), deg_to_rad(fore_r.y), deg_to_rad(fore_r.z))))

func _attach() -> void:
	if _skel == null:
		return
	var ba := BoneAttachment3D.new()
	ba.bone_name = "Hand_R"
	_skel.add_child(ba)
	var w: Node3D = load(WEAPONS[weapon]).instantiate()
	ba.add_child(w)
	w.position = wpos
	w.rotation = Vector3(deg_to_rad(wrot.x), deg_to_rad(wrot.y), deg_to_rad(wrot.z))

func _lights() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	add_child(sun)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.45, 0.5, 0.55)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_energy = 0.8
	env.environment = e
	add_child(env)

func _camera() -> void:
	var cam := Camera3D.new()
	cam.current = true
	add_child(cam)
	var yr := deg_to_rad(yaw)
	var pr := deg_to_rad(pitch)
	cam.position = Vector3(sin(yr) * cos(pr), sin(pr), cos(yr) * cos(pr)) * dist + Vector3(0, 1.0, 0)
	cam.look_at(Vector3(0, 1.0, 0), Vector3.UP)

func _shoot() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(out))
	print("CHAR VIEW SAVED ", ProjectSettings.globalize_path(out))
	get_tree().quit()
