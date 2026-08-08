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
# ---- reload（换弹下沉+倾斜）----
@export var reload_drop := 0.10
@export var reload_tilt := 0.5
# ---- swing（近战挥击）----
@export var swing_pitch := 1.1
# ---- throw（手雷后拉）----
@export var throw_pull := 0.5

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
var _throw_t := -1.0
var _deploy_t := 0.0
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
	_mount(manager.get_current_slot())


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
	_swing_dur = 0.3 if heavy else 0.12
	_swing_t = 0.0


func _on_throw_primed() -> void:
	_throw_t = 0.0


func _on_throw_released() -> void:
	_throw_t = -1.0


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


func _apply() -> void:
	var pos := _kick + _sway + _bob
	var rot := _kick_rot + _sway_rot
	# reload 下沉+倾斜（前半下沉，后半回位）
	if _reload_t >= 0.0 and _reload_dur > 0.0:
		var t := _reload_t / _reload_dur
		var env := sin(t * PI)  # 0→1→0
		pos += Vector3(0, -reload_drop * env, 0)
		rot += Vector3(reload_tilt * env, 0, 0)
	# swing 下挥
	if _swing_t >= 0.0 and _swing_dur > 0.0:
		var t := _swing_t / _swing_dur
		var env := sin(t * PI)
		rot += Vector3(-swing_pitch * env, 0, 0)
	# throw 后拉（保持）+ 释放回位
	if _throw_t >= 0.0:
		var t := clampf(_throw_t / throw_pull, 0.0, 1.0)
		rot += Vector3(-0.5 * t, 0, 0)
		pos += Vector3(0, 0, 0.05 * t)
	# deploy 滑入
	if _deploy_t > 0.0:
		var t := _deploy_t / 0.18
		pos += Vector3(0, -0.10 * t * t, 0)
		rot += Vector3(-0.3 * t * t, 0, 0)
	view_model.position = pos
	view_model.rotation = rot
