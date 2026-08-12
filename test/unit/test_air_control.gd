# test/unit/test_air_control.gd
# F2 空中控制（TDD）：Source PM_AirAccelerate 投影式加速 + 起跳定档 + 落地钳制。
# 用户需求："无初速度起跳时空中可用方向键移动；有初速度起跳时跳跃不增加速度"。
# 机制（调研定稿）：
#   - 投影公式（所有空中帧）：proj = 水平速度·wishdir；addspeed = wish_cap − proj；
#     addspeed>0 时 速度 += wishdir × min(AIR_ACCELERATE × wish_cap × dt, addspeed)
#   - 起跳定档：水平速度 < 0.5 → REST 档 cap 3.0（原地跳可空中转向）；
#     否则 RUN 档 cap 0.76（=CS sv_airaccelerate 12 / wish 帽 30u，天然零加速）
#   - 落地钳制：非接地→接地帧水平速度 > speed(6.35) → 钳回 speed（防 bhop 叠速）
# 全部用例为真实物理场景：地面 StaticBody + MovementController.tscn 实例 + 物理帧推进。
# 胶囊来自生产 tscn（radius 0.5 / height 1.83）：站地面（顶面 y=0）→ 中心 cap_half。
# 输入时序注记（实测）：本环境手动 action_press 的 just_pressed 比 pressed 状态晚约
# 1 物理步生效——"跳+方向同时按"会先产生 1 帧地面加速再起跳（起跳速度 ≈1.06）。
# 故静止跳用例先按跳、确认冲量离地后再按方向，复现真实"起跳瞬间速度 0"的定档语义。
extends GutTest

var controller: MovementController
# 生产胶囊半高——从 tscn 实例读取（不硬编码字面量），1.83/2 = 0.915
var cap_half := 0.915


func before_each() -> void:
    controller = load("res://Player/MovementController.tscn").instantiate()
    controller.position = Vector3(0, 1.5, 0)
    add_child_autofree(controller)
    var col := controller.get_node("Collision") as CollisionShape3D
    cap_half = (col.shape as CapsuleShape3D).height * 0.5


func after_each() -> void:
    Input.action_release("jump")
    Input.action_release("move_forward")
    Input.action_release("move_back")
    Input.action_release("move_left")
    Input.action_release("move_right")


## 按跳并等待冲量生效（just_pressed 滞后 ~1 步，最多等 10 步），断言已离地上升
func _press_jump_until_airborne() -> void:
    Input.action_press("jump")
    for i in 10:
        await wait_physics_frames(1)
        if controller.velocity.y > 0.0 and not controller.is_on_floor():
            return
    # 兜底：冲量帧 vy 精确 7.54 已过也可能仍在上升段，交由调用方断言现状
    assert_gt(controller.velocity.y, 0.0, "前置：跳跃冲量应已生效（离地上升）")


# ── 用例 1：静止起跳空中转向——水平速度从 0 增长，落点前移 ──
# REST 档（起跳水平速度 < 0.5 → wish_cap=3.0）：离地后持续前输入 → 空中获得前向速度。
func test_rest_jump_steers() -> void:
    _make_floor()
    await wait_physics_frames(25)
    assert_true(controller.is_on_floor(), "前置：控制器应站在地面")
    assert_lt(_h_speed(), 0.1, "前置：静止（水平速度 ≈ 0）")

    var takeoff_z: float = controller.global_position.z
    await _press_jump_until_airborne()
    Input.action_press("move_forward")
    var max_h := 0.0
    var landed := false
    for i in 160:
        await wait_physics_frames(1)
        if not controller.is_on_floor():
            max_h = maxf(max_h, _h_speed())
        else:
            landed = true
            break
    Input.action_release("jump")
    Input.action_release("move_forward")
    print("REST_STEER max_h=", snappedf(max_h, 0.001),
            " forward_dz=", snappedf(takeoff_z - controller.global_position.z, 0.001))
    assert_true(landed, "160 帧内应落地")
    assert_gt(max_h, 1.0, "静止起跳：滞空期间水平速度应从 0 增长（空中转向，某帧 > 1.0）")
    assert_gt(takeoff_z - controller.global_position.z, 0.8,
            "落点比起跳点前移 > 0.8m（REST 档空中转向位移）")


# ── 用例 2（用户核心场景）：静止贴 0.9m 箱起跳 → 落在箱顶 ──
# 贴面站位（胶囊半径 0.5，箱前表面 z=-0.5），起跳 + 朝箱输入 → 空中转向越过箱棱
# 落在箱顶（脚底 0.9±0.1）。无空中控制时纯垂直跳只会撞墙落回原地。
func test_rest_jump_climbs_adjacent_box() -> void:
    _make_floor()
    # 0.9m 箱（V3 蹲藏档高度）：前表面 z=-0.5，与玩家胶囊表面贴面
    _make_box(Vector3(4, 0.9, 4), Vector3(0, 0.45, -2.5))
    await wait_physics_frames(25)
    assert_true(controller.is_on_floor(), "前置：控制器应站在箱旁地面")

    await _press_jump_until_airborne()
    Input.action_press("move_forward")
    var airborne_steps := 0
    for i in 200:
        await wait_physics_frames(1)
        if not controller.is_on_floor():
            airborne_steps += 1
        elif airborne_steps > 0:
            break
    Input.action_release("jump")
    Input.action_release("move_forward")
    var feet_y: float = controller.global_position.y - cap_half
    print("CLIMB_BOX feet_y=", snappedf(feet_y, 0.001),
            " pos=", controller.global_position,
            " on_floor=", controller.is_on_floor())
    assert_gt(airborne_steps, 0, "应曾离地起跳")
    assert_almost_eq(feet_y, 0.9, 0.1, "应落在箱顶（脚底 0.9±0.1）")
    assert_true(controller.is_on_floor(), "箱顶应 is_on_floor")


# ── 用例 3：跑动起跳零加速（CS 手感）——全程水平速度 ≤ 6.36 ──
# RUN 档（起跳水平速度 ≥ 0.5 → wish_cap=0.76）：proj=6.35 ≫ cap → addspeed<0 → 零加速。
func test_run_jump_no_accel() -> void:
    _make_floor()
    await wait_physics_frames(25)
    assert_true(controller.is_on_floor(), "前置：控制器应站在地面")

    Input.action_press("move_forward")
    await wait_physics_frames(90)  # 地面加速收敛到 ~6.35
    var run_speed := _h_speed()
    assert_gt(run_speed, 6.3, "前置：跑动接近满速")

    Input.action_press("jump")
    var max_h := run_speed
    var airborne := false
    var landed := false
    for i in 160:
        await wait_physics_frames(1)
        if not controller.is_on_floor():
            airborne = true
            max_h = maxf(max_h, _h_speed())
        elif airborne:
            landed = true
            break
    Input.action_release("jump")
    Input.action_release("move_forward")
    print("RUN_JUMP run_speed=", snappedf(run_speed, 0.001),
            " max_h=", snappedf(max_h, 0.001))
    assert_true(landed, "160 帧内应落地")
    assert_lte(max_h, 6.36, "跑动起跳：滞空全程水平速度 ≤ 6.36（跳跃不增加速度）")


# ── 用例 4：跑动起跳纯侧向输入——≤cap 微调（Source air-strafe 特性保留）──
# 侧向 wishdir 与前进速度正交 → proj=0 < cap 0.76 → 获得侧向分量；
# 合速 sqrt(6.35²+0.76²) ≈ 6.395 ≤ 6.41。
func test_run_jump_lateral_micro() -> void:
    _make_floor()
    await wait_physics_frames(25)
    Input.action_press("move_forward")
    await wait_physics_frames(90)
    assert_gt(_h_speed(), 6.3, "前置：跑动接近满速")

    Input.action_press("jump")
    await wait_physics_frames(1)  # 起跳帧：RUN 档定档（h≈6.35 ≥ 0.5）
    Input.action_release("move_forward")
    Input.action_press("move_right")  # 纯侧向输入
    var max_h := 0.0
    var max_lateral := 0.0
    var airborne := false
    for i in 160:
        await wait_physics_frames(1)
        if not controller.is_on_floor():
            airborne = true
            max_h = maxf(max_h, _h_speed())
            max_lateral = maxf(max_lateral, absf(controller.velocity.x))
        elif airborne:
            break
    Input.action_release("jump")
    Input.action_release("move_right")
    print("LATERAL_MICRO max_h=", snappedf(max_h, 0.001),
            " max_lateral=", snappedf(max_lateral, 0.001))
    assert_true(airborne, "应曾离地起跳")
    assert_gt(max_lateral, 0.3, "纯侧向输入应获得侧向分量 > 0.3（≤cap 微调）")
    assert_lte(max_h, 6.41, "合速 ≤ 6.41（侧向微调不增速）")


# ── 用例 5：无 bhop 叠速链——连续 3 跳速度 ≤ 6.4 ──
# 静止起跳（REST 档）+ 前输入 → 落地立即再跳：第 2 跳起跳速度 ≥ 0.5 → 自动回落
# RUN 档，投影公式 proj≫cap 不再加速；落地钳制兜底。连续 3 跳后无叠速。
func test_no_bhop_chain() -> void:
    _make_floor()
    await wait_physics_frames(25)
    assert_true(controller.is_on_floor(), "前置：控制器应站在地面")

    await _press_jump_until_airborne()
    Input.action_press("move_forward")
    var max_h := 0.0
    var jumps := 0
    var airborne := false
    for i in 600:
        await wait_physics_frames(1)
        max_h = maxf(max_h, _h_speed())
        if not controller.is_on_floor():
            airborne = true
        elif airborne:
            airborne = false
            jumps += 1
            if jumps >= 3:
                break
            # 落地立即再跳：release+press → just_pressed 在地面帧触发跳跃分支
            # （输入滞后期间地面加速继续，起跳速度 ≥0.5 → RUN 档，符合机制设计）
            Input.action_release("jump")
            await wait_physics_frames(1)
            Input.action_press("jump")
    Input.action_release("jump")
    Input.action_release("move_forward")
    print("BHOP_CHAIN jumps=", jumps, " max_h=", snappedf(max_h, 0.001))
    assert_eq(jumps, 3, "应完成连续 3 跳")
    assert_lte(max_h, 6.4, "连续 3 跳全程水平速度 ≤ 6.4（无叠速链）")


# ── 用例 6：落地钳制——水平速度 8.0 落地 → 钳回 6.35±0.01 ──
func test_landing_clamp() -> void:
    _make_floor()
    # 人为设置高空水平速度 8.0（> 基础 speed 6.35），无输入直落地面
    controller.global_position = Vector3(0, 3.0, 0)
    controller.velocity = Vector3(0, 0, -8.0)
    var sampler := _LandVelSampler.new()
    sampler.target = controller
    add_child(sampler)
    await wait_physics_frames(80)
    print("LAND_CLAMP land_speed=", snappedf(sampler.land_speed, 0.001))
    assert_true(sampler.landed, "80 帧内应落地")
    assert_almost_eq(sampler.land_speed, 6.35, 0.01,
            "落地瞬间水平速度 > 6.35 → 钳回 6.35（防 bhop）")
    remove_child(sampler)
    sampler.free()


# ── 用例 7：垂直跳高零回归（实测口径 1.51±0.05）──
# 口径说明：生产 _physics_process 起跳帧走地面分支不扣重力，离散积分实测最大
# 升空 1.5136m（probe_jump.gd 的 1.39 为起跳帧也扣重力的理想化积分序，非生产
# 实测值）。空中控制不得改变跳高：无方向输入 → wishdir 为零，垂直行为不变。
func test_jump_height_unchanged() -> void:
    _make_floor()
    await wait_physics_frames(25)
    assert_true(controller.is_on_floor(), "前置：控制器应站在地面")
    var stand_y: float = controller.global_position.y

    Input.action_press("jump")
    var peak_y: float = stand_y
    var airborne := false
    for i in 160:
        await wait_physics_frames(1)
        peak_y = maxf(peak_y, controller.global_position.y)
        if not controller.is_on_floor():
            airborne = true
        elif airborne:
            break
    Input.action_release("jump")
    var rise: float = peak_y - stand_y
    print("JUMP_HEIGHT rise=", snappedf(rise, 0.001))
    assert_true(airborne, "应离地起跳")
    assert_almost_eq(rise, 1.51, 0.05,
            "垂直跳最大高度 ≈1.51±0.05（生产实测口径，空中控制不得改变跳高）")


# ── 逐物理步落地速度采样器（用例 6）──
# await 级采样无法对准落地帧（落地后地面 deceleration 每帧衰减 ~1.06）；
# 树序在控制器之后 → 读到落地当帧 move_and_slide+钳制后的精确速度。
class _LandVelSampler extends Node:
    var target: MovementController
    var landed := false
    var land_speed := -1.0

    func _physics_process(_d: float) -> void:
        if not landed and target.is_on_floor():
            landed = true
            land_speed = Vector2(target.velocity.x, target.velocity.z).length()


# ── 工具 ──

func _h_speed() -> float:
    return Vector2(controller.velocity.x, controller.velocity.z).length()


# 测试辅助：盒构造器——BoxShape3D StaticBody（Objects 层 1，与 test_controller.gd 同款）
func _make_box(size: Vector3, center: Vector3) -> StaticBody3D:
    var body := StaticBody3D.new()
    body.collision_layer = 1
    body.collision_mask = 0
    var col := CollisionShape3D.new()
    var shape := BoxShape3D.new()
    shape.size = size
    col.shape = shape
    body.add_child(col)
    body.position = center
    add_child_autofree(body)
    return body


# 测试辅助：物理地面（40×1×40，顶面 y=0）
func _make_floor() -> StaticBody3D:
    return _make_box(Vector3(40, 1, 40), Vector3(0, -0.5, 0))
