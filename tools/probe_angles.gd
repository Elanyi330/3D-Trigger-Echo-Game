# tools/probe_angles.gd
# v3 俯仰治理审计探针（T16，设计文档 §八.4）：可登表面 × 其压制区俯仰 ≤30°。
# 模型：守方站在面上（眼高 top_y + 1.7），攻方地面眼高 1.7 → 高差 Δh = top_y；
# 俯仰 ≤30° 的最小水平距 d_min = top_y / tan(30°)。
# 断言：① top_y ≥ 2.0 的面（Corridor/WestTower/EastTower）必须有栏板防护——
#   all_solids() 中 kind=="cover"、底面 ≈ 该面 top_y（±0.01）、整体位于面 x/z 范围内的实体 ≥3 个/面；
#   ② 全部面 d_min ≤ 6.0（设计上限——超过说明高点失控）。
# 纯数据审计（standable_surfaces/all_solids），不需要物理空间。
# 用法: godot --headless --path . -s res://tools/probe_angles.gd
extends SceneTree

const LAYOUT := preload("res://Levels/M2_TDM/map_layout_v3.gd")
const TAN30 := 0.5773502691896258  # tan(30°)
const D_MIN_CAP := 6.0
const RAIL_TOP_Y_TOL := 0.01
const RAIL_MIN_PER_FACE := 3
const HIGH_FACE := 2.0


func _initialize() -> void:
	var ok := true
	print("PROBE_ANGLES 可登表面俯仰治理审计（d_min = top_y / tan30°）")
	print("%-16s %8s %8s" % ["面", "top_y", "d_min"])
	for f in LAYOUT.standable_surfaces():
		var top_y: float = f["top_y"]
		var d_min: float = top_y / TAN30
		print("%-16s %8.2f %8.2f" % [f["name"], top_y, d_min])
		if d_min > D_MIN_CAP:
			print("  FAIL ② %s d_min=%.2f > %.1f（高点失控）" % [f["name"], d_min, D_MIN_CAP])
			ok = false
	print("")
	# 断言 ①：高面栏板防护
	for f in LAYOUT.standable_surfaces():
		var top_y: float = f["top_y"]
		if top_y < HIGH_FACE:
			continue
		var rails := _rails_for(f)
		if rails.size() < RAIL_MIN_PER_FACE:
			print("FAIL ① %s（top_y=%.1f）栏板段 %d < %d: %s" % [
				f["name"], top_y, rails.size(), RAIL_MIN_PER_FACE, str(rails)])
			ok = false
		else:
			print("OK ① %s（top_y=%.1f）栏板段 %d ≥ %d: %s" % [
				f["name"], top_y, rails.size(), RAIL_MIN_PER_FACE, str(rails)])
	print("")
	if ok:
		print("俯仰治理审计全通 ✓（d_min 上限 %.1fm；高面栏板 ≥%d 段/面）" % [D_MIN_CAP, RAIL_MIN_PER_FACE])
	else:
		print("俯仰治理审计存在违规 ✗")
	quit(0 if ok else 1)


# 面 f 的栏板段：kind=="cover"、底面（center.y - size.y/2）≈ f.top_y（±容差）、
# 且实体 AABB 整体位于面 x/z 范围内（center ± size/2，容差同号）。
func _rails_for(f: Dictionary) -> Array:
	var top_y: float = f["top_y"]
	var fc: Vector3 = f["center"]
	var fs: Vector3 = f["size"]
	var x_lo: float = fc.x - fs.x * 0.5
	var x_hi: float = fc.x + fs.x * 0.5
	var z_lo: float = fc.z - fs.z * 0.5
	var z_hi: float = fc.z + fs.z * 0.5
	var out := []
	for e in LAYOUT.all_solids():
		if e.get("kind", "cover") != "cover":
			continue
		var c: Vector3 = e["center"]
		var s: Vector3 = e["size"]
		var bottom: float = c.y - s.y * 0.5
		if absf(bottom - top_y) > RAIL_TOP_Y_TOL:
			continue
		var ex_lo: float = c.x - s.x * 0.5
		var ex_hi: float = c.x + s.x * 0.5
		var ez_lo: float = c.z - s.z * 0.5
		var ez_hi: float = c.z + s.z * 0.5
		if ex_lo >= x_lo - RAIL_TOP_Y_TOL and ex_hi <= x_hi + RAIL_TOP_Y_TOL \
				and ez_lo >= z_lo - RAIL_TOP_Y_TOL and ez_hi <= z_hi + RAIL_TOP_Y_TOL:
			out.append(e["name"])
	return out
