# Headless probe: fire a full AK spray at a wall, report per-shot hit + hole-node count.
# Distinguishes "shot missed (recoil climb)" vs "hole node created but invisible (z-fight/cap)".
#   godot --headless --path . -s tools/probe_holes.gd [--recoil]
extends SceneTree

const AK := preload("res://Weapons/weapon_ak47.tres")

var _mgr: WeaponManager
var _cam: Camera3D
var _hits := 0

func _initialize() -> void:
	var use_recoil := "--recoil" in OS.get_cmdline_user_args()
	var root := Node3D.new()
	root.name = "ProbeRoot"
	get_root().add_child(root)
	# Big wall at z=-10 (layer 1 = Objects), 20m wide × 20m tall to catch a climbing spray
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	wall.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20, 20, 0.2)
	cs.shape = box
	wall.add_child(cs)
	wall.position = Vector3(0, 5, -10)
	root.add_child(wall)
	# Camera (eye) at origin facing -Z (fixed; no recoil climb unless --recoil)
	_cam = Camera3D.new()
	_cam.current = true
	root.add_child(_cam)
	var move := MovementController.new()
	root.add_child(move)
	_mgr = WeaponManager.new()
	root.add_child(_mgr)
	_mgr.auto_switch_after_throw = false
	_mgr.setup([AK], move)
	# ensure hitscan camera (find via viewport can be null this early in a bare SceneTree)
	_mgr._camera = _cam
	_mgr.get_core(0)._camera = _cam
	_mgr.get_melee_controller().origin = _cam
	# count actual hitscan hits on the wall
	_mgr.get_core(0).hit_landed.connect(func(t, d, p, n): _hits += 1)
	if use_recoil:
		print("PROBE recoil mode: NOT simulating camera climb in this probe (pattern only)")
	_run()

func _run() -> void:
	# wait out deploy (0.3s ≈ 18 physics frames)
	for i in range(25):
		await physics_frame
	# hold fire for ~35 shots at 600rpm (0.1s/shot = 6 physics frames)
	Input.action_press("fire")
	for i in range(220):
		await physics_frame
	Input.action_release("fire")
	await physics_frame
	var holes := _count_holes(get_root())
	var ammo: Vector2 = _mgr.get_core(0).get_ammo()
	var shots_fired := int(AK.magazine - ammo.x)
	print("PROBE RESULT: shots_fired=%d  hitscan_hits=%d  bullet_hole_nodes=%d  (manager tracked=%d, MAX=%d)" % [
		shots_fired, _hits, holes, _mgr._bullet_holes.size(), WeaponManager.MAX_BULLET_HOLES])
	quit()

func _count_holes(n: Node) -> int:
	var c := 0
	if n is BulletHole:
		c += 1
	for ch in n.get_children():
		c += _count_holes(ch)
	return c
