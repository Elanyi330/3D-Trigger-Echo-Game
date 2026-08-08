extends Node3D

# L_Main.gd — M1.5 主场景控制器：装配武器系统（WeaponManager 逻辑 + WeaponView 表现）
# + HUD（弹药/准星/命中标记）+ 训练靶子。移动/相机由 M0 Player（FirstPersonStarter）提供。
#
# 接线（全部代码装配，数值唯一来源 Weapons/weapon_*.tres，企划书 §4.2.5）：
#   Player(MovementController) > WeaponManager   —— 逻辑（射击/换弹/切枪/投掷/近战）
#   Player/Head > WeaponView(ViewModel)          —— 表现（武器+方块手臂 + 程序化动画）
# 输入：fire 由 WeaponManager._physics_process 每物理帧轮询（半自动契约）；reload/aim/切枪在此路由。

@export var fast_close := true
@export var cheats := false  # 测试版无限弹药开关（正式/验收 false = 真实弹药/换弹）

const WEAPON_RES := [
	preload("res://Weapons/weapon_ak47.tres"),
	preload("res://Weapons/weapon_glock18.tres"),
	preload("res://Weapons/weapon_knife.tres"),
	preload("res://Weapons/weapon_m67.tres"),
]
const WEAPON_MODELS := [
	preload("res://Assets/Models/Weapons/Rifle/AK47_Echo/AK47_Echo.glb"),
	preload("res://Assets/Models/Weapons/Pistol/Glock18_Echo/Glock18_Echo.glb"),
	preload("res://Assets/Models/Weapons/Melee/Knife_Echo/Knife_Echo.glb"),
	preload("res://Assets/Models/Weapons/Throwable/Grenade_M67_Echo/Grenade_M67_Echo.glb"),
]
const ENEMY_SCRIPT := preload("res://Levels/Enemy/Enemy.gd")

var _manager: WeaponManager
var _view: WeaponView
var _movement: MovementController
var _head: Node3D
var _ammo_label: Label
var _weapon_label: Label
var _hitmarker: Label
var _photo_path := ""
var _photo_frames := -1  # >=0 = 拍照模式（N 帧后截图退出）


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	if !OS.is_debug_build():
		fast_close = false
	if fast_close:
		print("** Fast Close: Esc 退出 / Shift+F1 释放鼠标 **")
	set_process_input(fast_close)
	_movement = $Player
	_head = $Player/Head
	_setup_weapons()
	_setup_hud()
	_spawn_targets()
	# 拍照模式：--photo=<path> [--frames=N] —— N 帧后截图退出（无头验证用）
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--photo="):
			_photo_path = a.split("=")[1]
			_photo_frames = 50
		elif a.begins_with("--frames="):
			_photo_frames = int(a.split("=")[1])


func _process(_delta: float) -> void:
	if _photo_frames < 0:
		return
	_photo_frames -= 1
	if _photo_frames <= 0:
		var img := get_viewport().get_texture().get_image()
		img.save_png(ProjectSettings.globalize_path(_photo_path))
		print("GAME PHOTO SAVED ", ProjectSettings.globalize_path(_photo_path))
		_photo_frames = -1
		get_tree().quit()


func _setup_weapons() -> void:
	# WeaponManager（逻辑，挂 Player 下）
	_manager = WeaponManager.new()
	_manager.name = "WeaponManager"
	var models: Array[PackedScene] = []
	for m in WEAPON_MODELS:
		models.append(m)
	_manager.view_models = models
	_movement.add_child(_manager)
	var slots: Array[WeaponResource] = []
	for r in WEAPON_RES:
		slots.append(r)
	_manager.setup(slots, _movement)
	_manager.set_head(_head)
	if cheats:
		for i in slots.size():
			var core := _manager.get_core(i)
			if core:
				core.infinite_ammo = true
	# 开火即刷新弹药 HUD（WeaponManager 不在逐发时发 ammo 信号）
	for i in slots.size():
		var c := _manager.get_core(i)
		if c:
			c.shot_fired.connect(func(_a: int) -> void: _refresh_hud())
	# WeaponView（表现，挂 Head 下——随视角俯仰/后坐力）
	_view = WeaponView.new()
	_view.name = "WeaponView"
	_head.add_child(_view)
	_view.setup(_manager, _movement)
	# HUD 信号
	_manager.weapon_ammo_updated.connect(_on_ammo_updated)
	_manager.weapon_switched.connect(_on_weapon_switched)
	_manager.enemy_hit.connect(_on_enemy_hit)


func _setup_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "HUD"
	add_child(layer)
	var vp := get_viewport().get_visible_rect().size
	# 准星（居中）
	var cross := Label.new()
	cross.text = "+"
	cross.add_theme_font_size_override("font_size", 36)
	cross.add_theme_color_override("font_color", Color(0.2, 1, 0.35))
	cross.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	cross.add_theme_constant_override("outline_size", 8)
	layer.add_child(cross)
	cross.position = vp * 0.5 + Vector2(-11, -26)
	# 命中标记（准星右下，闪现）
	_hitmarker = Label.new()
	_hitmarker.text = "✕"
	_hitmarker.add_theme_color_override("font_color", Color(1, 0.25, 0.15))
	_hitmarker.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_hitmarker.add_theme_constant_override("outline_size", 8)
	_hitmarker.add_theme_font_size_override("font_size", 40)
	layer.add_child(_hitmarker)
	_hitmarker.position = vp * 0.5 + Vector2(14, -28)
	_hitmarker.modulate.a = 0.0
	# 弹药背板（右下，半透明黑底保证可读）
	var panel := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.5)
	sb.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", sb)
	layer.add_child(panel)
	panel.position = Vector2(vp.x - 300, vp.y - 110)
	panel.size = Vector2(270, 80)
	_ammo_label = Label.new()
	_ammo_label.name = "AmmoLabel"  # 保持 HUD 直接子节点（测试路径 HUD/AmmoLabel）
	_ammo_label.add_theme_font_size_override("font_size", 46)
	_ammo_label.add_theme_color_override("font_color", Color(1, 1, 1))
	layer.add_child(_ammo_label)
	_ammo_label.position = Vector2(vp.x - 300 + 18, vp.y - 110 + 14)
	# 武器名（左下）
	_weapon_label = Label.new()
	_weapon_label.add_theme_font_size_override("font_size", 28)
	_weapon_label.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	_weapon_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_weapon_label.add_theme_constant_override("outline_size", 8)
	layer.add_child(_weapon_label)
	_weapon_label.position = Vector2(30, vp.y - 70)
	_refresh_hud()


func _spawn_targets() -> void:
	var targets := Node3D.new()
	targets.name = "Targets"
	add_child(targets)
	# TargetA：正前方可见躯干靶（纯 torso，命中判定/爆炸结收集成测试基准）
	var target_a := Target.new()
	target_a.name = "TargetA"
	target_a.position = Vector3(0, 0, -9.5)
	var a_col := CollisionShape3D.new()
	var a_box := BoxShape3D.new()
	a_box.size = Vector3(0.6, 1.8, 0.4)
	a_col.shape = a_box
	a_col.position = Vector3(0, 0.9, 0)
	target_a.add_child(a_col)
	var a_mesh := MeshInstance3D.new()
	var a_bm := BoxMesh.new()
	a_bm.size = Vector3(0.6, 1.8, 0.4)
	a_mesh.mesh = a_bm
	a_mesh.position = Vector3(0, 0.9, 0)
	var a_mat := StandardMaterial3D.new()
	a_mat.albedo_color = Color(0.75, 0.6, 0.2)
	a_mesh.material_override = a_mat
	target_a.add_child(a_mesh)
	targets.add_child(target_a)
	# 敌人（红色方块人，排两侧/后方，不挡 TargetA 正前方射线）
	var enemy_positions := [
		Vector3(3.5, 0, -7), Vector3(-3.5, 0, -7),
		Vector3(5.5, 0, -4), Vector3(-5.5, 0, -4),
		Vector3(2.5, 0, -9), Vector3(-2.5, 0, -9),
	]
	for pos in enemy_positions:
		var e := Enemy.new()
		e.position = pos
		targets.add_child(e)


func _input(event: InputEvent) -> void:
	if fast_close and event.is_action_pressed(&"ui_cancel"):
		get_tree().quit()
	if event.is_action_pressed(&"change_mouse_input"):
		match Input.get_mouse_mode():
			Input.MOUSE_MODE_CAPTURED:
				Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
			Input.MOUSE_MODE_VISIBLE:
				Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	# fire 由 WeaponManager 物理帧轮询；这里路由 reload/aim/切枪
	if event.is_action_pressed(&"reload"):
		_manager.start_reload()
	elif event.is_action_pressed(&"aim"):
		_manager.set_aim(true)
	elif event.is_action_released(&"aim"):
		_manager.set_aim(false)
	elif event.is_action_pressed(&"weapon_1"):
		_manager.switch_to(0)
	elif event.is_action_pressed(&"weapon_2"):
		_manager.switch_to(1)
	elif event.is_action_pressed(&"weapon_3"):
		_manager.switch_to(2)
	elif event.is_action_pressed(&"weapon_4"):
		_manager.switch_to(3)
	elif event.is_action_pressed(&"next_weapon"):
		_manager.next_weapon()


func _on_ammo_updated(_slot: int, _mag: int, _reserve: int) -> void:
	_refresh_hud()


func _on_weapon_switched(_slot: int) -> void:
	_refresh_hud()


func _refresh_hud() -> void:
	if _manager == null:
		return
	var slot := _manager.get_current_slot()
	var core := _manager.get_core(slot)
	var res := _manager.get_resource(slot)
	if core == null or res == null:
		return
	var ammo := core.get_ammo()
	if res.fire_mode == WeaponResource.FireMode.MELEE:
		_ammo_label.text = "—"  # 近战无弹药
	else:
		_ammo_label.text = "%d / %d" % [int(ammo.x), int(ammo.y)]  # 枪械+投掷统一 "x / y"
	_weapon_label.text = res.weapon_name


func _on_enemy_hit() -> void:
	_hitmarker.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_property(_hitmarker, "modulate:a", 0.0, 0.25)
