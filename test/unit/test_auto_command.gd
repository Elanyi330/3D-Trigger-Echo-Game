# test/unit/test_auto_command.gd
# T1（2026-08-14）：MovementCommand 命令接管钩子测试（TDD，先 RED 后 GREEN）
# 目标：AI/自动遍历通过 MovementCommand 驱动玩家同款控制器——物理语义零改动，
#   MOVEMENT_REV 不 bump（测试 4 红线钉死）。
# 装配方式同 test_controller.gd：实例化生产场景 Player.tscn + 物理地面 + 真实物理帧推进。
# move_axis 语义（MovementCommand.gd 注释）：角色本地轴 x=左右/y=前后——
#   旋转 0 时前进 = -Z（y=+1），右移 = +X（x=+1），与标准 Godot 模板 get_vector
#   (&"move_left", &"move_right", &"move_forward", &"move_back") 同构。
extends GutTest

var player: MovementController


func before_each() -> void:
	player = load("res://Player/Player.tscn").instantiate()
	player.position = Vector3(0, 1.5, 0)
	add_child_autofree(player)


# 测试辅助：台阶/地面盒构造器——BoxShape3D StaticBody（Objects 层 1）
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


# ── T1-1：命令轴驱动角色——y=+1 前进（-Z），x=+1 右移（+X）──
func test_command_axis_drives_character() -> void:
	_make_floor()
	await wait_physics_frames(25)
	assert_true(player.is_on_floor(), "前置：玩家应落在地面上")

	var cmd := MovementCommand.new()
	player.command_override = cmd

	# 相位 1：move_axis=(0,1) = 前进（rotation.y=0 → -Z）
	cmd.move_axis = Vector2(0, 1)
	var start_pos := player.global_position
	await wait_physics_frames(60)
	var d := player.global_position - start_pos
	print("CMD_AXIS_FWD d=", d)
	assert_lt(d.z, -0.5, "前进指令 60 帧后沿前方（-Z）位移 > 0.5m（实际 %.2f）" % -d.z)
	assert_almost_eq(d.x, 0.0, 0.2, "纯前进指令不应产生横向（X）位移")

	# 相位 2：move_axis=(1,0) = 右移（+X）
	var x0 := player.global_position.x
	cmd.move_axis = Vector2(1, 0)
	await wait_physics_frames(60)
	var d2x := player.global_position.x - x0
	print("CMD_AXIS_RIGHT d2x=", d2x)
	assert_gt(d2x, 0.5, "右移指令 60 帧后沿 +X 位移 > 0.5m（实际 %.2f）" % d2x)


# ── T1-2：命令跳跃边沿消费——单帧边沿，读取即清零；只离地一次 ──
func test_command_jump_edge_consumed() -> void:
	_make_floor()
	await wait_physics_frames(25)
	assert_true(player.is_on_floor(), "前置：玩家应落在地面上")

	var cmd := MovementCommand.new()
	player.command_override = cmd

	var y0 := player.global_position.y
	cmd.jump_pressed = true
	await wait_physics_frames(2)
	assert_false(cmd.jump_pressed, "跳跃边沿应在控制器读取后清零（单帧边沿消费语义）")
	assert_gt(player.velocity.y, 0.0, "起跳后应上升（velocity.y > 0）")
	assert_gt(player.global_position.y, y0, "起跳后位置升高")

	# 随后 120 帧：边沿消费后 jump_pressed 恒 false，落地后不再二次起跳
	var takeoffs := 0
	var prev_on_floor := false
	for i in 120:
		await wait_physics_frames(1)
		assert_false(cmd.jump_pressed,
				"第 %d 帧：边沿已消费，期间 jump_pressed 恒 false" % i)
		var on_floor := player.is_on_floor()
		if not on_floor and prev_on_floor:
			takeoffs += 1
		prev_on_floor = on_floor
	print("CMD_JUMP takeoffs_in_window=", takeoffs,
			" on_floor=", player.is_on_floor())
	assert_eq(takeoffs, 0, "只离地一次：落地后无第二次离地（无二次跳跃）")
	assert_true(player.is_on_floor(), "120 帧内应已落地且保持 on_floor")


# ── T1-3：override 置空恢复 Input 路径——注入前后行为一致 ──
# 注（与 brief 的偏差，物理红线所迫）：brief 原断言"置空后 30 帧位移 <0.2m"在本引擎
# 物理下不可达——无输入时 ground 分支以 deceleration=10 刹车，满速 6.35 的刹车滑行
# 距离 = speed/deceleration = 0.635m（离散帧 Σv·dt = v/w_frame·dt = v/10），任何 >=0.2m
# 的断言都会误杀真实行为。改断言 <0.7m（物理上限 0.635 + 裕量）：若 override 未被
# 置空而继续读命令，位移 ≈5.5m 远超阈值，判别力不变。物理语义零改动（红线）不受影响。
func test_override_null_restores_input_path() -> void:
	_make_floor()
	await wait_physics_frames(25)
	assert_true(player.is_on_floor(), "前置：玩家应落在地面上")

	var cmd := MovementCommand.new()
	cmd.move_axis = Vector2(0, 1)  # 前进（-Z）
	player.command_override = cmd
	await wait_physics_frames(30)
	var pos_a := player.global_position
	assert_lt(pos_a.z, -0.5, "命令驱动 30 帧应已前进（A 位移 > 0.5m）")

	player.command_override = null
	await wait_physics_frames(30)
	var pos_b := player.global_position
	var drift: float = absf(pos_b.z - pos_a.z)
	print("CMD_NULL drift_z=", drift)
	assert_lt(drift, 0.7,
			"override 置空后无命令输入：刹车滑行 <0.7m（若仍读命令则 ≈5m，实际 %.2f）" % drift)

	player.command_override = cmd
	await wait_physics_frames(30)
	var pos_c := player.global_position
	var c_move: float = pos_b.z - pos_c.z
	print("CMD_REINJECT c_move_z=", c_move)
	assert_gt(c_move, 0.2,
			"重新注入命令后位置继续沿前进方向增长（位移 C > 0.2m，实际 %.2f）" % c_move)


# ── T1-4：MOVEMENT_REV 红线钉死——命令接管是输入来源切换，不是移动语义变更 ──
func test_movement_rev_unchanged() -> void:
	assert_eq(MovementController.MOVEMENT_REV,
			"move-r3:step0.62+chain+firstframe,air-rest3.0/run0.76",
			"MOVEMENT_REV 不得 bump：物理语义零改动")
