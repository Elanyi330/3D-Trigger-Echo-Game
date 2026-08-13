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
	nav.agent_radius = 0.25  # 2026-08-13 实测：0.3 侵蚀 2cell=0.5m/侧吃光 1m 墙顶；0.25 侵蚀
	                        # 1cell=0.25m/侧，1m 墙顶保 0.5m。游戏窄缝红线 1.2m 保证 AI 胶囊
	                        # 直径 0.62 在 0.7m 导航通道仍可通过。
	nav.agent_max_climb = 0.62
	nav.agent_max_slope = 45.0
	nav.cell_size = 0.25
	nav.cell_height = 0.2
	var geom := NavigationMeshSourceGeometryData3D.new()
	for e0 in LAYOUT.all_solids():
		var e: Dictionary = e0
		if e["kind"] == "decor":
			continue  # 钟饰无碰撞
		# 任一水平边 <1.2 的实体（簇板/斜板/微台阶/箱类）该边放大至 1.2（仅烘焙几何，
		# 游戏几何不动）：agent_radius 0.25 侵蚀后 1.2-0.5=0.7m 顶面可烘出。
		# Rail 栏板类跳过——放大会覆盖回廊面边缘（2026-08-13 实测破坏回廊导航面）；
		# 栏板顶 0.2m 本来站不了人，无导航需求。
		var bs: Vector3 = e["size"]
		if str(e["name"]).contains("Rail"):
			pass
		else:
			if bs.x < 1.2:
				bs.x = 1.2
			if bs.z < 1.2:
				bs.z = 1.2
		var bm := BoxMesh.new()
		bm.size = bs
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
