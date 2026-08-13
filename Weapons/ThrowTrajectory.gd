# Weapons/ThrowTrajectory.gd
# M1 任务8：投掷抛物线预览（长按持雷实时显示）
# M2 增强（2026-08-10）：更醒目——更长弹道 + 加粗亮绿虚线 + 蓄力落点标记（圆环）。
#
# 需求（spec §9.1）：每物理帧沿投掷方向积分重力抛体弹道（v0 = throw_strength），
#   生成 200 点虚线预览，落点 = 首次穿越地面插值点；THROWING 显示、取消/投出隐藏（WeaponManager 控制 visible）。
# 积分：半隐式欧拉，重力与 Grenade（RigidBody3D）同源 ProjectSettings default_gravity——
#   预览与真实投掷落点一致（测试以同公式解析式派生期望，不硬编码散值）。
# 渲染：ImmediateMesh 虚线（PRIMITIVE_LINES 每段画前 70% 留空），top_level 世界空间（点在全局坐标系）；
#   落点 = 首次穿越地面 y=0 的线性插值点 + 竖直落点线（可见点列末端 → 落点环，绿色描边更醒目）。
class_name ThrowTrajectory
extends Node3D

const POINT_COUNT := 200  # 预览点列上限（M2 手感修复：50→200；STEP 1/60 → 3.33s 覆盖垂直上抛 3.06s 全弧）
const STEP_SECONDS := 1.0 / 60.0  # 积分步长 = 物理帧长（与 RigidBody3D 积分同构 → 预览≈实际轨迹）
const DASH_RATIO := 0.7  # 虚线：每段画前 70%，留 30% 空隙（更连续醒目）

var points: PackedVector3Array = PackedVector3Array()  # 点列（全局坐标，供测试/渲染）
var landing_point: Vector3 = Vector3.ZERO  # 落点（弹道末点投影到地面 y=0）

var _mesh_instance: MeshInstance3D
var _immediate_mesh: ImmediateMesh
var _line_material: StandardMaterial3D
var _landing_mesh: MeshInstance3D
var _landing_ring: ImmediateMesh
var _landing_material: StandardMaterial3D


func _ready() -> void:
	_immediate_mesh = ImmediateMesh.new()
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.mesh = _immediate_mesh
	_mesh_instance.top_level = true  # 世界空间渲染：点列是全局坐标（跟随相机，不受玩家变换影响）
	add_child(_mesh_instance)
	# 落点圆环（地面标记）
	_landing_ring = ImmediateMesh.new()
	_landing_mesh = MeshInstance3D.new()
	_landing_mesh.mesh = _landing_ring
	_landing_mesh.top_level = true
	add_child(_landing_mesh)


# 沿 origin（投掷原点=右手雷处）/direction（向视角目标点）以 strength 初速积分弹道并刷新渲染。
# M2 手感修复（2026-08-13）：落地判定 = 首次穿越 y≤0 线性插值求精确落点；可见点列截至触地点
# （不再画入地下）；旧"末点投影 y=0"作废（长弧时末点浮空错标）。全程不落地兜底 = 末点投影。
func update_trajectory(origin: Vector3, direction: Vector3, strength: float) -> void:
	var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
	var velocity := direction.normalized() * strength
	var position := origin
	points.clear()
	var landed := false
	for i in POINT_COUNT:
		points.append(position)
		velocity.y -= gravity * STEP_SECONDS
		var next := position + velocity * STEP_SECONDS
		if next.y <= 0.0:
			var t := position.y / (position.y - next.y)  # 两已知点线性插值：y=0 处
			landing_point = position.lerp(next, clampf(t, 0.0, 1.0))
			landed = true
			break
		position = next
	if not landed:
		landing_point = position  # 兜底：全程不落地（极端）→ 末点投影（旧行为）
		landing_point.y = 0.0
	_render()


func _render() -> void:
	if _immediate_mesh == null:
		return  # _ready 未执行（未入树）：仅保留点列数据
	_immediate_mesh.clear_surfaces()
	if points.size() < 2:
		return
	_immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES, _get_material())
	for i in points.size() - 1:
		var a := points[i]
		_immediate_mesh.surface_add_vertex(a)
		_immediate_mesh.surface_add_vertex(a + (points[i + 1] - a) * DASH_RATIO)
	_immediate_mesh.surface_end()
	_render_landing()


func _render_landing() -> void:
	if _landing_ring == null or points.is_empty():
		return
	_landing_ring.clear_surfaces()
	# 地面落点圆环（半径 0.3m，16 段），绿色描边——蓄力时标记落点
	var center := landing_point
	var segs := 16
	var radius := 0.3
	_landing_ring.surface_begin(Mesh.PRIMITIVE_LINES, _get_landing_material())
	for i in segs:
		var a0 := float(i) / segs * TAU
		var a1 := float(i + 1) / segs * TAU
		var p0 := center + Vector3(cos(a0) * radius, 0.02, sin(a0) * radius)
		var p1 := center + Vector3(cos(a1) * radius, 0.02, sin(a1) * radius)
		_landing_ring.surface_add_vertex(p0)
		_landing_ring.surface_add_vertex(p1)
	# 竖直落点线：可见点列末端 → 落点环（M2 手感修复：落点清晰明了——弧线止于空中点，垂直线指向落点）
	var top := points[points.size() - 1]
	_landing_ring.surface_add_vertex(top)
	_landing_ring.surface_add_vertex(center)
	_landing_ring.surface_end()


func _get_material() -> StandardMaterial3D:
	if _line_material == null:
		_line_material = StandardMaterial3D.new()
		_line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_line_material.albedo_color = Color(0.2, 1.0, 0.3)  # 更醒目的亮绿
	return _line_material


func _get_landing_material() -> StandardMaterial3D:
	if _landing_material == null:
		_landing_material = StandardMaterial3D.new()
		_landing_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_landing_material.albedo_color = Color(0.2, 1.0, 0.3)  # 与弹道同绿
	return _landing_material
