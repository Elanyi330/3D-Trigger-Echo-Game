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
| T4 | 投掷手感 | impl-t4（aa12bf9f） | review-t4 ✅✅（af250ca+12c81fa） | **完成**（289 全绿×2；测试期望算术修正×3 授权；Minor×2 注释过期归入 T5a） |
| T5a | wave flake 种子 + 注释清理 | impl-t5a（haiku） | 终审覆盖 | **完成**（seed 20260813，10/10 连跑绿） |
| T5 | 回归+文档同步 | 控制器 | 终审覆盖 | **完成**（289/289 新鲜验证 + L_M2 冒烟 180 帧 + 文档同步） |
| 终审 | 全分支 | final-review（opus） | - | **APPROVE_WITH_NOTES**（9 优势/0 Critical/0 Major/5 Minor；收尾：账本落定+第 4 处过期注释补清+设计表头措辞） |

## 决策记录

- 2026-08-13 用户拍板：M2 范围仅团战地图（占点/大图推迟）——文档已同步。
- 2026-08-13 用户批准三项优化设计；投掷手感新增需求（起自右手雷/瞄哪打哪/轨迹一致/落点清晰）。
- 设计修正：_in_cone 垂直判定为脚部-脚部（origin 眼位须减 EYE_HEIGHT 1.63）——同层直减会误判 1.63>1.5 全挡。
- LOS 语义修正：0.9 矮墙对贴地爆炸**也遮挡**（射线路径相交即挡，CS trace 语义）——设计原"0.9 不遮挡"表述有误，已按几何正确性修正。
- T4 测试期望算术修正×3（38 点/`−g·dt²`/容差 1.0）：简报连续解析式误用于离散半隐式欧拉。
- test_integration flaky 裁决：freeze+高空传送确定性化（不放松断言强度）。
- T5a：wave_spawner RNG flake 以 seed(20260813) 确定性化。

## 教训

1. **测试期望必须按离散公式逐点推导**：半隐式欧拉的落地点数与连续解析解差一个 ½·g·dt²·i(i+1) 项——简报写测试期望时用连续公式导致 39 vs 38 点、−½g·dt² vs −g·dt² 两处错。
2. **新增遮挡/判定机制会暴露既有测试对随机路径的隐含依赖**：LOS 上线后 test_integration 随机落点 flaky——机制变更时排查既有测试的随机性假设。
3. **RNG 断言必须 seed 确定性化**（P≈1/243 的 flake 也迟早会红）。
4. **注释与语义变更同步清理**：改值/改语义时全面 grep 相邻注释（本轮漏 1 处，终审补清）。
