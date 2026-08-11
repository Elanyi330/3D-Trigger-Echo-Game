# tools/probe_sightlines.gd
# v3 视线探针（T16，设计文档 §八.3）：战斗区内无 >40m 单一通视（双层门控，2026-08-11 控制器裁决）。
# 采样：网格 x∈[-29,29]、z∈[-28,28]、步长 4m、眼高 1.7（地面点；眼点落入实体数据 AABB 内的点排除——
# 玩家无法站在实体体积内）；加点：回廊面眼高 4.7（(0,4.7,±3)/(±3,4.7,0)）、双塔顶眼高 4.2（(±18.5,4.2,0)）。
# 两两 intersect_ray（collision_mask=1）：无命中 = 通视；距离 = 两点欧氏距离（与命中无关，可先按距离筛候选）。
# 门控 ①硬门控（决定 EXIT 码）：两端点均在战斗矩形（|x|≤23.5 且 |z|≤14）内的 >40m 通视对必须 0；
# 门控 ②基线层（仅报告）：其余 >40m 对（外环/营前场/边界带/单端战斗区内）计数 + 前 20 条清单，
#   标注基线日期语义，灰盒阶段接受、playtest 后复评，不影响 EXIT。
# 用法: godot --headless --path . -s res://tools/probe_sightlines.gd
extends SceneTree

const LAYOUT := preload("res://Levels/M2_TDM/map_layout_v3.gd")
const EYE := 1.7          # 站姿眼高
const CORRIDOR_EYE := 4.7  # 回廊面 3.0 + 1.7
const TOWER_EYE := 4.2     # 塔顶 2.5 + 1.7
const MAX_LOS := 40.0
const STEP := 4.0
# 战斗矩形（硬门控边界）：长墙 x=±23 内侧 + rim 墙 z=±9.5 外沿留量——核心交战带
const COMBAT_X := 23.5
const COMBAT_Z := 14.0
# 外环基线日期语义：基线建立日；布局数据变更 → 基线作废需复测重立
const BASELINE_TAG := "BASELINE_2026-08-11"
const BASELINE_LIST_MAX := 20


func _initialize() -> void:
	# 灰盒地图（build() 生成全部 StaticBody，含地面，collision_layer=1）
	var gb_script := load("res://Levels/M2_TDM/map_greybox.gd")
	var gb: Node3D = gb_script.new()
	gb.name = "MapGreybox"
	root.add_child(gb)
	gb.build()
	_run()


func _run() -> void:
	print("PROBE_SIGHTLINES 战斗矩形硬门控: |x|≤%.1f 且 |z|≤%.1f；基线=%s" % [
		COMBAT_X, COMBAT_Z, BASELINE_TAG])
	# 等物理空间同步（StaticBody broadphase 注册）
	for f in 3:
		await physics_frame
	var pts := _collect_points()
	var space := root.get_world_3d().direct_space_state
	var total_pairs := 0
	var cand_pairs := 0
	var bad := []
	for i in range(pts.size()):
		for j in range(i + 1, pts.size()):
			total_pairs += 1
			var d: float = pts[i].distance_to(pts[j])
			if d <= MAX_LOS:
				continue  # 距离 ≤40m 的对不可能违规，无需 ray
			cand_pairs += 1
			var q := PhysicsRayQueryParameters3D.create(pts[i], pts[j], 1)
			if space.intersect_ray(q).is_empty():
				bad.append([pts[i], pts[j], d])
	print("PROBE_SIGHTLINES 采样点=%d  全部对=%d  检测对(d>%.0fm)=%d" % [
		pts.size(), total_pairs, MAX_LOS, cand_pairs])
	# 门控 ① 硬门控：两端点均在战斗矩形内
	var hard := []
	var baseline := []
	for b in bad:
		if _in_combat(b[0]) and _in_combat(b[1]):
			hard.append(b)
		else:
			baseline.append(b)
	if hard.is_empty():
		print("硬门控：战斗矩形内无 >40m 通视 ✓（0 对）")
	else:
		for b in hard:
			print("  硬门控违规: %s" % _fmt_pair(b))
		print("硬门控违规 %d 对 ✗（战斗矩形内不得有 >40m 通视）" % hard.size())
	# 门控 ② 基线层：仅报告，不影响 EXIT
	print("外环基线 %d 对（灰盒阶段接受，playtest 后复评；%s）" % [
		baseline.size(), BASELINE_TAG])
	for k in range(mini(BASELINE_LIST_MAX, baseline.size())):
		print("  基线[%02d]: %s" % [k + 1, _fmt_pair(baseline[k])])
	if baseline.size() > BASELINE_LIST_MAX:
		print("  …其余 %d 对省略" % (baseline.size() - BASELINE_LIST_MAX))
	quit(0 if hard.is_empty() else 1)


# 端点是否位于战斗矩形（按 x/z 判定；眼高不影响分区）
func _in_combat(p: Vector3) -> bool:
	return absf(p.x) <= COMBAT_X and absf(p.z) <= COMBAT_Z


func _fmt_pair(b: Array) -> String:
	var a: Vector3 = b[0]
	var c: Vector3 = b[1]
	return "(%.1f,%.1f,%.1f) <-> (%.1f,%.1f,%.1f)  d=%.1fm" % [
		a.x, a.y, a.z, c.x, c.y, c.z, b[2]]


# 采样点收集：网格地面点（排除眼点落入实体 AABB 的）+ 回廊 4 点 + 塔顶 2 点
func _collect_points() -> Array:
	var pts: Array[Vector3] = []
	var x := -29.0
	while x <= 29.0:
		var z := -28.0
		while z <= 28.0:
			var p := Vector3(x, EYE, z)
			if not _eye_inside_solid(p):
				pts.append(p)
			z += STEP
		x += STEP
	var grid_n := pts.size()
	pts.append(Vector3(0, CORRIDOR_EYE, 3))
	pts.append(Vector3(0, CORRIDOR_EYE, -3))
	pts.append(Vector3(3, CORRIDOR_EYE, 0))
	pts.append(Vector3(-3, CORRIDOR_EYE, 0))
	pts.append(Vector3(18.5, TOWER_EYE, 0))
	pts.append(Vector3(-18.5, TOWER_EYE, 0))
	print("PROBE_SIGHTLINES 网格点=%d（排除实体内 %d）+ 高点 6" % [
		grid_n, _grid_total() - grid_n])
	return pts


func _grid_total() -> int:
	var nx := 0
	var x := -29.0
	while x <= 29.0:
		nx += 1
		x += STEP
	var nz := 0
	var z := -28.0
	while z <= 28.0:
		nz += 1
		z += STEP
	return nx * nz


# 眼点是否落入实体数据 AABB（center ± size/2）。地面 y∈[-1,0] 不含眼高 1.7，无需特判；
# 屋顶/过梁底 ≥4.5 不含 1.7 → 其下站立点合法保留。bigtree 数据 AABB y∈[0,2.5] 与灰盒树干一致。
func _eye_inside_solid(p: Vector3) -> bool:
	for e in LAYOUT.all_solids():
		var c: Vector3 = e["center"]
		var s: Vector3 = e["size"]
		if absf(p.x - c.x) <= s.x * 0.5 and absf(p.y - c.y) <= s.y * 0.5 \
				and absf(p.z - c.z) <= s.z * 0.5:
			return true
	return false
