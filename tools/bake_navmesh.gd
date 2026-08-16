# tools/bake_navmesh.gd — 阶段2：navmesh 烘焙（2026-08-13；2026-08-15 方案 A 塔坡道替身）
# 用法：godot --headless --path . -s tools/bake_navmesh.gd
# 从布局数据（193 实体）生成 BoxMesh 几何 → NavigationServer 烘焙 → 保存
# Levels/M2_TDM/navmesh.res。参数（方案拍板）：
#   agent_radius 0.3（AI 胶囊 0.31）/ agent_max_climb 0.62（step-up 拍板值——
#   0.6m 台面自动连通）/ cell 0.25。
# 地图布局变更后必须重新烘焙（与跳跃记录同源的"几何稳定"前提）。
extends SceneTree

const LAYOUT := preload("res://Levels/M2_TDM/map_layout_v3.gd")
const OUT_PATH := "res://Levels/M2_TDM/navmesh.res"

# 坡道烘焙替身（2026-08-15 用户拍板方案 A；T-nav-ext 扩至四坡道）：台阶整高盒烘焙
# 几何互相重叠（窄边放大 1.2 后相邻盒叠加）把台阶顶面埋掉 → 烘焙出斜跨悬空多边形
# （塔坡道 poly 637 实锤；祭坛坡道 RampE/RampW 同款缺陷，导航面差可达 1.11——冒烟
# CorridorSlab 的 RampE 弹出楔死根因）。替身=真斜坡平面（物理台阶经 step-up
# 0.25/0.3≤0.62 可走，导航面表达为斜坡是物理语义的忠实近似）。
# 参数与 map_layout_v3.gd _ramp_steps 调用逐字同步（勿改布局，仅此处烘焙替身）：
#   塔坡道 L164-165 / 祭坛坡道 L100-101；steps = 各级数（供自检断言与 ④ 门禁采样）。
const RAMP_SLOPES := [
	{"x0": -21.0, "x1": -18.5, "z0": 8.2, "z1": 2.0, "y0": 0.0, "y1": 2.5, "steps": 10},
	{"x0": 18.5, "x1": 21.0, "z0": -8.2, "z1": -2.0, "y0": 0.0, "y1": 2.5, "steps": 10},
	{"x0": 3.6, "x1": 6.6, "z0": -3.5, "z1": 2.5, "y0": 0.6, "y1": 3.0, "steps": 8, "side_plates": true},
	{"x0": -6.6, "x1": -3.6, "z0": 3.5, "z1": -2.5, "y0": 0.6, "y1": 3.0, "steps": 8, "side_plates": true},
]
# 与 RAMP_SLOPES 顺序对应的台阶实体名前缀（all_solids 实测命名：
# West/EastTowerRampStep1..10、RampE/RampWStep1..8，精确到 "Step" 防误伤）。
const RAMP_STEP_PREFIXES := ["WestTowerRampStep", "EastTowerRampStep", "RampEStep", "RampWStep"]


func _init() -> void:
	# 运行时自检断言（布局参数变更时烘焙立即报错而非静默漂移）：四组坡道前缀台阶
	# 实体各恰 steps 个，且实体包围盒 x/z 范围与 RAMP_SLOPES 参数吻合（±0.01）。
	var ramp_groups := {}
	for e0 in LAYOUT.all_solids():
		var nm0: String = e0["name"]
		for p in RAMP_STEP_PREFIXES:
			if nm0.begins_with(p):
				if not ramp_groups.has(p):
					ramp_groups[p] = []
				ramp_groups[p].append(e0)
	for i in RAMP_SLOPES.size():
		var s: Dictionary = RAMP_SLOPES[i]
		var p: String = RAMP_STEP_PREFIXES[i]
		var ents: Array = ramp_groups.get(p, [])
		assert(ents.size() == s["steps"], "坡道烘焙自检：%s 前缀实体 %d 个 != %d（布局已变，先同步 RAMP_SLOPES）" % [p, ents.size(), s["steps"]])
		var mn := Vector3(INF, INF, INF)
		var mx := Vector3(-INF, -INF, -INF)
		for e0 in ents:
			var c: Vector3 = e0["center"]
			var h: Vector3 = e0["size"] * 0.5
			mn = mn.min(c - h)
			mx = mx.max(c + h)
		var lo_x := minf(s["x0"], s["x1"])
		var hi_x := maxf(s["x0"], s["x1"])
		var lo_z := minf(s["z0"], s["z1"])
		var hi_z := maxf(s["z0"], s["z1"])
		assert(absf(mn.x - lo_x) <= 0.01 and absf(mx.x - hi_x) <= 0.01, "坡道烘焙自检：%s 实体 x 范围 [%.2f,%.2f] 与替身 [%.2f,%.2f] 不符" % [p, mn.x, mx.x, lo_x, hi_x])
		assert(absf(mn.z - lo_z) <= 0.01 and absf(mx.z - hi_z) <= 0.01, "坡道烘焙自检：%s 实体 z 范围 [%.2f,%.2f] 与替身 [%.2f,%.2f] 不符" % [p, mn.z, mx.z, lo_z, hi_z])
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
		var nm: String = e["name"]
		var is_ramp_step := false
		for p in RAMP_STEP_PREFIXES:
			if nm.begins_with(p):
				is_ramp_step = true
				break
		# 任一水平边 <1.2 的实体（簇板/斜板/微台阶/箱类）该边放大至 1.2（仅烘焙几何，
		# 游戏几何不动）：agent_radius 0.25 侵蚀后 1.2-0.5=0.7m 顶面可烘出。
		# Rail 栏板类跳过——放大会覆盖回廊面边缘（2026-08-13 实测破坏回廊导航面）；
		# 栏板顶 0.2m 本来站不了人，无导航需求。
		var bs: Vector3 = e["size"]
		if str(e["name"]).contains("Rail"):
			pass
		elif is_ramp_step:
			# 2026-08-15 方案 A（T-nav-ext 扩至四坡道）：坡道台阶实体跳过烘焙（仅这四组），
			# 台阶区导航面由替身斜坡四边形提供。
			continue
		else:
			if bs.x < 1.2:
				bs.x = 1.2
			if bs.z < 1.2:
				bs.z = 1.2
		var bm := BoxMesh.new()
		bm.size = bs
		geom.add_mesh(bm, Transform3D(Basis(), e["center"]))
	# 坡道替身斜坡四边形（四坡道，SurfaceTool 两三角）。绕序必须每侧都面朝上：
	# Godot 前向=顺时针（叉积 (v2-v0)×(v1-v0) 指向背面），故叉积 y<0 即面朝上。
	# 控制器实验：西塔 [0,2,1][0,3,2] 可烘出；东塔为西塔 180° 镜像几何（z 升序方向
	# 相反），同绕序面朝下 → 烘不出上段；祭坛坡道同为镜像对（RampE 叉积 y>0 翻转、
	# RampW 叉积 y<0 不翻）。此处按叉积自动取向上绕序，四侧都烘出。
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for s in RAMP_SLOPES:
		var v0 := Vector3(s["x0"], s["y0"], s["z0"])
		var v1 := Vector3(s["x1"], s["y0"], s["z0"])
		var v2 := Vector3(s["x1"], s["y1"], s["z1"])
		var v3 := Vector3(s["x0"], s["y1"], s["z1"])
		var vs := [v0, v1, v2, v3]
		var cross_y: float = (v2 - v0).cross(v1 - v0).y
		var tris := [[0, 2, 1], [0, 3, 2]] if cross_y < 0.0 else [[0, 1, 2], [0, 2, 3]]
		print("坡道替身 x0=%+.1f z0=%+.1f 叉积y=%+.2f 绕序 %s" % [s["x0"], s["z0"], cross_y, str(tris)])
		for tri in tris:
			for idx in tri:
				st.set_normal(Vector3.UP)
				st.add_vertex(vs[idx])
	geom.add_mesh(st.commit(), Transform3D())
	# 坡道侧壁板（祭坛坡道两侧，2026-08-15 T-nav-ext 实测）：台阶实体的侧立面封板——
	# 薄片斜坡在坡道 x 侧缘与相邻表面（祭坛平台 0.6）的高差 ≤0.62 时会被寻路当入口穿越
	# （phantom side entry：祭坛坡道实测在 x=6.6 东缘穿入 → 楔入台阶盒东壁 stuck，
	# CorridorSlab 回归）。物理上台阶盒侧立面整面封死、只能从坡脚入——用垂直无顶
	# 四边形封住 x0/x1 两侧（z0..z1、y0..y1；无顶面→不产生步行面，实测薄盒顶面会被
	# 烘成步行面并桥接成新倾斜多边形）。
	# 塔坡道不加（2026-08-16 重试实验裁定回退）：walker 侧进化后重试仍复现
	# WestTowerBox 回退（test_full_traversal + test 11 双 stuck——塔坡道寻路径形被侧板
	# 改变、简化后大斜角途经点楔东壁，与 2026-08-15 同款）。东区侧入楔死
	# （实机 r8 26 stuck：走廊路径从坡道西侧中段切入压 0.75m 台阶立面 > step-up 0.62）
	# 保持 F13 有界兜底，记入账本遗留。
	# 祭坛坡道脚（z=z0）与顶（z=z1）出入口保持开放。
	var st_w := SurfaceTool.new()
	st_w.begin(Mesh.PRIMITIVE_TRIANGLES)
	for s in RAMP_SLOPES:
		if not s.get("side_plates", false):
			continue
		for edge_x in [s["x0"], s["x1"]]:
			var a := Vector3(edge_x, s["y0"], s["z0"])
			var b := Vector3(edge_x, s["y1"], s["z1"])
			var c := Vector3(edge_x, s["y0"], s["z1"])
			var d := Vector3(edge_x, s["y1"], s["z0"])
			for tri in [[a, b, c], [a, d, b]]:
				for v in tri:
					st_w.add_vertex(v)
	geom.add_mesh(st_w.commit(), Transform3D())
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
