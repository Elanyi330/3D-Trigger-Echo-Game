# 账本：M2 边界隐形高墙 + 面级跳跃边四层设计（本轮 1+2+3+量化验证）

> 日期：2026-08-13（收尾跨夜至 08-14）。分支 feat/m1-assets，单目录（勿建 worktree）。
> 计划：`docs/superpowers/plans/2026-08-13-m2-boundary-walls-and-jump-edges.md`
> 用户拍板（HANDOFF 待做段）：①边界隐形高墙 ②面级跳跃边四层设计；本轮只做 ②(1)(2)(3)+量化验证，②(4) M3/M4 接口留待下一轮。

## 探索发现（设计依据，重要）

1. **真实跳跃物理 ≠ probe_jump 的 1.388**：MovementController 跳帧不减重力（满速位移一帧后才开始 vy−=g·dt）→ 离散峰值 **1.5133m @ 24 帧**（闭合式 rise(n)=n·7.54/60−19.6·n(n−1)/7200）；probe_jump 的 1.388 是其自带积分模型低估。语料逐帧实证（WestTower→WestWall_M ep13：t=0 时 vy=7.54 且已升 0.1257）。
2. **边缘抓取机制**：玩家胶囊半径 0.5（Player/MovementController.tscn，AI 是 0.31）——脚只需 ≥ 顶面−0.5，底球滚上边缘+去穿透/floor_snap(0.5) 抬升。翼墙→门梁（Δh1.9）轨迹实证：身体沿门梁西棱滑升（位置被挡、y 续升、vx 保持 5.45）。
3. **4 条疑似数据错误链接**（本轮报告不修，待用户拍板）：
   - PavToSpur_WS/ES：from 端点开阔地（摊阁 x 范围外），水平跨距 16.8m ≈ 物理上限 5 倍——镜像笔误。
   - ClusterToRim_WS/ES：from 端点在 2026-08-11 簇板迁离坡道带后悬空（z=±4.9 距任何 2.2m 面 >5m）——端点未随迁移更新。
   - 白名单注释"修复待用户拍板；修复后此白名单应收敛"。
4. **jump_links 实为 56 条**（HANDOFF 旧计数 54 已修正）；52 条有效 + 4 白名单。
5. **链接端点级 vs 面级差异**（点链接→面级升级的价值实证）：WingToLintel 端点 6.5m 不可执行（v_req 13.0），人类实际起跳在翼墙内端（d≈1.6m，v_req 3.16）✓；RimToWing 端点 5.608m infeasible，人类 n=3 从 rim 最近缘跳 3.5m ✓（zone 级 4.44 tight）。

## 任务链（SDD：每任务实现者+审查者，模型：机械=haiku/集成=sonnet/审查=opus）

| 任务 | 内容 | 实现者 | 审查 | 结果 |
|------|------|--------|------|------|
| T1 | 边界隐形高墙（map_greybox `_build_boundary_walls()` + 6 测试） | haiku DONE_WITH_CONCERNS | APPROVE_WITH_NOTES | 4 面 12m 隐形墙，内缘贴外缘 x=±31/z=±30（用户口径 z=±30.5=1m 厚墙中心）、角部互叠零缝隙；static_bodies 196（brief 197 错——BellDecor 是 decor→Node3D，实现者双证据修正）；哈希钉死 f935ccd7c32c7cd4bdd47e8b9f6ef858b8f4220bd3f85606e810743eeb6bcef0=当前布局哈希（与语料 manifest 一致 ✓） |
| T2 | jump_edges.gd 面级数据结构（faces 160/link_face_edges 56/face_edge_groups 52）+ 6 测试 | sonnet DONE_WITH_CONCERNS→裁决轮→DONE | APPROVE | 实现者发现 2 条新白名单链接（ClusterToRim_WS/ES）；控制器裁决：白名单扩 4 条+zone 断言 ≥0.2；56 条链接（54 旧计数修正）；0.001 归一化防 float32 ULP 重名（最小 top_y 差 0.3 不误并）；WestTower/EastTower 自环组（standable 塔面含坡道顶端点，合规） |
| T3 | jump_solver.gd（class_name JumpSolver，闭合式离散物理）+ 6 测试 81 断言 | sonnet DONE_WITH_CONCERNS | APPROVE | 实现者纠正 5 处 brief 手算锚点错误（rise47/48、f_max50、v_hi30、margin 阈值 tight），审查者 python 独立重算全部属实——brief 错实现对 |
| T4 | export_jump_edges.gd + build_jump_dataset.py + jump_edges_dataset.json（262 非 fail episode 校准） | sonnet DONE_WITH_CONCERNS→裁决轮→DONE | APPROVE | 裁决：①edges 自包含双区 takeoff/landing_zone ②链式 skill 改多数判据 chain_n*2≥n（WestSpurS 1/3 转 verified）③calibrated 增 peak_rise_p50。语料组 121、匹配 28、unlinked 93（未来补链候选） |
| T5 | probe_jump_edges.gd 量化验证报告（三门禁+报告表） | sonnet DONE | APPROVE_WITH_NOTES | 门禁 A 布局哈希/B 链接覆盖 52+白名单 4/C 求解器交叉校验（verdict 逐字+v_req 1%）；报告：52 边、5 skill、10 infeasible 链接、4 suspicious_link、24 physics_only；负向验证 exit 1 ✓ |

**关键产物**：
- `Levels/M2_TDM/jump_edges.gd`：面表 160 + 56 链接归属 + 52 面级边组（zone 兜底 = 链接端点 ±0.5 钳面矩形）
- `Levels/M2_TDM/jump_solver.gd`：确定性求解器（常量 G19.6/V7.54/DT1/60/CAP6.35/CATCH_BAND0.5；rise_at/catch_window/required_speed/feasibility/landable_zone）
- `Levels/M2_TDM/jump_edges_dataset.json`：M4 消费数据集（meta.map_hash 随附铁律 ✓；52 边×11 键、56 链接审计、93 未链接人类边；校准 peak_rise_p50=0.849/p99=1.668（超理论 1.513=真实对局坡面滑升/台阶链效应）/catch_depth_p90=0.106（带 0.5 内））
- `tools/probe_jump_edges.gd`：量化验证门禁工具（以后每轮布局/链接变更必跑）

**流程记录**：T2/T4 各 1 轮裁决（控制器不亲自改码，裁决发回原实现者）；T3 实现者以公式为准纠正控制器 brief 手算错误（5 处，全部独立复算确认）；auto-push hook 中途提交了 T4 第一版数据集（HEAD 3113 行），T6 提交工作区终版（复跑管线逐字节一致验证）。

## 验证基线（T6 全量复跑 + 终审 APPROVE_WITH_NOTES）

- GUT：**364/364**（基线 339 + T1 6 + T2 6 + T3 6 + **test_player_life 复活 7**）
- probe_v3_walk 79/79（边界墙无副作用实证）、probe_navmesh 全过、probe_jump_edges 退出 0（门禁 A/B/C）、sightlines 硬门控 0 对、angles 全通、timing 4.93s ✓、theme 193 实体 41 抽查 0 失败、scan_gaps 0 窄缝
- 布局不变量：193 实体、布局哈希 f935ccd7… 不变（跳跃记录不重置，577 episode 保留）
- **验证阶段两个诚实发现（已修复+记录）**：
  1. **test_player_life.gd 自 TDM 轮起因解析错误被 GUT 静默跳过**（`var life: Node` 上 `:= life.health` 推断失败 → 整个脚本不加载、退出码仍 0——"全绿 ≠ 全跑"）。本轮修复（`life: PlayerLife` ×7 + dummy Node→Node3D 满足 _do_respawn 写 global_position），复活 7 测试，**此前各轮 339/345/351/357 计数均不含这 7 个测试**（诚实口径）。终审 Major 建议：M3/M4 轮落地"GUT 日志解析/加载错误硬门禁"。
  2. **外环视线基线 178→180**：HANDOFF 旧记 178 系文档过时——A/B 实测（临时换旧版 map_greybox 跑同探针）**旧灰盒同样 180 对**，边界墙对视线世界零影响，已修正文档。
- 终审（opus）：接口链四重验证（代码比对+门禁交叉校验+独立数学复算+管线逐字节复现）全 PASS；数据集与管线产物 BYTE-IDENTICAL；改动文件 23 个全部在范围内（无 map_layout_v3.gd/Player/Weapons 越界）。Minor 同步项已处理（jump_edges 头注释 2→4 条、HANDOFF 357→364）。遗留 Minor：白名单三处维护（双门禁兜底）、M4 必须消费 dist_zone 而非面距 dist、数据集是语料快照（M4 前重跑管线）。

## 遗留（待用户拍板）

1. **4 条疑似错误链接修复方案**（建议下轮 F 任务）：PavToSpur_WS/ES 删除或改为真旋转对；ClusterToRim_WS/ES from 端点改至簇板实际位置（如 (±17.5, 2.2, ±10.8)）；修复后 T2 白名单收敛、probe_jump_edges 重跑。
2. **链接端点可执行性**：WingToLintel/TowerToRim/RimToWing 端点级 infeasible 但 zone/人类级可行——M4 消费面级 zone 而非链接端点（数据集双区已备）；是否调整链接端点坐标待用户定。
3. ②(4) M3/M4 接口设计（寻路经过边→from_zone 边缘→求解器参数+语料采样执行跳跃）——下一轮。
