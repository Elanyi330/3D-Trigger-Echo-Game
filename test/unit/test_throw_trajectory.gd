# test/unit/test_throw_trajectory.gd
# M1 任务8：ThrowTrajectory 投掷抛物线预览测试（TDD RED 先行）
# M2 手感修复（2026-08-13）重写：
#   - 积分步长 STEP_SECONDS=1/60（=物理帧长，与 RigidBody3D 同构）、点列上限 POINT_COUNT=200（3.33s）
#   - 落地判定 = 首次穿越 y≤0 线性插值（旧"末点投影 y=0"作废——长弧浮空错标）
#   - 可见点列截至触地点（最后一点 y>0，不画入地下）；不落地兜底 = 末点投影
# 行为：半隐式欧拉积分（重力与 Grenade 同源 default_gravity）；首点 = 投掷原点。
# 全局约束：不硬编码散值——期望由解析式 + ProjectSettings 重力派生；
#   Vector3 断言按分量比较（GUT assert_almost_eq 不支持 Vector3 操作数）。
extends GutTest

var trajectory: ThrowTrajectory


func before_each() -> void:
	trajectory = ThrowTrajectory.new()
	add_child_autofree(trajectory)


# ================= 1. 常量 =================
func test_step_and_point_count_constants() -> void:
	assert_almost_eq(ThrowTrajectory.STEP_SECONDS, 1.0 / 60.0, 0.00001, "积分步长 = 物理帧长（同构）")
	assert_eq(ThrowTrajectory.POINT_COUNT, 200, "点列上限 200（3.33s 覆盖垂直抛 3.06s）")


# ================= 2. 点列生成（落地截止） =================
func test_generates_points_until_ground_crossing() -> void:
	# dt=1/60 平抛 y=2：t_land=√(2·2/g)≈0.6389s → y>0 的 i<38.33 → 39 点（i=0..38，解析确定）
	var origin := Vector3(0, 2, 0)
	trajectory.update_trajectory(origin, Vector3(0, 0, -1), 15.0)
	assert_eq(trajectory.points.size(), 39, "落地前点列 = 39 点（解析确定）")
	assert_eq(trajectory.points[0], origin, "首点 = 投掷原点")
	assert_lt(trajectory.points[1].z, 0.0, "水平沿投掷方向（-Z）")
	assert_gt(trajectory.points[38].y, 0.0, "最后可见点在空中（不画入地下）")


# ================= 3. 落地穿越插值 =================
func test_landing_point_is_ground_crossing_interpolation() -> void:
	# 落点 = 穿越区间线性插值：y 精确 0；x/z 与解析值 15×t_land 容差 0.25（单步穿越离散化误差）
	var origin := Vector3(0, 2, 0)
	trajectory.update_trajectory(origin, Vector3(0, 0, -1), 15.0)
	assert_eq(trajectory.landing_point.y, 0.0, "落点 y = 地面 0（插值穿越点）")
	var g: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
	var t_land := sqrt(2.0 * 2.0 / g)
	assert_almost_eq(trajectory.landing_point.z, -15.0 * t_land, 0.25, "落点 z ≈ 解析平抛距离")
	assert_almost_eq(trajectory.landing_point.x, 0.0, 0.001, "无横向漂移")


func test_vertical_throw_lands_within_coverage() -> void:
	# 90° 上抛 t_land=(15+√(15²+2·9.8·2))/9.8≈3.19s → ~192 点 < 200 上限
	trajectory.update_trajectory(Vector3(0, 2, 0), Vector3(0, 1, 0), 15.0)
	assert_lt(trajectory.points.size(), ThrowTrajectory.POINT_COUNT, "垂直抛在点列上限内落地")
	assert_eq(trajectory.landing_point.y, 0.0, "垂直抛落点在地面")


# ================= 4. 实时更新 =================
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
