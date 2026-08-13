## Jump edge 面级数据结构（T2，2026-08-13）。
##
## 将 LAYOUT.jump_links() 的 56 处点链接升级为面级边，供 T3 物理求解器 /
## T4 语料校准 / M4 AI 消费。本轮只建数据结构，不做物理。
##
## 三个静态接口（签名固定，供消费方 preload + static func 调用）：
##   faces()             —— 面表：{"name": String, "top_y": float,
##                          "center": Vector2(xz), "size": Vector2(xz)}
##   link_face_edges()   —— 每条链接归属：{"link", "from_face", "to_face",
##                          "delta_h", "dist"}
##   face_edge_groups()  —— 面到面边组：{"from_face", "to_face", "delta_h",
##                          "dist", "link_names", "takeoff_zone", "landing_zone"}
## 无 class_name；仿 LAYOUT 用 preload + static func 模式。

const LAYOUT := preload("res://Levels/M2_TDM/map_layout_v3.gd")

# standable_surfaces() 名称 → 实体名别名（与 LAYOUT 注释口径一致）
const ALIAS := {"Corridor": "CorridorSlab", "Altar": "AltarPlatform"}
# 实体顶面入表的 xz 最小边长（栏板/微台阶等细条不入面表）
const MIN_SIDE := 0.4
# 链接端点 y 与面 top_y 的匹配容差
const Y_TOL := 0.01
# 严格匹配失败后的矩形膨胀量
const INFLATE := 0.3
# 去重键浮点归一网格：实体顶 top_y = center.y + size.y/2 与 standable 字面 top_y
# 可能差 1 ULP（例 CorridorSlab：2.85+0.15=3.00000000000000008 vs 字面 3.0），
# 0.001 归一使 (center.x, top_y, center.z) 键在两种来源下相等；
# 不同高度同 (x,z) 的真实面 top_y 差 ≥ 0.3，不会被 0.001 误并（历史教训保留）。
const SNAP := 0.001


static func _key(x: float, top_y: float, z: float) -> Vector3:
	return Vector3(snappedf(x, SNAP), snappedf(top_y, SNAP), snappedf(z, SNAP))


## 面表：Ground → standable_surfaces()（别名映射）→ all_solids() 实体顶面。
## 去重键 Vector3(center.x, top_y, center.z)（0.001 归一，见 SNAP 注释）；
## Ground 先入、已见跳过；输出顺序 = 构建顺序（确定性）。
static func faces() -> Array:
	var out := []
	var seen := {}
	var ground := {"name": "Ground", "top_y": 0.0,
		"center": Vector2(0, 0), "size": Vector2(60, 58)}
	out.append(ground)
	seen[_key(0.0, 0.0, 0.0)] = true
	# standable（name 走别名映射；top_y 直接用；center/size 取 xz）
	for s0 in LAYOUT.standable_surfaces():
		var s: Dictionary = s0
		var c: Vector3 = s["center"]
		var sz: Vector3 = s["size"]
		var top_y: float = s["top_y"]
		var key := _key(c.x, top_y, c.z)
		if seen.has(key):
			continue
		seen[key] = true
		out.append({
			"name": ALIAS.get(s["name"], s["name"]),
			"top_y": top_y,
			"center": Vector2(c.x, c.z),
			"size": Vector2(sz.x, sz.z),
		})
	# 实体顶面：kind ∈ {wall, cover, roof} 且 x/z ≥ MIN_SIDE；top_y = center.y + size.y/2
	for e0 in LAYOUT.all_solids():
		var e: Dictionary = e0
		var kind: String = e["kind"]
		if kind != "wall" and kind != "cover" and kind != "roof":
			continue
		var sz: Vector3 = e["size"]
		if sz.x < MIN_SIDE or sz.z < MIN_SIDE:
			continue
		var c: Vector3 = e["center"]
		var top_y: float = c.y + sz.y * 0.5
		var key := _key(c.x, top_y, c.z)
		if seen.has(key):
			continue
		seen[key] = true
		out.append({
			"name": e["name"],
			"top_y": top_y,
			"center": Vector2(c.x, c.z),
			"size": Vector2(sz.x, sz.z),
		})
	return out


# 点 p 是否在面 f 的矩形内（inclusive；inflate 为矩形每边外扩量）
static func _in_rect(f: Dictionary, p: Vector3, inflate: float) -> bool:
	var c: Vector2 = f["center"]
	var s: Vector2 = f["size"]
	var hx: float = s.x * 0.5 + inflate
	var hz: float = s.y * 0.5 + inflate
	return p.x >= c.x - hx and p.x <= c.x + hx and p.z >= c.y - hz and p.z <= c.y + hz


## 端点找归属面：先严格匹配（|y − top_y| ≤ Y_TOL 且 xz 在面矩形内），
## 无则矩形膨胀 INFLATE 再匹配，仍无 → ""（不抛错：已知有 2 条疑似数据错误
## 链接端点不在任何面上，白名单 PavToSpur_WS/PavToSpur_ES）。
## 两轮均按 faces() 顺序取首个命中（确定性）。
static func _find_face(face_list: Array, p: Vector3) -> String:
	for f0 in face_list:
		var f: Dictionary = f0
		if absf(p.y - float(f["top_y"])) <= Y_TOL and _in_rect(f, p, 0.0):
			return f["name"]
	for f0 in face_list:
		var f: Dictionary = f0
		if absf(p.y - float(f["top_y"])) <= Y_TOL and _in_rect(f, p, INFLATE):
			return f["name"]
	return ""


static func _top_y_of(face_list: Array, face_name: String) -> float:
	for f0 in face_list:
		var f: Dictionary = f0
		if f["name"] == face_name:
			return f["top_y"]
	return 0.0


## 每条链接的归属与几何量。delta_h = to.top_y − from.top_y（from/to 都非空
## 才有意义，否则 0）；dist = 链接 from→to 端点水平距离
## （Vector2(to.x − from.x, to.z − from.z).length()）。
static func link_face_edges() -> Array:
	var face_list := faces()
	var out := []
	for l0 in LAYOUT.jump_links():
		var l: Dictionary = l0
		var fp: Vector3 = l["from"]
		var tp: Vector3 = l["to"]
		var from_face := _find_face(face_list, fp)
		var to_face := _find_face(face_list, tp)
		var delta_h := 0.0
		if from_face != "" and to_face != "":
			delta_h = _top_y_of(face_list, to_face) - _top_y_of(face_list, from_face)
		out.append({
			"link": l["name"],
			"from_face": from_face,
			"to_face": to_face,
			"delta_h": delta_h,
			"dist": Vector2(tp.x - fp.x, tp.z - fp.z).length(),
		})
	return out


static func _face_by_name(face_list: Array, face_name: String) -> Dictionary:
	for f0 in face_list:
		var f: Dictionary = f0
		if f["name"] == face_name:
			return f
	return {}


## 两矩形水平最短距：各分量 |中心差| − 半宽高之和，负值（重叠/相邻）归 0
## 后取模——差值必须取绝对值（负间隙被 maxf 归零误判相邻是历史教训）。
static func _rect_dist(a: Dictionary, b: Dictionary) -> float:
	var ca: Vector2 = a["center"]
	var cb: Vector2 = b["center"]
	var sa: Vector2 = a["size"]
	var sb: Vector2 = b["size"]
	var dx: float = absf(cb.x - ca.x) - (sa.x + sb.x) * 0.5
	var dz: float = absf(cb.y - ca.y) - (sa.y + sb.y) * 0.5
	return Vector2(maxf(dx, 0.0), maxf(dz, 0.0)).length()


## 端点 xz 包围盒 ±0.5 膨胀后钳制在面矩形内；中心/尺寸由钳后矩形给出
## （单端点膨胀为 1×1 再钳制）。
static func _zone(pts: Array, face: Dictionary) -> Dictionary:
	var min_x: float = (pts[0] as Vector2).x
	var max_x: float = min_x
	var min_z: float = (pts[0] as Vector2).y
	var max_z: float = min_z
	for p0 in pts:
		var p: Vector2 = p0
		min_x = minf(min_x, p.x)
		max_x = maxf(max_x, p.x)
		min_z = minf(min_z, p.y)
		max_z = maxf(max_z, p.y)
	var lo_x: float = min_x - 0.5
	var hi_x: float = max_x + 0.5
	var lo_z: float = min_z - 0.5
	var hi_z: float = max_z + 0.5
	var fc: Vector2 = face["center"]
	var fs: Vector2 = face["size"]
	var f_lo_x: float = fc.x - fs.x * 0.5
	var f_hi_x: float = fc.x + fs.x * 0.5
	var f_lo_z: float = fc.y - fs.y * 0.5
	var f_hi_z: float = fc.y + fs.y * 0.5
	lo_x = clampf(lo_x, f_lo_x, f_hi_x)
	hi_x = clampf(hi_x, f_lo_x, f_hi_x)
	lo_z = clampf(lo_z, f_lo_z, f_hi_z)
	hi_z = clampf(hi_z, f_lo_z, f_hi_z)
	return {
		"center": Vector2((lo_x + hi_x) * 0.5, (lo_z + hi_z) * 0.5),
		"size": Vector2(hi_x - lo_x, hi_z - lo_z),
	}


## 面到面边组：link_face_edges() 中 from_face/to_face 均非空的条目按
## (from_face, to_face) 去重合并（键 "%s|%s"，按首次出现顺序）。
## from_face == to_face 的自环照常成组（键含方向）。
## delta_h = 两面 top_y 差；dist = 两面矩形水平最短距（_rect_dist）。
## takeoff_zone = 该组各链接 from 端点在 from 面上的 xz 包围盒 ±0.5 膨胀、
## 钳制在 from 面矩形内；landing_zone 同理（to 端点 / to 面）。
static func face_edge_groups() -> Array:
	var face_list := faces()
	var edges := link_face_edges()
	var links := LAYOUT.jump_links()  # 与 edges 同序（link_face_edges 逐条顺序输出）
	var groups := []
	var group_by_key := {}
	var from_pts := {}   # key -> Array[Vector2]
	var to_pts := {}
	for i in range(edges.size()):
		var e: Dictionary = edges[i]
		if e["from_face"] == "" or e["to_face"] == "":
			continue
		var key: String = "%s|%s" % [e["from_face"], e["to_face"]]
		if not group_by_key.has(key):
			var ff := _face_by_name(face_list, e["from_face"])
			var tf := _face_by_name(face_list, e["to_face"])
			var g := {
				"from_face": e["from_face"],
				"to_face": e["to_face"],
				"delta_h": float(tf["top_y"]) - float(ff["top_y"]),
				"dist": _rect_dist(ff, tf),
				"link_names": [],
				"takeoff_zone": {},
				"landing_zone": {},
			}
			groups.append(g)
			group_by_key[key] = g
			from_pts[key] = []
			to_pts[key] = []
		group_by_key[key]["link_names"].append(e["link"])
		var lp: Dictionary = links[i]
		var lfp: Vector3 = lp["from"]
		var ltp: Vector3 = lp["to"]
		from_pts[key].append(Vector2(lfp.x, lfp.z))
		to_pts[key].append(Vector2(ltp.x, ltp.z))
	for g0 in groups:
		var g: Dictionary = g0
		var key: String = "%s|%s" % [g["from_face"], g["to_face"]]
		g["takeoff_zone"] = _zone(from_pts[key], _face_by_name(face_list, g["from_face"]))
		g["landing_zone"] = _zone(to_pts[key], _face_by_name(face_list, g["to_face"]))
	return groups
