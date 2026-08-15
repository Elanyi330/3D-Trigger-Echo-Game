# TEMP 诊断脚本（用后即删）：沿塔坡道中心线密集扫描旧 navmesh 表面高度分布
extends SceneTree


func _init() -> void:
	var nav: NavigationMesh = load("res://Levels/M2_TDM/navmesh.res")
	var map_rid := get_root().get_world_3d().navigation_map
	var region := NavigationRegion3D.new()
	region.navigation_mesh = nav
	root.add_child(region)
	for i in 10:
		await physics_frame
	for s in [{"x": -19.75, "z0": 8.2, "z1": 2.0}, {"x": 19.75, "z0": -8.2, "z1": -2.0}]:
		print("== 塔 x=%.2f ==" % s["x"])
		# z 从 z1-0.3 到 z0+0.8，步长 0.25；每个 z 查询多个 y，收集不同最近点高度
		var n := int(round((absf(s["z1"] - 0.3 - (s["z0"] + 0.8))) / 0.25)) + 1
		for k in n:
			var z: float = s["z0"] + (s["z1"] - s["z0"]) * 0.0  # unused
			var t: float = float(k) / float(n - 1)
			z = (s["z1"] - 0.3) + ((s["z0"] + 0.8) - (s["z1"] - 0.3)) * t
			var ys := {}
			for qy in [0.4, 0.65, 0.9, 1.15, 1.4, 1.65, 1.9, 2.15, 2.4, 2.65, 2.9]:
				var p: Vector3 = NavigationServer3D.map_get_closest_point(map_rid, Vector3(s["x"], qy, z))
				ys["%.2f" % p.y] = true
			var phy := 0.0
			if absf(z) > absf(s["z0"]) - 0.01:
				phy = 0.0
			elif absf(z) < absf(s["z1"]) + 0.01:
				phy = 2.5
			else:
				var d: float = (absf(z) - absf(s["z0"])) / (absf(s["z1"]) - absf(s["z0"]))
				phy = d * 2.5
			var exp_y: float = 0.4 + phy
			print("z=%+.2f 物理=%.2f 期望=%.2f 面高=%s" % [z, phy, exp_y, ", ".join(ys.keys())])
	quit(0)
