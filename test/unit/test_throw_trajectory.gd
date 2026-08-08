# test/unit/test_throw_trajectory.gd
# M1 任务8：ThrowTrajectory 投掷抛物线预览测试（TDD RED 先行）
# 行为（brief §9.1）：30 点重力积分弹道（半隐式欧拉，重力与 Grenade 同源 default_gravity）、
#   首点 = 投掷原点、终点 = 弹道末点（解析式派生期望）、随方向实时更新。
# 全局约束：不硬编码散值——期望由解析式 + ProjectSettings 重力派生；
#   Vector3 断言按分量比较（GUT assert_almost_eq 不支持 Vector3 操作数）。
extends GutTest

var trajectory: ThrowTrajectory


func before_each() -> void:
	trajectory = ThrowTrajectory.new()
	add_child_autofree(trajectory)


# ================= 1. 点列生成 =================
func test_generates_30_points_from_origin() -> void:
	var origin := Vector3(0, 2, 0)
	trajectory.update_trajectory(origin, Vector3(0, 0, -1), 15.0)
	assert_eq(trajectory.points.size(), 30, "点列 = 30 点")
	assert_eq(trajectory.points[0], origin, "首点 = 投掷原点")
	assert_lt(trajectory.points[1].z, 0.0, "水平沿投掷方向（-Z）")
	assert_almost_eq(trajectory.points[1].x, origin.x, 0.001, "水平无横向漂移")


# ================= 2. 重力积分正确性 =================
func test_endpoint_matches_gravity_integration() -> void:
	# 半隐式欧拉解析式（重力恒定、无空气阻力）——实现先更新速度再位移、点列在更新前捕获：
	#   pos_n = origin + v0×n×dt - ½ g dt² n(n+1)   （第 n 点 t = n×dt，30 点末点 n = 29）
	var origin := Vector3(0, 2, 0)
	var dir := Vector3(0, 0, -1)
	var strength := 15.0
	trajectory.update_trajectory(origin, dir, strength)
	var g: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
	var dt := 0.02
	var n := 29  # 第 30 点索引（0 起）
	var expected := origin + dir * (strength * n * dt) - Vector3(0, 1, 0) * (0.5 * g * dt * dt * n * (n + 1))
	assert_almost_eq(trajectory.points[29].x, expected.x, 0.001, "终点 x = 解析解")
	assert_almost_eq(trajectory.points[29].y, expected.y, 0.001, "终点 y = 重力积分解析解")
	assert_almost_eq(trajectory.points[29].z, expected.z, 0.001, "终点 z = 解析解")


func test_y_monotonic_descent_under_gravity() -> void:
	trajectory.update_trajectory(Vector3(0, 2, 0), Vector3(0, 0, -1), 15.0)
	for i in range(1, trajectory.points.size()):
		assert_lt(trajectory.points[i].y, trajectory.points[i - 1].y,
				"第 %d 点 y 递减（重力下落）" % i)


# ================= 3. 实时更新 =================
func test_update_with_new_direction_recomputes_points() -> void:
	var origin := Vector3(0, 2, 0)
	trajectory.update_trajectory(origin, Vector3(0, 0, -1), 15.0)
	assert_lt(trajectory.points[1].z, 0.0, "前置：初始视向 -Z")
	trajectory.update_trajectory(origin, Vector3(1, 0, 0), 15.0)
	assert_gt(trajectory.points[1].x, 0.0, "新视向 +X：第 2 点沿 +X")
	assert_almost_eq(trajectory.points[1].z, origin.z, 0.001, "新视向 +X：无 -Z 分量（实时覆盖）")


func test_update_with_new_origin_moves_arc() -> void:
	trajectory.update_trajectory(Vector3(0, 2, 0), Vector3(0, 0, -1), 15.0)
	var before: Vector3 = trajectory.points[5]
	trajectory.update_trajectory(Vector3(0, 5, 0), Vector3(0, 0, -1), 15.0)
	assert_almost_eq(trajectory.points[5].x, before.x, 0.001, "原点抬高：x 不变")
	assert_almost_eq(trajectory.points[5].y, before.y + 3.0, 0.001, "原点抬高 3m → y 上移 3m")
	assert_almost_eq(trajectory.points[5].z, before.z, 0.001, "原点抬高：z 不变")
