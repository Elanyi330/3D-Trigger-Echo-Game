# test/unit/test_limited_ammo.gd
# 有限弹药（2026-08-13，TDD RED 先行）：
# 需求（用户拍板）：取消无限子弹/无限手雷；手雷用完按 4 无反应（只有手中有雷才可切）；
# 弹药箱拾取：备弹回归上限（弹匣不自动补充）+ 补一枚新手雷。
extends GutTest

var mgr: WeaponManager

func before_each() -> void:
	Input.action_release("fire")
	mgr = WeaponManager.new()
	add_child_autofree(mgr)
	var slots: Array[WeaponResource] = [
		load("res://Weapons/weapon_ak47.tres"),
		load("res://Weapons/weapon_glock18.tres"),
		load("res://Weapons/weapon_knife.tres"),
		load("res://Weapons/weapon_m67.tres"),
	]
	mgr.setup(slots, null)
	watch_signals(mgr)


func test_grenade_switch_blocked_when_empty() -> void:
	# 开局在槽 0（主武器）；空雷按 4 必须无反应（不切槽、不发切换信号）
	var g := mgr.get_core(3)
	g._mag = 0  # 手雷已用完
	mgr.switch_to(3)
	assert_eq(mgr.get_current_slot(), 0, "空雷按 4 无反应（保持当前武器）")
	assert_signal_not_emitted(mgr, "weapon_switched", "无切换信号")


func test_grenade_switch_allowed_with_grenade() -> void:
	mgr.switch_to(3)
	assert_eq(mgr.get_current_slot(), 3, "手中有雷可正常切入手雷槽")


func test_collect_ammo_box_refills_reserve_not_mag() -> void:
	var ak := mgr.get_core(0)
	ak._mag = 5       # 弹匣剩 5
	ak._reserve = 10  # 备弹剩 10
	mgr.collect_ammo_box()
	var ammo: Vector2 = ak.get_ammo()
	assert_eq(ammo.x, 5.0, "弹匣不自动补充（保持 5）")
	assert_eq(ammo.y, ak._resource.max_ammo, "备弹回归上限")
	assert_signal_emitted(mgr, "weapon_ammo_updated", "拾取发弹药信号")


func test_collect_ammo_box_adds_grenade() -> void:
	var g := mgr.get_core(3)
	g._mag = 0  # 手雷用完了
	mgr.collect_ammo_box()
	assert_eq(g.get_ammo().x, 1.0, "拾取补一枚新手雷")
	# 再拾取不超上限
	mgr.collect_ammo_box()
	assert_eq(g.get_ammo().x, 1.0, "手雷上限 1 枚")


func test_ammo_box_refill_all_slots() -> void:
	var ak := mgr.get_core(0)
	var glock := mgr.get_core(1)
	ak._reserve = 0
	glock._reserve = 0
	mgr.collect_ammo_box()
	assert_eq(ak.get_ammo().y, load("res://Weapons/weapon_ak47.tres").max_ammo, "AK 备弹补满")
	assert_eq(glock.get_ammo().y, load("res://Weapons/weapon_glock18.tres").max_ammo, "Glock 备弹补满")
