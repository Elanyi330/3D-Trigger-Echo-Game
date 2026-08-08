extends Node3D
## Animation photo harness: build WeaponView + WeaponManager, trigger an action,
## capture the viewmodel at a chosen animation phase (diagnose reload/swing visuals).
##   godot --path . Assets/Viewmodel/PhotoAnim.tscn -- --weapon=0 --action=reload --at=0.4

const ViewModel := preload("res://Assets/Viewmodel/ViewModel.gd")
const WeaponView := preload("res://Player/WeaponView.gd")

const RES := [
	preload("res://Weapons/weapon_ak47.tres"),
	preload("res://Weapons/weapon_glock18.tres"),
	preload("res://Weapons/weapon_knife.tres"),
	preload("res://Weapons/weapon_m67.tres"),
]
const MODELS := [
	preload("res://Assets/Models/Weapons/Rifle/AK47_Echo/AK47_Echo.glb"),
	preload("res://Assets/Models/Weapons/Pistol/Glock18_Echo/Glock18_Echo.glb"),
	preload("res://Assets/Models/Weapons/Melee/Knife_Echo/Knife_Echo.glb"),
	preload("res://Assets/Models/Weapons/Throwable/Grenade_M67_Echo/Grenade_M67_Echo.glb"),
]

var weapon_idx := 0
var action := "reload"
var at := 0.4
var out := "user://anim.png"
var inspect := false
var _mgr: WeaponManager
var _view: WeaponView
var _cam: Camera3D
var _frames := 0
var _action_fired := false

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--weapon="): weapon_idx = int(a.split("=")[1])
		elif a.begins_with("--action="): action = a.split("=")[1]
		elif a.begins_with("--at="): at = float(a.split("=")[1])
		elif a.begins_with("--out="): out = a.split("=")[1]
		elif a == "--inspect": inspect = true
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-50,-30,0); add_child(sun)
	var env := WorldEnvironment.new(); var e := Environment.new()
	e.background_mode = Environment.BG_COLOR; e.background_color = Color(0.35,0.4,0.45)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; e.ambient_light_energy = 0.7
	env.environment = e; add_child(env)
	var move := MovementController.new(); add_child(move)
	_mgr = WeaponManager.new(); add_child(_mgr)
	var models: Array[PackedScene] = []
	for m in MODELS: models.append(m)
	_mgr.view_models = models
	var slots: Array[WeaponResource] = []
	for r in RES: slots.append(r)
	_mgr.setup(slots, move)
	_cam = Camera3D.new(); _cam.fov = 70; _cam.current = true; add_child(_cam)
	_view = WeaponView.new(); _cam.add_child(_view)
	_view.setup(_mgr, move)
	_mgr.switch_to(weapon_idx)
	if inspect:
		_cam.position = Vector3(0.9, 0.1, 0.9)
		_cam.look_at(Vector3(0.1,-0.2,-0.4), Vector3.UP)

func _physics_process(_d: float) -> void:
	_frames += 1
	# 换弹需先打几发（满弹匣 start_reload 会被守卫拦截）
	if action == "reload" and _frames == 18:
		Input.action_press("fire")
	if action == "reload" and _frames == 24:
		Input.action_release("fire")
	# deploy takes deploy_time; act after ~20 frames (reload: fire first, then reload at frame 30)
	var trig := 20 if action != "reload" else 30
	if _frames == trig and not _action_fired:
		_action_fired = true
		match action:
			"reload": _mgr.start_reload()
			"swing": _mgr.try_fire()
			"heavyswing": _mgr.set_aim(true)
			"fire": _mgr.try_fire()
	# capture at the 'at' fraction of the action
	var total := _total_frames()
	if _frames == trig + int(total * at):
		_capture()

func _total_frames() -> int:
	match action:
		"reload": return int(RES[weapon_idx].reload_time * 60)
		"swing": return int(RES[weapon_idx].melee_light_time * 60)  # 取实际轻击时长
		"heavyswing": return int(RES[weapon_idx].melee_heavy_time * 60)
	return 30

func _capture() -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(out))
	print("ANIM PHOTO SAVED ", ProjectSettings.globalize_path(out), " action=", action, " at=", at)
	get_tree().quit()
