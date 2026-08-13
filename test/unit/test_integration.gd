# test/unit/test_integration.gd
# M1 任务6：L_Main 场景集成测试（TDD RED 先行）
# 行为（brief §交付内容 1+2 + 计划 §5 任务6 步骤 1）：
#   - L_Main 加载：WeaponManager 挂 Player 下（4 资源挂载）、WeaponView 挂 Head 下
#   - 相机路径验证：try_fire 对靶子触发 hit_landed（Manager setup 时缓存相机在真实场景可用）
#   - 切枪更新移速（speed_modifier 生效，数值派生自 .tres）
#   - 弹药 HUD 更新（开火后 Label 文本 = 当前槽位弹匣/备弹，CS 式 "30 / 120"）
#   - 机瞄接线：set_aim → Head.set_ads（FOV ÷ads_multiplier，.tres 数值）
#   - M67 右键取消投掷（THROWING + aim 按下 → 取消、弹药不消耗、回 ACTIVE、不生成投掷物）
#   - Grenade 接线：投掷 → 引信 → 爆炸对靶子伤害（集成层验证 Manager→Grenade 全链路）
# 全局约束（计划 §4）：数值唯一来源 weapon_*.tres；hitscan mask=1 仅 Objects 层。
# 测试提示（brief）：L_Main 用 load() + instantiate() + add_child；hitscan 需要相机 current
# （Head/Camera3D 场景已置 current，setup 在 _ready 中晚于实例化）；物理帧推进 await。
extends GutTest

var level: Node
var manager: WeaponManager
var player: MovementController
var ammo_label: Label
var target_a: StaticBody3D


func before_each() -> void:
	Input.action_release("fire")
	Input.action_release("aim")
	# 防御：清理上一测试残留的场景根手雷（任务14 脱手后挂根，测试树 autofree 不覆盖——
	# 引信继续计时会在本测试中途爆炸干扰伤害断言）
	for child in get_tree().root.get_children():
		if child is Grenade:
			child.queue_free()
	level = load("res://Levels/Main/L_Main.tscn").instantiate()
	add_child_autofree(level)
	manager = level.get_node("Player/WeaponManager")
	player = level.get_node("Player")
	ammo_label = level.get_node("HUD/AmmoLabel")
	target_a = level.get_node("Targets/TargetA")
	await wait_physics_frames(2)  # _ready setup 后物理稳定


func after_each() -> void:
	Input.action_release("fire")
	Input.action_release("aim")


# ---- 夹具 ----

func _deploy_frames(res: WeaponResource) -> int:
	# deploy 计时在 _physics_process（60Hz）：0.5s → 30 帧；+2 帧余量
	return int(ceil(res.deploy_time * float(Engine.physics_ticks_per_second))) + 2


func _count_grenades_in_scene() -> int:
	# M1 任务14：脱手后 Grenade 挂场景根（不随玩家）——搜索范围从 manager 子节点改为根
	var count := 0
	for child in get_tree().root.get_children():
		if child is Grenade:
			count += 1
	return count


func _find_grenade_in_scene() -> Grenade:
	for child in get_tree().root.get_children():
		if child is Grenade:
			return child
	return null


# ================= 1. 场景加载与武器层 =================
func test_level_loads_weapon_layer() -> void:
	var ak: WeaponResource = load("res://Weapons/weapon_ak47.tres")
	assert_not_null(manager, "WeaponManager 挂 Player 下")
	assert_not_null(level.get_node("Player/Head/WeaponView"), "WeaponView 挂 Head 下")
	assert_not_null(manager.get_core(0), "槽位 0 AK 挂载（.tres 预装载）")
	assert_not_null(manager.get_core(1), "槽位 1 Glock 挂载")
	assert_not_null(manager.get_core(2), "槽位 2 匕首挂载")
	assert_not_null(manager.get_core(3), "槽位 3 M67 挂载")
	assert_eq(manager.get_current_slot(), 0, "初始槽位 0（primary）")
	assert_almost_eq(player.speed_modifier, ak.mobility / 250.0, 0.001,
			"初始移速写入 AK（215/250 = 0.86）")


# ================= 2. 相机路径 + hitscan 集成 =================
func test_try_fire_hits_target_and_emits_hit_landed() -> void:
	var ak: WeaponResource = load("res://Weapons/weapon_ak47.tres")
	var core: WeaponCore = manager.get_core(0)
	var hits: Array = []
	core.hit_landed.connect(func(target: Node, damage: float, _pos: Vector3, _normal: Vector3) -> void:
		hits.append([target, damage]))
	Input.action_press("fire")
	await wait_physics_frames(2)
	Input.action_release("fire")
	assert_eq(hits.size(), 1, "AK 开火命中靶子（Manager 相机路径在真实场景可用）")
	assert_eq(hits[0][0], target_a, "命中 TargetA（Objects 层 + torso Group）")
	assert_almost_eq(hits[0][1], ak.damage, 0.001, "2m 内满伤 36（effective_range 内无衰减）")


# ================= 3. 切枪更新移速 =================
func test_switch_updates_speed_modifier() -> void:
	var glock: WeaponResource = load("res://Weapons/weapon_glock18.tres")
	var knife: WeaponResource = load("res://Weapons/weapon_knife.tres")
	var m67: WeaponResource = load("res://Weapons/weapon_m67.tres")
	manager.switch_to(2)
	assert_almost_eq(player.speed_modifier, knife.mobility / 250.0, 0.001, "刀 250/250 = 1.0")
	manager.switch_to(1)
	assert_almost_eq(player.speed_modifier, glock.mobility / 250.0, 0.001, "Glock 240/250 = 0.96")
	manager.switch_to(3)
	assert_almost_eq(player.speed_modifier, m67.mobility / 250.0, 0.001, "M67 245/250 = 0.98")
	manager.switch_to(0)
	var ak: WeaponResource = load("res://Weapons/weapon_ak47.tres")
	assert_almost_eq(player.speed_modifier, ak.mobility / 250.0, 0.001, "回 AK 215/250 = 0.86")


# ================= 4. 弹药 HUD =================
func test_hud_label_shows_ammo_and_updates_on_shot() -> void:
	var ak: WeaponResource = load("res://Weapons/weapon_ak47.tres")
	assert_eq(ammo_label.text, "%d / %d" % [ak.magazine, ak.max_ammo], "初始 HUD：30 / 90")
	Input.action_press("fire")
	await wait_physics_frames(2)
	Input.action_release("fire")
	assert_eq(ammo_label.text, "%d / %d" % [ak.magazine - 1, ak.max_ammo], "开火 1 发 → 29 / 90")


# ================= 5. 机瞄接线（Head FOV，M1.5 平滑插值） =================
func test_aim_wires_head_fov_zoom() -> void:
	var ak: WeaponResource = load("res://Weapons/weapon_ak47.tres")
	var head: Node3D = player.get_node("Head")
	var cam: Camera3D = head.get_node("Camera")
	var base_fov: float = cam.fov
	manager.set_aim(true)
	await wait_physics_frames(40)  # M1.5 平滑开镜：等 FOV 插值到位（ads_zoom_speed 14 → ~0.1s）
	assert_almost_eq(cam.fov, base_fov / ak.ads_multiplier, 0.01, "AK 机瞄 FOV ÷1.5（平滑到位，.tres 数值）")
	manager.set_aim(false)
	await wait_physics_frames(40)  # 关镜插值恢复
	assert_almost_eq(cam.fov, base_fov, 0.01, "关镜平滑恢复 FOV")


# ================= 6. M67 右键取消投掷 =================
func test_m67_rightclick_cancels_throw_and_keeps_ammo() -> void:
	var m67: WeaponResource = load("res://Weapons/weapon_m67.tres")
	var core: WeaponCore = manager.get_core(3)
	manager.switch_to(3)
	await wait_physics_frames(_deploy_frames(m67))
	assert_eq(manager.get_state(), WeaponManager.State.ACTIVE, "M67 deploy 完成")
	# 左键按住 = 引信阶段（THROWING，手中持雷）
	Input.action_press("fire")
	await wait_physics_frames(2)
	assert_eq(manager.get_state(), WeaponManager.State.THROWING, "fire 按住 → THROWING（引信）")
	# 右键取消（经 L_Main 输入绑定路径：合成 aim 事件 → _unhandled_input）
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_RIGHT
	ev.pressed = true
	level._unhandled_input(ev)
	assert_eq(manager.get_state(), WeaponManager.State.ACTIVE, "右键取消 → 回 ACTIVE")
	assert_almost_eq(core.get_ammo().x, 1.0, 0.001, "取消后弹药不消耗（弹匣返还 1）")
	assert_almost_eq(core.get_ammo().y, 1.0, 0.001, "备弹保持 1")
	assert_eq(ammo_label.text, "1 / 1", "HUD 恢复 1 / 1")
	# 释放 fire：已取消 → 不生成投掷物、不再投掷
	Input.action_release("fire")
	await wait_physics_frames(5)
	assert_eq(_count_grenades_in_scene(), 0, "取消后不生成 Grenade")
	assert_almost_eq(core.get_ammo().x, 1.0, 0.001, "释放后不再扣减")


# ================= 7. Grenade 接线（投掷 → 引信 → 爆炸伤害） =================
func test_m67_throw_explodes_and_damages_target() -> void:
	var m67: WeaponResource = load("res://Weapons/weapon_m67.tres")
	manager.switch_to(3)
	await wait_physics_frames(_deploy_frames(m67))
	assert_eq(manager.get_state(), WeaponManager.State.ACTIVE, "M67 deploy 完成")
	Input.action_press("fire")
	await wait_physics_frames(2)
	Input.action_release("fire")  # 释放 = 出手：下一物理帧生成 Grenade
	await wait_physics_frames(5)
	assert_eq(_count_grenades_in_scene(), 1, "释放 fire 生成真实 Grenade（接线验证）")
	# 引信 1.5s（90 物理帧）→ 爆炸。弹道随测试环境物理漂移，精确落点不可靠——
	# 确定性验证接线：爆炸前把 TargetA 传送到手雷落点正下方，再断言受伤。
	await wait_physics_frames(70)  # 飞到引信将尽（未爆）
	var grenade := _find_grenade_in_scene()
	if grenade != null:
		# M2 手感修复（2026-08-13）：LOS 挡伤后手雷弹道落点随机（旋转+反弹），落入洼地/墙根时
		# 胸口射线被几何遮挡 → 正确挡伤 → 原"落点正上方"断言随机红。确定性化：冻结雷体传送到
		# 开阔高空（LOS 纯净区），目标贴身正上方——接线断言不再依赖随机落点。
		grenade.freeze = true
		grenade.global_position = Vector3(0, 20, 0)
		target_a.global_position = grenade.global_position + Vector3(0, 0.3, 0)
	await wait_physics_frames(40)  # 引信到 → 爆炸
	assert_eq(_count_grenades_in_scene(), 0, "引信到 → Grenade 爆炸自清")
	assert_lt(target_a.health, 100.0, "目标受到爆炸伤害（Manager→Grenade→explode→take_damage 接线有效）")
	assert_gt(target_a.health, 0.0, "伤害在有效带内（未超杀出界）")
