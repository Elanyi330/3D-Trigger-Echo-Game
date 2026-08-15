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

## F5-F7 执行层优化轮（2026-08-15，用户"失败率非常高"反馈驱动）

**失败样本分析**（r4 时代 160 attempts 67/93）：no_path 剩余 ~30 全为真不可达面（正确数据）；主导失败=**卡死 28**（压墙干顶机制：位置冻结/速度非零/命令前进——样本逐帧实证）+ **跳空 16**（箱→面板 M4 类 + 链中跳）。
**F5**：行走滑墙（实现者实证修正：速度方向不可用→改"到目标方向投影到墙面+固定侧向兜底"）+ 行走坠落重规划；8 分钟数据验证 stuck 28→2（降 93%）。
**F6**：TO_ANCHOR 滑墙+坠落→重试、阈值 0.5→0.2；GateN_WingE 转 jump_missed（机制生效）；RimW_B 定位坡面基座棱角（is_on_wall=false 不触发——单面残余，机制文档化）。
**F7（多路 finder 共识 Critical）**：press→follow 循环饿死卡死检测（锁存不清 press_t+超时重置卡死 → 冻结楔角无限循环挂到会话超时）——锁存清 press/超时退出喂卡死计时/`_reset_wall_state` 五调用点/TO_ANCHOR 实际指令语义/坠落检查前置+垂直退出/`_to_anchor_max_feet` 假阳性防护/r7。数据验证：stuck 3/105、max attempt 70.5s 无挂死、滑墙触发 87→22（循环假触发消除）。
**终审 APPROVE_WITH_NOTES**：3 Minor（`_skip_jump`/`restart_session` 补 `_reset_wall_state`、注释精度）记下轮。

## F8-F13 执行层修复轮 + 塔/祭坛坡道烘焙替身（2026-08-16 收官，用户拍板）

**触发**：用户反馈「跳跃前莫名其妙转圈」+ 失败/卡顿分析 → 119 attempt 帧数据根因分析（RC-1 转圈=最小转弯圆 R_min=v/ω 实测吻合 v=5.45→r=1.07-1.64m；RC-2 漂移跳=±53° 锥+近静止放行 45° 失跳；RC-3 卡顿=轨道白转 30-43s/不可达锚点压墙 23s/楔死冻结 21s；RC-4 助跑楔墙无恢复）。设计：docs/superpowers/specs/2026-08-15-auto-traversal-runup-fixes-design.md；计划：docs/superpowers/plans/2026-08-15-auto-traversal-runup-fixes.md。

**T-nav/T-nav-ext（用户拍板方案 A 烘焙替身）**：四坡道台阶区 navmesh 数据缺陷根治——台阶整高盒经「窄边放大 1.2」烘焙互相重叠（0.62/0.75 深 → 1.2 深，重叠 0.58/0.45m）埋掉台阶顶面 → 烘焙器产出斜跨 5m 悬空多边形（poly 637 顶点 y 0.4/1.4/0.4 实锤；西/东塔+两祭坛坡道四区同族）。修复=烘焙几何用真斜坡替身（游戏几何/碰撞/视觉/布局哈希全部不动，跳跃记录不重置）+ probe_navmesh ④ 梯度门禁（四坡道 40 列 80 判定，坡脚缝+槽中点×低/高双查）+ 祭坛坡道侧板（垂直无顶四边形封 phantom 侧入口；塔坡道加板会回退寻路径形故不加）。navmesh 1087→1113 多边形。**关键发现：旧坏 navmesh 逼路径绕行 rim 墙链使历史冒烟能过（运气路径）——修复后坡道成直路，暴露 walker 执行层新病理链**。

**T1（F8+F9 + 修复链 1-9）**：RUNUP 直线化（转向门 0.3rad）+ 触发门控收紧（±25° 锥 cos0.9/近静止按路径声明：墙探 false/停摆 true/圆盘 false）+ optimize=false 走廊忠实路径（optimize 拉直切角穿墙是压墙根因）+ 滑墙可达性守卫（>0.72 面高差 replan）+ 滑墙手性锁存（每 episode 锁存，R1 M1 修复）+ 可攀面滑墙不介入（(0,0.62] 压入交 step-up）+ 踢面正压转向（碰撞法向朝玩家侧——pos−cn 恒在墙内）+ 可攀点前瞻转向（窗口前移到地面段：「当前可攀→视下一；当前水平且下一可攀→视再下一」）。WestTowerBox 冒烟 90s 挂死 → 6.6s 逐级 step-up success（踢面接触点离西缘 0.15m→1.35m）。

**T2（F11+F12）**：RUNUP 压墙 0.5s → recover 回锚点（停摆先行不被抢）；垂直链接模式（<0.05 水平距→停摆唯一触发+空中零输入）落地但**当前 navmesh 恒惰性**（snap 水平距实测最小 0.732——RC-2 已被 F8/F9+新 navmesh 根治，F12 为防御层，测试 9 惰性锚守护未来重烘焙回归）。测试 10 导航竞态加固（R2 REJECT：重试路径从不真驱动——第二轮 summary 继承使 _build_queue 跳过 → 清临时目录修复，审查者探针实证）。

**T3（F10+F-degen）**：锚点可达性预检（面高差 >0.72 → 重寻路一次 → 诚实失败「锚点不可达」；白盒锚测试 12——活体路径上惰性：原 23s 样本机制已被 fix 4 守卫拦截）；**F-degen 退化跑道圆盘近静止放行**——锚点 snap 坍缩到侵蚀导航岛（1m 箱顶锚点≈起跳点 0.02-0.19m）→ F8 转向门对亚 0.2m 目标永不收敛 → hspeed=0 被近静止拒放 → 8s recover 死循环（箱顶冻结 32.07s 仅靠 recover>3 强制跳有界）→ 放行后 0.53s 有界（同结果快 ~30 倍）。

**T4（F13+rev r8）**：WALK 途经点 8s 进展超时（无进展→重寻路→耗尽 stuck「途经点 8s 无进展」）+ 到达推进计时重置门控位移 ≥0.2m（偏差 1：门控移到计时重置而非推进条件——直击设计文档「假到达清卡死计时」本体，正常轨迹零扰动：test 11 frames=579/test 13 frame_count=1933 与 T3 实测全等复原）+ 重寻路计数化 MAX_REPLANS=2（原一次性）。TRAVERSAL_REV r7→r8（铁律：实机记录自动清空重建）。

**审查链**：R-nav APPROVE / R1 APPROVE_WITH_NOTES（M1 Major 锁存生命周期已修+5 Minor）/ R2 REJECT（测试 10 重试空转 Major 已修+3 Minor）/ R3 APPROVE（3 Minor 记录）/ R4 APPROVE（3 Minor 记录）。

**最终验证（2026-08-16）**：GUT **403/403**（45 scripts/35160 asserts）；probe_navmesh ①-④ 全过（四坡道梯度门禁）；probe_v3_walk **79/79**；probe_jump_edges 全过；布局哈希不变（跳跃记录不重置）。

**遗留（记下轮）**：①R4 Minor 1——非超时重寻路成功路径未重置 _wp_t（一行级；冗余超时重寻路最坏多烧一次计数，有界）②测试 13 的 Crate_WS 上箱 4 次起跳+压墙 5s（~13s，M4 链执行范畴）③单目标 spawn→WestTowerBox 坡道西立面楔死（navmesh 替身坡面侧面可穿越 vs 物理阶梯封死，数据级怪癖，F13 有界兜底）④坡脚残余悬空桥面 ≤0.35（④ 门禁容差内、walker 到达门 0.3 边界）⑤RimN4 类高边坠落反向跳（重跑数据复评）⑥no_path 数据缺口（Belt/Corner 箱链接）留 M4。

**用户实机验证指引**：TRAVERSAL_REV r8 → 实机启动自动清空重建遍历记录（铁律预期）；P 启动重跑 30 分钟 → `python3 tools/analyze_auto_traversal.py` 三源对照——预期 stuck 类大幅减少、attempt 时长压缩、转圈时长显著下降（原 30-43s 白转 → 秒级直线助跑）。
