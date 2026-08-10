# tools/probe_platform.gd
# T1a-2: 决定性实测"能跳上的平台高度"——用中心峰值判据（不依赖落地判定）：
#   平台顶 H 可达 ⇔ 跳跃中心峰值 ≥ H + CAP_HALF（胶囊半高 0.915）+ 余量 0.02
# 用法: godot --headless --path . -s res://tools/probe_platform.gd
extends SceneTree

const GRAVITY_BASE := 9.8
const GRAVITY_MULT := 2.0
const JUMP_VELOCITY := 7.54
const SPEED := 6.35
const BODY_RADIUS := 0.31
const BODY_HEIGHT := 1.83
const CAP_HALF := BODY_HEIGHT * 0.5

var _ground: StaticBody3D
var _player: CharacterBody3D
var _mode := "run"
var _phase := "wait"
var _settle := 0
var _jump_frames := 0
var _peak_y := 0.0
var _start_y := 0.0


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
		match _phase:
			"wait":
				_settle += 1
				if _settle > 15:
					_phase = "jump"
					_jump_frames = 0
					_start_y = _player.global_position.y
					_peak_y = _start_y
			"jump":
				_jump_frames += 1
				if _jump_frames == 1:
					_player.velocity.y = JUMP_VELOCITY
					_player.velocity.x = SPEED if _mode == "run" else 0.0
				_player.velocity.y -= GRAVITY_BASE * GRAVITY_MULT * d
				_player.move_and_slide()
				_peak_y = maxf(_peak_y, _player.global_position.y)
				if _player.is_on_floor() and _jump_frames > 20:
					# 中心峰值 → 可达高度
					var center_clear: float = _peak_y - _start_y
					var reachable_top: float = center_clear - CAP_HALF
					print("PROBE %s center_clear=%.3f -> reachable_platform_top=%.3f" % [_mode, center_clear, reachable_top])
					if _mode == "run":
						_mode = "stand"
						_phase = "wait"
						_settle = 0
						_player.velocity = Vector3.ZERO
						_player.global_position = Vector3(0, 1.0, 0)
					else:
						print("PROBE PLATFORM_DONE")
						quit()
						return
		if _jump_frames > 300:
			print("PROBE TIMEOUT")
			quit()
			return
