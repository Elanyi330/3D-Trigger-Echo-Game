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
const SPAWN_PROTECTION := 2.0  # 出生保护（2026-08-13 用户拍板）：刚复活 2s 无敌 + 全身白闪

@export var max_health: float = 100.0  # 企划书：所有单位统一 100HP
@export var tint: Color = Color(0.65, 0.25, 0.22)  # 敌方红（队友绿/玩家本色）
@export var is_enemy: bool = true  # 阵营标记（小地图红绿 + 阵营级友伤过滤的阵营来源）
@export var display_name: String = ""  # 头顶英文名（2026-08-13 用户拍板：取消血量显示，改显示名字）

var health: float = 100.0
var dead: bool = false
var spawn_protection: float = 0.0  # 出生保护剩余（>0 免伤 + 白闪）

var _fall_remaining := 0.0
var _fade_remaining := 0.0
var _died_fired := false
var _visual: Node3D
var _label: Label3D
var _flash_mats: Array = []  # [{mat: StandardMaterial3D, base: Color}] 保护白闪用（_ready 缓存）


## 阵营查询（2026-08-13 阵营级友伤过滤接口）：角色阵营 = "enemy"/"friendly"。
## 玩家侧由 PlayerLife.get_faction() 提供 "friendly"（同一鸭子接口）。
func get_faction() -> String:
	return "enemy" if is_enemy else "friendly"


## 更新头顶名（重开换名/运行时改名；标签已建时同步刷新）
func set_display_name(n: String) -> void:
	display_name = n
	if _label:
		_label.text = n


## 友伤过滤通用谓词（2026-08-13 用户拍板：**任何阵营内部均无友伤**，为 M3 预留设计）：
## 射击方阵营 == 目标阵营 → 跳过伤害。M2 玩家武器系统以 "friendly" 射击；
## M3 队友 AI 同样 "friendly"（不打玩家/队友）；M3 敌人 AI 以 "enemy" 射击
## （不打敌人，可打玩家/友军——玩家/友军 get_faction()=="friendly" ≠ "enemy"）。
## 穿透头部 hitbox：hitscan 爆头命中 HeadHitbox（group "head"，转发伤害到本体），
## 其自身无阵营接口——取其 enemy 引用判断（2026-08-13 用户反馈爆头友军死亡 bug 根因）。
## 无阵营目标（地形/训练靶）不拦（返回 false）。
static func is_friendly_fire(shooter_faction: String, target: Node) -> bool:
	var faction_target: Node = target
	if target != null and target.is_in_group("head") and target.get("enemy") != null:
		faction_target = target.get("enemy")
	if faction_target != null and faction_target.has_method("get_faction"):
		return faction_target.get_faction() == shooter_faction
	return false


func _ready() -> void:
	health = max_health
	# 注意：出生保护由生成方显式设置（L_M2 spawn 时 spawn_protection = SPAWN_PROTECTION）——
	# 不在 _ready 默认开启：既有测试与训练场场景的 Enemy 直建实例不受影响。
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
	# 视觉：Soldier_Echo 换色（缓存材质供出生保护白闪）
	var char_scene: PackedScene = load("res://Assets/Models/Characters/Soldier_Echo/Soldier_Echo.glb")
	_visual = char_scene.instantiate()
	_tint(_visual)
	add_child(_visual)
	_equip_random_weapon()  # M1.5：随机配备一款武器（第三人称持枪姿态，握法与玩家一致）
	# 头顶名字标签（2026-08-13：取消血量显示，改为显示英文名）
	_label = Label3D.new()
	_label.position = Vector3(0, 2.1, 0)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 36
	_label.outline_size = 8
	_label.modulate = Color(1, 1, 1)
	_label.text = display_name if display_name != "" else "???"
	add_child(_label)


# M1.75：随机武器配备——统一 GripRig 持握（与玩家/队友同一组件同一数据表）。
# 持握姿态（双手据枪/单手持/竖持刀/掌心雷）由 GripRig.GRIP_STYLE 唯一定义，IK 双手到握把标记。
const ENEMY_WEAPONS := [
	"res://Assets/Models/Weapons/Rifle/AK47_Echo/AK47_Echo.glb",
	"res://Assets/Models/Weapons/Pistol/Glock18_Echo/Glock18_Echo.glb",
	"res://Assets/Models/Weapons/Melee/Knife_Echo/Knife_Echo.glb",
	"res://Assets/Models/Weapons/Throwable/Grenade_M67_Echo/Grenade_M67_Echo.glb",
]

var _rig: GripRig

func _equip_random_weapon() -> void:
	var skel := _find_skeleton(_visual)
	if skel == null:
		return
	_rig = GripRig.new()
	_rig.name = "GripRig"
	add_child(_rig)
	_rig.setup(skel)
	_rig.equip(load(ENEMY_WEAPONS[randi() % ENEMY_WEAPONS.size()]))


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
		_flash_mats.append({"mat": m, "base": tint})
	for c in n.get_children():
		_tint(c)


func take_damage(dmg: float) -> void:
	if dead or spawn_protection > 0.0:
		return  # 出生保护（2026-08-13 用户拍板）：2s 无敌
	health -= dmg
	if health <= 0.0:
		_die()


func _die() -> void:
	dead = true
	_fall_remaining = FALL_TIME
	_fade_remaining = FALL_TIME + FADE_TIME
	if not _died_fired:
		_died_fired = true
		died.emit()


func _physics_process(delta: float) -> void:
	if not dead:
		# 出生保护白闪（2026-08-13 用户拍板：2s 内全身白色闪烁）
		if spawn_protection > 0.0:
			spawn_protection = maxf(spawn_protection - delta, 0.0)
			_apply_flash()
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


## 出生保护白闪：全身材质在基色与白色间快速脉冲；保护结束复位基色。
func _apply_flash() -> void:
	var pulse: float = 0.5 + 0.5 * sin(spawn_protection * 24.0)
	for entry in _flash_mats:
		var m: StandardMaterial3D = entry["mat"]
		var base: Color = entry["base"]
		m.albedo_color = base.lerp(Color.WHITE, pulse)


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
