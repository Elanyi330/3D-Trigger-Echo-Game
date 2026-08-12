extends CharacterBody3D
class_name MovementController


@export var gravity_multiplier := 2.0
@export var speed: float = 6.35
# 武器移速倍率（mobility/250，M1 任务2）：WeaponManager 切枪时写入；默认 1.0 = 无武器影响，M0 行为不变
@export var speed_modifier: float = 1.0
# 下蹲速度（CS 固定 2.59，M1 任务3）：下蹲时豁免 speed_modifier，蹲速固定不受武器移速影响
@export var crouch_speed: float = 2.59
@export var acceleration := 8
@export var deceleration := 10
# 注意：空中加速已按 CS 禁用（temp_accel=0），此参数保留为未来 airstrafe 扩展预留
@export_range(0.0, 1.0, 0.05) var air_control := 0.3
@export var jump_height := 7.54
# 自动登台（F1）：on_floor + 水平移动时，高差 ≤ STEP_MAX 视为斜坡直接走上去。
# 取值 0.62 的依据与 CS 偏离说明见 _try_step_up() 头部注释。
const STEP_MAX := 0.62
var direction := Vector3()
var input_axis := Vector2()
# 下蹲状态（M1 任务3）：由 Crouch.gd 进入/退出下蹲时联动设置；下蹲时加速目标用 crouch_speed 固定
var is_crouching: bool = false
# 移动状态（M1 任务8 精度模型）：水平速度 > 0.1 m/s 时 true（_physics_process 更新）——
# WeaponCore 散布惩罚查询（move_spread_multiplier）；不依赖输入轴（斜坡滑行等实际位移也算移动）
var is_moving: bool = false
# Get the gravity from the project settings to be synced with RigidDynamicBody nodes.
@onready var gravity: float = (ProjectSettings.get_setting("physics/3d/default_gravity")
		* gravity_multiplier)


# Called every physics tick. 'delta' is constant
func _physics_process(delta: float) -> void:
	input_axis = Input.get_vector(&"move_back", &"move_forward",
			&"move_left", &"move_right")

	direction_input()
	
	if is_on_floor():
		if Input.is_action_just_pressed(&"jump"):
			velocity.y = jump_height
	else:
		velocity.y -= gravity * delta
	
	accelerate(delta)

	_try_step_up(delta)

	move_and_slide()
	_update_is_moving()


func _update_is_moving() -> void:
	# 水平速度 > 0.1 m/s = 移动中（精度模型散布惩罚查询；阈值参数与 brief 一致）
	var horizontal := Vector2(velocity.x, velocity.z).length()
	is_moving = horizontal > 0.1


func direction_input() -> void:
	direction = Vector3()
	var aim: Basis = get_global_transform().basis
	direction = aim.z * -input_axis.x + aim.x * input_axis.y


func accelerate(delta: float) -> void:
	# Using only the horizontal velocity, interpolate towards the input.
	var temp_vel := velocity
	temp_vel.y = 0

	var temp_accel: float
	# 下蹲豁免 speed_modifier（CS：蹲速固定 2.59，不受武器移速影响——任务2 审查移交约束）；
	# 站立时用 走速 × 武器移速倍率
	var effective_speed: float = crouch_speed if is_crouching else speed * speed_modifier
	var target: Vector3 = direction * effective_speed

	if direction.dot(temp_vel) > 0:
		temp_accel = acceleration
	else:
		temp_accel = deceleration

	if not is_on_floor() or velocity.y > 0.0:
		# 空中（含起跳瞬间）：CS 式——水平速度完全保留（无空气阻力、无空中加速），
		# 跳跃轨迹由起跳时的速度决定（跳上掩体窗口的前提）；起跳帧不衰减
		temp_accel = 0.0

	var accel_weight = clamp(temp_accel * delta, 0.0, 1.0)
	temp_vel = temp_vel.lerp(target, accel_weight)

	velocity.x = temp_vel.x
	velocity.z = temp_vel.z


# ── 自动登台（F1）──────────────────────────────────────────────
# STEP_MAX = 0.62 的依据 + CS 权威值偏离注记：
#   本项目台阶几何为 0.6m 级（AI navmesh 与方块视觉需求），0.62 覆盖全部
#   0.6m 坡道级 / 0.3m 微台阶 / 0.6m 摊阁台阶；0.9m 箱保持只能跳上（设计意图不变）。
#   CS 权威 step-up 18u=0.457m 不适用——它低于本项目最小台阶档 0.6m，照搬会导致
#   楼梯仍需跳跃，违背"一定高低差内视为斜坡自由通行"的需求。
# 机制（仅 is_on_floor 且水平速度 >0.1 时，move_and_slide 之前）：
#   相位1：胶囊抬升 STEP_MAX 后检查前进路径（起点+终点静态重叠查询，exclude 自身、
#          mask=1 Objects）——被挡（高箱 / 低净空顶板）即放弃；
#   相位2：从抬升+前移位置向下垂射线探测落点（STEP_MAX+0.2 余量，法线≈上行才采纳）——
#          落点高于当前脚底才吸附登台（只升不降，走下台阶仍由自然跌落处理）；
#          再用水平射线定位台阶棱线，把胶囊原点放到棱线内侧台面平面上（留在棱线
#          前会因凸棱接触被 move_and_slide 推回台阶下）；
#   空中（非 on_floor）绝不触发——防下落贴墙瞬移上高台。
# Godot 4.7 API 注记：intersect_shape 为静态重叠查询（不沿 motion 扫描、返回无
#   position/normal）；cast_motion 扫掠只返回命中分数且胶囊底半球贴棱时高度偏低。
#   故相位1 用"起点+终点"静态查询覆盖扫掠体（advance ≤0.106 « 胶囊直径 1.0，
#   无隧穿可能），相位2 用 intersect_ray 直接命中台面平面取真值高度。
const STEP_DOWN_EXTRA := 0.2   # 相位2 向下余量
const STEP_MIN_ADVANCE := 0.02  # 最小前移量（极低速时保证相位查询有效）
const STEP_MIN_RISE := 0.01    # 只升不降阈值（防平地抖动/反复触发）
const STEP_CAST_MARGIN := 0.001  # 查询 margin：默认 0.04 会误判（0.62-0.04<0.6 卡台阶顶）
const STEP_FLOOR_NORMAL_Y := 0.7  # ≈45°：只吸附可行走面（与默认 floor_max_angle 一致）
const STEP_EDGE_INSET := 0.05  # 登台后胶囊原点越过台阶棱线的距离（落在台面平面上才稳定）


func _try_step_up(delta: float) -> void:
	# 空中绝不触发；起跳上升帧（velocity.y>0）不触发，避免吞掉跳跃冲量
	if not is_on_floor() or velocity.y > 0.0:
		return
	var hvel := Vector2(velocity.x, velocity.z)
	if hvel.length() <= 0.1:
		return
	var col := _find_collision_shape()
	if col == null:
		return
	var capsule := col.shape as CapsuleShape3D
	if capsule == null:
		return

	var space_state := get_world_3d().direct_space_state
	var dir := Vector3(hvel.x, 0.0, hvel.y).normalized()
	var advance := maxf(hvel.length() * delta, STEP_MIN_ADVANCE)
	var half_height: float = capsule.height * 0.5
	# shape 查询变换 = 真实胶囊世界变换（含 CollisionShape3D 本地偏移，
	# 与 Crouch.gd 动态改胶囊高度/中心的联动保持一致）
	var capsule_xform := global_transform * col.transform
	var feet_y: float = capsule_xform.origin.y - half_height
	var raised := capsule_xform
	raised.origin += Vector3.UP * STEP_MAX

	# 相位1：抬升后路径被挡（高箱/低净空顶板）即放弃
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = capsule
	params.margin = STEP_CAST_MARGIN
	params.collision_mask = 1  # Objects 层（地形/台阶/箱体）
	params.exclude = [get_rid()]
	params.transform = raised
	if not space_state.intersect_shape(params).is_empty():
		return
	var raised_fwd := raised
	raised_fwd.origin += dir * advance
	params.transform = raised_fwd
	if not space_state.intersect_shape(params).is_empty():
		return

	# 相位2：垂射线探测前方落点高度。用射线而非胶囊扫掠：胶囊底半球扫过台阶
	# 棱线时只能得到"曲面贴棱"的偏低高度，射线直接命中台面平面真值。
	# 探针 = 抬升+前移后的胶囊原点与前进方向满半径处（越过台阶棱线）。
	var probe_top_y: float = raised_fwd.origin.y - half_height + 0.001
	var ray_len: float = STEP_MAX + STEP_DOWN_EXTRA
	var best_y := -INF
	var probe_offsets: Array[Vector3] = [Vector3.ZERO, dir * capsule.radius]
	for offset in probe_offsets:
		var rp := PhysicsRayQueryParameters3D.new()
		var origin: Vector3 = raised_fwd.origin + offset
		origin.y = probe_top_y
		rp.from = origin
		rp.to = origin + Vector3.DOWN * ray_len
		rp.collision_mask = 1
		rp.exclude = [get_rid()]
		var hit := space_state.intersect_ray(rp)
		if not hit.is_empty() and hit.normal.y > STEP_FLOOR_NORMAL_Y \
				and hit.position.y > best_y:
			best_y = hit.position.y
	if best_y == -INF:
		return
	# 只升不降：走下台阶/平地不干扰
	if best_y - feet_y <= STEP_MIN_RISE:
		return

	# 定位台阶棱线：在落点高度略下方水平前射命中竖面。胶囊原点必须越过棱线
	# 落在台面平面上——留在棱线前会因凸棱接触被 move_and_slide 推回台阶下。
	var target_origin: Vector3
	var edge_rp := PhysicsRayQueryParameters3D.new()
	var edge_from := raised_fwd.origin
	edge_from.y = best_y - 0.05
	edge_rp.from = edge_from
	edge_rp.to = edge_from + dir * 1.5
	edge_rp.collision_mask = 1
	edge_rp.exclude = [get_rid()]
	var edge_hit := space_state.intersect_ray(edge_rp)
	if edge_hit.is_empty():
		# 无竖面（坡道等）：直接落到命中面
		target_origin = Vector3(raised_fwd.origin.x, best_y + half_height,
				raised_fwd.origin.z)
	else:
		var edge_point: Vector3 = edge_hit.position + dir * STEP_EDGE_INSET
		target_origin = Vector3(edge_point.x, best_y + half_height, edge_point.z)

	# 嵌体防护：目标位与任何几何重叠则放弃（如玩家与台阶间夹有矮墙）。
	# 上抬 0.02 再查：目标位脚底恰落在台面上（0 距接触会被 margin 误判为重叠）。
	var target_xform := capsule_xform
	target_xform.origin = target_origin + Vector3.UP * 0.02
	params.transform = target_xform
	if not space_state.intersect_shape(params).is_empty():
		return

	global_position += target_origin - capsule_xform.origin
	velocity.y = 0.0


func _find_collision_shape() -> CollisionShape3D:
	for child in get_children():
		if child is CollisionShape3D:
			return child
	return null
