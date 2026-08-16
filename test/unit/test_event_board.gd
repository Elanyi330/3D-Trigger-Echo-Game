# test/unit/test_event_board.gd
# M3.2 T9（2026-08-17）：EventBoard 事件板测试（TDD，先 RED 后 GREEN）。
# 目标：死亡事件记录（faction+pos+t）/ 时间窗查询（faction+within 双条件）/
#   TTL 30s 剔除 / L_M2 集成：敌死钩子写 "enemy" 事件、玩家死钩子写 "friendly" 事件。
# RED 锚：生产类 EventBoard 尚不存在——本脚本引用该类即编译失败（错误信息 =
#   "Could not find type EventBoard" 类加载错误，即正确的 RED 失败原因）。
# 时间口径：_elapsed 由 tick(delta) 求和单调累计（不用 Time.get_ticks，测试可控）；
#   集成测试以真实物理帧推进，与生产 L_M2._process 每帧 tick 驱动同构。
extends GutTest

var _events: Array = []  # death_event 信号捕获 [{faction, pos, t}]


func _on_death_event(faction: String, pos: Vector3, t: float) -> void:
	_events.append({"faction": faction, "pos": pos, "t": t})


func _make_board() -> EventBoard:
	var board := EventBoard.new()
	add_child_autofree(board)
	board.death_event.connect(_on_death_event)
	return board


## 装配 L_M2 场景 + 立即 queue_free 场景内 JumpRecorder（防测试帧污染
##   user://jump_training 人类语料——项目铁律）+ 等导航两轮迭代（迭代 id ≥ 基值 +2，
##   同 L_M2._create_nav_links_after_sync 口径）+ 再等 60 物理帧（链接注册余量）。
##   返回已同步的场景实例（同 test_bot_locomotion_path.gd 范式）。
func _assemble_l2() -> Node3D:
	var l2: Node3D = load("res://Levels/M2_TDM/L_M2.tscn").instantiate()
	add_child_autofree(l2)
	var recorder: Node = l2.get_node_or_null("JumpRecorder")
	assert_not_null(recorder, "前置：L_M2._ready 应创建 JumpRecorder 子节点")
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
	return l2


# ── T9-1：record ×3（不同 faction/时间）→ recent_deaths faction+within 双条件过滤 ──
func test_record_and_query() -> void:
	var board := _make_board()
	board.record_death("enemy", Vector3(1, 0, 0))     # t=0
	board.tick(5.0)                                    # _elapsed=5
	board.record_death("friendly", Vector3(2, 0, 0))  # t=5
	board.tick(5.0)                                    # _elapsed=10
	board.record_death("enemy", Vector3(3, 0, 0))     # t=10
	# faction 过滤 + t 升序
	var all_enemy: Array = board.recent_deaths("enemy", 100.0)
	assert_eq(all_enemy.size(), 2, "enemy 事件 2 条（friendly 被 faction 过滤）")
	assert_eq(all_enemy[0]["pos"], Vector3(1, 0, 0), "按 t 升序：先 t=0 事件")
	assert_eq(all_enemy[1]["pos"], Vector3(3, 0, 0), "按 t 升序：后 t=10 事件")
	assert_eq(board.recent_deaths("friendly", 100.0).size(), 1, "friendly 事件 1 条")
	# within 过滤：t=0 事件 age 10 > 7 排除；t=10 事件 age 0 ≤ 7 保留
	var recent: Array = board.recent_deaths("enemy", 7.0)
	assert_eq(recent.size(), 1, "within=7 仅保留 7s 内事件")
	assert_eq(recent[0]["pos"], Vector3(3, 0, 0), "保留的是最新事件")
	# death_event 信号：record 每次发射、参数一致
	assert_eq(_events.size(), 3, "record_death 每次发射 death_event")
	assert_eq(_events[0]["faction"], "enemy", "信号 faction 正确")
	assert_eq(_events[0]["pos"], Vector3(1, 0, 0), "信号 pos 正确")
	assert_eq(_events[0]["t"], 0.0, "信号 t = 记录时 _elapsed")
	# 查询返回副本：外部改动不回写板内
	recent[0]["pos"] = Vector3.ZERO
	assert_eq(board.recent_deaths("enemy", 7.0)[0]["pos"], Vector3(3, 0, 0),
			"查询返回副本，外部改动不回写")


# ── T9-2：注入推进 30.1s → age > DEATH_TTL 旧事件剔除（窗口 60 也不复活）──
func test_ttl_expiry() -> void:
	var board := _make_board()
	board.record_death("enemy", Vector3(1, 0, 0))   # t=0
	board.tick(20.0)                                 # _elapsed=20
	board.record_death("enemy", Vector3(2, 0, 0))   # t=20
	board.tick(10.1)                                 # _elapsed=30.1
	var recent: Array = board.recent_deaths("enemy", 60.0)
	assert_eq(recent.size(), 1, "age 30.1 > DEATH_TTL(30) 旧事件已剔除（窗口 60 不含）")
	assert_eq(recent[0]["pos"], Vector3(2, 0, 0), "age 10.1 ≤ 30 新事件保留")


# ── T9-3：within=15 时间窗边界——14s 前含 / 15.1s 前不含 / 恰好 15s 界内（<= 语义）──
func test_time_window_semantics() -> void:
	var board := _make_board()
	board.record_death("enemy", Vector3(1, 0, 0))   # t=0
	board.tick(3.0)                                  # _elapsed=3
	board.record_death("enemy", Vector3(2, 0, 0))   # t=3
	board.tick(14.0)                                 # _elapsed=17
	var recent: Array = board.recent_deaths("enemy", 15.0)
	assert_eq(recent.size(), 1, "within=15：t=0 事件 age 17 > 15 不含")
	assert_eq(recent[0]["pos"], Vector3(2, 0, 0), "t=3 事件 age 14 ≤ 15 含（14s 前含）")
	board.record_death("enemy", Vector3(3, 0, 0))   # t=17
	board.tick(1.0)                                  # _elapsed=18
	recent = board.recent_deaths("enemy", 15.0)
	assert_eq(recent.size(), 2, "t=3 事件 age 15 界内含（<= 语义，追加序即 t 升序）")
	assert_eq(recent[0]["pos"], Vector3(2, 0, 0), "旧事件仍按 t 升序在前")
	assert_eq(recent[1]["pos"], Vector3(3, 0, 0), "最新事件在后")


# ── T9-4（集成）：L_M2 敌死钩子——敌 bot take_damage(999) → board 含 "enemy" 事件 ──
# 死亡链全同步（Enemy.died → TdmRespawner.enemy_died → L_M2._on_enemy_died →
# EventBoard.record_death），take_damage 返回即已写板；再推几帧让场景稳定。
# 位置容差 0.5（记录时刻 = 死亡时刻，同步链内位置不变）。
func test_l2_enemy_death_hook() -> void:
	var l2 := await _assemble_l2()
	var board: EventBoard = l2.get_node_or_null("EventBoard")
	assert_not_null(board, "前置：L_M2._ready 应创建 EventBoard 子节点")
	if board == null:
		return
	var victim: Enemy = null
	for c in l2.get_children():
		if c is Enemy and c.is_enemy:
			victim = c
			break
	assert_not_null(victim, "前置：L_M2 场景应有 is_enemy 敌 bot")
	if victim == null:
		return
	victim.spawn_protection = 0.0  # 出生保护免疫伤害，测试先清（L_M2 开局 2s 保护）
	var death_pos: Vector3 = victim.global_position
	victim.take_damage(999.0)
	await wait_physics_frames(5)  # 推进死亡链/场景稳定帧
	var deaths: Array = board.recent_deaths("enemy", 30.0)
	var found := false
	var best := INF
	for ev in deaths:
		var d := (ev["pos"] as Vector3).distance_to(death_pos)
		best = minf(best, d)
		if d <= 0.5:
			found = true
	assert_true(found,
			"敌死钩子应写 enemy 事件且位置=死亡位置（最近距 %.3f，事件 %d 条）"
			% [best, deaths.size()])


# ── T9-5（集成）：L_M2 玩家死钩子——life.take_damage(999) → board 含 "friendly" 事件 ──
# 走真实 K 自杀链（PlayerLife.died → L_M2._on_player_died → record_death("friendly")）。
func test_l2_player_death_hook() -> void:
	var l2 := await _assemble_l2()
	var board: EventBoard = l2.get_node_or_null("EventBoard")
	assert_not_null(board, "前置：L_M2._ready 应创建 EventBoard 子节点")
	if board == null:
		return
	var life: PlayerLife = l2.get_node("Player/PlayerLife")
	life.protection_left = 0.0  # 出生保护免疫伤害，测试先清
	var player: Node3D = l2.get_node("Player")
	var death_pos: Vector3 = player.global_position
	life.take_damage(999.0)
	await wait_physics_frames(5)
	var deaths: Array = board.recent_deaths("friendly", 30.0)
	var found := false
	var best := INF
	for ev in deaths:
		var d := (ev["pos"] as Vector3).distance_to(death_pos)
		best = minf(best, d)
		if d <= 0.5:
			found = true
	assert_true(found,
			"玩家死钩子应写 friendly 事件且位置=玩家死亡位置（最近距 %.3f，事件 %d 条）"
			% [best, deaths.size()])
