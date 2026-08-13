# 账本：M2 小地图（圆形 2D 雷达，2026-08-13）

> 设计：`docs/superpowers/specs/2026-08-13-m2-minimap-design.md`（用户拍板：A 数据驱动蓝图投影；半径 12m；12m 内敌人全显）
> 计划：`docs/superpowers/plans/2026-08-13-m2-minimap.md`
> 基线：GUT 290/290（26 脚本）。

## 任务状态

| 任务 | 内容 | 实现者 | 审查 | 状态 |
|------|------|--------|------|------|
| MM1 | MinimapCore 投影数学 | impl-mm1（a93dd12c） | review-mm1 ✅✅（e78e22c） | **完成**（299 全绿；偏差×2 批准：typed 迭代编译修复/测试墙 (40,1,4) 几何修正；数学值独立验算全吻合） |
| MM2 | Minimap 渲染 + L_M2 装配 | impl-mm2（a3e0131d） | review-mm2 ✅✅（5bfe3b0） | **完成**（300 全绿+冒烟干净；Minor：_minimap 成员赋值 → MM2a 修复） |
| MM2a | 成员赋值 + 测试时序修复 | impl-mm2a（add9a9e） | - | **完成**（单跑 10/10×2；测试首帧等待改 wait_process_frames(2)——物理帧信号先于 process 派发，证据确凿） |
| MM3 | 回归+实机+文档+终审 | 控制器 | final-review-mm（opus）APPROVE_WITH_NOTES | **完成**（301/301；终审 Major=文档计数→已同步；用户复测三轮：放大 1.5×/波次标签右上角/方向反转修复——**用户实机验收 OK**） |

## 决策记录

- 2026-08-13 用户需求：左上角圆形 2D 地图；朝向=玩家面对方向；组件投影+敌友标志。
- 拍板：渲染 = 数据驱动蓝图投影（AABB 线框，非 SubViewport 相机）；**半径 12m**（用户：不可过大）；敌人 12m 内全显（CS 式 LOS 开关预留 M3）。
- 实施细化：圆形裁剪在 MinimapCore 内做线段-圆求交（无 shader），渲染层零几何逻辑。

## 教训

1. **核心坐标系与渲染坐标系必须显式约定**：MinimapCore 输出"前方=+Y"（数学友好）但 CanvasItem 绘制 +Y 向下 → 用户实测"方向整个弄反了"。修复 = 渲染层 `map_to_screen` y 翻转 + 单元测试固化。凡是核心输出几何被 CanvasItem 直绘的场景，坐标约定写进接口注释。
2. **GUT 短跑场景新节点 `_process` 首帧未 tick**：`wait_physics_frames` 的物理帧信号先于同迭代 process 派发——等待"新节点已跑过 _process"应使用 `wait_process_frames`。
3. **新 class_name 脚本须先 `--import` 重建类缓存**，否则 GUT 误报解析错误。
4. **终审文档计数同步**：交付后头部/摘要行计数与正文条目必须同轮同步（290/300/301 三处漏改被终审列为 Major）。
