# 自动跳跃遍历器（AutoTraversal）实施计划

> 2026-08-14。设计文档：`docs/superpowers/specs/2026-08-14-auto-traversal-design.md`。
> 用户拍板（三点）：目标=全部 160 面（22 无导航面记 no_path）；失败恢复=传送归位（记入 attempt）；记录=独立 `user://auto_traversal/`（自动期间挂起 JumpRecorder）。
> 分支 feat/m1-assets，单目录（勿建 worktree）。SDD：每任务实现者+审查者；模型：机械=haiku / 集成=sonnet / 审查=opus（继承）。

## 全局约束（逐字执行）

- **MOVEMENT_REV 不变**（`move-r3:step0.62+chain+firstframe,air-rest3.0/run0.76`）——钩子只换输入来源，物理语义零改动；测试钉死该常量。
- 自动遍历期间 `JumpRecorder.recording_enabled = false`，结束恢复；自动记录哈希随附 = `JumpRecordCore.map_hash(LAYOUT.all_solids(), MovementController.MOVEMENT_REV)`（复用现成函数）。
- 确定性：无随机（贪心最近未访问 + 固定参数微调网格）。
- 常量出处：跳跃引擎全部用 `JumpSolver`（G19.6/V7.54/DT/SPEED_CAP/CATCH_BAND）与 `jump_edges.gd`/`jump_edges_dataset.json`，禁散值。
- 帧采样 schema = JumpRecorder 15 字段 + `auto: true`。
- 新 class_name 脚本先 `godot --headless --path . --import` 再跑测试；不并行多个 godot 进程。

## 任务分解

### T1 MovementCommand + 控制器命令钩子（机械）

**文件**：新建 `Player/MovementCommand.gd`；改 `Player/MovementController.gd`；新建 `test/unit/test_auto_command.gd`。

**MovementCommand.gd**（完整代码）：
```gdscript
# Player/MovementCommand.gd —— AI/自动遍历驱动玩家控制器的命令接口（2026-08-14）。
# 未来 AI 移动底层 = 玩家运动逻辑：AI 队友/敌人通过本接口发指令驱动同款控制器。
# 语义：move_axis 为角色本地轴（x=左右/y=前后，与 Input.get_vector(&"move_left",…) 同构）；
# jump_pressed 为单帧边沿（控制器读取后清零）；crouch 预留（自动遍历恒 false，未来 AI 蹲伏接入点）。
class_name MovementCommand
extends RefCounted

var move_axis := Vector2.ZERO
var jump_pressed := false
var crouch := false
```

**MovementController.gd 改动（精确）**：
1. 新增成员：`var command_override: MovementCommand = null`（注释：非空时输入来源切换为命令接口，物理零改动——AI/自动遍历接入点）。
2. `_physics_process` 顶部：`input_axis = Input.get_vector(...)` 改为
   `input_axis = command_override.move_axis if command_override != null else Input.get_vector(&"move_back", &"move_forward", &"move_left", &"move_right")`。
3. 跳跃分支（`if is_on_floor():` 内）：`Input.is_action_just_pressed(&"jump")` 改为：
   ```gdscript
   var jump_pressed := false
   if command_override != null:
       jump_pressed = command_override.jump_pressed
       command_override.jump_pressed = false  # 边沿消费（读取即清零）
   else:
       jump_pressed = Input.is_action_just_pressed(&"jump")
   if jump_pressed:
       velocity.y = jump_height
       …（原起跳定档逻辑不变）
   ```
4. **其余一字不动**（accelerate/step-up/落地钳制/空中控制全不变）。

**测试（先 RED 后 GREEN，test_auto_command.gd）**：
1. `test_command_axis_drives_character`：实例化 Player.tscn（test_level_geometry 同款装配），注入 `MovementCommand`，`move_axis=(0,1)`，60 物理帧后位移朝角色前方（rotation.y=0 时 -Z 方向）且 >0.5m；`move_axis=(1,0)` 位移朝 +X。
2. `test_command_jump_edge_consumed`：`jump_pressed=true` 一帧后控制器起跳（velocity.y==7.54 或离地），下一帧 `command.jump_pressed==false`（边沿消费），且不再连续起跳（观察 N 帧 is_on_floor 只离地一次）。
3. `test_override_null_restores_input_path`：override=null 时 `input_axis` 与 `Input.get_vector(...)` 同值（headless 无输入为 ZERO）；注入再释放后行为恢复（再次注入仍生效）。
4. `test_movement_rev_unchanged`：`MovementController.MOVEMENT_REV == "move-r3:step0.62+chain+firstframe,air-rest3.0/run0.76"`（钉死——本任务红线）。

**验证**：`-gselect=test_auto_command` 全绿 + 全量 GUT 364 不减。

### T2 规划器/跳跃引擎纯逻辑（标准）

**文件**：新建 `Levels/M2_TDM/auto_traversal.gd`（本任务只写 static 纯逻辑段 + 类骨架）；新建 `test/unit/test_auto_traversal_plan.gd`。

**static 接口（签名固定）**：
```gdscript
class_name AutoTraversal
extends Node

const JE := preload("res://Levels/M2_TDM/jump_edges.gd")

## 路径段分类：path 相邻点对与 links 端点（已 snap 的 from/to）首尾双向匹配 ≤1.0m → 跳跃段
## （携带 link）；其余为行走段。返回 [{"kind": "walk"|"jump", "start": Vector3, "end": Vector3,
## "link": Dictionary}]
static func classify_segments(path: PackedVector3Array, links: Array) -> Array

## 起跳参数选择：human（语料 p50 起跳速度，可空）→ 钳入求解器可行带 [v_req, min(v_hi, cap)]；
## 无人类数据 → min(v_req * 1.15, cap)。返回 {"v": float, "source": "corpus"|"solver"}
static func pick_jump_speed(delta_h: float, dist: float, human_p50: float) -> Dictionary

## 起跳触发距离：水平投影到起跳点 ≤ v*DT + 0.05（约 1 帧）时触发
static func trigger_distance(v: float) -> float

## 着陆判定：on_floor 且（floor_name == to_face 或 xz 在接收区矩形内且 |脚y−top|≤0.2）→ success；
## 超时/落错面/坠落由调用方枚举。返回 {"verdict": "success"|"pending"|"wrong_face"|"fell"}
static func landing_verdict(on_floor: bool, floor_name: String, pos: Vector3,
        to_face: String, zone_rect: Rect2, top_y: float) -> Dictionary
```

**测试**（合成数据 + 真实 54 链接）：
1. 合成 path 穿过 `RimGap_E` 两端点 ±0.5 → 分类恰 1 个 jump 段且 link 名对；纯直线 path → 全 walk。
2. 真实数据锚：构造 path 从西摊阁中心经 `PavToSpur_W` 端点至西横脊墙中心 → 中间段识别为 PavToSpur_W。
3. `pick_jump_speed(0.8, 4.235, 5.0)`（ClusterToRim_WS 修复边）：human 5.0 ∈ [5.77?? — 注意 v_hi=dist/t_min：Δh0.8 → t_min=3帧=0.05 → v_hi=4.235/0.05=84.7 → 可行带 [5.77, 6.35]：5.0 低于 v_req → 钳到 5.77，source 仍 "corpus"（钳制注记）——**断言 v==5.77**；`pick_jump_speed(0.8, 4.235, 0)` → v = min(5.77*1.15, 6.35) = 6.35? 5.77*1.15=6.64→6.35，断言 6.35 source "solver"。再锚 `pick_jump_speed(1.9, 1.58, 5.45)`（翼墙→门梁人类）→ 5.45 ∈ [3.16, 5.267]?? 5.45 > v_hi 5.267 → 钳到 5.267（过快到早到）——断言 v≈5.27。
4. `trigger_distance(6.35)` ≈ 0.1558（6.35/60+0.05）。
5. `landing_verdict` 四态：正确面名/位置在矩形内/落错面/坠落（y 低于 top−2）。
6. 确定性：同输入两次全等。

**验证**：`-gselect=test_auto_traversal_plan` 全绿 + 全量不回归。

### T3 AutoTraversal 状态机与执行循环（标准）

**文件**：续写 `Levels/M2_TDM/auto_traversal.gd`；新建 `test/unit/test_auto_smoke.gd`。

**规格**：
- `setup(player, nav_region, record: AutoTraversalRecord, hud: Callable)`；信号 `attempt_finished(face, verdict)`、`progress_changed(total, success, fail)`。
- 状态机：`idle → plan(目标面=贪心最近未访问) → walk(行走段) → jump(跳跃段,≤3 重试) → verify(着陆判定) → record → next`。22 无导航面：路径查询末端距目标>0.8 → 立即记 `no_path` 不执行。
- 行走：`rotation.y` 以 4 rad/s lerp 至路径方向；`command.move_axis=(0,1)`；途经点切换半径 0.8m；卡死检测（5s 位移<0.3m）→ `stuck` 记录+传送归位。
- 跳跃执行：锚点=起跳点沿行进反方向 2.5m（钳 from 面矩形）；直线助跑至 v（起跳前 0.5m 距离检查实际速度，不足则补跑）；投影距离 ≤ trigger_distance(v) → `jump_pressed=true`；窗口期不按跳；着陆判定轮询至 t_max+1.5s；重试微调：第 2 次 v×1.05、第 3 次起跳点偏移 0.1m。
- 失败传送归位：`global_position = 上次安全导航点`（记入 attempt.teleported）；坠落 y<−2 → 传送出生点。
- 目标面成功判据：站在面上（landing_verdict 同口径）；**同一目标面路径无跳跃段时到达即 success**。
- 全部 160 面处理完 → 状态 `done`（信号通知，HUD 显示完成）。

**冒烟测试（test_auto_smoke.gd）**：GUT 内建 MapGreybox + NavigationRegion(navmesh.res) + 54 NavigationLink（snap 同 probe_navmesh 流程）+ Player.tscn + AutoTraversal + 临时记录目录；目标限定 `["AltarPlatform", "WestTower"]`；跑 ≤120 物理秒（wait_physics_frames 循环）断言：≥1 个 attempt success、attempt 文件存在、JumpRecorder 未被写入（注入假 recorder 验证 recording_enabled=false 置位）。超时即失败（防 CI 挂死）。

**验证**：`-gselect=test_auto_smoke` 全绿 + 全量不回归 + `probe_v3_walk` 79/79。

### T4 记录器 AutoTraversalRecord（标准）

**文件**：新建 `Levels/M2_TDM/auto_traversal_record.gd`（class_name AutoTraversalRecord，extends RefCounted，base_dir 可注入）；新建 `test/unit/test_auto_traversal_record.gd`。

**接口**：
```gdscript
static func frame_line(t_ms: int, p: Vector3, v: Vector3, yaw: float, pitch: float,
        axis: Vector2, crouch: bool, jump_held: bool, on_floor: bool,
        floor_name: String) -> String   # JSON 行，15 字段 + "auto": true
func begin_attempt(face: String, link: String, plan: Dictionary) -> int   # 开 attempt 缓冲
func sample_frame(...同 frame_line 参数) -> void                           # 追加帧行
func end_attempt(verdict: String, failure_reason: String, teleported: bool,
        params_used: Dictionary) -> void   # 写 attempts/ep_%04d.jsonl（head 行 + 帧行）+ summary 增量
func summary_dict() -> Dictionary   # {"counters": {...}, "per_face": {...}}
func set_progress(visited: int, total: int) -> void
```
- `setup(map_hash_str: String, base_dir := "user://auto_traversal")`：manifest 缺失/哈希不符 → 清空重建（同 JumpRecorder 铁律）；哈希一致 → 保留（**跨会话续跑**：manifest + summary 恢复 per_face）。
- head 行：`{attempt_id, face, link, verdict, failure_reason, plan, params_used, teleported, frame_count}`。

**测试**：哈希不符清空重建/一致保留；attempt 写盘后读回逐字段相等；frame_line 15+1 字段；summary 计数正确；确定性（两次同输入字节一致）。

**验证**：`-gselect=test_auto_traversal_record` 全绿 + 全量不回归。

### T5 L_M2 装配 + HUD + 输入锁定（标准）

**文件**：改 `Levels/M2_TDM/L_M2.gd`。

**规格**（2026-08-14 用户拍板修正：全锁 + Esc 直接退出，无暂停面板）：
- `_ready`：先建 `AutoTraversal` 节点 add_child（**在 Player 之前**——命令先行，读玩家上一帧状态），再建玩家，后 `autopilot.setup(_player, nav_region, _auto_record, _hud_cb)`；记录器 `_auto_record` 用当前布局哈希 setup（哈希一致自动恢复 summary → 跨会话续跑）。
- **P 键启动**（`_input`，仅 autopilot idle 时响应 KEY_P）：启动 = 挂起 JumpRecorder（recording_enabled=false）+ 挂起轮询输入节点（`_manager.process_mode=DISABLED`、玩家下 Crouch 节点 process_mode=DISABLED）+ 显示 HUD 面板。运行中 P 无效。
- **输入锁定**（`_input`，autopilot active 时）：`ui_cancel` → `get_tree().quit()`（**Esc 直接退出程序=训练结束**）；其余一切事件 → `get_viewport().set_input_as_handled()`（拦截 L_M2 自身 K/R/切枪路线 + Head 事件式鼠标视角）。
- done（160 面全处理）→ 解锁：恢复 JumpRecorder/WeaponManager/Crouch 状态 + HUD 显示完成。
- HUD 面板（`_hud_label` 工厂 + Panel，右上角）：`自动遍历中`｜目标面名｜动作｜`已处理 X/160 · 成功 S · 失败 F`｜`Esc 退出程序`；信号驱动刷新（attempt_finished/progress_changed）。

**验证**：`godot --headless --path . -s addons/gut/gut_cmdln.gd` 全量（含 test_integration 既有 L_M2 场景测试不回归）+ 锁定行为实机验证交用户验收（headless 无法测 UI/Input 锁定——报告注明）。

### T6 后处理分析（标准）

**文件**：新建 `tools/analyze_auto_traversal.py`（纯标准库）。

**规格**：
- 读 `~/Library/Application Support/Godot/app_userdata/Trigger Echo/auto_traversal/`（manifest + summary + attempts）与 `Levels/M2_TDM/jump_edges_dataset.json`。
- 每边/每面：attempt 数、成功率、失败原因分布、实测起跳速度 p50（首帧 |v_xz|）vs 人类 p50 vs 求解器 v_req/v_hi。
- 重点对照表：10 条端点级 infeasible 链接（WingToLintel×4/TowerToRim×2/RimToWing×4）从面级起跳区执行的实测成功率（验证"面级 zone 替代链接端点"的 M4 口径）。
- 输出终端报告 + `/tmp/auto_verification.json`（供后续并入数据集）；无 attempts 数据时打印提示并退出 0（不误报）。

**验证**：用 test_auto_smoke 的真实产出跑一遍 + 构造 2 个合成 attempt（成功/失败各一）核对统计；python3 -m json.tool。

### T7 文档 + 全量门禁 + 验收指南（控制器）

- HANDOFF（新功能段+运行方式+P/Esc 说明）、记忆（auto-traversal 条目）、账本 `2026-08-14-auto-traversal-ledger.md`。
- 全量门禁：GUT（364+新增）、probe_v3_walk 79/79、probe_navmesh 全过、probe_jump_edges 退出 0。
- **用户验收指南**（写入 HANDOFF）：启动游戏 → P 开启 → 观察自动遍历 ≥10 分钟（访问 ≥30 面、≥5 个跳跃高面）→ Esc 暂停/继续/停止 → 手动 WASD 立即接管 → 退出后看 `user://auto_traversal/` 记录与 `python3 tools/analyze_auto_traversal.py` 报告。

## 门禁汇总

| 门禁 | 命令 | 期望 |
|------|------|------|
| GUT | `godot --headless --path . -s addons/gut/gut_cmdln.gd` | 364+新增全绿 |
| 冒烟 | 含于 GUT（test_auto_smoke） | ≥1 面 success、文件落盘 |
| 漫游 | `tools/probe_v3_walk.gd` | 79/79 |
| navmesh | `tools/probe_navmesh.gd` | 全过 |
| 跳跃边 | `tools/probe_jump_edges.gd` | 退出 0 |
| 机制不变量 | test_auto_command 4 | MOVEMENT_REV 钉死、物理零改动 |
