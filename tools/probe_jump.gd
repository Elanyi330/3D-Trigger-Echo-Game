# tools/probe_jump.gd
# T1a: 实测跳跃能力（MovementController 物理参数）——站立跳高 / 助跑跳远。
# 用法: godot --headless --path . -s res://tools/probe_jump.gd
# 输出: PROBE stand_jump_clear=... run_jump_clear=...（脚本解析用）
extends SceneTree

const GRAVITY_BASE := 9.8
const GRAVITY_MULT := 2.0
const JUMP_VELOCITY := 7.54   # MovementController.jump_height 初速度 m/s
const SPEED := 6.35           # MovementController.speed 站走速
const BODY_RADIUS := 0.31
const BODY_HEIGHT := 1.83

var _ground: StaticBody3D
var _player: CharacterBody3D
var _frames := 0
var _start_y := 0.0
var _start_x := 0.0
var _max_y := 0.0
var _max_x := 0.0
var _phase := "stand"
var _jumped := false


func _initialize() -> void:
	_ground = StaticBody3D.new()
	_ground.collision_layer = 1
	_ground.collision_mask = 0
	var gs := CollisionShape3D.new()
	gs.shape = BoxShape3D.new()
	(gs.shape as BoxShape3D).size = Vector3(200, 1, 200)
	_ground.add_child(gs)
	root.add_child(_ground)

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
	_player.global_position = Vector3(0, 1.0, 0)
	_run()


func _run() -> void:
	while true:
		await physics_frame
		var d := 1.0 / Engine.physics_ticks_per_second
		_frames += 1
		if _frames == 20 and not _jumped:
			_jumped = true
			_start_y = _player.global_position.y
			_start_x = _player.global_position.x
			_player.velocity.y = JUMP_VELOCITY
			_player.velocity.x = SPEED if _phase == "run" else 0.0
		_player.velocity.y -= GRAVITY_BASE * GRAVITY_MULT * d
		_player.move_and_slide()
		if _phase == "stand":
			if _jumped and _player.velocity.y > 0.0:
				_max_y = maxf(_max_y, _player.global_position.y)
		elif _phase == "run":
			if _player.velocity.y > 0.0 or _player.global_position.y > _start_y - 0.05:
				_max_x = maxf(_max_x, _player.global_position.x - _start_x)
		if _jumped and _player.velocity.y <= 0.0 and _player.global_position.y <= _start_y + 0.05 and _player.is_on_floor():
			if _phase == "stand":
				print("PROBE stand_jump_clear=%.3f" % (_max_y - _start_y))
				_phase = "run"
				_jumped = false
				_frames = 0
				_start_y = _player.global_position.y
				_start_x = _player.global_position.x
				_max_x = 0.0
			elif _phase == "run":
				print("PROBE run_jump_clear=%.3f" % _max_x)
				print("PROBE JUMP_DONE")
				quit()
				return
		if _frames > 900:
			print("PROBE TIMEOUT phase=" + _phase)
			quit()
			return
