# Levels/M2_TDM/L_M2.gd
# M2 TDM 小图主场景控制器：灰盒地图 + 玩家（MovementController）+ 武器系统 + WaveSpawner 波次刷怪。
# 验收目标（用户 2026-08-10）：①玩家可逛遍全图无 bug；②可踏足位置波次刷敌人（每波 5 个，全灭 1.5s 后下一波），
# 验证射击角度与空气墙。武器装配移植自 L_Main.gd（同一套 WeaponManager + WeaponView + 输入路由 + HUD）。
extends Node3D

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
const GREYBOX := preload("res://Levels/M2_TDM/map_greybox.gd")
const VISUALS := preload("res://Levels/M2_TDM/map_visuals.gd")
const LAYOUT := preload("res://Levels/M2_TDM/map_layout_v3.gd")
const ENEMY_SCRIPT := preload("res://Levels/Enemy/Enemy.gd")

@export var range_mode := true  # 测试模式：枪械备弹无限（弹匣有限正常换弹）+ 手雷无限（投完切回主武器但可再切回投）

var _player: CharacterBody3D
var _head: Node3D
var _manager: WeaponManager
var _view: WeaponView
var _spawner: WaveSpawner
var _recorder: JumpRecorder
var _spawn_serial := 0   # 敌人名序号（同面一敌一名会撞名——Godot 撞名会重置为 @Class@id）


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	# 灰盒地图（纯灰盒——Kenney 平铺方向错误导致视觉更差，已回退；视觉重做放 T5）
	var gb: Node3D = GREYBOX.new()
	gb.name = "Greybox"
	add_child(gb)
	gb.build()
	# 玩家（Player.tscn：MovementController + Head + Crouch）
	_player = load("res://Player/Player.tscn").instantiate()
	_player.name = "Player"
	add_child(_player)
	_player.global_position = LAYOUT.player_spawn()
	_head = _player.get_node("Head")
	_setup_weapons()
	_setup_hud()
	# 波次刷怪（WaveSpawner：每波 5 敌刷在可踏足面，全灭 1.5s 后下一波）
	_setup_wave_spawner()
	# 跳跃记录（任务 15）：记录跳建筑操作供 AI 学习；地图哈希不符自动清空旧记录。
	# 必须在 Player 入树之后 add_child——Godot 4.7 _physics_process 按树序执行，
	# recorder 排玩家之后才能在 move_and_slide 之后读当帧状态。
	_recorder = JumpRecorder.new()
	_recorder.name = "JumpRecorder"
	add_child(_recorder)
	_recorder.setup(_player, LAYOUT.all_solids(), "回声祭坛v3")

# ---- 武器装配（移植自 L_Main.gd，同款：逻辑挂 Player 下，表现挂 Head 下）----
func _setup_weapons() -> void:
	_manager = WeaponManager.new()
	_manager.name = "WeaponManager"
	var models: Array[PackedScene] = []
	for m in WEAPON_MODELS:
		models.append(m)
	_manager.view_models = models
	_player.add_child(_manager)
	var slots: Array[WeaponResource] = []
	for r in WEAPON_RES:
		slots.append(r)
	_manager.setup(slots, _player)
	_manager.set_head(_head)
	if range_mode:
		# 测试模式（L_Main 同款）：枪械备弹无限（弹匣有限正常换弹）；手雷无限（投完自动切回主武器，可再切回投）
		for i in slots.size():
			var core := _manager.get_core(i)
			if core == null:
				continue
			var res := _manager.get_resource(i)
			if res.fire_mode == WeaponResource.FireMode.THROWABLE:
				core.infinite_ammo = true  # 手雷无限（投出后 refund 回 1 枚）
			elif res.fire_mode != WeaponResource.FireMode.MELEE:
				core.infinite_reserve = true  # 枪械备弹无限、弹匣有限
	# 开火即刷新弹药 HUD（WeaponManager 不在逐发时发 ammo 信号——L_Main 同款修复）
	for i in slots.size():
		var c := _manager.get_core(i)
		if c:
			c.shot_fired.connect(func(_a: int) -> void: _refresh_hud())
	_view = WeaponView.new()
	_view.name = "WeaponView"
	_head.add_child(_view)
	_view.setup(_manager, _player)


# ---- HUD（弹药/准星/命中标记/波次，移植自 L_Main.gd）----
var _ammo_label: Label
var _weapon_label: Label
var _wave_label: Label
var _hitmarker: Label
var _minimap: Minimap  # M2 小地图（左上角圆形雷达）


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
	# 弹药背板（右下）
	var panel := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.5)
	sb.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", sb)
	layer.add_child(panel)
	panel.position = Vector2(vp.x - 300, vp.y - 110)
	panel.size = Vector2(270, 80)
	_ammo_label = Label.new()
	_ammo_label.name = "AmmoLabel"
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
	# 波次（左上角：「波次 N · 剩余 X」，WaveSpawner 信号驱动）
	_wave_label = Label.new()
	_wave_label.text = "波次 1 · 剩余 %d" % WaveSpawner.WAVE_SIZE
	_wave_label.add_theme_font_size_override("font_size", 28)
	_wave_label.add_theme_color_override("font_color", Color(0.55, 0.85, 1))
	_wave_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_wave_label.add_theme_constant_override("outline_size", 8)
	layer.add_child(_wave_label)
	_wave_label.position = Vector2(30, 24)
	# 小地图（M2 左上角圆形雷达）：数据驱动蓝图投影 + 12m 内敌我标志
	var minimap := Minimap.new()
	minimap.name = "Minimap"
	layer.add_child(minimap)
	minimap.setup(LAYOUT.all_solids(), _player, _enemy_entities)
	_minimap = minimap  # 成员句柄（M3 操作小地图用；审查 MM2a 修复）
	# 弹药/切枪信号刷新
	_manager.weapon_ammo_updated.connect(_on_ammo_updated)
	_manager.weapon_switched.connect(_on_weapon_switched)
	_manager.enemy_hit.connect(_on_enemy_hit)
	_refresh_hud()


func _enemy_entities() -> Array:
	# 小地图实体提供者：L_M2 直接子节点中的 Enemy（≤5 个，每帧枚举零成本）。
	# M3 队友出现后在此追加 is_enemy=false 条目（同一接口）。
	var out: Array = []
	for c in get_children():
		if c is Enemy:
			out.append({"pos": c.global_position, "is_enemy": true})
	return out


func _on_ammo_updated(_slot: int, _mag: int, _reserve: int) -> void:
	_refresh_hud()


func _on_weapon_switched(_slot: int) -> void:
	_refresh_hud()


func _on_enemy_hit() -> void:
	_hitmarker.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_property(_hitmarker, "modulate:a", 0.0, 0.25)


func _refresh_hud() -> void:
	if _manager == null or _ammo_label == null:
		return
	var slot := _manager.get_current_slot()
	var core := _manager.get_core(slot)
	var res := _manager.get_resource(slot)
	if core == null or res == null:
		return
	var ammo := core.get_ammo()
	if res.fire_mode == WeaponResource.FireMode.MELEE:
		_ammo_label.text = "—"
	else:
		_ammo_label.text = "%d / %d" % [int(ammo.x), int(ammo.y)]
	_weapon_label.text = res.weapon_name


# ---- 波次刷怪（T12：WaveSpawner 装配；取代 T10 的临时 standable shuffle 撒点）----
func _setup_wave_spawner() -> void:
	_spawner = WaveSpawner.new()
	_spawner.name = "WaveSpawner"
	add_child(_spawner)
	_spawner.setup(LAYOUT.standable_surfaces(), _spawn_enemy, LAYOUT.spawn_exclusions())
	_spawner.wave_started.connect(_on_wave_started)
	_spawner.enemies_left.connect(_on_enemies_left)
	_spawner.start()


## spawn_fn 闭包：实例化 Enemy 并放到位（pos.y 已含面 top_y——Enemy 原点在脚底）。
## 朝向沿用 T10：面向广场中心 (0,0,0) ±30°（Godot -Z 前向：yaw = atan2(-dir.x, -dir.z)）。
func _spawn_enemy(surface: Dictionary, pos: Vector3) -> Node:
	var e := Enemy.new()
	e.name = "Enemy%d_%s" % [_spawn_serial, str(surface["name"])]
	_spawn_serial += 1
	add_child(e)
	e.global_position = pos
	var dir := Vector3(-pos.x, 0.0, -pos.z)
	if dir.length_squared() < 0.01:  # 退化兜底：中心位无朝向，默认朝 -Z
		dir = Vector3(0, 0, -1)
	dir = dir.normalized()
	e.rotation.y = atan2(-dir.x, -dir.z) + randf_range(-PI / 6.0, PI / 6.0)
	return e


func _on_wave_started(n: int) -> void:
	_update_wave_label(n, WaveSpawner.WAVE_SIZE)


func _on_enemies_left(count: int) -> void:
	_update_wave_label(_spawner.current_wave(), count)


func _update_wave_label(wave_n: int, left: int) -> void:
	if _wave_label:
		_wave_label.text = "波次 %d · 剩余 %d" % [wave_n, left]


func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_tree().quit()


# ---- 输入路由（L_Main 同款：fire 由 WeaponManager 物理帧轮询，这里路由 reload/aim/切枪）----
func _unhandled_input(event: InputEvent) -> void:
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
