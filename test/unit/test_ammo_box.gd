# test/unit/test_ammo_box.gd
# 弹药箱（2026-08-13，TDD RED 先行）：
# 需求（用户拍板）：固定点位刷新；玩家靠近自动拾取（弹药回归上限+新手雷一枚）；
# 拾取后 30s（可注入）自动重新刷新；重开强制恢复。
extends GutTest

const AMMO_BOX := preload("res://Levels/M2_TDM/ammo_box.gd")


func test_pick_on_proximity() -> void:
	var target := Node3D.new()
	add_child_autofree(target)
	target.position = Vector3(0, 0, 0)
	var box = AMMO_BOX.new()
	add_child_autofree(box)
	box.setup(target, 30.0)
	box.global_position = Vector3(1.0, 0, 0)  # 距 1.0 ≤ 拾取半径 1.4
	var picks := []
	box.picked_up.connect(func() -> void: picks.append(true))
	await wait_seconds(0.1)
	assert_eq(picks.size(), 1, "靠近自动拾取")
	assert_false(box.is_active(), "拾取后失效")


func test_no_pick_when_far() -> void:
	var target := Node3D.new()
	add_child_autofree(target)
	target.position = Vector3(0, 0, 0)
	var box = AMMO_BOX.new()
	add_child_autofree(box)
	box.setup(target, 30.0)
	box.global_position = Vector3(5.0, 0, 0)  # 距 5 > 1.4
	var picks := []
	box.picked_up.connect(func() -> void: picks.append(true))
	await wait_seconds(0.1)
	assert_eq(picks.size(), 0, "远处不拾取")
	assert_true(box.is_active())


func test_respawn_after_delay() -> void:
	var target := Node3D.new()
	add_child_autofree(target)
	target.position = Vector3(0, 0, 0)
	var box = AMMO_BOX.new()
	add_child_autofree(box)
	box.setup(target, 0.3)  # 注入短刷新时间
	box.global_position = Vector3(1.0, 0, 0)
	await wait_seconds(0.1)
	assert_false(box.is_active(), "已拾取")
	target.position = Vector3(50, 0, 0)  # 走远
	await wait_seconds(0.5)
	assert_true(box.is_active(), "30s（注入 0.3s）后自动重新刷新")


func test_respawn_box_repickable() -> void:
	var target := Node3D.new()
	add_child_autofree(target)
	target.position = Vector3(0, 0, 0)
	var box = AMMO_BOX.new()
	add_child_autofree(box)
	box.setup(target, 0.3)
	box.global_position = Vector3(1.0, 0, 0)
	var picks := []
	box.picked_up.connect(func() -> void: picks.append(true))
	await wait_seconds(0.1)
	assert_eq(picks.size(), 1)
	# 刷新后仍在拾取半径内 → 再次拾取（时序竞态：第 3 次拾取可能刚好发生，断言 ≥2）
	await wait_seconds(0.6)
	assert_gte(picks.size(), 2, "刷新后可再次拾取")


func test_force_respawn() -> void:
	var target := Node3D.new()
	add_child_autofree(target)
	target.position = Vector3(0, 0, 0)
	var box = AMMO_BOX.new()
	add_child_autofree(box)
	box.setup(target, 999.0)
	box.global_position = Vector3(1.0, 0, 0)
	await wait_seconds(0.1)
	assert_false(box.is_active())
	target.position = Vector3(50, 0, 0)
	box.force_respawn()  # 重开恢复
	assert_true(box.is_active(), "force_respawn 立即恢复激活")
