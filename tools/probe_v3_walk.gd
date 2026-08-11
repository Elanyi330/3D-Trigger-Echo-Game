# tools/probe_v3_walk.gd
# v3 漫游探针（T10，替代 v2 的 probe_walk.gd）：沿覆盖 v3 全动线的路线逐点推进，
# 验证"玩家可走遍全图无 bug"。
# 模式沿用 probe_walk.gd（直接设位 + 物理推进 + 到达判定）并增强为"行走优先"：
#   ① 从当前位置朝目标点物理行走（走速/重力/跳跃辅助同 MovementController 参数），
#      到达判定 = 水平距离 <0.6m 且站立高度与目标面吻合（±0.45m）；
#   ② 行走超时/卡死 → 回退 probe_walk 式瞬移+物理落地判定（目标点可站立 + 未被推出界）。
# 每点输出 OK / OK(瞬移) / FAIL + 汇总；全通 EXIT=0 否则 EXIT=1。
#
# 路线覆盖（brief T10 D 全要素）：营 3 门（南门出/东侧门出/西侧门进）、市集带（含摊阁登台）、
# 钟门门廊、rim 四向豁口（北中豁/北东口/东口/西口/南口）、祭坛台登台（微台阶）、
# 坡道上下（东坡道+东西塔坡道）、回廊+跳落、双塔登台、长墙豁、外环、角场摊阁登台、背街。
# 部分 brief 原点落在实体 AABB 内（市集带 (3.5,0,11)=摊阁体积、东街 (18,0,0)=水塔体积、
# 外环 (26.5,0,12)=大树树干、背街 (-10,0,17.75)=断视板体积、塔顶 (±18.5,2.5,0)=塔箱体积），
# 按"目标区域不变"微调至邻近可站立点（各点注释标明）。
# 用法: godot --headless --path . -s res://tools/probe_v3_walk.gd
extends SceneTree

const LAYOUT := preload("res://Levels/M2_TDM/map_layout_v3.gd")
const GRAVITY_MULT := 2.0
const SPEED := 6.35
const JUMP_VELOCITY := 7.54
const BODY_RADIUS := 0.5
const BODY_HEIGHT := 1.83
const CAPSULE_HALF := BODY_HEIGHT * 0.5  # 0.915：站立时原点（胶囊中心）= 面高 + 0.915
const ARRIVE_DIST := 0.6
const ARRIVE_Y_TOL := 0.45

# 路线：[标签, 目标点 Vector3(x, 站立面高, z)]。引导点（"引"前缀）用于绕过几何障碍，
# 与目标点同等判定（路线可按实际几何微调——目标区域不变）。
const ROUTE := [
	# ---- 营（3 门）----
	["北营内", Vector3(0, 0, 26.5)],
	["南门出", Vector3(0.5, 0, 23.5)],
	["引·影壁西", Vector3(-2, 0, 23)],
	["引·营前场西", Vector3(-2, 0, 21)],
	["营前场东", Vector3(2, 0, 21)],
	["引·影壁西回", Vector3(-2, 0, 21)],
	["引·影壁西北回", Vector3(-2, 0, 23)],
	["引·南门回入营", Vector3(4.5, 0, 26.5)],
	["东侧门出", Vector3(8, 0, 26.5)],
	# ---- 钟门 + 市集带 ----
	["引·营东南外", Vector3(10, 0, 21)],
	["引·门前场", Vector3(0.5, 0, 17)],
	["引·门廊轴线", Vector3(0, 0, 17)],
	["钟门门廊", Vector3(0, 0, 14.5)],
	["市集北带", Vector3(0.5, 0, 11.2)],  # brief (3.5,0,11) 在摊阁体积内→邻近可站立带面
	["市集摊阁顶", Vector3(3.5, 1.2, 10.9)],  # BeltN_PavE 顶（可跳 1.2）
	["带东端", Vector3(7.75, 0, 11)],
	["rim北东口", Vector3(7.75, 0, 9.5)],
	["广场东北", Vector3(7.75, 0, 7.5)],
	["引·广场北带", Vector3(3.25, 0, 7.5)],
	["rim北中豁", Vector3(3.25, 0, 9.5)],
	["广场东南", Vector3(5, 0, 6.2)],  # brief (5,0,5) 贴祭坛台角→外移 1.2m
	# ---- 祭坛台（微台阶登台）----
	["广场南·微台阶口", Vector3(0, 0, 6.8)],
	["微台阶S1顶", Vector3(0, 0.3, 5.45)],
	["祭坛台南", Vector3(0, 0.6, 4)],
	["引·台西廊口", Vector3(-3, 0.6, 3)],
	["引·台西廊中", Vector3(-3, 0.6, -1)],
	["引·台西廊南", Vector3(-3, 0.6, -4)],
	["祭坛台北", Vector3(0, 0.6, -4.5)],
	# ---- 东坡道 + 回廊 ----
	["东坡道底", Vector3(5.1, 0.6, -4.2)],  # brief (5.1,0.6,-3) 在 Step1 体积内→南移 1.2m
	["东坡道顶", Vector3(5.1, 3.0, 2.1)],
	["回廊", Vector3(0, 3.0, 0)],
	["回廊跳落点", Vector3(0, 0, -6.5)],  # 南栏豁口走出坠落落点（无摔伤机制，验证落点可站）
	# ---- rim 东口 + 东街 + 东塔 ----
	["引·广场东缘", Vector3(8, 0, -5.5)],
	["rim东口", Vector3(13.5, 0, 0)],
	["引·rim外东", Vector3(15.5, 0, 3.5)],
	["东街", Vector3(18, 0, 3.5)],  # brief (18,0,0) 在水塔体积内→北移 3.5m
	["引·街东", Vector3(21.5, 0, 3)],
	["引·塔坡道南口", Vector3(21.5, 0, -8.8)],
	["东塔坡道底", Vector3(19.75, 0, -8.8)],
	["东塔坡道顶", Vector3(19.75, 2.5, -2.3)],
	["引·入塔", Vector3(18.8, 2.5, -1.8)],
	["东塔顶", Vector3(17.4, 2.5, 1.0)],  # brief (19.75,2.5,-2.6)/台缘——塔顶可站立区（箱西侧）
	["引·下塔", Vector3(21.5, 0, -8.8)],
	["东街北", Vector3(20.5, 0, 7)],  # brief (18,0,10) 在摊阁体积内→邻近街面
	["东摊阁顶", Vector3(18.5, 1.2, 10)],
	# ---- 长墙豁 + 外环 + 角场 ----
	["长墙北豁", Vector3(23, 0, 6.75)],
	["外环东北", Vector3(26.5, 0, 14)],  # brief (26.5,0,12) 在大树树干内→北移 2m
	["NE角场摊阁顶", Vector3(26, 1.2, 21.5)],
	# ---- 背街 ----
	["引·摊阁南落", Vector3(26, 0, 19.3)],
	["引·角场箱南", Vector3(22, 0, 17.5)],
	["引·角场树南", Vector3(20, 0, 16)],
	["背街北", Vector3(-10, 0, 16.5)],  # brief (-10,0,17.75) 在断视板体积内→南移 1.25m
	["引·背街西", Vector3(-21.5, 0, 16)],
	["引·西市外", Vector3(-21.5, 0, 8.5)],
	# ---- 西塔坡道 + 西塔 ----
	["西塔坡道底", Vector3(-19.75, 0, 8.8)],
	["西塔坡道顶", Vector3(-19.75, 2.5, 2.3)],
	["引·栏豁口西", Vector3(-18.5, 2.5, 2.3)],
	["西塔顶", Vector3(-18.5, 2.5, 1.2)],
	["引·下塔西", Vector3(-15.3, 0, 8.5)],
	# ---- rim 西口 + 南口 ----
	["引·rim外西南", Vector3(-15.3, 0, 0.5)],
	["rim西口", Vector3(-13.5, 0, 0)],
	["引·rim外西角", Vector3(-15.3, 0, -11.2)],
	["引·南带西", Vector3(-7.75, 0, -12.5)],
	["rim南口", Vector3(-7.75, 0, -9.5)],
	# ---- 回营（西侧门）----
	["引·南口西南", Vector3(-8.6, 0, -11.2)],
	["引·外环西直道", Vector3(-15.3, 0, -11.2)],
	["引·外环西直道北", Vector3(-15.3, 0, 23)],
	["引·营西", Vector3(-8, 0, 23)],
	["西侧门外", Vector3(-8, 0, 26.5)],
	["西侧门进", Vector3(-4, 0, 26.5)],
	["北营内·回环", Vector3(0, 0, 26.5)],
]

var _player: CharacterBody3D
var _reports := []
var _fail := 0
var _walked := 0
var _teleported := 0


func _initialize() -> void:
	# 灰盒地图（map_greybox 已切 v3 LAYOUT）
	var gb_script := load("res://Levels/M2_TDM/map_greybox.gd")
	var map := Node3D.new()
	root.add_child(map)
	var gb: Node3D = gb_script.new()
	gb.name = "MapGreybox"
	map.add_child(gb)
	gb.build()
	# 玩家胶囊（同 probe_walk.gd：layer 2 / mask 1，半径 0.5 高 1.83）
	_player = CharacterBody3D.new()
	_player.collision_layer = 2
	_player.collision_mask = 1
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = BODY_RADIUS
	cap.height = BODY_HEIGHT
	cs.shape = cap
	_player.add_child(cs)
	root.add_child(_player)
	# 起点初始放置（用 position——父级 root 在原点，等价 global_position；
	# _initialize 阶段 add_child 后变换树尚未注册，global_position 会触发 is_inside_tree 报错）
	var start: Vector3 = ROUTE[0][1]
	_player.position = Vector3(start.x, start.y + 1.0, start.z)
	_player.velocity = Vector3.ZERO
	_run()


func _run() -> void:
	var d := 1.0 / Engine.physics_ticks_per_second
	# 起点：落地判定（位置已在 _initialize 设好）
	var start: Vector3 = ROUTE[0][1]
	var settled0 := await _settle(d)
	var ok0 := settled0 and _stand_ok(start)
	_reports.append(_fmt(0, ok0, false, start))
	if not ok0:
		_fail += 1
	else:
		_teleported += 1
	# 逐段行走
	for i in range(1, ROUTE.size()):
		var label: String = ROUTE[i][0]
		var target: Vector3 = ROUTE[i][1]
		var reached := await _walk_to(target, d)
		if reached:
			_walked += 1
			_reports.append(_fmt(i, true, false, target))
			continue
		# 行走失败 → 瞬移回退（probe_walk.gd 模式：设位 + 物理落地 + 站立判定）
		_player.global_position = Vector3(target.x, target.y + 1.0, target.z)
		_player.velocity = Vector3.ZERO
		var settled := await _settle(d)
		var ok := settled and _stand_ok(target)
		if ok:
			_teleported += 1
		else:
			_fail += 1
		_reports.append(_fmt(i, ok, true, target))
	for r in _reports:
		print(r)
	print("PROBE_V3_WALK %d/%d reached（行走 %d / 瞬移 %d / 失败 %d）" % [
		ROUTE.size() - _fail, ROUTE.size(), _walked, _teleported, _fail])
	quit(0 if _fail == 0 else 1)


# 物理落地（≤60 帧重力推进），返回是否踏上地面
func _settle(d: float) -> bool:
	for f in 60:
		await physics_frame
		_player.velocity.y -= 9.8 * GRAVITY_MULT * d
		_player.move_and_slide()
		if _player.is_on_floor():
			return true
	return false


# 站立判定：目标点水平 ±0.6m、站立高度吻合、未出地图边界
func _stand_ok(target: Vector3) -> bool:
	var pos := _player.global_position
	var horiz := Vector2(pos.x - target.x, pos.z - target.z).length()
	var y_ok: bool = absf(pos.y - (target.y + CAPSULE_HALF)) < ARRIVE_Y_TOL
	var in_bounds: bool = absf(pos.x) < LAYOUT.BOUND_X and absf(pos.z) < LAYOUT.BOUND_Z
	return horiz < ARRIVE_DIST and y_ok and in_bounds


# 朝目标行走（走速 + 重力 + 跳跃辅助：贴墙/卡住即起跳——台阶/坡道/矮掩体翻越），
# 帧预算按距离放大；到达（水平 <0.6m 且高度吻合）返回 true。
func _walk_to(target: Vector3, d: float) -> bool:
	var dist0 := _horiz_dist(target)
	var budget := 90 + int(dist0 * 30.0)
	var prev_dist := dist0
	var stuck := 0
	var jump_cooldown := 0
	for f in budget:
		await physics_frame
		var pos := _player.global_position
		var dir := Vector3(target.x - pos.x, 0, target.z - pos.z)
		var hd: float = dir.length()
		if hd < ARRIVE_DIST and absf(pos.y - (target.y + CAPSULE_HALF)) < ARRIVE_Y_TOL:
			return true
		if hd > 0.001:
			dir /= hd
		_player.velocity.x = dir.x * SPEED
		_player.velocity.z = dir.z * SPEED
		_player.velocity.y -= 9.8 * GRAVITY_MULT * d
		jump_cooldown -= 1
		if _player.is_on_floor() and jump_cooldown <= 0 \
				and (_player.is_on_wall() or stuck >= 6):
			_player.velocity.y = JUMP_VELOCITY
			jump_cooldown = 14
			stuck = 0
		_player.move_and_slide()
		var nd := _horiz_dist(target)
		if nd >= prev_dist - 0.005:
			stuck += 1
		else:
			stuck = 0
		prev_dist = nd
	return false


func _horiz_dist(target: Vector3) -> float:
	var pos := _player.global_position
	return Vector2(pos.x - target.x, pos.z - target.z).length()


func _fmt(i: int, ok: bool, teleported: bool, target: Vector3) -> String:
	var pos := _player.global_position
	var tag := "FAIL"
	if ok:
		tag = "OK(瞬移)" if teleported else "OK"
	return "  [%s] %d/%d %s 目标=(%.1f,%.1f,%.1f) 实位=(%.2f,%.2f,%.2f)" % [
		tag, i + 1, ROUTE.size(), ROUTE[i][0],
		target.x, target.y, target.z, pos.x, pos.y, pos.z]
