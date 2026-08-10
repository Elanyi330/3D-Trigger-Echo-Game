# Levels/M2_TDM/L_M2.gd
# M2 TDM 小图主场景控制器：灰盒地图 + 玩家（MovementController）+ 随机敌人撒点。
# 验收目标（用户 2026-08-10）：①玩家可逛遍全图无 bug；②可踏足位置随机撒敌人，验证射击角度与空气墙。
extends Node3D

const GREYBOX := preload("res://Levels/M2_TDM/map_greybox.gd")
const LAYOUT := preload("res://Levels/M2_TDM/map_layout.gd")
const ENEMY_SCRIPT := preload("res://Levels/Enemy/Enemy.gd")

@export var enemy_count := 10   # 随机撒敌人数量（验收可调）

var _player: CharacterBody3D
var _enemies: Array[Enemy] = []


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	# 灰盒地图
	var gb: Node3D = GREYBOX.new()
	gb.name = "Greybox"
	add_child(gb)
	gb.build()
	# 玩家（MovementController，代码装配——L_Main 同款）
	_player = load("res://Player/Player.tscn").instantiate()
	_player.name = "Player"
	add_child(_player)
	_player.global_position = Vector3(0, 1.0, 0)  # 出生点
	# 随机敌人撒点（可踏足位置抽样）
	_spawn_random_enemies()


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
