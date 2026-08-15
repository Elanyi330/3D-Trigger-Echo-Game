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
const RUNUP_TURN_GATE := 0.3   # rad（≈17°）：助跑转向门——转向差超此值原地转（F8 直线助跑）
const WALL_PROBE_DIST := 0.6      # 助跑前向墙体探测距离：触墙前提前起跳（见 _runup_tick）
const SESSION_TIMEOUT := 1800.0   # 单次自动运行上限（秒）——用户拍板 2026-08-14：≤30 分钟
const TARGET_SNAP_TOL := 0.8      # 目标点 snap 先验容差（防 closest 落到邻近面，probe_navmesh 同口径）

## 遍历逻辑版本键（2026-08-15）：参与自动记录哈希——逻辑变更（链接触发/快照语义等）
## 自动作废旧记录重来（与 MovementController.MOVEMENT_REV 同铁律模式）。
## r1 = 首版（磁盘触发+最小转弯圆 bug 已修）；r2 起逻辑再变须 bump。
const TRAVERSAL_REV := "at-r7:wall-loop-liveness"

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
var _speed_gate_relaxed := false  # 小面助跑（可用助跑 <1.2m）→ 速度门 0.6v（2026-08-15 裁决 3）
var _to_anchor_max_feet := 0.0    # TO_ANCHOR 期间脚高最大值（坠落判定的假阳性防护，2026-08-15 F7-5）
var _walk_replanned := false
var _jump_seg := {}
# 行走滑墙（2026-08-15 F5）：压墙干顶是 26 卡死样本的共同机制
var _wall_press_t := 0.0          # 压墙累计计时
var _wall_press_origin := Vector3.ZERO
var _wall_follow := false         # 滑墙模式
var _wall_follow_t := 0.0
var _wall_follow_origin := Vector3.ZERO
var _wall_follow_dir := Vector3.ZERO  # 滑墙手性锁存（F8-F13 修复轮）：首帧锁存初始切向，滑墙期间保持

# 会话计时（active 期间累计；达上限 → 暂停）
var _session_timeout := SESSION_TIMEOUT
var _session_t := 0.0


## 装配。hud: Callable 接收 {"state": str, "target": str, "action": str, "visited": int,
## "total": int, "success": int, "fail": int}（T5 接 HUD；测试可传空 Callable）。
func setup(player: MovementController, record: AutoTraversalRecord, hud: Callable) -> void:
	_player = player
	_record = record
	_hud = hud
	player.command_override = _cmd
	_map_rid = player.get_world_3d().navigation_map
	# _spawn 原值（2026-08-15 F3 审查 2）：setup 在 L_M2._ready 同步调用时导航未同步，
	# map_get_closest_point 查询返回原值（非导航点）→ 快照移到 start()（P 时刻地图
	# 必已激活）——_teleport_to 的 y 补偿以导航点为基准，快照必须可靠。
	_spawn = LAYOUT.player_spawn()
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
	# _spawn 快照到导航点（2026-08-15 F3 审查 2）：start 时地图必已激活（P 时刻），
	# 此处快照才可靠——setup 在 _ready 同步调用时导航未同步（查询返回原值）。
	_spawn = NavigationServer3D.map_get_closest_point(_map_rid, _spawn)
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


## 当前玩家位置到目标面的导航路径几何长度（空路径/未知面 → INF 排最后）。
## （2026-08-15 F8-F13 修复轮）optimize=false 走廊忠实路径——optimize 拉直会切角穿墙
## （WestTowerBox 基座压墙样本：走廊走坡道北端入口上塔，拉直后直穿坡道东侧立面）
func _path_length_to(face_name: String) -> float:
	var face: Dictionary = _faces_by_name.get(face_name, {})
	if face.is_empty():
		return INF
	var c: Vector2 = face["center"]
	var target_point := Vector3(c.x, float(face["top_y"]) + 0.4, c.y)
	var closest := NavigationServer3D.map_get_closest_point(_map_rid, target_point)
	var path: PackedVector3Array = NavigationServer3D.map_get_path(
			_map_rid, _player.global_position, closest, false)
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
## （2026-08-15 F8-F13 修复轮）optimize=false 走廊忠实路径——optimize 拉直会切角穿墙
## （WestTowerBox 基座压墙样本：走廊走坡道北端入口上塔，拉直后直穿坡道东侧立面）
func _plan_to_face(face: Dictionary) -> Dictionary:
	var best_end := 999.0
	var from := _player.global_position
	for cand in _face_target_candidates(face):
		var closest := NavigationServer3D.map_get_closest_point(_map_rid, cand)
		if closest.distance_to(cand) > TARGET_SNAP_TOL:
			continue
		var path: PackedVector3Array = NavigationServer3D.map_get_path(
				_map_rid, from, closest, false)
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


## 目标航向 yaw（Godot 惯例：atan2(-dir.x, -dir.z)；F8 抽纯函数供 _steer_toward 复用与测试）
static func target_yaw(from: Vector3, to: Vector3) -> float:
	var dir := to - from
	dir.y = 0.0
	return atan2(-dir.x, -dir.z)


## 触发门控纯谓词（F9）：速度门 + 方向锥 ±25° + 近静止按路径声明放行。
## 与原 _try_trigger 差异：①方向锥 0.6 → 0.9 系数（±53°→±25°）②近静止（hspeed ≤0.5）
## 原无条件放行 → 改按 allow_near_still 参数（停摆路径传 true，墙探/圆盘传 false——
## 真实跳跃必须过速度门；F8 直线助跑保证速度门可达）。jump_v ≤ 0.4 原地跳恒放行。
static func trigger_allowed(jump_v: float, hspeed: float, v_h: Vector2, td: Vector2,
		gate_speed: float, require_heading: bool, allow_near_still: bool) -> bool:
	if jump_v <= 0.4:
		return true
	if hspeed > 0.5 and hspeed < gate_speed:
		return false
	if hspeed <= 0.5:
		return allow_near_still
	if require_heading and td.length() > 0.01 and v_h.dot(td) < 0.9 * hspeed:
		return false
	return true


## 滑墙切向（2026-08-15 F8-F13 修复轮）：到目标方向投影到墙面（减墙法向分量）；
## 投影 < 0.1（目标正穿墙后）→ 用锁存手性（latched，滑墙期间保持的初始方向——
## 防投影零点两侧翻转换向的 0.3m 滑移振荡）；锁存为零（首帧）→ 固定侧向兜底。
static func wall_follow_tangent(to_t: Vector3, wall_n: Vector3, latched: Vector3) -> Vector3:
	var tangent := to_t - wall_n * to_t.dot(wall_n)
	tangent.y = 0.0
	if tangent.length() < 0.1:
		if latched.length() > 0.01:
			return latched.normalized()
		return Vector3(wall_n.z, 0.0, -wall_n.x)
	return tangent.normalized()


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
	_reset_wall_state()  # 跨 attempt 状态泄漏洞（F7-2）
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


## 传送实现（2026-08-15 控制器裁决 1 + F3 审查 7）：目标恒为导航点 y（表面+偏移），
## 站立 origin = 表面+FEET_OFFSET（0.915）。偏移取导航面实测漂移下界 0.3：
## origin.y = 导航 y + (FEET_OFFSET − 0.3)（=+0.615）——导航面偏移实测 0.3~0.4 漂移，
## 用下界保证落地时脚 ≤ 表面（宁浮 0.1 不嵌 0.1），交给 floor-snap 沉降。
## 旧代码直接放 origin 到导航 y → 胶囊嵌体被物理推出（CrateToCluster_WN 箱顶重试后
## 掉到箱东侧地面贴墙卡死的根因）。所有调用点（spawn/anchor）均为导航点，统一走
## 本补偿；velocity 清零 + 清跳跃边沿（F3 审查 5：边沿仅落地帧被消费——空中触发后
## 重试传送会携带陈旧边沿，首个落地帧幽灵跳）。
func _teleport_to(pos: Vector3) -> void:
	_reset_wall_state()  # 跨传送状态泄漏洞（F7-2）
	_player.global_position = pos + Vector3(0.0, FEET_OFFSET - 0.3, 0.0)
	_player.velocity = Vector3.ZERO
	_cmd.jump_pressed = false


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
	var goal_yaw := target_yaw(_player.global_position, target)
	_player.rotation.y = lerp_angle(_player.rotation.y, goal_yaw,
			clampf(TURN_RATE * delta, 0.0, 1.0))
	return absf(angle_difference(_player.rotation.y, goal_yaw)) <= TURN_STOP_ANGLE


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


# ---- WALK ----

## 滑墙模式推进（2026-08-15 F5，F6 抽共享供 WALK/TO_ANCHOR 复用）：
## target = 方位基准（WALK 途经点 / TO_ANCHOR 锚点）。滑墙切向 = 到 target 的
## 方向投影到墙面（减去墙法向分量；墙法向取滑动碰撞）。注意速度方向本身仍是
## 入墙的愿望向（控制器逐帧重建速度，move_and_slide 不写回切向——F5 样本实测
## 速度非零而位移冻结），直接用它只会继续干顶。投影 ≈0（target 正穿墙后）→
## 固定侧向兜底（法向水平旋转 90°，确定性）。返回 true = 本帧滑墙接管。
## 退出语义（2026-08-15 F7-1/4）：位移恢复 >0.3m 退出并重置卡死计时；2s 超时
## 退出**不**重置卡死——冻结楔角下 press→follow 循环继续，但 _stuck_check 计时
## 持续累积，5s 后照常裁决 stuck+传送（有界性恢复）；锁存起 |Δy| > 0.5 退出
## （贴墙坠落不被滑墙掩盖）也不重置卡死。
func _wall_follow_step(target: Vector3, delta: float) -> bool:
	_wall_follow_t += delta
	if absf(_player.global_position.y - _wall_follow_origin.y) > 0.5:
		_wall_follow = false  # 垂直退出（坠落）——不重置卡死，交卡死/坠落兜底
		return false
	var follow_moved := Vector2(_player.global_position.x - _wall_follow_origin.x,
			_player.global_position.z - _wall_follow_origin.z).length()
	if follow_moved > 0.3:
		_wall_follow = false  # 位移恢复 → 退出并重置卡死计时
		_reset_stuck()
		return false
	if _wall_follow_t >= 2.0:
		_wall_follow = false  # 超时退出——不重置卡死（喂卡死计时，F7-1 有界性）
		return false
	var to_t := target - _player.global_position
	to_t.y = 0.0
	var wall_n := Vector3.ZERO
	for ci in _player.get_slide_collision_count():
		var cn := _player.get_slide_collision(ci).get_normal()
		if absf(cn.y) < 0.5:
			wall_n = cn
			break
	var tangent: Vector3 = wall_follow_tangent(to_t, wall_n, _wall_follow_dir)
	if _wall_follow_dir.length() <= 0.01 and tangent.length() > 0.01:
		_wall_follow_dir = tangent  # 首帧锁存手性
	if tangent.length() > 0.01:
		var tangent_yaw := atan2(-tangent.x, -tangent.z)
		_player.rotation.y = lerp_angle(_player.rotation.y, tangent_yaw,
				clampf(TURN_RATE * delta, 0.0, 1.0))
	return true


## 压墙检测（滑墙前置，F5/F6 共享）：压墙期间（on_wall + 命令速度 ≥0.2——F6 阈值
## 放宽：RimW_B 样本低速节流 ~0.45 贴塔坡道棱角低于 0.5 漏检）位移 ≥0.05m 即
## 刷新窗口重新计时（=在滑动，非冻结干顶）；冻结（位移 <0.05m）才累计计时，
## 0.5s 触发滑墙模式。锁存时清零 _wall_press_t（F7-1：滑墙结束后再压墙重新
## 计时，防 press→follow 循环饿死卡死检测）。
func _wall_press_detect(cmd_speed: float, delta: float) -> void:
	if _player.is_on_wall() and cmd_speed >= 0.2:
		if Vector2(_player.global_position.x - _wall_press_origin.x,
				_player.global_position.z - _wall_press_origin.z).length() >= 0.05:
			_wall_press_t = 0.0
			_wall_press_origin = _player.global_position
		else:
			_wall_press_t += delta
	else:
		_wall_press_t = 0.0
		_wall_press_origin = _player.global_position
	if _wall_press_t >= 0.5:
		_wall_follow = true
		_wall_follow_t = 0.0
		_wall_follow_origin = _player.global_position
		_wall_press_t = 0.0


## 滑墙状态生命周期重置（2026-08-15 F7-2）：跨相位/传送/attempt 的状态泄漏洞——
## _enter_jump/_jump_success/_jump_fail/_end_attempt/_teleport_to 入口调用。
func _reset_wall_state() -> void:
	_wall_follow = false
	_wall_follow_t = 0.0
	_wall_follow_origin = Vector3.ZERO
	_wall_follow_dir = Vector3.ZERO
	_wall_press_t = 0.0
	_wall_press_origin = Vector3.ZERO


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
	# 行走坠落重规划（2026-08-15 F5，F7-4 前置到滑墙之前——贴墙坠落不被滑墙
	# 掩盖）：掉下高面后旧路径失效——继续按旧路径方位会把玩家带进墙里干顶
	# （RimW_B 样本机制）。每帧检查脚低于当前段终点表面 2.0m → 从当前位置重寻路
	# （失败继续原路径交卡死兜底；每 attempt 一次有界）。
	if _feet_y() < _waypoint_surface_y(waypoint) - 2.0 and not _walk_replanned:
		if _replan_from_current():
			_walk_replanned = true
			_reset_stuck()
			return
	# 滑墙前置可达性守卫（2026-08-15 F8-F13 修复轮）：途经点面高 − 脚高 >
	# 0.72（step-up 0.62 + 容差）→ 到达判定必失败，滑墙无意义——优先重寻路绕行
	# （WestTowerBox 基座压墙振荡 + 用户 23s 箱底压墙样本同源根治；重寻路后
	# 新路径的首段为短段，不再切角穿墙）
	if _wall_follow and _waypoint_surface_y(waypoint) - _feet_y() > 0.72:
		if not _walk_replanned and _replan_from_current():
			_walk_replanned = true
			_reset_wall_state()
			_reset_stuck()
			return
		_wall_follow = false  # 重寻路不可用 → 撤滑墙回普通转向（卡死检测有界兜底）
		return
	# 行走滑墙（2026-08-15 F5/F6 共享 _wall_follow_step）：压墙干顶是 26 卡死
	# 样本的共同机制——纯方位追踪压墙只会顶着墙原地磨（位移 ~0 但速度/命令非零）。
	# 人类绕墙行为的最小实现：连续 0.5s 压墙 → 滑墙（到途经点方向投影到墙面，
	# 持续 ≤2s 或位移恢复 >0.3m 退出）。
	if _wall_follow and _wall_follow_step(waypoint, delta):
		_cmd.move_axis = Vector2(0, _approach_throttle(waypoint))
		return
	# 滑墙仅介入水平面途经点（面高−脚高 ≤ 0）：可攀台阶面（0 < 差 ≤ 0.62）的踢面
	# 是要爬的台阶不是要绕的墙——压入直走交 step-up 爬升（2026-08-15 修复 4：
	# WestTowerBox 台阶 1→2 楔死=斜向逼近时滑墙切向把 walker 沿踢面推出坡道西缘
	# 全速顶西壁；T-nav 重烘焙后坡道成直路，此病理成为冒烟主失败）
	if _waypoint_surface_y(waypoint) - _feet_y() <= 0.0:
		_wall_press_detect(Vector2(_cmd.move_axis.x, _cmd.move_axis.y).length(), delta)
	# 修复 5（2026-08-15）：可攀踢面正压转向——on_wall 且 0 < 途经点面高−脚高 ≤ 0.62
	# 时，转向对准碰撞反法向（正对踢面）而非途经点：斜向压入的切向滑移（纯物理
	# move_and_slide 碰撞切向，非滑墙逻辑）把角色沿踢面滑出坡道西缘（WestTowerBox
	# 楔死第二轮根因：x -20.85→-21.50 弹出 2.5m 宽坡道）；正对后斜切角归零、
	# step-up 垂直抬升。
	# 法向约定（2026-08-15 修复 6 符号修正）：Godot 碰撞法向=表面外法向朝玩家侧
	# （实测压踢面帧 cn=(0,0.40,-0.92) 朝玩家侧、背离踢面）——pos − cn 恒在墙内，
	# 转向对准踢面；pos + cn 会转向背离踢面（旧符号反）。
	var _riser_face := false
	if _player.is_on_wall() and _waypoint_surface_y(waypoint) - _feet_y() > 0.0 \
			and _waypoint_surface_y(waypoint) - _feet_y() <= 0.62:
		for ci in _player.get_slide_collision_count():
			var cn := _player.get_slide_collision(ci).get_normal()
			if absf(cn.y) < 0.5:
				_riser_face = true
				_cmd.move_axis = Vector2(0, _approach_throttle(waypoint)) \
						if _steer_toward(_player.global_position - cn, delta) else Vector2.ZERO
				break
	if not _riser_face:
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
	# 跳跃瞄准改接收区最近点（2026-08-15 控制器裁决 2）：链接端点距常超出可行带
	# （CrateToCluster_WN 端点 3.5m → v_req 5.385，0.9v 速度门物理不可达）——
	# _to_point 改为接收区矩形内距 _from_point 水平最近的点（y 取原 to_point.y），
	# v_req 降到 zone 近点距；空中转向/超时/落地判定口径不变。
	# 短跳守卫（zone 近点水平距 < 1.2m 不应用）：短跳端点 v_req 本就可行，zone 瞄准
	# 把 v 压低反而破坏助跑动力学——实测 Crate_WN（0.26m：v 1.26→0.42 起跳过冲落回
	# 地面）与 TowerRampToTower_W（0.72m：v 1.88→0.99 → 锚点接近转弯路径变紧贴墙
	# 楔死）两例回归。
	var zone_target: Vector3 = _zone_nearest_point(_from_point, _to_point)
	if Vector2(zone_target.x - _from_point.x, zone_target.z - _from_point.z).length() >= 1.2:
		_to_point = zone_target
	# 起跳参数：edge 人类 p50（无 → 0）；v 钳入求解器可行带
	var h := Vector3(_to_point.x - _from_point.x, 0.0, _to_point.z - _from_point.z)
	var dist := h.length()
	_travel_dir = h.normalized() if dist > 0.01 else Vector3.ZERO
	var p := pick_jump_speed(_delta_h, dist, _human_p50(_from_face, _to_face))
	_jump_v = float(p["v"])
	# 物理包络钳制（2026-08-15 审查 B-3）：速度门 hspeed ≥ 0.9v 的物理可达上限
	# = speed×mod/0.9——语料 3 条 Δh=0 边 p50 超 6.068 会系统性 miss；钳入
	# 包络后落点短缩约 5%，优于永远 miss
	_jump_v = minf(_jump_v, _player.speed * _player.speed_modifier * 0.95)
	_jump_params = {"v": snappedf(_jump_v, 0.001), "source": p["source"], "clamped": p["clamped"]}
	_jump_retry = 0
	_runup_recover = 0
	_runup_t = 0.0
	_anchor = _compute_anchor(fface)
	# 小面助跑速度门放宽（2026-08-15 控制器裁决 3 + F3 审查 4）：可用助跑 = 锚点
	# 实测水平距（先算锚点再判定——锚点才是真实助跑距离，面矩形测距被导航侵蚀/
	# 界外锚点失真）；< 1.2m → 0.9v 门在该助跑内不可达（箱顶 0.5m 助跑实测门永远
	# 达不到、冲出箱缘坠地）→ 放宽 0.6v：REST 档空中转向补足——静止跳起后空中可
	# 加速至 ~3m/s，落点近缘可达。
	_speed_gate_relaxed = Vector2(_from_point.x - _anchor.x,
			_from_point.z - _anchor.z).length() < 1.2
	_air_t = 0.0
	var w := JumpSolver.catch_window(_delta_h)
	_air_timeout = float(w["t_max"]) + 1.5
	_jump_phase = _JumpPhase.TO_ANCHOR
	_state = _State.JUMP
	_to_anchor_max_feet = _feet_y()  # 进入 TO_ANCHOR 时置当前脚高（F7-5 假阳性防护基准）
	_reset_wall_state()  # 跨相位状态泄漏洞（F7-2）
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


## 接收区矩形内距 from 水平最近的点（xz 平面钳制），y 取原 to.y——跳跃瞄准目标
## （2026-08-15 控制器裁决 2：链接端点距超出可行带时改瞄准 zone 近点）
func _zone_nearest_point(from: Vector3, to: Vector3) -> Vector3:
	var p := _zone_rect.position
	var s := _zone_rect.size
	return Vector3(clampf(from.x, p.x, p.x + s.x), to.y, clampf(from.z, p.y, p.y + s.y))


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
			# TO_ANCHOR 坠落（F6；F7-4 前置到滑墙之前——贴墙坠落不被滑墙掩盖；
			# F7-5 假阳性防护：曾到过锚点高度才判坠落——坡道低位进场/锚点 snap 到
			# 高位邻面时不误判）。坠落离锚 → 走既有重试路径（传送回锚点重跑，
			# 优于干顶卡死；3 次重试仍坠则记录）——不动锚点重算（简单方案）。
			_to_anchor_max_feet = maxf(_to_anchor_max_feet, _feet_y())
			if _to_anchor_max_feet > _waypoint_surface_y(_anchor) - 2.0 \
					and _feet_y() < _waypoint_surface_y(_anchor) - 2.0:
				_jump_fail("jump_missed", "锚点坠落")
				return
			# TO_ANCHOR 滑墙（2026-08-15 F6）：GateN_WingE「助跑锚点卡死」=
			# 坠落压墙干顶（样本①同款）——与 WALK 相同机制接入共享滑墙。
			if _wall_follow and _wall_follow_step(_anchor, delta):
				_cmd.move_axis = Vector2(0, minf(_runup_throttle(),
						_approach_throttle(_anchor)))
				return
			# 以起跳速度 v 为目标的节流接近锚点（设计文档「直线加速至 v」：
			# 全速冲刺会在锚点留下 ~6.35m/s 惯性，起跳速度远超规划 v 导致飞过落点）
			# 修复 5（2026-08-15）：可攀踢面正压转向（与 WALK 同口径；锚点面高差
			# _waypoint_surface_y(_anchor) − _feet_y()）——斜向压入的切向滑移把角色
			# 沿踢面滑出坡道西缘；正对后斜切角归零、step-up 垂直抬升
			# 法向约定（2026-08-15 修复 6 符号修正）：碰撞法向朝玩家侧（背离踢面）
			# ——pos − cn 恒在墙内、转向对准踢面（pos + cn 为旧符号反）
			var _riser_face := false
			if _player.is_on_wall() and _waypoint_surface_y(_anchor) - _feet_y() > 0.0 \
					and _waypoint_surface_y(_anchor) - _feet_y() <= 0.62:
				for ci in _player.get_slide_collision_count():
					var cn := _player.get_slide_collision(ci).get_normal()
					if absf(cn.y) < 0.5:
						_riser_face = true
						_cmd.move_axis = Vector2(0, minf(_runup_throttle(),
								_approach_throttle(_anchor))) \
								if _steer_toward(_player.global_position - cn, delta) else Vector2.ZERO
						break
			if not _riser_face:
				_cmd.move_axis = Vector2(0, minf(_runup_throttle(),
						_approach_throttle(_anchor))) \
						if _steer_toward(_anchor, delta) else Vector2.ZERO
			# 压墙检测传实际施加的指令（F7-3）：先转向再取 _cmd 幅值——与 WALK
			# 同口径；预测节流在转向帧假积累的洞
			# 滑墙仅介入水平面途经点（面高−脚高 ≤ 0）：可攀台阶面的踢面是要爬的
			# 台阶不是要绕的墙——压入直走交 step-up 爬升（2026-08-15 修复 4，
			# 与 WALK 同口径；锚点面高差口径 _waypoint_surface_y(_anchor)）
			if _waypoint_surface_y(_anchor) - _feet_y() <= 0.0:
				_wall_press_detect(Vector2(_cmd.move_axis.x, _cmd.move_axis.y).length(),
						delta)
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


## 触发路径统一门控谓词（2026-08-15 F3 审查 3）：三条触发路径（墙探预跳/停摆/圆盘）
## 共用速度门 + 方向锥。速度门：hspeed ≥ gate_speed（调用方按 relaxed 口径传
## 0.6/0.9v）；近静止（hspeed ≤ 0.5m/s，贴墙停摆场景）放行——贴墙起跳本就低速，
## REST 漂移是设计内。方向锥（require_heading）：水平速度与 travel_dir 同向
## （投影 ≥ 0.6×|v|，约 ±53°）——小面助跑从侧面触发会把起跳速度正交化
## （实测 CrateToCluster_WN 向北飞出箱顶落回地面）；近静止时方向无意义跳过。
## _jump_v ≤ 0.4（近乎原地跳）恒放行。
## F9 差异（2026-08-15）：方向锥 0.6 → 0.9（±53°→±25°）+ 近静止放行按
## allow_near_still 路径声明（停摆 true / 墙探·圆盘 false）——逻辑本体在 static
## trigger_allowed，本函数只读实例状态转发。
func _try_trigger(gate_speed: float, require_heading: bool, allow_near_still: bool) -> bool:
	var v_h := Vector2(_player.velocity.x, _player.velocity.z)
	var td := Vector2(_travel_dir.x, _travel_dir.z)
	return trigger_allowed(_jump_v, v_h.length(), v_h, td,
			gate_speed, require_heading, allow_near_still)


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
	# F8 直线助跑：转向差 ≤ RUNUP_TURN_GATE 才前进（超差 → axis=0 原地转，TURN_RATE
	# 4 rad/s 最坏 180° 转 0.78s）——消除纯追踪最小转弯圆轨道（R_min=v/ω 恒大于
	# 0.6m 触发圆盘，v>2.4 时永不收敛的 30-43s 转圈根因）
	_cmd.move_axis = Vector2(0, _runup_throttle()) \
			if absf(angle_difference(_player.rotation.y,
					target_yaw(_player.global_position, _from_point))) <= RUNUP_TURN_GATE \
			else Vector2.ZERO
	_steer_toward(_from_point, delta)
	var to_h := Vector3(_from_point.x - _player.global_position.x, 0.0,
			_from_point.z - _player.global_position.z)
	var along: float = to_h.dot(_travel_dir)  # 停摆触发判定用
	var height_ok: bool = _waypoint_surface_y(_from_point) - _feet_y() <= 0.3
	var gate_speed: float = _jump_v * (0.6 if _speed_gate_relaxed else 0.9)
	# 前向墙体探测预跳：起跳点贴近障碍时（如 Crate_WN 起跳点距箱面仅 0.25m <
	# 胶囊半径 0.5），触发线不可达——等贴墙停摆起跳会把速度降为 ~0（REST 漂移
	# 补正脆弱，落点随起跳速度摆动）。探测 travel_dir 前方 0.6m 内墙体且门控
	# 通过 → 以当前速度立即起跳（RUN 档弹道，无漂移依赖）。
	# 三路径统一门控（2026-08-15 F3 审查 3）：原速度门只盖圆盘一条路径——
	# 墙探硬编码 0.9v（relaxed 口径漏）、停摆无门（任意速度贴墙即跳）；
	# 现三路径共用 _try_trigger（速度门 + 方向锥，gate 随 relaxed 口径；
	# F9 近静止按路径声明放行：停摆 true / 墙探·圆盘 false）。
	if _try_trigger(gate_speed, true, false) and _wall_ahead():
		_trigger_jump()
		return
	# 撞墙停摆兜底（探测未覆盖的贴墙情形）：近静止（≤0.5m/s）按停摆路径声明放行
	# （F9 allow_near_still=true——贴墙起跳本就低速，REST 漂移是设计内）
	if _player.is_on_wall() and along <= STALL_TRIGGER_ALONG and _runup_t >= 0.5 \
			and _try_trigger(gate_speed, true, true):
		_trigger_jump()
		return
	# 触发条件（2026-08-14 修复轮改圆盘）：原沿线投影 ≤ trigger_distance 且横向
	# ≤0.3m 的线窗口位于最小转弯圆之内不可达（TURN_RATE 4 rad/s 时 R_min =
	# v/ω ≈ 0.52m > 窗口半径）→ 改为到起跳点水平距 ≤ 0.6m 的圆盘（0.6 > R_min
	# 保证收敛可达；落点接收区 1-2m 宽，横向精度无必要）。保留 height_ok、
	# 速度门；超跑恢复职责由 8s 超时兜底承担。
	# 近墙抑制：前方 1.0m 内有墙体时不抢跑——贴墙预跳/停摆两条先行触发
	# 处理（起跳点贴障碍的链接如 Crate_WN：圆盘 0.6 环在墙探 0.6 射程之前
	# 0.25m 抢先触发，起跳点漂移 → 落点漂移 → 下游相位破坏）
	if to_h.length() <= 0.6 and height_ok and not _wall_ahead(1.0):
		if _try_trigger(gate_speed, true, false):
			_trigger_jump()
			return
	elif _stuck_check(delta):
		_teleport_to(_spawn)
		_teleported = true
		_end_attempt("stuck", "助跑卡死")


## 前方墙体探测：从脚上 0.7m 沿 travel_dir 射 dist（默认 0.6m；脚上高度避开
## 地面/台阶棱线——0.25m 坡道级不触发，0.9m 箱/1.2m+ 墙触发；排除自身胶囊）
func _wall_ahead(dist: float = WALL_PROBE_DIST) -> bool:
	var space := _player.get_world_3d().direct_space_state
	var origin := _player.global_position
	origin.y = _feet_y() + 0.7
	var q := PhysicsRayQueryParameters3D.create(
			origin, origin + _travel_dir * dist, 1, [_player.get_rid()])
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
	_reset_wall_state()  # 跨相位状态泄漏洞（F7-2）
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
	_reset_wall_state()  # 跨相位状态泄漏洞（F7-2）
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
		# 起跳点前移后 relaxed 同步重算（F3 审查 6）：与 _enter_jump 同口径
		# （锚点实测水平距 <1.2m → 0.6v 门）——起跳点前移改变锚点距离
		_speed_gate_relaxed = Vector2(_from_point.x - _anchor.x,
				_from_point.z - _anchor.z).length() < 1.2
	_teleport_to(_anchor)
	_teleported = true
	_reset_stuck()
	_air_t = 0.0
	_runup_recover = 0
	_runup_t = 0.0
	_jump_phase = _JumpPhase.RUNUP
	_hud_update("重试", "重试")
