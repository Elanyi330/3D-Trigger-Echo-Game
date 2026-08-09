# Windowed probe: fire a 6x5 grid of shots at a wall (fixed camera, no recoil climb),
# then screenshot — counts how many bullet-hole decals actually RENDER.
#   godot --path . tools/probe_holes_scene.gd -- --out=<abs.png>
extends Node3D

var _mgr: WeaponManager
var _cam: Camera3D
var _out := "user://holes_grid.png"

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.split("=")[1]
	# wall: collision (layer 1) + VISUAL mesh (decals project onto visual meshes)
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	wall.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20, 20, 0.2)
	cs.shape = box
	wall.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(20, 20, 0.2)
	mi.mesh = bm
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.9, 0.9, 0.88)
	mi.material_override = wm
	wall.add_child(mi)
	wall.position = Vector3(0, 5, -10)
	add_child(wall)
	# light + env
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	add_child(sun)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.5, 0.55, 0.6)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_energy = 0.8
	env.environment = e
	add_child(env)
	# camera (eye) — fixed, no recoil
	_cam = Camera3D.new()
	_cam.current = true
	_cam.position = Vector3(0, 1.63, 0)
	add_child(_cam)
	# weapon — zero-spread AK duplicate so shots land exactly on the grid (isolate render cap vs clustering)
	var move := MovementController.new()
	add_child(move)
	var ak: WeaponResource = load("res://Weapons/weapon_ak47.tres").duplicate()
	ak.first_shot_spread = 0.0
	ak.pattern_offsets = PackedVector2Array()  # no climb — every shot lands on aim point
	ak.recoil_val = Vector3.ZERO
	_mgr = WeaponManager.new()
	add_child(_mgr)
	_mgr.auto_switch_after_throw = false
	_mgr.setup([ak], move)
	_mgr._camera = _cam
	_mgr.get_core(0)._camera = _cam
	_mgr.get_melee_controller().origin = _cam
	_mgr.get_core(0).hit_landed.connect(func(t, d, p, n): print("  HIT %.2f,%.2f,%.2f" % [p.x, p.y, p.z]))
	_fire_grid()

func _fire_grid() -> void:
	for i in range(25):  # deploy wait
		await get_tree().physics_frame
	var shots := 0
	for gy in range(5):
		for gx in range(6):
			var target := Vector3(-2.5 + gx * 1.0, 0.5 + gy * 0.8, -10)
			_cam.look_at(target, Vector3.UP)
			_mgr.try_fire()
			shots += 1
			for i in 7:  # > 0.1s fire cooldown (600rpm)
				await get_tree().physics_frame
	# recenter camera to view the whole grid
	_cam.look_at(Vector3(0, 2.2, -10), Vector3.UP)
	for i in range(5):
		await get_tree().physics_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(_out))
	print("GRID PROBE: shots=%d  holes_tracked=%d  saved=%s" % [shots, _mgr._bullet_holes.size(), _out])
	get_tree().quit()
