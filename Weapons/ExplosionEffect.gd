# Weapons/ExplosionEffect.gd
# M1 任务11：手雷爆炸视觉效果（spec §9.8，结构参考 Mucurata explosion.gd，MIT）
#
# 组成（位置 = Grenade 爆炸点，由 Grenade._spawn_explosion_effect 生成）：
#   - GPUParticles3D 火花粒子（one_shot 一次性喷发 + 粒子寿命 0.5s = 短时喷射 0.5s）
#   - OmniLight3D 闪光（light_energy 8.0 → 0 线性衰减，与生命周期同步）
#   - 冲击波环（TorusMesh 扩散圆环，0.3s 内放大 ×(1+RING_GROWTH) + alpha 淡出）
# 生命周期 1.5s 后 queue_free；数值全部参数化 const（禁止散值）。
# 时间推进在 _physics_process（60Hz 确定性——GUT headless 的 _process 帧率不稳定，
# 与 Grenade 引信/BulletHole 生命周期同样的物理帧语义）。
class_name ExplosionEffect
extends Node3D

const LIFETIME := 1.5  # 爆炸生命周期（s，spec §9.8）
const LIGHT_ENERGY := 8.0  # 闪光起始能量（线性衰减到 0）
const SPARK_LIFETIME := 0.5  # 火花粒子寿命（s，短时喷射）
const RING_EXPAND_TIME := 0.3  # 冲击波环放大+淡出时长（s）
const RING_GROWTH := 3.0  # 环放大倍率（scale 1 → 1+RING_GROWTH）
const RING_RADIUS := 0.6  # 环初始半径（m）
const RING_TUBE := 0.04  # 环管粗细（m，外半径-内半径）

var _time := 0.0
var _light: OmniLight3D
var _ring: MeshInstance3D
var _ring_material: StandardMaterial3D
var _crater_spawned := false  # 爆炸坑生成闸（首物理帧：_ready 早于爆炸点位置赋值）


func _ready() -> void:
	_build_sparks()
	_build_flash_light()
	_build_shockwave()


func _physics_process(delta: float) -> void:
	# 爆炸坑首帧生成：_ready 时本节点位置尚未赋值（调用方先 add_child 再设 global_position）——
	# 若在 _ready 生成则坑会落在父级原点而非爆炸点。
	if not _crater_spawned:
		_crater_spawned = true
		_spawn_crater()
	_time += delta
	if _light != null:
		_light.light_energy = maxf(0.0, LIGHT_ENERGY * (1.0 - _time / LIFETIME))
	if _ring != null and _time <= RING_EXPAND_TIME:
		var t := _time / RING_EXPAND_TIME
		_ring.scale = Vector3.ONE * (1.0 + t * RING_GROWTH)
		_ring_material.albedo_color.a = 1.0 - t
	if _time >= LIFETIME:
		queue_free()


# ---- 组成构建 ----

func _build_sparks() -> void:
	# 火花粒子：球形一次性喷发，全方向飞溅，颜色由亮黄→橙→暗红（火焰渐变）
	var particles := GPUParticles3D.new()
	particles.name = "Sparks"
	particles.amount = 48
	particles.lifetime = SPARK_LIFETIME
	particles.one_shot = true
	particles.explosiveness = 1.0  # 爆炸瞬间全部粒子一次性喷出
	particles.emitting = true
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 0.05
	mat.direction = Vector3.ZERO  # 无方向偏好
	mat.spread = 180.0  # 全方向球形喷发（度）
	mat.initial_velocity_min = 2.0
	mat.initial_velocity_max = 6.0
	mat.gravity = Vector3(0.0, -6.0, 0.0)  # 火花受重力回落
	mat.scale_min = 0.02
	mat.scale_max = 0.05
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.6, 1.0])
	ramp.colors = PackedColorArray([
		Color(1.0, 0.95, 0.6),   # 亮黄白（初始）
		Color(1.0, 0.45, 0.1),   # 橙（中段）
		Color(0.25, 0.06, 0.02), # 暗红黑（熄灭）
	])
	var ramp_tex := GradientTexture1D.new()
	ramp_tex.gradient = ramp
	mat.color_ramp = ramp_tex
	particles.process_material = mat
	add_child(particles)


func _build_flash_light() -> void:
	# 闪光：暖色点光源，能量由 _physics_process 随生命周期线性衰减
	var light := OmniLight3D.new()
	light.name = "FlashLight"
	light.light_energy = LIGHT_ENERGY
	light.omni_range = 12.0
	light.light_color = Color(1.0, 0.72, 0.3)
	add_child(light)
	_light = light


func _build_shockwave() -> void:
	# 冲击波环：TorusMesh 平放（Godot 圆环默认轴 = Y，位于 XZ 平面）扩散
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.95, 0.8, 0.5, 1.0)
	var torus := TorusMesh.new()
	torus.inner_radius = RING_RADIUS
	torus.outer_radius = RING_RADIUS + RING_TUBE
	var ring := MeshInstance3D.new()
	ring.name = "Shockwave"
	ring.mesh = torus
	ring.material_override = mat
	add_child(ring)
	_ring = ring
	_ring_material = mat


# M1 任务14：爆炸坑（黑色圆盘贴地，30s 自动消失）。生成在同级父节点而非自身子节点：
# 本效果 1.5s 后释放，坑须保留 30s（独立生命周期）；位置 = 爆炸点（先 add_child 再 init——
# 按父级变换正确换算，同 BulletHole/Grenade 约定）。
func _spawn_crater() -> void:
	var parent := get_parent()
	if parent == null:
		return  # 未入树（纯逻辑环境）：不生成视觉
	var crater := Crater.new()
	crater.name = "Crater"
	parent.add_child(crater)
	crater.init(global_position)
