# Task 10 Brief — 近战完整实现（匕首挥击动画 + 扇形判定）

> 分支: `feat/m1-weapon-system`（工作树 `/Users/elanyi/Projects/Trigger-Echo-m1`）
> spec: `docs/superpowers/specs/2026-08-06-m1-weapon-system-design.md` §9.5（先读）
> 方法: TDD 铁律——先写失败测试（RED）→ 确认失败原因 → 实现（GREEN）→ REFACTOR。不跳步。

## 工作环境
- 工作树: `/Users/elanyi/Projects/Trigger-Echo-m1`
- 测试命令: `godot --headless -s addons/gut/gut_cmdln.gd`（退出码 0 = 全绿）
- 当前测试基线: 137/137 全绿

## 必读文件（动手前先读）
1. spec §9.5（近战完整实现）
2. `/Users/elanyi/Projects/Trigger-Echo-m1/Weapons/Weapon_Resource.gd`（melee 字段：melee_primary/secondary/stab/backstab_damage、melee_light/heavy_time、melee_range/angle）
3. `/Users/elanyi/Projects/Trigger-Echo-m1/Weapons/WeaponManager.gd`（fire 分发——MELEE 槽位当前走空弹药分支，需改造）
4. `/Users/elanyi/Projects/Trigger-Echo-m1/Player/WeaponAnchor.gd`（挥击动画接线）
5. `/Users/elanyi/Projects/Trigger-Echo-m1/docs/superpowers/reference/m1-src/Weapon_State_Machine/Weapon_State_Machine.gd`（melee 判定参考：ShapeCast3D 扇形）

## 核心要求

### 1. 近战攻击逻辑（WeaponCore 或独立 Melee 处理）

**当前问题**：匕首槽位 `fire_mode == MELEE`，但 WeaponManager fire 分发无 MELEE 分支（走空弹药 out_of_ammo）——**左键完全无反应**（用户反馈）。

**实现**：
- WeaponManager fire 分发加 MELEE 分支 → 触发近战攻击
- **左键轻击**：`melee_light_time`（0.4s）间隔；伤害 `melee_primary_damage`（40）→ 连击 `melee_secondary_damage`（25，交替）
- **右键重刺**：`melee_heavy_time`（1.0s）间隔；伤害 `melee_stab_damage`（65）；**背刺**（命中点法线背离目标朝向 → 或目标背后 150° 内）`melee_backstab_damage`（180 秒杀）
- **扇形判定**：`melee_range`（1.5m）× `melee_angle`（60° 扇形）——ShapeCast3D 或球体扫掠 + 角度过滤（参考 FPS-Template melee_hitbox ShapeCast3D）
- 伤害结算：近战直接调用目标 `take_damage`（Target.gd 已实现）或发信号（对齐 hitscan 的 hit_landed 风格——**推荐信号 `melee_hit(target, damage)` 或复用 hit_landed**，由 L_Main/Target 消费）
- 命中反馈：命中时视模型小停顿（hit-stop，可选）

### 2. 挥击动画（WeaponAnchor）

- 左键轻击：视模型绕 Y 快速前挥（0→-0.8rad 再回位，0.4s 周期）
- 右键重刺：绕 Y 前刺（0→-0.5rad + Z 前推，1.0s 周期）
- 背刺判定时可有区别动画（可选）
- 代码插值（Tween/_process，项目风格）

### 3. 测试 `test/unit/test_melee.gd`（RED 先行）

- 左键轻击：伤害 40（Target.take_damage 被调）+ 间隔 0.4s
- 连击交替：第二击 25
- 右键重刺：伤害 65 + 间隔 1.0s
- **背刺**：目标背面 150° 内 → 180 秒杀；正面 → 40
- 扇形范围：1.5m 内命中、2m 外不命中、60° 外不命中
- 挥击动画：轻击/重刺时视模型旋转变化

**测试提示**：近战判定纯逻辑可测（距离 + 角度函数）；Target 场景构建（现有 Target.gd）；挥击动画断言 WeaponAnchor 旋转。

## 验证步骤（必须真实运行）
1. `godot --headless --import`
2. `godot --headless -s addons/gut/gut_cmdln.gd` 退出码 0：test_melee 全过 + 全量 137 项不回归
3. git commit（工作树内）：`git add -A && git commit -m "feat: M1 任务10 近战完整实现（轻击/重刺/背刺 + 扇形判定 + 挥击动画）"`

## 完成报告
返回：DONE / DONE_WITH_CONCERNS / NEEDS_CONTEXT / BLOCKED
- 报告内容：实现的文件清单、测试结果摘要、遇到的问题、与 brief 的偏差
