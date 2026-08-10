# tools/probe_global.gd
# 全图网格扫描：逐点检查站立可达性 + 标记疑似卡点。
# 网格 1m 间隔覆盖全图（x∈[-29,29], z∈[-28,28]），每点：
#   ① 落地（重力+物理推进）→ 判断是否站立（底在合理高度、未被推出）
#   ② 尝试跳跃（原地起跳）→ 判断是否能跳起（不被天花板/碰撞压住）
# 输出：FAIL 点（站立失败/跳跃失败）+ 汇总。用于排查"部分位置跳跃卡顿"。
# 用法: godot --headless --path . -s res://tools/probe_global.gd
extends SceneTree

const GRAVITY_MULT := 2.0
const JUMP_VELOCITY := 7.54
const BODY_RADIUS := 0.5
const BODY_HEIGHT := 1.83

var _map: Node3D
var _player: CharacterBody3D
var _fail_count := 0
var _total := 0
var _reports := []


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
	for x in range(-29, 30):
		for z in range(-28, 29):
			_total += 1
			# ① 落地检查
			_player.global_position = Vector3(x, 3.0, z)
			_player.velocity = Vector3.ZERO
			var landed := false
			for f in 30:
				await physics_frame
				_player.velocity.y -= 9.8 * GRAVITY_MULT * d
				_player.move_and_slide()
				if _player.is_on_floor():
					landed = true
					break
			var y := _player.global_position.y
			var stand_ok: bool = landed and y > 0.8 and y < 6.0
			# ② 跳跃检查（站定后原地起跳，看能否跳起 0.3m+）
			var jump_ok := true
			if stand_ok:
				var start_y := y
				_player.velocity.y = JUMP_VELOCITY
				var peak := y
				for f in 20:
					await physics_frame
					_player.velocity.y -= 9.8 * GRAVITY_MULT * d
					_player.move_and_slide()
					peak = maxf(peak, _player.global_position.y)
				jump_ok = peak - start_y > 0.3
			if not stand_ok or not jump_ok:
				_fail_count += 1
				var reason := "落地失败" if not stand_ok else "跳跃失败"
				_reports.append("FAIL (%d,%d) %s y=%.2f" % [x, z, reason, y])
	print("PROBE_GLOBAL total=%d fail=%d" % [_total, _fail_count])
	if _fail_count > 0:
		for r in _reports:
			print(r)
	quit()
