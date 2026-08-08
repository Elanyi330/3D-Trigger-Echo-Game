# test/unit/test_infinite_ammo.gd
# M1 任务11：无限弹药测试环境（spec §9.9，cheats 开关）测试（TDD RED 先行）
# 行为（brief §交付内容）：
#   - WeaponCore.infinite_ammo=true：开火弹药自愈——弹匣打空自动补满（spec §9.9 措辞：
#     开火仍逐发扣减以保 HUD 真实计数（集成测试锁定 1 发显示 29/120），扣空后下次开火自动
#     补满，等效弹药无限）、换弹瞬时满（立即补满 + reload_finished，不进入换弹状态）、
#     备弹无穷（恒满）
#   - M67 投出后自动补 1 枚（投掷路径等价 refund_throw）：可连续投掷无需换弹
#   - L_Main.cheats 默认 true → setup 后所有核心 infinite_ammo = true
# 全局约束（计划 §4）：数值唯一来源 weapon_*.tres（期望值引用 .tres 字段，不硬编码散值）。
extends GutTest

var core: WeaponCore
var ak: WeaponResource
var glock: WeaponResource
var knife: WeaponResource
var m67: WeaponResource
var movement: MovementController


func before_each() -> void:
	Input.action_release("fire")
	ak = load("res://Weapons/weapon_ak47.tres")
	glock = load("res://Weapons/weapon_glock18.tres")
	knife = load("res://Weapons/weapon_knife.tres")
	m67 = load("res://Weapons/weapon_m67.tres")
	core = WeaponCore.new()
	add_child_autofree(core)
	watch_signals(core)
	core.setup(ak, null)
	movement = MovementController.new()
	add_child_autofree(movement)


func after_each() -> void:
	Input.action_release("fire")


# ---- 夹具 ----

func _fast_ak() -> WeaponResource:
	# 派生资源：数值来源 .tres，测试仅提速节流（单发间隔 0.001s < 物理帧）
	var res: WeaponResource = ak.duplicate()
	res.rpm = 60000
	res.reload_time = 0.05
	return res


func _fire_n(n: int) -> void:
	for i in n:
		core.try_fire()
		await wait_physics_frames(1)


func _build_manager() -> WeaponManager:
	var m := WeaponManager.new()
	add_child_autofree(m)
	m.setup([ak, glock, knife, m67], movement)
	return m


func _with_camera() -> Camera3D:
	# 投掷需要真实相机（Manager._throw_grenade 无相机 = 测试环境不生成投掷物）——
	# setup 时缓存相机，须先建相机再 _build_manager
	var cam := Camera3D.new()
	add_child_autofree(cam)
	cam.global_position = Vector3(0, 1, 0)
	cam.look_at(Vector3(0, 1, -5), Vector3.UP)
	cam.current = true
	return cam


func _deploy_frames(res: WeaponResource) -> int:
	return int(ceil(res.deploy_time * float(Engine.physics_ticks_per_second))) + 2


func _count_grenades(_manager: WeaponManager) -> int:
	# M1 任务14：脱手后 Grenade 挂场景根（不随玩家）——搜索范围从 manager 子节点改为根
	var count := 0
	for child in get_tree().root.get_children():
		if child is Grenade:
			count += 1
	return count


# ================= 1. 无限射击（弹匣打空自动补满） =================
func test_infinite_ammo_never_runs_dry() -> void:
	# 连续射击超过弹匣容量：不触发 out_of_ammo，弹药自愈（spec §9.9 "弹匣打空自动补满"）
	var res := _fast_ak()
	core.setup(res, null)
	core.infinite_ammo = true
	await _fire_n(res.magazine + 5)  # 35 发 > 30 弹匣容量
	assert_signal_emit_count(core, "out_of_ammo", 0, "无限弹药不触发 out_of_ammo")
	# 35 发 = 前 30 发打空 + 第 31 发前自动补满再打 5 发 → 弹匣剩 25，备弹恒满
	assert_eq(core.get_ammo(), Vector2(res.magazine - 5, res.max_ammo),
			"打空后自动补满再扣减（备弹恒满 = 无穷）")


func test_infinite_ammo_off_still_runs_dry() -> void:
	# 对照：开关关闭时行为不变（打空触发 out_of_ammo）
	var res := _fast_ak()
	core.setup(res, null)
	await _fire_n(res.magazine)
	assert_signal_emit_count(core, "out_of_ammo", 0, "打空最后一发不发 out_of_ammo")
	await wait_physics_frames(2)  # 过射速节流
	core.try_fire()
	assert_signal_emit_count(core, "out_of_ammo", 1, "非无限模式空匣发 out_of_ammo")


# ================= 2. 换弹瞬时满 =================
func test_infinite_ammo_reload_instantly_fills() -> void:
	var res := _fast_ak()
	core.setup(res, null)
	await _fire_n(20)  # 弹匣 30 → 10
	assert_eq(core.get_ammo(), Vector2(res.magazine - 20, res.max_ammo), "前置：弹匣剩 10")
	core.infinite_ammo = true
	core.start_reload()
	assert_false(core.is_reloading(), "无限弹药换弹瞬时完成（不进入换弹状态）")
	assert_signal_emit_count(core, "reload_finished", 1, "换弹立即完成发 reload_finished")
	assert_eq(core.get_ammo(), Vector2(res.magazine, res.max_ammo), "弹匣瞬时补满 30")
	assert_almost_eq(core.get_ammo().y, float(res.max_ammo), 0.001, "备弹回满 120（无穷）")


func test_infinite_ammo_full_mag_reload_still_emits_finished() -> void:
	# 满弹匣 + 无限弹药：换弹同样瞬时完成（非无限模式满匣换弹静默无信号——行为差异）
	core.infinite_ammo = true
	core.start_reload()
	assert_signal_emit_count(core, "reload_finished", 1, "满匣换弹瞬时完成发 reload_finished")
	assert_eq(core.get_ammo(), Vector2(ak.magazine, ak.max_ammo), "弹药保持满")


# ================= 3. M67 投出自动补 1 枚（spec §9.9） =================
func test_infinite_ammo_m67_refunds_after_throw() -> void:
	_with_camera()
	var manager := _build_manager()
	var m67_core: WeaponCore = manager.get_core(3)
	m67_core.infinite_ammo = true
	manager.switch_to(3)
	await wait_physics_frames(_deploy_frames(m67))
	Input.action_press("fire")
	await wait_physics_frames(2)
	assert_eq(manager.get_state(), WeaponManager.State.THROWING, "前置：引信 THROWING")
	Input.action_release("fire")
	await wait_physics_frames(2)
	assert_eq(_count_grenades(manager), 1, "投出生成真实 Grenade")
	assert_eq(m67_core.get_ammo(), Vector2(1, 1), "投出后自动补 1 枚（等价 refund_throw）")
	# 连续投掷：无需换弹（开火冷却已随 refund 重置——rpm=0 的 INF 冷却不重置会锁死）
	Input.action_press("fire")
	await wait_physics_frames(2)
	assert_eq(manager.get_state(), WeaponManager.State.THROWING, "可再次进入引信")
	Input.action_release("fire")
	await wait_physics_frames(2)
	assert_eq(_count_grenades(manager), 2, "第二次投掷成功（无需换弹）")
	assert_eq(m67_core.get_ammo(), Vector2(1, 1), "弹药仍 1 枚（自动补）")
	# 清理：脱手后 Grenade 挂场景根（任务14），不随测试树释放——引信 1.5s 会在后续测试中途爆炸，
	# 显式释放防跨测试污染（否则爆炸伤害干扰后续集成断言）
	await _clean_root_grenades()


func _clean_root_grenades() -> void:
	# 场景根手雷清理（任务14 脱手后挂根：测试树 autofree 不覆盖）
	for child in get_tree().root.get_children():
		if child is Grenade:
			child.queue_free()
	await wait_physics_frames(1)


# ================= 4. L_Main cheats 开关（spec §9.9） =================
# M1.5：cheats 默认 false（真实弹药/换弹，供验收）；置 true 时注入无限弹药。
func test_l_main_cheats_default_off() -> void:
	var level: Node = load("res://Levels/Main/L_Main.tscn").instantiate()
	add_child_autofree(level)
	await wait_physics_frames(2)
	assert_eq(level.get("cheats"), false, "cheats 默认关闭（真实弹药；测试可开启）")
	var level_manager: WeaponManager = level.get_node("Player/WeaponManager")
	var c0: WeaponCore = level_manager.get_core(0)
	assert_not_null(c0, "槽位 0 核心存在")
	if c0 != null:
		assert_false(c0.infinite_ammo, "cheats 关闭 → 槽位 0 非无限弹药")


func test_l_main_cheats_on_injects_infinite_ammo() -> void:
	var level: Node = load("res://Levels/Main/L_Main.tscn").instantiate()
	level.set("cheats", true)  # 入树前开启（_ready/_setup_weapons 时注入）
	add_child_autofree(level)
	await wait_physics_frames(2)  # _ready → _setup_weapons 完成
	var level_manager: WeaponManager = level.get_node("Player/WeaponManager")
	for i in 4:
		var c: WeaponCore = level_manager.get_core(i)
		assert_not_null(c, "槽位 %d 核心存在" % i)
		if c != null:
			assert_true(c.infinite_ammo, "槽位 %d infinite_ammo = true（cheats 注入）" % i)
