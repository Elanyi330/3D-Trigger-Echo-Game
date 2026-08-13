# Task Brief: T1 — 武器资源新字段（机械实现）

> 项目：Trigger Echo（Godot 4.7.1 + GDScript + GUT 测试）
> 工作目录：`/Users/elanyi/Projects/Trigger-Echo`（分支 feat/m1-assets，**直接在此目录工作**）
> 父计划：`docs/superpowers/plans/2026-08-13-m2-melee-grenade-fixes.md`（本 brief 为该计划 T1 的完整规格，不要依赖其他上下文）

## 目标

为 WeaponResource 增加 4 个导出字段并在两个 .tres 资源文件中赋值。**纯机械改动**——不写测试、不改行为、不重构。完成后现有 GUT 测试必须保持全绿（基线 276）。

## 背景约束（铁律）

- 数值唯一来源是 `Weapons/weapon_*.tres`，代码禁止硬编码这些值。
- 项目是纯离线单机 FPS；本任务不涉及任何网络/渲染。
- Godot 4.7.1；GDScript `@export` 字段有默认值即可被 .tres 覆盖。

## 改动 1：`Weapons/Weapon_Resource.gd`

在该文件**最后一行**（当前是 `@export var melee_heavy_hit_delay: float = 0.45`）之后追加以下内容（含注释，逐字）：

```gdscript
# M2 手感修复（2026-08-13）：近战连击窗口（s）——自挥击发起帧计时，窗口内轻击=连击 25，超时重置首挥 40。
@export var melee_combo_window: float = 0.8
# M2 手感修复（2026-08-13）：重刺射程分级（m）——CS 权威 stab 32u≈1.6 短于 slash 48u≈2.0
# （docs/superpowers/reference/cs2-weapon-data.md 近战表"攻击距离"行：CS 重刺前送触及短于斜挥弧线）。
@export var melee_stab_range: float = 0.0
# M2 手感修复（2026-08-13）：近战垂直差上限（m，脚部-脚部）——1.5 允许同层/1.2m 摊阁/0.6m 祭坛台，
# 禁止 2.5m 望楼 / 3.0m 回廊隔层刀人。
@export var melee_vertical_range: float = 0.0
# M2 手感修复（2026-08-13）：手雷爆炸 LOS 探测点高度（m，目标脚部上方=胸口参考点）——
# LOS 射线打此点而不打脚部：防贴地射线打中地板造成假遮挡。
@export var blast_los_probe_height: float = 1.0
```

## 改动 2：`Weapons/weapon_knife.tres`

在 `melee_heavy_hit_delay = 0.45` 行之后追加（逐字）：

```
melee_combo_window = 0.8
melee_stab_range = 1.6
melee_vertical_range = 1.5
```

## 改动 3：`Weapons/weapon_m67.tres`

在 `blast_radius = 8.89` 行之后追加（逐字）：

```
blast_los_probe_height = 1.0
```

## 验证步骤（必须执行并报告输出）

1. `cd /Users/elanyi/Projects/Trigger-Echo && godot --headless --path . -s addons/gut/gut_cmdln.gd`
   - 预期：全绿、276 测试、0 失败。输出末尾统计行粘贴进报告。
2. 若测试数不是 276 或出现失败：**不要修**，报告 DONE_WITH_CONCERNS 并附完整输出末尾 40 行。

## 报告格式（最终回复 = 数据，不是给人看的对话）

返回：
- DONE（若验证通过）/ DONE_WITH_CONCERNS（若有异常）
- 每个改动的文件 + 实际插入位置行号
- 验证命令完整输出末尾 15 行（含 tests/failures 统计）
