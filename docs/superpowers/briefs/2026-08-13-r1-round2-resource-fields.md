# Task Brief: R1 — 修复轮 2 资源字段（机械实现）

> 项目：Trigger Echo（Godot 4.7.1 + GDScript + GUT）
> 工作目录：`/Users/elanyi/Projects/Trigger-Echo`（分支 feat/m1-assets，直接在此目录工作）
> 父计划：`docs/superpowers/plans/2026-08-13-m2-combat-fixes-round2.md`（本 brief 为该计划 R1 的完整规格）

## 目标

WeaponResource 增加 2 个导出字段并在 m67.tres 赋值。纯机械改动，不写测试、不改行为。完成后 GUT 全量必须 289 全绿（基线）。

## 改动 1：`Weapons/Weapon_Resource.gd`

文件末行之后追加（逐字，含注释）：

```gdscript
# M2 修复轮2（2026-08-13）：爆炸穿透衰减——全挡厚度（m，线性截断：mult=clamp(1−T/3.0,0,1)，3m 全挡）
# 与 LOS 采样步长（m，沿爆心→目标胸口线段点采样累计墙厚；越厚挡越多、越薄挡越少——用户拍板方案 A）。
@export var blast_penetration_max: float = 3.0
@export var blast_los_sample_step: float = 0.25
```

## 改动 2：`Weapons/weapon_m67.tres`

`blast_los_probe_height = 1.0` 行之后追加（逐字）：

```
blast_penetration_max = 3.0
blast_los_sample_step = 0.25
```

## 验证步骤（必须执行并报告输出）

1. `cd /Users/elanyi/Projects/Trigger-Echo && godot --headless --path . -s addons/gut/gut_cmdln.gd`
   - 预期：289 测试全绿 0 失败。输出末尾统计行粘贴进报告。
2. 若测试数不是 289 或出现失败：**不要修**，报告 DONE_WITH_CONCERNS 并附完整输出末尾 40 行。

## 报告格式

- DONE / DONE_WITH_CONCERNS
- 每个改动的文件 + 实际插入位置行号
- 验证命令完整输出末尾 15 行（含 tests/failures 统计）
