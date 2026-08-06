# Task Brief — 任务 3：控制器行为测试（TDD：RED → GREEN）

> 实现工作目录: `/Users/elanyi/Projects/Trigger-Echo-m0`（分支 feat/m0-engine-skeleton）
> 计划来源: `docs/superpowers/plans/2026-08-06-m0-engine-skeleton.md` 任务 3

## 目标

为 MovementController 编写真实行为测试（非 mock、非仅读属性），遵循 TDD 铁律：**先写失败测试（RED），确认失败原因正确，再实现使通过（GREEN）**。控制器代码已移植完毕（任务 2），因此本任务的核心是**先证明测试能正确检测行为（故意制造失败确认原因），再恢复实现使其通过**。

## 环境事实

- MovementController.gd 已就位：`class_name MovementController`，`@export speed=10, acceleration=8, deceleration=10, jump_height=10, gravity_multiplier=3.0, air_control=0.3`；`_physics_process(delta)` 读 `Input.get_vector(&"move_back", &"move_forward", &"move_left", &"move_right")`；跳跃分支 `if is_on_floor(): if Input.is_action_just_pressed(&"jump"): velocity.y = jump_height`（is_on_floor 依赖物理场景/重力）
- GUT 9.7.1 已就位；测试目录 `res://test/unit/`
- 项目物理层：1=Objects（地面/墙），2=Player

## 测试设计（写入 `test/unit/test_controller.gd`）

### 测试结构（全部 extends GutTest）

```gdscript
extends GutTest
var controller: MovementController

func before_each() -> void:
    controller = MovementController.new()
    add_child_autofree(controller)

func after_each() -> void:
    Input.action_release("jump")
    Input.action_release("move_forward")
    Input.action_release("move_back")
    Input.action_release("move_left")
    Input.action_release("move_right")
```

### 必测用例（每个独立、一次断言一个行为）

1. **test_initial_speed**: `assert_eq(controller.speed, 10, ...)` — 默认速度
2. **test_jump_height_default**: `assert_eq(controller.jump_height, 10, ...)` — 默认跳跃高度
3. **test_move_forward_moves_player_forward**: 纯逻辑测试：
   ```gdscript
   func test_move_forward_moves_player_forward() -> void:
       Input.action_press("move_forward")
       controller._physics_process(1.0 / 60.0)
       assert_eq(controller.velocity.z, -10.0, "前进时 velocity.z 应为 -speed")  # 注意：Forward = -Z
   ```
   - 需在 before_each 设置位置/朝向保证可测
   - **若 `direction.dot(temp_vel) > 0` 依赖初速为 0 → 首帧 accelerate 可能为 0**：首帧 `direction*(0)` 点积为 0 → temp_accel=deceleration(10)，`temp_vel.lerp(target, clamp(10/60,0,1)=0.1667)` → velocity.z ≈ -1.667 而非 -10！**这是加速模型（acceleration）导致的**。**测试必须断言合理值**：要么断言 `velocity.z < 0`（方向正确），要么推进多帧后断言接近 -10。**自行决定并说明理由**，但必须测出"向前移动"这一真实行为
4. **test_jump_impulse**: `Input.action_press("jump")` 后单帧 `_physics_process`，断言 `velocity.y == 10.0`（jump_height）
   - **注意坑**：MovementController 的跳跃在 `is_on_floor()` 分支内，而纯 `new()` 的节点不在物理场景中，`is_on_floor()` 恒 false → 测试失败。**解决**：在测试场景中放置地面（StaticBody3D layer=1）+ 把 controller 放地面之上并 `await` 物理帧让重力落稳，再测跳跃。或者**测试先写失败，用真实物理场景实现 GREEN**（推荐，测真实行为）
5. **test_gravity_applies_when_airborne**: 节点在空（无地面）时推进数帧，断言 `velocity.y` 小于 0（重力生效）且随时间增大
6. **test_sprint_speed_exposed**: 可选（Sprint 组件不在本任务范围，跳过）

### TDD 流程要求（必须真实执行并报告）

1. **RED 阶段**：先写测试（含上述设计），运行 `godot --headless -s addons/gut/gut_cmdln.gd` → **必须真实观察到至少一个测试失败**，且失败原因正确（断言不满足/物理场景缺失），**不是**拼写或 GUT 配置错误
2. **确认失败原因**：报告失败输出片段，说明为什么失败是"正确的失败"（测试测到了真实行为/真实缺失）
3. **GREEN 阶段**：补充实现（若测试依赖真实物理场景则添加测试辅助函数/场景；**不得修改 MovementController.gd 生产代码**——它已移植定稿，测试应适配控制器行为而非控制器适配测试）
4. 运行全部测试 → 全绿，退出码 0

## 验证步骤（必须真实执行）

1. RED：跑测试记录失败输出（至少 1 个测试失败且原因正确）
2. GREEN：跑测试全绿，`godot --headless -s addons/gut/gut_cmdln.gd; echo EXIT=$?` → EXIT=0
3. 连续跑 2 次确认稳定（无随机失败）
4. `godot --headless --path . --quit-after 60` → 退出码 0（游戏主场景仍正常）

## 硬性约束

- **不得修改 `Player/MovementController.gd`、`Head.gd`、`Sprint.gd`、`Player.tscn`、`L_Main.tscn`**（已定稿移植）
- 测试文件唯一产物：`test/unit/test_controller.gd`
- 如需测试辅助节点（地面等），在测试文件内用代码创建（`StaticBody3D.new()` + shape），**不新建 .tscn**
- 若物理帧推进需要 `await`（如 `await get_tree().physics_frame`），在 GUT 中 `await` 需要测试函数返回信号——查阅 GUT 约定使用 `await get_tree().physics_frame` 或 `await gut.wait_frames(n)`（GUT 提供 `wait_frames` 辅助）

## 报告格式

- 状态：DONE / DONE_WITH_CONCERNS / NEEDS_CONTEXT / BLOCKED
- TDD 证据：RED 失败输出片段 + 失败原因分析 + GREEN 全绿输出
- 每个测试用例：名称 / 断言 / 设计理由（尤其加速模型与物理场景决策）
- 验证步骤逐条输出
- 偏离说明