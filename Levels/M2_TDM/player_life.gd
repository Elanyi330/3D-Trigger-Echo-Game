# Levels/M2_TDM/player_life.gd
# 玩家生命组件（2026-08-13，TDM 框架）：100HP / 受伤 / 死亡 / 复活。
# 死亡：died 信号 + 冻结玩家节点（PROCESS_MODE_DISABLED 锁全部输入）+ on_death 回调
#       （L_M2 释放营地点位）→ 3s（可注入）→ 复活：
#       位置 = on_respawn_point 回调（L_M2 从北营空点 acquire，保证不与友军重叠）、
#       满血 + on_reset 回调（武器满弹重置）、恢复玩家节点、respawned 信号。
# M3 接入：敌人 AI 对枪时调用 take_damage 即可，接口已备。
class_name PlayerLife
extends Node

signal health_changed(hp: float)
signal died
signal respawned

const MAX_HEALTH := 100.0   # 企划书：所有单位统一 100HP
const RESPAWN_DELAY := 3.0  # 2026-08-11 用户拍板

var health: float = MAX_HEALTH
var dead: bool = false

var _player: Node
var _respawn_delay: float = RESPAWN_DELAY
var _on_death: Callable = Callable()         # 死亡瞬间回调（释放营地点位）
var _on_respawn_point: Callable = Callable()  # 复活取点回调 -> Vector3（空点，防重叠）
var _on_reset: Callable = Callable()          # 复活重置回调（武器满弹等）
var _respawn_gen := 0                          # 复活计时器失效键（防旧计时器/重开竞态）


func setup(player: Node, on_death: Callable = Callable(),
		on_respawn_point: Callable = Callable(), on_reset: Callable = Callable(),
		respawn_delay: float = RESPAWN_DELAY) -> void:
	_player = player
	_on_death = on_death
	_on_respawn_point = on_respawn_point
	_on_reset = on_reset
	_respawn_delay = respawn_delay


func take_damage(dmg: float) -> void:
	if dead:
		return
	health = maxf(health - dmg, 0.0)
	health_changed.emit(health)
	if health <= 0.0:
		_die()


func _die() -> void:
	dead = true
	_respawn_gen += 1
	died.emit()
	if _player:
		_player.process_mode = Node.PROCESS_MODE_DISABLED  # 冻结移动/开火/相机
	if _on_death.is_valid():
		_on_death.call()
	_respawn_soon()


func _respawn_soon() -> void:
	var gen := _respawn_gen
	await get_tree().create_timer(_respawn_delay).timeout
	if not is_inside_tree() or gen != _respawn_gen:
		return  # 场景退出/重开强制复活后旧计时器失效
	_do_respawn()


## 重开强制复活（R 键重开消费）：无论存活与否，立即回满血、取新点、满弹重置。
## 死亡倒计时挂起时先使旧计时器失效（_respawn_gen），绝不双重复活。
func respawn_now() -> void:
	_respawn_gen += 1
	_do_respawn()


func _do_respawn() -> void:
	health = MAX_HEALTH
	dead = false
	if _player:
		if _on_respawn_point.is_valid():
			_player.global_position = _on_respawn_point.call()
		_player.process_mode = Node.PROCESS_MODE_INHERIT
	if _on_reset.is_valid():
		_on_reset.call()
	health_changed.emit(health)
	respawned.emit()
