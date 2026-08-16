# test/unit/test_bot_hearing.gd
# M3.2 T7（2026-08-17）：听觉事件测试（TDD，先 RED 后 GREEN）。
# 目标：四武器 noise_radius 入 .tres（AK 45/Glock 30/刀 2/M67 50，数值唯一来源）/
#   FootstepEmitter 步幅事件（每 2.5m 一发；跑动 20m 半径 / 蹲行 5m 半径）/
#   感知听觉节 TTL 衰减（枪声 3s / 脚步 1.5s）/ heard_at 距离判定边界 /
#   heard_event 全链路（距离 ≤ radius + 阵营过滤：同阵营源忽略）。
# RED 锚：生产类 FootstepEmitter 尚不存在——本脚本引用该类型即类加载失败
#   （"Could not find type FootstepEmitter"），即正确的 RED 失败原因。
# tick 频率铁律：感知与脚步发射器均每物理帧 tick 一次（1/60 delta，60Hz 口径，
#   同生产节奏）；物理帧驱动断言用行为断言（不断言精确帧数）。
extends GutTest

const ENEMY_SCRIPT := preload("res://Levels/Enemy/Enemy.gd")

var _footsteps: Array = []   # [{pos: Vector3, radius: float}]
var _heard: Array = []       # [{kind: String, pos: Vector3}]


func _on_footstep(pos: Vector3, radius: float) -> void:
	_footsteps.append({"pos": pos, "radius": radius})


func _on_heard(kind: String, pos: Vector3) -> void:
	_heard.append({"kind": kind, "pos": pos})


## GUT 同脚本实例跨测试复用——实例数组必须逐测试清零（防跨测试事件泄漏）。
func before_each() -> void:
	_footsteps.clear()
	_heard.clear()


# ── 测试辅助 ──

# 盒构造器（同 test_enemy_command_drive.gd 范式）：BoxShape3D StaticBody（Objects 层 1）
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
func _spawn_settled() -> Enemy:
	var e := Enemy.new()
	e.position = Vector3(0, 1, 0)
	add_child_autofree(e)
	await wait_physics_frames(50)
	return e


# 感知 tick 驱动：每物理帧 tick 一次（60Hz 口径），≤frames 帧推进。
func _drive_ticks(per: BotPerception, frames: int) -> void:
	for i in frames:
		per.tick(1.0 / 60.0)
		await wait_physics_frames(1)


# ── T7-1：四把武器 noise_radius = 45/30/2/50（.tres 数值唯一来源）──
func test_noise_radius_resources() -> void:
	var ak: WeaponResource = load("res://Weapons/weapon_ak47.tres")
	var glock: WeaponResource = load("res://Weapons/weapon_glock18.tres")
	var knife: WeaponResource = load("res://Weapons/weapon_knife.tres")
	var m67: WeaponResource = load("res://Weapons/weapon_m67.tres")
	assert_almost_eq(ak.noise_radius, 45.0, 1e-4, "AK 噪音半径 45m（.tres 唯一来源）")
	assert_almost_eq(glock.noise_radius, 30.0, 1e-4, "Glock 噪音半径 30m")
	assert_almost_eq(knife.noise_radius, 2.0, 1e-4, "刀 噪音半径 2m（轻微挥击声）")
	assert_almost_eq(m67.noise_radius, 50.0, 1e-4, "M67 爆炸噪音半径 50m")


# ── T7-2：命令驱动直走——每 2.5m 一发 footstep，满速半径 = RUN_RADIUS ──
# 满速 6.35 m/s > CROUCH_SPEED_MAX 3.0 → 跑动半径；80 帧 ≈ 8.4m → ≥2 次事件（2.5/5.0/7.5m）。
func test_footstep_stride_emits() -> void:
	_make_floor()
	var e := await _spawn_settled()
	assert_true(e.is_on_floor(), "前置：bot 应落定在地面上")
	var emitter := FootstepEmitter.new()
	add_child_autofree(emitter)
	emitter.setup(e)
	emitter.footstep.connect(_on_footstep)
	var cmd: MovementCommand = e.command_override
	cmd.move_axis = Vector2(0, 1)  # 本地前进（yaw=0 → -Z）
	for i in 80:
		await wait_physics_frames(1)
		emitter.tick(1.0 / 60.0)
	assert_gte(_footsteps.size(), 2,
			"直走约 8m（步幅 2.5m）应发 ≥2 次 footstep（实际 %d）" % _footsteps.size())
	for f in _footsteps:
		assert_almost_eq(f["radius"], FootstepEmitter.RUN_RADIUS, 1e-4,
				"满速（6.35 > 3.0）应为跑动半径 20m")


# ── T7-3：蹲行模拟（is_crouching → crouch_speed 2.59 ≤ 3.0）→ CROUCH_RADIUS ──
# 150 帧 ≈ 6.5m → ≥2 次事件；全程速度 ≤ 3.0 → 蹲行半径。
func test_footstep_crouch_radius() -> void:
	_make_floor()
	var e := await _spawn_settled()
	assert_true(e.is_on_floor(), "前置：bot 应落定在地面上")
	e.is_crouching = true  # 蹲行模拟：加速目标用 crouch_speed 2.59（≤ CROUCH_SPEED_MAX 3.0）
	var emitter := FootstepEmitter.new()
	add_child_autofree(emitter)
	emitter.setup(e)
	emitter.footstep.connect(_on_footstep)
	var cmd: MovementCommand = e.command_override
	cmd.move_axis = Vector2(0, 1)
	for i in 150:
		await wait_physics_frames(1)
		emitter.tick(1.0 / 60.0)
	assert_gte(_footsteps.size(), 2,
			"蹲行约 6.5m 应发 ≥2 次 footstep（实际 %d）" % _footsteps.size())
	for f in _footsteps:
		assert_almost_eq(f["radius"], FootstepEmitter.CROUCH_RADIUS, 1e-4,
				"蹲速 2.59 ≤ 3.0 应为蹲行半径 5m")


# ── T7-4：heard_at 距离判定边界——radius 内 true / 外 false ──
func test_heard_at_boundary() -> void:
	assert_true(BotPerception.heard_at(Vector3.ZERO, Vector3(20, 0, 0), 20.0),
			"20m 界内（含边界）→ true")
	assert_false(BotPerception.heard_at(Vector3.ZERO, Vector3(20.1, 0, 0), 20.0),
			"20.1m 界外 → false")


# ── T7-5：TTL 衰减——枪声 3s / 脚步 1.5s 到期剔除 ──
# 事件置 200m 远处（超出任何半径：不触发 heard 消费，纯 TTL 口径）；
# 推 1.0s 均仍在 → 推 1.667s 脚步已剔除 → 推 3.1s 队列空。
func test_ttl_decay() -> void:
	var body := CharacterBody3D.new()
	add_child_autofree(body)
	var per := BotPerception.new()
	add_child_autofree(per)
	per.setup(body, "enemy", null)
	per._push_noise_event("gunshot", Vector3(200, 0, 0), 45.0)
	per._push_noise_event("footstep", Vector3(200, 0, 0), 20.0)
	await _drive_ticks(per, 60)   # 累计 1.0s
	assert_eq(per._heard_events.size(), 2, "推 1.0s：枪声(3s)与脚步(1.5s)均未到期")
	await _drive_ticks(per, 40)   # 累计 1.667s
	assert_eq(per._heard_events.size(), 1, "脚步 1.5s TTL 已剔除（剩枪声 1 条）")
	await _drive_ticks(per, 86)   # 累计 3.1s
	assert_eq(per._heard_events.size(), 0, "枪声 3s TTL 剔除 → 队列空")


# ── T7-6：heard_event 全链路——距离判定 + 阵营过滤 ──
# 感知 faction="enemy"：friendly 源 30m（< AK 45）→ 发射；enemy 源（同阵营）→ 不发；
# friendly 源 50m（> 45）→ 不发。耳朵 = body + EYE_OFFSET（1.65m 高差无碍余量）。
func test_heard_event_flow() -> void:
	var body := CharacterBody3D.new()
	add_child_autofree(body)
	await wait_physics_frames(1)
	var per := BotPerception.new()
	add_child_autofree(per)
	per.setup(body, "enemy", null)
	per.heard_event.connect(_on_heard)
	# ① friendly 源 30m（< 45）→ 听到
	per._push_noise_event("gunshot", Vector3(30, 0, 0), 45.0, "friendly")
	await _drive_ticks(per, 2)
	assert_eq(_heard.size(), 1, "friendly 源枪声 30m 内应发 heard_event")
	if _heard.size() == 1:
		assert_eq(_heard[0]["kind"], "gunshot", "事件类型 = gunshot")
	# ② enemy 源（同阵营）→ 不发
	per._push_noise_event("gunshot", Vector3(10, 0, 0), 45.0, "enemy")
	await _drive_ticks(per, 2)
	assert_eq(_heard.size(), 1, "同阵营源（enemy）不发 heard_event")
	# ③ friendly 源 50m（> 45 半径）→ 不发
	per._push_noise_event("gunshot", Vector3(50, 0, 0), 45.0, "friendly")
	await _drive_ticks(per, 2)
	assert_eq(_heard.size(), 1, "50m 超出噪音半径不发 heard_event")
