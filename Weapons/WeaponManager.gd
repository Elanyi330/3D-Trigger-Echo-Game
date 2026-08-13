# Weapons/WeaponManager.gd
# M1 任务2：四槽位切换状态机 + 移速联动
#
# 接口签名按计划 §5 任务2 逐字照抄；数值唯一来源 WeaponResource（weapon_*.tres，禁止硬编码散值，企划书 §4.2.5）。
# 半自动调用契约（WeaponCore.try_fire 注释）：开火由 _physics_process 每物理帧轮询
# Input.is_action_pressed(&"fire") 驱动（禁止 is_action_just_pressed——回调先于物理帧，沿未设置）。
# 输入动作名 &"fire" 与 WeaponCore 的沿检测构成双处耦合（重绑定需两处同步）。
# 参考：docs/superpowers/reference/m1-src/Weapon_State_Machine/Weapon_State_Machine.gd（槽位切换/延迟模式）
class_name WeaponManager
extends Node3D

signal weapon_switched(slot: int)  # 0=primary 1=secondary 2=melee 3=throwable
signal weapon_ammo_updated(slot: int, mag: int, reserve: int)
# M1 任务14：M67 引信开始（fire 按下，手中持雷）——握持系统消费（左手抽拉环动画）
signal throw_primed
# M1 任务16：投掷出手/取消（fire 松开出手 / 右键取消）——握持系统消费（持雷手臂挥出反向回位）
signal throw_released
# M1 任务16：机瞄正反播（active）——WeaponAnchor 消费（AimAnim play/play_backwards）
signal aim_toggled(active: bool)
# M1 任务15：命中敌人（hit_landed 命中 Enemy，非训练靶子）→ hitmarker（HUD 消费）
signal enemy_hit

# M1 任务5：视模型场景（4 槽位，索引=槽位；null/越界=无模型 → 挂点隐藏手）。
# 挂载逻辑在 WeaponAnchor（订阅 weapon_switched），Manager 保持纯逻辑只提供数据。
@export var view_models: Array[PackedScene] = []
# 投掷出手速度（m/s，M67 出手速度；参数化导出避免硬编码散值——非 .tres 字段，调参走此导出）
@export var throw_strength: float = 15.0
# M2 手感修复（2026-08-13）：投掷手感——瞄准点射线距离上限（m）/ 瞄天空回退瞄准距离（m）。
# 投掷方向 = 瞄准点 − 手雷原点（瞄哪打哪）；强度保持 throw_strength 固定（CS 固定投速）。
@export var throw_aim_max_dist: float = 30.0
@export var throw_aim_fallback_dist: float = 25.0
# M1.5：投掷出手后自动切回主武器（CS 式；用户拍板）。默认开启；机制单测可关闭以隔离流程。
@export var auto_switch_after_throw: bool = true

enum State { HOLSTERED, DEPLOYING, ACTIVE, RELOADING, THROWING }

var _cores: Array[WeaponCore] = []  # 每槽位一个 WeaponCore 实例（各自持有弹药总账）
var _resources: Array[WeaponResource] = []  # 与 _cores 等长：槽位资源引用（null = 空槽位，防御）
var _movement: MovementController
var _head: Node3D  # 机瞄 FOV/灵敏度接线目标（Head.gd 无 class_name，按 Node3D 持有；任务 6）
var _camera: Camera3D  # hitscan + 投掷方向相机（setup 时缓存；无相机 = 单元测试环境）
var _current_slot: int = 0
var _state: State = State.HOLSTERED
var _deploy_remaining: float = 0.0  # 切枪部署倒计时（秒，来自资源 deploy_time）
var _throw_pending: bool = false  # M67 引信阶段标志（fire 按住 = 手中持雷；松开 = 真实 Grenade 出手）
var _trajectory: ThrowTrajectory  # 投掷抛物线预览（任务 8：THROWING 显示/取消/投出隐藏）
var _bullet_holes: Array[BulletHole] = []  # 弹孔跟踪（M1.5 起取消数量上限——30s 生命周期自然约束累积）
var _melee: MeleeController  # 近战判定控制器（任务 10：MELEE 槽位 fire 分发/右键重刺）
var _weapon_view: Node = null  # 投掷原点来源（WeaponView.get_throw_origin；null = 回退相机，测试兼容）
# M1 任务15：换弹排队（CC0 gun.gd 照搬）——射击中按 R 标记排队，射完自动 start_reload；
# 队列跟随当前槽位（切枪取消），空仓路径不走排队（立即换）
var _queued_reload: bool = false
# M1.5：机瞄状态跟踪（修复"开镜期间换弹/切枪仍保持开镜"bug）——set_aim 写入，
# 换弹/切枪时经 _exit_ads 自动取消开镜（CS 式：换弹/切枪退出瞄准，FOV/灵敏度恢复）。
var _ads_active: bool = false


func setup(slots: Array[WeaponResource], movement: MovementController) -> void:
	for old in _cores:
		old.queue_free()
	_cores.clear()
	_resources.clear()
	_bullet_holes.clear()
	_movement = movement
	_camera = _find_camera()
	if _trajectory == null:
		_trajectory = ThrowTrajectory.new()
		_trajectory.name = "ThrowTrajectory"
		add_child(_trajectory)
	_trajectory.visible = false  # 默认隐藏（THROWING 才显示）
	# M1 任务10：近战控制器（全槽位单例，MELEE 槽位挥击判定；origin = 相机，无相机 = 测试环境默认原点）
	if _melee == null:
		_melee = MeleeController.new()
		_melee.name = "MeleeController"
		add_child(_melee)
	_melee.origin = _camera
	for i in slots.size():
		var core := WeaponCore.new()
		core.name = "WeaponCore_%d" % i
		if slots[i] != null:
			core.setup(slots[i], _camera, movement)
		core.reload_finished.connect(_on_reload_finished.bind(core))
		core.hit_landed.connect(_on_hit_landed)
		# M1 任务15：空仓自动换弹（out_of_ammo → 备弹 > 0 时自动 start_reload）
		core.out_of_ammo.connect(_on_out_of_ammo.bind(core))
		# M1 任务15：相机后坐力接线（开火 → Head.add_recoil，双层 lerp）
		core.shot_fired.connect(_on_shot_fired.bind(core))
		# M1 任务15：曳光弹（枪口→命中点线条，0.1s 淡出自清）
		core.tracer_fired.connect(_on_tracer_fired)
		add_child(core)
		_cores.append(core)
		_resources.append(slots[i])
	_current_slot = 0
	_state = State.ACTIVE  # 出生即持枪（CS 式），初始槽位 0（primary）
	_ads_active = false  # 机瞄状态复位（M1.5）
	_apply_speed_modifier()


func set_head(head: Node3D) -> void:
	# 机瞄接线（任务 6）：Head.set_ads(active, ads_multiplier) —— FOV 缩放 + 灵敏度缩放
	_head = head


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


func switch_to(slot: int) -> void:
	if slot < 0 or slot >= _cores.size():
		return
	if _resources[slot] == null:
		return  # 空槽位：无操作
	if slot == _current_slot:
		return  # 切同一槽位：无操作（不发信号）
	# THROWING（M67 引信）期间切枪：先取消投掷（弹药返还 + 复位 + ammo 信号）再切换——
	# 否则弹药已扣 + _throw_pending 残留 + Grenade 永不生成 = 静默丢雷（审查重要修复；
	# CS2 切枪收雷保留，取消不消耗弹药）。
	if _state == State.THROWING:
		_cancel_throw()
	# 中断当前槽位：换弹打断（弹药不返还，WeaponCore.interrupt_reload 语义）；
	# 开火中断由状态离开 ACTIVE 后轮询门控实现（立即停火）。
	_queued_reload = false  # M1 任务15：切枪取消换弹排队（队列跟随当前槽位）
	_exit_ads()  # M1.5：切枪自动取消开镜（CS 式——换武器退出瞄准，FOV 恢复）
	if _melee != null:
		_melee.cancel_pending()  # M1.5：切枪取消未结算挥击（防延迟伤害在换持武器后空发）
	var old_core := _cores[_current_slot]
	if old_core != null and old_core.is_reloading():
		old_core.interrupt_reload()
	_current_slot = slot
	_state = State.DEPLOYING
	_deploy_remaining = _resources[slot].deploy_time
	_apply_speed_modifier()  # CS2 式：持枪移速立即生效（DEPLOYING 期间也更新）
	weapon_switched.emit(slot)
	var ammo := _cores[slot].get_ammo()
	weapon_ammo_updated.emit(slot, int(ammo.x), int(ammo.y))


func next_weapon() -> void:
	# 滚轮循环 0→1→2→3→0；跳过无资源槽位（防御）
	if _cores.is_empty():
		return
	var next := _current_slot
	for i in _cores.size():
		next = (next + 1) % _cores.size()
		if _resources[next] != null:
			break
	if next != _current_slot:
		switch_to(next)


func get_current_slot() -> int:
	return _current_slot


func get_state() -> int:
	return _state


func get_core(slot: int) -> WeaponCore:
	if slot < 0 or slot >= _cores.size():
		return null
	return _cores[slot]


func get_view_model(slot: int) -> PackedScene:
	if slot < 0 or slot >= view_models.size():
		return null
	return view_models[slot]


func get_resource(slot: int) -> WeaponResource:
	# M1 任务9：槽位资源访问器（WeaponAnchor 换弹/切枪动画时长联动读取 reload_time/deploy_time）
	if slot < 0 or slot >= _resources.size():
		return null
	return _resources[slot]


func get_melee_controller() -> MeleeController:
	# M1 任务10：近战控制器访问器（WeaponAnchor 挥击动画接线消费 melee_swung）
	return _melee


func try_fire() -> void:
	# 半自动调用契约：本方法由 _physics_process 每物理帧轮询调用（见类头注释）。
	if _state != State.ACTIVE:
		return  # DEPLOYING/RELOADING/THROWING/HOLSTERED 期间开火无效
	var core := _cores[_current_slot]
	if core == null or _resources[_current_slot] == null:
		return
	# M1 任务10：fire 分发按开火模式路由——MELEE 左键轻击（修复"左键完全无反应"）、
	# THROWABLE 投掷、其余走 WeaponCore 射击
	var res := _resources[_current_slot]
	match res.fire_mode:
		WeaponResource.FireMode.MELEE:
			_melee.try_swing(true, res)
		WeaponResource.FireMode.THROWABLE:
			_try_throw(core)
		_:
			core.try_fire()


func start_reload() -> void:
	if _state != State.ACTIVE:
		return  # DEPLOYING/THROWING 期间换弹无效
	var core := _cores[_current_slot]
	if core == null:
		return
	# M1 任务15：射击中按 R → 排队换弹（CC0 gun.gd 的 animation_player.queue("reload")
	# 等价——当前射击中标记排队，射完自动 start_reload）。仅弹匣有余弹且射击中才排队：
	# 空仓（mag 0）不排队立即换（CS 式空仓自动换，即使仍按住开火）。
	var res := _resources[_current_slot]
	if _is_burst_firing() and core.get_ammo().x > 0.0 and _reload_possible(core, res):
		_queued_reload = true
		return
	core.start_reload()
	if core.is_reloading():
		_queued_reload = false  # 换弹真正开始：消费排队
		_exit_ads()  # M1.5：开镜期间换弹自动取消开镜（CS 式——用户反馈修复）
		_state = State.RELOADING


func set_aim(active: bool) -> void:
	# M67 右键取消投掷（企划书 §4.2.3⑦ + 任务 2/4 审查移交）：THROWING（引信阶段）+
	# aim 按下 → 取消投掷：弹药返还、回 ACTIVE、不生成投掷物。
	if _state == State.THROWING and active:
		_cancel_throw()
		return
	if _state != State.ACTIVE:
		return  # DEPLOYING/THROWING 期间机瞄无效
	# M1 任务10：近战右键重刺（spec §9.5）——匕首无机瞄（ads_multiplier 1.0），右键 = 重刺
	var res := _resources[_current_slot]
	if res != null and res.fire_mode == WeaponResource.FireMode.MELEE:
		if active:
			_melee.try_swing(false, res)
		return
	var core := _cores[_current_slot]
	if core == null:
		return
	_ads_active = active  # M1.5：跟踪机瞄状态（换弹/切枪 _exit_ads 消费）
	core.set_ads(active)
	# 机瞄动画正反播接线（任务16）：AimAnim 消费（枪滑向视线中心）；拼装视模型防御跳过
	aim_toggled.emit(active)
	# 机瞄 FOV/灵敏度接线（任务 6）：仅 ACTIVE 写入；数值唯一来源 .tres ads_multiplier
	if _head != null and _head.has_method("set_ads"):
		_head.set_ads(active, res.ads_multiplier if res != null else 1.0)


func _exit_ads() -> void:
	# M1.5：换弹/切枪自动取消开镜（CS 式）——核心 ADS 标志复位 + 动画反播 + FOV/灵敏度恢复。
	# 幂等：未开镜时为空操作（不重复发 aim_toggled / 不动 FOV）。Head.set_ads(false) 内部
	# 用记录的 _base_fov/_base_sensitivity 恢复，第三参数（multiplier）非 active 时忽略，传 1.0。
	if not _ads_active:
		return
	_ads_active = false
	var core := _cores[_current_slot]
	if core != null:
		core.set_ads(false)
	aim_toggled.emit(false)
	if _head != null and _head.has_method("set_ads"):
		_head.set_ads(false, 1.0)


func get_speed_modifier() -> float:
	if _resources.is_empty() or _resources[_current_slot] == null:
		return 1.0
	return _resources[_current_slot].mobility / 250.0


func _physics_process(delta: float) -> void:
	if _state == State.DEPLOYING:
		_deploy_remaining -= delta
		if _deploy_remaining <= 0.0:
			_state = State.ACTIVE
	# M67 引信释放（任务 6 接线 + 任务 8 长按持雷）：THROWING + fire 松开 → 生成真实 Grenade 出手；
	# 按住期间每物理帧刷新抛物线预览（无限持雷，无超时自动投出——用户拍板）；
	# 释放前右键取消（set_aim）→ 不生成（_throw_pending 复位）
	if _state == State.THROWING and _throw_pending:
		if not Input.is_action_pressed(&"fire"):
			_throw_grenade()
		elif _trajectory != null and _camera != null:
			var lp := _launch_params()
			_trajectory.update_trajectory(lp["origin"], lp["direction"], throw_strength)
	# 开火轮询契约：开火键按住期间每物理帧轮询 try_fire（全自动维持射速节流，半自动靠 WeaponCore 沿检测）
	if Input.is_action_pressed(&"fire") and _state == State.ACTIVE:
		try_fire()
	# M1 任务15：换弹排队消费——射击结束（松开 fire）且 ACTIVE → 自动 start_reload
	if _queued_reload and _state == State.ACTIVE and not Input.is_action_pressed(&"fire"):
		_queued_reload = false
		start_reload()


# ---- M67 投掷（任务 4 Grenade 接线；任务 6：引信阶段 + 真实投掷物） ----

func _try_throw(core: WeaponCore) -> void:
	var ammo := core.get_ammo()
	if ammo.x <= 0.0:
		core.try_fire()  # 空投掷：转发触发 out_of_ammo（冷却 INF 节流，不刷屏）
		return
	core.try_fire()  # 扣减弹药（引信开始）：mag 1 → 0（rpm=0 → 冷却 INF，天然单次）
	_state = State.THROWING
	_throw_pending = true
	if _trajectory != null:
		_trajectory.visible = true  # 长按持雷：显示抛物线预览
	throw_primed.emit()  # M1 任务14：引信开始（握持系统消费：左手抽拉环动画）
	var after := core.get_ammo()
	weapon_ammo_updated.emit(_current_slot, int(after.x), int(after.y))


func _throw_grenade() -> void:
	# fire 释放 = 出手：生成真实 Grenade（init 位置/方向/强度）挂到场景，引信由 Grenade 自身计时。
	# 状态流转先行（审查收尾）：即使相机缺失（单元测试环境）也不滞留 THROWING。
	_throw_pending = false
	_state = State.ACTIVE  # 投出后回 ACTIVE（可换弹/再投/切枪）
	if _trajectory != null:
		_trajectory.visible = false  # 出手后隐藏预览
	throw_released.emit()  # 任务16：出手 → 持雷手臂挥出反向回位（握持系统消费）
	# M1 任务11：无限弹药（spec §9.9 测试环境）——M67 投出后自动补 1 枚（等价 refund_throw：
	# 弹匣补回 + 开火冷却重置——rpm=0 的 INF 冷却不重置则后续投掷被节流静默锁死）。
	var core := _cores[_current_slot]
	if core != null and core.infinite_ammo:
		core.refund_throw()
		var ammo := core.get_ammo()
		weapon_ammo_updated.emit(_current_slot, int(ammo.x), int(ammo.y))
	if _camera == null:
		_auto_switch_to_primary()  # M1.5：投掷后自动切回主武器（测试路径同样切换）
		return  # 无相机（单元测试环境）：不生成投掷物，仅状态流转
	var res := _resources[_current_slot]
	if res == null:
		return
	var grenade := Grenade.new()
	grenade.resource = res
	# M1 任务14：脱手后挂场景根（get_tree().root）——不再作为玩家子节点（脱手后不随玩家运动，
	# 爆炸/弹道以场景坐标为准）；未入树（纯逻辑环境）防御回退挂自身
	var tree := get_tree()
	if tree != null:
		tree.root.add_child(grenade)  # 先入树再 init：global_position 按父级变换正确换算
	else:
		add_child(grenade)
	var lp := _launch_params()
	grenade.init(lp["origin"], lp["direction"], throw_strength)
	# M1.5：投掷出手后自动切回主武器（CS 式——投完即回步枪；用户拍板）
	_auto_switch_to_primary()


func _auto_switch_to_primary() -> void:
	# 投掷后自动切回主武器（槽位 0）。主武器槽位有效才切换（switch_to 内部走 DEPLOYING）。
	if not auto_switch_after_throw:
		return
	if _cores.size() > 0 and _resources[0] != null and _current_slot != 0:
		switch_to(0)


func _cancel_throw() -> void:
	# M67 右键取消投掷（企划书 §4.2.3⑦）：引信阶段取消 → 弹药返还、回 ACTIVE（未生成投掷物）
	var core := _cores[_current_slot]
	if core != null:
		core.refund_throw()
	_throw_pending = false
	_state = State.ACTIVE
	if _trajectory != null:
		_trajectory.visible = false  # 取消后隐藏预览
	throw_released.emit()  # 任务16：取消 → 持雷手臂挥出反向回位（握持系统消费）
	var ammo := core.get_ammo() if core != null else Vector2.ZERO
	weapon_ammo_updated.emit(_current_slot, int(ammo.x), int(ammo.y))


# ---- 换弹 ----

func _on_out_of_ammo(core: WeaponCore) -> void:
	# M1 任务15：空仓自动换弹（CC0：current_ammo == 0 → play("reload")）——备弹 > 0 才换
	# （start_reload 内部有满弹匣/无备弹守卫）；取消残余排队：空仓立即换不等待。
	if core != _cores[_current_slot]:
		return  # 防御：非当前槽位空仓（切换竞态）不动作
	_queued_reload = false
	start_reload()


func _on_reload_finished(core: WeaponCore) -> void:
	if core != _cores[_current_slot]:
		return  # 防御：非当前槽位换弹完成（切换已打断，不应发生）
	_state = State.ACTIVE
	var ammo := core.get_ammo()
	weapon_ammo_updated.emit(_current_slot, int(ammo.x), int(ammo.y))


func _is_burst_firing() -> bool:
	# M1 任务15：判断当前是否处于射击中（开火键按住 = 连射持续；半自动按住 = 同射击期）
	return Input.is_action_pressed(&"fire")


func _reload_possible(core: WeaponCore, res: WeaponResource) -> bool:
	# M1 任务15：换弹可行性（弹匣未满 + 备弹 > 0）——排队与空仓守卫共用
	if res == null:
		return false
	var ammo := core.get_ammo()
	return int(ammo.x) < res.magazine and int(ammo.y) > 0


# ---- 移速联动 ----

func _apply_speed_modifier() -> void:
	if _movement != null:
		_movement.speed_modifier = get_speed_modifier()


# ---- 弹孔系统（M1 任务8：命中点 quad 面片，30s 生命周期；M1.5 起取消数量上限） ----

func _on_tracer_fired(from: Vector3, to: Vector3) -> void:
	# M1 任务15：曳光弹（CC0 bullet_tracer）——枪口→命中点（或 max_range 端点）短暂线条，
	# 0.1s 淡出自清（Tracer 自身 _physics_process，无管理方计数）
	var tracer := Tracer.new()
	tracer.name = "Tracer"
	add_child(tracer)
	tracer.init(from, to)


func _on_shot_fired(_ammo_left: int, core: WeaponCore) -> void:
	# M1 任务15：相机后坐力接线——开火按当前槽位资源 recoil_val（.tres）叠加到 Head
	# （双层 lerp 入口：target_rotation 抬升 + Y/Z 抖动；快抬-慢回由 Head 物理帧驱动）
	if core != _cores[_current_slot]:
		return  # 防御：非当前槽位开火（切换竞态）不叠加
	var res := _resources[_current_slot]
	if _head != null and res != null and _head.has_method("add_recoil"):
		_head.add_recoil(res.recoil_val)


func _on_hit_landed(target: Node, damage: float, position: Vector3, normal: Vector3) -> void:
	# M1 任务12：hitscan 伤害结算（spec §9.10 训练场：射击对敌人减血）。
	# 任务6 起 hit_landed 仅弹孔消费；伤害结算集中在此信号唯一消费方，与 Grenade/Melee
	# 的 has_method 目标结算约定一致（企划书：所有单位统一 100HP，Target/Enemy 实现 take_damage）。
	# null target 防御：单元测试可裸发信号仅验弹孔路径（test_weapon_manager）。
	if target != null and target.has_method("take_damage"):
		target.take_damage(damage)
	# M1 任务15：hitmarker（仅命中敌人，非训练靶子 Target）——HUD 消费
	if target is Enemy:
		enemy_hit.emit()
	# M1 任务15：弹孔挂被击中 collider 下（随物体动，GarbajYT decals）
	_spawn_bullet_hole(position, normal, target)


func _spawn_bullet_hole(position: Vector3, normal: Vector3, parent: Node = null) -> BulletHole:
	var hole := BulletHole.new()
	hole.expired.connect(_on_bullet_hole_expired.bind(hole))
	add_child(hole)
	# M1 任务15：parent（命中 collider）非空且有效 → 弹孔挂其下（init 内 reparent）
	hole.init(position, normal,
			parent if (parent is Node3D and is_instance_valid(parent)) else null)
	_bullet_holes.append(hole)
	# M1.5：取消数量上限（用户拍板——弹孔不设场景最大存在数；由 30s 生命周期自然约束累积）。
	return hole


func _on_bullet_hole_expired(hole: BulletHole) -> void:
	# 30s 生命周期自然结束：从计数中移除（释放由 BulletHole 自身 queue_free）
	_bullet_holes.erase(hole)


func _find_camera() -> Camera3D:
	# hitscan 相机：取当前视口相机（集成场景中为 Head/Camera3D，current=true）；
	# 无相机（如单元测试）→ null，WeaponCore 跳过 hitscan 仅走开火逻辑
	var viewport := get_viewport()
	if viewport == null:
		return null
	return viewport.get_camera_3d()
