# test/unit/test_bot_strategy.gd
# M3.3 T15（2026-08-17）：BotStrategy 策略选择器测试（TDD，先 RED 后 GREEN）。
# 覆盖：4 触发纯函数（death_cluster/hunt_target_bias/flanker_eligible/
#   hold_eligible）+ 优先级裁决（防横跳）+ 冷却 20s + Hunter 槽位上限 2（先到先得）
#   + HUNTER 45s 生命周期 + 直接威胁优先铁律（ENGAGE/CHASE 冻结触发评估）。
# RED 锚：生产类 BotStrategy 尚不存在——本脚本引用该类即编译失败（错误信息 =
#   "Could not find type BotStrategy" 类加载错误，即正确的 RED 失败原因）。
# 时间口径：策略 _elapsed 与事件板 _elapsed 由各自 tick(delta) 求和单调累计；
#   集成语义测试以 1/60s 步进驱动（60Hz tick 铁律），与生产物理帧驱动同构。
extends GutTest

var _changes: Array = []  # strategy_changed 信号捕获 [[from, to], ...]


func before_each() -> void:
	_changes = []


func _on_strategy_changed(from: int, to: int) -> void:
	_changes.append([from, to])


## 测试夹具：独立 EventBoard + BotBlackboard + BotStrategy。with_body=true 时注入
## 真实 CharacterBody3D（global_position 默认 ZERO）——T15-6 判别力（审查 Minor 1）：
## FLANKER 候选需要 body 非 null 才真实成立，注入后优先级规则被真实受测。
func _make_rig(faction: String, with_body: bool = false) -> Dictionary:
	var board := EventBoard.new()
	add_child_autofree(board)
	var bb := BotBlackboard.new()
	add_child_autofree(bb)
	var st := BotStrategy.new()
	add_child_autofree(st)
	var bd: CharacterBody3D = null
	if with_body:
		bd = CharacterBody3D.new()
		add_child_autofree(bd)
	st.setup(faction, board, bb, bd)
	st.strategy_changed.connect(_on_strategy_changed)
	return {"strategy": st, "board": board, "blackboard": bb, "body": bd}


## 60Hz 步进：strategy 与 board 同步 tick（同锁步口径——board._elapsed 与
## strategy._elapsed 一致，阵亡窗口/冷却计时对齐）。
func _step(rig: Dictionary, seconds: float) -> void:
	var ticks := int(round(seconds * 60.0))
	for i in ticks:
		rig["strategy"].tick(1.0 / 60.0)
		rig["board"].tick(1.0 / 60.0)


# ── T15-1：3 死亡质心间距 ≤10 → clustered + centroid/max_pair_dist 正确 ──
func test_death_cluster_positive() -> void:
	var deaths := [
		{"pos": Vector3(0, 0, 0), "t": 0.0},
		{"pos": Vector3(6, 0, 0), "t": 1.0},
		{"pos": Vector3(0, 0, 8), "t": 2.0},
	]
	var r: Dictionary = BotStrategy.death_cluster(deaths, 15.0, 10.0)
	assert_true(r["clustered"], "3 死亡质心间最大距 10 ≤ 10 → 簇")
	assert_almost_eq(r["centroid"].x, 2.0, 1e-4, "质心 x = 2（均值）")
	assert_almost_eq(r["centroid"].y, 0.0, 1e-4, "质心 y = 0")
	assert_almost_eq(r["centroid"].z, 8.0 / 3.0, 1e-4, "质心 z = 8/3")
	assert_almost_eq(r["max_pair_dist"], 10.0, 1e-4, "质心间最大距 = 10")


# ── T15-2：间距 >10 或 <2 死亡 → 非簇 ──
func test_death_cluster_negative() -> void:
	var spread := [
		{"pos": Vector3(0, 0, 0), "t": 0.0},
		{"pos": Vector3(20, 0, 0), "t": 1.0},
	]
	var r1: Dictionary = BotStrategy.death_cluster(spread, 15.0, 10.0)
	assert_false(r1["clustered"], "间距 20 > 10 → 非簇")
	assert_almost_eq(r1["max_pair_dist"], 20.0, 1e-4, "非簇仍报最大距 20")
	var single := [{"pos": Vector3(0, 0, 0), "t": 0.0}]
	assert_false(BotStrategy.death_cluster(single, 15.0, 10.0)["clustered"],
			"<2 死亡 → 非簇")


# ── T15-3：目标在 C 25m 内 → 3.0；外 → 1.0（边界 25.0 含，<= 语义）──
func test_hunt_bias_in_radius() -> void:
	var p := {"centroid": Vector3.ZERO, "radius": 25.0, "bias": 3.0}
	assert_almost_eq(BotStrategy.hunt_target_bias(p, Vector3(24.9, 0, 0),
			Vector3(100, 0, 100)), 3.0, 1e-4, "24.9m 内 → 3.0")
	assert_almost_eq(BotStrategy.hunt_target_bias(p, Vector3(25.0, 0, 0),
			Vector3(100, 0, 100)), 3.0, 1e-4, "边界 25.0 → 3.0（<= 语义）")
	assert_almost_eq(BotStrategy.hunt_target_bias(p, Vector3(25.1, 0, 0),
			Vector3(100, 0, 100)), 1.0, 1e-4, "25.1m 外 → 1.0")


# ── T15-4：直线 15/path 22.5（恰 1.5 倍）→ true；直线 14 或 1.4 倍 → false ──
func test_flanker_eligible_boundary() -> void:
	assert_true(BotStrategy.flanker_eligible(Vector3.ZERO, Vector3(15, 0, 0), 22.5),
			"直线 15/path 22.5（恰 1.5 倍）→ true")
	assert_false(BotStrategy.flanker_eligible(Vector3.ZERO, Vector3(14, 0, 0), 21.0),
			"直线 14 < 15 → false")
	assert_false(BotStrategy.flanker_eligible(Vector3.ZERO, Vector3(15, 0, 0), 21.0),
			"path/直线 1.4 < 1.5 → false")


# ── T15-4b（审查裁决修复 1，2026-08-17）：FLANKER 出口 10m 与 ≥15m 触发无重叠 ──
# 目标直线 20m（旧 [15,30) 重叠区间）触发 FLANKER → 推进若干帧不立即退出（仍
# FLANKER——Flanker 在逼近 15m→10m 全程有效）；目标移到 9m → 接敌出口回 ROAM。
func test_flanker_exit_10m_regression() -> void:
	var rig := _make_rig("enemy", true)
	rig["blackboard"].set_value("state", "PATROL")
	rig["blackboard"].set_value("target_lkp", Vector3(20, 0, 0))  # 直线 20m ∈ 旧重叠区间
	rig["blackboard"].set_value("path_remaining", 40.0)          # 比率 2.0 ≥ 1.5
	rig["strategy"].tick(1.0 / 60.0)
	assert_eq(rig["strategy"].current(), BotStrategy.Strategy.FLANKER,
			"前置：直线 20m 触发 FLANKER")
	_step(rig, 1.0)  # 推进 60 帧
	assert_eq(rig["strategy"].current(), BotStrategy.Strategy.FLANKER,
			"出口 10m：20m 不立即退出（与 ≥15m 触发无重叠）")
	rig["blackboard"].set_value("target_lkp", Vector3(9, 0, 0))  # 目标逼近 9m
	rig["strategy"].tick(1.0 / 60.0)
	assert_eq(rig["strategy"].current(), BotStrategy.Strategy.ROAM,
			"目标 9m < 10m → 接敌出口回 ROAM")


# ── T15-5：存活少 + ≥2 阵亡非簇 → true；簇 → false；存活持平 → false ──
func test_hold_eligible_conditions() -> void:
	assert_true(BotStrategy.hold_eligible(2, 4, 2, false), "存活少 + 2 阵亡非簇 → true")
	assert_false(BotStrategy.hold_eligible(2, 4, 2, true), "簇 → false（Hunter 优先）")
	assert_false(BotStrategy.hold_eligible(2, 2, 2, false), "存活持平 → false")
	assert_false(BotStrategy.hold_eligible(2, 4, 1, false), "阵亡 <2 → false")


# ── T15-6：当前 HUNTER 遇 FLANKER 候选 → 不切换；当前 ROAM 遇 HOLD 候选 → 切换 ──
func test_priority_arbitration() -> void:
	# A：HUNTER（最高优先级）遇 FLANKER 候选 → 不切换（防横跳）
	# body 注入（审查 Minor 1 判别力）：FLANKER 候选真实成立（而非 body=null 候选
	# 缺失假通过）——优先级规则被真实受测。
	var rig := _make_rig("enemy", true)
	rig["blackboard"].set_value("state", "PATROL")
	rig["board"].record_death("enemy", Vector3(0, 0, 0))
	rig["board"].record_death("enemy", Vector3(5, 0, 0))  # 间距 5 → 簇 → HUNTER
	rig["strategy"].tick(1.0 / 60.0)
	assert_eq(rig["strategy"].current(), BotStrategy.Strategy.HUNTER,
			"前置：阵亡簇 → HUNTER")
	assert_true(_changes.has([BotStrategy.Strategy.ROAM, BotStrategy.Strategy.HUNTER]),
			"前置：ROAM→HUNTER 切换信号已发")
	# Flanker 候选：目标 LKP 直线 40m、path_remaining 100（比率 2.5 ≥ 1.5）
	rig["blackboard"].set_value("target_lkp", Vector3(40, 0, 0))
	rig["blackboard"].set_value("path_remaining", 100.0)
	assert_true(BotStrategy.flanker_eligible(Vector3.ZERO, Vector3(40, 0, 0), 100.0),
			"判别力前置：FLANKER 候选真实成立（body 非 null + 直线 40m + path 100）")
	_step(rig, 0.5)  # 0.5s（远小于 HUNTER 45s 生命周期与 20s 离 C 连续计时）
	assert_eq(rig["strategy"].current(), BotStrategy.Strategy.HUNTER,
			"HUNTER 优先级最高，FLANKER 候选不切换")
	assert_false(_changes.has([BotStrategy.Strategy.HUNTER, BotStrategy.Strategy.FLANKER]),
			"无 HUNTER→FLANKER 切换信号")
	# B：ROAM 遇 HOLD 候选 → 切换（HOLD 优先级 > ROAM）
	var rig2 := _make_rig("enemy")
	rig2["blackboard"].set_value("state", "PATROL")
	rig2["blackboard"].set_value("alive_own", 2)
	rig2["blackboard"].set_value("alive_enemy", 4)
	rig2["board"].record_death("enemy", Vector3(0, 0, 0))
	rig2["board"].record_death("enemy", Vector3(20, 0, 0))  # 间距 20 → 非簇 → HOLD
	rig2["strategy"].tick(1.0 / 60.0)
	assert_eq(rig2["strategy"].current(), BotStrategy.Strategy.HOLD,
			"ROAM 遇 HOLD 候选 → 切换")
	assert_eq(rig2["strategy"].params()["type"], "hold", "参数包 type=hold")


# ── T15-7：HOLD 超时结束后 20s 冷却内不重复触发；21s 后触发 ──
func test_cooldown_blocks_retrigger() -> void:
	var rig := _make_rig("enemy")
	rig["blackboard"].set_value("state", "PATROL")
	rig["blackboard"].set_value("alive_own", 2)
	rig["blackboard"].set_value("alive_enemy", 4)
	rig["board"].record_death("enemy", Vector3(0, 0, 0))
	rig["board"].record_death("enemy", Vector3(20, 0, 0))  # 非簇 → HOLD
	rig["strategy"].tick(1.0 / 60.0)
	assert_eq(rig["strategy"].current(), BotStrategy.Strategy.HOLD, "前置：触发 HOLD")
	_step(rig, 30.2)  # 超 HOLD_TIMEOUT(30) → ROAM + 冷却启动
	assert_eq(rig["strategy"].current(), BotStrategy.Strategy.ROAM,
			"HOLD 30s 超时 → ROAM")
	# 再造触发条件（新阵亡 2 条非簇——旧事件已出 15s 窗自然失效）
	rig["board"].record_death("enemy", Vector3(0, 0, 0))
	rig["board"].record_death("enemy", Vector3(20, 0, 0))
	_step(rig, 10.0)  # 结束后 10s：冷却余 10 → 不触发
	assert_eq(rig["strategy"].current(), BotStrategy.Strategy.ROAM,
			"结束 10s（冷却 20s 内）→ 不重复触发")
	# 再补新阵亡（保 15s 窗内）推 11.2s → 累计 21.2s 冷却过 → 触发
	rig["board"].record_death("enemy", Vector3(0, 0, 0))
	rig["board"].record_death("enemy", Vector3(20, 0, 0))
	_step(rig, 11.2)
	assert_eq(rig["strategy"].current(), BotStrategy.Strategy.HOLD,
			"结束 21.2s 冷却过 → 可再触发")


# ── T15-8：3 实例共享同一事件板依次申请 Hunter → 仅 2 成功；release 后可补位 ──
func test_slot_cap_two() -> void:
	var board := EventBoard.new()
	add_child_autofree(board)
	var strategies: Array = []
	for i in 3:
		var bb := BotBlackboard.new()
		add_child_autofree(bb)
		var st := BotStrategy.new()
		add_child_autofree(st)
		st.setup("enemy", board, bb, null)
		bb.set_value("state", "PATROL")
		strategies.append(st)
	board.record_death("enemy", Vector3(0, 0, 0))
	board.record_death("enemy", Vector3(5, 0, 0))  # 簇 → 三实例都申请 Hunter
	for s in strategies:
		s.tick(1.0 / 60.0)
	assert_eq(board.strategy_slots.get("hunter", 0), 2, "3 实例依次申请 → 仅 2 获槽")
	assert_eq(strategies[0].current(), BotStrategy.Strategy.HUNTER, "实例 0 获槽 HUNTER")
	assert_eq(strategies[1].current(), BotStrategy.Strategy.HUNTER, "实例 1 获槽 HUNTER")
	assert_eq(strategies[2].current(), BotStrategy.Strategy.ROAM,
			"实例 2 槽位失败 → 降级评估（无候选）保持 ROAM")
	# 实例 0 生命周期超时（45.1s）→ 释放槽位 → 实例 2 可补位
	for i in 2706:  # 45.1s @60Hz
		strategies[0].tick(1.0 / 60.0)
	assert_eq(board.strategy_slots.get("hunter", 0), 1, "实例 0 超时释放 → 余 1")
	strategies[2].tick(1.0 / 60.0)
	assert_eq(strategies[2].current(), BotStrategy.Strategy.HUNTER,
			"空出后第 3 个可 acquire → HUNTER")
	assert_eq(board.strategy_slots.get("hunter", 0), 2, "槽位计数回到 2")


# ── T15-9：HUNTER 推 45.1s → ROAM + 槽位释放（slots 计数回落）──
func test_hunter_lifetime() -> void:
	var rig := _make_rig("enemy")
	rig["blackboard"].set_value("state", "PATROL")
	rig["board"].record_death("enemy", Vector3(0, 0, 0))
	rig["board"].record_death("enemy", Vector3(5, 0, 0))  # 簇 → HUNTER
	rig["strategy"].tick(1.0 / 60.0)
	assert_eq(rig["strategy"].current(), BotStrategy.Strategy.HUNTER, "前置：触发 HUNTER")
	assert_eq(rig["board"].strategy_slots.get("hunter", 0), 1, "前置：槽位占用 1")
	var p: Dictionary = rig["strategy"].params()
	assert_eq(p["type"], "hunter", "参数包 type=hunter")
	assert_almost_eq(p["centroid"].x, 2.5, 1e-4, "参数包质心 x = 2.5")
	assert_almost_eq(p["radius"], 25.0, 1e-4, "参数包 radius = 25")
	assert_almost_eq(p["bias"], 3.0, 1e-4, "参数包 bias = 3.0")
	assert_eq(p["grenade_open"], true, "参数包 grenade_open = true")
	assert_eq(rig["blackboard"].get_value("hunt_centroid", Vector3.ZERO),
			Vector3(2.5, 0, 0), "进入时黑板写 hunt_centroid")
	_step(rig, 45.2)  # 超 HUNTER_LIFETIME(45)
	assert_eq(rig["strategy"].current(), BotStrategy.Strategy.ROAM,
			"45.2s 超时 → ROAM")
	assert_eq(rig["board"].strategy_slots.get("hunter", 0), 0,
			"槽位配对释放 → 计数回落 0")
	assert_eq(rig["strategy"].params()["type"], "roam", "参数包回 type=roam")


# ── T15-10：黑板 state 注入 ENGAGE/CHASE → 触发条件满足也不切换（直接威胁优先）──
func test_engage_freeze() -> void:
	# ENGAGE 冻结：HUNTER 簇条件满足也不切换；解冻后同条件切换（条件有效证明）
	var rig := _make_rig("enemy")
	rig["blackboard"].set_value("state", "ENGAGE")
	rig["blackboard"].set_value("alive_own", 2)
	rig["blackboard"].set_value("alive_enemy", 4)
	rig["board"].record_death("enemy", Vector3(0, 0, 0))
	rig["board"].record_death("enemy", Vector3(5, 0, 0))  # 簇 → HUNTER 条件满足
	_step(rig, 1.0)
	assert_eq(rig["strategy"].current(), BotStrategy.Strategy.ROAM,
			"ENGAGE 冻结：簇触发条件满足也不切换")
	rig["blackboard"].set_value("state", "PATROL")
	rig["strategy"].tick(1.0 / 60.0)
	assert_eq(rig["strategy"].current(), BotStrategy.Strategy.HUNTER,
			"解冻（PATROL）后同条件 → 切换（条件有效证明）")
	# CHASE 冻结：HOLD 条件满足也不切换
	var rig2 := _make_rig("friendly")
	rig2["blackboard"].set_value("state", "CHASE")
	rig2["blackboard"].set_value("alive_own", 1)
	rig2["blackboard"].set_value("alive_enemy", 3)
	rig2["board"].record_death("friendly", Vector3(0, 0, 0))
	rig2["board"].record_death("friendly", Vector3(20, 0, 0))  # 非簇 → HOLD 条件满足
	_step(rig2, 1.0)
	assert_eq(rig2["strategy"].current(), BotStrategy.Strategy.ROAM,
			"CHASE 冻结：HOLD 条件满足也不切换")
