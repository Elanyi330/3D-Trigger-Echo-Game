# 任务简报 T-nav-ext：祭坛坡道 RampE/RampW 烘焙替身扩展

> 项目：Trigger Echo（Godot 4.7.1，GDScript）。分支 feat/m1-assets。
> 前置：T-nav（塔坡道替身）已收官；本任务把已批准方案 A 扩展到同族缺陷的祭坛坡道。
> 证据（控制器探针 2026-08-15）：RampE/RampW 台阶区 navmesh 多边形与塔坡道同款缺陷——
> 无台阶顶面多边形（应有 y 恒 1.0/1.3/1.6/1.9/2.2/2.5/2.8/3.1 的 8 级顶面），全是
> y∈[1.6,2.4]/[1.8,2.4]/[2.4,3.4] 的倾斜多边形（台阶物理顶 0.6+0.3k，导航面差可达 1.11——
> 冒烟 CorridorSlab 的 RampE 弹出楔死根因）。

## 任务范围

- 生产文件：`tools/bake_navmesh.gd` + 重烘焙 `Levels/M2_TDM/navmesh.res`
- 门禁文件：`tools/probe_navmesh.gd`（④ 门禁扩展祭坛坡道采样列）
- **禁止改动**：map_layout_v3.gd / map_greybox.gd / auto_traversal.gd / 测试文件（工作区有
  T1 修复循环的未提交改动，一字不许动——本任务与它共享 navmesh.res 消费，**不得在其
  GUT 运行期间重烘焙**，但你收到本任务时它已完成）

## 规格

### 1. bake_navmesh.gd：替身扩展到四坡道

1. TOWER_RAMP_SLOPES 数组扩展为四坡道（或改名 RAMP_SLOPES 并保留塔坡道参数——你定，
   注释注明参数逐字同步出处）：
   ```gdscript
   # 祭坛坡道（map_layout_v3.gd L100-101 逐字同步）：
   #   _ramp_steps(3.6, 6.6, -3.5, 2.5, 0.6, 3.0, "RampE", 8)
   #   _ramp_steps(-6.6, -3.6, 3.5, -2.5, 0.6, 3.0, "RampW", 8)
   {"x0": 3.6, "x1": 6.6, "z0": -3.5, "z1": 2.5, "y0": 0.6, "y1": 3.0},
   {"x0": -6.6, "x1": -3.6, "z0": 3.5, "z1": -2.5, "y0": 0.6, "y1": 3.0},
   ```
2. 跳过条件扩展：`RampE`/`RampW` 前缀（仅这四组台阶实体；注意 `RampEStep1` 等命名——
   与布局前缀精确匹配 `nm.begins_with("RampE")` 会误伤？核实布局台阶实体名（RampEStep1..
   RampEStep8 / RampWStep1..），前缀匹配须精确到 `"RampEStep"`/`"RampWStep"` 或先查
   all_solids 实际命名再定——**不得**误跳过名为 RampE 的其他实体（若有）
3. 运行时自检断言扩展：四组前缀台阶实体各恰 8 个 + AABB 与参数 ±0.01 吻合
4. 绕序自动翻转逻辑（叉积 y<0 → 翻转）复用——祭坛坡道是镜像对，同塔坡道规律

### 2. ④ 门禁扩展

祭坛坡道采样列：x=±5.1（RampE x∈[3.6,6.6] 中线 5.1 / RampW 中线 -5.1），
8 个台阶槽中点 `z_i = z0 + (z1-z0)*(i+0.5)/8`（i 0..7，槽深 0.75 一半）。
物理台阶顶 = `0.6 + 0.3*(i+1)`（8 级 × 0.3 高，y 从 0.6 起），期望导航 y ≈
`0.4 + 0.6 + 0.3*(i+1)`。容差 0.35。加坡脚地面缝采样列（z=z0，期望 0.4+0.6=1.0）
与「自上而下」高查列（期望 +1.0，抓悬空面族）——与塔坡道 ④ 同口径。

### 3. 验证（全部执行并贴输出）

1. RED：扩展后的 ④ 在当前 navmesh（祭坛坡道未修复）上失败（采样点证据）
2. 重烘焙 → ④ 全过（四坡道 44+ 判定）
3. `tools/probe_navmesh.gd` ①-④ 全过 exit 0；`tools/probe_v3_walk.gd` 79/79；
   `tools/probe_jump_edges.gd` exit 0
4. 全量 GUT：`godot --headless --path . -s addons/gut/gut_cmdln.gd` → **394/394**——
   重点：test_full_traversal 的 **CorridorSlab 必须转 success**（RampE 弹出回归锚，
   此前 stuck/hang）与 WestTowerBox（T1 修复循环已转 success，不得回退）、
   AltarPlatform（祭坛台目标不得回退）

## 报告格式

开头一行 DONE / DONE_WITH_CONCERNS / NEEDS_CONTEXT / BLOCKED + 改动清单 + RED/GREEN 证据
+ 多边形数 + 各探针/GUT 数字 + 偏差发现。
