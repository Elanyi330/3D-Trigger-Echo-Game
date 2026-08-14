# 账本：自动跳跃遍历器（AutoTraversal）

> 日期：2026-08-14。分支 feat/m1-assets，单目录（勿建 worktree）。
> 设计：docs/superpowers/specs/2026-08-14-auto-traversal-design.md；计划：docs/superpowers/plans/2026-08-14-auto-traversal.md。
> 用户需求：自动操纵第一人称角色在全图平台间自动移动跳跃（用户零操作观看），成功+失败数据全部记录供未来 AI 参考；未来 AI 移动底层 = 把玩家角色运动逻辑搬到队友/敌人身上。
> **用户拍板（4 项）**：目标=全部 160 面（22 无导航面记 no_path）；失败恢复=传送归位（记入 attempt）；记录=独立 user://auto_traversal/（自动期间挂起 JumpRecorder）；**运行期间所有操作按钮锁定 + Esc 直接退出程序 + 单次 30 分钟上限（到点暂停显示"按 R 重启测试流程"）+ 训练期间临时取消一局 8 分钟局时**。

## 任务链（SDD）

| 任务 | 内容 | 实现者 | 审查 | 结果 |
|------|------|--------|------|------|
| T1 | MovementCommand 命令接口 + MovementController 接管钩子（物理零改动、MOVEMENT_REV 钉死）+ 4 测试 | haiku DONE_WITH_CONCERNS | APPROVE | 实现者纠正 brief 2 处错误：①命令轴映射（brief 字面直接赋值会让"前进"指令横移——控制器内部轴 x=前后/y=左右，实证+数学双证据，改 Vector2(cmd.y, cmd.x)）②刹车滑行阈值 0.2m 物理不可达（几何级数上限 0.635m，改 0.7m 判别力不变） |
| T2 | auto_traversal.gd 纯逻辑（classify_segments/pick_jump_speed/trigger_distance/landing_verdict）+ 7 测试 | sonnet DONE | APPROVE | 锚点与 JumpSolver 公式逐项一致（brief 表 5.77 系 3 位截断，实跑 5.775） |
| T4 | AutoTraversalRecord 记录器（manifest 哈希重置/续跑、summary 增量、attempts head+帧行 16 键、target_faces）+ 7 测试 | sonnet DONE | APPROVE | JSON int→float 往返按 engine 语义；created_at 续跑保留（有意改进） |
| T3 | 状态机+执行循环（贪心 160 面/PLAN 分类/WALK/JUMP 引擎/重试 3/安全网/传送）+ 冒烟测试 | sonnet 首轮 API 超限中断→重派→DONE_WITH_CONCERNS→裁决轮→Minor 修复轮 | APPROVE_WITH_NOTES | 首轮实现者输出超 32k token 被终止（工作树残留 678 行已 git checkout 清理重派+分块写指令）；**裁决轮**：①目标点回退（面中心→四角→边中点 8 偏点，AltarPlatform 面心是导航孤岛实测走达）②move_axis 幅值控速（v/cap 缩放=速度乘数，direction 未归一化实证）③30 分钟上限+restart_session+aborted 落盘+timeout_paused ④六项几何对策（高度感知到达/路径简化/原地转向+节流/墙探预跳/下坠行走/已越豁口免跳）；Minor 修复：no_path 的 plan 字段旧数据 → 空 plan（+UmbrellaN 防回归断言）。冒烟 2 测试（3 跳跃目标全 success + 超时暂停重启） |
| T5 | L_M2 装配+HUD+输入全锁+Esc 退出+局时取消+R 重启（+169 行增补式） | sonnet DONE_WITH_CONCERNS | APPROVE_WITH_NOTES | 实现者纠正 brief 2 处机制错误（探针实证）：①_input 事件**子节点先于根节点**收到——set_input_as_handled 拦不住 Head 鼠标视角 → Head 同走 process_mode=DISABLED 杠杆 ②command_override 生命周期（setup 永久接管会废掉正常游戏输入）→ 装配后置空/启动 re-setup/完成置空（与 T1 释放契约一致）；③brief 锁吞 R 矛盾 → paused_timeout 下 R 放行唯一自洽读法。独立冒烟 20/20 检查全过 |
| T6 | tools/analyze_auto_traversal.py（三源对照报告+auto_verification.json） | sonnet DONE | APPROVE_WITH_NOTES | 1 Minor isinstance 守卫（实际语料恒 dict，跳过不修） |

**关键产物**：
- `Player/MovementCommand.gd` + `MovementController.command_override`——**AI 驱动玩家同款控制器的唯一接口**（move_axis x=左右/y=前后、jump_pressed 边沿消费、crouch 预留）
- `Levels/M2_TDM/auto_traversal.gd`——状态机+执行循环（session_state idle/active/paused_timeout/done；SESSION_TIMEOUT 1800；贪心+8 偏点回退；跳跃引擎=求解器参数+语料 p50 钳带+幅值控速助跑+触发距离+着陆判定）
- `Levels/M2_TDM/auto_traversal_record.gd`——独立记录器（哈希随附铁律/跨会话续跑/aborted 收尾）
- `Levels/M2_TDM/L_M2.gd` 装配——P 启动、全锁（事件消费+WeaponManager/Crouch/Head 挂起）、Esc 直接退出、8 分钟局时冻结、R 重启（paused_timeout）、HUD 四行（本轮 X/剩余 Y · 累计成功 S 失败 F）
- `tools/analyze_auto_traversal.py`——三源对照（自动实测 vs 求解器 vs 人类语料）+ 10 条端点级 infeasible 链接的面级执行实测口径检查

## 验证基线（T7 全量）

- GUT **384/384**（364 基线 + T1 4 + T2 7 + T4 7 + T3 冒烟 2）
- probe_v3_walk 79/79、probe_navmesh 全过、probe_jump_edges 退出 0（布局/机制未动，复跑确认）
- 深度集成（真实 L_M2 场景 headless 注入 P 跑 150s）：**36 成功 / 63 失败 / 80/141 面已处理，全程 active 无崩溃**（成功面含摊阁/角场/望楼/塔坡道各级；141 = 160 − 用户此前已处理 19 面——**跨会话续跑在真实场景实证生效**）；验证产物已与用户训练数据分离（跑前备份跑后还原，用户记录回到 19/160 自己状态）。
- **用户实机记录核实**：用户已实机按 P 跑过（19 attempt @18:37 全 no_path=出生点附近 22 个无导航面被贪心先处理——**设计预期行为非 bug**；失败数据=产出；Esc 退出后 summary 续跑机制生效，下次启动跳过这 19 面）

## 遗留 / 待议

1. **开局 22 连败观感**：贪心最近未访问使出生点旁的 22 个无导航面（营墙等）先被处理（~30s 快速 no_path 后进入真实遍历）。设计如此（确定性+失败数据）；若想改善演示观感可改为"无导航面批量后置"（另行拍板）。
2. RESULT 态按 P 的边界（结算冻结玩家→stuck 循环）未处理——实际不可达（训练期间局时冻结+玩家不射击），低风险。
3. 输入锁定/UI 手感 headless 不可验——实机验收归用户。
4. AutoTraversal 完成后（done）与 M4 的关系：跳跃引擎（参数选择/助跑/触发/判定）即 ②(4) M3/M4 接口的执行原型；auto_verification.json 可并入 jump_edges_dataset.json。
