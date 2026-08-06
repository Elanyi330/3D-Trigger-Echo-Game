# Task 2 Brief — WeaponManager 切换状态机 + 移速联动

> 分支: `feat/m1-weapon-system`（工作树 `/Users/elanyi/Projects/Trigger-Echo-m1`）
> 计划: `docs/superpowers/plans/2026-08-06-m1-weapon-system.md` 任务 2（先读 §5 任务 2 + §4 全局约束）
> 前置: 任务 0（资源）+ 任务 1（WeaponCore，注意半自动调用契约）
> 方法: TDD 铁律——先写失败测试（RED）→ 确认失败原因 → 实现（GREEN）→ REFACTOR。不跳步。

## 工作环境
- 工作树: `/Users/elanyi/Projects/Trigger-Echo-m1`
- 测试命令: `godot --headless -s addons/gut/gut_cmdln.gd`（退出码 0 = 全绿）
- 新增 class_name 后先 `godot --headless --import` 再跑测试（GUT 陷阱）
- 当前测试基线: 48/48 全绿（M0 14 + 任务 0 9 + 任务 1 25）

## ⚠️ 任务 1 关键契约（必须先读 WeaponCore 注释）

**WeaponCore.try_fire() 调用契约**：调用方（WeaponManager）需**在开火键按住期间每物理帧轮询 `try_fire()`**（半自动模式依赖粘性按压沿检测；全自动模式同样需持续轮询以维持射速节流）。**禁止用 `is_action_just_pressed` 驱动**（回调先于物理帧，沿未设置，Glock 会静默打不响）。输入动作名 `&"fire"` 与 Manager 输入所有权是双处耦合。

## 交付内容（严格按计划 §5 任务 2）

### `Weapons/WeaponManager.gd`（class_name WeaponManager extends Node3D）
```gdscript
signal weapon_switched(slot: int)  # 0=primary 1=secondary 2=melee 3=throwable
signal weapon_ammo_updated(slot: int, mag: int, reserve: int)
func setup(slots: Array[WeaponResource], movement: MovementController) -> void
func switch_to(slot: int) -> void
func next_weapon() -> void  # 滚轮循环
func get_current_slot() -> int
func try_fire() -> void
func start_reload() -> void
func set_aim(active: bool) -> void
func get_speed_modifier() -> float
```

### 行为要求（全部 TDD 覆盖）

**1. 槽位与状态机**：
- 槽位：0=primary（AK）/ 1=secondary（Glock）/ 2=melee（匕首）/ 3=throwable（M67）
- 初始槽位 0（primary）；`setup(slots, movement)` 预装载 4 个 Weapon_Resource
- 状态：HOLSTERED / DEPLOYING（切枪延迟）/ ACTIVE / RELOADING / THROWING
- `switch_to(slot)`：切换到指定槽位 → DEPLOYING（deploy 时间，AK 0.3s / Glock 0.3s / 刀 0.3s / M67 0.5s，参数化）→ ACTIVE；期间 `try_fire`/`start_reload`/`set_aim` 无效
- `next_weapon()`：滚轮循环 0→1→2→3→0（跳过无资源槽位——v1.0 全有资源，仍实现防御）
- 切枪**中断换弹**（调用 WeaponCore.interrupt_reload()）且弹药不返还
- 开火中切枪 → 立即中断开火
- 切到同一槽位：无操作（不发信号）

**2. 动作分发**：
- `try_fire()`：转发当前 ACTIVE 槽位的 WeaponCore.try_fire()（注意契约——**每物理帧轮询**，WeaponManager 的 `_physics_process` 里做 `if Input.is_action_pressed(&"fire") and 当前 ACTIVE: core.try_fire()`）
- `start_reload()`：转发（RELOADING 状态跟踪；换弹完成发 `weapon_ammo_updated`）
- `set_aim(active)`：转发（AK 开镜；Glock/M67 无开镜由 WeaponCore 内部处理）
- M67（THROWABLE 槽位）：`try_fire` = 投掷动作（进入 THROWING 状态，本任务先占位——投掷逻辑任务 4 实现，本任务只做状态流转与弹药扣减占位，任务 4 接真实 Grenade）

**3. 弹药总账**：
- 每个槽位独立弹匣/备弹（各自 WeaponCore 实例持有）
- 切枪时发 `weapon_ammo_updated(slot, mag, reserve)`（当前槽位弹药状态）

**4. 移速联动**：
- `get_speed_modifier()`：当前 ACTIVE 槽位武器 `mobility / 250`（AK 215→0.86 / Glock 240→0.96 / 刀 250→1.0 / M67 245→0.98）
- 切枪后写入 `movement.speed_modifier`（MovementController 新增属性，见任务 3——本任务**先直接赋值**（`movement.speed_modifier = x`），任务 3 会实现该属性；若 MovementController 尚无该属性，先加（`@export var speed_modifier: float = 1.0`）并在 `accelerate()` 中用 `speed * speed_modifier` 替换 speed）
- DEPLOYING 期间也更新（CS2 式：持枪移动速度立即生效）

### 测试 `test/unit/test_weapon_manager.gd`（RED 先行，每行为一测试）
- 初始槽位 0；切枪 → 槽位更新 + `weapon_switched` 信号
- deploy 延迟：切枪后立即 try_fire 无效，deploy 时间后有效（用 await 等物理帧）
- 滚轮循环 0→1→2→3→0
- 换弹中切枪 → 换弹中断、弹药不返还
- 开火中切枪 → 开火中断
- `speed_modifier` 随切枪更新（0.86→1.0→0.98→0.96）
- 切同一槽位无操作
- M67 槽位 try_fire 进入 THROWING（状态可查）

**测试提示**：WeaponManager 需要 MovementController——GUT 中可 `MovementController.new()` 直接实例化（纯逻辑类，不需要场景），或挂到测试根下。deploy 计时用 `_physics_process` 计数（60Hz）或 `get_tree().create_timer`。

### 参考源码（禁止在线拉取，读本地副本）
- `docs/superpowers/reference/m1-src/Weapon_State_Machine/Weapon_State_Machine.gd`（槽位切换/change_weapon/动画延迟模式）

## 验证步骤（必须真实运行）
1. `godot --headless --import`
2. `godot --headless -s addons/gut/gut_cmdln.gd` 退出码 0，test_weapon_manager 全过 + 全量不回归（48 项基线）
3. git commit（工作树内）：`git add -A && git commit -m "feat: M1 任务2 WeaponManager 切换状态机 + 移速联动"`

## 完成报告
返回：DONE / DONE_WITH_CONCERNS / NEEDS_CONTEXT / BLOCKED
- 报告内容：实现的文件清单、测试结果摘要、遇到的问题、与 brief 的偏差
