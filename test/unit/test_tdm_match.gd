# test/unit/test_tdm_match.gd
# TDM 比赛状态机（2026-08-13，TDD RED 先行）：
# 需求（用户 2026-08-11 拍板）：无限复活、先到 50 击杀获胜、或 8 分钟内击杀多者获胜。
# 断言：计分信号 / 50 杀胜负（注入低目标）/ 时间到判分 / 平局 / 结束冻结计分 / reset 全清。
extends GutTest

const MATCH := preload("res://Levels/M2_TDM/tdm_match.gd")


func test_score_changed_signal() -> void:
	var m = MATCH.new()
	add_child_autofree(m)
	m.setup(50, 480.0)
	var got := []
	m.score_changed.connect(func(f: int, e: int) -> void: got.append([f, e]))
	m.start()
	m.add_friendly_kill()
	m.add_friendly_kill()
	m.add_enemy_kill()
	assert_eq(got.size(), 4, "start + 3 次击杀各发一次 score_changed")
	assert_eq(got[1], [1, 0], "我方 +1")
	assert_eq(got[3], [2, 1], "敌方 +1")


func test_score_target_win_friendly() -> void:
	var m = MATCH.new()
	add_child_autofree(m)
	m.setup(3, 999.0)  # 注入低目标
	var winners := []
	m.match_ended.connect(func(w: int) -> void: winners.append(w))
	m.start()
	m.add_friendly_kill()
	m.add_friendly_kill()
	assert_eq(winners.size(), 0, "未到目标不结束")
	m.add_friendly_kill()
	assert_eq(winners, [MATCH.Winner.FRIENDLY], "第 3 杀结束，我方胜")
	assert_eq(m.state, MATCH.State.RESULT, "状态 RESULT")


func test_score_target_win_enemy() -> void:
	var m = MATCH.new()
	add_child_autofree(m)
	m.setup(2, 999.0)
	var winners := []
	m.match_ended.connect(func(w: int) -> void: winners.append(w))
	m.start()
	m.add_enemy_kill()
	m.add_enemy_kill()
	assert_eq(winners, [MATCH.Winner.ENEMY], "敌方先到目标，敌方胜")


func test_time_limit_judge_by_score() -> void:
	var m = MATCH.new()
	add_child_autofree(m)
	m.setup(999, 10.0)
	var winners := []
	m.match_ended.connect(func(w: int) -> void: winners.append(w))
	m.start()
	m.add_friendly_kill()
	m.add_enemy_kill()
	m.add_enemy_kill()  # 1:2 敌方领先
	m._process(10.5)
	assert_eq(winners, [MATCH.Winner.ENEMY], "时间到，击杀多者（敌方）胜")


func test_time_limit_draw() -> void:
	var m = MATCH.new()
	add_child_autofree(m)
	m.setup(999, 10.0)
	var winners := []
	m.match_ended.connect(func(w: int) -> void: winners.append(w))
	m.start()
	m.add_friendly_kill()
	m.add_enemy_kill()  # 1:1
	m._process(10.5)
	assert_eq(winners, [MATCH.Winner.DRAW], "时间到同分 → 平局")


func test_kills_frozen_after_end() -> void:
	var m = MATCH.new()
	add_child_autofree(m)
	m.setup(1, 999.0)
	m.start()
	m.add_friendly_kill()
	assert_eq(m.state, MATCH.State.RESULT)
	m.add_friendly_kill()
	m.add_enemy_kill()
	assert_eq(m.friendly_score, 1, "结束后我方计分冻结")
	assert_eq(m.enemy_score, 0, "结束后敌方计分冻结")


func test_time_changed_signal_seconds() -> void:
	# 不入树：手动推进 _process，避免树帧叠加污染计时
	var m = MATCH.new()
	m.setup(999, 480.0)
	var seconds := []
	m.time_changed.connect(func(s: int) -> void: seconds.append(s))
	m.start()
	m._process(0.4)
	m._process(0.4)
	m._process(0.4)
	assert_eq(seconds.size(), 2, "start 发 480 + 跨整秒发 479，共 2 次")
	assert_eq(seconds[1], 479, "第二次为 479 秒")


func test_reset_clears_all() -> void:
	var m = MATCH.new()
	add_child_autofree(m)
	m.setup(1, 999.0)
	m.start()
	m.add_friendly_kill()  # 结束
	var score_sig := []
	m.score_changed.connect(func(f: int, e: int) -> void: score_sig.append([f, e]))
	m.reset()
	assert_eq(m.state, MATCH.State.PLAYING, "reset 回 PLAYING")
	assert_eq(m.friendly_score, 0, "我方分清零")
	assert_eq(m.enemy_score, 0, "敌方分清零")
	assert_eq(m.elapsed, 0.0, "计时归零")
	assert_eq(score_sig.size(), 1, "reset 重发初始计分信号")
