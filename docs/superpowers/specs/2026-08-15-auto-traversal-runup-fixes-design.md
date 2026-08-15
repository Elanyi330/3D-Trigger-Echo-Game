# 设计：AutoTraversal 转圈/卡顿/跳失 六项执行层修复（F8-F13）

> 日期：2026-08-15。分支 feat/m1-assets，单目录（勿建 worktree）。
> 触发：用户实机反馈「跳跃前莫名其妙转圈」+「失败率/卡顿高」→ 119 attempt 帧数据根因分析。
> 依据：docs/superpowers/ledger/2026-08-14-auto-traversal-ledger.md（F1-F7 历史）；本设计为 F8-F13。
> 变更全部落在 `Levels/M2_TDM/auto_traversal.gd`（+ 新测试文件）；`TRAVERSAL_REV` r7→r8（铁律：逻辑变更自动作废旧记录）。

## 一、根因（帧数据证据，2026-08-15 分析）

### RC-1 跳跃前转圈 = 最小转弯圆轨道（核心）

纯追踪转向（TURN_RATE 4 rad/s）+ 助跑速度 ≈ v → 最小转弯半径 R_min = v/ω。
触发圆盘 0.6m 在轨道**内侧**，v > 2.4 m/s 时永远不可达：

| 链接 | jump_v | 理论 R_min=v/4 | 实测轨道半径 | 白转时长 |
|------|--------|----------------|--------------|----------|
| PavToSpur_E | 5.45 | 1.36m | 1.07-1.64m | 30-43s（EastTower/RimE_T）|
| PavToCluster_E | 5.45 | 1.36m | 2.44m | — |
| Crate_WN | 5.45 | 1.36m | 2.24m | — |
| RampTopToCorridor | 2.17 | 0.54m | 0.68m | — |

F5 的 0.6m 圆盘假设 v≈2.08（R_min 0.52 < 0.6）——只对低速跳成立。现状 8s 超时
传送回锚点重转（EastTower 转 4 轮 34s 后强制起跳，落点随轨道相位随机）。成功样本
基线：起跳前平均累计旋转 4.22rad——**转圈是系统性行为，连成功跳都在转**。

### RC-2 漂移跳（jump_missed 主因之一）

方向锥 ±53°（cos 0.6）+ 近静止（≤0.5m/s）直接放行 → ep_0025 实测起跳方向偏离
travel_dir 45°、Crate_WN 链 6 面全因「travel_dir=0 + 残余动量方向=落点方向」失跳。
0.4m 深接收区（簇板）吃不下漂移。

### RC-3 卡顿三子类

- (a) RC-1 轨道本身（30-43s 白转）
- (b) 不可达锚点压墙：WestClusterS_Panel 锚点在 0.8m 箱顶、人在箱底（0.8 > step-up
  0.62 走不上去）→ 压墙振荡 23s（x ±0.26m、yaw ±3.14 翻转、axis 恒 0.5）
- (c) step-up 楔死冻结：EastTower 冻结 (18.59, 2.17, -5.53) 21s——velocity 恒 0、
  无 floor 无 wall 碰撞、axis=1.00；冻结点附近途经点「假到达」（高度门挡不住的
  邻近点）推进 seg 并重置卡死计时 → 卡死 5s+重寻路后仍冻 21s

### RC-4 助跑楔墙无恢复（EastSpurN/WestSpurS「助跑卡死」）

轨道漂移进墙角 → 全速压墙冻结（hspeed 5.45 位移 0）→ RUNUP 阶段无压墙检测
（滑墙只在 WALK/TO_ANCHOR）→ 5s 卡死裁决。

### RC-5 数据缺口（本轮不动，留 M4）

- 34 no_path 中 ~5 个 0.9m 箱缺 ground→box 链接（BeltN_Box1/2、BeltS_Box1/2、
  CornerNE_Box1）；其余 29 个墙/柱/伞/屏/屋顶合理不可达（M4 zone 级）
- 箱顶→簇板链（CrateToCluster）zone 级执行（既有拍板）

## 二、修复设计（F8-F13）

物理依据：控制器加速度 lerp-8 → 静止到 0.9v 仅需 **0.96m**（∫v_target(1−e^−8t)），
2.5m 直线助跑对速度门富余——**直线化后速度门必然可达**。

### F8 RUNUP 直线化（RC-1 根治）

- 新增 `RUNUP_TURN_GATE := 0.3`（rad ≈17°）：`_runup_tick` 的转向门从
  `_steer_toward` 的 TURN_STOP_ANGLE(1.4) 改为专用更严阈值——转向差 > 0.3 →
  move_axis=ZERO 原地转（TURN_RATE 4 rad/s，最坏 180° 转 0.78s）；≤ 0.3 →
  直线加速跑（保持 `_steer_toward(_from_point)` 微修正）
- 锚点已在 travel_dir 反向延长线上（既有 `_compute_anchor`），对准后锚点→起跳点
  即直线，穿盘横向偏差 ≈0，方向锥自然满足
- 预期：PavToSpur 类 30-43s 转圈 → ~3s 直线助跑；8s recover 兜底保留（不应再触发）

### F9 触发门控收紧（RC-2 根治）

- `_try_trigger(gate_speed, require_heading)` → `(gate_speed, require_heading, allow_near_still)`：
  - 方向锥 ±53° → **±25°**：`v_h.dot(td) >= 0.9 * hspeed`（cos 25°≈0.906）
  - 近静止（hspeed ≤0.5）放行改为**按路径声明**：停摆路径（贴墙设计内）传
    `allow_near_still=true`；墙探预跳与圆盘路径传 false——真实跳跃必须过速度门
    （F8 保证直线助跑速度门可达，不破坏停摆语义）
  - `_jump_v <= 0.4`（原地跳）恒放行不变

### F10 锚点可达性预检（RC-3b 根治）

- `_enter_jump` 计算锚点后：`锚点面高 − 脚高 > STEP_MAX(0.62) + 0.1` → 锚点步行
  不可达 → 从当前位置重寻路一次（复用 `_replan_from_current`，尊重 attempt 级
  重寻路次数上限）；重寻路仍含不可达跳跃 → `_end_attempt("jump_missed",
  "锚点不可达（面高差 %.2fm）")` 诚实失败
- 预期：23s 压墙 → 立即重寻路（新路径含 Crate_WS 上箱链接时正常执行）或立即失败
- 注意：不做「锚点低于脚」的对称检查——下行走下边缘是设计内（TO_ANCHOR 坠落
  重试已兜底）

### F11 RUNUP 压墙恢复（RC-4 根治）

- `_runup_tick` 接入 `_wall_press_detect`（与 TO_ANCHOR 同口径，传实际施加指令）；
  压墙 0.5s 锁存 `_wall_follow` 后**不走滑墙**，直接 `_recover_runup()`（传送回
  锚点重跑，≤3 次后按当前状态起跳——既有有界语义）
- F8 直线化后轨道漂移楔墙消失，剩余场景=跑道上有障碍 → recover 有界化
- 预期：助跑卡死 2 面 → 有界重试 → 或成功或诚实失败

### F12 垂直链接专用模式（Crate_WN/WS/ES/EN，RC-2 的子集）

- `_enter_jump` 检测：snap 后 from/to 水平距 < 0.05 → `_vertical_jump = true`
  - `_jump_v = pick_jump_speed(delta_h, 0)`（既有口径，0.9m 箱 ≈2.4-2.6）
  - 触发=停摆路径语义：跑向 from_point（箱体挡住）→ 贴箱停摆 → 直上跳
    （`_travel_dir` 为零向量时 `_wall_ahead` 探针天然不命中、圆盘路径由 F9 的
    「圆盘不允许近静止」排除——停摆成为唯一有效触发路径）
  - AIR 期间 `move_axis = ZERO`（零水平输入 → 无 REST 漂移 → 纯弹道落回箱顶；
    1×1 箱顶 + 胶囊 0.5 压箱侧，落点 xz 在箱矩形内）
- 已在 to_face 上 → 既有 `_jump_already_crossed` skip 逻辑覆盖（面高 ±0.3 判据）
- 预期：Crate_WN 链 6 个失败面 → 上箱 → 后续 CrateToCluster 正常执行

### F13 WALK 进展超时 + 到达需位移（RC-3a/c 根治）

- `_walk_tick` 新增途经点计时 `_wp_t`：seg 推进时清零；**8s 未推进 → 强制重寻路**
  （attempt 级重寻路次数上限 1 → **2**，`_walk_replanned` bool → int 计数）；
  重寻路仍 8s 无推进 → `stuck` 裁决（既有）
- 「假到达」防护：seg 推进需本段实际位移 ≥ 0.2m（`_seg_move_origin` 记录 seg
  起点，推进时校验）——冻结点附近途经点不再推进重置卡死计时
- 预期：EastTower 类 71s attempt → <20s 裁决；压墙振荡 23s → 8s 重寻路

## 三、影响与验证

- **TRAVERSAL_REV r7→r8**：逻辑变更 → 用户实机记录自动清空重建（铁律，预期）
- GUT：新测试文件 `test/unit/test_auto_traversal_runup.gd`（F8-F13 各 1-2 测试，
  复用既有冒烟 harness 模式）+ 既有 387 全绿
- 探针复跑：probe_v3_walk 79/79、probe_jump_edges 退出 0（布局/机制未动）
- 实机重跑：30 分钟积累新数据 → analyze_auto_traversal.py 三源对照复评
  （成功面数、stuck/jump_missed 计数、转圈时长应显著下降）

## 四、范围外（明确不做）

- no_path 数据缺口（Belt/Corner 箱链接、29 面合理不可达）→ M4
- 箱顶→簇板 zone 级执行 → M4（既有拍板）
- RimN4 类「高边坠落反向跳」：先靠 F8/F9 缓解，重跑数据复评后再定
