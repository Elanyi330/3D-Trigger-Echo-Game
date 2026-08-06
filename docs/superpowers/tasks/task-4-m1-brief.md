# Task 4 Brief — Grenade 投掷物（抛物线 + 爆炸衰减）

> 分支: `feat/m1-weapon-system`（工作树 `/Users/elanyi/Projects/Trigger-Echo-m1`）
> 计划: `docs/superpowers/plans/2026-08-06-m1-weapon-system.md` 任务 4（先读 §5 任务 4 + §4 全局约束）
> 前置: 任务 2 已完成（WeaponManager THROWING 占位 + M67 弹药扣减）
> 方法: TDD 铁律——先写失败测试（RED）→ 确认失败原因 → 实现（GREEN）→ REFACTOR。不跳步。

## 工作环境
- 工作树: `/Users/elanyi/Projects/Trigger-Echo-m1`
- 测试命令: `godot --headless -s addons/gut/gut_cmdln.gd`（退出码 0 = 全绿）
- 当前测试基线: 70/70 全绿（M0 14 + 任务 0 9 + 任务 1 25 + 任务 2 13 + 任务 3 9）

## 交付内容（严格按计划 §5 任务 4）

### `Weapons/Grenade.gd`（class_name Grenade extends RigidBody3D）
```gdscript
signal exploded(center: Vector3)
func init(origin: Vector3, direction: Vector3, strength: float) -> void
func explode() -> void
```

### 行为要求（全部 TDD 覆盖）

**1. 投掷**：
- `init(origin, direction, strength)`：设置初始位置 + `linear_velocity = direction.normalized() * strength`（抛物线重力抛体，RigidBody3D 自然下落）
- 引信计时：投掷后 `fuse_time`（M67 = 1.5s）→ 自动 `explode()`
- 右键取消投掷：WeaponManager 层面（任务 2 的 THROWING 状态 + aim 键）→ 不生成 Grenade、弹药不消耗（本任务实现 Grenade 本体，取消逻辑接线任务 6 场景集成时确认；本任务可加 `func cancel() -> void` 占位若需要）

**2. 爆炸**：
- 半径 `blast_radius`（M67 = 6m）内 `Area3D` 检测目标（collision_layer 匹配）
- 距离衰减伤害：中心 98（2m 内）→ 60（4m 内）→ 30（6m 边缘）——按距离线性/阶梯衰减（用 .tres 数值派生，禁止硬编码）
- 目标判定：爆炸半径内 Objects 层目标（Group `"torso"` 等，与任务 1 部位判定一致；爆炸为范围伤害无部位倍率）
- 爆炸后 `queue_free()` 释放；爆炸特效占位（可选，M1 简化——可跳过视觉）

### 测试 `test/unit/test_grenade.gd`（RED 先行，每行为一测试）
- 投掷后引信 1.5s 计时 → `exploded` 信号（await 物理帧推进）
- 爆炸伤害衰减：目标距离 1m → 98 / 3m → 60 / 5m → 30（100HP 单位场景）
- 爆炸半径外（>6m）不伤害
- 抛物线：投掷后 linear_velocity 设置正确、重力作用下落（y 速度变化）
- `explode()` 手动调用 → 爆炸 + 释放（queue_free 后 is_queued_for_deletion）

**测试提示**：Grenade 是 RigidBody3D 需要物理场景（add_child + await physics_frame）；爆炸检测用 Area3D（`body_entered` 或爆炸瞬间扫描 `get_overlapping_bodies`）；目标 StaticBody3D/CharacterBody3D + Group；伤害通过信号 `exploded` 参数或直接查询（设计上 `explode()` 对半径内目标结算伤害——需与 WeaponCore 的 hit_landed 一致或独立；本任务独立实现 `damage_in_radius()` 纯逻辑可单测）。

### 参考源码（禁止在线拉取）
- `docs/superpowers/reference/m1-src/Weapon_State_Machine/Weapon_State_Machine.gd`（投掷物思路）
- 企划书 §4.2.3⑦ M67 规格（中心 98 不秒杀 / 引信 1.5s / 半径 6m / 弹道可反弹——弹道反弹 M1 简化，RigidBody3D 物理碰撞自然具备）

## 验证步骤（必须真实运行）
1. `godot --headless --import`
2. `godot --headless -s addons/gut/gut_cmdln.gd` 退出码 0，test_grenade 全过 + 全量 70 项不回归
3. git commit（工作树内）：`git add -A && git commit -m "feat: M1 任务4 Grenade 投掷物（抛物线+爆炸衰减）"`

## 完成报告
返回：DONE / DONE_WITH_CONCERNS / NEEDS_CONTEXT / BLOCKED
- 报告内容：实现的文件清单、测试结果摘要、遇到的问题、与 brief 的偏差
