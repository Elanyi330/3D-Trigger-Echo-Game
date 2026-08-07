# Task 9 Brief — 程序化武器动画（kickback/sway/bob 三通道 + 换弹/切枪动画）

> 分支: `feat/m1-weapon-system`（工作树 `/Users/elanyi/Projects/Trigger-Echo-m1`）
> spec: `docs/superpowers/specs/2026-08-06-m1-weapon-system-design.md` §9.4（先读）
> 方法: TDD 铁律——先写失败测试（RED）→ 确认失败原因 → 实现（GREEN）→ REFACTOR。不跳步。

## 工作环境
- 工作树: `/Users/elanyi/Projects/Trigger-Echo-m1`
- 测试命令: `godot --headless -s addons/gut/gut_cmdln.gd`（退出码 0 = 全绿）
- 当前测试基线: 127/127 全绿

## 必读文件（动手前先读）
1. spec §9.4（程序化武器动画）
2. `/Users/elanyi/Projects/Trigger-Echo-m1/docs/superpowers/reference/m1-src/weapon_motions_dragon20c.gd` — **设计参考（Dragon20C，无许可证——仅学习"三通道合成"理念，代码必须自研，不得逐字复制）**
3. `/Users/elanyi/Projects/Trigger-Echo-m1/Player/WeaponAnchor.gd` — 现有实现（kick 单向 Z 位移，本次扩展为多通道）
4. `/Users/elanyi/Projects/Trigger-Echo-m1/Weapons/WeaponManager.gd` — 切枪/换弹信号（weapon_switched/reload_started）
5. `/Users/elanyi/Projects/Trigger-Echo-m1/Player/MovementController.gd` — is_moving（bob 输入）

## 核心要求（这是"丝滑感"的核心任务——用户体验反馈重点）

### 1. 程序化三通道合成（Dragon20C 理念自研）

在 `Player/WeaponAnchor.gd` 实现三通道**独立计算 → 合成**：
```
weapon_container.position = kickback_pos + sway_pos + bob_pos
weapon_container.rotation = kickback_rot + sway_rot
```

**kickback（开火后坐）**：
- 开火时位移：Z 推近（现有 kick_distance）+ **Y 上抬**（枪口上跳视觉）
- 开火时旋转：pitch 上跳（X 轴负向旋转，对应弹道上跳）
- 回弹：线性/指数回零（保留现有 0.2m/s 手感，旋转恢复可稍快）
- 触发：shot_fired 信号（现有接线保留）

**sway（鼠标摆动）**：
- 鼠标移动时视模型跟随摆动（位置轻微偏移 + 旋转）
- `mouse_motion` 输入：`_input` 捕获 InputEventMouseMotion（仅 MOUSE_MODE_CAPTURED）
- 参数：sway_amount（位置）/ sway_rot_amount（旋转），平滑插值（lerp 到目标，速度快），松手回中
- 参考 Dragon20C：`sway_amount=0.005`、`max_pos_sway`、`max_rot_sway` 量级

**bob（移动步幅）**：
- 移动时视模型上下/左右起伏（步幅节奏）
- 输入：MovementController.is_moving + 移动速度 → 相位累积（`motion += speed * delta * frequency`）
- 输出：`bob_pos.y = sin(motion) * amplitude`、`bob_pos.x = cos(motion * 0.5) * amplitude * 0.5`
- 静止时回中（平滑）
- 参考 Dragon20C：`frequency=1.0`、`amplitude=0.01`、`bobbing_speed=1.4` 量级

### 2. 换弹动画（reload_time 时长联动）

- WeaponManager `reload_started` 信号 → WeaponAnchor 播放换弹动作：
  - 视模型**下移**（Y 下降 0.06m）+ **旋转**（X 倾斜 0.3rad）→ 持续 reload_time → 回位
  - 代码插值（Tween 或 _process），非动画系统
- 时长联动：动画时长 = reload_time（AK 2.4s / Glock 2.3s）

### 3. 切枪部署动画（deploy_time 联动）

- `weapon_switched` 信号 → 新旧武器过渡：
  - 旧武器：下移 + 旋转淡出（0.1s）
  - 新武器：从低位/旋转滑入回位（deploy_time 时长）
  - 代码插值过渡
- 手部同步参与（视模型随手部整体动）

### 4. 测试 `test/unit/test_weapon_animations.gd`（RED 先行）

- kickback：开火 → 位移 Z/Y 变化 + 旋转变化；回弹归零
- sway：模拟鼠标移动 → 视模型位置/旋转跟随；松手回中
- bob：is_moving=true → 上下起伏（sin 相位）；静止回中
- 三通道合成：同时触发 → 位置 = kickback+sway+bob 之和
- 换弹动画：reload_started → 下移 → reload_time 后回位
- 切枪动画：weapon_switched → 新武器滑入（deploy 后到位）

**测试提示**：WeaponAnchor 单测手动构建（现测试模式）；sway 用合成 InputEventMouseMotion 或直接设 mouse_motion 属性；bob 用 is_moving 直设。

## 验证步骤（必须真实运行）
1. `godot --headless --import`
2. `godot --headless -s addons/gut/gut_cmdln.gd` 退出码 0：test_weapon_animations 全过 + 全量 127 项不回归
3. git commit（工作树内）：`git add -A && git commit -m "feat: M1 任务9 程序化武器动画（kickback/sway/bob 三通道 + 换弹/切枪动画）"`

## 完成报告
返回：DONE / DONE_WITH_CONCERNS / NEEDS_CONTEXT / BLOCKED
- 报告内容：实现的文件清单、测试结果摘要、遇到的问题、与 brief 的偏差
