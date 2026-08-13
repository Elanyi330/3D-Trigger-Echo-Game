# 账本：M2 战斗修复轮 2（2026-08-13）

> 设计：`docs/superpowers/specs/2026-08-13-m2-combat-fixes-round2-design.md`（用户批准；衰减公式拍板 A 线性截断）
> 计划：`docs/superpowers/plans/2026-08-13-m2-combat-fixes-round2.md`
> 基线：GUT 289/289（26 脚本）。来源：用户实机 playtest 反馈三条。

## 任务状态

| 任务 | 内容 | 实现者 | 审查 | 状态 |
|------|------|--------|------|------|
| R1 | 资源字段（机械） | impl-r1（haiku） | review-r1 ✅✅（2e61731） | **完成**（289 全绿） |
| R2 | 换弹锁切枪 | impl-r2（a86273b8） | review-r2 ✅✅（9cb0831） | **完成**（289 全绿；测试 lambda 按值捕获偏差已批准改数组计数；观察项：interrupt_reload 分支成纯防御） |
| R3 | CCD + 厚度衰减 | impl-r3（a9a5d735） | review-r3 ✅✅（5bb621e） | **完成**（290 全绿；:= 显式类型偏差批准；Minor-1 头注释 R4a 补清） |
| R4 | 回归+文档+终审 | 控制器 | final-review-r2（opus）APPROVE_WITH_NOTES | **完成**（290/290 新鲜验证+冒烟 180 帧+文档同步；Minor×4：①设计表 0.9→×5/6 已修 ②3m 全挡边界测试待补——下轮跟进 ③计划采样标注（教训 3）④README 276 待下个里程碑刷新） |

## 决策记录

- 2026-08-13 用户 playtest 反馈：①换弹中切枪动画串扰（拍板：换弹中**禁止切枪**，非 CS 切枪取消）②平台向下投雷概率穿地（根因：高速隧穿，CCD 修复）③墙挡雷太死（拍板：墙体按厚度精密衰减，越厚挡越多）。
- 2026-08-13 衰减公式拍板：**A 线性截断** mult=clamp(1−T/3.0,0,1)（AskUserQuestion 用户选择；B 指数/C 平方根未选）。
- 采样参数：步长 0.25m、半步偏移起点、终点=胸口参考点；exclude 目标 RID 防自身计入厚度。

## 教训

1. **GDScript `:=` 对 `Node` 类型无法推断属性**：简报代码里 `target: Node` 后的 `target.global_position` 用 `:=` 必炸（两轮简报连犯两次）——写简报代码时，凡入参为基类型（Node/Variant）的派生表达式一律显式类型声明。
2. **GDScript lambda 按值捕获局部原始值**：`var n := 0` + lambda `n += 1` 不更新外部变量——测试计数用 `Array[int]` + append + size()（test_weapon_manager.gd 既有约定）。
3. **采样几何期望必须按代码的半步方案验算**：计划文本用 1 基序号/整数 k 标注与实现 k=0.5+1.0n 不一致（T 值与期望仍吻合）——文档标注与代码采样方案要对齐。
