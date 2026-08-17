# test/unit/test_tactical_points.gd
# M3.3 T12：战术点库测试（2026-08-17，GUT RED 先行）。
# 需求：JumpEdges.faces() 160 面 → 排除面级分析报告（2026-08-16）标注
# 「导航不可达」的 20 面 → 140 战术点（面中心 Vector3(x, top_y, z) + tier + weight）。
# score / weighted_pick / nearest 语义见 tactical_points.gd 注释。规格见任务 brief。

extends GutTest

const TP := preload("res://Levels/M2_TDM/tactical_points.gd")
const JE := preload("res://Levels/M2_TDM/jump_edges.gd")

# N = 20：报告 docs/reports/2026-08-16-face-analysis.md §2 全部「导航不可达」标注面
# （BackN_LOS_E/W、BeltN_Box1/2、CampN_* 12 面、CornerNE_Box1、Pillar_SW、UmbrellaW、
# WallNorth）——逐条提取后钉死，测试 1 断言点数 = 160 − 20 = 140。
const UNREACHABLE_N := 20


func test_build_counts() -> void:
	var faces := JE.faces()
	assert_eq(faces.size(), 160, "faces() 面数 == 160")
	var tp = TP.build_from_faces(faces)
	assert_eq(tp._points.size(), 140, "点数 == 160 − 20 == 140")
	# 快照表逐条抄录不可遗漏/多录：条目数 == 报告面数 160
	assert_eq(TP._POINTS.size(), 160, "快照表 _POINTS 条目 == 报告面数 160")


func test_tier_weights() -> void:
	assert_eq(TP.TIER_WEIGHT["simple"], 1.0, "simple 权重 1.0")
	assert_eq(TP.TIER_WEIGHT["medium"], 0.7, "medium 权重 0.7")
	assert_eq(TP.TIER_WEIGHT["hard"], 0.35, "hard 权重 0.35")
	assert_eq(TP.TIER_WEIGHT["extreme"], 0.15, "extreme 权重 0.15")
	# 导航不可达面不在点集（抽名断言：BackN_LOS_E 等不可达名查无）
	var tp = TP.build_from_faces(JE.faces())
	var names := {}
	for p0 in tp._points:
		var p: Dictionary = p0
		names[p["face"]] = true
	for n in ["BackN_LOS_E", "BeltN_Box1", "CampN_Roof", "CampN_WallN",
			"CornerNE_Box1", "Pillar_SW", "UmbrellaW", "WallNorth"]:
		assert_false(names.has(n), "导航不可达面 %s 不在点集" % n)
	# 抽样 tier 映射：报告分档面在点集中的 tier/weight 正确
	var by_name := {}
	for p0 in tp._points:
		var p: Dictionary = p0
		by_name[p["face"]] = p
	assert_eq(by_name["EastTower"]["tier"], "medium", "EastTower 中等档")
	assert_eq(by_name["EastTower"]["weight"], 0.7, "EastTower weight == 0.7")
	assert_eq(by_name["RimN2"]["tier"], "hard", "RimN2 困难档")
	assert_eq(by_name["RimN2"]["weight"], 0.35, "RimN2 weight == 0.35")
	assert_eq(by_name["GateN_Lintel"]["tier"], "extreme", "GateN_Lintel 高难档")
	assert_eq(by_name["GateN_Lintel"]["weight"], 0.15, "GateN_Lintel weight == 0.15")
	assert_eq(by_name["Ground"]["tier"], "simple", "Ground 简单档")


func test_weighted_pick_seed_deterministic() -> void:
	var tp = TP.build_from_faces(JE.faces())
	var pos := Vector3(100, 0, 100)  # 远在地图外：全部点水平距 ≥ 8m，均为候选
	var a: Dictionary = tp.weighted_pick(pos, 12345)
	var b: Dictionary = tp.weighted_pick(pos, 12345)
	assert_false(a.is_empty(), "候选集非空")
	assert_eq(a["face"], b["face"], "同 seed 同 pos 两次 pick 相同面名")


func test_score_prefers_near_easy() -> void:
	# 权重仅影响同等成本比较：同距 5m 下 simple(1.0) 分 > medium(0.7) 分
	assert_gt(TP.score(1.0, 5.0), TP.score(0.7, 5.0), "同距：高权重分高")
	# 距离衰减方向：1m 的 medium 分 > 40m 的 simple 分（0.7/1.1 vs 1.0/5.0）
	assert_gt(TP.score(0.7, 1.0), TP.score(1.0, 40.0), "近 medium 胜远 simple")


func test_nearest_tier_filter() -> void:
	# 构造小点集：近 hard 点 vs 远 simple 点——build_from_faces 按面名查快照表，
	# 借用快照实名（CorridorSlab=hard / Ground=simple）+ 自定义 center 构造
	var tp = TP.build_from_faces([
		{"name": "CorridorSlab", "top_y": 3.0, "center": Vector2(2, 0), "size": Vector2(1, 1)},
		{"name": "Ground", "top_y": 0.0, "center": Vector2(5, 0), "size": Vector2(1, 1)},
	])
	var r: Dictionary = tp.nearest(Vector3.ZERO, "medium")
	assert_eq(r["face"], "Ground", "tier 过滤优先于距离：hard 超 medium 限 → 远 simple 点")
	assert_almost_eq(float(r["dist"]), 5.0, 1e-4, "返回距离 == 5m")
	assert_eq(r["tier"], "simple", "返回 tier == simple")
	var r2: Dictionary = tp.nearest(Vector3.ZERO)
	assert_eq(r2["face"], "CorridorSlab", "默认 tier_max=extreme 不过滤 hard → 近点")
