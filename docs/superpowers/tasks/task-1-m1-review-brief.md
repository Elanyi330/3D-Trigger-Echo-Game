# Task 1 审查 Brief — WeaponCore 射击核心

> 审查对象: 提交 `75f26b5`（feat/m1-weapon-system，工作树 /Users/elanyi/Projects/Trigger-Echo-m1）
> 审查方式: 双裁定——①规格合规 ②代码质量

## 审查范围（git show 75f26b5 查看 diff）
- `Weapons/WeaponCore.gd`（class_name WeaponCore extends Node3D）
- `test/unit/test_weapon_core.gd`（25 项测试）

## 审查标准

### 一、规格合规（对照计划 §4 全局约束 + 任务 1 brief）
1. **接口签名**：`shot_fired/reload_started/reload_finished/hit_landed/out_of_ammo` 信号 + `setup/try_fire/can_fire/start_reload/is_reloading/get_ammo/add_ammo/get_recoil_offset/set_ads` 方法（+ brief 补充的 interrupt_reload），签名与 brief 一致
2. **开火**：mag-1 + shot_fired；射速节流（RPM→间隔）；全自动/半自动差异；空匣 out_of_ammo
3. **hitscan**：collision_mask=1（仅 Objects 层）；max_range 截断；部位 Group（head ×4.0 / limb ×0.8 / 无=躯干 ×1）；falloff_curve 分段线性插值下限 0.96
4. **换弹**：reload_time 计时；丢弃弹匣剩余（CS2 规则）；换弹中 fire 无效；interrupt_reload 弹药不返还
5. **后坐力**：SET_PATTERN 逐发 pattern_offsets[i]（越界循环最后项）；RANDOM amount±variance；recovery 衰减；首发 first_shot_spread
6. **数值唯一来源**：伤害/射速/弹匣等从 Weapon_Resource 读，无硬编码散值
7. **纯离线**：无网络调用
8. **参考算法融入**（用户 2026-08-06 指导）：hitscan 参考 weapon_proto.gd（相机射线 + PhysicsRayQueryParameters3D）的实现方式，同时保持本项目特色（CS2 部位倍率/衰减/后坐力表、mask=1）

### 二、代码质量
1. GDScript 风格：命名一致、方法按职责分组（hitscan/换弹/后坐力）、注释清晰（中文符合项目惯例）
2. 测试质量：每个行为一测试、真实断言（非 mock）、浮点容差、物理场景正确推进 physics frame
3. 信号/事件：hit_landed 携带正确参数；无泄漏（节点释放）
4. 无过度设计（YAGNI）

## 验证（必须真实运行）
1. 进入 `/Users/elanyi/Projects/Trigger-Echo-m1`
2. `godot --headless --import`（如新增 class_name）
3. `godot --headless -s addons/gut/gut_cmdln.gd` 退出码 0、48/48 全绿（含 M0 14 + 任务 0 9 + 本任务 25）
4. 抽查 WeaponCore.gd 关键逻辑（射线 mask、部位判定、换弹丢弃规则、后坐力取表）

## 输出格式（你的最终返回）
```
裁定：PASS / FAIL（规格合规）
裁定：PASS / FAIL（代码质量）
发现的问题（按严重度：关键/重要/次要）：
- [严重度] 文件:行 — 描述 — 建议修复
结论：批准 / 需修复（列出必须修复项）
```
