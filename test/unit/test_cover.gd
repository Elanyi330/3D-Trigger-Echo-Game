# 掩体地形资产验收测试（M0 验收项，企划书 §4.1.1）
# CoverShort：1.22m 矮掩体（CS 箱子 48u），三重物理身份——
#   侧面=墙（阻挡）、顶部=地（可站立）、边缘=平滑走下（自然跌落）
#   下蹲联动（CS 式）：蹲下 1.37m > 掩体 1.22m——仍露头但暴露面大幅减小
extends GutTest

var controller: MovementController
var cover: Node3D


func _build_arena() -> void:
    # 地面
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

    # 玩家（用真实 Player.tscn，含 Crouch 组件）
    var scene: PackedScene = load("res://Player/Player.tscn")
    var player: Node = scene.instantiate()
    add_child_autofree(player)
    controller = player as MovementController
    controller.global_position = Vector3(0, 1, 0)

    # 掩体（真实资产 CoverShort.tscn）—— 放在玩家前方 z=-3，中心 y=0.61（顶面 y=1.22）
    var cover_scene: PackedScene = load("res://Levels/Geometry/CoverShort.tscn")
    cover = cover_scene.instantiate()
    add_child_autofree(cover)
    cover.global_position = Vector3(0, 0.61, -3)

    await wait_physics_frames(40)  # 落稳
    print("SETTLED_Y=", controller.global_position.y)


# 验收 1：侧面 = 墙——站立向前走，被掩体挡住不能穿过
func test_side_blocks_walk() -> void:
    _build_arena()
    controller.global_position = Vector3(0, 1, 0)
    await wait_physics_frames(5)

    Input.action_press("move_forward")  # 向前（-Z），掩体在 z=-3
    await wait_physics_frames(60)
    Input.action_release("move_forward")
    print("BLOCKED_POS=", controller.global_position)
    # 掩体侧面 z=-3.5（中心 z=-3 厚 1 → 前表面 z=-3.5），胶囊半径 0.5 → 接触面 z≈-3.0
    assert_gt(controller.global_position.z, -3.5,
            "玩家应被掩体侧面挡住（z 应 > -3.5，不能穿过到 z<-3.5）")


# 验收 2：顶部 = 地——掩体顶可站立（放置验证）+ 跳跃可达（CS 跳高 1.45m > 掩体 1.22m）
func test_top_is_floor() -> void:
    _build_arena()

    # 2a：放置到掩体顶上方，下落应站在顶部
    controller.global_position = Vector3(0, 2.2, -3.0)
    await wait_physics_frames(40)
    print("ON_TOP_POS=", controller.global_position)
    assert_gt(controller.global_position.y, 1.8,
            "玩家从掩体顶上方下落应站在顶部（中心 ≈2.13）")
    assert_true(controller.is_on_floor(), "站在掩体顶部应 is_on_floor=true")

    # 2b：跳跃峰值应超过掩体顶（CS 跳高 1.45m，掩体 1.22m）
    controller.global_position = Vector3(0, 1.0, -2.0)
    await wait_physics_frames(30)
    Input.action_press("jump")
    await wait_physics_frames(15)  # 峰值附近
    Input.action_release("jump")
    print("JUMP_PEAK=", controller.global_position)
    assert_gt(controller.global_position.y, 2.13,
            "跳跃峰值应超过掩体顶中心高度（CS 跳高 1.45m）")


# 验收 3：边缘 = 平滑走下——从顶部走向边缘自然跌落（无需跳跃）
func test_edge_walk_off() -> void:
    _build_arena()
    controller.global_position = Vector3(0, 1, 0)
    await wait_physics_frames(5)

    # 放置到掩体顶上方，下落站在顶部
    controller.global_position = Vector3(0, 2.2, -3.0)
    await wait_physics_frames(40)
    assert_gt(controller.global_position.y, 1.8, "前置：应在掩体顶部")
    print("TOP_POS=", controller.global_position)

    # 在顶部向侧面（+X）走，走出掩体边缘（宽 1m，中心 x=0 → 边缘 x=0.5）
    Input.action_press("move_right")
    await wait_physics_frames(50)
    Input.action_release("move_right")
    print("WALKED_OFF_POS=", controller.global_position)
    # 应已落到地面（y≈1.0），且 x 越过边缘（>0.5）
    assert_lt(controller.global_position.y, 1.5,
            "走出边缘后应自然跌落回地面（y≈1.0）")
    assert_gt(controller.global_position.x, 0.5,
            "应已越过掩体边缘（x>0.5）")


# 验收 4（CS 式）：下蹲后胶囊顶（1.37m）> 掩体顶（1.22m）——蹲下仍露头，但比站立（1.83m）暴露面小
func test_crouch_hidden_behind_cover() -> void:
    _build_arena()
    controller.global_position = Vector3(0, 1, 0)
    await wait_physics_frames(5)

    Input.action_press("sprint")  # 下蹲
    await wait_physics_frames(30)
    Input.action_release("sprint")
    print("CROUCHED_CAM_Y=", controller.get_node("Head").global_position.y)
    # CS 数值：下蹲胶囊顶 = 中心 -0.23 + 半高 0.685 = 1.37m；站立 1.83m
    var capsule_top: float = controller.get_node("Collision").global_position.y + 0.685  # 1.37/2 半高
    print("CAPSULE_TOP_Y=", capsule_top)
    assert_gt(capsule_top, 1.22, "下蹲胶囊顶（1.37m）> 掩体顶（1.22m）——CS 式：蹲下仍露头")
