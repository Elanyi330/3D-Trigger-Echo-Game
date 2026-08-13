# test/unit/test_boundary_walls.gd
# 任务 T1（2026-08-13）：M2 边界隐形高墙——地图边界墙外缘加 4 面 12m 高隐形高墙
# （仅碰撞、无视觉），防止玩家从高处（营顶 4.9m 等）跳越 4m 边界墙坠出地图
# （图外无地面 = 虚空）。
# 实现位于 map_greybox.gd 的 _build_boundary_walls() 独立函数，绝不写进布局数据——
# 193 实体数 / 布局哈希 / 玩家跳跃记录 / 窄缝扫描 / 探针全部不受影响（用户铁律）。
# TDD：本文件先行（RED），map_greybox 实现后 GREEN。
extends GutTest

const LAYOUT := preload("res://Levels/M2_TDM/map_layout_v3.gd")
const JumpRecordCore := preload("res://Levels/M2_TDM/jump_record_core.gd")
const MovementController := preload("res://Player/MovementController.gd")

# 4 面隐形高墙精确几何（brief T1 表格，逐字）。
# 几何依据：可见边界墙外缘实测西/东 x=±31、北/南 z=±30；用户口径「x=±31/z=±30.5」——
# 北/南 1m 厚墙中心 z=±30.5 内缘恰贴可见墙外缘 z=±30；西/东内缘贴 x=±31 向外延 1m
# （中心 ±31.5），内缘与可见墙外缘平齐零缝隙（图外无地面，留缝 = 虚空坠落陷阱）。
# 角部：东西墙 z∈[−31,31] 与南北墙 x∈[−31,31] 互叠无缝隙。
const WALLS := {
	"BoundaryWallN": {"center": Vector3(0, 6, 30.5), "size": Vector3(62, 12, 1)},
	"BoundaryWallS": {"center": Vector3(0, 6, -30.5), "size": Vector3(62, 12, 1)},
	"BoundaryWallW": {"center": Vector3(-31.5, 6, 0), "size": Vector3(1, 12, 62)},
	"BoundaryWallE": {"center": Vector3(31.5, 6, 0), "size": Vector3(1, 12, 62)},
}

# 布局哈希指纹（2026-08-13 实测：godot --headless --path . -s /tmp/hash_probe.gd，
# 布局 v3 + MovementController.MOVEMENT_REV）。地图每改动一次此值即变（跳跃记录自动作废），
# 本测试钉死「布局数据一字不动」。
const EXPECTED_HASH := "f935ccd7c32c7cd4bdd47e8b9f6ef858b8f4220bd3f85606e810743eeb6bcef0"


func _build_greybox() -> Node3D:
	var gb: Node3D = preload("res://Levels/M2_TDM/map_greybox.gd").new()
	add_child_autofree(gb)
	gb.build()
	return gb


# ================= 1. 4 面墙精确几何 =================
func test_boundary_walls_built_with_exact_geometry() -> void:
	var gb: Node3D = preload("res://Levels/M2_TDM/map_greybox.gd").new()
	add_child_autofree(gb)
	gb.build()
	for wall_name in WALLS.keys():
		var body := gb.get_node_or_null(wall_name) as StaticBody3D
		assert_not_null(body, "存在边界墙节点 " + wall_name)
		if body == null:
			continue
		var exp: Dictionary = WALLS[wall_name]
		var pos: Vector3 = body.position
		var c: Vector3 = exp["center"]
		assert_almost_eq(pos.x, c.x, 0.001, wall_name + " center.x")
		assert_almost_eq(pos.y, c.y, 0.001, wall_name + " center.y")
		assert_almost_eq(pos.z, c.z, 0.001, wall_name + " center.z")
		var col := body.get_child(0) as CollisionShape3D
		assert_not_null(col, wall_name + " 首个子节点为 CollisionShape3D")
		if col == null:
			continue
		var shape := col.shape as BoxShape3D
		assert_not_null(shape, wall_name + " shape 为 BoxShape3D")
		if shape == null:
			continue
		var s: Vector3 = shape.size
		var es: Vector3 = exp["size"]
		assert_almost_eq(s.x, es.x, 0.001, wall_name + " size.x")
		assert_almost_eq(s.y, es.y, 0.001, wall_name + " size.y")
		assert_almost_eq(s.z, es.z, 0.001, wall_name + " size.z")


# ================= 2. 隐形（无视觉网格） =================
func test_boundary_walls_have_no_visual_mesh() -> void:
	var gb := _build_greybox()
	for wall_name in WALLS.keys():
		var body := gb.get_node_or_null(wall_name) as StaticBody3D
		assert_not_null(body, "存在边界墙节点 " + wall_name)
		if body == null:
			continue
		assert_true(body.find_children("*", "MeshInstance3D", true, false).is_empty(),
				wall_name + " 无任何 MeshInstance3D（隐形墙无视觉）")
		assert_eq(body.find_children("*", "CollisionShape3D", true, false).size(), 1,
				wall_name + " 恰有 1 个 CollisionShape3D")


# ================= 3. static_bodies() 计入 4 面边界墙 =================
func test_static_bodies_count_196() -> void:
	var gb := _build_greybox()
	# 193 all_solids 中 1 个 decor（_spawn_decor 生成 Node3D，非 StaticBody3D），
	# 故 192 布局静态体 + 4 边界墙 = 196。
	# （brief 原写 197 基于「193 全部生成 StaticBody」口径，实测修正，见任务报告。）
	assert_eq(gb.static_bodies().size(), 196, "static_bodies = 192 布局 + 4 边界墙")


# ================= 4. 布局数据一字不动 =================
func test_layout_solids_untouched() -> void:
	assert_eq(LAYOUT.all_solids().size(), 193, "布局实体数恒为 193（边界墙不写进布局）")


# ================= 5. 布局哈希钉死 =================
func test_layout_hash_pinned() -> void:
	var h := JumpRecordCore.map_hash(LAYOUT.all_solids(), MovementController.MOVEMENT_REV)
	assert_eq(h, EXPECTED_HASH, "布局哈希钉死（地图改动一次 → 跳跃记录作废）")


# ================= 6. 197 名互不重复 =================
func test_boundary_names_unique() -> void:
	var seen := {}
	for solid in LAYOUT.all_solids():
		seen[solid["name"]] = true
	for wall_name in WALLS.keys():
		seen[wall_name] = true
	assert_eq(seen.size(), 197, "193 布局名 + 4 边界墙名共 197 个互不重复（Dictionary 当 set）")
