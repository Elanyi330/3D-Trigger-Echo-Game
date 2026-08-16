# Weapons/MeleeController.gd
# M1 任务10：近战判定控制器（spec §9.5，TDD RED 先行）
#
# 职责：
#   - 挥击节流：轻击 melee_light_time（0.4s）/ 重刺 melee_heavy_time（1.0s）——单一共享冷却
#     （重刺后轻击同样锁定 = CS2 重刺长后摇）
#   - 连击交替：轻击首击 melee_primary_damage（40）→ 连击 melee_secondary_damage（25）→ 交替
#   - 扇形判定：melee_range × melee_angle 距离 + 角度过滤（参考 FPS-Template melee_hitbox
#     ShapeCast3D 思路，纯逻辑实现）；候选目标注入（测试/集成）或物理球扫掠（集成自动收集）
#   - 背刺：目标朝向（-basis.z）与"目标→攻击者"方向夹角 > melee_backstab_angle（150°）
#     → melee_backstab_damage（180 秒杀）
#   - 延迟命中（M1.5）：挥击动画立即开始，伤害延迟到动画接触帧结算（melee_light/heavy_hit_delay，
#     修复"重刺秒出伤"——重击以蓄力动作换高伤害，判定与动画同步）；切枪 cancel_pending 取消未结算挥击
#   - 伤害结算：直接调用目标 take_damage（Target.gd 已实现）；melee_hit(target, damage)
#     信号供反馈消费（spec §9.5 推荐信号，M1 暂无 HUD 消费，预留）
# 全局约束（计划 §4）：数值唯一来源 WeaponResource（weapon_*.tres，禁止硬编码散值）；
#   命中判定对 Objects|Bots 层（物理扫掠 mask=5，2026-08-16 M3.1 T0 扩展）；纯离线。
class_name MeleeController
extends Node3D

# M2 手感修复（2026-08-13）：CS 站立眼位 64u≈1.63m（GripRig.EYE_Y / Crouch 相机全局高同源）——
# _in_cone 垂直判定需把眼位原点换算回脚部（脚部-脚部比较）。
const EYE_HEIGHT := 1.63

signal melee_swung(heavy: bool)  # 挥击动画驱动（WeaponAnchor 消费；heavy=true 重刺）
signal melee_hit(target: Node, damage: float)  # 命中反馈（spec §9.5；预留消费）

var origin: Node3D  # 攻击位置/朝向来源（WeaponManager 注入相机；测试可直设）
var targets: Array[Node] = []  # 扇形候选目标（测试/集成注入；空 = 自动物理球扫掠）

var _resource: WeaponResource  # 最近一次挥击的资源（数值唯一来源 .tres）
var _cooldown: float = 0.0  # 挥击冷却（s；轻 0.4 / 重 1.0，自 .tres）
var _combo_secondary: bool = false  # 连击交替：false=首击 → true=连击 → 交替
# M1.5：延迟命中（修复"重刺秒出伤"）——挥击动画立即开始（melee_swung），伤害延迟到动画接触帧结算。
var _pending_hit: bool = false  # 有待结算命中
var _pending_damage: float = 0.0  # 待结算伤害（挥击开始时捕获，接触帧结算）
var _pending_timer: float = 0.0  # 距接触帧剩余时间（s，自 melee_*_hit_delay）
var _combo_timer: float = 0.0  # 连击窗口倒计时（s，自挥击发起帧；≤0 = 窗口过期，下一击回首挥）
var _pending_range: float = 0.0  # 待结算挥击射程（轻=melee_range / 重=melee_stab_range，挥击时捕获）


func try_swing(light: bool, resource: WeaponResource) -> void:
	# 调用契约：WeaponManager 按槽位 fire_mode 路由（MELEE：左键 try_swing(true)、
	# 右键 set_aim → try_swing(false)）；左键按住可被持续轮询（CS2 持刀连斩）。
	_resource = resource
	if _resource == null or _cooldown > 0.0:
		return
	_cooldown = _resource.melee_light_time if light else _resource.melee_heavy_time
	var damage := _light_damage() if light else _resource.melee_stab_damage
	melee_swung.emit(not light)  # 挥击动画立即开始（蓄力/挥出）
	# 伤害延迟到动画接触帧结算（重刺以蓄力换高伤，不再秒出伤；轻击亦有短接触延迟对齐斜挥）。
	_pending_hit = true
	_pending_damage = damage
	_pending_timer = _resource.melee_light_hit_delay if light else _resource.melee_heavy_hit_delay
	_pending_range = _resource.melee_range if light else _resource.melee_stab_range


func cancel_pending() -> void:
	# 切枪取消未结算挥击（WeaponManager.switch_to 调用）——CS 式切枪取消攻击，
	# 防延迟伤害在换持武器后空发（M1.5 延迟命中引入的边界，配套取消）。
	_pending_hit = false


func _light_damage() -> float:
	if _combo_timer <= 0.0:
		_combo_secondary = false  # 连击窗口过期：重置回首挥 40（严格化——原实现无条件交替）
	var d := _resource.melee_primary_damage if not _combo_secondary else _resource.melee_secondary_damage
	_combo_secondary = not _combo_secondary  # 每次轻击交替（CS2 左挥/右挥连击）
	_combo_timer = _resource.melee_combo_window  # 窗口自挥击发起帧刷新
	return d


# ---- 扇形判定 + 伤害结算 ----

func _resolve_swing(base_damage: float, range_val: float) -> void:
	var o := _origin_pos()
	var facing := _facing_dir()
	for target in _candidate_targets():
		if not is_instance_valid(target) or not target.has_method("take_damage"):
			continue
		if target.is_in_group("head"):
			continue  # CS：近战无部位倍率。头部 hitbox 转发本体会与躯干双结算 → 跳过
		# 2026-08-13 友伤过滤（用户拍板：任何阵营内部均无友伤）——近战同样不伤友军
		if Enemy.is_friendly_fire("friendly", target):
			continue
		if not _in_cone(target.global_position, o, facing, range_val):
			continue
		var damage := base_damage
		if _is_backstab(target, o):
			damage = _resource.melee_backstab_damage  # 背刺秒杀（CS2 180）
		target.take_damage(damage)
		melee_hit.emit(target, damage)


func _in_cone(target_pos: Vector3, origin_pos: Vector3, facing: Vector3, range_val: float) -> bool:
	# M1.5：水平面（XZ）判定——修复"攻击距离过短/打不到"。根因：敌人原点（StaticBody3D）在脚部
	# （y=0），而攻击原点在相机眼位（y≈1.63m），3D 中心距的垂直分量（≥1.6m）直接超出旧 melee_range，
	# 且"指向脚部"的 3D 夹角在平视时恒 > 半角 → 平视永远打不到。改为水平面投影（等效 CS 刀的眼位视线触及）：
	# 距离与夹角都只看 XZ——相机高度/目标原点高低不再影响，面向目标即判定。
	# M2 手感修复（2026-08-13）：垂直差上限（脚部-脚部）——origin 是眼位相机，减 EYE_HEIGHT 换算脚部；
	# ≤1.5 允许同层（0）/1.2m 摊阁（1.2）/0.6m 祭坛台（0.6）；禁止 2.5m 望楼 / 3.0m 回廊隔层刀人。
	if absf(target_pos.y - (origin_pos.y - EYE_HEIGHT)) > _resource.melee_vertical_range:
		return false
	var to_target := target_pos - origin_pos
	var flat := Vector3(to_target.x, 0.0, to_target.z)
	var dist := flat.length()
	if dist > range_val:
		return false
	if dist <= 0.0001:
		return true  # 贴身（同一水平位置）防御
	var flat_facing := Vector3(facing.x, 0.0, facing.z)
	if flat_facing.length() <= 0.0001:
		return true  # 视线近乎竖直（正上/正下）：水平朝向不可靠，距离已过即判中
	var angle_deg := rad_to_deg(flat.normalized().angle_to(flat_facing.normalized()))
	return angle_deg <= _resource.melee_angle * 0.5


func _is_backstab(target: Node, attacker_pos: Vector3) -> bool:
	# 背刺：目标朝向与"目标→攻击者"方向夹角 > melee_backstab_angle（150°）→ 背刺（180 秒杀）。
	# M1.5：身前/身后判定用**水平面(XZ)投影**——相机眼位(y≈1.63)与敌人脚部原点(y=0)的垂直差
	# 会稀释 3D 点积（垂直分量拉大 to_attacker 长度），导致正背后也判不出背刺；投影到水平面后严格准确。
	# target 参数为 Node（候选数组元素类型）：Node 无 global_transform 静态成员 → 显式类型注解
	var tf3: Vector3 = -target.global_transform.basis.z
	var ta3: Vector3 = attacker_pos - target.global_position
	var target_forward := Vector3(tf3.x, 0.0, tf3.z)
	var to_attacker := Vector3(ta3.x, 0.0, ta3.z)
	if target_forward.length() < 0.001 or to_attacker.length() < 0.001:
		return false  # 退化（目标竖直朝向 / 同一水平位置）：不判背刺
	return target_forward.normalized().dot(to_attacker.normalized()) < cos(deg_to_rad(_resource.melee_backstab_angle))


func _candidate_targets() -> Array[Node]:
	if not targets.is_empty():
		return targets
	return _query_physics_targets()


func _query_physics_targets() -> Array[Node]:
	# 集成自动收集：球体扫掠（半径 melee_range，mask=5 = Objects|Bots 层）→ 取 take_damage 目标
	var space := get_world_3d().direct_space_state
	if space == null or _resource == null:
		return []
	var shape := SphereShape3D.new()
	shape.radius = _resource.melee_range
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.transform = Transform3D(Basis(), _origin_pos())
	params.collision_mask = 5  # Objects|Bots 层（2026-08-16 M3.1 T0：bot 换层 4 后近战仍命中）
	var found: Array[Node] = []
	for hit in space.intersect_shape(params, 32):
		var collider: Node = hit["collider"]
		if collider != null and collider.has_method("take_damage") and not found.has(collider):
			found.append(collider)
	return found


func _origin_pos() -> Vector3:
	if origin != null and is_instance_valid(origin):
		return origin.global_position
	return Vector3.ZERO


func _facing_dir() -> Vector3:
	if origin != null and is_instance_valid(origin):
		return -origin.global_transform.basis.z
	return Vector3(0, 0, -1)


func _physics_process(delta: float) -> void:
	if _cooldown > 0.0:
		_cooldown = maxf(0.0, _cooldown - delta)
	if _combo_timer > 0.0:
		_combo_timer = maxf(0.0, _combo_timer - delta)
	# M1.5：延迟命中——到接触帧才结算扇形伤害（动画与判定同步）
	if _pending_hit:
		_pending_timer -= delta
		if _pending_timer <= 0.0:
			_pending_hit = false
			_resolve_swing(_pending_damage, _pending_range)
