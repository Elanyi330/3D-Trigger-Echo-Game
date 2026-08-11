## Map layout data (v3) for the M2 TDM map "回声祭坛" (60x58m).
##
## v3 重设计：中央钟楼枢纽 + 三档环路（设计文档
## docs/superpowers/specs/2026-08-11-m2-echo-altar-v3-design.md）。
## 实体表 = GDScript const Array of Dictionary，
## 实体格式 {"name": String, "kind": String, "center": Vector3, "size": Vector3}（同 v2）。
##
## Godot frame: +X=east, +Z=north, Y=up.

const PLAYER_W := 1.0
const CORRIDOR_MIN := 3.0
const DOOR_MIN := 2.0
const JUMPABLE_MAX := 1.3
const BOUND_X := 30.0
const BOUND_Z := 29.0
const COVER_CROUCH := 0.9   # 蹲藏档掩体高度
const COVER_FULL := 2.2     # 站藏档掩体高度
const WALL_H := 3.0         # 墙体高度
const GRENADE_RADIUS := 8.89

# ---- 地面（与 v2 相同）----
const GROUNDS := [
	{"name": "Ground", "kind": "ground", "center": Vector3(0, -0.5, 0), "size": Vector3(60, 1, 58)},
]

# ---- 边界墙（与 v2 相同）----
const WALLS := [
	{"name": "WallNorth", "kind": "wall", "center": Vector3(0, 2.0, 29.5),   "size": Vector3(60, 4, 1)},
	{"name": "WallSouth", "kind": "wall", "center": Vector3(0, 2.0, -29.5),  "size": Vector3(60, 4, 1)},
	{"name": "WallWest",  "kind": "wall", "center": Vector3(-30.5, 2.0, 0),  "size": Vector3(1, 4, 58)},
	{"name": "WallEast",  "kind": "wall", "center": Vector3(30.5, 2.0, 0),   "size": Vector3(1, 4, 58)},
]

# ---- 中央广场：祭坛台 + 斜板 + rim 围墙（任务 2，设计 §3.2/§3.3）----
const PLAZA := [
	# 祭坛台（台面 y=0.6，x∈[-7,7] z∈[-5,5]）
	{"name": "AltarPlatform", "kind": "cover", "center": Vector3(0, 0.3, 0), "size": Vector3(14, 0.6, 10)},
	# 斜板 4 块（建筑元素，高 2.1：坐台面底 0.6、顶 2.7 齐回廊板底——控制器裁决 A1，2026-08-11；A/B 南对 + A2/B2 = 180° 旋转）
	{"name": "AltarSlabA", "kind": "cover", "center": Vector3(-1.5, 1.65, -2.8), "size": Vector3(3, 2.1, 0.4)},
	{"name": "AltarSlabB", "kind": "cover", "center": Vector3(2.6, 1.65, -1.5), "size": Vector3(0.4, 2.1, 3)},
	{"name": "AltarSlabA2", "kind": "cover", "center": Vector3(1.5, 1.65, 2.8), "size": Vector3(3, 2.1, 0.4)},
	{"name": "AltarSlabB2", "kind": "cover", "center": Vector3(-2.6, 1.65, 1.5), "size": Vector3(0.4, 2.1, 3)},
	# rim 围墙（3m 高厚 1m）：N 边 z=9.5 四段 3 豁——中豁 x∈[2,4.5]（错轴）/侧豁 x∈[-9,-6.5]∪[6.5,9]
	{"name": "RimN1", "kind": "wall", "center": Vector3(-11.25, 1.5, 9.5), "size": Vector3(4.5, 3, 1)},
	{"name": "RimN2", "kind": "wall", "center": Vector3(-2.25, 1.5, 9.5), "size": Vector3(8.5, 3, 1)},
	{"name": "RimN3", "kind": "wall", "center": Vector3(5.5, 1.5, 9.5), "size": Vector3(2, 3, 1)},
	{"name": "RimN4", "kind": "wall", "center": Vector3(11.25, 1.5, 9.5), "size": Vector3(4.5, 3, 1)},
	# S 边 z=-9.5 = 180° 旋转（中豁 x∈[-4.5,-2]，侧豁相同）
	{"name": "RimS1", "kind": "wall", "center": Vector3(-11.25, 1.5, -9.5), "size": Vector3(4.5, 3, 1)},
	{"name": "RimS2", "kind": "wall", "center": Vector3(-5.5, 1.5, -9.5), "size": Vector3(2, 3, 1)},
	{"name": "RimS3", "kind": "wall", "center": Vector3(2.25, 1.5, -9.5), "size": Vector3(8.5, 3, 1)},
	{"name": "RimS4", "kind": "wall", "center": Vector3(11.25, 1.5, -9.5), "size": Vector3(4.5, 3, 1)},
	# E/W 边 x=±14 各两段，留街口 z∈[-2,2]（4m）
	{"name": "RimE_T", "kind": "wall", "center": Vector3(14, 1.5, 6), "size": Vector3(1, 3, 8)},
	{"name": "RimE_B", "kind": "wall", "center": Vector3(14, 1.5, -6), "size": Vector3(1, 3, 8)},
	{"name": "RimW_T", "kind": "wall", "center": Vector3(-14, 1.5, 6), "size": Vector3(1, 3, 8)},
	{"name": "RimW_B", "kind": "wall", "center": Vector3(-14, 1.5, -6), "size": Vector3(1, 3, 8)},
]

# ---- 钟楼（任务 2，设计 §3.2）：基座/回廊/栏板/组合柱/伞顶/钟饰 ----
const CLOCK := [
	# 钟基座（坐台面 0.6，顶 2.7）
	{"name": "Pedestal", "kind": "cover", "center": Vector3(0, 1.65, 0), "size": Vector3(4, 2.1, 4)},
	# 回廊板（底 2.7、行走面 3.0，四边出挑 1.5m）
	{"name": "CorridorSlab", "kind": "cover", "center": Vector3(0, 2.85, 0), "size": Vector3(7, 0.3, 7)},
	# 回廊栏板（0.9 高 0.2 厚，坐回廊面 3.0）：N/S 中豁 1.5m；E 豁 z∈[1.5,3.5]、W 豁 z∈[-3.5,-1.5]（坡道落点）
	# RailE/RailW 闭端各缩 0.2 避免与 S/N 栏板角部体积相撞——控制器裁决 B1，2026-08-11（豁口宽度/位置不变）
	{"name": "RailN_W", "kind": "cover", "center": Vector3(-2.125, 3.45, 3.4), "size": Vector3(2.75, 0.9, 0.2)},
	{"name": "RailN_E", "kind": "cover", "center": Vector3(2.125, 3.45, 3.4), "size": Vector3(2.75, 0.9, 0.2)},
	{"name": "RailS_W", "kind": "cover", "center": Vector3(-2.125, 3.45, -3.4), "size": Vector3(2.75, 0.9, 0.2)},
	{"name": "RailS_E", "kind": "cover", "center": Vector3(2.125, 3.45, -3.4), "size": Vector3(2.75, 0.9, 0.2)},
	{"name": "RailE", "kind": "cover", "center": Vector3(3.4, 3.45, -0.9), "size": Vector3(0.2, 0.9, 4.8)},
	{"name": "RailW", "kind": "cover", "center": Vector3(-3.4, 3.45, 0.9), "size": Vector3(0.2, 0.9, 4.8)},
	# 组合柱 ×4（角柱掩体 + 伞顶支柱，底 3.0 顶 7.1）
	{"name": "Pillar_NE", "kind": "cover", "center": Vector3(2.9, 5.05, 2.9), "size": Vector3(0.5, 4.1, 0.5)},
	{"name": "Pillar_NW", "kind": "cover", "center": Vector3(-2.9, 5.05, 2.9), "size": Vector3(0.5, 4.1, 0.5)},
	{"name": "Pillar_SE", "kind": "cover", "center": Vector3(2.9, 5.05, -2.9), "size": Vector3(0.5, 4.1, 0.5)},
	{"name": "Pillar_SW", "kind": "cover", "center": Vector3(-2.9, 5.05, -2.9), "size": Vector3(0.5, 4.1, 0.5)},
	# 伞顶 4 板（厚 0.4，底面 7.1；中央 x/z∈[-1.5,1.5] 开敞 = 雷口）
	{"name": "UmbrellaN", "kind": "cover", "center": Vector3(0, 7.3, 2.75), "size": Vector3(8, 0.4, 2.5)},
	{"name": "UmbrellaS", "kind": "cover", "center": Vector3(0, 7.3, -2.75), "size": Vector3(8, 0.4, 2.5)},
	{"name": "UmbrellaW", "kind": "cover", "center": Vector3(-2.75, 7.3, 0), "size": Vector3(2.5, 0.4, 3)},
	{"name": "UmbrellaE", "kind": "cover", "center": Vector3(2.75, 7.3, 0), "size": Vector3(2.5, 0.4, 3)},
	# 钟饰（无碰撞 weenie，顶 ~9.5）
	{"name": "BellDecor", "kind": "decor", "center": Vector3(0, 8.6, 0), "size": Vector3(1.2, 1.8, 1.2)},
]
# ---- 空表占位（后续任务填充）----
const RAMPS := []        # 任务3：坡道/微台阶
const STREETS := []      # 任务4：东/西市街
const GATES := []        # 任务5：钟门/市集带
const BACKSTREETS := []  # 任务6：背街/营
const OUTER := []        # 任务7：外环/角场


static func all_solids() -> Array:
	var out := []
	out.append_array(GROUNDS)
	out.append_array(WALLS)
	out.append_array(PLAZA)
	out.append_array(CLOCK)
	out.append_array(RAMPS)
	out.append_array(STREETS)
	out.append_array(GATES)
	out.append_array(BACKSTREETS)
	out.append_array(OUTER)
	return out


## 可踏足/可刷怪表面清单（任务 8 填充——每项 {"name": String, "center": Vector3, "size": Vector3, "top_y": float}，center.y = top_y）
static func standable_surfaces() -> Array:
	return []
