# 实施计划：M2 战斗手感三项修复（手雷 LOS + 投掷手感 / 近战连击窗口+stab 射程 / _in_cone 垂直差）

> 日期：2026-08-13 · 分支 feat/m1-assets · 设计文档：`docs/superpowers/specs/2026-08-13-m2-melee-grenade-fixes-design.md`（用户已批准）
> 账本：`docs/superpowers/ledger/2026-08-13-m2-melee-grenade-fixes-ledger.md`
> 实施环境：**单目录** `/Users/elanyi/Projects/Trigger-Echo`（勿建 worktree，用户 2026-08-10 拍板）

## 〇、目标

三项战斗手感优化（全部 TDD 先行，数值唯一来源 .tres）：

1. **手雷 LOS 墙体挡伤**：爆炸伤害被墙体遮挡（CS 全遮挡语义）
2. **手雷投掷手感**：蓄力抛物线起自右手雷处（视图模型实时位置）、向视角中间目标点延伸（视线射线瞄点）、弧线完整可见、落点=首次触地插值点+竖直落点线；**预览与真实轨迹单一来源一致**
3. **近战**：连击窗口 0.8s 严格化（过期回首挥 40）；重刺射程分级 stab 1.6m < slash 2.0m（CS 权威）；`_in_cone` 垂直差上限 1.5m（脚部-脚部）

## 一、架构（改动文件清单）

| 文件 | 改动 |
|---|---|
| `Weapons/Weapon_Resource.gd` | +4 字段（melee_combo_window/melee_stab_range/melee_vertical_range/blast_los_probe_height） |
| `Weapons/weapon_knife.tres` | +3 值（0.8/1.6/1.5） |
| `Weapons/weapon_m67.tres` | +1 值（1.0） |
| `Weapons/MeleeController.gd` | 连击窗口计时 / _pending_range 捕获 / _in_cone 垂直判定+range 参数 |
| `Weapons/Grenade.gd` | `_apply_blast_damage` LOS 射线（exclude 本体+子 CollisionObject3D RID） |
| `Weapons/WeaponManager.gd` | `_launch_params()` 单一来源 + 瞄点射线 + `set_weapon_view` 接线 + 2 export（30/25） |
| `Player/WeaponView.gd` | `get_throw_origin()` + setup 时接线 manager.set_weapon_view(self) |
| `Weapons/ThrowTrajectory.gd` | STEP 1/60、POINT_COUNT 200、落地穿越插值、竖直落点线、环 0.3 |
| `test/unit/test_melee.gd` | +5 测试（连击窗口×1/stab 射程×2/垂直差×2） |
| `test/unit/test_grenade_los.gd` | 新文件：+6 测试 |
| `test/unit/test_throw_trajectory.gd` | 重写（新积分/落地语义） |
| `test/unit/test_weapon_manager.gd` | +1 测试（launch_params 单一来源一致性） |

## 二、全局约束（精确值，逐字复制）

- 数值唯一来源 `.tres`：melee_combo_window=**0.8**、melee_stab_range=**1.6**、melee_vertical_range=**1.5**、blast_los_probe_height=**1.0**。代码中禁止硬编码这些值。
- WeaponManager export：throw_strength=15.0（既有）、throw_aim_max_dist=**30.0**、throw_aim_fallback_dist=**25.0**。
- ThrowTrajectory：STEP_SECONDS=**1.0/60.0**、POINT_COUNT=**200**、DASH_RATIO=0.7（既有）。
- MeleeController 常量：`const EYE_HEIGHT := 1.63`（CS 站立眼位 64u≈1.63，与 GripRig.EYE_Y/Crouch 相机全局高同源）。
- 重力：`ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)` 唯一来源（既有）。
- 射线/查询 mask=1（仅 Objects 层）；Grenade/玩家 body 层 2；命中判定跳过 group "head"（既有铁律）。
- 测试数基线：276（25 脚本）→ 完成后 ~296+；测试断言需用容差（浮点）。

## 三、任务拆解

### T1 资源字段（机械；最便宜模型）

**接口-消费**：Weapon_Resource.gd 现有 @export 字段模式（`melee_*` 段与 `blast_radius` 行）。

**接口-产出**：4 个新字段可在 .tres 中赋值并在测试中读取。

**修改**（精确代码）：

1. `Weapons/Weapon_Resource.gd` —— 在 `melee_heavy_hit_delay` 行（现最后一行）之后追加：

```gdscript
# M2 手感修复（2026-08-13）：近战连击窗口（s）——自挥击发起帧计时，窗口内轻击=连击 25，超时重置首挥 40。
@export var melee_combo_window: float = 0.8
# M2 手感修复（2026-08-13）：重刺射程分级（m）——CS 权威 stab 32u≈1.6 短于 slash 48u≈2.0
# （docs/superpowers/reference/cs2-weapon-data.md 近战表"攻击距离"行：CS 重刺前送触及短于斜挥弧线）。
@export var melee_stab_range: float = 0.0
# M2 手感修复（2026-08-13）：近战垂直差上限（m，脚部-脚部）——1.5 允许同层/1.2m 摊阁/0.6m 祭坛台，
# 禁止 2.5m 望楼 / 3.0m 回廊隔层刀人。
@export var melee_vertical_range: float = 0.0
# M2 手感修复（2026-08-13）：手雷爆炸 LOS 探测点高度（m，目标脚部上方=胸口参考点）——
# LOS 射线打此点而不打脚部：防贴地射线打中地板造成假遮挡。
@export var blast_los_probe_height: float = 1.0
```

2. `Weapons/weapon_knife.tres` —— 在 `melee_heavy_hit_delay = 0.45` 行之后追加：

```
melee_combo_window = 0.8
melee_stab_range = 1.6
melee_vertical_range = 1.5
```

3. `Weapons/weapon_m67.tres` —— 在 `blast_radius = 8.89` 行之后追加：

```
blast_los_probe_height = 1.0
```

**验证**：`godot --headless --path . -s addons/gut/gut_cmdln.gd` 全绿（字段纯新增，无行为变化；276 基线不降）。

### T2 MeleeController 三项（标准模型；TDD RED→GREEN）

**接口-消费**：weapon_knife.tres 新字段（T1 产出）；test_melee.gd 夹具（`_ready_melee`/`_await_hit(heavy)`/`_await_cooldown(seconds)`/`_front_target`/`_set_targets`/`last_hit_damage`）。

**接口-产出**：`_in_cone(target_pos: Vector3, origin_pos: Vector3, facing: Vector3, range_val: float) -> bool`（签名变更）；`_resolve_swing(base_damage: float, range_val: float)`（签名变更）。

**RED（先写失败测试）**——`test/unit/test_melee.gd` 末尾追加第 7 节：

```gdscript
# ================= 7. M2 手感修复：连击窗口 / stab 射程 / 垂直差 =================
func test_combo_resets_after_window_expiry() -> void:
	await _ready_melee()
	var t := _front_target()
	manager.try_fire()  # 首挥 40
	await _await_hit(false)
	assert_almost_eq(t.health, 100.0 - knife.melee_primary_damage, 0.001, "首挥 40")
	await _await_cooldown(knife.melee_light_time)
	manager.try_fire()  # 窗口内（自首挥 0.4s < 0.8s）→ 连击 25
	await _await_hit(false)
	assert_almost_eq(t.health, 100.0 - knife.melee_primary_damage - knife.melee_secondary_damage,
			0.001, "窗口内连击 25")
	# 自第二次挥击起等窗口过期（0.8s + 0.1s 余量）→ 第三击回首挥 40（用信号断言防血量到 0）
	await _await_cooldown(knife.melee_combo_window + 0.1)
	manager.try_fire()
	await _await_hit(false)
	assert_almost_eq(last_hit_damage, knife.melee_primary_damage, 0.001,
			"窗口过期后回首挥 40（非连击 25）")


func test_stab_range_shorter_than_slash() -> void:
	await _ready_melee()
	var t := Target.new()
	add_child_autofree(t)
	t.position = Vector3(0, 0, -(knife.melee_stab_range + 0.2))  # 1.8m：> stab 1.6、< 轻击 2.0
	t.rotation = Vector3(0, PI, 0)
	_set_targets(t)
	manager.set_aim(true)  # 重刺
	await _await_hit(true)
	assert_almost_eq(t.health, 100.0, 0.001, "1.8m > stab 射程 1.6 → 重刺不命中")
	await _await_cooldown(knife.melee_heavy_time)
	manager.try_fire()  # 同 1.8m 轻击（射程 2.0）→ 命中首挥 40
	await _await_hit(false)
	assert_almost_eq(t.health, 100.0 - knife.melee_primary_damage, 0.001, "同距轻击命中 40")


func test_stab_hits_within_stab_range() -> void:
	await _ready_melee()
	var t := Target.new()
	add_child_autofree(t)
	t.position = Vector3(0, 0, -(knife.melee_stab_range - 0.2))  # 1.4m < 1.6
	t.rotation = Vector3(0, PI, 0)
	_set_targets(t)
	manager.set_aim(true)
	await _await_hit(true)
	assert_almost_eq(t.health, 100.0 - knife.melee_stab_damage, 0.001, "1.4m ≤ stab 射程 → 重刺命中 65")


func test_vertical_cap_blocks_cross_level_knifing() -> void:
	await _ready_melee()
	origin.position = Vector3(0, 1.63, 0)  # 眼位（脚部 0）
	var t := Target.new()
	add_child_autofree(t)
	t.position = Vector3(0, 2.5, -1.5)  # 目标站 2.5m 望楼（水平 1.5m 在射程内）
	t.rotation = Vector3(0, PI, 0)
	_set_targets(t)
	manager.try_fire()
	await _await_hit(false)
	assert_almost_eq(t.health, 100.0, 0.001, "2.5m 高差 > 1.5 → 隔层不命中")


func test_vertical_cap_allows_one_step_difference() -> void:
	await _ready_melee()
	origin.position = Vector3(0, 1.63, 0)
	var t := Target.new()
	add_child_autofree(t)
	t.position = Vector3(0, 1.2, -1.5)  # 1.2m 摊阁级（脚部 y=1.2，水平 1.5m）
	t.rotation = Vector3(0, PI, 0)
	_set_targets(t)
	manager.try_fire()
	await _await_hit(false)
	assert_almost_eq(t.health, 100.0 - knife.melee_primary_damage, 0.001, "1.2m 位差 ≤ 1.5 → 命中 40")
```

**GREEN（实现）**——`Weapons/MeleeController.gd` 精确改动：

1. 文件头注释区后（`var _pending_timer` 行后）追加常量与变量：

```gdscript
# M2 手感修复（2026-08-13）：CS 站立眼位 64u≈1.63m（GripRig.EYE_Y / Crouch 相机全局高同源）——
# _in_cone 垂直判定需把眼位原点换算回脚部（脚部-脚部比较）。
const EYE_HEIGHT := 1.63
```

在 `var _pending_timer: float = 0.0` 行后追加：

```gdscript
var _combo_timer: float = 0.0  # 连击窗口倒计时（s，自挥击发起帧；≤0 = 窗口过期，下一击回首挥）
var _pending_range: float = 0.0  # 待结算挥击射程（轻=melee_range / 重=melee_stab_range，挥击时捕获）
```

2. `try_swing` 中 `_pending_timer = ...` 行后追加：

```gdscript
	_pending_range = _resource.melee_range if light else _resource.melee_stab_range
```

3. `_light_damage` 整体替换为：

```gdscript
func _light_damage() -> float:
	if _combo_timer <= 0.0:
		_combo_secondary = false  # 连击窗口过期：重置回首挥 40（严格化——原实现无条件交替）
	var d := _resource.melee_primary_damage if not _combo_secondary else _resource.melee_secondary_damage
	_combo_secondary = not _combo_secondary  # 每次轻击交替（CS2 左挥/右挥连击）
	_combo_timer = _resource.melee_combo_window  # 窗口自挥击发起帧刷新
	return d
```

4. `_physics_process` 中 `_cooldown` 递减块后追加：

```gdscript
	if _combo_timer > 0.0:
		_combo_timer = maxf(0.0, _combo_timer - delta)
```

5. `_resolve_swing` 签名改为 `func _resolve_swing(base_damage: float, range_val: float) -> void`，其中 `_in_cone` 调用行改为 `if not _in_cone(target.global_position, o, facing, range_val):`；调用处（`_physics_process` 延迟命中块）改为 `_resolve_swing(_pending_damage, _pending_range)`。

6. `_in_cone` 签名与开头改为（其余不变）：

```gdscript
func _in_cone(target_pos: Vector3, origin_pos: Vector3, facing: Vector3, range_val: float) -> bool:
	# M2 手感修复（2026-08-13）：垂直差上限（脚部-脚部）——origin 是眼位相机，减 EYE_HEIGHT 换算脚部；
	# ≤1.5 允许同层（0）/1.2m 摊阁（1.2）/0.6m 祭坛台（0.6）；禁止 2.5m 望楼 / 3.0m 回廊隔层刀人。
	if absf(target_pos.y - (origin_pos.y - EYE_HEIGHT)) > _resource.melee_vertical_range:
		return false
```

并将其中 `if dist > _resource.melee_range:` 改为 `if dist > range_val:`。

**验证**：`godot --headless --path . -s addons/gut/gut_cmdln.gd`——新增 5 测试绿 + 既有 test_melee/test_damage_dedup 全绿（注意既有 `test_hits_feet_origin_enemy_from_eye_height`：origin.y=1.63 换算脚部 0，目标 y=0 → 差 0 ✓ 不受影响）。

### T3 手雷 LOS（标准模型；TDD RED→GREEN）

**接口-消费**：weapon_m67.tres `blast_los_probe_height`（T1）；Enemy 结构（躯干胶囊本体 + HeadHitbox 独立 StaticBody3D 子节点，group "head"）。

**接口-产出**：`Grenade._los_blocked(target: Node) -> bool`（私有；`_apply_blast_damage` 消费）。

**RED（先写失败测试）**——新文件 `test/unit/test_grenade_los.gd`：

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

**GREEN（实现）**——`Weapons/Grenade.gd`：`_apply_blast_damage` 中 `if dmg > 0.0 and target.has_method("take_damage"):` 行改为：

```gdscript
		if dmg > 0.0 and target.has_method("take_damage") and not _los_blocked(target):
			target.take_damage(dmg)
```

文件末尾（`_spawn_explosion_effect` 前）新增：

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

**验证**：新增 6 测试绿；test_damage_dedup（脚下 98 不秒杀）回归绿。

### T4 投掷手感（标准模型；多文件协调，TDD RED→GREEN）

**接口-消费**：ThrowTrajectory.update_trajectory(origin, direction, strength) 既有签名；WeaponView.view_model（ViewModel 实例）；Grenade.init(origin, direction, strength) 既有签名。

**接口-产出**：
- `WeaponManager.set_weapon_view(view: Node) -> void`
- `WeaponManager._launch_params() -> Dictionary`（{"origin": Vector3, "direction": Vector3}；预览与 Grenade.init 共用）
- `WeaponManager._throw_origin() -> Vector3`、`WeaponManager._aim_point() -> Vector3`
- `WeaponView.get_throw_origin() -> Variant`（Vector3 或 null）

**RED**——`test/unit/test_throw_trajectory.gd` **整体重写**为：

```gdscript
# test/unit/test_throw_trajectory.gd
# M1 任务8：ThrowTrajectory 投掷抛物线预览测试（TDD RED 先行）
# M2 手感修复（2026-08-13）重写：
#   - 积分步长 STEP_SECONDS=1/60（=物理帧长，与 RigidBody3D 同构）、点列上限 POINT_COUNT=200（3.33s）
#   - 落地判定 = 首次穿越 y≤0 线性插值（旧"末点投影 y=0"作废——长弧浮空错标）
#   - 可见点列截至触地点（最后一点 y>0，不画入地下）；不落地兜底 = 末点投影
# 行为：半隐式欧拉积分（重力与 Grenade 同源 default_gravity）；首点 = 投掷原点。
# 全局约束：不硬编码散值——期望由解析式 + ProjectSettings 重力派生；
#   Vector3 断言按分量比较（GUT assert_almost_eq 不支持 Vector3 操作数）。
extends GutTest

var trajectory: ThrowTrajectory


func before_each() -> void:
	trajectory = ThrowTrajectory.new()
	add_child_autofree(trajectory)


# ================= 1. 常量 =================
func test_step_and_point_count_constants() -> void:
	assert_almost_eq(ThrowTrajectory.STEP_SECONDS, 1.0 / 60.0, 0.00001, "积分步长 = 物理帧长（同构）")
	assert_eq(ThrowTrajectory.POINT_COUNT, 200, "点列上限 200（3.33s 覆盖垂直抛 3.06s）")


# ================= 2. 点列生成（落地截止） =================
func test_generates_points_until_ground_crossing() -> void:
	# dt=1/60 平抛 y=2：t_land=√(2·2/g)≈0.6389s → y>0 的 i<38.33 → 39 点（i=0..38，解析确定）
	var origin := Vector3(0, 2, 0)
	trajectory.update_trajectory(origin, Vector3(0, 0, -1), 15.0)
	assert_eq(trajectory.points.size(), 39, "落地前点列 = 39 点（解析确定）")
	assert_eq(trajectory.points[0], origin, "首点 = 投掷原点")
	assert_lt(trajectory.points[1].z, 0.0, "水平沿投掷方向（-Z）")
	assert_gt(trajectory.points[38].y, 0.0, "最后可见点在空中（不画入地下）")


# ================= 3. 落地穿越插值 =================
func test_landing_point_is_ground_crossing_interpolation() -> void:
	# 落点 = 穿越区间线性插值：y 精确 0；x/z 与解析值 15×t_land 容差 0.25（单步穿越离散化误差）
	var origin := Vector3(0, 2, 0)
	trajectory.update_trajectory(origin, Vector3(0, 0, -1), 15.0)
	assert_eq(trajectory.landing_point.y, 0.0, "落点 y = 地面 0（插值穿越点）")
	var g: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
	var t_land := sqrt(2.0 * 2.0 / g)
	assert_almost_eq(trajectory.landing_point.z, -15.0 * t_land, 0.25, "落点 z ≈ 解析平抛距离")
	assert_almost_eq(trajectory.landing_point.x, 0.0, 0.001, "无横向漂移")


func test_vertical_throw_lands_within_coverage() -> void:
	# 90° 上抛 t_land=(15+√(15²+2·9.8·2))/9.8≈3.19s → ~192 点 < 200 上限
	trajectory.update_trajectory(Vector3(0, 2, 0), Vector3(0, 1, 0), 15.0)
	assert_lt(trajectory.points.size(), ThrowTrajectory.POINT_COUNT, "垂直抛在点列上限内落地")
	assert_eq(trajectory.landing_point.y, 0.0, "垂直抛落点在地面")


# ================= 4. 实时更新 =================
func test_update_with_new_direction_recomputes_points() -> void:
	var origin := Vector3(0, 2, 0)
	trajectory.update_trajectory(origin, Vector3(0, 0, -1), 15.0)
	assert_lt(trajectory.points[1].z, 0.0, "前置：初始视向 -Z")
	trajectory.update_trajectory(origin, Vector3(1, 0, 0), 15.0)
	assert_gt(trajectory.points[1].x, 0.0, "新视向 +X：第 2 点沿 +X")
	assert_almost_eq(trajectory.points[1].z, origin.z, 0.001, "新视向 +X：无 -Z 分量（实时覆盖）")


func test_update_with_new_origin_moves_arc() -> void:
	trajectory.update_trajectory(Vector3(0, 2, 0), Vector3(0, 0, -1), 15.0)
	var before: Vector3 = trajectory.points[5]
	trajectory.update_trajectory(Vector3(0, 5, 0), Vector3(0, 0, -1), 15.0)
	assert_almost_eq(trajectory.points[5].x, before.x, 0.001, "原点抬高：x 不变")
	assert_almost_eq(trajectory.points[5].y, before.y + 3.0, 0.001, "原点抬高 3m → y 上移 3m")
	assert_almost_eq(trajectory.points[5].z, before.z, 0.001, "原点抬高：z 不变")
```

`test/unit/test_weapon_manager.gd` 末尾追加（在 `_find_grenade`/`_trajectory` 夹具之后区域、按文件现有分节追加新节）：

```gdscript
# ================= 7. M2 手感修复：投掷 launch 单一来源 =================
func test_launch_params_feed_preview_and_grenade_consistently() -> void:
	_with_camera()
	manager = _build_manager([ak, glock, knife, m67])
	await _deploy_m67()
	Input.action_press("fire")
	await wait_physics_frames(2)
	var lp: Dictionary = manager._launch_params()
	var traj := _trajectory()
	assert_eq(traj.points[0], lp["origin"], "预览原点 = 发射原点（单一来源）")
	var v0: Vector3 = (lp["direction"] as Vector3) * manager.throw_strength
	var dt := ThrowTrajectory.STEP_SECONDS
	var g: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
	# 预览第 2 点 = 半隐式欧拉一步（同公式同源重力）
	assert_almost_eq(traj.points[1].x, (lp["origin"] as Vector3).x + v0.x * dt, 0.001, "预览 x 与 launch 一致")
	assert_almost_eq(traj.points[1].y, (lp["origin"] as Vector3).y + v0.y * dt - 0.5 * g * dt * dt, 0.001,
			"预览 y 与 launch 一致（重力同源）")
	assert_almost_eq(traj.points[1].z, (lp["origin"] as Vector3).z + v0.z * dt, 0.001, "预览 z 与 launch 一致")
	Input.action_release("fire")
	await wait_physics_frames(2)
	var grenade := _find_grenade()
	assert_not_null(grenade, "松开后生成真实 Grenade")
	assert_almost_eq(grenade.global_position.x, (lp["origin"] as Vector3).x, 0.3,
			"出手位置 = 发射原点（物理 2 帧位移容差）")
	assert_almost_eq(grenade.global_position.z, (lp["origin"] as Vector3).z, 0.3, "出手位置 z = 发射原点")


func test_weapon_view_throw_origin_returns_grenade_mesh_position() -> void:
	var view := WeaponView.new()
	add_child_autofree(view)
	await wait_physics_frames(1)  # _ready 建 view_model
	view.view_model.equip(load("res://Assets/Models/Weapons/Throwable/Grenade_M67_Echo/Grenade_M67_Echo.glb"))
	var o: Variant = view.get_throw_origin()
	assert_not_null(o, "装备手雷后返回投掷原点")
	var p: Vector3 = o
	assert_lt(p.z, 0.0, "手雷原点在相机前方（-Z，WEAPON_FRAME 取景）")
	assert_gt(p.y, -0.5, "手雷原点在画面下方（-Y，右手持雷位）")
```

**GREEN（实现）**——精确改动：

1. `Weapons/WeaponManager.gd`：
   - `throw_strength` export 行后追加两个 export：

```gdscript
# M2 手感修复（2026-08-13）：投掷手感——瞄准点射线距离上限（m）/ 瞄天空回退瞄准距离（m）。
# 投掷方向 = 瞄准点 − 手雷原点（瞄哪打哪）；强度保持 throw_strength 固定（CS 固定投速）。
@export var throw_aim_max_dist: float = 30.0
@export var throw_aim_fallback_dist: float = 25.0
```

   - `var _weapon_view` 声明区（`var _melee: MeleeController` 行后）追加：

```gdscript
var _weapon_view: Node = null  # 投掷原点来源（WeaponView.get_throw_origin；null = 回退相机，测试兼容）
```

   - `set_head` 函数后追加三个函数：

```gdscript
func set_weapon_view(view: Node) -> void:
	# M2 手感修复（2026-08-13）：投掷原点接线——WeaponView.setup 调用；null 回退相机（单元测试环境）。
	_weapon_view = view


func _throw_origin() -> Vector3:
	if _weapon_view != null and _weapon_view.has_method("get_throw_origin"):
		var p: Variant = _weapon_view.get_throw_origin()
		if p != null:
			return p
	return _camera.global_position if _camera != null else Vector3.ZERO


func _aim_point() -> Vector3:
	# 瞄准点 = 相机视线射线命中世界（mask=1）的点；无命中（瞄天空）→ 视向固定距离回退点。
	# 回退点远离时方向≈视向，行为连续；测试环境无相机 → 沿默认视向兜底。
	if _camera == null:
		return Vector3(0, 1, -throw_aim_fallback_dist)
	var dir := -_camera.global_transform.basis.z
	var from := _camera.global_position
	var ray := PhysicsRayQueryParameters3D.create(from, from + dir * throw_aim_max_dist, 1)
	var hit := _camera.get_world_3d().direct_space_state.intersect_ray(ray)
	if not hit.is_empty():
		return hit["position"]
	return from + dir * throw_aim_fallback_dist


func _launch_params() -> Dictionary:
	# 单一来源：预览与真实投掷共用（同原点/方向/强度 → 轨迹一致——设计 §2.3）。
	var origin := _throw_origin()
	var direction := (_aim_point() - origin).normalized()
	return {"origin": origin, "direction": direction}
```

   - `_physics_process` THROWING 分支（`_trajectory.update_trajectory(_camera.global_position, ...)` 两行）替换为：

```gdscript
			elif _trajectory != null and _camera != null:
				var lp := _launch_params()
				_trajectory.update_trajectory(lp["origin"], lp["direction"], throw_strength)
```

   - `_throw_grenade` 中 `grenade.init(_camera.global_position, -_camera.global_transform.basis.z, throw_strength)` 行替换为：

```gdscript
	var lp := _launch_params()
	grenade.init(lp["origin"], lp["direction"], throw_strength)
```

2. `Player/WeaponView.gd`：
   - `setup` 末尾（`_build_body()` 行后）追加：

```gdscript
	manager.set_weapon_view(self)  # M2 手感修复：投掷原点接线（get_throw_origin 提供右手雷位置）
```

   - `_mount` 函数后追加：

```gdscript
func get_throw_origin() -> Variant:
	# M2 手感修复（2026-08-13）：投掷原点 = 视图模型手雷网格中心（右手雷处，随蓄力动画实时跟随）。
	# 返回 null = 当前无武器模型（WeaponManager 回退相机）。
	var weapon := view_model.current_weapon
	if weapon == null:
		return null
	for c in weapon.find_children("*", "MeshInstance3D", true, false):
		return c.global_position
	return null
```

3. `Weapons/ThrowTrajectory.gd`：
   - 常量替换：

```gdscript
const POINT_COUNT := 200  # 预览点列上限（M2 手感修复：50→200；STEP 1/60 → 3.33s 覆盖垂直上抛 3.06s 全弧）
const STEP_SECONDS := 1.0 / 60.0  # 积分步长 = 物理帧长（与 RigidBody3D 积分同构 → 预览≈实际轨迹）
const DASH_RATIO := 0.7  # 虚线：每段画前 70%，留 30% 空隙（更连续醒目）
```

   - `update_trajectory` 整体替换为：

```gdscript
# 沿 origin（投掷原点=右手雷处）/direction（向视角目标点）以 strength 初速积分弹道并刷新渲染。
# M2 手感修复（2026-08-13）：落地判定 = 首次穿越 y≤0 线性插值求精确落点；可见点列截至触地点
# （不再画入地下）；旧"末点投影 y=0"作废（长弧时末点浮空错标）。4s 内不落地兜底 = 末点投影。
func update_trajectory(origin: Vector3, direction: Vector3, strength: float) -> void:
	var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
	var velocity := direction.normalized() * strength
	var position := origin
	points.clear()
	var landed := false
	for i in POINT_COUNT:
		points.append(position)
		velocity.y -= gravity * STEP_SECONDS
		var next := position + velocity * STEP_SECONDS
		if next.y <= 0.0:
			var t := position.y / (position.y - next.y)  # 两已知点线性插值：y=0 处
			landing_point = position.lerp(next, clampf(t, 0.0, 1.0))
			landed = true
			break
		position = next
	if not landed:
		landing_point = position  # 兜底：全程不落地（极端）→ 末点投影（旧行为）
		landing_point.y = 0.0
	_render()
```

   - `_render_landing` 中：`var radius := 0.25` 改 `var radius := 0.3`；`_landing_ring.surface_end()` 前追加竖直落点线：

```gdscript
	# 竖直落点线：可见点列末端 → 落点环（M2 手感修复：落点清晰明了——弧线止于空中点，垂直线指向落点）
	var top := points[points.size() - 1]
	_landing_ring.surface_add_vertex(top)
	_landing_ring.surface_add_vertex(center)
```

   - `_render_landing` 开头防御条件 `if _landing_ring == null or points.size() < 2:` 改为 `if _landing_ring == null or points.is_empty():`（竖直落点线只需 ≥1 点）。

**验证**：新增 3 测试绿 + 既有 test_weapon_manager 投掷测试回归绿（注意：`test_throw_release_spawns_grenade_along_camera` 断言预览起点 = 相机位置——无 WeaponView 接线时回退相机 ✓ 不受影响）。

### T5 回归 + 门禁 + 文档同步（控制器执行，不涉及生产代码）

1. 全量：`godot --headless --path . -s addons/gut/gut_cmdln.gd` → 预期 ~296 全绿（276 基线 + ~20 新增；断言计数波动 ±1 以测试数为准）。
2. 场景冒烟：`godot --headless --path . Levels/M2_TDM/L_M2.tscn --quit-after 120`（无脚本错误退出）。
3. 文档同步（按各司其职）：
   - `docs/FEATURES.md`：§"遗留（M2 前）"三行改为 🟢 已完成（含提交与设计文档引用）；地图与模式节 M2 手雷描述补 LOS。
   - `docs/HANDOFF.md`：运行细节补投掷手感（起自右手雷/瞄哪打哪/落点=首次触地+竖直落点线/墙挡爆炸）；§五 待做移除三项遗留。
   - `docs/PROGRESS.md`：M2 剩余更新（三项遗留完成）。
   - 记忆 `trigger-echo-m2-tdm-map-progress.md`：待做行更新。
4. 实机验证留给用户 playtest（投掷手感/近战隔层/雷伤遮挡为体感项）。

## 四、任务间依赖与派发顺序

```
T1（机械）→ 审查1 → T2（近战）→ 审查2 → T3（手雷LOS）→ 审查3 → T4（投掷手感）→ 审查4 → T5（回归+文档）→ 全分支终审
```

- **禁止并行派发实现子代理**（同仓冲突）；每任务 RED 先行由实现者执行（先写测试看红，再实现看绿）。
- 审查 = 新子代理，两个裁定：规格合规（对照本计划逐行）+ 代码质量；Critical/Major 发现打回实现者修复（≤5 轮）。
- 模型：T1 最便宜；T2-T4 标准；终审最强。
