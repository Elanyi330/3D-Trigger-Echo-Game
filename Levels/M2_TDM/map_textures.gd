# Levels/M2_TDM/map_textures.gd
# M2 纹理级视觉升级（2026-08-13）：程序化 MC 风 16×16 像素纹理层。
# 职责：把已验收的主题配色（map_greybox.gd NAME_THEME 颜色键）映射为对应纹理材质，
#       并产出"几何与 BoxMesh(size) 完全一致、每面 UV 按世界米数展开"的定制 mesh。
# 只改视觉表层（albedo_texture / UV / roughness / metallic），结构/碰撞零改动。
# 用法：MapGreybox._spawn_solid 调用 box_mesh(size) + material_for(theme_color)。
# 约束：纹理确定性生成（seed = 类型名 hash），探针 tools/probe_textures.gd 门禁。
class_name MapTextures
extends Object

const TEX_SIZE := 16
const PX_PER_METER := 16.0  # 1 世界米 = 一张 16px 纹理（MC 视觉密度）

# ---- 主题色 → 纹理类型（颜色键与 NAME_THEME 规则色一一对应；同类型可多键）----
const TEXTURE_BY_COLOR := {
	Color(0.62, 0.6, 0.55): "ground_stone",      # 石板广场
	Color(0.86, 0.79, 0.59): "sandstone",        # 金砂岩（祭坛台/微台阶）
	Color(0.69, 0.4, 0.23): "red_sandstone",     # 红砂岩（斜板）
	Color(0.47, 0.47, 0.51): "stone_brick",      # 石砖（rim/横脊墙）
	Color(0.53, 0.53, 0.57): "polished_stone",   # 磨制石砖（主坡道）
	Color(0.33, 0.33, 0.37): "deepslate",        # 深板岩（钟基座/边界墙）
	Color(0.9, 0.87, 0.82): "quartz",            # 亮石英（回廊行走面）
	Color(0.84, 0.81, 0.76): "quartz",           # 石英（回廊栏板）
	Color(0.86, 0.83, 0.78): "quartz",           # 石英（钟门柱/翼墙）
	Color(0.72, 0.58, 0.32): "bronze",           # 青铜（组合柱）
	Color(0.85, 0.68, 0.3): "gold",              # 金饰（门梁）
	Color(0.95, 0.75, 0.25): "gold",             # 金（铜钟）
	Color(0.31, 0.22, 0.13): "dark_oak",         # 深橡木（伞顶/塔体/断视板/营顶）
	Color(0.45, 0.33, 0.19): "spruce",           # 云杉木（台阶/塔栏/塔坡道）
	Color(0.65, 0.51, 0.33): "oak",              # 橡木（摊阁/簇板）
	Color(0.52, 0.4, 0.24): "crate",             # 货物箱
	Color(0.56, 0.29, 0.24): "red_canvas",       # 红陶瓦帆布（市集高棚）
	Color(0.42, 0.48, 0.4): "mossy",             # 苔石（市街长墙）
	Color(0.55, 0.47, 0.38): "mud_brick",        # 泥砖（营墙/影壁）
	Color(0.28, 0.42, 0.3): "military_green",    # 军绿（货车）
}

# 材质手感参数（缺省：roughness 0.9 无金属）
const MAT_PROPS := {
	"bronze": {"roughness": 0.45, "metallic": 0.6},
	"gold": {"roughness": 0.4, "metallic": 0.65},
	"quartz": {"roughness": 0.5, "metallic": 0.0},
	"red_canvas": {"roughness": 0.95, "metallic": 0.0},
}

static var _tex_cache: Dictionary = {}


## 纹理材质：主题色 → 对应纹理（未映射颜色回退纯色材质，防御性）
static func material_for(theme_color: Color, _size: Vector3) -> StandardMaterial3D:
	var kind: String = TEXTURE_BY_COLOR.get(theme_color, "")
	var mat := StandardMaterial3D.new()
	if kind == "":
		mat.albedo_color = theme_color
		mat.roughness = 0.9
		return mat
	mat.albedo_texture = texture_for(kind)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	var props: Dictionary = MAT_PROPS.get(kind, {"roughness": 0.9, "metallic": 0.0})
	mat.roughness = props["roughness"]
	mat.metallic = props["metallic"]
	return mat


## 纹理缓存（确定性：seed = 类型名 hash，同类型永远同一张）
static func texture_for(kind: String) -> ImageTexture:
	if _tex_cache.has(kind):
		return _tex_cache[kind]
	var img := Image.create(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind)
	_draw(kind, img, rng)
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_tex_cache[kind] = tex
	return tex


## 定制 UV 的方块 mesh：几何形状与 BoxMesh(size) 完全一致（24 顶点/12 三角），
## 每面 UV 按世界米数展开（u/v ∈ [0, 面宽米数]），纹理 Repeat 采样 → 全图均匀 16px/m。
static func box_mesh(size: Vector3) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h := size * 0.5
	# 每面：[法线 n, U 轴向量, U 长, V 轴向量, V 长, 左下角点 o]
	var faces := [
		[Vector3(0, 0, -1), Vector3(1, 0, 0), size.x, Vector3(0, 1, 0), size.y, Vector3(-h.x, -h.y, -h.z)],
		[Vector3(0, 0, 1), Vector3(-1, 0, 0), size.x, Vector3(0, 1, 0), size.y, Vector3(h.x, -h.y, h.z)],
		[Vector3(-1, 0, 0), Vector3(0, 0, 1), size.z, Vector3(0, 1, 0), size.y, Vector3(-h.x, -h.y, -h.z)],
		[Vector3(1, 0, 0), Vector3(0, 0, -1), size.z, Vector3(0, 1, 0), size.y, Vector3(h.x, -h.y, h.z)],
		[Vector3(0, -1, 0), Vector3(1, 0, 0), size.x, Vector3(0, 0, 1), size.z, Vector3(-h.x, -h.y, -h.z)],
		[Vector3(0, 1, 0), Vector3(1, 0, 0), size.x, Vector3(0, 0, -1), size.z, Vector3(-h.x, h.y, h.z)],
	]
	var base := 0
	for f in faces:
		var n: Vector3 = f[0]
		var u_axis: Vector3 = f[1]
		var w: float = f[2]
		var v_axis: Vector3 = f[3]
		var v_len: float = f[4]
		var o: Vector3 = f[5]
		var corners := [
			[o, Vector2(0, 0)],
			[o + u_axis * w, Vector2(w, 0)],
			[o + u_axis * w + v_axis * v_len, Vector2(w, v_len)],
			[o + v_axis * v_len, Vector2(0, v_len)],
		]
		for c in corners:
			st.set_normal(n)
			st.set_uv(c[1])
			st.add_vertex(c[0])
		st.add_index(base + 0)
		st.add_index(base + 1)
		st.add_index(base + 2)
		st.add_index(base + 0)
		st.add_index(base + 2)
		st.add_index(base + 3)
		base += 4
	var mesh := ArrayMesh.new()
	st.commit(mesh)
	return mesh


# ==================== 纹理绘制（16×16，确定性 RNG） ====================
# 像素风格：MC 经典 16px 纹理密度；噪点/砖缝/木纹全部由固定 seed 生成。

static func _draw(kind: String, img: Image, rng: RandomNumberGenerator) -> void:
	_fill(img, _base_of(kind))
	match kind:
		"ground_stone":
			_brick(img, Color(0.55, 0.53, 0.48), 4, 0, rng)  # 4×4 大石板
			_noise(img, rng, 0.035)
		"stone_brick":
			_brick(img, Color(0.36, 0.36, 0.4), 8, 4, rng)   # 8×4 砖错缝
			_noise(img, rng, 0.03)
		"polished_stone":
			_brick(img, Color(0.44, 0.44, 0.48), 4, 4, rng)  # 4×4 细缝
			_noise(img, rng, 0.02)
		"sandstone":
			_brick(img, Color(0.76, 0.7, 0.52), 8, 4, rng)
			_noise(img, rng, 0.04)
		"red_sandstone":
			_brick(img, Color(0.6, 0.35, 0.2), 8, 4, rng)
			_noise(img, rng, 0.04)
		"deepslate":
			_strata(img, 0.06, rng)
			_noise(img, rng, 0.05)
		"quartz":
			_brick(img, Color(0.78, 0.75, 0.7), 4, 4, rng)  # 4×4 浅缝
			_noise(img, rng, 0.015)
		"bronze":
			_strata(img, 0.05, rng)
			_patches(img, rng, Color(0.3, 0.5, 0.32), 10)   # 氧化绿斑
		"gold":
			_strata(img, 0.06, rng)
			_noise(img, rng, 0.03)
		"dark_oak", "spruce", "oak":
			_wood(img, rng, 0.07, 8)                        # 竖向木纹 + 横向接缝
		"crate":
			_frame(img, Color(0.38, 0.28, 0.16))            # 深色边框 + 对角 X
		"red_canvas":
			_weave(img, rng)                                # 编织纹
		"mossy":
			_brick(img, Color(0.34, 0.39, 0.32), 8, 4, rng)
			_patches(img, rng, Color(0.28, 0.5, 0.27), 22)  # 苔斑
		"mud_brick":
			_brick(img, Color(0.47, 0.39, 0.31), 8, 4, rng)
			_noise(img, rng, 0.03)
		"military_green":
			_plate(img, Color(0.22, 0.34, 0.24), 4, rng)    # 板缝 + 铆钉点
		_:
			_noise(img, rng, 0.02)


static func _base_of(kind: String) -> Color:
	for c in TEXTURE_BY_COLOR:
		if TEXTURE_BY_COLOR[c] == kind:
			return c
	return Color.WHITE


static func _fill(img: Image, col: Color) -> void:
	for y in TEX_SIZE:
		for x in TEX_SIZE:
			img.set_pixel(x, y, col)


## 砖格：bw×bh 砖 + 1px 缝；stagger>0 时奇数行错半砖
static func _brick(img: Image, joint: Color, bw: int, bh: int, rng: RandomNumberGenerator) -> void:
	for y in TEX_SIZE:
		for x in TEX_SIZE:
			if x % (bw + 1) == bw or y % (bh + 1) == bh:
				img.set_pixel(x, y, joint)


## 亮度噪点（±amt）
static func _noise(img: Image, rng: RandomNumberGenerator, amt: float) -> void:
	for y in TEX_SIZE:
		for x in TEX_SIZE:
			var c: Color = img.get_pixel(x, y)
			var d: float = (rng.randf() * 2.0 - 1.0) * amt
			img.set_pixel(x, y, Color(
				clampf(c.r + d, 0.0, 1.0),
				clampf(c.g + d, 0.0, 1.0),
				clampf(c.b + d, 0.0, 1.0)))


## 横向层纹（深板岩/金属）：每行亮度按正弦+随机波动
static func _strata(img: Image, amt: float, rng: RandomNumberGenerator) -> void:
	for y in TEX_SIZE:
		var d: float = (rng.randf() * 2.0 - 1.0) * amt + sin(y * 0.8) * amt * 0.5
		for x in TEX_SIZE:
			var c: Color = img.get_pixel(x, y)
			img.set_pixel(x, y, Color(
				clampf(c.r + d, 0.0, 1.0),
				clampf(c.g + d, 0.0, 1.0),
				clampf(c.b + d, 0.0, 1.0)))


## 斑块（苔斑/氧化斑）：count 个 2×2 块
static func _patches(img: Image, rng: RandomNumberGenerator, col: Color, count: int) -> void:
	for i in count:
		var px := rng.randi_range(0, TEX_SIZE - 2)
		var py := rng.randi_range(0, TEX_SIZE - 2)
		for dy in 2:
			for dx in 2:
				var c: Color = img.get_pixel(px + dx, py + dy)
				img.set_pixel(px + dx, py + dy, c.lerp(col, 0.55))


## 木纹：竖向明暗条纹 + 每 gap 行一条横向深接缝（错位）
static func _wood(img: Image, rng: RandomNumberGenerator, amt: float, gap: int) -> void:
	for x in TEX_SIZE:
		var d: float = (rng.randf() * 2.0 - 1.0) * amt
		for y in TEX_SIZE:
			var c: Color = img.get_pixel(x, y)
			img.set_pixel(x, y, Color(
				clampf(c.r + d, 0.0, 1.0),
				clampf(c.g + d, 0.0, 1.0),
				clampf(c.b + d, 0.0, 1.0)))
	# 横向接缝：每 gap 行，行内错位半段
	var seg := 0
	while seg < TEX_SIZE:
		var y := rng.randi_range(0, TEX_SIZE - 2)
		var x0 := rng.randi_range(0, 3)
		var x1 := rng.randi_range(8, 15)
		for x in TEX_SIZE:
			if x < x0 or x > x1:
				continue
			var c: Color = img.get_pixel(x, y)
			img.set_pixel(x, y, c.darkened(0.25))
		seg += gap


## 箱体边框 + 对角 X 线（MC 箱风）
static func _frame(img: Image, joint: Color) -> void:
	for i in TEX_SIZE:
		img.set_pixel(i, 0, joint)
		img.set_pixel(i, TEX_SIZE - 1, joint)
		img.set_pixel(0, i, joint)
		img.set_pixel(TEX_SIZE - 1, i, joint)
		img.set_pixel(i, i, joint)
		img.set_pixel(i, TEX_SIZE - 1 - i, joint)


## 编织纹（帆布）：1px 明暗交替
static func _weave(img: Image, rng: RandomNumberGenerator) -> void:
	for y in TEX_SIZE:
		for x in TEX_SIZE:
			if (x + y) % 2 == 0:
				var c: Color = img.get_pixel(x, y)
				img.set_pixel(x, y, c.lightened(0.05) if rng.randf() > 0.3 else c.darkened(0.06))


## 金属板：每 gap 行横缝 + 1px 铆钉点
static func _plate(img: Image, joint: Color, gap: int, rng: RandomNumberGenerator) -> void:
	for y in TEX_SIZE:
		if y % gap == 0:
			for x in TEX_SIZE:
				img.set_pixel(x, y, joint)
		if y % gap == gap / 2:
			for x in range(0, TEX_SIZE, 4):
				img.set_pixel(x, y, Color(0.15, 0.25, 0.16))
