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

# ---- 空表占位（后续任务填充）----
const PLAZA := []        # 任务2：祭坛台/斜板/rim
const CLOCK := []        # 任务2：钟楼（基座/回廊/栏板/伞顶）
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
