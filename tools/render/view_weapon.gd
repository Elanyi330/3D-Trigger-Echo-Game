# Isolated weapon render from a custom camera angle — verify ECHO sticker orientation/appearance.
#   godot --path . tools/render/view_weapon.tscn -- --weapon=AK47_Echo --yaw=35 --out=<abs.png>
extends Node3D

const WEAPONS := {
	"AK47_Echo": "res://Assets/Models/Weapons/Rifle/AK47_Echo/AK47_Echo.glb",
	"Glock18_Echo": "res://Assets/Models/Weapons/Pistol/Glock18_Echo/Glock18_Echo.glb",
	"Knife_Echo": "res://Assets/Models/Weapons/Melee/Knife_Echo/Knife_Echo.glb",
	"Grenade_M67_Echo": "res://Assets/Models/Weapons/Throwable/Grenade_M67_Echo/Grenade_M67_Echo.glb",
}

var weapon := "AK47_Echo"
var yaw := 35.0   # 相机绕 -Z(前) 为轴的水平角；负值看 -X 左侧（ECHO 面）
var pitch := 12.0
var dist := 0.9
var out := "user://view.png"

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--weapon="): weapon = a.split("=")[1]
		elif a.begins_with("--yaw="): yaw = float(a.split("=")[1])
		elif a.begins_with("--pitch="): pitch = float(a.split("=")[1])
		elif a.begins_with("--dist="): dist = float(a.split("=")[1])
		elif a.begins_with("--out="): out = a.split("=")[1]
	var w: Node3D = load(WEAPONS[weapon]).instantiate()
	add_child(w)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	add_child(sun)
	var sun2 := DirectionalLight3D.new()
	sun2.rotation_degrees = Vector3(-20, 40, 0)
	sun2.light_energy = 0.6
	add_child(sun2)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.45, 0.5, 0.55)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_energy = 0.8
	env.environment = e
	add_child(env)
	var cam := Camera3D.new()
	cam.current = true
	add_child(cam)
	# orbit camera around origin (weapon at origin, muzzle -Z)
	var yr := deg_to_rad(yaw)
	var pr := deg_to_rad(pitch)
	var pos := Vector3(sin(yr) * cos(pr), sin(pr), cos(yr) * cos(pr)) * dist
	cam.position = pos
	cam.look_at(Vector3(0, 0.05, 0), Vector3.UP)
	_shoot()

func _shoot() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(out))
	print("VIEW SAVED ", ProjectSettings.globalize_path(out))
	get_tree().quit()
