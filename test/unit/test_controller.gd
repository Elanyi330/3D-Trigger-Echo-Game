# test/unit/test_controller.gd
# 任务 3：MovementController 行为测试（TDD）
# 阶段：GREEN（终版，全绿）。RED 证据：用例 3/4 曾用朴素断言制造"正确失败"——
#   用例 3：加速模型下首帧不可能达到满速（单帧断言 -10.0 实际得 -0.5，已改为收敛断言）
#   用例 4：is_on_floor() 依赖物理场景，无地面时跳跃分支不可达（已改为落地后跳跃）
# F2a（2026-08-12）：before_each 改实例化生产场景 MovementController.tscn（删手镜像，
#   碰撞配置/胶囊尺寸全部来自 tscn）；新增 5 个 step-up 加固用例（P1-P5 先行 RED）。
extends GutTest

const V3 := preload("res://Levels/M2_TDM/map_layout_v3.gd")

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


# 测试辅助：台阶/地面盒构造器——BoxShape3D StaticBody（Objects 层 1）
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


# 测试辅助：物理地面（_make_box 表达：40×1×40，顶面 y=0）
func _make_floor() -> StaticBody3D:
    return _make_box(Vector3(40, 1, 40), Vector3(0, -0.5, 0))


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
# 台阶几何 = 地面 StaticBody + 台阶盒（Objects 层 1）+ 真实控制器实例（tscn）+ 物理帧推进。
# 胶囊来自生产 MovementController.tscn（radius 0.5 / height 1.83，CollisionShape3D 本地偏移 0）：
#   脚底 = 中心 - cap_half；站地面（顶面 y=0）→ 中心 0.915；站 0.6 台面 → 中心 1.515。
# 设计：高差 ≤0.62m 视为斜坡直接走上去；V3.COVER_CROUCH(0.9)m 箱保持只能跳上；空中绝不触发。
# ══════════════════════════════════════════════════════════════


# ── F1-1：平地 + 0.6m 台阶——持续前进（无跳跃）自动登上 ──
func test_step_up_climbs_06() -> void:
    _make_floor()
    # 0.6m 台阶盒：顶面 y=0.6，前表面 z=-2，盒体 z=-2..-14（足够长，不会走出台面）
    _make_box(Vector3(6, 0.6, 12), Vector3(0, 0.3, -8))
    await wait_physics_frames(25)
    assert_true(controller.is_on_floor(), "前置：控制器应落在地面上")

    Input.action_press("move_forward")  # 朝台阶持续前进，无跳跃输入
    await wait_physics_frames(70)
    print("STEP_UP_06_POS=", controller.global_position,
            " on_floor=", controller.is_on_floor())
    assert_almost_eq(controller.global_position.y, 0.6 + cap_half, 0.05,
            "不跳跃自动登上 0.6m 台阶（脚底抬升 0.6±0.05 → 中心 ≈1.515）")
    assert_true(controller.is_on_floor(), "台阶顶上应 is_on_floor")
    assert_lt(controller.global_position.z, -2.0, "应已越过台阶前表面（z=-2）到达顶部")


# ── F1-2：0.3 → 0.6 两级微台阶——连续走上顶 ──
func test_step_up_micro_stairs() -> void:
    _make_floor()
    _make_box(Vector3(6, 0.3, 6), Vector3(0, 0.15, -5))   # 第一级：顶面 0.3，前表面 z=-2
    _make_box(Vector3(6, 0.6, 12), Vector3(0, 0.3, -14))  # 第二级：顶面 0.6，前表面 z=-8
    await wait_physics_frames(25)
    assert_true(controller.is_on_floor(), "前置：控制器应落在地面上")

    Input.action_press("move_forward")
    await wait_physics_frames(90)
    print("MICRO_STAIRS_POS=", controller.global_position,
            " on_floor=", controller.is_on_floor())
    assert_almost_eq(controller.global_position.y, 0.6 + cap_half, 0.05,
            "连续登上 0.3→0.6 两级微台阶（脚底 0.6±0.05）")
    assert_true(controller.is_on_floor(), "第二级顶上应 is_on_floor")
    assert_lt(controller.global_position.z, -8.0, "应已越过第二级前表面（z=-8）")


# ── F1-3：V3.COVER_CROUCH(0.9)m 箱——高于 STEP_MAX，同样输入上不去（保持只能跳上）──
func test_step_up_blocked_by_09() -> void:
    _make_floor()
    # 0.9m 箱（V3 蹲藏档掩体高度）：顶面 0.9，前表面 z=-2
    _make_box(Vector3(4, V3.COVER_CROUCH, 4), Vector3(0, V3.COVER_CROUCH * 0.5, -4))
    await wait_physics_frames(25)
    assert_true(controller.is_on_floor(), "前置：控制器应落在地面上")

    Input.action_press("move_forward")
    await wait_physics_frames(60)
    print("BLOCKED_BY_09_POS=", controller.global_position)
    assert_gt(controller.global_position.z, -1.7,
            "应被 0.9m 箱侧面挡住（接触位 z≈-1.5），不能越过箱体")
    assert_almost_eq(controller.global_position.y, cap_half, 0.05,
            "0.9 > STEP_MAX 0.62：仍在箱底地面（不上去）")


# ── F1-4：0.6 台阶上方净空 1.0m（< 玩家高 1.83）——不触发登台，不嵌进顶板 ──
func test_step_up_low_ceiling() -> void:
    _make_floor()
    _make_box(Vector3(6, 0.6, 8), Vector3(0, 0.3, -6))   # 0.6 台阶：顶面 0.6，前表面 z=-2
    _make_box(Vector3(6, 0.2, 8), Vector3(0, 1.7, -6))   # 顶板：底面 y=1.6，恰在台阶上方（净空 1.0）
    await wait_physics_frames(25)
    assert_true(controller.is_on_floor(), "前置：控制器应落在地面上")

    Input.action_press("move_forward")
    await wait_physics_frames(60)
    print("LOW_CEILING_POS=", controller.global_position)
    assert_almost_eq(controller.global_position.y, cap_half, 0.05,
            "净空不足：不触发登台，仍站地面")
    assert_lt(controller.global_position.y - cap_half, 0.6,
            "脚底抬升 < 0.6（未登上台阶、未嵌进顶板）")
    assert_gt(controller.global_position.z, -1.7, "应被台阶侧面挡住")


# ── F1-5：空中经过高台侧面——绝不触发登台（防下落贴墙瞬移上高台）──
# 注：0.6m 矮台阶物理上无法构造空中误登台（脚底<0.6 贴墙必与台阶体重叠、脚底>0.6
# 登台增量≤0 被"只升不降"守卫拦下）；空中窗口存在于高台侧落——下落脚底经过
# (台高-0.62, 台高) 时，无空中守卫的实现会抬升 cast 越台顶、向下命中台面、把空中
# 玩家瞬移上台。故用 2.0m 高台 + 贴墙下坠（velocity 直设，模拟击退/坠落）验证守卫。
func test_no_step_up_airborne() -> void:
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
    assert_almost_eq(controller.global_position.y, cap_half, 0.1,
            "落地在高台旁地面（y≈0.915），而非空中瞬移上高台（2.915）")
    assert_gt(controller.global_position.z, -1.6, "未越过高台前表面")


# ── F1-6：从 0.6 台面向前走下——自然下落，无异常弹跳，落地恢复 on_floor ──
func test_step_down_smooth() -> void:
    _make_floor()
    _make_box(Vector3(8, 0.6, 8), Vector3(0, 0.3, -6))    # 0.6 平台：顶面 0.6，z=-2..-10
    _make_box(Vector3(8, 2.0, 1), Vector3(0, 1.0, -13.5)) # 背后挡墙（z=-13..-14）：防止走出地图
    controller.global_position = Vector3(0, 2.0, -6)       # 平台顶上方
    await wait_physics_frames(25)
    assert_true(controller.is_on_floor(), "前置：应站在平台顶")
    assert_almost_eq(controller.global_position.y, 0.6 + cap_half, 0.05, "前置：站在平台顶")

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
    assert_almost_eq(controller.global_position.y, cap_half, 0.1, "落地在地面（y≈0.915）")


# ══════════════════════════════════════════════════════════════
# F2a step-up 加固（2026-08-12）：P1-P5 修复的先行用例
# ══════════════════════════════════════════════════════════════


# 台阶几何辅助：胶囊轴段（竖直）到点的最短距离——用于球/胶囊重叠判定
func _capsule_axis_distance(axis_z: float, feet_y: float, height: float,
        radius: float, point: Vector3) -> float:
    var axis_top_y: float = feet_y + height - radius
    var axis_bottom_y: float = feet_y + radius
    var closest := Vector3(0.0, clampf(point.y, axis_bottom_y, axis_top_y), axis_z)
    return closest.distance_to(point)


# 逐物理步采样器：本环境 headless 下 wait_physics_frames(1) ≈ 2 物理步，
# await 级采样会混叠——单帧位移/贴墙时刻必须在 _physics_process 粒度测量。
# 树序在被测控制器之后入树 → 读到的是控制器本步 move_and_slide/登台后的位置。
class _PaceSampler extends Node:
    var target: MovementController
    var steps := 0
    var wall_step := -1
    var max_h_disp := 0.0
    var prev := Vector3()

    func _physics_process(_d: float) -> void:
        steps += 1
        var p := target.global_position
        max_h_disp = maxf(max_h_disp, Vector2(p.x - prev.x, p.z - prev.z).length())
        prev = p
        if wall_step < 0 and target.is_on_wall():
            wall_step = steps


# ── F2a-1（P1）：3 级 0.6m 楼梯——登台节奏 = 行走节奏，无连锁突进 ──
# 级深 0.62 级高 0.6。断言（物理步粒度）：① 贴上台阶壁后登上台顶的耗时
# ≥ 走完 3 个踏面理论时间的 0.8（不允许显著快于行走速度）；
# ② 全程单物理步水平位移 ≤ 0.2（无突进帧：走速步幅 0.106，登台预算 ≤0.156）。
func test_step_up_pace_coupled() -> void:
    _make_floor()
    # 三级楼梯：踏面深 0.62，前表面依次 z=-2 / -2.62 / -3.24；第三级向后延伸防走出
    _make_box(Vector3(6, 0.6, 0.62), Vector3(0, 0.3, -2.31))
    _make_box(Vector3(6, 1.2, 0.62), Vector3(0, 0.6, -2.93))
    _make_box(Vector3(6, 1.8, 6.0), Vector3(0, 0.9, -6.24))
    await wait_physics_frames(25)
    assert_true(controller.is_on_floor(), "前置：控制器应落在地面上")

    var sampler := _PaceSampler.new()
    sampler.target = controller
    add_child(sampler)
    sampler.prev = controller.global_position

    var done := false
    Input.action_press("move_forward")
    for i in 300:
        await wait_physics_frames(1)
        if controller.global_position.y > 1.8 + cap_half - 0.05:  # 抵达第三级顶（脚底 1.8）
            done = true
            break
    Input.action_release("move_forward")
    print("PACE_COUPLED steps=", sampler.steps, " wall_step=", sampler.wall_step,
            " max_h_disp=", snappedf(sampler.max_h_disp, 0.001),
            " pos=", controller.global_position)
    assert_true(done, "300 帧内应登上第三级台阶顶")
    # 爬升耗时：首次贴墙物理步 → 登顶（HEAD 连锁突进远快于行走节奏）
    var climb_steps: int = sampler.steps - maxi(sampler.wall_step, 0)
    var min_time: float = (3.0 * 0.62) / 6.35 * 0.8
    assert_gte(climb_steps / 60.0, min_time,
            "登台耗时不得显著快于行走节奏（≥ 3×0.62/6.35×0.8 = %.3fs）" % min_time)
    assert_lte(sampler.max_h_disp, 0.2, "单物理步水平位移 ≤ 0.2（杜绝突进帧）")
    remove_child(sampler)
    sampler.free()


# ── F2a-2（P2）：台阶顶缘旁的 torso 组假敌人不阻挡登台 ──
func test_step_up_enemy_not_blocking() -> void:
    _make_floor()
    _make_box(Vector3(6, 0.6, 12), Vector3(0, 0.3, -8))  # 0.6 台阶：顶面 0.6，棱线 z=-2
    # 假敌人：StaticBody3D + CapsuleShape，layer 1，group torso；站台阶顶、表面距棱线 0.3m
    var enemy := StaticBody3D.new()
    enemy.collision_layer = 1
    enemy.collision_mask = 0
    enemy.add_to_group("torso")
    var ecol := CollisionShape3D.new()
    var eshape := CapsuleShape3D.new()
    eshape.radius = 0.3
    eshape.height = 1.2
    ecol.shape = eshape
    enemy.add_child(ecol)
    enemy.position = Vector3(0, 0.6 + 0.6, -2.6)  # 脚底在台面 0.6，表面 z=-2.3（距棱线 0.3）
    add_child_autofree(enemy)
    await wait_physics_frames(25)
    assert_true(controller.is_on_floor(), "前置：控制器应落在地面上")

    Input.action_press("move_forward")
    await wait_physics_frames(90)
    print("ENEMY_NOT_BLOCKING_POS=", controller.global_position,
            " on_floor=", controller.is_on_floor())
    assert_almost_eq(controller.global_position.y, 0.6 + cap_half, 0.05,
            "torso 组敌人贴台阶不阻挡登台（脚底应达台面 0.6）")
    assert_true(controller.is_on_floor(), "登台后应 is_on_floor")


# ── F2a-3（P2）：登台落点的手雷（layer 2 球刚体）阻挡登台、无瞬移嵌入 ──
func test_step_up_grenade_blocks() -> void:
    _make_floor()
    _make_box(Vector3(6, 0.6, 12), Vector3(0, 0.3, -8))  # 0.6 台阶：棱线 z=-2
    # 手雷模拟：RigidBody3D layer 2、球 r=0.15、冻结；置于登台落点（棱线内侧 0.17m）
    var grenade := RigidBody3D.new()
    grenade.collision_layer = 2
    grenade.collision_mask = 0
    grenade.freeze = true
    var gcol := CollisionShape3D.new()
    var gshape := SphereShape3D.new()
    gshape.radius = 0.15
    gcol.shape = gshape
    grenade.add_child(gcol)
    grenade.position = Vector3(0, 0.6 + 0.15, -2.17)
    add_child_autofree(grenade)
    await wait_physics_frames(25)
    assert_true(controller.is_on_floor(), "前置：控制器应落在地面上")

    Input.action_press("move_forward")
    var overlapped := false
    for i in 90:
        await wait_physics_frames(1)
        # 胶囊（含抬升中的帧）与球体重叠检测：轴段到球心距离 < 半径和
        var feet_y: float = controller.global_position.y - cap_half
        var d: float = _capsule_axis_distance(controller.global_position.z, feet_y,
                cap_half * 2.0, 0.5, grenade.position)
        if d < 0.5 + 0.15 - 0.001:
            overlapped = true
            print("GRENADE_OVERLAP frame=", i, " pos=", controller.global_position)
    Input.action_release("move_forward")
    print("GRENADE_BLOCKS_POS=", controller.global_position,
            " on_floor=", controller.is_on_floor())
    assert_false(overlapped, "全程不得瞬移嵌入手雷球体")
    var still_ground: bool = absf(controller.global_position.y - cap_half) < 0.05
    var no_overlap: float = _capsule_axis_distance(controller.global_position.z,
            controller.global_position.y - cap_half, cap_half * 2.0, 0.5, grenade.position)
    assert_true(still_ground or no_overlap >= 0.65 - 0.001,
            "尝试登台后：仍在地面，或位置未与手雷重叠（物理阻挡合理）")
    # brief 意图强化（宽松 OR 断言在 HEAD 上因引擎帧内去穿透而漏检）：
    # 手雷落台阶边登台落点 → 自然阻挡登台，玩家不得越过台阶棱线
    assert_gt(controller.global_position.z, -2.0,
            "手雷阻挡登台：不得越过台阶前表面（z=-2）")


# ── F2a-4：走向台阶同时按跳——跳跃冲量保留，不被 step-up 吞掉 ──
func test_jump_frame_guard_locked() -> void:
    _make_floor()
    _make_box(Vector3(6, 0.6, 12), Vector3(0, 0.3, -8))
    await wait_physics_frames(25)
    assert_true(controller.is_on_floor(), "前置：控制器应落在地面上")

    Input.action_press("move_forward")
    await wait_physics_frames(30)  # 走到台阶壁附近
    Input.action_press("jump")
    var impulse_seen := false
    var peak_y: float = controller.global_position.y
    for i in 40:
        await wait_physics_frames(1)
        if absf(controller.velocity.y - 7.54) < 0.01:
            impulse_seen = true
        peak_y = maxf(peak_y, controller.global_position.y)
    Input.action_release("jump")
    print("JUMP_GUARD impulse_seen=", impulse_seen, " peak_y=", snappedf(peak_y, 0.001))
    assert_true(impulse_seen, "应存在 velocity.y==7.54 的帧（跳跃冲量未被 step-up 吞掉）")
    assert_gt(peak_y, 1.4, "跳跃应真实起跳（峰值显著高于地面站位）")


# ── F2a-5：蹲姿登台——胶囊蹲姿尺寸 + 2.0m 净空顶板（站立不够高，蹲姿够） ──
# 蹲姿几何（Crouch.gd 同款）：胶囊高 1.37、Collision 中心 -0.23（脚底仍 origin-0.915）。
# 站上 0.6 台面 → origin.y = 0.6 + 0.915 = 1.515（胶囊中心全局 y = 1.285 = 0.6+0.685）。
func test_crouch_step_up() -> void:
    _make_floor()
    _make_box(Vector3(6, 0.6, 12), Vector3(0, 0.3, -8))   # 0.6 台阶：顶面 0.6，棱线 z=-2
    _make_box(Vector3(6, 0.2, 10), Vector3(0, 2.1, -7))   # 顶板：底面 y=2.0，覆盖台阶上方
    # 手动改蹲姿胶囊（tscn 胶囊是共享 SubResource——复制为实例私有，同 Crouch.gd）
    var col := controller.get_node("Collision") as CollisionShape3D
    var shape := (col.shape as CapsuleShape3D).duplicate()
    shape.height = 1.37
    col.shape = shape
    col.position.y = -0.23
    controller.is_crouching = true
    await wait_physics_frames(25)
    assert_true(controller.is_on_floor(), "前置：控制器应落在地面上")

    Input.action_press("move_forward")
    await wait_physics_frames(150)  # 蹲速 2.59 接近较慢
    print("CROUCH_STEP_UP_POS=", controller.global_position,
            " on_floor=", controller.is_on_floor())
    assert_almost_eq(controller.global_position.y, 0.6 + cap_half, 0.05,
            "蹲姿登台成功（脚底 0.6 → origin 1.515；胶囊中心 1.285 = 0.6+0.685）")
    assert_true(controller.is_on_floor(), "台阶顶上应 is_on_floor")
    assert_lt(controller.global_position.z, -2.0, "应已越过台阶前表面到达顶部")


# ══════════════════════════════════════════════════════════════
# F2a 二轮守卫（2026-08-12）：G1 滑翔跨隙 / G2 中段穿透 / G3 坡道瞬移
# ══════════════════════════════════════════════════════════════


# 逐物理步 y 增量采样器（坡道测试用；await 级采样在本环境混叠 ~2 物理步）
class _SlopeSampler extends Node:
    var target: MovementController
    var steps := 0
    var max_dy := 0.0
    var prev_y := -1.0
    var start_y := 0.0
    var peak_y := 0.0
    var peak_step := 0

    func _physics_process(_d: float) -> void:
        steps += 1
        var y := target.global_position.y
        if prev_y >= 0.0:
            max_dy = maxf(max_dy, y - prev_y)
        prev_y = y
        if y > peak_y:
            peak_y = y
            peak_step = steps


# ── G1：地板吸附滑翔不得跨隙瞬移上相邻高台 ──
# 平台 A 顶 0.6（z=-2..-10），间隙 0.4m，平台 B 顶 1.2（z=-10.4 起），从 A 走向 B。
# 无守卫时：走离 A 边缘后 floor_snap_length 滑翔窗口内 is_on_floor 仍真，
# 探针够到 B → 跨隙瞬移（实测 HEAD：中心 y 直达 1.99+，脚底 ≥1.08）。
# 守卫：底缘前缘下方支撑深度超过 floor_snap_length（悬挑跨隙）即放弃登台。
# 阈值用脚底高度（站立 A：脚底 0.6 < 1.15；登上 B：脚底 1.2 ≥ 1.15）。
func test_no_gap_cross_teleport() -> void:
    _make_floor()
    _make_box(Vector3(8, 0.6, 8), Vector3(0, 0.3, -6))    # 平台 A：顶 0.6，z=-2..-10
    _make_box(Vector3(8, 1.2, 8), Vector3(0, 0.6, -14.4)) # 平台 B：顶 1.2，z=-10.4..-18.4
    controller.global_position = Vector3(0, 0.6 + cap_half + 0.5, -4)  # A 顶上方
    await wait_physics_frames(25)
    assert_true(controller.is_on_floor(), "前置：应站在平台 A 顶")
    assert_almost_eq(controller.global_position.y - cap_half, 0.6, 0.05, "前置：A 顶（脚底 0.6）")

    Input.action_press("move_forward")
    var breached := false
    for i in 200:
        await wait_physics_frames(1)
        if controller.global_position.y - cap_half >= 1.15:
            breached = true
            break
    Input.action_release("move_forward")
    print("GAP_CROSS pos=", controller.global_position,
            " on_floor=", controller.is_on_floor())
    assert_false(breached, "不得跨隙登上平台 B（任意帧脚底高度 < 1.15）")
    assert_true(controller.is_on_floor(), "最终应站在实地（地面/平台 A/间隙槽底）")


# ── G3：真坡道上不得逐帧登台瞬移（20° 坡走廊贴墙爬坡） ──
# 坡面法线通过地板判定（0.94 ≥ cos45）；无守卫时侧墙贴墙帧触发 step-up，
# 探针命中坡面把自己当台阶逐帧抬升（深验实测 5 倍速）。守卫：触发墙与棱线
# 命中均要求法线 y<0.5（近垂直立面），坡面命中即放弃。本环境直走坡道无墙不
# 触发（HEAD 亦绿）——走廊构型覆盖守卫代码路径，属封死型回归用例。
func test_no_step_up_on_slope() -> void:
    _make_floor()
    # 20° 坡：斜面板（旋转盒），底端埋入平地（尖端 z≈-2），沿 -z 上升
    var ramp := StaticBody3D.new()
    ramp.collision_layer = 1
    ramp.collision_mask = 0
    var rc := CollisionShape3D.new()
    var rs := BoxShape3D.new()
    rs.size = Vector3(6, 0.2, 6.5)
    rc.shape = rs
    ramp.add_child(rc)
    ramp.rotation_degrees = Vector3(20, 0, 0)
    ramp.position = Vector3(0, 1.0, -5.054)
    add_child_autofree(ramp)
    # 侧墙走廊：内表面 x=2.5，沿坡延伸
    _make_box(Vector3(0.4, 4, 24), Vector3(2.7, 2, -10))

    # 玩家置于坡面中段贴墙（坡面 h≈0.73 处）
    controller.global_position = Vector3(2.0, 2.14, -4)
    await wait_physics_frames(30)
    assert_true(controller.is_on_floor(), "前置：应站在坡面上")

    var sampler := _SlopeSampler.new()
    sampler.target = controller
    add_child(sampler)
    sampler.start_y = controller.global_position.y
    sampler.peak_y = sampler.start_y
    Input.action_press("move_forward")
    Input.action_press("move_right")  # 持续压向侧墙——贴墙爬坡触发场景
    await wait_physics_frames(80)
    Input.action_release("move_forward")
    Input.action_release("move_right")
    print("SLOPE max_dy_per_step=", snappedf(sampler.max_dy, 0.001),
            " peak=", snappedf(sampler.peak_y, 0.001))
    # ① 单物理步 y 增量 ≤ 0.06（行走爬坡 = 0.106×tan20 ≈ 0.039；逐帧登台瞬移 ≥0.2）
    assert_lte(sampler.max_dy, 0.06, "爬坡期间单物理步 y 增量 ≤ 0.06（无逐帧瞬移）")
    # ② 整体爬升速率 ≤ walk_speed×sin20°×1.6（行走爬坡 = walk×sin20）
    var climb_time: float = maxi(sampler.peak_step, 1) / 60.0
    var rate: float = (sampler.peak_y - sampler.start_y) / climb_time
    var limit: float = 6.35 * sin(deg_to_rad(20.0)) * 1.6
    assert_lte(rate, limit, "爬升速率 ≤ walk×sin20°×1.6（%.2f m/s）" % limit)
    remove_child(sampler)
    sampler.free()


# ── G2：登台路径中段的薄几何（细柱）阻挡登台，不得穿透 ──
# 0.6 台阶（棱线 z=-2）；登台路径（贴墙位 z=-1.5 → 落点 z≈-1.656）中段立
# 0.1×0.1 细柱（高 1.5，z=-1.578）。断言：登台被拦、玩家保持在地面不穿柱。
# 注：胶囊半径 0.5 » 登台水平位移 0.156，起点/路径/落点三查已覆盖路径全程，
# 中段查为保险层——本用例锁定"薄几何拦登台"行为（HEAD 三查亦拦，属回归守卫）。
func test_step_up_mid_path_blocked() -> void:
    _make_floor()
    _make_box(Vector3(6, 0.6, 12), Vector3(0, 0.3, -8))          # 0.6 台阶：棱线 z=-2
    _make_box(Vector3(0.1, 1.5, 0.1), Vector3(0, 0.75, -1.578)) # 细柱：路径中段
    await wait_physics_frames(25)
    assert_true(controller.is_on_floor(), "前置：控制器应落在地面上")

    Input.action_press("move_forward")
    for i in 90:
        await wait_physics_frames(1)
        assert_lt(controller.global_position.y, 0.6 + cap_half - 0.1,
                "第 %d 帧不得登上台阶（细柱阻挡）" % i)
    Input.action_release("move_forward")
    print("MID_BLOCKED pos=", controller.global_position)
    assert_almost_eq(controller.global_position.y, cap_half, 0.05,
            "登台被细柱拦下：仍站地面")
    assert_gt(controller.global_position.z, -1.7, "未穿过细柱/台阶")
