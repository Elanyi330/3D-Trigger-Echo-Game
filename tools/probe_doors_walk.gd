# tools/probe_doors_walk.gd
# 过门探针：遍历所有建筑门洞（角建筑/建筑岛/出生建筑/大厅），
# 玩家从门洞一侧物理走到另一侧，检测是否卡住（走不通 = 窄道卡人）。
# 用法: godot --headless --path . -s res://tools/probe_doors_walk.gd
extends SceneTree

const GRAVITY_MULT := 2.0
const SPEED := 6.35
const BODY_RADIUS := 0.5
const BODY_HEIGHT := 1.83

var _map: Node3D
var _player: CharacterBody3D
var _fail := 0
var _total := 0


func _initialize() -> void:
	var gb_script := load("res://Levels/M2_TDM/map_greybox.gd")
	_map = Node3D.new()
	root.add_child(_map)
	var gb: Node3D = gb_script.new()
	gb.build()
	_map.add_child(gb)
	_player = CharacterBody3D.new()
	_player.collision_layer = 2
	_player.collision_mask = 1
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = BODY_RADIUS
	cap.height = BODY_HEIGHT
	cs.shape = cap
	_player.add_child(cs)
	root.add_child(_player)
	_run()


# 门洞测试点：[名称, 门洞中心, 穿行轴（x=沿x走穿门/z=沿z走穿门）]
const DOOR_TESTS := [
	# 大厅 4 门（门洞 4m）
	["大厅北门", Vector3(0, 0, 8.5), "z"],    # 沿 z 穿北门
	["大厅南门", Vector3(0, 0, -8.5), "z"],
	["大厅西门", Vector3(-10.5, 0, 0), "x"],  # 沿 x 穿西门
	["大厅东门", Vector3(10.5, 0, 0), "x"],
	# 角建筑门（NW 东门在 x=-16.5 朝东 → 沿 x 穿）
	["NW东门", Vector3(-16.5, 0, 21.5), "x"],
	["NW南门", Vector3(-23, 0, 14.5), "z"],
	["NE西门", Vector3(16.5, 0, 21.5), "x"],
	["NE南门", Vector3(23, 0, 14.5), "z"],
	["SW东门", Vector3(-16.5, 0, -21.5), "x"],
	["SW北门", Vector3(-23, 0, -14.5), "z"],
	["SE西门", Vector3(16.5, 0, -21.5), "x"],
	["SE北门", Vector3(23, 0, -14.5), "z"],
	# 建筑岛门（W_N：东门 x=-15、西门 x=-27，均沿 x 穿）
	["W_N东门", Vector3(-15.0, 0, -7.0), "x"],
	["W_N西门", Vector3(-27.0, 0, -7.0), "x"],
	# 出生建筑左右门（沿 x 穿）
	["SpawnN西门", Vector3(-6.5, 0, 23.0), "x"],
	["SpawnN东门", Vector3(6.5, 0, 23.0), "x"],
]


func _run() -> void:
	var d := 1.0 / Engine.physics_ticks_per_second
	for t in DOOR_TESTS:
		_total += 1
		var name: String = t[0]
		var center: Vector3 = t[1]
		var axis: String = t[2]
		var offset := Vector3(2.0, 0, 0) if axis == "x" else Vector3(0, 0, 2.0)
		var start := center - offset  # 门洞内侧 2m 出发
		var end := center + offset   # 穿到门洞另一侧 2m
		# 起点落地稳定（若起点在墙内，物理会推出）
		_player.global_position = Vector3(start.x, 1.0, start.z)
		_player.velocity = Vector3.ZERO
		for f in 20:
			await physics_frame
			_player.velocity.y -= 9.8 * GRAVITY_MULT * d
			_player.move_and_slide()
		var start_pos := _player.global_position
		# 记录起点是否被推出（起点卡墙内 = 探针起点问题）
		var start_displaced: float = start_pos.distance_to(start)
		# 走向另一侧（最多 150 帧）
		var dir := (end - start_pos).normalized()
		dir.y = 0
		var prev_dist := start_pos.distance_to(end)
		var reached := false
		var stuck_frames := 0
		var max_progress := start_pos.distance_to(end)
		for f in 150:
			await physics_frame
			_player.velocity = dir * SPEED
			_player.velocity.y -= 9.8 * GRAVITY_MULT * d
			_player.move_and_slide()
			var cur_dist := _player.global_position.distance_to(end)
			max_progress = minf(max_progress, cur_dist)
			if cur_dist < 1.0:
				reached = true
				break
			# 卡住检测：连续 30 帧没接近
			if cur_dist >= prev_dist - 0.05:
				stuck_frames += 1
				if stuck_frames > 30:
					break
			else:
				stuck_frames = 0
			prev_dist = cur_dist
		var status := "OK"
		if not reached:
			status = "FAIL 卡住(剩%.1fm)" % max_progress
			if start_displaced > 0.5:
				status = "起点被推出%.1fm(探针起点问题)" % start_displaced
			_fail += 1
		print("DOOR %s: %s" % [name, status])
	print("PROBE_DOORS total=%d fail=%d" % [_total, _fail])
	quit()
