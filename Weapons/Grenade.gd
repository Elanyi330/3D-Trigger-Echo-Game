# Weapons/Grenade.gd
# M1 任务4：Grenade 投掷物（抛物线 + 爆炸衰减）
#
# 接口签名按计划 §5 任务4 逐字照抄；数值唯一来源 WeaponResource（weapon_*.tres，禁止硬编码散值，企划书 §4.2.5）。
# 全局约束（计划 §4）：爆炸范围伤害无部位倍率；命中判定对 Objects 层（collision_mask=1）；纯离线。
# 弹道为重力抛体（RigidBody3D 物理积分；碰撞反弹自然具备，企划书 §4.2.3⑦ 弹道可反弹——M1 简化不特判）。
# 参考：docs/superpowers/reference/m1-src/Weapon_State_Machine/bullet.gd
#   （RigidBody3D 弹道 + has_method 目标结算 + 生命周期结束释放）
class_name Grenade
extends RigidBody3D

signal exploded(center: Vector3)

# 武器数据（fuse_time/blast_radius/damage）；须在 init() 前赋值（WeaponManager 任务 6 接线）
var resource: WeaponResource

var _fuse_remaining: float = 0.0  # 引信倒计时（秒）；0 = 未投掷
var _exploded: bool = false
var _visual: Node3D = null  # 投掷物视觉（M67 弹体模型）


func init(origin: Vector3, direction: Vector3, strength: float) -> void:
	global_position = origin
	linear_velocity = direction.normalized() * strength
	if resource != null:
		_fuse_remaining = resource.fuse_time
	_attach_visual()


func _attach_visual() -> void:
	# M1.5：投掷物可视化——挂手雷模型（Grenade_M67_Echo），可见抛物线飞行/落地。
	# 模型原点 = 弹体中心；清掉标记子节点（投影无需握把/拉环标记）。
	if _visual != null:
		return
	var model: PackedScene = load("res://Assets/Models/Weapons/Throwable/Grenade_M67_Echo/Grenade_M67_Echo.glb")
	_visual = model.instantiate()
	for c in _visual.get_children():
		if not c is MeshInstance3D:
			c.queue_free()  # 移除 Marker 节点（PullRing/Spoon/GripRight），只留弹体网格
	add_child(_visual)
	# 飞行旋转（翻滚感）
	angular_velocity = Vector3(randf_range(-6, 6), randf_range(-6, 6), randf_range(-6, 6))


func explode() -> void:
	if _exploded:
		return  # 幂等：引信自动爆炸与手动调用不重复结算
	_exploded = true
	# 先结算伤害再发信号：exploded 监听方（HUD/任务 6）收到时伤害已全部落定
	_apply_blast_damage()
	# M1 任务11：爆炸视觉（spec §9.8）——生成 ExplosionEffect（火花/闪光/冲击波环）
	_spawn_explosion_effect()
	exploded.emit(global_position)
	queue_free()


# 爆炸范围伤害（纯逻辑可单测）：CS 同款**线性衰减** dmg = damage × (1 − d/blast_radius)；
# 无部位倍率（范围伤害）。中心 = 满伤（M67 98），随距离线性降，半径边缘（8.89m）归 0。
# 公式学习自 Source RadiusDamage 机制（自研实现，非复制代码，CLAUDE.md 合规红线）。
func damage_in_radius(distance: float) -> float:
	if resource == null or resource.blast_radius <= 0.0:
		return 0.0
	if distance < 0.0 or distance >= resource.blast_radius:
		return 0.0  # 半径外不伤害；半径边缘恰归 0
	return clampf(resource.damage * (1.0 - distance / resource.blast_radius), 0.0, resource.damage)


func _physics_process(delta: float) -> void:
	if _exploded or _fuse_remaining <= 0.0:
		return
	_fuse_remaining -= delta
	if _fuse_remaining <= 0.0:
		explode()


func _ready() -> void:
	# 物理弹道：球体碰撞体；本体 Player 层(2)、仅与 Objects 层(1) 碰撞（全局约束 §4）
	collision_layer = 2
	collision_mask = 1
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.1
	shape.shape = sphere
	add_child(shape)


func _apply_blast_damage() -> void:
	if resource == null:
		return
	# 爆炸瞬间形状查询 blast_radius 内 Objects 层碰撞体（确定性，无需 Area3D 监测延迟）；
	# 结算参考 bullet.gd：目标实现 take_damage 则调用（无方法 = 不可伤，如地形）。
	# 去重：intersect_shape 对同一 collider 的每个相交形状各返回一条结果，按 collider_id 判重。
	# 跳过 group "head"（CS：爆炸无部位倍率）——头 hitbox 是独立 collider 且转发本体，
	# collider_id 判重拦不住"本体+头"组合，不跳过会双结算（98×2=196 脚下秒杀）。
	var sphere := SphereShape3D.new()
	sphere.radius = resource.blast_radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = global_transform
	query.collision_mask = 1  # 仅 Objects 层（全局约束 §4）
	var hits := get_world_3d().direct_space_state.intersect_shape(query)
	var seen := {}  # 已结算的 collider_id
	for hit in hits:
		var target := hit["collider"] as Node
		if target == null or target == self:
			continue
		if seen.has(hit["collider_id"]):
			continue
		if target.is_in_group("head"):
			continue  # 头部 hitbox 转发本体 → 爆炸无头部倍率，跳过防双结算
		seen[hit["collider_id"]] = true
		var dmg := damage_in_radius(global_position.distance_to(target.global_position))
		if dmg > 0.0 and target.has_method("take_damage"):
			target.take_damage(dmg)


# M1 任务11：爆炸视觉（spec §9.8）——生成 ExplosionEffect（火花粒子/闪光/冲击波环）。
# 效果挂在父级而非自身子节点：本雷 explode 立即 queue_free，挂自身下会随父一起释放。
# 位置 = 爆炸点（先 add_child 再设 global_position——按父级变换正确换算，BulletHole 同约定）。
func _spawn_explosion_effect() -> void:
	var parent := get_parent()
	if parent == null:
		return  # 未入树（纯逻辑环境）：不生成视觉
	var effect := ExplosionEffect.new()
	effect.name = "ExplosionEffect"
	parent.add_child(effect)
	effect.global_position = global_position
