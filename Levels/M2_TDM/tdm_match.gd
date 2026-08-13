# Levels/M2_TDM/tdm_match.gd
# TDM 比赛状态机（2026-08-13）：计分/胜负/平局/重开。
# 需求（用户 2026-08-11 拍板）：无限复活、先到 50 击杀获胜、或 8 分钟内击杀多者获胜。
# 信号驱动 HUD：score_changed / time_changed（整秒变化才发）/ match_ended。
# 参数可注入（score_target/time_limit）便于测试。
class_name TdmMatch
extends Node

signal score_changed(friendly: int, enemy: int)
signal time_changed(seconds_left: int)
signal match_ended(winner: int)  # Winner 枚举

enum Winner { DRAW, FRIENDLY, ENEMY }
enum State { PLAYING, RESULT }

const SCORE_TARGET := 50
const TIME_LIMIT := 480.0  # 8 分钟

var state: int = State.PLAYING
var friendly_score: int = 0
var enemy_score: int = 0
var elapsed: float = 0.0

var _score_target: int = SCORE_TARGET
var _time_limit: float = TIME_LIMIT
var _last_second := -1


func setup(score_target: int = SCORE_TARGET, time_limit: float = TIME_LIMIT) -> void:
	_score_target = score_target
	_time_limit = time_limit


## 开局/重开：回 PLAYING、清零、重发初始信号
func start() -> void:
	state = State.PLAYING
	friendly_score = 0
	enemy_score = 0
	elapsed = 0.0
	_last_second = time_left()
	score_changed.emit(0, 0)
	time_changed.emit(_last_second)


func time_left() -> int:
	return maxi(0, int(ceil(_time_limit - elapsed)))


## 我方击杀（M3 队友击杀同样入此账）
func add_friendly_kill() -> void:
	if state != State.PLAYING:
		return
	friendly_score += 1
	score_changed.emit(friendly_score, enemy_score)
	if friendly_score >= _score_target:
		end(Winner.FRIENDLY)


## 敌方击杀（M3 敌人对枪后生效；M3 前恒 0）
func add_enemy_kill() -> void:
	if state != State.PLAYING:
		return
	enemy_score += 1
	score_changed.emit(friendly_score, enemy_score)
	if enemy_score >= _score_target:
		end(Winner.ENEMY)


func _process(delta: float) -> void:
	if state != State.PLAYING:
		return
	elapsed += delta
	var s := time_left()
	if s != _last_second:
		_last_second = s
		time_changed.emit(s)
	if elapsed >= _time_limit:
		end(_judge())


func _judge() -> int:
	if friendly_score > enemy_score:
		return Winner.FRIENDLY
	if enemy_score > friendly_score:
		return Winner.ENEMY
	return Winner.DRAW


## 结束（幂等：RESULT 态不再触发）；结束后计分/计时冻结
func end(winner: int) -> void:
	if state != State.PLAYING:
		return
	state = State.RESULT
	match_ended.emit(winner)


func reset() -> void:
	start()
