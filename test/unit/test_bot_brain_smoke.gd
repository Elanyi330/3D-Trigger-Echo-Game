# test/unit/test_bot_brain_smoke.gd
# M3.3 T17+T18（2026-08-17）：L_M2 装配 + 5 敌 bot 全流程冒烟（TDD，先 RED 后 GREEN）——
# 出生→巡逻→感知（听觉/视线）→接敌意图（fire_intent 发射）→追击（CHASE）。
# RED 锚：L_M2 尚未装配 AI 链——test 1 前置断言「bot 已挂 BotBrain」失败、
# test 2 前置断言「NoiseBus 存在」失败、test 3 前置断言「至少一个 PATROL 敌 bot」
# 失败（黑板缺失 → _pick_patrol_bot 返回 null；装配缺失即正确的 RED 失败原因）。
# 冒烟口径（简报）：test 1 出生保护结束 + ≤300 帧 5 bot 全 PATROL 且真巡逻（各移动
# ≥0.5m）；test 2 噪音总线注入枪声（bot 30m 内）→ ≤120 帧 ALERT 且警戒目标 ≈ 枪声
# 位置（容差 5m）；test 3 玩家入视线（10m 无遮挡）→ ≤120 帧 ENGAGE + 反应时间后
# fire_intent ≥1，移出视线（锥外站位）→ ≤120 帧 CHASE；test 4（修复轮 1 回归）死
# bot 总线连接生命周期——击杀→淡出→注入事件零脚本错误 + 活 bot 仍收。
extends GutTest

const BOT_PERCEPTION := preload("res://Levels/M2_TDM/bot_perception.gd")

# fire_intent 信号计数（成员变量 + 方法连接——GDScript lambda 按值捕获局部变量，
# 局部 int 计数在 lambda 内自增不传播，实测假红；同 test_bot_locomotion_path 口径）
var _fire_count := 0


func _on_fire_intent(_target: Node) -> void:
	_fire_count += 1


# ── 测试辅助 ──

## 装配 L_M2 场景 + 立即 queue_free 场景内 JumpRecorder（防测试帧污染
##   user://jump_training 人类语料——项目铁律）+ 等导航两轮迭代（迭代 id ≥ 基值 +2，
##   同 L_M2._create_nav_links_after_sync 口径）+ 再等 60 物理帧（54 链接注册余量，
##   call_deferred 异步链，L_M2 F4 教训）+ 等 5 bot 出生保护（2s）过期全入 PATROL
##   （≤120 帧——暖进程导航复同步快、装配总帧数 < 保护 120 帧，bot 尚在 IDLE；
##   简报「出生保护结束」口径）。返回已同步且 5 bot 全 PATROL 的场景实例。
func _assemble_l2() -> Node3D:
	var l2: Node3D = load("res://Levels/M2_TDM/L_M2.tscn").instantiate()
	add_child_autofree(l2)
	var recorder: Node = l2.get_node_or_null("JumpRecorder")
	if recorder:
		recorder.queue_free()
	var map_rid: RID = l2.get_world_3d().navigation_map
	var base_iter := NavigationServer3D.map_get_iteration_id(map_rid)
	var synced := false
	for i in 120:
		await wait_physics_frames(1)
		if NavigationServer3D.map_get_iteration_id(map_rid) >= base_iter + 2:
			synced = true
			break
	assert_true(synced, "导航地图应在 120 帧内完成两轮迭代")
	await wait_physics_frames(60)
	await _wait_bots_patrol(l2, 120)
	return l2


## 等 5 敌 bot 黑板 state 全 PATROL（≤max_frames 帧；装配缺失时恒 false，
## 由各测试前置断言给出 RED 原因）。
func _wait_bots_patrol(l2: Node3D, max_frames: int) -> bool:
	for _f in max_frames:
		await wait_physics_frames(1)
		var all := true
		for b in _enemy_bots(l2):
			var bb := _bb(b)
			if bb == null or bb.get_value("state", "") != "PATROL":
				all = false
				break
		if all:
			return true
	return false


## 取场景内 5 敌 bot（L_M2 直接子节点中 is_enemy==true 的 Enemy）。
func _enemy_bots(l2: Node3D) -> Array:
	var out: Array = []
	for c in l2.get_children():
		if c is Enemy and (c as Enemy).is_enemy:
			out.append(c)
	return out


func _brain(bot: Node) -> Node:
	return bot.get_node_or_null("BotBrain")


func _bb(bot: Node) -> Node:
	return bot.get_node_or_null("BotBlackboard")


## 选一个 PATROL 中的 bot（hearing/视线转移以 PATROL 为常态前提；全队恒 PATROL
## 于冒烟 1 已钉死，此处防御性挑选；装配缺失时 bb 为 null → 返回 null 由前置断言接管）。
func _pick_patrol_bot(bots: Array) -> Enemy:
	for b in bots:
		var bb := _bb(b)
		if bb != null and bb.get_value("state", "") == "PATROL":
			return b
	return null


## LOS 射线排除集合（BotPerception._exclude_rids 同口径）：观察者（bot）与目标（玩家）
## 本体及子碰撞体——射线终点在目标躯干胶囊内，不排除则恒被目标本体遮挡。
func _exclude_rids(bot: Node3D, player: Node3D) -> Array[RID]:
	var out: Array[RID] = []
	for n in [bot, player]:
		if n is CollisionObject3D:
			out.append((n as CollisionObject3D).get_rid())
			for c in n.get_children():
				if c is CollisionObject3D:
					out.append((c as CollisionObject3D).get_rid())
	return out


## 玩家视线内站位搜索（bot 相对，确定性）：LOS 无遮挡 + 可站立（10m 优先——
## 简报「10m 无遮挡」；锥角不由本函数约束——测试直接设定 bot 朝向）。地面探针
## 自 5m 高处下探（高于树顶 3.75/墙 3/屋顶 4.9）：首命中高度 ≈ bot y = 同层平地；
## ≥2.5 = 头顶高位遮挡（营地屋顶 4.5+，下方仍可站立）；其余（0.6 台面/1.2 摊阁——
## 胸口高度与感知口径偏移）剔除；墙内/树内站位由 LOS 判定先行剔除（射线穿体必挡）。
## 返回 INF = 无可用点（应视为基础设施失败）。
func _find_visible_spot(bot: Enemy, player: Node3D) -> Vector3:
	var space := bot.get_world_3d().direct_space_state
	var eye := bot.global_position + BOT_PERCEPTION.EYE_OFFSET
	var exclude := _exclude_rids(bot, player)
	for dist: float in [10.0, 8.0, 12.0, 15.0, 20.0]:
		for k in 12:
			var ang := float(k) * PI / 6.0
			var dir := Vector3(-sin(ang), 0.0, -cos(ang))
			var p := bot.global_position + dir * dist
			if absf(p.x) > 28.0 or absf(p.z) > 27.0:
				continue  # 地图边界（BOUND_X 30 / BOUND_Z 29）内
			if BOT_PERCEPTION.los_blocked(space, eye, p + BOT_PERCEPTION.CHEST_OFFSET,
					BOT_PERCEPTION.LOS_MASK, exclude):
				continue
			var probe := PhysicsRayQueryParameters3D.create(
					p + Vector3(0, 5.0, 0), p + Vector3(0, -3.0, 0), 1)
			var hit := space.intersect_ray(probe)
			if hit.is_empty():
				continue
			var hit_y := float(hit["position"].y)
			if absf(hit_y - bot.global_position.y) > 0.35 and hit_y < 2.5:
				continue
			return p
	return Vector3.INF


## 朝目标设定 bot 朝向：前向口径 (−sin yaw, −cos yaw)（T3 修正）→
## yaw = atan2(−dx, −dz)。测试控制朝向保证锥角确定性（ENGAGE 期 bot 站定不转）。
func _face_toward(bot: Enemy, target: Vector3) -> void:
	var d := Vector3(target.x - bot.global_position.x, 0.0,
			target.z - bot.global_position.z)
	if d.length() > 1e-6:
		bot.rotation.y = atan2(-d.x, -d.z)


## 目标移出视线站位：bot 身后 12m（朝向反侧 180°，锥外——感知锥 120° 全锥，
## 身后点与任意锥内方向夹角 ≥120°）。ENGAGE 期 bot 站定不转（locomotion 目标已清），
## 追击转身朝向 LKP（锥内 ±60°）时该点仍恒锥外。视距内锥外 = 不可见（感知三条件
## 与逻辑），CHASE 全窗口稳定。
func _hide_behind(bot: Enemy) -> Vector3:
	var fwd := Vector2(-sin(bot.rotation.y), -cos(bot.rotation.y))
	return bot.global_position + Vector3(-fwd.x, 0.0, -fwd.y) * 12.0


## 等待谓词成立（每物理帧轮询一次；≤max_frames）。
func _wait_until(pred: Callable, max_frames: int) -> bool:
	for _f in max_frames:
		if pred.call():
			return true
		await wait_physics_frames(1)
	return false


# ── 冒烟 1：出生保护结束 → 5 bot 全部 PATROL + 巡逻目标非空 + 真巡逻（移动 ≥0.5m）──
func test_five_bots_patrol_after_spawn() -> void:
	var l2 := await _assemble_l2()
	var bots := _enemy_bots(l2)
	assert_eq(bots.size(), 5, "前置：L_M2 应产出 5 敌 bot")
	var chains_ok := true
	for b in bots:
		if _brain(b) == null or _bb(b) == null:
			chains_ok = false
	assert_true(chains_ok, "前置：5 bot 应已挂 BotBrain/BotBlackboard（L_M2 装配链）")
	if not chains_ok:
		return  # 装配缺失：其余断言无意义（RED 阶段到此为止）
	var start_pos: Dictionary = {}
	for b in bots:
		start_pos[b] = (b as Node3D).global_position
	# 出生保护（2s）已在装配等待中过期；推进 ≤300 帧：全 PATROL + 各移动 ≥0.5m
	var all_patrol := false
	var all_moved := false
	for _f in 300:
		await wait_physics_frames(1)
		all_patrol = true
		all_moved = true
		for b in bots:
			if _bb(b).get_value("state", "") != "PATROL":
				all_patrol = false
			var sp: Vector3 = start_pos[b]
			var bp: Vector3 = (b as Node3D).global_position
			if Vector2(bp.x - sp.x, bp.z - sp.z).length() < 0.5:
				all_moved = false
		if all_patrol and all_moved:
			break
	assert_true(all_patrol, "≤300 帧内 5 bot 应全部 PATROL（黑板 state 键）")
	assert_true(all_moved, "≤300 帧内 5 bot 各应移动 ≥0.5m（真巡逻而非站桩）")
	for b in bots:
		var pt: Dictionary = _bb(b).get_value("patrol_target", {})
		assert_false(pt.is_empty(), "bot %s 巡逻目标（locomotion 目标）非空" % b.name)


# ── 冒烟 2：枪声（噪音总线注入，bot 30m 内）→ ≤120 帧 ALERT 且警戒目标 ≈ 枪声位置 ──
func test_bot_alerts_on_gunshot() -> void:
	var l2 := await _assemble_l2()
	var bus: Node = l2.get_node_or_null("NoiseBus")
	assert_not_null(bus, "前置：L_M2._setup_bot_ai 应创建 NoiseBus（T7 契约装配）")
	var bots := _enemy_bots(l2)
	var bot := _pick_patrol_bot(bots)
	assert_not_null(bot, "前置：应至少有一个 PATROL 中的敌 bot")
	if bus == null or bot == null:
		return
	# 枪声位置：bot 北方 12m（bot 30m 内——简报口径；经噪音总线注入，简报允许
	# 「经 noise_bus 注入或直调」）。北向 = 远离玩家营地侧，防转身后视线接敌转
	# ENGAGE 干扰 ALERT 断言（其余 4 bot 同闻事件转 ALERT，不影响本断言）。
	var event_pos: Vector3 = bot.global_position + Vector3(0, 0, 12)
	bus.noise_event.emit("gunshot", event_pos, 100.0)
	var alerted := await _wait_until(func() -> bool:
		return _bb(bot).get_value("state", "") == "ALERT", 120)
	assert_true(alerted, "≤120 帧内 bot 应进入 ALERT（实际状态 %s）"
			% _bb(bot).get_value("state", ""))
	var target: Vector3 = _bb(bot).get_value("target_lkp", Vector3.INF)
	var d := Vector2(target.x - event_pos.x, target.z - event_pos.z).length()
	assert_lt(d, 5.0, "警戒目标应 ≈ 枪声位置（容差 5m，实际 %.2f）" % d)


# ── 冒烟 3：玩家入视线（10m 无遮挡）→ ENGAGE + fire_intent ≥1；移出视线 → CHASE ──
func test_bot_engages_on_sight() -> void:
	var l2 := await _assemble_l2()
	var player: Node3D = l2.get_node("Player")
	var bots := _enemy_bots(l2)
	var bot := _pick_patrol_bot(bots)
	assert_not_null(bot, "前置：应至少有一个 PATROL 中的敌 bot")
	if bot == null:
		return
	var brain: Node = _brain(bot)
	assert_not_null(brain, "前置：bot 应已挂 BotBrain（L_M2 装配链）")
	if brain == null:
		return
	_fire_count = 0
	brain.fire_intent.connect(_on_fire_intent)
	# 确定性站位控制：bot 迁至已知开阔走廊（(0,0,5.5)——既有移动测试验证的平地
	# 目标点；bot 巡逻随机落点可能在营地墙内，锥内视线被墙全封、无可视站位）+
	# 清零移动指令（防残留 move_axis 推动）+ 落定。玩家随后入视线（简报
	# 「玩家走到敌 bot 视线内」——bot 站定、玩家移动等价，测试为确定性迁 bot）。
	bot.global_position = Vector3(0, 0.5, 5.5)
	bot.velocity = Vector3.ZERO
	var loco: Node = bot.get_node_or_null("BotLocomotion")
	if loco != null:
		loco.clear_target()
	bot.command_override.move_axis = Vector2.ZERO
	await wait_physics_frames(5)  # 落定
	var visible_pos := _find_visible_spot(bot, player)
	assert_false(is_inf(visible_pos.x), "应能找到 bot 视线内站位（10m 无遮挡）")
	if is_inf(visible_pos.x):
		return
	_face_toward(bot, visible_pos)
	player.global_position = visible_pos
	var engaged := await _wait_until(func() -> bool:
		return _bb(bot).get_value("state", "") == "ENGAGE", 120)
	assert_true(engaged, "≤120 帧内 bot 应 ENGAGE（玩家入视线；实际状态 %s）"
			% _bb(bot).get_value("state", ""))
	# 反应时间（0.3-0.6s 随机）归零后首发 fire_intent（此后 0.2s 节流持续发）
	var fired := await _wait_until(func() -> bool: return _fire_count >= 1, 90)
	assert_true(fired, "反应时间后应发射 fire_intent（实际 %d 次）" % _fire_count)
	# 移出视线：身后 12m（锥外）→ hostile_lost → CHASE（LKP 8s 内保持追击）
	var hide_pos := _hide_behind(bot)
	player.global_position = hide_pos
	var chasing := await _wait_until(func() -> bool:
		return _bb(bot).get_value("state", "") == "CHASE", 120)
	assert_true(chasing, "目标移出视线 ≤120 帧内 bot 应 CHASE（实际状态 %s）"
			% _bb(bot).get_value("state", ""))


# ── 冒烟 4：死 bot 总线连接生命周期（2026-08-17 M3.3 T18 修复轮 1 回归）──
# 实机 bug：噪音总线 lambda 捕获 bot 感知，bot 死亡淡出 queue_free 后 lambda 仍挂
# 总线，玩家每走一步触发已释放捕获 → SCRIPT ERROR 刷屏（GUT 冒烟未抓到：原测试
# 从不击杀 bot 后发噪音）。RED 锚：修复前本测试注入事件必触发脚本错误，GUT 对
# 测试期间脚本错误自动判失败。
# 断言口径：无脚本错误（GUT 自动）+ 存活 bot 感知队列非空（断开只影响死 bot）。
func test_dead_bot_bus_silent() -> void:
	var l2 := await _assemble_l2()
	var bus: Node = l2.get_node_or_null("NoiseBus")
	assert_not_null(bus, "前置：NoiseBus 应存在")
	var bots := _enemy_bots(l2)
	assert_eq(bots.size(), 5, "前置：L_M2 应产出 5 敌 bot")
	if bus == null or bots.size() != 5:
		return
	# 击杀一名敌 bot（出生保护已过期——_assemble_l2 已等 PATROL；999 伤害即死）
	var victim: Enemy = bots[0]
	assert_false(victim.dead, "前置：受害 bot 应存活")
	victim.take_damage(999.0)
	assert_true(victim.dead, "前置：take_damage 999 应立即致死（died 已同步发射）")
	# 等死亡淡出结束（倒地 0.3s + 淡出 0.5s = 48 帧；60 帧余量）→ 尸体已 queue_free
	await wait_physics_frames(60)
	assert_false(is_instance_valid(victim), "前置：死亡淡出后敌 bot 尸体应已释放")
	# 经总线注入脚步/枪声 ×3（修复前：已释放 lambda 捕获被触发 → SCRIPT ERROR）
	for k in 3:
		bus.noise_event.emit("footstep", Vector3(0, 0, 5), 20.0)
		bus.noise_event.emit("gunshot", Vector3(0, 0, 5), 100.0)
		await wait_physics_frames(1)
	# 推进若干帧（无脚本错误即本测试核心断言——GUT 自动判失败，无额外错误断言）
	await wait_physics_frames(10)
	# 存活 bot 仍正常收到事件（事件队列在 TTL 内非空——断开只影响死 bot 不影响活 bot）
	var alive_got := false
	for b in bots:
		if not is_instance_valid(b):
			continue
		var perc: Node = (b as Node).get_node_or_null("BotPerception")
		if perc != null and not (perc.get("_heard_events") as Array).is_empty():
			alive_got = true
			break
	assert_true(alive_got, "存活 bot 应仍经总线收到噪音事件（断开仅限死 bot）")
