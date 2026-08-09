# Weapons/BulletHole.gd
# M1 任务8：弹孔（命中点 quad 面片，30s 生命周期）
#
# 需求（spec §9.2）：位置 = 实际射线命中点（弹道已含全部稳定性因素，弹孔天然符合武器设定）；
#   面片贴合命中表面（局部 +Z 沿 hit_normal 朝外）；存在 30s 后自动消失（Timer 一次性，用户拍板）；
#   M1.5 起取消场景数量上限（用户拍板）——由 30s 生命周期自然约束累积。
#   渲染用 quad 面片而非 Decal 节点：Forward Mobile 渲染器对每簇 clustered decal 有数量上限会丢弃
#   超出弹孔（实测 30 发仅渲染 ~8 个），quad 网格无此限制、全部渲染。
# 参考：docs/superpowers/reference/m1-src/bullet_hole_dragon20c.gd（Node3D + 生命周期释放理念）
class_name BulletHole
extends Node3D

signal expired  # 生命周期结束（WeaponManager 据此从计数中移除）

const DEFAULT_LIFETIME := 30.0  # 用户拍板：30s 自动消失
const TEXTURE_SIZE := 64  # 程序化弹孔贴图分辨率（px，方形）
const TEXTURE_RADIUS_RATIO := 0.45  # 弹孔圆形半径（贴图边长比例）


# 命中点 + 表面法线初始化（须在 add_child 后调用：global_position 按父级变换正确换算）。
# M1 任务15：parent 非空时挂到被击中 collider 下（GarbajYT decals——随物体动，
#   比挂世界根更稳；敌人移动/倒地弹孔跟着走）。
func init(position: Vector3, normal: Vector3, parent: Node3D = null) -> void:
	if parent != null and parent != get_parent():
		reparent(parent)  # 保持 global 变换迁移到 collider 下
	var dir := normal.normalized()
	# 沿法线外移 2cm（防嵌入/深度冲突），look_at 命中点 → 局部 -Z 朝墙内、+Z（quad 正面）朝外。
	global_position = position + dir * 0.02
	var up := Vector3.UP
	if absf(dir.dot(Vector3.UP)) > 0.99:
		up = Vector3.FORWARD
	look_at(position, up)
	# M1.5 修复"连射后面的子弹没弹孔"：改用**自发光遮光 quad 面片**而非 Decal 节点——
	# 本工程为 Forward Mobile 渲染器，对**每簇 clustered decal 有数量上限**，超出部分被丢弃
	# （30 发实测仅 ~8 个渲染）；quad 网格无此限制，全部渲染。+Z 正面朝外（= +normal）。
	var quad := MeshInstance3D.new()
	quad.name = "HoleQuad"
	var q := QuadMesh.new()
	q.size = Vector2(0.11, 0.11)  # 弹孔直径 ~11cm（CS 弹孔尺寸感）
	quad.mesh = q
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = _make_bullet_hole_texture()  # 程序化圆形焦痕（含 alpha）
	m.roughness = 0.9
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	quad.material_override = m
	add_child(quad)


func _make_bullet_hole_texture() -> ImageTexture:
	# 程序化圆形黑色焦痕：透明底 + 黑色圆（边缘柔和过渡，防硬边锯齿）
	var img := Image.create(TEXTURE_SIZE, TEXTURE_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.0, 0.0, 0.0, 0.0))
	var center := Vector2(TEXTURE_SIZE * 0.5, TEXTURE_SIZE * 0.5)
	var radius := TEXTURE_SIZE * TEXTURE_RADIUS_RATIO
	for y in TEXTURE_SIZE:
		for x in TEXTURE_SIZE:
			var dist := Vector2(x, y).distance_to(center)
			if dist <= radius:
				# 边缘 30% 半径内柔和过渡（alpha 0.25→0.95），中心深黑
				var edge := clampf((radius - dist) / (radius * 0.3), 0.0, 1.0)
				var alpha := 0.25 + 0.7 * edge
				img.set_pixel(x, y, Color(0.04, 0.04, 0.04, alpha))
	return ImageTexture.create_from_image(img)


func _ready() -> void:
	var timer := Timer.new()
	timer.name = "LifetimeTimer"
	timer.one_shot = true
	timer.wait_time = DEFAULT_LIFETIME
	timer.autostart = true  # 入树即开始 30s 倒计时
	timer.timeout.connect(_on_lifetime_timeout)
	add_child(timer)


func _on_lifetime_timeout() -> void:
	expired.emit()
	queue_free()
