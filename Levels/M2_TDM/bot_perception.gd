# Levels/M2_TDM/bot_perception.gd
# M3.2 T6（2026-08-17）：BotPerception 视线子系统——bot 的视觉感知。
# 视锥 120°（yaw 平面角，忽略俯仰）/视距 40m/节流 0.2s：每个节流周期枚举 torso 组
# Enemy（≤9 个零成本）+ player_target，过滤敌对阵营（is_hostile）与死亡目标，
# 逐目标三级裁剪（视距 → 视锥 → 视线射线）后发 hostile_visible；上周期可见本周期
# 不可见 → hostile_lost（T8 LKP 消费）。
# 视线射线：主射线（眼→目标胸口）+ SEGMENT_SAMPLES 中间点射线（1/3、2/3 分位点
# 横向散布半身宽后射向目标胸口——细缝窄于身体宽度不应透过视线，防穿缝假阳性）；
# 掩码 5（Objects|Bots，武器命中同口径）；exclude 观察者与目标自身碰撞 RID（射线
# 终点在目标躯干胶囊内，不排除则恒被目标本体遮挡——Grenade._penetration_mult 同款
# 口径）。
# 感知与决策分离铁律：只发信号 + 维护 _visible 集合，禁止内嵌状态机（企划书 §4.2）。
# 前向口径（2026-08-17 M3.1 T3 修复轮 2 钉死）：本地前 = (−sin yaw, −cos yaw)，
# 旧公式 (sin, −cos) 仅在 yaw=0 成立。
# M3.2 无 Brain 站桩：本节点由装配方（M3.3 Brain / L_M2）驱动 tick；未装配即零运行。
class_name BotPerception
extends Node

signal hostile_visible(target: Node, pos: Vector3)   # 视线内敌对出现（节流周期上报）
signal hostile_lost(target: Node)                    # 目标离开视线（不可见计时起）

const CONE_HALF_ANGLE := deg_to_rad(60.0)  # 半视锥角（全锥 120°）
const VIEW_RANGE := 40.0                   # 视距（m）
const THROTTLE := 0.2                      # s：感知节流间隔
const SEGMENT_SAMPLES := 2                 # 分段采样中间点数（防穿缝）
const EYE_OFFSET := Vector3(0, 1.65, 0)    # 眼睛高度（bot 头 hitbox 1.70 下方）
const CHEST_OFFSET := Vector3(0, 1.2, 0)   # 目标胸部参考点
const LOS_MASK := 5                        # 视线射线掩码：Objects(1)|Bots(4)，武器命中同口径
const SAMPLE_SPREAD := 0.3                 # m：中间采样点横向散布（≈身体半径，细缝窄于身体不透过）

var body: CharacterBody3D        # 宿主 Enemy
var faction: String              # "enemy" | "friendly"（Enemy.get_faction 口径）
var player_target: Node3D        # 玩家节点（torso 组外显式目标）

var _throttle_t := 0.0
var _visible: Dictionary = {}    # target -> true（可见集合，T8 LKP / T10 黑板读取）


func setup(b: CharacterBody3D, f: String, player: Node3D) -> void:
	body = b
	faction = f
	player_target = player


## 每物理帧调用（Enemy._physics_process 或 Brain）；内部节流——< THROTTLE 直接 return。
func tick(delta: float) -> void:
	if body == null:
		return
	_throttle_t += delta
	if _throttle_t < THROTTLE:
		return
	_throttle_t = 0.0
	_scan()


## 节流周期扫描：枚举目标 → 单目标裁剪 → 发信号 + 维护 _visible 集合。
func _scan() -> void:
	var space := body.get_world_3d().direct_space_state
	var seen: Dictionary = {}
	for target in _targets():
		if _visible_for(target, space):
			seen[target] = true
			hostile_visible.emit(target, target.global_position)
	for t in _visible.keys():
		if not seen.has(t):
			hostile_lost.emit(t)
	_visible = seen


## 目标枚举：torso 组（Enemy 类 ≤9 个零成本）+ 玩家显式目标（torso 组外）。
func _targets() -> Array:
	var out: Array = []
	for n in get_tree().get_nodes_in_group("torso"):
		out.append(n)
	if player_target != null and is_instance_valid(player_target):
		out.append(player_target)
	return out


## 单目标可见判定：敌对过滤 → 死亡过滤 → 视距 → 视锥（yaw 平面角）→ 视线射线。
func _visible_for(target: Node3D, space: PhysicsDirectSpaceState3D) -> bool:
	if not is_hostile(target, faction):
		return false
	if _is_dead(target):
		return false
	var eye := body.global_position + EYE_OFFSET
	var chest := target.global_position + CHEST_OFFSET
	if not within_range(eye, chest, VIEW_RANGE):
		return false
	if not in_cone(body.global_position, body.rotation.y, target.global_position,
			CONE_HALF_ANGLE):
		return false
	return not los_blocked(space, eye, chest, LOS_MASK, _exclude_rids(target))


## 视线排除集合：观察者本体+子碰撞体（头 hitbox）+ 目标本体+子碰撞体——射线终点
## 在目标躯干胶囊内，不排除则恒被目标本体遮挡（Grenade 爆炸采样同款口径）。
func _exclude_rids(target: Node3D) -> Array[RID]:
	var out: Array[RID] = []
	out.append(body.get_rid())
	for c in body.get_children():
		if c is CollisionObject3D:
			out.append((c as CollisionObject3D).get_rid())
	if target is CollisionObject3D:
		out.append((target as CollisionObject3D).get_rid())
		for c in target.get_children():
			if c is CollisionObject3D:
				out.append((c as CollisionObject3D).get_rid())
	return out


## 目标死亡判定：Enemy.dead 在根上；玩家侧 dead 由 PlayerLife 子节点持有。
static func _is_dead(target: Node) -> bool:
	if target.get("dead") == true:
		return true
	for c in target.get_children():
		if c.get("dead") == true:
			return true
	return false


## 目标阵营解析：根 get_faction 鸭子接口；无则查子节点（L_M2 玩家阵营由 PlayerLife
## 子节点提供 "friendly"）。无阵营目标返回 ""（非敌对）。
static func _faction_of(target: Node) -> String:
	if target.has_method("get_faction"):
		return target.get_faction()
	for c in target.get_children():
		if c.has_method("get_faction"):
			return c.get_faction()
	return ""


static func is_hostile(target: Node, own_faction: String) -> bool:
	if target == null:
		return false
	var f := _faction_of(target)
	return f != "" and f != own_faction


## 视锥判定：目标方向水平投影与 body 前向（−sin yaw, −cos yaw——T3 修正口径）夹角
## ≤ half_angle。目标与自身水平重合（方向未定义）视为锥内。
static func in_cone(body_pos: Vector3, body_yaw: float, target_pos: Vector3,
		half_angle: float) -> bool:
	var fw := Vector2(-sin(body_yaw), -cos(body_yaw))
	var to := Vector2(target_pos.x - body_pos.x, target_pos.z - body_pos.z)
	if to.length_squared() < 1e-12:
		return true
	return fw.angle_to(to) <= half_angle


static func within_range(a: Vector3, b: Vector3, max_range: float) -> bool:
	return a.distance_to(b) <= max_range


## 视线遮挡：主射线 from→to + SEGMENT_SAMPLES 中间点射线（分位点横向散布
## SAMPLE_SPREAD 后射向目标胸口）——任一命中即遮挡（防细缝透视线假阳性）。
## exclude 为可选参数（接口块 4 参 + 自身/目标 RID 排除——观察者与目标本体不挡视线）。
static func los_blocked(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3,
		mask: int, exclude: Array[RID] = []) -> bool:
	if _ray_hits(space, from, to, mask, exclude):
		return true
	var dir := to - from
	var side := 1.0
	for i in SEGMENT_SAMPLES:
		var t := float(i + 1) / float(SEGMENT_SAMPLES + 1)
		var mid := from + dir * t + _spread_dir(dir) * (SAMPLE_SPREAD * side)
		if _ray_hits(space, mid, to, mask, exclude):
			return true
		side = -side
	return false


## 横向散布方向：视线方向的水平垂线（忽略 y）；近垂直射线退化为 +X。
static func _spread_dir(dir: Vector3) -> Vector3:
	var h := Vector3(dir.z, 0.0, -dir.x)
	if h.length_squared() < 1e-10:
		return Vector3(1, 0, 0)
	return h.normalized()


static func _ray_hits(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3,
		mask: int, exclude: Array[RID]) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from, to, mask)
	q.exclude = exclude
	return not space.intersect_ray(q).is_empty()
