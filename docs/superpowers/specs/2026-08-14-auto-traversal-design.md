# 自动跳跃遍历器（AutoTraversal）设计方案

> 日期：2026-08-14。阶段：设计已验收（三点拍板）→ 实施计划 docs/superpowers/plans/2026-08-14-auto-traversal.md → SDD。
> 用户需求：自动操纵第一人称角色在全地图各平台间自动移动/跳跃，尽量到达全部已计算平台；
> 用户视角 = 角色自主行动（零手动操作）；退出界面暂停；成功与失败数据全部记录，
> 作为未来 AI 开发的关键参考（未来 AI 移动底层 = 把当前玩家角色的运动逻辑搬到队友/敌人身上）。

## 一、目标与验收标准

1. 按 P 键（或启动参数）开启自动遍历：角色自主寻路+行走+跳跃，逐个尝试到达全部**已计算平台**。
2. 用户全程零操作即可观看；Esc 打开暂停面板（继续/停止自动/退出游戏），任意手动移动/跳跃输入立即停止自动操作。
3. 每次尝试（成功与失败）完整记录：计划、使用的物理参数、逐帧轨迹、判定与失败原因。
4. 记录独立于人类语料（`user://jump_training/` 不受污染）；自动遍历期间暂停 JumpRecorder。
5. 验收判据：
   - GUT 全绿（364 基线 + 新增测试）；
   - 演示运行：自动遍历 ≥10 分钟不崩溃，访问面 ≥30 个（含 ≥5 个经跳跃链接到达的高面），attempt 文件与 summary 计数一致；
   - 失败数据完整：每个失败 attempt 有 failure_reason 与逐帧轨迹；
   - 移动机制零改动（MOVEMENT_REV 不变、跳跃记录重置机制不触发）。

## 二、目标平台集合（实测数据，2026-08-14 探针）

- 面表 `jump_edges.faces()` 共 **160 面**；探针实测 **138 面在导航网格上**（面中心 top+0.4 处 closest<0.8）。
- 22 面无导航面（被遮蔽无法烘焙：边界墙顶/钟门柱顶/营墙顶/rim 中段 2 段）→ **先验不可达**，自动遍历仍会尝试并记录 `no_path`（失败数据同样是产出）。
- 138 面中仍有导航孤岛（伞顶等）→ 运行时实测判定。**预期成功率下限**：链接覆盖的可达面 ≥60 个（19 关键点门禁已实证 + 链接链覆盖）。
- 目标顺序策略：贪心最近未访问面（当前位置 navmesh 路径长度排序），确定性无随机。

## 三、架构总览（4 层 + HUD）

```
┌─────────────────────────────────────────────────────────────┐
│ L_M2（装配层）：AutoTraversal 节点加在 Player 之前（树序=命令先行）│
│   ├─ 状态机（空闲/寻路/行走/跳跃执行/重试/记录/下一个目标）         │
│   ├─ 规划器：NavigationServer3D.map_get_path(当前位置→目标面中心)  │
│   │    路径段分类：普通行走段 vs 跳跃链接段（端点与 54 链接        │
│   │    snap 端点匹配 ≤1m）                                      │
│   ├─ 执行器：行走（转向+前进轴）/ 跳跃引擎（求解器参数+语料采样）    │
│   ├─ 安全网：卡死检测/超时/坠落检测/失败重定位（传送，记录）        │
│   └─ 记录器 AutoTraversalRecord：user://auto_traversal/          │
│       manifest.json + attempts/*.jsonl + summary.json           │
├─ MovementController（唯一改动点：+命令接管钩子，物理零改动）        │
├─ HUD：状态/目标/进度/提示；P 切换；Esc 暂停面板；手动输入即停        │
└─ 后处理：tools/analyze_auto_traversal.py（成功率 vs 求解器 vs 语料）│
```

## 四、关键设计决策（2026-08-14 用户已拍板：三项全选推荐方案）

### 决策 1：目标范围——全部 160 面 ✅拍板方案 A

- **方案 A（推荐）**：全部 **160 面**逐面尝试——138 导航面走真实寻路+执行；22 无导航面走一遍路径查询即记录 `no_path`（先验不可达）。失败数据本身就是产出（孤岛/不可达的实证清单，供 M4 避坑）。
- 方案 B：只遍历链接可达集（先跑离线 BFS 筛出可达面再遍历），演示更"顺滑"但丢失失败数据。
- **推荐 A**：用户明确"失败的数据同样是关键参考"。

### 决策 2：失败恢复 ✅拍板方案 A（传送归位）

- **方案 A（推荐）**：跳跃失败（坠落/卡死/超时）→ 记录 → **传送**回起跳面安全点继续下一个目标（传送事件记入 attempt 记录）。数据采集工具以覆盖率为重，演示不卡死。
- 方案 B：纯物理（掉下去就重新寻路走回）——更"真实"但慢 3-10 倍，演示体验差。
- **推荐 A**；可在 attempt 记录里保留"失败后传送"标记，M4 训练时不采信该类轨迹。

### 决策 3：记录隔离 ✅拍板方案 A（独立目录）

- **方案 A（推荐）**：独立 `user://auto_traversal/`（自动遍历期间 JumpRecorder.recording_enabled=false 暂停）。人类语料纯度是 M4 校准基准，自动数据物理等价但语义不同（失败/重试/传送），必须隔离。
- 方案 B：混入 jump_training——污染人类校准分布，否决。

## 五、分层详细设计

### 5.1 MovementController 命令接管钩子（唯一生产代码改动）

```gdscript
# Player/MovementController.gd 新增（物理语义零改动，MOVEMENT_REV 不 bump）
var command_override: MovementCommand = null  # class_name MovementCommand（新文件）
# _physics_process 内：
#   input_axis = command_override.move_axis if command_override else Input.get_vector(...)
#   跳跃：command_override.jump_pressed（边沿触发，读后清零）替代 Input.is_action_just_pressed
#   下蹲：command_override.crouch 替代 Input 查询
```

- `MovementCommand`（新文件，未来 AI 队友/敌人驱动同一控制器的**接口雏形**）：
  `{move_axis: Vector2（角色本地前后/左右）, jump_pressed: bool（单帧边沿）, crouch: bool}`。
- 自动遍历/未来 AI 只通过此接口发指令——**AI 移动底层 = 玩家控制器**的承诺在此落地。
- 不 bump MOVEMENT_REV 的依据：输入来源不是移动语义（物理公式/参数全不变）；且自动遍历期间 JumpRecorder 已暂停，无污染窗口。
- TDD：命令接管后 axis 移动/跳跃/读后清零/释放恢复 Input，全部 GUT 覆盖。

### 5.2 规划器（AutoTraversal 内，纯逻辑可单测）

- `map_get_path(当前位置, 目标面中心@top+0.4)`（snap 后）。
- 路径段分类：逐对相邻点，与 54 链接的 snap 端点（注册时 `map_get_closest_point` 后缓存）双向匹配（首尾各 ≤1m）→ 跳跃段；其余为行走段。跳跃段携带 link 引用（含 Δh/dist/from_face/to_face）。
- 目标排序：未访问面按当前路径长度贪心；每次成功后重排。
- 路径末端距目标 >0.8 → `no_path` 失败（部分路径判据，历史坑）。

### 5.3 执行器

**行走段**：
- 朝向：`rotation.y` 以最大角速度（~4 rad/s）lerp 至路径方向（平滑转向，防晕）。
- 移动：`move_axis = (0, 1)`（前进）；到达途经点（≤0.8m）切下一途经点。
- step-up 0.62 自动处理台阶；≤0.6 高差无需跳跃。

**跳跃段（跳跃引擎，本轮核心）**：
1. **参数选择**：edge 有人类语料 → 起跳速度取人类 p50（±求解器可行域内钳制）；无 → 求解器 `v = min(v_req × 1.15, cap)`；降落目标点 = 接收区内距起跳点最近的点（刀锋边最大化余量；`landable_zone` 网格采样兜底验证）。
2. **助跑**：从 from_face 的起跳区背侧锚点（沿行进反方向 2-3m，受面矩形钳制）直线加速至 v（lerp 加速度 8 收敛快，1.5m 即可达 98%）；助跑空间不足 → 原地跳（REST 空中转向档）。
3. **起跳触发**：沿行进方向投影到起跳点的距离 ≤ v·dt + 0.05（约 1 帧）时置 `jump_pressed=true`。
4. **着陆判定**：`is_on_floor()` 且（floor_name == to_face 或位置在接收区矩形内且 |y−top|≤0.2）→ success；超时（solver t_max+1.5s）→ `jump_timeout`；落错面/坠落（y 低于起跳面−2m）→ `jump_missed`。
5. **重试**：每链接 ≤3 次（参数微调：速度 +5%、起跳点偏移 0.1m 网格）；3 次失败 → 记录后传送归位，该目标面标记 `failed`，继续下一个目标。

**安全网**（全部记录进 attempt）：卡死（5s 内位移 <0.3m 且不在等待）→ `stuck`；行走段超时（段长/3m/s + 10s）→ `walk_timeout`；坠落出图（y < −2）→ 传送出生点。

### 5.4 记录器（AutoTraversalRecord）

```
user://auto_traversal/
  manifest.json   {map_hash, movement_rev, created_at, attempt_count, target_faces: 160}
  summary.json    {per_face: {verdict, attempts, link}, counters}   # 每次尝试后增量写
  attempts/ep_%04d.jsonl
    head 行: {attempt_id, face, link|null, verdict, failure_reason,
              plan: {segments, params_used: {v_target, takeoff, landing}}, teleported: bool}
    帧行:   沿用 JumpRecorder 15 字段（t_ms/px..pz/vx..vz/yaw/pitch/ix,iy/crouch/jump_held/on_floor/floor_name）
    + 新增: auto 标志字段（区分自动帧）
```
- 地图哈希随附（铁律）：manifest.map_hash = 当前布局哈希（JumpRecordCore.map_hash(all_solids, MOVEMENT_REV)）。
- 一次 attempt = 一次"目标面到达尝试"（含 0..N 次跳跃重试），帧采样从寻路开始到判定结束。
- 确定性：无随机（贪心+固定参数网格）。

### 5.5 HUD 与操控（2026-08-14 用户拍板修正：全锁 + Esc 直接退出）

- **P：启动自动遍历**（仅 idle 时响应；运行中 P 无效，无切换回退——训练结束方式=退出程序）。
- **运行期间所有玩家操作按钮锁定**：
  - 事件式输入（鼠标视角 Head._input / 切枪换弹瞄准 / K/R 键）：L_M2._input 全量 `set_input_as_handled()`（ui_cancel 除外）——根节点先于子节点收到事件，消费即拦截；
  - **轮询式输入**（WeaponManager 开火轮询 `is_action_pressed("fire")`、Crouch 蹲伏轮询 `is_action_pressed("sprint")`）：事件消费拦不住 Input 轮询 → 运行期间这两个节点 `process_mode = DISABLED` 挂起（done/结束后恢复）。
  - MovementController 的移动/跳跃已被 command_override 接管，真实输入天然无效。
- **Esc：直接退出程序**（ui_cancel → get_tree().quit()，训练结束；记录已实时落盘不丢）。
- **跨会话续跑**：manifest/summary 哈希一致即恢复已访问面集合，下次启动 P 从上次进度继续（"Esc 退出"流程的闭环）。
- 全部 160 面处理完（done）→ 解锁操作 + HUD 显示完成（Esc 仍退出，P 可重启新一轮）。
- HUD 右上角面板：`自动遍历中`｜目标：<面名>｜动作：寻路/行走/跳跃n/重试｜`已处理 X/160 · 成功 S · 失败 F`｜`Esc 退出程序`。
- 自动遍历期间 `JumpRecorder.recording_enabled = false`（独立记录决策 3 落地；done/结束后恢复）。

### 5.6 后处理分析（tools/analyze_auto_traversal.py）

- 每边/每面：attempt 数、成功率、失败原因分布、实测起跳速度分布 vs 人类 p50 vs 求解器 v_req；
- 重点对照：10 条端点级 infeasible 链接（WingToLintel 等）从面级起跳区执行的实测成功率——**实证验证"面级 zone 替代链接端点"的 M4 消费口径**；
- 输出报告 + `auto_verification.json`（可并入 jump_edges_dataset.json 供 M4）。

## 六、与未来 AI 的关系（本方案的长期价值）

| 组件 | 未来复用 |
|------|---------|
| MovementCommand + 控制器钩子 | **M3/M4 AI 队友/敌人驱动玩家同款控制器的唯一接口**（用户承诺的"AI 移动底层=玩家运动逻辑"） |
| 跳跃引擎（参数选择/助跑/触发/判定） | ②(4) M3/M4 接口设计的**执行原型**（寻路过边→起跳区→求解器参数+语料采样执行跳跃） |
| 自动遍历记录 | AI 跳跃执行的真实成功率/参数分布基准（与人类语料、求解器三源对照） |
| 失败数据 | 不可达面/不可执行链接的实证清单（M4 避坑 + 数据修正信号） |

## 七、风险与对策

| 风险 | 对策 |
|------|------|
| 刀锋边（margin<5%）自动执行成功率低 | 预期内——失败数据有价值；参数微调重试 3 次；语料 p50 优先 |
| 一帧延迟控制振荡（自动节点在玩家前） | 60Hz 下 16ms 延迟对转向无影响；起跳触发 epsilon 已含 v·dt |
| 长路径寻路抖动 | 途经点 0.8m 半径切换 + 卡死检测重寻路 |
| 用户视觉眩晕（视角自转） | 转向限速 4 rad/s + 面板提示 |
| 记录膨胀（逐帧 60Hz） | 与人类语料同规模（577 episodes 先例），无问题 |

## 八、文件与任务拆解预估（writing-plans 阶段细化）

1. `Player/MovementController.gd` +新 `Player/MovementCommand.gd`（钩子+TDD）
2. `Levels/M2_TDM/auto_traversal.gd`（规划器+执行器纯逻辑，可单测部分抽 static）
3. `Levels/M2_TDM/auto_traversal_record.gd`（记录器 core+IO，仿 JumpRecordCore 分层）
4. `Levels/M2_TDM/L_M2.gd` 装配 + HUD/按键/暂停面板 + JumpRecorder 挂起
5. 测试：test_auto_command / test_auto_traversal_plan / test_auto_traversal_record + headless 冒烟（60s 实跑 ≥1 面成功）
6. `tools/analyze_auto_traversal.py`
7. 文档/账本/记忆同步 + 全量门禁
