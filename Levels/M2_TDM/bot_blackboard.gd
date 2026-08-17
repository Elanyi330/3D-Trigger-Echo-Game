# Levels/M2_TDM/bot_blackboard.gd
# M3.2 T10（2026-08-17）：BotBlackboard 黑板——M3.3 决策层 BotBrain 的输入存储。
# 语义：
#   1. 极简键值存储（Dictionary 底层）；set_value 写后发 key_changed(key)
#      （同值重写仍发，无去重——订阅方自行幂等）。
#   2. M3.2 装配口径（本任务不装配 L_M2）：每 bot 持一个 BotBlackboard；
#      M3.3 Brain 装配时感知层写入标准键 `hostiles`（可见敌对列表）、
#      `heard`（近期听觉事件）、`lkp`（各目标最后位置）；死亡事件由 Brain
#      主动查 EventBoard（黑板不主动存 deaths）。
#   3. clear() 清空且不发信号（全量重建语义：重建认知不逐键通知订阅方）。
#   4. 无任何逻辑（无状态机/推理）——纯存储 + 通知。
class_name BotBlackboard
extends Node

signal key_changed(key: String)

var _data: Dictionary = {}


func set_value(key: String, value: Variant) -> void:
	_data[key] = value
	key_changed.emit(key)


func get_value(key: String, default: Variant = null) -> Variant:
	return _data.get(key, default)


func has(key: String) -> bool:
	return _data.has(key)


func clear() -> void:
	_data.clear()
