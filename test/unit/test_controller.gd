# test/unit/test_controller.gd
# 任务 3：MovementController 行为测试（TDD）
# 阶段：GREEN（终版，全绿）。RED 证据：用例 3/4 曾用朴素断言制造"正确失败"——
#   用例 3：加速模型下首帧不可能达到满速（单帧断言 -10.0 实际得 -0.5，已改为收敛断言）
#   用例 4：is_on_floor() 依赖物理场景，无地面时跳跃分支不可达（已改为落地后跳跃）
extends GutTest

var controller: MovementController


func before_each() -> void:
    controller = MovementController.new()
    # 镜像生产场景（MovementController.tscn）的碰撞配置：
    # capsule（默认 radius=0.5, height=1.83 CS）、layer=2(Player)、mask=3(Objects+Player)
    controller.collision_layer = 2
    controller.collision_mask = 3
    controller.floor_snap_length = 0.5
    controller.floor_block_on_wall = false
    var col := CollisionShape3D.new()
    col.shape = CapsuleShape3D.new()
    controller.add_child(col)
    controller.position = Vector3(0, 1.5, 0)  # 胶囊底部距地面（y=0）0.5 单位
    add_child_autofree(controller)


func after_each() -> void:
    Input.action_release("jump")
    Input.action_release("move_forward")
    Input.action_release("move_back")
    Input.action_release("move_left")
    Input.action_release("move_right")


# ── 用例 1：默认速度（纯属性）──
# 2026-08-06 CS 照搬：走速 250u/s = 6.35m/s
func test_initial_speed() -> void:
    assert_eq(controller.speed, 6.35, "默认速度应为 6.35（CS 250u/s）")


# ── 用例 2：默认跳跃高度（纯属性）──
# 2026-08-06 CS 照搬：jump_height 7.54（跳高 1.45m，到顶 0.385s）
func test_jump_height_default() -> void:
    assert_eq(controller.jump_height, 7.54, "默认跳跃高度应为 7.54（CS 跳高 1.45m）")


# ── 用例 3（GREEN 版）：真实物理场景 + 加速模型收敛断言 ──
# RED 证据：单帧朴素断言得 -0.5 ≠ -10（加速模型首帧 lerp 权重仅 0.05）。
# 修正：落地后推进 60 物理帧，断言水平速度收敛到接近 -speed，且位置真实前移。
func test_move_forward_moves_player_forward() -> void:
    _make_floor()
    await wait_physics_frames(25)
    assert_true(controller.is_on_floor(), "前置：控制器应落在地面上")
    Input.action_press("move_forward")
    await wait_physics_frames(60)
    assert_lt(controller.velocity.z, -5.85,
            "60 帧加速收敛后 velocity.z 应接近 -speed（CS 6.35）")
    assert_lt(controller.position.z, -5.08,
            "控制器应真实向前移动（理论位移 ≈ -6.35 单位）")


# ── 用例 4（GREEN 版）：真实物理场景落地后跳 ──
# RED 证据：无地面时 is_on_floor() 恒 false，跳跃分支不可达（velocity.y = -0.49 为重力）。
# 修正：放置地面、await 落地、确认 is_on_floor 后按跳，单物理帧内断言精确冲量。
func test_jump_impulse() -> void:
    _make_floor()
    await wait_physics_frames(25)
    assert_true(controller.is_on_floor(), "前置：控制器应落在地面上")
    Input.action_press("jump")
    await wait_physics_frames(1)
    assert_almost_eq(controller.velocity.y, 7.54, 0.001,
            "落地按跳后 velocity.y 应精确等于 jump_height（跳跃冲量）")


# ── 用例 6：CS 式纯物理跳上 1.22m 掩体（掩体附近起跳窗口）──
# 设计（2026-08-06 CS 照搬）：jump_height=7.54、重力 19.6——升到 1.22m 需 0.231s，
#   水平位移 1.47m——掩体前 1.47m 内起跳都能跳上（CS 式提前量窗口）。
func test_jump_clears_1_22m_cover() -> void:
    _make_floor()
    await wait_physics_frames(25)
    assert_true(controller.is_on_floor(), "前置：控制器应落在地面上")

    # 放置 1.22m 高掩体（Objects 层，Box 1×1.22×1，顶面 y=1.22），玩家前方 z=-3
    var cover := StaticBody3D.new()
    cover.collision_layer = 1
    cover.collision_mask = 0
    var cover_col := CollisionShape3D.new()
    var cover_shape := BoxShape3D.new()
    cover_shape.size = Vector3(1, 1.22, 1)
    cover_col.shape = cover_shape
    cover.add_child(cover_col)
    cover.position = Vector3(0, 0.61, -3)  # 中心 y=0.61 → 顶面 y=1.22
    add_child_autofree(cover)

    # 在掩体顶正上方放置（落点验证：顶部可站）
    controller.global_position = Vector3(0, 2.2, -3.0)
    await wait_physics_frames(40)
    print("ON_COVER_PLAYER_Y=", controller.global_position.y)
    assert_gt(controller.global_position.y, 1.8,
            "玩家从掩体顶上方下落应站在顶部（胶囊底在 1.22 → 中心 ≈2.13）")
    assert_true(controller.is_on_floor(), "站在掩体顶部应 is_on_floor=true")

    # 跳跃可达性：从地面起跳，峰值应超过掩体顶（1.22+0.915=2.13 中心）
    controller.global_position = Vector3(0, 1.0, -2.0)
    await wait_physics_frames(30)
    Input.action_press("jump")
    await wait_physics_frames(15)  # 峰值附近
    Input.action_release("jump")
    print("JUMP_PEAK_Y=", controller.global_position.y)
    assert_gt(controller.global_position.y, 2.13,
            "跳跃峰值应超过掩体顶中心高度（CS 跳高 1.45m）")


# 测试辅助：代码创建物理地面（StaticBody3D + BoxShape3D，Objects 层=1，顶面 y=0）
func _make_floor() -> StaticBody3D:
    var floor_body := StaticBody3D.new()
    floor_body.collision_layer = 1
    floor_body.collision_mask = 0
    var col := CollisionShape3D.new()
    var shape := BoxShape3D.new()
    shape.size = Vector3(40, 1, 40)
    col.shape = shape
    floor_body.add_child(col)
    floor_body.position = Vector3(0, -0.5, 0)
    add_child_autofree(floor_body)
    return floor_body


# ── 用例 5：空中重力（真实物理帧推进）──
func test_gravity_applies_when_airborne() -> void:
    await wait_physics_frames(10)
    var v_early: float = controller.velocity.y
    assert_lt(v_early, 0.0, "空中无输入时重力应使 velocity.y < 0")
    await wait_physics_frames(50)
    assert_lt(controller.velocity.y, v_early,
            "随下落时间增长，velocity.y 应更负（重力持续加速）")


# ══════════════════════════════════════════════════════════════
# F1 自动登台（step-up 0.62m）：真实物理场景测试
# 台阶几何 = 地面 StaticBody + 台阶盒（Objects 层 1）+ 真实控制器实例 + 物理帧推进。
# 胶囊镜像生产 MovementController.tscn（radius 0.5 / height 1.83，CollisionShape3D 本地偏移 0）：
#   脚底 = 中心 - 0.915；站地面（顶面 y=0）→ 中心 0.915；站 0.6 台面 → 中心 1.515。
# 设计：高差 ≤0.62m 视为斜坡直接走上去；0.9m 箱保持只能跳上；空中绝不触发。
# ══════════════════════════════════════════════════════════════

const CAP_HALF := 0.915  # 生产胶囊半高（1.83/2）


# 替换 before_each 的默认胶囊为生产尺寸（radius 0.5 / height 1.83）
func _production_capsule() -> void:
    var cap := CapsuleShape3D.new()
    cap.radius = 0.5
    cap.height = 1.83
    var col := _controller_collision()
    assert_not_null(col, "前置：控制器应有 CollisionShape3D 子节点")
    col.shape = cap


func _controller_collision() -> CollisionShape3D:
    for child in controller.get_children():
        if child is CollisionShape3D:
            return child
    return null


# 台阶盒辅助：BoxShape3D StaticBody（Objects 层 1），center_y 由调用方给定（= top_y - size.y/2）
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


# ── F1-1：平地 + 0.6m 台阶——持续前进（无跳跃）自动登上 ──
func test_step_up_climbs_06() -> void:
    _production_capsule()
    _make_floor()
    # 0.6m 台阶盒：顶面 y=0.6，前表面 z=-2，盒体 z=-2..-14（足够长，不会走出台面）
    _make_box(Vector3(6, 0.6, 12), Vector3(0, 0.3, -8))
    await wait_physics_frames(25)
    assert_true(controller.is_on_floor(), "前置：控制器应落在地面上")

    Input.action_press("move_forward")  # 朝台阶持续前进，无跳跃输入
    await wait_physics_frames(70)
    print("STEP_UP_06_POS=", controller.global_position,
            " on_floor=", controller.is_on_floor())
    assert_almost_eq(controller.global_position.y, 0.6 + CAP_HALF, 0.05,
            "不跳跃自动登上 0.6m 台阶（脚底抬升 0.6±0.05 → 中心 ≈1.515）")
    assert_true(controller.is_on_floor(), "台阶顶上应 is_on_floor")
    assert_lt(controller.global_position.z, -2.0, "应已越过台阶前表面（z=-2）到达顶部")


# ── F1-2：0.3 → 0.6 两级微台阶——连续走上顶 ──
func test_step_up_micro_stairs() -> void:
    _production_capsule()
    _make_floor()
    _make_box(Vector3(6, 0.3, 6), Vector3(0, 0.15, -5))   # 第一级：顶面 0.3，前表面 z=-2
    _make_box(Vector3(6, 0.6, 12), Vector3(0, 0.3, -14))  # 第二级：顶面 0.6，前表面 z=-8
    await wait_physics_frames(25)
    assert_true(controller.is_on_floor(), "前置：控制器应落在地面上")

    Input.action_press("move_forward")
    await wait_physics_frames(90)
    print("MICRO_STAIRS_POS=", controller.global_position,
            " on_floor=", controller.is_on_floor())
    assert_almost_eq(controller.global_position.y, 0.6 + CAP_HALF, 0.05,
            "连续登上 0.3→0.6 两级微台阶（脚底 0.6±0.05）")
    assert_true(controller.is_on_floor(), "第二级顶上应 is_on_floor")
    assert_lt(controller.global_position.z, -8.0, "应已越过第二级前表面（z=-8）")


# ── F1-3：0.9m 箱——高于 STEP_MAX，同样输入上不去（保持只能跳上）──
func test_step_up_blocked_by_09() -> void:
    _production_capsule()
    _make_floor()
    _make_box(Vector3(4, 0.9, 4), Vector3(0, 0.45, -4))  # 0.9m 箱：顶面 0.9，前表面 z=-2
    await wait_physics_frames(25)
    assert_true(controller.is_on_floor(), "前置：控制器应落在地面上")

    Input.action_press("move_forward")
    await wait_physics_frames(60)
    print("BLOCKED_BY_09_POS=", controller.global_position)
    assert_gt(controller.global_position.z, -1.7,
            "应被 0.9m 箱侧面挡住（接触位 z≈-1.5），不能越过箱体")
    assert_almost_eq(controller.global_position.y, CAP_HALF, 0.05,
            "0.9 > STEP_MAX 0.62：仍在箱底地面（不上去）")


# ── F1-4：0.6 台阶上方净空 1.0m（< 玩家高 1.83）——不触发登台，不嵌进顶板 ──
func test_step_up_low_ceiling() -> void:
    _production_capsule()
    _make_floor()
    _make_box(Vector3(6, 0.6, 8), Vector3(0, 0.3, -6))   # 0.6 台阶：顶面 0.6，前表面 z=-2
    _make_box(Vector3(6, 0.2, 8), Vector3(0, 1.7, -6))   # 顶板：底面 y=1.6，恰在台阶上方（净空 1.0）
    await wait_physics_frames(25)
    assert_true(controller.is_on_floor(), "前置：控制器应落在地面上")

    Input.action_press("move_forward")
    await wait_physics_frames(60)
    print("LOW_CEILING_POS=", controller.global_position)
    assert_almost_eq(controller.global_position.y, CAP_HALF, 0.05,
            "净空不足：不触发登台，仍站地面")
    assert_lt(controller.global_position.y - CAP_HALF, 0.6,
            "脚底抬升 < 0.6（未登上台阶、未嵌进顶板）")
    assert_gt(controller.global_position.z, -1.7, "应被台阶侧面挡住")


# ── F1-5：空中经过高台侧面——绝不触发登台（防下落贴墙瞬移上高台）──
# 注：0.6m 矮台阶物理上无法构造空中误登台（脚底<0.6 贴墙必与台阶体重叠、脚底>0.6
# 登台增量≤0 被"只升不降"守卫拦下）；空中窗口存在于高台侧落——下落脚底经过
# (台高-0.62, 台高) 时，无空中守卫的实现会抬升 cast 越台顶、向下命中台面、把空中
# 玩家瞬移上台。故用 2.0m 高台 + 贴墙下坠（velocity 直设，模拟击退/坠落）验证守卫。
func test_no_step_up_airborne() -> void:
    _production_capsule()
    _make_floor()
    _make_box(Vector3(6, 2.0, 12), Vector3(0, 1.0, -8))  # 2.0m 高台：顶面 2.0，前表面 z=-2
    # 贴住高台侧面、脚底 1.585（落在登台窗口 (1.38,2.2) 内）、带水平冲向高台的速度。
    # 不做落地前等待 → 首帧 is_on_floor=false。无空中守卫的实现首帧即会瞬移上台顶。
    controller.global_position = Vector3(0, 2.5, -1.5)
    controller.velocity = Vector3(0, -1.0, -6.0)
    await wait_physics_frames(40)  # 下落 + 贴墙滑落到地面
    print("AIRBORNE_POS=", controller.global_position,
            " on_floor=", controller.is_on_floor())
    assert_true(controller.is_on_floor(), "应落地（高台旁地面）")
    assert_almost_eq(controller.global_position.y, CAP_HALF, 0.1,
            "落地在高台旁地面（y≈0.915），而非空中瞬移上高台（2.915）")
    assert_gt(controller.global_position.z, -1.6, "未越过高台前表面")


# ── F1-6：从 0.6 台面向前走下——自然下落，无异常弹跳，落地恢复 on_floor ──
func test_step_down_smooth() -> void:
    _production_capsule()
    _make_floor()
    _make_box(Vector3(8, 0.6, 8), Vector3(0, 0.3, -6))    # 0.6 平台：顶面 0.6，z=-2..-10
    _make_box(Vector3(8, 2.0, 1), Vector3(0, 1.0, -13.5)) # 背后挡墙（z=-13..-14）：防止走出地图
    controller.global_position = Vector3(0, 2.0, -6)       # 平台顶上方
    await wait_physics_frames(25)
    assert_true(controller.is_on_floor(), "前置：应站在平台顶")
    assert_almost_eq(controller.global_position.y, 0.6 + CAP_HALF, 0.05, "前置：站在平台顶")

    Input.action_press("move_forward")  # 向前走离后缘（z=-10）
    var prev_y: float = controller.global_position.y
    var bounced := false
    var landed := false
    for i in 180:
        await wait_physics_frames(1)
        var y: float = controller.global_position.y
        if y > prev_y + 0.03:
            bounced = true
        prev_y = y
        if controller.is_on_floor() and y < 1.2:  # 已落到地面（平台顶 y=1.515）
            landed = true
            break
    Input.action_release("move_forward")
    print("STEP_DOWN_POS=", controller.global_position,
            " on_floor=", controller.is_on_floor())
    assert_true(landed, "应已走下平台落到地面")
    assert_false(bounced, "走下台阶全程 y 单调下降（无异常弹跳）")
    assert_true(controller.is_on_floor(), "落地后 is_on_floor 恢复")
    assert_almost_eq(controller.global_position.y, CAP_HALF, 0.1, "落地在地面（y≈0.915）")
