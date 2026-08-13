# Task Brief: R2 — 换弹锁切枪（bug 修复）

> 项目：Trigger Echo（Godot 4.7.1 + GDScript + GUT）
> 工作目录：`/Users/elanyi/Projects/Trigger-Echo`（分支 feat/m1-assets，直接在此目录工作）
> 父计划：`docs/superpowers/plans/2026-08-13-m2-combat-fixes-round2.md`（本 brief 为该计划 R2 的完整规格）

## 目标（用户实机反馈 bug）

换弹过程中**不允许切换武器**（用户拍板，非 CS"切枪取消换弹"）。现状 bug：换弹中切枪成功，且视图层换弹动画不重置 → 动画串到新挂载武器（手枪继续换弹动画）。

根因：①`WeaponManager.switch_to` 只处理 THROWING 门控，无 RELOADING 门控；②`WeaponView._on_switched` 不重置 `_reload_t`。

## 改动范围

只改 `Weapons/WeaponManager.gd`、`Player/WeaponView.gd`、`test/unit/test_weapon_manager.gd` 三个文件。

## TDD 步骤（严格顺序）

### RED 1：改写失败测试

`test/unit/test_weapon_manager.gd` 中既有 `test_switch_during_reload_interrupts_and_keeps_ammo`（约第 154-175 行，旧语义"切枪打断换弹"与用户拍板冲突）**整体替换**为：

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

运行 GUT 确认该测试**红**（旧代码下 switch_to(1) 成功 → `get_current_slot()` 断言 1≠0 失败，失败原因正确）。

### GREEN：实现

1. `Weapons/WeaponManager.gd` `switch_to` 中 `if slot == _current_slot: return` 行（含其注释）之后插入：

```gdscript
	# M2 修复轮2（2026-08-13，用户拍板）：换弹中不允许切换武器（非 CS"切枪取消换弹"——
	# 视图层 _reload_t 不随切枪复位，动画会串到新挂载武器上，直接禁止切换）。
	if _state == State.RELOADING:
		return
```

2. `Player/WeaponView.gd` `_on_switched` 函数体开头（`_mount(slot)` 之前）插入：

```gdscript
	_reload_t = -1.0  # M2 修复轮2（2026-08-13）：防御——换弹动画不延续到新挂载武器
```

### VERIFY（全量）

`cd /Users/elanyi/Projects/Trigger-Echo && godot --headless --path . -s addons/gut/gut_cmdln.gd`
预期：**289 全绿**（改写 1 测试不减数）。注意 `_queued_reload`（射击中按 R 排队，非 RELOADING 状态）切枪取消语义不变——排队相关测试不受影响。若既有测试红：检查是否还有别的测试依赖"换弹中切枪打断"旧语义，一并报告。

## 报告格式

- DONE / DONE_WITH_CONCERNS / BLOCKED
- RED 证据（改写测试失败输出摘要）
- 改动行号
- 全量统计行（Tests/Passing/Fails）
- 规格偏差说明（如有）
