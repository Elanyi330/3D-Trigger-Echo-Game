# test/unit/test_bullet_hole.gd
# M1 任务8：BulletHole 弹孔测试（TDD RED 先行）
# 行为（brief §9.2）：命中点生成弹孔面片（M1.5：quad 替代 Decal）、贴合表面法线（局部 -Z 朝外）、
#   30s 自动消失（Timer 一次性）、超时发 expired 信号供管理方计数清理。
# 全局约束：30s 生命周期不真实等待——查 Timer 配置 + 缩短重启验证实际消失；
#   Vector3 断言按分量比较（GUT assert_almost_eq 不支持 Vector3 操作数）。
extends GutTest


func _spawn_hole(position: Vector3, normal: Vector3) -> BulletHole:
	var hole := BulletHole.new()
	add_child_autofree(hole)
	hole.init(position, normal)
	return hole


# ================= 1. 命中点与表面贴合 =================
func test_init_position_and_surface_alignment() -> void:
	var hole := _spawn_hole(Vector3(0, 1, -8), Vector3(0, 0, 1))
	# M1.5 修复：弹孔沿法线外移 0.02（防嵌入/深度冲突），-Z 朝墙内、+Z(quad 正面)朝外
	assert_almost_eq(hole.global_position.x, 0.0, 0.001, "位置 x = 命中点")
	assert_almost_eq(hole.global_position.y, 1.0, 0.001, "位置 y = 命中点")
	assert_almost_eq(hole.global_position.z, -7.98, 0.001, "位置 z = 命中点沿法线外移 0.02")
	var z := hole.global_transform.basis.z
	assert_almost_eq(z.x, 0.0, 0.001, "贴合 basis.z x 分量")
	assert_almost_eq(z.y, 0.0, 0.001, "贴合 basis.z y 分量")
	assert_almost_eq(z.z, 1.0, 0.001, "basis.z 朝外（= 投影 -Z 朝墙内，decal 贴合墙面）")
	var quad := hole.get_node_or_null("HoleQuad") as MeshInstance3D
	assert_not_null(quad, "生成 HoleQuad 弹孔面片（M1.5：quad 替代 Decal——Mobile 渲染器 decal 簇上限会丢弃超出弹孔）")
	if quad != null:
		var mat := quad.material_override as StandardMaterial3D
		assert_not_null(mat, "弹孔面片有材质")
		if mat != null:
			assert_not_null(mat.albedo_texture, "M1 任务14：弹孔有贴图（无贴图不可见——可见性修复）")
			if mat.albedo_texture != null:
				assert_eq(mat.albedo_texture.get_width(), 64, "程序化圆形焦痕贴图 64×64")


func test_normal_parallel_to_up_fallback_no_error() -> void:
	# 地面/天花板（法线 = ±UP）：look_at 的 up 向量退化为平行 → 回退 up 防退化
	var hole := _spawn_hole(Vector3(0, 1, 0), Vector3.UP)
	var z := hole.global_transform.basis.z
	assert_almost_eq(z.x, 0.0, 0.001, "贴地面 basis.z x 分量")
	assert_almost_eq(z.y, 1.0, 0.001, "贴地面：basis.z 朝上（= 投影 -Z 朝下入地面）")
	assert_almost_eq(z.z, 0.0, 0.001, "贴地面 basis.z z 分量")


# ================= 1.5 M1 任务15：挂被击中 collider 下（随物体动，GarbajYT decals） =================
func test_attaches_under_collider_and_follows_it() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	body.add_child(shape)
	add_child_autofree(body)
	body.global_position = Vector3(0, 1, -5)
	var hole := BulletHole.new()
	add_child_autofree(hole)
	hole.init(Vector3(0, 1, -5), Vector3(0, 0, 1), body)
	assert_eq(hole.get_parent(), body, "弹孔父节点 = 被击中 collider")
	assert_almost_eq(hole.global_position.x, 0.0, 0.001, "位置 x = 命中点（父级变换正确换算）")
	assert_almost_eq(hole.global_position.y, 1.0, 0.001, "位置 y = 命中点")
	assert_almost_eq(hole.global_position.z, -4.98, 0.001, "位置 z = 命中点沿法线外移 0.02")
	var z := hole.global_transform.basis.z
	assert_almost_eq(z.x, 0.0, 0.001, "贴合法线 basis.z x 分量")
	assert_almost_eq(z.y, 0.0, 0.001, "贴合法线 basis.z y 分量")
	assert_almost_eq(z.z, 1.0, 0.001, "basis.z 朝外（= 投影 -Z 朝墙内，贴平）")
	# 随物体动：collider 平移 → 弹孔 global 位置跟随（body 从 (0,1,-5) → (2,1,-8)，y 不变）
	body.global_position = Vector3(2, 1, -8)
	await wait_physics_frames(1)
	assert_almost_eq(hole.global_position.x, 2.0, 0.001, "collider 移动 → 弹孔随动（x）")
	assert_almost_eq(hole.global_position.y, 1.0, 0.001, "collider 移动 → 弹孔随动（y）")
	assert_almost_eq(hole.global_position.z, -7.98, 0.001, "collider 移动 → 弹孔随动（z，含 0.02 偏移）")


# ================= 2. 30s 生命周期 =================
func test_lifetime_timer_configured_30_seconds() -> void:
	var hole := _spawn_hole(Vector3.ZERO, Vector3.UP)
	var timer := hole.get_node_or_null("LifetimeTimer") as Timer
	assert_not_null(timer, "生命周期 Timer 存在")
	assert_almost_eq(timer.wait_time, 30.0, 0.001, "30s 后自动消失（用户拍板）")
	assert_true(timer.one_shot, "单次触发")
	# 注：Godot 4.7 的 Timer.autostart 是消耗性标志——启动后被引擎清空（实现细节），
	# 行为验证改为：入树后已启动（is_stopped = false，30s 后触发超时）
	assert_false(timer.is_stopped(), "入树即开始 30s 倒计时")


func test_expires_after_lifetime_emits_and_frees() -> void:
	var hole := _spawn_hole(Vector3.ZERO, Vector3.UP)
	var expired_events: Array = []  # GDScript lambda 对局部原始值按值捕获——用数组引用（同 test_grenade 约定）
	hole.expired.connect(func() -> void: expired_events.append(true))
	var timer := hole.get_node_or_null("LifetimeTimer") as Timer
	timer.start(0.05)  # 缩短重启：等效 30s 超时
	await wait_physics_frames(10)  # 0.167s > 0.05s
	assert_eq(expired_events.size(), 1, "超时发 expired（管理方移除计数）")
	assert_false(is_instance_valid(hole), "超时后释放（queue_free 已生效）")
