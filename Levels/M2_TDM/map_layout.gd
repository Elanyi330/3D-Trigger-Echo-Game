## Map layout data (v1) for the M2 TDM map "回声集市" (60x58m).
##
## Data-driven layout: single source of truth for the greybox. All coordinates in
## meters, Godot frame: +X = east, +Z = north (south = -Z), Y = up.
## North = T spawn, South = CT spawn (mirror symmetry).
##
## Values calibrated by T1 probes (2026-08-10):
##   player capsule r0.5/h1.83 (width 1.0m) → corridor min 3.0m, doors min 2.0m
##   stand jump reachable top ≈1.39-1.45m  → jumpable ≤1.3m
##   run jump distance ≈4.87m              → jump gaps ≤4.5m
##   grenade radius 8.89m                  → hall 14x12m (diag 18.4m > radius)

# ---------------------------------------------------------------------------
# AABB element type: {name, kind, center: Vector3, size: Vector3}
# kind: "ground" | "wall" | "cover" | "roof" | "ramp" | "spawn"
# ---------------------------------------------------------------------------
const PLAYER_W := 1.0   # player capsule width (r0.5)
const CORRIDOR_MIN := 3.0   # min corridor width
const DOOR_MIN := 2.0   # min doorway width
const JUMPABLE_MAX := 1.3  # max height jumpable (T1: 1.39m - margin)
const JUMP_GAP_MAX := 4.5  # max jumpable gap (T1: 4.87m - margin)
const BOUND_X := 30.0   # half map width (60m)
const BOUND_Z := 29.0   # half map depth (58m)

# ---- single ground slab (60 x 58) ----
const GROUNDS := [
	{"name": "Ground", "kind": "ground", "center": Vector3(0, -0.5, 0), "size": Vector3(60, 1, 58)},
]

# ---- boundary walls (height 4m, thick 1m, y center 2.0) — 边到边相接，角点不重叠 ----
const WALLS := [
	{"name": "WallNorth", "kind": "wall", "center": Vector3(0, 2.0, 29.5),   "size": Vector3(60, 4, 1)},
	{"name": "WallSouth", "kind": "wall", "center": Vector3(0, 2.0, -29.5),  "size": Vector3(60, 4, 1)},
	{"name": "WallWest",  "kind": "wall", "center": Vector3(-30.5, 2.0, 0),  "size": Vector3(1, 4, 58)},
	{"name": "WallEast",  "kind": "wall", "center": Vector3(30.5, 2.0, 0),   "size": Vector3(1, 4, 58)},
]

# ---- central hall (14 x 12 x 3.0m), walls split into 8 segments with 2m door gaps ----
# 内廓 x -7..7, z -6..6；墙厚 1m。门缝 x/z ∈ [-1,1]。
const HALL_WALL_SEGMENTS := [
	{"name": "HallWallN_L", "kind": "wall", "center": Vector3(-4.0, 1.5, 6.5), "size": Vector3(6, 3.0, 1)},
	{"name": "HallWallN_R", "kind": "wall", "center": Vector3(4.0, 1.5, 6.5),  "size": Vector3(6, 3.0, 1)},
	{"name": "HallWallS_L", "kind": "wall", "center": Vector3(-4.0, 1.5, -6.5), "size": Vector3(6, 3.0, 1)},
	{"name": "HallWallS_R", "kind": "wall", "center": Vector3(4.0, 1.5, -6.5),  "size": Vector3(6, 3.0, 1)},
	{"name": "HallWallW_T", "kind": "wall", "center": Vector3(-7.5, 1.5, 3.5), "size": Vector3(1, 3.0, 5)},
	{"name": "HallWallW_B", "kind": "wall", "center": Vector3(-7.5, 1.5, -3.5), "size": Vector3(1, 3.0, 5)},
	{"name": "HallWallE_T", "kind": "wall", "center": Vector3(7.5, 1.5, 3.5),  "size": Vector3(1, 3.0, 5)},
	{"name": "HallWallE_B", "kind": "wall", "center": Vector3(7.5, 1.5, -3.5),  "size": Vector3(1, 3.0, 5)},
]

const HALL_DOORS := [
	{"name": "DoorNorth", "center": Vector3(0, 1.5, 6.5),   "gap_x": 2.0},
	{"name": "DoorSouth", "center": Vector3(0, 1.5, -6.5),  "gap_x": 2.0},
	{"name": "DoorWest",  "center": Vector3(-7.5, 1.5, 0),  "gap_z": 2.0},
	{"name": "DoorEast",  "center": Vector3(7.5, 1.5, 0),   "gap_z": 2.0},
]

# ---- interior pillars (0.6m, 2x3 grid, height 3.0) ----
const HALL_PILLARS := [
	{"name": "PillarA", "center": Vector3(-3.5, 1.5, -3.0), "size": Vector3(0.6, 3.0, 0.6)},
	{"name": "PillarB", "center": Vector3(0.0, 1.5, -3.0),  "size": Vector3(0.6, 3.0, 0.6)},
	{"name": "PillarC", "center": Vector3(3.5, 1.5, -3.0),  "size": Vector3(0.6, 3.0, 0.6)},
	{"name": "PillarD", "center": Vector3(-3.5, 1.5, 3.0),  "size": Vector3(0.6, 3.0, 0.6)},
	{"name": "PillarE", "center": Vector3(0.0, 1.5, 3.0),   "size": Vector3(0.6, 3.0, 0.6)},
	{"name": "PillarF", "center": Vector3(3.5, 1.5, 3.0),   "size": Vector3(0.6, 3.0, 0.6)},
]

# ---- interior half-walls (1.2m, split north/south blocks) ----
const HALL_DIVIDERS := [
	{"name": "DividerN", "kind": "cover", "center": Vector3(-3.0, 0.6, 1.5),  "size": Vector3(6.0, 1.2, 0.5)},
	{"name": "DividerS", "kind": "cover", "center": Vector3(3.0, 0.6, -1.5),  "size": Vector3(6.0, 1.2, 0.5)},
]

# ---- 大厅屋顶（问题4：中央建筑实体感——加盖 3.0m 高屋顶，形成建筑而非开放几何）----
# 屋顶面板：y 中心 3.25（顶面 3.5，高于柱顶 3.0），厚度 0.5；两端留 2m 天窗缝（采光+视觉）
const HALL_ROOF := [
	{"name": "HallRoofN", "kind": "roof", "center": Vector3(0, 3.25, 3.5), "size": Vector3(14, 0.5, 4.0)},
	{"name": "HallRoofS", "kind": "roof", "center": Vector3(0, 3.25, -3.5), "size": Vector3(14, 0.5, 4.0)},
]
# 门框（问题4：门洞加框柱，强化出入口的"门"感）——框柱内移（中心 ±0.8）避开墙段边界（±1.0 起）
const HALL_DOOR_FRAMES := [
	{"name": "DoorFrameN_L", "kind": "wall", "center": Vector3(-0.8, 1.5, 6.5), "size": Vector3(0.4, 3.0, 1.4)},
	{"name": "DoorFrameN_R", "kind": "wall", "center": Vector3(0.8, 1.5, 6.5),  "size": Vector3(0.4, 3.0, 1.4)},
	{"name": "DoorFrameS_L", "kind": "wall", "center": Vector3(-0.8, 1.5, -6.5), "size": Vector3(0.4, 3.0, 1.4)},
	{"name": "DoorFrameS_R", "kind": "wall", "center": Vector3(0.8, 1.5, -6.5),  "size": Vector3(0.4, 3.0, 1.4)},
	{"name": "DoorFrameW_T", "kind": "wall", "center": Vector3(-7.5, 1.5, 0.8), "size": Vector3(1.4, 3.0, 0.4)},
	{"name": "DoorFrameW_B", "kind": "wall", "center": Vector3(-7.5, 1.5, -0.8), "size": Vector3(1.4, 3.0, 0.4)},
	{"name": "DoorFrameE_T", "kind": "wall", "center": Vector3(7.5, 1.5, 0.8),  "size": Vector3(1.4, 3.0, 0.4)},
	{"name": "DoorFrameE_B", "kind": "wall", "center": Vector3(7.5, 1.5, -0.8),  "size": Vector3(1.4, 3.0, 0.4)},
]

# ---- outdoor vertical layer ----
# West low roofs (1.2m jumpable), only in mid street band (z -6.5..6.5), west of west street
const WEST_ROOFS := [
	{"name": "RoofWest1", "kind": "roof", "center": Vector3(-16, 0.6, -4), "size": Vector3(6, 1.2, 5)},
	{"name": "RoofWest2", "kind": "roof", "center": Vector3(-16, 0.6, 4),  "size": Vector3(6, 1.2, 5)},
]
# East rooftop (2.5m) — 东侧建筑群（问题3 修复）：
#   东街走廊 x∈[9.5,13.5]（4m，大厅东口直通）
#   三级台阶 x∈[13.5,21.5]（每级 2.67m 宽 × 0.83m 高 → 逐级跳上屋顶；灰盒斜坡替代，真斜坡 T4 三角棱柱）
#   屋顶 x∈[21.5,29.5]（8m 宽，顶面 2.5m，顶到东墙 → 零夹缝）
#   注：台阶每级 0.83m 远小于可跳上限 1.3m ✓
const EAST_ROOF := {"name": "RoofEast", "kind": "roof", "center": Vector3(25.5, 1.25, 0), "size": Vector3(8, 2.5, 12)}
const EAST_STEPS := [
	{"name": "StepEast1", "kind": "roof", "center": Vector3(14.3, 0.415, 0), "size": Vector3(2.67, 0.83, 12)},
	{"name": "StepEast2", "kind": "roof", "center": Vector3(17.0, 1.245, 0), "size": Vector3(2.67, 0.83, 12)},
	{"name": "StepEast3", "kind": "roof", "center": Vector3(19.7, 2.075, 0), "size": Vector3(2.67, 0.83, 12)},
]

# ---- cover pieces ----
const COVERS := [
	# west street (x=-10) low boxes (0.9m)
	{"name": "BoxW1", "kind": "cover", "center": Vector3(-10, 0.45, -8), "size": Vector3(1.0, 0.9, 1.0)},
	{"name": "BoxW2", "kind": "cover", "center": Vector3(-10, 0.45, -6), "size": Vector3(1.0, 0.9, 1.0)},
	{"name": "BoxW3", "kind": "cover", "center": Vector3(-10, 0.45, -4), "size": Vector3(1.0, 0.9, 1.0)},
	# west street cars (1.3m mid cover)
	{"name": "CarW1", "kind": "cover", "center": Vector3(-10, 0.65, 2), "size": Vector3(2.0, 1.3, 1.2)},
	{"name": "CarW2", "kind": "cover", "center": Vector3(-10, 0.65, 5), "size": Vector3(2.0, 1.3, 1.2)},
	# east containers (2.2m high cover) — 东街两侧（避开斜坡 z∈[-6,6]），不挡走廊
	{"name": "ContainerE1", "kind": "cover", "center": Vector3(11, 1.1, -11), "size": Vector3(3.5, 2.2, 2.5)},
	{"name": "ContainerE2", "kind": "cover", "center": Vector3(11, 1.1, 9), "size": Vector3(3.5, 2.2, 2.5)},
	# mid-street 1.4m walls (grenade coverage + spawn cover)
	{"name": "BoxM1", "kind": "cover", "center": Vector3(0, 0.7, -14), "size": Vector3(2.0, 1.4, 0.5)},
	{"name": "BoxM2", "kind": "cover", "center": Vector3(0, 0.7, 14), "size": Vector3(2.0, 1.4, 0.5)},
]

# ---- spawn alcoves (symmetric N/S; 1.4m half-wall blocks spawn-kill LOS) ----
const SPAWNS := [
	{"name": "SpawnN", "kind": "spawn", "center": Vector3(-2, 0, 27), "facing": "S"},
	{"name": "SpawnS", "kind": "spawn", "center": Vector3(-2, 0, -27), "facing": "N"},
]
const SPAWN_WALLS := [
	{"name": "SpawnWallN", "kind": "cover", "center": Vector3(0, 0.7, 25.5), "size": Vector3(12, 1.4, 1.0)},
	{"name": "SpawnWallS", "kind": "cover", "center": Vector3(0, 0.7, -25.5), "size": Vector3(12, 1.4, 1.0)},
]

# ---- 出生区掩体（问题4：出生区过分空旷——补箱堆/矮墙形成遮蔽，防出生即被看穿）----
const SPAWN_COVERS := [
	# T 出生（北）：前方两侧箱堆 + 中央矮墙
	{"name": "SpawnBoxN1", "kind": "cover", "center": Vector3(-6, 0.45, 27), "size": Vector3(2.0, 0.9, 1.0)},
	{"name": "SpawnBoxN2", "kind": "cover", "center": Vector3(6, 0.45, 27), "size": Vector3(2.0, 0.9, 1.0)},
	{"name": "SpawnBoxN3", "kind": "cover", "center": Vector3(-3, 0.45, 24), "size": Vector3(1.0, 0.9, 1.0)},
	{"name": "SpawnBoxN4", "kind": "cover", "center": Vector3(3, 0.45, 24), "size": Vector3(1.0, 0.9, 1.0)},
	# CT 出生（南）：对称
	{"name": "SpawnBoxS1", "kind": "cover", "center": Vector3(-6, 0.45, -27), "size": Vector3(2.0, 0.9, 1.0)},
	{"name": "SpawnBoxS2", "kind": "cover", "center": Vector3(6, 0.45, -27), "size": Vector3(2.0, 0.9, 1.0)},
	{"name": "SpawnBoxS3", "kind": "cover", "center": Vector3(-3, 0.45, -24), "size": Vector3(1.0, 0.9, 1.0)},
	{"name": "SpawnBoxS4", "kind": "cover", "center": Vector3(3, 0.45, -24), "size": Vector3(1.0, 0.9, 1.0)},
]

# ---- all solids for AABB checks ----
static func all_solids() -> Array:
	var out := []
	out.append_array(GROUNDS)
	out.append_array(WALLS)
	out.append_array(HALL_WALL_SEGMENTS)
	out.append_array(HALL_PILLARS)
	out.append_array(HALL_DIVIDERS)
	out.append_array(HALL_ROOF)
	out.append_array(HALL_DOOR_FRAMES)
	out.append_array(WEST_ROOFS)
	out.append_array([EAST_ROOF])
	out.append_array(EAST_STEPS)
	out.append_array(COVERS)
	out.append_array(SPAWN_WALLS)
	out.append_array(SPAWN_COVERS)
	return out

static func hall_center() -> Vector3:
	return Vector3(0, 0, 0)

static func hall_size() -> Vector3:
	return Vector3(14, 3.0, 12)
