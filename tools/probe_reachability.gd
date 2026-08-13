# tools/probe_reachability.gd — 阶段1：几何可达性静态分析（2026-08-13 navmesh 前置）
# 可达图：节点 = 全部可站立面（Ground + standable_surfaces + 实体顶面）；
# 三类边：步行边（|Δh|≤0.62 相邻，step-up 拍板值）/ 跳跃边（上升 ≤1.51 水平 ≤1.2，
# probe_jump 实测跳高）/ 下跳边（下降 ≤4.0 水平 ≤1.2，无掉落伤害）。
# BFS 自北营出生点 → 理论可达集；与跳跃数据真值（/tmp/jump_study.json 由 jump_study.py 产出）对照：
#   ✅ 人类验证+理论可达 / ⚠️ 理论可达人类未登（候选）/ ❌ 完全不可达。
# 输出：分类清单 + 步行连通对 + 跳跃边对（阶段 3 链接数据决策输入）。
# 用法：先跑 python3 tools/jump_study.py，再 godot --headless --path . -s tools/probe_reachability.gd
extends SceneTree

const LAYOUT := preload("res://Levels/M2_TDM/map_layout_v3.gd")
const WALK_DH := 0.62   # step-up 拍板值（2026-08-12）
const JUMP_DH := 1.4    # 站立跳高实测 1.388（probe_jump）
const JUMP_HORIZ := 4.0  # 保守助跑跳远（实测 4.868；人类数据摊阁→簇板水平 3.8 成功）
const DROP_DH := 4.0
const ADJ_HORIZ := 0.6  # 步行相邻水平距

var _faces: Array = []  # {name, top_y, center(xz), size(xz)}


func _init() -> void:
	_build_faces()
	var reachable := _bfs(_find_face("Ground"))
	# 加载人类真值
	var human := {}
	var study := FileAccess.open("/tmp/jump_study.json", FileAccess.READ)
	if study:
		var data: Dictionary = JSON.parse_string(study.get_as_text())
		for k in data["reachable_faces"]:
			human[str(k)] = int(data["reachable_faces"][k])
	print("=== 面清单（%d 个）===" % _faces.size())
	var confirmed := []
	var candidates := []
	var impossible := []
	for f in _faces:
		var nm: String = f["name"]
		var h: bool = human.has(nm)
		if reachable.has(nm):
			if h:
				confirmed.append(nm)
			else:
				candidates.append(nm)
		else:
			impossible.append(nm)
	print("\n✅ 人类验证+理论可达（%d）: %s" % [confirmed.size(), str(confirmed)])
	print("\n⚠️ 理论可达、人类未登（%d）: %s" % [candidates.size(), str(candidates)])
	print("\n❌ 完全不可达（%d）: %s" % [impossible.size(), str(impossible)])
	# 人类可达但理论不可达 = 分析缺口（bug 信号；@StaticBody3D@ 为运行时动态名噪声，白名单忽略）
	var gaps := []
	for k in human:
		if str(k).begins_with("@"):
			continue
		if not reachable.has(k) and not _face_exists(k):
			gaps.append(k)
	if gaps.size() > 0:
		print("\n! 人类可达但面枚举缺失（分析缺口）: %s" % str(gaps))
	_print_edges(reachable)
	quit(0)


func _build_faces() -> void:
	# Ground
	_faces.append({"name": "Ground", "top_y": 0.0, "center": Vector2(0, 0), "size": Vector2(60, 58)})
	# 去重 key 用 3D（x, top_y, z）——不同高度同 (x,z) 的面不得互撞（2026-08-13 修复：
	# 旧 (x,z) key 让 Ground 撞掉 AltarPlatform/CorridorSlab 等全部中心面）
	var seen := {Vector3(0, 0, 0): true}
	# standable_surfaces
	# 别名映射：standable_surfaces 的 name 与 all_solids 实体名（人类 floor_name 用实体名）
	const ALIAS := {"Corridor": "CorridorSlab", "Altar": "AltarPlatform"}
	for s0 in LAYOUT.standable_surfaces():
		var s: Dictionary = s0
		var key := Vector3(s["center"].x, s["top_y"], s["center"].z)
		if seen.has(key):
			continue
		seen[key] = true
		var nm: String = s["name"]
		if ALIAS.has(nm):
			nm = ALIAS[nm]
		_faces.append({"name": nm, "top_y": s["top_y"], "center": Vector2(s["center"].x, s["center"].z), "size": Vector2(s["size"].x, s["size"].z)})
	# 实体顶面（kind wall/cover/roof；水平尺寸 ≥0.4——塔坡道级 0.62/簇板 0.4/斜板 0.4 需纳入）
	for e0 in LAYOUT.all_solids():
		var e: Dictionary = e0
		if e["kind"] == "ground" or e["kind"] == "decor" or e["kind"] == "bigtree":
			continue
		var s: Vector3 = e["size"]
		if s.x < 0.4 or s.z < 0.4:
			continue
		var top: float = e["center"].y + s.y * 0.5
		var key := Vector3(e["center"].x, top, e["center"].z)
		if seen.has(key):
			continue
		seen[key] = true
		_faces.append({"name": e["name"], "top_y": top, "center": Vector2(e["center"].x, e["center"].z), "size": Vector2(s.x, s.z)})


func _find_face(nm: String) -> Dictionary:
	for f in _faces:
		if f["name"] == nm:
			return f
	return {}


func _face_exists(nm: String) -> bool:
	return not _find_face(nm).is_empty()


## 两面水平相邻（投影矩形膨胀 ADJ_HORIZ 相交）
func _adjacent(a: Dictionary, b: Dictionary) -> bool:
	var a0: Vector2 = a["center"] - a["size"] * 0.5 - Vector2(ADJ_HORIZ, ADJ_HORIZ)
	var a1: Vector2 = a["center"] + a["size"] * 0.5 + Vector2(ADJ_HORIZ, ADJ_HORIZ)
	var b0: Vector2 = b["center"] - b["size"] * 0.5
	var b1: Vector2 = b["center"] + b["size"] * 0.5
	return a0.x < b1.x and a1.x > b0.x and a0.y < b1.y and a1.y > b0.y


func _horiz_dist(a: Dictionary, b: Dictionary) -> float:
	# 矩形间最短水平距离（2026-08-13 修复：差值必须取绝对值——负间隙被 maxf 归零会误判相邻）
	var dx := maxf(absf(a["center"].x - b["center"].x) - (a["size"].x + b["size"].x) * 0.5, 0.0)
	var dz := maxf(absf(a["center"].y - b["center"].y) - (a["size"].y + b["size"].y) * 0.5, 0.0)
	return Vector2(dx, dz).length()


func _bfs(start: Dictionary) -> Dictionary:
	var reached := {start["name"]: true}
	var queue := [start]
	while not queue.is_empty():
		var cur: Dictionary = queue.pop_front()
		for n in _faces:
			if reached.has(n["name"]):
				continue
			if cur["name"] == n["name"]:
				continue
			var dh: float = n["top_y"] - cur["top_y"]
			var hd: float = _horiz_dist(cur, n)
			var ok := false
			if absf(dh) <= WALK_DH and _adjacent(cur, n):
				ok = true  # 步行边（step-up 同高相邻）
			elif absf(dh) <= WALK_DH and hd > ADJ_HORIZ and hd <= JUMP_HORIZ:
				ok = true  # 同高水平跳（跳过豁口/间隙——人类 RimS1→RimS2 实证）
			elif dh > WALK_DH and dh <= JUMP_DH and hd <= JUMP_HORIZ:
				ok = true  # 上升跳跃边
			elif dh < -WALK_DH and dh >= -DROP_DH and hd <= JUMP_HORIZ:
				ok = true  # 下跳边
			if ok:
				reached[n["name"]] = true
				queue.append(n)
	return reached


func _print_edges(reachable: Dictionary) -> void:
	print("\n=== 跳跃边对（上升 >0.62 可达对——阶段 3 链接候选）===")
	var seen_pairs := {}
	var edges: Array = []
	for a in _faces:
		if not reachable.has(a["name"]):
			continue
		for b in _faces:
			if a["name"] == b["name"] or not reachable.has(b["name"]):
				continue
			var dh: float = b["top_y"] - a["top_y"]
			if dh > WALK_DH and dh <= JUMP_DH and _horiz_dist(a, b) <= JUMP_HORIZ:
				var key := "%s->%s" % [a["name"], b["name"]]
				if seen_pairs.has(key):
					continue
				seen_pairs[key] = true
				edges.append({"from": a, "to": b})
	edges.sort_custom(func(x, y): return x["to"]["top_y"] - x["from"]["top_y"] > y["to"]["top_y"] - y["from"]["top_y"])
	for e in edges:
		print("  %-20s -> %-20s  Δh=%.2f" % [e["from"]["name"], e["to"]["name"], e["to"]["top_y"] - e["from"]["top_y"]])
	print("跳跃边对总数: %d" % edges.size())
