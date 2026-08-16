# Levels/M2_TDM/event_board.gd
# M3.2 T9（2026-08-17）：EventBoard 事件板——死亡事件记录 / 时间窗查询 / TTL 剔除。
# 语义：
#   1. record_death：追加 {faction, pos, t=_elapsed}（时间戳用 _elapsed 单调累计，
#      tick 首行 delta 求和——测试可控，不用 Time.get_ticks），同步发 death_event。
#   2. recent_deaths(faction, within)：返回 faction 的 _elapsed - t <= within 事件
#      （副本、按 t 升序——追加序即时间序）。
#   3. tick：_elapsed - t > DEATH_TTL(30s) 剔除（L_M2._process 每帧驱动）。
#   4. 阵营共享：全局一板，faction 字段区分阵营——两阵营 bot 都读（M3.3 装配）。
#   5. 不含击杀者位置（拍板铁律：死亡源头由 bot 自己感知推导）——事件只有
#      faction + 位置 + 时间戳。
class_name EventBoard
extends Node

signal death_event(faction: String, pos: Vector3, t: float)

const DEATH_TTL := 30.0     # s：死亡事件保留

var _elapsed := 0.0
var _deaths: Array = []     # [{faction, pos, t}]（追加序 = t 升序）


func record_death(faction: String, pos: Vector3) -> void:
	var ev := {"faction": faction, "pos": pos, "t": _elapsed}
	_deaths.append(ev)
	death_event.emit(faction, pos, _elapsed)


func recent_deaths(faction: String, within: float) -> Array:
	var out: Array = []
	for ev in _deaths:
		if ev["faction"] == faction and _elapsed - ev["t"] <= within:
			out.append(ev.duplicate())  # 副本——外部改动不回写板内
	return out


func tick(delta: float) -> void:
	_elapsed += delta
	for i in range(_deaths.size() - 1, -1, -1):
		if _elapsed - _deaths[i]["t"] > DEATH_TTL:
			_deaths.remove_at(i)
