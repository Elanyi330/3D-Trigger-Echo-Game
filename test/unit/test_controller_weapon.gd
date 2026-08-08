# test/unit/test_controller_weapon.gd
# M1 任务3：MovementController speed_modifier（含下蹲豁免）+ Head add_recoil/set_ads（TDD）
# 阶段：RED（先跑失败）→ GREEN
# 行为契约（计划 §5 任务3 + §4 全局约束）：
#   站立：水平收敛速度 = speed × speed_modifier（AK 0.86 → 6.35×0.86=5.46）
#   下蹲：蹲速固定 2.59，豁免 speed_modifier（错误实现会收敛到 2.59×0.86≈2.23）
#   空中：CS 无空中加速，水平速度完全保留，speed_modifier 不生效（M0 已实现，回归守卫）
#   Head.add_recoil：recoil_offset 累计（度），相机 rotation.x 叠加 deg_to_rad(recoil_offset)
#   Head 恢复：recoil_offset 按 recoil_recovery_speed（°/s）向 0 移动
#   Head.set_ads：开镜 FOV ÷multiplier + 灵敏度 ÷multiplier；关镜恢复原值
extends GutTest

var controller: MovementController


func before_each() -> void:
	controller = MovementController.new()
	# 镜像生产场景（MovementController.tscn）的碰撞配置（同 test_controller.gd）
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
	Input.action_release("sprint")


# ── MovementController：speed_modifier ──

# 用例 1：站立时水平收敛速度 = speed × speed_modifier（AK mobility 215u → 0.86）
func test_speed_modifier_scales_walk_speed() -> void:
	_make_floor()
	controller.speed_modifier = 0.86
	await wait_physics_frames(25)
	assert_true(controller.is_on_floor(), "前置：控制器应落在地面上")
	Input.action_press("move_forward")
	await wait_physics_frames(60)
	assert_almost_eq(controller.velocity.z, -6.35 * 0.86, 0.05,
			"speed_modifier=0.86 时收敛速度 ≈ 6.35×0.86 = 5.46（CS 持 AK 移速）")


# 用例 2：下蹲豁免 speed_modifier——蹲速固定 2.59（任务 2 审查移交的关键约束）
func test_crouch_speed_ignores_speed_modifier() -> void:
	_make_floor()
	controller.speed_modifier = 0.86
	await wait_physics_frames(25)
	assert_true(controller.is_on_floor(), "前置：控制器应落在地面上")
	controller.is_crouching = true  # 模拟 Crouch.gd 联动（真实联动见用例 4）
	Input.action_press("move_forward")
	await wait_physics_frames(60)
	assert_almost_eq(controller.velocity.z, -2.59, 0.05,
			"下蹲速度固定 2.59，不受 speed_modifier=0.86 影响（错误实现会收敛到 ≈2.23）")


# 用例 3：空中水平速度完全保留，speed_modifier 不生效（CS 无空中加速；M0 已实现，回归守卫）
func test_airborne_speed_not_scaled_by_speed_modifier() -> void:
	_make_floor()
	await wait_physics_frames(25)
	assert_true(controller.is_on_floor(), "前置：控制器应落在地面上")
	Input.action_press("move_forward")
	await wait_physics_frames(60)
	assert_almost_eq(controller.velocity.z, -6.35, 0.02, "前置：地面收敛满速 -6.35")
	Input.action_press("jump")
	await wait_physics_frames(5)  # 起跳上升段
	assert_gt(controller.velocity.y, 3.0, "前置：应在上升段")
	controller.speed_modifier = 0.5  # 空中改倍率：不应生效
	await wait_physics_frames(10)
	assert_almost_eq(controller.velocity.z, -6.35, 0.02,
			"空中水平速度完全保留，speed_modifier 不生效（CS 无空中加速）")


# 用例 4：Crouch.gd 联动——下蹲时设置 controller.is_crouching（真实 Player.tscn 集成）
func test_crouch_sets_controller_is_crouching() -> void:
	var scene: PackedScene = load("res://Player/Player.tscn")
	var player: Node = scene.instantiate()
	add_child_autofree(player)
	var ctrl: MovementController = player as MovementController
	await wait_physics_frames(20)
	Input.action_press("sprint")
	await wait_physics_frames(10)
	assert_true(ctrl.is_crouching, "按住 sprint 时 Crouch 应联动 controller.is_crouching=true")
	Input.action_release("sprint")
	await wait_physics_frames(10)
	assert_false(ctrl.is_crouching, "松开 sprint 后 controller.is_crouching=false")


# ── Head：add_recoil（双层 lerp 后坐力，M1 任务15，Jeh3no 22 行照搬）──

# 用例 5：add_recoil 抬升 target_rotation，current_rotation 追击后叠加到相机
func test_add_recoil_raises_target_then_camera() -> void:
	var head := _build_head()
	head.add_recoil(Vector3(0.06, 0.0, 0.0))  # 无 Y/Z 抖动分量：确定性断言
	assert_almost_eq(head.target_rotation.x, 0.06, 0.0001,
			"add_recoil → target_rotation.x 瞬时抬升 0.06 rad（快抬）")
	assert_almost_eq(head.current_rotation.x, 0.0, 0.0001,
			"current_rotation 初始为 0（下一物理帧才开始追击）")
	await wait_physics_frames(1)
	assert_gt(head.current_rotation.x, 0.0, "current_rotation 追击抬升")
	head.camera_rotation()  # 无鼠标输入，仅叠加后坐力
	assert_gt(head.rotation.x, 0.0, "相机 rotation.x = 鼠标 rot + current_rotation")


# 用例 6：多次 add_recoil 累计到 target_rotation
func test_add_recoil_accumulates_in_target() -> void:
	var head := _build_head()
	head.add_recoil(Vector3(0.06, 0.0, 0.0))
	head.add_recoil(Vector3(0.06, 0.0, 0.0))
	assert_almost_eq(head.target_rotation.x, 0.12, 0.0001, "两次 add_recoil 累计 0.12 rad")


# 用例 7：双层回摆——target 回零 + current 追击归零（快抬-慢回，不突变）
func test_recoil_recovers_to_zero_over_time() -> void:
	var head := _build_head()
	head.add_recoil(Vector3(0.06, 0.0, 0.0))
	await wait_physics_frames(90)  # 1.5s：base 5.0/s 指数回摆 → 残余 < 0.001
	assert_almost_eq(head.target_rotation.x, 0.0, 0.001, "target_rotation 回摆归零")
	assert_almost_eq(head.current_rotation.x, 0.0, 0.001, "current_rotation 归零")


# 用例 8：Y/Z 随机抖动（Jeh3no：randf_range(-v, v)）——多次采样都在幅度范围内
func test_add_recoil_y_z_jitter_within_bounds() -> void:
	var head := _build_head()
	for i in 20:
		head.target_rotation = Vector3.ZERO
		head.add_recoil(Vector3(0.06, 0.02, 0.02))
		assert_between(head.target_rotation.y, -0.02, 0.02, "Y 抖动在 ±0.02 内")
		assert_between(head.target_rotation.z, -0.02, 0.02, "Z 抖动在 ±0.02 内")
		assert_almost_eq(head.target_rotation.x, 0.06, 0.0001, "X 抬升确定（无抖动）")


# 用例 9：recoil_val .tres 参数化（AK/Glock 数值唯一来源资源，近战默认 ZERO）
func test_recoil_val_parameterized_in_tres() -> void:
	var ak: WeaponResource = load("res://Weapons/weapon_ak47.tres")
	assert_eq(ak.recoil_val, Vector3(0.06, 0.02, 0.02), "AK recoil_val = (0.06, 0.02, 0.02)")
	var glock: WeaponResource = load("res://Weapons/weapon_glock18.tres")
	assert_eq(glock.recoil_val, Vector3(0.04, 0.015, 0.015),
			"Glock recoil_val = (0.04, 0.015, 0.015)")
	var knife: WeaponResource = load("res://Weapons/weapon_knife.tres")
	assert_eq(knife.recoil_val, Vector3.ZERO, "近战无相机后坐力（默认 ZERO）")


# ── Head：set_ads（开镜）──

# 用例 8：开镜 FOV ÷multiplier + 灵敏度 ÷multiplier；关镜恢复原值
func test_set_ads_scales_fov_and_sensitivity() -> void:
	var head := _build_head()
	var cam: Camera3D = head.get_node("Camera")
	cam.fov = 75.0
	head.set_ads(true, 1.5)
	assert_true(head.ads_active, "开镜后 ads_active = true")
	assert_almost_eq(head.ads_multiplier, 1.5, 0.0001, "ads_multiplier 记录 1.5")
	assert_almost_eq(cam.fov, 75.0 / 1.5, 0.001, "开镜 FOV = fov ÷multiplier（75→50）")
	assert_almost_eq(head.mouse_sensitivity, 2.0 / 1000.0 / 1.5, 0.000001,
			"开镜灵敏度 = base（2.0÷1000）÷ 1.5")
	head.set_ads(false, 1.5)
	assert_false(head.ads_active, "关镜后 ads_active = false")
	assert_almost_eq(cam.fov, 75.0, 0.001, "关镜恢复 FOV 75")
	assert_almost_eq(head.mouse_sensitivity, 2.0 / 1000.0, 0.000001, "关镜恢复灵敏度")


# 用例 9：multiplier=1.0（无开镜武器，如 Glock 默认）FOV 不变
func test_set_ads_no_multiplier_keeps_fov() -> void:
	var head := _build_head()
	var cam: Camera3D = head.get_node("Camera")
	cam.fov = 75.0
	head.set_ads(true, 1.0)
	assert_almost_eq(cam.fov, 75.0, 0.001, "multiplier=1.0（无开镜武器）FOV 不变")


# 用例 10：multiplier 防护——inf/NaN/负向缩放夹取到 1.0（任务 6 审查收尾：防错误数据源 FOV 除零/NaN）
func test_set_ads_guards_invalid_multiplier() -> void:
	var head := _build_head()
	var cam: Camera3D = head.get_node("Camera")
	cam.fov = 75.0
	head.set_ads(true, INF)
	assert_almost_eq(cam.fov, 75.0, 0.001, "multiplier=inf → 夹取 1.0（FOV 不变，防除零）")
	assert_almost_eq(head.ads_multiplier, 1.0, 0.0001, "inf 夹取为 1.0")
	head.set_ads(false, INF)
	head.set_ads(true, NAN)
	assert_almost_eq(cam.fov, 75.0, 0.001, "multiplier=NaN → 夹取 1.0（is_finite 防护）")
	assert_almost_eq(head.ads_multiplier, 1.0, 0.0001, "NaN 夹取为 1.0")
	head.set_ads(false, NAN)
	head.set_ads(true, 0.5)
	assert_almost_eq(cam.fov, 75.0, 0.001, "multiplier=0.5（负向缩放）→ 夹取 1.0")


# ── 测试辅助 ──

# 代码创建物理地面（StaticBody3D + BoxShape3D，Objects 层=1，顶面 y=0；同 test_controller.gd）
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


# 手动构建 Head（Head.gd + Camera3D 子节点）：
#   Head.gd 无 class_name → set_script 加载；@onready cam 按 cam_path("Camera") 解析
#   camera_rotation() 写 get_owner().rotation.y——运行时节点 owner 为空会崩，手动指向容器节点
func _build_head() -> Node3D:
	var head := Node3D.new()
	head.name = "Head"
	var cam := Camera3D.new()
	cam.name = "Camera"
	cam.fov = 75.0
	head.add_child(cam)
	head.set_script(load("res://Player/Head.gd"))
	var owner_node := Node3D.new()
	owner_node.add_child(head)
	head.owner = owner_node
	add_child_autofree(owner_node)
	return head
