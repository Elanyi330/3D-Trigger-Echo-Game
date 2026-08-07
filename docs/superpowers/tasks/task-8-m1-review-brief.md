# Task 8 审查 Brief — 投掷重构 + 精度模型 + 弹孔

> 审查对象: 提交 `7ffd474`（feat/m1-weapon-system，工作树 /Users/elanyi/Projects/Trigger-Echo-m1）
> 审查方式: 双裁定——①规格合规 ②代码质量

## 审查范围（git show 7ffd474 查看 diff）
- `Weapons/ThrowTrajectory.gd`（抛物线预览）
- `Weapons/BulletHole.gd`（弹孔 30s）
- `Weapons/WeaponManager.gd`（投掷重构/弹孔接线）
- `Weapons/WeaponCore.gd`（精度模型/hit_landed normal）
- `Weapons/Weapon_Resource.gd` + .tres（move/crouch_spread_multiplier）
- `Player/MovementController.gd`（is_moving）
- 测试（test_throw_trajectory/test_bullet_hole + 扩展）

## 审查标准

### 一、规格合规（对照 spec §9.1/9.2/9.3 + 任务 8 brief）
1. **投掷重构**：按住 fire → THROWING + 抛物线；松开 → 投出；右键取消（返还+隐藏）；点击天然投出；**无限持雷（无超时）**
2. **抛物线**：30 点重力积分、虚线渲染、实时随相机、显示/隐藏时机
3. **精度模型**：叠加顺序 base×move×crouch÷ads（开镜保留移动惩罚）；.tres 参数化（AK 3.0/0.7、Glock 1.5/0.7）；is_moving 正确
4. **弹孔**：命中点（实际射线）、**30s 自动消失**、200 上限淘汰最旧、贴合表面（normal）
5. **不回归**：127/127（含 105 基线）；hit_landed 4 参兼容

### 二、代码质量
1. ThrowTrajectory 积分正确性（与 Grenade 同源重力）、渲染性能（ImmediateMesh）
2. BulletHole Timer 生命周期、淘汰逻辑
3. 测试质量（真实断言/物理帧推进/时序）
4. 偏差评估（中性默认 1.0、终点=弧线末点）

## 验证（必须真实运行）
1. `cd /Users/elanyi/Projects/Trigger-Echo-m1 && godot --headless -s addons/gut/gut_cmdln.gd` 退出码 0、127/127
2. 抽查：精度叠加顺序实现、抛物线积分、弹孔淘汰、无限持雷

## 输出格式
```
裁定：PASS / FAIL（规格合规）
裁定：PASS / FAIL（代码质量）
发现的问题（按严重度：关键/重要/次要）
结论：批准 / 需修复
```
