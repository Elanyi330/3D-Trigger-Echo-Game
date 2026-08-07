# Task 8 Brief — 投掷交互重构 + 精度模型 + 弹孔系统（体验改进 1）

> 分支: `feat/m1-weapon-system`（工作树 `/Users/elanyi/Projects/Trigger-Echo-m1`）
> spec: `docs/superpowers/specs/2026-08-06-m1-weapon-system-design.md` §9.1/9.2/9.3（先读）
> 方法: TDD 铁律——先写失败测试（RED）→ 确认失败原因 → 实现（GREEN）→ REFACTOR。不跳步。

## 工作环境
- 工作树: `/Users/elanyi/Projects/Trigger-Echo-m1`（git worktree，分支 feat/m1-weapon-system）
- 测试命令: `godot --headless -s addons/gut/gut_cmdln.gd`（退出码 0 = 全绿）
- 当前测试基线: 105/105 全绿

## 必读文件（动手前先读）
1. spec §9.1/9.2/9.3 + §10（任务分解）
2. `/Users/elanyi/Projects/Trigger-Echo-m1/Weapons/WeaponManager.gd`（投掷状态机/`_try_throw`/`_throw_grenade`/`_cancel_throw`）
3. `/Users/elanyi/Projects/Trigger-Echo-m1/Weapons/WeaponCore.gd`（弹道散布/`_get_ballistic_deviation`/`hit_landed`）
4. `/Users/elanyi/Projects/Trigger-Echo-m1/Weapons/Weapon_Resource.gd`（字段）
5. `/Users/elanyi/Projects/Trigger-Echo-m1/Player/MovementController.gd`（is_moving/is_crouching 状态）
6. `/Users/elanyi/Projects/Trigger-Echo-m1/docs/superpowers/reference/m1-src/grenade.gd` + `explosion.gd`（Mucurata，MIT，投掷/爆炸结构）

## 交付内容

### 1. 投掷交互重构：长按持雷 + 抛物线预览（§9.1，**无限持雷**）

**交互流**（CS 式）：
- M67 槽位 ACTIVE：按住 `fire` → **无限持雷**（无超时，用户拍板）+ **抛物线预览**实时显示
- 松开 `fire` → 沿预览抛物线投出（真实 Grenade）
- 按住 `aim`（右键）→ 取消（弹药返还 + 抛物线隐藏）
- 点击（按下即松）→ 天然投出（消除旧点击无反应竞态）

**实现**：
- WeaponManager：`_try_throw` 改为**按下进入 THROWING + 显示抛物线**（不再依赖松键检测竞态）；`_physics_process` 中 THROWING 且 fire 松开 → `_throw_grenade`（沿用现有）；**去掉超时自动投出**（无限持雷）
- **抛物线预览**：新类 `Weapons/ThrowTrajectory.gd`（Node3D）——每物理帧沿投掷方向积分弹道（重力抛体 v0=throw_strength），生成点列（30 点）→ `ImmediateMesh` 或 `MultiMesh` 虚线渲染；终点 = 落点；随相机方向实时更新；THROWING 进入时显示、取消/投出时隐藏
- 投掷方向：相机视向（现有 `-_camera.global_transform.basis.z`）

### 2. 精度稳定性模型（§9.3，弹孔"综合因素"）

WeaponCore 弹道散布计算扩展：
- **移动惩罚**：MovementController 提供 `is_moving`（水平速度 > 0.1 m/s）→ WeaponCore 散布 × `move_spread_multiplier`（AK 参考 CS2 running 182 vs standing 7，惩罚显著；默认 3.0，.tres 参数化）
- **下蹲收窄**：`is_crouching`（MovementController 已有）→ 散布 × `crouch_spread_multiplier`（默认 0.7）
- **开镜收窄**：已有（÷ads_multiplier）
- 叠加顺序：base × move × crouch ÷ ads（开镜时移动惩罚保留——CS2 开镜移动仍有精度损失）
- Weapon_Resource 新增：`move_spread_multiplier` / `crouch_spread_multiplier`（.tres 默认值：AK 3.0/0.7，Glock 1.5/0.7——手枪移动惩罚小）
- MovementController：加 `is_moving` 状态（`var is_moving: bool`，_physics_process 中速度检测更新；is_crouching 已有）

### 3. 弹孔系统（§9.2，30s 生命周期）

- 新类 `Weapons/BulletHole.gd`（Node3D）：命中点生成 decal（`Decal` 节点或贴片 mesh），**存在 30s 后自动消失**（`Timer` 或 `_process` 计数，30s 后 queue_free）
- 位置 = **实际射线命中点**（`hit_landed` 的 position 参数——弹道已含全部稳定性因素，弹孔天然符合武器设定）
- 上限防刷屏：全局最多 200 个弹孔，超出移除最旧（WeaponManager 或独立管理器计数）
- 弹孔方向：贴合命中表面（`hit_normal`——hit_landed 信号需补 normal 参数，或从碰撞结果取）
- WeaponCore：`hit_landed` 信号补 `normal: Vector3` 参数（现有 target/damage/position 后追加，检查现有监听兼容——L_Main `_on_shot_fired` 不接 hit_landed 则无影响；test_weapon_core 的捕获需同步）

### 4. 测试 `test/unit/test_throw_trajectory.gd` + `test_bullet_hole.gd` + 扩展 test_weapon_core

- 投掷：按住 fire → THROWING + 抛物线可见；松开 → Grenade 生成（方向/强度正确）；右键取消 → 弹药返还 + 抛物线隐藏；**无限持雷**（持续按住 5s 不自动投出）
- 抛物线：点列生成（30 点）、终点 = 落点（重力积分正确）、实时随相机更新
- 精度：移动中散布放大（多发射击方差增大或散布角计算正确）、下蹲收窄、开镜收窄、叠加顺序
- 弹孔：命中点生成、30s 后消失（模拟时间或直接查 timer）、200 上限淘汰最旧

## 验证步骤（必须真实运行）
1. `godot --headless --import`
2. `godot --headless -s addons/gut/gut_cmdln.gd` 退出码 0：新增测试全过 + 全量 105 项不回归
3. git commit（工作树内）：`git add -A && git commit -m "feat: M1 任务8 投掷交互重构（长按+抛物线）+ 精度模型 + 弹孔系统"`

## 完成报告
返回：DONE / DONE_WITH_CONCERNS / NEEDS_CONTEXT / BLOCKED
- 报告内容：实现的文件清单、测试结果摘要、遇到的问题、与 brief 的偏差
