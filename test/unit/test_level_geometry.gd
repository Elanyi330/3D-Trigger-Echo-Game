# 回归测试：L_Main 测试场景几何布局正确性（玩家出生点不被碰撞体罩住）
# 背景：M0 手动冒烟发现屏幕闪烁/移动异常，根因为东西墙 BoxShape 尺寸错误
#   （20.5×4×1 沿 X 延伸，罩住半个场地；应 1×4×20.5 沿 Z 延伸）
# 本测试锁定：玩家在场地中央出生后 60 物理帧内，位置稳定无抖动、无滑动碰撞。
extends GutTest

func test_spawn_point_clear_of_colliders() -> void:
    var scene: PackedScene = load("res://Levels/Main/L_Main.tscn")
    var level: Node = scene.instantiate()
    add_child_autofree(level)

    var player: Node = level.get_node("Player")
    var mc: MovementController = player as MovementController
    var spawn: Vector3 = player.global_position

    # 60 帧观察（无任何输入）
    await wait_physics_frames(60)

    # 1. 玩家未被任何碰撞体推离出生点（抖动检测：位移 < 0.5m，防"被墙夹住反复弹射"）
    var drift: Vector3 = player.global_position - spawn
    print("DRIFT=", drift)
    assert_lt(absf(drift.x), 0.5, "玩家不应被碰撞体水平推离出生点（东西墙 BoxShape 尺寸错误的回归）")
    assert_lt(absf(drift.z), 0.5, "玩家不应被碰撞体水平推离出生点")

    # 2. 玩家应站在地面上（不是悬空失重）
    print("IS_ON_FLOOR=", mc.is_on_floor())
    assert_true(mc.is_on_floor(), "玩家应站在地面上（is_on_floor=true）")

    # 3. 不应与任何墙发生滑动碰撞（站地面与 Ground 接触属正常；被墙夹住时才有 Wall* 碰撞）
    var collisions: int = mc.get_slide_collision_count()
    print("SLIDE_COLLISION_COUNT=", collisions)
    var wall_hit: bool = false
    for i in range(collisions):
        var collider_name: String = mc.get_slide_collision(i).get_collider().name
        if String(collider_name).begins_with("Wall"):
            wall_hit = true
            print("  WALL_COLLISION=", collider_name)
    assert_false(wall_hit, "玩家在场地中央不应与任何墙发生滑动碰撞")

    # 4. 玩家 y 应稳定在 ~1.0（胶囊底部贴地，中心 1.0；允许物理微小沉降）
    var y: float = player.global_position.y
    print("PLAYER_Y=", y)
    assert_between(y, 0.99, 1.01, "玩家高度应稳定在 ~1.0（胶囊中心，底部贴地）")
