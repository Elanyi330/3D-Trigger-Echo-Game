# Weapons/ThrowTrajectory.gd
# M1 任务8：投掷抛物线预览（长按持雷实时显示）
#
# 需求（spec §9.1）：每物理帧沿投掷方向积分重力抛体弹道（v0 = throw_strength），
#   生成 30 点虚线预览，终点 = 弹道末点；THROWING 显示、取消/投出隐藏（WeaponManager 控制 visible）。
# 积分：半隐式欧拉，重力与 Grenade（RigidBody3D）同源 ProjectSettings default_gravity——
#   预览与真实投掷落点一致（测试以同公式解析式派生期望，不硬编码散值）。
# 渲染：ImmediateMesh 虚线（PRIMITIVE_LINES 每段画前 60% 留空），top_level 世界空间（点在全局坐标系）。
class_name ThrowTrajectory
extends Node3D

const POINT_COUNT := 30  # 预览点列长度（brief §9.1：30 点）
const STEP_SECONDS := 0.02  # 积分步长（s）：30 点 → 0.58s 弹道弧
const DASH_RATIO := 0.6  # 虚线：每段画前 60%，留 40% 空隙

var points: PackedVector3Array = PackedVector3Array()  # 点列（全局坐标，供测试/渲染）

var _mesh_instance: MeshInstance3D
var _immediate_mesh: ImmediateMesh
var _line_material: StandardMaterial3D


func _ready() -> void:
	_immediate_mesh = ImmediateMesh.new()
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.mesh = _immediate_mesh
	_mesh_instance.top_level = true  # 世界空间渲染：点列是全局坐标（跟随相机，不受玩家变换影响）
	add_child(_mesh_instance)


# 沿 origin（相机位置）/direction（相机视向）以 strength 初速积分弹道并刷新渲染。
func update_trajectory(origin: Vector3, direction: Vector3, strength: float) -> void:
	var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
	var velocity := direction.normalized() * strength
	var position := origin
	points.resize(POINT_COUNT)
	for i in POINT_COUNT:
		points[i] = position
		velocity.y -= gravity * STEP_SECONDS
		position += velocity * STEP_SECONDS
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


func _get_material() -> StandardMaterial3D:
	if _line_material == null:
		_line_material = StandardMaterial3D.new()
		_line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_line_material.albedo_color = Color(0.4, 1.0, 0.4)
	return _line_material
