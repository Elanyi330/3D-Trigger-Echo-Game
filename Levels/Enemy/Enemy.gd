# Levels/Enemy/Enemy.gd
# M1.5：训练/对战敌人（静态桩，无 AI——M3 才做寻路/感知/对枪）。
# 视觉：Soldier_Echo 方块角色（仅换色区分敌我，企划书角色规范）。
# 部位判定：躯干 capsule（group "torso"）+ 独立头部 hitbox（group "head"，转发伤害到本体）
#   ——hitscan 爆头 ×4（WeaponCore 部位 Group 判定）；手雷 AoE 双命中为已知可接受边界。
# 接口：take_damage(dmg)（WeaponManager/Grenade/Melee 约定）+ died 信号 + 头顶血条。
class_name Enemy
extends StaticBody3D

signal died

const FALL_TIME := 0.3   # 倒地时长（s）
const FADE_TIME := 0.5   # 淡出时长（s）

@export var max_health: float = 100.0  # 企划书：所有单位统一 100HP
@export var tint: Color = Color(0.65, 0.25, 0.22)  # 敌方红（队友绿/玩家本色）

var health: float = 100.0
var dead: bool = false

var _fall_remaining := 0.0
var _fade_remaining := 0.0
var _died_fired := false
var _visual: Node3D
var _label: Label3D


func _ready() -> void:
	health = max_health
	collision_layer = 1  # Objects 层（hitscan/近战/爆炸 mask=1 命中）
	collision_mask = 0
	add_to_group("torso")
	# 躯干碰撞（胶囊，对齐 1.83m CS 身高角色：覆盖腿+躯干至颈，CS 比例）
	var body_shape := CollisionShape3D.new()
	var caps := CapsuleShape3D.new()
	caps.radius = 0.31
	caps.height = 1.54
	body_shape.shape = caps
	body_shape.position = Vector3(0, 0.92, 0)
	add_child(body_shape)
	# 头部 hitbox（独立 body，group "head"，转发伤害到本体 → hitscan 爆头 ×4；贴合 1.83m 角色头部）
	var head := HeadHitbox.new()
	head.enemy = self
	head.position = Vector3(0, 1.70, 0)
	add_child(head)
	# 视觉：Soldier_Echo 换色
	var char_scene: PackedScene = load("res://Assets/Models/Characters/Soldier_Echo/Soldier_Echo.glb")
	_visual = char_scene.instantiate()
	_tint(_visual)
	add_child(_visual)
	_equip_random_weapon()  # M1.5：随机配备一款武器（第三人称持枪姿态，握法与玩家一致）
	# 血条
	_label = Label3D.new()
	_label.position = Vector3(0, 2.1, 0)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 64
	_label.outline_size = 8
	_update_label()
	add_child(_label)


# M1.5：随机武器配备（用户：查看第三人称角色持枪表现）——真实尺寸 + 真实握把挂接，
# 与 1.83m（CS 身高）角色比例统一适配。每件武器：右臂前摆 + 武器挂 Hand_R（GripRight=原点即握把）。
const ENEMY_WEAPONS := [  # 路径 → 武器在手中的 (位移, 欧拉角°)；wrot 翻正枪口朝前、贴右手
	{"path": "res://Assets/Models/Weapons/Rifle/AK47_Echo/AK47_Echo.glb", "pos": Vector3(0, 0, 0), "rot": Vector3(25, 180, 0)},
	{"path": "res://Assets/Models/Weapons/Pistol/Glock18_Echo/Glock18_Echo.glb", "pos": Vector3(0, 0, 0), "rot": Vector3(25, 180, 0)},
	{"path": "res://Assets/Models/Weapons/Melee/Knife_Echo/Knife_Echo.glb", "pos": Vector3(0, 0, 0), "rot": Vector3(25, 180, 0)},
	{"path": "res://Assets/Models/Weapons/Throwable/Grenade_M67_Echo/Grenade_M67_Echo.glb", "pos": Vector3(0, 0, 0), "rot": Vector3(25, 180, 0)},
]
const ARM_RAISE_DEG := -50.0  # 右臂前摆角（UpperArm_R 局部 X）


func _equip_random_weapon() -> void:
	var skel := _find_skeleton(_visual)
	if skel == null:
		return
	# 右臂前摆（持枪姿态）
	var ua := skel.find_bone("UpperArm_R")
	if ua >= 0:
		skel.set_bone_pose_rotation(ua, Quaternion.from_euler(Vector3(deg_to_rad(ARM_RAISE_DEG), 0.0, 0.0)))
	# 随机选一款，挂右手骨（GripRight=武器原点即握把，真实尺寸——与角色比例统一适配）
	var cfg: Dictionary = ENEMY_WEAPONS[randi() % ENEMY_WEAPONS.size()]
	var ba := BoneAttachment3D.new()
	ba.bone_name = "Hand_R"
	skel.add_child(ba)
	var w: Node3D = load(cfg["path"]).instantiate()
	ba.add_child(w)
	w.position = cfg["pos"]
	w.rotation = Vector3(deg_to_rad(cfg["rot"].x), deg_to_rad(cfg["rot"].y), deg_to_rad(cfg["rot"].z))


func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var r := _find_skeleton(c)
		if r:
			return r
	return null


func _tint(n: Node) -> void:
	if n is MeshInstance3D:
		var m := StandardMaterial3D.new()
		m.albedo_color = tint
		m.roughness = 0.75
		n.material_override = m
	for c in n.get_children():
		_tint(c)


func take_damage(dmg: float) -> void:
	if dead:
		return
	health -= dmg
	_update_label()
	if health <= 0.0:
		_die()


func _update_label() -> void:
	if _label:
		_label.text = "%d" % maxi(0, int(ceil(health)))


func _die() -> void:
	dead = true
	_fall_remaining = FALL_TIME
	_fade_remaining = FALL_TIME + FADE_TIME
	if not _died_fired:
		_died_fired = true
		died.emit()


func _physics_process(delta: float) -> void:
	if not dead:
		return
	if _fall_remaining > 0.0:
		_fall_remaining -= delta
		if _visual:
			_visual.rotation.x = lerp(_visual.rotation.x, -PI * 0.5, 10.0 * delta)  # 前倾倒地
	_fade_remaining -= delta
	if _fade_remaining < FADE_TIME and _visual:
		var t := clampf(_fade_remaining / FADE_TIME, 0.0, 1.0)
		_visual.scale = Vector3.ONE * maxf(t, 0.001)
	if _fade_remaining <= 0.0:
		queue_free()


## 头部 hitbox：group "head"（爆头 ×4），take_damage 转发到 Enemy 本体。
class HeadHitbox extends StaticBody3D:
	var enemy: Enemy
	func _ready() -> void:
		collision_layer = 1
		collision_mask = 0
		add_to_group("head")
		var cs := CollisionShape3D.new()
		var sp := SphereShape3D.new()
		sp.radius = 0.18
		cs.shape = sp
		add_child(cs)
	func take_damage(dmg: float) -> void:
		if enemy:
			enemy.take_damage(dmg)
