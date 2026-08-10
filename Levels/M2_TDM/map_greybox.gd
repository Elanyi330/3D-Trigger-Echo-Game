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
		_:
			return MAT_COVER


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
