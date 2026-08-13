# test/unit/test_jump_solver.gd
# T3 JumpSolver 抛物线物理求解器锚点测试（2026-08-13，TDD）。
# 全部锚点由闭合式 rise(n) = n·V_JUMP·DT − G·DT·DT·n·(n−1)/2 推导（n≥1；n≤0 → 0），
# V_JUMP=7.54，G=19.6（9.8 × 重力倍率 2.0），DT=1/60，SPEED_CAP=6.35，CATCH_BAND=0.5。
# 与任务 brief 手算锚点的偏差（已按公式复核，brief 手算误差；详见实现文件头部）：
#   1. rise_at(47)：brief 0.0206 → 公式 0.020889（差 2.9e-4 > 容差 1e-4）
#   2. rise_at(48)：brief −0.1073 → 公式 −0.109333
#   3. catch_window(0.0).f_max：brief 49 → 公式 50（rise(50)=−0.386≥−0.5；rise(51)=−0.533<−0.5）
#      → 连锁 feasibility(0.0,4.0).v_req：brief 4.8979 → 公式 4.8
#   4. required_speed(0.9,2.0).v_hi：brief 8.0 → 公式 30.0（brief 自注 2.0/(4/60)=30 与其 8.0 自相矛盾）
#   5. feasibility(1.8,3.2).verdict：brief "knife" → 按阈值规则 "tight"（margin 0.0551 ≥ 0.05，
#      brief 与其自定阈值「≥0.05 → tight」矛盾）；feasibility(-1.0,5.0).margin 0.156→0.1564（截断误差）
extends GutTest

const TOL := 0.0001


func test_rise_anchor() -> void:
    assert_almost_eq(JumpSolver.rise_at(0), 0.0, TOL)
    assert_almost_eq(JumpSolver.rise_at(24), 1.5133, TOL)
    # 闭合式：47·7.54/60 − 19.6/3600·47·46/2 = 0.0208889（brief 手算 0.0206 有误）
    assert_almost_eq(JumpSolver.rise_at(47), 0.0209, TOL)
    # 闭合式：48·7.54/60 − 19.6/3600·48·47/2 = −0.1093333（brief 手算 −0.1073 有误）
    assert_almost_eq(JumpSolver.rise_at(48), -0.1093, TOL)
    assert_almost_eq(JumpSolver.peak_rise(), 1.5133333, TOL)


func test_catch_window_anchors() -> void:
    var w := JumpSolver.catch_window(0.9)
    assert_eq(w.ok, true)
    assert_eq(w.f_min, 4)
    assert_eq(w.f_max, 43)
    assert_almost_eq(w.t_min, 4.0 / 60.0, TOL)
    assert_almost_eq(w.t_max, 43.0 / 60.0, TOL)

    w = JumpSolver.catch_window(1.8)
    assert_eq(w.ok, true)
    assert_eq(w.f_min, 15)
    assert_eq(w.f_max, 32)

    w = JumpSolver.catch_window(0.0)
    assert_eq(w.ok, true)
    assert_eq(w.f_min, 0)
    # 公式 f_max=50：rise(50)=−0.3861≥−0.5 仍满足；rise(51)=−0.5327<−0.5（brief 手算 49 有误）
    assert_eq(w.f_max, 50)

    w = JumpSolver.catch_window(2.5)
    assert_eq(w.ok, false)
    assert_eq(w.f_min, 0)
    assert_eq(w.f_max, 0)
    assert_almost_eq(w.t_min, 0.0, TOL)
    assert_almost_eq(w.t_max, 0.0, TOL)

    w = JumpSolver.catch_window(-1.0)
    assert_eq(w.ok, true)
    assert_eq(w.f_min, 0)
    assert_eq(w.f_max, 56)


func test_required_speed_anchors() -> void:
    var r := JumpSolver.required_speed(0.9, 0.0)
    assert_eq(r.ok, true)
    assert_almost_eq(r.v_req, 0.0, TOL)
    assert_true(is_inf(r.v_hi))

    r = JumpSolver.required_speed(0.9, 2.0)
    assert_eq(r.ok, true)
    # v_req = 2.0/(43/60) = 120/43 = 2.7907
    assert_almost_eq(r.v_req, 2.7907, TOL)
    # v_hi = dist/t_min = 2.0/(4/60) = 30.0（brief 8.0 与其自注公式自相矛盾，按公式取 30）
    assert_almost_eq(r.v_hi, 30.0, TOL)

    r = JumpSolver.required_speed(1.9, 1.58)
    assert_eq(r.ok, true)
    # 窗口 [18,30]：v_req = 1.58/(30/60) = 3.16；v_hi = 1.58/(18/60) = 5.2667
    assert_almost_eq(r.v_req, 3.16, TOL)
    assert_almost_eq(r.v_hi, 5.2667, TOL)


func test_feasibility_anchors() -> void:
    var f := JumpSolver.feasibility(1.8, 2.62)
    assert_eq(f.ok, true)
    assert_eq(f.verdict, "easy")
    # v_req = 2.62/(32/60) = 4.9125；margin = 1 − 4.9125/6.35 = 0.2264
    assert_almost_eq(f.v_req, 4.9125, TOL)
    assert_almost_eq(f.margin, 0.2264, TOL)

    f = JumpSolver.feasibility(1.9, 1.58)
    assert_eq(f.ok, true)
    assert_eq(f.verdict, "easy")
    assert_almost_eq(f.v_req, 3.16, TOL)

    f = JumpSolver.feasibility(1.9, 6.5)
    assert_eq(f.ok, false)
    assert_eq(f.verdict, "infeasible")
    # v_req = 6.5/(30/60) = 13.0 > cap 6.35
    assert_almost_eq(f.v_req, 13.0, TOL)

    f = JumpSolver.feasibility(0.0, 4.0)
    assert_eq(f.ok, true)
    assert_eq(f.verdict, "easy")
    # f_max=50 → v_req = 4.0/(50/60) = 4.8（brief 4.8979=240/49 系 f_max=49 手算误差连锁）
    assert_almost_eq(f.v_req, 4.8, TOL)

    f = JumpSolver.feasibility(-1.0, 5.0)
    assert_eq(f.ok, true)
    assert_eq(f.verdict, "tight")
    # v_req = 5.0/(56/60) = 5.3571；margin = 1 − 5.3571/6.35 = 0.15636（brief 0.156 为截断，差 3.6e-4 > 容差）
    assert_almost_eq(f.v_req, 5.3571, TOL)
    assert_almost_eq(f.margin, 0.1564, TOL)

    f = JumpSolver.feasibility(1.8, 3.2)
    assert_eq(f.ok, true)
    # margin = 1 − 6.0/6.35 = 0.0551 ≥ 0.05 → 按阈值规则为 "tight"
    #（brief 标 "knife" 与其自定阈值「≥0.05 → tight」矛盾，按可执行规则取 tight）
    assert_eq(f.verdict, "tight")
    # v_req = 3.2/(32/60) = 6.0
    assert_almost_eq(f.v_req, 6.0, TOL)
    assert_almost_eq(f.margin, 0.0551, TOL)

    f = JumpSolver.feasibility(0.9, 0.0)
    assert_eq(f.ok, true)
    assert_eq(f.verdict, "easy")
    assert_almost_eq(f.v_req, 0.0, TOL)
    assert_almost_eq(f.margin, 1.0, TOL)


func test_determinism() -> void:
    var a := JumpSolver.feasibility(1.8, 2.62)
    var b := JumpSolver.feasibility(1.8, 2.62)
    for key in a:
        assert_eq(a[key], b[key])
    var c := JumpSolver.landable_zone(Rect2(0, 0, 1, 1), 0.0, Rect2(3, 0, 4, 4))
    var d := JumpSolver.landable_zone(Rect2(0, 0, 1, 1), 0.0, Rect2(3, 0, 4, 4))
    for key in c:
        assert_eq(c[key], d[key])


func test_landable_zone_anchors() -> void:
    # 窗口 ok（f_max=50 → r=6.35·50/60=5.2917）：近角 (3,0) 距 2 ≤ r 覆盖，远角 (7,4) 距 6.71 > r
    var z := JumpSolver.landable_zone(Rect2(0, 0, 1, 1), 0.0, Rect2(3, 0, 4, 4))
    assert_eq(z.ok, true)
    assert_gt(z.coverage, 0.0)
    assert_lt(z.coverage, 1.0)

    # 最近距 9.9 > r → 全覆盖不到
    z = JumpSolver.landable_zone(Rect2(0, 0, 1, 1), 0.0, Rect2(8, 8, 4, 4))
    assert_eq(z.ok, true)
    assert_almost_eq(z.coverage, 0.0, TOL)

    # 窗口 [5,42] → r = 6.35·42/60 = 4.445：原点角覆盖，远角 (6,6) 距 7.07 > r
    z = JumpSolver.landable_zone(Rect2(0, 0, 1, 1), 1.0, Rect2(0, 0, 6, 6))
    assert_eq(z.ok, true)
    assert_gt(z.coverage, 0.0)
    assert_lt(z.coverage, 1.0)

    # 2.5−0.5=2.0 > 峰值 1.5133 → 窗口无解
    z = JumpSolver.landable_zone(Rect2(0, 0, 1, 1), 2.5, Rect2(0, 0, 2, 2))
    assert_eq(z.ok, false)
    assert_almost_eq(z.coverage, 0.0, TOL)
