# Task Brief: MM1 — MinimapCore 投影核心（纯逻辑）

> 项目：Trigger Echo（Godot 4.7.1 + GDScript + GUT）
> 工作目录：`/Users/elanyi/Projects/Trigger-Echo`（分支 feat/m1-assets，直接在此目录工作）
> 父计划：`docs/superpowers/plans/2026-08-13-m2-minimap.md`（本 brief 为该计划 MM1 的完整规格）

## 目标

小地图投影核心 `MinimapCore`（RefCounted 纯逻辑）：世界坐标 → 玩家中心旋转 2D 地图坐标（上=玩家朝向）+ 范围剔除 + 线段-圆几何裁剪。全部数学可单测。

## 数学规格（精确）

- 缩放 = `radius_px / radius_m`（默认 90/12 = 7.5 px/m）。
- 旋转：f = 玩家前向 XZ 归一（退化兜底 (0,−1)）；`cy = −f.y`、`sy = −f.x`；投影：
  `mx = (rx·cy − rz·sy)·scale`、`my = (−rx·sy − rz·cy)·scale`（rx/rz = 相对玩家位置）。
  验证例：yaw=0 世界 (0,0,−10) → 地图 (0, +75)；yaw=π/2（前向 −X）世界 (0,0,−10) → 地图 (+75, 0)。
- 实体矩形：4 角世界坐标（center ± size/2 的 (x,z) 两轴组合）**逐一投影**——yaw≠0 时世界 AABB 在地图系是旋转矩形，禁止地图系 AABB 近似。角序 (−,−),(+,−),(+,+),(−,+)（绕行闭环）。
- 剔除：`Vector2(mx,my).length() > radius_px + sqrt(hx²+hz²)`（hx=size.x/2·scale、hz=size.z/2·scale）→ 跳过实体；标志点 `length() > radius_px` → 剔除。
- 线段-圆裁剪：二次方程 `t²(d·d) + 2t(a·d) + (a·a − r²) = 0`（d=b−a，r=radius_px）；判别式<0 且起点在圆内 → 整段；否则可见子段 `[max(t1,0), min(t2,1)]`（`t_lo < t_hi` 才产出）；退化 |d|²<1e-10 且起点在圆内 → 保留。
- `SKIP_KINDS: Array = ["ground"]`。

## TDD 步骤（严格顺序）

### RED 1：新文件 `test/unit/test_minimap_core.gd`（逐字，测试先红——核心类不存在 → 全部失败）

```gdscript
# test/unit/test_minimap_core.gd
# M2 小地图核心测试（TDD RED 先行）：投影变换/矩形保形/范围剔除/线段-圆裁剪/确定性
extends GutTest

var core: MinimapCore
const SCALE := 90.0 / 12.0  # 7.5 px/m（radius_px/radius_m）


func before_each() -> void:
	core = MinimapCore.new()


func _wall(center: Vector3, size: Vector3, kind: String = "wall") -> Dictionary:
	return {"name": "W", "kind": kind, "center": center, "size": size}


# ================= 1. 投影变换 =================
func test_forward_point_projects_to_map_up() -> void:
	var ents: Array = [{"pos": Vector3(0, 0, -10), "is_enemy": true}]
	core.project(Vector3.ZERO, Vector3(0, 0, -1), [], ents)
	assert_eq(core.markers.size(), 1, "正前 10m 在 12m 半径内")
	assert_almost_eq(core.markers[0]["pos"].x, 0.0, 0.001, "正前方 x=0")
	assert_almost_eq(core.markers[0]["pos"].y, 10.0 * SCALE, 0.001, "正前方 → 地图上方 +75px")


func test_right_point_projects_to_map_right() -> void:
	var ents: Array = [{"pos": Vector3(10, 0, 0), "is_enemy": false}]
	core.project(Vector3.ZERO, Vector3(0, 0, -1), [], ents)
	assert_almost_eq(core.markers[0]["pos"].x, 10.0 * SCALE, 0.001, "右侧 → 地图 +X")
	assert_almost_eq(core.markers[0]["pos"].y, 0.0, 0.001, "右侧 y=0")


func test_yaw_rotation_keeps_forward_up() -> void:
	# yaw=π/2（面朝 -X）：世界 -Z 点是玩家右侧 → 地图 +X
	var ents: Array = [{"pos": Vector3(0, 0, -10), "is_enemy": true}]
	core.project(Vector3.ZERO, Vector3(-1, 0, 0), [], ents)
	assert_almost_eq(core.markers[0]["pos"].x, 10.0 * SCALE, 0.001, "面朝 -X 时世界 -Z → 地图 +X（右侧）")
	assert_almost_eq(core.markers[0]["pos"].y, 0.0, 0.001, "y=0")


# ================= 2. 矩形投影保形 =================
func test_rect_corners_preserve_shape() -> void:
	var solids: Array = [_wall(Vector3(0, 1, -4), Vector3(4, 2, 1))]
	core.project(Vector3.ZERO, Vector3(0, 0, -1), solids, [])
	assert_eq(core.segments.size(), 4, "矩形 4 条边")
	var xs := {}
	var ys := {}
	for s in core.segments:
		for p in [s["a"], s["b"]]:
			xs[p.x] = true
			ys[p.y] = true
	assert_eq(xs.size(), 2, "x 端点为 2 个值（±2m×7.5=±15px）")
	assert_eq(ys.size(), 2, "y 端点为 2 个值（z∈[−4.5,−3.5]→[26.25,33.75]px）")
	var sorted_x: Array = xs.keys()
	sorted_x.sort()
	assert_almost_eq(sorted_x[1] - sorted_x[0], 4.0 * SCALE, 0.001, "宽度保形 30px")
	var sorted_y: Array = ys.keys()
	sorted_y.sort()
	assert_almost_eq(sorted_y[1] - sorted_y[0], 1.0 * SCALE, 0.001, "深度保形 7.5px")


# ================= 3. 范围剔除 =================
func test_far_solid_and_marker_culled() -> void:
	var solids: Array = [_wall(Vector3(0, 1, -50), Vector3(2, 2, 2))]
	var ents: Array = [{"pos": Vector3(0, 0, -15), "is_enemy": true}]
	core.project(Vector3.ZERO, Vector3(0, 0, -1), solids, ents)
	assert_eq(core.segments.size(), 0, "50m 外实体剔除")
	assert_eq(core.markers.size(), 0, "15m > 12m 标志剔除")


func test_near_edge_kept() -> void:
	var ents: Array = [{"pos": Vector3(0, 0, -11.9), "is_enemy": true}]
	core.project(Vector3.ZERO, Vector3(0, 0, -1), [], ents)
	assert_eq(core.markers.size(), 1, "11.9m 在 12m 内保留")


# ================= 4. 线段-圆裁剪 =================
func test_spanning_wall_clipped_to_circle() -> void:
	# 贯穿地图的大墙：可见段端点恰在圆上
	var solids: Array = [_wall(Vector3(0, 1, 0), Vector3(40, 1, 40))]
	core.project(Vector3.ZERO, Vector3(0, 0, -1), solids, [])
	assert_gt(core.segments.size(), 0, "有可见段")
	for s in core.segments:
		for p in [s["a"], s["b"]]:
			assert_between(p.length(), core.radius_px - 0.5, core.radius_px + 0.5,
					"裁剪端点落在圆上（±0.5px 容差）")


func test_ground_kind_skipped() -> void:
	var solids: Array = [_wall(Vector3(0, -0.5, 0), Vector3(60, 1, 58), "ground")]
	core.project(Vector3.ZERO, Vector3(0, 0, -1), solids, [])
	assert_eq(core.segments.size(), 0, "ground 不投影")


# ================= 5. 确定性 =================
func test_deterministic_same_input_same_output() -> void:
	var solids: Array = [_wall(Vector3(0, 1, -4), Vector3(4, 2, 1)), _wall(Vector3(3, 1, 2), Vector3(2, 3, 2))]
	var ents: Array = [{"pos": Vector3(0, 0, -4), "is_enemy": true}]
	core.project(Vector3.ZERO, Vector3(0, 0, -1), solids, ents)
	var seg_a: Array = core.segments.duplicate()
	var mk_a: Array = core.markers.duplicate()
	core.project(Vector3.ZERO, Vector3(0, 0, -1), solids, ents)
	assert_eq(core.segments.size(), seg_a.size(), "段数一致")
	assert_eq(core.markers.size(), mk_a.size(), "标志数一致")
```

运行 `godot --headless --path . -s addons/gut/gut_cmdln.gd -gselect=test_minimap_core` 确认**红**（class_name MinimapCore 不存在 → 解析错误/全失败，失败原因正确）。

### GREEN：新文件 `Assets/Minimap/MinimapCore.gd`（逐字）

```gdscript
# Assets/Minimap/MinimapCore.gd
# M2 小地图投影核心（纯逻辑，RefCounted 可单测）——数据驱动蓝图投影：
#   世界坐标 → 平移（−玩家位置）→ 绕 Y 旋转（玩家朝向恒指地图上方）→ 缩放 → 圆形裁剪。
# 旋转：f=玩家前向 XZ 归一，cy=−f.y、sy=−f.x；
#   mx = (rx·cy − rz·sy)·scale，my = (−rx·sy − rz·cy)·scale（世界 -Z 前 → 地图 +Y 上）。
# 实体矩形：4 角世界坐标逐一变换（yaw≠0 时世界 AABB 在地图系是旋转矩形，非轴对齐）。
# 线段-圆裁剪：二次方程 |a+t·d|²=r² 求可见子段——渲染层只画裁剪后折线（无 shader）。
# 数值唯一来源：radius_m/radius_px 由 Minimap 节点注入；SKIP_KINDS 常量。
class_name MinimapCore
extends RefCounted

const SKIP_KINDS: Array = ["ground"]  # 底板不投影（非"组件"）

var radius_m: float = 12.0  # 地图覆盖半径（世界米；用户拍板 12m）
var radius_px: float = 90.0  # 地图半径（像素）

var segments: Array = []  # [{a: Vector2, b: Vector2}] 裁剪后可见边线段（地图局部坐标，原点=玩家）
var markers: Array = []  # [{pos: Vector2, is_enemy: bool}]


func project(player_pos: Vector3, player_forward: Vector3, solids: Array, entities: Array) -> void:
	segments.clear()
	markers.clear()
	var scale := radius_px / radius_m
	var f := Vector2(player_forward.x, player_forward.z)
	if f.length_squared() < 0.000001:
		f = Vector2(0, -1)  # 前向退化兜底（默认 -Z）
	f = f.normalized()
	var cy := -f.y
	var sy := -f.x
	for s in solids:
		var c: Vector3 = s["center"]
		var sz: Vector3 = s["size"]
		if s.get("kind", "") in SKIP_KINDS:
			continue
		var rel := c - player_pos
		var mx := (rel.x * cy - rel.z * sy) * scale
		var my := (-rel.x * sy - rel.z * cy) * scale
		var hx := sz.x * 0.5 * scale
		var hz := sz.z * 0.5 * scale
		if Vector2(mx, my).length() > radius_px + sqrt(hx * hx + hz * hz):
			continue  # 中心距 > 半径+半对角：不可能与圆相交
		var corners := PackedVector2Array()
		var sgns := [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]  # 绕行闭环角序
		for sgn in sgns:
			var rx := (c.x + sgn.x * sz.x * 0.5) - player_pos.x
			var rz := (c.z + sgn.y * sz.z * 0.5) - player_pos.z
			corners.append(Vector2((rx * cy - rz * sy) * scale, (-rx * sy - rz * cy) * scale))
		_emit_rect(corners)
	for e in entities:
		var rel_e: Vector3 = e["pos"] - player_pos
		var ex := (rel_e.x * cy - rel_e.z * sy) * scale
		var ey := (-rel_e.x * sy - rel_e.z * cy) * scale
		var p := Vector2(ex, ey)
		if p.length() <= radius_px:
			markers.append({"pos": p, "is_enemy": e["is_enemy"]})


func _emit_rect(corners: PackedVector2Array) -> void:
	for i in 4:
		_emit_segment(corners[i], corners[(i + 1) % 4])


func _emit_segment(a: Vector2, b: Vector2) -> void:
	# 线段-圆（圆心原点、半径 radius_px）求交：可见子段 = [max(t1,0), min(t2,1)]。
	# 二次方程 |a + t·d|² = r² → t²(d·d) + 2t(a·d) + (a·a − r²) = 0
	var d := b - a
	var r := radius_px
	if d.length_squared() < 1e-10:
		if a.length() <= r:
			segments.append({"a": a, "b": b})  # 退化点：在圆内保留
		return
	var c2 := a.length_squared() - r * r
	var half_b := a.dot(d)
	var disc := half_b * half_b - d.length_squared() * c2
	if disc < 0.0:
		if a.length() <= r:
			segments.append({"a": a, "b": b})  # 无交点且起点在圆内：整段可见
		return
	var sq := sqrt(disc)
	var dd := d.length_squared()
	var t1 := (-half_b - sq) / dd
	var t2 := (-half_b + sq) / dd
	var t_lo := maxf(t1, 0.0)
	var t_hi := minf(t2, 1.0)
	if t_lo < t_hi:
		segments.append({"a": a + d * t_lo, "b": a + d * t_hi})
```

注意：新目录 `Assets/Minimap/` 需创建；`Assets/` 下已有目录（Models/Viewmodel 等），放在 `Assets/Minimap/` 与其并列。

### VERIFY

`cd /Users/elanyi/Projects/Trigger-Echo && godot --headless --path . -s addons/gut/gut_cmdln.gd`
预期：**298 全绿**（290 + 8 新测试；GUT 自动发现 test_minimap_core.gd）。

常见坑：
- `s.get("kind", "")` 的默认参数用法（Dictionary.get 双参）——solid 字典必有 kind，防御取空串。
- `s["center"]` 直接下标：类型是 Vector3（GDScript 对 Variant 下标赋值给 `var c: Vector3` 会自动转换，若报错改 `var c: Vector3 = s["center"]` 显式）。
- 角序必须绕行闭环 (−,−)→(+,−)→(+,+)→(−,+)——简报用 `sgns` 数组显式固定（嵌套循环会生成对角顺序画出蝴蝶结，禁止改动）。

## 报告格式

- DONE / DONE_WITH_CONCERNS / BLOCKED
- RED 证据（新测试失败输出摘要）
- 文件与行号
- 全量统计行（Tests/Passing/Fails）
- 规格偏差说明（如有）
