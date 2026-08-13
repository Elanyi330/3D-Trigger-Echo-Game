# test/unit/test_minimap.gd
# M2 小地图渲染胶水测试：装配/投影烟测/标志传递
extends GutTest


func test_minimap_setup_and_projection_smoke() -> void:
	var m := Minimap.new()
	add_child_autofree(m)
	var player := Node3D.new()
	add_child_autofree(player)
	var solids: Array = [{"name": "TestWall", "kind": "wall", "center": Vector3(0, 1, -4), "size": Vector3(4, 2, 1)}]
	var ents: Array = []
	m.setup(solids, player, func() -> Array: return ents)
	await wait_physics_frames(1)
	assert_gt(m._core.segments.size(), 0, "投影产出 ≥1 段")
	assert_eq(m._core.markers.size(), 0, "无实体标志")
	ents.append({"pos": Vector3(0, 0, -4), "is_enemy": true})
	await wait_physics_frames(1)
	assert_eq(m._core.markers.size(), 1, "敌人标志出现")
	assert_true(m._core.markers[0]["is_enemy"], "is_enemy 传递")
	assert_eq(m.mouse_filter, Control.MOUSE_FILTER_IGNORE, "不拦截鼠标（HUD）")
