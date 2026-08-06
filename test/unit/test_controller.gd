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
    # capsule（默认 radius=0.5, height=2.0）、layer=2(Player)、mask=3(Objects+Player)
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
func test_initial_speed() -> void:
    assert_eq(controller.speed, 10, "默认速度应为 10")


# ── 用例 2：默认跳跃高度（纯属性）──
func test_jump_height_default() -> void:
    assert_eq(controller.jump_height, 10, "默认跳跃高度应为 10")


# ── 用例 3（GREEN 版）：真实物理场景 + 加速模型收敛断言 ──
# RED 证据：单帧朴素断言得 -0.5 ≠ -10（加速模型首帧 lerp 权重仅 0.05）。
# 修正：落地后推进 60 物理帧，断言水平速度收敛到接近 -speed，且位置真实前移。
func test_move_forward_moves_player_forward() -> void:
    _make_floor()
    await wait_physics_frames(25)
    assert_true(controller.is_on_floor(), "前置：控制器应落在地面上")
    Input.action_press("move_forward")
    await wait_physics_frames(60)
    assert_lt(controller.velocity.z, -9.0,
            "60 帧加速收敛后 velocity.z 应接近 -speed（理论 ≈ -9.998）")
    assert_lt(controller.position.z, -5.0,
            "控制器应真实向前移动（理论位移 ≈ -8.96 单位）")


# ── 用例 4（GREEN 版）：真实物理场景落地后跳 ──
# RED 证据：无地面时 is_on_floor() 恒 false，跳跃分支不可达（velocity.y = -0.49 为重力）。
# 修正：放置地面、await 落地、确认 is_on_floor 后按跳，单物理帧内断言精确冲量。
func test_jump_impulse() -> void:
    _make_floor()
    await wait_physics_frames(25)
    assert_true(controller.is_on_floor(), "前置：控制器应落在地面上")
    Input.action_press("jump")
    await wait_physics_frames(1)
    assert_eq(controller.velocity.y, 10.0,
            "落地按跳后 velocity.y 应精确等于 jump_height（跳跃冲量）")


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
