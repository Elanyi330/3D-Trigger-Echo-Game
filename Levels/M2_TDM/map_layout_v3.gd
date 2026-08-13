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
	# 斜板 4 块（建筑元素，高 2.1：底 0.6 坐台面、顶 2.7 齐回廊板底——任务 9 A1 贴基座修复，
	# 2026-08-11。brief 原文 center.y=1.7，但 y=1.7 时顶 2.75 侵入回廊板底 2.7（重叠 0.05）
	# 且底 0.65 浮空、boost 门禁 22 对违规；size 2.1 介于台面 0.6 与回廊底 2.7 之间的
	# 唯一无冲突 center.y = 1.65（x/z 均按 brief 执行）。已记入报告待控制器确认。
	# 残留窄缝修复：贴基座后 A/A2 与坡道 Step8 夹 0.6m 缝（z 投影进入坡道带），
	# A/A2 center.x ±1.5→±0.9 内收，缝恰 1.2 合法（L 形互保/面接触/对称保持）。
	# A/B 南对 + A2/B2 = 180° 旋转）
	{"name": "AltarSlabA", "kind": "cover", "center": Vector3(-0.9, 1.65, -2.2), "size": Vector3(3, 2.1, 0.4)},
	{"name": "AltarSlabB", "kind": "cover", "center": Vector3(2.2, 1.65, -1.5), "size": Vector3(0.4, 2.1, 3)},
	{"name": "AltarSlabA2", "kind": "cover", "center": Vector3(0.9, 1.65, 2.2), "size": Vector3(3, 2.1, 0.4)},
	{"name": "AltarSlabB2", "kind": "cover", "center": Vector3(-2.2, 1.65, 1.5), "size": Vector3(0.4, 2.1, 3)},
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
	# 组合柱 ×4（角柱掩体 + 伞顶支柱，底 3.0 顶 7.1；任务 9 A3：外移至 ±3.05 贴栏板——
	# 柱面 x/z=±3.3 与 N/S 栏板内缘 z=±3.3、E/W 栏板内缘 x=±3.3 面接触）
	{"name": "Pillar_NE", "kind": "cover", "center": Vector3(3.05, 5.05, 3.05), "size": Vector3(0.5, 4.1, 0.5)},
	{"name": "Pillar_NW", "kind": "cover", "center": Vector3(-3.05, 5.05, 3.05), "size": Vector3(0.5, 4.1, 0.5)},
	{"name": "Pillar_SE", "kind": "cover", "center": Vector3(3.05, 5.05, -3.05), "size": Vector3(0.5, 4.1, 0.5)},
	{"name": "Pillar_SW", "kind": "cover", "center": Vector3(-3.05, 5.05, -3.05), "size": Vector3(0.5, 4.1, 0.5)},
	# 伞顶 4 板（厚 0.4，底面 7.1；中央 x/z∈[-1.5,1.5] 开敞 = 雷口）
	{"name": "UmbrellaN", "kind": "cover", "center": Vector3(0, 7.3, 2.75), "size": Vector3(8, 0.4, 2.5)},
	{"name": "UmbrellaS", "kind": "cover", "center": Vector3(0, 7.3, -2.75), "size": Vector3(8, 0.4, 2.5)},
	{"name": "UmbrellaW", "kind": "cover", "center": Vector3(-2.75, 7.3, 0), "size": Vector3(2.5, 0.4, 3)},
	{"name": "UmbrellaE", "kind": "cover", "center": Vector3(2.75, 7.3, 0), "size": Vector3(2.5, 0.4, 3)},
	# 钟饰（无碰撞 weenie，顶 ~9.5）
	{"name": "BellDecor", "kind": "decor", "center": Vector3(0, 8.6, 0), "size": Vector3(1.2, 1.8, 1.2)},
]
# ---- 任务 3：坡道（生成器产出）+ 祭坛台微台阶（手写）----
# GDScript const 不允许函数调用，故表为 static var（外部访问方式 V3.RAMPS 不变）。
# 西坡道 z_from/z_to = 东坡道的 180° 旋转像 z∈[-2.5,3.5]（任务 8 对称修复，2026-08-11；
# 原参数 (2.5,-3.5) 与东坡道同跨度，破坏全局旋转对称）；末级 z∈[-2.5,-1.75] 仍落 W 栏豁口。
# 任务 9 A2（2026-08-11）：坡道外移 0.1（x 3.6..6.6 / -6.6..-3.6）——B 板贴基座后
# B↔坡道缝恰 1.2；基座↔坡道缝 1.6；坡道↔回廊板缝 0.1 但垂直重叠仅 0.3<0.8 扫描豁免。
static var RAMPS: Array = _ramp_steps(3.6, 6.6, -3.5, 2.5, 0.6, 3.0, "RampE", 8) \
		+ _ramp_steps(-6.6, -3.6, 3.5, -2.5, 0.6, 3.0, "RampW", 8) \
		+ [
	# 祭坛台微台阶（N/S 缘各两级，供 AI 行走登台；坐广场地面，盒底 0，不在台面上）
	{"name": "MicroN1", "kind": "cover", "center": Vector3(0, 0.15, -5.45), "size": Vector3(2, 0.3, 0.3)},
	{"name": "MicroN2", "kind": "cover", "center": Vector3(0, 0.3, -5.15), "size": Vector3(2, 0.6, 0.3)},
	{"name": "MicroS1", "kind": "cover", "center": Vector3(0, 0.15, 5.45), "size": Vector3(2, 0.3, 0.3)},
	{"name": "MicroS2", "kind": "cover", "center": Vector3(0, 0.3, 5.15), "size": Vector3(2, 0.6, 0.3)},
]
# ---- 任务 4：东/西市街（长墙 + 水塔 + 摊位簇 + 摊阁 + 塔坡道）----
# 塔坡道为生成器产出，GDScript const 不允许函数调用，故表为 static var（同 RAMPS）。
static var STREETS: Array = [
	# 长墙（高 3 厚 1；豁口 z∈[5.5,8]∪[-8,-5.5] 各 2.5m 通外环）
	{"name": "EastWall_S", "kind": "wall", "center": Vector3(23, 1.5, -11), "size": Vector3(1, 3, 6)},
	{"name": "EastWall_M", "kind": "wall", "center": Vector3(23, 1.5, 0), "size": Vector3(1, 3, 11)},
	{"name": "EastWall_N", "kind": "wall", "center": Vector3(23, 1.5, 11), "size": Vector3(1, 3, 6)},
	{"name": "WestWall_S", "kind": "wall", "center": Vector3(-23, 1.5, -11), "size": Vector3(1, 3, 6)},
	{"name": "WestWall_M", "kind": "wall", "center": Vector3(-23, 1.5, 0), "size": Vector3(1, 3, 11)},
	{"name": "WestWall_N", "kind": "wall", "center": Vector3(-23, 1.5, 11), "size": Vector3(1, 3, 6)},
	# 西望楼：台体（顶 2.5）+ 栏板（北向 2m 豁口朝坡道落点）+ 台上箱
	# （任务 9 A5：箱居中台顶 (±18.5, 2.95, 0) 四向栏板缝 1.4；brief 原文东箱 x=17.5
	# 残留 0.4m 窄缝且破旋转对称，扫描后按最小修复归位 18.5，已记入报告）
	{"name": "WestTower", "kind": "wall", "center": Vector3(-18.5, 1.25, 0), "size": Vector3(4, 2.5, 4)},
	{"name": "WestTowerRailN_1", "kind": "cover", "center": Vector3(-20, 2.95, 1.9), "size": Vector3(1, 0.9, 0.2)},
	{"name": "WestTowerRailN_2", "kind": "cover", "center": Vector3(-17, 2.95, 1.9), "size": Vector3(1, 0.9, 0.2)},
	{"name": "WestTowerRailS", "kind": "cover", "center": Vector3(-18.5, 2.95, -1.9), "size": Vector3(4, 0.9, 0.2)},
	{"name": "WestTowerRailE", "kind": "cover", "center": Vector3(-16.6, 2.95, 0), "size": Vector3(0.2, 0.9, 3.6)},
	{"name": "WestTowerRailW", "kind": "cover", "center": Vector3(-20.4, 2.95, 0), "size": Vector3(0.2, 0.9, 3.6)},
	{"name": "WestTowerBox", "kind": "cover", "center": Vector3(-18.5, 2.95, 0), "size": Vector3(0.8, 0.9, 0.8)},
	# 东水塔 = 180° 旋转（南向豁口）
	{"name": "EastTower", "kind": "wall", "center": Vector3(18.5, 1.25, 0), "size": Vector3(4, 2.5, 4)},
	{"name": "EastTowerRailS_1", "kind": "cover", "center": Vector3(20, 2.95, -1.9), "size": Vector3(1, 0.9, 0.2)},
	{"name": "EastTowerRailS_2", "kind": "cover", "center": Vector3(17, 2.95, -1.9), "size": Vector3(1, 0.9, 0.2)},
	{"name": "EastTowerRailN", "kind": "cover", "center": Vector3(18.5, 2.95, 1.9), "size": Vector3(4, 0.9, 0.2)},
	{"name": "EastTowerRailW", "kind": "cover", "center": Vector3(16.6, 2.95, 0), "size": Vector3(0.2, 0.9, 3.6)},
	{"name": "EastTowerRailE", "kind": "cover", "center": Vector3(20.4, 2.95, 0), "size": Vector3(0.2, 0.9, 3.6)},
	{"name": "EastTowerBox", "kind": "cover", "center": Vector3(18.5, 2.95, 0), "size": Vector3(0.8, 0.9, 0.8)},
	# 摊位簇（每簇 1 板 + 1 箱；板箱同坐地面缝恰 1.5——项目级 boost 规则；
	# 控制器裁决 2026-08-11：簇迁离塔坡道带，N 簇 z=5 / S 簇 z=-11，箱收至 x=±15）
	{"name": "EastClusterN_Panel", "kind": "cover", "center": Vector3(18.5, 1.1, 5), "size": Vector3(3, 2.2, 0.4)},
	{"name": "EastClusterN_Box", "kind": "cover", "center": Vector3(15, 0.45, 5), "size": Vector3(1, 0.9, 1)},
	{"name": "EastClusterS_Panel", "kind": "cover", "center": Vector3(18.5, 1.1, -11), "size": Vector3(3, 2.2, 0.4)},
	{"name": "EastClusterS_Box", "kind": "cover", "center": Vector3(15, 0.45, -11), "size": Vector3(1, 0.9, 1)},
	{"name": "WestClusterN_Panel", "kind": "cover", "center": Vector3(-18.5, 1.1, 11), "size": Vector3(3, 2.2, 0.4)},
	{"name": "WestClusterN_Box", "kind": "cover", "center": Vector3(-15, 0.45, 11), "size": Vector3(1, 0.9, 1)},
	{"name": "WestClusterS_Panel", "kind": "cover", "center": Vector3(-18.5, 1.1, -5), "size": Vector3(3, 2.2, 0.4)},
	{"name": "WestClusterS_Box", "kind": "cover", "center": Vector3(-15, 0.45, -5), "size": Vector3(1, 0.9, 1)},
	# 摊阁（翼引力锚：顶 1.2 可跳 + 台阶顶 0.6 贴缘无缝）
	{"name": "EastPavilion", "kind": "cover", "center": Vector3(18.5, 0.6, 10), "size": Vector3(2.5, 1.2, 2.5)},
	{"name": "EastPavilionStep", "kind": "cover", "center": Vector3(18.5, 0.3, 12.0), "size": Vector3(1.5, 0.6, 1.5)},
	{"name": "WestPavilion", "kind": "cover", "center": Vector3(-18.5, 0.6, -10), "size": Vector3(2.5, 1.2, 2.5)},
	{"name": "WestPavilionStep", "kind": "cover", "center": Vector3(-18.5, 0.3, -12.0), "size": Vector3(1.5, 0.6, 1.5)},
	# F3 高墙×4（3m 高）横脊墙：rim 侧伸入街中，为市街增加博弈空间。
	# EastSpurN x∈[14.5,17.5] z∈[6.7,7.5]，西面贴 RimE_T 面 x=14.5。
	# 旋转对：EastSpurN↔WestSpurS、EastSpurS↔WestSpurN（与 _rot_pair 映射自洽）。
	# F8（2026-08-12 用户实测定位）：EastSpurS/WestSpurN 墙头↔塔坡道绕墙通道仅 1.0m 卡顿
	#   （玩家宽 1.0 零余量），两墙 size.x 3→2（center.x 16→15.5 / -16→-15.5 保持贴 rim 根不动），
	#   墙头 17.5→16.5 / -17.5→-16.5，留 2.0m 通道；EastSpurN/WestSpurS 不动
	#   （另两面绕行路径净距充足，用户确认不卡）。
	{"name": "EastSpurN", "kind": "wall", "center": Vector3(16.0, 1.5, 7.1), "size": Vector3(3.0, 3.0, 0.8)},
	{"name": "EastSpurS", "kind": "wall", "center": Vector3(15.5, 1.5, -7.1), "size": Vector3(2.0, 3.0, 0.8)},
	{"name": "WestSpurS", "kind": "wall", "center": Vector3(-16.0, 1.5, -7.1), "size": Vector3(3.0, 3.0, 0.8)},
	{"name": "WestSpurN", "kind": "wall", "center": Vector3(-15.5, 1.5, 7.1), "size": Vector3(2.0, 3.0, 0.8)},
] \
		+ _ramp_steps(-21, -18.5, 8.2, 2.0, 0.0, 2.5, "WestTowerRamp", 10) \
		+ _ramp_steps(18.5, 21, -8.2, -2.0, 0.0, 2.5, "EastTowerRamp", 10)
# ---- 任务 5：钟门 + 市集带（南半 = 北半 180° 旋转：(x,z)→(−x,−z)）----
# GDScript const 不允许函数调用，故表为 static var（同 RAMPS/STREETS）。
# 碰撞审计修正：brief 翼墙原文 "size (9,1,3)" 与其自身标注【z∈[13.5,14.5]】矛盾
# （center z=14 配 size.z=3 → z∈[12.5,15.5]），且会破坏测试 5/6/8 与 boost gate；
# 按项目墙体惯例 (长, 墙高 3, 厚 1) 取 (9,3,1)（坐地面，同 rim 墙），详见任务报告。
static var GATES: Array = _bell_gate(1) + _market_belt(1) + _bell_gate(-1) + _market_belt(-1)
# ---- 任务 6：背街 + 营（南半 = 北半 180° 旋转：(x,z)→(−x,−z)）----
# GDScript const 不允许函数调用，故表为 static var（同 RAMPS/STREETS/GATES）。
# 命名按物理位置：北半 CampN_/BackN_ 前缀，南半 CampS_/BackS_ 前缀，
# W/E 按实体旋转后的实际 x 侧（旋转映射含 W↔E 互换）。
static var BACKSTREETS: Array = _backstreet(1) + _camp(1) + _backstreet(-1) + _camp(-1)
# ---- 任务 7：外环视线打断树 + 角场×4 ----
# GDScript const 不允许函数调用，故表为 static var（同 RAMPS/STREETS/GATES/BACKSTREETS）。
# 角场由生成器 _corner_court(cx, cz) 产出：偏移按象限符号推导——x 偏移朝地图中心内向、
# z 偏移 s=sign(cz)（南半 = 北半 180° 旋转）；NE = NW 之 x 镜像（原 brief 显式坐标）。
# 每角 4 实体 = 摊阁 + 台阶 + Box1 + 大树（裁决轮：删除 Box2，Box1 x 偏移 1.85 真贴缘）。
static var OUTER: Array = [
	# 外环视线打断树（bigtree：center.y = 树干半高，数据 AABB y∈[0,2.5]）
	{"name": "OuterRing_TreeNW", "kind": "bigtree", "center": Vector3(-26.5, 1.25, 12), "size": Vector3(0.7, 2.5, 0.7)},
	{"name": "OuterRing_TreeNE", "kind": "bigtree", "center": Vector3(26.5, 1.25, 12), "size": Vector3(0.7, 2.5, 0.7)},
	{"name": "OuterRing_TreeSW", "kind": "bigtree", "center": Vector3(-26.5, 1.25, -12), "size": Vector3(0.7, 2.5, 0.7)},
	{"name": "OuterRing_TreeSE", "kind": "bigtree", "center": Vector3(26.5, 1.25, -12), "size": Vector3(0.7, 2.5, 0.7)},
] \
		+ _corner_court(-26, 21.5) + _corner_court(26, 21.5) \
		+ _corner_court(26, -21.5) + _corner_court(-26, -21.5)


## 台阶坡道生成器：沿 z 从 z_from 到 z_to 均分 steps 级整高盒。
## 每级盒底 = y_from（坐落面）、顶 = y_from + (y_to-y_from)*(i+1)/steps；
## 盒 x 跨度 [x_min,x_max]，z 跨度为均分段，级间 z 不重叠；级 1 在 z_from 端
## （z_to < z_from 时方向自动反向）。kind "cover"，name = name_prefix + "Step%d"（i 从 1 起）。
static func _ramp_steps(x_min: float, x_max: float, z_from: float, z_to: float,
		y_from: float, y_to: float, name_prefix: String, steps: int = 8) -> Array:
	var out := []
	for i in range(steps):
		var top: float = y_from + (y_to - y_from) * float(i + 1) / float(steps)
		var za: float = z_from + (z_to - z_from) * float(i) / float(steps)
		var zb: float = z_from + (z_to - z_from) * float(i + 1) / float(steps)
		var z_lo := minf(za, zb)
		var z_hi := maxf(za, zb)
		out.append({
			"name": name_prefix + "Step%d" % (i + 1),
			"kind": "cover",
			"center": Vector3((x_min + x_max) * 0.5, (y_from + top) * 0.5, (z_lo + z_hi) * 0.5),
			"size": Vector3(x_max - x_min, top - y_from, z_hi - z_lo),
		})
	return out


## 钟门生成器：side=1 北 / side=-1 南（180° 旋转 = x/z 乘 side）。
## 双柱间 2.5m 门廊（柱 x 内缘 ±1.25）+ 过梁（底 4.5 顶 4.9）+ 两侧低翼墙。
## F5（2026-08-12 用户验收反馈）：摊阁台阶↔门柱夹缝 0.45m 卡顿——柱深 3→2.25
## 靠广场侧收缩 0.75m（北 z∈[13,16]→[13.75,16]，南镜像），留 1.2m 通道；
## F7（2026-08-12 用户二次反馈）：1.2m 通道仍卡——柱深 2.25→1.5 再收缩 0.75m
## （北 z∈[13.75,16]→[14.5,16]，南镜像），留 1.95m 通道；
## 过梁（z∈[12.75,16.25]）不动仍覆盖柱顶；旋转对称保持（size.z 与 center.z 同步变）。
static func _bell_gate(side: int) -> Array:
	var tag: String = "GateN" if side == 1 else "GateS"
	return [
		{"name": tag + "_PillarW", "kind": "wall",
			"center": Vector3(-3.125 * side, 1.5, 15.25 * side), "size": Vector3(3.75, 3, 1.5)},
		{"name": tag + "_PillarE", "kind": "wall",
			"center": Vector3(3.125 * side, 1.5, 15.25 * side), "size": Vector3(3.75, 3, 1.5)},
		{"name": tag + "_Lintel", "kind": "wall",
			"center": Vector3(0, 4.7, 14.5 * side), "size": Vector3(11, 0.4, 3.5)},
		{"name": tag + "_WingW", "kind": "wall",
			"center": Vector3(-9.5 * side, 1.5, 14 * side), "size": Vector3(9, 3, 1)},
		{"name": tag + "_WingE", "kind": "wall",
			"center": Vector3(9.5 * side, 1.5, 14 * side), "size": Vector3(9, 3, 1)},
	]


## 市集带生成器：side=1 北 / side=-1 南。
## 摊阁（2.0×1.8 顶 1.2 可跳，z∈[10,11.8] 贴 rim N 面 z=10，x∈[±2.5,±4.5] 避开翼墙 x≥5、
## 与门柱 z 缝 2.7——F7 柱深 2.25→1.5 后）+ 摊阁台阶（顶 0.6，贴摊阁北缘 z=11.8，
## 与门柱 z 缝恰 1.95）+ 中央双箱（x=±0.5 内收，原 ±2 与台阶缝 0.25——任务 9 A4 重布，
## 2026-08-11）+ 高棚板对（底 4.5，间留 2m 天井 x∈[-1,1]）。
static func _market_belt(side: int) -> Array:
	var tag: String = "BeltN" if side == 1 else "BeltS"
	return [
		{"name": tag + "_PavW", "kind": "cover",
			"center": Vector3(-3.5 * side, 0.6, 10.9 * side), "size": Vector3(2.0, 1.2, 1.8)},
		{"name": tag + "_PavE", "kind": "cover",
			"center": Vector3(3.5 * side, 0.6, 10.9 * side), "size": Vector3(2.0, 1.2, 1.8)},
		{"name": tag + "_PavStepE", "kind": "cover",
			"center": Vector3(3.5 * side, 0.3, 12.175 * side), "size": Vector3(1.5, 0.6, 0.75)},
		{"name": tag + "_PavStepW", "kind": "cover",
			"center": Vector3(-3.5 * side, 0.3, 12.175 * side), "size": Vector3(1.5, 0.6, 0.75)},
		{"name": tag + "_Box1", "kind": "cover",
			"center": Vector3(0.5 * side, 0.45, 12.5 * side), "size": Vector3(1, 0.9, 1)},
		{"name": tag + "_Box2", "kind": "cover",
			"center": Vector3(-0.5 * side, 0.45, 12.5 * side), "size": Vector3(1, 0.9, 1)},
		{"name": tag + "_CanopyW", "kind": "roof",
			"center": Vector3(-3 * side, 4.7, 10.75 * side), "size": Vector3(4, 0.4, 2.5)},
		{"name": tag + "_CanopyE", "kind": "roof",
			"center": Vector3(3 * side, 4.7, 10.75 * side), "size": Vector3(4, 0.4, 2.5)},
	]


## 背街生成器：side=1 北 / side=-1 南（180° 旋转 = x/z 乘 side）。
## LOS 断视板 ×2（x=±10）+ 大树 ×2（x=±21，bigtree：center.y=树干半高，
## 数据 AABB = center±size/2，y∈[0,2.5]）。W/E 按旋转后物理位置命名。
static func _backstreet(side: int) -> Array:
	var tag: String = "BackN" if side == 1 else "BackS"
	# 180° 旋转映射含 E↔W 互换：side=1 北半保持原字符，side=-1 南半互换
	var e_ch: String = "E" if side == 1 else "W"
	var w_ch: String = "W" if side == 1 else "E"
	return [
		{"name": tag + "_LOS_" + e_ch, "kind": "cover",
			"center": Vector3(10 * side, 1.1, 17.75 * side), "size": Vector3(3, 2.2, 0.4)},
		{"name": tag + "_LOS_" + w_ch, "kind": "cover",
			"center": Vector3(-10 * side, 1.1, 17.75 * side), "size": Vector3(3, 2.2, 0.4)},
		{"name": tag + "_Tree_" + e_ch, "kind": "bigtree",
			"center": Vector3(21 * side, 1.25, 18 * side), "size": Vector3(0.7, 2.5, 0.7)},
		{"name": tag + "_Tree_" + w_ch, "kind": "bigtree",
			"center": Vector3(-21 * side, 1.25, 18 * side), "size": Vector3(0.7, 2.5, 0.7)},
	]


## 营生成器：side=1 北 / side=-1 南（180° 旋转 = x/z 乘 side）。
## 营墙 3m 高 1m 厚：北墙 x∈[-6,6]（角部由东西墙覆盖，避免角重叠）；
## 南门缝 x∈[-1.5,1.5] 宽 3m；东西侧门缝 z∈[25.5,27.5] 宽 2m；
## 顶板底 4.5 出挑 0.5；影壁三道（南门缝 2.0 / 侧缝 2.25）；营前场货车掩体
## （偏离门轴 x=0——2026-08-11 碰撞审计修正：原 x=2.5 与影壁 AABB 重叠）。
static func _camp(side: int) -> Array:
	var tag: String = "CampN" if side == 1 else "CampS"
	# 180° 旋转映射含 N↔S / E↔W 互换：后缀方向字符按旋转后物理位置命名
	var n_ch: String = "N" if side == 1 else "S"
	var s_ch: String = "S" if side == 1 else "N"
	var e_ch: String = "E" if side == 1 else "W"
	var w_ch: String = "W" if side == 1 else "E"
	return [
		{"name": tag + "_Wall" + n_ch, "kind": "wall",
			"center": Vector3(0, 1.5, 28.5 * side), "size": Vector3(12, 3, 1)},
		{"name": tag + "_Wall" + s_ch + "_" + w_ch, "kind": "wall",
			"center": Vector3(-3.75 * side, 1.5, 24.5 * side), "size": Vector3(4.5, 3, 1)},
		{"name": tag + "_Wall" + s_ch + "_" + e_ch, "kind": "wall",
			"center": Vector3(3.75 * side, 1.5, 24.5 * side), "size": Vector3(4.5, 3, 1)},
		{"name": tag + "_Wall" + w_ch + "_" + s_ch, "kind": "wall",
			"center": Vector3(-6.5 * side, 1.5, 24.75 * side), "size": Vector3(1, 3, 1.5)},
		{"name": tag + "_Wall" + w_ch + "_" + n_ch, "kind": "wall",
			"center": Vector3(-6.5 * side, 1.5, 28.25 * side), "size": Vector3(1, 3, 1.5)},
		{"name": tag + "_Wall" + e_ch + "_" + s_ch, "kind": "wall",
			"center": Vector3(6.5 * side, 1.5, 24.75 * side), "size": Vector3(1, 3, 1.5)},
		{"name": tag + "_Wall" + e_ch + "_" + n_ch, "kind": "wall",
			"center": Vector3(6.5 * side, 1.5, 28.25 * side), "size": Vector3(1, 3, 1.5)},
		{"name": tag + "_Roof", "kind": "roof",
			"center": Vector3(0, 4.7, 26.5 * side), "size": Vector3(15, 0.4, 6)},
		{"name": tag + "_Screen_" + s_ch, "kind": "wall",
			"center": Vector3(1 * side, 1.5, 21.75 * side), "size": Vector3(4, 3, 0.5)},
		{"name": tag + "_Screen_" + w_ch, "kind": "wall",
			"center": Vector3(-9.5 * side, 1.5, 27.0 * side), "size": Vector3(0.5, 3, 4)},
		{"name": tag + "_Screen_" + e_ch, "kind": "wall",
			"center": Vector3(9.5 * side, 1.5, 27.0 * side), "size": Vector3(0.5, 3, 4)},
		{"name": tag + "_Truck", "kind": "cover",
			"center": Vector3(4.5 * side, 1.1, 21.5 * side), "size": Vector3(3, 2.2, 1)},
	]


## 角场生成器：(cx,cz) = 摊阁中心。偏移按象限符号推导（裁决轮：删除 rot 参数）：
## s  = sign(cz)（北半 +1 / 南半 −1，南半 = 北半 180° 旋转 (dx,dz)→(−dx,−dz)）；
## mx = cx>0 ? −1 : +1（x 偏移朝地图中心内向，NE/SW = 镜像，原 brief 显式坐标）。
## 每角 4 实体：摊阁（顶 1.2 可跳）+ 台阶（顶 0.6）+ Box1（顶 0.9）+ 大树。
## "贴缘"以 NW 基准角描述：台阶贴摊阁北缘缝 0（z 向）、Box1 对角贴摊阁内角
## （x/z 双缝 0）；NE/SE/SW 的接触缘随符号推导自动镜像/反向。
static func _corner_court(cx: float, cz: float) -> Array:
	var mx := -1.0 if cx > 0.0 else 1.0
	var s := -1.0 if cz < 0.0 else 1.0
	var tag: String = "Corner" + ("N" if cz > 0.0 else "S") + ("W" if cx < 0.0 else "E") + "_"
	return [
		{"name": tag + "Pav", "kind": "cover",
			"center": Vector3(cx, 0.6, cz), "size": Vector3(2.5, 1.2, 2.5)},
		{"name": tag + "PavStep", "kind": "cover",
			"center": Vector3(cx, 0.3, cz + 2.0 * s), "size": Vector3(1.5, 0.6, 1.5)},
		{"name": tag + "Box1", "kind": "cover",
			"center": Vector3(cx + 1.85 * mx, 0.45, cz - 1.85 * s), "size": Vector3(1.2, 0.9, 1.2)},
		{"name": tag + "Tree", "kind": "bigtree",
			"center": Vector3(cx + 3.0 * mx, 1.25, cz + 0.5 * s), "size": Vector3(0.7, 2.5, 0.7)},
	]


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


## 玩家出生点（v3）：北营内 (0,1,26.5)——probe_v3_walk/probe_timing 已验证可站立位置。
## 注：v2 出生点 (0,1,0) 在 v3 布局中位于钟楼基座 Pedestal 实体 AABB 内部
## （x/z∈[-2,2]、y∈[0.6,2.7]），玩家会嵌在实体里动不了，故迁至北营。
static func player_spawn() -> Vector3:
	return Vector3(0, 1.0, 26.5)


## 可踏足/可刷怪表面清单（任务 8）——每项 {"name": String, "center": Vector3（y=top_y）,
## "size": Vector3（面尺寸，y=0.1）, "top_y": float}。直书表：name 与 all_solids() 中
## 对应实体一致（Corridor→CorridorSlab、Altar→AltarPlatform 的别名映射由消费侧持有）。
static func standable_surfaces() -> Array:
	return [
		# 钟楼回廊（撒点排除基座区 x/z∈[-2,2]——WaveSpawner 侧拒绝采样）
		{"name": "Corridor", "center": Vector3(0, 3.0, 0), "size": Vector3(7, 0.1, 7), "top_y": 3.0},
		{"name": "WestTower", "center": Vector3(-18.5, 2.5, 0), "size": Vector3(4, 0.1, 4), "top_y": 2.5},
		{"name": "EastTower", "center": Vector3(18.5, 2.5, 0), "size": Vector3(4, 0.1, 4), "top_y": 2.5},
		# 祭坛台面（撒点排除基座/坡道/斜板投影——WaveSpawner 侧拒绝采样）
		{"name": "Altar", "center": Vector3(0, 0.6, 0), "size": Vector3(14, 0.1, 10), "top_y": 0.6},
		# 市集带摊阁×4（名称对应 GATES 实体，南半坐标随生成器 180° 旋转；任务 9 A4 重布）
		{"name": "BeltN_PavE", "center": Vector3(3.5, 1.2, 10.9), "size": Vector3(2.0, 0.1, 1.8), "top_y": 1.2},
		{"name": "BeltN_PavW", "center": Vector3(-3.5, 1.2, 10.9), "size": Vector3(2.0, 0.1, 1.8), "top_y": 1.2},
		{"name": "BeltS_PavE", "center": Vector3(-3.5, 1.2, -10.9), "size": Vector3(2.0, 0.1, 1.8), "top_y": 1.2},
		{"name": "BeltS_PavW", "center": Vector3(3.5, 1.2, -10.9), "size": Vector3(2.0, 0.1, 1.8), "top_y": 1.2},
		# 东/西市街摊阁
		{"name": "EastPavilion", "center": Vector3(18.5, 1.2, 10), "size": Vector3(2.5, 0.1, 2.5), "top_y": 1.2},
		{"name": "WestPavilion", "center": Vector3(-18.5, 1.2, -10), "size": Vector3(2.5, 0.1, 2.5), "top_y": 1.2},
		# 角场摊阁×4
		{"name": "CornerNW_Pav", "center": Vector3(-26, 1.2, 21.5), "size": Vector3(2.5, 0.1, 2.5), "top_y": 1.2},
		{"name": "CornerNE_Pav", "center": Vector3(26, 1.2, 21.5), "size": Vector3(2.5, 0.1, 2.5), "top_y": 1.2},
		{"name": "CornerSE_Pav", "center": Vector3(26, 1.2, -21.5), "size": Vector3(2.5, 0.1, 2.5), "top_y": 1.2},
		{"name": "CornerSW_Pav", "center": Vector3(-26, 1.2, -21.5), "size": Vector3(2.5, 0.1, 2.5), "top_y": 1.2},
	]


## 营地出生点（2026-08-13 用户拍板）：玩家+4 友军出生在北营、5 敌人出生在南营，
## 每营内置 10 个随机刷新点——角色只在"当前无其他角色占用"的点位出现（SpawnPool 消费）。
## 布局：2 行 × 5 列网格（x∈{-4..4} 步长 2，z = ±25.5 / ±27.5），营内范围
## x∈[-6,6]×z∈[25,28]（北营；南营为 180° 旋转 z 取负）。
## 间距：同行/同列 2m、对角 2.83m ≥ 角色胶囊直径 0.62m，恒不重叠；
## 边距：z 行距墙内缘 0.5m（净隙 0.19m 不穿墙）、x 边列距侧墙 2m。
## y=0 地面（Enemy/玩家原点在脚底）。side=1 北营 / side=-1 南营。
static func camp_spawn_points(side: int) -> Array:
	var pts := []
	for x in [-4.0, -2.0, 0.0, 2.0, 4.0]:
		for z in [25.5, 27.5]:
			pts.append(Vector3(x, 0.0, z * side))
	return pts


## 弹药箱固定刷新点（2026-08-13 用户需求）：总计 10 处，180° 旋转对称（5 对）。
## 约束：①不在双方营地（营矩形 x∈[-6,6]×z∈[±24.5,±28.5] 之外）②两两水平距 ≥5m
## ③覆盖点名位置：中心塔二楼（钟楼回廊 ×2）、两边祭坛（祭坛台东/西 ×2）、
##   东西望楼/水塔顶 ×2、背街 ×2、外环街 ×2。
## y = 放置面高度（箱底贴面）：回廊 3.0 / 祭坛台 0.6 / 塔顶 2.5 / 地面 0。
## 位置复核：全部避开实体 AABB（塔顶箱/坡道/斜板/基座/影壁/货车/角场摊阁），间距最小 5.05m。
static func ammo_box_points() -> Array:
	return [
		# 钟楼回廊（塔二楼）东/西
		{"name": "CorridorE", "pos": Vector3(2.8, 3.0, 0.0)},
		{"name": "CorridorW", "pos": Vector3(-2.8, 3.0, 0.0)},
		# 祭坛台东/西（两边祭坛上；避开基座/坡道/斜板投影）
		{"name": "AltarE", "pos": Vector3(5.6, 0.6, 4.2)},
		{"name": "AltarW", "pos": Vector3(-5.6, 0.6, -4.2)},
		# 东/西望楼水塔顶（塔顶箱南/北侧 0.6m）
		{"name": "EastTower", "pos": Vector3(18.5, 2.5, 1.0)},
		{"name": "WestTower", "pos": Vector3(-18.5, 2.5, -1.0)},
		# 背街北/南（营前场开阔处，影壁南侧）
		{"name": "BackN", "pos": Vector3(0.0, 0.0, 19.0)},
		{"name": "BackS", "pos": Vector3(0.0, 0.0, -19.0)},
		# 外环街北/南
		{"name": "OuterN", "pos": Vector3(27.0, 0.0, 17.5)},
		{"name": "OuterS", "pos": Vector3(-27.0, 0.0, -17.5)},
	]
