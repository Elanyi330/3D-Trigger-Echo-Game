# Task Brief: T3 — 手雷爆炸 LOS 墙体挡伤

> 项目：Trigger Echo（Godot 4.7.1 + GDScript + GUT 测试）
> 工作目录：`/Users/elanyi/Projects/Trigger-Echo`（分支 feat/m1-assets，**直接在此目录工作**）
> 父计划：`docs/superpowers/plans/2026-08-13-m2-melee-grenade-fixes.md`（本 brief 为该计划 T3 的完整规格）
> 前置：T1 已完成——`weapon_m67.tres` 已有 `blast_los_probe_height=1.0`。**不要改动 T1/T2 的文件。**

## 目标

手雷爆炸伤害被墙体遮挡：每个半径内目标从爆心打一条 LOS 射线到**胸口参考点**（目标脚部 + `blast_los_probe_height`=1.0m），排除目标自身全部碰撞 RID 后任何剩余命中 → 该目标伤害 0（CS 全遮挡语义，无穿透衰减）。现状 bug：球形查询按距离吃伤，穿墙满伤（M2 v3 设计"棚下段雷不进"依赖此机制）。

## 背景结构（关键坑，务必理解）

- `Levels/Enemy/Enemy.gd`：Enemy 是 StaticBody3D（collision_layer=1，mask=0），躯干胶囊 CollisionShape3D 是其子节点；**HeadHitbox 是独立 StaticBody3D 子节点**（layer 1，group "head"，r=0.18 球，位置 y≈1.70）。两者 RID 不同——射线 exclude 必须同时排除，否则**爆心在头顶上方时射线穿头 hitbox 会自挡**（假遮挡）。
- 地图墙体/地板都在 layer 1（mask=1 射线可打中）。**射线不能打脚部**：贴地爆心→目标脚部的射线会打中地板（y=0 也是 layer 1）→ 全部假遮挡。胸口参考点（y=+1.0）从地面爆心射出是上升射线，不贴地。
- 0.9m 矮墙对贴地爆炸**也遮挡**（射线从 y=0 升到 y=1，中点 ~0.5 < 0.9 墙顶 → 相交即挡，CS trace 语义）；爆心抬高（如 1.2m 摊阁）射线在墙处 ~1.1m > 0.9 → 过顶不挡。两条都有测试固化。

## 全局约束

- 只改 `Weapons/Grenade.gd` + 新建 `test/unit/test_grenade_los.gd`。
- mask=1；数值唯一来源 .tres（damage/blast_radius/blast_los_probe_height，测试派生期望）。
- 既有测试（含 test_damage_dedup.gd 的"脚下爆炸 98 不秒杀"）必须保持全绿。

## TDD 步骤（严格顺序）

### RED 1：先写失败测试

新建 `test/unit/test_grenade_los.gd`（逐字）：

```gdscript
# test/unit/test_grenade_los.gd
# M2 手感修复（2026-08-13）：手雷爆炸 LOS 墙体遮挡（TDD RED 先行）
# 行为（设计 2026-08-13-m2-melee-grenade-fixes-design §一）：
#   - 墙在爆心与目标之间（射线路径相交）→ 伤害 0（CS 全遮挡语义，无穿透衰减）
#   - 无遮挡 → 距离线性衰减满值
#   - 贴地爆炸同层目标不假遮挡（胸口参考点防地板挡射线——回归重点）
#   - 头 hitbox 自挡回归：爆心在头顶上方时射线穿过头 hitbox——exclude 本体+子 CollisionObject3D RID
#   - 矮掩体 0.9 墙：贴地爆炸射线路径相交 → 遮挡（CS trace 语义）；爆心抬高 1.2m → 射线过顶不遮挡
# 全局约束：期望值由 m67.tres 派生（damage/blast_radius），不硬编码散值。
extends GutTest

var m67: WeaponResource
const ENEMY_SCENE := "res://Levels/Enemy/Enemy.tscn"


func before_each() -> void:
	m67 = load("res://Weapons/weapon_m67.tres")


func _spawn_enemy(at: Vector3) -> Enemy:
	var e: Enemy = load(ENEMY_SCENE).instantiate()
	add_child_autofree(e)
	e.global_position = at
	e.rotation.y = PI
	return e


func _wall(center: Vector3, size: Vector3) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.collision_layer = 1
	b.collision_mask = 0
	add_child_autofree(b)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	b.add_child(cs)
	b.global_position = center
	return b


func _explode_at(pos: Vector3) -> void:
	var g := Grenade.new()
	g.resource = m67
	add_child_autofree(g)
	g.init(pos, Vector3(0, 0, -1), 20.0)
	g.explode()


func _dist_damage(dist: float) -> float:
	return m67.damage * (1.0 - dist / m67.blast_radius)


func test_wall_blocks_blast_damage() -> void:
	var e := _spawn_enemy(Vector3(0, 0, -4))
	await wait_physics_frames(2)
	_wall(Vector3(0, 1.5, -2), Vector3(4, 3, 1))  # 爆心(0)与目标(-4)之间：3m 高墙
	_explode_at(Vector3.ZERO)
	assert_almost_eq(e.health, 100.0, 0.001, "墙后目标 0 伤（CS 全遮挡）")


func test_no_wall_full_distance_damage() -> void:
	var e := _spawn_enemy(Vector3(0, 0, -4))
	await wait_physics_frames(2)
	_explode_at(Vector3.ZERO)
	assert_almost_eq(e.health, 100.0 - _dist_damage(4.0), 0.001, "无遮挡 → 距离线性衰减")


func test_ground_blast_does_not_false_block() -> void:
	# 回归：贴地爆炸 + 同层目标——射线打胸口参考点（不打脚部），地板不挡
	var e := _spawn_enemy(Vector3(0, 0, -2))
	await wait_physics_frames(2)
	_wall(Vector3(0, -0.5, 0), Vector3(40, 1, 40))  # 大底板（爆心/目标脚下）
	_explode_at(Vector3.ZERO)
	assert_almost_eq(e.health, 100.0 - _dist_damage(2.0), 0.001, "贴地爆炸无地板假遮挡")


func test_elevated_blast_does_not_self_block_via_head() -> void:
	# 回归：爆心在头顶上方 → 射线穿过头 hitbox（y≈1.70）——exclude 头 RID 防自挡
	var e := _spawn_enemy(Vector3.ZERO)
	await wait_physics_frames(2)
	_explode_at(Vector3(0, 2.5, 0))
	assert_almost_eq(e.health, 100.0 - _dist_damage(2.5), 0.001,
			"头顶爆炸：射线穿头 hitbox 不自挡（exclude 本体+头 RID）")


func test_low_cover_blocks_ground_blast() -> void:
	# 0.9m 矮墙在贴地爆心与目标之间：射线路径相交（射线从 y=0 升到 y=1，中点 ~0.5 < 0.9）→ 遮挡
	var e := _spawn_enemy(Vector3(0, 0, -4))
	await wait_physics_frames(2)
	_wall(Vector3(0, 0.45, -2), Vector3(4, 0.9, 0.6))
	_explode_at(Vector3.ZERO)
	assert_almost_eq(e.health, 100.0, 0.001, "0.9m 矮墙遮挡贴地爆炸（射线相交即挡）")


func test_elevated_blast_clears_low_cover() -> void:
	# 爆心抬高 1.2m（摊阁级）→ 射线在墙处高度 ≈1.1 > 0.9 → 过顶不遮挡
	var e := _spawn_enemy(Vector3(0, 0, -4))
	await wait_physics_frames(2)
	_wall(Vector3(0, 0.45, -2), Vector3(4, 0.9, 0.6))
	_explode_at(Vector3(0, 1.2, 0))
	assert_almost_eq(e.health, 100.0 - _dist_damage(4.0), 0.001, "爆心抬高 → 射线过顶矮墙")
```

运行 GUT 确认这 6 个测试**红**且失败原因正确（墙后仍有伤——现实现无 LOS）。注意：`test_elevated_blast_does_not_self_block_via_head` 可能**意外变绿**（爆心 y=2.5 距目标 2.5 < 半径，现实现穿墙满伤），但其他 5 个必红；若全部绿说明测试夹具写错（如 _explode_at 未真正引爆——检查 resource 赋值在 init 前），排查夹具。

### GREEN：实现（`Weapons/Grenade.gd` 精确改动）

1. `_apply_blast_damage` 中 `if dmg > 0.0 and target.has_method("take_damage"):` 行改为：

```gdscript
		if dmg > 0.0 and target.has_method("take_damage") and not _los_blocked(target):
			target.take_damage(dmg)
```

2. 文件末尾 `_spawn_explosion_effect` 函数之前新增：

```gdscript
# M2 手感修复（2026-08-13）：爆炸 LOS 墙体遮挡（Source RadiusDamage 每受害者 trace 思路，自研实现）。
# 从爆心向目标胸口参考点（脚部 + blast_los_probe_height）打射线——不打脚部：贴地射线会打中地板假遮挡；
# exclude 目标自身全部碰撞 RID（本体 + 子 CollisionObject3D——头 hitbox 是独立 body，不排除会自挡）；
# 任何剩余命中 = 墙体遮挡 → 该目标伤害 0（CS 全遮挡语义，无穿透衰减）。
func _los_blocked(target: Node) -> bool:
	if resource == null or not target is CollisionObject3D:
		return false
	var probe := target.global_position + Vector3(0, resource.blast_los_probe_height, 0)
	var ray := PhysicsRayQueryParameters3D.create(global_position, probe, 1)
	var exclude: Array[RID] = [(target as CollisionObject3D).get_rid()]
	for child in target.get_children():
		if child is CollisionObject3D:
			exclude.append((child as CollisionObject3D).get_rid())
	ray.exclude = exclude
	return not get_world_3d().direct_space_state.intersect_ray(ray).is_empty()
```

### VERIFY（全量）

`cd /Users/elanyi/Projects/Trigger-Echo && godot --headless --path . -s addons/gut/gut_cmdln.gd`
预期：全绿（281 + 6 = 287 测试，若 T2 已合入）。**重点回归**：test_damage_dedup.gd 两个测试必须仍绿（脚下爆炸 98——爆心 y=0 与目标同点：射线 (0,0,0)→(0,1,0) 竖直向上，无几何命中 → 不挡 ✓）。

常见坑（若红）：
- GDScript `Array[RID]` 赋给 `ray.exclude` 类型不匹配 → 用 `var exclude: Array[RID] = [...]` 显式类型（brief 已含）。
- `(target as CollisionObject3D).get_rid()` 语法错误 → 确认 target 是 CollisionObject3D 分支后才调用。
- 测试夹具中 Enemy 未 await 2 物理帧（碰撞体未入空间）→ 射线查询不到头 hitbox。

## 报告格式（最终回复 = 数据，不是给人看的对话）

返回：
- DONE / DONE_WITH_CONCERNS / BLOCKED
- RED 阶段证据（6 新测试红/意外绿情况）
- 改动行号
- 最终全量测试统计行（Tests/Passing/Fails 数）
- 任何规格偏差说明
