# Player/MovementCommand.gd —— AI/自动遍历驱动玩家控制器的命令接口（2026-08-14）。
# 未来 AI 移动底层 = 玩家运动逻辑：AI 队友/敌人通过本接口发指令驱动同款控制器。
# 语义：move_axis 为角色本地轴（x=左右/y=前后，与 Input.get_vector(&"move_left",…) 同构）；
# jump_pressed 为单帧边沿（控制器读取后清零）；crouch 预留（自动遍历恒 false，未来 AI 蹲伏接入点）。
class_name MovementCommand
extends RefCounted

var move_axis := Vector2.ZERO
var jump_pressed := false
var crouch := false
