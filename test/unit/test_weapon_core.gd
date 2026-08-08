# test/unit/test_weapon_core.gd
# M1 任务1：WeaponCore 射击核心测试（TDD RED 先行）
# 行为（brief §行为要求）：开火/节流/空匣、hitscan 部位×距离衰减、换弹（丢弃剩余/打断/换弹中无效）、
# 后坐力（SET_PATTERN 逐发 / RANDOM 范围 / recovery 恢复衰减 / 首发 first_shot_spread）、
# 半自动 vs 全自动、弹药（get_ammo / add_ammo 上限）。
# 全局约束（计划 §4）：数值唯一来源 weapon_*.tres；测试夹具通过 .duplicate() 调整提速，不硬编码散值；
# hitscan 射线 mask=1 仅 Objects 层。
extends GutTest

var core: WeaponCore
var ak: WeaponResource
var glock: WeaponResource

func before_each() -> void:
	Input.action_release("fire")  # 防跨测试输入污染
	ak = load("res://Weapons/weapon_ak47.tres")
	glock = load("res://Weapons/weapon_glock18.tres")
	core = WeaponCore.new()
	add_child_autofree(core)
	core.setup(ak, null)
	watch_signals(core)

# ---- 夹具：派生资源（数值来源 .tres，测试仅提速节流/换弹/恢复） ----
func _fast_ak() -> WeaponResource:
	var res: WeaponResource = ak.duplicate()
	res.rpm = 60000  # 单发间隔 0.001s < 物理帧 → 每帧可开火
	res.reload_time = 0.05
	return res

func _fast_glock() -> WeaponResource:
	var res: WeaponResource = glock.duplicate()
	res.rpm = 60000
	return res

func _fire_n_times(n: int) -> void:
	for i in n:
		core.try_fire()
		await wait_physics_frames(1)

# ---- 物理场景辅助 ----
func _build_camera_at(origin: Vector3, looking_at: Vector3) -> Camera3D:
	var cam := Camera3D.new()
	add_child_autofree(cam)
	cam.global_position = origin
	cam.look_at(looking_at, Vector3.UP)
	return cam

func _build_target(group: String, at: Vector3, size := Vector3(2, 2, 2), layer := 1) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = layer  # 1=Objects 层（全局约束 §4）
	body.collision_mask = 0
	if group != "":
		body.add_to_group(group)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	add_child_autofree(body)
	body.global_position = at
	return body

func _capture_hits() -> Array:
	# M1 任务8：hit_landed 补 normal 参数（弹孔贴合表面）——捕获 4 参同步
	var hits: Array = []
	core.hit_landed.connect(func(target: Node, damage: float, position: Vector3, normal: Vector3) -> void:
		hits.append([target, damage, position, normal]))
	return hits

# ================= 1. 开火 =================
func test_fire_decrements_mag_and_emits_shot_fired() -> void:
	var fired: Array = []
	core.shot_fired.connect(func(ammo_left: int) -> void: fired.append(ammo_left))
	core.try_fire()
	assert_eq(core.get_ammo(), Vector2(ak.magazine - 1, ak.max_ammo), "开火后 mag-1、备弹不变")
	assert_eq(fired, [ak.magazine - 1], "shot_fired(剩余 mag)")

func test_fire_throttle_two_presses_one_shot() -> void:
	# AK 600RPM → 单发间隔 60/600 = 0.1s（数值来自 .tres）
	core.try_fire()
	await wait_physics_frames(5)  # 83ms < 100ms
	core.try_fire()
	assert_signal_emit_count(core, "shot_fired", 1, "间隔内连按只响一次")
	await wait_physics_frames(2)  # 总计 117ms > 100ms
	core.try_fire()
	assert_signal_emit_count(core, "shot_fired", 2, "间隔过后再次开火")

func test_empty_mag_emits_out_of_ammo() -> void:
	var res: WeaponResource = ak.duplicate()
	res.magazine = 1
	core.setup(res, null)
	core.try_fire()  # 打空弹匣
	assert_signal_emit_count(core, "shot_fired", 1, "最后一发正常发射")
	assert_signal_emit_count(core, "out_of_ammo", 0, "尚未空匣不发 out_of_ammo")
	await wait_physics_frames(7)  # 过射速间隔（空匣点击同样节流）
	core.try_fire()  # 空匣再开火
	assert_signal_emit_count(core, "shot_fired", 1, "空匣不发 shot_fired")
	assert_signal_emit_count(core, "out_of_ammo", 1, "空匣发 out_of_ammo")

func test_can_fire_reflects_state() -> void:
	assert_true(core.can_fire(), "初始满匣可开火")
	core.try_fire()
	assert_false(core.can_fire(), "节流间隔内不可开火")
	await wait_physics_frames(7)
	assert_true(core.can_fire(), "间隔过后可开火")
	var res: WeaponResource = ak.duplicate()
	res.magazine = 1
	core.setup(res, null)
	core.try_fire()
	assert_false(core.can_fire(), "空匣不可开火")
	var res2 := _fast_ak()
	core.setup(res2, null)
	core.try_fire()
	core.start_reload()
	assert_false(core.can_fire(), "换弹中不可开火")
	core.interrupt_reload()

# ================= 2. hitscan 命中 =================
func test_hitscan_torso_damage_36() -> void:
	var hits := _capture_hits()
	var target := _build_target("torso", Vector3(0, 0, -8))
	var cam := _build_camera_at(Vector3.ZERO, Vector3(0, 0, -8))
	core.setup(ak, cam)
	await wait_physics_frames(3)
	core.try_fire()
	assert_eq(hits.size(), 1, "命中 1 次")
	assert_is(hits[0][0], StaticBody3D, "target 为碰撞体")
	assert_almost_eq(hits[0][1], ak.damage, 0.001, "躯干 = 基础伤害 36")
	assert_almost_eq(hits[0][3].x, 0.0, 0.001, "命中法线 x = 0")
	assert_almost_eq(hits[0][3].y, 0.0, 0.001, "命中法线 y = 0")
	assert_almost_eq(hits[0][3].z, 1.0, 0.001, "命中法线朝射手（弹孔贴合表面）")

func test_hitscan_head_damage_144() -> void:
	var hits := _capture_hits()
	_build_target("head", Vector3(0, 0, -8))
	var cam := _build_camera_at(Vector3.ZERO, Vector3(0, 0, -8))
	core.setup(ak, cam)
	await wait_physics_frames(3)
	core.try_fire()
	assert_eq(hits.size(), 1, "命中 1 次")
	assert_almost_eq(hits[0][1], ak.damage * ak.headshot_multiplier, 0.001, "爆头 = 36×4.0 = 144")

func test_hitscan_limb_damage_28_8() -> void:
	var hits := _capture_hits()
	_build_target("limb", Vector3(0, 0, -8))
	var cam := _build_camera_at(Vector3.ZERO, Vector3(0, 0, -8))
	core.setup(ak, cam)
	await wait_physics_frames(3)
	core.try_fire()
	assert_eq(hits.size(), 1, "命中 1 次")
	assert_almost_eq(hits[0][1], ak.damage * ak.limb_multiplier, 0.001, "四肢 = 36×0.8 = 28.8")

func test_hitscan_falloff_50m_ak_098() -> void:
	# 目标中心 -51、尺寸 2 → 近表面 z = -50，恰好命中 50m 处（falloff_curve[1] = 0.98）
	var hits := _capture_hits()
	_build_target("torso", Vector3(0, 0, -51), Vector3(2, 2, 2))
	var cam := _build_camera_at(Vector3.ZERO, Vector3(0, 0, -51))
	core.setup(ak, cam)
	await wait_physics_frames(3)
	core.try_fire()
	assert_eq(hits.size(), 1, "命中 1 次")
	var expected: float = ak.damage * ak.falloff_curve[1]  # 36 × 0.98 = 35.28
	assert_almost_eq(hits[0][1], expected, 0.001, "50m 处衰减 0.98 → 35.28")

func test_hitscan_truncates_at_max_range() -> void:
	var hits := _capture_hits()
	_build_target("torso", Vector3(0, 0, -70), Vector3(4, 4, 4))  # 超出 AK max_range 60m
	var cam := _build_camera_at(Vector3.ZERO, Vector3(0, 0, -70))
	core.setup(ak, cam)
	await wait_physics_frames(3)
	core.try_fire()
	assert_eq(hits.size(), 0, "超过 max_range 不命中")

func test_hitscan_ignores_non_objects_layer() -> void:
	# 仅 Player 层(2) 目标：mask=1 射线应直接穿过不命中
	var hits := _capture_hits()
	_build_target("torso", Vector3(0, 0, -8), Vector3(2, 2, 2), 2)
	var cam := _build_camera_at(Vector3.ZERO, Vector3(0, 0, -8))
	core.setup(ak, cam)
	await wait_physics_frames(3)
	core.try_fire()
	assert_eq(hits.size(), 0, "mask=1 仅 Objects 层，Player 层不命中")

func test_hitscan_passes_through_player_layer_to_objects() -> void:
	# Player 层目标在前、Objects 层目标在后：射线穿过前者命中后者（验证 mask=1 而非全层或 0）
	var hits := _capture_hits()
	_build_target("torso", Vector3(0, 0, -5), Vector3(2, 2, 2), 2)
	var objects_target := _build_target("torso", Vector3(0, 0, -8))
	var cam := _build_camera_at(Vector3.ZERO, Vector3(0, 0, -8))
	core.setup(ak, cam)
	await wait_physics_frames(3)
	core.try_fire()
	assert_eq(hits.size(), 1, "仅命中 Objects 层目标")
	assert_eq(hits[0][0], objects_target, "命中目标为 Objects 层碰撞体")

# ---- M1 任务15：曳光弹（tracer_fired 信号端点计算，CC0 bullet_tracer） ----

func test_hitscan_emits_tracer_to_hit_point() -> void:
	# 命中 → tracer_fired(to = 命中点)；起点 = 相机（枪口近似，无视模型接线）
	var tracers: Array = []
	core.tracer_fired.connect(func(from: Vector3, to: Vector3) -> void: tracers.append([from, to]))
	var res: WeaponResource = ak.duplicate()
	res.first_shot_spread = 0.0  # 首发零散布：方向精确 -Z（tracer 端点确定）
	_build_target("torso", Vector3(0, 0, -8))
	var cam := _build_camera_at(Vector3.ZERO, Vector3(0, 0, -8))
	core.setup(res, cam)
	await wait_physics_frames(3)
	core.try_fire()
	assert_eq(tracers.size(), 1, "命中发 1 次 tracer")
	if tracers.size() == 1:
		assert_almost_eq(tracers[0][0].z, 0.0, 0.001, "起点 = 相机位置（枪口近似）")
		assert_almost_eq(tracers[0][1].z, -7.0, 0.01, "终点 = 命中点（目标近表面 z=-7）")


func test_hitscan_miss_emits_tracer_to_max_range_endpoint() -> void:
	# 未命中 → tracer_fired(to = max_range 端点)（曳光弹到最大射程）
	var tracers: Array = []
	core.tracer_fired.connect(func(from: Vector3, to: Vector3) -> void: tracers.append([from, to]))
	var res: WeaponResource = ak.duplicate()
	res.first_shot_spread = 0.0
	var cam := _build_camera_at(Vector3.ZERO, Vector3(0, 0, -8))
	core.setup(res, cam)
	await wait_physics_frames(3)
	core.try_fire()
	assert_eq(tracers.size(), 1, "未命中发 1 次 tracer")
	if tracers.size() == 1:
		assert_almost_eq(tracers[0][1].z, -res.max_range, 0.01,
				"终点 = 相机 + dir × max_range（AK 60m）")

func test_first_shot_spread_bounds_deviation() -> void:
	# 首发精度：弹道散布被 first_shot_spread 约束（10m 处 ≤ tan(0.1°)×10 ≈ 1.7cm）
	var hits := _capture_hits()
	_build_target("torso", Vector3(0, 0, -10), Vector3(0.5, 0.5, 0.5))
	var cam := _build_camera_at(Vector3.ZERO, Vector3(0, 0, -10))
	core.setup(ak, cam)
	await wait_physics_frames(3)
	core.try_fire()
	assert_eq(hits.size(), 1, "首发散布内命中小目标")
	var max_dev: float = tan(deg_to_rad(ak.first_shot_spread)) * 10.25 + 0.01
	assert_true(absf(hits[0][2].x) < max_dev and absf(hits[0][2].y) < max_dev,
			"命中点偏离 ≤ 首发散布锥（实测 %s）" % str(hits[0][2]))

# ================= 3. 换弹（CS2 2026-03 丢弃剩余规则） =================
func test_reload_fills_mag_and_drains_reserve() -> void:
	# 弹匣剩 10 → 换弹后 30，备弹减 20（丢弃弹匣剩余）
	var res := _fast_ak()
	core.setup(res, null)
	await _fire_n_times(20)
	assert_eq(core.get_ammo(), Vector2(10, res.max_ammo), "开火 20 发后弹匣剩 10")
	core.start_reload()
	assert_signal_emit_count(core, "reload_started", 1, "发 reload_started")
	assert_true(core.is_reloading(), "换弹中")
	await wait_physics_frames(4)  # 0.0667s > reload_time 0.05s
	assert_signal_emit_count(core, "reload_finished", 1, "发 reload_finished")
	assert_false(core.is_reloading(), "换弹完成")
	assert_eq(core.get_ammo(), Vector2(res.magazine, res.max_ammo - 20),
			"弹匣满 30、备弹 120-20=100（丢弃剩余）")

func test_reload_insufficient_reserve_fills_what_it_can() -> void:
	var res := _fast_ak()
	res.max_ammo = 15  # 备弹不足场景
	core.setup(res, null)
	await _fire_n_times(20)
	assert_eq(core.get_ammo(), Vector2(10, 15))
	core.start_reload()
	await wait_physics_frames(4)
	assert_eq(core.get_ammo(), Vector2(25, 0), "弹匣 = min(30, 15+10) = 25，备弹 0")

func test_fire_during_reload_is_noop() -> void:
	var res := _fast_ak()
	res.reload_time = 0.5
	core.setup(res, null)
	await _fire_n_times(20)
	var fired_before: int = get_signal_emit_count(core, "shot_fired")
	core.start_reload()
	core.try_fire()
	assert_eq(get_signal_emit_count(core, "shot_fired"), fired_before, "换弹中开火无效")
	assert_eq(core.get_ammo(), Vector2(10, 120), "弹药不变")
	assert_true(core.is_reloading(), "换弹未被取消")
	await wait_physics_frames(40)  # 0.667s > 0.5s
	assert_eq(core.get_ammo(), Vector2(30, 100), "换弹仍正常完成")

func test_reload_interrupt_keeps_ammo() -> void:
	var res := _fast_ak()
	core.setup(res, null)
	await _fire_n_times(20)
	assert_eq(core.get_ammo(), Vector2(10, 120))
	core.start_reload()
	await wait_physics_frames(2)
	core.interrupt_reload()
	assert_false(core.is_reloading(), "打断后不在换弹")
	assert_signal_emit_count(core, "reload_finished", 0, "打断不发 reload_finished")
	assert_eq(core.get_ammo(), Vector2(10, 120), "弹药保持换弹前状态（不返还）")
	core.start_reload()  # 打断后可再次换弹
	await wait_physics_frames(4)
	assert_eq(core.get_ammo(), Vector2(30, 100), "再次换弹正常完成")

func test_reload_skipped_when_mag_full() -> void:
	core.start_reload()
	assert_signal_emit_count(core, "reload_started", 0, "满弹匣不开始换弹")
	assert_false(core.is_reloading())

# ================= 4. 后坐力 =================
func test_set_pattern_offsets_per_shot() -> void:
	var res := _fast_ak()
	core.setup(res, null)
	for i in res.pattern_offsets.size():
		core.try_fire()
		await wait_physics_frames(1)
		assert_eq(core.get_recoil_offset(), res.pattern_offsets[i],
				"第 %d 发偏移 == pattern[%d]" % [i + 1, i])

func test_set_pattern_beyond_bounds_uses_last() -> void:
	var res := _fast_ak()
	core.setup(res, null)
	for i in res.pattern_offsets.size() + 3:
		core.try_fire()
		await wait_physics_frames(1)
	assert_eq(core.get_recoil_offset(), res.pattern_offsets[res.pattern_offsets.size() - 1],
			"越界循环到最后一项")

func test_random_recoil_within_range() -> void:
	var res := _fast_glock()
	core.setup(res, null)
	var low: float = glock.recoil_amount - glock.recoil_variance
	var high: float = glock.recoil_amount + glock.recoil_variance
	for i in 8:
		Input.action_press("fire")
		await wait_physics_frames(1)  # 半自动按压沿在物理帧检测
		core.try_fire()
		Input.action_release("fire")
		await wait_physics_frames(1)  # 松开后复位沿检测
		var off := core.get_recoil_offset()
		assert_between(off.x, low, high,
				"第 %d 发垂直偏移 %s ∈ [%.2f, %.2f]" % [i + 1, str(off.x), low, high])
		assert_between(off.y, -glock.recoil_variance, glock.recoil_variance,
				"第 %d 发水平偏移 ±variance" % [i + 1])

func test_recovery_decays_accum_to_zero() -> void:
	var res := _fast_ak()
	res.recovery_speed = 1000.0  # 测试提速（原始 8°/s 数值来自 .tres）
	core.setup(res, null)
	core.try_fire()  # 第 1 发 pattern[0]=(0,0)
	await wait_physics_frames(1)
	core.try_fire()  # 第 2 发 pattern[1]=(0.9,0) → 累计 (0.9,0)
	assert_almost_eq(core.recoil_accum.x, res.pattern_offsets[1].x, 0.001, "射击累计 0.9°")
	await wait_physics_frames(3)  # 停止射击后按 recovery_speed 衰减
	assert_almost_eq(core.recoil_accum.x, 0.0, 0.001, "恢复衰减回零")
	assert_almost_eq(core.recoil_accum.y, 0.0, 0.001, "水平恢复回零")

# ================= 5. 全自动 / 半自动 =================
func test_semi_auto_one_shot_per_press() -> void:
	var res := _fast_glock()
	core.setup(res, null)
	# 第 1 次按键：按下 → 下一物理帧沿检测 → 开火 1 发
	Input.action_press("fire")
	await wait_physics_frames(1)
	core.try_fire()
	assert_signal_emit_count(core, "shot_fired", 1, "第 1 次按键 1 发")
	Input.action_release("fire")
	await wait_physics_frames(1)
	# 第 2 次按键：再次开火 1 发
	Input.action_press("fire")
	await wait_physics_frames(1)
	core.try_fire()
	assert_signal_emit_count(core, "shot_fired", 2, "第 2 次按键 1 发")
	Input.action_release("fire")
	await wait_physics_frames(1)
	# 第 3 次按键开火后，按住不放不再发（每次按键只发一发）
	Input.action_press("fire")
	await wait_physics_frames(1)
	core.try_fire()
	assert_signal_emit_count(core, "shot_fired", 3, "第 3 次按键 1 发")
	await wait_physics_frames(10)  # 持续按住
	core.try_fire()
	assert_signal_emit_count(core, "shot_fired", 3, "按住只发一发（半自动）")
	Input.action_release("fire")

func test_full_auto_fires_while_held() -> void:
	Input.action_press("fire")
	core.try_fire()
	assert_signal_emit_count(core, "shot_fired", 1, "按下即发")
	await wait_physics_frames(7)  # 117ms > 100ms 间隔
	core.try_fire()
	assert_signal_emit_count(core, "shot_fired", 2, "按住持续射击")
	await wait_physics_frames(7)
	core.try_fire()
	assert_signal_emit_count(core, "shot_fired", 3, "继续射击")
	Input.action_release("fire")

# ================= 6. 弹药 =================
func test_get_ammo_returns_mag_and_reserve() -> void:
	assert_eq(core.get_ammo(), Vector2(ak.magazine, ak.max_ammo), "初始 30+120")
	core.try_fire()
	assert_eq(core.get_ammo(), Vector2(ak.magazine - 1, ak.max_ammo), "开火后 (29, 120)")

func test_add_ammo_caps_at_max() -> void:
	core.add_ammo(50)
	assert_almost_eq(core.get_ammo().y, float(ak.max_ammo), 0.001, "满备弹补给封顶 120")
	var res := _fast_ak()
	core.setup(res, null)
	await _fire_n_times(20)
	core.start_reload()
	await wait_physics_frames(4)
	assert_eq(core.get_ammo(), Vector2(30, 100))
	core.add_ammo(10)
	assert_almost_eq(core.get_ammo().y, 110.0, 0.001, "补给 10 生效")
	core.add_ammo(50)
	assert_almost_eq(core.get_ammo().y, float(ak.max_ammo), 0.001, "超过 max_ammo 封顶")


# ================= 7. 精度稳定性模型（M1 任务8：base × move × crouch ÷ ads） =================
func _with_movement() -> MovementController:
	var mv := MovementController.new()
	add_child_autofree(mv)
	return mv


func test_spread_standing_equals_base() -> void:
	var res := _fast_ak()
	core.setup(res, null, _with_movement())
	assert_almost_eq(core._get_first_shot_spread(), res.first_shot_spread, 0.001,
			"静止站立 = 基础散布（无惩罚）")


func test_spread_moving_penalty_multiplies() -> void:
	var res := _fast_ak()
	var mv := _with_movement()
	core.setup(res, null, mv)
	mv.is_moving = true
	assert_almost_eq(core._get_first_shot_spread(),
			res.first_shot_spread * res.move_spread_multiplier, 0.001,
			"移动中 = base × move_spread_multiplier（数值来自 .tres）")


func test_spread_crouch_narrows() -> void:
	var res := _fast_ak()
	var mv := _with_movement()
	core.setup(res, null, mv)
	mv.is_crouching = true
	assert_almost_eq(core._get_first_shot_spread(),
			res.first_shot_spread * res.crouch_spread_multiplier, 0.001,
			"下蹲 = base × crouch_spread_multiplier（收窄 <1）")


func test_spread_moving_and_crouch_stack() -> void:
	var res := _fast_ak()
	var mv := _with_movement()
	core.setup(res, null, mv)
	mv.is_moving = true
	mv.is_crouching = true
	assert_almost_eq(core._get_first_shot_spread(),
			res.first_shot_spread * res.move_spread_multiplier * res.crouch_spread_multiplier,
			0.001, "叠加：base × move × crouch")


func test_spread_ads_keeps_moving_penalty() -> void:
	# 叠加顺序 base×move×crouch÷ads：开镜保留移动惩罚（CS2 开镜移动仍有精度损失）
	var res := _fast_ak()
	var mv := _with_movement()
	core.setup(res, null, mv)
	mv.is_moving = true
	mv.is_crouching = true
	core.set_ads(true)
	assert_almost_eq(core._get_first_shot_spread(),
			res.first_shot_spread * res.move_spread_multiplier
					* res.crouch_spread_multiplier / res.ads_multiplier,
			0.001, "全因素：base × move × crouch ÷ ads")
