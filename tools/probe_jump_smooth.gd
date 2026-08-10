# tools/probe_jump_smooth.gd
# 跳跃流畅度探针：在关键点位测"跳跃到落地"的物理行为——
#   检测跳跃是否被异常减速/卡住（上升高度、空中速度变化、落地延迟）。
# 关键点位：高台旁（WestHigh1）、箱堆旁（WestBox1）、矮墙旁（NMidWall1）、大厅内柱旁。
# 用法: godot --headless --path . -s res://tools/probe_jump_smooth.gd
extends SceneTree

const GRAVITY_MULT := 2.0
const JUMP_VELOCITY := 7.54
const SPEED := 6.35
const BODY_RADIUS := 0.5
const BODY_HEIGHT := 1.83

var _map: Node3D
var _player: CharacterBody3D

# [点位名, 位置, 跳跃方向] — 在组件边缘起跳，测是否被卡
const SPOTS := [
	["WestHigh1旁", Vector3(-13.0, 1.0, -4.5), Vector3(0, 0, 1)],
	["WestBox1旁", Vector3(-14.0, 1.0, -5.5), Vector3(1, 0, 0)],
	["NMidWall1旁", Vector3(-8.0, 1.0, 17.5), Vector3(1, 0, 0)],
	["大厅柱旁", Vector3(-6.0, 1.0, -4.5), Vector3(1, 0, 0)],
	["东街高台旁", Vector3(14.0, 1.0, -4.5), Vector3(0, 0, 1)],
]


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


func _run() -> void:
	var d := 1.0 / Engine.physics_ticks_per_second
	for spot in SPOTS:
		var name: String = spot[0]
		var pos: Vector3 = spot[1]
		var dir: Vector3 = spot[2]
		# 出生到点位（物理落地稳定）
		_player.global_position = pos
		_player.velocity = Vector3.ZERO
		for f in 20:
			await physics_frame
			_player.velocity.y -= 9.8 * GRAVITY_MULT * d
			_player.move_and_slide()
		# 跳跃（沿 dir 水平移动 + 起跳）
		var start_y := _player.global_position.y
		_player.velocity.y = JUMP_VELOCITY
		_player.velocity.x = dir.x * SPEED
		_player.velocity.z = dir.z * SPEED
		var peak := start_y
		var min_dy := 0.0
		var frames_air := 0
		var stuck_frames := 0
		var last_vel := _player.velocity
		for f in 60:
			await physics_frame
			_player.velocity.y -= 9.8 * GRAVITY_MULT * d
			_player.move_and_slide()
			peak = maxf(peak, _player.global_position.y)
			# 检测"卡住"：连续多帧几乎不动（速度被碰撞吃掉）
			var speed := _player.velocity.length()
			if speed < 0.3:
				stuck_frames += 1
			else:
				stuck_frames = 0
			if _player.is_on_floor() and f > 5:
				frames_air = f
				break
		var jump_clear := peak - start_y
		var status := "OK"
		if stuck_frames > 10:
			status = "⚠️ 卡住(连续%d帧速度<0.3)" % stuck_frames
		elif jump_clear < 0.5:
			status = "⚠️ 跳不高(%.2fm)" % jump_clear
		print("JUMP %s: 起跳高度=%.2fm 滞空=%d帧 状态=%s" % [name, jump_clear, frames_air, status])
	print("PROBE_JUMP_SMOOTH_DONE")
	quit()
