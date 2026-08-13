# 实施计划：M2 战斗修复轮 2（换弹锁切枪 / 手雷 CCD / 厚度衰减伤害）

> 日期：2026-08-13 · 分支 feat/m1-assets · 设计：`docs/superpowers/specs/2026-08-13-m2-combat-fixes-round2-design.md`（用户已批准，衰减公式拍板 **A 线性截断**）
> 账本：`docs/superpowers/ledger/2026-08-13-m2-combat-fixes-round2-ledger.md`
> 基线：GUT 289/289（26 脚本）

## 〇、目标

1. **换弹锁切枪**（bug）：RELOADING 中 `switch_to` 无操作（用户拍板"换弹中不允许切枪"）；视图层换弹动画切枪复位（防御）。
2. **手雷穿地**（bug）：`Grenade.continuous_cd = true` 根治高速隧穿。
3. **厚度衰减伤害**：二值 LOS 全挡 → 沿"爆心→目标胸口"点采样累计墙厚 T（步长 0.25m），`dmg = dist_dmg × clamp(1 − T/3.0, 0, 1)`。

## 一、全局约束（精确值）

- .tres 新字段：`blast_penetration_max = 3.0`、`blast_los_sample_step = 0.25`（数值唯一来源）。
- 采样起点偏移 **半步**（k=0.5 起），终点 = 胸口参考点（`blast_los_probe_height` 1.0 沿用）；采样条件 `k*step < dist`。
- mask=1；exclude 目标本体 RID + 直接子节点 CollisionObject3D RID（防目标自身身体计入厚度）。
- 既有 T3 语义保留项：无墙满伤 / 地板不假遮挡 / 头自挡 / 爆心抬高过顶 / integration 高空接线——期望不变。

## 二、任务拆解

### R1 资源字段（机械，最便宜模型）

1. `Weapons/Weapon_Resource.gd` 末行后追加：

```gdscript
# M2 修复轮2（2026-08-13）：爆炸穿透衰减——全挡厚度（m，线性截断：mult=clamp(1−T/3.0,0,1)，3m 全挡）
# 与 LOS 采样步长（m，沿爆心→目标胸口线段点采样累计墙厚；越厚挡越多、越薄挡越少——用户拍板方案 A）。
@export var blast_penetration_max: float = 3.0
@export var blast_los_sample_step: float = 0.25
```

2. `Weapons/weapon_m67.tres` `blast_los_probe_height = 1.0` 行后追加：

```
blast_penetration_max = 3.0
blast_los_sample_step = 0.25
```

验证：GUT 全量 289 绿（纯新增字段无行为变化）。

### R2 换弹锁切枪（标准模型，TDD）

**RED 测试**——`test/unit/test_weapon_manager.gd`：**改写**既有 `test_switch_during_reload_interrupts_and_keeps_ammo`（第 154-175 行，旧语义"切枪打断换弹"与用户拍板冲突）为：

```gdscript
func test_switch_blocked_during_reload_completes_normally() -> void:
	# M2 修复轮2（2026-08-13，用户拍板）：换弹中不允许切枪——切枪无操作、换弹继续、完成后恢复切枪。
	var fast := _fast_ak()
	manager = _build_manager([fast, glock, knife, m67])
	var ak_core: WeaponCore = manager.get_core(0)
	var reload_finished_count := 0
	ak_core.reload_finished.connect(func() -> void: reload_finished_count += 1)
	Input.action_press("fire")
	await wait_physics_frames(1)  # 全自动：按住 1 帧 → 1 发
	Input.action_release("fire")
	await wait_physics_frames(1)
	assert_almost_eq(ak_core.get_ammo().x, float(fast.magazine - 1), 0.001, "开火 1 发 → 29")
	manager.start_reload()
	assert_eq(manager.get_state(), WeaponManager.State.RELOADING, "换弹 → RELOADING")
	assert_true(ak_core.is_reloading(), "AK 换弹中")
	manager.switch_to(1)  # 换弹中切枪 → 禁止
	assert_eq(manager.get_current_slot(), 0, "换弹中切枪无效（槽位不变）")
	assert_eq(manager.get_state(), WeaponManager.State.RELOADING, "换弹继续（不打断）")
	assert_signal_emit_count(manager, "weapon_switched", 0, "不发 weapon_switched")
	await wait_physics_frames(10)  # 0.05s 换弹完成
	assert_eq(reload_finished_count, 1, "换弹正常完成发 reload_finished")
	assert_eq(manager.get_state(), WeaponManager.State.ACTIVE, "换弹完成 → ACTIVE")
	assert_almost_eq(ak_core.get_ammo().x, float(fast.magazine), 0.001, "换弹完成弹匣回满 30")
	manager.switch_to(1)
	assert_eq(manager.get_current_slot(), 1, "换弹完成后切枪恢复")
```

**GREEN**：
1. `Weapons/WeaponManager.gd` `switch_to` 中 `if slot == _current_slot: return` 行之后插入：

```gdscript
	# M2 修复轮2（2026-08-13，用户拍板）：换弹中不允许切换武器（非 CS"切枪取消换弹"——
	# 视图层 _reload_t 不随切枪复位，动画会串到新挂载武器上，直接禁止切换）。
	if _state == State.RELOADING:
		return
```

2. `Player/WeaponView.gd` `_on_switched` 函数体开头插入：

```gdscript
	_reload_t = -1.0  # M2 修复轮2（2026-08-13）：防御——换弹动画不延续到新挂载武器
```

验证：改写测试绿 + 全量 289 绿（其余测试不受影响——`_queued_reload` 排队切枪取消语义不变，仅 RELOADING 门控）。

### R3 手雷 CCD + 厚度衰减（标准模型，TDD）

**RED 测试**：

1. 新测试（`test/unit/test_grenade_los.gd` 追加）：

```gdscript
func test_grenade_continuous_cd_enabled() -> void:
	var g := Grenade.new()
	add_child_autofree(g)
	await wait_physics_frames(1)
	assert_true(g.continuous_cd, "CCD 开启（修复高速隧穿穿地）")
```

2. 改写既有 2 个测试期望（厚度衰减语义）：
   - `test_wall_blocks_blast_damage` 改名 `test_wall_attenuates_damage_by_thickness`：1m 厚墙（z∈[−2.5,−1.5]，y∈[0,3]），爆心 (0,0,0)、目标 (0,0,−4)、胸口 (0,1,−4)，线段 4.123m，采样 f=k·0.25/4.123：k=7,8,9,10（f=0.424..0.606）落在墙内 → T=1.0 → mult=2/3。期望：
```gdscript
	assert_almost_eq(e.health, 100.0 - _dist_damage(4.0) * (2.0 / 3.0), 1.0,
			"1m 厚墙：伤害 = 距离衰减 × 2/3（线性截断 1−1/3）")
```
   - `test_low_cover_blocks_ground_blast` 改名 `test_low_cover_attenuates_ground_blast`：0.9m 矮墙（z∈[−2.3,−1.7]，y∈[0,0.9]）：k=8,9（f=0.485/0.545）落墙内 → T=0.5 → mult=1−0.5/3=5/6。期望：
```gdscript
	assert_almost_eq(e.health, 100.0 - _dist_damage(4.0) * (5.0 / 6.0), 1.0,
			"0.9m 矮墙：离散采样 T=0.5 → 伤害 × 5/6（±δ 容差 1.0）")
```
   - 其余 4 测试（无墙满伤/地板不假遮挡/头自挡/过顶）期望不变保持绿。

**GREEN**——`Weapons/Grenade.gd`：

1. `_ready` 中 `collision_mask = 1` 行后追加：

```gdscript
	continuous_cd = true  # M2 修复轮2（2026-08-13）：CCD 连续碰撞——15m/s+平台下坠≈0.25m/帧 > 球径 0.2m，
	# 离散检测漏检薄板（平台板 0.4-0.6m/地面）→ 概率穿地。CCD 扫掠根治（代价仅投掷物，可忽略）。
```

2. `_apply_blast_damage` 结算块改为：

```gdscript
		var dmg := damage_in_radius(global_position.distance_to(target.global_position))
		if dmg > 0.0 and target.has_method("take_damage"):
			var pen_mult := _penetration_mult(target)
			if pen_mult > 0.0:
				target.take_damage(dmg * pen_mult)
```

3. `_los_blocked` 整体替换为：

```gdscript
# M2 修复轮2（2026-08-13，用户拍板方案 A）：墙体厚度穿透衰减——替代旧二值 LOS 全挡
# （"雷丢小平台下全挡"反馈根因）。沿"爆心 → 目标胸口参考点"线段以 blast_los_sample_step
# 点采样累计墙厚 T（采样点落在实心几何内 = 计入；半步偏移起点避开爆心贴面歧义）；
# 倍率 = clamp(1 − T/blast_penetration_max, 0, 1)：越厚挡越多、越薄挡越少、3m 全挡。
# exclude 目标自身全部碰撞 RID（本体+子 CollisionObject3D——头 hitbox/躯干胶囊不计入墙厚）。
func _penetration_mult(target: Node) -> float:
	if resource == null or not target is CollisionObject3D:
		return 1.0
	var probe := target.global_position + Vector3(0, resource.blast_los_probe_height, 0)
	var dir := probe - global_position
	var dist := dir.length()
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
		var p := global_position + dir * (k * step / dist)
		var pq := PhysicsPointQueryParameters3D.new()
		pq.position = p
		pq.collision_mask = 1
		pq.exclude = exclude
		if not space.intersect_point(pq).is_empty():
			inside += 1
		k += 1.0
	var thickness := float(inside) * step
	return clampf(1.0 - thickness / resource.blast_penetration_max, 0.0, 1.0)
```

**VERIFY**：test_grenade_los 7 测试绿 + 全量 290 绿（289+1 新；改写 2 个语义测试不减数）。

### R4 回归 + 文档同步（控制器）

1. 全量 GUT（预期 290 全绿）+ L_M2 冒烟 180 帧。
2. 文档：FEATURES（遗留行补修复轮 2）/HANDOFF（运行细节补厚度衰减+换弹锁+CCD）/PROGRESS（第 8 条补轮 2）/设计文档状态行/记忆。
3. 全分支终审（最强模型，聚焦本轮 2ce617f..HEAD 净改动）。

## 三、派发顺序

```
R1（机械）→ 审查 → R2（换弹锁）→ 审查 → R3（CCD+厚度衰减）→ 审查 → R4（回归+文档+终审）
```
禁止并行实现者；每任务 RED 先行；审查两裁定。
