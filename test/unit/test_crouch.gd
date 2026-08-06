# 下蹲行为测试（TDD：先 RED）
# 需求：Shift 从"无限冲刺"改为"下蹲"——2026-08-06 完全照搬 CS 数值：
#   胶囊高 1.83m → 1.37m（中心 y=0 → -0.23）；相机 1.63m → 1.17m；移速 6.35 → 2.59 m/s
#   掩体 1.22m（CS 箱子 48u）：蹲下 1.37m > 1.22m 仍露头（CS 式减少暴露）
extends GutTest

var crouch: Node
var controller: MovementController
var head: Node3D

func _build_player() -> void:
    # 用真实 Player.tscn（含 Crouch 组件）验证 + 代码创建测试地面（层 1 Objects）
    var scene: PackedScene = load("res://Player/Player.tscn")
    var player: Node = scene.instantiate()
    add_child_autofree(player)
    controller = player as MovementController
    head = player.get_node("Head")
    crouch = player.get_node("Crouch")

    var floor_body: StaticBody3D = StaticBody3D.new()
    floor_body.collision_layer = 1
    floor_body.collision_mask = 0
    var shape: CollisionShape3D = CollisionShape3D.new()
    var box: BoxShape3D = BoxShape3D.new()
    box.size = Vector3(40, 1, 40)
    shape.shape = box
    floor_body.add_child(shape)
    add_child_autofree(floor_body)
    floor_body.global_position = Vector3(0, -0.5, 0)

    # 让玩家落到地面站稳（胶囊 1.83 高 → 中心 y≈0.915）
    await wait_physics_frames(40)
    print("SETTLED_PLAYER_Y=", player.global_position.y, " (胶囊 1.83 → 应≈0.915)")

func _stand() -> void:
    Input.action_release("sprint")
    await wait_physics_frames(60)

func test_crouch_lowers_camera() -> void:
    _build_player()
    await _stand()
    var stand_cam_y: float = head.global_position.y
    print("STAND_CAM_Y=", stand_cam_y)
    assert_almost_eq(stand_cam_y, 1.63, 0.01, "站立相机高度 = 1.63m（CS 眼位 64u）")

    Input.action_press("sprint")
    await wait_physics_frames(60)  # 蹲下过渡完成（lerp 收敛）
    var crouch_cam_y: float = head.global_position.y
    print("CROUCH_CAM_Y=", crouch_cam_y)
    assert_almost_eq(crouch_cam_y, 1.17, 0.01, "下蹲相机高度 = 1.17m（CS 下蹲眼位 46u）")

func test_crouch_reduces_speed() -> void:
    _build_player()
    await _stand()
    print("STAND_SPEED=", controller.speed)
    assert_almost_eq(controller.speed, 6.35, 0.01, "站立移速 = 6.35（CS 250u/s）")

    Input.action_press("sprint")
    await wait_physics_frames(60)
    print("CROUCH_SPEED=", controller.speed)
    assert_almost_eq(controller.speed, 2.59, 0.01, "下蹲移速 = 2.59（CS 102u/s）")
