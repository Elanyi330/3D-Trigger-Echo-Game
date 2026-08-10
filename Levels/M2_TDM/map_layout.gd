## Map layout data (v2) for the M2 TDM map "回声集市" (60x58m).
##
## v2 布局重构（2026-08-10 用户反馈）：出生区缩小、中央建筑扩大、四角加建筑、街道环形化，
## 增加交火区域密度，使地图更饱满、适合 5v5 团战。
##
## 结构（俯视）：
##   z=29   ┌───北墙────────────┐
##          │ NW建筑  出生区   NE建筑 │  z∈[14,29]: 角建筑(±16..±30) + 出生区(-6..6)
##   z=14   ├───门─────────────┤
##          │  西街   中央大厅    │  z∈[9,14]: 北街(5m)
##   z=9    ├───门─────────────┤
##          │                  │  z∈[-9,9]: 中央大厅(20×16m)
##   z=-9   ├───门─────────────┤
##          │  西街   中央大厅    │  z∈[-14,-9]: 南街(5m)
##   z=-14  ├───门─────────────┤
##          │ SW建筑  出生区   SE建筑 │  z∈[-29,-14]: 角建筑 + 出生区
##   z=-29  └───南墙────────────┘
##          x=-30  -16    16  30
##
## Godot frame: +X=east, +Z=north, Y=up. North=T spawn, South=CT spawn (mirror).
## T1 实测：站立跳可达 1.39m → 可跳 ≤1.3m；玩家宽 1.0m → 通道 ≥3m、门 ≥2m。

const PLAYER_W := 1.0
const CORRIDOR_MIN := 3.0
const DOOR_MIN := 2.0
const JUMPABLE_MAX := 1.3
const BOUND_X := 30.0
const BOUND_Z := 29.0

# ---- 地面 ----
const GROUNDS := [
	{"name": "Ground", "kind": "ground", "center": Vector3(0, -0.5, 0), "size": Vector3(60, 1, 58)},
]

# ---- 边界墙 ----
const WALLS := [
	{"name": "WallNorth", "kind": "wall", "center": Vector3(0, 2.0, 29.5),   "size": Vector3(60, 4, 1)},
	{"name": "WallSouth", "kind": "wall", "center": Vector3(0, 2.0, -29.5),  "size": Vector3(60, 4, 1)},
	{"name": "WallWest",  "kind": "wall", "center": Vector3(-30.5, 2.0, 0),  "size": Vector3(1, 4, 58)},
	{"name": "WallEast",  "kind": "wall", "center": Vector3(30.5, 2.0, 0),   "size": Vector3(1, 4, 58)},
]

# ---- 中央大厅（20×16×3.0m，内廓 x∈[-10,10] z∈[-8,8]，墙厚 1m）----
# 墙段精确分段：门洞 4m（x/z∈[-2,2]）。墙段贴门洞边界，角落相接（oz/ox=0）不重叠。
const HALL_WALL_SEGMENTS := [
	{"name": "HallWallN_L", "kind": "wall", "center": Vector3(-6.0, 1.5, 8.5), "size": Vector3(8, 3.0, 1)},
	{"name": "HallWallN_R", "kind": "wall", "center": Vector3(6.0, 1.5, 8.5),  "size": Vector3(8, 3.0, 1)},
	{"name": "HallWallS_L", "kind": "wall", "center": Vector3(-6.0, 1.5, -8.5), "size": Vector3(8, 3.0, 1)},
	{"name": "HallWallS_R", "kind": "wall", "center": Vector3(6.0, 1.5, -8.5),  "size": Vector3(8, 3.0, 1)},
	# 西/东墙：z∈[2,8]（上段 center 5 深 6）与 z∈[-8,-2]（下段 center -5 深 6）——贴门洞边界 ±2
	{"name": "HallWallW_T", "kind": "wall", "center": Vector3(-10.5, 1.5, 5.0), "size": Vector3(1, 3.0, 6)},
	{"name": "HallWallW_B", "kind": "wall", "center": Vector3(-10.5, 1.5, -5.0), "size": Vector3(1, 3.0, 6)},
	{"name": "HallWallE_T", "kind": "wall", "center": Vector3(10.5, 1.5, 5.0),  "size": Vector3(1, 3.0, 6)},
	{"name": "HallWallE_B", "kind": "wall", "center": Vector3(10.5, 1.5, -5.0),  "size": Vector3(1, 3.0, 6)},
]

const HALL_DOORS := [
	{"name": "DoorNorth", "center": Vector3(0, 1.5, 8.5),   "gap_x": 4.0},
	{"name": "DoorSouth", "center": Vector3(0, 1.5, -8.5),  "gap_x": 4.0},
	{"name": "DoorWest",  "center": Vector3(-10.5, 1.5, 0), "gap_z": 4.0},
	{"name": "DoorEast",  "center": Vector3(10.5, 1.5, 0),  "gap_z": 4.0},
]

# ---- 大厅柱列（12 根，0.6m 见方，高 2.2m）----
# M2 修复：柱列移到大厅四边贴墙（x∈{±9}, z∈{±7} 靠墙排布）——玩家活动区在中央，
# 柱只做贴墙视线遮挡，玩家不会贴着柱起跳（杜绝胶囊顶柱压跳高卡顿）。
const HALL_PILLARS := [
	# 北墙内沿（z=7.5）
	{"name": "PillarA", "center": Vector3(-6.0, 1.1, 7.5), "size": Vector3(0.6, 2.2, 0.6)},
	{"name": "PillarB", "center": Vector3(-2.0, 1.1, 7.5), "size": Vector3(0.6, 2.2, 0.6)},
	{"name": "PillarC", "center": Vector3(2.0, 1.1, 7.5),  "size": Vector3(0.6, 2.2, 0.6)},
	{"name": "PillarD", "center": Vector3(6.0, 1.1, 7.5),  "size": Vector3(0.6, 2.2, 0.6)},
	# 南墙内沿（z=-7.5）
	{"name": "PillarE", "center": Vector3(-6.0, 1.1, -7.5), "size": Vector3(0.6, 2.2, 0.6)},
	{"name": "PillarF", "center": Vector3(-2.0, 1.1, -7.5), "size": Vector3(0.6, 2.2, 0.6)},
	{"name": "PillarG", "center": Vector3(2.0, 1.1, -7.5),  "size": Vector3(0.6, 2.2, 0.6)},
	{"name": "PillarH", "center": Vector3(6.0, 1.1, -7.5),  "size": Vector3(0.6, 2.2, 0.6)},
	# 西墙内沿（x=-9.5）
	{"name": "PillarI", "center": Vector3(-9.5, 1.1, -3.0), "size": Vector3(0.6, 2.2, 0.6)},
	{"name": "PillarJ", "center": Vector3(-9.5, 1.1, 3.0),  "size": Vector3(0.6, 2.2, 0.6)},
	# 东墙内沿（x=9.5）
	{"name": "PillarK", "center": Vector3(9.5, 1.1, -3.0),  "size": Vector3(0.6, 2.2, 0.6)},
	{"name": "PillarL", "center": Vector3(9.5, 1.1, 3.0),   "size": Vector3(0.6, 2.2, 0.6)},
]

# ---- 大厅内隔断墙（1.4m 高，不可跳跃——室内跳上会被 3m 天花板卡住；分割南北区）----
const HALL_DIVIDERS := [
	{"name": "DividerN", "kind": "cover", "center": Vector3(-4.0, 0.7, 2.0), "size": Vector3(7.0, 1.4, 0.5)},
	{"name": "DividerS", "kind": "cover", "center": Vector3(4.0, 0.7, -2.0),  "size": Vector3(7.0, 1.4, 0.5)},
]

# ---- 大厅屋顶（4.5m 高——M2 修复：原 3.25m 底面 3.0m 低于玩家跳跃顶 3.22m，跳上被屋顶压住卡顿）----
# 底面 4.25m > 跳跃顶 3.22m（站高1.83+跳1.39），玩家在大厅任意位置跳跃不撞屋顶
const HALL_ROOF := [
	{"name": "HallRoofN", "kind": "roof", "center": Vector3(0, 4.25, 4.0), "size": Vector3(20, 0.5, 6.0)},
	{"name": "HallRoofS", "kind": "roof", "center": Vector3(0, 4.25, -4.0), "size": Vector3(20, 0.5, 6.0)},
]

# ---- 大厅门框（门洞两侧框柱，贴墙段内沿，不与墙段重叠；4m 门洞）----
const HALL_DOOR_FRAMES := [
	{"name": "DoorFrameN_L", "kind": "wall", "center": Vector3(-2.2, 1.5, 8.5), "size": Vector3(0.4, 3.0, 1.4)},
	{"name": "DoorFrameN_R", "kind": "wall", "center": Vector3(2.2, 1.5, 8.5),  "size": Vector3(0.4, 3.0, 1.4)},
	{"name": "DoorFrameS_L", "kind": "wall", "center": Vector3(-2.2, 1.5, -8.5), "size": Vector3(0.4, 3.0, 1.4)},
	{"name": "DoorFrameS_R", "kind": "wall", "center": Vector3(2.2, 1.5, -8.5),  "size": Vector3(0.4, 3.0, 1.4)},
	{"name": "DoorFrameW_T", "kind": "wall", "center": Vector3(-10.5, 1.5, 2.2), "size": Vector3(1.4, 3.0, 0.4)},
	{"name": "DoorFrameW_B", "kind": "wall", "center": Vector3(-10.5, 1.5, -2.2), "size": Vector3(1.4, 3.0, 0.4)},
	{"name": "DoorFrameE_T", "kind": "wall", "center": Vector3(10.5, 1.5, 2.2),  "size": Vector3(1.4, 3.0, 0.4)},
	{"name": "DoorFrameE_B", "kind": "wall", "center": Vector3(10.5, 1.5, -2.2),  "size": Vector3(1.4, 3.0, 0.4)},
]

# ---- 四角建筑（14×15m 外廓，2 门朝地图中心，内部 CQB，1.2m 屋顶盖后半可跳上俯瞰街道）----
# 角建筑外廓：x∈[cx-7, cx+7], z∈[cz-7.5, cz+7.5]（14 宽 × 15 深）
# 角落规则：墙段从外廓边界起、到相邻垂墙外沿止（角落 ox=0/oz=0 相接，不重叠不露缝）。
# 门洞：朝向地图中心的两面墙各留 3m 门洞（居中）。
# 由 _corner_walls() 生成——避免手算坐标误差。
static func _corner_walls() -> Array:
	var out := []
	# 四角建筑规格（外廓 + 门朝向）
	var corners := [
		{"name": "NW", "cx": -23.0, "cz": 21.5},   # 门朝 东(E) + 南(S)
		{"name": "NE", "cx": 23.0,  "cz": 21.5},   # 门朝 西(W) + 南(S)
		{"name": "SW", "cx": -23.0, "cz": -21.5},  # 门朝 东(E) + 北(N)
		{"name": "SE", "cx": 23.0,  "cz": -21.5},  # 门朝 西(W) + 北(N)
	]
	for c in corners:
		var n: String = c["name"]
		var cx: float = c["cx"]
		var cz: float = c["cz"]
		var x0 := cx - 7.0   # 外廓西沿
		var x1 := cx + 7.0   # 外廓东沿
		var z0 := cz - 7.5   # 外廓南沿
		var z1 := cz + 7.5   # 外廓北沿
		# 门朝向（朝地图中心的两面）
		var door_e := n.contains("W")   # NW/SW 东墙开门（朝东街）
		var door_s := n.contains("N")   # NW/NE 南墙开门（朝南街）
		# --- 北墙（z1，横跨 x0..x1）---
		out.append({"name": n + "Wall_N", "kind": "wall", "center": Vector3((x0 + x1) * 0.5, 1.5, z1 - 0.5), "size": Vector3(x1 - x0, 3.0, 1)})
		# --- 南墙（z0，若开门则分两段）---
		if door_s:
			# 门洞 3m：x∈[cx-1.5, cx+1.5]
			out.append({"name": n + "Wall_S_L", "kind": "wall", "center": Vector3((x0 + cx - 1.5) * 0.5, 1.5, z0 + 0.5), "size": Vector3((cx - 1.5) - x0, 3.0, 1)})
			out.append({"name": n + "Wall_S_R", "kind": "wall", "center": Vector3((cx + 1.5 + x1) * 0.5, 1.5, z0 + 0.5), "size": Vector3(x1 - (cx + 1.5), 3.0, 1)})
		else:
			out.append({"name": n + "Wall_S", "kind": "wall", "center": Vector3((x0 + x1) * 0.5, 1.5, z0 + 0.5), "size": Vector3(x1 - x0, 3.0, 1)})
		# --- 东墙（x1，若开门则分两段）---
		if door_e:
			out.append({"name": n + "Wall_E_T", "kind": "wall", "center": Vector3(x1 - 0.5, 1.5, (cz + 1.5 + z1) * 0.5), "size": Vector3(1, 3.0, z1 - (cz + 1.5))})
			out.append({"name": n + "Wall_E_B", "kind": "wall", "center": Vector3(x1 - 0.5, 1.5, (z0 + cz - 1.5) * 0.5), "size": Vector3(1, 3.0, (cz - 1.5) - z0)})
		else:
			out.append({"name": n + "Wall_E", "kind": "wall", "center": Vector3(x1 - 0.5, 1.5, (z0 + z1) * 0.5), "size": Vector3(1, 3.0, z1 - z0)})
		# --- 西墙（x0）---
		out.append({"name": n + "Wall_W", "kind": "wall", "center": Vector3(x0 + 0.5, 1.5, (z0 + z1) * 0.5), "size": Vector3(1, 3.0, z1 - z0)})
	return out

# ---- 角建筑内部（开放院落，无屋顶——室内 1.2m 屋顶下净高不足 1.83m 会卡玩家）----
# 内部：两道 1.4m 隔断墙分割 3 个 CQB 区（不可跳）+ 贴墙 0.9m 箱堆（低掩体）
static func _corner_interiors() -> Array:
	var out := []
	var corners := [
		{"name": "NW", "cx": -23.0, "cz": 21.5},
		{"name": "NE", "cx": 23.0,  "cz": 21.5},
		{"name": "SW", "cx": -23.0, "cz": -21.5},
		{"name": "SE", "cx": 23.0,  "cz": -21.5},
	]
	for c in corners:
		var n: String = c["name"]
		var cx: float = c["cx"]
		var cz: float = c["cz"]
		# 两道 1.4m 隔断墙（把内部 14×13 分成 3 个 CQB 区）
		out.append({"name": n + "IntWall1", "kind": "cover", "center": Vector3(cx, 0.7, cz - 3.5), "size": Vector3(10.0, 1.4, 0.5)})
		out.append({"name": n + "IntWall2", "kind": "cover", "center": Vector3(cx, 0.7, cz + 2.5), "size": Vector3(10.0, 1.4, 0.5)})
		# 贴外墙 0.9m 箱堆（低掩体，不可跳——0.9m 起跳仍会顶屋顶？无屋顶则室外可跳，但保持低矮避免挡视线）
		out.append({"name": n + "IntBox1", "kind": "cover", "center": Vector3(cx - 5.0, 0.45, cz + 5.0), "size": Vector3(2.0, 0.9, 1.0)})
		out.append({"name": n + "IntBox2", "kind": "cover", "center": Vector3(cx + 5.0, 0.45, cz - 5.0), "size": Vector3(2.0, 0.9, 1.0)})
	return out

# ---- 街道掩体（环形街道：西街 x∈[-16,-11]、东街 x∈[11,16]、北街 z∈[9,14]、南街 z∈[-14,-9]）----
# 西/东街交火组件组（参考 dust2 mid / bloodstrike 街道掩体模式）：
#   中央 1.2m 高台（室外可跳，压制街道/看路口）+ 两侧 0.9m 蹲掩体 + 横向 1.4m 隔断墙（分割通道）
const COVERS := [
	# ===== 西街（x∈[-16,-11]，5m 宽）=====
	# 中央高台（可跳压制）——用 2 级 0.6m 微台阶替代 1.2m 垂直面（杜绝跳上卡角：玩家逐级走上）
	{"name": "WestHigh1_Base", "kind": "cover", "center": Vector3(-13.5, 0.3, -4.5), "size": Vector3(2.0, 0.6, 1.5)},
	{"name": "WestHigh1_Top", "kind": "cover", "center": Vector3(-13.5, 0.9, -4.5), "size": Vector3(1.6, 0.6, 1.1)},
	{"name": "WestHigh2_Base", "kind": "cover", "center": Vector3(-13.5, 0.3, 4.5), "size": Vector3(2.0, 0.6, 1.5)},
	{"name": "WestHigh2_Top", "kind": "cover", "center": Vector3(-13.5, 0.9, 4.5), "size": Vector3(1.6, 0.6, 1.1)},
	# 贴西墙 0.9m 蹲掩体
	{"name": "WestBox1", "kind": "cover", "center": Vector3(-14.5, 0.45, -6), "size": Vector3(1.0, 0.9, 1.0)},
	{"name": "WestBox2", "kind": "cover", "center": Vector3(-14.5, 0.45, 6), "size": Vector3(1.0, 0.9, 1.0)},
	# 横向 1.4m 隔断墙（z∈[-1.5,1.5] 中央；高台在 z=±4.5 → 通道 3m）
	{"name": "WestWall1", "kind": "cover", "center": Vector3(-14.5, 0.7, 0), "size": Vector3(1.0, 1.4, 3.0)},
	# ===== 东街（x∈[11,16]，5m 宽）=====
	# 中央高台（可跳压制）——2 级 0.6m 微台阶（杜绝跳上卡角）
	{"name": "EastHigh1_Base", "kind": "cover", "center": Vector3(13.5, 0.3, -4.5), "size": Vector3(2.0, 0.6, 1.5)},
	{"name": "EastHigh1_Top", "kind": "cover", "center": Vector3(13.5, 0.9, -4.5), "size": Vector3(1.6, 0.6, 1.1)},
	{"name": "EastHigh2_Base", "kind": "cover", "center": Vector3(13.5, 0.3, 4.5), "size": Vector3(2.0, 0.6, 1.5)},
	{"name": "EastHigh2_Top", "kind": "cover", "center": Vector3(13.5, 0.9, 4.5), "size": Vector3(1.6, 0.6, 1.1)},
	# 贴东墙 0.9m 蹲掩体
	{"name": "EastBox1", "kind": "cover", "center": Vector3(14.5, 0.45, -6), "size": Vector3(1.0, 0.9, 1.0)},
	{"name": "EastBox2", "kind": "cover", "center": Vector3(14.5, 0.45, 6), "size": Vector3(1.0, 0.9, 1.0)},
	# 横向 1.4m 隔断墙（z∈[-1.5,1.5] 中央）
	{"name": "EastWall1", "kind": "cover", "center": Vector3(14.5, 0.7, 0), "size": Vector3(1.0, 1.4, 3.0)},
	# 北街箱堆
	{"name": "BoxN1", "kind": "cover", "center": Vector3(-4, 0.45, 11.5), "size": Vector3(1.0, 0.9, 1.0)},
	{"name": "BoxN2", "kind": "cover", "center": Vector3(4, 0.45, 11.5), "size": Vector3(1.0, 0.9, 1.0)},
	# 南街箱堆
	{"name": "BoxS1", "kind": "cover", "center": Vector3(-4, 0.45, -11.5), "size": Vector3(1.0, 0.9, 1.0)},
	{"name": "BoxS2", "kind": "cover", "center": Vector3(4, 0.45, -11.5), "size": Vector3(1.0, 0.9, 1.0)},
]

# ---- 街道绿化/零散组件（用户：两侧太空——植物/矮墙碎片填充，营造城市感 + 散点掩体）----
const GREENERY := [
	# 西街外侧（x≈-17.5，贴西边界墙）：树/花坛/长凳
	{"name": "TreeW1", "kind": "decor", "center": Vector3(-18.0, 1.0, -10), "size": Vector3(0.8, 2.0, 0.8)},
	{"name": "TreeW2", "kind": "decor", "center": Vector3(-18.0, 1.0, 10), "size": Vector3(0.8, 2.0, 0.8)},
	{"name": "PlanterW1", "kind": "cover", "center": Vector3(-17.0, 0.5, -5), "size": Vector3(1.2, 1.0, 1.2)},
	{"name": "PlanterW2", "kind": "cover", "center": Vector3(-17.0, 0.5, 5), "size": Vector3(1.2, 1.0, 1.2)},
	{"name": "BenchW1", "kind": "cover", "center": Vector3(-17.0, 0.4, 0), "size": Vector3(1.6, 0.8, 0.6)},
	# 东街外侧（x≈17.5，贴东边界墙）
	{"name": "TreeE1", "kind": "decor", "center": Vector3(18.0, 1.0, -10), "size": Vector3(0.8, 2.0, 0.8)},
	{"name": "TreeE2", "kind": "decor", "center": Vector3(18.0, 1.0, 10), "size": Vector3(0.8, 2.0, 0.8)},
	{"name": "PlanterE1", "kind": "cover", "center": Vector3(17.0, 0.5, -5), "size": Vector3(1.2, 1.0, 1.2)},
	{"name": "PlanterE2", "kind": "cover", "center": Vector3(17.0, 0.5, 5), "size": Vector3(1.2, 1.0, 1.2)},
	{"name": "BenchE1", "kind": "cover", "center": Vector3(17.0, 0.4, 0), "size": Vector3(1.6, 0.8, 0.6)},
	# 北街/南街绿化（稀疏点缀）
	{"name": "TreeN1", "kind": "decor", "center": Vector3(-8, 1.0, 13.5), "size": Vector3(0.8, 2.0, 0.8)},
	{"name": "TreeN2", "kind": "decor", "center": Vector3(8, 1.0, 13.5), "size": Vector3(0.8, 2.0, 0.8)},
	{"name": "TreeS1", "kind": "decor", "center": Vector3(-8, 1.0, -13.5), "size": Vector3(0.8, 2.0, 0.8)},
	{"name": "TreeS2", "kind": "decor", "center": Vector3(8, 1.0, -13.5), "size": Vector3(0.8, 2.0, 0.8)},
	# 大厅四角外散碎矮墙（0.9m 掩体碎片，填空白）
	{"name": "Scrap1", "kind": "cover", "center": Vector3(-13, 0.45, -11), "size": Vector3(1.0, 0.9, 1.0)},
	{"name": "Scrap2", "kind": "cover", "center": Vector3(13, 0.45, -11), "size": Vector3(1.0, 0.9, 1.0)},
	{"name": "Scrap3", "kind": "cover", "center": Vector3(-13, 0.45, 11), "size": Vector3(1.0, 0.9, 1.0)},
	{"name": "Scrap4", "kind": "cover", "center": Vector3(13, 0.45, 11), "size": Vector3(1.0, 0.9, 1.0)},
]

# ---- 两侧交火区加粗（用户：左右两侧太空——加大树（有碰撞）+ 墙体碎片）----
# 大树 = kind "bigtree"：有碰撞体积（Box 0.7×2.5×0.7 近似树干），视觉树干+树冠。
# 小树保持 decor 无碰撞（用户确认保留）。
const BIG_TREES := [
	# 西街外侧（x∈[-21,-18] 空地，西边界墙 -30）— 中心 y=1.25（树干从地面到 2.5m）
	{"name": "BigTreeW1", "kind": "bigtree", "center": Vector3(-19.0, 1.25, -7), "size": Vector3(0.7, 2.5, 0.7)},
	{"name": "BigTreeW2", "kind": "bigtree", "center": Vector3(-20.5, 1.25, -2), "size": Vector3(0.7, 2.5, 0.7)},
	{"name": "BigTreeW3", "kind": "bigtree", "center": Vector3(-19.0, 1.25, 3), "size": Vector3(0.7, 2.5, 0.7)},
	{"name": "BigTreeW4", "kind": "bigtree", "center": Vector3(-20.5, 1.25, 8), "size": Vector3(0.7, 2.5, 0.7)},
	# 东街外侧（x∈[18,21] 空地）
	{"name": "BigTreeE1", "kind": "bigtree", "center": Vector3(19.0, 1.25, -7), "size": Vector3(0.7, 2.5, 0.7)},
	{"name": "BigTreeE2", "kind": "bigtree", "center": Vector3(20.5, 1.25, -2), "size": Vector3(0.7, 2.5, 0.7)},
	{"name": "BigTreeE3", "kind": "bigtree", "center": Vector3(19.0, 1.25, 3), "size": Vector3(0.7, 2.5, 0.7)},
	{"name": "BigTreeE4", "kind": "bigtree", "center": Vector3(20.5, 1.25, 8), "size": Vector3(0.7, 2.5, 0.7)},
	# 南北带两侧（x=±15.5 空旷带）
	{"name": "BigTreeN1", "kind": "bigtree", "center": Vector3(-15.5, 1.25, 16.5), "size": Vector3(0.7, 2.5, 0.7)},
	{"name": "BigTreeN2", "kind": "bigtree", "center": Vector3(15.5, 1.25, 16.5), "size": Vector3(0.7, 2.5, 0.7)},
	{"name": "BigTreeS1", "kind": "bigtree", "center": Vector3(-15.5, 1.25, -16.5), "size": Vector3(0.7, 2.5, 0.7)},
	{"name": "BigTreeS2", "kind": "bigtree", "center": Vector3(15.5, 1.25, -16.5), "size": Vector3(0.7, 2.5, 0.7)},
]

# ---- 两侧墙体碎片（西/东街 + 南北带补充短墙，形成更多交火位）----
const SIDE_WALLS := [
	# 西街（已有 WestWall1 在 z=0）补充上下段
	{"name": "WestWall2", "kind": "cover", "center": Vector3(-14.5, 0.7, -2.5), "size": Vector3(1.0, 1.4, 2.0)},
	{"name": "WestWall3", "kind": "cover", "center": Vector3(-14.5, 0.7, 2.5), "size": Vector3(1.0, 1.4, 2.0)},
	# 东街（已有 EastWall1）补充上下段
	{"name": "EastWall2", "kind": "cover", "center": Vector3(14.5, 0.7, -2.5), "size": Vector3(1.0, 1.4, 2.0)},
	{"name": "EastWall3", "kind": "cover", "center": Vector3(14.5, 0.7, 2.5), "size": Vector3(1.0, 1.4, 2.0)},
	# 南北带补充短墙（错开已有 NMid/SMid 墙）— z=17 远离出生建筑南墙 19.5（缝 1.75m）
	{"name": "NWall5", "kind": "cover", "center": Vector3(0, 0.7, 17.0), "size": Vector3(2.0, 1.4, 0.5)},
	{"name": "SWall5", "kind": "cover", "center": Vector3(0, 0.7, -17.0), "size": Vector3(2.0, 1.4, 0.5)},
	# 大厅四角外补充碎墙（Scrap5-8）
	{"name": "Scrap5", "kind": "cover", "center": Vector3(-13, 0.45, -13), "size": Vector3(1.0, 0.9, 1.0)},
	{"name": "Scrap6", "kind": "cover", "center": Vector3(13, 0.45, -13), "size": Vector3(1.0, 0.9, 1.0)},
	{"name": "Scrap7", "kind": "cover", "center": Vector3(-13, 0.45, 13), "size": Vector3(1.0, 0.9, 1.0)},
	{"name": "Scrap8", "kind": "cover", "center": Vector3(13, 0.45, 13), "size": Vector3(1.0, 0.9, 1.0)},
]

# ---- 南北中间带填充（用户：两侧仍太空——z∈[14,21]/-[21,-14] 空带）----
# 布局：四条横向矮墙（分割南北通道形成对枪位）+ 中央箱堆掩体 + 两侧树
const NORTH_MID_FILL := [
	# 横向 1.4m 矮墙（北带，z≈17 和 z≈19，错开排列形成曲折通道）
	{"name": "NMidWall1", "kind": "cover", "center": Vector3(-8, 0.7, 17.0), "size": Vector3(4.0, 1.4, 0.5)},
	{"name": "NMidWall2", "kind": "cover", "center": Vector3(8, 0.7, 17.5), "size": Vector3(4.0, 1.4, 0.5)},
	{"name": "NMidWall3", "kind": "cover", "center": Vector3(-12, 0.7, 19.5), "size": Vector3(3.0, 1.4, 0.5)},
	{"name": "NMidWall4", "kind": "cover", "center": Vector3(12, 0.7, 16.5), "size": Vector3(3.0, 1.4, 0.5)},
	# 中央箱堆（北带）
	{"name": "NMidBox1", "kind": "cover", "center": Vector3(0, 0.45, 16.0), "size": Vector3(1.0, 0.9, 1.0)},
	{"name": "NMidBox2", "kind": "cover", "center": Vector3(0, 0.45, 20.5), "size": Vector3(1.0, 0.9, 1.0)},
	# 树（x=±5 中央区装饰，纯视觉无碰撞——不参与掩体/窄缝判定）
	{"name": "NMidTree1", "kind": "decor", "center": Vector3(-5, 1.0, 17.0), "size": Vector3(0.8, 2.0, 0.8)},
	{"name": "NMidTree2", "kind": "decor", "center": Vector3(5, 1.0, 17.0), "size": Vector3(0.8, 2.0, 0.8)},
	{"name": "NMidTree3", "kind": "decor", "center": Vector3(-5, 1.0, 18.0), "size": Vector3(0.8, 2.0, 0.8)},
	{"name": "NMidTree4", "kind": "decor", "center": Vector3(5, 1.0, 18.0), "size": Vector3(0.8, 2.0, 0.8)},
]
const SOUTH_MID_FILL := [
	# 横向 1.4m 矮墙（南带，z≈-17 和 z≈-19，错开排列）
	{"name": "SMidWall1", "kind": "cover", "center": Vector3(-8, 0.7, -17.0), "size": Vector3(4.0, 1.4, 0.5)},
	{"name": "SMidWall2", "kind": "cover", "center": Vector3(8, 0.7, -17.5), "size": Vector3(4.0, 1.4, 0.5)},
	{"name": "SMidWall3", "kind": "cover", "center": Vector3(-12, 0.7, -19.5), "size": Vector3(3.0, 1.4, 0.5)},
	{"name": "SMidWall4", "kind": "cover", "center": Vector3(12, 0.7, -16.5), "size": Vector3(3.0, 1.4, 0.5)},
	# 中央箱堆（南带）— SMidBox1 移 z=-15 避开 CarM1(z=-16)
	{"name": "SMidBox1", "kind": "cover", "center": Vector3(0, 0.45, -15.0), "size": Vector3(1.0, 0.9, 1.0)},
	{"name": "SMidBox2", "kind": "cover", "center": Vector3(0, 0.45, -20.5), "size": Vector3(1.0, 0.9, 1.0)},
	# 树（x=±5 中央区装饰，纯视觉无碰撞——不参与掩体/窄缝判定）
	{"name": "SMidTree1", "kind": "decor", "center": Vector3(-5, 1.0, -17.0), "size": Vector3(0.8, 2.0, 0.8)},
	{"name": "SMidTree2", "kind": "decor", "center": Vector3(5, 1.0, -17.0), "size": Vector3(0.8, 2.0, 0.8)},
	{"name": "SMidTree3", "kind": "decor", "center": Vector3(-5, 1.0, -18.0), "size": Vector3(0.8, 2.0, 0.8)},
	{"name": "SMidTree4", "kind": "decor", "center": Vector3(5, 1.0, -18.0), "size": Vector3(0.8, 2.0, 0.8)},
]

# ---- 出生建筑（用户：双方出生点用封顶建筑围起来，左右两个出口）----
# 建筑 12×10×3.0m（x∈[-6,6], z∈[19,29] 北 / [-29,-19] 南），贴边界墙（北墙=地图北界），屋顶封顶。
# 出口：西墙/东墙中部各留 3m 门洞（z∈[21.5,24.5]，中心 23）——左右两个出口。
const SPAWN_BUILDINGS := [
	# ===== 北（T 出生）=====
	{"name": "SpawnB_N_WallN", "kind": "wall", "center": Vector3(0, 1.5, 28.5), "size": Vector3(12, 3.0, 1)},     # 北墙（贴地图北界，内沿 29）
	{"name": "SpawnB_N_WallS", "kind": "wall", "center": Vector3(0, 1.5, 19.5), "size": Vector3(12, 3.0, 1)},     # 南墙（面向地图）
	# 西墙两段（出口 z∈[21.5,24.5]）：北段 z∈[24.5,28.5]（中心 26.5 深 4）、南段 z∈[19,21.5]（中心 20.25 深 2.5）
	{"name": "SpawnB_N_WallW_T", "kind": "wall", "center": Vector3(-6.5, 1.5, 26.5), "size": Vector3(1, 3.0, 4)},
	{"name": "SpawnB_N_WallW_B", "kind": "wall", "center": Vector3(-6.5, 1.5, 20.25), "size": Vector3(1, 3.0, 2.5)},
	# 东墙两段（出口 z∈[21.5,24.5]）
	{"name": "SpawnB_N_WallE_T", "kind": "wall", "center": Vector3(6.5, 1.5, 26.5), "size": Vector3(1, 3.0, 4)},
	{"name": "SpawnB_N_WallE_B", "kind": "wall", "center": Vector3(6.5, 1.5, 20.25), "size": Vector3(1, 3.0, 2.5)},
	{"name": "SpawnB_N_Roof", "kind": "roof", "center": Vector3(0, 3.0, 24), "size": Vector3(12, 0.5, 10)},       # 封顶
	# ===== 南（CT 出生）=====
	{"name": "SpawnB_S_WallN", "kind": "wall", "center": Vector3(0, 1.5, -19.5), "size": Vector3(12, 3.0, 1)},    # 北墙（面向地图）
	{"name": "SpawnB_S_WallS", "kind": "wall", "center": Vector3(0, 1.5, -28.5), "size": Vector3(12, 3.0, 1)},    # 南墙（贴地图南界，内沿 -29）
	# 西墙两段（出口 z∈[-24.5,-21.5]）
	{"name": "SpawnB_S_WallW_T", "kind": "wall", "center": Vector3(-6.5, 1.5, -20.25), "size": Vector3(1, 3.0, 2.5)},
	{"name": "SpawnB_S_WallW_B", "kind": "wall", "center": Vector3(-6.5, 1.5, -26.5), "size": Vector3(1, 3.0, 4)},
	# 东墙两段（出口 z∈[-24.5,-21.5]）
	{"name": "SpawnB_S_WallE_T", "kind": "wall", "center": Vector3(6.5, 1.5, -20.25), "size": Vector3(1, 3.0, 2.5)},
	{"name": "SpawnB_S_WallE_B", "kind": "wall", "center": Vector3(6.5, 1.5, -26.5), "size": Vector3(1, 3.0, 4)},
	{"name": "SpawnB_S_Roof", "kind": "roof", "center": Vector3(0, 3.0, -24), "size": Vector3(12, 0.5, 10)},       # 封顶
]

# ---- all solids ----
static func all_solids() -> Array:
	var out := []
	out.append_array(GROUNDS)
	out.append_array(WALLS)
	out.append_array(HALL_WALL_SEGMENTS)
	out.append_array(HALL_PILLARS)
	out.append_array(HALL_DIVIDERS)
	out.append_array(HALL_ROOF)
	out.append_array(HALL_DOOR_FRAMES)
	out.append_array(_corner_walls())
	out.append_array(_corner_interiors())
	out.append_array(COVERS)
	out.append_array(GREENERY)
	out.append_array(BIG_TREES)
	out.append_array(SIDE_WALLS)
	out.append_array(NORTH_MID_FILL)
	out.append_array(SOUTH_MID_FILL)
	out.append_array(SPAWN_BUILDINGS)
	return out

static func hall_center() -> Vector3:
	return Vector3(0, 0, 0)

static func hall_size() -> Vector3:
	return Vector3(20, 3.0, 16)
