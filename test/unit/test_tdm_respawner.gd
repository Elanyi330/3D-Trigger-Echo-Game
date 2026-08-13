# test/unit/test_tdm_respawner.gd
# TDM 敌营补位器（2026-08-13，TDD RED 先行）：
# 需求（用户拍板）：敌人从敌方营地出生（10 点随机取 5），死亡后 3s（可注入）
# 从"当前无角色占用的点位"补位——恒 5 敌、绝不与其他角色重叠。
# 断言：开局 5 敌不重叠 / 敌死延迟后补位到空点 / enemy_died 信号 / clear 清场 /
#       generation 防旧计时器重开后多刷。
extends GutTest

const RESPAWNER := preload("res://Levels/M2_TDM/tdm_respawner.gd")


class StubEnemy extends Node3D:
	signal died
	var health := 100.0
	var spawn_pos: Vector3
	var _fired := false

	func take_damage(d: float) -> void:
		health -= d
		if health <= 0.0 and not _fired:
			_fired = true
			died.emit()


func _make() -> Dictionary:
	var r = RESPAWNER.new()
	add_child_autofree(r)
	var pts := []
	for i in range(10):
		pts.append(Vector3(i * 3.0, 0, 0))
	var spawned: Array = []
	r.setup(pts, func() -> Node:
		var e := StubEnemy.new()
		r.add_child(e)  # 入树：global_position 定位需要（生产侧 L_M2._spawn_enemy 同款 add_child）
		spawned.append(e)
		return e, 0.1)
	return {"r": r, "spawned": spawned}


func test_start_spawns_five_distinct() -> void:
	var d := _make()
	var r: Node = d["r"]
	r.start()
	assert_eq(r.alive_count(), 5, "开局恒 5 敌")
	var pos_seen := {}
	for e in d["spawned"]:
		assert_false(pos_seen.has(e.global_position), "5 敌点位不重叠")
		pos_seen[e.global_position] = true
	assert_eq(r._pool.occupied_count(), 5, "池占用 5")


func test_kill_respawns_to_free_point() -> void:
	var d := _make()
	var r: Node = d["r"]
	var died_log: Array = []
	r.enemy_died.connect(func(e: Node) -> void: died_log.append(e))
	r.start()
	var victim: Node = d["spawned"][0]
	var living_pos := []
	for i in range(1, 5):
		living_pos.append(d["spawned"][i].global_position)
	victim.take_damage(999.0)
	assert_eq(died_log.size(), 1, "敌死发 enemy_died")
	assert_eq(r.alive_count(), 4, "死亡后在场 4")
	await wait_seconds(0.3)
	assert_eq(r.alive_count(), 5, "延迟后补位回 5")
	assert_eq(d["spawned"].size(), 6, "新敌已生成")
	var newcomer: Node = d["spawned"][5]
	assert_false(living_pos.has(newcomer.global_position), "补位新敌不与存活 4 敌重叠")


func test_clear_frees_field() -> void:
	var d := _make()
	var r: Node = d["r"]
	r.start()
	var spawned: Array = d["spawned"]
	r.clear()
	assert_eq(r.alive_count(), 0, "清场 alive=0")
	assert_eq(r._pool.occupied_count(), 0, "池全部释放")
	await wait_seconds(0.05)
	for e in spawned:
		assert_false(is_instance_valid(e), "清场后敌人全部释放")


func test_generation_guard_after_clear() -> void:
	var d := _make()
	var r: Node = d["r"]
	r.start()
	var victim: Node = d["spawned"][0]
	victim.take_damage(999.0)  # 补位计时器已挂
	r.clear()                  # 重开：旧计时器必须失效
	await wait_seconds(0.3)
	assert_eq(r.alive_count(), 0, "重开后旧补位计时器不生效（generation 防御）")
	assert_eq(d["spawned"].size(), 5, "无新敌生成")


func test_null_spawn_fn_defensive() -> void:
	var r = RESPAWNER.new()
	add_child_autofree(r)
	r.setup([Vector3(0, 0, 0)], func() -> Node: return null, 0.1)
	r.start()
	assert_eq(r.alive_count(), 0, "spawn_fn 返回 null 防御性跳过")
