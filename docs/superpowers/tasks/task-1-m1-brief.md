# Task 1 Brief — WeaponCore 射击核心（hitscan + 后坐力 + 换弹）

> 分支: `feat/m1-weapon-system`（工作树 `/Users/elanyi/Projects/Trigger-Echo-m1`）
> 计划: `docs/superpowers/plans/2026-08-06-m1-weapon-system.md` 任务 1（先读 §5 任务 1 + §4 全局约束）
> 前置: 任务 0 已完成（Weapon_Resource + 4 个 .tres + 8 输入动作）
> 方法: TDD 铁律——先写失败测试（RED）→ 确认失败原因 → 实现（GREEN）→ REFACTOR。不跳步。

## 工作环境
- 工作树: `/Users/elanyi/Projects/Trigger-Echo-m1`（在此目录内操作）
- 测试命令: `godot --headless -s addons/gut/gut_cmdln.gd`（退出码 0 = 全绿）
- 新增 class_name 后需先 `godot --headless --import` 再跑测试（GUT 陷阱）
- 当前测试基线: 20/20 全绿（M0 14 + 任务 0 新增 6）

## 交付内容（严格按计划 §5 任务 1）

### `Weapons/WeaponCore.gd`（class_name WeaponCore extends Node3D）
```gdscript
signal shot_fired(ammo_left: int)
signal reload_started
signal reload_finished
signal hit_landed(target: Node, damage: float, position: Vector3)
signal out_of_ammo
func setup(resource: WeaponResource, camera: Camera3D) -> void
func try_fire() -> void
func can_fire() -> bool
func start_reload() -> void
func is_reloading() -> bool
func get_ammo() -> Vector2  # Vector2(mag, reserve)
func add_ammo(amount: int) -> void
func get_recoil_offset() -> Vector2  # 本次射击后坐力偏移（度）
func set_ads(active: bool) -> void
```

### 行为要求（全部 TDD 覆盖）

**1. 开火流程**：
- 弹药检查：mag=0 → 不发 `shot_fired`，发 `out_of_ammo`
- 射速节流：RPM → 单发间隔 = 60/RPM 秒；间隔内连按只响一次（AK 600RPM → 0.1s；Glock 400RPM → 0.15s）
- 全自动（FULL_AUTO）：按住 `fire` 持续射击（每过间隔发射）；半自动（SEMI_AUTO）：每次按键只发一发
- 开火后 mag-1，发 `shot_fired(mag)`

**2. hitscan 命中判定**（参考 `docs/superpowers/reference/m1-src/weapon_proto.gd` 的 `check_hitscan_collision()` 思路）：
- 射线从 camera 原点沿视向发出，`PhysicsRayQueryParameters3D`，**collision_mask=1（仅 Objects 层）**
- 命中最远距离 = `max_range`（AK 60m / Glock 30m）
- 命中判定部位：碰撞体 Group `"head"` → ×headshot_multiplier（4.0）/ `"limb"` → ×limb_multiplier（0.8）/ 无 Group → 躯干 ×1
- 伤害结算：`damage × 部位倍率 × 距离衰减`；距离衰减按 `falloff_curve`（0-有效=1.0，有效→最大线性插值到末段，下限 0.96）
- 命中发 `hit_landed(target, damage, position)`

**3. 换弹**（CS2 2026-03 规则）：
- `start_reload()` → `reload_time` 秒后完成 → 弹匣满、备弹减少
- **丢弃弹匣剩余**：换弹后弹匣 = magazine，备弹 -= (magazine - 换弹前弹匣值)；备弹不足则弹匣 = min(magazine, 备弹+旧弹匣剩余)
- 换弹中 `try_fire()` 无效
- 换弹可被打断：`interrupt_reload()`（切枪/开火时调用）→ 弹匣剩余**不返还**（保持换弹前状态，弹药已丢）

**4. 后坐力（CS2 Recoil Pattern）**：
- SET_PATTERN：按射击序号取 `pattern_offsets[i]`（i 从 0 递增，超出循环到最后一项），返回 `get_recoil_offset()`
- RANDOM：每发返回 `recoil_amount ± recoil_variance` 随机（垂直），水平随机 ±variance
- `recovery_speed`：停止射击后随时间衰减回零（本任务实现累计偏移的**计算**；恢复应用在任务 3 Head 接口）
- 首发精度：`first_shot_spread` 影响散布（本任务先实现后坐力偏移计算，散布角用于弹道偏移——第 1 发用 first_shot_spread，后续用 pattern/random）

**5. 弹药**：`get_ammo()` 返回 (mag, reserve)；`add_ammo()` 补给备弹（上限 max_ammo）

### 测试 `test/unit/test_weapon_core.gd`（RED 先行，每行为一测试）
- 开火：mag 减 1 + `shot_fired`；射速节流（连按两次仅一次）；弹匣空 `out_of_ammo`
- 命中：物理场景放 Box 目标（Objects 层，Group "torso"）→ `hit_landed` 伤害 36；Group "head" → 144；"limb" → 28.8；远距衰减（50m 处 AK 0.98 → 35.28）
- 换弹：计时完成弹匣满、备弹减；**丢弃剩余**（弹匣剩 10 → 换弹后 30，备弹减 20）；换弹中 fire 无效；打断后弹药不返还
- 后坐力：SET_PATTERN 第 i 发偏移 == pattern[i]；RANDOM 在 [amount-variance, amount+variance] 内；恢复衰减
- 半自动/全自动模式差异
- 浮点断言用 `assert_almost_eq`（容差 0.001）

**测试物理场景提示**：GUT 中可用 `add_child_autofree()` 或手动构建场景树——创建 Node3D 根 + CharacterBody3D/StaticBody3D 目标（collision_layer=1 Objects 层），WeaponCore 挂到根下，camera 用 Camera3D（需 add 到树并 `make_current` 或直接传 camera 引用），射线方向手动设（camera.look_at 目标）。物理射线需要场景在 physics 帧推进，用 `await get_tree().physics_frame` 或 `await wait_physics_frames()`。

### 参考源码（禁止在线拉取，读本地副本）
- `docs/superpowers/reference/m1-src/weapon_proto.gd`（hitscan 射线写法 + has_shot 信号）
- `docs/superpowers/reference/m1-src/Weapon_State_Machine/Weapon_State_Machine.gd`（shoot/换弹流程）

## 验证步骤（必须真实运行）
1. `godot --headless --import`
2. `godot --headless -s addons/gut/gut_cmdln.gd` 退出码 0，test_weapon_core 全过 + 全量不回归（含 M0 14 + 任务 0 6）
3. git commit（工作树内）：`git add -A && git commit -m "feat: M1 任务1 WeaponCore 射击核心（hitscan+后坐力+换弹）"`

## 完成报告
返回：DONE / DONE_WITH_CONCERNS / NEEDS_CONTEXT / BLOCKED
- 报告内容：实现的文件清单、测试结果摘要、遇到的问题、与 brief 的偏差
