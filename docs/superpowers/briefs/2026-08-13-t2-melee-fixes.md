# Task Brief: T2 — MeleeController 三项（连击窗口 / stab 射程 / 垂直差）

> 项目：Trigger Echo（Godot 4.7.1 + GDScript + GUT 测试）
> 工作目录：`/Users/elanyi/Projects/Trigger-Echo`（分支 feat/m1-assets，**直接在此目录工作**）
> 父计划：`docs/superpowers/plans/2026-08-13-m2-melee-grenade-fixes.md`（本 brief 为该计划 T2 的完整规格，不要依赖其他上下文）
> 前置：T1 已完成——`Weapons/weapon_knife.tres` 已有 `melee_combo_window=0.8`、`melee_stab_range=1.6`、`melee_vertical_range=1.5`；`Weapon_Resource.gd` 已有对应 @export 字段。**不要改动 T1 的文件。**

## 目标（三项行为变更，全部 TDD）

1. **连击窗口严格化**：轻击连击（首挥 40 → 连击 25）只在 `melee_combo_window`（0.8s，自挥击发起帧计时）内成立；窗口过期后下一击回首挥 40。现状 bug：`_combo_secondary` 无条件交替（隔 10 秒再挥仍算连击）。
2. **stab 射程分级**：重刺用 `melee_stab_range`（1.6m），轻击仍用 `melee_range`（2.0m）。CS 权威：stab 32u≈1.6 短于 slash 48u≈2.0（cs2-weapon-data.md）。现状 bug：轻重共用 2.0m。
3. **`_in_cone` 垂直差上限**：`abs(target.y − (origin.y − EYE_HEIGHT)) ≤ melee_vertical_range`（1.5m）——**脚部-脚部**（origin 是眼位相机，必须减眼高 1.63 换算脚部；若直接比眼位 y，同层 |0−1.63|=1.63>1.5 会全挡）。禁止 2.5m 望楼/3.0m 回廊隔层刀人；允许同层/1.2m 摊阁/0.6m 祭坛台。

## 全局约束

- 数值唯一来源 .tres（测试派生期望，不硬编码）；新增 `const EYE_HEIGHT := 1.63`（CS 站立眼位 64u，与 Character/GripRig.gd 的 EYE_Y 同源）。
- 只改 `Weapons/MeleeController.gd` 与 `test/unit/test_melee.gd` 两个文件。
- GUT 测试：浮点断言用 assert_almost_eq；既有 276 测试必须保持全绿（其中 test_melee.gd 既有测试不得改动——验证新逻辑不破坏旧行为，特别是 `test_hits_feet_origin_enemy_from_eye_height`：origin.y=1.63 换算脚部 0、目标脚部 0 → 差 0 ✓）。

## TDD 步骤（严格顺序）

### RED 1：先写失败测试

`test/unit/test_melee.gd` 末尾追加第 7 节（逐字，含注释）：

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

运行 GUT 确认这 5 个测试**红**（失败原因正确：连击窗口未重置/stab 距离未分级/垂直未过滤——不是拼写错误），其余 276 绿。

### GREEN：实现（`Weapons/MeleeController.gd` 精确改动）

1. `class_name MeleeController extends Node3D` 之后（信号声明前）追加常量：

```gdscript
# M2 手感修复（2026-08-13）：CS 站立眼位 64u≈1.63m（GripRig.EYE_Y / Crouch 相机全局高同源）——
# _in_cone 垂直判定需把眼位原点换算回脚部（脚部-脚部比较）。
const EYE_HEIGHT := 1.63
```

2. `var _pending_timer: float = 0.0` 行之后追加：

```gdscript
var _combo_timer: float = 0.0  # 连击窗口倒计时（s，自挥击发起帧；≤0 = 窗口过期，下一击回首挥）
var _pending_range: float = 0.0  # 待结算挥击射程（轻=melee_range / 重=melee_stab_range，挥击时捕获）
```

3. `try_swing` 中 `_pending_timer = ...` 行之后追加：

```gdscript
	_pending_range = _resource.melee_range if light else _resource.melee_stab_range
```

4. `_light_damage` 整体替换为：

```gdscript
func _light_damage() -> float:
	if _combo_timer <= 0.0:
		_combo_secondary = false  # 连击窗口过期：重置回首挥 40（严格化——原实现无条件交替）
	var d := _resource.melee_primary_damage if not _combo_secondary else _resource.melee_secondary_damage
	_combo_secondary = not _combo_secondary  # 每次轻击交替（CS2 左挥/右挥连击）
	_combo_timer = _resource.melee_combo_window  # 窗口自挥击发起帧刷新
	return d
```

5. `_physics_process` 中 `_cooldown` 递减块（`if _cooldown > 0.0:` 两行）之后追加：

```gdscript
	if _combo_timer > 0.0:
		_combo_timer = maxf(0.0, _combo_timer - delta)
```

6. `_resolve_swing` 签名改为 `func _resolve_swing(base_damage: float, range_val: float) -> void`；其中 `_in_cone` 调用行改为 `if not _in_cone(target.global_position, o, facing, range_val):`；调用处（`_physics_process` 延迟命中块内）改为 `_resolve_swing(_pending_damage, _pending_range)`。

7. `_in_cone` 签名改为 `func _in_cone(target_pos: Vector3, origin_pos: Vector3, facing: Vector3, range_val: float) -> bool:`，函数体开头（现有注释块之后、`var to_target` 之前）插入：

```gdscript
	# M2 手感修复（2026-08-13）：垂直差上限（脚部-脚部）——origin 是眼位相机，减 EYE_HEIGHT 换算脚部；
	# ≤1.5 允许同层（0）/1.2m 摊阁（1.2）/0.6m 祭坛台（0.6）；禁止 2.5m 望楼 / 3.0m 回廊隔层刀人。
	if absf(target_pos.y - (origin_pos.y - EYE_HEIGHT)) > _resource.melee_vertical_range:
		return false
```

并将函数体内 `if dist > _resource.melee_range:` 改为 `if dist > range_val:`。

### VERIFY（全量）

`cd /Users/elanyi/Projects/Trigger-Echo && godot --headless --path . -s addons/gut/gut_cmdln.gd`
预期：**281 测试全绿**（276 + 5 新增），0 失败。若既有测试红了：**停**，检查是否新逻辑破坏旧行为（常见坑：垂直判定忘了减 EYE_HEIGHT 会误挡 test_hits_feet_origin_enemy_from_eye_height；_in_cone 漏改 range 参数会让 stab 测试失败方向相反），修到全绿为止。

## 报告格式（最终回复 = 数据，不是给人看的对话）

返回：
- DONE / DONE_WITH_CONCERNS / BLOCKED
- RED 阶段证据（5 新测试失败输出摘要）
- 每个改动的行号
- 最终全量测试统计行（Tests/Passing/Fails 数）
- 任何规格偏差说明
