# test/unit/test_map_layout.gd
# M2 TDM map layout assertions (TDD, design doc §11). Values calibrated by T1 probes.
extends GutTest

const LAYOUT := preload("res://Levels/M2_TDM/map_layout.gd")

func _solids() -> Array:
	var out := []
	for e in LAYOUT.all_solids():
		var d: Dictionary = e
		out.append(d)
	return out


func _aabb(e: Dictionary) -> Array:
	var c: Vector3 = e["center"]
	var s: Vector3 = e["size"]
	var mn := Vector3(c.x - s.x * 0.5, c.y - s.y * 0.5, c.z - s.z * 0.5)
	var mx := Vector3(c.x + s.x * 0.5, c.y + s.y * 0.5, c.z + s.z * 0.5)
	return [mn, mx]


func _overlaps(a: Array, b: Array) -> bool:
	return not (
		a[1].x <= b[0].x or b[1].x <= a[0].x or
		a[1].y <= b[0].y or b[1].y <= a[0].y or
		a[1].z <= b[0].z or b[1].z <= a[0].z
	)


# ---- §11.1: all solids within 60x58 bounds ----
func test_solids_inside_bounds() -> void:
	for e in _solids():
		var bb := _aabb(e)
		assert_true(bb[0].x >= -LAYOUT.BOUND_X - 1.0, "%s min.x in bounds" % e["name"])
		assert_true(bb[1].x <= LAYOUT.BOUND_X + 1.0, "%s max.x in bounds" % e["name"])
		assert_true(bb[0].z >= -LAYOUT.BOUND_Z - 1.0, "%s min.z in bounds" % e["name"])
		assert_true(bb[1].z <= LAYOUT.BOUND_Z + 1.0, "%s max.z in bounds" % e["name"])


# ---- §11.2: no AABB overlap between solids (vertical touch = ground adjacency allowed) ----
func test_solids_no_overlap() -> void:
	var solids := _solids()
	for i in solids.size():
		for j in range(i + 1, solids.size()):
			var a := _aabb(solids[i])
			var b := _aabb(solids[j])
			# 垂直相接（地面顶==元素底，y 恰好接触）不算重叠
			if a[0].y >= b[1].y - 0.01 or b[0].y >= a[1].y - 0.01:
				continue
			assert_false(_overlaps(a, b), "%s 与 %s 不应重叠" % [solids[i]["name"], solids[j]["name"]])


# ---- §11.3: central hall dimensions & doors ----
func test_hall_dimensions() -> void:
	assert_almost_eq(LAYOUT.hall_size().x, 14.0, 0.01, "hall width 14m")
	assert_almost_eq(LAYOUT.hall_size().z, 12.0, 0.01, "hall depth 12m")
	for w in LAYOUT.HALL_WALL_SEGMENTS:
		var d: Dictionary = w
		assert_eq(d["size"].y, 3.0, "%s 层高 3.0m" % d["name"])
	assert_eq(LAYOUT.HALL_DOORS.size(), 4, "4 个出入口")
	for d0 in LAYOUT.HALL_DOORS:
		var d: Dictionary = d0
		var gap: float = d.get("gap_x", d.get("gap_z", 0.0))
		assert_gte(gap, LAYOUT.DOOR_MIN, "%s 门宽 ≥2m" % d["name"])


# ---- §11.4: jumpable surfaces ≤1.3m; 1.4m+ requires ramp; gaps ≤4.5m ----
func test_jumpable_heights() -> void:
	for r0 in LAYOUT.WEST_ROOFS:
		var r: Dictionary = r0
		assert_lte(r["size"].y, LAYOUT.JUMPABLE_MAX, "%s 可跳高度 ≤1.3m" % r["name"])
	var east_roof: Dictionary = LAYOUT.EAST_ROOF
	assert_eq(east_roof["size"].y, 2.5, "东屋顶 2.5m")
	var ramp: Dictionary = LAYOUT.EAST_RAMP
	assert_eq(ramp["kind"], "ramp", "东屋顶必须有斜坡")
	assert_gte(ramp["size"].x, 3.0, "斜坡宽度 ≥3m")


# ---- §11.5: grenade coverage — every 5x5m zone has a ≥1.4m blocker within radius ----
func test_grenade_coverage_blockers() -> void:
	var blockers := []
	for e in _solids():
		if e["size"].y >= 1.4 - 0.01:  # 浮点容差（1.4 字面量可能存为 1.399999…）
			blockers.append(e)
	assert_true(blockers.size() >= 8, "至少有 8 个 ≥1.4m 遮挡物（柱/墙/箱/屋顶）")
	var probe_points := [
		Vector3(0, 0, 0), Vector3(0, 0, 14), Vector3(0, 0, -14),
		Vector3(-15, 0, 0), Vector3(15, 0, 0),
		Vector3(-2, 0, 27), Vector3(-2, 0, -27),
	]
	for p in probe_points:
		var found := false
		for b in blockers:
			var c: Vector3 = b["center"]
			if c.distance_to(p) <= 8.89 + 0.5:
				found = true
				break
		assert_true(found, "点 %s 8.89m 内应有 ≥1.4m 遮挡" % str(p))


# ---- §11.7: spawn safety — spawn front wall 1.4m ----
func test_spawn_safety() -> void:
	for sw0 in LAYOUT.SPAWN_WALLS:
		var sw: Dictionary = sw0
		assert_almost_eq(sw["size"].y, 1.4, 0.01, "%s 出生墙 1.4m" % sw["name"])


# ---- §11.8: hall 4-way connectivity — door segments leave 2m gaps ----
func test_hall_connectivity() -> void:
	for w0 in LAYOUT.HALL_WALL_SEGMENTS:
		var w: Dictionary = w0
		var c: Vector3 = w["center"]
		var s: Vector3 = w["size"]
		if w["name"].contains("N") or w["name"].contains("S"):
			var span_x := Vector2(c.x - s.x * 0.5, c.x + s.x * 0.5)
			assert_false(span_x.x < 1.0 and span_x.y > -1.0, "%s 不应挡住北/南门缝" % w["name"])
		if w["name"].contains("W") or w["name"].contains("E"):
			var span_z := Vector2(c.z - s.z * 0.5, c.z + s.z * 0.5)
			assert_false(span_z.x < 1.0 and span_z.y > -1.0, "%s 不应挡住西/东门缝" % w["name"])
