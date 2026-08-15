# tools/probe_navmesh.gd — 阶段4：navmesh 验证门禁（2026-08-13）
# 用法：godot --headless --path . -s tools/probe_navmesh.gd
# 验证：
#   ① 关键地面/可达面点全部有导航路径（出生点/弹药箱/祭坛台/回廊/塔顶/摊阁/围墙顶/
#      长墙顶/横脊墙顶——含 28 处跳跃链接的链式可达）
#   ② 不可达面（伞顶/门梁/市集高棚）路径查询必失败（防穿墙）
#   ③ 网格质量：多边形数 >0、顶点数 >0
#   ④ 坡道台阶区导航梯度（2026-08-15 方案 A 门禁，T-nav-ext 扩至四坡道，见下）
extends SceneTree

const LAYOUT := preload("res://Levels/M2_TDM/map_layout_v3.gd")
const BAKE := preload("res://tools/bake_navmesh.gd")
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
	# link 端点 snap 到导航面（端点悬空 → 整条 link 被丢弃，links:0 根因）
	var link_map := root.get_world_3d().navigation_map
	for c in root.get_children():
		if c is NavigationLink3D:
			var lk := c as NavigationLink3D
			lk.start_position = NavigationServer3D.map_get_closest_point(link_map, lk.start_position)
			lk.end_position = NavigationServer3D.map_get_closest_point(link_map, lk.end_position)
	for i in 5:
		await physics_frame  # link 重定位后再同步

	var spawn := LAYOUT.player_spawn()
	# ① 关键点可达性（跳跃链接链式可达含高墙顶；目标 y = 导航面高度 = 表面+0.4，
	# 且避开实体投影区——2026-08-13 实测修正：塔顶箱下/坡道上的目标会投影到错误面）
	var targets := [
		["出生点", spawn],
		["祭坛台", Vector3(5.0, 0.6, 3.0)],
		["钟楼回廊", Vector3(0, 3.0, 2.5)],
		["西望楼顶", Vector3(-18.5, 2.5, 1.2)],
		["西塔顶箱", Vector3(-18.5, 3.4, 0)],
		["西摊阁", Vector3(-18.5, 1.2, -10)],
		["西簇板顶", Vector3(-18.5, 2.2, -5)],
		["西rim围墙顶", Vector3(-14, 3.0, -6)],
		["西横脊墙顶", Vector3(-16, 3.0, -7.1)],
		["西长墙顶", Vector3(-23, 3.0, 0)],
		["北钟门翼墙顶", Vector3(-9.5, 3.0, 14)],
		["东望楼顶", Vector3(18.5, 2.5, -1.2)],
		["北外环街", Vector3(27, 0, 17.5)],
		["南营前场", Vector3(0, 0, -19)],
		["北钟门门梁顶", Vector3(0, 4.9, 14.5)],
		["北市集高棚顶", Vector3(3, 4.9, 10.75)],
		["东长墙顶", Vector3(23, 3.0, -1.5)],
		["东rim围墙顶", Vector3(14, 3.0, 3.2)],
	]
	for t in targets:
		var from: Vector3 = NavigationServer3D.map_get_closest_point(map_rid, spawn)
		var to: Vector3 = NavigationServer3D.map_get_closest_point(map_rid, t[1])
		# 先验：目标点本身必须在导航面上（closest 距原始目标 <0.8——防"closest 落到邻近面"
		# 的假阳性，2026-08-13 加固）；再验路径终点到达 to。
		if to.distance_to(t[1]) > 0.8:
			fails += 1
			print("FAIL 目标面无导航面: %-14s %s（closest 距 %.2fm）" % [t[0], t[1], to.distance_to(t[1])])
			continue
		var path: PackedVector3Array = NavigationServer3D.map_get_path(map_rid, from, to, true)
		var ok := path.size() >= 2 and path[path.size() - 1].distance_to(to) < 0.8
		if not ok:
			fails += 1
			print("FAIL 不可达: %-14s %s（路径终点 %s）" % [t[0], t[1], path[path.size() - 1] if path.size() > 0 else "-"])
		else:
			print("ok    %-14s 路径 %d 段" % [t[0], path.size() - 1])
	# ② 不可达面必失败（伞顶——门梁/高棚已被用户新开发跳跃点验证可达，2026-08-13 移出此表）
	var impossible := [
		["伞顶", Vector3(0, 7.5, 2.75)],
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
	# ④ 坡道台阶区导航梯度（2026-08-15 方案 A 门禁，T-nav-ext 扩至四坡道）：沿每条
	#   坡道中心线 x=(x0+x1)/2 采样列 = 坡脚缝 z=z0（期望 0.4+y0）+ steps 个台阶槽中点
	#   z_i=z0+(z1-z0)*(i+0.5)/steps（期望 0.4+y0+(y1-y0)*(i+1)/steps），每列双查容差 0.35：
	#   A. 查询 y=期望：|导航 y − 期望| ≤ 0.35（目标高度处有面）；
	#   B. 查询 y=期望+1.0（自上而下）：导航 y − 期望 ≤ 0.35（无悬空面压顶）。
	#   实测旧缺陷 navmesh：塔坡脚上方挂倾斜多边形（西塔 z=8.2 差 +0.42，A 判失败）；
	#   槽区另有悬空面族（东塔 z≈-7.4 挂 1.40 vs 物理 0.32 → 差 +0.5，B 判失败——
	#   单用 A 判会被邻近低位面掩蔽，实测必需 B 判）；祭坛坡道同款缺陷（面高差可达
	#   1.11，RampE 弹出楔死根因）。斜坡替身后梯度差 ≤0.125。
	var ramp_fail := 0
	var ramp_cols := 0
	for s in BAKE.RAMP_SLOPES:
		var x: float = (s["x0"] + s["x1"]) * 0.5
		var steps: int = s["steps"]
		var foot_expected: float = 0.4 + s["y0"]
		var cols := [{"z": s["z0"], "expected": foot_expected}]
		for i in steps:
			cols.append({
				"z": s["z0"] + (s["z1"] - s["z0"]) * (float(i) + 0.5) / float(steps),
				"expected": foot_expected + (s["y1"] - s["y0"]) * float(i + 1) / float(steps),
			})
		for c in cols:
			ramp_cols += 1
			var p_lo: Vector3 = NavigationServer3D.map_get_closest_point(map_rid, Vector3(x, c["expected"], c["z"]))
			var p_hi: Vector3 = NavigationServer3D.map_get_closest_point(map_rid, Vector3(x, c["expected"] + 1.0, c["z"]))
			var fail_a: bool = absf(p_lo.y - c["expected"]) > 0.35
			var fail_b: bool = p_hi.y - c["expected"] > 0.35
			if fail_a or fail_b:
				ramp_fail += 1
				fails += 1
				print("FAIL 坡道梯度 x=%.2f z=%+.2f 期望 %.2f：低查 y=%.2f 差 %+.2f%s；高查 y=%.2f 差 %+.2f%s" % [
					x, c["z"], c["expected"], p_lo.y, p_lo.y - c["expected"], "（超）" if fail_a else "",
					p_hi.y, p_hi.y - c["expected"], "（超）" if fail_b else ""])
	if ramp_fail == 0:
		print("ok    坡道梯度 四坡道 %d 列 %d 判定全过（坡脚缝 + 台阶槽 × 低/高双查，容差 0.35）" % [ramp_cols, ramp_cols * 2])
	else:
		print("坡道梯度失败列 %d/%d" % [ramp_fail, ramp_cols])
	print("---")
	print("navmesh 门禁: %s" % ("FAIL %d 项" % fails if fails > 0 else "全过"))
	quit(1 if fails > 0 else 0)
