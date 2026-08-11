# M2 v3 实施计划 —— 「回声祭坛」布局重写 + 敌人波次刷新 + 跳跃操作记录器

> 分支 feat/m1-assets · 单目录 /Users/elanyi/Projects/Trigger-Echo · 基线 GUT 全绿（M1.5/M1.75 后 163/163）
> 对应设计：docs/superpowers/specs/2026-08-11-m2-echo-altar-v3-design.md（已获用户批准；坐标级几何在 §三，以下任务引用其小节号）
> 账本：docs/superpowers/ledger/2026-08-11-m2-v3-ledger.md
> 全局铁律：TDD RED 先行；验证后才声明完成；每任务 = 新子代理 + 两阶段审查。

## 全局约束（精确值，逐字生效）

| 约束 | 值 |
|---|---|
| 地图可玩区 | x∈[-30,30]、z∈[-29,29]（60×58m） |
| 玩家 | 身高 1.83m / 碰撞宽 1.0m / 移速 6.35 / 蹲高 1.37m |
| 跳跃 | 站立跳顶 1.39m → 可跳面 ≤1.3m；助跑跳远 4.87m → 窗口 ≤4.5m |
| 通道/门 | 通道净宽 ≥3.0m；门洞 ≥2.0m；两碰撞体缝要么 0 要么 ≥1.2m |
| 室内屋顶 | 底面 ≥4.25m |
| 掩体三档 | COVER_CROUCH=0.9（蹲藏）/ COVER_FULL=2.2（站藏）/ WALL=3.0；全图无 1.4m 档 |
| 每建筑 ≥2 门 | v3 封闭建筑仅双营（各 3 门）；开敞结构（rim/长墙）豁口按设计 |
| 手雷 | 满伤半径 8.89m；一雷不得横覆盖主通道（通道 >8.89×2 或有隔断） |
| 俯仰角 | 全部可登表面交战俯仰 ≤±30° |
| 无摔伤 | 跳落 = 免费单向下行 |
| 实体类型 | ground/wall/cover/roof/decor（无碰撞）/bigtree（有碰撞，允许叠墙） |
| 测试命令 | `godot --headless --path . -s addons/gut/gut_cmdln.gd`（先 `--import` 若改 class_name） |

## 架构决策

1. **v3 平行构建**：新文件 `Levels/M2_TDM/map_layout_v3.gd` + `test/unit/test_map_layout_v3.gd`；v2（map_layout.gd + test_map_layout.gd）保持可玩直到 P2 切换任务一次性退役（切换后 GUT 必须全绿）。
2. **坡道 = 台阶盒数据**：`_ramp_steps()` 生成器输出 8 级整高盒（中央坡道每级 0.3m），灰盒无需新实体类型（kind "cover"，灰盒已有盒生成）。
3. **WaveSpawner / JumpRecorder 为新组件**，L_M2.gd 只做装配；纯逻辑类（JumpRecordCore）无场景依赖可单测。
4. **14 刷怪面清单**是 map_layout_v3.gd 的导出接口 `standable_surfaces()`，WaveSpawner 与探针共用。

---

## P1 布局 v3 数据表（任务 1-9）

### 任务 1 [haiku] v3 骨架：常量 + 接口 + 测试框架
- 产出文件：
  - `Levels/M2_TDM/map_layout_v3.gd`：头部注释（v3 设计引用）；常量：`PLAYER_W=1.0 / CORRIDOR_MIN=3.0 / DOOR_MIN=2.0 / JUMPABLE_MAX=1.3 / BOUND_X=30.0 / BOUND_Z=29.0 / COVER_CROUCH=0.9 / COVER_FULL=2.2 / WALL_H=3.0 / GRENADE_RADIUS=8.89`；`GROUNDS`（沿用 v2 地面 60×1×58）+ `WALLS`（沿用 v2 四面边界墙）；空表占位常量（CLOCK/BELT/STREETS/BACKSTREETS/CAMPS/OUTER 全部 `:= []`）；`static func all_solids() -> Array`（拼装全部表，当前=地面+边界墙）；`static func standable_surfaces() -> Array`（返回空数组，任务 8 填充，每项格式 `{"name": String, "center": Vector3, "size": Vector3, "top_y": float}`——顶面即刷怪/可踏面）
  - `test/unit/test_map_layout_v3.gd`：`extends GutTest`；preload V3；测试①常量值断言（上表逐值）②`all_solids()` 返回 Array 且含 Ground/四面边界墙 ③全部实体 AABB 在 60×58 界内（复用 v2 测试的 `_aabb()` 辅助逻辑，拷贝自 test_map_layout.gd）④`standable_surfaces()` 每项含 4 键
- RED→GREEN：先写测试（常量不存在→编译失败=RED），再写 layout 文件至绿。
- 验证：`godot --headless --path . -s addons/gut/gut_cmdln.gd -gselect=test_map_layout_v3.gd` 绿；全套件仍绿（v2 未动）。
- 接口消费：无。产生：V3 常量与接口骨架。

### 任务 2 [sonnet] 中央区块：祭坛台 + 斜板 + 钟楼 + rim
- 数据（全部按设计 §3.2/§3.3 精确值【含 2026-08-11 回廊 3.0 修正】，生成进 `CLOCK` 与 `PLAZA` 常量表）：
  - 祭坛台 (0,0.3,0) size (14,0.6,10)
  - 斜板 4 块（坐台面 0.6，高 2.1 顶齐回廊底 2.7 → center y=1.65）：A(-1.5,1.65,-2.8) (3,2.1,0.4) / B(2.6,1.65,-1.5) (0.4,2.1,3) / A'(1.5,1.65,2.8) / B'(-2.6,1.65,1.5)（后两块 = 前两块 180° 旋转）
  - 钟基座 (0,1.65,0) (4,2.1,4)【坐台面 0.6，顶 2.7】；回廊板 (0,2.85,0) (7,0.3,7)【底 2.7、**行走面 3.0**；出挑下净空 2.1 ≥1.83 ✓】；回廊栏板 0.9 高厚 0.2（center y=3.45）：N 边 z=3.4 两段（x∈[-3.5,-0.75]/[0.75,3.5]，中豁 1.5m）、S 边同（旋转自洽）、E 边 x=3.4 一段长 4.8m（z∈[-3.3,1.5]，豁口 z∈[1.5,3.5]，闭端缩 0.2 避角撞）、W 边 x=-3.4 一段长 4.8m（z∈[-1.5,3.3]，豁口 z∈[-3.5,-1.5]）；组合柱 4 根 0.5×0.5×4.1 center (±2.9, 5.05, ±2.9)【底 3.0 顶 7.1，兼角柱掩体+伞顶支柱】
  - 伞顶：4 块板围合中央 3×3 雷口——板 N (0,7.3,2.75) (8,0.4,2.5)、板 S (0,7.3,-2.75) (8,0.4,2.5)、板 W (-2.75,7.3,0) (2.5,0.4,3)、板 E (2.75,7.3,0) (2.5,0.4,3)【底面 7.1】
  - 钟饰 decor (0, 8.6, 0) (1.2, 1.8, 1.2)【无碰撞 weenie，顶 ~9.5】
  - rim 围墙 3m 高厚 1m（center y=1.5）：N/S 边 x 跨度 [-13.5,13.5]（角部由 E/W 边覆盖）。N 边 z=9.5 四段留 3 豁——中豁 **x∈[2,4.5]**（错轴）、侧豁 x∈[-9,-6.5] 与 [6.5,9]：N1 (-11.25,1.5,9.5) (4.5,3,1)、N2 (-2.25,1.5,9.5) (8.5,3,1)、N3 (5.5,1.5,9.5) (2,3,1)、N4 (11.25,1.5,9.5) (4.5,3,1)；S 边 z=-9.5 180° 旋转（中豁 x∈[-4.5,-2]）：S1 (-11.25,1.5,-9.5) (4.5,3,1)、S2 (-5.5,1.5,-9.5) (2,3,1)、S3 (2.25,1.5,-9.5) (8.5,3,1)、S4 (11.25,1.5,-9.5) (4.5,3,1)；E 边 x=14 两段留街口 z∈[-2,2]（4m）：E_T (14,1.5,6) (1,3,8)、E_B (14,1.5,-6) (1,3,8)；W 边 x=-14 同
- RED 测试（加入 test_map_layout_v3.gd）：①祭坛台尺寸 14×0.6×10 ②rim N 中豁 = x∈[2,4.5]（span 断言：无任何 N rim 段覆盖 x∈[2,4.5]；两侧豁同理）③rim S 中豁 = x∈[-4.5,-2]（旋转对称断言）④E/W 街口 z∈[-2,2] 无墙 ⑤回廊板顶面 =3.0、底面 =2.7（容差 0.001）⑥伞顶底面 =7.1 ⑦斜板 4 块全在祭坛台投影内、底面 =0.6、与基座无 AABB 重叠 ⑧中央区块内部两两 AABB 无重叠（豁免：垂直相接 顶==底 ±0.01——基座/回廊板/栏板/组合柱/伞顶/斜板的堆叠接触）
- 验证：v3 测试绿 + 全套件绿。
- 消费：任务 1 常量。产生：CLOCK/PLAZA 表 + rim 数据。

### 任务 3 [sonnet] 坡道生成器 + 祭坛台微台阶
- 实现 `static func _ramp_steps(x_min, x_max, z_from, z_to, y_from, y_to, name_prefix) -> Array`：沿 z 均分 8 级，第 i 级为整高盒（**底 = y_from**（坐落面：祭坛台坡道底=台面 0.6、望楼坡道底=街面 0）、顶 = y_from + (y_to-y_from)*(i+1)/8），center.y=(底+顶)/2，size (x_max-x_min, 顶-底, 级深)，kind "cover"，name = prefix+"Step%d"。签名加 base 语义即 y_from，相邻级 z 段互不重叠。
  - 东坡道：x∈[3.5,6.5]、z -3.5→2.5（跑 6.0m）、y 0.6→3.0（8 级×0.3，坡度 21.8°）
  - 西坡道：x∈[-6.5,-3.5]、z 2.5→-3.5（旋转对称）
  - 祭坛台微台阶（N/S 缘各一组两级 0.3，供 AI 行走登台）：N 缘级1 center (0,0.15,-5.45) size (2,0.3,0.3)【顶 0.3】、级2 center (0,0.3,-5.15) size (2,0.6,0.3)【顶 0.6=台面，贴台缘 z=-5.0】；S 缘旋转对称；E/W 缘由坡道承担不另设
- RED 测试：①每坡道级数 8、顶面等差 0.3（首 0.9 末 3.0 容差 0.001）②坡道宽 3.0（size.x）③东坡道末级顶 =3.0 且末级 z 范围与回廊 E 豁 z∈[1.5,3.5] 相交 ④坡道与基座缝 =1.5（坡道 x_min 3.5 − 基座 x_max 2，精确断言）⑤**boost 组合禁令门禁**（项目级新断言，遍历 V3 全表）：精确表述：对任意两实体 a(低顶)/b(高顶)，若 0 < top_b−top_a ≤ 1.39 且 b 非叠坐于 a 之上（b.bottom < a.top−0.01），则 a/b 水平净距必须 ≥1.5m（防止踩矮物跳翻邻接高物的组合 boost）——写成测试辅助 `_boost_gate_ok()` 对全部 solid 对断言；叠坐豁免覆盖坡道级/台阶/台上箱等合法堆叠 ⑥微台阶顶面 0.3/0.6 两级、级2 贴台缘
- 验证：v3 测试绿 + 全套件绿。
- 消费：任务 2 中央区块。产生：`_ramp_steps()` + RAMPS 表（含微台阶）。


### 任务 4 [haiku] 东/西市街
- 数据（设计 §3.4）：
  - 长墙（东街 x=23 / 西街 x=-23，厚 1m 长 28m z∈[-14,14]）：3 段留 2 豁 z∈[5.5,8] 与 [-8,-5.5]（2.5m）——分段精确：段1 z∈[-14,-8]、段2 z∈[-5.5,5.5]、段3 z∈[8,14]
  - 望楼台（西 x=-18.5）：台体 (-18.5,1.25,0) (4,2.5,4)【顶 2.5】；栏板 0.9 四边厚 0.2（留北向 2m 豁口朝坡道，z∈[-1,1] 偏北段——豁口 z∈[1,2] 侧留 1m 栏板短段与豁口宽 2m 由实现精确分段，总则：豁口朝坡道顶端落点）；台上箱 0.9 (-17.5,2.95,-1) (0.8,0.9,0.8)；坡道（`_ramp_steps` 变体，宽 2.5m 次要通道）：x∈[-21,-18.5]、z 8.2→2（底 z=8.2 高 0 → 顶 z=2 高 2.5，跑 6.2m=22°，9 级≈0.278m 或 10 级 0.25m 任选——实现定，测试只断言坡度 ≤22° 与顶面 2.5），顶步贴台体北缘 z=2 与台顶齐平
  - 水塔台（东 x=18.5）：180° 旋转：台体 (18.5,1.25,0)、栏板豁口朝南、箱 (17.5,2.95,1)、坡道 x∈[18.5,21]、z -8.2→-2
  - 摊位簇×2/街：箱 0.9 两个成簇 + LOS 板 2.2 (±18.5,1.1,±7) (3,2.2,0.4)——东街簇 z=7 与 -7 各一簇（簇 = 箱 (17.5,0.45,6) (1,0.9,1)+箱 (19.5,0.45,8) (1,0.9,1)+板）
  - 摊阁（翼引力锚）：平台 (18.5,0.6,10) (2.5,1.2,2.5) + 登临台阶 (18.5,0.3,12.25) (1.5,0.6,1.5)【0.6 级】；西街 (-18.5,0.6,-10) + 台阶 (-18.5,0.3,-12.25)（旋转）
- RED 测试：①长墙 3 段 2 豁尺寸位置 ②望楼台顶 2.5 ③坡道坡度：升 2.5/跑 ≥6.2（级数×级深）④摊阁顶 1.2 ≤ JUMPABLE_MAX ⑤市街实体全在 x∈[±14,±23.5] z∈[-14,14] 带内 ⑥旋转对称抽查：东街每实体存在旋转对应体（名称前缀 E_↔W_，center 互为 (-x,-z)，size 相同）——写辅助断言 `_rot_pair_exists(name)`
- 验证：v3 + 全套件绿。
- 消费：任务 1 `_ramp_steps`（任务 3 已并入则用；若任务 3 未完成则等待——顺序依赖任务 3）。

### 任务 5 [haiku] 钟门 + 市集带（南北）
- 数据（设计 §3.5）：
  - 北钟门：门柱 (∓3.125,1.5,14.5) (3.75,3,3)；过梁 (0,4.7,14.5) (11,0.4,3.5)【底 4.5】；翼墙 (±9.5,1.5,14) (9,1,3)
  - 市集北带：摊阁×2 (±6,0.6,11.5) (2.5,1.2,2.5) + 台阶 (±6,0.3,13.25) (1.5,0.6,1.5)；摊簇箱 0.9×4（(±2,0.45,12.5) (1,0.9,1) 两两成簇）；棚板 (±3,4.7,10.75) (4,0.4,2.5)【底 4.5，中央天井 x∈[-1,1]】
  - 南钟门 + 市集南带：全部 180° 旋转（生成器 `_bell_gate(side)` / `_market_belt(side)` 参数 ±1）
- RED 测试：①门廊宽 2.5（两门柱间缝 x∈[-1.25,1.25] 无实体）②过梁底面 4.5 ③棚板与过梁 AABB 无重叠（z 缝 ≥0.75：棚板 z_max 12 ≤ 过梁 z_min 12.75）④天井缝 x∈[-1,1] 在 z∈[9.5,12] 无顶板 ⑤翼墙外端 x=±14 与市街/广场衔接处留 ≥4m 侧豁（z 向无墙段阻挡 z∈[9.5,13.5] x∈[5,14] 区域——区域空断言）⑥旋转对称抽查（N↔S）
- 验证：v3 + 全套件绿。

### 任务 6 [haiku] 背街 + 营（南北）
- 数据（设计 §3.6/§3.7）：
  - 北背街：LOS 板 (±10,1.1,17.75) (3,2.2,0.4)；大树 (±21, 0, 18)（bigtree，沿用 v2 bigtree 数据格式 center.y=1.25 size (0.7,2.5,0.7)）
  - 北营：墙壳 x∈[-7,7] z∈[24,29]：北墙 (0,1.5,28.5) (14,3,1)；南墙两段留中门 3m（x∈[-1.5,1.5]）：段 (-4.25,1.5,24.5) (5.5,3,1) 与 (4.25,1.5,24.5) (5.5,3,1)；西墙两段留侧门 2m（z∈[25.5,27.5]）：段 (-6.5,1.5,24.75) (1,3,1.5)【z∈[24,25.5]】与 (-6.5,1.5,28.25) (1,3,1.5)【z∈[27.5,29]】；东墙旋转对称；顶板 (0,4.7,26.5) (15,0.4,6)【底 4.5】
  - 影壁：南门影壁 (1,1.5,21.75) (4,3,0.5)；东西侧门影壁 (±9.5,1.5,26.5) (0.5,3,4)
  - 营前场货车掩体 (2.5,1.1,21.5) (3,2.2,1)【偏置 x=2.5 避南门轴线】
  - 南营 + 南背街：180° 旋转（生成器 `_camp(side)` / `_backstreet(side)`）
- RED 测试：①营 3 门（南门缝 3m + 双侧门缝 2m，缝内无实体断言）②顶板底面 4.5 ③影壁与营墙外沿缝：南影壁 z∈[21.5,22] 与营南墙 z=24 缝 ≥2 ✓（断言缝值）；侧影壁与营墙缝 2.5（x 向）④营内地面出生区无实体（x∈[-6,6] z∈[25,28] 空断言——出生点空间保护）⑤背街 LOS 板把 58m 通长切成 ≤19m 段（x 向投影断言：板+大树覆盖 x=±10/±21 处）⑥旋转对称抽查

### 任务 7 [haiku] 外环 + 角场
- 数据（设计 §3.8）：外环视线打断 bigtree×4：(-26.5,1.25,12)/(-26.5,1.25,-12)/(26.5,1.25,-12)/(26.5,1.25,12)（bigtree 格式）；角场×4（以 NW 为例）：摊阁 (-26,0.6,21.5) (2.5,1.2,2.5) + 台阶 (-26,0.3,23.25) (1.5,0.6,1.5)；箱簇 0.9×2 (-24,0.45,19.5) (1.2,0.9,1.2) 与 (-28,0.45,23) (1.2,0.9,1.2)；大树 (-23,1.25,22)（bigtree）。其余三角 180°/旋转生成（生成器 `_corner_court(cx, cz)`，四角 (∓26, ±21.5) 参数化）
- RED 测试：①外环街通道宽断言：长墙外沿 x=±23.5 与边界内沿 x=±30 之间无实体（bigtree 豁免——bigtree 0.7m 树干不构成窄缝：任意 bigtree 与相邻体缝 ≥1.2 或豁免规则沿用 scan_gaps bigtree 豁免）②角场 4 组旋转对称 ③角场摊阁顶 1.2
- 验证：v3 + 全套件绿。

### 任务 8 [sonnet] 组装 + standable_surfaces + 宏观断言
- `all_solids()` 拼装全部表（顺序：GROUNDS/WALLS/PLAZA/CLOCK/RAMPS/STREETS/GATES/BACKSTREETS/CAMPS/OUTER）
- `standable_surfaces() -> Array` 返回 **14 面**（每项 {name, center（面中心，y=顶面）, size（面尺寸）, top_y}）：回廊面（7×7 减基座——拆为环带 4 块矩形面数据即可，WaveSpawner 撒点在矩形内随机）、西望楼/东水塔台顶（4×4@2.5）、祭坛台面（14×10@0.6，排除基座/坡道投影区——撒点时 WaveSpawner 侧排除）、市集带摊阁×4（2.5×2.5@1.2）、市街摊阁×2、角场摊阁×4
- RED 测试（宏观）：①standable_surfaces().size() == 14 ②每面 top_y ∈ {0.6, 1.2, 2.5, 2.6} ③每面有 name 且全图唯一 ④全实体数 ≤ 160（实体预算警戒线，v2 为 ~120）⑤≥1.4m 遮挡物（此处用 2.2/3.0 档）≥8 且 7 个探针点 8.89m 内各 ≥1（沿用 v2 test §11.5 探针点集，按 v3 几何微调点位：大厅中心(0,0,0)/市集带(0,±11.5)/市街(±18.5,0)/营前(0,±21.5)/背街(0,±17.75)）⑥全部实体在界内 ⑦旋转对称全表校验（decor/bigtree 豁免装饰差异——v3 无装饰差异，全表严格）
- 验证：v3 + 全套件绿。

### 任务 9 [sonnet] 无重叠全审计 + 窄缝扫描 v3
- 测试：V3 全表两两 AABB 无重叠——豁免清单（精确列出，不得扩大）：a) 垂直相接（顶==底 ±0.01）b) 同坡道相邻级 c) 栏板/角柱/伞顶柱 vs 回廊板/伞顶（垂直）d) 营墙段角落相接 + 顶板盖墙 e) 门柱贴翼墙（面接触）f) rim 段角落相接 g) 长墙段角落相接 h) bigtree 叠墙（铁律）i) 微台阶贴祭坛台（面接触）j) 伞顶板之间角接。豁免必须按名称模式精确匹配，每个豁免注释理由。
- `tools/scan_gaps.py` 适配 v3：切换数据源为 map_layout_v3.gd（脚本解析 GDScript 常量——若解析成本高，改为新增 `tools/dump_v3_solids.gd`（headless 场景脚本，打印 all_solids() JSON 到 stdout），scan_gaps.py 读 JSON）；bigtree 豁免沿用；运行 = **0 处 <1.2m 窄缝**。
- 验证：v3 全断言绿 + scan_gaps 0 + 全套件绿 + `git commit`（P1 里程碑）。

## P2 灰盒切换（任务 10）

### 任务 10 [sonnet] 灰盒 v3 切换 + v2 退役 + 渲染/漫游验证
- `map_greybox.gd`：`LAYOUT` preload → `map_layout_v3.gd`；`_color_for()` 保持（v3 kind 集合不变）
- `L_M2.gd`：`LAYOUT` preload → v3；删除 `_sample_standable_spots()`（P3 用 standable_surfaces 替代——本任务先把 `_spawn_random_enemies()` 临时改为从 `LAYOUT.standable_surfaces()` 的地面级面撒点保持可运行，P3 整体替换）
- 退役：删除 `Levels/M2_TDM/map_layout.gd` + `test/unit/test_map_layout.gd`（+ .uid 文件）——v3 全断言已覆盖其全部有效规则（边界/无重叠/双门/遮挡/门宽）
- 探针：新 `tools/probe_v3_walk.gd`（沿用 probe_walk.gd 结构）：漫游路径覆盖 外环→角场→背街→营→钟门→市集带→广场→祭坛台→坡道→回廊→跳落→市街→望楼→长墙豁→外环，全通
- 验证：全套件绿 + probe_v3_walk EXIT=0 全通 + `godot --path . Levels/M2_TDM/L_M2.tscn` 渲染亲眼看（截图/描述）+ commit

## P3 WaveSpawner（任务 11-12）

### 任务 11 [haiku] WaveSpawner RED
- 新文件 `test/unit/test_wave_spawner.gd`：用假刷怪面数组（3 面）+ 假敌人类（StubEnemy：Node + died 信号 + take_damage→died）注入 `WaveSpawner`（`setup(surfaces, enemy_factory)` 依赖注入）；断言：①spawn_wave 产 5 敌 ②同面 ≤2 ③敌间水平 ≥2m ④敌 y = 面 top_y ⑤全部 died → wave_cleared 信号 → 1.5s 后下一波（用 `await wait_seconds(1.6)` 或注入 Timer 参数缩短）⑥连续波组合不完全相同（上波位置集记录）⑦信号 enemies_left 递减正确
- RED：WaveSpawner 不存在→失败。

### 任务 12 [sonnet] WaveSpawner GREEN + L_M2 集成
- `Levels/M2_TDM/wave_spawner.gd`（class_name WaveSpawner extends Node）：信号 wave_started/enemies_left/wave_cleared；`setup(surfaces: Array, spawn_fn: Callable)`；波次逻辑按任务 11 断言实现；敌人生成委托 spawn_fn（L_M2 传入创建 Enemy 的闭包——保持 Enemy.gd 零改动）
- `L_M2.gd`：删除旧撒点逻辑；`_ready()` 装配 WaveSpawner（surfaces = LAYOUT.standable_surfaces()，spawn_fn 实例化 Enemy 并设置 global_position=面中心+随机偏移(面内 ±0.8m，y=top_y)、rotation.y=面向广场中心±30°）；HUD 增「波次 N · 剩余 X」Label（左上，接 wave_started/enemies_left）
- 验证：全套件绿 + 实机运行打 3 波（杀完 5 → 1.5s 后新 5 个出现在不同面）+ commit

## P4 JumpRecorder（任务 13-15）

### 任务 13 [haiku] JumpRecordCore RED
- 新文件 `test/unit/test_jump_record_core.gd`：JumpRecordCore（纯静态类）断言：
  ①`serialize_solids(solids) -> String` 确定性：同数组乱序输入 → 同串（按 name 排序）；格式 `name|kind|cx,cy,cz|sx,sy,sz`（3 位小数）行连接
  ②`map_hash(solids) -> String`：sha256 十六进制 64 位；改任一 center 分量 0.001 → 哈希变；增删实体 → 哈希变
  ③`classify_episode(start_floor_y, end_floor_y, start_name, end_name) -> String`：end-start ≥0.5 → "climb"；同名面 → "fail"；其它 → "traverse"
  ④`manifest_dict(hash, map_name, episode_count) -> Dictionary` 字段完整
- RED：类不存在→失败。

### 任务 14 [sonnet] JumpRecordCore GREEN
- `Levels/M2_TDM/jump_record_core.gd`（class_name JumpRecordCore，static-only）：实现任务 13 全部；sha256 用 `var ctx := HashingContext.new(); ctx.start(HashingContext.HASH_SHA256); ctx.update(s.to_utf8_buffer()); ctx.finish().hex_encode()`

### 任务 15 [sonnet] JumpRecorder + 集成
- `Levels/M2_TDM/jump_recorder.gd`（class_name JumpRecorder extends Node）：
  - `setup(player: MovementController, layout_solids: Array, map_name: String)`：算哈希→读 `user://jump_training/manifest.json`→哈希不匹配/缺失→`DirAccess.remove_absolute` 递归清空→重建+日志 `地图布局已变更，跳跃记录已重置`
  - `_physics_process`：检测起跳（player 离地且 velocity.y>0 且上帧在地）→ 开始 episode 缓冲；采样字段 `t_ms/px,py,pz/vx,vy,vz/yaw,pitch/ix,iy/crouch/jump_held/on_floor/floor_name`（floor_name 取 `player.get_last_slide_collision()`... 用 `move_and_slide` 碰撞：`player.get_slide_collision_count()` 遍历取 floor 碰撞体名；无则 ""）；结束：连续 0.5s on_floor 或 5s 超时→classify→写 `episodes/ep_%04d.jsonl`（首行元数据 JSON，后续每帧一行 JSON）→更新 manifest 计数
  - `@export var recording_enabled := true`；`flush()` 在 NOTIFICATION_WM_CLOSE_REQUEST 调用
- RED 测试（test_jump_recorder.gd，无头可测部分）：①setup 于空目录→创建 manifest 含哈希 ②二次 setup 同哈希→保留记录 ③改 solids 一坐标→setup 清空目录（目录重建、manifest 哈希为新）④episode 写入文件格式（首行元数据键齐全）——用 FakePlayer（CharacterBody3D 脚本驱动 velocity 模拟跳跃轨迹）或直接调用内部 `_begin_episode/_end_episode` 钩子保证无头可测
- `L_M2.gd`：`_ready()` 装配 JumpRecorder.setup(_player, LAYOUT.all_solids(), "回声祭坛v3")
- 验证：全套件绿 + 实机：跳上祭坛台→退出→检查 user://jump_training/ 有 1 条 climb episode + 手改 map_layout_v3.gd 一坐标→重跑→日志显示重置且目录只剩新 manifest + commit

## P5 探针与文档（任务 16-17）

### 任务 16 [sonnet] 视线/俯仰/timing 探针
- `tools/probe_sightlines.gd`：全图网格采样（2m 网格地面眼高 1.7m），RayCast3D 两两通视检测，报告 >40m 通视对——验收 0 对
- `tools/audit_angles.gd`（headless 脚本）：对 standable_surfaces 每面 × 其设计压制区（面数据附 suppress_radius 字段，任务 8 补），计算俯仰角 ≤30° 断言——验收全过
- 验证：两探针 EXIT=0 + commit

### 任务 17 [sonnet] 最终门禁 + 文档同步
- 全套件绿（新鲜运行，记录数字）+ scan_gaps 0 + probe_v3_walk 全通 + 实机一轮（波次+记录器同时工作）
- 文档：HANDOFF.md（M2 v3 状态 + 新工具清单 + 开场提示词）；FEATURES.md（波次刷新/跳跃记录器 + TDM 参数）；PROGRESS.md（M2 v3 完成记录）；README.md（无新资产则只更进度）；企划书 §4.3/模式二（无限复活 50杀/8分钟）
- commit + 账本收官

---

## 模型层级与派发纪律

| 任务 | 层级 | 理由 |
|---|---|---|
| 1/4/5/6/7/11/13 | haiku | 机械实现（设计文档已有精确坐标，照抄+测试） |
| 2/3/8/9/10/12/14/15/16/17 | sonnet | 集成/几何推理/工具编写 |
| 各任务审查 + 最终全分支审查 | sonnet（任务审查）/ opus（最终） | 方法论规定 |

派发规则（CLAUDE.md §〇.5）：任务 brief 文件传递（/tmp/te-briefs/T*.md，含设计文档对应小节 + 本计划任务全文）；不并行派发实现者；每任务 DONE/DONE_WITH_CONCERNS/NEEDS_CONTEXT/BLOCKED 报告 → 两阶段审查（规格合规 ✅ + 代码质量）→ 修复循环最多 5 轮；账本逐任务记录。

## 验证关卡（每阶段末）

1. P1 末：v3 布局断言全绿 + scan_gaps 0 + 全套件绿
2. P2 末：probe_v3_walk 全通 + 渲染亲眼看
3. P3 末：实机打 3 波
4. P4 末：实机录 episode + 重置验证
5. P5 末：全套件绿 + 全探针 EXIT=0 + 用户实机验收
