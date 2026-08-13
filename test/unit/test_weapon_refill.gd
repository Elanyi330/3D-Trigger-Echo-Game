# test/unit/test_weapon_refill.gd
# TDM 复活满弹（2026-08-13，TDD RED 先行）：WeaponCore.refill()——
# 弹匣/备弹填满、打断换弹、后坐力/射击序号/冷却复位（复活即全新武器手感）。
extends GutTest

func before_each() -> void:
	Input.action_release("fire")


func test_refill_fills_mag_and_reserve() -> void:
	var core := WeaponCore.new()
	add_child_autofree(core)
	var ak: WeaponResource = load("res://Weapons/weapon_ak47.tres")
	core.setup(ak, null)
	core._mag = 3        # 模拟打到剩 3 发
	core._reserve = 10
	core.refill()
	var ammo: Vector2 = core.get_ammo()
	assert_eq(ammo.x, ak.magazine, "弹匣填满")
	assert_eq(ammo.y, ak.max_ammo, "备弹填满")


func test_refill_interrupts_reload() -> void:
	var core := WeaponCore.new()
	add_child_autofree(core)
	var ak: WeaponResource = load("res://Weapons/weapon_ak47.tres")
	core.setup(ak, null)
	core._reloading = true
	core.refill()
	assert_false(core.is_reloading(), "换弹被打断")
	assert_eq(core.get_ammo().x, ak.magazine, "打断后弹匣仍填满")


func test_refill_resets_recoil_and_shot_index() -> void:
	var core := WeaponCore.new()
	add_child_autofree(core)
	var ak: WeaponResource = load("res://Weapons/weapon_ak47.tres")
	core.setup(ak, null)
	core.recoil_accum = Vector2(3.5, -1.2)
	core._shot_index = 7
	core._fire_cooldown = 1.5
	core.refill()
	assert_eq(core.recoil_accum, Vector2.ZERO, "后坐力累积清零")
	assert_eq(core._shot_index, 0, "射击序号复位（压枪曲线从头）")
	assert_eq(core._fire_cooldown, 0.0, "冷却清零（复活立即可开火）")
