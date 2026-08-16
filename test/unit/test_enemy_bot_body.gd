# test/unit/test_enemy_bot_body.gd
# M3.1 T0（2026-08-16）：物理层 Bots + Enemy 类改造测试（TDD，先 RED 后 GREEN）。
# 目标：Enemy StaticBody3D → CharacterBody3D（MovementController 驱动）——重力落地、
#   无 Brain 站桩（command_override 恒 ZERO）、bot 挡玩家路（玩家碰撞掩码 7）、
#   武器命中掩码 5 命中 Bots 层、死亡帧清零速度。
# 装配方式同 test_auto_command.gd：真实 Enemy.tscn 实例 + 物理地面 + 真实物理帧推进。
# RED 锚：测试 1（类型）/ 2（重力落地）/ 5（collision_layer==4）/ 6（velocity 属性）；
#   测试 3/4 为回归守卫（改造前 StaticBody3D 站桩/挡路同语义，RED 阶段可能先绿）。
extends GutTest


# 测试辅助：盒构造器——BoxShape3D StaticBody（Objects 层 1，同 test_auto_command.gd）
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


# 测试辅助：物理地面（_make_box 表达：40×1×40，顶面 y=0）
func _make_floor() -> StaticBody3D:
	return _make_box(Vector3(40, 1, 40), Vector3(0, -0.5, 0))


# 测试辅助：真实 Enemy.tscn 实例（入树 + 定位；_ready 在 add_child 时同步执行）
func _spawn_enemy(at: Vector3) -> Enemy:
	var e: Enemy = load("res://Levels/Enemy/Enemy.tscn").instantiate()
	add_child_autofree(e)
	e.global_position = at
	return e


# ── T0-1：类型改造——Enemy 是 CharacterBody3D（改造前是 StaticBody3D）──
func test_enemy_is_character_body() -> void:
	# 显式 Node 类型：改造前 Enemy extends StaticBody3D，`e is CharacterBody3D` 在
	# 硬类型 Enemy 上会被静态类型系统直接拒编译（RED 证据即断言 false，而非脚本报错）
	var e: Node = Enemy.new()
	assert_true(e is CharacterBody3D, "Enemy 应为 CharacterBody3D（M3.1 T0 类型改造：可移动角色）")
	e.free()


# ── T0-2：重力落地——悬空生成后落到地面（改造前静态体悬空不动）──
func test_enemy_falls_onto_floor() -> void:
	_make_floor()
	var e := _spawn_enemy(Vector3(0, 2, 0))
	await wait_physics_frames(60)
	assert_lt(e.global_position.y, 1.1,
			"重力落地：60 帧后 y < 1.1（实际 %.3f；改造前静态体悬空不动）" % e.global_position.y)


# ── T0-3：无 Brain 站桩——command_override 恒 ZERO，水平零位移 ──
func test_enemy_stands_still_without_brain() -> void:
	_make_floor()
	var e := _spawn_enemy(Vector3(0, 0.5, 0))
	await wait_physics_frames(30)  # 落定
	var start := e.global_position
	await wait_physics_frames(60)
	var drift := Vector2(e.global_position.x - start.x, e.global_position.z - start.z).length()
	assert_lt(drift, 0.1,
			"无 Brain：60 帧水平位移 < 0.1（实际 %.3f）——command_override 恒 ZERO 站桩" % drift)


# ── T0-4：bot 挡玩家路——玩家碰撞掩码 7 包含 Bots 层，push 不穿过 ──
func test_player_blocked_by_bot() -> void:
	_make_floor()
	var player: MovementController = load("res://Player/Player.tscn").instantiate()
	player.position = Vector3(0, 1.5, 0)
	add_child_autofree(player)
	var bot := _spawn_enemy(Vector3(0, 0.5, -2))
	await wait_physics_frames(30)  # 双方落定
	var cmd := MovementCommand.new()
	cmd.move_axis = Vector2(0, 1)  # 前进（rotation.y=0 → -Z）
	player.command_override = cmd
	# 与简报口径的偏差：简报断言阈值"bot z+0.3"未计入双方胶囊半径——实际接触点 =
	# bot.z + 玩家半径 0.5 + bot 半径 0.31 = bot.z + 0.81（RED 实测玩家停于 -1.19）。
	# 按接触几何取阈值 bot.z + 0.85（接触 + 0.04 裕量）：被挡停住不触发；若掩码缺
	# Bots 层玩家 60 帧走 ~6.3m（z ≈ -6.3）远越阈值——判别力不变（偏差记录于任务报告）。
	for i in 60:
		await wait_physics_frames(1)
		assert_lt(player.global_position.z, bot.global_position.z + 0.85,
				"第 %d 帧：玩家被 bot 挡路，z 未越过接触前沿 bot.z+0.85（玩家 %.3f / bot %.3f）"
				% [i, player.global_position.z, bot.global_position.z])


# ── T0-5：武器命中掩码 5 命中 Bots 层 bot（RED 锚 = bot 在层 4）──
func test_hitscan_mask_hits_bot() -> void:
	_make_floor()
	var e := _spawn_enemy(Vector3(0, 0.5, 0))
	await wait_physics_frames(30)  # 落定
	assert_eq(e.collision_layer, 4, "bot 在 Bots 层（1<<2 = 4）——改造前在 Objects 层 1")
	# 自上而下射线，x 偏移 0.25 避开头 hitbox（球 r=0.18 于 x=0），只命中躯干胶囊
	var query := PhysicsRayQueryParameters3D.create(
			e.global_position + Vector3(0.25, 2.5, 0),
			e.global_position + Vector3(0.25, -0.5, 0))
	query.collision_mask = 5  # Objects|Bots（M3.1 T0 武器命中掩码）
	var hit := e.get_world_3d().direct_space_state.intersect_ray(query)
	assert_false(hit.is_empty(), "mask=5 自上而下应命中 bot 碰撞体")
	if hit.is_empty():
		return
	assert_eq(hit["collider"], e, "命中碰撞体 = bot 本体（躯干胶囊）")


# ── T0-6：死亡帧清零速度——防尸体被残余速度推离倒地点 ──
func test_dead_bot_velocity_zeroed() -> void:
	_make_floor()
	var e := _spawn_enemy(Vector3(0, 0.5, 0))
	await wait_physics_frames(30)  # 落定
	# 动态 set/get：改造前 Enemy 无 velocity 属性（硬类型 e.velocity 会拒编译，
	# set() 运行时报 "Invalid set index" 即 RED 证据）
	e.set("velocity", Vector3(5, 0, 0))  # 直接赋残余速度（模拟死亡前移动中）
	e.take_damage(999)
	assert_eq(e.get("velocity"), Vector3.ZERO, "死亡帧清零速度（改造前 StaticBody3D 无 velocity 属性）")
