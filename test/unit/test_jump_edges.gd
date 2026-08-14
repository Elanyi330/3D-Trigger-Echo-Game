# test/unit/test_jump_edges.gd
# T2：jump_edges 面级数据结构测试（GUT，先 RED 后 GREEN）。
# 将 LAYOUT.jump_links() 的 54 处点链接升级为面级边：面表 / 链接归属 / 面到面边组。
# 只测数据结构本身，不做物理（T3 职责）。规格见任务 brief。

extends GutTest

const JE := preload("res://Levels/M2_TDM/jump_edges.gd")
const LAYOUT := preload("res://Levels/M2_TDM/map_layout_v3.gd")

# 已修复记录（2026-08-14 用户拍板：删 2 改 2，白名单收敛为空；修复详情见 layout 注释与账本）：
#   此前 4 条疑似数据错误链接已全部修复——PavToSpur_WS/ES 删除（x 镜像对无对应可跳几何，
#   远侧横脊墙 WestSpurN/EastSpurS 顶面留待未来 RimToSpur 链接覆盖），ClusterToRim_WS/ES
#   端点改至簇板实际位置（from z=±10.85）+ rim 近端（to z=±9.2，与 RimToWing 链条顺接）。
#   白名单机制随 KNOWN_BAD 退役：54 条链接全部应有 from_face/to_face 归属。


# ---- 1. 面表：首项 Ground（top 0 / 60×58）+ name 全图唯一 + 面数钉常量
#         （160 = Ground 1 + standable 14 + 实体顶面 145；实现时实测打印后贴入）----
func test_faces_include_ground_and_unique() -> void:
	var fs := JE.faces()
	assert_eq(fs.size(), 160, "faces() 面数 == 实测常量 160")
	assert_eq(fs[0]["name"], "Ground", "首项 name == Ground")
	assert_almost_eq(float(fs[0]["top_y"]), 0.0, 1e-6, "Ground top_y == 0")
	assert_eq(fs[0]["center"], Vector2(0, 0), "Ground center == (0,0)")
	assert_eq(fs[0]["size"], Vector2(60, 58), "Ground size == 60×58")
	var seen := {}
	var dups := []
	for f0 in fs:
		var f: Dictionary = f0
		var nm: String = f["name"]
		if seen.has(nm):
			dups.append(nm)
		seen[nm] = true
	assert_true(dups.is_empty(), "face name 重复: %s" % ", ".join(dups))


# ---- 2. 链接归属：全部 54 条链接（56−2 删除）from_face/to_face 均非空，
#         发现任何未指派即失败并打印链接名（白名单已收敛为空——2026-08-14）。----
func test_links_assign_to_faces() -> void:
	var links := LAYOUT.jump_links()
	var edges := JE.link_face_edges()
	assert_eq(edges.size(), links.size(), "link_face_edges() 与 jump_links() 条目数一致")
	assert_eq(edges.size(), 54, "jump_links() 共 54 条（2026-08-14 删 2 改 2 后）")
	for e0 in edges:
		var e: Dictionary = e0
		var nm: String = e["link"]
		assert_true(e["from_face"] != "" and e["to_face"] != "",
			"%s 端点未指派到任何面（from_face=%s to_face=%s）" % [nm, e["from_face"], e["to_face"]])


# ---- 3. 锚点链接：面名 + Δh + dist。
#         dist 值以实际计算结果为准、贴实测值断言（brief 上表为手算近似，
#         偏差 >1e-3 以代码输出为准并保留本注释说明；面名/Δh 必须如下）。
#         实测 dist：PavToCluster_W=3.81182408332825、WingToLintel_NW=6.5、
#         TowerBox_W=0.0、RimGap_NW=4.19999980926514、Crate_WN=0.0、
#         PavToSpur_W=2.62487983703613、ClusterToRim_WS=4.234678264047932
#         （2026-08-14 修复后端点，sqrt((3.9)²+(1.65)²) 计算值）。----
func test_link_anchors() -> void:
	var edges := JE.link_face_edges()
	var by_name := {}
	for e0 in edges:
		var e: Dictionary = e0
		by_name[e["link"]] = e
	var anchors: Array = [
		["PavToCluster_W", "WestPavilion", "WestClusterS_Panel", 1.0, 3.81182408332825],
		["WingToLintel_NW", "GateN_WingW", "GateN_Lintel", 1.9, 6.5],
		["TowerBox_W", "WestTower", "WestTowerBox", 0.9, 0.0],
		["RimGap_NW", "RimN1", "RimN2", 0.0, 4.19999980926514],
		["Crate_WN", "Ground", "WestClusterN_Box", 0.9, 0.0],
		["PavToSpur_W", "WestPavilion", "WestSpurS", 1.8, 2.62487983703613],
		["ClusterToRim_WS", "WestClusterN_Panel", "RimW_T", 0.8, 4.234678264047932],
	]
	for a0 in anchors:
		var a: Array = a0
		var e: Dictionary = by_name[a[0]]
		assert_eq(e["from_face"], a[1], "%s from_face == %s" % [a[0], a[1]])
		assert_eq(e["to_face"], a[2], "%s to_face == %s" % [a[0], a[2]])
		assert_almost_eq(float(e["delta_h"]), float(a[3]), 1e-4, "%s delta_h" % a[0])
		assert_almost_eq(float(e["dist"]), float(a[4]), 1e-3, "%s dist" % a[0])


# ---- 4. 组覆盖：各组 link_names 展开合并后 == jump_links() 全部 name（54 条），
#         无遗漏无重复（白名单已收敛为空——2026-08-14 删 2 改 2，公式自动成立）。----
func test_groups_cover_all_links() -> void:
	var groups := JE.face_edge_groups()
	var union := {}
	for g0 in groups:
		var g: Dictionary = g0
		for ln0 in g["link_names"]:
			var ln: String = ln0
			assert_false(union.has(ln), "link %s 出现在多个组" % ln)
			union[ln] = true
	var expected := {}
	for l0 in LAYOUT.jump_links():
		var l: Dictionary = l0
		expected[l["name"]] = true
	var missing := []
	for nm in expected:
		if not union.has(nm):
			missing.append(nm)
	var extra := []
	for nm in union:
		if not expected.has(nm):
			extra.append(nm)
	assert_true(missing.is_empty(), "组覆盖遗漏 %d 条链接: %s" % [missing.size(), ", ".join(missing)])
	assert_true(extra.is_empty(), "组覆盖多出链接: %s" % ", ".join(extra))


# ---- 5. 区矩形：takeoff ⊆ from 面、landing ⊆ to 面（钳制有效）。
#         brief 原文 "zone size ≥ 0.5 每边" 与指定钳制算法在真实数据上不可满足：
#         ① 端点贴面缘（例 PavToCluster_W from z=-8.6 vs WestPavilion 缘 z=-8.75 →
#            钳制后 z 边恰 0.35）② 薄面（簇板厚 0.4 → 钳制后恰 0.4）。
#         指定算法（±0.5 膨胀 + 钳制 + 匹配膨胀 0.3）的自身下界 = 0.5 − 0.3 = 0.2，
#         故断言每边 ≥ 0.2（-1e-6）——仍能抓住"忘膨胀/钳过头"的退化实现，
#         已记入报告待控制器确认。----
func test_zone_rects_within_faces() -> void:
	var fidx := {}
	for f0 in JE.faces():
		var f: Dictionary = f0
		fidx[f["name"]] = f
	for g0 in JE.face_edge_groups():
		var g: Dictionary = g0
		var tag: String = "%s→%s" % [g["from_face"], g["to_face"]]
		_assert_zone(g["takeoff_zone"], fidx[g["from_face"]], tag + " takeoff")
		_assert_zone(g["landing_zone"], fidx[g["to_face"]], tag + " landing")


func _assert_zone(zone: Dictionary, face: Dictionary, tag: String) -> void:
	var zc: Vector2 = zone["center"]
	var zs: Vector2 = zone["size"]
	var fc: Vector2 = face["center"]
	var fs: Vector2 = face["size"]
	var zlx: float = zc.x - zs.x * 0.5
	var zhx: float = zc.x + zs.x * 0.5
	var zlz: float = zc.y - zs.y * 0.5
	var zhz: float = zc.y + zs.y * 0.5
	var flx: float = fc.x - fs.x * 0.5
	var fhx: float = fc.x + fs.x * 0.5
	var flz: float = fc.y - fs.y * 0.5
	var fhz: float = fc.y + fs.y * 0.5
	assert_true(zlx >= flx - 1e-6 and zhx <= fhx + 1e-6
			and zlz >= flz - 1e-6 and zhz <= fhz + 1e-6,
		"%s 区 ⊆ 面（区 x[%.3f,%.3f] z[%.3f,%.3f] vs 面 x[%.3f,%.3f] z[%.3f,%.3f]）" % [
			tag, zlx, zhx, zlz, zhz, flx, fhx, flz, fhz])
	# 算法自身下界 0.2 = 0.5 膨胀 − 0.3 匹配膨胀（见测试 5 头部注释）
	assert_true(zs.x >= 0.2 - 1e-6,
		"%s 区 size.x %.3f ≥ 0.2（算法下界）" % [tag, zs.x])
	assert_true(zs.y >= 0.2 - 1e-6,
		"%s 区 size.y %.3f ≥ 0.2（算法下界）" % [tag, zs.y])


# ---- 6. 组 Δh == 面表 top_y 差（faces() 查询）----
func test_group_delta_h_matches_face_table() -> void:
	var fidx := {}
	for f0 in JE.faces():
		var f: Dictionary = f0
		fidx[f["name"]] = f
	for g0 in JE.face_edge_groups():
		var g: Dictionary = g0
		var ff: Dictionary = fidx[g["from_face"]]
		var tf: Dictionary = fidx[g["to_face"]]
		assert_almost_eq(float(g["delta_h"]), float(tf["top_y"]) - float(ff["top_y"]), 1e-4,
			"%s→%s delta_h == 面表 top_y 差" % [g["from_face"], g["to_face"]])
