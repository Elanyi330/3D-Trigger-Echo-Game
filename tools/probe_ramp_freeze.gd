# tools/probe_ramp_freeze.gd —— 塔坡道台阶冻结复现探针（2026-08-15）
# 复现 ep_0104 EastTower 卡死现场：玩家在 (18.59, 2.17, -5.53)（东塔坡道第 5 级）
# 面朝 +z（坡上）全速前进 23s 不动。探针直接接管命令推进，观察控制器行为。
# 最小场景（map_greybox 物理图 + 裸 MovementController，无渲染资源，headless 安全）。
# 用法：godot --headless --path . -s tools/probe_ramp_freeze.gd
extends SceneTree

const TEST_POS := Vector3(18.59, 2.17, -5.53)   # 卡死现场（胶囊中心 = 脚 + 0.915）
const TEST_YAW := -178.93 * PI / 180.0
const SAMPLE_S := 4.0


func _init() -> void:
	# 灰盒地图（同 probe_v3_walk 模式：物理碰撞无视觉）
	var map := Node3D.new()
	root.add_child(map)
	var gb: Node3D = (load("res://Levels/M2_TDM/map_greybox.gd") as GDScript).new()
	gb.name = "MapGreybox"
	map.add_child(gb)
	gb.build()
	# 裸玩家控制器（同 Player.tscn 结构：MovementController + 胶囊碰撞）
	var player := MovementController.new()
	player.name = "Player"
	player.collision_layer = 2
	player.collision_mask = 1
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.5
	cap.height = 1.83
	cs.shape = cap
	player.add_child(cs)
	root.add_child(player)
	await physics_frame
	await physics_frame
	var cmd := MovementCommand.new()
	cmd.move_axis = Vector2(0, 1)
	player.command_override = cmd
	player.global_position = TEST_POS
	player.velocity = Vector3.ZERO
	player.rotation.y = TEST_YAW
	var t := 0.0
	var last_report := -1.0
	while t < SAMPLE_S:
		await physics_frame
		t += 1.0 / 60.0
		var slot := int(t * 4.0)
		if slot != last_report:
			last_report = slot
			var floor_n := ""
			var walls: Array[String] = []
			for i in player.get_slide_collision_count():
				var c := player.get_slide_collision(i)
				if c.get_normal().y >= 0.7071:
					floor_n = str(c.get_collider().name)
				elif absf(c.get_normal().y) < 0.5:
					walls.append(str(c.get_collider().name)
							+ " n=(%.2f,%.2f,%.2f)"
							% [c.get_normal().x, c.get_normal().y, c.get_normal().z])
			print("t=%.2f pos=(%.3f,%.3f,%.3f) v=(%.2f,%.2f,%.2f) yaw=%.1f° on_floor=%s on_wall=%s floor=%s walls=%s"
					% [t, player.global_position.x, player.global_position.y,
					player.global_position.z, player.velocity.x, player.velocity.y,
					player.velocity.z, player.rotation.y * 180.0 / PI, player.is_on_floor(),
					player.is_on_wall(), floor_n, "|".join(walls)])
	var moved := Vector2(player.global_position.x - TEST_POS.x,
			player.global_position.z - TEST_POS.z).length()
	print("4s 总水平位移: %.3fm" % moved)
	if moved < 0.05:
		print("REPRO: 玩家冻结复现（%s 处全速推进不动）" % TEST_POS)
		quit(2)
	else:
		print("OK: 玩家可移动（位移 %.3fm），未复现冻结" % moved)
		quit(0)
