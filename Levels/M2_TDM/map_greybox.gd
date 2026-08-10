# Levels/M2_TDM/map_greybox.gd
# M2 TDM 灰盒生成器：从 map_layout.gd 数据表程序化生成可玩场景（T2）。
# 生成 StaticBody3D 墙/地面/掩体 + MeshInstance3D 灰盒视觉。
# 用法：作为场景根节点（MapGreybox），或实例化后 add_child。
class_name MapGreybox
extends Node3D

const LAYOUT := preload("res://Levels/M2_TDM/map_layout.gd")

# 灰盒材质：墙/地面/掩体/屋顶 分色便于识别
const MAT_WALL := Color(0.55, 0.55, 0.6)
const MAT_GROUND := Color(0.4, 0.42, 0.45)
const MAT_COVER := Color(0.7, 0.55, 0.35)
const MAT_ROOF := Color(0.5, 0.6, 0.7)
const MAT_RAMP := Color(0.6, 0.6, 0.4)
const MAT_SPAWN := Color(0.3, 0.7, 0.3)

var built := false


func build() -> void:
	if built:
		return
	built = true
	for e in LAYOUT.all_solids():
		# decor（树等纯视觉装饰）不生成碰撞——只生成无碰撞网格
		if e.get("kind", "cover") == "decor":
			_spawn_decor(e)
			continue
		_spawn_solid(e)


func _spawn_solid(e: Dictionary) -> void:
	var c: Vector3 = e["center"]
	var s: Vector3 = e["size"]
	var kind: String = e.get("kind", "cover")  # 缺省按 cover（柱等无 kind 字段）

	var body := StaticBody3D.new()
	body.name = e["name"]
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)

	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = s
	col.shape = box
	body.add_child(col)

	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = s
	mesh.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = _color_for(kind)
	mat.roughness = 0.85
	mesh.material_override = mat
	body.add_child(mesh)

	body.global_position = c


func _color_for(kind: String) -> Color:
	match kind:
		"wall":
			return MAT_WALL
		"ground":
			return MAT_GROUND
		"cover":
			return MAT_COVER
		"roof":
			return MAT_ROOF
		"ramp":
			return MAT_RAMP
		"spawn":
			return MAT_SPAWN
		"decor":
			return Color(0.3, 0.7, 0.3)  # 树绿色
		_:
			return MAT_COVER


# 装饰（树/植物）：无碰撞纯视觉——树干圆柱 + 树冠球
func _spawn_decor(e: Dictionary) -> void:
	var c: Vector3 = e["center"]
	var s: Vector3 = e["size"]
	var root_node := Node3D.new()
	root_node.name = e["name"]
	add_child(root_node)
	root_node.global_position = c
	# 树干（深棕圆柱）
	var trunk := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.12
	cyl.bottom_radius = 0.15
	cyl.height = s.y * 0.5
	trunk.mesh = cyl
	var trunk_mat := StandardMaterial3D.new()
	trunk_mat.albedo_color = Color(0.35, 0.25, 0.15)
	trunk.material_override = trunk_mat
	trunk.position = Vector3(0, -s.y * 0.25, 0)
	root_node.add_child(trunk)
	# 树冠（绿色球）
	var crown := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = s.x * 0.7
	sph.height = s.x * 1.4
	crown.mesh = sph
	var crown_mat := StandardMaterial3D.new()
	crown_mat.albedo_color = Color(0.2, 0.6, 0.25)
	crown.material_override = crown_mat
	crown.position = Vector3(0, s.y * 0.25, 0)
	root_node.add_child(crown)


# ---- 提供导航层所需的静态体集合（T6 navmesh 烘焙用）----
func static_bodies() -> Array:
	var out := []
	for c in get_children():
		if c is StaticBody3D:
			out.append(c)
	return out


# 隐藏全部灰盒网格（视觉层启用后调用——消灭 Z-fighting 闪烁；碰撞保留）
func hide_meshes() -> void:
	for body in get_children():
		if body is StaticBody3D:
			for mi in body.find_children("*", "MeshInstance3D", true, false):
				(mi as MeshInstance3D).visible = false
