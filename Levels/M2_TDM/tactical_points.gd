## 战术点库（2026-08-17 M3.3 T12）。
##
## 从 JumpEdges.faces() 160 面表派生战术点（面中心 + tier 权重），供 BotBrain
## 目标/掩体选择。tier 快照表 _POINTS 逐条抄录自
## docs/reports/2026-08-16-face-analysis.md §2 分档清单（快照日期 2026-08-16；
## 简单 137 / 中等 13 / 困难 4 / 高难 6，合计 160），条目按报告行序排列；
## 报告标注「导航不可达」的 20 面 tier 记为 "unreachable"，build_from_faces
## 时排除（不进入 _points）——点集数 = 160 − 20 = 140（测试 1 钉死）。
class_name TacticalPoints
extends RefCounted

const TIER_WEIGHT := {"simple": 1.0, "medium": 0.7, "hard": 0.35, "extreme": 0.15}
# 面级分析报告 tier 映射：简单→simple / 中等→medium / 困难→hard / 高难→extreme
const TIER_ORDER := ["simple", "medium", "hard", "extreme"]  # 序：nearest tier_max 过滤用

# weighted_pick 候选最小水平距（避免原地）；score 距离衰减系数（score = weight / (1 + dist * DIST_DECAY)）
const MIN_PICK_DIST := 8.0
const DIST_DECAY := 0.1

# tier 快照表：160 面名 → tier（快照日期 2026-08-16，来源
# docs/reports/2026-08-16-face-analysis.md §2，逐条抄录、按报告行序）。
# "unreachable" = 报告「导航不可达」标注面（共 20 个），build 时排除。
# 数据债务注记：报告后新增的面不在此表 → build 时默认 simple + push_warning；
# 下次面级分析报告再生后应补录 tier。
const _POINTS := {
	"AltarPlatform": "simple",
	"AltarSlabA": "simple",
	"AltarSlabA2": "simple",
	"AltarSlabB": "simple",
	"AltarSlabB2": "simple",
	"BackN_LOS_E": "unreachable",
	"BackN_LOS_W": "unreachable",
	"BackS_LOS_E": "simple",
	"BackS_LOS_W": "simple",
	"BeltN_Box1": "unreachable",
	"BeltN_Box2": "unreachable",
	"BeltN_CanopyE": "simple",
	"BeltN_CanopyW": "simple",
	"BeltN_PavE": "simple",
	"BeltN_PavStepE": "simple",
	"BeltN_PavStepW": "simple",
	"BeltS_Box1": "simple",
	"BeltS_Box2": "simple",
	"BeltS_CanopyE": "simple",
	"BeltS_CanopyW": "simple",
	"BeltS_PavE": "simple",
	"BeltS_PavStepE": "simple",
	"BeltS_PavStepW": "simple",
	"CampN_Roof": "unreachable",
	"CampN_Screen_E": "unreachable",
	"CampN_Screen_S": "unreachable",
	"CampN_Screen_W": "unreachable",
	"CampN_Truck": "unreachable",
	"CampN_WallE_N": "unreachable",
	"CampN_WallE_S": "unreachable",
	"CampN_WallN": "unreachable",
	"CampN_WallS_E": "unreachable",
	"CampN_WallS_W": "unreachable",
	"CampN_WallW_N": "unreachable",
	"CampN_WallW_S": "unreachable",
	"CampS_Roof": "simple",
	"CampS_Screen_E": "simple",
	"CampS_Screen_W": "simple",
	"CampS_Truck": "simple",
	"CampS_WallE_N": "simple",
	"CampS_WallE_S": "simple",
	"CampS_WallN_E": "simple",
	"CampS_WallN_W": "simple",
	"CampS_WallS": "simple",
	"CampS_WallW_N": "simple",
	"CampS_WallW_S": "simple",
	"CornerNE_Box1": "unreachable",
	"CornerNE_Pav": "simple",
	"CornerNE_PavStep": "simple",
	"CornerNW_Box1": "simple",
	"CornerNW_Pav": "simple",
	"CornerNW_PavStep": "simple",
	"CornerSE_Box1": "simple",
	"CornerSE_Pav": "simple",
	"CornerSE_PavStep": "simple",
	"CornerSW_Box1": "simple",
	"CornerSW_Pav": "simple",
	"CornerSW_PavStep": "simple",
	"EastClusterN_Box": "simple",
	"EastClusterS_Box": "simple",
	"EastClusterS_Panel": "simple",
	"EastPavilionStep": "simple",
	"EastSpurN": "simple",
	"EastSpurS": "simple",
	"EastTowerBox": "simple",
	"EastTowerRampStep1": "simple",
	"EastTowerRampStep10": "simple",
	"EastTowerRampStep2": "simple",
	"EastTowerRampStep3": "simple",
	"EastTowerRampStep4": "simple",
	"EastTowerRampStep5": "simple",
	"EastTowerRampStep6": "simple",
	"EastTowerRampStep7": "simple",
	"EastTowerRampStep8": "simple",
	"EastTowerRampStep9": "simple",
	"EastWall_M": "simple",
	"EastWall_N": "simple",
	"EastWall_S": "simple",
	"GateN_PillarE": "simple",
	"GateN_PillarW": "simple",
	"GateS_PillarE": "simple",
	"GateS_PillarW": "simple",
	"Ground": "simple",
	"Pedestal": "simple",
	"Pillar_NE": "simple",
	"Pillar_NW": "simple",
	"Pillar_SE": "simple",
	"Pillar_SW": "unreachable",
	"RampEStep1": "simple",
	"RampEStep2": "simple",
	"RampEStep3": "simple",
	"RampEStep4": "simple",
	"RampEStep5": "simple",
	"RampEStep6": "simple",
	"RampEStep7": "simple",
	"RampEStep8": "simple",
	"RampWStep1": "simple",
	"RampWStep2": "simple",
	"RampWStep3": "simple",
	"RampWStep5": "simple",
	"RampWStep7": "simple",
	"RampWStep8": "simple",
	"RimN1": "simple",
	"RimN3": "simple",
	"RimN4": "simple",
	"RimS1": "simple",
	"RimS3": "simple",
	"RimS4": "simple",
	"UmbrellaE": "simple",
	"UmbrellaN": "simple",
	"UmbrellaS": "simple",
	"UmbrellaW": "unreachable",
	"WallEast": "simple",
	"WallNorth": "unreachable",
	"WallSouth": "simple",
	"WallWest": "simple",
	"WestClusterN_Box": "simple",
	"WestClusterN_Panel": "simple",
	"WestClusterS_Box": "simple",
	"WestPavilion": "simple",
	"WestPavilionStep": "simple",
	"WestSpurN": "simple",
	"WestSpurS": "simple",
	"WestTowerBox": "simple",
	"WestTowerRampStep1": "simple",
	"WestTowerRampStep10": "simple",
	"WestTowerRampStep2": "simple",
	"WestTowerRampStep3": "simple",
	"WestTowerRampStep4": "simple",
	"WestTowerRampStep5": "simple",
	"WestTowerRampStep6": "simple",
	"WestTowerRampStep7": "simple",
	"WestTowerRampStep8": "simple",
	"WestTowerRampStep9": "simple",
	"WestWall_M": "simple",
	"WestWall_N": "simple",
	"WestWall_S": "simple",
	"BeltN_PavW": "medium",
	"BeltS_PavW": "medium",
	"EastClusterN_Panel": "medium",
	"EastPavilion": "medium",
	"EastTower": "medium",
	"RampWStep6": "medium",
	"RimE_B": "medium",
	"RimE_T": "medium",
	"RimS2": "medium",
	"RimW_B": "medium",
	"RimW_T": "medium",
	"WestClusterS_Panel": "medium",
	"WestTower": "medium",
	"CampS_Screen_N": "hard",
	"CorridorSlab": "hard",
	"RampWStep4": "hard",
	"RimN2": "hard",
	"GateN_Lintel": "extreme",
	"GateN_WingE": "extreme",
	"GateN_WingW": "extreme",
	"GateS_Lintel": "extreme",
	"GateS_WingE": "extreme",
	"GateS_WingW": "extreme",
}


var _points: Array = []   # [{face, center: Vector3, tier: String, weight: float}]


## 从 JumpEdges.faces() 面表构建点集：每面查快照表 → 点
## {face, center: Vector3(x, top_y, z), tier, weight=TIER_WEIGHT[tier]}。
## 「导航不可达」（快照 tier=="unreachable"）面排除；
## 快照表未含面名（报告后新增）→ 默认 "simple" + push_warning（数据债务注记）。
static func build_from_faces(faces: Array) -> TacticalPoints:
	var tp := TacticalPoints.new()
	for f0 in faces:
		var f: Dictionary = f0
		var name: String = f["name"]
		var tier: String = _POINTS.get(name, "")
		if tier == "unreachable":
			continue
		if tier == "":
			# 数据债务：快照表未含面名（2026-08-16 报告后新增）→ 默认 simple，
			# 下次面级分析报告再生后应补录 tier。
			push_warning("TacticalPoints: 面 '%s' 不在 tier 快照表（2026-08-16），默认 simple" % name)
			tier = "simple"
		var c: Vector2 = f["center"]
		tp._points.append({
			"face": name,
			"center": Vector3(c.x, float(f["top_y"]), c.y),
			"tier": tier,
			"weight": TIER_WEIGHT[tier],
		})
	return tp


## score = weight / (1.0 + dist * 0.1)：权重仅影响同等成本比较（dist=水平距）。
static func score(weight: float, dist: float) -> float:
	return weight / (1.0 + dist * DIST_DECAY)


## 目标选择：候选 = 距 pos 水平距 ≥ MIN_PICK_DIST 的点（避免原地）；
## score 排序取最高。返回点 {face, center, tier, weight}；无候选 → {}。
## 平局规则（同分候选多个）：rng_seed=0 真随机取一；
## rng_seed>0 确定性——同分候选按面名升序，取 seeded rng 索引（同 seed 同结果）。
func weighted_pick(pos: Vector3, rng_seed: int = 0) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	if rng_seed > 0:
		rng.seed = rng_seed
	else:
		rng.randomize()
	var best: Array = []
	var best_score := -INF
	for p0 in _points:
		var p: Dictionary = p0
		var c: Vector3 = p["center"]
		var dist: float = Vector2(c.x - pos.x, c.z - pos.z).length()
		if dist < MIN_PICK_DIST:
			continue
		var s := score(float(p["weight"]), dist)
		if s > best_score + 1e-9:
			best = [p]
			best_score = s
		elif absf(s - best_score) <= 1e-9:
			best.append(p)
	if best.is_empty():
		return {}
	if best.size() == 1:
		return best[0]
	best.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["face"] < b["face"])
	return best[rng.randi() % best.size()]


## 掩体/战术点查询：距 pos 最近且 tier 序 ≤ tier_max 的点（序
## simple < medium < hard < extreme）。返回 {face, center, tier, weight, dist}；
## 无合规点 → 空字典 {}。
func nearest(pos: Vector3, tier_max: String = "extreme") -> Dictionary:
	var max_idx: int = TIER_ORDER.find(tier_max)
	var best := {}
	var best_dist := INF
	for p0 in _points:
		var p: Dictionary = p0
		if TIER_ORDER.find(p["tier"]) > max_idx:
			continue
		var c: Vector3 = p["center"]
		var dist: float = Vector2(c.x - pos.x, c.z - pos.z).length()
		if dist < best_dist:
			best = p
			best_dist = dist
	if best.is_empty():
		return {}
	return {
		"face": best["face"],
		"center": best["center"],
		"tier": best["tier"],
		"weight": best["weight"],
		"dist": best_dist,
	}
