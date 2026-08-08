# test/unit/test_tracer.gd
# M1 任务15：曳光弹（CC0 bullet_tracer 照搬）——枪口→命中点短暂线条测试（TDD RED 先行）
# 行为（brief 交付内容 4）：射击生成枪口→命中点线条（十字双面 QuadMesh），0.1s 淡出自清；
#   位置 = 线段中点、长度轴沿线段方向；命中点 = hit_landed 位置，未命中 = max_range 端点。
# 全局约束：0.1s 生命周期不真实等待——物理帧步进（wait_physics_frames）。
extends GutTest


func _spawn(from: Vector3, to: Vector3) -> Tracer:
	var tracer := Tracer.new()
	add_child_autofree(tracer)
	tracer.init(from, to)
	return tracer


# ================= 1. 几何（中点/长度轴/十字双面） =================
func test_init_midpoint_and_alignment() -> void:
	var tracer := _spawn(Vector3(0, 1, 0), Vector3(0, 1, -10))
	assert_almost_eq(tracer.global_position.x, 0.0, 0.001, "位置 x = 线段中点")
	assert_almost_eq(tracer.global_position.y, 1.0, 0.001, "位置 y = 线段中点")
	assert_almost_eq(tracer.global_position.z, -5.0, 0.001, "位置 z = 线段中点")
	var dir := tracer.global_transform.basis.y
	assert_almost_eq(dir.x, 0.0, 0.001, "长度轴 x 分量")
	assert_almost_eq(dir.y, 0.0, 0.001, "长度轴 y 分量")
	assert_almost_eq(dir.z, -1.0, 0.001, "长度轴沿线段方向（从 枪口 → 命中点）")
	var quads: Array[MeshInstance3D] = []
	for child in tracer.get_children():
		if child is MeshInstance3D:
			quads.append(child)
	assert_eq(quads.size(), 2, "十字双面 QuadMesh（任何视角至少一面可见）")
	if quads.size() >= 1:
		var mesh := quads[0].mesh as QuadMesh
		assert_not_null(mesh, "QuadMesh 网格")
		if mesh != null:
			assert_almost_eq(mesh.size.y, 10.0, 0.001, "quad 长度 = 线段距离（10m）")
			assert_almost_eq(mesh.size.x, 0.004, 0.001, "quad 宽度 = 线条宽度（参数化）")


func test_second_quad_twisted_90_degrees() -> void:
	# 第二面绕长度轴（局部 Y）转 90°：两 quad 平面互成十字
	var tracer := _spawn(Vector3(0, 0, 0), Vector3(0, 0, -5))
	var quads: Array[MeshInstance3D] = []
	for child in tracer.get_children():
		if child is MeshInstance3D:
			quads.append(child)
	assert_eq(quads.size(), 2, "两个 quad")
	if quads.size() == 2:
		assert_almost_eq(quads[1].rotation.y, PI * 0.5, 0.001, "第二面绕长度轴转 90°（十字）")


# ================= 2. 0.1s 生命周期（淡出 + 自清） =================
func test_fades_and_frees_after_lifetime() -> void:
	var tracer := _spawn(Vector3(0, 1, 0), Vector3(0, 1, -10))
	assert_true(is_instance_valid(tracer), "生成后有效")
	await wait_physics_frames(4)  # 0.067s < 0.1s
	assert_true(is_instance_valid(tracer), "0.1s 内仍存在（淡出中）")
	await wait_physics_frames(6)  # 累计 0.167s > 0.1s
	assert_false(is_instance_valid(tracer), "0.1s 后淡出自清")


func test_alpha_fades_over_lifetime() -> void:
	var tracer := _spawn(Vector3(0, 1, 0), Vector3(0, 1, -10))
	var start_a: float = tracer._material.albedo_color.a
	assert_gt(start_a, 0.5, "起始不透明")
	await wait_physics_frames(3)  # 0.05s：半程
	assert_lt(tracer._material.albedo_color.a, start_a, "透明度随时间下降（淡出）")


func test_degenerate_line_self_frees() -> void:
	var tracer := _spawn(Vector3(1, 2, 3), Vector3(1, 2, 3))
	await wait_physics_frames(1)
	assert_false(is_instance_valid(tracer), "零长度线段（from == to）直接自清")
