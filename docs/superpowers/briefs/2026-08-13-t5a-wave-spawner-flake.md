# Task Brief: T5a — wave_spawner RNG flake 确定性化（机械小修）

> 项目：Trigger Echo（Godot 4.7.1 + GDScript + GUT 测试）
> 工作目录：`/Users/elanyi/Projects/Trigger-Echo`（分支 feat/m1-assets，**直接在此目录工作**）
> 背景：T3 审查发现既有 RNG flake——`test/unit/test_wave_spawner.gd::test_wave_combo_variety` 断言"连续 6 波面名组合至少 2 种"，全部同组合概率 P≈1/243，全量跑随机红。与本轮 T1-T4 改动无关，属既有缺陷。

## 目标

给该测试确定性 RNG 种子，flaky 根治。**只改 `test/unit/test_wave_spawner.gd` 一个文件、一个测试函数。** 附带（T4 审查 Minor，控制器裁定顺带清理）：`Weapons/ThrowTrajectory.gd` 两处过期注释修正：
1. `_render_landing` 内注释"半径 0.25m"→"半径 0.3m"（实值已改 0.3，注释未同步）。
2. 文件头注释中"50 点虚线预览/终点 = 弹道末点"描述改为"200 点虚线预览/落点 = 首次穿越地面插值点"（M1 遗留描述，语义已变）。仅改注释文本，不动任何代码。

## 改动（精确）

`test_wave_combo_variety` 函数体开头（`var s := _make_spawner()` 之前）插入：

```gdscript
	seed(20260813)  # 确定性种子（T5a 2026-08-13）：根治"6 波全同组合"RNG flake（P≈1/243 随机红）
```

（Godot 全局 RNG `seed()` 对后续 `randf_range` 生效；wave_spawner.gd 刷点用全局 `randf_range`，种子生效。）

## 验证（必须执行并报告输出）

1. 单文件连跑 10 次：
   `cd /Users/elanyi/Projects/Trigger-Echo && for i in $(seq 1 10); do godot --headless --path . -s addons/gut/gut_cmdln.gd -gselect=test_wave_spawner; done | grep -c "All tests passed"`
   预期输出 `10`（10/10 全绿）。若种子 20260813 恰好产生 6 波全同组合（该种子下必红），改试 `seed(1)`、`seed(42)`、`seed(777)` 直到找到一个 10/10 全绿的种子，并在报告注明最终种子值。
2. 全量：`godot --headless --path . -s addons/gut/gut_cmdln.gd` 预期 289 全绿。

## 报告格式

- DONE / DONE_WITH_CONCERNS
- 最终种子值 + 单文件 10 连跑通过计数
- 全量统计行（Tests/Passing/Fails）
