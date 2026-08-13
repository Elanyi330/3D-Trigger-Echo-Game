# test/unit/test_camp_points.gd
# 营地出生点数据（2026-08-13，TDD RED 先行）：
# 需求（用户拍板）：玩家+4 友军出生北营、5 敌人出生南营；每营 10 个随机刷新点
# 互相距离隔开——角色只在无其他角色占用的点位出现，保证不挤在一起。
# 断言：每营 10 点 / 南北营 180° 旋转对称 / 任意两点间距 ≥ 1.9m /
#       全部点在营内地面范围（北营 x∈[-6,6] z∈[25,28]，南营为负）。
extends GutTest

const V3 := preload("res://Levels/M2_TDM/map_layout_v3.gd")


func test_camp_point_counts_and_symmetry() -> void:
	var north: Array = V3.camp_spawn_points(1)
	var south: Array = V3.camp_spawn_points(-1)
	assert_eq(north.size(), 10, "北营 10 点")
	assert_eq(south.size(), 10, "南营 10 点")
	# 180° 旋转对称：北营每点的 (-x,-z) 旋转像必在南营集合中（生成序 x 反转，不能按同索引比）
	for p0 in north:
		var p: Vector3 = p0
		assert_true(south.has(Vector3(-p.x, p.y, -p.z)),
			"北营点 %s 的 180° 旋转像应在南营集合中" % p)


func test_camp_points_spacing() -> void:
	for side in [1, -1]:
		var pts: Array = V3.camp_spawn_points(side)
		for i in pts.size():
			for j in range(i + 1, pts.size()):
				var a: Vector3 = pts[i]
				var b: Vector3 = pts[j]
				assert_gte((a - b).length(), 1.9,
					"点 %d-%d 间距 ≥ 1.9m（角色胶囊直径 0.62m 两倍余量）" % [i, j])


func test_camp_points_inside_camp() -> void:
	for side in [1, -1]:
		for p0 in V3.camp_spawn_points(side):
			var p: Vector3 = p0
			assert_between(p.x, -6.0, 6.0, "x 在营墙内")
			assert_between(p.z * side, 25.0, 28.0, "z 在营墙内（南营取负后同区间）")
			assert_eq(p.y, 0.0, "y=0 地面")


func test_camp_points_clear_of_solids() -> void:
	# 点位不得与任何实体 AABB 重叠（影壁/货车在营外已核，此处防御性断言）
	for side in [1, -1]:
		for p0 in V3.camp_spawn_points(side):
			var p: Vector3 = p0
			for e0 in V3.all_solids():
				var e: Dictionary = e0
				var c: Vector3 = e["center"]
				var s: Vector3 = e["size"]
				var inside: bool = absf(p.x - c.x) < s.x * 0.5 + 0.3 \
						and absf(p.y - c.y) < s.y * 0.5 + 0.3 \
						and absf(p.z - c.z) < s.z * 0.5 + 0.3
				if inside:
					assert_eq(e["kind"], "ground", "点位只允许与地面重叠，撞 %s" % e["name"])
