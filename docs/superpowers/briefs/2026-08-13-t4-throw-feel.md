# Task Brief: T4 — 投掷手感（起自右手雷处 / 瞄哪打哪 / 轨迹一致 / 落点清晰）

> 项目：Trigger Echo（Godot 4.7.1 + GDScript + GUT 测试）
> 工作目录：`/Users/elanyi/Projects/Trigger-Echo`（分支 feat/m1-assets，**直接在此目录工作**）
> 父计划：`docs/superpowers/plans/2026-08-13-m2-melee-grenade-fixes.md`（本 brief 为该计划 T4 的完整规格）
> 前置：T1/T2/T3 已完成或进行中。本任务只改本 brief 列出的 4 个源文件 + 2 个测试文件；**不碰 T2/T3 的文件（MeleeController/Grenade 逻辑）**。

## 目标（用户需求原文要点）

蓄力投掷抛物线**起点在右手手雷处**，向**玩家视角中间的目标点**延伸；抛物线能被更完整看到、落点更清晰；**手雷落点和运行轨迹必须和蓄力抛物线基本一致**（精准丢雷）。

四个子项：
1. **投掷原点 = 右手雷处**：视图模型手雷网格的实时世界位置（随蓄力后拉动画跟随）。无视图模型（单元测试）回退相机位置。
2. **方向 = 向视角中间目标点**：相机视线射线（mask=1）命中世界几何的点；瞄天空 → 视向固定距离回退点。方向 = (瞄点 − 原点).normalized()——瞄哪打哪。强度保持固定 `throw_strength`（15.0）。
3. **轨迹一致**：`_launch_params()` 单一来源同时喂预览与 `Grenade.init`；预览积分步长 1/60（=物理帧长，与 RigidBody3D 同构）。
4. **落点清晰**：落地判定 = 首次穿越 y≤0 线性插值（旧"末点投影 y=0"作废——长弧末点浮空错标）；可见点列截至触地点（不画入地下）；落点环 0.3 + 竖直落点线。

## 现状（改动锚点）

- `Weapons/WeaponManager.gd`：`@export var throw_strength: float = 15.0`（行 27 附近）；`_physics_process` THROWING 分支当前 `_trajectory.update_trajectory(_camera.global_position, -_camera.global_transform.basis.z, throw_strength)`（行 272-273）；`_throw_grenade` 当前 `grenade.init(_camera.global_position, -_camera.global_transform.basis.z, throw_strength)`（行 330）。
- `Player/WeaponView.gd`：`setup(manager, move)` 末尾有 `_build_body()`；`view_model`（ViewModel 实例）持有 `current_weapon`（装备的武器根节点；GLB 根 origin == GripRight 标记，网格是子节点 MeshInstance3D）。
- `Weapons/ThrowTrajectory.gd`：常量 `POINT_COUNT := 50`、`STEP_SECONDS := 0.02`、`DASH_RATIO := 0.7`；`update_trajectory` 50 点全量采样、末点投影 y=0；`_render_landing` 环半径 0.25、16 段、防御条件 `points.size() < 2`。

## 全局约束

- 数值：throw_aim_max_dist=**30.0**、throw_aim_fallback_dist=**25.0**（WeaponManager export，非 .tres）；STEP_SECONDS=**1.0/60.0**、POINT_COUNT=**200**、环半径 **0.3**。
- 重力唯一来源 `ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)`。
- 既有测试 `test_throw_release_spawns_grenade_along_camera`（无 WeaponView 接线 → 原点回退相机；测试场景无世界几何 → 瞄点回退 = 视向延伸 → 方向 == -相机 basis.z）**必须保持绿**——不得改该测试。
- 半隐式欧拉积分公式不变（先速度后位置，点在更新前捕获）。

## TDD 步骤（严格顺序）

### RED 1：先写失败测试

1. `test/unit/test_throw_trajectory.gd` **整体重写**为（逐字）：

```gdscript
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
```

2. `test/unit/test_weapon_manager.gd` 末尾追加新节（逐字）：

```gdscript
# ================= 7. M2 手感修复：投掷 launch 单一来源 =================
func test_launch_params_feed_preview_and_grenade_consistently() -> void:
	_with_camera()
	manager = _build_manager([ak, glock, knife, m67])
	await _deploy_m67()
	Input.action_press("fire")
	await wait_physics_frames(2)
	var lp: Dictionary = manager._launch_params()
	var traj := _trajectory()
	assert_eq(traj.points[0], lp["origin"], "预览原点 = 发射原点（单一来源）")
	var v0: Vector3 = (lp["direction"] as Vector3) * manager.throw_strength
	var dt := ThrowTrajectory.STEP_SECONDS
	var g: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
	# 预览第 2 点 = 半隐式欧拉一步（同公式同源重力）
	assert_almost_eq(traj.points[1].x, (lp["origin"] as Vector3).x + v0.x * dt, 0.001, "预览 x 与 launch 一致")
	assert_almost_eq(traj.points[1].y, (lp["origin"] as Vector3).y + v0.y * dt - 0.5 * g * dt * dt, 0.001,
			"预览 y 与 launch 一致（重力同源）")
	assert_almost_eq(traj.points[1].z, (lp["origin"] as Vector3).z + v0.z * dt, 0.001, "预览 z 与 launch 一致")
	Input.action_release("fire")
	await wait_physics_frames(2)
	var grenade := _find_grenade()
	assert_not_null(grenade, "松开后生成真实 Grenade")
	assert_almost_eq(grenade.global_position.x, (lp["origin"] as Vector3).x, 0.3,
			"出手位置 = 发射原点（物理 2 帧位移容差）")
	assert_almost_eq(grenade.global_position.z, (lp["origin"] as Vector3).z, 0.3, "出手位置 z = 发射原点")


func test_weapon_view_throw_origin_returns_grenade_mesh_position() -> void:
	var view := WeaponView.new()
	add_child_autofree(view)
	await wait_physics_frames(1)  # _ready 建 view_model
	view.view_model.equip(load("res://Assets/Models/Weapons/Throwable/Grenade_M67_Echo/Grenade_M67_Echo.glb"))
	var o: Variant = view.get_throw_origin()
	assert_not_null(o, "装备手雷后返回投掷原点")
	var p: Vector3 = o
	assert_lt(p.z, 0.0, "手雷原点在相机前方（-Z，WEAPON_FRAME 取景）")
	assert_gt(p.y, -0.5, "手雷原点在画面下方（-Y，右手持雷位）")
```

运行 GUT 确认新测试**红**（旧常量/旧落地语义/无 `_launch_params` 方法），既有 281/287 测试保持绿（`test_throw_release_spawns_grenade_along_camera` 现在也应该绿——它测的是旧行为，GREEN 阶段回退路径保持该行为）。

### GREEN：实现（精确改动）

**1. `Weapons/WeaponManager.gd`**

- `throw_strength` export 行之后追加：

```gdscript
# M2 手感修复（2026-08-13）：投掷手感——瞄准点射线距离上限（m）/ 瞄天空回退瞄准距离（m）。
# 投掷方向 = 瞄准点 − 手雷原点（瞄哪打哪）；强度保持 throw_strength 固定（CS 固定投速）。
@export var throw_aim_max_dist: float = 30.0
@export var throw_aim_fallback_dist: float = 25.0
```

- `var _melee: MeleeController` 行之后追加：

```gdscript
var _weapon_view: Node = null  # 投掷原点来源（WeaponView.get_throw_origin；null = 回退相机，测试兼容）
```

- `set_head` 函数之后追加：

```gdscript
func set_weapon_view(view: Node) -> void:
	# M2 手感修复（2026-08-13）：投掷原点接线——WeaponView.setup 调用；null 回退相机（单元测试环境）。
	_weapon_view = view


func _throw_origin() -> Vector3:
	if _weapon_view != null and _weapon_view.has_method("get_throw_origin"):
		var p: Variant = _weapon_view.get_throw_origin()
		if p != null:
			return p
	return _camera.global_position if _camera != null else Vector3.ZERO


func _aim_point() -> Vector3:
	# 瞄准点 = 相机视线射线命中世界（mask=1）的点；无命中（瞄天空）→ 视向固定距离回退点。
	# 回退点远离时方向≈视向，行为连续；测试环境无相机 → 沿默认视向兜底。
	if _camera == null:
		return Vector3(0, 1, -throw_aim_fallback_dist)
	var dir := -_camera.global_transform.basis.z
	var from := _camera.global_position
	var ray := PhysicsRayQueryParameters3D.create(from, from + dir * throw_aim_max_dist, 1)
	var hit := _camera.get_world_3d().direct_space_state.intersect_ray(ray)
	if not hit.is_empty():
		return hit["position"]
	return from + dir * throw_aim_fallback_dist


func _launch_params() -> Dictionary:
	# 单一来源：预览与真实投掷共用（同原点/方向/强度 → 轨迹一致——设计 §2.3）。
	var origin := _throw_origin()
	var direction := (_aim_point() - origin).normalized()
	return {"origin": origin, "direction": direction}
```

- `_physics_process` THROWING 分支内 `_trajectory.update_trajectory(_camera.global_position, -_camera.global_transform.basis.z, throw_strength)` 两行替换为：

```gdscript
			elif _trajectory != null and _camera != null:
				var lp := _launch_params()
				_trajectory.update_trajectory(lp["origin"], lp["direction"], throw_strength)
```

- `_throw_grenade` 中 `grenade.init(_camera.global_position, -_camera.global_transform.basis.z, throw_strength)` 行替换为：

```gdscript
	var lp := _launch_params()
	grenade.init(lp["origin"], lp["direction"], throw_strength)
```

**2. `Player/WeaponView.gd`**

- `setup` 末尾 `_build_body()` 行之后追加：

```gdscript
	manager.set_weapon_view(self)  # M2 手感修复：投掷原点接线（get_throw_origin 提供右手雷位置）
```

- `_mount` 函数之后追加：

```gdscript
func get_throw_origin() -> Variant:
	# M2 手感修复（2026-08-13）：投掷原点 = 视图模型手雷网格中心（右手雷处，随蓄力动画实时跟随）。
	# 返回 null = 当前无武器模型（WeaponManager 回退相机）。
	var weapon := view_model.current_weapon
	if weapon == null:
		return null
	for c in weapon.find_children("*", "MeshInstance3D", true, false):
		return c.global_position
	return null
```

**3. `Weapons/ThrowTrajectory.gd`**

- 常量替换为：

```gdscript
const POINT_COUNT := 200  # 预览点列上限（M2 手感修复：50→200；STEP 1/60 → 3.33s 覆盖垂直上抛 3.06s 全弧）
const STEP_SECONDS := 1.0 / 60.0  # 积分步长 = 物理帧长（与 RigidBody3D 积分同构 → 预览≈实际轨迹）
const DASH_RATIO := 0.7  # 虚线：每段画前 70%，留 30% 空隙（更连续醒目）
```

- `update_trajectory` 整体替换为：

```gdscript
# 沿 origin（投掷原点=右手雷处）/direction（向视角目标点）以 strength 初速积分弹道并刷新渲染。
# M2 手感修复（2026-08-13）：落地判定 = 首次穿越 y≤0 线性插值求精确落点；可见点列截至触地点
# （不再画入地下）；旧"末点投影 y=0"作废（长弧时末点浮空错标）。全程不落地兜底 = 末点投影。
func update_trajectory(origin: Vector3, direction: Vector3, strength: float) -> void:
	var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
	var velocity := direction.normalized() * strength
	var position := origin
	points.clear()
	var landed := false
	for i in POINT_COUNT:
		points.append(position)
		velocity.y -= gravity * STEP_SECONDS
		var next := position + velocity * STEP_SECONDS
		if next.y <= 0.0:
			var t := position.y / (position.y - next.y)  # 两已知点线性插值：y=0 处
			landing_point = position.lerp(next, clampf(t, 0.0, 1.0))
			landed = true
			break
		position = next
	if not landed:
		landing_point = position  # 兜底：全程不落地（极端）→ 末点投影（旧行为）
		landing_point.y = 0.0
	_render()
```

- `_render_landing`：防御条件 `if _landing_ring == null or points.size() < 2:` 改为 `if _landing_ring == null or points.is_empty():`；`var radius := 0.25` 改为 `var radius := 0.3`；`_landing_ring.surface_end()` 之前追加：

```gdscript
	# 竖直落点线：可见点列末端 → 落点环（M2 手感修复：落点清晰明了——弧线止于空中点，垂直线指向落点）
	var top := points[points.size() - 1]
	_landing_ring.surface_add_vertex(top)
	_landing_ring.surface_add_vertex(center)
```

### VERIFY（全量）

`cd /Users/elanyi/Projects/Trigger-Echo && godot --headless --path . -s addons/gut/gut_cmdln.gd`
预期：全绿（约 290 测试）。**不得改动 `test_throw_release_spawns_grenade_along_camera`**——回退路径保持其行为。

常见坑：
- `PhysicsRayQueryParameters3D.create` 的 from 在墙内（相机贴墙时）会空命中 → 回退点，行为可接受，不必处理。
- 测试场景中 `_launch_params` 的瞄点射线可能命中其他测试残留几何 → `_with_camera` 测试的场景只有 manager/movement（layer 2），射线 mask=1 不会命中；若红，检查测试文件内是否有额外 StaticBody 残留。
- `points.clear()` 后 `_render` 中 `points.size() - 1` 若 size 0 → 但 update 至少 append 1 点后才可能 break，size≥1 保证。

## 报告格式（最终回复 = 数据，不是给人看的对话）

返回：
- DONE / DONE_WITH_CONCERNS / BLOCKED
- RED 阶段证据（新测试失败摘要）
- 每个文件的改动行号
- 最终全量测试统计行（Tests/Passing/Fails 数）
- 任何规格偏差说明
