# test/unit/test_minimap_core.gd
# M2 小地图核心测试（TDD RED 先行）：投影变换/矩形保形/范围剔除/线段-圆裁剪/确定性
extends GutTest

var core: MinimapCore
const SCALE := 90.0 / 12.0  # 7.5 px/m（radius_px/radius_m）


func before_each() -> void:
	core = MinimapCore.new()


func _wall(center: Vector3, size: Vector3, kind: String = "wall") -> Dictionary:
	return {"name": "W", "kind": kind, "center": center, "size": size}


# ================= 1. 投影变换 =================
func test_forward_point_projects_to_map_up() -> void:
	var ents: Array = [{"pos": Vector3(0, 0, -10), "is_enemy": true}]
	core.project(Vector3.ZERO, Vector3(0, 0, -1), [], ents)
	assert_eq(core.markers.size(), 1, "正前 10m 在 12m 半径内")
	assert_almost_eq(core.markers[0]["pos"].x, 0.0, 0.001, "正前方 x=0")
	assert_almost_eq(core.markers[0]["pos"].y, 10.0 * SCALE, 0.001, "正前方 → 地图上方 +75px")


func test_right_point_projects_to_map_right() -> void:
	var ents: Array = [{"pos": Vector3(10, 0, 0), "is_enemy": false}]
	core.project(Vector3.ZERO, Vector3(0, 0, -1), [], ents)
	assert_almost_eq(core.markers[0]["pos"].x, 10.0 * SCALE, 0.001, "右侧 → 地图 +X")
	assert_almost_eq(core.markers[0]["pos"].y, 0.0, 0.001, "右侧 y=0")


func test_yaw_rotation_keeps_forward_up() -> void:
	# yaw=π/2（面朝 -X）：世界 -Z 点是玩家右侧 → 地图 +X
	var ents: Array = [{"pos": Vector3(0, 0, -10), "is_enemy": true}]
	core.project(Vector3.ZERO, Vector3(-1, 0, 0), [], ents)
	assert_almost_eq(core.markers[0]["pos"].x, 10.0 * SCALE, 0.001, "面朝 -X 时世界 -Z → 地图 +X（右侧）")
	assert_almost_eq(core.markers[0]["pos"].y, 0.0, 0.001, "y=0")


# ================= 2. 矩形投影保形 =================
func test_rect_corners_preserve_shape() -> void:
	var solids: Array = [_wall(Vector3(0, 1, -4), Vector3(4, 2, 1))]
	core.project(Vector3.ZERO, Vector3(0, 0, -1), solids, [])
	assert_eq(core.segments.size(), 4, "矩形 4 条边")
	var xs := {}
	var ys := {}
	for s in core.segments:
		for p in [s["a"], s["b"]]:
			xs[p.x] = true
			ys[p.y] = true
	assert_eq(xs.size(), 2, "x 端点为 2 个值（±2m×7.5=±15px）")
	assert_eq(ys.size(), 2, "y 端点为 2 个值（z∈[−4.5,−3.5]→[26.25,33.75]px）")
	var sorted_x: Array = xs.keys()
	sorted_x.sort()
	assert_almost_eq(sorted_x[1] - sorted_x[0], 4.0 * SCALE, 0.001, "宽度保形 30px")
	var sorted_y: Array = ys.keys()
	sorted_y.sort()
	assert_almost_eq(sorted_y[1] - sorted_y[0], 1.0 * SCALE, 0.001, "深度保形 7.5px")


# ================= 3. 范围剔除 =================
func test_far_solid_and_marker_culled() -> void:
	var solids: Array = [_wall(Vector3(0, 1, -50), Vector3(2, 2, 2))]
	var ents: Array = [{"pos": Vector3(0, 0, -15), "is_enemy": true}]
	core.project(Vector3.ZERO, Vector3(0, 0, -1), solids, ents)
	assert_eq(core.segments.size(), 0, "50m 外实体剔除")
	assert_eq(core.markers.size(), 0, "15m > 12m 标志剔除")


func test_near_edge_kept() -> void:
	var ents: Array = [{"pos": Vector3(0, 0, -11.9), "is_enemy": true}]
	core.project(Vector3.ZERO, Vector3(0, 0, -1), [], ents)
	assert_eq(core.markers.size(), 1, "11.9m 在 12m 内保留")


# ================= 4. 线段-圆裁剪 =================
func test_spanning_wall_clipped_to_circle() -> void:
	# 贯穿地图的大墙：可见段端点恰在圆上
	var solids: Array = [_wall(Vector3(0, 1, 0), Vector3(40, 1, 40))]
	core.project(Vector3.ZERO, Vector3(0, 0, -1), solids, [])
	assert_gt(core.segments.size(), 0, "有可见段")
	for s in core.segments:
		for p in [s["a"], s["b"]]:
			assert_between(p.length(), core.radius_px - 0.5, core.radius_px + 0.5,
					"裁剪端点落在圆上（±0.5px 容差）")


func test_ground_kind_skipped() -> void:
	var solids: Array = [_wall(Vector3(0, -0.5, 0), Vector3(60, 1, 58), "ground")]
	core.project(Vector3.ZERO, Vector3(0, 0, -1), solids, [])
	assert_eq(core.segments.size(), 0, "ground 不投影")


# ================= 5. 确定性 =================
func test_deterministic_same_input_same_output() -> void:
	var solids: Array = [_wall(Vector3(0, 1, -4), Vector3(4, 2, 1)), _wall(Vector3(3, 1, 2), Vector3(2, 3, 2))]
	var ents: Array = [{"pos": Vector3(0, 0, -4), "is_enemy": true}]
	core.project(Vector3.ZERO, Vector3(0, 0, -1), solids, ents)
	var seg_a: Array = core.segments.duplicate()
	var mk_a: Array = core.markers.duplicate()
	core.project(Vector3.ZERO, Vector3(0, 0, -1), solids, ents)
	assert_eq(core.segments.size(), seg_a.size(), "段数一致")
	assert_eq(core.markers.size(), mk_a.size(), "标志数一致")
