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
		for sgn: Vector2 in sgns:
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
