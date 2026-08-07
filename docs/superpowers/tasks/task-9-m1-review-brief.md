# Task 9 审查 Brief — 程序化武器动画

> 审查对象: 提交 `cb0af17`（feat/m1-weapon-system，工作树 /Users/elanyi/Projects/Trigger-Echo-m1）
> 审查方式: 双裁定——①规格合规 ②代码质量

## 审查范围（git show cb0af17 查看 diff）
- `Player/WeaponAnchor.gd`（三通道合成 + 换弹/切枪动画）
- `Weapons/WeaponManager.gd`（get_resource 访问器）
- `Levels/Main/L_Main.gd`（movement 注入）
- `test/unit/test_weapon_animations.gd`（10 项）

## 审查标准

### 一、规格合规（对照 spec §9.4 + 任务 9 brief）
1. **三通道合成**：`position = kickback_pos + sway_pos + bob_pos`；`rotation = kickback_rot + sway_rot`
2. **kickback**：开火 Z 推近 + Y 上抬 + pitch 旋转；回弹归零（保留 0.2m/s 手感）
3. **sway**：鼠标移动跟随（仅 CAPTURED）+ 平滑回中
4. **bob**：is_moving 驱动 sin/cos 步幅 + 静止回中
5. **换弹动画**：reload_started → 下移+倾斜（reload_time 联动）→ 回位
6. **切枪动画**：weapon_switched → 旧淡出 + 新滑入（deploy_time 联动）
7. **自研**：理念参考 Dragon20C（无许可证），代码原创
8. **不回归**：137/137

### 二、代码质量
1. 合成方法清晰、通道独立、参数可导出调参
2. 动画插值实现（Tween/_process）、时长联动正确
3. 测试质量（真实断言/物理帧推进/不锁方向）
4. 偏差评估：kick_pitch 正值（Godot 右手系数学）、reload_started 为 WeaponCore 信号、初始挂载不播动画

## 验证（必须真实运行）
1. `cd /Users/elanyi/Projects/Trigger-Echo-m1 && godot --headless -s addons/gut/gut_cmdln.gd` 退出码 0、137/137
2. 抽查：三通道合成方法、kickback 回弹、sway 捕获、bob 相位、换弹/切枪时长联动

## 输出格式
```
裁定：PASS / FAIL（规格合规）
裁定：PASS / FAIL（代码质量）
发现的问题（按严重度：关键/重要/次要）
结论：批准 / 需修复
```
