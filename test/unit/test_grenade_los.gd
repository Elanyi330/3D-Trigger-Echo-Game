# test/unit/test_grenade_los.gd
# M2 修复轮2（2026-08-13）：手雷爆炸厚度穿透衰减 + CCD（TDD）
# 行为（设计 2026-08-13-m2-combat-fixes-round2-design §一）：
#   - 沿"爆心→目标胸口参考点"线段点采样累计墙厚 T（步长 0.25m）→ 伤害 × clamp(1−T/3.0,0,1)
#     （线性截断：越厚挡越多、越薄挡越少、3m 全挡——用户拍板方案 A，替代旧二值 LOS 全挡）
#   - 无遮挡 → 距离线性衰减满值
#   - 贴地爆炸同层目标不假遮挡（胸口参考点防地板计入厚度——回归重点）
#   - 头 hitbox 自挡回归：爆心在头顶上方时采样点穿过头 hitbox——exclude 本体+子 CollisionObject3D RID
#   - 矮掩体 0.9 墙：贴地爆炸采样点落在墙内 → T=0.5 → ×5/6；爆心抬高 1.2m → 采样点过顶不挡
#   - CCD：continuous_cd = true（修复高速隧穿穿地）
# 全局约束：期望值由 m67.tres 派生（damage/blast_radius），不硬编码散值。
extends GutTest

var m67: WeaponResource
const ENEMY_SCENE := "res://Levels/Enemy/Enemy.tscn"


func before_each() -> void:
	m67 = load("res://Weapons/weapon_m67.tres")


func _spawn_enemy(at: Vector3) -> Enemy:
	var e: Enemy = load(ENEMY_SCENE).instantiate()
	add_child_autofree(e)
	e.global_position = at
	e.rotation.y = PI
	return e


func _wall(center: Vector3, size: Vector3) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.collision_layer = 1
	b.collision_mask = 0
	add_child_autofree(b)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	b.add_child(cs)
	b.global_position = center
	return b


func _explode_at(pos: Vector3) -> void:
	var g := Grenade.new()
	g.resource = m67
	add_child_autofree(g)
	g.init(pos, Vector3(0, 0, -1), 20.0)
	g.explode()


func _dist_damage(dist: float) -> float:
	return m67.damage * (1.0 - dist / m67.blast_radius)


func test_wall_attenuates_damage_by_thickness() -> void:
	var e := _spawn_enemy(Vector3(0, 0, -4))
	await wait_physics_frames(2)
	_wall(Vector3(0, 1.5, -2), Vector3(4, 3, 1))  # 爆心(0)与目标(-4)之间：3m 高墙
	await wait_physics_frames(1)  # 墙形状入空间需一物理帧（同帧 raycast 不可见——Godot 4.7.1 实测）
	_explode_at(Vector3.ZERO)
	assert_almost_eq(e.health, 100.0 - _dist_damage(4.0) * (2.0 / 3.0), 1.0,
			"1m 厚墙：伤害 = 距离衰减 × 2/3（线性截断 1−1/3）")


func test_no_wall_full_distance_damage() -> void:
	var e := _spawn_enemy(Vector3(0, 0, -4))
	await wait_physics_frames(2)
	_explode_at(Vector3.ZERO)
	assert_almost_eq(e.health, 100.0 - _dist_damage(4.0), 0.001, "无遮挡 → 距离线性衰减")


func test_ground_blast_does_not_false_block() -> void:
	# 回归：贴地爆炸 + 同层目标——射线打胸口参考点（不打脚部），地板不挡
	var e := _spawn_enemy(Vector3(0, 0, -2))
	await wait_physics_frames(2)
	_wall(Vector3(0, -0.5, 0), Vector3(40, 1, 40))  # 大底板（爆心/目标脚下）
	_explode_at(Vector3.ZERO)
	assert_almost_eq(e.health, 100.0 - _dist_damage(2.0), 0.001, "贴地爆炸无地板假遮挡")


func test_elevated_blast_does_not_self_block_via_head() -> void:
	# 回归：爆心在头顶上方 → 射线穿过头 hitbox（y≈1.70）——exclude 头 RID 防自挡
	var e := _spawn_enemy(Vector3.ZERO)
	await wait_physics_frames(2)
	_explode_at(Vector3(0, 2.5, 0))
	assert_almost_eq(e.health, 100.0 - _dist_damage(2.5), 0.001,
			"头顶爆炸：射线穿头 hitbox 不自挡（exclude 本体+头 RID）")


func test_low_cover_attenuates_ground_blast() -> void:
	# 0.9m 矮墙在贴地爆心与目标之间：射线路径相交（射线从 y=0 升到 y=1，中点 ~0.5 < 0.9）→ 遮挡
	var e := _spawn_enemy(Vector3(0, 0, -4))
	await wait_physics_frames(2)
	_wall(Vector3(0, 0.45, -2), Vector3(4, 0.9, 0.6))
	await wait_physics_frames(1)  # 墙形状入空间需一物理帧
	_explode_at(Vector3.ZERO)
	assert_almost_eq(e.health, 100.0 - _dist_damage(4.0) * (5.0 / 6.0), 1.0,
			"0.9m 矮墙：离散采样 T=0.5（2 个采样点 ×0.25）→ 伤害 × 5/6（容差 1.0 含 ±δ）")


func test_elevated_blast_clears_low_cover() -> void:
	# 爆心抬高 1.2m（摊阁级）→ 射线在墙处高度 ≈1.1 > 0.9 → 过顶不遮挡
	var e := _spawn_enemy(Vector3(0, 0, -4))
	await wait_physics_frames(2)
	_wall(Vector3(0, 0.45, -2), Vector3(4, 0.9, 0.6))
	await wait_physics_frames(1)  # 墙形状入空间需一物理帧
	_explode_at(Vector3(0, 1.2, 0))
	assert_almost_eq(e.health, 100.0 - _dist_damage(sqrt(4.0 * 4.0 + 1.2 * 1.2)), 0.001,
			"爆心抬高 → 射线过顶矮墙")


func test_grenade_continuous_cd_enabled() -> void:
	var g := Grenade.new()
	add_child_autofree(g)
	await wait_physics_frames(1)
	assert_true(g.continuous_cd, "CCD 开启（修复高速隧穿穿地）")
