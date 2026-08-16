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


# 测试辅助：真实 Enemy.tscn 实例（定位先于入树——入树后再设 global_position 会让形状
# 以原点陈旧变换注册进物理空间一帧，附近玩家 move_and_slide 会被去穿透推开（2026-08-16 实测）；
# 未入树时须用 position 而非 global_position（后者触发引擎 !is_inside_tree 报错，GUT 计为失败））
func _spawn_enemy(at: Vector3) -> Enemy:
	var e: Enemy = load("res://Levels/Enemy/Enemy.tscn").instantiate()
	e.position = at
	add_child_autofree(e)
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
	# bot.z + 玩家半径 0.5 + bot 半径 0.31 = bot.z + 0.81（接触前沿）。
	# 断言形式为终态双界（非逐帧）：逐帧 assert_lt 在接近阶段必然失败（玩家合法地
	# 从 +Z 走向接触点，途中 z 恒大于阈值——此前被"入树后再定位"的陈旧形状去穿透
	# 瞬移掩盖，2026-08-16 修复后暴露，改为终态断言，判别力不变）：
	#   上界 bot.z+0.85：被挡停在接触点 -1.19 < -1.15（无掩码时玩家 60 帧走 ~6.3m 亦过界，
	#     但下界拦截）；下界 bot.z-0.5：未穿过 bot（无掩码时 z≈-6.3 越过此界 → 失败）。
	await wait_physics_frames(60)
	assert_lt(player.global_position.z, bot.global_position.z + 0.85,
			"玩家被 bot 挡路：停在接触前沿（玩家 %.3f / bot %.3f）"
			% [player.global_position.z, bot.global_position.z])
	assert_gt(player.global_position.z, bot.global_position.z - 0.5,
			"玩家未穿过 bot（玩家 %.3f / bot %.3f）"
			% [player.global_position.z, bot.global_position.z])


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


# ── T0-7（修复轮 2）：Enemy.new() 路径懒创建躯干碰撞体——不穿地坠落 ──
func test_enemy_new_path_has_body_and_rests() -> void:
	# 回归锚：生产消费方（L_M2/L_Main）走 Enemy.new()（非 tscn），无懒创建兜底则
	# 无躯干碰撞体 → 穿地板坠落（审查实测 y=-36.87）、不可命中、不挡路
	_make_floor()
	var e := Enemy.new()
	e.position = Vector3(0, 1, 0)  # 先定位再入树（防陈旧形状注册，见 _spawn_enemy 注释）
	add_child_autofree(e)
	await wait_physics_frames(60)
	var col: CollisionShape3D = null
	for c in e.get_children():
		if c is CollisionShape3D:
			col = c
			break
	assert_not_null(col, "Enemy.new() 路径应懒创建躯干碰撞体（与 tscn 同参）")
	assert_lt(e.global_position.y, 0.2, "不再穿地坠落（实际 y %.3f）" % e.global_position.y)
	assert_true(e.is_on_floor(), "落定站在地面上")


# ── T0-8（修复轮 2）：bot 碰撞掩码含 Player 层——移动 bot 不穿玩家身体 ──
func test_bot_blocked_by_player_body() -> void:
	# 回归锚：bot collision_mask=3（1|2）后，bot 撞玩家身体被挡——胶囊半径和
	# 0.5+0.31=0.81（接触前沿）；掩码缺 Player 层则 bot 穿过静止玩家
	_make_floor()
	var player: MovementController = load("res://Player/Player.tscn").instantiate()
	player.position = Vector3(0, 1.5, 0)
	add_child_autofree(player)
	var bot := Enemy.new()
	bot.position = Vector3(0, 0.5, 3)  # 默认 yaw 0 面向 -Z = 玩家方向；先定位再入树
	add_child_autofree(bot)
	await wait_physics_frames(30)  # 双方落定
	bot.command_override.move_axis = Vector2(0, 1)  # 前进（-Z，朝玩家）
	await wait_physics_frames(60)
	assert_lt(bot.global_position.z, 2.0, "bot 确实向玩家移动（防空转假绿，实际 z %.3f）" % bot.global_position.z)
	assert_gt(bot.global_position.z, 0.8, "bot 被玩家身体挡住：z 停在接触前沿 0.81 以北（实际 %.3f）" % bot.global_position.z)
