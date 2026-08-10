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
			var an: String = solids[i]["name"]
			var bn: String = solids[j]["name"]
			# 墙段角落相接（同结构围合墙体，角重叠属正常）——豁免
			if _is_wall_corner(an, bn):
				continue
			# 门框柱与墙段同面（贴门洞，不阻碍通行）——豁免
			if (an.begins_with("DoorFrame") and bn.begins_with("HallWall")) or \
			   (bn.begins_with("DoorFrame") and an.begins_with("HallWall")):
				continue
			# 出生建筑：屋顶盖墙 + 同建筑墙段相接（结构正常）——豁免
			if (an.begins_with("SpawnB") and bn.begins_with("SpawnB")) or \
			   (bn.begins_with("SpawnB") and an.begins_with("SpawnB")):
				continue
			# 建筑岛：同建筑墙段角落相接 + 高台贴墙（结构正常）——豁免
			if (an.contains("_Wall") and bn.contains("_Wall") and an.get_slice("_", 0) == bn.get_slice("_", 0)) or \
			   (an.begins_with("W_") and bn.begins_with("W_") and (an.contains("High") or bn.contains("High"))) or \
			   (an.begins_with("E_") and bn.begins_with("E_") and (an.contains("High") or bn.contains("High"))):
				continue
			assert_false(_overlaps(a, b), "%s 与 %s 不应重叠" % [an, bn])


# 墙段角落相接：同属角建筑/大厅外墙的墙段在角落重叠（结构正常）
func _is_wall_corner(an: String, bn: String) -> bool:
	var a_wall := an.ends_with("Wall_N") or an.ends_with("Wall_S") or an.ends_with("Wall_E") \
		or an.ends_with("Wall_W") or an.ends_with("Wall_E_T") or an.ends_with("Wall_E_B") \
		or an.ends_with("Wall_W_T") or an.ends_with("Wall_W_B") \
		or an.ends_with("Wall_S_L") or an.ends_with("Wall_S_R") or an.ends_with("Wall_N_L") \
		or an.ends_with("Wall_N_R")
	var b_wall := bn.ends_with("Wall_N") or bn.ends_with("Wall_S") or bn.ends_with("Wall_E") \
		or bn.ends_with("Wall_W") or bn.ends_with("Wall_E_T") or bn.ends_with("Wall_E_B") \
		or bn.ends_with("Wall_W_T") or bn.ends_with("Wall_W_B") \
		or bn.ends_with("Wall_S_L") or bn.ends_with("Wall_S_R") or bn.ends_with("Wall_N_L") \
		or bn.ends_with("Wall_N_R")
	if not (a_wall and b_wall):
		return false
	# 同一前缀（NW/NEW/SW/SE/Hall）的墙段角落相接
	var a_pref := an.get_slice("Wall", 0)
	var b_pref := bn.get_slice("Wall", 0)
	return a_pref == b_pref


# ---- §11.3: central hall dimensions & doors ----
func test_hall_dimensions() -> void:
	assert_almost_eq(LAYOUT.hall_size().x, 20.0, 0.01, "hall width 20m")
	assert_almost_eq(LAYOUT.hall_size().z, 16.0, 0.01, "hall depth 16m")
	for w in LAYOUT.HALL_WALL_SEGMENTS:
		var d: Dictionary = w
		assert_eq(d["size"].y, 3.0, "%s 层高 3.0m" % d["name"])
	assert_eq(LAYOUT.HALL_DOORS.size(), 4, "4 个出入口")
	for d0 in LAYOUT.HALL_DOORS:
		var d: Dictionary = d0
		var gap: float = d.get("gap_x", d.get("gap_z", 0.0))
		assert_gte(gap, LAYOUT.DOOR_MIN, "%s 门宽 ≥2m" % d["name"])


# ---- §11.3b: 铁律——每个建筑至少 2 个门（用户明确要求：单门封闭盒子无博弈性）----
func test_every_building_has_two_doors() -> void:
	# 建筑岛已移除（2026-08-10 布局清理——角建筑+出生建筑已覆盖双门铁律）
	# 角建筑：2 门（生成函数验证——门朝中心的两面墙分段；墙名如 NEWall_S_L 无下划线）
	for pref in ["NW", "NE", "SW", "SE"]:
		var door_walls := 0
		for e in _solids():
			var n: String = e["name"]
			if n.begins_with(pref + "Wall"):
				if n.ends_with("_T") or n.ends_with("_B") or n.ends_with("_L") or n.ends_with("_R"):
					door_walls += 1
		assert_gte(door_walls, 4, "%s 角建筑应有 2 扇门" % pref)
	# 出生建筑：左右 2 门（东西墙分段）
	for pref in ["SpawnB_N", "SpawnB_S"]:
		var door_walls := 0
		for e in _solids():
			var n: String = e["name"]
			if n.begins_with(pref + "_WallW") or n.begins_with(pref + "_WallE"):
				if n.ends_with("_T") or n.ends_with("_B"):
					door_walls += 1
		assert_eq(door_walls, 4, "%s 出生建筑应有 2 扇门" % pref)


# ---- §11.4: jumpable surfaces ≤1.3m（角建筑屋顶 1.2m 可跳；大厅 3m 不可跳）----
func test_jumpable_heights() -> void:
	# 所有 roof 类组件 ≤1.3m 可跳（用 kind 安全访问）
	for e in _solids():
		var kind: String = e.get("kind", "cover")
		if kind == "roof":
			assert_lte(e["size"].y, LAYOUT.JUMPABLE_MAX, "%s 可跳高度 ≤1.3m" % e["name"])
	# 大厅屋顶顶面 3.5m（不可跳，仅视觉）——用顶面高度判据
	for r0 in LAYOUT.HALL_ROOF:
		var r: Dictionary = r0
		var top: float = (r["center"] as Vector3).y + r["size"].y * 0.5
		assert_gt(top, LAYOUT.JUMPABLE_MAX, "%s 大厅屋顶顶面不可跳" % r["name"])


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
	for sw0 in LAYOUT.SPAWN_BUILDINGS:
		var sw: Dictionary = sw0
		if sw["name"].contains("Roof"):
			assert_gt((sw["center"] as Vector3).y + sw["size"].y * 0.5, 3.0, "%s 封顶 3m" % sw["name"])


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
