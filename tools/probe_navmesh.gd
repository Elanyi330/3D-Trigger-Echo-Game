# tools/probe_navmesh.gd — 阶段4：navmesh 验证门禁（2026-08-13）
# 用法：godot --headless --path . -s tools/probe_navmesh.gd
# 验证：
#   ① 关键地面/可达面点全部有导航路径（出生点/弹药箱/祭坛台/回廊/塔顶/摊阁/围墙顶/
#      长墙顶/横脊墙顶——含 28 处跳跃链接的链式可达）
#   ② 不可达面（伞顶/门梁/市集高棚）路径查询必失败（防穿墙）
#   ③ 网格质量：多边形数 >0、顶点数 >0
extends SceneTree

const LAYOUT := preload("res://Levels/M2_TDM/map_layout_v3.gd")
const NAV_PATH := "res://Levels/M2_TDM/navmesh.res"


func _init() -> void:
	var fails := 0
	var nav: NavigationMesh = load(NAV_PATH)
	if nav == null:
		print("FAIL navmesh.res 未找到（先跑 bake_navmesh.gd）")
		quit(1)
		return
	print("网格: %d 多边形 / %d 顶点" % [nav.get_polygon_count(), nav.get_vertices().size()])
	if nav.get_polygon_count() <= 0:
		fails += 1
		print("FAIL 空网格")
	# 注册地图 + 链接
	var map_rid := get_root().get_world_3d().navigation_map
	var region := NavigationRegion3D.new()
	region.navigation_mesh = nav
	root.add_child(region)
	for l0 in LAYOUT.jump_links():
		var l: Dictionary = l0
		var link := NavigationLink3D.new()
		link.start_position = l["from"]
		link.end_position = l["to"]
		link.bidirectional = true
		root.add_child(link)
	for i in 10:
		await physics_frame  # 导航网格同步发生在物理帧（process_frame 不够——实测路径空）

	var spawn := LAYOUT.player_spawn()
	# ① 关键点可达性（跳跃链接链式可达含高墙顶）
	var targets := [
		["出生点", spawn],
		["祭坛台", Vector3(5.0, 0.6, 0.0)],
		["钟楼回廊", Vector3(0, 3.0, 2.5)],
		["西望楼顶", Vector3(-18.5, 2.5, 0)],
		["西塔顶箱", Vector3(-18.5, 3.4, 0)],
		["西摊阁", Vector3(-18.5, 1.2, -10)],
		["西簇板顶", Vector3(-18.5, 2.2, -5)],
		["西rim围墙顶", Vector3(-14, 3.0, -6)],
		["西横脊墙顶", Vector3(-16, 3.0, -7.1)],
		["西长墙顶", Vector3(-23, 3.0, 0)],
		["北钟门翼墙顶", Vector3(-9.5, 3.0, 14)],
		["东望楼顶", Vector3(18.5, 2.5, 0)],
		["北外环街", Vector3(27, 0, 17.5)],
		["南营前场", Vector3(0, 0, -19)],
	]
	for t in targets:
		var from: Vector3 = NavigationServer3D.map_get_closest_point(map_rid, spawn)
		var to: Vector3 = NavigationServer3D.map_get_closest_point(map_rid, t[1])
		var path: PackedVector3Array = NavigationServer3D.map_get_path(map_rid, from, to, true)
		# 可达判定 = 路径终点落在目标 0.8m 内（map_get_path 对不可达目标返回部分路径，
		# 终点停在最近可达点——段数不可作依据，2026-08-13 实测修正）
		var ok := path.size() >= 2 and path[path.size() - 1].distance_to(to) < 0.8
		if not ok:
			fails += 1
			print("FAIL 不可达: %-14s %s（路径终点 %s）" % [t[0], t[1], path[path.size() - 1] if path.size() > 0 else "-"])
		else:
			print("ok    %-14s 路径 %d 段" % [t[0], path.size() - 1])
	# ② 不可达面必失败（伞顶/门梁/高棚——烘焙会生成孤立导航面，但 AI 必须找不到路径）
	var impossible := [
		["伞顶", Vector3(0, 7.5, 2.75)],
		["钟门过梁", Vector3(0, 4.9, 14.5)],
		["市集高棚", Vector3(3, 4.9, 10.75)],
	]
	for t in impossible:
		var closest: Vector3 = NavigationServer3D.map_get_closest_point(map_rid, t[1])
		var from: Vector3 = NavigationServer3D.map_get_closest_point(map_rid, spawn)
		var path: PackedVector3Array = NavigationServer3D.map_get_path(map_rid, from, closest, true)
		# 不可达判定 = 路径终点未达目标 0.8m 内（部分路径的终点会停在最近可达点）
		var reached := path.size() >= 2 and path[path.size() - 1].distance_to(closest) < 0.8
		if reached:
			fails += 1
			print("FAIL 不应可达: %s（路径终点距目标 %.2fm）" % [t[0], path[path.size() - 1].distance_to(closest)])
		else:
			print("ok    %-14s 无路径可达（AI 到不了）" % t[0])
	print("---")
	print("navmesh 门禁: %s" % ("FAIL %d 项" % fails if fails > 0 else "全过"))
	quit(1 if fails > 0 else 0)
