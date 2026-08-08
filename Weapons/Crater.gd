# Weapons/Crater.gd
# M1 任务14：手雷爆炸坑（黑色圆盘贴地，30s 自动消失）
#
# 需求（brief §6）：爆炸点生成黑色圆盘（焦痕）贴地；存在 30s 后自动消失（用户拍板，
# 与弹孔同一生命周期语义）；生命周期独立于 ExplosionEffect（效果 1.5s 释放，坑保留 30s）——
# 由 ExplosionEffect._spawn_crater 同级生成（父级 = 手雷所在节点，脱手后为场景根）。
# 贴地：自爆炸点垂直向下射线（Objects 层 1）找地面，命中 → 圆盘放地面 + 半厚抬升防 z-fighting；
# 未命中（无物理环境/纯逻辑测试）→ 落爆炸点。
# 时间推进在 Timer（30s 一次性，同 BulletHole 生命周期模式）。
class_name Crater
extends Node3D

const DEFAULT_LIFETIME := 30.0  # 用户拍板：爆炸坑 30s 自动消失
const RADIUS := 0.35  # 圆盘半径（m，爆炸焦痕范围）
const THICKNESS := 0.02  # 圆盘厚度（m，扁平贴地盘）
const RAY_UP := 10.0  # 贴地射线向上延伸（m）
const RAY_DOWN := 10.0  # 贴地射线向下延伸（m）

@export var lifetime: float = DEFAULT_LIFETIME  # 生命周期（s；测试可缩短验证自动释放）


# 爆炸点初始化（须在 add_child 后调用：global_position 按父级变换正确换算）。
func init(explosion_pos: Vector3) -> void:
	# 贴地：垂直向下射线找地面（Objects 层 1——地形/掩体同层，与命中判定一致）
	var hit := _find_ground(explosion_pos)
	if hit.is_empty():
		global_position = explosion_pos
	else:
		var normal := hit["normal"] as Vector3
		global_position = (hit["position"] as Vector3) + normal * (THICKNESS * 0.5)
	_build_disc()


func _ready() -> void:
	var timer := Timer.new()
	timer.name = "LifetimeTimer"
	timer.one_shot = true
	timer.wait_time = lifetime
	timer.autostart = true  # 入树即开始 30s 倒计时（同 BulletHole 生命周期）
	timer.timeout.connect(queue_free)
	add_child(timer)


func _find_ground(pos: Vector3) -> Dictionary:
	var world := get_world_3d()
	if world == null or world.direct_space_state == null:
		return {}  # 无物理环境（纯逻辑测试）：不射线
	var query := PhysicsRayQueryParameters3D.create(
		pos + Vector3(0.0, RAY_UP, 0.0), pos + Vector3(0.0, -RAY_DOWN, 0.0), 1)
	return world.direct_space_state.intersect_ray(query)


func _build_disc() -> void:
	# 黑色焦痕圆盘：CylinderMesh 平放（圆盘面垂直于 Y = 贴地；无旋转——Cylinder 轴即 Y）
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.02, 0.02, 0.02, 0.95)  # 黑色焦痕（半透明防硬边）
	var cyl := CylinderMesh.new()
	cyl.top_radius = RADIUS
	cyl.bottom_radius = RADIUS
	cyl.height = THICKNESS
	var disc := MeshInstance3D.new()
	disc.name = "CraterDisc"
	disc.mesh = cyl
	disc.material_override = mat
	add_child(disc)
