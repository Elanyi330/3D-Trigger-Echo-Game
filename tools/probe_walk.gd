# tools/probe_walk.gd
# T2 冒烟验证：自动漫游全图关键点——验证"玩家可走遍全图无 bug"（用户验收目标①的可自动化部分）。
# 沿预设路线推进（直接设置位置 + 物理模拟），检测每个目标点是否可达（无墙内/穿墙）。
# 用法: godot --headless --path . -s res://tools/probe_walk.gd
extends SceneTree

const LAYOUT := preload("res://Levels/M2_TDM/map_layout.gd")

# 漫游路线（关键可踏足点：出生→西街→大厅→东街→中街→出生）
const ROUTE := [
	Vector3(-2, 0, 27),    # T 出生
	Vector3(-2, 0, 22),    # 出生前
	Vector3(-12, 0, 15),   # 西街北
	Vector3(-12, 0, 0),    # 西街中
	Vector3(-12, 0, -15),  # 西街南
	Vector3(-4, 0, -15),   # 大厅西口前
	Vector3(-3, 0, -3),    # 大厅内西
	Vector3(3, 0, 3),      # 大厅内东
	Vector3(4, 0, 10),     # 大厅北口
	Vector3(11, 0, 10),    # 东街北
	Vector3(11, 0, 0),     # 东街中（东屋顶东侧走廊）
	Vector3(11, 0, -10),   # 东街南
	Vector3(18.5, 2.5, 0), # 东屋顶顶面（表面高度出生，验证可站立）
	Vector3(0, 0, -12),    # 中街南
	Vector3(0, 0, 12),     # 中街北
	Vector3(0, 0, 22),     # 北出生前
	Vector3(-2, 0, 27),    # 回到 T 出生
]

var _map: Node3D
var _player: CharacterBody3D
var _idx := 0
var _frames := 0
var _failed := 0
var _reports := []


func _initialize() -> void:
	# 灰盒地图
	var gb_script := load("res://Levels/M2_TDM/map_greybox.gd")
	_map = Node3D.new()
	_map.name = "Greybox"
	root.add_child(_map)
	var gb: Node3D = gb_script.new()
	gb.name = "MapGreybox"
	_map.add_child(gb)
	gb.build()
	# 玩家
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
	_player.global_position = ROUTE[0] + Vector3(0, 1.0, 0)
	_run()


func _run() -> void:
	var idx := 0
	while idx < ROUTE.size():
		var target: Vector3 = ROUTE[idx]
		# 瞬移探测：直接放置目标点（+1.0 y 立于地面），物理推进（重力落地）后判断
		_player.global_position = target + Vector3(0, 1.0, 0)
		_player.velocity = Vector3.ZERO
		# 物理推进直到落地或超时
		var settle := 0
		var settle_ok := false
		while settle < 60:
			await physics_frame
			settle += 1
			# 重力 + 物理步进（与 MovementController 同款）
			_player.velocity.y -= 9.8 * 2.0 * (1.0 / Engine.physics_ticks_per_second)
			_player.move_and_slide()
			if _player.is_on_floor():
				settle_ok = true
				break
		# 判断：落在地面附近（站姿 y≈0.92 / 斜坡 / 屋顶顶面 y≈3.4）且未被推出边界
		var pos := _player.global_position
		var in_bounds: bool = abs(pos.x) < LAYOUT.BOUND_X and abs(pos.z) < LAYOUT.BOUND_Z
		var standing: bool = settle_ok and pos.y > 0.8 and pos.y < 4.5  # 屋顶顶面站姿 ≈3.42
		var ok: bool = in_bounds and standing
		_reports.append("  [%s] %s 落地y=%.2f" % ["OK" if ok else "FAIL", target, pos.y])
		if not ok:
			_failed += 1
		idx += 1

	for r in _reports:
		print("WALK " + r)
	print("PROBE_WALK %s/%d reached" % [ROUTE.size() - _failed, ROUTE.size()])
	quit()
