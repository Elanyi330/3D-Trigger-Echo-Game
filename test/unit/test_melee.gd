# test/unit/test_melee.gd
# M1 任务10：近战完整实现测试（TDD RED 先行，spec §9.5 + task-10 brief）
#
# 行为（brief 任务10 §核心要求）：
#   - fire 分发 MELEE 分支：左键轻击（修复"左键完全无反应"）
#   - 轻击伤害 melee_primary_damage(40) → 连击 melee_secondary_damage(25) 交替；间隔 melee_light_time(0.4s)
#   - 右键重刺：melee_stab_damage(65)；间隔 melee_heavy_time(1.0s)
#   - 背刺：目标朝向与攻击者方向夹角 > melee_backstab_angle(150°) → melee_backstab_damage(180 秒杀)
#   - 扇形判定：melee_range(1.5m) × melee_angle(60°)——距离 + 角度过滤
#   - 伤害结算：Target.take_damage 直接调用 + melee_hit(target, damage) 信号
#   - 挥击动画（WeaponAnchor）：轻击绕 Y 前挥（0.4s 周期）/ 重刺前刺 + Z 前推（1.0s 周期）
# 全局约束（计划 §4）：数值唯一来源 weapon_*.tres（测试派生期望，不硬编码散值）。
extends GutTest

var manager: WeaponManager
var movement: MovementController
var ak: WeaponResource
var glock: WeaponResource
var knife: WeaponResource
var m67: WeaponResource
var melee  # MeleeController（class_name 由实现提供；按现有测试模式 Variant 持有）
var origin: Node3D
var last_hit_target: Node = null
var last_hit_damage: float = -1.0


func before_each() -> void:
	Input.action_release("fire")  # 防跨测试输入污染
	ak = load("res://Weapons/weapon_ak47.tres")
	glock = load("res://Weapons/weapon_glock18.tres")
	knife = load("res://Weapons/weapon_knife.tres")
	m67 = load("res://Weapons/weapon_m67.tres")
	movement = MovementController.new()
	add_child_autofree(movement)
	manager = WeaponManager.new()
	add_child_autofree(manager)
	manager.setup([ak, glock, knife, m67], movement)
	melee = manager.get_melee_controller()
	# 攻击原点（集成 = 相机；测试直设）：位置 (0,0,0)、默认朝向 -Z
	origin = Node3D.new()
	add_child_autofree(origin)
	melee.origin = origin
	last_hit_target = null
	last_hit_damage = -1.0
	melee.melee_hit.connect(_on_melee_hit)


func after_each() -> void:
	Input.action_release("fire")


func _on_melee_hit(t: Node, d: float) -> void:
	last_hit_target = t
	last_hit_damage = d


# ---- 夹具 ----
func _deploy_frames() -> int:
	return int(ceil(knife.deploy_time * float(Engine.physics_ticks_per_second))) + 2


func _await_cooldown(seconds: float) -> void:
	await wait_physics_frames(int(ceil(seconds * float(Engine.physics_ticks_per_second))) + 2)


func _ready_melee() -> void:
	manager.switch_to(2)
	await wait_physics_frames(_deploy_frames())
	assert_eq(manager.get_state(), WeaponManager.State.ACTIVE, "前置：刀 deploy 完成")


func _set_targets(node: Node) -> void:
	# typed 数组不可协变赋值（Array[Target] → Array[Node] 报错）：显式构建 Array[Node]
	var arr: Array[Node] = [node]
	melee.targets = arr


func _front_target() -> Target:
	# 正面目标：攻击者前方 1m、朝向攻击者（yaw π → 前向 +Z，攻击者在其 -Z 侧 = 正面）
	var t := Target.new()
	add_child_autofree(t)
	t.position = Vector3(0, 0, -1.0)
	t.rotation = Vector3(0, PI, 0)
	_set_targets(t)
	return t


# ================= 1. fire 分发 MELEE 分支（左键修复） =================
func test_light_swing_via_fire_input_hits_with_primary_damage() -> void:
	await _ready_melee()
	var t := _front_target()
	Input.action_press("fire")  # 左键：Manager 物理帧轮询 → MELEE 分支轻击
	await wait_physics_frames(2)
	Input.action_release("fire")
	assert_almost_eq(t.health, 100.0 - knife.melee_primary_damage, 0.001,
			"左键轻击：Target.take_damage(40) → 100-40")
	assert_eq(last_hit_target, t, "melee_hit 目标 = 受击 Target")
	assert_almost_eq(last_hit_damage, knife.melee_primary_damage, 0.001, "melee_hit 伤害 = 40")


# ================= 2. 轻击连击 + 间隔 =================
func test_light_combo_alternates_primary_secondary_primary() -> void:
	await _ready_melee()
	var t := _front_target()
	manager.try_fire()  # 首击 40
	await _await_cooldown(knife.melee_light_time)
	manager.try_fire()  # 连击 25
	await _await_cooldown(knife.melee_light_time)
	manager.try_fire()  # 再首击 40
	assert_almost_eq(t.health,
			100.0 - knife.melee_primary_damage - knife.melee_secondary_damage - knife.melee_primary_damage,
			0.001, "连击交替 40→25→40")


func test_light_swing_blocked_during_cooldown_then_allowed() -> void:
	await _ready_melee()
	var t := _front_target()
	manager.try_fire()
	manager.try_fire()  # 同帧再挥：0.4s 冷却中 → 无效
	assert_almost_eq(t.health, 100.0 - knife.melee_primary_damage, 0.001, "0.4s 冷却内第二击无效")
	await _await_cooldown(knife.melee_light_time)
	manager.try_fire()
	assert_almost_eq(t.health,
			100.0 - knife.melee_primary_damage - knife.melee_secondary_damage, 0.001,
			"冷却后连击生效（第二击 25）")


# ================= 3. 重刺 + 间隔 =================
func test_heavy_stab_deals_stab_damage() -> void:
	await _ready_melee()
	var t := _front_target()
	manager.set_aim(true)  # 右键 = 重刺（刀无机瞄）
	assert_almost_eq(t.health, 100.0 - knife.melee_stab_damage, 0.001, "重刺 65")
	assert_almost_eq(last_hit_damage, knife.melee_stab_damage, 0.001, "melee_hit 伤害 = 65")


func test_heavy_stab_blocked_during_cooldown_then_allowed() -> void:
	await _ready_melee()
	var t := _front_target()
	manager.set_aim(true)
	manager.set_aim(true)  # 同帧再刺：1.0s 冷却中 → 无效
	assert_almost_eq(t.health, 100.0 - knife.melee_stab_damage, 0.001, "1.0s 冷却内第二次重刺无效")
	await _await_cooldown(knife.melee_heavy_time)
	manager.set_aim(true)
	assert_almost_eq(t.health, 100.0 - knife.melee_stab_damage * 2.0, 0.001, "冷却后重刺可再发")


# ================= 4. 背刺 =================
func test_backstab_from_behind_deals_backstab_damage() -> void:
	await _ready_melee()
	# 目标默认朝向 -Z（旋转 0）；攻击者在目标 -Z 侧 = 其背后 → 夹角 180° > 150°
	var t := Target.new()
	add_child_autofree(t)
	t.position = Vector3(0, 0, -1.0)
	_set_targets(t)
	manager.try_fire()
	assert_almost_eq(t.health, 100.0 - knife.melee_backstab_damage, 0.001, "背刺 180 秒杀")
	assert_almost_eq(last_hit_damage, knife.melee_backstab_damage, 0.001, "melee_hit 伤害 = 180")


func test_front_attack_is_not_backstab() -> void:
	await _ready_melee()
	var t := _front_target()  # 目标面向攻击者：夹角 0° → 正常伤害
	manager.try_fire()
	assert_almost_eq(t.health, 100.0 - knife.melee_primary_damage, 0.001, "正面 → 40（非背刺）")


# ================= 5. 扇形判定（距离 + 角度） =================
func test_cone_misses_beyond_range() -> void:
	await _ready_melee()
	var t := Target.new()
	add_child_autofree(t)
	t.position = Vector3(0, 0, -(knife.melee_range + 0.5))  # 2.0m > 1.5m
	t.rotation = Vector3(0, PI, 0)
	_set_targets(t)
	manager.try_fire()
	assert_almost_eq(t.health, 100.0, 0.001, "射程外不命中")


func test_cone_misses_outside_angle() -> void:
	await _ready_melee()
	var t := Target.new()
	add_child_autofree(t)
	var half := deg_to_rad(knife.melee_angle * 0.5)  # 半角 30°
	var d := knife.melee_range * 0.8  # 距离在射程内（1.2m）
	t.position = Vector3(sin(half + deg_to_rad(10.0)) * d, 0.0, -cos(half + deg_to_rad(10.0)) * d)
	t.rotation = Vector3(0, PI, 0)
	_set_targets(t)
	manager.try_fire()
	assert_almost_eq(t.health, 100.0, 0.001, "扇形外（40° > 半角 30°）不命中")


# ================= 6. 挥击动画（WeaponView，M1.5 新表现层） =================
func _build_view_with_models() -> WeaponView:
	var models: Array[PackedScene] = [
		load("res://Assets/Models/Weapons/Rifle/AK47_Echo/AK47_Echo.glb"),
		load("res://Assets/Models/Weapons/Pistol/Glock18_Echo/Glock18_Echo.glb"),
		load("res://Assets/Models/Weapons/Melee/Knife_Echo/Knife_Echo.glb"),
		load("res://Assets/Models/Weapons/Throwable/Grenade_M67_Echo/Grenade_M67_Echo.glb"),
	]
	manager.view_models = models
	var view := WeaponView.new()
	add_child_autofree(view)
	view.setup(manager, movement)
	return view


func test_light_swing_dips_viewmodel_and_returns() -> void:
	var view := _build_view_with_models()
	manager.switch_to(2)
	await wait_physics_frames(_deploy_frames())
	var wm: Node3D = view.view_model.weapon_mount  # M1.5：挥砍作用于 weapon_mount（手臂动态追踪握把）
	assert_not_null(view.view_model.current_weapon, "刀视图模型已挂载")
	var base_pos: Vector3 = wm.position
	var base_rot: Vector3 = wm.rotation
	manager.try_fire()  # 轻击
	await wait_physics_frames(2)  # 挥砍蓄力/挥出中
	var dev := (wm.position - base_pos).length() + (wm.rotation - base_rot).length()
	assert_gt(dev, 0.02, "轻击：武器产生挥砍位移/旋转（CS 斜挥）")
	await _await_cooldown(knife.melee_light_time + 0.3)
	var after := (wm.position - base_pos).length() + (wm.rotation - base_rot).length()
	assert_lt(after, 0.01, "挥击结束回位")


func test_heavy_swing_dips_viewmodel_and_returns() -> void:
	var view := _build_view_with_models()
	manager.switch_to(2)
	await wait_physics_frames(_deploy_frames())
	var wm: Node3D = view.view_model.weapon_mount
	var base_pos: Vector3 = wm.position
	var base_rot: Vector3 = wm.rotation
	manager.set_aim(true)  # 重刺
	await wait_physics_frames(2)  # 回拉/前刺中
	var dev := (wm.position - base_pos).length() + (wm.rotation - base_rot).length()
	assert_gt(dev, 0.02, "重刺：武器产生前刺位移/旋转")
	await _await_cooldown(knife.melee_heavy_time + 0.3)
	var after := (wm.position - base_pos).length() + (wm.rotation - base_rot).length()
	assert_lt(after, 0.01, "重刺结束回位")

