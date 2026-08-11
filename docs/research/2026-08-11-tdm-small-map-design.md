# TDM / Deathmatch 小型地图设计调研报告

> 日期: 2026-08-11 ｜ 用途: Trigger Echo M2 小图（TDM）设计参考 ｜ 来源: 12+ 篇一手/二手资料
> 调研范围: Quake/UT 经典 DM 图、CoD 小图 TDM、CS 社区 DM 图、出生点逻辑、交战密度

---

## 0. TL;DR（十句话核心结论）

1. **环形动线（loops）是小 DM 图的骨架**：玩家位置决定视线，单通道=没有战术选择；经典做法是"2-3 个大环互相叠压"（CS 社区布局公式、de_dust2 范式）。
2. **垂直叠加是小图扩容的最便宜手段**：同一占地做 2-3 层，每层都有回路、所有路都汇回至少一个共享交战点（Quake DM6 → Halo 2 Lockout 的直接传承）。
3. **高价值道具是战斗的"引力源"**：把 1-2 件强力物品放在中心/高地、距双方出生点等距，战斗自然围绕它周期性发生——小图保持持续交火靠这个，而不是靠缩小地图。
4. **出生点铁律**：互相不可直视、合理分散、朝向安全方向（玩家出生后会本能向前走）；但不能孤立到找不到敌人。
5. **FFA 出生算法 = 距离权重 + 视线惩罚 + 避开高流量区**；可预测的算法会被反向工程用来蹲点，加入随机性（UT4 社区结论：出生保护 2.5s 可被滥用，不如纯随机选点）。
6. **TDM 动态出生（CoD 式）= 队友邻近 + 敌方视线 + 区域控制权加权**，且要有 spawn flip 机制；小图必须留足"出生面"的缓冲深度，否则压家即崩（BO6 社区对小图的批评）。
7. **反 spawn trap 的布局手段**：每个出生区 ≥2 条互不相通的出路；没有任何一个 chokepoint 能同时看到所有出生口；强点掩体不能同时防住所有入口（dust2 A 点只盖住 3 个入口中的 2 个）。
8. **交战密度靠"短决策链"维持**：CoD 设计师 Vonderhaar 的原则是玩家移动中"永远不超过三个决策"；出生到第一次交火应在数秒内。
9. **小图的死法**：出生互视的狙击线、死胡同、64 单位"头露半格"掩体、过窄走廊（玩家互相挡路）、分支多到变猜拳图、过长开阔走廊（狙击主宰，Vanguard Berlin 反例）。
10. **数值锚点（Quake/CS，1 单位=1 英寸）**：走廊宽推荐 ≥128u≈3.25m、天花高 ≥128u（CS 推荐 144-192u）、普通跳 244u≈6.2m 远/43u≈1.1m 高、火箭跳约 320u≈8m 远/128u≈3.25m 高。详见第 5 节。

---

## 1. 两种布局流派

### 1.1 竞技场环形流（Arena Loop）——Quake / UT / Halo 路线

**核心概念：loops（环）**。Celia Wagar 的总结：好的 FPS 地图靠环状路径提供多选择——"你的位置决定你的视线"，单条走廊会把站位策略降为零。CS 社区流行布局的经验公式是"**3 个大环互相叠压**"，de_dust2 就是互联环形路线 + 极少硬卡点的范本；但分支过多会退化成不可预判的"猜拳图（Guess map）"。

**Jaquaying**（以 Quake 关卡设计师 Jennell Jaquays 命名）= 非线性交织循环 + 垂直性 + 多路径。对 Quake 2 各图的分析显示：互联性得分最高的图都大量使用"桥的层叠"与多层房间，用垂直性与备选路径鼓励探索，而不是强迫回头路。

**流动（flow）的操作性定义**（Game Developer《Deathmatch Map Design: The Architecture of Flow》，受访者含 Respawn / 343 / Certain Affinity 设计师）：

- flow 是"推着玩家前进的隐形力量"，布局应避免强迫 180° 掉头；
- **布局先画纸面草图**——"layout 是地图最重要的部分"；
- **出生点朝向极其重要**：玩家出生后默认向前走，朝向决定初始路线选择；
- 强力武器对玩家移动有"引力"（gravitational pull）；
- 据点类位置必须有 **≥3 个入口**，防守方无法同时封锁全部；
- 地标=商场的"主力店"，帮玩家定位；
- 验收方式：早期靠试玩感受，后期用数据清除死胡同、平衡交战距离。

### 1.2 三通道（Three-Lane）——CoD 路线

- 结构：出生点到敌方出生点之间由建筑分隔出 **3 条路**；Treyarch 设计师 Vonderhaar 的说法是保证玩家移动中"**永远不超过三个决策**"。
- 分工：**外侧两条开阔、偏远程**；**中路多障碍与房间、偏近战**，利于突入敌营；通道交汇处支持霰弹类近距偷袭，防止单一玩法主宰。
- 目标模式通常把目标放中路引发主战，侧道用于绕后；目标偏侧时中路转为侧攻通道。
- 反例教训：《Vanguard》Berlin 各通道**过长且开阔**→ 狙击手主宰、大量 head glitch——三通道必须用掩体打破远距离对峙。
- 小图标杆 **Shoot House**：近对称三通道，开局即需决定抢哪条路；社区评价"**小空间里的受控混乱**（controlled chaos in a small space）"、**无死区**、侧翼路线不断重置，防止背板蹲点。后续作品（如 BO7 的 Kill Block）仍以它为紧凑交战设计的基准。
- 尺寸分档（社区共识）：Shipment（extra small，纯混战）< Shoot House（small，有战术结构）。**BO6 社区批评部分地图小到无法支撑出生点保护**——三通道结构需要最小尺寸才能运作。

**两种流派的取舍**：竞技场环流适合 FFA/2v2/小队死斗，强调位置与道具控制；三通道适合 6v6 TDM，强调可读性与稳定交战节奏。Trigger Echo 的 TDM 小图可以取三通道的"可读性"，但用环形流打通三条路（通道之间横向连接），避免变成三条平行走廊。

---

## 2. 经典案例拆解

### 2.1 Quake 1 DM6 "The Dark Zone"（1996，Tim Willits）

学术界称之为死亡匹配地图的"模板"。要点：

- **全武器覆盖 + 传送网络**：游戏里所有武器都在图上（含 2 把火箭筒），多个传送门把房间两两串联，形成非线性跳转网络；
- **二层走廊俯瞰大片地图**——垂直监视层是这张图的灵魂之一；
- **道具控制决定胜负**：区域价值排序为 Red Armor 房 > 100% 血量区 > Green Armor 房 > 榴弹发射器平台 > Lightning Gun 洞 > 下层区；"控制 RA 房永远是 DM6 对局的焦点"；
- **固定出生点的信息博弈**：地图只有约 7 个固定出生位，对手可以通过出生音效 + 排除法定位你——教训：**出生点少且可预测时，出生本身成为战术信息**；
- Halo 2 的 Lockout 直接致敬它：**三层结构、所有路径都汇回中央**（Halopedia 明确记载）。

### 2.2 Quake 3 DM6 "Campgrounds"

FFA/TDM 常青树。社区分析（Ferdinand List 等）关键词：**"相当开放"、"极佳的流动感"、"大量垂直变化"**。结构上是三层垂直竞技场：玩家在高价值道具（Megahealth、红甲、黄甲）的刷新节奏驱动下不断上中下层移动，战斗围绕道具时间周期性爆发——这是小图保持交战密度的教科书做法。B 站/YouTube 的 "What Makes This Map Great?" 系列第 33 期有完整拆解。

### 2.3 UT99 DM-Deck16][（Elliot "Myscha" Cannon）

- 官方定位 **2-16 人** DM——小图弹性容纳人数上限的参照；
- 从初代 Unreal 到 UT99 布局几乎原样保留，社区称之为"史上最佳 FPS 地图的有力竞争者"，以节奏与强度著称；
- UT 地图史的教训（arenafps.com）：UT99 的 duel 图普遍偏大且平衡怪异；后来社区做的 1on1 包**把图做太小**，导致"劣势方难以翻盘"；UT2004 官方 1on1 图在无 weaponstay 规则下"一边倒、没法玩"。**结论：缩小地图会放大（而不是掩盖）平衡问题。**

### 2.4 Halo 2 Lockout / Halo Infinite Bazaar（现代竞技场小图）

**Lockout**：三层、全路径回中，是 DM6 的精神续作。
**Bazaar**（Halo Infinite 设计师视角的拆解）：

- 垂直轴对称，剖面呈波浪形，**上下层占地相近**以平衡高低地机会；
- 三条主通道连中央竞技场，上层走廊包抄、底层隧道直插敌后——蛛网状路径服务于"向前推进的战斗"而非固守；
- 交战距离目标："**以近战为主，保留少量远程窗口**"（小图的标准配比）；
- 掩体策略：低层用**少量大掩体**而非大量小掩体——小掩体让玩家频繁转移反而停滞；大掩体内开小通道供安全横穿，两侧设跳台两跳上顶，**防止低地成为绝对劣势区**；
- 强力武器放中央高地、距双方基地等距，取物路径（无护栏楼梯）暴露在多角度火力下——强点必须付出暴露代价；
- 核心信条："**clean mental map（清晰心理地图）是竞技射击地图的基石**"。

### 2.5 CS 社区 DM 图与服务器

- 社区热门 FFA/DM 练习图（Steam 工坊 4-5 星合集、RPS 年度榜）的共同特征：**对称或环形布局、多个高度层次、短视线**，以最大化交战频率——很多就是把官方大图的局部截出来做成环形；
- 服务器功能层面的出生点工程：WarmupServer 主打"优化出生、无限战斗"，xplay 提供"击杀回血 + 智能机器人 + 安全重生（safe respawn）"——**安全重生（视线外、背敌）是 FFA 服务器的标配功能**，说明出生视线隔离是社区公认的第一需求。

---

## 3. 出生点逻辑（spawn logic）

### 3.1 FFA / DM 静态出生点池

Valve 开发者社区《Deathmatch Map Design Theory》的原则：

1. 出生点**合理分散**在整张图上，防止扎堆；
2. 玩家**不得出生在彼此或高流量区域的直接视线内**——防止开局即死；
3. 但也**不能孤立/隐蔽到破坏流动**、让人找不到对手；
4. 地图应设计明确的 **clash points（交锋点）**，让战斗发生在设计好的区域而不是出生点旁；
5. 坡道/多层区域要检查**垂直视线**，避免高处对出生点的单向压制。

选点算法的常见实现（r/gamedesign 社区共识）：**距离权重（远离活着的敌人）+ 视线 raycast 惩罚 + 避开最近 N 秒的交火热点**。

Quake 1 的教训（DM6）：出生点数量少且固定时，出生音效成为对手的定位情报；UT4 社区进一步指出：**可预测的出生算法会被反向工程用来蹲出生**，UT4 的 2500ms 出生保护可在开火时取消、反而可被滥用；他们的替代方案——**出生选择 100% 随机 + 出生延迟代替即时重生 + 扩大出生 volume/点数 + 移除出生音效**。

### 3.2 TDM 动态出生（CoD 体系）

- 加权系统：**队友邻近度 + 敌方视线遮挡 + 目标点距离**；优先选活着的队友附近最近的合法点；
- **spawn flip**：一方持续压上会把对方出生点翻转到地图另一侧；
- 失败模式（MW3 社区大量批评）：proximity spawn 在敌人也临近时失效 → **直接出生在敌人视线里甚至敌人身后**；
- 对地图设计的要求：小图必须为"出生面"留出**缓冲深度与多条前出路线**，否则一旦压家，翻转后的出生点仍在对方火力圈内（BO6 部分小图的根本问题）。

### 3.3 防 spawn trap 布局检查清单

- [ ] 每个出生区 ≥2 条方向不同的出路，且互不共用第一个转角；
- [ ] 不存在能同时看到多个出生口的单一位置；
- [ ] 出生点朝向墙/掩体/安全走廊，而不是开阔交战带（玩家出生即向前走）;
- [ ] 出生点抬高 16u≈0.4m 防卡模、朝向正确（CS 社区标准）；
- [ ] 强点掩体不同时覆盖所有出生出口（dust2 A 点范式：只盖 3 个入口中的 2 个）；
- [ ] 若用 TDM 动态出生：沿两条主轴都要有可翻转的出生面。

---

## 4. 交战密度（engagement density）怎么保持

业界更常用的同义词：**flow、pacing、encounter frequency、combat intensity**。小图的做法：

1. **道具引力**：把战斗"约"到固定地点与固定时间（Quake 的甲/大血刷新、CoD 目标模式的中央目标）。Game Developer 原文：power weapons 对玩家移动有引力。
2. **压缩决策链**：Vonderhaar 的"≤3 个决策"；出生→第一次交火以秒计。
3. **短视线 + 多层**：CS DM 练习图的配方——短视线保证"转角必遇敌"，多层保证被打时有纵向逃脱选择。
4. **消灭死区**：用数据找出无人经过的区域并打通或删除（Game Developer 的后期流程）。
5. **侧翼持续重置**：Shoot House 的做法——绕后路线存在但短，蹲点者总会被绕，没有人能长期锁住一条路。
6. **尺寸匹配人数**：Deck16 的 2-16 人是弹性上限；图大人少→相遇率崩，图小人多→出生即战场（Shipment 是有意为之的极端，不是 TDM 的默认目标）。
7. **可测量的试玩指标**：平均首次交火时间、重生→再交火时间、每分钟击杀数、各区域到访率热力图（死区=0 流量）。

---

## 5. 数值参考（可直接换算）

### 5.1 Quake 体系（1 单位 = 1 英寸 = 2.54cm；无下蹲）

| 项目 | 数值 | 换算 |
|---|---|---|
| 玩家碰撞体 | 32×32×56 u | 0.81×0.81×1.42 m |
| 走廊最小宽 | 33 u（绝对下限） | 0.84 m |
| 走廊推荐宽 | 128 u+ | 3.25 m+ |
| 天花最小高 | 57/64 u | 1.45/1.63 m |
| 天花推荐高 | 128 u | 3.25 m |
| 楼梯 | 16 升 : 32 进 | 1:2 坡度 |
| 坡道 | 1:2 | — |
| 奔跑跳 | 244 u 远 / 43 u 高 | 6.2 m / 1.09 m |
| 火箭跳 | ~320 u 远 / ~128 u 高 | ~8.1 m / 3.25 m |
| 通风管 | ≥64 u（无下蹲） | ≥1.63 m |

补充实践：blockout 用 64/32 网格；坡道沿轴对齐（斜向碰撞体验差）；**跳跃距离按保守值设计**，极限跳留给可选捷径，不作为关键路径（不是所有玩家都能稳定按出）。

### 5.2 CS 体系（Source 单位=英寸）

| 项目 | 数值 | 换算 |
|---|---|---|
| 玩家站/蹲 | 32×72 / 32×54 u | 1.83 m / 1.37 m |
| 走廊宽 | 128-256 u（宁宽勿窄，防互挡） | 3.25-6.5 m |
| 天花高 | 144-192 u，绝不低于 128 | 3.66-4.88 m |
| 双开门 | 48×108 u | 1.22×2.74 m |
| 掩体高度 | ~56 u 或 ~72 u，**避开 64 u**（半露头最难受） | ~1.42 m / ~1.83 m |
| 静默落差 | 站 46 u / 蹲 55 u | 1.17 m / 1.4 m |
| 每队出生点 | 16 个（社区兼容标准），抬高 16 u 放置 | 0.4 m |
| 两站点间轮转 | 10-15 s（炸弹 40 s 倒推） | 小图尺度参考 |

### 5.3 对 MC 方块风格（1 格≈1 m）的换算建议

- 走廊宽：主通道 **3-4 格**，交战房间至少 6-8 格见方；
- 层高：**3-4 格**（128-192u ≈ 3.25-4.9m）；
- 掩体：半墙 1 格出头无意义（对应 64u 头露问题），做 **1.5 格档胸口或 2 格全掩体**（若物理不支持半格则 1 格矮墙 + 2 格高墙两档）；
- 跳台：普通跳安全间距 ≤3 格垂直可达范围；若有爆炸物跳跃武器，**8m 级间距**可作为进阶捷径（对应火箭跳 8.1m）；
- 楼梯 1:2（每升 1 格进 2 格）或直接用半砖台阶。

### 5.4 节奏数值

- 安全区穿越 ≤30 s（第一人称关卡实践指南的"安全区"上限）——小 DM 图应远小于此，**目标：任意两点 ≤10-15 s**；
- UT4 出生保护参考值 2.5 s（可被滥用，慎用）；
- 出生到首次交火：CoD 小图为秒级——试玩时以此为 KPI。

---

## 6. 反面教材清单

| # | 反模式 | 出处/案例 |
|---|---|---|
| 1 | 出生点之间直接通视的长视线 | CS 设计指南："不推荐出生对出生视线"，只有狙击手受益 |
| 2 | 死胡同 | Valve DM 理论；Game Developer 用数据清除死区 |
| 3 | 64u 半露头掩体 | CS 指南：最恼人的对枪高度 |
| 4 | 过窄走廊，队友互挡 | CS 指南：128u 起步、越宽越好 |
| 5 | 强点掩体同时防住所有入口 | CS 指南：好掩体只盖部分入口（dust2 A 点） |
| 6 | 无风险死亡陷阱位 | Mirage ninja corner 式强点必须带高风险 |
| 7 | 分支过多→猜拳图 | Celia Wagar：路径太多反而不可读 |
| 8 | 过长开阔走廊→狙击主宰 | CoD Vanguard Berlin |
| 9 | 图过小→出生保护崩溃、无法翻盘 | BO6 社区；UT 1on1 小图史（"一边倒、没法玩"） |
| 10 | 可预测出生算法被蹲点 | UT4 社区：出生音效+固定算法=情报 |
| 11 | proximity spawn 失效出生在敌人脸前 | MW3 社区对出生系统的集中批评 |
| 12 | 过度复杂/过度垂直 | CS 指南："最成功的地图简单易学"；垂直过多干扰声音与雷达判读 |
| 13 | 黑暗角落/噪点纹理 | 角色辨识度下降，交战不公平 |
| 14 | 关键路径要求极限操作 | Level Design Book：特殊跳只留给可选捷径 |

---

## 7. Trigger Echo M2 小图可执行清单

**布局**
- [ ] 1 个主环 + 至少 1 条捷径环；三条"通道"之间至少有 2 处横向连接（三通道可读性 + 环形流自由度）；
- [ ] 2-3 层垂直结构，每层有回路，至少 2 处上下连接（楼梯/跳台分开布置）；
- [ ] 所有路径汇回 ≥1 个共享中央交战点（Lockout/DM6 范式）；
- [ ] 中央交战点放置 1-2 件高价值道具（对应五武器中的强势武器或护甲），距双方出生等距，取物路线暴露于多角度火力。

**出生点**
- [ ] 每队 ≥8 个出生位（CS 社区标准 16/队，小图酌情），分散、互不通视、朝向安全方向；
- [ ] 每个出生区 ≥2 条出路；无单一位置可见多个出生口；
- [ ] TDM 动态出生权重：队友邻近 > 敌方视线惩罚 > 区域热度；实现 spawn flip 并压测压家场景；
- [ ] 若做 FFA 模式：距离+视线惩罚算法，加随机扰动，考虑移除/弱化出生音效。

**交战密度验证（试玩指标）**
- [ ] 出生→首次交火 ≤5 s（小图 KPI）；
- [ ] 重生→再交火 ≤8 s；
- [ ] 热力图无 0 流量死区；
- [ ] 无位置连续 3 局以上成为无解蹲点。

**数值**
- [ ] 主通道宽 3-4 格、房间天花 3-4 格；掩体两档高度；普通跳间距保守设计；
- [ ] 任意两点移动时间 ≤10-15 s。

---

## 8. 来源列表

1. [Valve Developer Community — Deathmatch Map Design Theory](https://developer.valvesoftware.com/wiki/Deathmatch_Map_Design_Theory)（页面本体 403，内容经搜索索引与引用交叉核对）
2. [Game Developer — Deathmatch Map Design: The Architecture of Flow](https://www.gamedeveloper.com/design/deathmatch-map-design-the-architecture-of-flow)
3. [Celia Wagar (CritPoints) — Good FPS Map Design](https://critpoints.net/2018/02/18/good-fps-map-design/)
4. [The Level Design Book — Quake Metrics](https://book.leveldesignbook.com/process/blockout/metrics/quake)
5. [Steam 社区 — The dos and don'ts of Counter-Strike level design](https://steamcommunity.com/sharedfiles/filedetails/?id=1110438811)
6. [Super Jump (Medium) — Why Have Three-Lane Maps Endured in Call of Duty?](https://medium.com/super-jump/why-have-three-lane-maps-endured-in-call-of-duty-9d3d2837efc9)
7. [Quake Terminus — DM6: The Dark Zone 地图指南](https://www.quaketerminus.com/quakebible/maps-dm6.htm)
8. [Quake Wiki — DM6: The Dark Zone](https://quake.fandom.com/wiki/DM6:_The_Dark_Zone)
9. [Halopedia — Lockout](https://www.halopedia.org/Lockout)（DM6 三层回中结构的传承记载）
10. [Psionic Blast — Jaquaying the Quake Maps](https://psionicblastfromthepast.blogspot.com/2020/07/jaquaying-quake-maps-analysis-of-quake_25.html)
11. [arenafps.com — Spawn rules and protection in UT4](https://arenafps.com/spawn-protection-ut4/)
12. [arenafps.com — Unreal Tournament Map History](https://arenafps.com/unreal-tournament-map-history/)
13. [Ketul Majmudar (Medium) — Halo Infinite Level Design: Bazaar](https://ketul1776.medium.com/halo-infinite-multiplayer-level-design-series-bazaar-a69fb9828762)
14. [Ferdinand List — Campgrounds Mood（q3dm6）](https://www.ferdinandlist.de/leveldesign/campgrounds/)
15. [Unreal Archive — DM-Deck16](https://unrealarchive.org/unreal-tournament/maps/deathmatch/D/dm-deck16_2c80e9fe.html) / [Unreal Wiki — DM-Deck16II](https://unreal.fandom.com/wiki/DM-Deck16II)
16. [CoD 官方 — MWIII 地图指南 Shoot House](https://www.callofduty.com/guides/multiplayer-maps/call-of-duty-guides-modern-warfare-iii-multiplayer-map-guide-shoot-house)；社区讨论（[r/ModernWarfareIII proximity spawns](https://www.reddit.com/r/ModernWarfareIII/comments/1et8f4z/proximity_spawns_are_the_worst_thing_to_ever/)、[r/CODBlackOps7 三通道](https://www.reddit.com/r/CODBlackOps7/comments/1o0ipn9/ill_never_understand_3_lane_map_design_in_cod/)）
17. CS 社区 DM 生态：[Rock Paper Shotgun — Best CS:GO Deathmatch maps](https://www.rockpapershotgun.com/csgo-best-deathmatch-maps-2018)、[Steam 工坊 DM 地图合集](https://steamcommunity.com/sharedfiles/filedetails/?id=738288644)、[WarmupServer](https://warmupserver.net/servers.php)、[xplay.gg](https://xplay.gg/cs2/dm)
18. 视频参考：[What Makes This Map Great Ep.33 — Q3DM6 Campgrounds](https://www.youtube.com/watch?v=TBD5R2ww_vU)、[Three Lane Map Design Deep Dive](https://www.youtube.com/watch?v=Slq8AU_QF6g)、[How Spawns Work in CoD](https://www.youtube.com/watch?v=tg6pv0B7A7g)
