# test/unit/test_map_layout_v3.gd
# M2 TDM map v3 "回声祭坛" layout skeleton assertions (TDD, task 1).
# 设计文档: docs/superpowers/specs/2026-08-11-m2-echo-altar-v3-design.md
extends GutTest

const V3 := preload("res://Levels/M2_TDM/map_layout_v3.gd")


# 拷贝自 v2 测试 test_map_layout.gd 的 _aabb() 辅助函数
func _aabb(e: Dictionary) -> Array:
	var c: Vector3 = e["center"]
	var s: Vector3 = e["size"]
	var mn := Vector3(c.x - s.x * 0.5, c.y - s.y * 0.5, c.z - s.z * 0.5)
	var mx := Vector3(c.x + s.x * 0.5, c.y + s.y * 0.5, c.z + s.z * 0.5)
	return [mn, mx]


# 垂直相接豁免：a 顶 == b 底（±0.01）或反之
func _v_touch(a: Array, b: Array) -> bool:
	return absf(a[1].y - b[0].y) <= 0.01 or absf(b[1].y - a[0].y) <= 0.01


# AABB 体积重叠判定（每轴交集 > eps；剔除浮点噪声与面/边接触）
func _overlap(a: Array, b: Array) -> bool:
	var eps := 0.0005
	return (a[0].x + eps < b[1].x) and (b[0].x + eps < a[1].x) \
		and (a[0].y + eps < b[1].y) and (b[0].y + eps < a[1].y) \
		and (a[0].z + eps < b[1].z) and (b[0].z + eps < a[1].z)


# 按 name 在表中查实体；未找到返回 {}
func _find(table: Array, ename: String) -> Dictionary:
	for e0 in table:
		var e: Dictionary = e0
		if e["name"] == ename:
			return e
	return {}


# 收集 PLAZA 中 name 以 prefix 开头的实体的 x 跨度
func _x_spans(prefix: String) -> Array:
	var spans := []
	for e0 in V3.PLAZA:
		var e: Dictionary = e0
		if (e["name"] as String).begins_with(prefix):
			var bb := _aabb(e)
			spans.append([bb[0].x, bb[1].x])
	return spans


# 收集 PLAZA 中 name 以 prefix 开头的实体的 z 跨度
func _z_spans(prefix: String) -> Array:
	var spans := []
	for e0 in V3.PLAZA:
		var e: Dictionary = e0
		if (e["name"] as String).begins_with(prefix):
			var bb := _aabb(e)
			spans.append([bb[0].z, bb[1].z])
	return spans


# 区间排序合并为不相交并集
func _merge_spans(spans: Array) -> Array:
	var sorted_spans := spans.duplicate()
	sorted_spans.sort_custom(func(a, b): return a[0] < b[0])
	var merged := []
	for s0 in sorted_spans:
		var s: Array = s0
		if merged.is_empty() or s[0] > merged.back()[1] + 0.001:
			merged.append([s[0], s[1]])
		else:
			merged.back()[1] = maxf(merged.back()[1], s[1])
	return merged


# 并集是否完整覆盖 [lo,hi]
func _span_covers(merged: Array, lo: float, hi: float) -> bool:
	for s0 in merged:
		var s: Array = s0
		if s[0] <= lo + 0.001 and s[1] >= hi - 0.001:
			return true
	return false


# 并集是否与 (lo,hi) 有实质相交
func _span_intersects(merged: Array, lo: float, hi: float) -> bool:
	for s0 in merged:
		var s: Array = s0
		if s[0] < hi - 0.001 and s[1] > lo + 0.001:
			return true
	return false


# 点 (x,z) 是否落在任一 AABB 的水平投影内
func _xz_covered(boxes: Array, x: float, z: float) -> bool:
	for bb0 in boxes:
		var bb: Array = bb0
		if bb[0].x <= x and x <= bb[1].x and bb[0].z <= z and z <= bb[1].z:
			return true
	return false


# 水平净距：两轴投影间隙 dx/dz（正=分离，负=重叠量）。
# 两轴投影均相交（足迹重叠）→ 返回负值；否则取分离轴间隙的欧氏距离（相交轴按 0 计）。
func _xz_net_dist(ba: Array, bb: Array) -> float:
	var dx := maxf(ba[0].x - bb[1].x, bb[0].x - ba[1].x)
	var dz := maxf(ba[0].z - bb[1].z, bb[0].z - ba[1].z)
	if dx < 0.0 and dz < 0.0:
		return maxf(dx, dz)
	return sqrt(maxf(dx, 0.0) * maxf(dx, 0.0) + maxf(dz, 0.0) * maxf(dz, 0.0))


# boost 组合禁令门禁（项目级硬规则，设计 §8.1）：对任意两实体 a(低顶)/b(高顶)，
# 若 0 < top_b−top_a ≤ 1.39 且 b 非叠坐于 a（b 盒底 < a 盒顶 − 0.01），
# 则 a/b 水平净距必须 ≥ 1.5m。返回违规描述列表（空 = 通过）。
# 叠坐豁免（brief 测试 #4 要求必须覆盖的两类）：
#   ① b 坐 a：b 盒底 ≥ a 盒顶 − 0.01（栏板/组合柱坐回廊板、伞顶坐柱、
#     坡道级坐台面、微台阶坐地面、斜板坐台面）
#   ② 同坐落面：|a 盒底 − b 盒底| ≤ 0.01（同级楼梯模式：生成器规定每级盒底=y_from，
#     相邻级/微台阶对/微台阶与祭坛台均为同坐落面而非叠坐——单靠公式①无法覆盖，
#     详见任务报告 concerns）
func _boost_gate_ok() -> Array:
	var violations := []
	var solids := V3.all_solids()
	for i in range(solids.size()):
		for j in range(i + 1, solids.size()):
			var ea: Dictionary = solids[i]
			var eb: Dictionary = solids[j]
			var ba := _aabb(ea)
			var bb := _aabb(eb)
			if bb[1].y < ba[1].y:  # 定向：a = 低顶
				var ta := ba; ba = bb; bb = ta
				var te := ea; ea = eb; eb = te
			var dtop: float = bb[1].y - ba[1].y
			if dtop <= 0.0 or dtop > 1.39:
				continue
			if bb[0].y >= ba[1].y - 0.01:  # 豁免①：b 叠坐于 a
				continue
			if absf(bb[0].y - ba[0].y) <= 0.01:  # 豁免②：同坐落面
				continue
			var nd := _xz_net_dist(ba, bb)
			if nd < 1.5:
				violations.append("%s(top %.3f,底 %.3f) vs %s(top %.3f,底 %.3f): 水平净距 %.3f < 1.5" % [
					ea["name"], ba[1].y, ba[0].y, eb["name"], bb[1].y, bb[0].y, nd])
	return violations


# ---- 1. 常量表（10 个精确值逐一断言）----
func test_v3_constants() -> void:
	assert_almost_eq(V3.PLAYER_W, 1.0, 0.001, "PLAYER_W == 1.0")
	assert_almost_eq(V3.CORRIDOR_MIN, 3.0, 0.001, "CORRIDOR_MIN == 3.0")
	assert_almost_eq(V3.DOOR_MIN, 2.0, 0.001, "DOOR_MIN == 2.0")
	assert_almost_eq(V3.JUMPABLE_MAX, 1.3, 0.001, "JUMPABLE_MAX == 1.3")
	assert_almost_eq(V3.BOUND_X, 30.0, 0.001, "BOUND_X == 30.0")
	assert_almost_eq(V3.BOUND_Z, 29.0, 0.001, "BOUND_Z == 29.0")
	assert_almost_eq(V3.COVER_CROUCH, 0.9, 0.001, "COVER_CROUCH == 0.9 (蹲藏档)")
	assert_almost_eq(V3.COVER_FULL, 2.2, 0.001, "COVER_FULL == 2.2 (站藏档)")
	assert_almost_eq(V3.WALL_H, 3.0, 0.001, "WALL_H == 3.0 (墙体高度)")
	assert_almost_eq(V3.GRENADE_RADIUS, 8.89, 0.001, "GRENADE_RADIUS == 8.89 (手雷满伤半径)")


# ---- 2. all_solids(): 含 Ground + 4 面边界墙（总数随任务 3-7 递增，只断言下限）----
func test_all_solids_has_ground_and_walls() -> void:
	var solids := V3.all_solids()
	assert_gte(solids.size(), 5, "all_solids() 总数 ≥ 5（Ground + 4 边界墙，随任务递增）")
	var names := []
	for e in solids:
		var d: Dictionary = e
		names.append(d["name"])
	assert_true(names.has("Ground"), "含 Ground")
	assert_true(names.has("WallNorth"), "含 WallNorth")
	assert_true(names.has("WallSouth"), "含 WallSouth")
	assert_true(names.has("WallWest"), "含 WallWest")
	assert_true(names.has("WallEast"), "含 WallEast")


# ---- 3. 所有实体在地图界内（同 v2 判据：center±size/2 落在 ±(BOUND+1) 内）----
func test_solids_inside_bounds() -> void:
	for e in V3.all_solids():
		var d: Dictionary = e
		var bb := _aabb(d)
		assert_true(bb[0].x >= -V3.BOUND_X - 1.0, "%s min.x in bounds" % d["name"])
		assert_true(bb[1].x <= V3.BOUND_X + 1.0, "%s max.x in bounds" % d["name"])
		assert_true(bb[0].z >= -V3.BOUND_Z - 1.0, "%s min.z in bounds" % d["name"])
		assert_true(bb[1].z <= V3.BOUND_Z + 1.0, "%s max.z in bounds" % d["name"])


# ---- 4. standable_surfaces(): 当前为空；schema 四键循环为任务 8 预埋 ----
func test_standable_surfaces_schema() -> void:
	var surfaces := V3.standable_surfaces()
	assert_eq(surfaces.size(), 0, "standable_surfaces() 当前为空（任务 8 填充）")
	for s0 in surfaces:
		var s: Dictionary = s0
		assert_true(s.has("name"), "standable 项含 name 键")
		assert_true(s.has("center"), "standable 项含 center 键")
		assert_true(s.has("size"), "standable 项含 size 键")
		assert_true(s.has("top_y"), "standable 项含 top_y 键")
		if s.has("name") and s.has("center") and s.has("top_y"):
			assert_almost_eq((s["center"] as Vector3).y, s["top_y"], 0.001,
				"%s center.y == top_y" % s["name"])


# ---- 5. 祭坛台：尺寸 (14,0.6,10)、center (0,0.3,0)、顶面 0.6 ----
func test_altar_platform() -> void:
	var ent := _find(V3.PLAZA, "AltarPlatform")
	assert_false(ent.is_empty(), "PLAZA 含 AltarPlatform")
	if ent.is_empty():
		return
	var c: Vector3 = ent["center"]
	var s: Vector3 = ent["size"]
	assert_almost_eq(s.x, 14.0, 0.001, "AltarPlatform size.x == 14")
	assert_almost_eq(s.y, 0.6, 0.001, "AltarPlatform size.y == 0.6")
	assert_almost_eq(s.z, 10.0, 0.001, "AltarPlatform size.z == 10")
	assert_almost_eq(c.x, 0.0, 0.001, "AltarPlatform center.x == 0")
	assert_almost_eq(c.y, 0.3, 0.001, "AltarPlatform center.y == 0.3")
	assert_almost_eq(c.z, 0.0, 0.001, "AltarPlatform center.z == 0")
	var bb := _aabb(ent)
	assert_almost_eq(bb[1].y, 0.6, 0.001, "AltarPlatform 顶面 == 0.6")


# ---- 6. rim 北边 3 豁：中豁错轴 x∈[2,4.5]、侧豁 x∈[-9,-6.5]∪[6.5,9] ----
func test_rim_north_gaps() -> void:
	var merged := _merge_spans(_x_spans("RimN"))
	assert_false(merged.is_empty(), "PLAZA 含 RimN* 段")
	for gap in [[2.0, 4.5], [-9.0, -6.5], [6.5, 9.0]]:
		var g: Array = gap
		assert_false(_span_intersects(merged, g[0], g[1]),
			"rim N 豁口 x∈[%s,%s] 完全无覆盖" % [g[0], g[1]])
	for seg in [[-13.5, -9.0], [-6.5, 2.0], [4.5, 6.5], [9.0, 13.5]]:
		var s: Array = seg
		assert_true(_span_covers(merged, s[0], s[1]),
			"rim N 段 x∈[%s,%s] 有实体覆盖" % [s[0], s[1]])


# ---- 7. rim 南边 = 180° 旋转：中豁 x∈[-4.5,-2]、侧豁相同 ----
func test_rim_south_gaps() -> void:
	var merged := _merge_spans(_x_spans("RimS"))
	assert_false(merged.is_empty(), "PLAZA 含 RimS* 段")
	for gap in [[-4.5, -2.0], [-9.0, -6.5], [6.5, 9.0]]:
		var g: Array = gap
		assert_false(_span_intersects(merged, g[0], g[1]),
			"rim S 豁口 x∈[%s,%s] 完全无覆盖" % [g[0], g[1]])
	for seg in [[-13.5, -9.0], [-6.5, -4.5], [-2.0, 6.5], [9.0, 13.5]]:
		var s: Array = seg
		assert_true(_span_covers(merged, s[0], s[1]),
			"rim S 段 x∈[%s,%s] 有实体覆盖" % [s[0], s[1]])


# ---- 8. rim E/W 街口 z∈[-2,2] 无墙 ----
func test_rim_street_mouths() -> void:
	for side in ["RimE", "RimW"]:
		var merged := _merge_spans(_z_spans(side))
		assert_false(merged.is_empty(), "PLAZA 含 %s* 段" % side)
		assert_false(_span_intersects(merged, -2.0, 2.0),
			"%s 街口 z∈[-2,2] 无覆盖" % side)


# ---- 9. 回廊板：行走面 3.0 / 底面 2.7 / size (7,0.3,7) ----
func test_corridor_slab() -> void:
	var ent := _find(V3.CLOCK, "CorridorSlab")
	assert_false(ent.is_empty(), "CLOCK 含 CorridorSlab")
	if ent.is_empty():
		return
	var c: Vector3 = ent["center"]
	var s: Vector3 = ent["size"]
	assert_almost_eq(s.x, 7.0, 0.001, "CorridorSlab size.x == 7")
	assert_almost_eq(s.y, 0.3, 0.001, "CorridorSlab size.y == 0.3")
	assert_almost_eq(s.z, 7.0, 0.001, "CorridorSlab size.z == 7")
	assert_almost_eq(c.y + s.y * 0.5, 3.0, 0.001, "CorridorSlab 顶面 == 3.0（行走面）")
	assert_almost_eq(c.y - s.y * 0.5, 2.7, 0.001, "CorridorSlab 底面 == 2.7")


# ---- 10. 伞顶：四板底面 7.1；中央 3×3 雷口开敞、四角 (±3,±3) 有覆盖 ----
func test_umbrella_bottom() -> void:
	var boxes := []
	for n in ["UmbrellaN", "UmbrellaS", "UmbrellaW", "UmbrellaE"]:
		var ent := _find(V3.CLOCK, n)
		assert_false(ent.is_empty(), "CLOCK 含 %s" % n)
		if ent.is_empty():
			continue
		var bb := _aabb(ent)
		boxes.append(bb)
		assert_almost_eq(bb[0].y, 7.1, 0.001, "%s 底面 == 7.1" % n)
	assert_false(_xz_covered(boxes, 0.0, 0.0), "点 (0,?,0) 正上方无伞板（雷口）")
	for px in [-3.0, 3.0]:
		for pz in [-3.0, 3.0]:
			assert_true(_xz_covered(boxes, px, pz),
				"点 (%s,?,%s) 正上方有伞板" % [px, pz])


# ---- 11. 四斜板：底面 0.6、投影在祭坛台内、与 Pedestal 无 AABB 重叠 ----
func test_slabs_on_altar() -> void:
	var platform := _find(V3.PLAZA, "AltarPlatform")
	var pedestal := _find(V3.CLOCK, "Pedestal")
	assert_false(platform.is_empty(), "PLAZA 含 AltarPlatform")
	assert_false(pedestal.is_empty(), "CLOCK 含 Pedestal")
	if platform.is_empty() or pedestal.is_empty():
		return
	var plat_bb := _aabb(platform)
	var ped_bb := _aabb(pedestal)
	for n in ["AltarSlabA", "AltarSlabB", "AltarSlabA2", "AltarSlabB2"]:
		var ent := _find(V3.PLAZA, n)
		assert_false(ent.is_empty(), "PLAZA 含 %s" % n)
		if ent.is_empty():
			continue
		var bb := _aabb(ent)
		assert_almost_eq(bb[0].y, 0.6, 0.001, "%s 底面 == 0.6（坐台面）" % n)
		assert_almost_eq(bb[1].y, 2.7, 0.001, "%s 顶面 == 2.7（齐回廊板底，垂直相接豁免）" % n)
		var inside: bool = bb[0].x >= plat_bb[0].x and bb[1].x <= plat_bb[1].x \
			and bb[0].z >= plat_bb[0].z and bb[1].z <= plat_bb[1].z
		assert_true(inside, "%s 投影在祭坛台投影内" % n)
		assert_false(_overlap(bb, ped_bb), "%s 与 Pedestal AABB 不重叠" % n)


# ---- 12. PLAZA+CLOCK 两两 AABB 无重叠（唯一豁免 = 垂直相接）----
func test_center_block_no_overlap() -> void:
	var ents := []
	ents.append_array(V3.PLAZA)
	ents.append_array(V3.CLOCK)
	assert_eq(ents.size(), 34, "PLAZA+CLOCK 实体总数 == 34（17+17）")
	for i in range(ents.size()):
		for j in range(i + 1, ents.size()):
			var a: Dictionary = ents[i]
			var b: Dictionary = ents[j]
			var ba := _aabb(a)
			var bb := _aabb(b)
			assert_true((not _overlap(ba, bb)) or _v_touch(ba, bb),
				"%s vs %s: AABB 重叠（非垂直相接豁免）" % [a["name"], b["name"]])


# ---- 13. 坡道生成器产出：恰 8 级 / 宽 3.0 / 顶面等差 0.3 / 盒底坐台面 / 级间 z 不重叠 ----
func test_ramp_steps() -> void:
	for prefix in ["RampE", "RampW"]:
		for n in range(1, 9):
			var ent := _find(V3.RAMPS, "%sStep%d" % [prefix, n])
			assert_false(ent.is_empty(), "RAMPS 含 %sStep%d" % [prefix, n])
			if ent.is_empty():
				continue
			var bb := _aabb(ent)
			var s: Vector3 = ent["size"]
			assert_almost_eq(s.x, 3.0, 0.001, "%sStep%d 级宽 == 3.0" % [prefix, n])
			var expect_top: float = 0.6 + 0.3 * n
			assert_almost_eq(bb[1].y, expect_top, 0.001,
				"%sStep%d 顶面 == %s" % [prefix, n, expect_top])
			assert_almost_eq(bb[0].y, 0.6, 0.001, "%sStep%d 盒底 == 0.6（坐台面）" % [prefix, n])
		# 级间 z 段无交叠且边界相接 ±0.001
		for n in range(1, 8):
			var ea := _find(V3.RAMPS, "%sStep%d" % [prefix, n])
			var eb := _find(V3.RAMPS, "%sStep%d" % [prefix, n + 1])
			if ea.is_empty() or eb.is_empty():
				continue
			var ba := _aabb(ea)
			var bb2 := _aabb(eb)
			var gap := maxf(ba[0].z, bb2[0].z) - minf(ba[1].z, bb2[1].z)
			assert_almost_eq(gap, 0.0, 0.001,
				"%sStep%d/%d 级间 z 段相接不重叠（gap=%s）" % [prefix, n, n + 1, gap])


# ---- 14. 坡道落点：末级顶 = 回廊行走面 3.0，z 范围与对应栏板豁口相交 ----
func test_ramp_e_landing() -> void:
	var e8 := _find(V3.RAMPS, "RampEStep8")
	assert_false(e8.is_empty(), "RAMPS 含 RampEStep8")
	if not e8.is_empty():
		var bb := _aabb(e8)
		assert_almost_eq(bb[1].y, 3.0, 0.001, "RampEStep8 顶面 == 3.0（齐回廊行走面）")
		assert_true(_span_intersects([[bb[0].z, bb[1].z]], 1.5, 3.5),
			"RampEStep8 z 范围与回廊 E 豁 z∈[1.5,3.5] 相交")
	var w8 := _find(V3.RAMPS, "RampWStep8")
	assert_false(w8.is_empty(), "RAMPS 含 RampWStep8")
	if not w8.is_empty():
		var bb := _aabb(w8)
		assert_almost_eq(bb[1].y, 3.0, 0.001, "RampWStep8 顶面 == 3.0（齐回廊行走面）")
		assert_true(_span_intersects([[bb[0].z, bb[1].z]], -3.5, -1.5),
			"RampWStep8 z 范围与回廊 W 豁 z∈[-3.5,-1.5] 相交")


# ---- 15. 坡道与基座缝 == 1.5（精确）+ 全部坡道盒与 Pedestal AABB 无重叠 ----
func test_ramp_pedestal_gap() -> void:
	var pedestal := _find(V3.CLOCK, "Pedestal")
	assert_false(pedestal.is_empty(), "CLOCK 含 Pedestal")
	if pedestal.is_empty():
		return
	var ped_bb := _aabb(pedestal)
	var e_min := INF
	var w_max := -INF
	for e0 in V3.RAMPS:
		var e: Dictionary = e0
		var nm: String = e["name"]
		var bb := _aabb(e)
		if nm.begins_with("RampE"):
			e_min = minf(e_min, bb[0].x)
			assert_false(_overlap(bb, ped_bb), "%s 与 Pedestal AABB 无重叠" % nm)
		elif nm.begins_with("RampW"):
			w_max = maxf(w_max, bb[1].x)
			assert_false(_overlap(bb, ped_bb), "%s 与 Pedestal AABB 无重叠" % nm)
	assert_almost_eq(e_min - ped_bb[1].x, 1.5, 0.001, "东坡道 x_min − 基座 x_max == 1.5")
	assert_almost_eq(ped_bb[0].x - w_max, 1.5, 0.001, "基座 x_min − 西坡道 x_max == 1.5")


# ---- 16. boost 组合禁令门禁（项目级硬规则）：遍历 all_solids() 全实体对 ----
func test_boost_gate() -> void:
	var violations := _boost_gate_ok()
	assert_true(violations.is_empty(),
		"boost 组合禁令门禁违规（%d 对）:\n%s" % [violations.size(), "\n".join(violations)])


# ---- 17. 祭坛台微台阶：N/S 各两级，顶面 0.3/0.6，级 2 贴台缘 ----
func test_micro_steps() -> void:
	var n1 := _find(V3.RAMPS, "MicroN1")
	assert_false(n1.is_empty(), "RAMPS 含 MicroN1")
	if not n1.is_empty():
		var bb := _aabb(n1)
		assert_almost_eq(bb[1].y, 0.3, 0.001, "MicroN1 顶面 == 0.3")
	var n2 := _find(V3.RAMPS, "MicroN2")
	assert_false(n2.is_empty(), "RAMPS 含 MicroN2")
	if not n2.is_empty():
		var bb := _aabb(n2)
		assert_almost_eq(bb[1].y, 0.6, 0.001, "MicroN2 顶面 == 0.6（=台面）")
		assert_almost_eq(bb[1].z, -5.0, 0.001, "MicroN2 贴台缘 z == -5.0")
	var s1 := _find(V3.RAMPS, "MicroS1")
	assert_false(s1.is_empty(), "RAMPS 含 MicroS1")
	if not s1.is_empty():
		var bb := _aabb(s1)
		assert_almost_eq(bb[1].y, 0.3, 0.001, "MicroS1 顶面 == 0.3")
	var s2 := _find(V3.RAMPS, "MicroS2")
	assert_false(s2.is_empty(), "RAMPS 含 MicroS2")
	if not s2.is_empty():
		var bb := _aabb(s2)
		assert_almost_eq(bb[1].y, 0.6, 0.001, "MicroS2 顶面 == 0.6（=台面）")
		assert_almost_eq(bb[0].z, 5.0, 0.001, "MicroS2 贴台缘 z == 5.0")
