# Levels/M2_TDM/L_M2.gd
# M2 TDM 小图主场景控制器：灰盒地图 + 玩家（MovementController）+ 武器系统 + 随机敌人撒点。
# 验收目标（用户 2026-08-10）：①玩家可逛遍全图无 bug；②可踏足位置随机撒敌人，验证射击角度与空气墙。
# 武器装配移植自 L_Main.gd（同一套 WeaponManager + WeaponView + 输入路由 + HUD）。
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
const LAYOUT := preload("res://Levels/M2_TDM/map_layout.gd")
const ENEMY_SCRIPT := preload("res://Levels/Enemy/Enemy.gd")

@export var enemy_count := 10   # 随机撒敌人数量（验收可调）

var _player: CharacterBody3D
var _head: Node3D
var _manager: WeaponManager
var _view: WeaponView
var _enemies: Array[Enemy] = []


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	# 灰盒地图
	var gb: Node3D = GREYBOX.new()
	gb.name = "Greybox"
	add_child(gb)
	gb.build()
	# 玩家（Player.tscn：MovementController + Head + Crouch）
	_player = load("res://Player/Player.tscn").instantiate()
	_player.name = "Player"
	add_child(_player)
	_player.global_position = Vector3(0, 1.0, 0)  # 大厅北口出生
	_head = _player.get_node("Head")
	_setup_weapons()
	_setup_hud()
	# 随机敌人撒点（可踏足位置抽样）
	_spawn_random_enemies()


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
	_view = WeaponView.new()
	_view.name = "WeaponView"
	_head.add_child(_view)
	_view.setup(_manager, _player)


# ---- 准星（简单 HUD，开火提示用）----
func _setup_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "HUD"
	add_child(layer)
	var cross := Label.new()
	cross.text = "+"
	cross.add_theme_font_size_override("font_size", 36)
	cross.add_theme_color_override("font_color", Color(0.2, 1, 0.35))
	cross.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	cross.add_theme_constant_override("outline_size", 8)
	layer.add_child(cross)
	cross.position = get_viewport().get_visible_rect().size * 0.5 + Vector2(-11, -26)


# ---- 随机敌人撒点 ----
func _spawn_random_enemies() -> void:
	var spots := _sample_standable_spots()
	for i in mini(enemy_count, spots.size()):
		var e := Enemy.new()
		e.name = "Enemy%d" % i
		add_child(e)
		e.global_position = spots[i] + Vector3(0, 1.0, 0)
		e.rotation.y = randf() * TAU
		_enemies.append(e)


# 可踏足位置抽样：地图各区域的站立点（灰盒数据驱动，避免出生在墙内/墙上）
func _sample_standable_spots() -> Array[Vector3]:
	var spots: Array[Vector3] = []
	# 西街沿线
	for z in [-10, -5, 0, 5, 10]:
		spots.append(Vector3(-12, 0, z))
	# 东街沿线
	for z in [-10, -4, 3, 9]:
		spots.append(Vector3(12, 0, z))
	# 中街北/南
	spots.append(Vector3(0, 0, -12))
	spots.append(Vector3(0, 0, 12))
	# 大厅内
	for x in [-5, 0, 5]:
		for z in [-4, 0, 4]:
			spots.append(Vector3(x, 0, z))
	# 出生区前
	spots.append(Vector3(-2, 0, 22))
	spots.append(Vector3(-2, 0, -22))
	return spots


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
