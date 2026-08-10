# test/unit/test_grenade.gd
# M1 任务4：Grenade 投掷物测试（TDD RED 先行）
# 行为（brief §行为要求）：
#   - 投掷：init(origin, direction, strength) 位置 + linear_velocity = direction.normalized() × strength
#     （重力抛体自然下落）
#   - 引信 fuse_time（M67 1.5s）计时 → 自动 explode → exploded 信号 + queue_free
#   - 爆炸：blast_radius 内 Objects 层目标（形状查询，无部位倍率），**CS 线性衰减**
#     dmg = damage × (1 − d/blast_radius)（数值来源 .tres：M67 damage 98 / blast_radius 8.89m）；
#     中心满伤 98 不秒杀 100HP，随距离线性降 0；目标实现 take_damage（参考 m1-src bullet.gd）
#   - 手动 explode() → 爆炸 + 释放 + 幂等（不重复结算）
# 全局约束（计划 §4）：数值唯一来源 weapon_*.tres（期望值引用 m67.damage/blast_radius，不硬编码散值）；
# 目标 100HP 单位（企划书：所有单位统一 100 HP）。
extends GutTest

var m67: WeaponResource


func before_each() -> void:
	m67 = load("res://Weapons/weapon_m67.tres")


# CS 线性衰近期望值（派生自 .tres，不硬编码）：dmg = damage×(1−d/radius)，夹取 [0, damage]
func _linear(d: float) -> float:
	return clampf(m67.damage * (1.0 - d / m67.blast_radius), 0.0, m67.damage)


# ---- 夹具 ----

# 100HP 靶子（Objects 层 + take_damage 结算接口）
class TargetDummy:
	extends StaticBody3D

	var hp: float = 100.0
	var taken: Array = []

	func take_damage(dmg: float) -> void:
		hp -= dmg
		taken.append(dmg)

	func _ready() -> void:
		collision_layer = 1  # Objects 层（全局约束 §4）
		collision_mask = 0
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(2, 2, 2)
		shape.shape = box
		add_child(shape)


# 多碰撞形状靶子（同父节点 2 个碰撞体，模拟未来敌人躯干+头部）：验证爆炸结算按 collider 去重
class MultiShapeDummy:
	extends StaticBody3D

	var taken: Array = []

	func take_damage(dmg: float) -> void:
		taken.append(dmg)

	func _ready() -> void:
		collision_layer = 1  # Objects 层（全局约束 §4）
		collision_mask = 0
		for i in 2:
			var shape := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(2, 2, 2)
			shape.shape = box
			shape.position = Vector3(float(i), 0, 0)  # 并排两个盒体，均落在爆炸球内
			add_child(shape)


func _spawn_grenade(origin: Vector3, direction: Vector3, strength: float) -> Grenade:
	var g := Grenade.new()
	g.resource = m67
	add_child_autofree(g)
	g.init(origin, direction, strength)
	return g


func _build_dummy(at: Vector3) -> TargetDummy:
	var d := TargetDummy.new()
	add_child_autofree(d)
	d.global_position = at
	return d


func _explode_over_dummy(dist: float) -> TargetDummy:
	# 靶子先注册进物理空间（await 2 帧），再生成手雷并当场引爆（无物理帧间隔，位置不受积分扰动）
	var dummy := _build_dummy(Vector3(0, 0, -dist))
	await wait_physics_frames(2)
	var g := _spawn_grenade(Vector3.ZERO, Vector3(0, 0, -1), 20.0)
	g.explode()
	return dummy


# ================= 1. 投掷与引信 =================
func test_init_sets_velocity_and_gravity_falls() -> void:
	# 抛物线：初始速度 = 方向 × 强度，重力抛体自然下落（y 速度变负）
	var g := _spawn_grenade(Vector3(0, 2, 0), Vector3(0, 0, -1), 20.0)
	assert_eq(g.linear_velocity, Vector3(0, 0, -20), "初始速度 = direction.normalized() × strength")
	await wait_physics_frames(10)
	assert_lt(g.linear_velocity.y, 0.0, "重力作用下落（y 速度变负）")
	assert_lt(g.global_position.y, 2.0, "高度随下落降低")


func test_fuse_explodes_after_fuse_time() -> void:
	# 引信 1.5s（m67.fuse_time）计时 → 自动爆炸 → exploded 信号 + 释放
	# （信号捕获用 Array：GDScript lambda 对局部变量按值捕获，数组为引用可变更）
	var g := _spawn_grenade(Vector3.ZERO, Vector3(0, 0, -1), 20.0)
	var exploded_events: Array = []
	g.exploded.connect(func(center: Vector3) -> void: exploded_events.append(center))
	await wait_physics_frames(95)  # 1.5s × 60Hz = 90 帧，+5 余量
	assert_eq(exploded_events.size(), 1, "引信结束自动爆炸一次")
	assert_true(not is_instance_valid(g) or g.is_queued_for_deletion(), "爆炸后已释放（queue_free）")


# ================= 2. 爆炸伤害衰减（CS 线性，100HP 单位场景） =================
func test_explosion_damage_center_max_no_instakill() -> void:
	# 脚下/中心爆炸 = 满伤 98，100 → 2 HP 不秒杀（用户要求：CS 手雷最高 98 无法直接秒杀）
	var dummy := await _explode_over_dummy(0.0)
	assert_almost_eq(dummy.taken[0], m67.damage, 0.001, "0m = 满伤 98（damage 字段）")
	assert_almost_eq(dummy.hp, 100.0 - m67.damage, 0.001, "100 → 2 HP")
	assert_gt(dummy.hp, 0.0, "最高 98 不秒杀满血")


func test_explosion_damage_linear_half_radius() -> void:
	var dist := m67.blast_radius * 0.5
	var dummy := await _explode_over_dummy(dist)
	assert_almost_eq(dummy.taken[0], _linear(dist), 0.001, "半径中点 = 50% 伤害（线性）")
	assert_almost_eq(dummy.hp, 100.0 - _linear(dist), 0.001, "HP = 100 − 线性伤害")


func test_explosion_damage_linear_far() -> void:
	var dist := m67.blast_radius * 0.8
	var dummy := await _explode_over_dummy(dist)
	assert_almost_eq(dummy.taken[0], _linear(dist), 0.001, "0.8 半径 = 20% 伤害（线性）")


func test_explosion_outside_radius_no_damage() -> void:
	# 爆炸半径外不伤害
	var dummy := await _explode_over_dummy(m67.blast_radius + 1.0)
	assert_eq(dummy.taken.size(), 0, "半径外目标不受伤害")
	assert_almost_eq(dummy.hp, 100.0, 0.001, "HP 保持 100")


func test_explosion_deduplicates_multi_shape_target() -> void:
	# 多碰撞形状目标（同父节点 2 个碰撞体）只结算一次伤害——
	# intersect_shape 对同一 collider 的每个相交形状各返回一条结果，须按 collider 去重
	var dummy := MultiShapeDummy.new()
	add_child_autofree(dummy)
	dummy.global_position = Vector3(0, 0, -1)
	await wait_physics_frames(2)  # 靶子注册进物理空间
	var g := _spawn_grenade(Vector3.ZERO, Vector3(0, 0, -1), 20.0)
	g.explode()
	assert_eq(dummy.taken, [_linear(1.0)], "多形状目标只结算一次 1m 线性伤害（非两次）")


# ================= 3. 手动爆炸 =================
func test_manual_explode_emits_and_frees() -> void:
	var g := _spawn_grenade(Vector3.ZERO, Vector3(0, 0, -1), 20.0)
	var exploded_events: Array = []
	g.exploded.connect(func(center: Vector3) -> void: exploded_events.append(center))
	g.explode()
	assert_eq(exploded_events.size(), 1, "手动 explode 发 exploded 信号")
	assert_true(g.is_queued_for_deletion(), "爆炸后 queue_free 释放")
	g.explode()  # 幂等：重复调用不重复结算
	assert_eq(exploded_events.size(), 1, "重复 explode 只爆一次")


# ================= 4. damage_in_radius 纯逻辑（CS 线性衰减） =================
func test_damage_in_radius_center_equals_damage_field() -> void:
	# 中心满伤 == damage 字段（企划书 §4.2.5 数值唯一来源 .tres）
	var g := _spawn_grenade(Vector3.ZERO, Vector3(0, 0, -1), 20.0)
	assert_almost_eq(g.damage_in_radius(0.0), m67.damage, 0.001, "0m = 满伤 98（damage 字段）")


func test_damage_in_radius_linear_falloff() -> void:
	# CS 同款线性：每 1/4 半径损失 25% 伤害
	var g := _spawn_grenade(Vector3.ZERO, Vector3(0, 0, -1), 20.0)
	var r := m67.blast_radius
	assert_almost_eq(g.damage_in_radius(r * 0.25), m67.damage * 0.75, 0.001, "1/4 半径 = 75% 伤害")
	assert_almost_eq(g.damage_in_radius(r * 0.5), m67.damage * 0.5, 0.001, "1/2 半径 = 50% 伤害")
	assert_almost_eq(g.damage_in_radius(r * 0.75), m67.damage * 0.25, 0.001, "3/4 半径 = 25% 伤害")


func test_damage_in_radius_at_and_beyond_radius_zero() -> void:
	var g := _spawn_grenade(Vector3.ZERO, Vector3(0, 0, -1), 20.0)
	var r := m67.blast_radius
	assert_almost_eq(g.damage_in_radius(r), 0.0, 0.001, "半径边缘 = 0（线性衰减到底）")
	assert_eq(g.damage_in_radius(r + 5.0), 0.0, "半径外不伤害")
	assert_eq(g.damage_in_radius(-1.0), 0.0, "负距离不伤害")
