# Levels/M2_TDM/tdm_respawner.gd
# TDM 敌营补位器（2026-08-13，替代旧 WaveSpawner 波次刷怪）：
# 敌方营地 10 个刷新点中随机取 5 点刷 5 敌（SpawnPool 保证不与任何角色重叠）；
# 敌死 → 释放点位 → 3s（可注入）后从"当前无角色占用的空点"补位——恒 5 敌。
# 依赖注入：不依赖 Enemy 类，spawn_fn() -> Node（L_M2 负责实例化 Enemy 并 add_child），
# 本类负责点位分配与定位（enemy.global_position = 池点）。
# 重开：clear() 清场 + 池全释放；generation 计数防旧补位计时器在重开后多刷。
class_name TdmRespawner
extends Node

signal enemy_spawned(enemy: Node)
signal enemy_died(enemy: Node)       # 计分接线（TdmMatch.add_friendly_kill）
signal strength_changed(alive: int)

const SQUAD_SIZE := 5
const RESPAWN_DELAY := 3.0  # 2026-08-11 用户拍板

var _pool: SpawnPool
var _spawn_fn: Callable
var _respawn_delay: float = RESPAWN_DELAY
var _squad: Array = []      # 存活敌人列表
var _generation := 0


func setup(points: Array, spawn_fn: Callable, respawn_delay: float = RESPAWN_DELAY) -> void:
	_pool = SpawnPool.new()
	_pool.setup(points)
	_spawn_fn = spawn_fn
	_respawn_delay = respawn_delay


## 开局/重开：清场后刷满 5 敌
func start() -> void:
	clear()
	for _i in SQUAD_SIZE:
		_spawn_one()


func alive_count() -> int:
	return _squad.size()


## 重开清场：存活敌人全部释放 + 点位池全释放；旧补位计时器因 generation 失效
func clear() -> void:
	_generation += 1
	_pool.release_all()
	for e in _squad:
		if is_instance_valid(e):
			e.queue_free()
	_squad.clear()


func _spawn_one() -> void:
	var enemy: Node = _spawn_fn.call()
	if enemy == null:
		push_warning("TdmRespawner._spawn_one(): spawn_fn 返回 null，跳过")
		return
	enemy.global_position = _pool.acquire(enemy)  # 空点分配（不重叠保证）
	_squad.append(enemy)
	enemy_spawned.emit(enemy)
	enemy.died.connect(_on_enemy_died.bind(enemy), CONNECT_ONE_SHOT)


func _on_enemy_died(enemy: Node) -> void:
	var gen := _generation
	_squad.erase(enemy)
	_pool.release(enemy)  # 立即释放点位
	strength_changed.emit(_squad.size())
	enemy_died.emit(enemy)
	await get_tree().create_timer(_respawn_delay).timeout
	if not is_inside_tree() or gen != _generation:
		return  # 场景退出/重开后旧计时器失效
	_spawn_one()
