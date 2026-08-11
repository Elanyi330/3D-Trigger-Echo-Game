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


# ---- 2. all_solids(): Ground + 4 面边界墙，当前共 5 项 ----
func test_all_solids_has_ground_and_walls() -> void:
	var solids := V3.all_solids()
	assert_eq(solids.size(), 5, "当前 all_solids() 总数 == 5（Ground + 4 边界墙）")
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
