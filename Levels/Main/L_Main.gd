extends Node3D

# L_Main.gd — M1.5 主场景控制器：装配武器系统（WeaponManager 逻辑 + WeaponView 表现）
# + HUD（弹药/准星/命中标记）+ 训练靶子。移动/相机由 M0 Player（FirstPersonStarter）提供。
#
# 接线（全部代码装配，数值唯一来源 Weapons/weapon_*.tres，企划书 §4.2.5）：
#   Player(MovementController) > WeaponManager   —— 逻辑（射击/换弹/切枪/投掷/近战）
#   Player/Head > WeaponView(ViewModel)          —— 表现（武器+方块手臂 + 程序化动画）
# 输入：fire 由 WeaponManager._physics_process 每物理帧轮询（半自动契约）；reload/aim/切枪在此路由。

@export var fast_close := true
@export var cheats := false  # 无限弹药作弊（免换弹；正式/验收 false）
@export var range_mode := true  # 靶场模式：枪械备弹无限（弹匣有限需换弹）+ 手雷无限（投完自动切回主武器）

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
var _burst := 0  # >0 = 拍照前连发 N 帧（复现弹孔/后坐力）
var _ads_photo := false  # true = 拍照前开镜（验证平滑开镜 + 步枪居中看瞄具）
# 靶场敌人按批刷新
var _active_enemies: Array[Enemy] = []
var _respawn_timer := -1.0  # <0 = 无计时
var _respawn_delay := 1.0


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
		elif a.begins_with("--burst="):
			_burst = int(a.split("=")[1])
		elif a.begins_with("--pz="):
			_movement.position = Vector3(0, 1, float(a.split("=")[1]))  # 拍照前传送玩家
		elif a.begins_with("--pitch="):
			_head.rot.x = deg_to_rad(float(a.split("=")[1]))  # 俯仰视角（低头看身体）
		elif a == "--ads":
			_ads_photo = true  # 开镜拍照（验证平滑开镜 + 步枪居中看瞄具）


func _process(_delta: float) -> void:
	# 靶场敌人按批刷新倒计时
	if _respawn_timer > 0.0:
		_respawn_timer -= _delta
		if _respawn_timer <= 0.0:
			_respawn_timer = -1.0
			_spawn_wave()
	if _photo_frames < 0:
		return
	_photo_frames -= 1
	# 开镜拍照：deploy 完成后开镜（平滑举枪到眼前 + FOV 缩放，截图定格开镜态）
	if _ads_photo and _photo_frames == 20:
		_manager.set_aim(true)
	# 连发阶段（复现弹孔/后坐力）：按住 fire
	if _burst > 0 and _photo_frames > 10:
		Input.action_press("fire")
		_burst -= 1
		if _burst <= 0:
			Input.action_release("fire")
	if _photo_frames <= 0:
		Input.action_release("fire")
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
	if range_mode:
		# 靶场模式：枪械（0步枪/1手枪）备弹无限但弹匣有限（正常换弹）；手雷（3）无限（refund_throw）
		for i in slots.size():
			var core := _manager.get_core(i)
			if core == null:
				continue
			var res := _manager.get_resource(i)
			if res.fire_mode == WeaponResource.FireMode.THROWABLE:
				core.infinite_ammo = true  # 手雷无限（投出后 refund 回 1 枚）
			elif res.fire_mode != WeaponResource.FireMode.MELEE:
				core.infinite_reserve = true  # 枪械备弹无限、弹匣有限
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
	# TargetA：圆形金色标靶（正对玩家，测准度看弹孔；也是集成测试命中/爆炸基准）
	_spawn_accuracy_target(targets)
	# 敌人按批刷新（全灭后 1s 自动刷新一批）
	_respawn_delay = 1.0
	_spawn_wave()


# 圆形金色标靶：薄板（圆环靶面贴图，透明角），正对玩家，弹孔落点可读准度。
func _spawn_accuracy_target(parent: Node) -> void:
	var target_a := Target.new()
	target_a.name = "TargetA"
	target_a.position = Vector3(0, 1.5, -9.8)
	# 碰撞：薄竖板（命中判定 + 弹孔投射面）
	var a_col := CollisionShape3D.new()
	var a_box := BoxShape3D.new()
	a_box.size = Vector3(1.7, 1.7, 0.08)
	a_col.shape = a_box
	target_a.add_child(a_col)
	# 靶面：PlaneMesh 正对玩家（+Z），圆形靶环贴图（透明角）
	var a_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(1.7, 1.7)
	a_mesh.mesh = plane
	# PlaneMesh 默认面朝 +Y（水平），旋转竖立面朝 +Z（朝玩家）
	a_mesh.rotation_degrees = Vector3(90, 0, 0)
	var a_mat := StandardMaterial3D.new()
	a_mat.albedo_texture = _make_bullseye_texture()
	a_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA  # 透明角（只显示圆靶）
	a_mat.roughness = 0.85
	a_mesh.material_override = a_mat
	a_mesh.position = Vector3(0, 0, 0.05)  # 靶面微出碰撞板（弹孔投在板上，靶面可见）
	target_a.add_child(a_mesh)
	parent.add_child(target_a)


# 程序化同心环靶面（金/红/白靶心，圆外透明），供弹孔判读准度
func _make_bullseye_texture() -> ImageTexture:
	var S := 256
	var img := Image.create(S, S, false, Image.FORMAT_RGBA8)
	var center := Vector2(S, S) * 0.5
	# 由外向内：金底 → 白环 → 红环 → 白环 → 金心（靶心）
	var bands := [
		[1.00, Color(0.85, 0.65, 0.15)],   # 外金底
		[0.78, Color(0.92, 0.92, 0.92)],   # 白环
		[0.58, Color(0.80, 0.20, 0.15)],   # 红环
		[0.36, Color(0.92, 0.92, 0.92)],   # 白环
		[0.18, Color(0.85, 0.30, 0.12)],   # 红心（靶心）
	]
	for y in S:
		for x in S:
			var d := Vector2(x, y).distance_to(center) / (S * 0.5)
			if d > 1.0:
				img.set_pixel(x, y, Color(0, 0, 0, 0))  # 圆外透明
				continue
			# 从靶心向外匹配：半径最小的包含带胜出（内→外遍历 + 命中即停）
			var col: Color = bands[0][1]  # 默认最外金底
			for i in range(bands.size() - 1, 0, -1):  # 内→外（bands 末位=靶心）
				if d <= bands[i][0]:
					col = bands[i][1]
					break
			img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)


# ---- 敌人按批刷新 ----
func _spawn_wave() -> void:
	_active_enemies.clear()
	# 一批 4 个，分布在正前方两侧（中央 x≈0 通道留空——TargetA 测准度/集成测试不被挡）
	var positions := [
		Vector3(-2.5, 0, -6), Vector3(1.8, 0, -7), Vector3(3.5, 0, -6), Vector3(-4.0, 0, -8),
	]
	for pos in positions:
		var e := Enemy.new()
		e.position = pos
		e.rotation.y = PI  # 面向玩家（角色默认朝 -Z，转 180° 朝 +Z 玩家侧）
		e.died.connect(_on_enemy_died.bind(e))
		add_child(e)
		_active_enemies.append(e)


func _on_enemy_died(e: Enemy) -> void:
	_active_enemies.erase(e)
	if _active_enemies.is_empty():
		_respawn_timer = _respawn_delay  # 全灭 → 1s 后刷新一批


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
