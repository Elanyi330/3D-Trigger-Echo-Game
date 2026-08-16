# 面级分析报告 2026-08-16（全量 160 面）

> 工具 `tools/analyze_faces.py` 产出。输入：`Levels/M2_TDM/jump_edges_dataset.json`
> （faces 160 + edges 54 + link_audit 54 + AU 增强 10）+ 人类语料 `jump_training`
> （706 episodes）+ 自动遍历 `auto_traversal`（r9 65 attempts）。数据快照 = 当前磁盘状态。

## 1. 汇总

- 总面数：**160**
- 分 tier 计数：

| tier | 面数 |
|---|---|
| 简单 | 137 |
| 中等 | 13 |
| 困难 | 4 |
| 高难 | 6 |

- 人类语料总览：**706 episodes** —— climb 181 / traverse 180 / fail 345（fail 全为同面失败 start==end；另有 @ 动态名噪声 2 条，climb 计数时跳过）
- 增强边数：**10**（meta.augmented_edges == edges 中 human.augmented==true 数 == meta.augmented 列表长）
- 自动数据快照：**r9 65 attempts** —— 成功 37（56.9%）/ 失败 28（no_path 20 / stuck 4 / jump_missed 4）；覆盖 65 面；summary.per_face 面名与 faces 表无未知面

## 2. 分 tier 清单

行格式：`面名（top_y=高度m）| 可达性 | 人类 n 真实/增强/失误率 | 自动 成/试 | 最优进路 verdict`。
口径说明：真实 n = 真实人类 climb 进面数（含未匹配链接的爬升；同层 traverse 不计入，
与 Ground 平地跳排除同源）；增强 n = 进面边 human.augmented==true 的 n 之和（单独统计）；
最优进路 verdict = 全部进面边 link_audit verdict 的最小 rank 值（无进面边 → "—"）；
失误率 = fail_n/(fail_n+真实 n)，Ground 的 fail 不计（战斗噪声，拍板排除）；
可达性按简报判定级联：no_path → 链接 → success → 未实测（stuck/jump_missed 且无链接
的面落入「未实测」兜底；auto 无该面数据 latest_verdict 标「无数据」）。

### 简单（137 面）

AltarPlatform（top_y=0.6m）| 实测可达 | 19/0/0.10 | 1/1 | —
AltarSlabA（top_y=2.7m）| 未实测 | 0/0/0.00 | 0/0 | —
AltarSlabA2（top_y=2.7m）| 未实测 | 0/0/0.00 | 0/0 | —
AltarSlabB（top_y=2.7m）| 未实测 | 0/0/0.00 | 0/0 | —
AltarSlabB2（top_y=2.7m）| 实测可达 | 0/0/0.00 | 1/1 | —
BackN_LOS_E（top_y=2.2m）| 导航不可达 | 0/0/0.00 | 0/1 | —
BackN_LOS_W（top_y=2.2m）| 导航不可达 | 0/0/0.00 | 0/1 | —
BackS_LOS_E（top_y=2.2m）| 未实测 | 0/0/0.00 | 0/0 | —
BackS_LOS_W（top_y=2.2m）| 未实测 | 0/0/0.00 | 0/0 | —
BeltN_Box1（top_y=0.9m）| 导航不可达 | 0/0/0.00 | 0/1 | —
BeltN_Box2（top_y=0.9m）| 导航不可达 | 0/0/0.00 | 0/1 | —
BeltN_CanopyE（top_y=4.9m）| 跳跃链接可达 | 0/0/0.00 | 0/0 | easy
BeltN_CanopyW（top_y=4.9m）| 跳跃链接可达 | 1/0/0.00 | 0/0 | easy
BeltN_PavE（top_y=1.2m）| 未实测 | 4/0/0.20 | 0/1 | —
BeltN_PavStepE（top_y=0.6m）| 未实测 | 0/0/0.00 | 0/1 | —
BeltN_PavStepW（top_y=0.6m）| 实测可达 | 1/0/0.00 | 1/1 | —
BeltS_Box1（top_y=0.9m）| 未实测 | 0/0/0.00 | 0/0 | —
BeltS_Box2（top_y=0.9m）| 未实测 | 0/0/0.00 | 0/0 | —
BeltS_CanopyE（top_y=4.9m）| 跳跃链接可达 | 0/0/0.00 | 0/0 | —
BeltS_CanopyW（top_y=4.9m）| 跳跃链接可达 | 0/0/0.00 | 0/0 | easy
BeltS_PavE（top_y=1.2m）| 未实测 | 10/0/0.17 | 0/0 | —
BeltS_PavStepE（top_y=0.6m）| 未实测 | 0/0/0.00 | 0/0 | —
BeltS_PavStepW（top_y=0.6m）| 未实测 | 0/0/0.00 | 0/0 | —
CampN_Roof（top_y=4.9m）| 导航不可达 | 0/0/0.00 | 0/1 | —
CampN_Screen_E（top_y=3.0m）| 导航不可达 | 0/0/0.00 | 0/1 | —
CampN_Screen_S（top_y=3.0m）| 导航不可达 | 0/0/0.00 | 0/1 | —
CampN_Screen_W（top_y=3.0m）| 导航不可达 | 0/0/0.00 | 0/1 | —
CampN_Truck（top_y=2.2m）| 导航不可达 | 0/0/0.00 | 0/1 | —
CampN_WallE_N（top_y=3.0m）| 导航不可达 | 0/0/0.00 | 0/1 | —
CampN_WallE_S（top_y=3.0m）| 导航不可达 | 0/0/0.00 | 0/1 | —
CampN_WallN（top_y=3.0m）| 导航不可达 | 0/0/0.00 | 0/1 | —
CampN_WallS_E（top_y=3.0m）| 导航不可达 | 0/0/0.00 | 0/1 | —
CampN_WallS_W（top_y=3.0m）| 导航不可达 | 0/0/0.00 | 0/1 | —
CampN_WallW_N（top_y=3.0m）| 导航不可达 | 0/0/0.00 | 0/1 | —
CampN_WallW_S（top_y=3.0m）| 导航不可达 | 0/0/0.00 | 0/1 | —
CampS_Roof（top_y=4.9m）| 未实测 | 0/0/0.00 | 0/0 | —
CampS_Screen_E（top_y=3.0m）| 未实测 | 0/0/0.00 | 0/0 | —
CampS_Screen_W（top_y=3.0m）| 未实测 | 0/0/0.00 | 0/0 | —
CampS_Truck（top_y=2.2m）| 未实测 | 0/0/0.00 | 0/0 | —
CampS_WallE_N（top_y=3.0m）| 未实测 | 0/0/0.00 | 0/0 | —
CampS_WallE_S（top_y=3.0m）| 未实测 | 0/0/0.00 | 0/0 | —
CampS_WallN_E（top_y=3.0m）| 未实测 | 0/0/0.00 | 0/0 | —
CampS_WallN_W（top_y=3.0m）| 未实测 | 0/0/0.00 | 0/0 | —
CampS_WallS（top_y=3.0m）| 未实测 | 0/0/0.00 | 0/0 | —
CampS_WallW_N（top_y=3.0m）| 未实测 | 0/0/0.00 | 0/0 | —
CampS_WallW_S（top_y=3.0m）| 未实测 | 0/0/0.00 | 0/0 | —
CornerNE_Box1（top_y=0.9m）| 导航不可达 | 0/0/0.00 | 0/1 | —
CornerNE_Pav（top_y=1.2m）| 实测可达 | 5/0/0.00 | 1/1 | —
CornerNE_PavStep（top_y=0.6m）| 实测可达 | 0/0/0.00 | 1/1 | —
CornerNW_Box1（top_y=0.9m）| 实测可达 | 1/0/0.00 | 1/1 | —
CornerNW_Pav（top_y=1.2m）| 实测可达 | 3/0/0.00 | 1/1 | —
CornerNW_PavStep（top_y=0.6m）| 实测可达 | 0/0/0.00 | 1/1 | —
CornerSE_Box1（top_y=0.9m）| 未实测 | 0/0/0.00 | 0/0 | —
CornerSE_Pav（top_y=1.2m）| 未实测 | 0/0/0.00 | 0/0 | —
CornerSE_PavStep（top_y=0.6m）| 未实测 | 0/0/0.00 | 0/0 | —
CornerSW_Box1（top_y=0.9m）| 未实测 | 0/0/0.00 | 0/0 | —
CornerSW_Pav（top_y=1.2m）| 未实测 | 2/0/0.00 | 0/0 | —
CornerSW_PavStep（top_y=0.6m）| 未实测 | 0/0/0.00 | 0/0 | —
EastClusterN_Box（top_y=0.9m）| 跳跃链接可达 | 0/2/0.00 | 0/1 | easy
EastClusterS_Box（top_y=0.9m）| 跳跃链接可达 | 1/0/0.00 | 0/0 | easy
EastClusterS_Panel（top_y=2.2m）| 跳跃链接可达 | 2/2/0.00 | 0/0 | easy
EastPavilionStep（top_y=0.6m）| 实测可达 | 0/0/0.00 | 1/1 | —
EastSpurN（top_y=3.0m）| 跳跃链接可达 | 4/0/0.00 | 1/1 | easy
EastSpurS（top_y=3.0m）| 未实测 | 0/0/0.00 | 0/0 | —
EastTowerBox（top_y=3.4m）| 跳跃链接可达 | 0/4/0.00 | 0/0 | easy
EastTowerRampStep1（top_y=0.2m）| 未实测 | 0/0/0.00 | 0/0 | —
EastTowerRampStep10（top_y=2.5m）| 跳跃链接可达 | 2/0/0.00 | 0/0 | —
EastTowerRampStep2（top_y=0.5m）| 未实测 | 0/0/0.00 | 0/0 | —
EastTowerRampStep3（top_y=0.8m）| 未实测 | 1/0/0.00 | 0/0 | —
EastTowerRampStep4（top_y=1.0m）| 未实测 | 1/0/0.00 | 0/0 | —
EastTowerRampStep5（top_y=1.2m）| 未实测 | 1/0/0.00 | 0/0 | —
EastTowerRampStep6（top_y=1.5m）| 未实测 | 0/0/0.00 | 0/0 | —
EastTowerRampStep7（top_y=1.8m）| 未实测 | 0/0/0.00 | 0/0 | —
EastTowerRampStep8（top_y=2.0m）| 未实测 | 0/0/0.00 | 0/0 | —
EastTowerRampStep9（top_y=2.2m）| 未实测 | 0/0/0.00 | 0/0 | —
EastWall_M（top_y=3.0m）| 跳跃链接可达 | 1/3/0.00 | 0/0 | easy
EastWall_N（top_y=3.0m）| 跳跃链接可达 | 0/0/0.00 | 0/0 | easy
EastWall_S（top_y=3.0m）| 跳跃链接可达 | 1/0/0.00 | 0/0 | —
GateN_PillarE（top_y=3.0m）| 未实测 | 0/0/0.00 | 0/0 | —
GateN_PillarW（top_y=3.0m）| 未实测 | 0/0/0.00 | 0/0 | —
GateS_PillarE（top_y=3.0m）| 未实测 | 0/0/0.00 | 0/0 | —
GateS_PillarW（top_y=3.0m）| 未实测 | 0/0/0.00 | 0/0 | —
Ground（top_y=0.0m）| 跳跃链接可达 | 0/0/0.00 | 1/1 | —
Pedestal（top_y=2.7m）| 实测可达 | 0/0/0.00 | 1/1 | —
Pillar_NE（top_y=7.1m）| 未实测 | 0/0/0.00 | 0/0 | —
Pillar_NW（top_y=7.1m）| 未实测 | 0/0/0.00 | 0/0 | —
Pillar_SE（top_y=7.1m）| 未实测 | 0/0/0.00 | 0/0 | —
Pillar_SW（top_y=7.1m）| 导航不可达 | 0/0/0.00 | 0/1 | —
RampEStep1（top_y=0.9m）| 未实测 | 0/0/0.00 | 0/0 | —
RampEStep2（top_y=1.2m）| 未实测 | 0/0/0.00 | 0/0 | —
RampEStep3（top_y=1.5m）| 未实测 | 1/0/0.00 | 0/0 | —
RampEStep4（top_y=1.8m）| 未实测 | 0/0/0.00 | 0/0 | —
RampEStep5（top_y=2.1m）| 未实测 | 0/0/0.00 | 0/0 | —
RampEStep6（top_y=2.4m）| 未实测 | 1/0/0.00 | 0/0 | —
RampEStep7（top_y=2.7m）| 未实测 | 1/0/0.00 | 0/0 | —
RampEStep8（top_y=3.0m）| 跳跃链接可达 | 1/0/0.00 | 0/0 | —
RampWStep1（top_y=0.9m）| 实测可达 | 0/0/0.00 | 1/1 | —
RampWStep2（top_y=1.2m）| 实测可达 | 0/0/0.00 | 1/1 | —
RampWStep3（top_y=1.5m）| 实测可达 | 0/0/0.00 | 1/1 | —
RampWStep5（top_y=2.1m）| 实测可达 | 2/0/0.00 | 1/1 | —
RampWStep7（top_y=2.7m）| 实测可达 | 2/0/0.00 | 1/1 | —
RampWStep8（top_y=3.0m）| 跳跃链接可达 | 5/0/0.00 | 1/1 | —
RimN1（top_y=3.0m）| 跳跃链接可达 | 1/0/0.00 | 1/1 | —
RimN3（top_y=3.0m）| 跳跃链接可达 | 0/0/0.00 | 0/0 | —
RimN4（top_y=3.0m）| 跳跃链接可达 | 0/0/0.00 | 0/1 | easy
RimS1（top_y=3.0m）| 跳跃链接可达 | 0/0/0.00 | 0/0 | —
RimS3（top_y=3.0m）| 跳跃链接可达 | 1/0/0.00 | 0/0 | —
RimS4（top_y=3.0m）| 跳跃链接可达 | 0/0/0.00 | 0/0 | easy
UmbrellaE（top_y=7.5m）| 未实测 | 0/0/0.00 | 0/0 | —
UmbrellaN（top_y=7.5m）| 未实测 | 0/0/0.00 | 0/0 | —
UmbrellaS（top_y=7.5m）| 未实测 | 0/0/0.00 | 0/0 | —
UmbrellaW（top_y=7.5m）| 导航不可达 | 0/0/0.00 | 0/1 | —
WallEast（top_y=4.0m）| 未实测 | 0/0/0.00 | 0/0 | —
WallNorth（top_y=4.0m）| 导航不可达 | 0/0/0.00 | 0/1 | —
WallSouth（top_y=4.0m）| 未实测 | 0/0/0.00 | 0/0 | —
WallWest（top_y=4.0m）| 未实测 | 0/0/0.00 | 0/0 | —
WestClusterN_Box（top_y=0.9m）| 跳跃链接可达 | 0/1/0.00 | 1/1 | easy
WestClusterN_Panel（top_y=2.2m）| 跳跃链接可达 | 0/1/0.00 | 0/1 | easy
WestClusterS_Box（top_y=0.9m）| 跳跃链接可达 | 2/0/0.00 | 0/0 | easy
WestPavilion（top_y=1.2m）| 跳跃链接可达 | 8/0/0.11 | 0/0 | —
WestPavilionStep（top_y=0.6m）| 未实测 | 0/0/0.00 | 0/0 | —
WestSpurN（top_y=3.0m）| 未实测 | 0/0/0.00 | 0/0 | —
WestSpurS（top_y=3.0m）| 跳跃链接可达 | 5/0/0.00 | 0/0 | easy
WestTowerBox（top_y=3.4m）| 跳跃链接可达 | 4/0/0.20 | 0/0 | easy
WestTowerRampStep1（top_y=0.2m）| 实测可达 | 0/0/0.00 | 1/1 | —
WestTowerRampStep10（top_y=2.5m）| 跳跃链接可达 | 4/0/0.00 | 1/1 | —
WestTowerRampStep2（top_y=0.5m）| 实测可达 | 0/0/0.00 | 1/1 | —
WestTowerRampStep3（top_y=0.8m）| 实测可达 | 0/0/0.00 | 1/1 | —
WestTowerRampStep4（top_y=1.0m）| 实测可达 | 0/0/0.00 | 1/1 | —
WestTowerRampStep5（top_y=1.2m）| 实测可达 | 0/0/0.00 | 1/1 | —
WestTowerRampStep6（top_y=1.5m）| 实测可达 | 0/0/0.00 | 1/1 | —
WestTowerRampStep7（top_y=1.8m）| 实测可达 | 0/0/0.00 | 1/1 | —
WestTowerRampStep8（top_y=2.0m）| 实测可达 | 0/0/0.00 | 1/1 | —
WestTowerRampStep9（top_y=2.2m）| 实测可达 | 2/0/0.00 | 1/1 | —
WestWall_M（top_y=3.0m）| 跳跃链接可达 | 3/1/0.00 | 1/1 | easy
WestWall_N（top_y=3.0m）| 跳跃链接可达 | 0/0/0.00 | 0/1 | easy
WestWall_S（top_y=3.0m）| 跳跃链接可达 | 0/0/0.00 | 0/0 | —

### 中等（13 面）

BeltN_PavW（top_y=1.2m）| 实测可达 | 4/0/0.43 | 1/1 | —
BeltS_PavW（top_y=1.2m）| 未实测 | 3/0/0.25 | 0/0 | —
EastClusterN_Panel（top_y=2.2m）| 跳跃链接可达 | 3/2/0.00 | 0/1 | tight
EastPavilion（top_y=1.2m）| 跳跃链接可达 | 4/0/0.33 | 1/1 | —
EastTower（top_y=2.5m）| 跳跃链接可达 | 6/0/0.25 | 0/0 | easy
RampWStep6（top_y=2.4m）| 实测可达 | 3/0/0.25 | 1/1 | —
RimE_B（top_y=3.0m）| 跳跃链接可达 | 1/0/0.00 | 0/0 | tight
RimE_T（top_y=3.0m）| 跳跃链接可达 | 4/0/0.00 | 1/1 | tight
RimS2（top_y=3.0m）| 跳跃链接可达 | 3/0/0.40 | 0/0 | easy
RimW_B（top_y=3.0m）| 跳跃链接可达 | 7/0/0.00 | 0/0 | tight
RimW_T（top_y=3.0m）| 跳跃链接可达 | 3/0/0.00 | 0/0 | tight
WestClusterS_Panel（top_y=2.2m）| 跳跃链接可达 | 6/0/0.00 | 0/0 | tight
WestTower（top_y=2.5m）| 跳跃链接可达 | 9/0/0.25 | 0/1 | easy

### 困难（4 面）

CampS_Screen_N（top_y=3.0m）| 未实测 | 1/0/0.50 | 0/0 | —
CorridorSlab（top_y=3.0m）| 跳跃链接可达 | 4/0/0.67 | 1/1 | easy
RampWStep4（top_y=1.8m）| 实测可达 | 1/0/0.50 | 1/1 | —
RimN2（top_y=3.0m）| 跳跃链接可达 | 0/0/1.00 | 0/0 | easy

### 高难（6 面）

GateN_Lintel（top_y=4.9m）| 跳跃链接可达 | 4/0/0.00 | 0/0 | infeasible
GateN_WingE（top_y=3.0m）| 跳跃链接可达 | 0/6/1.00 | 0/0 | infeasible
GateN_WingW（top_y=3.0m）| 跳跃链接可达 | 0/0/0.00 | 0/0 | infeasible
GateS_Lintel（top_y=4.9m）| 跳跃链接可达 | 7/0/0.12 | 0/0 | infeasible
GateS_WingE（top_y=3.0m）| 跳跃链接可达 | 0/0/1.00 | 0/0 | infeasible
GateS_WingW（top_y=3.0m）| 跳跃链接可达 | 0/0/1.00 | 0/0 | infeasible

## 3. 无数据面清单（human 真实==0 且 增强==0 且 auto 无 attempts，共 63 面）

AltarSlabA
AltarSlabA2
AltarSlabB
BackS_LOS_E
BackS_LOS_W
BeltN_CanopyE
BeltS_Box1
BeltS_Box2
BeltS_CanopyE
BeltS_CanopyW
BeltS_PavStepE
BeltS_PavStepW
CampS_Roof
CampS_Screen_E
CampS_Screen_W
CampS_Truck
CampS_WallE_N
CampS_WallE_S
CampS_WallN_E
CampS_WallN_W
CampS_WallS
CampS_WallW_N
CampS_WallW_S
CornerSE_Box1
CornerSE_Pav
CornerSE_PavStep
CornerSW_Box1
CornerSW_PavStep
EastSpurS
EastTowerRampStep1
EastTowerRampStep2
EastTowerRampStep6
EastTowerRampStep7
EastTowerRampStep8
EastTowerRampStep9
EastWall_N
GateN_PillarE
GateN_PillarW
GateN_WingW
GateS_PillarE
GateS_PillarW
GateS_WingE
GateS_WingW
Pillar_NE
Pillar_NW
Pillar_SE
RampEStep1
RampEStep2
RampEStep4
RampEStep5
RimN2
RimN3
RimS1
RimS4
UmbrellaE
UmbrellaN
UmbrellaS
WallEast
WallSouth
WallWest
WestPavilionStep
WestSpurN
WestWall_S

## 4. 数据质量注记

- 增强边标记说明：数据集 edges 中 `human.augmented == true` 共 10 条，均带 `source_edge` 指向真实源边（180° 旋转复制、标量不变、矩形取负）； augmented_n 单独统计，不进入 real_n / fail_ratio 分母——增强是合成副本， 真实数据优先原则下不得混入真实口径。
- 人类频率偏好的对称性验证证据（180° 旋转对，非 fail episode 计数，语料现算）：Ground→WestTower 9 vs Ground→EastTower 5；WestTower→WestTowerBox 4 vs EastTower→EastTowerBox 0；WestPavilion→WestClusterS_Panel 2 vs EastPavilion→EastClusterN_Panel 0；RimN1→RimN2 4 vs RimS1→RimS2 4；RimW_B→GateS_WingE 6 vs RimE_T→GateN_WingE 0。 对称侧数量级一致（0 侧由 180° 旋转增强补齐，见 meta.augmented）， 非零侧的差异即人类游玩频率偏好——这正是增强边单独标记、 不计入真实口径的原因。
- 哈希一致性：语料 manifest.map_hash == 数据集 meta.map_hash：一致
- 自动数据 map_hash 与语料不同（自动 manifest.map_hash 为移动语义修订后快照）， 按任务简报口径作为验证器使用，未作对齐处理。

（本报告与 /tmp/face_analysis.json 由同一次确定性运行产出，两次运行逐字节一致。）
