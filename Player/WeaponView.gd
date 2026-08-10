# Player/WeaponView.gd
# M1.5 表现层（替代旧 WeaponAnchor）：视图模型 + 程序化动画。
#
# 手-武器协调由 ViewModel 构造保证（手放 GripRight/GripLeft 标记）；本层只做"手感"：
# 把整个视图模型（武器+手臂）作为刚体做程序化动画——kickback/sway/bob/reload/swing/throw/deploy，
# 数学参考旧 WeaponAnchor（Dragon20C 三通道理念，自研实现）。
# 枪口火光/曳光起点 = 武器 _Muzzle 标记（资产内置，非魔数）。
# 逻辑（射击/换弹/切枪/伤害）全在 WeaponManager/WeaponCore——本层纯视觉，订阅信号驱动。
class_name WeaponView
extends Node3D

const ViewModel := preload("res://Assets/Viewmodel/ViewModel.gd")

# ---- kickback（开火后坐，视图模型推近+上抬，线性回弹）----
@export var kick_distance := 0.03
@export var kick_up := 0.015
@export var kick_pitch := 0.03
@export var kick_recover := 6.0
# ---- sway（鼠标滞后）----
@export var sway_amount := 0.004
@export var sway_speed := 8.0
@export var max_sway := Vector3(0.012, 0.008, 0.008)
# ---- bob（移动步幅）----
@export var bob_freq := 1.0
@export var bob_amp := 0.012
@export var bob_speed := 1.4
# ---- reload（换弹下沉+内倾，CS 多相位；内倾+偏航展示弹匣侧，姿态可读）----
@export var reload_drop := 0.09
@export var reload_tilt := 0.15
@export var reload_cant := 0.7
@export var reload_yaw := 0.45
# ---- swing（近战挥击，CS 风格；幅度大——中段刀刃横扫过画面中心）----
@export var swing_sweep := 0.26
@export var swing_roll := 1.15
@export var swing_stab_push := 0.16
# ---- throw（手雷后拉）----
@export var throw_pull := 0.5
# ---- ADS 开镜动画（M1.5：平滑举枪到眼前正中 + 眼看瞄具；步枪模板，狙击枪沿用）----
@export var ads_speed := 9.0  # 开镜位置/旋转插值速率（越大到位越快；CS 开镜干脆利落 ~0.1s）
@export var ads_sway_reduce := 0.75  # 开镜时 sway/bob 减弱比例（举镜更稳）

var view_model: ViewModel
var movement: MovementController

var _manager: WeaponManager
var _kick := Vector3.ZERO
var _kick_rot := Vector3.ZERO
var _sway := Vector3.ZERO
var _sway_rot := Vector3.ZERO
var _bob := Vector3.ZERO
var _bob_phase := 0.0
var _reload_t := -1.0   # <0 = 不在换弹
var _reload_dur := 0.0
var _swing_t := -1.0
var _swing_dur := 0.0
var _swing_heavy := false
var _throw_t := -1.0
var _deploy_t := 0.0
var _ads_blend := 0.0  # 开镜进度 0=腰射 1=举镜（M1.5 平滑插值）
var _ads_target := 0.0
var _mouse := Vector2.ZERO
var _muzzle_flash: OmniLight3D
var _flash_t := 0.0


func _ready() -> void:
	view_model = ViewModel.new()
	view_model.name = "ViewModel"
	add_child(view_model)
	_muzzle_flash = OmniLight3D.new()
	_muzzle_flash.light_color = Color(1.0, 0.7, 0.3)
	_muzzle_flash.light_energy = 0.0
	_muzzle_flash.omni_range = 4.0
	_muzzle_flash.visible = false
	add_child(_muzzle_flash)


func setup(manager: WeaponManager, move: MovementController) -> void:
	_manager = manager
	movement = move
	manager.weapon_switched.connect(_on_switched)
	manager.throw_primed.connect(_on_throw_primed)
	manager.throw_released.connect(_on_throw_released)
	manager.aim_toggled.connect(_on_aim_toggled)  # M1.5：开镜动画（举枪到眼前 + FOV 由 Head 平滑）
	_mount(manager.get_current_slot())
	_build_body()  # 下半身自见（低头可见自己身体——相机挂在角色眼睛上）


# 下半身自见：与 Soldier_Echo 同比例的骨盆/双腿/双脚，挂玩家（随 yaw、不随俯仰）。
# 低头时看到自己的身体——第一人称与角色建模一致、不割裂。
# M2：补全上半身（骨盆/躯干/头）——玩家低头可见完整身体，影子完整，AI 命中判定有据。
func _build_body() -> void:
	if movement == null:
		return
	var body := Node3D.new()
	body.name = "FirstPersonBody"
	body.position = Vector3(0, -0.915, 0)  # 玩家 origin（胶囊中心）→ 脚底贴地
	# 虚化材质（用户：低头看自己身体半透明，不挡视野）
	var uniform := _ghost_body_mat(Color(0.35, 0.48, 0.32))
	var uniform_dark := _ghost_body_mat(Color(0.245, 0.336, 0.224))
	var skin := _ghost_body_mat(Color(0.85, 0.68, 0.55))
	var boot := _ghost_body_mat(Color(0.15, 0.13, 0.12))
	# 双腿（±X）+ 双脚（脚尖朝 -Z 前方）
	for sx in [0.11, -0.11]:
		_body_box(body, Vector3(sx, 0.67, 0), Vector3(0.16, 0.38, 0.18), uniform_dark)  # 大腿
		_body_box(body, Vector3(sx, 0.28, 0), Vector3(0.14, 0.40, 0.16), uniform)       # 小腿
		_body_box(body, Vector3(sx, 0.04, -0.04), Vector3(0.14, 0.08, 0.26), boot)      # 脚（尖朝前）
	# 骨盆（0.86-1.00 高度带）
	_body_box(body, Vector3(0, 0.93, 0), Vector3(0.40, 0.14, 0.24), uniform_dark)
	# 躯干（1.00-1.46 高度带，胸/腹）——相机在眼位 1.63，低头可见躯干
	_body_box(body, Vector3(0, 1.23, 0), Vector3(0.42, 0.46, 0.24), uniform)
	# 头（1.52-1.78 高度带）——低头可见头顶/额头
	_body_box(body, Vector3(0, 1.65, 0.02), Vector3(0.26, 0.26, 0.26), skin)
	movement.add_child(body)


func _body_box(parent: Node3D, center: Vector3, size: Vector3, mat: Material) -> void:
	var bm := BoxMesh.new()
	bm.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = bm
	mi.material_override = mat
	mi.position = center
	parent.add_child(mi)


func _body_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.8
	return m


# 虚化身体材质（用户：低头看自己躯干/脚应半透明，方便看路不挡视野）
func _ghost_body_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	var ghost := c
	ghost.a = 0.35  # 半透明 35%
	m.albedo_color = ghost
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.8
	return m


func _on_switched(slot: int) -> void:
	_mount(slot)
	_deploy_t = 0.18  # 新武器滑入


func _mount(slot: int) -> void:
	var scene := _manager.get_view_model(slot)
	if scene == null:
		return
	var w := view_model.equip(scene)
	_wire_core(slot)
	_position_flash(w)


func _wire_core(slot: int) -> void:
	var core := _manager.get_core(slot)
	if core == null:
		return
	if not core.shot_fired.is_connected(_on_shot_fired):
		core.shot_fired.connect(_on_shot_fired)
	if not core.reload_started.is_connected(_on_reload_started):
		core.reload_started.connect(_on_reload_started)
	var melee := _manager.get_melee_controller()
	if melee != null and not melee.melee_swung.is_connected(_on_melee_swung):
		melee.melee_swung.connect(_on_melee_swung)


func _position_flash(weapon: Node3D) -> void:
	var muzzle := ViewModel.find_marker(weapon, "_Muzzle")
	_muzzle_flash.get_parent().remove_child(_muzzle_flash)
	if muzzle:
		muzzle.add_child(_muzzle_flash)
		_muzzle_flash.position = Vector3.ZERO
	else:
		add_child(_muzzle_flash)
		_muzzle_flash.position = Vector3(0.2, -0.2, -0.6)


func _on_shot_fired(_ammo: int) -> void:
	_kick = Vector3(0, kick_up, kick_distance)
	_kick_rot = Vector3(kick_pitch, 0, 0)
	_flash_t = 0.05
	_muzzle_flash.visible = true
	_muzzle_flash.light_energy = 3.0


func _on_reload_started() -> void:
	var res := _manager.get_resource(_manager.get_current_slot())
	_reload_dur = res.reload_time if res else 1.0
	_reload_t = 0.0


func _on_melee_swung(heavy: bool) -> void:
	_swing_heavy = heavy
	var res := _manager.get_resource(_manager.get_current_slot())
	if heavy:
		_swing_dur = res.melee_heavy_time if res and res.melee_heavy_time > 0.0 else 1.0
	else:
		_swing_dur = res.melee_light_time if res and res.melee_light_time > 0.0 else 0.4
	_swing_t = 0.0


func _on_throw_primed() -> void:
	_throw_t = 0.0


func _on_throw_released() -> void:
	_throw_t = -1.0


func _on_aim_toggled(active: bool) -> void:
	_ads_target = 1.0 if active else 0.0


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_mouse = -event.relative * sway_amount


func _physics_process(delta: float) -> void:
	_tick_kick(delta)
	_tick_sway(delta)
	_tick_bob(delta)
	_tick_reload(delta)
	_tick_swing(delta)
	_tick_throw(delta)
	_tick_deploy(delta)
	_tick_flash(delta)
	_tick_ads(delta)
	_apply()


func _tick_kick(d: float) -> void:
	_kick = _kick.move_toward(Vector3.ZERO, kick_recover * d * 0.03)
	_kick_rot = _kick_rot.move_toward(Vector3.ZERO, kick_recover * d * 0.04)


func _tick_sway(d: float) -> void:
	_mouse = _mouse.move_toward(Vector2.ZERO, sway_speed * d * 0.1)
	var tp := Vector3(_mouse.x, _mouse.y, 0).clamp(-max_sway, max_sway)
	var tr := Vector3(_mouse.y, _mouse.x, _mouse.x).clamp(-max_sway * 2.0, max_sway * 2.0)
	_sway = _sway.lerp(tp, sway_speed * d)
	_sway_rot = _sway_rot.lerp(tr, sway_speed * d)


func _tick_bob(d: float) -> void:
	var moving := false
	var spd := 6.35
	if movement and is_instance_valid(movement):
		moving = movement.is_moving
		spd = Vector2(movement.velocity.x, movement.velocity.z).length()
	if moving:
		_bob_phase += spd * bob_speed * d
	var target := Vector3.ZERO
	if moving:
		target = Vector3(cos(_bob_phase * bob_freq * 0.5) * bob_amp * 0.5,
				sin(_bob_phase * bob_freq) * bob_amp, 0)
	_bob = _bob.lerp(target, 12.0 * d)


func _tick_reload(d: float) -> void:
	if _reload_t < 0.0:
		return
	_reload_t += d
	if _reload_t >= _reload_dur:
		_reload_t = -1.0


func _tick_swing(d: float) -> void:
	if _swing_t < 0.0:
		return
	_swing_t += d
	if _swing_t >= _swing_dur:
		_swing_t = -1.0


func _tick_throw(d: float) -> void:
	if _throw_t < 0.0:
		return
	_throw_t += d  # 后拉保持直到 throw_released


func _tick_deploy(d: float) -> void:
	if _deploy_t > 0.0:
		_deploy_t = maxf(0.0, _deploy_t - d)


func _tick_flash(d: float) -> void:
	if _flash_t > 0.0:
		_flash_t -= d
		_muzzle_flash.light_energy = maxf(0.0, _flash_t / 0.05 * 3.0)
		if _flash_t <= 0.0:
			_muzzle_flash.visible = false


func _tick_ads(d: float) -> void:
	_ads_blend = move_toward(_ads_blend, _ads_target, ads_speed * d)


func _apply() -> void:
	var ads_t := _smoothstep(_ads_blend)  # 缓动开镜进度（0=腰射 1=举镜）
	var stead := 1.0 - ads_t * ads_sway_reduce  # 开镜时 sway/bob 减弱（举镜更稳）
	# —— 相机锁定的微妙通道（作用于整个 view_model：武器+手臂一起微动）——
	var pos := _kick + (_sway + _bob) * stead
	var rot := _kick_rot + _sway_rot * stead
	# deploy 滑入（整体）
	if _deploy_t > 0.0:
		var t := _deploy_t / 0.18
		pos += Vector3(0, -0.10 * t * t, 0)
		rot += Vector3(-0.3 * t * t, 0, 0)
	view_model.position = pos
	view_model.rotation = rot

	# —— 武器动作通道（只作用于 weapon_mount；手臂每帧动态追踪握把，肩部不入镜）——
	var wpos := Vector3.ZERO
	var wrot := Vector3.ZERO
	# reload：CS 风格（下沉+内倾，多相位；含后段拉枪栓小动作）
	if _reload_t >= 0.0 and _reload_dur > 0.0:
		var t := clampf(_reload_t / _reload_dur, 0.0, 1.0)
		var env := _reload_env(t)
		var rack := _reload_rack_env(t)
		wpos += Vector3(0.03 * env, -reload_drop * env, 0.03 * env + rack * 0.04)
		wrot += Vector3(reload_tilt * env, reload_yaw * env, -reload_cant * env)
	# swing：CS 近战（轻击斜挥 / 重刺前送），时序取自 .tres melee_*_time
	if _swing_t >= 0.0 and _swing_dur > 0.0:
		var t := clampf(_swing_t / _swing_dur, 0.0, 1.0)
		if _swing_heavy:
			# 重刺：蓄力(0-0.3) → 前刺(0.3-0.5，0.5 相位满伸=接触=伤害帧) → 收势(0.5-1.0)。
			# 接触相位 0.5 = hit_delay(0.5s)/heavy_time(1.0s)——判定与动画同步（CS：重击 1s 动画，伤害在刀落下时刻）。
			var windup := _smoothstep(clampf(t / 0.3, 0.0, 1.0)) * (1.0 - _smoothstep(clampf((t - 0.3) / 0.05, 0.0, 1.0)))
			var thrust := _smoothstep(clampf((t - 0.3) / 0.2, 0.0, 1.0)) * (1.0 - _smoothstep(clampf((t - 0.5) / 0.5, 0.0, 1.0)))
			wpos += Vector3(0.03 * windup, 0.01 * windup, 0.07 * windup - swing_stab_push * thrust)
			wrot += Vector3(-0.25 * windup + 0.2 * thrust, 0.1 * windup, 0.0)
		else:
			# 轻击斜挥：右上蓄(0-0.25) → 横扫左下过中心(0.25-0.5) → 回位(0.5-1.0)
			var windup := _smoothstep(clampf(t / 0.25, 0.0, 1.0)) * (1.0 - _smoothstep(clampf((t - 0.25) / 0.05, 0.0, 1.0)))
			var slash := _smoothstep(clampf((t - 0.25) / 0.25, 0.0, 1.0)) * (1.0 - _smoothstep(clampf((t - 0.5) / 0.5, 0.0, 1.0)))
			wpos += Vector3(0.10 * windup - swing_sweep * slash, 0.04 * windup - 0.02 * slash, -0.04 * slash)
			wrot += Vector3(-0.15 * slash, 0.2 * windup + 0.4 * slash, 0.5 * windup - swing_roll * slash)
	# throw：后拉蓄力（保持）
	if _throw_t >= 0.0:
		var t := clampf(_throw_t / throw_pull, 0.0, 1.0)
		wrot += Vector3(-0.5 * t, 0, 0)
		wpos += Vector3(0, 0, 0.05 * t)
	# 叠加到基础取景（腰射↔开镜按 ads_t 插值；开镜时武器举到眼前正中、眼看瞄具），再叠加动作通道
	var wbase_pos: Vector3 = view_model.base_offset.lerp(view_model.base_ads_offset, ads_t)
	var wbase_rot: Vector3 = view_model.base_rotation.lerp(view_model.base_ads_rotation, ads_t)
	view_model.weapon_mount.position = wbase_pos + wpos
	view_model.weapon_mount.rotation = wbase_rot + wrot


# ---- 动画包络辅助（CS 多相位） ----

func _smoothstep(x: float) -> float:
	var v := clampf(x, 0.0, 1.0)
	return v * v * (3.0 - 2.0 * v)


func _reload_env(t: float) -> float:
	# 快降(0-0.22) → 低位保持(0.22-0.68) → 回升(0.68-1.0)，全程平滑
	if t < 0.22:
		return _smoothstep(t / 0.22)
	if t < 0.68:
		return 1.0
	return 1.0 - _smoothstep((t - 0.68) / 0.32)


func _reload_rack_env(t: float) -> float:
	# 拉枪栓小动作：仅在 0.68-0.85 段快速后拉-回位（换弹尾声的上膛感）
	if t < 0.68 or t > 0.9:
		return 0.0
	var u := (t - 0.68) / 0.22  # 0→1
	return sin(u * PI)  # 0→1→0 后拉再回
