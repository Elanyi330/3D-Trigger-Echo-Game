# tools/probe_theme.gd — 模块主题配色门禁（2026-08-13 视觉提升）
# 用法：godot --headless --path . -s tools/probe_theme.gd
# 验证三件事：
#   1. 193 实体全量扫描——生产中走 map_greybox._color_for 的实体（非 decor/bigtree）
#      除 Ground 外全部命中 NAME_THEME 名称规则（防未来新增实体漏配色）；
#   2. 关键名 41 项抽查期望色（防子串规则误吞，如 TowerRail 被 Rail 吞、Box 被 Cluster 吞）；
#   3. 总实体数 = 193（结构不变红线：配色升级只改 material_override，布局数据零改动）。
# 注意：修改 NAME_THEME 配色值后必须同步本文件 expect 表（门禁 = 定稿配色）。
extends SceneTree

const GB := preload("res://Levels/M2_TDM/map_greybox.gd")
const LAYOUT := preload("res://Levels/M2_TDM/map_layout_v3.gd")

func _init() -> void:
	var gb = GB.new()
	var fails := 0
	var solids: Array = LAYOUT.all_solids()
	var expect := {
		"Ground": Color(0.62, 0.6, 0.55),
		"AltarPlatform": Color(0.86, 0.79, 0.59),
		"AltarSlabA": Color(0.69, 0.4, 0.23),
		"MicroN1": Color(0.86, 0.79, 0.59),
		"Pedestal": Color(0.33, 0.33, 0.37),
		"CorridorSlab": Color(0.9, 0.87, 0.82),
		"RailN_W": Color(0.84, 0.81, 0.76),
		"Pillar_NE": Color(0.72, 0.58, 0.32),
		"UmbrellaN": Color(0.31, 0.22, 0.13),
		"RimN1": Color(0.47, 0.47, 0.51),
		"RampEStep1": Color(0.53, 0.53, 0.57),
		"RampWStep8": Color(0.53, 0.53, 0.57),
		"GateN_Lintel": Color(0.85, 0.68, 0.3),
		"GateN_PillarW": Color(0.86, 0.83, 0.78),
		"GateS_WingW": Color(0.86, 0.83, 0.78),
		"BeltN_CanopyW": Color(0.56, 0.29, 0.24),
		"BeltN_PavW": Color(0.65, 0.51, 0.33),
		"BeltS_PavStepE": Color(0.45, 0.33, 0.19),
		"BeltS_Box2": Color(0.52, 0.4, 0.24),
		"EastWall_S": Color(0.42, 0.48, 0.4),
		"WestWall_M": Color(0.42, 0.48, 0.4),
		"WestTower": Color(0.31, 0.22, 0.13),
		"WestTowerRailN_1": Color(0.45, 0.33, 0.19),
		"WestTowerRampStep1": Color(0.45, 0.33, 0.19),
		"EastTowerBox": Color(0.52, 0.4, 0.24),
		"EastClusterN_Panel": Color(0.65, 0.51, 0.33),
		"WestClusterS_Box": Color(0.52, 0.4, 0.24),
		"EastPavilion": Color(0.65, 0.51, 0.33),
		"EastPavilionStep": Color(0.45, 0.33, 0.19),
		"EastSpurN": Color(0.47, 0.47, 0.51),
		"WestSpurN": Color(0.47, 0.47, 0.51),
		"BackN_LOS_E": Color(0.31, 0.22, 0.13),
		"CampN_WallN": Color(0.55, 0.47, 0.38),
		"CampN_Screen_S": Color(0.55, 0.47, 0.38),
		"CampN_Roof": Color(0.31, 0.22, 0.13),
		"CampS_Truck": Color(0.28, 0.42, 0.3),
		"CornerNE_Pav": Color(0.65, 0.51, 0.33),
		"CornerSW_PavStep": Color(0.45, 0.33, 0.19),
		"CornerSE_Box1": Color(0.52, 0.4, 0.24),
		"WallNorth": Color(0.33, 0.33, 0.37),
		"WallEast": Color(0.33, 0.33, 0.37),
	}
	for e in solids:
		var name: String = e["name"]
		var kind: String = e.get("kind", "cover")
		var col: Color = gb._color_for(kind, name)
		var hit_rule := ""
		for rule in GB.NAME_THEME:
			if name.contains(rule[0]):
				hit_rule = rule[0]
				break
		if expect.has(name):
			if not col.is_equal_approx(expect[name]):
				fails += 1
				print("FAIL  %-22s got %s expected %s" % [name, col, expect[name]])
		elif hit_rule == "" and kind != "decor" and kind != "bigtree" and name != "Ground":
			fails += 1
			print("FAIL  %-22s 未命中主题规则（kind=%s）" % [name, kind])
	# 生产中只有非 decor/bigtree 的实体走 _color_for：断言除 Ground 外全部命中主题规则
	var uncovered := []
	for e in solids:
		var name: String = e["name"]
		var kind: String = e.get("kind", "cover")
		if kind == "decor" or kind == "bigtree":
			continue
		var hit := false
		for rule in GB.NAME_THEME:
			if name.contains(rule[0]):
				hit = true
				break
		if not hit and name != "Ground":
			uncovered.append(name)
	print("solid 总数: %d, 抽查 %d 项失败 %d, 生产中走 matcher 但未命中规则: %s" % [solids.size(), expect.size(), fails, str(uncovered)])
	quit(1 if fails > 0 or uncovered.size() > 0 or solids.size() != 193 else 0)
