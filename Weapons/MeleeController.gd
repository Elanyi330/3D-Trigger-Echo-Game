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
#   - 伤害结算：直接调用目标 take_damage（Target.gd 已实现）；melee_hit(target, damage)
#     信号供反馈消费（spec §9.5 推荐信号，M1 暂无 HUD 消费，预留）
# 全局约束（计划 §4）：数值唯一来源 WeaponResource（weapon_*.tres，禁止硬编码散值）；
#   命中判定只对 Objects 层（物理扫掠 mask=1）；纯离线。
class_name MeleeController
extends Node3D

signal melee_swung(heavy: bool)  # 挥击动画驱动（WeaponAnchor 消费；heavy=true 重刺）
signal melee_hit(target: Node, damage: float)  # 命中反馈（spec §9.5；预留消费）

var origin: Node3D  # 攻击位置/朝向来源（WeaponManager 注入相机；测试可直设）
var targets: Array[Node] = []  # 扇形候选目标（测试/集成注入；空 = 自动物理球扫掠）

var _resource: WeaponResource  # 最近一次挥击的资源（数值唯一来源 .tres）
var _cooldown: float = 0.0  # 挥击冷却（s；轻 0.4 / 重 1.0，自 .tres）
var _combo_secondary: bool = false  # 连击交替：false=首击 → true=连击 → 交替


func try_swing(light: bool, resource: WeaponResource) -> void:
	# 调用契约：WeaponManager 按槽位 fire_mode 路由（MELEE：左键 try_swing(true)、
	# 右键 set_aim → try_swing(false)）；左键按住可被持续轮询（CS2 持刀连斩）。
	_resource = resource
	if _resource == null or _cooldown > 0.0:
		return
	_cooldown = _resource.melee_light_time if light else _resource.melee_heavy_time
	var damage := _light_damage() if light else _resource.melee_stab_damage
	melee_swung.emit(not light)
	_resolve_swing(damage)


func _light_damage() -> float:
	var d := _resource.melee_primary_damage if not _combo_secondary else _resource.melee_secondary_damage
	_combo_secondary = not _combo_secondary  # 每次轻击交替（CS2 左挥/右挥连击）
	return d


# ---- 扇形判定 + 伤害结算 ----

func _resolve_swing(base_damage: float) -> void:
	var o := _origin_pos()
	var facing := _facing_dir()
	for target in _candidate_targets():
		if not is_instance_valid(target) or not target.has_method("take_damage"):
			continue
		if not _in_cone(target.global_position, o, facing):
			continue
		var damage := base_damage
		if _is_backstab(target, o):
			damage = _resource.melee_backstab_damage  # 背刺秒杀（CS2 180）
		target.take_damage(damage)
		melee_hit.emit(target, damage)


func _in_cone(target_pos: Vector3, origin_pos: Vector3, facing: Vector3) -> bool:
	# 扇形过滤：距离 ≤ melee_range 且 夹角 ≤ melee_angle/2（60° 扇形 = 半角 30°）
	var to_target := target_pos - origin_pos
	var dist := to_target.length()
	if dist > _resource.melee_range:
		return false
	if dist <= 0.0001:
		return true  # 原点重合防御（normalized 除零）
	var angle_deg := rad_to_deg(to_target.normalized().angle_to(facing))
	return angle_deg <= _resource.melee_angle * 0.5


func _is_backstab(target: Node, attacker_pos: Vector3) -> bool:
	# 背刺：目标朝向（-basis.z，Godot 前向）与"目标→攻击者"方向夹角 > melee_backstab_angle（150°）
	# target 参数为 Node（候选数组元素类型）：Node 无 global_transform 静态成员 → 显式类型注解
	var target_forward: Vector3 = -target.global_transform.basis.z
	var to_attacker: Vector3 = (attacker_pos - target.global_position).normalized()
	return target_forward.dot(to_attacker) < cos(deg_to_rad(_resource.melee_backstab_angle))


func _candidate_targets() -> Array[Node]:
	if not targets.is_empty():
		return targets
	return _query_physics_targets()


func _query_physics_targets() -> Array[Node]:
	# 集成自动收集：球体扫掠（半径 melee_range，mask=1 仅 Objects 层）→ 取 take_damage 目标
	var space := get_world_3d().direct_space_state
	if space == null or _resource == null:
		return []
	var shape := SphereShape3D.new()
	shape.radius = _resource.melee_range
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.transform = Transform3D(Basis(), _origin_pos())
	params.collision_mask = 1
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
