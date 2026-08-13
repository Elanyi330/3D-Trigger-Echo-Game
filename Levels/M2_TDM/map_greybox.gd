# Levels/M2_TDM/map_greybox.gd
# M2 TDM 灰盒生成器：从 map_layout_v3.gd 数据表程序化生成可玩场景（T2；T10 切 v3）。
# 生成 StaticBody3D 墙/地面/掩体 + MeshInstance3D 灰盒视觉。
# 用法：作为场景根节点（MapGreybox），或实例化后 add_child。
class_name MapGreybox
extends Node3D

const LAYOUT := preload("res://Levels/M2_TDM/map_layout_v3.gd")
const TEX := preload("res://Levels/M2_TDM/map_textures.gd")

# 灰盒材质：墙/地面/掩体/屋顶 分色便于识别（kind 兜底色；模块名称主题优先，见 NAME_THEME）
const MAT_WALL := Color(0.55, 0.55, 0.6)
const MAT_GROUND := Color(0.62, 0.6, 0.55)  # 石板广场（2026-08-13 视觉提升：浅暖灰）
const MAT_COVER := Color(0.7, 0.55, 0.35)
const MAT_ROOF := Color(0.5, 0.6, 0.7)
const MAT_RAMP := Color(0.6, 0.6, 0.4)
const MAT_SPAWN := Color(0.3, 0.7, 0.3)

# ---- 模块主题配色（2026-08-13 视觉提升）----
# 只改 material_override 颜色，不动任何结构/碰撞/尺寸。
# 名称子串规则，数组顺序 = 优先级（先命中先得）；未命中回退 kind 兜底色。
# 注意顺序陷阱：TowerRail 必须先于 Rail、Box 先于 Cluster/Tower、Camp 先于 Wall——
# 子串匹配会吞掉更具体的前缀（详见注释）。
# 主题：古城祭坛 MC 风——中央圣地（金砂岩/红砂岩/石英/青铜/金）、市集（橡木/云杉/红陶瓦帆布）、
#       市街（苔石长墙/深橡木望楼）、背街（深橡木板）、营（泥砖/军绿货车）、边界（深板岩）。
const NAME_THEME := [
	# —— 中央圣地 · 钟楼 ——
	["Umbrella", Color(0.31, 0.22, 0.13)],      # 伞顶：深橡木
	["Lintel", Color(0.85, 0.68, 0.3)],         # 钟门过梁：金饰
	["Gate", Color(0.86, 0.83, 0.78)],          # 钟门柱/翼墙：白石英
	["Pillar_", Color(0.72, 0.58, 0.32)],       # 钟楼组合柱：青铜
	["CorridorSlab", Color(0.9, 0.87, 0.82)],   # 回廊行走面：亮石英
	["Pedestal", Color(0.33, 0.33, 0.37)],      # 钟基座：深板岩
	["AltarSlab", Color(0.69, 0.4, 0.23)],      # 祭坛斜板：红砂岩
	["AltarPlatform", Color(0.86, 0.79, 0.59)], # 祭坛台：金砂岩
	["Micro", Color(0.86, 0.79, 0.59)],         # 微台阶：随祭坛台
	["Rim", Color(0.47, 0.47, 0.51)],           # 广场 rim 围墙：石砖
	["RampE", Color(0.53, 0.53, 0.57)],         # 东坡道：磨制石砖
	["RampW", Color(0.53, 0.53, 0.57)],         # 西坡道：磨制石砖
	# —— 市集带 / 市街 / 角场 ——
	["Canopy", Color(0.56, 0.29, 0.24)],        # 市集高棚：红陶瓦帆布
	["PavStep", Color(0.45, 0.33, 0.19)],       # 摊阁台阶：云杉木
	["PavilionStep", Color(0.45, 0.33, 0.19)],  # 市街摊阁台阶（EastPavilionStep 命名系）：云杉木
	["Pav", Color(0.65, 0.51, 0.33)],           # 摊阁：橡木
	["Box", Color(0.52, 0.4, 0.24)],            # 货箱/塔顶箱：货物箱
	["EastWall", Color(0.42, 0.48, 0.4)],       # 东市街长墙：苔石
	["WestWall", Color(0.42, 0.48, 0.4)],       # 西市街长墙：苔石
	["TowerRamp", Color(0.45, 0.33, 0.19)],     # 塔坡道：云杉木
	["TowerRail", Color(0.45, 0.33, 0.19)],     # 塔栏板：云杉木
	["Rail", Color(0.84, 0.81, 0.76)],          # 回廊栏板：白石英（必须在 TowerRail 之后）
	["Tower", Color(0.31, 0.22, 0.13)],         # 望楼/水塔塔体：深橡木
	["Cluster", Color(0.65, 0.51, 0.33)],       # 摊位簇板：橡木
	["Spur", Color(0.47, 0.47, 0.51)],          # 横脊墙：石砖
	# —— 背街 ——
	["LOS", Color(0.31, 0.22, 0.13)],           # 断视板：深橡木
	# —— 营 ——
	["Truck", Color(0.28, 0.42, 0.3)],          # 货车：军绿
	["Roof", Color(0.31, 0.22, 0.13)],          # 营顶板：深橡木
	["Camp", Color(0.55, 0.47, 0.38)],          # 营墙/影壁：泥砖
	# —— 边界 ——
	["Wall", Color(0.33, 0.33, 0.37)],          # 外边界墙：深板岩
]

var built := false


func build() -> void:
	if built:
		return
	built = true
	for e in LAYOUT.all_solids():
		var kind: String = e.get("kind", "cover")
		if kind == "decor":
			_spawn_decor(e)
			continue
		if kind == "bigtree":
			_spawn_big_tree(e)
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
	body.position = c

	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = s
	col.shape = box
	body.add_child(col)

	var mesh := MeshInstance3D.new()
	# 2026-08-13 纹理级视觉升级：定制 UV BoxMesh + 主题纹理材质。
	# 微放大 0.02（每侧 0.01）：仅视觉层消除贴面实体共面 z-fighting（纹理花纹会闪，
	# 纯色同色看不出）；碰撞仍用上方 BoxShape3D 原尺寸，零改动。
	mesh.mesh = TEX.box_mesh(s + Vector3(0.02, 0.02, 0.02))
	mesh.material_override = TEX.material_for(_color_for(kind, e["name"]), s)
	body.add_child(mesh)


func _color_for(kind: String, name: String = "") -> Color:
	# 模块名称主题优先（2026-08-13 视觉提升）；未命中回退 kind 兜底色
	if name != "":
		for rule in NAME_THEME:
			if name.contains(rule[0]):
				return rule[1]
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


# 大树（有碰撞体积——用户要求）：StaticBody 树干碰撞（0.7m 见方高 2.5m）+ 树冠视觉球
# 注意：bigtree 数据 center.y 是树干高度一半（1.25）——body 放在全局 y=0（地面），
# 树干从地面起（y 0→2.5m），树冠在顶部。杜绝悬空。
func _spawn_big_tree(e: Dictionary) -> void:
	var c: Vector3 = e["center"]
	var s: Vector3 = e["size"]
	var body := StaticBody3D.new()
	body.name = e["name"]
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	# 树干碰撞（Box 近似树干）——body 原点在地面，树干 0→2.5m
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = s
	col.shape = box
	col.position = Vector3(0, s.y * 0.5, 0)  # 树干从地面到 2.5m（相对 body 原点）
	body.add_child(col)
	# body 放地面（global y = 0），x/z 取数据位置
	body.position = Vector3(c.x, 0, c.z)
	# 视觉：树干圆柱 + 大树冠球（相对 body 原点）
	var trunk := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.3
	cyl.bottom_radius = 0.4
	cyl.height = s.y
	trunk.mesh = cyl
	var trunk_mat := StandardMaterial3D.new()
	trunk_mat.albedo_color = Color(0.35, 0.25, 0.15)  # 深橡木树干（2026-08-13 与 decor 统一）
	trunk.material_override = trunk_mat
	trunk.position = Vector3(0, s.y * 0.5, 0)
	body.add_child(trunk)
	var crown := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 1.6
	sph.height = 3.2
	crown.mesh = sph
	var crown_mat := StandardMaterial3D.new()
	crown_mat.albedo_color = Color(0.2, 0.6, 0.25)  # 树叶绿（2026-08-13 与 decor 统一）
	crown.material_override = crown_mat
	crown.position = Vector3(0, s.y + 1.0, 0)
	body.add_child(crown)


# 装饰（小树/植物）：无碰撞纯视觉——树干圆柱 + 树冠球
# 注意：decor 数据 center.y 是视觉中心高度——root 放地面（y=0），树干从地面起。
# 钟饰（BellDecor）专用钟形几何——2026-08-13 纹理级视觉升级唯一豁免的几何改动（用户拍板）。
func _spawn_decor(e: Dictionary) -> void:
	var c: Vector3 = e["center"]
	var s: Vector3 = e["size"]
	var is_bell: bool = str(e["name"]).contains("Bell")
	var root_node := Node3D.new()
	root_node.name = e["name"]
	add_child(root_node)
	# 树 root 在地面；钟饰 root 抬高到 data center.y 下方（悬于伞顶雷口上方——
	# 2026-08-13 修正：旧代码钟也放地面，嵌在 Pedestal 内部不可见）
	root_node.position = Vector3(c.x, 0, c.z) if not is_bell else Vector3(c.x, c.y - 0.6, c.z)
	if is_bell:
		_build_bell(root_node, s)
	else:
		_build_tree(root_node, s)


# MC 钟形：钟体（上收下张）+ 口沿环 + 钟钮 + 顶球。无碰撞（decor 语义不变）；
# 金纹理金属材质 + 微自发光。
func _build_bell(root_node: Node3D, _s: Vector3) -> void:
	var mat := TEX.material_for(Color(0.95, 0.75, 0.25), Vector3.ONE)
	mat.emission_enabled = true
	mat.emission = Color(0.35, 0.25, 0.06)
	var body := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.22
	cyl.bottom_radius = 0.5
	cyl.height = 0.95
	body.mesh = cyl
	body.material_override = mat
	body.position = Vector3(0, 0.475, 0)
	root_node.add_child(body)
	var rim := MeshInstance3D.new()
	var rcyl := CylinderMesh.new()
	rcyl.top_radius = 0.5
	rcyl.bottom_radius = 0.56
	rcyl.height = 0.1
	rim.mesh = rcyl
	rim.material_override = mat
	rim.position = Vector3(0, 0.05, 0)
	root_node.add_child(rim)
	var knob := MeshInstance3D.new()
	var kcyl := CylinderMesh.new()
	kcyl.top_radius = 0.07
	kcyl.bottom_radius = 0.07
	kcyl.height = 0.18
	knob.mesh = kcyl
	knob.material_override = mat
	knob.position = Vector3(0, 1.01, 0)
	root_node.add_child(knob)
	var ball := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.11
	sph.height = 0.22
	ball.mesh = sph
	ball.material_override = mat
	ball.position = Vector3(0, 1.13, 0)
	root_node.add_child(ball)


# 小树：树干圆柱 + 树冠球（纯色，自然形体不贴纹理）
func _build_tree(root_node: Node3D, s: Vector3) -> void:
	# 树干（深棕圆柱，从地面到 1.0m）
	var trunk := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.12
	cyl.bottom_radius = 0.15
	cyl.height = s.y * 0.5
	trunk.mesh = cyl
	var trunk_mat := StandardMaterial3D.new()
	trunk_mat.albedo_color = Color(0.35, 0.25, 0.15)
	trunk.material_override = trunk_mat
	trunk.position = Vector3(0, s.y * 0.25, 0)
	root_node.add_child(trunk)
	# 树冠（绿色球，在树干顶部上方）
	var crown := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = s.x * 0.7
	sph.height = s.x * 1.4
	crown.mesh = sph
	var crown_mat := StandardMaterial3D.new()
	crown_mat.albedo_color = Color(0.2, 0.6, 0.25)
	crown.material_override = crown_mat
	crown.position = Vector3(0, s.y * 0.5 + 0.5, 0)
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
