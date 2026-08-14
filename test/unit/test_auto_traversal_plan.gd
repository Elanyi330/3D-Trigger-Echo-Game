# test/unit/test_auto_traversal_plan.gd
# T2 AutoTraversal 规划器/跳跃引擎纯逻辑测试（2026-08-14，TDD）。
# 覆盖 classify_segments / pick_jump_speed / trigger_distance / landing_verdict 四个 static 函数。
# 锚点值先由 JumpSolver 实跑确认（godot --headless 实测）：
#   - pick_jump_speed(0.8, 4.235, 5.0)：v_req = 4.235/(44/60) = 5.775（brief 手算 5.77，
#     差 5e-3 > 1e-3，按 brief 规则以实跑 5.775 为准）；human 5.0 低于带下界被钳上。
#   - 其余锚点与 brief 表一致：6.35 / 5.2667 / 3.5 / trigger_distance 两值。

extends GutTest

const AT := preload("res://Levels/M2_TDM/auto_traversal.gd")
const LAYOUT := preload("res://Levels/M2_TDM/map_layout_v3.gd")

const TOL := 0.0001


# ---- 1. 纯直线 path（6 个点沿 z）→ 5 段全 walk（links 为空，纯走分支 + 段数）----
func test_classify_all_walk() -> void:
	var path := PackedVector3Array([
		Vector3(0, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, 2),
		Vector3(0, 0, 3), Vector3(0, 0, 4), Vector3(0, 0, 5),
	])
	var segs: Array = AT.classify_segments(path, [])
	assert_eq(segs.size(), 5)
	for s0 in segs:
		var s: Dictionary = s0
		assert_eq(s["kind"], "walk")


# ---- 2. 合成链接：from (0,1,0) to (0,1,5)，path 4 点 → walk/jump/walk，jump 段 link 名对 ----
func test_classify_synthetic_jump() -> void:
	var links := [{"name": "Synth", "from": Vector3(0, 1, 0), "to": Vector3(0, 1, 5)}]
	var path := PackedVector3Array([
		Vector3(0, 1, -2), Vector3(0, 1, 0), Vector3(0, 1, 5), Vector3(0, 1, 8),
	])
	var segs: Array = AT.classify_segments(path, links)
	assert_eq(segs.size(), 3)
	assert_eq(segs[0]["kind"], "walk")
	assert_eq(segs[1]["kind"], "jump")
	assert_eq(segs[1]["link"]["name"], "Synth")
	assert_eq(segs[1]["start"], Vector3(0, 1, 0))
	assert_eq(segs[1]["end"], Vector3(0, 1, 5))
	assert_eq(segs[2]["kind"], "walk")


# ---- 3. 真实 54 链接：西摊阁面心 → PavToSpur_W 两端点 → 西横脊墙心，中间段识别为 jump ----
func test_classify_real_link_anchor() -> void:
	var path := PackedVector3Array([
		Vector3(-18.5, 1.2, -10), Vector3(-17.9, 1.2, -9.4),
		Vector3(-16.2, 3.0, -7.4), Vector3(-16.0, 3.0, -7.1),
	])
	var segs: Array = AT.classify_segments(path, LAYOUT.jump_links())
	assert_eq(segs.size(), 3)
	assert_eq(segs[0]["kind"], "walk")
	assert_eq(segs[1]["kind"], "jump")
	assert_eq(segs[1]["link"]["name"], "PavToSpur_W")
	assert_eq(segs[2]["kind"], "walk")


# ---- 4. 起跳参数选择锚点（实跑值见文件头注释）+ 确定性 ----
func test_pick_jump_speed_anchors() -> void:
	# ClusterToRim_WS 修复边：窗口 [3,44]，v_req=4.235/(44/60)=5.775，
	# human 5.0 低于带下界被钳上 → v=5.775、corpus、clamped
	var r := AT.pick_jump_speed(0.8, 4.235, 5.0)
	assert_almost_eq(r["v"], 5.775, TOL)
	assert_eq(r["source"], "corpus")
	assert_eq(r["clamped"], true)

	# 无人类数据：目标 = min(5.775*1.15, 6.35) = 6.35，带内不钳
	r = AT.pick_jump_speed(0.8, 4.235, 0.0)
	assert_almost_eq(r["v"], 6.35, TOL)
	assert_eq(r["source"], "solver")
	assert_eq(r["clamped"], false)

	# 翼墙→门梁人类：窗口 [18,30]，v_hi=1.58/(18/60)=5.2667 钳制（过快早到）
	r = AT.pick_jump_speed(1.9, 1.58, 5.45)
	assert_almost_eq(r["v"], 5.2666667, TOL)
	assert_eq(r["source"], "corpus")
	assert_eq(r["clamped"], true)

	# 带内不钳
	r = AT.pick_jump_speed(1.9, 1.58, 3.5)
	assert_almost_eq(r["v"], 3.5, TOL)
	assert_eq(r["source"], "corpus")
	assert_eq(r["clamped"], false)

	# 确定性：同参数两次全等（assert_eq 整字典）
	var a := AT.pick_jump_speed(0.8, 4.235, 5.0)
	var b := AT.pick_jump_speed(0.8, 4.235, 5.0)
	assert_eq(a, b)


# ---- 5. 起跳触发距离：v*DT + 0.05（DT=1/60）----
func test_trigger_distance() -> void:
	assert_almost_eq(AT.trigger_distance(6.35), 6.35 / 60.0 + 0.05, TOL)
	assert_almost_eq(AT.trigger_distance(0.0), 0.05, TOL)


# ---- 6. 着陆判定状态（zone Rect2(0,0,2,2)、top_y=3.0、to_face=WestSpurS）----
func test_landing_verdict_states() -> void:
	var zone := Rect2(0, 0, 2, 2)
	# 面名命中优先
	assert_eq(AT.landing_verdict(true, "WestSpurS", Vector3(0.5, 3.915, 0.5),
		"WestSpurS", zone, 3.0)["verdict"], "success")
	# 矩形内 + 脚高 3.0 == top
	assert_eq(AT.landing_verdict(true, "Ground", Vector3(0.5, 3.915, 0.5),
		"WestSpurS", zone, 3.0)["verdict"], "success")
	# 面不对且矩形外
	assert_eq(AT.landing_verdict(true, "Ground", Vector3(5, 3.915, 5),
		"WestSpurS", zone, 3.0)["verdict"], "wrong_face")
	# 未落地
	assert_eq(AT.landing_verdict(false, "Ground", Vector3(0.5, 3.915, 0.5),
		"WestSpurS", zone, 3.0)["verdict"], "pending")
	# 脚 −0.115 < top−2
	assert_eq(AT.landing_verdict(true, "Ground", Vector3(0.5, 0.8, 0.5),
		"WestSpurS", zone, 3.0)["verdict"], "fell")


# ---- 7. 确定性：classify_segments 同输入两次全等 ----
func test_determinism() -> void:
	var path := PackedVector3Array([
		Vector3(-18.5, 1.2, -10), Vector3(-17.9, 1.2, -9.4),
		Vector3(-16.2, 3.0, -7.4), Vector3(-16.0, 3.0, -7.1),
	])
	var a: Array = AT.classify_segments(path, LAYOUT.jump_links())
	var b: Array = AT.classify_segments(path, LAYOUT.jump_links())
	assert_eq(a, b)
