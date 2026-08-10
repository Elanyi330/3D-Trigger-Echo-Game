# tools/probe_step_climb.gd
# 验证东区台阶→屋顶可走通（用户问题：黄灰组件间无法通过）。
# 玩家从东街 (x=11) 沿 +X 走，遇台阶起跳，检测能否到达屋顶顶面 (x=28, 顶面 2.5m)。
# 用法: godot --headless --path . -s res://tools/probe_step_climb.gd
extends SceneTree

const GRAVITY_MULT := 2.0
const JUMP_VELOCITY := 7.54
const SPEED := 6.35

var _map: Node3D
var _player: CharacterBody3D
var _max_x := 0.0
var _peak_y := 0.0
var _frames := 0


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
	cap.radius = 0.5
	cap.height = 1.83
	cs.shape = cap
	_player.add_child(cs)
	root.add_child(_player)
	_player.global_position = Vector3(11, 1.0, 0)  # 东街中
	_run()


func _run() -> void:
	var d := 1.0 / Engine.physics_ticks_per_second
	while true:
		await physics_frame
		_frames += 1
		# 朝 +X 走，贴墙或每 20 帧尝试跳（模拟玩家遇台阶起跳）
		_player.velocity.x = SPEED
		_player.velocity.y -= 9.8 * GRAVITY_MULT * d
		if _player.is_on_floor():
			if _player.is_on_wall() or _frames % 20 == 0:
				_player.velocity.y = JUMP_VELOCITY
		_player.move_and_slide()
		_max_x = maxf(_max_x, _player.global_position.x)
		_peak_y = maxf(_peak_y, _player.global_position.y)
		# 到达屋顶顶面（x>21.5, y>2.4）或超时
		if _player.global_position.x > 24.0 and _player.global_position.y > 2.4:
			print("PROBE_STEP_CLIMB OK: 到达屋顶 x=%.1f y=%.2f" % [_player.global_position.x, _player.global_position.y])
			quit()
			return
		if _frames > 900:
			print("PROBE_STEP_CLIMB FAIL: 卡在 x=%.1f y=%.2f（max_x=%.1f peak_y=%.2f）" % [_player.global_position.x, _player.global_position.y, _max_x, _peak_y])
			quit()
			return
