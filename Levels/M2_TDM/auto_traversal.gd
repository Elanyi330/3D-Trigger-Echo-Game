# Levels/M2_TDM/auto_traversal.gd —— 自动跳跃遍历器（2026-08-14）。
# 本文件分层：static 纯逻辑（本任务 T2）→ 状态机与执行循环（T3 续写）。
# 本任务只包含：类声明 + extends Node + 4 个 static 函数。禁随机、禁场景依赖
# （static 函数内不访问场景树）。
class_name AutoTraversal
extends Node

# ==================== T3：状态机与执行循环 ====================
const DATASET := preload("res://Levels/M2_TDM/jump_edges_dataset.json").data  # Dictionary
const JE := preload("res://Levels/M2_TDM/jump_edges.gd")
const LAYOUT := preload("res://Levels/M2_TDM/map_layout_v3.gd")
const WALK_ARRIVE_RADIUS := 0.8    # 途经点切换半径
const TURN_RATE := 4.0             # rad/s 转向限速（防晕）
const RUNUP_LEN := 2.5             # 助跑锚点距起跳点（沿行进反方向）
const STUCK_TIME := 5.0            # 卡死判定
const STUCK_DIST := 0.3
const JUMP_RETRIES := 3
const FALL_Y := -2.0
const NO_PATH_DIST := 0.8          # 路径末端距目标 > 此值 → no_path（部分路径判据）
const NAV_OFFSET := 0.4            # 导航面高度 ≈ 表面 + 0.4（probe_navmesh 实测口径）
const FEET_OFFSET := 0.915         # CharacterBody3D origin − 脚（与记录器同口径）
const PATH_SIMPLIFY_MIN := 1.0     # 途经点简化：与前保留点 < 此距的稠密点丢弃
const ENDPOINT_KEEP := 0.9         # 距链接端点 < 此值的路径点保留（跳跃段匹配依赖）
const VERT_KEEP := 0.2             # 与前保留点导航高度差 ≥ 此值的点保留（台阶/坡道级点——
                                    # 丢级后直线切进楼梯侧面，step-up 无法面朝台阶触发）
const STALL_TRIGGER_ALONG := 0.8   # 助跑撞墙停摆触发：距起跳点投影 ≤ 此值且贴墙 → 起跳
const TURN_STOP_ANGLE := 1.4      # rad（≈80°）：转向差超过此值 → 原地转向（防满速甩尾）
const WALL_PROBE_DIST := 0.6      # 助跑前向墙体探测距离：触墙前提前起跳（见 _runup_tick）
const SESSION_TIMEOUT := 1800.0   # 单次自动运行上限（秒）——用户拍板 2026-08-14：≤30 分钟
const TARGET_SNAP_TOL := 0.8      # 目标点 snap 先验容差（防 closest 落到邻近面，probe_navmesh 同口径）

signal attempt_finished(face: String, verdict: String)
signal progress_changed(visited: int, total: int, success: int, fail: int)
signal finished
signal timeout_paused

var active := false
var done := false
## 会话状态：idle / active / paused_timeout / done（String 状态字段）
var session_state := "idle"

enum _State { PLAN, WALK, JUMP }
enum _JumpPhase { TO_ANCHOR, RUNUP, AIR }

var _player: MovementController = null
var _record: AutoTraversalRecord = null
var _hud := Callable()
var _cmd := MovementCommand.new()
var _map_rid := RID()
var _spawn := Vector3.ZERO
var _floor_normal_y := 0.7071   # setup 时按 player.floor_max_angle 更新
var _faces_by_name := {}
var _target_faces: Array = []
var _links := []

# 目标循环
var _state: int = _State.PLAN
var _pending: Array = []      # 本轮未处理目标名（贪心重排）
var _total_targets := 0
var _processed := 0
var _target_name := ""
var _segments: Array = []
var _seg_idx := 0
var _last_path := PackedVector3Array()

# attempt
var _attempt_active := false
var _attempt_ms := 0.0
var _attempt_link := ""
var _teleported := false
var _params_used := {}

# walk / 卡死
var _stuck_origin := Vector3.ZERO
var _stuck_t := 0.0

# jump
var _jump_phase: int = _JumpPhase.TO_ANCHOR
var _from_point := Vector3.ZERO
var _to_point := Vector3.ZERO
var _from_face := ""
var _to_face := ""
var _anchor := Vector3.ZERO
var _travel_dir := Vector3.ZERO
var _jump_v := 0.0
var _jump_params := {}
var _jump_retry := 0
var _air_t := 0.0
var _air_timeout := 0.0
var _zone_rect := Rect2()
var _to_top := 0.0
var _delta_h := 0.0
var _runup_recover := 0
var _runup_t := 0.0
var _walk_replanned := false
var _jump_seg := {}

# 会话计时（active 期间累计；达上限 → 暂停）
var _session_timeout := SESSION_TIMEOUT
var _session_t := 0.0
var _dbg5 := 0


## 装配。hud: Callable 接收 {"state": str, "target": str, "action": str, "visited": int,
## "total": int, "success": int, "fail": int}（T5 接 HUD；测试可传空 Callable）。
func setup(player: MovementController, record: AutoTraversalRecord, hud: Callable) -> void:
	_player = player
	_record = record
	_hud = hud
	player.command_override = _cmd
	_spawn = LAYOUT.player_spawn()
	_map_rid = player.get_world_3d().navigation_map
	_floor_normal_y = cos(player.floor_max_angle)
	_faces_by_name = {}
	for f0 in JE.faces():
		var f: Dictionary = f0
		_faces_by_name[f["name"]] = f


## 限定目标面（测试/T5 用；不调用 = 全部 faces()）
func set_target_faces(names: Array) -> void:
	_target_faces = []
	for n0 in names:
		if not _target_faces.has(n0):
			_target_faces.append(n0)


## 启动（P 键入口，T5 调）
func start() -> void:
	if _player == null or _record == null:
		return
	if active or done:
		return
	if session_state == "paused_timeout":
		return  # 暂停后经 restart_session() 恢复，不重复启动
	active = true
	session_state = "active"
	_session_t = 0.0
	_snap_links()
	_build_queue()
	_cmd.move_axis = Vector2.ZERO
	_cmd.jump_pressed = false
	if _pending.is_empty():
		_finish_all()
		return
	_next_target()


## 单次运行上限（测试注入钩子；默认 SESSION_TIMEOUT 1800s）
func set_session_timeout(seconds: float) -> void:
	_session_timeout = maxf(seconds, 0.01)


## 超时暂停后重启：清暂停、计时归零、active=true；进度从 summary 继续
## （不清记录——per_face 保留；被 "aborted" 收尾的面视为未完成，重启后重试）
func restart_session() -> void:
	if session_state != "paused_timeout":
		return
	session_state = "active"
	active = true
	done = false
	_session_t = 0.0
	_build_queue()
	_cmd.move_axis = Vector2.ZERO
	_cmd.jump_pressed = false
	if _pending.is_empty():
		_finish_all()
		return
	_next_target()


## snap 链接缓存：LAYOUT.jump_links() 的 from/to 各做 map_get_closest_point 后缓存，
## 附 link 名与 JE.link_face_edges() 按名查得的 from_face/to_face/delta_h。
## start() 时导航已同步（T5 保证先 _snap_nav_links；冒烟测试同 probe_navmesh 等待流程）。
func _snap_links() -> void:
	_links = []
	var edge_by_link := {}
	for e0 in JE.link_face_edges():
		var e: Dictionary = e0
		edge_by_link[e["link"]] = e
	for l0 in LAYOUT.jump_links():
		var l: Dictionary = l0
		var f: Vector3 = NavigationServer3D.map_get_closest_point(_map_rid, l["from"])
		var t: Vector3 = NavigationServer3D.map_get_closest_point(_map_rid, l["to"])
		var e: Dictionary = edge_by_link.get(l["name"], {})
		_links.append({
			"name": l["name"],
			"from": f, "to": t,
			"from_face": e.get("from_face", ""),
			"to_face": e.get("to_face", ""),
			"delta_h": e.get("delta_h", 0.0),
		})


## 目标队列：未访问面（summary.per_face 无记录）∪ 目标限定；按当前路径长度贪心
## 重排（稳定排序：路径长度相等按面名字典序）。全部已访问 → 空队列 → 完成。
func _build_queue() -> void:
	var names: Array = _target_faces.duplicate()
	if names.is_empty():
		for f0 in JE.faces():
			names.append(f0["name"])
	var per_face: Dictionary = _record.summary_dict().get("per_face", {})
	_pending = []
	for n0 in names:
		var n: String = n0
		# 已访问（per_face 有记录且最新 verdict ≠ "aborted"）跳过；超时 "aborted"
		# 收尾的面视为未完成——restart_session 后重试（进度从 summary 继续，记录不清）
		var entry: Dictionary = per_face.get(n, {})
		if entry.has("verdict") and entry["verdict"] != "aborted":
			continue
		if not _faces_by_name.has(n):
			continue
		if not _pending.has(n):
			_pending.append(n)
	_total_targets = _pending.size()
	_processed = 0
	_resort_pending()


## 贪心重排剩余目标（每目标重排：路径长度相等按面名字典序——确定性无随机）
func _resort_pending() -> void:
	if _pending.is_empty():
		return
	var scored := []
	for n0 in _pending:
		var n: String = n0
		scored.append({"name": n, "len": _path_length_to(n)})
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if float(a["len"]) != float(b["len"]):
			return float(a["len"]) < float(b["len"])
		return String(a["name"]) < String(b["name"]))
	_pending = []
	for s0 in scored:
		_pending.append(s0["name"])


## 当前玩家位置到目标面的导航路径几何长度（空路径/未知面 → INF 排最后）
func _path_length_to(face_name: String) -> float:
	var face: Dictionary = _faces_by_name.get(face_name, {})
	if face.is_empty():
		return INF
	var c: Vector2 = face["center"]
	var target_point := Vector3(c.x, float(face["top_y"]) + 0.4, c.y)
	var closest := NavigationServer3D.map_get_closest_point(_map_rid, target_point)
	var path: PackedVector3Array = NavigationServer3D.map_get_path(
			_map_rid, _player.global_position, closest, true)
	if path.size() < 2:
		return INF
	var total := 0.0
	for i in range(path.size() - 1):
		total += path[i].distance_to(path[i + 1])
	return total


## 途经点简化（确定性）：与前保留点水平距 < PATH_SIMPLIFY_MIN 的稠密点丢弃，
## 但距任一链接端点（snap 后 from/to）< ENDPOINT_KEEP 的点保留（跳跃段分类
## 依赖路径点与链接端点 ≤1.0 匹配）；首尾点恒保留。目的：导航路径在墙缝/转角
## 常产出 0.1~0.5m 稠密点列，途经点切换振荡使满速行走在 2m 门洞/窄巷切角楔墙
## （实测：营地西侧门 2m 豁口在 z=25.5 楔死——简化后过门线落回门洞中线）。
func _simplify_path(path: PackedVector3Array) -> PackedVector3Array:
	if path.size() <= 2:
		return path
	var out := PackedVector3Array()
	for i in range(path.size()):
		var p: Vector3 = path[i]
		if i == 0 or i == path.size() - 1:
			out.append(p)
			continue
		var keep := false
		var last: Vector3 = out[out.size() - 1]
		if Vector2(p.x - last.x, p.z - last.z).length() >= PATH_SIMPLIFY_MIN 				or absf(p.y - last.y) >= VERT_KEEP:
			keep = true
		else:
			for l0 in _links:
				var l: Dictionary = l0
				if p.distance_to(l["from"]) <= ENDPOINT_KEEP \
						or p.distance_to(l["to"]) <= ENDPOINT_KEEP:
					keep = true
					break
		if keep:
			out.append(p)
	return out


## 取下一个目标并 PLAN：map_get_path(当前位置, 目标面中心@top_y+0.4 的 snap 点)。
## 路径末端距目标（snap 点）> NO_PATH_DIST → verdict "no_path" 记录 → 下一目标。
func _next_target() -> void:
	_resort_pending()
	if _pending.is_empty():
		_finish_all()
		return
	_target_name = _pending.pop_front()
	var face: Dictionary = _faces_by_name.get(_target_name, {})
	if face.is_empty():
		_next_target()
		return
	# 目标点回退（2026-08-14 拍板）：面中心不一定在导航面上（祭坛台面心被基座+
	# 四斜板密封成导航孤岛）——按序尝试 面中心 → 面矩形四角 → 四边中点（固定
	# 顺序确定性）；全部路径末端距目标 > NO_PATH_DIST 才判 no_path
	var plan := _plan_to_face(face)
	if plan["found"] == false:
		# no_path 无计划：清空路径/段再开 attempt——_build_plan_dict 读到的是
		# 上一目标的 _last_path/_segments，不清理 plan 字段会带旧数据
		# （T6 分析会采信，失真不可接受）
		_last_path = PackedVector3Array()
		_segments = []
		_begin_attempt("")
		_end_attempt("no_path", "路径末端距目标 %.2fm（面中心及四角/边中点均不可达）"
				% plan["best_end"])
		return
	_last_path = _simplify_path(plan["path"])
	_segments = classify_segments(_last_path, _links) if not _last_path.is_empty() else []
	_seg_idx = 0
	_begin_attempt(_first_link_name())
	_state = _State.WALK
	_reset_stuck()
	_hud_update("行走", "寻路")


## 面目标点按序寻路（确定性）：面中心 → 四角（固定顺序）→ 四边中点。
## 每个候选：先验 snap 距离 ≤ TARGET_SNAP_TOL（防 closest 落到邻近面）且
## 路径末端距 snap 点 ≤ NO_PATH_DIST → 采用；全不可达 → found=false + best_end
## （各候选路径末端距的最小值，供 no_path 失败原因）。
func _plan_to_face(face: Dictionary) -> Dictionary:
	var best_end := 999.0
	var from := _player.global_position
	for cand in _face_target_candidates(face):
		var closest := NavigationServer3D.map_get_closest_point(_map_rid, cand)
		if closest.distance_to(cand) > TARGET_SNAP_TOL:
			continue
		var path: PackedVector3Array = NavigationServer3D.map_get_path(
				_map_rid, from, closest, true)
		if path.size() < 2:
			continue
		var end_dist: float = path[path.size() - 1].distance_to(closest)
		best_end = minf(best_end, end_dist)
		if end_dist <= NO_PATH_DIST:
			return {"found": true, "path": path, "closest": closest, "best_end": best_end}
	return {"found": false, "path": PackedVector3Array(), "closest": Vector3.ZERO,
			"best_end": best_end}


## 目标候选点（固定顺序确定性）：面中心 → 四角 (+x,+z)/(−x,+z)/(+x,−z)/(−x,−z)
## → 四边中点 (+x)/(−x)/(+z)/(−z)。y 均为面顶 + 0.4（导航面高度口径）
func _face_target_candidates(face: Dictionary) -> Array:
	var c: Vector2 = face["center"]
	var sz: Vector2 = face["size"]
	var hx: float = sz.x * 0.5
	var hz: float = sz.y * 0.5
	var y: float = float(face["top_y"]) + 0.4
	return [
		Vector3(c.x, y, c.y),
		Vector3(c.x + hx, y, c.y + hz),
		Vector3(c.x - hx, y, c.y + hz),
		Vector3(c.x + hx, y, c.y - hz),
		Vector3(c.x - hx, y, c.y - hz),
		Vector3(c.x + hx, y, c.y),
		Vector3(c.x - hx, y, c.y),
		Vector3(c.x, y, c.y + hz),
		Vector3(c.x, y, c.y - hz),
	]


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


# ==================== 执行循环 ====================

## active 时驱动（每物理帧）
func _physics_process(delta: float) -> void:
	if not active or done:
		return
	if _player == null:
		return
	# 会话计时（active 期间累计）：达上限 → 暂停（进行中 attempt 按 "aborted" 收尾）
	_session_t += delta
	if _session_t >= _session_timeout:
		_pause_timeout()
		return
	# 坠落：y < FALL_Y → 传送 spawn（teleported 标记）→ verdict "fell"
	if _player.global_position.y < FALL_Y:
		_teleport_to(_spawn)
		_teleported = true
		_end_attempt("fell", "坠落出图")
		return
	if _attempt_active:
		_sample_frame(delta)
	match _state:
		_State.WALK:
			_walk_tick(delta)
		_State.JUMP:
			_jump_tick(delta)


# ---- attempt 生命周期 ----

## 开 attempt（PLAN 后）：link = 首个跳跃段的 link 名（无跳跃段 = ""）
func _begin_attempt(link: String) -> void:
	_attempt_active = true
	_attempt_ms = 0.0
	_attempt_link = link
	_teleported = false
	_params_used = {}
	_walk_replanned = false
	_record.begin_attempt(_target_name, link, _build_plan_dict())


## 首个跳跃段的 link 名（无 → ""）
func _first_link_name() -> String:
	for s0 in _segments:
		var s: Dictionary = s0
		if s["kind"] == "jump":
			return s["link"]["name"]
	return ""


## plan 序列化（JSON 安全：路径点/段表转普通数组）
func _build_plan_dict() -> Dictionary:
	if _last_path.is_empty():
		return {}  # no_path 无计划（防御：正常情况下 _next_target 已先清空）
	var pts := []
	for p in _last_path:
		pts.append([snappedf(p.x, 0.001), snappedf(p.y, 0.001), snappedf(p.z, 0.001)])
	var segs := []
	for s0 in _segments:
		var s: Dictionary = s0
		var entry := {"kind": s["kind"]}
		if s["kind"] == "jump":
			entry["link"] = s["link"]["name"]
		segs.append(entry)
	return {"target": _target_name, "path_points": pts, "segments": segs}


## 收 attempt：end_attempt + set_progress + 信号 + HUD → 下一目标
func _end_attempt(verdict: String, failure_reason: String) -> void:
	_finalize_attempt(verdict, failure_reason)
	_next_target()


## attempt 收尾落盘（不含下一目标调度——超时暂停的 "aborted" 收尾复用本函数）
func _finalize_attempt(verdict: String, failure_reason: String) -> void:
	if not _attempt_active:
		return
	_attempt_active = false
	_cmd.move_axis = Vector2.ZERO
	_cmd.jump_pressed = false
	_record.end_attempt(verdict, failure_reason, _teleported, _params_used)
	_processed += 1
	_record.set_progress(_processed, _total_targets)
	var counters: Dictionary = _record.summary_dict().get("counters", {})
	attempt_finished.emit(_target_name, verdict)
	progress_changed.emit(_processed, _total_targets,
			int(counters.get("success", 0)), int(counters.get("failed", 0)))
	_hud_update(verdict, verdict)


## 每物理帧采样（t_ms/p/v/yaw/pitch=head.rotation.x/axis/crouch=false/
## jump_held=跳跃空中阶段/on_floor/floor_name）
func _sample_frame(delta: float) -> void:
	_attempt_ms += delta * 1000.0
	var head := _player.get_node_or_null("Head") as Node3D
	var pitch := 0.0
	if head != null:
		pitch = head.rotation.x
	_record.sample_frame(
			int(round(_attempt_ms)),
			_player.global_position,
			_player.velocity,
			_player.rotation.y,
			pitch,
			_cmd.move_axis,
			false,
			_state == _State.JUMP and _jump_phase == _JumpPhase.AIR,
			_player.is_on_floor(),
			_floor_name())


## 踩踏面名（滑动碰撞法线 y ≥ cos(floor_max_angle) 的 collider.name，
## 同 JumpRecorder._find_floor_collision）
func _floor_name() -> String:
	for i in _player.get_slide_collision_count():
		var col := _player.get_slide_collision(i)
		if col.get_normal().y >= _floor_normal_y:
			var collider := col.get_collider()
			return str(collider.name) if collider else ""
	return ""


## 传送实现：global_position = spawn；velocity 清零
func _teleport_to(pos: Vector3) -> void:
	_player.global_position = pos
	_player.velocity = Vector3.ZERO


## 全部目标处理完 → done=true; active=false → finished 信号
func _finish_all() -> void:
	done = true
	active = false
	session_state = "done"
	_cmd.move_axis = Vector2.ZERO
	_hud_update("完成", "完成")
	finished.emit()


## 会话超时暂停：进行中 attempt 按 "aborted" 收尾落盘（failure_reason="30 分钟到"），
## active=false、状态 paused_timeout、发 timeout_paused + HUD（hint 供 T5 显示 R 重启）
func _pause_timeout() -> void:
	if _attempt_active:
		_finalize_attempt("aborted", "30 分钟到")
	active = false
	session_state = "paused_timeout"
	_cmd.move_axis = Vector2.ZERO
	_cmd.jump_pressed = false
	if _hud.is_valid():
		var counters: Dictionary = _record.summary_dict().get("counters", {})
		_hud.call({
			"state": "已暂停（30 分钟到）",
			"target": _target_name,
			"action": "完成",
			"visited": _processed,
			"total": _total_targets,
			"success": int(counters.get("success", 0)),
			"fail": int(counters.get("failed", 0)),
			"hint": "按 R 重启测试流程",
		})
	timeout_paused.emit()


## HUD 回调（状态/目标/动作变化时；动作 ∈ "寻路/行走/跳跃n/重试/完成"）
func _hud_update(state_str: String, action: String) -> void:
	if not _hud.is_valid():
		return
	var counters: Dictionary = _record.summary_dict().get("counters", {})
	_hud.call({
		"state": state_str,
		"target": _target_name,
		"action": action,
		"visited": _processed,
		"total": _total_targets,
		"success": int(counters.get("success", 0)),
		"fail": int(counters.get("failed", 0)),
	})


# ---- 转向 / 到达 / 卡死 ----

## 目标航向 yaw = atan2(-dir.x, -dir.z)（Godot 惯例）；TURN_RATE 限速 lerp
## 转向（返回是否已对准目标，供行进/原地转向门控）：目标航向 yaw = atan2(-dir.x, -dir.z)
## （Godot 惯例）；TURN_RATE 限速 lerp。转向差 > TURN_STOP_ANGLE → false（原地转向，
## 防满速甩尾：6.35m/s + 4rad/s 的 1.59m 转弯半径在小台面/窄巷会甩出路径切角楔墙——
## 实测：箱顶 180° 掉头甩下箱、簇板东北角楔死）
func _steer_toward(target: Vector3, delta: float) -> bool:
	var dir := target - _player.global_position
	dir.y = 0.0
	if dir.length() <= 0.001:
		return true
	var target_yaw := atan2(-dir.x, -dir.z)
	_player.rotation.y = lerp_angle(_player.rotation.y, target_yaw,
			clampf(TURN_RATE * delta, 0.0, 1.0))
	return absf(angle_difference(_player.rotation.y, target_yaw)) <= TURN_STOP_ANGLE


## 途经点到达判定：水平距 ≤ WALK_ARRIVE_RADIUS 且目标面不高于脚底 0.3 以上
## （防高台途经点被水平距离提前跳过——0.8 半径会吞掉台面高度差，导致直线转向
## 切角撞墙卡死；历史坑：EastPavilion 步道途经点）
func _arrived(target: Vector3) -> bool:
	var d := target - _player.global_position
	d.y = 0.0
	if d.length() > WALK_ARRIVE_RADIUS:
		return false
	return _waypoint_surface_y(target) - _feet_y() <= 0.3


## 途经点所在表面高度（导航面 − NAV_OFFSET）
func _waypoint_surface_y(p: Vector3) -> float:
	return p.y - NAV_OFFSET


## 玩家脚底高度（origin − 0.915）
func _feet_y() -> float:
	return _player.global_position.y - FEET_OFFSET


func _reset_stuck() -> void:
	_stuck_origin = _player.global_position
	_stuck_t = 0.0


## 卡死：STUCK_TIME 内水平位移 < STUCK_DIST（位移达标即重置窗口）
func _stuck_check(delta: float) -> bool:
	_stuck_t += delta
	var d := _player.global_position - _stuck_origin
	d.y = 0.0
	if d.length() >= STUCK_DIST:
		_stuck_origin = _player.global_position
		_stuck_t = 0.0
		return false
	return _stuck_t >= STUCK_TIME


## 攀爬辅助激活：距途经点较近且当前或下一途经点需登台。不要求贴墙——斜滑
## 在无接触段就把玩家带进台阶角缺口（实测西塔坡道：滑到 0.75m 级面贴死，
## 该级 > step-up 0.62 不可登且胶囊嵌入台阶角缺口冻结）；攀爬临近即接管，
## 按台面探测引导到可登级贴面（斜滑贴面常发生在攀爬段的前一段——需看下一途经点）
func _climb_assist_active(waypoint: Vector3) -> bool:
	if not _needs_climb(waypoint) \
			and not (_seg_idx + 1 < _segments.size()
					and _needs_climb(_segments[_seg_idx + 1]["end"])):
		return false
	var d := waypoint - _player.global_position
	d.y = 0.0
	return d.length() < 3.0


## 途经点是否需要登台（目标面高于脚底 0.3 以上）
func _needs_climb(target: Vector3) -> bool:
	return _waypoint_surface_y(target) - _feet_y() > 0.3


## 攀爬辅助（2026-08-14 修复轮）：斜向贴墙滑行会让 step-up 前向探针沿切线方向
## 永远错过台面（探针朝速度方向、台阶在墙后——实测西塔坡道东侧斜滑一路滑过
## 可登台阶、贴死在 0.75m 级面（step-up 上限 0.62 拒绝，且胶囊嵌入台阶角缺口
## 冻结）。分两档：
##   - 贴面处台面高 ≤ STEP_MAX（可登）：按墙面法线正对按压，step-up 面朝台阶触发；
##   - 台面高 > STEP_MAX（不可登）：沿墙朝上一途经点方向横移，找低端可登级。
func _climb_press(waypoint: Vector3, delta: float) -> void:
	# 按压方向 = 朝途经点水平方向（途经点必在墙后——斜滑贴面时墙面法线朝向
	# 不定，直接朝途经点按压即可面朝台阶）
	var press_dir := waypoint - _player.global_position
	press_dir.y = 0.0
	if press_dir.length() <= 0.001:
		_cmd.move_axis = Vector2.ZERO
		return
	press_dir = press_dir.normalized()
	var target := waypoint
	var feet := _feet_y()
	var top := _face_top_at(waypoint, press_dir)
	if _dbg5 < 40:
		_dbg5 += 1
		if _dbg5 % 5 == 0:
			print("DBG5 pos=(%.2f,%.2f) wp=(%.2f,%.2f) top=%.2f feet=%.2f" % [
				_player.global_position.x, _player.global_position.z,
				waypoint.x, waypoint.z, top, feet])
	if not (top < INF and top - feet <= _player.STEP_MAX):
		# 途经点贴面不可登（该级 > STEP_MAX）：沿墙面切线两侧偏移探测可登级
		# （台阶坡道的可登级在低端一侧——西塔坡道斜滑贴死教训）
		var tangent := Vector3(-press_dir.z, 0.0, press_dir.x)
		for off in [-0.7, 0.7]:
			var cand: Vector3 = waypoint + tangent * float(off)
			var t2 := _face_top_at(cand, press_dir)
			if t2 < INF and t2 - feet <= _player.STEP_MAX:
				target = cand
				break
	_cmd.move_axis = Vector2(0, 1) if _steer_toward(target, delta) else Vector2.ZERO


## 指定 xz 点的贴面台面高度探测（模拟 step-up 相位2 探针）：从该点沿按压方向
## 偏移 0.6m、抬升 STEP_MAX，向下射线取落地高度（法线合格）；无合格命中 → INF。
## 射线必须下探到脚底以下（STEP_MAX + FEET_OFFSET + 0.3）——过短会漏掉地面
## 与低台面（历史坑：1.22m 射线从 1.54 出发够不到 0 地面，全 INF）
func _face_top_at(point: Vector3, press_dir: Vector3) -> float:
	var space := _player.get_world_3d().direct_space_state
	var origin := Vector3(point.x, _feet_y(), point.z) + press_dir * 0.6 \
			+ Vector3.UP * _player.STEP_MAX
	var q := PhysicsRayQueryParameters3D.create(
			origin, origin + Vector3.DOWN * (_player.STEP_MAX + FEET_OFFSET + 0.3),
			1, [_player.get_rid()])
	var hit := space.intersect_ray(q)
	if hit.is_empty() or float(hit["normal"].y) < _floor_normal_y:
		return INF
	return float(hit["position"].y)


# ---- WALK ----

## 逐段行走（jump 段前停下进入 JUMP）：cmd.move_axis=(0,1) 前进；
## 途经点 ≤ WALK_ARRIVE_RADIUS 切换下一途经点；卡死 → verdict "stuck" → 传送 spawn
func _walk_tick(delta: float) -> void:
	if _seg_idx >= _segments.size():
		_end_attempt("success", "")
		return
	var seg: Dictionary = _segments[_seg_idx]
	if seg["kind"] == "jump" and not _seg_is_down_drop(seg):
		if _jump_already_crossed(seg):
			# 已物理站在落面上（导航链接本是绕开可走通豁口的捷径——实测：
			# TowerRampToTower_W 的 0.2m 栏板豁口被 agent 半径侵蚀断开才补的
			# 链接，玩家沿坡道南缘直接走到了塔顶）→ 跳过该链接段，不执行跳跃
			_skip_jump(seg)
			return
		_enter_jump(seg)
		return
	# 行走段（含下坠段：反向穿越上跳链接 = 自由落体下边缘——navmesh 下行本
	# 无需跳跃，起跳执行只会反跳回低处徒增卡死面）
	var waypoint: Vector3 = seg["end"]
	if _climb_assist_active(waypoint):
		_climb_press(waypoint, delta)
	else:
		_cmd.move_axis = Vector2(0, _approach_throttle(waypoint)) \
				if _steer_toward(waypoint, delta) else Vector2.ZERO
	if _arrived(waypoint):
		_seg_idx += 1
		_reset_stuck()
		return
	if _stuck_check(delta):
		# 卡死重寻路（设计文档「卡死检测重寻路」）：满速行走 + 0.8m 途经点半径
		# 在墙缝/窄巷会切角楔墙（实测：营地西侧门、簇板东北角）——从当前位置
		# 重寻一次路（每 attempt 一次，确定性有界）；重寻仍卡 → stuck 记录
		if not _walk_replanned and _replan_from_current():
			_walk_replanned = true
			_reset_stuck()
			return
		_teleport_to(_spawn)
		_teleported = true
		_end_attempt("stuck", "卡死：%.1fs 内水平位移 < %.1fm" % [STUCK_TIME, STUCK_DIST])


## 从当前位置重寻路（同一目标面）：空路径/末端仍距目标 > NO_PATH_DIST → false
func _replan_from_current() -> bool:
	var face: Dictionary = _faces_by_name.get(_target_name, {})
	if face.is_empty():
		return false
	var plan := _plan_to_face(face)
	if plan["found"] == false:
		return false
	_last_path = _simplify_path(plan["path"])
	_segments = classify_segments(_last_path, _links)
	_seg_idx = 0
	return true


## 跳过当前跳跃段（含紧邻同链接重复段）回到 WALK——用于「已物理越过豁口」
## 与「下坠段视作行走」之外的免跳路径
func _skip_jump(seg: Dictionary) -> void:
	_seg_idx += 1
	while _seg_idx < _segments.size():
		var s0: Dictionary = _segments[_seg_idx]
		if s0["kind"] == "jump" and s0["link"]["name"] == seg["link"]["name"]:
			_seg_idx += 1
			continue
		break
	_state = _State.WALK
	_reset_stuck()
	_hud_update("行走", "行走")


## 已站在该跳跃段的落面上（xz 在穿越方向 to_face 的矩形内且脚高 ≈ 面顶 ±0.3）
## → 无需跳跃。位置口径（不用踩踏面名：贴墙/行进帧滑动碰撞常为空）
func _jump_already_crossed(seg: Dictionary) -> bool:
	var link: Dictionary = seg["link"]
	var lf: Vector3 = link["from"]
	var lt: Vector3 = link["to"]
	var start_pt: Vector3 = seg["start"]
	var start_is_from: bool = start_pt.distance_to(lf) <= start_pt.distance_to(lt)
	var to_face: String = link["to_face"] if start_is_from else link["from_face"]
	if to_face.is_empty():
		return false
	var face: Dictionary = _faces_by_name.get(to_face, {})
	if face.is_empty():
		return false
	var c: Vector2 = face["center"]
	var sz: Vector2 = face["size"]
	var pos := _player.global_position
	if pos.x < c.x - sz.x * 0.5 or pos.x > c.x + sz.x * 0.5:
		return false
	if pos.z < c.y - sz.y * 0.5 or pos.z > c.y + sz.y * 0.5:
		return false
	return absf(_feet_y() - float(face["top_y"])) <= 0.3


## 该跳跃段在本穿越方向是否为下坠（drop ≤ −0.3 → 走下边缘，不执行跳跃）
func _seg_is_down_drop(seg: Dictionary) -> bool:
	var link: Dictionary = seg["link"]
	var lf: Vector3 = link["from"]
	var lt: Vector3 = link["to"]
	var start_pt: Vector3 = seg["start"]
	var start_is_from: bool = start_pt.distance_to(lf) <= start_pt.distance_to(lt)
	var drop: float = float(link["delta_h"]) if start_is_from else -float(link["delta_h"])
	return drop <= -0.3


# ---- JUMP ----

## 进入跳跃段：解析起跳/落点（路径可能反向穿链接）、落点接收区、起跳参数、
## 助跑锚点（xz 钳入 from 面矩形）与空中超时（catch_window(delta_h).t_max + 1.5s）
func _enter_jump(seg: Dictionary) -> void:
	_jump_seg = seg
	var link: Dictionary = seg["link"]
	var lf: Vector3 = link["from"]
	var lt: Vector3 = link["to"]
	var start_pt: Vector3 = seg["start"]
	var start_is_from: bool = start_pt.distance_to(lf) <= start_pt.distance_to(lt)
	_from_point = lf if start_is_from else lt
	_to_point = lt if start_is_from else lf
	_from_face = link["from_face"] if start_is_from else link["to_face"]
	_to_face = link["to_face"] if start_is_from else link["from_face"]
	_delta_h = float(link["delta_h"])
	if not start_is_from:
		_delta_h = -_delta_h
	var fface: Dictionary = _faces_by_name.get(_from_face, {})
	var tface: Dictionary = _faces_by_name.get(_to_face, {})
	_to_top = float(tface.get("top_y", 0.0))
	_zone_rect = _landing_zone_rect(_from_face, _to_face)
	# 起跳参数：edge 人类 p50（无 → 0）；v 钳入求解器可行带
	var h := Vector3(_to_point.x - _from_point.x, 0.0, _to_point.z - _from_point.z)
	var dist := h.length()
	_travel_dir = h.normalized() if dist > 0.01 else Vector3.ZERO
	var p := pick_jump_speed(_delta_h, dist, _human_p50(_from_face, _to_face))
	_jump_v = float(p["v"])
	_jump_params = {"v": snappedf(_jump_v, 0.001), "source": p["source"], "clamped": p["clamped"]}
	_jump_retry = 0
	_runup_recover = 0
	_runup_t = 0.0
	_anchor = _compute_anchor(fface)
	_air_t = 0.0
	var w := JumpSolver.catch_window(_delta_h)
	_air_timeout = float(w["t_max"]) + 1.5
	_jump_phase = _JumpPhase.TO_ANCHOR
	_state = _State.JUMP
	_reset_stuck()
	_hud_update("跳跃", "跳跃%d" % (_jump_retry + 1))


## 助跑锚点：from_point 沿行进反方向 RUNUP_LEN；xz 钳入 from 面矩形
## （JE.faces() 查 from_face；锚点在矩形外时收至最近矩形内点）；最后 snap 到导航面
## （钳制可能推到面缘/导航面外——悬空锚点不可达，snap 保证锚点必为导航位置）
func _compute_anchor(fface: Dictionary) -> Vector3:
	var anchor := _from_point - _travel_dir * RUNUP_LEN
	if fface.is_empty():
		return NavigationServer3D.map_get_closest_point(_map_rid, anchor)
	var c: Vector2 = fface["center"]
	var s: Vector2 = fface["size"]
	var hx: float = s.x * 0.5
	var hz: float = s.y * 0.5
	anchor.x = clampf(anchor.x, c.x - hx, c.x + hx)
	anchor.z = clampf(anchor.z, c.y - hz, c.y + hz)
	anchor.y = _from_point.y
	return NavigationServer3D.map_get_closest_point(_map_rid, anchor)


## 数据集边匹配：(from_face,to_face) 与 (to_face,from_face) 任一匹配 → 该边；
## 无匹配 → {}（接收区回退 1×1、human p50 = 0）
func _find_dataset_edge(from_f: String, to_f: String) -> Dictionary:
	for e0 in DATASET["edges"]:
		var e: Dictionary = e0
		if (e["from_face"] == from_f and e["to_face"] == to_f) \
				or (e["from_face"] == to_f and e["to_face"] == from_f):
			return e
	return {}


## 接收区 Rect2（xz 平面）：正向 → landing_zone；反向穿越 → takeoff_zone；
## 无数据边 → 落点 ±0.5 兜底
func _landing_zone_rect(from_f: String, to_f: String) -> Rect2:
	var e := _find_dataset_edge(from_f, to_f)
	if e.is_empty():
		return Rect2(Vector2(_to_point.x - 0.5, _to_point.z - 0.5), Vector2(1.0, 1.0))
	if e["from_face"] == from_f:
		return _zone_rect_of(e["landing_zone"])
	return _zone_rect_of(e["takeoff_zone"])


func _zone_rect_of(z: Dictionary) -> Rect2:
	var c: Dictionary = z["center"]
	var s: Dictionary = z["size"]
	return Rect2(
			Vector2(float(c["x"]) - float(s["x"]) * 0.5, float(c["z"]) - float(s["z"]) * 0.5),
			Vector2(float(s["x"]), float(s["z"])))


## 人类 p50（边无 human 数据 → 0）
func _human_p50(from_f: String, to_f: String) -> float:
	var e := _find_dataset_edge(from_f, to_f)
	if e.is_empty():
		return 0.0
	var human: Variant = e.get("human")
	if human is Dictionary:
		var ts: Variant = human.get("takeoff_speed")
		if ts is Dictionary and ts.has("p50"):
			return float(ts["p50"])
	return 0.0


## 跳跃主状态机：TO_ANCHOR（走到锚点）→ RUNUP（朝起跳点直线助跑）→ AIR（着陆判定轮询）
func _jump_tick(delta: float) -> void:
	match _jump_phase:
		_JumpPhase.TO_ANCHOR:
			# 走向锚点途中持续检测是否已站在落面上（入口检测只能看进入帧——
			# 实测：进入时仍在坡道末级，走向锚点途中跌落塔顶即已物理越过豁口）
			if _jump_already_crossed(_jump_seg):
				_skip_jump(_jump_seg)
				return
			# 以起跳速度 v 为目标的节流接近锚点（设计文档「直线加速至 v」：
			# 全速冲刺会在锚点留下 ~6.35m/s 惯性，起跳速度远超规划 v 导致飞过落点）
			_cmd.move_axis = Vector2(0, minf(_runup_throttle(),
					_approach_throttle(_anchor))) \
					if _steer_toward(_anchor, delta) else Vector2.ZERO
			if _arrived(_anchor):
				_jump_phase = _JumpPhase.RUNUP
				_runup_t = 0.0
				_reset_stuck()
			elif _stuck_check(delta):
				_teleport_to(_spawn)
				_teleported = true
				_end_attempt("stuck", "助跑锚点卡死")
		_JumpPhase.RUNUP:
			_runup_tick(delta)
		_JumpPhase.AIR:
			_air_tick(delta)


## 助跑：直线朝 from_point 前进（move_axis 幅值缩放使目标速度 = 起跳速度 v——
## 控制器 lerp 加速度收敛到 |direction|×speed，设计文档「直线加速至 v」）。
## 触发：沿 travel_dir 的水平投影到 from_point 的距离 ≤ trigger_distance(v)
## 且横向偏差 ≤0.3m → jump_pressed=true。速度不足（<0.9v）→ 补跑（过起跳点
## ≤1m 仍不足 → 传送回锚点重跑，≤3 次后按当前状态起跳）。
func _runup_tick(delta: float) -> void:
	_runup_t += delta
	# 助跑超时兜底（2026-08-14 修复轮）：残余轨道有界化——纯追踪的最小转弯圆
	# R_min = v/ω 与触发窗口重叠时可形成 0.45-0.5m 半径的稳定转圈（实测轨道
	# 位移持续重置卡死检测，RampTopToCorridor_E 水平跳 runup 38s+ 未触发）；
	# 8s 无果 → 传送回锚点重跑（3 次恢复后强制起跳兜底——无限转圈不可能）
	if _runup_t > 8.0:
		_recover_runup()
		return
	_cmd.move_axis = Vector2(0, _runup_throttle()) \
			if _steer_toward(_from_point, delta) else Vector2.ZERO
	var to_h := Vector3(_from_point.x - _player.global_position.x, 0.0,
			_from_point.z - _player.global_position.z)
	var along: float = to_h.dot(_travel_dir)  # 仅用于下方超跑恢复判定
	var height_ok: bool = _waypoint_surface_y(_from_point) - _feet_y() <= 0.3
	var hspeed := Vector2(_player.velocity.x, _player.velocity.z).length()
	# 前向墙体探测预跳：起跳点贴近障碍时（如 Crate_WN 起跳点距箱面仅 0.25m <
	# 胶囊半径 0.5），触发线不可达——等贴墙停摆起跳会把速度降为 ~0（REST 漂移
	# 补正脆弱，落点随起跳速度摆动）。探测 travel_dir 前方 0.6m 内墙体且速度
	# 已达标 → 以当前速度立即起跳（RUN 档弹道，无漂移依赖）
	if hspeed >= _jump_v * 0.9 and _wall_ahead():
		_trigger_jump()
		return
	# 撞墙停摆兜底（探测未覆盖的贴墙情形）
	if _player.is_on_wall() and along <= STALL_TRIGGER_ALONG and _runup_t >= 0.5:
		_trigger_jump()
		return
	# 触发条件（2026-08-14 修复轮改圆盘）：原沿线投影 ≤ trigger_distance 且横向
	# ≤0.3m 的线窗口位于最小转弯圆之内不可达（TURN_RATE 4 rad/s 时 R_min =
	# v/ω ≈ 0.52m > 窗口半径）→ 改为到起跳点水平距 ≤ 0.6m 的圆盘（0.6 > R_min
	# 保证收敛可达；落点接收区 1-2m 宽，横向精度无必要）。保留 height_ok、
	# 速度门与 along < -1.0 超跑恢复（along 仍按投影计算，仅用于恢复判定）
	if to_h.length() <= 0.6 and height_ok:
		if _jump_v <= 0.4 or hspeed >= _jump_v * 0.9:
			_trigger_jump()
			return
		# 速度不足：继续前跑（补跑窗口），过起跳点 1m 仍不足 → 回锚点重跑
		if along < -1.0:
			_recover_runup()
	elif _stuck_check(delta):
		_teleport_to(_spawn)
		_teleported = true
		_end_attempt("stuck", "助跑卡死")


## 前方墙体探测：从脚上 0.7m 沿 travel_dir 射 0.6m（脚上高度避开地面/台阶
## 棱线——0.25m 坡道级不触发，0.9m 箱/1.2m+ 墙触发；排除自身胶囊）
func _wall_ahead() -> bool:
	var space := _player.get_world_3d().direct_space_state
	var origin := _player.global_position
	origin.y = _feet_y() + 0.7
	var q := PhysicsRayQueryParameters3D.create(
			origin, origin + _travel_dir * WALL_PROBE_DIST, 1, [_player.get_rid()])
	return not space.intersect_ray(q).is_empty()


## 助跑节流：目标速度 = 起跳速度 v（move_axis 幅值缩放，控制器 lerp 加速
## 收敛到 |direction|×speed）；v < 0.4（近乎原地跳）→ 保底 0.25 接近起跳点
func _runup_throttle() -> float:
	# 除数 = speed × speed_modifier（2026-08-14 修复轮）：控制器 effective_speed =
	# speed×speed_modifier（武器移速倍率）——漏倍率时持枪实际极速低于规划极速，
	# 速度门（hspeed ≥ 0.9×v）物理不可达（实测持枪 hspeed 2.09 < 0.9×2.48）
	var throttle := clampf(_jump_v / maxf(_player.speed * _player.speed_modifier, 0.01),
			0.0, 1.0)
	if _jump_v < 0.4:
		throttle = maxf(throttle, 0.25)
	return throttle


## 接近节流：目标距离 / 2.0 钳 [0.25,1]——满速 + 4rad/s 限速的纯追踪在途经点
## 半径外存在稳定轨道均衡（实测：6.35m/s 绕途经点 1.21m 半径永转圈，0.8 到达
## 半径不可达）；速度随距离收缩 → 轨道半径随之收缩 → 螺旋收敛入到达半径
func _approach_throttle(target: Vector3) -> float:
	var d := target - _player.global_position
	d.y = 0.0
	return clampf(d.length() / 2.0, 0.25, 1.0)


## 补跑：传送回锚点重新助跑（≤3 次；仍不足则按当前状态起跳，防死循环）
func _recover_runup() -> void:
	_runup_recover += 1
	if _runup_recover > 3:
		_trigger_jump()
		return
	_teleport_to(_anchor)
	_teleported = true
	_reset_stuck()
	_runup_t = 0.0
	_jump_phase = _JumpPhase.RUNUP


## 起跳：jump_pressed 单帧边沿；空中保持朝落点前进
## （RUN 档天然零空中加速；REST 档 ≤3m/s 漂移——人类塔顶箱跳同款）
func _trigger_jump() -> void:
	_cmd.jump_pressed = true
	_cmd.move_axis = Vector2(0, 1)
	_jump_phase = _JumpPhase.AIR
	_air_t = 0.0


## 空中监控：landing_verdict 轮询——"success" → 该目标面 success；
## 超时（catch_window(delta_h).t_max + 1.5s）→ 重试或 "jump_timeout"；
## "fell"/落错面 → 重试或 "jump_missed"（failure_reason 注明错面名）
func _air_tick(delta: float) -> void:
	_air_t += delta
	_steer_toward(_to_point, delta)
	_cmd.move_axis = Vector2(0, 1)
	var on_floor := _player.is_on_floor()
	var floor_now := _floor_name()
	var verdict: Dictionary = landing_verdict(on_floor, floor_now,
			_player.global_position, _to_face, _zone_rect, _to_top)
	if verdict["verdict"] == "success":
		_jump_success()
		return
	if _air_t >= _air_timeout:
		_jump_fail("jump_timeout", "跳跃超时 %.1fs" % _air_timeout)
		return
	if verdict["verdict"] == "fell" or verdict["verdict"] == "wrong_face":
		_jump_fail("jump_missed", "落错面：%s" % (floor_now if on_floor else "未落地"))


## 跳跃成功：跳过该 jump 段（含紧邻的同链接重复段——导航路径在链接端点附近
## 逗留会产生连续两个同链接 jump 段，同一链接只执行一次）；落面 == 目标面 →
## 该目标面 success，否则继续走剩余段
func _jump_success() -> void:
	_seg_idx += 1
	while _seg_idx < _segments.size():
		var s: Dictionary = _segments[_seg_idx]
		if s["kind"] == "jump" and s["link"]["name"] == _current_link_name():
			_seg_idx += 1
			continue
		break
	_params_used = _jump_params.duplicate()
	_params_used["retries"] = _jump_retry
	if _to_face == _target_name:
		_end_attempt("success", "")
		return
	_state = _State.WALK
	_reset_stuck()
	_hud_update("行走", "行走")


## 当前跳跃段所属链接名（同链接重复段跳过用）
func _current_link_name() -> String:
	if _seg_idx - 1 < 0 or _seg_idx - 1 >= _segments.size():
		return ""
	var s: Dictionary = _segments[_seg_idx - 1]
	if s["kind"] != "jump":
		return ""
	return s["link"]["name"]


## 跳跃失败：≤ JUMP_RETRIES 次重试（第 2 次 v×1.05 钳 cap、第 3 次 from_point
## 沿 travel_dir 前移 0.1m；重试前传送回 anchor）；3 次失败 → 记录 → 传送 spawn
func _jump_fail(verdict: String, reason: String) -> void:
	_jump_retry += 1
	_params_used = _jump_params.duplicate()
	_params_used["retries"] = _jump_retry
	if _jump_retry >= JUMP_RETRIES:
		_teleport_to(_spawn)
		_teleported = true
		_end_attempt(verdict, reason)
		return
	if _jump_retry == 1:
		_jump_v = minf(_jump_v * 1.05, JumpSolver.SPEED_CAP)
		_jump_params = {"v": snappedf(_jump_v, 0.001),
				"source": _jump_params.get("source", ""), "clamped": true}
	elif _jump_retry == 2:
		_from_point += _travel_dir * 0.1
		_anchor = _compute_anchor(_faces_by_name.get(_from_face, {}))
	_teleport_to(_anchor)
	_teleported = true
	_reset_stuck()
	_air_t = 0.0
	_runup_recover = 0
	_runup_t = 0.0
	_jump_phase = _JumpPhase.RUNUP
	_hud_update("重试", "重试")
