# GripRig render harness: 统一持握组件的姿态肉眼验证。窗口运行：
#   godot --path . tools/render/view_grip.tscn -- --weapon=AK47_Echo --yaw=35 --out=<abs.png>
extends Node3D

const CHAR := "res://Assets/Models/Characters/Soldier_Echo/Soldier_Echo.glb"
const WEAPONS := {
	"AK47_Echo": "res://Assets/Models/Weapons/Rifle/AK47_Echo/AK47_Echo.glb",
	"Glock18_Echo": "res://Assets/Models/Weapons/Pistol/Glock18_Echo/Glock18_Echo.glb",
	"Knife_Echo": "res://Assets/Models/Weapons/Melee/Knife_Echo/Knife_Echo.glb",
	"Grenade_M67_Echo": "res://Assets/Models/Weapons/Throwable/Grenade_M67_Echo/Grenade_M67_Echo.glb",
}

var weapon := "AK47_Echo"
var yaw := 35.0
var pitch := 8.0
var dist := 2.6
var out := "user://grip.png"
var _rig: GripRig

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--weapon="): weapon = a.split("=")[1]
		elif a.begins_with("--yaw="): yaw = float(a.split("=")[1])
		elif a.begins_with("--pitch="): pitch = float(a.split("=")[1])
		elif a.begins_with("--dist="): dist = float(a.split("=")[1])
		elif a.begins_with("--out="): out = a.split("=")[1]
	var char: Node3D = load(CHAR).instantiate()
	add_child(char)
	var skel := _find_skel(char)
	_rig = GripRig.new()
	add_child(_rig)
	_rig.setup(skel)
	_rig.equip(load(WEAPONS[weapon]))
	_lights()
	_camera()
	_shoot()

func _find_skel(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var r := _find_skel(c)
		if r:
			return r
	return null

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
	for i in 8:  # 等渲染帧让 GripRig IK 稳定 + 首帧绘制完成（与 view_character 同为 process_frame）
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(out))
	print("GRIP VIEW SAVED ", ProjectSettings.globalize_path(out))
	get_tree().quit()
