# Task 0 审查 Brief — 输入动作 + Weapon_Resource 资源骨架

> 审查对象: 提交 `51fae8a`（feat/m1-weapon-system）
> 审查方式: 双裁定——①规格合规 ②代码质量

## 审查范围（git diff 51fae8a 或工作树当前状态）
- `Weapons/Weapon_Resource.gd`（class_name WeaponResource）
- `Weapons/weapon_ak47.tres` / `weapon_glock18.tres` / `weapon_knife.tres` / `weapon_m67.tres`
- `project.godot`（新增 8 输入动作）
- `test/unit/test_weapon_resource.gd`

## 审查标准

### 一、规格合规（对照计划 §4 全局约束 + 任务 0 brief）
1. **CS2 数值对齐**（对照 `docs/superpowers/reference/cs2-weapon-data.md`）：
   - AK：36 / ×4.0 / 600RPM / 30+120 / 2.4s / 215u / 40-60m / 0.96 下限 / ads 1.5
   - Glock：30 / ×4.0 / 400RPM / 20+80 / 2.3s / 240u / 15-30m / RANDOM / 无开镜（ads 1.0）
   - 匕首：40 / 250u（=1.0）/ MELEE / 背刺 180
   - M67：98 / 引信 1.5s / 半径 6m / 245u / THROWABLE / magazine 1
2. **输入动作**：8 个新增（fire/reload/aim/weapon_1-4/next_weapon）键位正确；M0 原 11 个动作未改动
3. **数值唯一来源**：代码中无硬编码武器数值（伤害/射速/弹匣等必须从 .tres 读）
4. **纯离线**：无网络调用
5. **字段完整性**：spec 要求的字段都在（含 melee 附加字段），默认值合理（×4.0/0.8/250u）

### 二、代码质量
1. GDScript 风格：命名一致、无冗余、注释清晰（含中文注释符合项目惯例）
2. 测试质量：断言真实行为、覆盖关键数值、浮点断言用容差、无 mock 行为
3. 资源文件：格式正确（PackedVector2Array 扁平序列等）、字段与脚本一致
4. .tres 数值与 CS2 数据源一致（抽查）

## 验证（必须真实运行）
1. 进入 `/Users/elanyi/Projects/Trigger-Echo-m1`
2. `godot --headless -s addons/gut/gut_cmdln.gd` 退出码 0（全量含 M0 14 项）
3. 抽查 .tres 关键数值与 cs2-weapon-data.md 一致

## 输出格式（你的最终返回）
```
裁定：PASS / FAIL（规格合规）
裁定：PASS / FAIL（代码质量）
发现的问题（按严重度：关键/重要/次要）：
- [严重度] 文件:行 — 描述 — 建议修复
结论：批准 / 需修复（列出必须修复项）
```
