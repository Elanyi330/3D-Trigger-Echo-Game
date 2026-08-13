# tools/bake_navmesh.gd — 阶段2：navmesh 烘焙（2026-08-13）
# 用法：godot --headless --path . -s tools/bake_navmesh.gd
# 从布局数据（193 实体）生成 BoxMesh 几何 → NavigationServer 烘焙 → 保存
# Levels/M2_TDM/navmesh.res。参数（方案拍板）：
#   agent_radius 0.3（AI 胶囊 0.31）/ agent_max_climb 0.62（step-up 拍板值——
#   0.6m 台面自动连通）/ cell 0.25。
# 地图布局变更后必须重新烘焙（与跳跃记录同源的"几何稳定"前提）。
extends SceneTree

const LAYOUT := preload("res://Levels/M2_TDM/map_layout_v3.gd")
const OUT_PATH := "res://Levels/M2_TDM/navmesh.res"


func _init() -> void:
	var nav := NavigationMesh.new()
	nav.agent_radius = 0.3
	nav.agent_max_climb = 0.62
	nav.agent_max_slope = 45.0
	nav.cell_size = 0.25
	nav.cell_height = 0.2
	var geom := NavigationMeshSourceGeometryData3D.new()
	for e0 in LAYOUT.all_solids():
		var e: Dictionary = e0
		if e["kind"] == "decor":
			continue  # 钟饰无碰撞
		var bm := BoxMesh.new()
		bm.size = e["size"]
		geom.add_mesh(bm, Transform3D(Basis(), e["center"]))
	# 烘焙（callback 异步 + 轮询多边形产出；5s 超时防御）
	var done := [false]
	NavigationServer3D.bake_from_source_geometry_data(nav, geom, func() -> void:
		done[0] = true)
	var t := 0
	while not done[0] and t < 500:
		await process_frame
		t += 1
	if not done[0]:
		push_error("烘焙超时")
		quit(1)
		return
	print("多边形数: %d, 顶点数: %d" % [nav.get_polygon_count(), nav.get_vertices().size()])
	var err: Error = ResourceSaver.save(nav, OUT_PATH)
	print("保存 %s err=%s" % [OUT_PATH, error_string(err)])
	quit(0 if err == OK else 1)
