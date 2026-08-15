# test/unit/test_auto_traversal_runup.gd
# 2026-08-15 F8/F9 TDD：RUNUP 直线化 + 触发门控收紧

extends GutTest

const AT := preload("res://Levels/M2_TDM/auto_traversal.gd")
const TOL := 0.0001

# 1. target_yaw 锚点（Godot 惯例 yaw）：北(0,0,-1)→0；东(1,0,0)→-PI/2；南→±PI 边界
func test_target_yaw_anchors() -> void:
	assert_almost_eq(AT.target_yaw(Vector3.ZERO, Vector3(0, 0, -1)), 0.0, TOL)
	assert_almost_eq(AT.target_yaw(Vector3.ZERO, Vector3(1, 0, 0)), -PI / 2.0, TOL)

# 2. 近静止放行按路径声明（F9 核心语义）：hspeed ≤0.5 时 allow_near_still 决定放行
func test_trigger_allowed_near_still() -> void:
	assert_true(AT.trigger_allowed(5.0, 0.3, Vector2(0.2, 0.2), Vector2(1, 0), 4.0, true, true))
	assert_false(AT.trigger_allowed(5.0, 0.3, Vector2(0.2, 0.2), Vector2(1, 0), 4.0, true, false))

# 3. 方向锥 ±25°（cos25°≈0.906 → 系数 0.9）：30° 偏（cos=0.866 < 0.9）拒；20° 偏放行
func test_trigger_allowed_cone_25deg() -> void:
	var td := Vector2(1, 0)
	var v30 := Vector2(cos(deg_to_rad(30.0)), sin(deg_to_rad(30.0))) * 5.0
	assert_false(AT.trigger_allowed(5.0, 5.0, v30, td, 4.0, true, true))
	var v20 := Vector2(cos(deg_to_rad(20.0)), sin(deg_to_rad(20.0))) * 5.0
	assert_true(AT.trigger_allowed(5.0, 5.0, v20, td, 4.0, true, true))

# 4. 速度门（hspeed 与 gate 边界；0.6 恰在 0.5 近静止阈值上、仍低于 gate 时拒）
func test_trigger_allowed_speed_gate() -> void:
	assert_false(AT.trigger_allowed(5.0, 3.5, Vector2(3.5, 0), Vector2(1, 0), 4.0, true, true))
	assert_true(AT.trigger_allowed(5.0, 4.5, Vector2(4.5, 0), Vector2(1, 0), 4.0, true, true))
	assert_false(AT.trigger_allowed(5.0, 0.6, Vector2(0.6, 0), Vector2(1, 0), 4.0, true, true))

# 5. 原地跳恒放行（jump_v ≤ 0.4 无视一切门控）
func test_trigger_allowed_stationary_jump() -> void:
	assert_true(AT.trigger_allowed(0.3, 0.0, Vector2.ZERO, Vector2.ZERO, 9.0, true, false))

# 6. 确定性：同参数两次全等
func test_trigger_allowed_determinism() -> void:
	var a := AT.trigger_allowed(5.0, 4.5, Vector2(4.5, 0), Vector2(1, 0), 4.0, true, true)
	var b := AT.trigger_allowed(5.0, 4.5, Vector2(4.5, 0), Vector2(1, 0), 4.0, true, true)
	assert_eq(a, b)

# 7. 滑墙切向手性锁存锚（纯逻辑）：投影充足 → 投影切线；投影 <0.1 + 锁存非零 →
#    锁存方向；投影 <0.1 + 锁存零 → 固定兜底 (wall_n.z, -wall_n.x)
func test_wall_follow_tangent_latch() -> void:
	var wall_n := Vector3(1, 0, 0)
	var t1: Vector3 = AT.wall_follow_tangent(Vector3(0, 0, 5), wall_n, Vector3.ZERO)
	assert_eq(t1, Vector3(0, 0, 1))
	var t2: Vector3 = AT.wall_follow_tangent(Vector3(1, 0, 0), wall_n, Vector3(0, 0, -1))
	assert_eq(t2, Vector3(0, 0, -1))
	var t3: Vector3 = AT.wall_follow_tangent(Vector3(1, 0, 0), wall_n, Vector3.ZERO)
	assert_eq(t3, Vector3(0, 0, -1))
	var t4: Vector3 = AT.wall_follow_tangent(Vector3(1, 0, 0.01), wall_n, Vector3(0, 0, 1))
	assert_eq(t4, Vector3(0, 0, 1))
