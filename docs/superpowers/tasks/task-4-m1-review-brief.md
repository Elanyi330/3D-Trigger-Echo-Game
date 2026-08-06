# Task 4 审查 Brief — Grenade 投掷物

> 审查对象: 提交 `5b07bc6`（feat/m1-weapon-system，工作树 /Users/elanyi/Projects/Trigger-Echo-m1）
> 审查方式: 双裁定——①规格合规 ②代码质量

## 审查范围（git show 5b07bc6 查看 diff）
- `Weapons/Grenade.gd`（class_name Grenade extends RigidBody3D + damage_in_radius 纯逻辑）
- `test/unit/test_grenade.gd`（11 项测试）
- `Weapons/Weapon_Resource.gd`（blast_falloff 新增字段）
- `Weapons/weapon_m67.tres`（blast_falloff = (98, 60, 30)）

## 审查标准

### 一、规格合规（对照计划 §4 + 任务 4 brief + 企划书 §4.2.3⑦）
1. **接口**：`signal exploded(center)` + `init(origin, direction, strength)` + `explode()` 与 brief 一致；`damage_in_radius(distance)` 纯逻辑
2. **投掷**：init 设置位置 + linear_velocity（重力抛体）；引信 fuse_time（1.5s）倒计时 → explode
3. **爆炸**：半径 6m 内目标（Objects 层）；距离衰减 98/60/30（2m/4m/6m 分带）；半径外不伤害；爆炸后 queue_free
4. **数值唯一来源**：blast_falloff 进 .tres（98/60/30 从资源读，代码无硬编码散值）；纯离线
5. **企划书对齐**：中心 98 不秒杀（100HP→2）、引信 1.5s、半径 6m、弹道反弹（RigidBody3D 自然具备）

### 二、代码质量
1. GDScript 风格、爆炸检测实现（形状查询 vs Area3D——评估确定性）、目标结算（take_damage has_method 模式）
2. 测试质量：每行为一测试、真实物理帧推进、衰减断言准确
3. 偏差评估：blast_falloff 资源化（合理？有更优方案？）、分带边界（radius/3 与 2·radius/3）

## 验证（必须真实运行）
1. 进入 `/Users/elanyi/Projects/Trigger-Echo-m1`
2. `godot --headless -s addons/gut/gut_cmdln.gd` 退出码 0、81/81 全绿
3. 抽查：damage_in_radius 分带逻辑、引信倒计时、explode 幂等

## 输出格式
```
裁定：PASS / FAIL（规格合规）
裁定：PASS / FAIL（代码质量）
发现的问题（按严重度：关键/重要/次要）：
- [严重度] 文件:行 — 描述 — 建议修复
结论：批准 / 需修复（列出必须修复项）
```
