# Levels/Main/Target.gd
# M1 任务6：L_Main 测试靶子（Objects 层 + Group "torso"）
#
# take_damage(dmg) 结算接口——Grenade 爆炸按 has_method 调用（参考 m1-src bullet.gd 目标结算约定）；
# 当前仅 Grenade 爆炸消费（hitscan 走 hit_landed 信号，不直接结算伤害）。企划书：所有单位统一 100 HP。
class_name Target
extends StaticBody3D

var health: float = 100.0


func take_damage(dmg: float) -> void:
	health -= dmg
