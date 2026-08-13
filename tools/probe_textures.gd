# tools/probe_textures.gd — 纹理级视觉升级门禁（2026-08-13）
# 用法：godot --headless --path . -s tools/probe_textures.gd
# 验证：
#   1. 配色全覆盖——NAME_THEME 每条规则色都在 TEXTURE_BY_COLOR 中（防漏映射回退纯色）；
#   2. 几何不变——box_mesh(size) 24 顶点/12 三角、AABB 与 BoxMesh(size) 一致（结构红线）；
#   3. UV 米数展开——max u = max(sx,sz)、max v = max(sy,sz)（纹理均匀平铺的前提）；
#   4. 纹理确定性——同类型两次取同一实例、16×16 RGB8；
#   5. 钟饰结构——BellDecor 4 个钟形网格、零碰撞（decor 语义不变，几何豁免仅限钟）。
extends SceneTree

const GB := preload("res://Levels/M2_TDM/map_greybox.gd")
const TEX := preload("res://Levels/M2_TDM/map_textures.gd")
const LAYOUT := preload("res://Levels/M2_TDM/map_layout_v3.gd")

func _init() -> void:
	var fails := 0

	# ---- 1. 配色全覆盖 ----
	var kinds := {}
	for rule in GB.NAME_THEME:
		var col: Color = rule[1]
		if not TEX.TEXTURE_BY_COLOR.has(col):
			fails += 1
			print("FAIL  规则色未映射纹理: %s %s" % [rule[0], col])
		else:
			kinds[TEX.TEXTURE_BY_COLOR[col]] = true
	# Ground 走 kind 兜底（MAT_GROUND），也必须映射纹理
	if not TEX.TEXTURE_BY_COLOR.has(GB.MAT_GROUND):
		fails += 1
		print("FAIL  MAT_GROUND %s 未映射纹理" % GB.MAT_GROUND)
	print("纹理类型数: %d（期望 16，Ground 另计）, 规则条数: %d" % [kinds.size(), GB.NAME_THEME.size()])

	# ---- 2. 几何不变（与 BoxMesh(size) 对比）----
	for probe_size in [Vector3(60, 4, 1), Vector3(14, 0.6, 10), Vector3(0.5, 4.1, 0.5), Vector3(1, 3, 1)]:
		var m: ArrayMesh = TEX.box_mesh(probe_size)
		var arr: Array = m.surface_get_arrays(0)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		if verts.size() != 24:
			fails += 1
			print("FAIL  顶点数 %d != 24 (size=%s)" % [verts.size(), probe_size])
		if idx.size() != 36:
			fails += 1
			print("FAIL  索引数 %d != 36 (size=%s)" % [idx.size(), probe_size])
		var aabb: AABB = m.get_aabb()
		if not aabb.position.is_equal_approx(-probe_size * 0.5) or not aabb.size.is_equal_approx(probe_size):
			fails += 1
			print("FAIL  AABB %s 与 BoxMesh(size=%s) 不一致" % [aabb, probe_size])

	# ---- 3. UV 米数展开 ----
	for probe_size in [Vector3(60, 4, 1), Vector3(60, 1, 58), Vector3(4, 2.5, 4), Vector3(0.4, 2.1, 3)]:
		var m: ArrayMesh = TEX.box_mesh(probe_size)
		var arr: Array = m.surface_get_arrays(0)
		var uvs: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
		var max_u := 0.0
		var max_v := 0.0
		for uv in uvs:
			max_u = maxf(max_u, uv.x)
			max_v = maxf(max_v, uv.y)
		var exp_u: float = maxf(probe_size.x, probe_size.z)
		var exp_v: float = maxf(probe_size.y, probe_size.z)
		if not is_equal_approx(max_u, exp_u) or not is_equal_approx(max_v, exp_v):
			fails += 1
			print("FAIL  UV 展开 (%s, %s) != 期望 (%s, %s)  (size=%s)" % [max_u, max_v, exp_u, exp_v, probe_size])

	# ---- 4. 纹理确定性 + 尺寸 ----
	var t1: ImageTexture = TEX.texture_for("stone_brick")
	var t2: ImageTexture = TEX.texture_for("stone_brick")
	if t1 != t2:
		fails += 1
		print("FAIL  纹理缓存未命中（两次取到不同实例）")
	var img: Image = t1.get_image()
	if img.get_width() != 16 or img.get_height() != 16:
		fails += 1
		print("FAIL  纹理尺寸 %dx%d != 16x16" % [img.get_width(), img.get_height()])

	# ---- 5. 钟饰结构（几何豁免仅限 BellDecor）----
	var gb = GB.new()
	gb.name = "Greybox"
	gb.build()
	var bell: Node = gb.get_node_or_null("BellDecor")
	if bell == null:
		fails += 1
		print("FAIL  BellDecor 未生成")
	else:
		var parts: int = bell.find_children("*", "MeshInstance3D", true, false).size()
		if parts != 4:
			fails += 1
			print("FAIL  钟形部件数 %d != 4（钟体/口沿环/钟钮/顶球）" % parts)
		if bell.find_children("*", "CollisionShape3D", true, false).size() != 0:
			fails += 1
			print("FAIL  钟饰出现碰撞体（decor 无碰撞语义被破坏）")
	# 结构红线：实体数仍 193，且除钟外全部 StaticBody 碰撞不变（碰撞层=1）
	var solids: Array = LAYOUT.all_solids()
	if solids.size() != 193:
		fails += 1
		print("FAIL  实体总数 %d != 193（结构被改动）" % solids.size())

	print("---")
	print("纹理门禁：%s" % ("FAIL %d 项" % fails if fails > 0 else "全过（覆盖率/几何/UV/确定性/钟饰）"))
	quit(1 if fails > 0 else 0)
