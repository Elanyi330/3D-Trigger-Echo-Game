# 计划：AutoTraversal 转圈/卡顿/跳失 六项修复（F8-F13）

> 日期：2026-08-15。分支 feat/m1-assets，单目录（勿建 worktree）。
> 设计：docs/superpowers/specs/2026-08-15-auto-traversal-runup-fixes-design.md
> 修改文件：`Levels/M2_TDM/auto_traversal.gd`（唯一生产文件）+ 新测试 `test/unit/test_auto_traversal_runup.gd`。
> 既有测试：`test/unit/test_auto_smoke.gd`（装配 harness 唯一来源，测试复制其 `_assemble` 模式）、
> `test/unit/test_auto_traversal_plan.gd`（纯逻辑 static 测试范式）。

## 全局约束（逐字复制进每个任务 brief）

- 所有改动仅限 `Levels/M2_TDM/auto_traversal.gd` 与新测试文件。**禁止改动** MovementController /
  JumpSolver / 布局 / navmesh / 数据集（物理语义不变 → MOVEMENT_REV 不 bump）。
- TDD：每个任务**先写失败测试跑 RED（证明失败原因正确），再实现跑 GREEN**。禁止先写生产代码。
- 每任务完成后跑全量 GUT：`godot --headless --path . -s addons/gut/gut_cmdln.gd`（基线 387，
  任务新增测试后应 387+N 全绿；既有断言不得改——除非 brief 明确授权）。
- 本计划 4 任务全部落在同一文件——**串行派发**（上一任务 GREEN + 审查通过后才派下一任务）。
- 注释口径：新代码块注释注明「(2026-08-15 F8/F9/… 修复)」+ 一句机制说明，与文件既有风格一致
  （中文注释、参考既有 `_try_trigger` 注释密度）。
- `TRAVERSAL_REV` 在最后一任务（T4）统一 bump r7→r8（`at-r8:straight-runup+trigger-cone+anchor-precheck+wall-recover+vertical-jump+walk-progress`），
  T1-T3 期间不 bump（避免逐任务作废测试缓存——临时目录哈希各测试自算）。
- 浮点断言容差 1e-4；物理帧驱动断言（harness 类）用行为断言（verdict/计数器），不断言精确帧数。

## 任务表

| 任务 | 修复 | 内容 | 测试数（新增） |
|------|------|------|----------------|
| T1 | F8+F9 | RUNUP 直线化（转向门 0.3rad）+ 触发门控收紧（±25° 锥 / 近静止按路径声明） | 6 |
| T2 | F11+F12 | RUNUP 压墙 → recover + 垂直链接专用模式 | 4 |
| T3 | F10 | 锚点可达性预检（高差 >0.72 → 重寻路一次 → 诚实失败） | 2 |
| T4 | F13 | WALK 途经点 8s 超时 + 到达需位移 0.2m + 重寻路计数化 | 3 |

---

## T1：F8 RUNUP 直线化 + F9 触发门控收紧

### 接口块（精确签名，实现者照抄）

```gdscript
# 常量（auto_traversal.gd 常量区，紧跟 TURN_STOP_ANGLE 后）
const RUNUP_TURN_GATE := 0.3   # rad（≈17°）：助跑转向门——超差原地转（F8）

# 新增 static 纯谓词（classify_segments 附近，可测试）
static func target_yaw(from: Vector3, to: Vector3) -> float:
    var dir := to - from
    dir.y = 0.0
    return atan2(-dir.x, -dir.z)

# 新增 static 纯谓词：F9 触发门控
static func trigger_allowed(jump_v: float, hspeed: float, v_h: Vector2, td: Vector2,
        gate_speed: float, require_heading: bool, allow_near_still: bool) -> bool:
```

### 语义规格

1. `_steer_toward` 内部改用 `target_yaw()`（行为不变，纯重构消除重复公式）。
2. `trigger_allowed` 语义（与原 `_try_trigger` 差异点）：
   - `jump_v <= 0.4` → true（不变）
   - `hspeed > 0.5 and hspeed < gate_speed` → false（不变）
   - `hspeed <= 0.5` → **返回 allow_near_still**（原实现无条件放行——F9：近静止放行按路径声明）
   - `require_heading and td.length() > 0.01 and v_h.dot(td) < 0.9 * hspeed` → false
     （**锥 ±53° → ±25°**：cos 25° ≈ 0.906 → 用 0.9 系数；原 0.6）
   - 其余 → true
3. `_try_trigger(gate_speed, require_heading, allow_near_still)`：实例包装——读
   `_jump_v`、`_player.velocity`、`_travel_dir`，调 `trigger_allowed`。
4. `_runup_tick` 转向门（F8）：
   ```gdscript
   # 原：_cmd.move_axis = Vector2(0, _runup_throttle()) if _steer_toward(_from_point, delta) else Vector2.ZERO
   # 新：转向差 ≤ RUNUP_TURN_GATE 才前进（转向差大 → 原地转，消除最小转弯圆轨道）
   var toward_aligned := absf(angle_difference(
           _player.rotation.y, target_yaw(_player.global_position, _from_point))) <= RUNUP_TURN_GATE
   _cmd.move_axis = Vector2(0, _runup_throttle()) if toward_aligned else Vector2.ZERO
   _steer_toward(_from_point, delta)
   ```
5. `_runup_tick` 三条触发路径调用点（F9 按路径声明）：
   - 墙探预跳：`_try_trigger(gate_speed, true, false)`
   - 撞墙停摆：`_try_trigger(gate_speed, true, true)`
   - 圆盘触发：`_try_trigger(gate_speed, true, false)`
   - 其余逻辑（8s 超时/高度门/近墙抑制）不动

### 测试规格（test/unit/test_auto_traversal_runup.gd 新建，TDD RED 先行）

```gdscript
extends GutTest
const AT := preload("res://Levels/M2_TDM/auto_traversal.gd")
const TOL := 0.0001

# 1. target_yaw 锚点：from(0,0,0) to(0,0,-1)（北）→ yaw 0；to(1,0,0)（东）→ atan2(-1,0) = -PI/2
func test_target_yaw_anchors()

# 2. trigger_allowed 近静止：hspeed=0.3、gate=4.0、require_heading=true →
#    allow_near_still=true → true；allow_near_still=false → false
func test_trigger_allowed_near_still_gate()

# 3. trigger_allowed 方向锥：hspeed=5.0、gate=4.0、td=(1,0)、require_heading=true：
#    v_h 偏离 30°（cos=0.866 < 0.9）→ false；偏离 20°（cos=0.940 ≥ 0.9）→ true
func test_trigger_allowed_cone_25deg()

# 4. trigger_allowed 速度门：hspeed=3.5 < gate=4.0 → false；hspeed=4.5 ≥ 4.0 → true
#    （近静止阈值 0.5 与 gate 的边界：hspeed=0.6、gate=4.0 → 速度门 false）
func test_trigger_allowed_speed_gate()

# 5. trigger_allowed 原地跳恒放行：jump_v=0.3、hspeed=0、gate=9 → true
func test_trigger_allowed_stationary_jump()

# 6. 确定性：同参数两次全等（assert_eq 字典化调用结果）
func test_trigger_allowed_determinism()
```

### 验证

- RED：新测试 6 条先失败（target_yaw 未定义 → parse error 即 RED；写测试时先只加测试文件）。
- GREEN：T1 实现后新 6 绿 + 既有 387 绿。
- 冒烟 `test_full_traversal` 中 CorridorSlab 水平跳回归锚必须仍 success（直线化不得破坏低速跳）。

---

## T2：F11 RUNUP 压墙恢复 + F12 垂直链接模式

### 接口块

```gdscript
# 常量区新增（紧跟 RUNUP_TURN_GATE）
const VERTICAL_LINK_DIST := 0.05  # snap 后 from/to 水平距 < 此值 = 垂直链接（F12）

# 状态区新增（_speed_gate_relaxed 附近）
var _vertical_jump := false  # 当前跳跃为垂直链接模式（F12）：AIR 零水平输入
```

### 语义规格

1. **F12 检测**（`_enter_jump`，`_travel_dir` 计算处）：
   `_vertical_jump = Vector2(_to_point.x - _from_point.x, _to_point.z - _from_point.z).length() < VERTICAL_LINK_DIST`
   （置位必须在 `_to_point` 的 zone 重瞄准**之后**——垂直链接 dist 0 不会进 zone 重瞄准分支，但以
   最终 `_to_point` 口径判定最稳）。每次 `_enter_jump` 开头重置为 false。
2. **F12 触发路径**（`_runup_tick`）：`_vertical_jump` 时跳过墙探预跳块
   （`_travel_dir` 为零向量，射线退化——语义上垂直跳只走停摆路径）；
   停摆路径（`is_on_wall and along <= STALL_TRIGGER_ALONG`）成为唯一有效触发
   （F9 的 allow_near_still=true 已就位）。圆盘路径自然不触发（F9 近静止不放行）。
3. **F12 空中**（`_air_tick`）：
   `_cmd.move_axis = Vector2.ZERO if _vertical_jump else Vector2(0, 1)`
   （零水平输入 → 无 REST 漂移 → 纯弹道落回箱顶）。
4. **F11 压墙恢复**（`_runup_tick` 顺序约束）：
   - 在**停摆检查之后**追加：
     `_wall_press_detect(Vector2(_cmd.move_axis.x, _cmd.move_axis.y).length(), delta)`
     （传实际施加指令——与 TO_ANCHOR F7-3 同口径）
   - 在 `_runup_tick` **开头**（8s 超时检查之后）加：
     ```gdscript
     if _wall_follow:
         _recover_runup()
         return
     ```
     （压墙 0.5s 锁存 → 传送回锚点重跑，≤3 次有界——`_teleport_to` 自带 `_reset_wall_state`，
     `_wall_follow` 锁存随之清除，无状态泄漏）
   - 顺序理由（brief 必须写明）：停摆先于压墙检测执行——起跳点贴墙是**设计内停摆跳**
     （沿 ≤0.8 + on_wall），不能被压墙 recover 抢走；只有停摆不满足（沿 >0.8 = 跑道中段
     障碍楔死）时才落压墙 → recover。

### 测试规格

```gdscript
# 7. 垂直链接检测锚：_enter_jump 路径难在 GUT 直测——改测行为：
#    装配 harness（复制 test_auto_smoke._assemble），目标限定 ["WestClusterN_Box"]，
#    驱动 ≤60s → verdict == "success"（Crate_WN 垂直链回归锚：停摆触发 + 纯弹道落箱顶）
func test_vertical_link_crate_wn_success()

# 8. 垂直模式空中零输入锚：装配 harness，目标 ["WestClusterN_Box"]，驱动期间采样
#    jump_held 帧的 _cmd.move_axis（在测试内轮询 autopilot 状态）——jump 段 AIR 期间
#    move_axis == Vector2.ZERO 至少出现 1 帧
#    （实现：wait_physics_frames 循环内读 autopilot._cmd.move_axis——GDScript 无私有，
#    下划线成员可直读；测试注释说明「白盒采样」）
func test_vertical_jump_air_zero_axis()

# 9. EastSpurN 助跑卡死回归锚（F11）：目标 ["EastSpurN"]，驱动 ≤60s →
#    verdict != "stuck" 或 failure_reason != "助跑卡死"
#    （F8 直线化后 PavToSpur_E 可能直接 success——断言口径：不得以「助跑卡死」收尾）
func test_runup_no_wall_wedge_stuck()

# 10. WestTowerBox 既有跳跃目标回归（TowerBox_W Δh0.9 非垂直链接）：
#     目标 ["WestTowerBox"] 驱动 ≤60s → success（F11/F12 不得破坏正常链接执行）
func test_normal_link_still_works()
```

### 验证

- T2 后：新 4 绿 + T1 6 绿 + 既有 387 绿（合计 397）。
- 注意测试 7/10 是慢测试（物理秒 30-60s），与 test_auto_smoke 同豁免口径。

---

## T3：F10 锚点可达性预检

### 接口块

```gdscript
# 常量区新增（紧跟 VERTICAL_LINK_DIST）
const ANCHOR_REACH_EPS := 0.1  # 锚点面高 − 脚高 判差容差（F10）

# 状态区新增（_walk_replanned 附近）
var _anchor_fallback_done := false  # 锚点不可达重寻路一次性守卫（F10）
```

### 语义规格

1. `_enter_jump` 末尾（`_reset_stuck()` 之前）追加预检：
   ```gdscript
   # F10 锚点可达性预检：锚点面高 − 脚高 > STEP_MAX(0.62) + 0.1 → 步行不可达
   # （箱顶锚点 + 人在箱底类压墙 23s 的根治——0.8m > step-up 0.62 走不上去）
   if _waypoint_surface_y(_anchor) - _feet_y() > 0.62 + ANCHOR_REACH_EPS:
       if not _anchor_fallback_done and _replan_from_current():
           _anchor_fallback_done = true
           return
       _end_attempt("jump_missed", "锚点不可达（面高差 %.2fm）"
               % (_waypoint_surface_y(_anchor) - _feet_y()))
       return
   ```
   注：`_replan_from_current()` 内部重排 `_segments` 并置 `_seg_idx=0`，状态机落回 WALK——
   新路径可含 Crate_WS 类上箱链接（锚点可达）→ 正常执行；重寻路失败或新路径仍不可达
   （`_anchor_fallback_done` 已 true）→ 诚实失败。**不判「锚点低于脚」**（下行走下边缘是
   设计内，TO_ANCHOR 坠落重试已兜底）。
2. `_begin_attempt` 重置 `_anchor_fallback_done = false`（跨 attempt 状态泄漏防护）。
3. 垂直链接豁免说明（brief 写明，不需代码）：垂直链接锚点=箱底 nav 点（面高差 0），预检天然通过。

### 测试规格

```gdscript
# 11. 锚点不可达诚实失败锚（WestClusterS_Panel——23s 压墙样本）：
#     目标 ["WestClusterS_Panel"]，驱动 ≤90s →
#     断言：attempt 有记录；verdict != "stuck"；且
#     （verdict == "success" 或 failure_reason 含 "锚点不可达"）
#     ——重寻路经 Crate_WS 上箱后可能直接 success（更优路径），两种结局都证明
#     压墙卡死路径被根治；另断言 attempt 时长 < 40s（frame_count < 40*60）
#     （防回归成压墙长挂）。
func test_anchor_unreachable_fallback()
```

### 验证

- T3 后：新 2 绿（11 + 其一拆分断言）→ 合计 398。全量 GUT 绿。

---

## T4：F13 WALK 进展超时 + 到达需位移 + TRAVERSAL_REV bump

### 接口块

```gdscript
# 常量区新增（紧跟 ANCHOR_REACH_EPS）
const WP_TIMEOUT := 8.0        # 途经点进展超时（F13）：8s 未推进 → 强制重寻路
const SEG_MOVE_MIN := 0.2      # 到达推进需本段实际位移 ≥ 此值（防冻结点假到达重置卡死）
const MAX_REPLANS := 2         # attempt 级重寻路次数上限（原 _walk_replanned 一次性 → 2 次）

# 状态区变更
var _replan_count := 0         # 重寻路计数（替代 _walk_replanned: bool）
var _wp_t := 0.0               # 当前途经点累计计时（F13）
var _seg_move_origin := Vector3.ZERO  # 当前段起点（到达推进位移校验基准）
```

### 语义规格

1. `_walk_replanned: bool` **全站替换**为 `_replan_count: int`（`_begin_attempt` 重置 0、
   `_next_target` 的 no_path 分支不受影响）：
   - 新增 helper：
     ```gdscript
     ## 有界重寻路（F13）：计数 < MAX_REPLANS 才执行；成功置 _seg_idx=0 返回 true
     func _try_replan_from_current() -> bool:
         if _replan_count >= MAX_REPLANS:
             return false
         _replan_count += 1
         return _replan_from_current()
     ```
   - 调用点替换：`_walk_tick` 行走坠落分支（`not _walk_replanned` → `_replan_count < MAX_REPLANS`，
     调用改 `_try_replan_from_current()`）、卡死分支（同）、T3 锚点回退分支
     （`_anchor_fallback_done` 守卫不变，`_replan_from_current()` 改 `_try_replan_from_current()`）。
2. 途经点计时（`_walk_tick`）：
   - `_wp_t += delta`（tick 开头）；`_seg_idx` 推进（`_arrived` 分支）时 `_wp_t = 0.0` 并
     `_seg_move_origin = _player.global_position`
   - 超过 `WP_TIMEOUT` → 先 `_try_replan_from_current()`；失败或计数耗尽 →
     `_end_attempt("stuck", "途经点 %ds 无进展" % WP_TIMEOUT)`（传送 spawn + teleported 标记同
     既有 stuck 路径）
   - 注：`_wp_t` 检查放 `_arrived` 判定之前（顺序：坠落 → 滑墙 → 转向/移动 → 超时 → 到达 → 卡死）
3. 到达需位移：`_arrived(waypoint)` 为真且 `Vector2(_player.global_position.x -
   _seg_move_origin.x, _player.global_position.z - _seg_move_origin.z).length() >= SEG_MOVE_MIN`
   才推进 seg；位移不足 → 不推进（继续走，交超时/卡死兜底）——冻结点附近途经点不再
   假到达重置卡死计时。
4. `TRAVERSAL_REV` bump：`"at-r7:wall-loop-liveness"` → `"at-r8:straight-runup+trigger-cone+anchor-precheck+wall-recover+vertical-jump+walk-progress"`。

### 测试规格

```gdscript
# 12. 途经点超时重寻路锚：装配 harness，目标 ["EastTower"]，驱动 ≤60s →
#     断言 attempt 总帧数 < 40*60（原 71s 冻结样本压缩）且 verdict != "stuck" 或
#     失败原因为 "途经点 8s 无进展"/"卡死"（有界裁决即可，防 21s 冻结回归）
func test_walk_waypoint_progress_timeout()

# 13. _try_replan_from_current 有界性（白盒）：装配后不启动，直接连续调用 3 次
#     （先手动 _replan_count=0）→ 第 1、2 次返回 true，第 3 次返回 false
#     （MAX_REPLANS=2 钉死——防无限重寻路挂死）
func test_replan_bounded()

# 14. TRAVERSAL_REV 版本键：断言 AT.TRAVERSAL_REV == "at-r8:straight-runup+trigger-cone+anchor-precheck+wall-recover+vertical-jump+walk-progress"
#     （版本键参与记录哈希——bump 即作废旧记录，铁律钉死）
func test_traversal_rev_r8()
```

### 验证

- T4 后：新 3 绿 → 合计 401。
- 控制器最终验证（不属子代理）：
  - 全量 GUT 401/401
  - `godot --headless --path . -s tools/probe_v3_walk.gd` 79/79
  - `godot --headless --path . -s tools/probe_jump_edges.gd` 退出 0
  - 账本更新（docs/superpowers/ledger/2026-08-14-auto-traversal-ledger.md 追加 F8-F13 节）
  - HANDOFF.md 更新
  - 提交 + 实机重跑（用户侧）
