# Task 2 审查 Brief — WeaponManager 切换状态机 + 移速联动

> 审查对象: 提交 `2e7519a`（feat/m1-weapon-system，工作树 /Users/elanyi/Projects/Trigger-Echo-m1）
> 审查方式: 双裁定——①规格合规 ②代码质量

## 审查范围（git show 2e7519a 查看 diff）
- `Weapons/WeaponManager.gd`（class_name WeaponManager extends Node3D）
- `test/unit/test_weapon_manager.gd`（13 项测试）
- `Player/MovementController.gd`（speed_modifier 扩展）
- `Weapons/Weapon_Resource.gd` + 4 个 .tres（deploy_time 新增）

## 审查标准

### 一、规格合规（对照计划 §4 + 任务 2 brief）
1. **接口签名**：信号（weapon_switched/weapon_ammo_updated）+ 方法（setup/switch_to/next_weapon/get_current_slot/try_fire/start_reload/set_aim/get_speed_modifier）与 brief 一致
2. **状态机**：HOLSTERED/DEPLOYING/ACTIVE/RELOADING/THROWING；初始槽位 0；deploy 延迟（DEPLOYING 期间 try_fire/start_reload/set_aim 无效）；切枪中断换弹（弹药不返还）；开火中切枪立即中断；切同一槽位无操作；next_weapon 循环跳过空槽位
3. **半自动调用契约**：`_physics_process` 每物理帧轮询 `Input.is_action_pressed(&"fire")`，**禁止 is_action_just_pressed 驱动**（任务 1 审查确定的契约）
4. **移速联动**：get_speed_modifier = mobility/250（AK 0.86/Glock 0.96/刀 1.0/M67 0.98）；切枪写 movement.speed_modifier（DEPLOYING 也更新）；MovementController speed_modifier 默认 1.0 行为不变（M0 不回归）
5. **数值唯一来源**：deploy_time 等武器数值从 .tres 读（无硬编码散值）；纯离线
6. **M67 占位**：try_fire → THROWING + 弹药扣减（任务 4 接真实 Grenade，占位语义合理）

### 二、代码质量
1. GDScript 风格、状态机清晰（枚举/常量）、方法分组、注释符合项目惯例（中文）
2. 测试质量：每行为一测试、真实断言、deploy 计时用 await 等物理帧、无 mock
3. 偏差评估：deploy_time 进资源（合理？）、get_state()/get_core(slot) 访问器（必要？）、相机接线 get_viewport().get_camera_3d()（脆弱性？）

## 验证（必须真实运行）
1. 进入 `/Users/elanyi/Projects/Trigger-Echo-m1`
2. `godot --headless -s addons/gut/gut_cmdln.gd` 退出码 0、61/61 全绿
3. 抽查 WeaponManager 状态流转逻辑 + MovementController speed_modifier 默认 1.0 不影响 M0 行为

## 输出格式
```
裁定：PASS / FAIL（规格合规）
裁定：PASS / FAIL（代码质量）
发现的问题（按严重度：关键/重要/次要）：
- [严重度] 文件:行 — 描述 — 建议修复
结论：批准 / 需修复（列出必须修复项）
```
