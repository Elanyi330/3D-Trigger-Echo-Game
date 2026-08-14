# tools/probe_jump_edges.gd — T5 跳跃边量化验证报告工具（2026-08-14）。
# 只读消费 T2/T3/T4 产物：jump_edges.gd / jump_solver.gd / jump_edges_dataset.json。
# 三道门禁（布局哈希 / 链接覆盖 / 求解器交叉校验）全过后输出边报告表 +
# link_audit 表 + 汇总；任一门禁失败打印 FAIL 退出 1。退出码是硬契约（脚本/CI 消费）。
# 用法: godot --headless --path . -s tools/probe_jump_edges.gd
extends SceneTree

const EDGES := preload("res://Levels/M2_TDM/jump_edges.gd")
const SOLVER := preload("res://Levels/M2_TDM/jump_solver.gd")
const LAYOUT := preload("res://Levels/M2_TDM/map_layout_v3.gd")
const CORE := preload("res://Levels/M2_TDM/jump_record_core.gd")
const MC := preload("res://Player/MovementController.gd")

const DS_PATH := "res://Levels/M2_TDM/jump_edges_dataset.json"
# 门禁 B 白名单：已收敛为空（2026-08-14 删 2 改 2 后 54 条链接全数有归属）——
# from_face=="" 的链接数必须 == 0，若再现即新数据错误
const WHITELIST := []
# 门禁 C 的 v_req 相对容差（数据集 dist_zone 存 3 位小数舍入值，允许 ±1% 波动）
const VREQ_TOL := 0.01
# 汇总校准对照的理论常量（JumpSolver 离散闭合式）
const THEORY_PEAK := 1.5133   # peak_rise() 理论峰值（rise_at(24)）
const CATCH_BAND := 0.5       # 抓边带：脚可低于顶面 0.5
# verdict 严重度排序（skill 优先，再按严重度）
const SEV := {"infeasible": 3, "knife": 2, "tight": 1, "easy": 0}

var _dataset: Dictionary = {}
var _edges: Array = []
var _link_audit: Array = []
var _meta: Dictionary = {}


func _initialize() -> void:
	if not _load_dataset():
		return
	# 门禁 A：布局哈希（用户铁律二次校验——旧数据集不得被消费）
	var expected_hash := CORE.map_hash(LAYOUT.all_solids(), MC.MOVEMENT_REV)
	var ds_hash: String = _meta["map_hash"]
	if ds_hash != expected_hash:
		print("[FAIL] 门禁A 布局哈希不符——数据集与当前布局不匹配（旧数据集不得被消费）")
		print("  数据集   map_hash = %s" % ds_hash)
		print("  当前布局 map_hash = %s（MOVEMENT_REV=%s）" % [expected_hash, MC.MOVEMENT_REV])
		quit(1)
		return
	print("[通过] 门禁A 布局哈希（%s）" % ds_hash)
	# 门禁 B：链接覆盖
	if not _gate_b():
		return
	# 门禁 C：求解器交叉校验
	if not _gate_c():
		return
	_print_edge_report()
	_print_link_audit()
	_print_summary()
	print("跳跃边量化验证: 全过")
	quit(0)


func _load_dataset() -> bool:
	var f := FileAccess.open(DS_PATH, FileAccess.READ)
	if f == null:
		print("[FAIL] 数据集无法打开: %s" % DS_PATH)
		quit(1)
		return false
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
		print("[FAIL] 数据集 JSON 解析失败: %s" % DS_PATH)
		quit(1)
		return false
	_dataset = parsed
	_meta = _dataset.get("meta", {})
	_edges = _dataset.get("edges", [])
	_link_audit = _dataset.get("link_audit", [])
	print("=== 跳跃边量化验证报告（probe_jump_edges）===")
	print("数据集: %s（map_name=%s，corpus_episodes=%d）" % [
		DS_PATH, _meta.get("map_name", "?"), int(_meta.get("corpus_episodes", 0))])
	return true


## 门禁 B：link_face_edges() 与 face_edge_groups() 的链接覆盖一致性。
## 有效链接（from/to 均非空）== 54，且名集合 == 边组 link_names 合并集合（无遗漏无重复）；
## from_face=="" 链接数 == 0（白名单已收敛为空——2026-08-14 删 2 改 2，若再现即新数据错误）。
func _gate_b() -> bool:
	var links := EDGES.link_face_edges()
	var groups := EDGES.face_edge_groups()
	var valid: Array = []
	var empty_from: Array = []
	for l0 in links:
		var l: Dictionary = l0
		if l["from_face"] != "" and l["to_face"] != "":
			valid.append(l["link"])
		elif l["from_face"] == "":
			empty_from.append(l["link"])
	var problems: Array = []
	if valid.size() != 54:
		problems.append("有效链接数 %d ≠ 54（总链接 %d）" % [valid.size(), links.size()])
	if groups.size() != 54:
		problems.append("边组数 %d ≠ 54" % groups.size())
	# 名集合 == 边组 link_names 合并（无遗漏无重复）
	var group_set := {}
	var dupes: Array = []
	for g0 in groups:
		var g: Dictionary = g0
		for nm0 in g["link_names"]:
			var nm: String = nm0
			if group_set.has(nm):
				dupes.append(nm)
			group_set[nm] = true
	var valid_set := {}
	for nm0 in valid:
		valid_set[nm0] = true
	var missing: Array = []
	for nm0 in valid:
		if not group_set.has(nm0):
			missing.append(nm0)
	var extra: Array = []
	for nm in group_set:
		if not valid_set.has(nm):
			extra.append(nm)
	if dupes.size() > 0 or missing.size() > 0 or extra.size() > 0:
		problems.append("链接名集合与边组 link_names 不一致（重复 %s / 遗漏 %s / 多出 %s）" % [
			str(dupes), str(missing), str(extra)])
	# from_face=="" 链接数 == 白名单数（== 0；白名单已收敛，若再现即新数据错误）
	var wl := {}
	for w in WHITELIST:
		wl[w] = true
	var ef_set := {}
	for nm0 in empty_from:
		ef_set[nm0] = true
	var wl_diff: Array = []
	for nm in ef_set:
		if not wl.has(nm):
			wl_diff.append(nm)
	for w in wl:
		if not ef_set.has(w):
			wl_diff.append(w)
	if empty_from.size() != WHITELIST.size() or wl_diff.size() > 0:
		problems.append("from_face==\"\" 链接数不符（实际 %d 条: %s；白名单已收敛为空，若再现即新数据错误）" % [
			empty_from.size(), str(empty_from)])
	if problems.size() > 0:
		print("[FAIL] 门禁B 链接覆盖校验失败:")
		for p in problems:
			print("  - %s" % p)
		quit(1)
		return false
	print("[通过] 门禁B 链接覆盖（有效链接 54 / 白名单 0 / 边组 54，无遗漏无重复）")
	return true


## v_req 相对容差 ±1%（b 为数据集值；b≈0 时改用绝对 0.01）
func _vreq_close(a: float, b: float) -> bool:
	if absf(b) < 1e-9:
		return absf(a - b) <= VREQ_TOL
	return absf(a - b) <= VREQ_TOL * absf(b)


## 门禁 C：JumpSolver.feasibility 重算 verdict/v_req 与数据集逐条对照。
## verdict 必须逐字相等（分类值，硬门禁）；v_req 相对容差 1%。
## link_audit 的 suspicious_link 条目跳过求解校验（疑似数据错误，非物理判定）。
func _gate_c() -> bool:
	var fails: Array = []
	for e0 in _edges:
		var e: Dictionary = e0
		var f := SOLVER.feasibility(float(e["delta_h"]), float(e["dist_zone"]))
		var dv: String = e["physics"]["verdict"]
		var dvr: float = float(e["physics"]["v_req"])
		if f["verdict"] != dv:
			fails.append("edge %s→%s: 求解verdict=%s vs 数据集=%s" % [
				e["from_face"], e["to_face"], f["verdict"], dv])
		elif not _vreq_close(float(f["v_req"]), dvr):
			fails.append("edge %s→%s: 求解v_req=%.6f vs 数据集=%.3f" % [
				e["from_face"], e["to_face"], float(f["v_req"]), dvr])
	var link_checked := 0
	for l0 in _link_audit:
		var l: Dictionary = l0
		if l["verdict"] == "suspicious_link":
			continue
		link_checked += 1
		var f := SOLVER.feasibility(float(l["delta_h"]), float(l["dist_link"]))
		if f["verdict"] != l["verdict"]:
			fails.append("link %s: 求解verdict=%s vs 数据集=%s" % [
				l["link"], f["verdict"], l["verdict"]])
	if fails.size() > 0:
		print("[FAIL] 门禁C 求解器交叉校验不一致（%d 条）" % fails.size())
		for s in fails:
			print("  - %s" % s)
		quit(1)
		return false
	print("[通过] 门禁C 求解器交叉校验（edges %d 条 + link_audit %d 条，verdict 逐字一致，v_req ±1%%）" % [
		_edges.size(), link_checked])
	return true


func _sev(v: String) -> int:
	return int(SEV.get(v, 0))


## 一致性列：skill=true → ★；人类 n≥1 且 easy/tight → ✓；n≥1 且 knife/infeasible → ★技巧；n=0 → ⚠️未实证
func _consistency(e: Dictionary) -> String:
	if e["skill"]:
		return "★"
	var human: Variant = e["human"]
	if human != null and int(human["n"]) >= 1:
		var v: String = e["physics"]["verdict"]
		if v == "easy" or v == "tight":
			return "✓"
		return "★技巧"
	return "⚠️未实证"


func _edge_header() -> String:
	return "%-36s | %5s | %8s | %7s | %-10s | %5s | %10s | %8s | %4s | %s" % [
		"from→to", "Δh", "dist_zone", "v_req", "求解verdict", "人类n",
		"起跳速度p50", "抓边深度p50", "skill", "一致性"]


func _edge_row(e: Dictionary) -> String:
	var human: Variant = e["human"]
	var n := 0
	var spd := "—"
	var dep := "—"
	if human != null:
		n = int(human["n"])
		spd = "%.3f" % float(human["takeoff_speed"]["p50"])
		dep = "%.3f" % float(human["catch_depth"]["p50"])
	return "%-36s | %+5.1f | %8.3f | %7.3f | %-10s | %5d | %10s | %8s | %4s | %s" % [
		"%s→%s" % [e["from_face"], e["to_face"]],
		float(e["delta_h"]), float(e["dist_zone"]),
		float(e["physics"]["v_req"]), e["physics"]["verdict"],
		n, spd, dep,
		"是" if e["skill"] else "否",
		_consistency(e),
	]


## 边报告表：每边一行；分组打印——先 skill 边、再 infeasible 边、再其余；
## 组内按 verdict 严重度排序（infeasible > knife > tight > easy），同严重度保持数据集顺序。
func _print_edge_report() -> void:
	print("")
	print("—— 边报告表（%d 条边 = 边组数）——" % _edges.size())
	print(_edge_header())
	var skill_rows: Array = []
	var inf_rows: Array = []
	var rest_rows: Array = []
	for i in range(_edges.size()):
		var e: Dictionary = _edges[i]
		var entry := {"i": i, "sev": _sev(e["physics"]["verdict"])}
		if e["skill"]:
			skill_rows.append(entry)
		elif e["physics"]["verdict"] == "infeasible":
			inf_rows.append(entry)
		else:
			rest_rows.append(entry)
	_emit_rows(skill_rows, "  —— skill 边（%d 条）——" % skill_rows.size())
	_emit_rows(inf_rows, "  —— infeasible 边（%d 条）——" % inf_rows.size())
	_emit_rows(rest_rows, "  —— 其余边（%d 条）——" % rest_rows.size())


func _emit_rows(rows: Array, title: String) -> void:
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["sev"] != b["sev"]:
			return a["sev"] > b["sev"]
		return a["i"] < b["i"])
	print(title)
	for r0 in rows:
		var r: Dictionary = r0
		print(_edge_row(_edges[r["i"]]))


func _link_row(l: Dictionary, flag: String) -> String:
	var ff: String = l["from_face"]
	if ff == "":
		ff = "(无)"
	return "%s%-20s | %-36s | %+5.1f | %8.3f | %-14s" % [
		flag, l["link"], "%s→%s" % [ff, l["to_face"]],
		float(l["delta_h"]), float(l["dist_link"]), l["verdict"]]


func _link_suggestion(l: Dictionary) -> String:
	var nm: String = l["link"]
	if l["verdict"] == "suspicious_link":
		return "疑似数据错误待修复（白名单已收敛，若再现即新数据错误）——修复前 M4 不得消费"
	if nm.begins_with("WingToLintel"):
		return "端点 6.5m 不可执行，M4 应改走翼墙内端起跳区"
	if nm.begins_with("TowerToRim"):
		return "端点 5.522m 不可执行，M4 应从塔身起跳区出发（边组 4.134m 可执行）"
	if nm.begins_with("RimToWing"):
		return "端点 5.608m 不可执行，M4 应从环形台起跳区出发（边组 4.442m 可执行）"
	return ""


## link_audit 表：每条链接逐行；infeasible 与 suspicious_link 行首标 !! 并附一行建议
## （suspicious_link 分支保留但当前恒不触发——白名单已收敛，若再现即新数据错误）
func _print_link_audit() -> void:
	print("")
	print("—— link_audit 表（%d 条链接；!! = infeasible / 疑似数据错误）——" % _link_audit.size())
	print("   %-20s | %-36s | %5s | %8s | %-14s" % [
		"link", "from→to 面", "Δh", "dist_link", "端点verdict"])
	for l0 in _link_audit:
		var l: Dictionary = l0
		var flagged: bool = l["verdict"] == "infeasible" or l["verdict"] == "suspicious_link"
		print(_link_row(l, "!! " if flagged else "   "))
		if flagged:
			print("     ↳ 建议：%s" % _link_suggestion(l))


func _print_summary() -> void:
	print("")
	print("—— 汇总 ——")
	print("边组数: %d" % EDGES.face_edge_groups().size())
	print("edges 数: %d" % _edges.size())
	var skill_names: Array = []
	var physics_only := 0
	for e0 in _edges:
		var e: Dictionary = e0
		if e["skill"]:
			skill_names.append("%s→%s" % [e["from_face"], e["to_face"]])
		if e["human"] == null:
			physics_only += 1
	print("skill 边（%d 条）: %s" % [skill_names.size(), "、".join(skill_names)])
	print("physics_only（无人类数据边）: %d" % physics_only)
	var inf_links := 0
	for l0 in _link_audit:
		if l0["verdict"] == "infeasible":
			inf_links += 1
	print("infeasible 链接数: %d" % inf_links)
	var unlinked: Array = _dataset.get("unlinked_human_edges", [])
	print("unlinked_human_edges 数: %d（前 10）" % unlinked.size())
	for i in range(mini(unlinked.size(), 10)):
		var u: Dictionary = unlinked[i]
		print("  %-24s→%-24s n=%d" % [u["from"], u["to"], int(u["n"])])
	var cal: Dictionary = _meta.get("calibrated", {})
	var p99 := float(cal.get("peak_rise_p99", 0.0))
	var p90 := float(cal.get("catch_depth_p90", 0.0))
	print("校准常量对照:")
	print("  peak_rise_p99   = %.3f  vs 理论峰值 %.4f%s" % [
		p99, THEORY_PEAK, " ⚠️超出理论峰值" if p99 > THEORY_PEAK else " ✓带内"])
	print("  catch_depth_p90 = %.3f  vs 抓边带 %.1f%s" % [
		p90, CATCH_BAND, " ⚠️超出抓边带" if p90 > CATCH_BAND else " ✓带内"])
