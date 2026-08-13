# test/unit/test_damage_dedup.gd
# M1.75：伤害双重结算修复回归测试（TDD RED 先行）
#
# 根因：Enemy 有两个独立碰撞体且都带 take_damage —— 躯干胶囊（本体）+ 头部球（HeadHitbox 转发本体）。
# 近战球扫掠 / 手雷形状查询会同时命中两者 → 每次伤害 ×2（连击 50、重刺 130 秒杀、手雷 196 秒杀）。
# CS 规则：头部 ×4 只属于 hitscan 枪弹；近战与爆炸**无部位倍率** → 结算须跳过 group "head"。
#
# 本文件断言修复后：近战单击只结算一次；手雷脚下爆炸最高 98、不秒杀、只结算一次。
extends GutTest

var knife: WeaponResource
var m67: WeaponResource
var melee: MeleeController
var origin: Node3D

const ENEMY_SCENE := "res://Levels/Enemy/Enemy.tscn"


func before_each() -> void:
	knife = load("res://Weapons/weapon_knife.tres")
	m67 = load("res://Weapons/weapon_m67.tres")
	melee = MeleeController.new()
	add_child_autofree(melee)
	origin = Node3D.new()
	add_child_autofree(origin)
	melee.origin = origin
	origin.position = Vector3(0, 1.63, 0)  # 眼位（M2 手感修复：垂直判定需真实眼高）


func _spawn_enemy(at: Vector3) -> Enemy:
	var e: Enemy = load(ENEMY_SCENE).instantiate()
	add_child_autofree(e)
	e.global_position = at
	e.rotation.y = PI  # 面向攻击者 → 非背刺（背刺 180 会干扰伤害断言）
	return e


func _head_hitbox_of(e: Enemy) -> Node:
	for c in e.get_children():
		if c.is_in_group("head"):
			return c
	return null


# ---- 近战：本体 + 头 hitbox 同被命中，只结算一次（跳过 head）----
func test_melee_single_settle_skips_head() -> void:
	var e := _spawn_enemy(Vector3(0, 0, -1.5))
	await wait_physics_frames(2)
	var head := _head_hitbox_of(e)
	assert_not_null(head, "前置：Enemy 有独立头 hitbox（group head）")
	var arr: Array[Node] = [e, head]  # 复现扫掠同时命中本体+头
	melee.targets = arr
	melee.try_swing(true, knife)  # 轻击首挥 40
	await wait_physics_frames(int(ceil(knife.melee_light_hit_delay * float(Engine.physics_ticks_per_second))) + 2)
	assert_almost_eq(e.health, 100.0 - knife.melee_primary_damage, 0.001,
			"近战只结算一次 40：跳过 head，本体+头不得结算成 80")


# ---- 手雷：脚下爆炸最高 98、只结算一次、不秒杀 ----
func test_grenade_at_feet_max_98_no_instakill() -> void:
	var e := _spawn_enemy(Vector3.ZERO)
	await wait_physics_frames(2)
	assert_not_null(_head_hitbox_of(e), "前置：头 hitbox 存在（会参与爆炸形状查询）")
	var g := Grenade.new()
	g.resource = m67
	add_child_autofree(g)
	g.init(Vector3.ZERO, Vector3(0, 0, -1), 20.0)  # 爆心就在敌人脚下
	g.explode()
	assert_almost_eq(e.health, 100.0 - m67.damage, 0.001,
			"脚下爆炸只结算一次 98：跳过 head，不得双结算成 196")
	assert_false(e.dead, "最高 98 无法秒杀 100HP（CS 规则）")
