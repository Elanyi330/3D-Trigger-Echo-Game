# test/unit/test_weapon_manager.gd
# M1 任务2：WeaponManager 切换状态机 + 移速联动测试（TDD RED 先行）
# 行为（brief §行为要求）：
#   - 槽位 0=primary(AK)/1=secondary(Glock)/2=melee(刀)/3=throwable(M67)，初始 0
#   - 状态机 HOLSTERED/DEPLOYING/ACTIVE/RELOADING/THROWING；deploy 延迟（参数化自 .tres）
#   - switch_to：DEPLOYING 期间 try_fire/start_reload/set_aim 无效；切枪打断换弹（弹药不返还）；
#     开火中切枪立即中断；切同一槽位无操作
#   - next_weapon 滚轮循环 0→1→2→3→0（跳过空槽位）
#   - 动作分发：try_fire/start_reload/set_aim 转发当前 ACTIVE 槽位；M67 try_fire = 投掷占位
#     （THROWING + 弹药扣减，任务 4 接真实 Grenade）
#   - 弹药总账：换弹完成发 weapon_ammo_updated(slot, mag, reserve)
#   - 移速联动：get_speed_modifier() = mobility/250；切枪写入 movement.speed_modifier
#     （DEPLOYING 期间也更新）
# 半自动调用契约（WeaponCore.try_fire 注释）：开火由 Manager._physics_process 每物理帧轮询
# Input.is_action_pressed(&"fire") 驱动，禁止 is_action_just_pressed。
# 全局约束（计划 §4）：数值唯一来源 weapon_*.tres（测试派生期望，不硬编码散值）。
extends GutTest

var manager: WeaponManager
var movement: MovementController
var ak: WeaponResource
var glock: WeaponResource
var knife: WeaponResource
var m67: WeaponResource


func before_each() -> void:
	Input.action_release("fire")  # 防跨测试输入污染
	# 清理上一测试残留的场景根手雷/爆炸坑（任务14 脱手后挂根，测试树 autofree 不覆盖——
	# 1.5s 引信 + 30s Crater 会跨测试存活，须显式清理防污染）
	for child in get_tree().root.get_children():
		if child is Grenade or child is Crater:
			child.queue_free()
	ak = load("res://Weapons/weapon_ak47.tres")
	glock = load("res://Weapons/weapon_glock18.tres")
	knife = load("res://Weapons/weapon_knife.tres")
	m67 = load("res://Weapons/weapon_m67.tres")
	movement = MovementController.new()
	add_child_autofree(movement)
	manager = null


func after_each() -> void:
	Input.action_release("fire")


# ---- 夹具 ----
func _build_manager(slots: Array[WeaponResource]) -> WeaponManager:
	var m := WeaponManager.new()
	add_child_autofree(m)
	m.auto_switch_after_throw = false  # 机制单测隔离投掷流程（自动切回由专门测试覆盖）
	m.setup(slots, movement)
	watch_signals(m)
	return m


func _fast_ak() -> WeaponResource:
	var res: WeaponResource = ak.duplicate()
	res.rpm = 60000  # 单发间隔 0.001s < 物理帧 → 按住每帧可开火
	res.reload_time = 0.05
	return res


func _deploy_frames(res: WeaponResource) -> int:
	# deploy 计时在 _physics_process（60Hz）：0.3s → 18 帧；+2 帧余量
	return int(ceil(res.deploy_time * float(Engine.physics_ticks_per_second))) + 2


# ================= 1. 槽位与状态机 =================
func test_initial_slot_zero_active() -> void:
	manager = _build_manager([ak, glock, knife, m67])
	assert_eq(manager.get_current_slot(), 0, "初始槽位 0（primary）")
	assert_eq(manager.get_state(), WeaponManager.State.ACTIVE, "setup 后武器就绪（ACTIVE）")
	assert_almost_eq(movement.speed_modifier, ak.mobility / 250.0, 0.001,
			"初始移速写入 AK（215/250 = 0.86）")


func test_switch_updates_slot_and_emits_signals() -> void:
	manager = _build_manager([ak, glock, knife, m67])
	manager.switch_to(1)
	assert_eq(manager.get_current_slot(), 1, "切到 secondary（Glock）")
	assert_eq(manager.get_state(), WeaponManager.State.DEPLOYING, "切枪 → DEPLOYING")
	assert_signal_emitted_with_parameters(manager, "weapon_switched", [1])
	assert_signal_emitted_with_parameters(manager, "weapon_ammo_updated",
			[1, glock.magazine, glock.max_ammo])


func test_switch_same_slot_noop() -> void:
	manager = _build_manager([ak, glock, knife, m67])
	manager.switch_to(0)
	assert_eq(manager.get_current_slot(), 0, "槽位不变")
	assert_eq(manager.get_state(), WeaponManager.State.ACTIVE, "状态不变（无 deploy）")
	assert_signal_emit_count(manager, "weapon_switched", 0, "不发 weapon_switched")


func test_next_weapon_cycles_0_to_3_to_0() -> void:
	manager = _build_manager([ak, glock, knife, m67])
	manager.next_weapon()
	assert_eq(manager.get_current_slot(), 1, "0 → 1")
	manager.next_weapon()
	assert_eq(manager.get_current_slot(), 2, "1 → 2")
	manager.next_weapon()
	assert_eq(manager.get_current_slot(), 3, "2 → 3")
	manager.next_weapon()
	assert_eq(manager.get_current_slot(), 0, "3 → 0")


func test_next_weapon_skips_empty_slots() -> void:
	manager = _build_manager([ak, null, knife, m67])
	manager.switch_to(1)  # 空槽位：无操作
	assert_eq(manager.get_current_slot(), 0, "切空槽位无操作")
	manager.next_weapon()  # 0 → 1（空）→ 2
	assert_eq(manager.get_current_slot(), 2, "滚轮跳过空槽位")


func test_deploy_delay_blocks_fire_then_allows() -> void:
	manager = _build_manager([ak, glock, knife, m67])
	var glock_core: WeaponCore = manager.get_core(1)
	assert_almost_eq(glock.deploy_time, 0.3, 0.001, "Glock deploy 0.3s（.tres 参数化）")
	manager.switch_to(1)
	# DEPLOYING 期间按下开火 → 无效（若 Manager 违规转发，半自动沿在第 2 帧即消费 → 弹匣减）
	Input.action_press("fire")
	await wait_physics_frames(3)  # 50ms < 300ms
	Input.action_release("fire")
	assert_almost_eq(glock_core.get_ammo().x, float(glock.magazine), 0.001,
			"deploy 期间开火无效（弹匣未减）")
	# deploy 完成 → ACTIVE
	await wait_physics_frames(_deploy_frames(glock))
	assert_eq(manager.get_state(), WeaponManager.State.ACTIVE, "deploy 完成 → ACTIVE")
	# ACTIVE 后开火有效（半自动：按下 → 下一物理帧沿检测 → 1 发）
	Input.action_press("fire")
	await wait_physics_frames(2)
	Input.action_release("fire")
	assert_almost_eq(glock_core.get_ammo().x, float(glock.magazine - 1), 0.001,
			"deploy 后开火 1 发")


func test_deploy_blocks_reload_and_aim() -> void:
	manager = _build_manager([ak, glock, knife, m67])
	var glock_core: WeaponCore = manager.get_core(1)
	manager.switch_to(1)
	manager.start_reload()
	assert_false(glock_core.is_reloading(), "DEPLOYING 期间换弹无效")
	manager.set_aim(true)
	assert_false(glock_core._ads_active, "DEPLOYING 期间机瞄无效")  # WeaponCore 无公开 getter，读私有字段
	await wait_physics_frames(_deploy_frames(glock))
	manager.set_aim(true)
	assert_true(glock_core._ads_active, "ACTIVE 后机瞄生效")
	manager.set_aim(false)
	assert_false(glock_core._ads_active, "ACTIVE 后机瞄可关闭")


# ================= 2. 换弹/开火中断 =================
func test_switch_during_reload_interrupts_and_keeps_ammo() -> void:
	var fast := _fast_ak()
	manager = _build_manager([fast, glock, knife, m67])
	var ak_core: WeaponCore = manager.get_core(0)
	var reload_finished_count := 0
	ak_core.reload_finished.connect(func() -> void: reload_finished_count += 1)
	Input.action_press("fire")
	await wait_physics_frames(1)  # 全自动：按住 1 帧 → 1 发
	Input.action_release("fire")
	await wait_physics_frames(1)
	assert_almost_eq(ak_core.get_ammo().x, float(fast.magazine - 1), 0.001, "开火 1 发 → 29")
	manager.start_reload()
	assert_eq(manager.get_state(), WeaponManager.State.RELOADING, "换弹 → RELOADING")
	assert_true(ak_core.is_reloading(), "AK 换弹中")
	manager.switch_to(1)  # 换弹中切枪 → 打断
	assert_false(ak_core.is_reloading(), "切枪打断换弹")
	assert_eq(manager.get_state(), WeaponManager.State.DEPLOYING, "切枪后 DEPLOYING")
	await wait_physics_frames(10)  # 若未打断：0.05s 换弹早已完成 → reload_finished 会被捕获
	assert_eq(reload_finished_count, 0, "打断不发 reload_finished")
	assert_almost_eq(ak_core.get_ammo().x, float(fast.magazine - 1), 0.001,
			"弹匣保持 29（弹药不返还）")
	assert_almost_eq(ak_core.get_ammo().y, float(fast.max_ammo), 0.001, "备弹保持 120")


func test_switch_during_fire_interrupts_firing() -> void:
	manager = _build_manager([_fast_ak(), glock, knife, m67])
	var ak_core: WeaponCore = manager.get_core(0)
	Input.action_press("fire")
	await wait_physics_frames(2)  # 全自动按住：每帧 1 发 → 2 发
	assert_almost_eq(ak_core.get_ammo().x, float(ak.magazine - 2), 0.001, "按住 2 帧开火 2 发")
	manager.switch_to(1)  # 开火中切枪（仍按住）→ 立即中断
	await wait_physics_frames(5)  # DEPLOYING 期间继续按住
	assert_almost_eq(ak_core.get_ammo().x, float(ak.magazine - 2), 0.001, "切枪后 AK 立即停火")
	await wait_physics_frames(_deploy_frames(glock))
	assert_almost_eq(ak_core.get_ammo().x, float(ak.magazine - 2), 0.001,
			"deploy 完成后 AK 仍不开火（已切到 Glock）")
	Input.action_release("fire")


# ================= 3. 弹药总账 =================
func test_reload_finish_emits_ammo_updated_and_active() -> void:
	var fast := _fast_ak()
	manager = _build_manager([fast, glock, knife, m67])
	var ak_core: WeaponCore = manager.get_core(0)
	Input.action_press("fire")
	await wait_physics_frames(1)
	Input.action_release("fire")
	await wait_physics_frames(1)
	manager.start_reload()
	assert_eq(manager.get_state(), WeaponManager.State.RELOADING)
	await wait_physics_frames(10)  # > 0.05s 换弹完成
	assert_eq(manager.get_state(), WeaponManager.State.ACTIVE, "换弹完成 → ACTIVE")
	assert_signal_emit_count(manager, "weapon_ammo_updated", 1, "换弹完成发一次弹药更新")
	assert_signal_emitted_with_parameters(manager, "weapon_ammo_updated",
			[0, fast.magazine, fast.max_ammo - 1])
	assert_almost_eq(ak_core.get_ammo().x, float(fast.magazine), 0.001, "弹匣满 30")


# ================= 3b. 开镜自动取消（M1.5 用户反馈修复） =================
func test_reload_cancels_ads() -> void:
	# 开镜期间换弹 → 自动取消开镜（CS 式）：换弹开始即退出瞄准（Manager 跟踪 + 核心标志双复位）。
	var fast := _fast_ak()
	manager = _build_manager([fast, glock, knife, m67])
	var ak_core: WeaponCore = manager.get_core(0)
	Input.action_press("fire")  # 打 1 发让弹匣不满（满弹匣 start_reload 被守卫拦截）
	await wait_physics_frames(1)
	Input.action_release("fire")
	await wait_physics_frames(1)
	manager.set_aim(true)
	assert_true(manager._ads_active, "前置：开镜中（读私有字段，同 test_deploy_blocks_reload_and_aim）")
	assert_true(ak_core._ads_active, "前置：核心 ADS 激活")
	manager.start_reload()
	assert_eq(manager.get_state(), WeaponManager.State.RELOADING, "进入换弹")
	assert_false(manager._ads_active, "换弹开始 → 开镜自动取消（Manager 跟踪）")
	assert_false(ak_core._ads_active, "换弹开始 → 核心 ADS 复位")


func test_switch_cancels_ads() -> void:
	# 开镜期间切枪 → 自动取消开镜（CS 式：换武器退出瞄准，防 FOV 卡在开镜）。
	manager = _build_manager([ak, glock, knife, m67])
	var ak_core: WeaponCore = manager.get_core(0)
	manager.set_aim(true)
	assert_true(manager._ads_active, "前置：开镜中")
	manager.switch_to(1)
	assert_false(manager._ads_active, "切枪 → 开镜自动取消（Manager 跟踪）")
	assert_false(ak_core._ads_active, "切枪 → 核心 ADS 复位")


# ================= 4. 移速联动 =================
func test_speed_modifier_tracks_mobility() -> void:
	manager = _build_manager([ak, glock, knife, m67])
	assert_almost_eq(movement.speed_modifier, ak.mobility / 250.0, 0.001, "初始 AK 215/250 = 0.86")
	manager.switch_to(2)  # 刀
	assert_almost_eq(movement.speed_modifier, knife.mobility / 250.0, 0.001, "刀 250/250 = 1.0")
	assert_almost_eq(manager.get_speed_modifier(), knife.mobility / 250.0, 0.001, "getter 同步")
	manager.switch_to(3)  # M67
	assert_almost_eq(movement.speed_modifier, m67.mobility / 250.0, 0.001, "M67 245/250 = 0.98")
	manager.switch_to(1)  # Glock
	assert_almost_eq(movement.speed_modifier, glock.mobility / 250.0, 0.001, "Glock 240/250 = 0.96")


func test_speed_modifier_applies_immediately_during_deploy() -> void:
	manager = _build_manager([ak, glock, knife, m67])
	manager.switch_to(3)  # M67（deploy 0.5s）
	assert_eq(manager.get_state(), WeaponManager.State.DEPLOYING, "切枪后立即 DEPLOYING")
	assert_almost_eq(movement.speed_modifier, m67.mobility / 250.0, 0.001,
			"DEPLOYING 期间移速立即生效（CS2 式）")


# ================= 5. M67 投掷占位 =================
func test_m67_throw_enters_throwing_and_deducts_ammo() -> void:
	manager = _build_manager([ak, glock, knife, m67])
	var m67_core: WeaponCore = manager.get_core(3)
	assert_almost_eq(m67.deploy_time, 0.5, 0.001, "M67 deploy 0.5s（.tres 参数化）")
	manager.switch_to(3)
	await wait_physics_frames(_deploy_frames(m67))  # 0.5s = 30 帧
	assert_eq(manager.get_state(), WeaponManager.State.ACTIVE, "M67 deploy 完成")
	Input.action_press("fire")
	await wait_physics_frames(2)
	Input.action_release("fire")
	assert_eq(manager.get_state(), WeaponManager.State.THROWING, "M67 开火 = 投掷 → THROWING")
	assert_almost_eq(m67_core.get_ammo().x, 0.0, 0.001, "投掷扣减占位：手中弹匣 1 → 0（不可再投）")
	assert_almost_eq(m67_core.get_ammo().y, 1.0, 0.001, "备弹 1 保留（max_ammo=1 的携带数，任务 4 接真实 Grenade）")
	assert_signal_emitted_with_parameters(manager, "weapon_ammo_updated", [3, 0, 1])
	# THROWING 中再开火：无操作（不重复扣减）
	var ammo_updates_before: int = get_signal_emit_count(manager, "weapon_ammo_updated")
	manager.try_fire()
	assert_eq(manager.get_state(), WeaponManager.State.THROWING, "THROWING 中保持")
	assert_eq(get_signal_emit_count(manager, "weapon_ammo_updated"), ammo_updates_before,
			"不重复扣减")
	# THROWING 中可切枪离开（任务 4 接真实 Grenade 的前提）
	manager.switch_to(0)
	assert_eq(manager.get_current_slot(), 0, "投掷后可切回 primary")
	assert_eq(manager.get_state(), WeaponManager.State.DEPLOYING, "切枪 → DEPLOYING")


func test_switch_during_throw_cancels_and_refunds_ammo() -> void:
	# 审查重要修复：THROWING（引信）期间切枪必须先取消投掷（弹药返还）再切换——
	# 否则弹药已扣 + _throw_pending 残留 + Grenade 永不生成 = 静默丢雷，
	# 且冷却 INF 节流锁死后续投掷（CS2 切枪收雷保留，取消不消耗弹药）。
	manager = _build_manager([ak, glock, knife, m67])
	var m67_core: WeaponCore = manager.get_core(3)
	manager.switch_to(3)
	await wait_physics_frames(_deploy_frames(m67))
	assert_eq(manager.get_state(), WeaponManager.State.ACTIVE, "前置：M67 deploy 完成")
	Input.action_press("fire")
	await wait_physics_frames(2)
	assert_eq(manager.get_state(), WeaponManager.State.THROWING, "前置：fire 按住 = 引信 THROWING")
	assert_almost_eq(m67_core.get_ammo().x, 0.0, 0.001, "前置：引信阶段弹匣已扣 1→0")
	# THROWING 期间切枪：先取消（返还弹药 + ammo 信号）再切换，不静默丢雷
	var ammo_updates_before: int = get_signal_emit_count(manager, "weapon_ammo_updated")
	Input.action_release("fire")  # 切枪前松开（模拟真实输入；THROWING 取消不依赖 fire 状态）
	manager.switch_to(1)
	assert_eq(manager.get_current_slot(), 1, "切到 secondary（Glock）")
	assert_eq(manager.get_state(), WeaponManager.State.DEPLOYING, "切换后 DEPLOYING")
	assert_almost_eq(m67_core.get_ammo().x, 1.0, 0.001, "切枪取消投掷：弹匣返还 1（不消耗）")
	assert_almost_eq(m67_core.get_ammo().y, 1.0, 0.001, "备弹保持 1")
	assert_eq(get_signal_emit_count(manager, "weapon_ammo_updated"), ammo_updates_before + 2,
			"取消（返还）与切枪各发一次弹药更新")
	# 切回 M67 能再次投掷（冷却 INF 必须重置，否则永远锁死）
	manager.switch_to(3)
	await wait_physics_frames(_deploy_frames(m67))
	assert_eq(manager.get_state(), WeaponManager.State.ACTIVE, "切回 M67 deploy 完成")
	Input.action_press("fire")
	await wait_physics_frames(2)
	assert_eq(manager.get_state(), WeaponManager.State.THROWING, "可再次进入引信（未锁死）")
	assert_almost_eq(m67_core.get_ammo().x, 0.0, 0.001, "再次投掷扣减")
	Input.action_release("fire")


# ================= 6. M1 任务8：投掷交互重构（长按持雷 + 抛物线预览，无限持雷） =================
func _with_camera() -> Camera3D:
	var cam := Camera3D.new()
	add_child_autofree(cam)
	cam.global_position = Vector3(0, 1, 0)
	cam.look_at(Vector3(0, 1, -5), Vector3.UP)
	cam.current = true  # 注册为当前视口相机（Manager._find_camera 经 viewport 取到）
	return cam


func _deploy_m67() -> void:
	manager.switch_to(3)
	await wait_physics_frames(_deploy_frames(m67))


func _find_grenade() -> Grenade:
	# M1 任务14：脱手后 Grenade 挂场景根（不随玩家）——搜索范围从 manager 子节点改为根
	var root := get_tree().root
	for child in root.get_children():
		if child is Grenade:
			return child
	return null


func _trajectory() -> ThrowTrajectory:
	return manager.get_node_or_null("ThrowTrajectory") as ThrowTrajectory


func test_throw_hold_shows_trajectory_release_hides() -> void:
	manager = _build_manager([ak, glock, knife, m67])
	await _deploy_m67()
	assert_eq(manager.get_state(), WeaponManager.State.ACTIVE, "前置：M67 deploy 完成")
	var traj := _trajectory()
	assert_not_null(traj, "管理器持有 ThrowTrajectory")
	assert_false(traj.visible, "初始隐藏")
	Input.action_press("fire")
	await wait_physics_frames(2)
	assert_eq(manager.get_state(), WeaponManager.State.THROWING, "按住 fire → THROWING")
	assert_true(traj.visible, "THROWING 中抛物线可见")
	Input.action_release("fire")
	await wait_physics_frames(1)
	assert_eq(manager.get_state(), WeaponManager.State.ACTIVE, "松开 → 投出回 ACTIVE")
	assert_false(traj.visible, "投出后抛物线隐藏")


func test_throw_release_spawns_grenade_along_camera() -> void:
	_with_camera()
	manager = _build_manager([ak, glock, knife, m67])
	await _deploy_m67()
	Input.action_press("fire")
	await wait_physics_frames(2)
	assert_eq(manager.get_state(), WeaponManager.State.THROWING, "前置：引信 THROWING")
	# 抛物线预览实时沿相机视向：起点 = 相机位置，水平沿 -Z（相机 look_at (0,1,-5)）
	var traj := _trajectory()
	assert_eq(traj.points[0], Vector3(0, 1, 0), "预览起点 = 相机位置（实时更新）")
	assert_lt(traj.points[1].z, -0.2, "预览沿相机视向 -Z")
	Input.action_release("fire")
	await wait_physics_frames(2)
	var grenade := _find_grenade()
	assert_not_null(grenade, "松开后生成真实 Grenade")
	assert_eq(grenade.resource, m67, "Grenade 携带 M67 资源（引信/爆炸数值）")
	assert_eq(grenade.get_parent(), get_tree().root,
			"M1 任务14：脱手后挂场景根（非玩家子节点，不随玩家运动）")
	# RigidBody 出手后已被物理积分（重力 + 项目 linear_damp）——容差断言方向与强度：
	#   -Z 点积不受重力影响（仅 y 分量受扰），始终 > 14
	var vel := grenade.linear_velocity
	assert_gt(vel.dot(Vector3(0, 0, -1)), 14.0, "出手方向沿相机视向 -Z")
	assert_between(vel.length(), manager.throw_strength * 0.95, manager.throw_strength * 1.05,
			"出手速度 ≈ throw_strength")
	assert_lt(grenade.global_position.z, -0.15, "沿 -Z 向前飞出")
	assert_lt(grenade.global_position.y, 1.0, "重力已作用于出手高度")


func test_throw_primed_signal_emitted_on_fuse_stage() -> void:
	# M1 任务14：fire 按下（引信开始）发 throw_primed（握持系统左手抽拉环动画触发）
	manager = _build_manager([ak, glock, knife, m67])
	await _deploy_m67()
	Input.action_press("fire")
	await wait_physics_frames(2)
	assert_signal_emitted(manager, "throw_primed", "fire 按下 → throw_primed（引信开始）")
	Input.action_release("fire")


func test_throw_click_press_release_throws_naturally() -> void:
	# 点击（按下即松）：天然投出——按下瞬间进入 THROWING，下一物理帧松开即出手（消除点击无反应）
	_with_camera()
	manager = _build_manager([ak, glock, knife, m67])
	await _deploy_m67()
	Input.action_press("fire")
	await wait_physics_frames(1)
	Input.action_release("fire")
	await wait_physics_frames(1)
	assert_eq(manager.get_state(), WeaponManager.State.ACTIVE, "点击投出回 ACTIVE")
	assert_not_null(_find_grenade(), "点击后生成 Grenade")


func test_throw_aim_cancel_hides_trajectory_and_refunds() -> void:
	manager = _build_manager([ak, glock, knife, m67])
	await _deploy_m67()
	Input.action_press("fire")
	await wait_physics_frames(2)
	assert_eq(manager.get_state(), WeaponManager.State.THROWING, "前置：引信 THROWING")
	var traj := _trajectory()
	assert_true(traj.visible, "前置：抛物线可见")
	var m67_core: WeaponCore = manager.get_core(3)
	assert_almost_eq(m67_core.get_ammo().x, 0.0, 0.001, "前置：引信阶段弹药已扣")
	manager.set_aim(true)  # 右键取消
	assert_eq(manager.get_state(), WeaponManager.State.ACTIVE, "取消回 ACTIVE")
	assert_false(traj.visible, "取消后抛物线隐藏")
	assert_almost_eq(m67_core.get_ammo().x, 1.0, 0.001, "取消弹药返还")
	Input.action_release("fire")


func test_throw_infinite_hold_no_timeout() -> void:
	# 无限持雷：持续按住 5s（300 物理帧）不自动投出（无超时，用户拍板）
	manager = _build_manager([ak, glock, knife, m67])
	await _deploy_m67()
	Input.action_press("fire")
	await wait_physics_frames(2)
	assert_eq(manager.get_state(), WeaponManager.State.THROWING, "前置：引信 THROWING")
	var m67_core: WeaponCore = manager.get_core(3)
	await wait_physics_frames(300)  # 5s
	assert_eq(manager.get_state(), WeaponManager.State.THROWING, "持雷 5s 仍 THROWING（无限持雷）")
	assert_almost_eq(m67_core.get_ammo().x, 0.0, 0.001, "弹药仍扣减（手中持雷）")
	assert_null(_find_grenade(), "未自动投出")
	Input.action_release("fire")


# ================= 6.5 M1.5：投掷后自动切回主武器 =================
func test_throw_auto_switches_to_primary() -> void:
	# 用户拍板：投掷出手后自动切回主武器（槽位 0），CS 式。
	manager = _build_manager([ak, glock, knife, m67])
	manager.auto_switch_after_throw = true  # 开启（游戏默认；机制测试默认关闭隔离）
	await _deploy_m67()
	assert_eq(manager.get_current_slot(), 3, "前置：持 M67")
	Input.action_press("fire")
	await wait_physics_frames(2)
	assert_eq(manager.get_state(), WeaponManager.State.THROWING, "引信 THROWING")
	Input.action_release("fire")  # 出手
	await wait_physics_frames(2)
	assert_eq(manager.get_current_slot(), 0, "投掷后自动切回主武器（槽位 0）")
	assert_eq(manager.get_state(), WeaponManager.State.DEPLOYING, "切回主武器 → DEPLOYING")
	await wait_physics_frames(_deploy_frames(ak))
	assert_eq(manager.get_state(), WeaponManager.State.ACTIVE, "主武器 deploy 完成回 ACTIVE")


# ================= 7. M1 任务8：弹孔系统（命中点 quad 面片，M1.5 起取消数量上限） =================
func test_hit_landed_spawns_bullet_hole_at_hit_point() -> void:
	manager = _build_manager([ak, glock, knife, m67])
	var ak_core: WeaponCore = manager.get_core(0)
	ak_core.hit_landed.emit(null, 36.0, Vector3(1, 2, 3), Vector3.UP)
	var holes: Array[BulletHole] = []
	for child in manager.get_children():
		if child is BulletHole:
			holes.append(child)
	assert_eq(holes.size(), 1, "命中生成 1 个弹孔")
	# M1.5：弹孔沿法线外移 0.02（防嵌入）——y = 命中点 2 + 法线 UP*0.02
	assert_almost_eq(holes[0].global_position.x, 1.0, 0.001, "弹孔 x = 实际命中点")
	assert_almost_eq(holes[0].global_position.y, 2.02, 0.001, "弹孔 y = 命中点沿法线外移 0.02")
	assert_almost_eq(holes[0].global_position.z, 3.0, 0.001, "弹孔 z = 实际命中点")


func test_bullet_hole_no_cap_all_persist() -> void:
	# M1.5：取消数量上限（用户拍板——弹孔不设场景最大存在数，由 30s 生命周期约束累积）。
	# 超过旧上限 200 也不淘汰最旧。
	manager = _build_manager([ak, glock, knife, m67])
	var count := 250
	for i in count:
		manager._spawn_bullet_hole(Vector3(i, 0, 0), Vector3.UP)
	assert_eq(manager._bullet_holes.size(), count, "无上限：250 个弹孔全部保留（不淘汰最旧）")


# ================= 8. M1 任务15：换弹排队 + 空仓自动换弹（CC0 gun.gd 照搬） =================
func test_reload_queued_during_fire_starts_after_burst() -> void:
	# 射击中按 R → _queued_reload 排队（animation_player.queue("reload") 等价）：
	# 不立即换弹，射完（松开 fire）自动 start_reload
	var fast := _fast_ak()
	fast.reload_time = 0.5  # 换弹时长拉长：RELOADING 状态可观测
	manager = _build_manager([fast, glock, knife, m67])
	var ak_core: WeaponCore = manager.get_core(0)
	Input.action_press("fire")
	await wait_physics_frames(1)  # 全自动：按住 1 帧 → 1 发
	manager.start_reload()  # 射击中按 R：排队
	assert_eq(manager.get_state(), WeaponManager.State.ACTIVE, "射击中按 R 不立即换弹（排队）")
	assert_true(manager._queued_reload, "排队标志置位")
	assert_false(ak_core.is_reloading(), "排队中不进入换弹")
	Input.action_release("fire")
	await wait_physics_frames(2)  # 射完（松开）→ 自动 start_reload
	assert_eq(manager.get_state(), WeaponManager.State.RELOADING, "射完自动换弹")
	assert_true(ak_core.is_reloading(), "核心进入换弹")
	assert_false(manager._queued_reload, "队列消费后清除")
	await wait_physics_frames(35)  # 0.5s 换弹完成
	assert_eq(manager.get_state(), WeaponManager.State.ACTIVE, "换弹完成回 ACTIVE")
	assert_almost_eq(ak_core.get_ammo().x, float(fast.magazine), 0.001, "弹匣补满")


func test_empty_mag_auto_reloads_with_reserve() -> void:
	# 空仓（out_of_ammo）→ 自动换弹（备弹 > 0，CC0：current_ammo == 0 → play("reload")）
	var small: WeaponResource = ak.duplicate()
	small.magazine = 1
	small.max_ammo = 30
	small.rpm = 60000
	small.reload_time = 0.5
	manager = _build_manager([small, glock, knife, m67])
	var core: WeaponCore = manager.get_core(0)
	Input.action_press("fire")
	await wait_physics_frames(2)  # 第 1 帧开火（1→0），第 2 帧空仓 out_of_ammo
	assert_almost_eq(core.get_ammo().x, 0.0, 0.001, "前置：弹匣打空")
	assert_eq(manager.get_state(), WeaponManager.State.RELOADING, "空仓自动换弹（即使仍按住 fire）")
	assert_true(core.is_reloading(), "核心进入换弹")
	Input.action_release("fire")


func test_empty_mag_no_auto_reload_without_reserve() -> void:
	# 备弹 0：空仓不自动换（无可换弹药）
	var small: WeaponResource = ak.duplicate()
	small.magazine = 1
	small.max_ammo = 0
	small.rpm = 60000
	manager = _build_manager([small, glock, knife, m67])
	var core: WeaponCore = manager.get_core(0)
	Input.action_press("fire")
	await wait_physics_frames(2)
	Input.action_release("fire")
	assert_eq(manager.get_state(), WeaponManager.State.ACTIVE, "备弹 0 空仓不自动换弹")
	assert_false(core.is_reloading(), "不进入换弹")


# ================= 9. M1 任务15：开火 → Head 双层后坐力接线（recoil_val .tres 参数化） =================
func _build_head() -> Node3D:
	# 手动构建 Head（同 test_controller_weapon 约定）：Head.gd + Camera3D 子节点 + owner
	var head := Node3D.new()
	head.name = "Head"
	var cam := Camera3D.new()
	cam.name = "Camera"
	head.add_child(cam)
	head.set_script(load("res://Player/Head.gd"))
	var owner_node := Node3D.new()
	owner_node.add_child(head)
	head.owner = owner_node
	add_child_autofree(owner_node)
	return head


func test_shot_fired_applies_recoil_val_to_head() -> void:
	# 开火 → Manager 将当前槽位 recoil_val（.tres）叠加到 Head.target_rotation（双层 lerp 入口）
	manager = _build_manager([ak, glock, knife, m67])
	var head := _build_head()
	manager.set_head(head)
	manager.get_core(0).shot_fired.emit(29)  # AK 开火信号
	assert_almost_eq(head.target_rotation.x, ak.recoil_val.x, 0.0001,
			"AK 开火 → Head target_rotation.x = recoil_val.x（0.06）")
	assert_between(head.target_rotation.y, -ak.recoil_val.y, ak.recoil_val.y,
			"Y 抖动在 ±recoil_val.y 内")
	assert_between(head.target_rotation.z, -ak.recoil_val.z, ak.recoil_val.z,
			"Z 抖动在 ±recoil_val.z 内")


# ================= 10. M1 任务15：曳光弹生成（CC0 bullet_tracer） =================
func test_tracer_fired_spawns_tracer_node() -> void:
	# 核心发 tracer_fired → Manager 生成 Tracer（枪口→命中点线条，0.1s 淡出自清）
	manager = _build_manager([ak, glock, knife, m67])
	manager.get_core(0).tracer_fired.emit(Vector3(0, 1, 0), Vector3(0, 1, -10))
	var tracers: Array[Tracer] = []
	for child in manager.get_children():
		if child is Tracer:
			tracers.append(child)
	assert_eq(tracers.size(), 1, "生成 1 个 Tracer")
	if tracers.size() == 1:
		assert_almost_eq(tracers[0].global_position.z, -5.0, 0.001, "Tracer 位于线段中点")
	await wait_physics_frames(10)  # 0.167s > 0.1s
	var alive: Array[Tracer] = []
	for child in manager.get_children():
		if child is Tracer:
			alive.append(child)
	assert_eq(alive.size(), 0, "0.1s 后淡出自清")


# ================= 11. M1 任务15：hitmarker 触发（命中敌人非靶子） =================
func test_hit_enemy_emits_enemy_hit() -> void:
	# 命中敌人（hit_landed）→ enemy_hit 信号（HUD hitmarker 消费）
	manager = _build_manager([ak, glock, knife, m67])
	var enemy: Enemy = load("res://Levels/Enemy/Enemy.tscn").instantiate()
	add_child_autofree(enemy)
	var enemy_hits: Array[int] = []  # lambda 按值捕获局部原始值：用数组承载计数（同 test_grenade 约定）
	manager.enemy_hit.connect(func() -> void: enemy_hits.append(1))
	manager._on_hit_landed(enemy, 36.0, Vector3(0, 1, -3), Vector3(0, 0, 1))
	assert_eq(enemy_hits.size(), 1, "命中敌人 → enemy_hit 发 1 次")


func test_hit_target_does_not_emit_enemy_hit() -> void:
	# 训练靶子（Target 非 Enemy）：命中不触发 hitmarker
	manager = _build_manager([ak, glock, knife, m67])
	var target := Target.new()
	add_child_autofree(target)
	var enemy_hits: Array[int] = []
	manager.enemy_hit.connect(func() -> void: enemy_hits.append(1))
	manager._on_hit_landed(target, 36.0, Vector3(0, 1, -3), Vector3(0, 0, 1))
	assert_eq(enemy_hits.size(), 0, "命中训练靶子（非敌人）不发 enemy_hit")


# ================= 12. M1 任务15：弹孔挂被击中 collider 下（随物体动） =================
func test_bullet_hole_parents_under_hit_collider() -> void:
	# hit_landed 带目标 → 弹孔挂到被击中 collider 下（GarbajYT decals），随物体动
	manager = _build_manager([ak, glock, knife, m67])
	var enemy: Enemy = load("res://Levels/Enemy/Enemy.tscn").instantiate()
	add_child_autofree(enemy)
	enemy.global_position = Vector3(0, 0, -5)
	manager._on_hit_landed(enemy, 36.0, Vector3(0, 1, -5), Vector3(0, 0, 1))
	var under_manager: Array[BulletHole] = []
	for child in manager.get_children():
		if child is BulletHole:
			under_manager.append(child)
	assert_eq(under_manager.size(), 0, "弹孔不在 manager 下（已挂到 collider）")
	var hole: BulletHole = null
	for child in enemy.get_children():
		if child is BulletHole:
			hole = child
	assert_not_null(hole, "弹孔挂在被击中 collider 下")
	if hole == null:
		return
	assert_almost_eq(hole.global_position.y, 1.0, 0.001, "弹孔位置 = 命中点（父级换算）")
	enemy.global_position = Vector3(3, 0, -7)  # 敌人移动 → 弹孔随动
	await wait_physics_frames(1)
	assert_almost_eq(hole.global_position.x, 3.0, 0.001, "collider 移动 → 弹孔随动")
	assert_almost_eq(hole.global_position.y, 1.0, 0.001, "随动 y 保持命中高度")


func test_bullet_hole_no_cap_parented_persist() -> void:
	# M1.5：取消数量上限——挂 collider 的弹孔超过旧上限 200 也不淘汰、不从父节点移除
	manager = _build_manager([ak, glock, knife, m67])
	var enemy: Enemy = load("res://Levels/Enemy/Enemy.tscn").instantiate()
	add_child_autofree(enemy)
	var count := 250
	for i in count:
		manager._spawn_bullet_hole(Vector3(i, 0, 0), Vector3.UP, enemy)
	assert_eq(manager._bullet_holes.size(), count, "无上限：250 个弹孔全部保留（不淘汰）")
	var holes_under_enemy := 0
	for child in enemy.get_children():
		if child is BulletHole:
			holes_under_enemy += 1
	assert_eq(holes_under_enemy, count, "collider 下 250 个全部保留（无淘汰移除）")
	for child in enemy.get_children():
		if child is BulletHole:
			child.queue_free()  # 清理：防跨测试残留


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
	assert_almost_eq(traj.points[1].y, (lp["origin"] as Vector3).y + v0.y * dt - g * dt * dt, 0.001,
			"预览 y 与 launch 一致（重力同源）")
	assert_almost_eq(traj.points[1].z, (lp["origin"] as Vector3).z + v0.z * dt, 0.001, "预览 z 与 launch 一致")
	Input.action_release("fire")
	await wait_physics_frames(2)
	var grenade := _find_grenade()
	assert_not_null(grenade, "松开后生成真实 Grenade")
	assert_almost_eq(grenade.global_position.x, (lp["origin"] as Vector3).x, 0.3,
			"出手位置 = 发射原点（物理 2 帧位移容差）")
	assert_almost_eq(grenade.global_position.z, (lp["origin"] as Vector3).z, 1.0, "出手位置 z = 发射原点（2~3 物理帧积分位移 ≤0.75m 容差）")


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
