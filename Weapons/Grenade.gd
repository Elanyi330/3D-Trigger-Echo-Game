# Weapons/Grenade.gd
# M1 任务4：Grenade 投掷物（抛物线 + 爆炸衰减）
#
# 接口签名按计划 §5 任务4 逐字照抄；数值唯一来源 WeaponResource（weapon_*.tres，禁止硬编码散值，企划书 §4.2.5）。
# 全局约束（计划 §4）：爆炸范围伤害无部位倍率；命中判定对 Objects|Bots 层（collision_mask=5，
# 2026-08-16 M3.1 T0）；纯离线。
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
	# 物理弹道：球体碰撞体；本体 Player 层(2)、与 Objects|Bots 层(5) 碰撞（2026-08-16 M3.1 T0：
	# bot 换层 4 后投掷物碰撞仍命中）
	collision_layer = 2
	collision_mask = 5
	continuous_cd = true  # M2 修复轮2（2026-08-13）：CCD 连续碰撞——15m/s+平台下坠≈0.25m/帧 > 球径 0.2m，
	# 离散检测漏检薄板（平台板 0.4-0.6m/地面）→ 概率穿地。CCD 扫掠根治（代价仅投掷物，可忽略）。
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
	query.collision_mask = 5  # Objects|Bots 层（2026-08-16 M3.1 T0：bot 换层 4 后爆炸仍命中）
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
		# 2026-08-13 友伤过滤（用户拍板：任何阵营内部均无友伤）——爆炸同样不伤友军
		if Enemy.is_friendly_fire("friendly", target):
			continue
		seen[hit["collider_id"]] = true
		var dmg := damage_in_radius(global_position.distance_to(target.global_position))
		if dmg > 0.0 and target.has_method("take_damage"):
			var pen_mult := _penetration_mult(target)
			if pen_mult > 0.0:
				target.take_damage(dmg * pen_mult)


# M2 修复轮2（2026-08-13，用户拍板方案 A）：墙体厚度穿透衰减——替代旧二值 LOS 全挡
# （"雷丢小平台下全挡"反馈根因）。沿"爆心 → 目标胸口参考点"线段以 blast_los_sample_step
# 点采样累计墙厚 T（采样点落在实心几何内 = 计入；半步偏移起点避开爆心贴面歧义）；
# 倍率 = clamp(1 − T/blast_penetration_max, 0, 1)：越厚挡越多、越薄挡越少、3m 全挡。
# exclude 目标自身全部碰撞 RID（本体+子 CollisionObject3D——头 hitbox/躯干胶囊不计入墙厚）。
func _penetration_mult(target: Node) -> float:
	if resource == null or not target is CollisionObject3D:
		return 1.0
	var probe: Vector3 = target.global_position + Vector3(0, resource.blast_los_probe_height, 0)
	var dir: Vector3 = probe - global_position
	var dist: float = dir.length()
	var step := resource.blast_los_sample_step
	if dist < step:
		return 1.0
	var exclude: Array[RID] = [(target as CollisionObject3D).get_rid()]
	for child in target.get_children():
		if child is CollisionObject3D:
			exclude.append((child as CollisionObject3D).get_rid())
	var inside := 0
	var space := get_world_3d().direct_space_state
	var k := 0.5  # 半步偏移起点
	while k * step < dist:
		var p: Vector3 = global_position + dir * (k * step / dist)
		var pq := PhysicsPointQueryParameters3D.new()
		pq.position = p
		pq.collision_mask = 5  # Objects|Bots 层（2026-08-16 M3.1 T0：bot 换层 4 后穿透采样同口径）
		pq.exclude = exclude
		if not space.intersect_point(pq).is_empty():
			inside += 1
		k += 1.0
	var thickness := float(inside) * step
	return clampf(1.0 - thickness / resource.blast_penetration_max, 0.0, 1.0)


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
