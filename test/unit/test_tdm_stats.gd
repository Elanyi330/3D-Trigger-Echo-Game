# test/unit/test_tdm_stats.gd
# TDM 战绩模块（2026-08-13，TDD RED 先行）：
# 需求（用户拍板）：每局随机英文名（全部 AI+玩家）；结算按昵称展示 KD 与 KD 比；
# 死亡 0 次 KD 比显示 "MVP"。
extends GutTest

const STATS := preload("res://Levels/M2_TDM/tdm_stats.gd")


func test_new_match_generates_unique_names() -> void:
	var s = STATS.new()
	s.new_match()
	var names := []
	for i in range(10):
		names.append(s.make_name())
	var unique := {}
	for n in names:
		unique[n] = true
	assert_eq(unique.size(), 10, "10 个名字互不重复")
	for n in names:
		assert_true(STATS.NAME_POOL.has(n), "名字来自名字池")


func test_records_kill_death_and_kd() -> void:
	var s = STATS.new()
	s.new_match()
	var n1: String = s.make_name()
	var n2: String = s.make_name()
	s.register("friendly", n1)
	s.register("enemy", n2)
	s.add_kill(n1)
	s.add_kill(n1)
	s.add_death(n1)
	s.add_death(n2)
	var fr: Array = s.roster("friendly")
	assert_eq(fr.size(), 1, "友方花名册 1 人")
	assert_eq(fr[0]["kills"], 2)
	assert_eq(fr[0]["deaths"], 1)
	assert_eq(fr[0]["kd"], "2.00", "2 杀 1 死 KD 比 2.00")
	var er: Array = s.roster("enemy")
	assert_eq(er[0]["deaths"], 1)
	assert_eq(er[0]["kd"], "0.00", "0 杀 1 死 KD 比 0.00（MVP 仅 0 死）")


func test_kd_text_zero_deaths_is_mvp() -> void:
	var s = STATS.new()
	assert_eq(s.kd_text(0, 0), "MVP", "0 死 → MVP")
	assert_eq(s.kd_text(12, 0), "MVP", "12 杀 0 死 → MVP")
	assert_eq(s.kd_text(10, 4), "2.50", "10/4 → 2.50")


func test_new_match_resets_all() -> void:
	var s = STATS.new()
	s.new_match()
	var n: String = s.make_name()
	s.register("friendly", n)
	s.add_kill(n)
	s.new_match()
	assert_eq(s.records.size(), 0, "战绩清空")
	assert_eq(s.player_name, "", "玩家名清空")
	assert_eq(s.roster("friendly").size(), 0)
