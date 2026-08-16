# Levels/M2_TDM/bot_locomotion.gd
# M3.1 T2（2026-08-16）：bot navmesh 路径跟随层——寻路 + 途经点简化 + 前瞻转向 +
# 高度门 + 到达判定。决策层（M3.3）经 set_target 指定目标，tick 每物理帧输出
# command.move_axis（= body.command_override 同引用），bot 复用玩家物理语义零改动。
# T2 只做路径跟随；跳跃段执行留给 T3（高度门触发时仅重寻路一次并诚实失败，
# 不发 jump_failed——T3 接管该分支）。
class_name BotLocomotion
extends Node

signal arrived                    # 到达目标（决策层 M3.3 消费；M3.1 仅冒烟断言）
signal jump_failed(link_name: String)  # 跳跃失败（T3 起发出；本任务仅声明不发出）

const ARRIVE_RADIUS := 0.8        # 到达半径（水平距）
const HEIGHT_GATE := 0.72         # 途经点高差门（> 此值 → 重寻路一次 / T3 接管跳跃执行）
const SIMPLIFY_STEP := 1.0        # 途经点简化：1.0m 稠密点
const SIMPLIFY_DY := 0.2          # 途经点简化：0.2 高差保留
const LOOKAHEAD_DIST := 1.5       # 前瞻转向距离（当前点距 body < 此值 → 转向基准取下一途经点）
const REPATH_LIMIT := 2           # 高度门重寻路上限（T4 卡顿对策复用同一预算语义）

var body: CharacterBody3D         # Enemy（读 global_position / rotation.y）
var map_rid: RID                  # 导航地图 RID（L_M2 get_world_3d().navigation_map）
var command: MovementCommand      # 指向 body.command_override（同引用，勿新建）

var _path := PackedVector3Array() # 简化后的途经点队列（[0] = 当前目标途经点）
var _target := Vector3.ZERO       # 原目标（高度门重寻路用）
var _repath_count := 0            # 高度门重寻路计数（新 set_target 重置）


func setup(b: CharacterBody3D, m: RID) -> void:
	body = b
	map_rid = m
	command = b.command_override  # 同引用（Enemy._ready 恒设，T0 已固化）
	# T0 移交注记（勿改行为，2026-08-16 M3.1 T0 审查遗留）：bot 的 step-up 查询掩码
	# 为 1（Enemy._ready 中 super 先于 mask=3 赋值执行）——语义上有意设计：bot 登台
	# 探针不含 Player 层，不把玩家当地形。本层不感知该差异（只读 body 位置/朝向，
	# 不动物理），记录此约定防未来误当 bug 修复。


## 寻路 + 简化（2026-08-16 M3.1 T2）：optimize=false 走廊忠实（遍历器时代教训——
## optimize 会切角，直线可能穿出走廊撞几何）。首点丢弃（含 body 自身位置）。
func _query_path(pos: Vector3) -> PackedVector3Array:
	var raw := NavigationServer3D.map_get_path(map_rid, body.global_position, pos, false)
	if raw.size() > 1:
		raw.remove_at(0)
	return simplify_path(raw)


## 指定新目标：寻路 → 简化 → 存 _path；重寻路预算归零（决策层换目标 = 新 episode）。
func set_target(pos: Vector3) -> void:
	_target = pos
	_path = _query_path(pos)
	_repath_count = 0


## 清除目标（高度门重寻路超限的诚实失败；T4 卡顿对策复用）。arrived 不发、
## jump_failed 不发——决策层 M3.3 接管换目标，T3 接管跳跃执行。
func clear_target() -> void:
	_path = PackedVector3Array()
	_target = Vector3.ZERO


## 每物理帧推进（Enemy._physics_process 或后续 Brain 调用）：
##   _path 空 → 站桩（move_axis ZERO）
##   到达/越过（水平距）→ 弹点；弹空 → arrived.emit() + 站桩——先于高度门
##     （修复轮 1 Minor 4：终点恰在高面时先判到达，防高面终点永不到达）
##   高度门（navmesh 空间双锚）→ 重寻路一次（上限 REPATH_LIMIT）→ 超限诚实失败
##   前瞻转向 → 输出 command.move_axis（jump/crouch 不碰——T3 接管）
func tick(delta: float) -> void:
	if command == null or body == null:
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
	while not _path.is_empty():
		var d_cur := Vector2(_path[0].x - body.global_position.x,
				_path[0].z - body.global_position.z).length()
		if d_cur < ARRIVE_RADIUS:
			_path.remove_at(0)
			continue
		if _path.size() > 1:
			var d_next := Vector2(_path[1].x - body.global_position.x,
					_path[1].z - body.global_position.z).length()
			if d_next <= d_cur:
				_path.remove_at(0)
				continue
		break
	if _path.is_empty():
		arrived.emit()
		command.move_axis = Vector2.ZERO
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
