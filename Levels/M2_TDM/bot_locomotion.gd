# Levels/M2_TDM/bot_locomotion.gd
# M3.1 T2（2026-08-16）：bot navmesh 路径跟随层——寻路 + 途经点简化 + 前瞻转向 +
# 高度门 + 到达判定。决策层（M3.3）经 set_target 指定目标，tick 每物理帧输出
# command.move_axis（= body.command_override 同引用），bot 复用玩家物理语义零改动。
# M3.1 T3（2026-08-17）：跳跃段分类 + 参数化执行——路径过跳跃链接时一次计算
# 起跳参数（数据集 p50 经消费口径 + 求解器钳制带）并执行，无重试无传送；失败 =
# jump_failed 事件 + 该链接临时惩罚 + 重寻路一次，重寻路仍含该链接 →
# clear_target 诚实放弃（决策层 M3.3 接管换目标）。WALK 段保留 T2 原逻辑
# （高度门重寻路作为无链接路径的兜底）。
class_name BotLocomotion
extends Node

signal arrived                    # 到达目标（决策层 M3.3 消费；M3.1 仅冒烟断言）
signal jump_failed(link_name: String)  # 跳跃失败（T3 起发出；决策层 M3.3 消费）

const LAYOUT := preload("res://Levels/M2_TDM/map_layout_v3.gd")

const ARRIVE_RADIUS := 0.8        # 到达半径（水平距）
const HEIGHT_GATE := 0.72         # 途经点高差门（> 此值 → 重寻路一次 / T3 接管跳跃执行）
const SIMPLIFY_STEP := 1.0        # 途经点简化：1.0m 稠密点
const SIMPLIFY_DY := 0.2          # 途经点简化：0.2 高差保留
const LOOKAHEAD_DIST := 1.5       # 前瞻转向距离（当前点距 body < 此值 → 转向基准取下一途经点）
const REPATH_LIMIT := 2           # 高度门重寻路上限（T4 卡顿对策复用同一预算语义）
# ── T3 跳跃执行（2026-08-17 M3.1 T3）──
const RUNUP_TURN_GATE := 0.3      # rad：助跑转向门（遍历器 F8 验证值）
const RUNUP_GATE_SPEED := 4.0     # m/s：触发速度门（遍历器验证值）
const TRIGGER_CONE := 0.9         # 方向锥 cos 系数（±25°，遍历器 F9 验证值）
const JUMP_TIMEOUT := 2.5         # s：起跳→落地判定超时
const JUMP_ARRIVE := 0.8          # m：助跑到达起跳点判定半径（水平距）
const LAND_TOLERANCE := 1.5       # m：落地判定容差（距段终点水平距）
const LINK_SNAP := 0.5            # m：路径点对与链接端点匹配容差（双向距离）
const TURN_RATE := 4.0            # rad/s：RUNUP 原地转向速率（遍历器 F8 同值；brief 未列，实现自选）
const TRIGGER_TIMEOUT := 1.0      # s：TRIGGER 未触发退回 RUNUP 重对准（语义规格值）
const AIR_MIN_T := 0.2            # s：落地判定最小滞空（防帧序陈旧 is_on_floor 误判成功）
const PENALTY_FRAMES := 300       # 帧：失败链接惩罚占位（重寻路临时加权语义预留，T4 消费）

var body: CharacterBody3D         # Enemy（读 global_position / rotation.y）
var map_rid: RID                  # 导航地图 RID（L_M2 get_world_3d().navigation_map）
var command: MovementCommand      # 指向 body.command_override（同引用，勿新建）

var _path := PackedVector3Array() # 简化后的途经点队列（[0] = 当前目标途经点）
var _target := Vector3.ZERO       # 原目标（高度门重寻路用）
var _repath_count := 0            # 高度门重寻路计数（新 set_target 重置）
var _segments: Array = []         # (2026-08-17 M3.1 T3)：段分类，与 _path 点对锁步
	                              #   （_segments[i] 覆盖 _path[i]→_path[i+1]；size = 点对数）
var _links: Array = []            # (2026-08-17 M3.1 T3)：setup 预对齐链接端点表
var _penalized_links: Dictionary = {}  # (2026-08-17 M3.1 T3)：link_name → 剩余惩罚帧数
var _jump_state: Dictionary = {}  # (2026-08-17 M3.1 T3)：{} | {phase, seg, t, gate}

static var _dataset_edges: Dictionary = {}  # (2026-08-17 M3.1 T3)：link 名 → 数据集边（静态缓存）
static var _dataset_loaded := false


func setup(b: CharacterBody3D, m: RID) -> void:
	body = b
	map_rid = m
	command = b.command_override  # 同引用（Enemy._ready 恒设，T0 已固化）
	# T0 移交注记（勿改行为，2026-08-16 M3.1 T0 审查遗留）：bot 的 step-up 查询掩码
	# 为 1（Enemy._ready 中 super 先于 mask=3 赋值执行）——语义上有意设计：bot 登台
	# 探针不含 Player 层，不把玩家当地形。本层不感知该差异（只读 body 位置/朝向，
	# 不动物理），记录此约定防未来误当 bug 修复。
	# (2026-08-17 M3.1 T3)：预对齐链接端点表——LAYOUT.jump_links() 每条 {name, from,
	# to} 经 map_get_closest_point 对齐（link 注册即导航点，L_M2 F4 教训；路径点
	# 本身即导航点，对齐后 classify 可直接比对，分类保持纯函数可单测）。
	_links.clear()
	for l0 in LAYOUT.jump_links():
		var l: Dictionary = l0
		_links.append({
			"name": l["name"],
			"from": NavigationServer3D.map_get_closest_point(m, l["from"]),
			"to": NavigationServer3D.map_get_closest_point(m, l["to"]),
		})


## 寻路 + 简化（2026-08-16 M3.1 T2）：optimize=false 走廊忠实（遍历器时代教训——
## optimize 会切角，直线可能穿出走廊撞几何）。首点丢弃（含 body 自身位置）。
func _query_path(pos: Vector3) -> PackedVector3Array:
	var raw := NavigationServer3D.map_get_path(map_rid, body.global_position, pos, false)
	if raw.size() > 1:
		raw.remove_at(0)
	return simplify_path(raw)


## 指定新目标：寻路 → 简化 → 段分类 → 存 _path/_segments；重寻路预算与跳跃状态
## 归零（决策层换目标 = 新 episode，中止在途跳跃状态机）。
func set_target(pos: Vector3) -> void:
	_target = pos
	_path = _query_path(pos)
	_segments = classify_segments(_path, _links)
	_repath_count = 0
	_jump_state = {}


## 清除目标（高度门重寻路超限 / 跳跃失败重寻路仍含该链接的诚实失败；T4 卡顿
## 对策复用）。arrived 不发、jump_failed 已发（T3）——决策层 M3.3 接管换目标。
func clear_target() -> void:
	_path = PackedVector3Array()
	_segments = []
	_target = Vector3.ZERO
	_jump_state = {}


## 每物理帧推进（Enemy._physics_process 或后续 Brain 调用）：
##   跳跃状态机激活 → 优先推进（RUNUP/TRIGGER/AIR）
##   _path 空 → 站桩（move_axis ZERO）
##   到达/越过（水平距）→ 弹点（跳跃段起点不弹——跳跃状态机接管到达判定）；
##   弹空 → arrived.emit() + 站桩——先于高度门（修复轮 1 Minor 4：终点恰在高面
##     时先判到达，防高面终点永不到达）
##   当前段为 JUMP → 参数化执行（T3：一次计算起跳参数，无重试无传送）
##   高度门（navmesh 空间双锚）→ 重寻路一次（上限 REPATH_LIMIT）→ 超限诚实失败
##     （WALK 段兜底；T3 起跳跃段在高度门之前被段分类接管）
##   前瞻转向 → 输出 command.move_axis（jump/crouch 由跳跃状态机接管）
func tick(delta: float) -> void:
	if command == null or body == null:
		return
	if not _jump_state.is_empty():
		_tick_jump(delta)  # (2026-08-17 M3.1 T3)：跳跃状态机优先
		return
	if _path.is_empty():
		command.move_axis = Vector2.ZERO
		return
	# 到达/越过判定（水平距，2026-08-16 M3.1 T2）：
	#   a) 距当前途经点 < ARRIVE_RADIUS → 弹点；
	#   b) 距下一途经点 ≤ 距当前途经点（越过中点）→ 弹点——纯半径判定在前瞻转向
	#      切角处有病理：锐角弯（实测微台阶绕行 U 形弯）转向基准提前切向下一途经点，
	#      切角半径 > ARRIVE_RADIUS 时当前点永不到达、bot 绕末点转圈（600 帧卡死）。
	#      越过规则与前瞻正交（转向基准只影响输出轴，不参与弹点判定），消除该病理。
	#   循环弹点：越过中点时可能一次越过多个稠密点（≤1.0m 间距）。
	#   (2026-08-17 M3.1 T3)：跳跃段起点不弹——弹掉起点则 JUMP 段被静默消费、
	#   bot 直行穿链接缺口坠落，跳跃状态机接管其到达判定。
	while not _path.is_empty():
		if not _segments.is_empty() and _segments[0]["type"] == "JUMP":
			break
		var d_cur := Vector2(_path[0].x - body.global_position.x,
				_path[0].z - body.global_position.z).length()
		if d_cur < ARRIVE_RADIUS:
			_path.remove_at(0)
			if not _segments.is_empty():
				_segments.remove_at(0)  # 锁步弹段
			continue
		if _path.size() > 1:
			var d_next := Vector2(_path[1].x - body.global_position.x,
					_path[1].z - body.global_position.z).length()
			if d_next <= d_cur:
				_path.remove_at(0)
				if not _segments.is_empty():
					_segments.remove_at(0)
				continue
		break
	if _path.is_empty():
		arrived.emit()
		command.move_axis = Vector2.ZERO
		return
	# T3：当前段为跳跃段 → 参数化执行（2026-08-17 M3.1 T3）——替代 T2 高度门
	# 重寻路分支（跳跃链接段在高度门之前接管：链接段 navmesh 落差 ≥1.0 必触发
	# 高度门，旧口径下重寻路永远返回同一路径 → 超限站桩，跳跃执行接管该分支）
	if not _segments.is_empty() and _segments[0]["type"] == "JUMP":
		_enter_jump(_segments[0])
		return
	# 高度门（2026-08-16 M3.1 T2 修复轮 1）：navmesh 空间双锚——body 侧锚 =
	# map_get_closest_point(body 位置).y（navmesh 空间），与途经点 y（同为 navmesh
	# 空间）比较，导航面 +0.3~0.4 烘焙偏移天然抵消（见 within_height_gate 注释）。
	# 重寻路直调 _query_path（不重置计数——set_target 归零计数语义下走 set_target
	# 会让上限永不触发，无限重寻路）。
	var nav_body_y := NavigationServer3D.map_get_closest_point(
			map_rid, body.global_position).y
	if not within_height_gate(nav_body_y, _path[0]):
		if _repath_count < REPATH_LIMIT:
			_repath_count += 1
			_path = _query_path(_target)
			_segments = classify_segments(_path, _links)  # (2026-08-17 M3.1 T3)：重寻路同步重分类
		else:
			clear_target()
		command.move_axis = Vector2.ZERO
		return
	# 前瞻转向（遍历器 fix 8 教训）：当前点距 body < LOOKAHEAD_DIST 时转向基准取
	# 下一途经点——提前转，不绕最小转弯圆（软加速转向下近角切入仍在到达半径内，
	# 拐点正常弹出）。
	var next_point := _path[1] if _path.size() > 1 else _path[0]
	command.move_axis = approach_point(
			body.global_position, body.rotation.y, _path[0], next_point)


## 途经点简化（static 纯函数，2026-08-16 M3.1 T2）：输出含首尾点。
## 保留集 = 首点 + 水平方向变化拐点 + 高差显著点（y 差 ≥ SIMPLIFY_DY——坡道/台阶
## 走面信息不丢）+ 尾点；相邻保留点对间沿段线性插值补稠密点（间距 ≤ SIMPLIFY_STEP）。
## 拐点误丢的代价 = 直线切角穿出走廊（optimize=false 走廊忠实的前提），
## 故转向阈值保守（方向夹角 > ~8° 即保留）。
static func simplify_path(points: PackedVector3Array) -> PackedVector3Array:
	const CORNER_DOT := 0.99  # cos(~8°)：水平方向点积低于此值（转向角更大）即保留为拐点
	var out := PackedVector3Array()
	if points.is_empty():
		return out
	var kept: Array[int] = [0]
	for i in range(1, points.size() - 1):
		var prev := points[i - 1]
		var cur := points[i]
		var nxt := points[i + 1]
		if absf(cur.y - prev.y) >= SIMPLIFY_DY or absf(nxt.y - cur.y) >= SIMPLIFY_DY:
			kept.append(i)  # 高差显著：坡道/台阶走面信息必保留
			continue
		var dir_in := Vector3(cur.x - prev.x, 0.0, cur.z - prev.z)
		var dir_out := Vector3(nxt.x - cur.x, 0.0, nxt.z - cur.z)
		if dir_in.length() > 1e-6 and dir_out.length() > 1e-6 \
				and dir_in.normalized().dot(dir_out.normalized()) < CORNER_DOT:
			kept.append(i)  # 水平方向拐点
	kept.append(points.size() - 1)
	for k in range(kept.size() - 1):
		_emit_dense(out, points[kept[k]], points[kept[k + 1]])
	_append_unique(out, points[points.size() - 1])  # 尾点兜底（_emit_dense 已含，防浮点差）
	return out


## 段内稠密插值：a→b 间按 ⌈len/STEP⌉ 等分补点（相邻间距 ≤ SIMPLIFY_STEP），
## 端点用保留集精确值（防浮点累加漂移——保留点必精确出现在输出中）。
static func _emit_dense(out: PackedVector3Array, a: Vector3, b: Vector3) -> void:
	var seg := b - a
	var len := seg.length()
	if len < 1e-6:
		return
	var n := maxi(1, int(ceil(len / SIMPLIFY_STEP)))
	_append_unique(out, a)
	for i in range(1, n):
		_append_unique(out, a + seg * (float(i) / float(n)))
	_append_unique(out, b)


## 相邻保留段共享端点去重（上一段尾 == 下一段首）。
static func _append_unique(out: PackedVector3Array, p: Vector3) -> void:
	if out.is_empty() or out[out.size() - 1].distance_squared_to(p) > 1e-12:
		out.append(p)


## 转向基准 → 移动轴（static 纯函数，2026-08-16 M3.1 T2）。
## 前瞻转向：当前点距 body 水平距 < LOOKAHEAD_DIST → 转向基准取 next_point
## （提前转，不绕最小转弯圆）；否则取 point。
## 坐标约定（T1 教训）：世界方向 = 基准点 − body 水平投影 → 转 body 本地坐标；
## Godot 右手系 yaw 下 本地前 = -basis.z = (sin yaw, -cos yaw)（yaw=0 → -Z），
## 本地右 = basis.x = (cos yaw, -sin yaw)（yaw=0 → +X）。
## 输出 Vector2(右分量, 前分量) = command.move_axis 语义（x=左右/y=前后，T1 钉死）。
## 基准点水平距 < 0.01 → 返回 ZERO（防除零）。
static func approach_point(body_pos: Vector3, body_yaw: float,
		point: Vector3, next_point: Vector3) -> Vector2:
	var ref := point
	if Vector2(point.x - body_pos.x, point.z - body_pos.z).length() < LOOKAHEAD_DIST:
		ref = next_point
	var dir := Vector3(ref.x - body_pos.x, 0.0, ref.z - body_pos.z)
	if dir.length() < 0.01:
		return Vector2.ZERO
	var d2 := Vector2(dir.x, dir.z).normalized()
	var rt := Vector2(cos(body_yaw), -sin(body_yaw))   # 本地右 = basis.x（xz 投影）
	var fw := Vector2(sin(body_yaw), -cos(body_yaw))   # 本地前 = -basis.z（xz 投影）
	return Vector2(d2.dot(rt), d2.dot(fw))


## 高度门（static 纯函数，2026-08-16 M3.1 T2 修复轮 1：navmesh 空间双锚比较）。
## nav_body_y = body 位置最近导航点 y（map_get_closest_point，navmesh 空间；由 tick
## 查询传入），point = 途经点（本身即 navmesh 空间 y）——两端同空间，导航面
## +0.3~0.4 烘焙偏移天然抵消，差值为真实可走升程：0.6m 台阶面（navmesh 1.0）对
## 地面（navmesh 0.4）量出 0.6 ≤ 0.72 放行；跳跃链接段落差 ≥1.0 正确触发。
## 旧口径（途经点 y − body 物理 y）把偏移计入门值——0.6 台面误判跳跃段 → 重寻路
## 超限站桩（审查者 v4 实证停摆）。
## 选型注记：map 查询留 tick 实例侧，本函数保持 static 纯（可脱离场景单测，边界
## 断言直测）——"static 纯函数优先"取可单测最简方案。float32 边界 workaround 保留：
## Vector3 分量 32 位存储，0.72 舍入 0.72000003 与双精度直比误拒边界（GDScript
## float() 为 64 位恒等转换、无 float32 构造器），门值经 Vector3 存储口径取整再比较。
static func within_height_gate(nav_body_y: float, point: Vector3) -> bool:
	return point.y - nav_body_y <= Vector3(0, HEIGHT_GATE, 0).y


# ── T3：跳跃段分类 + 参数化执行（2026-08-17 M3.1 T3）──

## 段分类（static 纯函数，2026-08-17 M3.1 T3）：相邻路径点对与 links 端点（setup
## 时经 map_get_closest_point 对齐——link 注册即导航点，L_M2 F4 教训；路径点本身
## 即导航点，对齐后可直接比对，分类保持纯函数可单测）双向距离 < LINK_SNAP 即
## JUMP 段（链接双向注册，from→to 与 to→from 均须匹配）。返回与点对锁步的段表
## [{type:"WALK"|"JUMP", from, to, link_name?}]（size = points.size() − 1）。
## 确定性：按 links 顺序取首个匹配。
static func classify_segments(points: PackedVector3Array, links: Array) -> Array:
	var out: Array = []
	for i in range(points.size() - 1):
		var a: Vector3 = points[i]
		var b: Vector3 = points[i + 1]
		var link_name := ""
		for l0 in links:
			var l: Dictionary = l0
			var lf: Vector3 = l["from"]
			var lt: Vector3 = l["to"]
			if (a.distance_to(lf) < LINK_SNAP and b.distance_to(lt) < LINK_SNAP) \
					or (a.distance_to(lt) < LINK_SNAP and b.distance_to(lf) < LINK_SNAP):
				link_name = str(l["name"])
				break
		if link_name != "":
			out.append({"type": "JUMP", "from": a, "to": b, "link_name": link_name})
		else:
			out.append({"type": "WALK", "from": a, "to": b})
	return out


## 起跳速度（static 纯函数，2026-08-17 M3.1 T3；消费口径 = 设计 §4.6 拍板哲学）：
##   真实人类 p50（augmented=false 且 human 非空）→ 原值
##   增强样本 p50（augmented=true）→ p50 × 0.9（置信折扣）
##   无人类数据（human_p50 传入 NAN）→ v_req × 1.15
## 最终钳制：clamp(v, r.v_req, r.v_hi)——r = JumpSolver.required_speed(delta_h,
## dist)（v_hi 可为 INF，clamp 对 INF 上界安全）；r.ok=false → 返回 v_req×1.15
## 且调用方不触发跳跃（诚实失败）。注意：feasibility 返回键为
## {ok, verdict, v_req, margin}（无 v_min/v_max）。
static func pick_jump_speed(delta_h: float, dist: float, human_p50: float,
		augmented: bool, v_req: float) -> float:
	var r: Dictionary = JumpSolver.required_speed(delta_h, dist)
	if not r.ok:
		return v_req * 1.15
	var v: float
	if is_nan(human_p50):
		v = v_req * 1.15
	elif augmented:
		v = human_p50 * 0.9
	else:
		v = human_p50
	return clampf(v, float(r["v_req"]), float(r["v_hi"]))


## 数据集静态缓存（2026-08-17 M3.1 T3）：首次使用时读
## res://Levels/M2_TDM/jump_edges_dataset.json → 遍历 edges 数组按 link_names
## 逐名建索引（key = link 名 → edge 条目）。只读资源缺失仅回退默认门（不打断寻路）。
static func _ensure_dataset() -> Dictionary:
	if not _dataset_loaded:
		_dataset_loaded = true
		var text := FileAccess.get_file_as_string(
				"res://Levels/M2_TDM/jump_edges_dataset.json")
		if text != "":
			var parsed: Variant = JSON.parse_string(text)
			if parsed is Dictionary:
				for e0 in parsed.get("edges", []):
					var e: Dictionary = e0
					for ln0 in e.get("link_names", []):
						_dataset_edges[str(ln0)] = e
	return _dataset_edges


# ── 跳跃状态机（2026-08-17 M3.1 T3）──

## 跳跃状态机分派：RUNUP（直线助跑，转向门内才前进）→ TRIGGER（速度门 +
## 方向锥，单帧边沿触发 jump_pressed）→ AIR（沿段方向微调，落地成败判定）。
## 一次参数化执行——不重试不传送；失败走 _on_jump_failed。
func _tick_jump(delta: float) -> void:
	var phase: String = _jump_state["phase"]
	if phase == "RUNUP":
		_tick_runup(delta)
	elif phase == "TRIGGER":
		_tick_trigger(delta)
	else:
		_tick_air(delta)


## RUNUP：朝段起点直线助跑——转向差 ≤ RUNUP_TURN_GATE 才前进（原地转消除最小
## 转弯圆，遍历器 F8；TURN_RATE 4 rad/s 同遍历器）；水平距 < JUMP_ARRIVE →
## TRIGGER。助跑中跌落（越过起跳点未触发）→ AIR 按跳跃成败判定（一次执行语义）。
func _tick_runup(delta: float) -> void:
	var seg: Dictionary = _jump_state["seg"]
	if not body.is_on_floor():
		_jump_state["phase"] = "AIR"
		_jump_state["t"] = 0.0
		return
	var from: Vector3 = seg["from"]
	if Vector2(from.x - body.global_position.x,
			from.z - body.global_position.z).length() < JUMP_ARRIVE:
		_jump_state["phase"] = "TRIGGER"
		_jump_state["t"] = 0.0
		return
	var ty := _target_yaw(body.global_position, from)
	var dy := angle_difference(body.rotation.y, ty)
	if absf(dy) <= RUNUP_TURN_GATE:
		command.move_axis = Vector2(0, 1)  # 直线助跑（本地前 = 段起点方向）
	else:
		body.rotation.y += clampf(dy, -TURN_RATE * delta, TURN_RATE * delta)
		command.move_axis = Vector2.ZERO


## TRIGGER：沿段方向前进；hspeed ≥ 触发速度门且 速度方向·段方向 ≥ TRIGGER_CONE
## × hspeed → command.jump_pressed = true（单帧边沿，控制器读取即清零）→ AIR。
## 超 TRIGGER_TIMEOUT 未触发（转向不到位）→ 退回 RUNUP 重对准；行进中跌落 → AIR。
func _tick_trigger(delta: float) -> void:
	var seg: Dictionary = _jump_state["seg"]
	if not body.is_on_floor():
		_jump_state["phase"] = "AIR"
		_jump_state["t"] = 0.0
		return
	_jump_state["t"] += delta
	if float(_jump_state["t"]) > TRIGGER_TIMEOUT:
		_jump_state["phase"] = "RUNUP"
		_jump_state["t"] = 0.0
		return
	var dir := _seg_dir(seg)
	command.move_axis = approach_point(body.global_position, body.rotation.y,
			body.global_position + dir * 10.0, body.global_position + dir * 10.0)
	var hv := Vector2(body.velocity.x, body.velocity.z)
	var hspeed := hv.length()
	var d2 := Vector2(dir.x, dir.z)
	if hspeed >= float(_jump_state["gate"]) and hv.dot(d2) >= TRIGGER_CONE * hspeed:
		command.jump_pressed = true
		_jump_state["phase"] = "AIR"
		_jump_state["t"] = 0.0


## AIR：move_axis 保持沿段方向（空中微调，物理层已有 RUN 档空中控制）；落地
## （is_on_floor 且滞空 > AIR_MIN_T，防帧序陈旧 is_on_floor 误判）或超时
## JUMP_TIMEOUT → 成败判定。成功（落点距段 to 水平 < LAND_TOLERANCE 或落点 xz
## 在数据集 landing_zone 膨胀 0.5 内）→ 弹段继续；失败 → _on_jump_failed。
func _tick_air(delta: float) -> void:
	var seg: Dictionary = _jump_state["seg"]
	_jump_state["t"] += delta
	var dir := _seg_dir(seg)
	command.move_axis = approach_point(body.global_position, body.rotation.y,
			body.global_position + dir * 10.0, body.global_position + dir * 10.0)
	if (body.is_on_floor() and float(_jump_state["t"]) > AIR_MIN_T) \
			or float(_jump_state["t"]) > JUMP_TIMEOUT:
		if _landed_ok(seg):
			_jump_state = {}
			if not _path.is_empty():
				_path.remove_at(0)  # 消耗起跳点（seg.from = _path[0]，锁步）
			if not _segments.is_empty():
				_segments.remove_at(0)  # 消耗 JUMP 段
			command.move_axis = Vector2.ZERO
		else:
			_on_jump_failed(str(seg["link_name"]))


## 进入跳跃段（2026-08-17 M3.1 T3）：查数据集边（delta_h/dist_zone/human p50/
## augmented/physics.v_req）→ pick_jump_speed（消费口径 + 钳制带）→ 触发速度门
## 动态值 = max(v, RUNUP_GATE_SPEED)——人类 p50 高于基门时按 p50 起跳（参数化
## 执行本体）。求解器窗口无解（r.ok=false）或 v 超物理上限 SPEED_CAP（如
## WingToLintel v_req 11.0 > 6.35）→ 不触发跳跃，直接诚实失败（防无限
## TRIGGER↔RUNUP 振荡——速度门物理不可达）。无数据集边 → 纯默认门。
func _enter_jump(seg: Dictionary) -> void:
	_jump_state = {"phase": "RUNUP", "seg": seg, "t": 0.0, "gate": RUNUP_GATE_SPEED}
	var link_name: String = seg["link_name"]
	var edge: Variant = _ensure_dataset().get(link_name)
	if edge == null:
		return
	var dh: float = float(edge["delta_h"])
	var dist: float = float(edge["dist_zone"])
	var pv_req: float = float(edge["physics"]["v_req"])
	var r: Dictionary = JumpSolver.required_speed(dh, dist)
	if not r.ok:
		_on_jump_failed(link_name)
		return
	var p50 := NAN
	var augmented := false
	var human: Variant = edge.get("human")
	if human != null:
		p50 = float(human["takeoff_speed"]["p50"])
		augmented = bool(human.get("augmented", false))
	var v: float = pick_jump_speed(dh, dist, p50, augmented, pv_req)
	if v > JumpSolver.SPEED_CAP:
		_on_jump_failed(link_name)
		return
	_jump_state["gate"] = maxf(v, RUNUP_GATE_SPEED)


## 失败处理（2026-08-17 M3.1 T3 跳跃执行铁律）：jump_failed 事件 + 该链接临时
## 惩罚 → set_target(原目标) 重寻路一次；重寻路后路径仍含该链接（classify 仍出
## 同 link 的 JUMP 段）→ clear_target 诚实放弃（决策层 M3.3 接管换目标）。
## 惩罚值 PENALTY_FRAMES 为重寻路临时加权语义预留（T4 卡顿对策消费）。
func _on_jump_failed(link_name: String) -> void:
	_jump_state = {}
	jump_failed.emit(link_name)
	_penalized_links[link_name] = PENALTY_FRAMES
	set_target(_target)
	for s0 in _segments:
		var s: Dictionary = s0
		if s["type"] == "JUMP" and str(s["link_name"]) == link_name:
			clear_target()
			return


## 落点成败（2026-08-17 M3.1 T3）：距段 to 点水平距 < LAND_TOLERANCE 成功；或
## 数据集边存在时落点 x/z 在 landing_zone（center±size/2，膨胀 0.5）内成功。
func _landed_ok(seg: Dictionary) -> bool:
	var p := body.global_position
	var to: Vector3 = seg["to"]
	if Vector2(to.x - p.x, to.z - p.z).length() < LAND_TOLERANCE:
		return true
	var edge: Variant = _ensure_dataset().get(str(seg["link_name"]))
	if edge != null:
		var zone: Dictionary = edge.get("landing_zone", {})
		if not zone.is_empty():
			var c: Dictionary = zone["center"]
			var s: Dictionary = zone["size"]
			if absf(p.x - float(c["x"])) <= float(s["x"]) * 0.5 + 0.5 \
					and absf(p.z - float(c["z"])) <= float(s["z"]) * 0.5 + 0.5:
				return true
	return false


## 段水平方向（2026-08-17 M3.1 T3）：from→to xz 归一化；垂直段（原地跳，如
## TowerBox dist=0）退化返回 ZERO——方向锥对零方向恒不满足（数据 p50=0 的
## 原地跳场景由 T4/T5 处理，本任务路径不含）。
func _seg_dir(seg: Dictionary) -> Vector3:
	var d := Vector3(float(seg["to"].x) - float(seg["from"].x), 0.0,
			float(seg["to"].z) - float(seg["from"].z))
	if d.length() < 1e-6:
		return Vector3.ZERO
	return d.normalized()


## 目标航向 yaw（2026-08-17 M3.1 T3）：T2 坐标系约定本地前 = -basis.z =
## (sin yaw, −cos yaw)（yaw=0 → −Z）→ yaw = atan2(dx, −dz) 使前向对准点方向。
func _target_yaw(body_pos: Vector3, point: Vector3) -> float:
	var d := Vector3(point.x - body_pos.x, 0.0, point.z - body_pos.z)
	if d.length_squared() < 1e-6:
		return 0.0
	return atan2(d.x, -d.z)
