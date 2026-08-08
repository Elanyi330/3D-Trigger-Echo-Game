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
