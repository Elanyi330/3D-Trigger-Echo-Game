# test/unit/test_player_life.gd
# 玩家生命组件（2026-08-13，TDD RED 先行）：
# 需求：100HP / 受伤扣血 / 死亡锁输入 / 3s（可注入）复活到随机空点 / 满血满弹（回调）。
# 断言：扣血信号 / 致命伤 died / 死亡期间伤害无效 / 复活满血+位置=回调点 / 回调触发。
extends GutTest

const LIFE := preload("res://Levels/M2_TDM/player_life.gd")


func _make_life() -> Dictionary:
	var life = LIFE.new()
	add_child_autofree(life)
	var dummy := Node.new()
	add_child_autofree(dummy)
	return {"life": life, "dummy": dummy}


func test_take_damage_reduces_health() -> void:
	var d := _make_life()
	var life: Node = d["life"]
	var dummy: Node = d["dummy"]
	var hps := []
	life.health_changed.connect(func(h: float) -> void: hps.append(h))
	life.setup(dummy)
	life.take_damage(25.0)
	assert_eq(life.health, 75.0, "100 − 25 = 75")
	assert_eq(hps.size(), 1, "扣血发一次信号")


func test_fatal_damage_dies_and_locks_input() -> void:
	var d := _make_life()
	var life: Node = d["life"]
	var dummy: Node = d["dummy"]
	var died := []
	life.died.connect(func() -> void: died.append(true))
	life.setup(dummy)
	life.take_damage(100.0)
	assert_eq(died.size(), 1, "致命伤发 died")
	assert_true(life.dead, "dead 置位")
	assert_eq(dummy.process_mode, Node.PROCESS_MODE_DISABLED, "死亡锁输入（玩家冻结）")


func test_damage_ignored_while_dead() -> void:
	var d := _make_life()
	var life: Node = d["life"]
	var dummy: Node = d["dummy"]
	life.setup(dummy)
	life.take_damage(200.0)
	var h := life.health
	life.take_damage(10.0)
	assert_eq(life.health, h, "死亡期间伤害无效")


func test_respawn_after_delay() -> void:
	var d := _make_life()
	var life: Node = d["life"]
	var dummy: Node = d["dummy"]
	var deaths := []
	var respawns := []
	life.died.connect(func() -> void: deaths.append(true))
	life.respawned.connect(func() -> void: respawns.append(true))
	life.setup(dummy, Callable(), func() -> Vector3: return Vector3(7, 0, 9), Callable(), 0.1)
	life.take_damage(999.0)
	assert_eq(respawns.size(), 0, "复活前无 respawned")
	await wait_seconds(0.3)
	assert_eq(respawns.size(), 1, "延迟后复活")
	assert_false(life.dead, "dead 复位")
	assert_eq(life.health, 100.0, "复活满血")
	assert_eq(dummy.position, Vector3(7, 0, 9), "复活到回调点")
	assert_eq(dummy.process_mode, Node.PROCESS_MODE_INHERIT, "复活恢复输入")


func test_death_and_reset_callbacks_fire() -> void:
	var d := _make_life()
	var life: Node = d["life"]
	var dummy: Node = d["dummy"]
	var on_death := []
	var on_reset := []
	life.setup(dummy,
		func() -> void: on_death.append(true),
		Callable(),  # 无复活点回调 → 保持原位
		func() -> void: on_reset.append(true),
		0.1)
	life.take_damage(999.0)
	assert_eq(on_death.size(), 1, "死亡瞬间回调（释放点位）")
	await wait_seconds(0.3)
	assert_eq(on_reset.size(), 1, "复活回调（满血满弹重置）")
	assert_eq(life.health, 100.0)


func test_respawn_now_overrides_pending_timer() -> void:
	var d := _make_life()
	var life: Node = d["life"]
	var dummy: Node = d["dummy"]
	var respawns := []
	life.respawned.connect(func() -> void: respawns.append(true))
	life.setup(dummy, Callable(), func() -> Vector3: return Vector3(1, 0, 2), Callable(), 5.0)
	life.take_damage(999.0)   # 死亡，5s 倒计时挂起
	life.respawn_now()        # 重开强制复活
	assert_eq(respawns.size(), 1, "立即复活")
	assert_false(life.dead)
	assert_eq(dummy.position, Vector3(1, 0, 2), "复活到回调点")
	await wait_seconds(0.5)
	assert_eq(respawns.size(), 1, "旧计时器失效，不双重复活")


func test_spawn_protection_blocks_damage() -> void:
	# 出生保护（2026-08-13 用户拍板）：复活后 2s 无敌
	var d := _make_life()
	var life: Node = d["life"]
	var dummy: Node = d["dummy"]
	life.setup(dummy, Callable(), Callable(), Callable(), 0.05)
	life.take_damage(999.0)
	await wait_seconds(0.15)  # 复活完成，protection_left=2.0
	assert_gt(life.protection_left, 0.0, "复活后保护期生效")
	life.take_damage(999.0)
	assert_eq(life.health, 100.0, "保护期内伤害无效")
	life.protection_left = 0.0  # 保护结束
	life.take_damage(40.0)
	assert_eq(life.health, 60.0, "保护结束后正常受伤")
