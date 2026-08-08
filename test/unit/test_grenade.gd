# test/unit/test_grenade.gd
# M1 任务4：Grenade 投掷物测试（TDD RED 先行）
# 行为（brief §行为要求）：
#   - 投掷：init(origin, direction, strength) 位置 + linear_velocity = direction.normalized() × strength
#     （重力抛体自然下落）
#   - 引信 fuse_time（M67 1.5s）计时 → 自动 explode → exploded 信号 + queue_free
#   - 爆炸：blast_radius 内 Objects 层目标（形状查询，无部位倍率），中心距离阶梯衰减
#     （blast_falloff 表，数值来源 .tres：1m→98 / 3m→60 / 5m→30 / >6m 不伤害）；
#     目标实现 take_damage（参考 m1-src bullet.gd 的 has_method 结算）
#   - 手动 explode() → 爆炸 + 释放 + 幂等（不重复结算）
# 全局约束（计划 §4）：数值唯一来源 weapon_*.tres（期望值引用 m67.blast_falloff，不硬编码散值）；
# 目标 100HP 单位（企划书：所有单位统一 100 HP）。
extends GutTest

var m67: WeaponResource


func before_each() -> void:
	m67 = load("res://Weapons/weapon_m67.tres")


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


# ================= 2. 爆炸伤害衰减（100HP 单位场景） =================
func test_explosion_damage_98_at_1m() -> void:
	# 中心 98 不秒杀（企划书 §4.2.3⑦：100 → 2 HP）
	var dummy := await _explode_over_dummy(1.0)
	assert_eq(dummy.taken, [m67.blast_falloff[0]], "1m 距离 = 满伤 98（blast_falloff 首段）")
	assert_almost_eq(dummy.hp, 100.0 - m67.blast_falloff[0], 0.001, "100 → 2 HP")


func test_explosion_damage_60_at_3m() -> void:
	var dummy := await _explode_over_dummy(3.0)
	assert_eq(dummy.taken, [m67.blast_falloff[1]], "3m 距离 = 中段 60（blast_falloff[1]）")
	assert_almost_eq(dummy.hp, 100.0 - m67.blast_falloff[1], 0.001, "100 → 40 HP")


func test_explosion_damage_30_at_5m() -> void:
	var dummy := await _explode_over_dummy(5.0)
	assert_eq(dummy.taken, [m67.blast_falloff[2]], "5m 距离 = 末段 30（blast_falloff[2]）")
	assert_almost_eq(dummy.hp, 100.0 - m67.blast_falloff[2], 0.001, "100 → 70 HP")


func test_explosion_outside_radius_no_damage() -> void:
	# 爆炸半径外（>6m）不伤害
	var dummy := await _explode_over_dummy(7.0)
	assert_eq(dummy.taken.size(), 0, "半径外目标不受伤害")
	assert_almost_eq(dummy.hp, 100.0, 0.001, "HP 保持 100")


func test_explosion_deduplicates_multi_shape_target() -> void:
	# 多碰撞形状目标（同父节点 2 个碰撞体）只结算一次伤害（98 而非 196）——
	# intersect_shape 对同一 collider 的每个相交形状各返回一条结果，须按 collider 去重
	var dummy := MultiShapeDummy.new()
	add_child_autofree(dummy)
	dummy.global_position = Vector3(0, 0, -1)
	await wait_physics_frames(2)  # 靶子注册进物理空间
	var g := _spawn_grenade(Vector3.ZERO, Vector3(0, 0, -1), 20.0)
	g.explode()
	assert_eq(dummy.taken, [m67.blast_falloff[0]], "多形状目标只结算一次满伤 98（非 [98, 98]）")


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


# ================= 4. damage_in_radius 纯逻辑（数值派生自 .tres） =================
func test_damage_in_radius_center_equals_damage_field() -> void:
	# 中心满伤 == damage 字段（blast_falloff 首段与基础伤害自洽，企划书 §4.2.5 数值唯一来源）
	var g := _spawn_grenade(Vector3.ZERO, Vector3(0, 0, -1), 20.0)
	assert_eq(m67.blast_falloff.size(), 3, "衰减表 3 段（98/60/30，.tres 数值）")
	assert_almost_eq(g.damage_in_radius(0.0), m67.damage, 0.001, "0m = 基础伤害 98")


func test_damage_in_radius_full_band() -> void:
	var g := _spawn_grenade(Vector3.ZERO, Vector3(0, 0, -1), 20.0)
	assert_almost_eq(g.damage_in_radius(1.0), m67.blast_falloff[0], 0.001, "1m（2m 内）= 98")
	assert_almost_eq(g.damage_in_radius(2.0), m67.blast_falloff[1], 0.001, "2m 边界进中段 = 60")


func test_damage_in_radius_mid_and_edge_bands() -> void:
	var g := _spawn_grenade(Vector3.ZERO, Vector3(0, 0, -1), 20.0)
	assert_almost_eq(g.damage_in_radius(3.0), m67.blast_falloff[1], 0.001, "3m（4m 内）= 60")
	assert_almost_eq(g.damage_in_radius(4.0), m67.blast_falloff[2], 0.001, "4m 边界进末段 = 30")
	assert_almost_eq(g.damage_in_radius(5.0), m67.blast_falloff[2], 0.001, "5m（6m 内）= 30")


func test_damage_in_radius_beyond_radius_zero() -> void:
	var g := _spawn_grenade(Vector3.ZERO, Vector3(0, 0, -1), 20.0)
	assert_almost_eq(g.damage_in_radius(6.0), m67.blast_falloff[2], 0.001, "6m 边缘 = 30（半径内）")
	assert_eq(g.damage_in_radius(7.0), 0.0, ">6m 不伤害")
	assert_eq(g.damage_in_radius(-1.0), 0.0, "负距离不伤害")
