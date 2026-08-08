# Weapons/WeaponCore.gd
# M1 任务1：射击核心（hitscan + 后坐力 + 换弹）
#
# 接口签名按计划 §5 任务1 逐字照抄；数值唯一来源 WeaponResource（weapon_*.tres，禁止硬编码散值，企划书 §4.2.5）。
# 全局约束（计划 §4）：hitscan 射线 collision_mask=1（仅 Objects 层）；纯离线。
# 参考：docs/superpowers/reference/m1-src/weapon_proto.gd（check_hitscan_collision 射线思路）
class_name WeaponCore
extends Node3D

signal shot_fired(ammo_left: int)
signal reload_started
signal reload_finished
signal hit_landed(target: Node, damage: float, position: Vector3, normal: Vector3)
signal out_of_ammo
# M1 任务15：曳光弹（CC0 bullet_tracer）——每次命中结算发枪口→端点线段（命中点 / max_range 端点）
signal tracer_fired(from: Vector3, to: Vector3)

# 累计后坐力偏移（度，未恢复部分）：每次射击累加逐发偏移，停止射击后按 recovery_speed 衰减回零。
# 计划 §5 任务1：本任务实现累计偏移的计算，恢复应用在任务 3 Head 接口；公开供测试观察恢复衰减。
var recoil_accum: Vector2 = Vector2.ZERO

var _resource: WeaponResource
var _camera: Camera3D
var _movement: Node  # 精度模型移动提供者（MovementController：is_moving/is_crouching 查询；null = 无惩罚）
var _mag: int = 0
var _reserve: int = 0
var _shot_index: int = 0  # 射击序号（0 起，SET_PATTERN 逐发索引）
var _last_shot_offset: Vector2 = Vector2.ZERO  # 最近一次射击的逐发偏移
var _fire_cooldown: float = 0.0  # 射速节流剩余冷却（秒）
var _since_last_shot: float = 0.0  # 距上次射击时间（恢复衰减门控）
var _reloading: bool = false
var _reload_remaining: float = 0.0
var _reload_old_mag: int = 0  # 换弹开始时的弹匣余量（丢弃剩余规则）
var _ads_active: bool = false
var _trigger_held: bool = false  # 上一次物理帧的扳机按下状态（半自动沿检测）
var _trigger_pressed_edge: bool = false  # 本物理帧检测到的按压沿（每次按键只发一发）
var _rng := RandomNumberGenerator.new()

# M1 任务11：无限弹药（spec §9.9 测试环境 cheats；正式版 L_Main.cheats=false 关闭）。
# 语义：开火照常逐发扣减（HUD 保持真实计数），弹匣打空后下次开火自动补满（等效无限）；
# 换弹瞬时满（立即补满 + reload_finished，不进入换弹状态）；备弹恒满（无穷）。
# M67 投出后自动补 1 枚由 WeaponManager._throw_grenade 走 refund_throw 等价路径。
var infinite_ammo: bool = false
# M1.5 靶场模式：备弹无限但弹匣有上限（换弹正常进行——CS 靶场手感；区别于 infinite_ammo 的免换弹）。
# 手雷等投掷物配合 infinite_ammo（refund_throw）实现"无限但投完仍自动切回主武器"。
var infinite_reserve: bool = false


func setup(resource: WeaponResource, camera: Camera3D, movement: Node = null) -> void:
	_resource = resource
	_camera = camera
	_movement = movement
	_mag = resource.magazine
	_reserve = resource.max_ammo
	_shot_index = 0
	_last_shot_offset = Vector2.ZERO
	_fire_cooldown = 0.0
	_since_last_shot = 0.0
	_reloading = false
	_trigger_held = false
	_trigger_pressed_edge = false
	recoil_accum = Vector2.ZERO


func try_fire() -> void:
	# 调用契约：调用方（WeaponManager）需在开火键按住期间**每物理帧轮询** try_fire()——
	# 半自动模式依赖 _physics_process 的按压沿检测（见 _fire_mode_allows_now）：沿只在
	# 按下后的物理帧出现并被本次调用消费，错过即不发（静默）；全自动模式同样需持续
	# 轮询以维持射速节流（RPM 间隔在 _physics_process 中衰减）。
	# 输入所有权：本类直接读取 Input 动作 "fire"（半自动沿检测），与 Manager 的输入处理
	# 构成双处耦合——重绑定输入动作时两处需同步修改。
	if _resource == null or _reloading:
		return
	if infinite_ammo and _mag <= 0:
		# 测试环境：弹匣打空自动补满（spec §9.9）——先补满再按正常流程开火
		_refill_infinite_ammo()
	if _mag <= 0:
		# 空匣：不发 shot_fired，发 out_of_ammo（节流，连发不刷屏）
		if _fire_mode_allows_now() and _fire_cooldown <= 0.0:
			_fire_cooldown = _fire_interval()
			_consume_trigger_edge()
			out_of_ammo.emit()
		return
	if not _fire_mode_allows_now():
		return
	if _fire_cooldown > 0.0:
		return
	_execute_shot()
	_consume_trigger_edge()


func can_fire() -> bool:
	if _resource == null or _reloading or _mag <= 0:
		return false
	if not _fire_mode_allows_now() or _fire_cooldown > 0.0:
		return false
	return true


func start_reload() -> void:
	if _resource == null or _reloading:
		return
	if infinite_ammo:
		# 测试环境：换弹瞬时满（spec §9.9）——立即补满弹匣/备弹，不进入换弹状态
		# （无等待；不播 reload_started 换弹动画——瞬时完成无需下压动作）
		_refill_infinite_ammo()
		reload_finished.emit()
		return
	if _mag >= _resource.magazine or (_reserve <= 0 and not infinite_reserve):
		return  # 满弹匣或无可换弹药（infinite_reserve 备弹无限，不因 reserve=0 拦截）
	_reloading = true
	_reload_old_mag = _mag
	_reload_remaining = _resource.reload_time
	reload_started.emit()


func interrupt_reload() -> void:
	# 打断换弹（切枪/开火时由 WeaponManager 调用）：弹匣/备弹保持换弹前状态，
	# 丢弃结算只在完成时进行——弹药不返还。
	_reloading = false


func is_reloading() -> bool:
	return _reloading


func get_ammo() -> Vector2:
	return Vector2(_mag, _reserve)


func add_ammo(amount: int) -> void:
	if _resource == null:
		return
	_reserve = mini(_reserve + amount, _resource.max_ammo)


func refund_throw() -> void:
	# M67 取消投掷（任务 6）：引信阶段取消 → 返还手中投掷物（弹匣 +1，上限 magazine；备弹不变）。
	# 同时重置开火冷却（rpm=0 → 上次投掷留下 INF 冷却，不重置则后续投掷被节流静默锁死——
	# 审查重要修复的配套：取消后必须能再次投掷）。
	if _resource != null:
		_mag = mini(_mag + 1, _resource.magazine)
	_fire_cooldown = 0.0


func _refill_infinite_ammo() -> void:
	# 无限弹药补满（spec §9.9）：弹匣满 + 备弹回满（备弹无穷）。调用方：try_fire 空匣补满、
	# start_reload 瞬时满。L_Main.cheats 注入在 setup 之后设置标志（无资源防御）。
	if _resource == null:
		return
	_mag = _resource.magazine
	_reserve = _resource.max_ammo


func get_recoil_offset() -> Vector2:
	return _last_shot_offset


func set_ads(active: bool) -> void:
	_ads_active = active


func _physics_process(delta: float) -> void:
	_tick_trigger_edge()
	_tick_fire_cooldown(delta)
	_tick_reload(delta)
	_tick_recoil_recovery(delta)


# ---- 开火 ----

func _execute_shot() -> void:
	var shot_index := _shot_index
	_last_shot_offset = _get_shot_offset(shot_index)
	recoil_accum += _last_shot_offset
	_shot_index += 1
	_mag -= 1
	_fire_cooldown = _fire_interval()
	_since_last_shot = 0.0
	shot_fired.emit(_mag)
	_perform_hitscan(shot_index)


func _fire_interval() -> float:
	if _resource.rpm <= 0:
		return INF
	return 60.0 / float(_resource.rpm)


func _fire_mode_allows_now() -> bool:
	if _resource.fire_mode != WeaponResource.FireMode.SEMI_AUTO:
		return true  # 全自动等：按住持续射击由调用方驱动节流
	# 半自动：每次按键只发一发——按压沿在 _physics_process 轮询检测。
	# 沿是"粘性"的：保持到被开火消费或松开，不依赖调用方与物理帧的对齐
	# （Input.is_action_just_pressed 的帧语义在 GUT headless 中不稳定）。
	return _trigger_pressed_edge


func _tick_trigger_edge() -> void:
	if _resource == null or _resource.fire_mode != WeaponResource.FireMode.SEMI_AUTO:
		_trigger_held = false
		_trigger_pressed_edge = false
		return
	var held := Input.is_action_pressed(&"fire")
	if held and not _trigger_held:
		_trigger_pressed_edge = true  # 按压沿：保持直到开火消费或松开
	if not held:
		_trigger_pressed_edge = false
	_trigger_held = held


func _consume_trigger_edge() -> void:
	_trigger_pressed_edge = false


func _tick_fire_cooldown(delta: float) -> void:
	if _fire_cooldown > 0.0:
		_fire_cooldown = maxf(0.0, _fire_cooldown - delta)


# ---- hitscan（参考 weapon_proto.gd check_hitscan_collision；全局约束：mask=1 仅 Objects 层） ----

func _perform_hitscan(shot_index: int) -> void:
	if _camera == null:
		return
	var origin: Vector3 = _camera.global_position
	var direction := _ballistic_direction(shot_index)
	var end := origin + direction * _resource.max_range
	var query := PhysicsRayQueryParameters3D.create(origin, end)
	query.collision_mask = 1  # 仅 Objects 层
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	if result.is_empty():
		# M1 任务15：未命中 → 曳光弹到 max_range 端点（CC0 bullet_tracer）
		tracer_fired.emit(origin, end)
		return
	var target := result["collider"] as Node
	var hit_pos: Vector3 = result["position"]
	var hit_normal: Vector3 = result["normal"]
	# M1 任务15：曳光弹枪口→命中点（命中反馈视觉）
	tracer_fired.emit(origin, hit_pos)
	var multiplier := _get_part_multiplier(target)
	var falloff := _get_falloff_multiplier(origin.distance_to(hit_pos))
	var damage := _resource.damage * multiplier * falloff
	hit_landed.emit(target, damage, hit_pos, hit_normal)


func _ballistic_direction(shot_index: int) -> Vector3:
	var basis := _camera.global_transform.basis
	var dir := -basis.z
	var dev := _get_ballistic_deviation(shot_index)
	if dev == Vector2.ZERO:
		return dir
	# 散布角（度）：x = 垂直（pitch，向上为正），y = 水平（yaw）
	dir = dir.rotated(basis.x, deg_to_rad(dev.x))
	dir = dir.rotated(basis.y, deg_to_rad(dev.y))
	return dir.normalized()


func _get_ballistic_deviation(shot_index: int) -> Vector2:
	if shot_index == 0:
		# 首发精度：综合稳定性因素（spec §9.3）——基础散布 × 移动惩罚 × 下蹲收窄 ÷ 开镜
		var s := _get_first_shot_spread()
		return Vector2(_rng.randf_range(-s, s), _rng.randf_range(-s, s))
	return _get_shot_offset(shot_index)  # 后续：pattern/random 偏移


# 首发散布角（度，综合因素后）：叠加顺序 base × move × crouch ÷ ads。
# 移动/下蹲状态从 MovementController 鸭子类型查询（is_moving/is_crouching，null 提供者 = 无惩罚）。
func _get_first_shot_spread() -> float:
	var s := _resource.first_shot_spread
	if _movement != null and bool(_movement.get("is_moving")):
		s *= _resource.move_spread_multiplier  # 移动惩罚（AK 3.0：CS2 running inaccuracy）
	if _movement != null and bool(_movement.get("is_crouching")):
		s *= _resource.crouch_spread_multiplier  # 下蹲收窄（0.7：CS2 crouch tighter）
	if _ads_active and _resource.ads_multiplier > 0.0:
		s /= _resource.ads_multiplier  # 开镜收窄（开镜时移动惩罚保留——CS2 开镜移动仍有精度损失）
	return s


func _get_part_multiplier(target: Node) -> float:
	if target.is_in_group("head"):
		return _resource.headshot_multiplier
	if target.is_in_group("limb"):
		return _resource.limb_multiplier
	return 1.0  # 躯干（含 "torso" Group 或未分组）


func _get_falloff_multiplier(distance: float) -> float:
	if distance <= _resource.effective_range:
		return 1.0  # 满伤段（AK 0-40m = 1.0）
	var curve := _resource.falloff_curve
	if curve.size() <= 1:
		return curve[0] if curve.size() == 1 else 1.0
	if distance >= _resource.max_range:
		return curve[curve.size() - 1]  # 下限（AK 末段 0.96）
	# 有效→最大 线性插值：曲线等分为 segments 段（AK [1.0, 0.98, 0.96] → 40-50m 与 50-60m 两段）
	var segments := curve.size() - 1
	var span := (_resource.max_range - _resource.effective_range) / float(segments)
	var offset := distance - _resource.effective_range
	var idx := mini(int(offset / span), segments - 1)
	var t := (offset - float(idx) * span) / span
	return lerpf(curve[idx], curve[idx + 1], t)


# ---- 换弹 ----

func _tick_reload(delta: float) -> void:
	if not _reloading:
		return
	_reload_remaining -= delta
	if _reload_remaining <= 0.0:
		finish_reload()  # 任务16：公开结算（幂等，动画信号路径亦可触发）


func finish_reload() -> void:
	# M1 任务16：换弹结算公开化（OpenFPS 动画信号驱动）——Reload 动画播完立即结算（非计时器；
	# WeaponCore 计时器保留为无动画环境的纯逻辑回退）。幂等：非换弹中调用为空操作——
	# 计时器与动画信号双路径先到先结算，不双发（WeaponManager/WeaponAnchor 均可安全调用）。
	if not _reloading:
		return
	_finish_reload()


func _finish_reload() -> void:
	_reloading = false
	# CS2 2026-03 丢弃弹匣剩余：弹匣 = magazine，备弹 -= (magazine - 换弹前弹匣值)
	# 备弹不足：弹匣 = min(magazine, 备弹 + 旧弹匣剩余)
	var needed := _resource.magazine - _reload_old_mag
	if infinite_reserve:
		# 靶场模式：备弹无限——弹匣补满，备弹数额不减少（HUD 备弹恒满）
		_mag = _reload_old_mag + needed
		_reserve = _resource.max_ammo
	else:
		var take := mini(needed, _reserve)
		_mag = _reload_old_mag + take
		_reserve -= take
	reload_finished.emit()


# ---- 后坐力 ----

func _get_shot_offset(shot_index: int) -> Vector2:
	match _resource.recoil_pattern:
		WeaponResource.RecoilPattern.SET_PATTERN:
			return _pattern_offset_at(shot_index)
		WeaponResource.RecoilPattern.RANDOM:
			return _random_offset()
		_:
			return Vector2.ZERO


func _pattern_offset_at(index: int) -> Vector2:
	var pattern := _resource.pattern_offsets
	if pattern.is_empty():
		return Vector2.ZERO
	return pattern[mini(index, pattern.size() - 1)]  # 越界循环到最后一项


func _random_offset() -> Vector2:
	var v := _resource.recoil_variance
	return Vector2(
		_rng.randf_range(_resource.recoil_amount - v, _resource.recoil_amount + v),
		_rng.randf_range(-v, v))


func _tick_recoil_recovery(delta: float) -> void:
	if _resource == null:
		return
	_since_last_shot += delta
	if _since_last_shot < _fire_interval() or recoil_accum == Vector2.ZERO:
		return  # 持续射击中不恢复；停止射击后按 recovery_speed 衰减回零
	var amount := _resource.recovery_speed * delta
	recoil_accum.x = move_toward(recoil_accum.x, 0.0, amount)
	recoil_accum.y = move_toward(recoil_accum.y, 0.0, amount)
