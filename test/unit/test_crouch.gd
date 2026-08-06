# 下蹲行为测试（TDD：先 RED）
# 需求：Shift 从"无限冲刺"改为"下蹲"——CS 风格参数：
#   胶囊高 2.0m → 1.3m（中心下降至 y=0.65）；相机 1.64m → 0.95m；移速 10 → 6 m/s
#   设计联动：未来矮掩体统一 1.4m（蹲下完全隐蔽，站立露头 0.24m）
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

    # 让玩家落到地面站稳
    await wait_physics_frames(40)
    print("SETTLED_PLAYER_Y=", player.global_position.y, " (应≈1.0)")

func _stand() -> void:
    Input.action_release("sprint")
    await wait_physics_frames(30)

func test_crouch_lowers_camera() -> void:
    _build_player()
    await _stand()
    var stand_cam_y: float = head.global_position.y
    print("STAND_CAM_Y=", stand_cam_y)
    assert_almost_eq(stand_cam_y, 1.64, 0.01, "站立相机高度 = 1.64m（玩家中心 1.0 + Head y 0.64）")

    Input.action_press("sprint")
    await wait_physics_frames(30)  # 蹲下过渡完成
    var crouch_cam_y: float = head.global_position.y
    print("CROUCH_CAM_Y=", crouch_cam_y)
    assert_almost_eq(crouch_cam_y, 0.95, 0.01, "下蹲相机高度 = 0.95m")

func test_crouch_reduces_speed() -> void:
    _build_player()
    await _stand()
    print("STAND_SPEED=", controller.speed)
    assert_eq(controller.speed, 10, "站立移速 = 10")

    Input.action_press("sprint")
    await wait_physics_frames(30)
    print("CROUCH_SPEED=", controller.speed)
    assert_eq(controller.speed, 6, "下蹲移速 = 6（60%）")
