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

## F2/F3 修复优化轮（2026-08-15，用户失败样本分析驱动）

**失败样本分析**（160 attempts / 65 成功 / 95 失败）：91 个 no_path 的"距目标距离"精确等于目标下方垂直高度差（rim 3.04=墙高+偏移、箱 0.94、高棚 3.60=棚顶 4.9−摊阁 1.2）→ 路径终点全在目标正下方 = **导航图内无链接**；用户 65 个成功面零链接依赖面 vs headless 同构建链接正常 → 根因：`L_M2._snap_nav_links` 5 帧固定等待在**实机全场景**下不足，54 链接悬空被静默丢弃（2026-08-13 历史坑复发）。

**F2**（链接注册 + 记录版本键）：map_is_active 哨兵轮询（≤60 帧）+ P 启动二次快照（`_snap_nav_links_now`）+ `TRAVERSAL_REV` 版本键接 MOVEMENT_REV 追加行（旧记录自动作废）+ test_l2_nav_link_snap（54 链接×2 端点 <0.1m 自洽）。**扩展轮**（裁决 4 项+实现者实测逼出 2 守卫）：传送 y 补偿（origin=导航点+0.515，脚面语义统一）/接收区最近点瞄准（+<1.2m 短跳守卫）/小面助跑速度门放宽 0.6v（+方向锥 ±53°）/冒烟隔离拆分；**WestClusterN_Panel 锚回退 WestClusterN_Box**（箱顶→面板跳 R_min 1.17m>1m 箱顶几何不可达——面板链执行留待 M4 zone 级）。

**F3**（多路审查 8 项）：TRAVERSAL_REV bump r3（语义变更未 bump 的洞）/`_spawn` 快照移入 start()（setup 时导航未同步的掩蔽态）/`_try_trigger` 谓词统一三路径门控（墙探 0.9v 硬编码+停摆无门的洞）/`_runup_available` 改锚点实测（面矩形测距被侵蚀失真）/传送清 jump_pressed 边沿（幽灵跳）/重试 2 后 relaxed 重算/传送偏移保守化（FEET_OFFSET−0.3=+0.615，宁浮 0.1 不嵌 0.1）/冒烟补强（link 使用断言 + test_chain_plan_two_links 双链接规划锚 + 迭代哨兵 + 哈希口径一致）。**实现者实证发现**：map_is_active 在未同步地图上返回 true 不可靠——链接需**两轮地图迭代**（iter 1 注册原始端点悬空者被弃，iter ≥2 后 snap 才入图），测试哨兵改基值相对 iter≥+2（生产侧由 P 时刻二次快照兜底 + test_l2_nav_link_snap 钉终态）。

**验证**：GUT **387/387**、冒烟 5/5（两遍确定性：5 目标 success+UmbrellaN no_path+链接使用断言+双链接规划锚+超时暂停重启+链接快照终态）、probe_v3_walk 79/79。TRAVERSAL_REV r3 → 用户实机记录自动清空重建（预期——r2 时代的 91 条错误 no_path 作废，修复后全量重测）。

**遗留（已明确）**：箱顶→簇板链（CrateToCluster 类）执行 = M4 zone 级执行范畴（规划层已锚定）；10 条端点级 infeasible 链接的面级执行实测待用户实机覆盖（analyze_auto_traversal.py 的「面级执行实测」小节）。

## F4 链接创建时序根治轮（2026-08-15，用户实机二次反馈驱动）

**用户反馈**：实机全程无多组件跳跃联动，高墙区顶部"不在目标位置"。数据核实：F2/F3 后实机 10 次"链接执行"是路径几何擦过链接端点的**分类巧合**（非真实链接执行）；链面（箱/簇板/rim/长墙/门梁/高棚）no_path 模式与修复前相同。
**决定性根因（控制器复刻实机生命周期实证）**：`_snap_nav_links` 哨兵 map_is_active 假阳性在帧 1 放行 → 同步前 closest 查询**报错返回 (0,0,0)** → 54 链接零点注册 → 首同步全部丢弃（0/54）→ **被丢弃链接永久性**：P 时刻再快照设回有效端点+触发 iter 2→3，仍 0/54 复活。
**修复**：链接节点改**地图同步后创建**（`_create_nav_links_after_sync`：迭代哨兵基值相对 +2——navmesh 第二迭代才可查询，实现者实测 iter 1 仍返 (0,0,0)；`_query_nav_point` 瞬时失败重试 ≤10 帧——GUT 复现率 1/3 的再同步窗口 flake）+ 删除旧快照函数 + TRAVERSAL_REV r4。
**验证**：probe_lifecycle2 **存活 54/54、死亡 0**、spawn→箱顶路径到达；冒烟 5/5×10 遍确定性；GUT 387/387；walk 79/79；navmesh 全过。审查 APPROVE_WITH_NOTES（2 Minor 文案/注释）。
**教训（重要）**：①NavigationLink3D **被丢弃即永久**——必须首注册有效端点，事后快照无法复活；②map_is_active 假阳性不可作哨兵；③navmesh 区域解析需两轮迭代；④closest 查询在迭代达标后仍有瞬时失败窗口（需重试）。
