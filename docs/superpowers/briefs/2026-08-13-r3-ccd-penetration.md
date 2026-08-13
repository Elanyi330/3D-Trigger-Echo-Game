# Task Brief: R3 — 手雷 CCD 穿地修复 + 爆炸厚度衰减伤害

> 项目：Trigger Echo（Godot 4.7.1 + GDScript + GUT）
> 工作目录：`/Users/elanyi/Projects/Trigger-Echo`（分支 feat/m1-assets，直接在此目录工作）
> 父计划：`docs/superpowers/plans/2026-08-13-m2-combat-fixes-round2.md`（本 brief 为该计划 R3 的完整规格）
> 前置：R1 完成（m67.tres 已有 `blast_penetration_max=3.0`、`blast_los_sample_step=0.25`；Weapon_Resource.gd 已有对应字段）。

## 目标（两项）

1. **CCD 穿地修复**：`Grenade.continuous_cd = true`。根因：15 m/s + 平台下坠加速 ≈ 0.25m/物理帧 > 碰撞球直径 0.2m → 离散检测漏检薄板 → 概率穿地。
2. **厚度衰减伤害**（用户拍板方案 A 线性截断）：二值 LOS 全挡 → 沿"爆心→目标胸口参考点"线段**点采样累计墙厚 T**（步长 `blast_los_sample_step`=0.25，半步偏移起点 k=0.5，条件 `k*step < dist`），`最终伤害 = 距离衰减 × clamp(1 − T/blast_penetration_max, 0, 1)`（3m 全挡）。"雷丢小平台下全挡"反馈根因根治。

## 改动范围

`Weapons/Grenade.gd` + `test/unit/test_grenade_los.gd`。不改其他文件。

## TDD 步骤

### RED 1：先写失败测试

1. `test/unit/test_grenade_los.gd` 末尾追加：

```gdscript
func test_grenade_continuous_cd_enabled() -> void:
	var g := Grenade.new()
	add_child_autofree(g)
	await wait_physics_frames(1)
	assert_true(g.continuous_cd, "CCD 开启（修复高速隧穿穿地）")
```

2. 改写既有 2 个测试（二值全挡 → 厚度衰减）：
   - `test_wall_blocks_blast_damage` 改名为 `test_wall_attenuates_damage_by_thickness`，函数体不变（3m 高墙 center (0,1.5,-2) size (4,3,1)=厚 1.0），断言改为：

```gdscript
	assert_almost_eq(e.health, 100.0 - _dist_damage(4.0) * (2.0 / 3.0), 1.0,
			"1m 厚墙：伤害 = 距离衰减 × 2/3（线性截断 1−1/3）")
```

   - `test_low_cover_blocks_ground_blast` 改名为 `test_low_cover_attenuates_ground_blast`，断言改为：

```gdscript
	assert_almost_eq(e.health, 100.0 - _dist_damage(4.0) * (5.0 / 6.0), 1.0,
			"0.9m 矮墙：离散采样 T=0.5（2 个采样点 ×0.25）→ 伤害 × 5/6（容差 1.0 含 ±δ）")
```

   - 其余 4 测试（`test_no_wall_full_distance_damage`/`test_ground_blast_does_not_false_block`/`test_elevated_blast_does_not_self_block_via_head`/`test_elevated_blast_clears_low_cover`）**不改**，保持绿（无墙/地板不假遮挡/头自挡/过顶语义不变）。

**采样几何复核（实现前先手工验算一遍，写进注释）**：
- 测试 1（1m 墙）：爆心 (0,0,0)、目标 (0,0,−4)、胸口 (0,1,−4)，线段长 4.123m。采样 f=k·0.25/4.123，墙 z∈[−2.5,−1.5] → f∈[0.375,0.625] → k=7,8,9,10（f=0.424..0.606）落墙内且 y=f∈[0.42,0.61]⊂[0,3] ✓ → T=4×0.25=1.0。
- 测试 5（0.9m 墙）：墙 z∈[−2.3,−1.7] → f∈[0.425,0.575] → k=8,9（f=0.485/0.545）→ T=2×0.25=0.5。
- 测试 4（头自挡）：爆心 (0,2.5,0) 到胸口 (0,1,0) 竖直，采样点 y=2.375..1.125 全部落在躯干胶囊（y∈[0.15,1.69]）或头球（y∈[1.52,1.88]）内 → exclude 后 T=0 ✓ 必须保持满伤。
- 测试 3（地板）：爆心 (0,0,0)→胸口 (0,1,−2) 采样 y=f>0 恒高于地板顶面 y=0 → T=0 ✓。
- 测试 6（过顶）：爆心 (0,1.2,0)，墙处（f≈0.425..0.575）y≈1.08..1.12 > 0.9 墙顶 → T=0 ✓。

运行 GUT 确认：新 CCD 测试红（旧代码 continuous_cd=false）+ 2 个改写测试红（旧代码全挡 0 伤 ≠ 2/3、5/6 期望）+ 其余 4 个保持绿。失败原因必须正确（非夹具错误）。

### GREEN：实现（`Weapons/Grenade.gd`）

1. `_ready` 中 `collision_mask = 1` 行之后追加：

```gdscript
	continuous_cd = true  # M2 修复轮2（2026-08-13）：CCD 连续碰撞——15m/s+平台下坠≈0.25m/帧 > 球径 0.2m，
	# 离散检测漏检薄板（平台板 0.4-0.6m/地面）→ 概率穿地。CCD 扫掠根治（代价仅投掷物，可忽略）。
```

2. `_apply_blast_damage` 中结算块：

```gdscript
		var dmg := damage_in_radius(global_position.distance_to(target.global_position))
		if dmg > 0.0 and target.has_method("take_damage") and not _los_blocked(target):
			target.take_damage(dmg)
```

替换为：

```gdscript
		var dmg := damage_in_radius(global_position.distance_to(target.global_position))
		if dmg > 0.0 and target.has_method("take_damage"):
			var pen_mult := _penetration_mult(target)
			if pen_mult > 0.0:
				target.take_damage(dmg * pen_mult)
```

3. `_los_blocked` 函数整体替换为：

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

### VERIFY（全量）

`cd /Users/elanyi/Projects/Trigger-Echo && godot --headless --path . -s addons/gut/gut_cmdln.gd`
预期：**290 全绿**（289 + 1 新 CCD 测试；改写 2 个语义测试不减数）。重点回归：test_damage_dedup（脚下爆炸：爆心 (0,0,0)→胸口 (0,1,0)，采样点 y=0.125..0.875——k=0.5 点 y=0.125 在胶囊底 y=0.15 之下 ✓ 不计入、其余在胶囊内被 exclude → T=0 → 满伤 98 不秒杀保持）与 test_integration（高空 (0,20,0) 采样点全在天空 → T=0 ✓）。

常见坑：
- `PhysicsPointQueryParameters3D` 的 exclude 属性名与射线查询一致（`exclude`，Array[RID]）——类型不匹配时报错，显式类型声明。
- `intersect_point` 需要物理空间已同步：测试夹具 Enemy 已 await 2 物理帧 ✓；墙体夹具已有 `await wait_physics_frames(1)`（轮 1 批准的夹具模式，沿用）。
- 采样点恰落在目标胶囊边界（y=0.15/1.69 附近）时 exclude 已兜底；不改采样公式。

## 报告格式

- DONE / DONE_WITH_CONCERNS / BLOCKED
- RED 证据（3 红 4 绿摘要 + 失败原因）
- 改动行号
- 全量统计行（Tests/Passing/Fails）
- 规格偏差说明（如有）
