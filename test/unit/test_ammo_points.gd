# test/unit/test_ammo_points.gd
# 弹药箱刷新点数据（2026-08-13，TDD RED 先行）：
# 需求（用户拍板）：总计 10 处固定刷新点——不在双方营地范围内、两两不能隔太近（≥5m）、
# 覆盖点名位置（中心塔二楼回廊 / 两边祭坛台）。
extends GutTest

const V3 := preload("res://Levels/M2_TDM/map_layout_v3.gd")


func test_count_and_rotation_symmetry() -> void:
	var pts: Array = V3.ammo_box_points()
	assert_eq(pts.size(), 10, "总计 10 处")
	var set := {}
	for p0 in pts:
		set[str(p0["pos"])] = true
	for p0 in pts:
		var p: Vector3 = p0["pos"]
		assert_true(set.has(str(Vector3(-p.x, p.y, -p.z))),
			"每点有 180° 旋转对（南北对称）")


func test_spacing_at_least_5m() -> void:
	var pts: Array = V3.ammo_box_points()
	for i in pts.size():
		for j in range(i + 1, pts.size()):
			var a: Vector3 = pts[i]["pos"]
			var b: Vector3 = pts[j]["pos"]
			var horiz := Vector2(a.x - b.x, a.z - b.z).length()
			assert_gte(horiz, 5.0, "点 %s-%s 水平距 %.2f ≥ 5m" % [pts[i]["name"], pts[j]["name"], horiz])


func test_outside_camps() -> void:
	for p0 in V3.ammo_box_points():
		var p: Vector3 = p0["pos"]
		var in_north: bool = absf(p.x) <= 6.0 and p.z >= 24.5 and p.z <= 28.5
		var in_south: bool = absf(p.x) <= 6.0 and p.z <= -24.5 and p.z >= -28.5
		assert_false(in_north or in_south, "点 %s 不在双方营地内" % p0["name"])


func test_named_locations_covered() -> void:
	var pts: Array = V3.ammo_box_points()
	var names := {}
	for p0 in pts:
		names[p0["name"]] = true
	assert_true(names.has("CorridorE") and names.has("CorridorW"), "中心塔二楼（钟楼回廊）有刷新点")
	assert_true(names.has("AltarE") and names.has("AltarW"), "两边祭坛（祭坛台东/西）有刷新点")
	# 回廊面与祭坛台面高度正确
	for p0 in pts:
		var p: Vector3 = p0["pos"]
		if str(p0["name"]).begins_with("Corridor"):
			assert_almost_eq(p.y, 3.0, 0.001, "回廊点 y=3.0")
		if str(p0["name"]).begins_with("Altar"):
			assert_almost_eq(p.y, 0.6, 0.001, "祭坛台点 y=0.6")


func test_clear_of_solids() -> void:
	# 箱自身体积（0.7×0.55×0.7，底贴 py）与实体 AABB 精确相交检查（±0.05 浮点容差）——
	# 箱底恰好贴所在台面顶（AltarPlatform 顶 0.6 / CorridorSlab 顶 3.0 等）不算重叠。
	for p0 in V3.ammo_box_points():
		var p: Vector3 = p0["pos"]
		var bx0: float = p.x - 0.35
		var bx1: float = p.x + 0.35
		var by0: float = p.y
		var by1: float = p.y + 0.55
		var bz0: float = p.z - 0.35
		var bz1: float = p.z + 0.35
		for e0 in V3.all_solids():
			var e: Dictionary = e0
			var c: Vector3 = e["center"]
			var s: Vector3 = e["size"]
			if e["kind"] == "ground":
				continue
			var ex0: float = c.x - s.x * 0.5
			var ex1: float = c.x + s.x * 0.5
			var ey0: float = c.y - s.y * 0.5
			var ey1: float = c.y + s.y * 0.5
			var ez0: float = c.z - s.z * 0.5
			var ez1: float = c.z + s.z * 0.5
			var hit: bool = bx1 > ex0 + 0.05 and bx0 < ex1 - 0.05 \
					and by1 > ey0 + 0.05 and by0 < ey1 - 0.05 \
					and bz1 > ez0 + 0.05 and bz0 < ez1 - 0.05
			assert_false(hit, "点 %s 箱体积与实体 %s 相交" % [p0["name"], e["name"]])
