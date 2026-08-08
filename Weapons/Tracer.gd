# Weapons/Tracer.gd
# M1 任务15：曳光弹（CC0 bullet_tracer 照搬理念）——枪口→命中点短暂线条
#
# 行为（brief 交付内容 4）：射击时生成枪口→命中点线条（0.1s 淡出自清）；
#   未命中则到 max_range 端点（WeaponCore 已算好端点，本类只画线段）。
# 几何：十字双面长条 QuadMesh（宽 WIDTH、长 = 线段距离，沿局部 +Y 伸展），
#   两平面绕长度轴互转 90°——任何视角至少一面可见（单面正对线段方向几乎不可见）。
# 淡出：透明度随时间线性下降（0.1s 后 queue_free 自清，无场景管理方）。
# 参考：docs/superpowers/reference/fps-animation-reference.md §2.5/§3.1（CC0 bullet_tracer）
class_name Tracer
extends Node3D

const LIFETIME := 0.1  # 存在时长（s，CC0）
const WIDTH := 0.004  # 线条宽度（m，细线不遮挡视野）
const ALPHA_START := 0.9  # 起始透明度

var _elapsed: float = 0.0
var _length: float = 0.0
var _material: StandardMaterial3D


# 枪口→命中点线段初始化（from/to 世界坐标；须 add_child 后调用——global 变换按父级正确换算）。
func init(from: Vector3, to: Vector3) -> void:
	_length = from.distance_to(to)
	if _length < 0.001:
		queue_free()  # 无效线段（from == to）：直接自清
		return
	global_position = (from + to) * 0.5
	var dir := (to - from) / _length
	# 局部 +Y = 线段方向：quad 沿 Y 伸展跨全长（QuadMesh 平面 X-Y，中点 = 线段中点）
	var x_axis := Vector3.UP.cross(dir)
	if x_axis.length_squared() < 0.0001:
		x_axis = Vector3.FORWARD.cross(dir)  # 线段平行 UP（垂直射击）：退化回退
	x_axis = x_axis.normalized()
	global_transform.basis = Basis(x_axis, dir, x_axis.cross(dir))
	_material = StandardMaterial3D.new()
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.albedo_color = Color(1.0, 0.85, 0.4, ALPHA_START)
	_add_quad(false)
	_add_quad(true)


func _add_quad(twisted: bool) -> void:
	var mesh := QuadMesh.new()
	mesh.size = Vector2(WIDTH, _length)
	var quad := MeshInstance3D.new()
	quad.mesh = mesh
	quad.material_override = _material
	if twisted:
		quad.rotation.y = PI * 0.5  # 绕长度轴（局部 Y）转 90°：十字双面
	add_child(quad)


func _physics_process(delta: float) -> void:
	# 0.1s 线性淡出（物理帧驱动：headless 测试可靠）；退化线段（init 已 queue_free）无材质 → 跳过
	if _material == null:
		return
	_elapsed += delta
	var t := clampf(_elapsed / LIFETIME, 0.0, 1.0)
	var c := _material.albedo_color
	c.a = ALPHA_START * (1.0 - t)
	_material.albedo_color = c
	if t >= 1.0:
		queue_free()  # 淡出完成：自清（无管理方计数）
