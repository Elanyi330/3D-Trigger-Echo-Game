# Levels/M2_TDM/map_visuals.gd
# M2 地图视觉升级层（问题B：块状组件过于单调）。
# 职责：在灰盒碰撞层之上叠加"视觉装饰"——用 CC0 现成模型（Kenney Modular Buildings 等）
#       覆盖灰盒组件的表面，让地图看起来像真实城市街区，同时保持布局/碰撞不变。
# 设计：纯视觉层（无碰撞/无层），挂在灰盒之上。每个灰盒组件 → 匹配一个装饰模型。
# 用法：MapGreybox.build() 之后 add_child 本节点并 build_visuals()。
class_name MapVisuals
extends Node3D

# 装饰模型注册表：灰盒组件 kind → 模型路径 + 缩放策略
# 模型来源：Kenney Modular Buildings (CC0) / City Kit Roads (CC0)，见 README 许可合规章节。
# Kenney 模型 = 1 单位基准（building-block 1x1x0.625m）→ 用 Tile 平铺覆盖组件表面。
const DECOR := {
	"wall": {
		"model": "res://tools/render/sources/map/kenney_modular/Models/GLB format/building-block.glb",
		"tile": true,       # 平铺：按组件尺寸复制
	},
	"roof": {
		"model": "res://tools/render/sources/map/kenney_modular/Models/GLB format/roof-flat-border-center.glb",
		"tile": true,
	},
	"cover": {
		"model": "res://tools/render/sources/map/kenney_modular/Models/GLB format/building-block.glb",
		"tile": false,      # 单块缩放
	},
}

const LAYOUT := preload("res://Levels/M2_TDM/map_layout.gd")

var _built := false


func build_visuals() -> void:
	if _built:
		return
	_built = true
	for e in LAYOUT.all_solids():
		var d: Dictionary = e
		var kind: String = d.get("kind", "cover")
		var c: Vector3 = d["center"]
		var s: Vector3 = d["size"]
		# 地面/出生区不装饰（保持地面简洁）
		if kind == "ground" or kind == "spawn":
			continue
		# 尝试加载装饰模型；无模型 → 程序化"带砖缝"立方体（视觉过渡）
		_add_decor(kind, c, s)


func _add_decor(kind: String, center: Vector3, size: Vector3) -> void:
	var cfg: Dictionary = DECOR.get(kind, DECOR["cover"])
	if cfg["model"] == "":
		_add_fallback(kind, center, size)
		return
	var scene: PackedScene = load(cfg["model"])
	if scene == null:
		_add_fallback(kind, center, size)
		return
	if cfg.get("tile", false):
		_tile_decor(scene, center, size)
	else:
		_single_decor(scene, center, size)


# 平铺模式：按组件表面铺 1m 网格模型（Kenney 1 单位模型）
func _tile_decor(scene: PackedScene, center: Vector3, size: Vector3) -> void:
	var nx := maxi(1, int(round(size.x)))
	var nz := maxi(1, int(round(size.z)))
	for ix in nx:
		for iz in nz:
			var inst: Node3D = scene.instantiate()
			add_child(inst)  # 先入树再定位
			inst.global_position = Vector3(
				center.x - size.x * 0.5 + 0.5 + ix,
				center.y,
				center.z - size.z * 0.5 + 0.5 + iz
			)


# 单块模式：等比缩放到组件
func _single_decor(scene: PackedScene, center: Vector3, size: Vector3) -> void:
	var inst: Node3D = scene.instantiate()
	add_child(inst)  # 先入树再定位
	inst.global_position = center
	# 等比缩放到组件尺寸
	var bbox := _calc_bbox(inst)
	if bbox.length() > 0.01:
		var s := minf(size.x / bbox.x, size.z / bbox.z)
		inst.scale = Vector3.ONE * s


func _add_fallback(kind: String, center: Vector3, size: Vector3) -> void:
	# 程序化过渡视觉：灰盒组件的"砖墙/屋顶/箱"纹理盒子（半透明强调位置）
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size + Vector3(0.02, 0.02, 0.02)  # 微放大盖住灰盒
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.8, 0.7, 0.9)  # 暖砖色半透明
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.9
	mi.material_override = mat
	mi.global_position = center
	add_child(mi)


func _calc_bbox(n: Node3D) -> Vector3:
	var mn := Vector3(1e9, 1e9, 1e9)
	var mx := -mn
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var aabb: AABB = (mi as MeshInstance3D).get_aabb()
		var world := (mi as MeshInstance3D).global_transform
		for i in 8:
			var corner := Vector3(
				aabb.position.x + (aabb.size.x if i & 1 else 0.0),
				aabb.position.y + (aabb.size.y if i & 2 else 0.0),
				aabb.position.z + (aabb.size.z if i & 4 else 0.0)
			)
			var wc: Vector3 = world * corner
			mn = mn.min(wc)
			mx = mx.max(wc)
	return mx - mn
