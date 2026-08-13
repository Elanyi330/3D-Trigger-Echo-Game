# 账本：M2 战斗手感三项修复（2026-08-13）

> 设计：`docs/superpowers/specs/2026-08-13-m2-melee-grenade-fixes-design.md`（用户批准）
> 计划：`docs/superpowers/plans/2026-08-13-m2-melee-grenade-fixes.md`
> 分支 feat/m1-assets（单目录）；基线 GUT 276/276（25 脚本）。

## 任务状态

| 任务 | 内容 | 实现者 | 审查 | 状态 |
|------|------|--------|------|------|
| T1 | .tres 资源字段（机械） | impl-t1（haiku，a1ee0c7e） | review-t1 ✅✅ | **完成**（276/276；偏差声明：knife.tres 锚点实际值 0.5 为生产正确值） |
| T2 | MeleeController 三项 | impl-t2（a0a7080e） | review-t2 ✅✅（e87b3c8 收敛） | **完成**（281 全绿）。审查 Minor×3 裁决记录：①下蹲姿态不对称（EYE_HEIGHT 固定→下蹲脚部−0.46m 偏移，边缘姿态组合才触发，容差内可接受）②新字段零值默认 fail-safe ③2 条 GUT warning 为存量非本任务引入 |
| T3 | Grenade LOS | impl-t3（a99de0ae） | review-t3 ✅✅（1242452） | **完成**（287 全绿；Minor×4 记录）。审查发现既有 RNG flake：test_wave_spawner::test_wave_combo_variety（P≈1/243）→ 归入 T5 确定性化 |
| T4 | 投掷手感 | impl-t4（后台运行中） | - | 进行中 |
| T5 | 回归+文档同步 | 控制器 | - | 未开始 |
| 终审 | 全分支 | - | - | 未开始 |

## 决策记录

- 2026-08-13 用户拍板：M2 范围仅团战地图（占点/大图推迟）——文档已同步。
- 2026-08-13 用户批准三项优化设计；投掷手感新增需求（起自右手雷/瞄哪打哪/轨迹一致/落点清晰）。
- 设计修正：_in_cone 垂直判定为脚部-脚部（origin 眼位须减 EYE_HEIGHT 1.63）——同层直减会误判 1.63>1.5 全挡。
- LOS 语义修正：0.9 矮墙对贴地爆炸**也遮挡**（射线路径相交即挡，CS trace 语义）——设计原"0.9 不遮挡"表述有误，已按几何正确性修正。

## 教训

（待填）
