# test/unit/test_spawn_exclusions.gd
# 任务 12（TDD GREEN）：map_layout_v3.spawn_exclusions() 敌人撒点排除区断言。
#
# spawn_exclusions() 为 WaveSpawner 的拒绝采样提供数据：面 name → 排除矩形列表
# {"x_min","x_max","z_min","z_max"}（世界坐标 XZ 投影）。三条断言：
#   ① Altar/Corridor 键存在且矩形非空
#   ② 每个矩形在所属面（standable_surfaces()）的 x/z 范围内（撒点只在面内采样）
#   ③ Pedestal 投影矩形 == [-2,2]×[-2,2]
extends GutTest

const V3 := preload("res://Levels/M2_TDM/map_layout_v3.gd")

const EPS := 0.001


func _surface_by_name(n: String) -> Dictionary:
	for s0 in V3.standable_surfaces():
		var s: Dictionary = s0
		if s["name"] == n:
			return s
	return {}


# ---- ① Altar/Corridor 键存在且矩形非空 ----
func test_exclusion_keys_exist() -> void:
	var ex: Dictionary = V3.spawn_exclusions()
	assert_true(ex.has("Altar"), "spawn_exclusions() 应含 Altar 键")
	assert_true(ex.has("Corridor"), "spawn_exclusions() 应含 Corridor 键")
	if ex.has("Altar"):
		assert_gt(int((ex["Altar"] as Array).size()), 0, "Altar 排除矩形应非空")
	if ex.has("Corridor"):
		assert_gt(int((ex["Corridor"] as Array).size()), 0, "Corridor 排除矩形应非空")


# ---- ② 每个矩形在所属面的 x/z 范围内（且自身良构：min < max）----
func test_rects_within_face_bounds() -> void:
	var ex: Dictionary = V3.spawn_exclusions()
	for face_key in ex:
		var face_name: String = str(face_key)
		var surf := _surface_by_name(face_name)
		assert_false(surf.is_empty(), "排除面 %s 应存在于 standable_surfaces()" % face_name)
		if surf.is_empty():
			continue
		var c: Vector3 = surf["center"]
		var sz: Vector3 = surf["size"]
		var x_lo: float = c.x - sz.x * 0.5
		var x_hi: float = c.x + sz.x * 0.5
		var z_lo: float = c.z - sz.z * 0.5
		var z_hi: float = c.z + sz.z * 0.5
		for r0 in ex[face_key]:
			var r: Dictionary = r0
			var tag: String = "面 %s 矩形 %s" % [face_name, str(r)]
			assert_lt(float(r["x_min"]), float(r["x_max"]), tag + " 应 x_min < x_max")
			assert_lt(float(r["z_min"]), float(r["z_max"]), tag + " 应 z_min < z_max")
			assert_gte(float(r["x_min"]), x_lo - EPS, tag + " x_min ≥ 面 x 下界")
			assert_lte(float(r["x_max"]), x_hi + EPS, tag + " x_max ≤ 面 x 上界")
			assert_gte(float(r["z_min"]), z_lo - EPS, tag + " z_min ≥ 面 z 下界")
			assert_lte(float(r["z_max"]), z_hi + EPS, tag + " z_max ≤ 面 z 上界")


# ---- ③ Pedestal 投影矩形 == [-2,2]×[-2,2]（基座 4×4）----
func test_pedestal_rect_exact() -> void:
	var ex: Dictionary = V3.spawn_exclusions()
	assert_true(ex.has("Altar"), "前置：Altar 键存在")
	if not ex.has("Altar"):
		return
	var found := false
	for r0 in ex["Altar"]:
		var r: Dictionary = r0
		if absf(float(r["x_min"]) - (-2.0)) <= EPS and absf(float(r["x_max"]) - 2.0) <= EPS \
				and absf(float(r["z_min"]) - (-2.0)) <= EPS and absf(float(r["z_max"]) - 2.0) <= EPS:
			found = true
			break
	assert_true(found, "Altar 排除表应含 Pedestal 投影矩形 [-2,2]×[-2,2]")
