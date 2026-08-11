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


# ---- 4. standable_surfaces() 数量与 schema（任务 8 C.2）：14 面 / 四键齐全 /
#         name 全图唯一 / center.y == top_y ----
func test_standable_surfaces_count_schema() -> void:
	var surfaces := V3.standable_surfaces()
	assert_eq(surfaces.size(), 14, "standable_surfaces() 共 14 个刷怪面")
	var seen := {}
	for s0 in surfaces:
		var s: Dictionary = s0
		assert_true(s.has("name"), "standable 项含 name 键")
		assert_true(s.has("center"), "standable 项含 center 键")
		assert_true(s.has("size"), "standable 项含 size 键")
		assert_true(s.has("top_y"), "standable 项含 top_y 键")
		if s.has("name"):
			var nm: String = s["name"]
			assert_false(seen.has(nm), "standable 面 name %s 全图唯一" % nm)
			seen[nm] = true
		if s.has("center") and s.has("top_y"):
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


# ---- 15. 坡道与基座缝 == 1.6（精确；任务 9 A2 外移 0.1 后）+ 全部坡道盒与 Pedestal AABB 无重叠 ----
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
	assert_almost_eq(e_min - ped_bb[1].x, 1.6, 0.001, "东坡道 x_min − 基座 x_max == 1.6")
	assert_almost_eq(ped_bb[0].x - w_max, 1.6, 0.001, "基座 x_min − 西坡道 x_max == 1.6")


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


# ==== 任务 4：东/西市街 ====

# 收集 table 中 name 以 prefix 开头的实体的 x 跨度
func _x_spans_in(table: Array, prefix: String) -> Array:
	var spans := []
	for e0 in table:
		var e: Dictionary = e0
		if (e["name"] as String).begins_with(prefix):
			var bb := _aabb(e)
			spans.append([bb[0].x, bb[1].x])
	return spans


# 收集 table 中 name 以 prefix 开头的实体的 z 跨度
func _z_spans_in(table: Array, prefix: String) -> Array:
	var spans := []
	for e0 in table:
		var e: Dictionary = e0
		if (e["name"] as String).begins_with(prefix):
			var bb := _aabb(e)
			spans.append([bb[0].z, bb[1].z])
	return spans


# 180° 旋转命名映射：前缀 East↔West（任务 4）、CampN_↔CampS_、BackN_↔BackS_（任务 6）、
# CornerNW_↔CornerSE_、CornerNE_↔CornerSW_（任务 7），其余部分方向字符 N↔S / E↔W 互换
# （W/E 按旋转后物理位置命名）。OuterRing 树用全名显式映射（任务 7 裁决轮：
# "TreeNW/NE" 尾字符受 prev_upper 保护不轮换，字符轮换会产生错误映射）。
# 仅轮换"后缀方向字符"（后随字符非小写，且前驱字符非大写——前驱大写说明该字符
# 属于全大写缩写词，如 "LOS" 的词尾 S），避免误伤 "Step" 等词首 S。
func _rot_pair(nm: String) -> String:
	# OuterRing 树全名映射（对称双向）——裁决 A.4
	if nm == "OuterRing_TreeNW":
		return "OuterRing_TreeSE"
	if nm == "OuterRing_TreeSE":
		return "OuterRing_TreeNW"
	if nm == "OuterRing_TreeNE":
		return "OuterRing_TreeSW"
	if nm == "OuterRing_TreeSW":
		return "OuterRing_TreeNE"
	var prefix := ""
	var rest := nm
	if nm.begins_with("East"):
		prefix = "West"
		rest = nm.trim_prefix("East")
	elif nm.begins_with("West"):
		prefix = "East"
		rest = nm.trim_prefix("West")
	elif nm.begins_with("CampN_"):
		prefix = "CampS_"
		rest = nm.trim_prefix("CampN_")
	elif nm.begins_with("CampS_"):
		prefix = "CampN_"
		rest = nm.trim_prefix("CampS_")
	elif nm.begins_with("BackN_"):
		prefix = "BackS_"
		rest = nm.trim_prefix("BackN_")
	elif nm.begins_with("BackS_"):
		prefix = "BackN_"
		rest = nm.trim_prefix("BackS_")
	elif nm.begins_with("CornerNW_"):
		prefix = "CornerSE_"
		rest = nm.trim_prefix("CornerNW_")
	elif nm.begins_with("CornerSE_"):
		prefix = "CornerNW_"
		rest = nm.trim_prefix("CornerSE_")
	elif nm.begins_with("CornerNE_"):
		prefix = "CornerSW_"
		rest = nm.trim_prefix("CornerNE_")
	elif nm.begins_with("CornerSW_"):
		prefix = "CornerNE_"
		rest = nm.trim_prefix("CornerSW_")
	var out := ""
	for i in rest.length():
		var ch := rest[i]
		var word_head: bool = i + 1 < rest.length() and rest[i + 1] >= "a" and rest[i + 1] <= "z"
		var prev_upper: bool = i > 0 and rest[i - 1] >= "A" and rest[i - 1] <= "Z"
		if not word_head and not prev_upper:
			match ch:
				"N": ch = "S"
				"S": ch = "N"
				"E": ch = "W"
				"W": ch = "E"
		out += ch
	return prefix + out


# ---- 18. 长墙：东/西各 3 段尺寸位置 + 豁口 z∈[5.5,8]∪[-8,-5.5] 无覆盖 ----
func test_street_longwalls() -> void:
	var specs := [
		["EastWall_S", Vector3(23, 1.5, -11), Vector3(1, 3, 6)],
		["EastWall_M", Vector3(23, 1.5, 0), Vector3(1, 3, 11)],
		["EastWall_N", Vector3(23, 1.5, 11), Vector3(1, 3, 6)],
		["WestWall_S", Vector3(-23, 1.5, -11), Vector3(1, 3, 6)],
		["WestWall_M", Vector3(-23, 1.5, 0), Vector3(1, 3, 11)],
		["WestWall_N", Vector3(-23, 1.5, 11), Vector3(1, 3, 6)],
	]
	for spec0 in specs:
		var spec: Array = spec0
		var nm: String = spec[0]
		var ent := _find(V3.STREETS, nm)
		assert_false(ent.is_empty(), "STREETS 含 %s" % nm)
		if ent.is_empty():
			continue
		assert_eq(ent["kind"], "wall", "%s kind == wall" % nm)
		var c: Vector3 = ent["center"]
		var s: Vector3 = ent["size"]
		var ec: Vector3 = spec[1]
		var es: Vector3 = spec[2]
		assert_almost_eq(c.x, ec.x, 0.001, "%s center.x == %s" % [nm, ec.x])
		assert_almost_eq(c.y, ec.y, 0.001, "%s center.y == %s" % [nm, ec.y])
		assert_almost_eq(c.z, ec.z, 0.001, "%s center.z == %s" % [nm, ec.z])
		assert_almost_eq(s.x, es.x, 0.001, "%s size.x == %s" % [nm, es.x])
		assert_almost_eq(s.y, es.y, 0.001, "%s size.y == %s" % [nm, es.y])
		assert_almost_eq(s.z, es.z, 0.001, "%s size.z == %s" % [nm, es.z])
	for side in ["EastWall", "WestWall"]:
		var merged := _merge_spans(_z_spans_in(V3.STREETS, side))
		assert_false(merged.is_empty(), "STREETS 含 %s* 段" % side)
		for gap in [[5.5, 8.0], [-8.0, -5.5]]:
			var g: Array = gap
			assert_false(_span_intersects(merged, g[0], g[1]),
				"%s 豁口 z∈[%s,%s] 无长墙覆盖" % [side, g[0], g[1]])
		for seg in [[-14.0, -8.0], [-5.5, 5.5], [8.0, 14.0]]:
			var s: Array = seg
			assert_true(_span_covers(merged, s[0], s[1]),
				"%s 段 z∈[%s,%s] 有长墙覆盖" % [side, s[0], s[1]])


# ---- 19. 水塔：台体顶 2.5 / size (4,2.5,4)；西塔栏板北豁 x∈[-19.5,-17.5]；台上箱底 = 2.5 ----
func test_towers() -> void:
	for spec0 in [["WestTower", "wall"], ["EastTower", "wall"]]:
		var spec: Array = spec0
		var nm: String = spec[0]
		var ent := _find(V3.STREETS, nm)
		assert_false(ent.is_empty(), "STREETS 含 %s" % nm)
		if ent.is_empty():
			continue
		assert_eq(ent["kind"], spec[1], "%s kind == %s（台体）" % [nm, spec[1]])
		var s: Vector3 = ent["size"]
		assert_almost_eq(s.x, 4.0, 0.001, "%s size.x == 4" % nm)
		assert_almost_eq(s.y, 2.5, 0.001, "%s size.y == 2.5" % nm)
		assert_almost_eq(s.z, 4.0, 0.001, "%s size.z == 4" % nm)
		var bb := _aabb(ent)
		assert_almost_eq(bb[1].y, 2.5, 0.001, "%s 台顶 == 2.5" % nm)
	# 西塔栏板北向豁口 = RailN_1/RailN_2 段间缝 x∈[-19.5,-17.5]（2m，朝坡道落点）
	var railn := _merge_spans(_x_spans_in(V3.STREETS, "WestTowerRailN"))
	assert_false(railn.is_empty(), "STREETS 含 WestTowerRailN* 栏板")
	assert_false(_span_intersects(railn, -19.5, -17.5),
		"西塔栏板北豁 x∈[-19.5,-17.5] 无覆盖")
	assert_true(_span_covers(railn, -20.5, -19.5),
		"西塔栏板北段 x∈[-20.5,-19.5] 有覆盖")
	assert_true(_span_covers(railn, -17.5, -16.5),
		"西塔栏板北段 x∈[-17.5,-16.5] 有覆盖")
	# 台上箱垂直坐台顶：盒底 == 2.5
	for bn in ["WestTowerBox", "EastTowerBox"]:
		var ent := _find(V3.STREETS, bn)
		assert_false(ent.is_empty(), "STREETS 含 %s" % bn)
		if ent.is_empty():
			continue
		var bb := _aabb(ent)
		assert_almost_eq(bb[0].y, 2.5, 0.001, "%s 箱底 == 2.5（坐台顶）" % bn)


# ---- 20. 塔坡道：各 10 级 / 顶面 0.25..2.5 等差 / 宽 2.5 / 末级贴台缘 / 坡度 ≤22.6° ----
func test_tower_ramps() -> void:
	for prefix in ["WestTowerRamp", "EastTowerRamp"]:
		var z_lo := INF
		var z_hi := -INF
		for n in range(1, 11):
			var ent := _find(V3.STREETS, "%sStep%d" % [prefix, n])
			assert_false(ent.is_empty(), "STREETS 含 %sStep%d" % [prefix, n])
			if ent.is_empty():
				continue
			var s: Vector3 = ent["size"]
			var bb := _aabb(ent)
			assert_almost_eq(s.x, 2.5, 0.001, "%sStep%d 级宽 == 2.5" % [prefix, n])
			assert_almost_eq(bb[1].y, 0.25 * n, 0.001,
				"%sStep%d 顶面 == %s（等差）" % [prefix, n, 0.25 * n])
			z_lo = minf(z_lo, bb[0].z)
			z_hi = maxf(z_hi, bb[1].z)
		var last := _find(V3.STREETS, "%sStep10" % prefix)
		if not last.is_empty():
			var bb := _aabb(last)
			assert_almost_eq(bb[1].y, 2.5, 0.001, "%sStep10 顶面 == 2.5" % prefix)
			if prefix == "WestTowerRamp":
				assert_true(bb[0].z <= 2.01 and bb[1].z >= 1.99,
					"WestTowerRampStep10 z 范围含 z=2.0±0.01（贴台体北缘）")
			else:
				assert_true(bb[0].z <= -1.99 and bb[1].z >= -2.01,
					"EastTowerRampStep10 z 范围含 z=-2.0±0.01（贴台体南缘）")
		var run: float = z_hi - z_lo
		assert_almost_eq(run, 6.2, 0.001, "%s 总跑 == 6.2" % prefix)
		if z_hi > z_lo:
			var angle: float = rad_to_deg(atan(2.5 / run))
			assert_lte(angle, 22.6, "%s 坡度 %.2f° ≤ 22.6°" % [prefix, angle])


# ---- 21. 摊阁：顶 1.2 ≤ JUMPABLE_MAX / 台阶顶 0.6 / 台阶贴摊阁缘缝 == 0 ----
func test_pavilions() -> void:
	for pair0 in [["EastPavilion", "EastPavilionStep"], ["WestPavilion", "WestPavilionStep"]]:
		var pair: Array = pair0
		var pav := _find(V3.STREETS, pair[0])
		var stp := _find(V3.STREETS, pair[1])
		assert_false(pav.is_empty(), "STREETS 含 %s" % pair[0])
		assert_false(stp.is_empty(), "STREETS 含 %s" % pair[1])
		if pav.is_empty() or stp.is_empty():
			continue
		var pb := _aabb(pav)
		var sb := _aabb(stp)
		assert_almost_eq(pb[1].y, 1.2, 0.001, "%s 顶 == 1.2" % pair[0])
		assert_lte(pb[1].y, V3.JUMPABLE_MAX, "%s 顶 ≤ JUMPABLE_MAX（可跳）" % pair[0])
		assert_almost_eq(sb[1].y, 0.6, 0.001, "%s 台阶顶 == 0.6" % pair[1])
		var gap: float = maxf(pb[0].z - sb[1].z, sb[0].z - pb[1].z)
		assert_almost_eq(gap, 0.0, 0.01, "%s/%s 贴缘缝 == 0" % [pair[0], pair[1]])


# ---- 22. 市街带界：STREETS 全部实体 x∈[-23.5,-14]∪[14,23.5]、z∈[-14.5,14.5] ----
func test_streets_bounds() -> void:
	assert_false(V3.STREETS.is_empty(), "STREETS 非空")
	for e0 in V3.STREETS:
		var e: Dictionary = e0
		var bb := _aabb(e)
		var in_west: bool = bb[0].x >= -23.51 and bb[1].x <= -13.99
		var in_east: bool = bb[0].x >= 13.99 and bb[1].x <= 23.51
		assert_true(in_west or in_east,
			"%s x 带 ∈[-23.5,-14]∪[14,23.5]（容差 0.01）" % e["name"])
		assert_true(bb[0].z >= -14.51 and bb[1].z <= 14.51,
			"%s z 带 ∈[-14.5,14.5]（容差 0.01）" % e["name"])


# ---- 23. 旋转对称：每个 East* 实体有 West* 对应体，center 互为 (-x,-z)、size 相同 ----
func test_streets_rotation_pairs() -> void:
	assert_false(V3.STREETS.is_empty(), "STREETS 非空")
	var east_count := 0
	for e0 in V3.STREETS:
		var e: Dictionary = e0
		var nm: String = e["name"]
		if not nm.begins_with("East"):
			continue
		east_count += 1
		var want := _rot_pair(nm)
		var w := _find(V3.STREETS, want)
		assert_false(w.is_empty(), "%s 有旋转对应体 %s" % [nm, want])
		if w.is_empty():
			continue
		var ce: Vector3 = e["center"]
		var cw: Vector3 = w["center"]
		var se: Vector3 = e["size"]
		var sw: Vector3 = w["size"]
		assert_almost_eq(cw.x, -ce.x, 0.001, "%s/%s center.x 互为 -x" % [nm, want])
		assert_almost_eq(cw.y, ce.y, 0.001, "%s/%s center.y 相同" % [nm, want])
		assert_almost_eq(cw.z, -ce.z, 0.001, "%s/%s center.z 互为 -z" % [nm, want])
		assert_lt((se - sw).length(), 0.001, "%s/%s size 相同" % [nm, want])
	assert_eq(east_count, 26, "East* 实体共 26 个（墙3+塔1+栏板5+箱1+坡道10+簇4+阁2）")


# ---- 24. boost 间距显式断言：4 块 Cluster Panel ↔ 最近箱缝 ≥1.5；Panel ↔ 最近摊阁缝 ≥1.5 ----
func test_streets_boost_spacing() -> void:
	var cboxes := []
	for e0 in V3.STREETS:
		var e: Dictionary = e0
		var nm: String = e["name"]
		if nm.contains("Cluster") and nm.contains("Box"):
			cboxes.append(_aabb(e))
	assert_eq(cboxes.size(), 4, "STREETS 含 4 个摊位簇箱")
	var panels := ["EastClusterN_Panel", "EastClusterS_Panel", "WestClusterN_Panel", "WestClusterS_Panel"]
	for pn in panels:
		var ent := _find(V3.STREETS, pn)
		assert_false(ent.is_empty(), "STREETS 含 %s" % pn)
		if ent.is_empty():
			continue
		var pb := _aabb(ent)
		var nd := INF
		for bb0 in cboxes:
			nd = minf(nd, _xz_net_dist(pb, bb0))
		assert_true(nd >= 1.5 - 0.01, "%s ↔ 最近箱缝 %.3f ≥ 1.5（容差 0.01）" % [pn, nd])
	# Panel ↔ 最近摊阁缝 ≥ 1.5
	var pavs := []
	for pv in ["EastPavilion", "WestPavilion"]:
		var pe := _find(V3.STREETS, pv)
		assert_false(pe.is_empty(), "STREETS 含 %s" % pv)
		if not pe.is_empty():
			pavs.append(_aabb(pe))
	for pn in panels:
		var ent := _find(V3.STREETS, pn)
		if ent.is_empty():
			continue
		var pb := _aabb(ent)
		var nd := INF
		for pav0 in pavs:
			nd = minf(nd, _xz_net_dist(pb, pav0))
		assert_true(nd >= 1.5 - 0.01, "%s ↔ 最近摊阁缝 %.3f ≥ 1.5（容差 0.01）" % [pn, nd])


# ---- 25. STREETS 内部两两 AABB 无重叠（豁免垂直相接 ±0.01）----
func test_streets_no_overlap() -> void:
	assert_false(V3.STREETS.is_empty(), "STREETS 非空")
	for i in range(V3.STREETS.size()):
		for j in range(i + 1, V3.STREETS.size()):
			var a: Dictionary = V3.STREETS[i]
			var b: Dictionary = V3.STREETS[j]
			var ba := _aabb(a)
			var bb := _aabb(b)
			assert_true((not _overlap(ba, bb)) or _v_touch(ba, bb),
				"%s vs %s: AABB 重叠（非垂直相接豁免）" % [a["name"], b["name"]])


# ==== 任务 5：钟门 + 市集带 ====

# 实体 AABB 与区域盒是否实质相交（每轴交集 > eps；面/边接触不算侵入）
func _in_region(bb: Array, x0: float, x1: float, y0: float, y1: float,
		z0: float, z1: float) -> bool:
	var eps := 0.0005
	return bb[0].x + eps < x1 and x0 + eps < bb[1].x \
		and bb[0].y + eps < y1 and y0 + eps < bb[1].y \
		and bb[0].z + eps < z1 and z0 + eps < bb[1].z


# ---- 26. 门廊净空：两柱间 x∈[-1.25,1.25] 全高带（0..过梁底 4.5）无任何实体 ----
func test_gate_doorway() -> void:
	for side0 in [["GateN", 13.0, 16.0], ["GateS", -16.0, -13.0]]:
		var side: Array = side0
		var tag: String = side[0]
		var zw: float = side[1]
		var zh: float = side[2]
		var pw := _find(V3.GATES, tag + "_PillarW")
		var pe := _find(V3.GATES, tag + "_PillarE")
		assert_false(pw.is_empty(), "GATES 含 %s_PillarW" % tag)
		assert_false(pe.is_empty(), "GATES 含 %s_PillarE" % tag)
		if pw.is_empty() or pe.is_empty():
			continue
		for e0 in V3.all_solids():
			var e: Dictionary = e0
			var bb := _aabb(e)
			assert_false(_in_region(bb, -1.25, 1.25, 0.0, 4.5, zw, zh),
				"%s 门廊 2.5m 净空被 %s 侵入" % [tag, e["name"]])


# ---- 27. 过梁：底面 4.5 / 顶面 4.9（南北）----
func test_gate_lintel() -> void:
	for tag in ["GateN", "GateS"]:
		var ent := _find(V3.GATES, tag + "_Lintel")
		assert_false(ent.is_empty(), "GATES 含 %s_Lintel" % tag)
		if ent.is_empty():
			continue
		var bb := _aabb(ent)
		assert_almost_eq(bb[0].y, 4.5, 0.001, "%s_Lintel 底面 == 4.5" % tag)
		assert_almost_eq(bb[1].y, 4.9, 0.001, "%s_Lintel 顶面 == 4.9" % tag)


# ---- 28. 棚板 vs 过梁：AABB 无重叠且 z 缝 == 0.75（南北）----
func test_canopy_vs_lintel() -> void:
	for pair0 in [["GateN", "BeltN"], ["GateS", "BeltS"]]:
		var pair: Array = pair0
		var lintel := _find(V3.GATES, pair[0] + "_Lintel")
		assert_false(lintel.is_empty(), "GATES 含 %s_Lintel" % pair[0])
		if lintel.is_empty():
			continue
		var lb := _aabb(lintel)
		for cn in [pair[1] + "_CanopyW", pair[1] + "_CanopyE"]:
			var ent := _find(V3.GATES, cn)
			assert_false(ent.is_empty(), "GATES 含 %s" % cn)
			if ent.is_empty():
				continue
			var cb := _aabb(ent)
			assert_false(_overlap(cb, lb), "%s 与过梁 AABB 无重叠" % cn)
			var gap: float = maxf(cb[0].z - lb[1].z, lb[0].z - cb[1].z)
			assert_almost_eq(gap, 0.75, 0.01, "%s 与过梁 z 缝 == 0.75" % cn)


# ---- 29. 天井：x∈[-1,1] 棚板带 z 区域内无 roof 实体；棚板恰 2 块/带 ----
func test_canopy_skywell() -> void:
	for region0 in [[-1.0, 1.0, 9.5, 12.0], [-1.0, 1.0, -12.0, -9.5]]:
		var region: Array = region0
		for e0 in V3.all_solids():
			var e: Dictionary = e0
			if e["kind"] != "roof":
				continue
			var bb := _aabb(e)
			assert_false(_in_region(bb, region[0], region[1], -INF, INF, region[2], region[3]),
				"天井区域 x∈[%s,%s] z∈[%s,%s] 出现 roof 实体 %s" % [
					region[0], region[1], region[2], region[3], e["name"]])
	var cn_count := 0
	var cs_count := 0
	for e0 in V3.GATES:
		var e: Dictionary = e0
		var nm: String = e["name"]
		if nm.begins_with("BeltN_Canopy"):
			cn_count += 1
		if nm.begins_with("BeltS_Canopy"):
			cs_count += 1
	assert_eq(cn_count, 2, "北市集带棚板恰 2 块")
	assert_eq(cs_count, 2, "南市集带棚板恰 2 块")


# ---- 30. 翼墙外端侧豁场：过梁底以下通行带内无 GATES wall 实体（北东 + 南镜像）----
# 区域限高 y∈[0,4.5]（过梁以下皆通路，同门廊判据）；rim 为既知背景不属 GATES，不在检查范围。
func test_wing_side_gap() -> void:
	for tag in ["GateN", "GateS"]:
		for wing in ["_WingW", "_WingE"]:
			var ent := _find(V3.GATES, tag + wing)
			assert_false(ent.is_empty(), "GATES 含 %s%s" % [tag, wing])
	for region0 in [[5.0, 14.0, 9.5, 13.5], [-14.0, -5.0, -13.5, -9.5]]:
		var region: Array = region0
		for e0 in V3.GATES:
			var e: Dictionary = e0
			if e["kind"] != "wall":
				continue
			var bb := _aabb(e)
			assert_false(_in_region(bb, region[0], region[1], 0.0, 4.5, region[2], region[3]),
				"侧豁场 x∈[%s,%s] z∈[%s,%s] 出现 wall 实体 %s（≥4m 通路被堵）" % [
					region[0], region[1], region[2], region[3], e["name"]])


# ---- 31. 市集带摊阁（任务 9 A4 重布后）：顶 1.2 可跳 / 尺寸 2.0×1.8 / 贴 rim 面 |z|=10 /
#         台阶顶 0.6 贴摊阁缘缝 0 / 台阶↔翼墙 z 缝 0.95（台阶顶 0.6≤0.95 非阻挡体，合法）/
#         摊阁↔门柱 z 缝恰 1.2 ----
func test_belt_pavilions() -> void:
	for tags0 in [["BeltN", "GateN"], ["BeltS", "GateS"]]:
		var tags: Array = tags0
		var belt: String = tags[0]
		var gate: String = tags[1]
		for lr in ["W", "E"]:
			var pav := _find(V3.GATES, belt + "_Pav" + lr)
			var stp := _find(V3.GATES, belt + "_PavStep" + lr)
			var wing := _find(V3.GATES, gate + "_Wing" + lr)
			var pillar := _find(V3.GATES, gate + "_Pillar" + lr)
			assert_false(pav.is_empty(), "GATES 含 %s_Pav%s" % [belt, lr])
			assert_false(stp.is_empty(), "GATES 含 %s_PavStep%s" % [belt, lr])
			assert_false(wing.is_empty(), "GATES 含 %s_Wing%s" % [gate, lr])
			assert_false(pillar.is_empty(), "GATES 含 %s_Pillar%s" % [gate, lr])
			if pav.is_empty() or stp.is_empty() or wing.is_empty() or pillar.is_empty():
				continue
			var ps: Vector3 = pav["size"]
			var pb := _aabb(pav)
			var sb := _aabb(stp)
			var wb := _aabb(wing)
			var plb := _aabb(pillar)
			assert_almost_eq(pb[1].y, 1.2, 0.001, "%s_Pav%s 顶 == 1.2" % [belt, lr])
			assert_lte(pb[1].y, V3.JUMPABLE_MAX, "%s_Pav%s 顶 ≤ JUMPABLE_MAX（可跳）" % [belt, lr])
			assert_almost_eq(ps.x, 2.0, 0.001, "%s_Pav%s size.x == 2.0（A4 缩为 2.0×1.8）" % [belt, lr])
			assert_almost_eq(ps.z, 1.8, 0.001, "%s_Pav%s size.z == 1.8（A4 缩为 2.0×1.8）" % [belt, lr])
			# 摊阁内缘面贴 rim N/S 面 |z|=10（BeltN 南面 z=10 / BeltS 北面 z=-10）
			var rim_face: float = minf(absf(pb[0].z), absf(pb[1].z))
			assert_almost_eq(rim_face, 10.0, 0.001, "%s_Pav%s 贴 rim 面 |z| == 10" % [belt, lr])
			assert_almost_eq(sb[1].y, 0.6, 0.001, "%s_PavStep%s 台阶顶 == 0.6" % [belt, lr])
			var gap_pav: float = maxf(sb[0].z - pb[1].z, pb[0].z - sb[1].z)
			assert_almost_eq(gap_pav, 0.0, 0.01, "%s_PavStep%s 与摊阁 z 贴缘缝 == 0" % [belt, lr])
			var gap_wing: float = maxf(sb[0].z - wb[1].z, wb[0].z - sb[1].z)
			assert_almost_eq(gap_wing, 0.95, 0.01,
				"%s_PavStep%s 与翼墙 z 缝 == 0.95（台阶顶 0.6 非阻挡体，窄缝规则不适用）" % [belt, lr])
			var gap_pillar: float = maxf(pb[0].z - plb[1].z, plb[0].z - pb[1].z)
			assert_almost_eq(gap_pillar, 1.2, 0.01, "%s_Pav%s 与门柱 z 缝 == 1.2" % [belt, lr])


# ---- 32. 旋转对称：每个 GateN_*/BeltN_* 有 GateS_*/BeltS_* 对应体，center 互为 (-x,-z)、size 相同 ----
func test_gates_rotation_pairs() -> void:
	var north := []
	for e0 in V3.GATES:
		var e: Dictionary = e0
		var nm: String = e["name"]
		if nm.begins_with("GateN_") or nm.begins_with("BeltN_"):
			north.append(e)
	assert_eq(north.size(), 13, "北半钟门+市集带实体共 13 个（门 5 + 带 8）")
	for e0 in north:
		var e: Dictionary = e0
		var nm: String = e["name"]
		var want := nm.replace("GateN_", "GateS_").replace("BeltN_", "BeltS_")
		var w := _find(V3.GATES, want)
		assert_false(w.is_empty(), "%s 有旋转对应体 %s" % [nm, want])
		if w.is_empty():
			continue
		var cn: Vector3 = e["center"]
		var cs: Vector3 = w["center"]
		var sn: Vector3 = e["size"]
		var ss: Vector3 = w["size"]
		assert_almost_eq(cs.x, -cn.x, 0.001, "%s/%s center.x 互为 -x" % [nm, want])
		assert_almost_eq(cs.y, cn.y, 0.001, "%s/%s center.y 相同" % [nm, want])
		assert_almost_eq(cs.z, -cn.z, 0.001, "%s/%s center.z 互为 -z" % [nm, want])
		assert_lt((sn - ss).length(), 0.001, "%s/%s size 相同" % [nm, want])


# ---- 33. GATES 内部两两 AABB 无重叠（豁免垂直相接 ±0.01）----
func test_gates_no_overlap() -> void:
	assert_eq(V3.GATES.size(), 26, "GATES 实体共 26 个（南/北各 13）")
	for i in range(V3.GATES.size()):
		for j in range(i + 1, V3.GATES.size()):
			var a: Dictionary = V3.GATES[i]
			var b: Dictionary = V3.GATES[j]
			var ba := _aabb(a)
			var bb := _aabb(b)
			assert_true((not _overlap(ba, bb)) or _v_touch(ba, bb),
				"%s vs %s: AABB 重叠（非垂直相接豁免）" % [a["name"], b["name"]])


# ==== 任务 6：背街 + 营（南北）====

# ---- 34. 营门缝净空：北营南门缝 x∈[-1.5,1.5] z∈[24,25]；东西侧门缝 z∈[25.5,27.5]
#         （x∈[-7,-6] 与 [6,7]）；南营镜像（z 取反）。门缝带内无 wall 实体 ----
func test_camp_doors() -> void:
	var regions := [
		[-1.5, 1.5, 24.0, 25.0],
		[-7.0, -6.0, 25.5, 27.5],
		[6.0, 7.0, 25.5, 27.5],
		[-1.5, 1.5, -25.0, -24.0],
		[-7.0, -6.0, -27.5, -25.5],
		[6.0, 7.0, -27.5, -25.5],
	]
	for r0 in regions:
		var r: Array = r0
		for e0 in V3.all_solids():
			var e: Dictionary = e0
			if e["kind"] != "wall":
				continue
			var bb := _aabb(e)
			assert_false(_in_region(bb, r[0], r[1], 0.0, 4.5, r[2], r[3]),
				"营门缝 x∈[%s,%s] z∈[%s,%s]（顶 4.5 以下通行带）出现 wall 实体 %s" % [
					r[0], r[1], r[2], r[3], e["name"]])


# ---- 35. 营顶板：南/北营 Roof 底面 == 4.5 ----
func test_camp_roof() -> void:
	for tag in ["CampN", "CampS"]:
		var ent := _find(V3.BACKSTREETS, tag + "_Roof")
		assert_false(ent.is_empty(), "BACKSTREETS 含 %s_Roof" % tag)
		if ent.is_empty():
			continue
		assert_eq(ent["kind"], "roof", "%s_Roof kind == roof" % tag)
		var bb := _aabb(ent)
		assert_almost_eq(bb[0].y, 4.5, 0.001, "%s_Roof 底面 == 4.5" % tag)


# ---- 36. 影壁：南门影壁 ↔ 营南墙外沿缝 == 2.0；侧影壁 ↔ 营侧墙缝 == 2.25；南北共 6 影壁 ----
func test_camp_screens() -> void:
	var screen_count := 0
	for e0 in V3.BACKSTREETS:
		var e: Dictionary = e0
		if (e["name"] as String).contains("_Screen_"):
			screen_count += 1
	assert_eq(screen_count, 6, "南北营影壁共 6 块")
	# 每营取影壁与其对应营墙名（南营为 180° 旋转命名：门侧影壁 Screen_N、南墙 = WallN_*）
	for spec0 in [
			["CampN", "Screen_S", "WallS_W", "Screen_W", "WallW_S", "Screen_E", "WallE_S"],
			["CampS", "Screen_N", "WallN_W", "Screen_W", "WallW_S", "Screen_E", "WallE_S"],
	]:
		var spec: Array = spec0
		var camp: String = spec[0]
		var scr_s := _find(V3.BACKSTREETS, camp + "_" + spec[1])
		var wall_s := _find(V3.BACKSTREETS, camp + "_" + spec[2])
		assert_false(scr_s.is_empty(), "BACKSTREETS 含 %s_%s" % [camp, spec[1]])
		assert_false(wall_s.is_empty(), "BACKSTREETS 含 %s_%s" % [camp, spec[2]])
		if not scr_s.is_empty() and not wall_s.is_empty():
			var sb := _aabb(scr_s)
			var wb := _aabb(wall_s)
			var gap_z: float = maxf(wb[0].z - sb[1].z, sb[0].z - wb[1].z)
			assert_almost_eq(gap_z, 2.0, 0.01,
				"%s_%s ↔ 营南墙外沿缝 == 2.0" % [camp, spec[1]])
		var scr_w := _find(V3.BACKSTREETS, camp + "_" + spec[3])
		var wall_w := _find(V3.BACKSTREETS, camp + "_" + spec[4])
		assert_false(scr_w.is_empty(), "BACKSTREETS 含 %s_%s" % [camp, spec[3]])
		assert_false(wall_w.is_empty(), "BACKSTREETS 含 %s_%s" % [camp, spec[4]])
		if not scr_w.is_empty() and not wall_w.is_empty():
			var sb := _aabb(scr_w)
			var wb := _aabb(wall_w)
			var gap_x: float = maxf(wb[0].x - sb[1].x, sb[0].x - wb[1].x)
			assert_almost_eq(gap_x, 2.25, 0.01,
				"%s_%s ↔ 营西墙缝 == 2.25" % [camp, spec[3]])
		var scr_e := _find(V3.BACKSTREETS, camp + "_" + spec[5])
		var wall_e := _find(V3.BACKSTREETS, camp + "_" + spec[6])
		assert_false(scr_e.is_empty(), "BACKSTREETS 含 %s_%s" % [camp, spec[5]])
		assert_false(wall_e.is_empty(), "BACKSTREETS 含 %s_%s" % [camp, spec[6]])
		if not scr_e.is_empty() and not wall_e.is_empty():
			var sb := _aabb(scr_e)
			var wb := _aabb(wall_e)
			var gap_x: float = maxf(sb[0].x - wb[1].x, wb[0].x - sb[1].x)
			assert_almost_eq(gap_x, 2.25, 0.01,
				"%s_%s ↔ 营东墙缝 == 2.25" % [camp, spec[5]])


# ---- 37. 营内部净空：北营 x∈[-6,6] z∈[25,28] y∈[0,3] 无任何实体（出生点空间保护）；南营同 ----
func test_camp_interior_clear() -> void:
	for region0 in [[-6.0, 6.0, 25.0, 28.0], [-6.0, 6.0, -28.0, -25.0]]:
		var region: Array = region0
		for e0 in V3.all_solids():
			var e: Dictionary = e0
			var bb := _aabb(e)
			assert_false(_in_region(bb, region[0], region[1], 0.0, 3.0, region[2], region[3]),
				"营内部 x∈[%s,%s] z∈[%s,%s] y∈[0,3] 被 %s 侵入" % [
					region[0], region[1], region[2], region[3], e["name"]])


# ---- 38. 背街断视线：北背街 LOS 板 ×2 在 x=±10、大树 ×2 在 x=±21（z=18±0.5 带内）；南背街同 ----
func test_backstreet_los_breakers() -> void:
	for spec0 in [
			["BackN_LOS_E", "cover", 10.0, 18.0],
			["BackN_LOS_W", "cover", -10.0, 18.0],
			["BackN_Tree_E", "bigtree", 21.0, 18.0],
			["BackN_Tree_W", "bigtree", -21.0, 18.0],
			["BackS_LOS_E", "cover", 10.0, -18.0],
			["BackS_LOS_W", "cover", -10.0, -18.0],
			["BackS_Tree_E", "bigtree", 21.0, -18.0],
			["BackS_Tree_W", "bigtree", -21.0, -18.0],
	]:
		var spec: Array = spec0
		var nm: String = spec[0]
		var ent := _find(V3.BACKSTREETS, nm)
		assert_false(ent.is_empty(), "BACKSTREETS 含 %s" % nm)
		if ent.is_empty():
			continue
		assert_eq(ent["kind"], spec[1], "%s kind == %s" % [nm, spec[1]])
		var c: Vector3 = ent["center"]
		assert_almost_eq(c.x, spec[2], 0.001, "%s center.x == %s" % [nm, spec[2]])
		assert_true(absf(c.z - spec[3]) <= 0.5, "%s 在 z=%s±0.5 带内" % [nm, spec[3]])


# ---- 39. 货车：center.x == 4.5（偏离门轴）；与南门影壁缝 == 0（面接触）；南营镜像 ----
func test_truck_placement() -> void:
	for pair0 in [["CampN_Truck", "CampN_Screen_S", 4.5],
			["CampS_Truck", "CampS_Screen_N", -4.5]]:
		var pair: Array = pair0
		var truck := _find(V3.BACKSTREETS, pair[0])
		var scr := _find(V3.BACKSTREETS, pair[1])
		assert_false(truck.is_empty(), "BACKSTREETS 含 %s" % pair[0])
		assert_false(scr.is_empty(), "BACKSTREETS 含 %s" % pair[1])
		if truck.is_empty() or scr.is_empty():
			continue
		var c: Vector3 = truck["center"]
		assert_almost_eq(c.x, pair[2], 0.001, "%s center.x == %s（偏离门轴）" % [pair[0], pair[2]])
		var tb := _aabb(truck)
		var sb := _aabb(scr)
		var gap: float = maxf(tb[0].x - sb[1].x, sb[0].x - tb[1].x)
		assert_almost_eq(gap, 0.0, 0.01, "%s ↔ %s x 缝 == 0（面接触）" % [pair[0], pair[1]])


# ---- 40. 旋转对称：每个 CampN_*/BackN_* 有 CampS_*/BackS_* 对应体（_rot_pair 含前缀与 W↔E 轮换），
#         center 互为 (-x,-z)、size 相同 ----
func test_backstreets_rotation_pairs() -> void:
	var north := []
	for e0 in V3.BACKSTREETS:
		var e: Dictionary = e0
		var nm: String = e["name"]
		if nm.begins_with("CampN_") or nm.begins_with("BackN_"):
			north.append(e)
	assert_eq(north.size(), 16, "北半背街+营实体共 16 个（营 12 + 背街 4）")
	for e0 in north:
		var e: Dictionary = e0
		var nm: String = e["name"]
		var want := _rot_pair(nm)
		var w := _find(V3.BACKSTREETS, want)
		assert_false(w.is_empty(), "%s 有旋转对应体 %s" % [nm, want])
		if w.is_empty():
			continue
		var cn: Vector3 = e["center"]
		var cs: Vector3 = w["center"]
		var sn: Vector3 = e["size"]
		var ss: Vector3 = w["size"]
		assert_almost_eq(cs.x, -cn.x, 0.001, "%s/%s center.x 互为 -x" % [nm, want])
		assert_almost_eq(cs.y, cn.y, 0.001, "%s/%s center.y 相同" % [nm, want])
		assert_almost_eq(cs.z, -cn.z, 0.001, "%s/%s center.z 互为 -z" % [nm, want])
		assert_lt((sn - ss).length(), 0.001, "%s/%s size 相同" % [nm, want])


# ---- 41. BACKSTREETS 内部两两 AABB 无重叠（豁免：a 垂直相接 ±0.01；
#         b 同营墙段角部相接——两名均以同一 CampN_Wall/CampS_Wall 前缀开头，防御性豁免）----
func test_backstreets_no_overlap() -> void:
	assert_eq(V3.BACKSTREETS.size(), 32, "BACKSTREETS 实体共 32 个（南/北各 16）")
	for i in range(V3.BACKSTREETS.size()):
		for j in range(i + 1, V3.BACKSTREETS.size()):
			var a: Dictionary = V3.BACKSTREETS[i]
			var b: Dictionary = V3.BACKSTREETS[j]
			var ba := _aabb(a)
			var bb := _aabb(b)
			var camp_wall_pair: bool = (
				((a["name"] as String).begins_with("CampN_Wall")
					and (b["name"] as String).begins_with("CampN_Wall"))
				or ((a["name"] as String).begins_with("CampS_Wall")
					and (b["name"] as String).begins_with("CampS_Wall")))
			assert_true((not _overlap(ba, bb)) or _v_touch(ba, bb) or camp_wall_pair,
				"%s vs %s: AABB 重叠（非垂直相接/同营墙段角部豁免）" % [a["name"], b["name"]])


# ==== 任务 7：外环 + 角场 ====

# ---- 42. OUTER 总数 20：外环视线打断树 4 + 角场 4×4（裁决轮：删除 Box2）----
func test_outer_counts() -> void:
	assert_eq(V3.OUTER.size(), 20, "OUTER 实体总数 == 20（外环树 4 + 角场 4×4）")
	var ring_count := 0
	var corner_count := 0
	for e0 in V3.OUTER:
		var e: Dictionary = e0
		var nm: String = e["name"]
		if nm.begins_with("OuterRing_"):
			ring_count += 1
		elif nm.begins_with("Corner"):
			corner_count += 1
	assert_eq(ring_count, 4, "外环视线打断树恰 4 棵")
	assert_eq(corner_count, 16, "角场实体恰 16 个（4 实体 × 4 角）")


# ---- 43. 角场摊阁：顶 1.2 ≤ JUMPABLE_MAX（可跳）；台阶顶 0.6 ----
func test_corner_pav_jumpable() -> void:
	for corner in ["CornerNW", "CornerNE", "CornerSE", "CornerSW"]:
		var pav := _find(V3.OUTER, corner + "_Pav")
		var stp := _find(V3.OUTER, corner + "_PavStep")
		assert_false(pav.is_empty(), "OUTER 含 %s_Pav" % corner)
		assert_false(stp.is_empty(), "OUTER 含 %s_PavStep" % corner)
		if pav.is_empty() or stp.is_empty():
			continue
		var pb := _aabb(pav)
		var sb := _aabb(stp)
		assert_almost_eq(pb[1].y, 1.2, 0.001, "%s_Pav 顶 == 1.2" % corner)
		assert_lte(pb[1].y, V3.JUMPABLE_MAX, "%s_Pav 顶 ≤ JUMPABLE_MAX（可跳）" % corner)
		assert_almost_eq(sb[1].y, 0.6, 0.001, "%s_PavStep 台阶顶 == 0.6" % corner)


# ---- 44. 角场真接触（裁决轮强化）：
#         PavStep↔Pav：z 缝 == 0 且正交轴 x 投影重叠 ≥0.3m（真面接触判据）；
#         Box1↔Pav：x 缝 == 0 且 z 缝 == 0（裁决 A.1 坐标下 Box1 恰对角贴摊阁外角——
#         两轴投影均恰好相接、重叠量为 0，≥0.3m 面接触判据几何不可满足，
#         故以双缝 == 0 作"真接触"判据，可根治旧数据缝读 0 实距 0.15 的假接触；见报告 concern）；
#         Box2 已删除 ----
func test_corner_face_contacts() -> void:
	for corner in ["CornerNW", "CornerNE", "CornerSE", "CornerSW"]:
		var pav := _find(V3.OUTER, corner + "_Pav")
		var stp := _find(V3.OUTER, corner + "_PavStep")
		var b1 := _find(V3.OUTER, corner + "_Box1")
		assert_false(pav.is_empty(), "OUTER 含 %s_Pav" % corner)
		assert_false(stp.is_empty(), "OUTER 含 %s_PavStep" % corner)
		assert_false(b1.is_empty(), "OUTER 含 %s_Box1" % corner)
		if pav.is_empty() or stp.is_empty() or b1.is_empty():
			continue
		var pb := _aabb(pav)
		var sb := _aabb(stp)
		var b1b := _aabb(b1)
		# PavStep 贴摊阁缘（z 向；maxf 双向取缝，旋转角自动覆盖）
		var gap_step: float = maxf(pb[0].z - sb[1].z, sb[0].z - pb[1].z)
		assert_almost_eq(gap_step, 0.0, 0.01, "%s_PavStep↔Pav z 缝 == 0" % corner)
		# 真面接触判据：正交轴（x）投影重叠 ≥ 0.3m
		var step_x_overlap: float = minf(pb[1].x, sb[1].x) - maxf(pb[0].x, sb[0].x)
		assert_true(step_x_overlap >= 0.3 - 0.001,
			"%s_PavStep↔Pav 正交轴 x 投影重叠 %.3f ≥ 0.3" % [corner, step_x_overlap])
		# Box1 西侧缘恰贴摊阁东缘（x 缝 == 0，裁决 A.1 真贴缘）
		var gap_b1x: float = maxf(pb[0].x - b1b[1].x, b1b[0].x - pb[1].x)
		assert_almost_eq(gap_b1x, 0.0, 0.01, "%s_Box1↔Pav x 缝 == 0" % corner)
		# Box1 同时贴摊阁南缘（z 缝 == 0）——对角相接，真接触
		var gap_b1z: float = maxf(pb[0].z - b1b[1].z, b1b[0].z - pb[1].z)
		assert_almost_eq(gap_b1z, 0.0, 0.01, "%s_Box1↔Pav z 缝 == 0" % corner)


# ---- 45. 旋转对称：OUTER 全部 20 实体逐一有旋转对应体（Corner 前缀映射 +
#         OuterRing 全名映射），center 互为 (-x,-z)、size 相同 ----
func test_corner_rotation_pairs() -> void:
	assert_eq(V3.OUTER.size(), 20, "OUTER 实体共 20 个")
	for e0 in V3.OUTER:
		var e: Dictionary = e0
		var nm: String = e["name"]
		var want := _rot_pair(nm)
		var w := _find(V3.OUTER, want)
		assert_false(w.is_empty(), "%s 有旋转对应体 %s" % [nm, want])
		if w.is_empty():
			continue
		var cn: Vector3 = e["center"]
		var cs: Vector3 = w["center"]
		var sn: Vector3 = e["size"]
		var ss: Vector3 = w["size"]
		assert_almost_eq(cs.x, -cn.x, 0.001, "%s/%s center.x 互为 -x" % [nm, want])
		assert_almost_eq(cs.y, cn.y, 0.001, "%s/%s center.y 相同" % [nm, want])
		assert_almost_eq(cs.z, -cn.z, 0.001, "%s/%s center.z 互为 -z" % [nm, want])
		assert_lt((sn - ss).length(), 0.001, "%s/%s size 相同" % [nm, want])


# ---- 46. 外环树：4 棵在 (±26.5, ±12)、size (0.7,2.5,0.7)；
#         距边界墙内沿 x=±30 ≥3.0；距长墙外沿 x=±23.5 ≥3.0 ----
# 间距按树 center.x 到墙面的距离度量（基准数据 26.5−23.5 == 3.0 恰为 center 距；
# 若按 AABB 边缘度量则为 2.65，与 brief 数据矛盾——已裁决保留中心距，见任务报告 concern）。
func test_outer_ring_trees() -> void:
	var specs := [
		["OuterRing_TreeNW", -26.5, 12.0],
		["OuterRing_TreeNE", 26.5, 12.0],
		["OuterRing_TreeSW", -26.5, -12.0],
		["OuterRing_TreeSE", 26.5, -12.0],
	]
	for spec0 in specs:
		var spec: Array = spec0
		var nm: String = spec[0]
		var ent := _find(V3.OUTER, nm)
		assert_false(ent.is_empty(), "OUTER 含 %s" % nm)
		if ent.is_empty():
			continue
		assert_eq(ent["kind"], "bigtree", "%s kind == bigtree" % nm)
		var c: Vector3 = ent["center"]
		assert_almost_eq(c.x, spec[1], 0.001, "%s center.x == %s" % [nm, spec[1]])
		assert_almost_eq(c.z, spec[2], 0.001, "%s center.z == %s" % [nm, spec[2]])
		# 树规格断言（裁决轮追加，防整体缩放盲区）
		var s: Vector3 = ent["size"]
		assert_almost_eq(s.x, 0.7, 0.001, "%s size.x == 0.7" % nm)
		assert_almost_eq(s.y, 2.5, 0.001, "%s size.y == 2.5" % nm)
		assert_almost_eq(s.z, 0.7, 0.001, "%s size.z == 0.7" % nm)
		# 距最近边界墙内沿（x=±BOUND_X）≥ 3.0
		var d_bound: float = minf(absf(c.x - V3.BOUND_X), absf(c.x + V3.BOUND_X))
		assert_true(d_bound >= 3.0 - 0.001,
			"%s 距边界墙内沿 %.3f ≥ 3.0" % [nm, d_bound])
		# 距最近长墙外沿（x=±23.5）≥ 3.0
		var d_wall: float = minf(absf(c.x - 23.5), absf(c.x + 23.5))
		assert_true(d_wall >= 3.0 - 0.001,
			"%s 距长墙外沿 %.3f ≥ 3.0" % [nm, d_wall])


# ---- 47. 角场净空：界内 x∈[-30,30] z∈[-29,29]；摊阁↔最近营影壁净距 ≥1.2；角场树↔最近背街树净距 ≥1.2 ----
func test_corner_clearance() -> void:
	var corners := []
	for e0 in V3.OUTER:
		var e: Dictionary = e0
		if (e["name"] as String).begins_with("Corner"):
			corners.append(e)
	assert_eq(corners.size(), 16, "角场实体共 16 个")
	for e0 in corners:
		var e: Dictionary = e0
		var bb := _aabb(e)
		assert_true(bb[0].x >= -V3.BOUND_X and bb[1].x <= V3.BOUND_X,
			"%s 界内 x∈[-30,30]" % e["name"])
		assert_true(bb[0].z >= -V3.BOUND_Z and bb[1].z <= V3.BOUND_Z,
			"%s 界内 z∈[-29,29]" % e["name"])
	# 参照物：营影壁 6 块 + 背街大树 4 棵（BACKSTREETS 既有数据）
	var screens := []
	var back_trees := []
	for e0 in V3.BACKSTREETS:
		var e: Dictionary = e0
		if (e["name"] as String).contains("_Screen_"):
			screens.append(_aabb(e))
		if e["kind"] == "bigtree":
			back_trees.append(_aabb(e))
	assert_eq(screens.size(), 6, "BACKSTREETS 影壁共 6 块（参照集）")
	assert_eq(back_trees.size(), 4, "BACKSTREETS 背街大树共 4 棵（参照集）")
	# 角场摊阁 ↔ 最近营影壁水平净距 ≥ 1.2（实际 15+，宽松断言）
	for corner in ["CornerNW", "CornerNE", "CornerSE", "CornerSW"]:
		var pav := _find(V3.OUTER, corner + "_Pav")
		assert_false(pav.is_empty(), "OUTER 含 %s_Pav" % corner)
		if pav.is_empty():
			continue
		var pb := _aabb(pav)
		var nd := INF
		for sb0 in screens:
			nd = minf(nd, _xz_net_dist(pb, sb0))
		assert_true(nd >= 1.2 - 0.001,
			"%s_Pav ↔ 最近营影壁净距 %.3f ≥ 1.2" % [corner, nd])
	# 角场大树 ↔ 最近背街大树净距 ≥ 1.2
	for corner in ["CornerNW", "CornerNE", "CornerSE", "CornerSW"]:
		var tree := _find(V3.OUTER, corner + "_Tree")
		assert_false(tree.is_empty(), "OUTER 含 %s_Tree" % corner)
		if tree.is_empty():
			continue
		var tb := _aabb(tree)
		var nd := INF
		for bt0 in back_trees:
			nd = minf(nd, _xz_net_dist(tb, bt0))
		assert_true(nd >= 1.2 - 0.001,
			"%s_Tree ↔ 最近背街大树净距 %.3f ≥ 1.2" % [corner, nd])


# ---- 48. OUTER 内部两两 AABB 无重叠（豁免垂直相接 ±0.01，面接触由 _overlap eps 判定不算重叠）；
#         OUTER × 其余实体无重叠（同上豁免 + bigtree 叠墙铁律豁免——收窄：
#         仅 bigtree 一方与 kind=="wall" 一方成对时豁免，铁律原意"大树只许叠墙"）----
func test_outer_no_overlap() -> void:
	assert_eq(V3.OUTER.size(), 20, "OUTER 实体共 20 个")
	for i in range(V3.OUTER.size()):
		for j in range(i + 1, V3.OUTER.size()):
			var a: Dictionary = V3.OUTER[i]
			var b: Dictionary = V3.OUTER[j]
			var ba := _aabb(a)
			var bb := _aabb(b)
			assert_true((not _overlap(ba, bb)) or _v_touch(ba, bb),
				"%s vs %s: AABB 重叠（非垂直相接豁免）" % [a["name"], b["name"]])
	# OUTER × all_solids() 中非 OUTER 实体（all_solids() 提到循环外，裁决轮）
	var outer_names := {}
	for e0 in V3.OUTER:
		outer_names[(e0 as Dictionary)["name"]] = true
	var solids := V3.all_solids()
	for e0 in V3.OUTER:
		var a: Dictionary = e0
		var ba := _aabb(a)
		for o0 in solids:
			var b: Dictionary = o0
			if outer_names.has(b["name"]):
				continue
			var bb := _aabb(b)
			# bigtree 叠墙铁律豁免（收窄）：仅 bigtree × wall 成对时豁免
			var bigtree_exempt: bool = (a["kind"] == "bigtree" and b["kind"] == "wall") \
				or (a["kind"] == "wall" and b["kind"] == "bigtree")
			assert_true((not _overlap(ba, bb)) or _v_touch(ba, bb) or bigtree_exempt,
				"%s vs %s: AABB 重叠（非垂直相接/bigtree×wall 豁免）" % [a["name"], b["name"]])


# ---- 49. 外环通道净空（裁决轮新增）：东带 x∈[23.5,30]×z∈[-14,14]、
#         西带 x∈[-30,-23.5]×z∈[-14,14] 内无任何非 bigtree 实体 ----
# 外环树 bigtree 为通道内指定视线打断物，豁免；Ground 为地面非障碍物，豁免；
# 角场实体天然在 |z|>14 不受影响。
func test_outer_corridor_clearance() -> void:
	for e0 in V3.all_solids():
		var e: Dictionary = e0
		if e["kind"] == "bigtree" or e["kind"] == "ground":
			continue
		var bb := _aabb(e)
		assert_false(_in_region(bb, 23.5, 30.0, -INF, INF, -14.0, 14.0),
			"东外环通道 x∈[23.5,30] z∈[-14,14] 出现非 bigtree 实体 %s" % e["name"])
		assert_false(_in_region(bb, -30.0, -23.5, -INF, INF, -14.0, 14.0),
			"西外环通道 x∈[-30,-23.5] z∈[-14,14] 出现非 bigtree 实体 %s" % e["name"])


# ---- 50. OUTER 绝对规格（裁决轮新增）：全部 20 实体 name→kind→center→size 逐一断言
#         （容差 0.001），防整体平移/缩放盲区 ----
func test_outer_absolute_specs() -> void:
	assert_eq(V3.OUTER.size(), 20, "OUTER 实体共 20 个")
	var specs := [
		["OuterRing_TreeNW", "bigtree", Vector3(-26.5, 1.25, 12), Vector3(0.7, 2.5, 0.7)],
		["OuterRing_TreeNE", "bigtree", Vector3(26.5, 1.25, 12), Vector3(0.7, 2.5, 0.7)],
		["OuterRing_TreeSW", "bigtree", Vector3(-26.5, 1.25, -12), Vector3(0.7, 2.5, 0.7)],
		["OuterRing_TreeSE", "bigtree", Vector3(26.5, 1.25, -12), Vector3(0.7, 2.5, 0.7)],
		["CornerNW_Pav", "cover", Vector3(-26, 0.6, 21.5), Vector3(2.5, 1.2, 2.5)],
		["CornerNW_PavStep", "cover", Vector3(-26, 0.3, 23.5), Vector3(1.5, 0.6, 1.5)],
		["CornerNW_Box1", "cover", Vector3(-24.15, 0.45, 19.65), Vector3(1.2, 0.9, 1.2)],
		["CornerNW_Tree", "bigtree", Vector3(-23, 1.25, 22), Vector3(0.7, 2.5, 0.7)],
		["CornerNE_Pav", "cover", Vector3(26, 0.6, 21.5), Vector3(2.5, 1.2, 2.5)],
		["CornerNE_PavStep", "cover", Vector3(26, 0.3, 23.5), Vector3(1.5, 0.6, 1.5)],
		["CornerNE_Box1", "cover", Vector3(24.15, 0.45, 19.65), Vector3(1.2, 0.9, 1.2)],
		["CornerNE_Tree", "bigtree", Vector3(23, 1.25, 22), Vector3(0.7, 2.5, 0.7)],
		["CornerSE_Pav", "cover", Vector3(26, 0.6, -21.5), Vector3(2.5, 1.2, 2.5)],
		["CornerSE_PavStep", "cover", Vector3(26, 0.3, -23.5), Vector3(1.5, 0.6, 1.5)],
		["CornerSE_Box1", "cover", Vector3(24.15, 0.45, -19.65), Vector3(1.2, 0.9, 1.2)],
		["CornerSE_Tree", "bigtree", Vector3(23, 1.25, -22), Vector3(0.7, 2.5, 0.7)],
		["CornerSW_Pav", "cover", Vector3(-26, 0.6, -21.5), Vector3(2.5, 1.2, 2.5)],
		["CornerSW_PavStep", "cover", Vector3(-26, 0.3, -23.5), Vector3(1.5, 0.6, 1.5)],
		["CornerSW_Box1", "cover", Vector3(-24.15, 0.45, -19.65), Vector3(1.2, 0.9, 1.2)],
		["CornerSW_Tree", "bigtree", Vector3(-23, 1.25, -22), Vector3(0.7, 2.5, 0.7)],
	]
	for spec0 in specs:
		var spec: Array = spec0
		var nm: String = spec[0]
		var ent := _find(V3.OUTER, nm)
		assert_false(ent.is_empty(), "OUTER 含 %s" % nm)
		if ent.is_empty():
			continue
		assert_eq(ent["kind"], spec[1], "%s kind == %s" % [nm, spec[1]])
		var c: Vector3 = ent["center"]
		var s: Vector3 = ent["size"]
		var ec: Vector3 = spec[2]
		var es: Vector3 = spec[3]
		assert_almost_eq(c.x, ec.x, 0.001, "%s center.x == %s" % [nm, ec.x])
		assert_almost_eq(c.y, ec.y, 0.001, "%s center.y == %s" % [nm, ec.y])
		assert_almost_eq(c.z, ec.z, 0.001, "%s center.z == %s" % [nm, ec.z])
		assert_almost_eq(s.x, es.x, 0.001, "%s size.x == %s" % [nm, es.x])
		assert_almost_eq(s.y, es.y, 0.001, "%s size.y == %s" % [nm, es.y])
		assert_almost_eq(s.z, es.z, 0.001, "%s size.z == %s" % [nm, es.z])


# ==== 任务 8：v3 组装 + standable_surfaces + 宏观断言 ====

# 几何指纹键：(round2(center.x), round2(center.z), round2(size.xyz))——round×100 取整
# 消浮点噪声（容差 0.01），int 编码天然归一 -0.0。
func _geo_key(cx: float, cz: float, s: Vector3) -> String:
	return "%d|%d|%d|%d|%d" % [
		roundi(cx * 100.0), roundi(cz * 100.0),
		roundi(s.x * 100.0), roundi(s.y * 100.0), roundi(s.z * 100.0)]


# ---- 51. 全局 180° 旋转对称（宏观）：all_solids() 几何多重集在 (x,z)→(−x,−z) 下不变。
#         对每个实体逐一断言：池中存在某实体（可同名可异名）指纹匹配 (−x,−z,同 size)；
#         旋转是对合，指纹类供需相等时贪心消耗必成功。报出无对应体的实体名+坐标 ----
func test_global_rotation_symmetry() -> void:
	var solids := V3.all_solids()
	var pool := {}  # 指纹 -> 剩余可用计数
	for e0 in solids:
		var e: Dictionary = e0
		var c: Vector3 = e["center"]
		var fp := _geo_key(c.x, c.z, e["size"])
		pool[fp] = int(pool.get(fp, 0)) + 1
	var missing := []
	for e0 in solids:
		var e: Dictionary = e0
		var c: Vector3 = e["center"]
		var s: Vector3 = e["size"]
		var want := _geo_key(-c.x, -c.z, s)
		if int(pool.get(want, 0)) <= 0:
			missing.append("%s center=(%.3f,%.3f,%.3f) size=(%.3f,%.3f,%.3f) 无 (−x,−z) 对应体" % [
				e["name"], c.x, c.y, c.z, s.x, s.y, s.z])
		else:
			pool[want] = int(pool[want]) - 1
	assert_true(missing.is_empty(),
		"全局旋转对称破缺（%d 实体无对应）:\n%s" % [missing.size(), "\n".join(missing)])


# ---- 52. standable 面顶高档：全部 top_y ∈ {0.6, 1.2, 2.5, 3.0}（容差 0.001）----
func test_standable_tops() -> void:
	var allowed := [0.6, 1.2, 2.5, 3.0]
	for s0 in V3.standable_surfaces():
		var s: Dictionary = s0
		var ok := false
		for a0 in allowed:
			if absf(float(s["top_y"]) - float(a0)) <= 0.001:
				ok = true
				break
		assert_true(ok, "%s top_y=%s ∈ {0.6, 1.2, 2.5, 3.0}" % [s["name"], s["top_y"]])


# ---- 53. standable 面 name 在 all_solids() 中有同名实体（别名显式映射：
#         Corridor→CorridorSlab、Altar→AltarPlatform，西/东望楼即台体本名）；
#         且该实体顶面 == 面 top_y ----
func test_standable_names_exist() -> void:
	var alias := {"Corridor": "CorridorSlab", "Altar": "AltarPlatform"}
	var solids := V3.all_solids()
	var surfaces := V3.standable_surfaces()
	assert_eq(surfaces.size(), 14, "standable_surfaces() 共 14 面（前置）")
	for s0 in surfaces:
		var s: Dictionary = s0
		var nm: String = s["name"]
		var ent_name: String = alias.get(nm, nm)
		var ent := _find(solids, ent_name)
		assert_false(ent.is_empty(),
			"standable 面 %s 在 all_solids() 有实体 %s" % [nm, ent_name])
		if ent.is_empty():
			continue
		var top: float = (ent["center"] as Vector3).y + (ent["size"] as Vector3).y * 0.5
		assert_almost_eq(top, float(s["top_y"]), 0.001,
			"%s 实体顶面 == 面 top_y %s" % [ent_name, s["top_y"]])
		# A6（T8 审查 Minor 补强）：面 center.x/z 与实体 center.x/z 一致
		# （面 center.y == top_y 已在测试 4 断言，此处只校 x/z 防平移漂移）
		var sc: Vector3 = s["center"]
		var ec: Vector3 = ent["center"]
		assert_almost_eq(sc.x, ec.x, 0.001, "%s 面 center.x == 实体 center.x" % ent_name)
		assert_almost_eq(sc.z, ec.z, 0.001, "%s 面 center.z == 实体 center.z" % ent_name)


# ---- 54. 实体预算（2026-08-11 裁决）：all_solids() ≤ 220 ----
func test_entity_budget() -> void:
	assert_lte(V3.all_solids().size(), 220,
		"all_solids() 实体数 ≤ 220（2026-08-11 裁决预算）")


# ---- 55. 手雷遮挡物覆盖：遮挡物 = size.y ≥ 2.2−0.01 的实体，数量 ≥8；
#         7 探针点各在 GRENADE_RADIUS+0.5 半径内 ≥1 遮挡物（探针→实体 center 欧氏距离）----
func test_grenade_blockers() -> void:
	var blockers := []
	for e0 in V3.all_solids():
		var e: Dictionary = e0
		if (e["size"] as Vector3).y >= 2.2 - 0.01:
			blockers.append(e)
	assert_gte(blockers.size(), 8, "遮挡物（size.y ≥ 2.19）数量 ≥ 8")
	var probes := [
		Vector3(0, 0, 0), Vector3(0, 0, 11.5), Vector3(0, 0, -11.5),
		Vector3(18.5, 0, 0), Vector3(-18.5, 0, 0),
		Vector3(0, 0, 21.5), Vector3(0, 0, -21.5),
	]
	var radius: float = V3.GRENADE_RADIUS + 0.5
	for p0 in probes:
		var p: Vector3 = p0
		var near := 0
		for b0 in blockers:
			var b: Dictionary = b0
			if p.distance_to(b["center"] as Vector3) <= radius:
				near += 1
		assert_gte(near, 1,
			"探针点 %s 半径 %.2f 内 ≥1 遮挡物（center 距离）" % [p, radius])


# ---- 57. 全图无重叠（任务 9 C）：all_solids() 全对（~18k 对）AABB 无重叠。
#         豁免清单（精确列出，不得扩大）：
#         a) 垂直相接（顶==底 ±0.01，_v_touch）——面/边接触由 _overlap eps 处理不算重叠
#         b) bigtree×wall 成对（铁律"大树只许叠墙"，收窄口径与测试 48/T7 一致）----
func test_full_map_no_overlap() -> void:
	var solids := V3.all_solids()  # 提到循环外（裁决：避免 N 次拼装）
	for i in range(solids.size()):
		var a: Dictionary = solids[i]
		var ba := _aabb(a)
		for j in range(i + 1, solids.size()):
			var b: Dictionary = solids[j]
			var bb := _aabb(b)
			var bigtree_exempt: bool = (a["kind"] == "bigtree" and b["kind"] == "wall") \
				or (a["kind"] == "wall" and b["kind"] == "bigtree")
			assert_true((not _overlap(ba, bb)) or _v_touch(ba, bb) or bigtree_exempt,
				"%s vs %s: AABB 重叠（非垂直相接/bigtree×wall 豁免）" % [a["name"], b["name"]])


# ---- 56. all_solids() 全部 name 唯一（为 T9/WaveSpawner/记录器引用安全预埋）----
func test_no_duplicate_names() -> void:
	var seen := {}
	var dups := []
	for e0 in V3.all_solids():
		var nm: String = (e0 as Dictionary)["name"]
		if seen.has(nm):
			dups.append(nm)
		seen[nm] = true
	assert_true(dups.is_empty(), "all_solids() 存在重名实体: %s" % ", ".join(dups))
