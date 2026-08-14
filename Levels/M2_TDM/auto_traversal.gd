# Levels/M2_TDM/auto_traversal.gd —— 自动跳跃遍历器（2026-08-14）。
# 本文件分层：static 纯逻辑（本任务 T2）→ 状态机与执行循环（T3 续写）。
# 本任务只包含：类声明 + extends Node + 4 个 static 函数。禁随机、禁场景依赖
# （static 函数内不访问场景树）。
class_name AutoTraversal
extends Node


## 路径段分类：path 相邻点对与 links 端点（已 snap 的 from/to）首尾双向匹配 ≤1.0m → 跳跃段；
## 其余为行走段。返回 [{"kind": "walk"|"jump", "start": Vector3, "end": Vector3,
## "link": Dictionary（jump 段才有）}]，按 path 顺序。确定性：按 links 顺序取首个匹配。
static func classify_segments(path: PackedVector3Array, links: Array) -> Array:
	var segments := []
	for i in range(path.size() - 1):
		var a: Vector3 = path[i]
		var b: Vector3 = path[i + 1]
		var hit := {}
		for l0 in links:
			var l: Dictionary = l0
			var f: Vector3 = l["from"]
			var t: Vector3 = l["to"]
			if (a.distance_to(f) <= 1.0 and b.distance_to(t) <= 1.0) \
					or (a.distance_to(t) <= 1.0 and b.distance_to(f) <= 1.0):
				hit = l
				break
		if hit.is_empty():
			segments.append({"kind": "walk", "start": a, "end": b})
		else:
			segments.append({"kind": "jump", "start": a, "end": b, "link": hit})
	return segments


## 起跳参数选择：human_p50（人类语料 p50 起跳速度，<=0 表示无数据）钳入求解器可行带
## [v_req, min(v_hi, cap)]（v_hi 为 INF 时上界=cap）；无人类数据 → min(v_req * 1.15, cap)。
## 返回 {"v": float, "source": "corpus"|"solver", "clamped": bool}。
## 本函数不判可行性（调用方用 feasibility 判断），仅按 v_req/v_hi 钳制；
## 窗口无解时 v_hi 可能 < v_req——此时定义返回 v=v_hi 且 clamped=true（任意输入不崩）。
static func pick_jump_speed(delta_h: float, dist: float, human_p50: float) -> Dictionary:
	var rs := JumpSolver.required_speed(delta_h, dist)
	var v_req: float = rs["v_req"]
	var v_hi: float = minf(rs["v_hi"], JumpSolver.SPEED_CAP)
	var source: String = "corpus" if human_p50 > 0.0 else "solver"
	var target: float = human_p50 if human_p50 > 0.0 else minf(v_req * 1.15, JumpSolver.SPEED_CAP)
	if v_hi < v_req:
		return {"v": v_hi, "source": source, "clamped": true}
	var v: float = clampf(target, v_req, v_hi)
	return {"v": v, "source": source, "clamped": v != target}


## 起跳触发距离：沿行进方向水平投影到起跳点的距离 ≤ 此值时触发跳（v*DT + 0.05，约 1 帧提前量）
static func trigger_distance(v: float) -> float:
	return v * JumpSolver.DT + 0.05


## 着陆判定（单帧）：on_floor 且（floor_name == to_face 或 xz 在接收区矩形内且 |脚高−top_y|≤0.2
##   —— pos 是 CharacterBody3D origin（脚+0.915），脚高 = pos.y − 0.915）→ "success"；
## 脚低于 top_y−2.0 → "fell"；on_floor 但面不对 → "wrong_face"；其余 → "pending"。
## zone_rect 为 Rect2(位置, 尺寸)（xz 平面）。判定顺序：success → fell → wrong_face → pending。
static func landing_verdict(on_floor: bool, floor_name: String, pos: Vector3,
		to_face: String, zone_rect: Rect2, top_y: float) -> Dictionary:
	var foot_y := pos.y - 0.915
	if on_floor and (floor_name == to_face
			or (zone_rect.has_point(Vector2(pos.x, pos.z)) and absf(foot_y - top_y) <= 0.2)):
		return {"verdict": "success"}
	if foot_y < top_y - 2.0:
		return {"verdict": "fell"}
	if on_floor:
		return {"verdict": "wrong_face"}
	return {"verdict": "pending"}
