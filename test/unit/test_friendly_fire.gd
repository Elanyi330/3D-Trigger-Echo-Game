# test/unit/test_friendly_fire.gd
# 阵营级友伤过滤（2026-08-13，TDD RED 先行）：
# 需求（用户拍板）：任何阵营内部均无友伤——M2 玩家不打友军；
# M3 队友 AI 不打玩家/队友（"friendly" 阵营）、M3 敌人 AI 不打敌人（"enemy" 阵营）。
# 断言：谓词语义 + hitscan 结算入口过滤（无伤害/无命中标记）。
extends GutTest

const ENEMY := preload("res://Levels/Enemy/Enemy.gd")


func test_predicate_friendly_vs_friendly() -> void:
	# 玩家（friendly 阵营）打友军 → 友伤
	var ally = ENEMY.new()
	ally.is_enemy = false
	assert_true(ENEMY.is_friendly_fire("friendly", ally), "friendly 打友军 = 友伤")
	assert_false(ENEMY.is_friendly_fire("friendly", null), "null 目标不拦")


func test_predicate_enemy_ai_rules() -> void:
	# M3 预留：敌人 AI（enemy 阵营）
	var enemy = ENEMY.new()      # is_enemy=true
	var ally = ENEMY.new()
	ally.is_enemy = false
	assert_true(ENEMY.is_friendly_fire("enemy", enemy), "敌人 AI 打敌人 = 友伤（拦截）")
	assert_false(ENEMY.is_friendly_fire("enemy", ally), "敌人 AI 打友军 = 有效伤害")
	# 玩家（get_faction 鸭子接口——PlayerLife 提供 "friendly"）
	var player_stub := Node.new()
	player_stub.set_script(load("res://Levels/M2_TDM/player_life.gd"))
	assert_false(ENEMY.is_friendly_fire("enemy", player_stub), "敌人 AI 打玩家 = 有效伤害")
	assert_true(ENEMY.is_friendly_fire("friendly", player_stub), "队友 AI 打玩家 = 友伤（拦截）")


func test_enemy_faction_api() -> void:
	var enemy = ENEMY.new()
	var ally = ENEMY.new()
	ally.is_enemy = false
	assert_eq(enemy.get_faction(), "enemy")
	assert_eq(ally.get_faction(), "friendly")


func test_enemy_spawn_protection_blocks_damage() -> void:
	# 出生保护（2026-08-13 用户拍板）：出生/复活 2s 无敌（Enemy 侧同规则）
	var foe = ENEMY.new()
	foe.is_enemy = true
	foe.spawn_protection = 2.0
	foe.take_damage(999.0)
	assert_eq(foe.health, 100.0, "保护期内伤害无效")
	foe.spawn_protection = 0.0
	foe.take_damage(40.0)
	assert_eq(foe.health, 60.0, "保护结束后正常受伤")


func test_hitscan_settlement_skips_friendly() -> void:
	# WeaponManager 伤害结算入口（_on_hit_landed 直调）：命中友军 → 不结算/不发命中标记
	var ally = ENEMY.new()
	ally.is_enemy = false
	ally.display_name = "Ally"
	add_child_autofree(ally)
	var foe = ENEMY.new()
	foe.is_enemy = true
	add_child_autofree(foe)  # 入树：弹孔挂载需要 global_transform
	var mgr := WeaponManager.new()
	add_child_autofree(mgr)
	var hits := []
	mgr.enemy_hit.connect(func() -> void: hits.append(true))
	mgr._on_hit_landed(ally, 30.0, Vector3.ZERO, Vector3.UP)
	assert_eq(ally.health, 100.0, "友军不掉血")
	assert_eq(hits.size(), 0, "不发命中标记")
	# 敌方目标仍正常结算
	mgr._on_hit_landed(foe, 30.0, Vector3.ZERO, Vector3.UP)
	assert_eq(foe.health, 70.0, "敌方正常掉血")
	assert_eq(hits.size(), 1, "敌方命中发标记")
