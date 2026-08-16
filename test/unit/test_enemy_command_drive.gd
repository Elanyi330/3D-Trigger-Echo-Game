# test/unit/test_enemy_command_drive.gd
# M3.1 T1（2026-08-16）：bot 输入语义固化测试（MovementCommand → MovementController 冒烟）。
# 目标：把 M3.3 决策层依赖的 bot 输入语义用测试钉死——move_axis 本地轴驱动（yaw=0 时
#   前进 = -Z）/ 命令轴随 yaw 旋转 / jump_pressed 单帧边沿读取即清零 / crouch 预留恒 false
#   不干扰移动。本任务为纯测试任务：生产代码零改动（MOVEMENT_REV 铁律）。生产语义全部
#   正确：测试 1/3/4 首跑直接 GREEN（回归守卫）；测试 2 首跑 RED——原因为简报"+X 位移"
#   期望与本引擎右手系相违（详见 T1-2 注释），改测试断言后 GREEN（各测试 RED 锚见文件尾）。
# 装配方式同 test_enemy_bot_body.gd：Enemy.new()（生产同款路径，T0 懒创建兜底保证碰撞体）
#   + 定位先于入树（防陈旧形状一帧注册，见 _spawn_enemy 注释）+ 物理地面（Objects 层 1，
#   顶面 y=0）+ 真实物理帧推进。command_override 在 Enemy._ready 恒设——直接取引用驱动，
#   不新建 MovementCommand（新实例与恒设实例路径分叉则测不到真实语义）。
extends GutTest

const SPAWN_POS := Vector3(0, 1, 0)  # 悬空生成（胶囊底=原点，落定 y≈0）
const SETTLE_FRAMES := 50            # 落定等待（重力下落 + 落地稳定）
const DRIVE_FRAMES := 60             # 驱动相位帧数（满速 6.35 下 60 帧位移 ≫ 0.5m）


# 测试辅助：盒构造器——BoxShape3D StaticBody（Objects 层 1，同 test_enemy_bot_body.gd）
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


# 测试辅助：Enemy.new() 落定实例——定位先于入树（防陈旧形状注册，见
# test_enemy_bot_body.gd _spawn_enemy 注释），返回时已落定在地面上。
func _spawn_settled() -> Enemy:
	var e := Enemy.new()
	e.position = SPAWN_POS
	add_child_autofree(e)
	await wait_physics_frames(SETTLE_FRAMES)
	return e


# ── T1-1：命令轴驱动 bot——move_axis=(0,1) 本地前进（yaw=0 → -Z），无横向漂移 ──
func test_bot_move_axis_forward() -> void:
	_make_floor()
	var e := await _spawn_settled()
	assert_true(e.is_on_floor(), "前置：bot 应落定在地面上")
	var cmd: MovementCommand = e.command_override
	cmd.move_axis = Vector2(0, 1)  # 本地前进
	var start := e.global_position
	await wait_physics_frames(DRIVE_FRAMES)
	var d := e.global_position - start
	print("BOT_FWD d=", d)
	assert_lt(d.z, -0.5, "前进指令 60 帧后沿前方（-Z）位移 > 0.5m（实际 %.2f）" % -d.z)
	assert_almost_eq(d.x, 0.0, 0.2, "纯前进指令不应产生横向（X）位移（实际 %.2f）" % d.x)


# ── T1-2：命令轴随 yaw 旋转——yaw=PI/2 后本地前进 = -X（Godot 右手系）──
# 方向口径（与简报"+X 位移"的偏差）：rotation.y=0 时本地前进 = -Z（T0-8 实测锚）；
# Godot +Y 正转为右手系俯视逆时针，basis.z=(sinθ,0,cosθ) → yaw=+PI/2 时前进 -basis.z
# = -X。首跑 RED 实测：生产沿 -X 走 5.79m 且 d.z≈0——命令轴严格随朝向旋转，生产正确；
# 简报的"+X"期望与引擎右手系相违，故断言改为沿本地前进轴（-X）位移 > 0.5。
func test_bot_move_follows_yaw() -> void:
	_make_floor()
	var e := await _spawn_settled()
	assert_true(e.is_on_floor(), "前置：bot 应落定在地面上")
	e.rotation.y = PI / 2  # 左转 90°（俯视逆时针）：本地前进 -Z → -X
	var cmd: MovementCommand = e.command_override
	cmd.move_axis = Vector2(0, 1)
	var start := e.global_position
	await wait_physics_frames(DRIVE_FRAMES)
	var d := e.global_position - start
	print("BOT_YAW d=", d)
	assert_lt(d.x, -0.5, "yaw=PI/2 时本地前进沿 -X（实际 %.2f）" % d.x)
	assert_almost_eq(d.z, 0.0, 0.2, "yaw 旋转后前进不应残留原 -Z 分量（实际 %.2f）" % d.z)


# ── T1-3：跳跃边沿消费——jump_pressed 单帧边沿读取即清零；真实物理起跳离地 ──
func test_bot_jump_edge_consumed() -> void:
	_make_floor()
	var e := await _spawn_settled()
	assert_true(e.is_on_floor(), "前置：bot 应落定在地面上")
	var cmd: MovementCommand = e.command_override
	var y0 := e.global_position.y
	cmd.jump_pressed = true
	# 边沿消费断言取第 2 帧（同 test_auto_command.gd：GUT wait 恢复时序下第 1 帧的
	# _physics_process 未必已完成——第 2 帧断言等价钉死"读取即清零"的消费语义）。
	await wait_physics_frames(2)
	assert_false(cmd.jump_pressed, "① 跳跃边沿应在控制器读取后清零（单帧边沿消费语义）")
	assert_gt(e.velocity.y, 0.0, "起跳后应上升（velocity.y > 0——真实物理，非位移模拟）")
	# ② 推进 ≤90 帧窗口：期间 y 上升超过落定 y + 0.5；边沿已消费则 jump_pressed 恒 false
	# （一次性边沿）。峰值 ≥ 阈值且已落地时提前退出。
	var max_y := e.global_position.y
	var risen: bool = max_y > y0 + 0.5
	var frames := 2
	while frames < 90 and not (risen and e.is_on_floor()):
		await wait_physics_frames(1)
		frames += 1
		assert_false(cmd.jump_pressed,
				"第 %d 帧：边沿已消费，期间 jump_pressed 恒 false（一次性边沿）" % frames)
		max_y = maxf(max_y, e.global_position.y)
		risen = max_y > y0 + 0.5
	print("BOT_JUMP max_rise=", max_y - y0, " frames=", frames)
	assert_true(risen, "② 期间 y 上升超过落定 y + 0.5（实际峰值 +%.2f）" % (max_y - y0))


# ── T1-4：crouch 预留恒 false——不干扰移动（前进位移与 T1-1 同量级）──
func test_bot_crouch_reserved_false() -> void:
	_make_floor()
	var e := await _spawn_settled()
	assert_true(e.is_on_floor(), "前置：bot 应落定在地面上")
	var cmd: MovementCommand = e.command_override
	assert_false(cmd.crouch, "crouch 预留默认恒 false（未来 AI 蹲伏接入点，当前无人写入）")
	cmd.move_axis = Vector2(0, 1)
	var start := e.global_position
	await wait_physics_frames(DRIVE_FRAMES)
	var d := e.global_position - start
	print("BOT_CROUCH d=", d)
	assert_lt(d.z, -0.5, "crouch=false 不干扰移动：前进位移与 T1-1 同量级（实际 %.2f）" % -d.z)


# ── RED 锚说明（本任务纯测试：生产零改动）──
# 1. move_axis 驱动：生产若未在 Enemy._ready 恒设 command_override、或控制器不读命令轴 →
#    bot 站桩 60 帧位移 < 0.5m → RED（对应 T0 前 StaticBody3D 站桩语义）。
# 2. 轴随 yaw：生产若用固定世界轴映射（不乘 get_global_transform().basis）→
#    yaw=PI/2 时位移留在 -Z（d.x≈0）→ RED。首跑 RED 实测为断言方向写反（简报 +X 期望
#    与右手系相违，见 T1-2 注释）——生产沿 -X 走满 5.79m 证明轴严格随朝向旋转。
# 3. 跳跃边沿：生产若读取后不清零 jump_pressed → 断言 ① RED；若不起跳（velocity.y 不动、
#    y 不升）→ 断言 ② RED。
# 4. crouch：生产若默认 crouch=true、或 crouch 进入减速路径（速度降档）→ 位移 < 0.5m → RED。
