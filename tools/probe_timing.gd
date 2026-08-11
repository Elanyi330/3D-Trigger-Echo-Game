# tools/probe_timing.gd
# v3 首交火 timing 探针（T16，设计文档 §八.8）：双 bot 南北出生相向跑，首次互见 4-6.5s。
# 胶囊 r=0.5 h=1.83，碰撞 shape 上移 0.915 → body 原点=脚底，眼位 = pos + (0,1.7,0)（眼高 1.7）；
# layer 2 / mask 1（同 probe_v3_walk；双 bot 互不碰撞）。每物理帧朝路点 seek（6.35 m/s），
# move_and_slide 沿墙滑行绕障 + 跳跃辅助（同 probe_v3_walk：贴墙/卡住即起跳）；
# 每帧双眼位互见 raycast（exclude 两胶囊 RID）；首次互见 t = 帧数/60.0。
#
# 路线调整说明（brief 允许"微调目标点并记录"）：单目标 (0,0,0) seek 会正面撞影壁/rim 墙/祭坛台
# （法向碰撞无切向分量→卡死），故按路点列行走。市集带双箱（x∈[-1,1] z∈[12,13] 顶 0.9）正封
# 钟门走廊轴线（两侧净距 0.25m 不可过），翻箱跳跃是必经动线（probe_v3_walk 同走法）。
# 关键设计：南 bot 前场东侧绕行拉长 ≥0.6s，使双方翻箱不同时——同时翻箱会把双眼位对称抬到
# ~3m，视线恰好越过基座顶 2.7m，造成 ~2.6s 的非意图早期互见（实测验证）。
# 翻箱后各走中豁（错轴：北 x∈[2,4.5] / 南 x∈[-4.5,-2]，无直通视），北入东走廊南下、
# 南穿南带东行入东走廊北上，首交火汇合于东走廊-南带视线窗（坡道台阶顶 ≥1.8m 挡此前视线）。
# 豁口角部为凸角刮擦（move_and_slide 自然绕行；凹角夹缝如"柱↔箱"已避开——走廊出口正对
# 双箱，东/西斜插会撞门柱侧腹，实测卡死，故一律先翻箱再展开）。
# 用法: godot --headless --path . -s res://tools/probe_timing.gd
extends SceneTree

const SPEED := 6.35
const GRAVITY_MULT := 2.0
const JUMP_VELOCITY := 7.54  # 同 MovementController/probe_v3_walk（跳高≈1.45m > 箱顶 0.9m）
const EYE_H := 1.7
const BODY_RADIUS := 0.5
const BODY_HEIGHT := 1.83
const CAPSULE_HALF := BODY_HEIGHT * 0.5
const PHYS_HZ := 60.0
const T_MIN := 4.0
const T_MAX := 6.5
const TIMEOUT_S := 15.0
const WP_ARRIVE := 0.9

const SPAWN_N := Vector3(0, 1.0, 26.5)
const SPAWN_S := Vector3(0, 1.0, -26.5)
const ROUTE_N := [
	Vector2(0.5, 23.5),    # 南门缝出（缝 x∈[-1.5,1.5]，穿越点 x≈0.33）
	Vector2(-3, 22.3),     # 影壁（x∈[-1,3] z∈[21.5,22]）西侧绕（切角后净空 ≥0.79）
	Vector2(0.5, 14.5),    # 钟门门廊轴线（柱间缝 x∈[-1.25,1.25]）
	Vector2(0.5, 11.2),    # 跳翻双箱 → 市集北带（probe_v3_walk 已验证点）
	Vector2(3.25, 9.5),    # rim 北中豁（错轴）x∈[2,4.5]
	Vector2(7.75, 6),      # 广场东北入东走廊
	Vector2(8, -6),        # 东走廊南下（终点）
]
const ROUTE_S := [
	Vector2(-0.5, -23.5),  # 北门缝出
	Vector2(3, -22.3),     # 影壁（旋转后 x∈[-3,1] z∈[-22,-21.5]）东侧绕
	Vector2(6, -18),       # 前场东侧绕行（与北 bot 翻箱时差 ≥0.6s，防对称高眼位互见）
	Vector2(0, -16),       # 收拢到走廊轴线（须在柱带 z∈[-16,-13] 之前完成，防斜插撞柱）
	Vector2(-0.5, -14.5),  # 钟门门廊轴线
	Vector2(-0.5, -11.2),  # 跳翻双箱 → 市集南带
	Vector2(-3.25, -9.5),  # rim 南中豁（错轴）x∈[-4.5,-2]
	Vector2(-2.5, -8.5),   # 出豁口转向（避 RimS3 角）
	Vector2(7.75, -6),     # 南带东行入东走廊
	Vector2(8, 6),         # 东走廊北上（终点）
]

var _bots := []  # [{body, tag, route, wp, path_len, jump_cd, stuck, prev_dist}]


func _initialize() -> void:
	var gb_script := load("res://Levels/M2_TDM/map_greybox.gd")
	var gb: Node3D = gb_script.new()
	gb.name = "MapGreybox"
	root.add_child(gb)
	gb.build()
	_bots.append(_make_bot(SPAWN_N, ROUTE_N, "北"))
	_bots.append(_make_bot(SPAWN_S, ROUTE_S, "南"))
	_run()


func _make_bot(spawn: Vector3, route: Array, tag: String) -> Dictionary:
	var body := CharacterBody3D.new()
	body.name = "ProbeBot" + tag
	body.collision_layer = 2
	body.collision_mask = 1
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = BODY_RADIUS
	cap.height = BODY_HEIGHT
	cs.shape = cap
	cs.position = Vector3(0, CAPSULE_HALF, 0)  # body 原点=脚底 → 眼位 pos+(0,1.7,0)
	body.add_child(cs)
	root.add_child(body)
	body.position = spawn
	return {"body": body, "tag": tag, "route": route, "wp": 0, "path_len": 0.0,
		"jump_cd": 0, "stuck": 0, "prev_dist": INF}


func _run() -> void:
	var d := 1.0 / Engine.physics_ticks_per_second
	# 落地稳定（不计入 timing）
	for f in 60:
		await physics_frame
		var grounded := true
		for b in _bots:
			b["body"].velocity.y -= 9.8 * GRAVITY_MULT * d
			b["body"].move_and_slide()
			if not b["body"].is_on_floor():
				grounded = false
		if grounded:
			break
	# seek + 互见检测
	var frames := 0
	var max_frames := int(TIMEOUT_S * PHYS_HZ)
	var sight_t := -1.0
	var debug := "--debug" in OS.get_cmdline_user_args()
	while frames < max_frames:
		await physics_frame
		frames += 1
		for b in _bots:
			_step_bot(b, d)
		if debug and frames % 15 == 0:
			for b in _bots:
				var bp: Vector3 = b["body"].global_position
				print("  f=%d %s wp=%d pos=(%.2f,%.2f,%.2f) floor=%s wall=%s" % [
					frames, b["tag"], b["wp"], bp.x, bp.y, bp.z,
					b["body"].is_on_floor(), b["body"].is_on_wall()])
		if _mutual_sight():
			sight_t = float(frames) / PHYS_HZ
			break
	for b in _bots:
		var pos: Vector3 = b["body"].global_position
		print("PROBE_TIMING %s bot 路径长=%.1fm  终点位=(%.2f,%.2f,%.2f)" % [
			b["tag"], b["path_len"], pos.x, pos.y, pos.z])
	if sight_t < 0:
		print("首交火：%.0fs 超时未见 ✗" % TIMEOUT_S)
		quit(1)
		return
	print("首交火 t=%.2fs" % sight_t)
	if sight_t >= T_MIN and sight_t <= T_MAX:
		print("首交火 timing %.1f ≤ t ≤ %.1f ✓" % [T_MIN, T_MAX])
		quit(0)
	else:
		print("首交火 timing 越界 ✗（期望 %.1f ≤ t ≤ %.1f）" % [T_MIN, T_MAX])
		quit(1)


# 朝当前路点行走（水平 seek + 重力 + 跳跃辅助——同 probe_v3_walk：贴墙/卡住即起跳，
# 翻 0.9 箱/0.6 台阶；本探针对路线按纯行走设计，正常不触发）；累计水平路径长。
func _step_bot(b: Dictionary, d: float) -> void:
	var body: CharacterBody3D = b["body"]
	var prev := body.global_position
	var route: Array = b["route"]
	var wp_idx: int = b["wp"]
	if wp_idx < route.size():
		var wp: Vector2 = route[wp_idx]
		var to_wp := Vector3(wp.x - prev.x, 0, wp.y - prev.z)
		var hd: float = to_wp.length()
		if hd < WP_ARRIVE:
			b["wp"] = wp_idx + 1
			b["stuck"] = 0
			b["prev_dist"] = INF
		elif hd > 0.001:
			to_wp /= hd
			body.velocity.x = to_wp.x * SPEED
			body.velocity.z = to_wp.z * SPEED
		else:
			body.velocity.x = 0.0
			body.velocity.z = 0.0
	else:
		body.velocity.x = 0.0
		body.velocity.z = 0.0
	body.velocity.y -= 9.8 * GRAVITY_MULT * d
	b["jump_cd"] -= 1
	if body.is_on_floor() and b["jump_cd"] <= 0 \
			and (body.is_on_wall() or b["stuck"] >= 6):
		body.velocity.y = JUMP_VELOCITY
		b["jump_cd"] = 14
		b["stuck"] = 0
	body.move_and_slide()
	var now := body.global_position
	b["path_len"] += Vector2(now.x - prev.x, now.z - prev.z).length()
	# 卡住检测（同 probe_v3_walk：距路点不缩短累计 6 帧 → 触发跳跃）
	if b["wp"] < route.size():
		var wp2: Vector2 = route[b["wp"]]
		var nd: float = Vector2(now.x - wp2.x, now.z - wp2.y).length()
		if nd >= b["prev_dist"] - 0.005:
			b["stuck"] += 1
		else:
			b["stuck"] = 0
		b["prev_dist"] = nd


# 双眼位互见：A 眼 → B 眼 raycast，exclude 两胶囊自身；命中地图实体 = 遮挡。
func _mutual_sight() -> bool:
	var ba: CharacterBody3D = _bots[0]["body"]
	var bb: CharacterBody3D = _bots[1]["body"]
	var eye_a := ba.global_position + Vector3(0, EYE_H, 0)
	var eye_b := bb.global_position + Vector3(0, EYE_H, 0)
	var q := PhysicsRayQueryParameters3D.create(eye_a, eye_b, 1)
	q.exclude = [ba.get_rid(), bb.get_rid()]
	return root.get_world_3d().direct_space_state.intersect_ray(q).is_empty()
