extends Node3D


@export_node_path("Camera3D") var cam_path := NodePath("Camera")
@onready var cam: Camera3D = get_node(cam_path)

@export var mouse_sensitivity := 2.0
@export var y_limit := 90.0
# ── M1 任务15：双层 lerp 相机后坐力（Jeh3no 22 行照搬，替代任务 3 单层 recoil_offset）──
# 机理：开火时 target_rotation 瞬间抬升（add_recoil），base_rotation_speed（5.0）把
# target 回摆归零，current_rotation 以 target_rotation_speed（12.0）追击 target——
# 快抬-慢回+抖动，永不突变。施加点与鼠标视角解耦（仅叠加 rotation，不改 rot）。
# 每发幅度（rad）唯一来源 WeaponResource.recoil_val（.tres：AK/Glock 参数化）。
@export var base_rotation_speed: float = 5.0  # target → 0 回摆速度（1/s）
@export var target_rotation_speed: float = 12.0  # current → target 追击速度（1/s）
var mouse_axis := Vector2()
var rot := Vector3()
var target_rotation := Vector3.ZERO  # 回摆层（开火瞬时抬升 + Y/Z 抖动）
var current_rotation := Vector3.ZERO  # 追击层（实际叠加到视角）

# ── M1 任务3：开镜接口 ──
var ads_active: bool = false
var ads_multiplier: float = 1.0

# 原始灵敏度（_ready ÷1000 前）与原始 FOV——开镜按比例缩放/恢复用
var _base_sensitivity: float = 0.0
var _base_fov: float = 0.0

# M1.5：开镜 FOV/灵敏度平滑插值（修复"开关镜突变不流畅"）——set_ads 只设目标值，
# 物理帧按 ads_zoom_speed 指数逼近（与 WeaponView 举枪动画同节奏）。
@export var ads_zoom_speed: float = 14.0
var _fov_target: float = 0.0
var _sens_target: float = 0.0


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	_base_sensitivity = mouse_sensitivity  # 保留原始导出值（开镜按比例缩放/恢复）
	mouse_sensitivity = mouse_sensitivity / 1000
	y_limit = deg_to_rad(y_limit)
	_base_fov = cam.fov  # 记录默认 FOV（开镜恢复基准）
	_fov_target = cam.fov
	_sens_target = mouse_sensitivity


# Called when there is an input event
func _input(event: InputEvent) -> void:
	# Mouse look (only if the mouse is captured).
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		mouse_axis = event.relative
		camera_rotation()


# Called every physics tick. 'delta' is constant
func _physics_process(delta: float) -> void:
	# M1.5：FOV/灵敏度平滑逼近目标（开镜/关镜渐变，非突变）；接近后吸附到位（指数 lerp 不渐近悬挂）
	if cam.fov != _fov_target:
		cam.fov = lerpf(cam.fov, _fov_target, ads_zoom_speed * delta)
		if absf(cam.fov - _fov_target) < 0.005:
			cam.fov = _fov_target
	if mouse_sensitivity != _sens_target:
		mouse_sensitivity = lerpf(mouse_sensitivity, _sens_target, ads_zoom_speed * delta)
		if absf(mouse_sensitivity - _sens_target) < 0.000001:
			mouse_sensitivity = _sens_target
	# M1 任务15：双层 lerp（Jeh3no）：target 回摆 → current 追击 → 叠加到现有视角
	target_rotation = target_rotation.lerp(Vector3.ZERO, base_rotation_speed * delta)
	current_rotation = current_rotation.lerp(target_rotation, target_rotation_speed * delta)
	_apply_view_rotation()

	var joystick_axis := Input.get_vector(&"look_left", &"look_right",
			&"look_down", &"look_up")

	if joystick_axis != Vector2.ZERO:
		mouse_axis = joystick_axis * 1000.0 * delta
		camera_rotation()


func camera_rotation() -> void:
	# Horizontal mouse look.
	rot.y -= mouse_axis.x * mouse_sensitivity
	# Vertical mouse look.
	rot.x = clamp(rot.x - mouse_axis.y * mouse_sensitivity, -y_limit, y_limit)

	get_owner().rotation.y = rot.y
	_apply_view_rotation()


func _apply_view_rotation() -> void:
	# 后坐力叠加（M1 任务15 双层）：视角 = 鼠标 rot + current_rotation（X 上抬 + Y/Z 抖动），
	# 在 M0 视角输出上纯加法叠加（不重构原逻辑）
	rotation.x = rot.x + current_rotation.x
	rotation.y = current_rotation.y
	rotation.z = current_rotation.z


# 叠加后坐力（rad/发，Jeh3no 照搬）：target_rotation 瞬时抬升 x + Y/Z 随机抖动；
# 由 _physics_process 双层 lerp 回摆归零。每发幅度唯一来源 WeaponResource.recoil_val（.tres）
func add_recoil(recoil_value: Vector3) -> void:
	target_rotation += Vector3(recoil_value.x,
			randf_range(-recoil_value.y, recoil_value.y),
			randf_range(-recoil_value.z, recoil_value.z))


# 开镜/关镜（CS 式机瞄）：设 FOV/灵敏度目标值，由 _physics_process 平滑插值逼近（M1.5 修复突变）
func set_ads(active: bool, multiplier: float) -> void:
	if active:
		# 防护（任务 6 收尾，任务 3 审查移交）：错误数据源 inf/NaN/负值 → 夹取 1.0（防 FOV 除零/NaN 缩放）
		if not is_finite(multiplier) or multiplier < 1.0:
			multiplier = 1.0
		ads_multiplier = multiplier  # 仅 active 写入（关镜不覆盖记录值）
		if not ads_active and _base_fov <= 0.0:
			_base_fov = cam.fov  # 首次进入开镜时记录原始 FOV（关镜恢复用）
	ads_active = active
	if ads_active:
		_fov_target = _base_fov / ads_multiplier
		_sens_target = _base_sensitivity / 1000.0 / ads_multiplier
	else:
		if _base_fov > 0.0:
			_fov_target = _base_fov  # 防御：未开镜过就关镜（不应发生）不改目标
		_sens_target = _base_sensitivity / 1000.0
