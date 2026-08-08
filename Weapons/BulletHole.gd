# Weapons/BulletHole.gd
# M1 任务8：弹孔（命中点 decal，30s 生命周期）
#
# 需求（spec §9.2）：位置 = 实际射线命中点（弹道已含全部稳定性因素，弹孔天然符合武器设定）；
#   decal 贴合命中表面（局部 -Z 沿 hit_normal，Decal 沿 -Z 投影）；存在 30s 后自动消失
#   （Timer 一次性，用户拍板）；数量上限（200）由 WeaponManager 维护淘汰最旧。
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
	# Decal 沿 -Z 投影：-Z 必须指向墙内（命中点方向）才投得上。
	# 先沿法线外移 2cm（防嵌入/深度冲突），再 look_at 命中点 → -Z 朝向表面。
	global_position = position + dir * 0.02
	var up := Vector3.UP
	if absf(dir.dot(Vector3.UP)) > 0.99:
		up = Vector3.FORWARD
	look_at(position, up)
	var decal := Decal.new()
	decal.name = "Decal"
	decal.size = Vector3(0.2, 0.2, 0.12)
	decal.modulate = Color(0.05, 0.05, 0.05, 1.0)
	# M1 任务14 可见性修复：Decal 无贴图不可见——程序化生成圆形黑色焦痕贴图（运行时，无外部资产）
	decal.texture_albedo = _make_bullet_hole_texture()
	add_child(decal)


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
