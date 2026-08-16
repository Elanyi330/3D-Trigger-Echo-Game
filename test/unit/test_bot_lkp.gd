# test/unit/test_bot_lkp.gd
# M3.2 T8（2026-08-17）：LKP 威胁记忆测试（TDD，先 RED 后 GREEN）。
# 目标：可见时记录最后已知位置（pos = hostile_visible 发射位置，invisible_t 清零）
#   / 不可见时位置冻结 + invisible_t 每 tick 累计 / 超 LKP_TTL 8s 遗忘
#   （条目删除 + lkp_updated(ZERO, false)）/ 死亡即时删除（不报信号）。
# 轻量装配（同 test_bot_hearing 范式）：GutTest 场景直建观察者/目标 Enemy + 地面 +
#   墙体——真实感知链路（节流扫描 + 视线射线）驱动，不装 L_M2（los 测试已证
#   GutTest 场景射线可用）。直建 Enemy spawn_protection=0（L_M2 才显式设置）→
#   take_damage(999) 立即死亡。
# RED 锚：生产类 BotPerception 尚无 LKP 接口（lkp_updated/_lkp/last_known_pos/
#   invisible_time）——本脚本引用即类加载失败（"Cannot find member 'lkp_updated'"
#   类错误，即正确的 RED 失败原因；同 T6/T7 锚口径）。
# tick 频率铁律：感知每物理帧 tick 一次（1/60 delta，60Hz 口径，同生产节奏）；
#   断言用行为断言（不断言精确帧数）。
extends GutTest

const ENEMY_SCRIPT := preload("res://Levels/Enemy/Enemy.gd")

var _lkp_events: Array = []   # [{target: Node, pos: Vector3, visible: bool}]


func _on_lkp(target: Node, pos: Vector3, visible: bool) -> void:
	_lkp_events.append({"target": target, "pos": pos, "visible": visible})


## GUT 同脚本实例跨测试复用——事件数组必须逐测试清零（防跨测试事件泄漏）。
func before_each() -> void:
	_lkp_events.clear()


# ── 测试辅助 ──

# 盒构造器（同 test_bot_hearing.gd 范式）：BoxShape3D StaticBody（Objects 层 1）
func _make_box(size: Vector3, center: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	body.position = center
	add_child_autofree(body)
	return body


# 物理地面（40×1×40，顶面 y=0）
func _make_floor() -> StaticBody3D:
	return _make_box(Vector3(40, 1, 40), Vector3(0, -0.5, 0))


# Enemy.new() 落定实例——定位先于入树（防陈旧形状注册，同 test_enemy_command_drive.gd）
func _spawn_settled(pos: Vector3, enemy_side: bool) -> Enemy:
	var e := Enemy.new()
	e.is_enemy = enemy_side
	e.position = pos
	add_child_autofree(e)
	await wait_physics_frames(50)
	return e


# 感知装配：先立地面（防落体——无地则观察者/目标持续下坠，LKP 位置断言失效）；
# 观察者（enemy）朝 -Z（rotation.y=0），目标（friendly）正前 10m 无遮挡；
# per 绑定观察者 + 连 lkp_updated（敌 bot 看友 bot 敌对——T6 阵营口径）。
func _setup_perception() -> Dictionary:
	_make_floor()
	var observer := await _spawn_settled(Vector3(0, 1, 0), true)
	var target := await _spawn_settled(Vector3(0, 1, -10), false)
	observer.rotation.y = 0.0
	var per := BotPerception.new()
	add_child_autofree(per)
	per.setup(observer, observer.get_faction(), null)
	per.lkp_updated.connect(_on_lkp)
	return {"observer": observer, "target": target, "per": per}


# 感知 tick 驱动：每物理帧 tick 一次（60Hz 口径），≤frames 帧推进。
func _drive(per: BotPerception, frames: int) -> void:
	for i in frames:
		per.tick(1.0 / 60.0)
		await wait_physics_frames(1)


# ── T8-1：可见 → LKP = 目标实际位置、invisible_t 0、lkp_updated(true) ──
func test_lkp_set_on_visible() -> void:
	var h := await _setup_perception()
	var per: BotPerception = h["per"]
	var target: Enemy = h["target"]
	await _drive(per, 30)  # ≥2 节流周期（0.2s = 12 帧）
	assert_almost_eq(per.last_known_pos(target).distance_to(target.global_position),
			0.0, 0.1, "可见目标 LKP = 目标实际位置（容差 0.1）")
	assert_almost_eq(per.invisible_time(target), 0.0, 1e-4,
			"可见时 invisible_t 恒 0（每次扫描刷新清零）")
	var saw_visible := false
	for ev in _lkp_events:
		if ev["target"] == target and ev["visible"]:
			saw_visible = true
	assert_true(saw_visible, "可见时应发射 lkp_updated(target, pos, true)（事件 %d 条）"
			% _lkp_events.size())


# ── T8-2：移出视线 → LKP 位置冻结 + invisible_t 递增 ──
# 可见相记录 old_pos → 立墙 + 目标墙后平移（(0,1,-8)，若位置刷新会跟随新位置）→
# 丢失相断言 LKP 仍 = old_pos（冻结）且 invisible_t > 0 并持续递增。
func test_lkp_retained_on_loss() -> void:
	var h := await _setup_perception()
	var per: BotPerception = h["per"]
	var target: Enemy = h["target"]
	await _drive(per, 30)  # 可见相
	var old_pos: Vector3 = per.last_known_pos(target)
	_make_box(Vector3(4, 3, 1), Vector3(0, 1.5, -5))  # 观察者与目标之间墙体
	await wait_physics_frames(2)  # 墙形状入空间（同帧 raycast 不可见）
	target.position = Vector3(0, 1, -8)  # 墙后平移：位置刷新会跟随新位置
	await wait_physics_frames(1)  # 目标形状注册（T0 教训）
	await _drive(per, 30)  # 丢失相（≥1 节流周期）
	var t1: float = per.invisible_time(target)
	assert_gt(t1, 0.0, "移出视线后 invisible_t 应开始累计（t1=%.3f）" % t1)
	assert_eq(per.last_known_pos(target), old_pos,
			"LKP 保持最后可见位置（不可见期间位置冻结）")
	await _drive(per, 30)
	assert_gt(per.invisible_time(target), t1,
			"invisible_t 持续递增（t2=%.3f > t1=%.3f）" % [per.invisible_time(target), t1])


# ── T8-3：不可见超 8.1s → 条目删除（遗忘）+ lkp_updated(ZERO, false) ──
# 丢失相推进 30 帧（invisible_t ≈ 0.4）再推 486 帧（8.1s）→ 累计 8.5s > LKP_TTL 8s。
func test_lkp_expiry() -> void:
	var h := await _setup_perception()
	var per: BotPerception = h["per"]
	var target: Enemy = h["target"]
	await _drive(per, 30)  # 可见相
	_make_box(Vector3(4, 3, 1), Vector3(0, 1.5, -5))
	await wait_physics_frames(2)
	await _drive(per, 30)  # 丢失相：hostile_lost 边沿已过，计时已起
	assert_gt(per.invisible_time(target), 0.0, "前置：已进入不可见计时")
	await _drive(per, 486)  # 再推 8.1s → 累计超 8s
	assert_eq(per.last_known_pos(target), Vector3.ZERO,
			"超 LKP_TTL 条目删除 → last_known_pos 返回 ZERO")
	assert_eq(per.invisible_time(target), -1.0, "无条目 → invisible_time 返回 -1")
	var saw_expiry := false
	for ev in _lkp_events:
		if ev["target"] == target and not ev["visible"] and ev["pos"] == Vector3.ZERO:
			saw_expiry = true
	assert_true(saw_expiry, "遗忘时应发射 lkp_updated(target, ZERO, false)")


# ── T8-4：可见后目标死亡 → 条目即时删除（不报信号）──
# 直建 Enemy spawn_protection=0（L_M2 才显式设置）→ take_damage(999) 立即死亡；
# 下一 tick 死亡检查删除条目（死亡删除静默——不报 lkp_updated）。
func test_lkp_clear_on_death() -> void:
	var h := await _setup_perception()
	var per: BotPerception = h["per"]
	var target: Enemy = h["target"]
	await _drive(per, 30)  # 可见相：LKP 条目建立
	assert_false(per._lkp.is_empty(), "前置：可见后 LKP 条目存在")
	_lkp_events.clear()  # 隔离死亡相事件
	target.take_damage(999.0)
	await _drive(per, 5)  # 下一 tick 死亡检查即删
	assert_eq(per.last_known_pos(target), Vector3.ZERO, "死亡 → 条目即时删除")
	assert_eq(per.invisible_time(target), -1.0, "无条目 → invisible_time 返回 -1")
	assert_eq(_lkp_events.size(), 0, "死亡删除不报 lkp_updated 信号")
