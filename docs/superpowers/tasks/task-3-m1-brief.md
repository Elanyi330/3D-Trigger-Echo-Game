# Task 3 Brief — MovementController + Head 扩展（speed_modifier / add_recoil / set_ads）

> 分支: `feat/m1-weapon-system`（工作树 `/Users/elanyi/Projects/Trigger-Echo-m1`）
> 计划: `docs/superpowers/plans/2026-08-06-m1-weapon-system.md` 任务 3（先读 §5 任务 3 + §4 全局约束）
> 前置: 任务 2 已完成（WeaponManager + MovementController.speed_modifier 已加）
> 方法: TDD 铁律——先写失败测试（RED）→ 确认失败原因 → 实现（GREEN）→ REFACTOR。不跳步。

## 工作环境
- 工作树: `/Users/elanyi/Projects/Trigger-Echo-m1`
- 测试命令: `godot --headless -s addons/gut/gut_cmdln.gd`（退出码 0 = 全绿）
- 当前测试基线: 61/61 全绿（M0 14 + 任务 0 9 + 任务 1 25 + 任务 2 13）

## 交付内容（严格按计划 §5 任务 3）

### 1. `Player/MovementController.gd`（speed_modifier 已由任务 2 加入）
- 任务 2 已加 `@export var speed_modifier: float = 1.0`，`accelerate()` 用 `speed * speed_modifier`
- **本任务必须落实（任务 2 审查移交的关键项）：下蹲速度固定 2.59 不受 speed_modifier 影响**（计划 §4 约束："下蹲速度固定 2.59 不受影响"）
  - 现状：Crouch.gd 写 `controller.speed = 2.59`，会被 `speed * speed_modifier` 缩放 → 持 AK 蹲速 2.59×0.86=2.23（错误）
  - 修复：下蹲时的有效速度 = `crouch_speed * 1.0`（固定，不乘 speed_modifier）。实现方式（任选，需 TDD 覆盖）：
    - 方案 A：MovementController 增加 `is_crouching` 状态（由 Crouch.gd 联动），`accelerate()` 中下蹲时用 `crouch_speed` 而非 `speed * speed_modifier`
    - 方案 B：Crouch.gd 改写法（不覆盖 speed，而是通过别的属性）——但会动 M0 代码，风险高
    - **推荐 A**：MovementController 加 `@export var crouch_speed: float = 2.59` + `var is_crouching: bool`，Crouch.gd 在进入/退出下蹲时设置 `controller.is_crouching`，`accelerate()` 中 `var effective_speed = crouch_speed if is_crouching else speed * speed_modifier`
  - 注意：Crouch.gd 是 M0 交付的 CS 数值实现（Shift 下蹲），改动必须保持 M0 下蹲测试（test_crouch 4 项）全绿

### 2. `Player/Head.gd`（后坐力 + 开镜接口）
```gdscript
var recoil_offset: float = 0.0  # 累计后坐力（度，向上为正）
var ads_active: bool = false
var ads_multiplier: float = 1.0
func add_recoil(offset: float) -> void
func set_ads(active: bool, multiplier: float) -> void
```
- `add_recoil(offset)`：`recoil_offset += offset`，然后叠加到相机 `rotation.x`（在 `camera_rotation()` 输出上再加 `deg_to_rad(recoil_offset)`）；`_physics_process` 中按 `recovery_speed`（° /s）衰减回零（`recoil_offset` 向 0 移动）
- `set_ads(active, multiplier)`：`ads_active = active`；`ads_multiplier = multiplier`；active 时 FOV 缩小 `fov / multiplier`（CS 式开镜），灵敏度 × `1/multiplier`；非 active 恢复
  - Head 需要持有 FOV 引用：`cam.fov` 读取/写入（Camera3D）；灵敏度是 `mouse_sensitivity`（_ready 已除以 1000——注意：先存原始值或按比例缩放）
- 后坐力恢复速度参数：从哪来？Head 加 `@export var recoil_recovery_speed: float = 8.0`（° /s，默认 8 与 AK 恢复 8°/s 对齐——但注意武器数值唯一来源原则：恢复速度属于手感参数，Weapon_Resource.recovery_speed 存在。折衷：Head 的 recoil_recovery_speed 为**通用兜底**，实际值由 WeaponCore/WeaponManager 在开火时通过 add_recoil 携带或 set_recovery 设置——本任务实现 Head 的通用接口即可，WeaponCore 侧接线任务 6 做）
- **重要**：Head.gd 是 M0 交付（鼠标视角），改动必须保持 M0 的 view 行为（test_controller 6 项）全绿；`camera_rotation()` 逻辑只做**加法**（在现有输出上叠 recoil），不重构原逻辑

### 3. 测试 `test/unit/test_controller_weapon.gd`（RED 先行，每行为一测试）
- MovementController：
  - `speed_modifier=0.86` 时水平加速度目标 = 6.35×0.86（模拟 accelerate 纯逻辑或帧推进后速度）
  - **下蹲时 speed_modifier 不影响蹲速**（is_crouching=true 时速度目标 = 2.59 固定）
  - 空中/跳跃时不受影响（CS 规则已实现）
- Head：
  - `add_recoil(3.0)` → rotation.x 增加（对应角度）
  - 恢复衰减：一段时间后 recoil_offset 回零（按 recovery_speed）
  - `set_ads(true, 1.5)` → FOV 缩小 1.5 倍 + 灵敏度 ÷1.5；`set_ads(false, 1.5)` → 恢复
- **M0 不回归**：test_crouch（4 项） + test_controller（6 项）全绿

**测试提示**：MovementController 可 `new()` 直接实例化测纯逻辑（accelerate）；Head 需要 Camera3D（可手动构建）。物理帧推进用 `await get_tree().physics_frame`。

### 参考源码
- `docs/superpowers/reference/m1-src/camera3d_proto.gd`（参考：相机 FOV 变化/后坐力应用思路）
- `docs/superpowers/reference/m1-src/weapon_proto.gd`（has_shot 信号 → 相机后坐力叠加模式）

## 验证步骤（必须真实运行）
1. `godot --headless --import`
2. `godot --headless -s addons/gut/gut_cmdln.gd` 退出码 0，test_controller_weapon 全过 + 全量 61 项不回归（**重点：test_crouch 4 项 + test_controller 6 项**）
3. git commit（工作树内）：`git add -A && git commit -m "feat: M1 任务3 MovementController+Head 扩展（speed_modifier 下蹲豁免 + add_recoil/set_ads）"`

## 完成报告
返回：DONE / DONE_WITH_CONCERNS / NEEDS_CONTEXT / BLOCKED
- 报告内容：实现的文件清单、测试结果摘要、遇到的问题、与 brief 的偏差
