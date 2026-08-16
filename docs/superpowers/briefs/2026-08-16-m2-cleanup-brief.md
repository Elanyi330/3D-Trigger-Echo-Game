# 任务简报 C1：M2 收官清理（遍历器退役 + 记录 3000 上限）

> 项目：Trigger Echo。分支 feat/m1-assets，单目录 `/Users/elanyi/Projects/Trigger-Echo`。
> 用户拍板（2026-08-16）：①M2 收官；②测试性组件精简——**AI 托管自动遍历功能去除**；
> ③玩家操作记录保留 + **至多 3000 条上限**（继续游玩持续记录，FIFO 淘汰最旧）；
> ④文档同步。数据基础（jump_edges/jump_solver/jump_edges_dataset/面级分析）全部保留。

## 任务范围

**删除（文件级）**：
- `Levels/M2_TDM/auto_traversal.gd`（+.uid）
- `Levels/M2_TDM/auto_traversal_record.gd`（+.uid）
- `test/unit/test_auto_traversal_plan.gd`（+.uid）
- `test/unit/test_auto_traversal_record.gd`（+.uid）
- `test/unit/test_auto_traversal_runup.gd`（+.uid）
- `test/unit/test_auto_smoke.gd`（+.uid）
- `tools/analyze_auto_traversal.py`

**L_M2.gd 清理**（逐项）：
- `_autopilot`/`_auto_record` 声明、`AutoTraversal.new()`/`AutoTraversalRecord.new()` 创建、
  `setup` 调用、`timeout_paused` 信号连接与 `_on_auto_timeout` 回调
- `_start_auto_traversal()` 函数整体
- `_input` 中的遍历输入锁块（`_autopilot.active or paused_timeout` 分支）与 KEY_P 分支、
  KEY_R 的「paused_timeout 重启」分支（保留 KEY_R 的结算后重开比赛分支）
- 遍历 HUD：`_auto_hint_label`（"Esc 退出程序" 提示标签）创建与引用
- 遍历局时冻结逻辑（`_match.process_mode` 相关）
- `command_override` 的 setup/teardown 行（装配后置空、启动 re-setup、完成置空）
- **保留**：Esc=退出程序（普通游玩也适用，最简单语义）；KEY_K 自杀测试键（M3 敌人攻击
  玩家前仍需死亡/复活流程测试——注释更新为「M3 开发期保留，M6 去除」）
- **保留**：`Player/MovementCommand.gd` + `MovementController.command_override` 接口 +
  `test_auto_command.gd` 测试（**M3 AI 驱动 bot 移动的输入抽象基础**，与遍历器解耦独立）
- 删除后 L_M2.gd 不得有 `AutoTraversal` 残留引用（grep 验证）

**jump_recorder.gd 3000 上限**（TDD）：
1. `const EPISODE_CAP := 3000`（注释：用户 2026-08-16 拍板——语料上限，FIFO 淘汰最旧，
   继续游玩持续记录；corpus 有界保证数据集重建时间可控）
2. 语义：每次新 episode 写盘后，若 episodes 目录文件数 > EPISODE_CAP → 按 episode_id
   升序删除最旧文件直至 ≤ EPISODE_CAP（manifest.episode_count 继续递增=唯一 ID 序列，
   文件数封顶；setup 时存量 ≤3000 不裁剪，仅运行时超限淘汰）
3. 测试（RED 先行）：jump_recorder 既有测试文件追加 `test_episode_cap_fifo`——注入小
   cap（如 5）：记录 7 条 → 目录剩 5 文件、ep_id 1/2 被删、ep_id 7 存在、manifest
   episode_count==7；再记录 1 条 → ep_id 3 被删、ep_id 8 存在（FIFO 语义逐次验证）
   （cap 可注入口径：读测试需临时构造——若 EPISODE_CAP 为 const 不可注入，改为
   `var _episode_cap := EPISODE_CAP` 实例字段 + 测试直写，注释说明注入理由）

**文档机械同步**：
- `docs/PROGRESS.md`：M2 收官总结（见下节要点）+ M3 规划中
- `docs/FEATURES.md`：移除 AutoTraversal 条目；跳跃记录条目补 3000 上限说明
- `docs/README.md`（若存在且提及遍历/记录，同步）
- `docs/HANDOFF.md`：遍历相关段落改「已退役（2026-08-16 用户拍板：数据基础已足，
  M3 运行时 AI 移动不走遍历范式）→ 记录 3000 上限 + 面级分析报告入口」；
  运行章节删 P 键说明

**M2 收官总结要点**（PROGRESS.md 用，事实核对后写）：M2 = 小图 v3 回声祭坛（布局/手感
修复轮/战斗修复两轮/小地图/模块配色/TDM 框架/波次刷怪）+ navmesh 全流程（54 链接/
四坡道烘焙替身修复）+ 跳跃边四层数据 + 人类语料（706→持续，3000 上限）+ 面级分析
报告（160 面四档分级）。GUT 收官数字按删除后实际值写。

## 验证

1. 删除后全量 GUT：`godot --headless --path . -s addons/gut/gut_cmdln.gd` → 全绿
   （预期 368 既有 − 35 遍历测试 + 1 新 cap 测试 = **369**；以实跑数字为准）
2. `grep -rn "AutoTraversal\|auto_traversal" Levels/ Player/ tools/ test/` → 仅
   auto_traversal 历史文档与 analyze_faces.py 的 auto 目录只读逻辑可提及，代码零引用
3. 游戏可启动冒烟：`godot --headless --path . -s tools/probe_v3_walk.gd` 79/79 不回归
   （probe 不依赖遍历）
4. jump_training 语料目录零改动（只读验证——你的 706 条人类数据一根毛都不能少）
5. 记录上限实测：临时注入 cap 跑测试验证 FIFO（测试内）

## 报告格式

开头一行 DONE / DONE_WITH_CONCERNS / NEEDS_CONTEXT / BLOCKED + 删除/保留清单 +
RED/GREEN 证据 + 最终 GUT 数字 + 文档改动清单。
