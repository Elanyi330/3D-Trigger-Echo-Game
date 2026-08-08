# Task 16 审查 Brief — 动画表现层

> 审查对象: 提交 `3b8e6f5`（feat/m1-weapon-system，工作树 /Users/elanyi/Projects/Trigger-Echo-m1）
> 审查方式: 双裁定——①规格合规 ②代码质量

## 审查范围（git show 3b8e6f5 查看 diff）
- 4 视模型 .tscn（AnimationPlayerIdle/AnimationPlayerAim/三层分离）
- `Player/WeaponAnchor.gd`（两拍式换弹/快下挥慢回位/投掷蓄力/AimAnim 正反播/动画信号驱动）
- `Weapons/WeaponManager.gd`（throw_released/aim_toggled）+ `Weapons/WeaponCore.gd`（finish_reload 幂等）
- 测试（+12 项）

## 审查标准（对照任务 16 brief + 参考文档 §三）

### 一、规格合规
1. **双 AnimationPlayer**：IdleBreath 呼吸循环（2s y-0.002+rot±0.01）+ 战斗打断/恢复
2. **两拍式换弹**：手枪 -35°→+15°→0 / 步枪 z-0.006+rotY80°（对齐 reload_time）
3. **近战节奏**：0.02s 快下挥 70° + 0.1s 慢回位（1:5）+ 命中窗口 = 下挥期
4. **投掷蓄力**：0.5s 后拉 30° → 0.2s 挥出（抽拉环保留）
5. **ADS 正反播**：AimAnim 0.3s play/play_backwards + FOV 联动
6. **动画信号驱动换弹**：animation_finished("Reload") 驱动结算
7. **不回归**：238/238

### 二、代码质量
1. 三层动画分离（程序化/呼吸/战斗）与程序化通道零冲突
2. 动画信号驱动实现（幂等防双发）
3. 测试质量（窗口语义/包络中间态）
4. 偏差评估：换弹计时器回退（双路径幂等）、旧斜挥被 70° 下挥取代、命中窗口暴露

## 验证（必须真实运行）
1. `cd /Users/elanyi/Projects/Trigger-Echo-m1 && godot --headless --import`
2. `godot --headless -s addons/gut/gut_cmdln.gd` 退出码 0、238/238
3. 抽查：两拍式包络中间态、快挥慢回节奏、蓄力→挥出、AimAnim 正反播、动画信号驱动

## 输出格式
```
裁定：PASS / FAIL（规格合规）
裁定：PASS / FAIL（代码质量）
发现的问题（按严重度：关键/重要/次要）
结论：批准 / 需修复
```
