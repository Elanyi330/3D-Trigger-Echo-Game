# Levels/M2_TDM/jump_solver.gd
# T3 抛物线物理求解器 JumpSolver（2026-08-13，TDD）。
#
# 物理模型（与 Player/MovementController.gd 常量 + 帧序实测一致，闭合式唯一、禁逐帧模拟）：
#   - 跳帧（仍 on_floor 分支）velocity.y = 7.54 后不减重力直接 move_and_slide（满速位移一帧）；
#     下一帧起每帧 vy −= 19.6·dt 再位移。60Hz 半隐式欧拉。
#   - 离散闭合式：rise(n) = n·V_JUMP·DT − G·DT·DT·n·(n−1)/2（n 帧，n≥1；n≤0 → 0）。
#     峰值 1.5133333 @ n=24；同高飞行全程 47 帧。
#   - 抓边：玩家胶囊底球半径 0.5；脚（身体原点 −0.915）只要 ≥ 目标顶面 − 0.5（CATCH_BAND），
#     底球即能滚上目标边缘。起跳水平速度 ∈ (0, SPEED_CAP]（地面助跑建立）。
#   - 判定：必需速度 v_req = dist/t_max；上跳（t_min>0）过快早到撞立面 → v_hi = dist/t_min
#     （信息性约束，不参与 ok 判定）。
#
# 与任务 brief 手算锚点的偏差（已按闭合式逐项复核，brief 手算误差，非实现误差）：
#   1. rise_at(47)：brief 0.0206 → 公式 0.020889（47·7.54/60 − 19.6/3600·47·46/2）
#   2. rise_at(48)：brief −0.1073 → 公式 −0.109333（48·7.54/60 − 19.6/3600·48·47/2）
#   3. catch_window(0.0).f_max：brief 49 → 公式 50（rise(50)=−0.386≥−0.5；rise(51)=−0.533<−0.5）
#      → 连锁 feasibility(0.0,4.0).v_req：brief 4.8979 → 公式 4.8（240/50）
#   4. required_speed(0.9,2.0).v_hi：brief 8.0 → 公式 30.0；brief 自注「2.0/(4/60)」=30，
#      与 8.0 自相矛盾（8.0 = 2.0/(15/60)，误用了 delta_h=1.8 的 f_min）
#   5. feasibility(1.8,3.2).verdict：brief "knife" → 阈值规则 "tight"（margin=1−6.0/6.35=0.0551
#      ≥ 0.05，brief 与其自定阈值「≥0.05 → tight」矛盾）；feasibility(-1.0,5.0).margin
#      brief 0.156 → 公式 0.15636（brief 为 3 位截断，超出 1e-4 容差，测试取 0.1564）
class_name JumpSolver

const G := 19.6               # 9.8 × gravity_multiplier 2.0（MovementController）
const V_JUMP := 7.54          # MovementController.jump_height
const DT := 1.0 / 60.0        # 物理帧
const SPEED_CAP := 6.35       # MovementController.speed（落地钳制 = 起跳上限）
const CATCH_BAND := 0.5       # 脚可低于顶面 0.5 抓边（底球半径，语料实证）
# 扫描上限防御：120 帧 = 2s > 全程 47 帧同高飞行，超限即不满足
const MAX_FRAMES := 120


## 闭合式位移：rise(n) = n·V_JUMP·DT − G·DT·DT·n·(n−1)/2（n≥1；n≤0 → 0）
static func rise_at(frame: int) -> float:
    if frame <= 0:
        return 0.0
    return frame * V_JUMP * DT - G * DT * DT * frame * (frame - 1) / 2.0


## 峰值 1.5133333 @ n=24
static func peak_rise() -> float:
    # 推导：rise(n) 顶点 n* = V_JUMP/(G·DT) + 0.5 = 7.54/(19.6/60) + 0.5 = 23.58
    #   → 相邻整数 n=24 处最大；rise(24) = 24·7.54/60 − 19.6/3600·276 = 3.016 − 1.502667
    #   = 1.5133333（与写死常量一致；测试 test_rise_anchor 已锚定 rise_at(24) 与峰值两者）
    return rise_at(24)


## 抓边帧窗口：满足 rise(n) ≥ delta_h − CATCH_BAND 的帧区间 [f_min, f_max]。
## f_min 首个满足帧；f_max 最后一个满足帧；delta_h − CATCH_BAND ≤ 0 时 f_min=0。
## 遍历 n=0..120；无解（区间空）→ ok=false 且 f/t 均为 0。t = f/60。
static func catch_window(delta_h: float) -> Dictionary:
    var threshold := delta_h - CATCH_BAND
    var f_min := -1
    var f_max := -1
    for n in range(0, MAX_FRAMES + 1):
        if rise_at(n) >= threshold:
            if f_min == -1:
                f_min = n
            f_max = n
    if f_max == -1:
        return {"ok": false, "f_min": 0, "f_max": 0, "t_min": 0.0, "t_max": 0.0}
    return {"ok": true, "f_min": f_min, "f_max": f_max,
            "t_min": f_min * DT, "t_max": f_max * DT}


## 必需速度：v_req = dist/t_max（dist≤0 → 0）；t_min>0 且 dist>0 → v_hi = dist/t_min，否则 INF。
## ok = 窗口 ok（窗口无解时 v_req 取 0，避免除零）。
static func required_speed(delta_h: float, dist: float) -> Dictionary:
    var w := catch_window(delta_h)
    var v_req := 0.0
    var v_hi := INF
    if w.ok and dist > 0.0:
        v_req = dist / w.t_max
        if w.t_min > 0.0:
            v_hi = dist / w.t_min
    return {"ok": w.ok, "v_req": v_req, "v_hi": v_hi}


## 可行性判定：ok = 窗口 ok 且 v_req ≤ cap；margin = 1 − v_req/cap（dist≤0 → 1.0）；
## verdict：!ok → "infeasible"；margin ≥ 0.2 → "easy"；≥ 0.05 → "tight"；其余 → "knife"。
static func feasibility(delta_h: float, dist: float, cap: float = SPEED_CAP) -> Dictionary:
    var r := required_speed(delta_h, dist)
    var ok: bool = r.ok and r.v_req <= cap
    var margin := 1.0
    if dist > 0.0:
        margin = 1.0 - r.v_req / cap
    var verdict := "infeasible"
    if ok:
        if margin >= 0.2:
            verdict = "easy"
        elif margin >= 0.05:
            verdict = "tight"
        else:
            verdict = "knife"
    return {"ok": ok, "verdict": verdict, "v_req": r.v_req, "margin": margin}


## 网格采样可达覆盖：r = cap·t_max（可达半径）；对 to_rect 内以 step 为步长的网格点 q
## （i ∈ 0..ceil(size/step)，pos + i·step 超出 rect 的点跳过），若 q 到 takeoff_rect 的
## 最近水平距离 ≤ r 则计入 covered。area = 计数·step²；coverage = covered/sampled
## （sampled=0 → 0）；ok = 窗口 ok（窗口无解 → 全 0）。纯网格无随机，确定性。
static func landable_zone(takeoff_rect: Rect2, delta_h: float, to_rect: Rect2,
        cap: float = SPEED_CAP, step: float = 0.25) -> Dictionary:
    var w := catch_window(delta_h)
    if not w.ok:
        return {"ok": false, "t_min": 0.0, "t_max": 0.0, "reach_radius": 0.0,
                "to_area": 0.0, "reach_area": 0.0, "coverage": 0.0,
                "sampled_points": 0, "covered_points": 0}
    var reach_radius: float = cap * w.t_max
    var sampled := 0
    var covered := 0
    var nx := int(ceil(to_rect.size.x / step)) + 1
    var ny := int(ceil(to_rect.size.y / step)) + 1
    for i in range(nx):
        for j in range(ny):
            var q := Vector2(to_rect.position.x + i * step,
                    to_rect.position.y + j * step)
            if not to_rect.has_point(q):
                continue
            sampled += 1
            if _nearest_horiz_dist(q, takeoff_rect) <= reach_radius:
                covered += 1
    var coverage := 0.0
    if sampled > 0:
        coverage = float(covered) / float(sampled)
    return {"ok": true, "t_min": w.t_min, "t_max": w.t_max,
            "reach_radius": reach_radius,
            "to_area": sampled * step * step,
            "reach_area": covered * step * step,
            "coverage": coverage,
            "sampled_points": sampled, "covered_points": covered}


## q 到 rect 的最近水平（xz 平面）距离：先钳制到 rect，再取欧氏距离
static func _nearest_horiz_dist(q: Vector2, rect: Rect2) -> float:
    var dx := maxf(rect.position.x - q.x, maxf(q.x - (rect.position.x + rect.size.x), 0.0))
    var dy := maxf(rect.position.y - q.y, maxf(q.y - (rect.position.y + rect.size.y), 0.0))
    return sqrt(dx * dx + dy * dy)
