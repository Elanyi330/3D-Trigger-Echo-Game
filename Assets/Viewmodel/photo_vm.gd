extends Node3D

const ViewModel := preload("res://Assets/Viewmodel/ViewModel.gd")
## Photo-mode: render the ViewModel from the FPS eye position and save a PNG.
## Run windowed (headless cannot render):
##   godot --path . Assets/Viewmodel/PhotoVM.tscn -- --weapon=AK47_Echo [--inspect]
##         [--ox=.. --oy=.. --oz=.. --scale=.. --pitch=.. --fov=..]

const WEAPONS := {
	"AK47_Echo": "res://Assets/Models/Weapons/Rifle/AK47_Echo/AK47_Echo.glb",
	"Glock18_Echo": "res://Assets/Models/Weapons/Pistol/Glock18_Echo/Glock18_Echo.glb",
	"Knife_Echo": "res://Assets/Models/Weapons/Melee/Knife_Echo/Knife_Echo.glb",
	"Grenade_M67_Echo": "res://Assets/Models/Weapons/Throwable/Grenade_M67_Echo/Grenade_M67_Echo.glb",
}

var weapon := "AK47_Echo"
var out_png := "user://photo.png"
var inspect := false
var p := Vector3(0.20, -0.26, -0.55)
var scl := 1.4
var pitch := 0.0
var fov := 70.0

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--weapon="): weapon = a.split("=")[1]
		elif a.begins_with("--out="): out_png = a.split("=")[1]
		elif a == "--inspect": inspect = true
		elif a.begins_with("--ox="): p.x = float(a.split("=")[1])
		elif a.begins_with("--oy="): p.y = float(a.split("=")[1])
		elif a.begins_with("--oz="): p.z = float(a.split("=")[1])
		elif a.begins_with("--scale="): scl = float(a.split("=")[1])
		elif a.begins_with("--pitch="): pitch = float(a.split("=")[1])
		elif a.begins_with("--fov="): fov = float(a.split("=")[1])

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.light_energy = 1.2
	add_child(sun)
	var sun2 := DirectionalLight3D.new()
	sun2.rotation_degrees = Vector3(-20, 150, 0)
	sun2.light_energy = 0.5
	add_child(sun2)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.35, 0.4, 0.45)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.8, 0.8, 0.85)
	e.ambient_light_energy = 0.6
	env.environment = e
	add_child(env)

	# rig that holds the viewmodel (represents the FPS camera/head)
	var rig := Node3D.new()
	rig.name = "Rig"
	add_child(rig)
	var vm := ViewModel.new()
	vm.weapon_offset = p
	vm.vm_scale = scl
	vm.weapon_pitch_deg = pitch
	rig.add_child(vm)
	var wscene: PackedScene = load(WEAPONS[weapon])
	vm.equip(wscene)

	var cam := Camera3D.new()
	cam.fov = fov
	cam.current = true
	if inspect:
		# external 3/4 view of the whole viewmodel assembly
		add_child(cam)
		cam.position = Vector3(0.9, 0.25, 0.9)
		cam.look_at(Vector3(0.05, -0.2, -0.4), Vector3.UP)
	else:
		# FPS eye: camera IS the rig
		rig.add_child(cam)
		# reference target ahead so muzzle direction reads clearly
		var wall := MeshInstance3D.new()
		var bm := BoxMesh.new(); bm.size = Vector3(6, 3, 0.1)
		wall.mesh = bm; wall.position = Vector3(0, 0, -10)
		add_child(wall)
		var grid := MeshInstance3D.new()
		var pm := PlaneMesh.new(); pm.size = Vector2(40, 40)
		grid.mesh = pm; grid.position = Vector3(0, -1.6, 0)
		add_child(grid)

	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(out_png))
	print("PHOTO SAVED ", ProjectSettings.globalize_path(out_png), " weapon=", weapon, " inspect=", inspect)
	get_tree().quit()
