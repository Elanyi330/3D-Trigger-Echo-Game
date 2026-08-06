# Task 3 审查 Brief — MovementController + Head 扩展

> 审查对象: 提交 `621dd55`（feat/m1-weapon-system，工作树 /Users/elanyi/Projects/Trigger-Echo-m1）
> 审查方式: 双裁定——①规格合规 ②代码质量

## 审查范围（git show 621dd55 查看 diff）
- `Player/MovementController.gd`（crouch_speed + is_crouching + accelerate 下蹲豁免）
- `Player/Crouch.gd`（is_crouching 联动）
- `Player/Head.gd`（recoil_offset/add_recoil/set_ads + 恢复衰减）
- `test/unit/test_controller_weapon.gd`（9 项测试）

## 审查标准

### 一、规格合规（对照计划 §4 + 任务 3 brief）
1. **下蹲豁免 speed_modifier**（任务 2 审查移交的关键约束）：`accelerate()` 中下蹲用 `crouch_speed`（2.59）固定，**不乘 speed_modifier**；持 AK 蹲速 = 2.59（非 2.23）
2. **Crouch 联动**：进入/退出下蹲设置 `controller.is_crouching`，M0 下蹲行为不变
3. **Head 接口**：`add_recoil(offset)` 叠加到 rotation.x（camera_rotation 只加法不重构）；`set_ads(active, multiplier)` FOV 缩放 + 灵敏度 ÷multiplier；`recoil_recovery_speed` 恢复衰减（° /s 回零）
4. **M0 不回归**：test_controller 6/6 + test_crouch 2/2（4 断言）全绿；speed_modifier 默认 1.0 行为不变
5. **数值来源**：recovery_speed 兜底参数化（export）；纯离线

### 二、代码质量
1. GDScript 风格、M0 代码只做加法（未重构）、注释符合项目惯例
2. 测试质量：每行为一测试、真实物理帧推进、无 mock
3. 实现细节：`_base_sensitivity` 保留原始值（÷1000 前）、`_base_fov` 记录；恢复衰减 move_toward 正确

## 验证（必须真实运行）
1. 进入 `/Users/elanyi/Projects/Trigger-Echo-m1`
2. `godot --headless -s addons/gut/gut_cmdln.gd` 退出码 0、70/70 全绿
3. 抽查：MovementController.accelerate 下蹲豁免逻辑、Head add_recoil/set_ads 实现、Crouch 联动

## 输出格式
```
裁定：PASS / FAIL（规格合规）
裁定：PASS / FAIL（代码质量）
发现的问题（按严重度：关键/重要/次要）：
- [严重度] 文件:行 — 描述 — 建议修复
结论：批准 / 需修复（列出必须修复项）
```
