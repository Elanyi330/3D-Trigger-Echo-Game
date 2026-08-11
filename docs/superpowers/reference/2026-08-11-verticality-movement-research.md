# 垂直层与移动设计调研（FPS 关卡设计）

> 日期：2026-08-11 · 用途：Trigger Echo M2 小图「回声集市」垂直层设计参考
> 调研方式：WebSearch + WebFetch，10+ 来源（学术/职业关卡设计师/CS 社区指南/实战分析）
> 单位换算：1 Source unit = 1 英寸 = 0.0254m；CS 移速 250u/s = 6.35m/s（本项目一致）

---

## 〇、摘要（TL;DR）

1. **高地不是免费优势，是风险-回报合约**：高地必须付出代价（暴露头部、可被手雷/多角度反制、撤退路线有限），否则成为"破坏 meta 的不公平位置"。
2. **垂直交战角控制在 ±30° 以内**——超过后准星垂直移动距离不一致，交战体验崩坏（CS 社区铁律）。
3. **垂直层数 ≤3 层**（底/中/顶）。第 4 层不产生新动态，只是"又一个中间层"，小图尤其如此。
4. **垂直层是空间复用器**：小图靠垂直层"把更多玩法塞进更小占地面积"，但层数过多会稀释玩家密度。
5. **上慢下快是天然节奏**：下楼/跳落永远比上楼快——用单向跳落制造不可逆推进，用楼梯/坡道/梯子作为有成本的上升通道。
6. **CS 的 boost 位是"设计出来的非常规性"**：off-angle 打破清图惯例、越过烟雾取信息，但都自带风险（暴露、怕火、无退路）。
7. **垂直层是信息机器**：梯声/落地声是免费情报；静默跳落阈值（CS 46u≈1.17m）是"花钱买安静"的设计刻度。

---

## 一、高地优势的风险-回报设计

### 1.1 高地的收益面
- **视野与先手**：俯视减少被遮挡面积，能看到低处玩家看不到的角落；Quora/社区共识：高处向下射击时对方暴露面积大，低处打高处则头部先露。
- **心理压制**：垂直位置"在交战发生前就隐性传达权力感"（r/gamedesign 讨论），高地天然是视觉焦点与目标引导工具。
- **投掷物增幅**：高处抛物线投掷更容易命中、覆盖更远（Overwatch University 分析），高打低的手雷是进攻方天然优势。

### 1.2 高地的风险面（设计时必须预埋的反制）
- **头部先暴露**：CS 玩家社区名言——"你还没拿到视线，下面的人已经看到你的额头了"。高台 peek 低处时，先暴露的是头，对预瞄方有利。
- **手雷/抛物线是机械反制**：不需要视线即可把高地守军逼出来；Apex 的 skynade 文化就是高地反制的极端演化。
- **多角度夹击与第三方**：Apex 社区结论——暴露的屋顶常常不如室内安全，高地的真正杀手是"被多方同时关注"。
- **撤退即死亡**：单一上下通道的高地 = 被围即死（Halo Bazaar 分析：中央高台"高风险高回报"，完全暴露，逼对手主动下来换公平交战）。

### 1.3 设计原则（可执行）
| 原则 | 做法 | 来源印证 |
|---|---|---|
| 高地必须有代价 | 暴露侧 ≥2 个，或顶面无全掩体；怕雷、怕绕 | Bazaar 中央高台、Apex 屋顶讨论 |
| 给进攻方反制工具 | 多条接近路线（≥2-3 入口）、雷抛射角、可侧 peek 的坡道 | On Game Design（每区 2-3 出入口）、CS 指南（坡道要能侧 peek） |
| 快速通道要有成本 | 最快上高地的路线附加噪声/暴露/坠落风险 | CS 社区指南："用摔落伤害或噪音惩罚平衡快速路线"（本项目无摔伤→用噪声/暴露替代） |
| 优势必须对等 | 一侧给了垂直优势，另一侧给等价物（另一高台/绕后路线/掩体密度） | Medium《第一人称关卡实用指南》 |
| 单一掩体不得锁死方向 | "没有任何一个掩体应强到逼所有进攻者从同一方向打" | Michael Barclay 关卡准则 |
| 高位武器要配脆弱通道 | 高台上的 power weapon 用无掩体楼梯接近 | Halo Bazaar：高台武器 + 暴露楼梯 |

---

## 二、垂直转点速度（楼梯/坡道/跳落/梯子）

### 2.1 CS 的关键数值（Source 单位 → 米）
| 项目 | Source 单位 | 米 | 设计含义 |
|---|---|---|---|
| 站立跳高 | 54u | ≈1.37m | 本项目实测 1.39–1.45m，基本一致 |
| 蹲跳高 | 64u | ≈1.63m | boost/单人蹲跳可达上限 |
| 静默落地高度 | 46u（站）/ 55u（蹲） | ≈1.17m / 1.40m | 超过即发出落地声=暴露信息 |
| 可跨障碍上限 | 18u | ≈0.46m | 高于此值的障碍会打断移动节奏 |
| 走廊宽度 | 128–256u | ≈3.25–6.5m | 避免队友互相卡位 |
| 梯子速度 | 0.78×250u/s = 195u/s | ≈4.95m/s | 比地面慢 22%，且有声、无武器 |
| 交战到达时间 | — | 5–12s | 出生点到主战场 |
| 转点时间 | — | 10–15s（≈20s 即 retake 不可能） | 两目标点/两翼之间 |

### 2.2 上升 vs 下降的不对称
- **下降永远更快**（重力免费）：单向跳落（one-way drop）阻止回头路、强制玩家进入下一场战斗——是把玩家"推"过地图的工具（Level Design Book）。
- **上升需要空间预算**：楼梯、坡道、梯子都要占面积；小图里每个上升通道都是预算决策。
- **梯子 = 高风险侧翼通道**：速度慢 22% + 攀爬有声 + 无法还击，所以梯子天然适合做"奇袭/绕后"路线而非主路线；CS2 社区甚至围绕"静默快速下梯"发展出专门 tech，说明梯子的声音信息量被玩家视为核心博弈点（2026-04 更新还专门修过静默梯 bug）。
- **坡道细节**：CS 社区指南明确——坡道要设计成能**侧身 peek**，而不是一露头只给楼下看脚（或只给楼下看头）。
- **楼梯要 clip**：CS 地图惯例是给楼梯刷 clip brush，避免台阶碰撞打断准星平稳移动。
- **避免极端坡度**：地形坡度突变"难以观察、难以通行"，缓坡更利于可读性（On Game Design）。
- **多层 circulation 部分重叠**：用楼梯/横梁/跳跃把院子、天桥、地道连成"无限路径"，并让高处的全景视角同时看到目标与到达目标的路线（Pascal Luban，Gamasutra）。

---

## 三、CS 的非常规跳跃位（boost / window / 梯子时机）

### 3.1 boost 位的战术价值（Refrag CS2 专文）
- **Off-angle 打破清图惯例**：敌人必须重新调整准星和清点顺序，"让对手永远在猜"。
- **越过烟雾/常规遮挡取信息**：例如 CT 侧 boost 从烟雾上方 peek。
- **早期首杀或信息收集**，可直接翻转关键局。
- **好的 boost 自带安全网**：即使被道具反制也能退（"被烧也不亏"的位置）；差的 boost 被一个火就团灭。

### 3.2 经典案例（按地图）
| 地图 | 位置 | 用途 |
|---|---|---|
| Dust2 | Cat boost（A 小道）| 打 Lower Tunnels 的恶心 off-angle |
| Dust2 | Window boost（A 小窗）| post-plant 反常规角度，retake 的 CT 很少预瞄 |
| Inferno | Newbox / Porch boost | B 点 setup、越过 smoke peek、增加 T 侧清点成本 |
| Nuke | Fake vent pixel walk / Ramp 箱堆 | A 点刁钻站位、低配局堵 rush |
| Train | Bomb train / Popdog | 高风险惊喜首杀 / 安全取 A 点信息 |
| Mirage | 各类 jump-boost | 非常规移动交互（社区创作） |

### 3.3 设计侧的两面性
- **有意为之 vs 必须封堵**：CS 关卡指南要求用 clip brush 封掉"游戏破坏性 boost"（小装饰物必须设为非实体，避免玩家踩灯爬上房）；而**有意的** boost 位是战术资产。→ 结论：**每张图应保留少量"设计过的非常规位"，同时系统性地清理意外位。**
- **head peek 高度讲究**：掩体高度避免恰好 64u（蹲下完全藏、站起完全露的二元尴尬），用 ≈56u（1.42m）或 ≈72u（1.83m）制造更好的视线关系。
- **boost 的成本结构**：双人 boost 需要队友配合（资源成本）+ 上得去下不来/怕火（风险）——这正是"非常规位"的回报定价。
- **梯子时机（ladder timing）**：Nuke/Ancient 等图的梯子口是声音博弈点——上梯慢（195u/s）+ 有声 = 可被预瞄惩罚；CS2 职业比赛里梯子口架枪与静默梯是固定战术内容。

---

## 四、垂直层如何制造信息差与奇袭

1. **视线不对称**：低处看不到高处内部（需要暴露换信息），高处看低处一览无余——高地本质是"信息存储罐"（ddk：信息决定站位，时间限制站位；信息会随时间贬值）。
2. **声音即免费情报**：落地声（>46u）、梯子声、跳落声都是垂直层特有的信息泄露通道。**把关键奇袭路线的跳落高度设计在静默阈值之上，等于给奇袭定价。**
3. **奇袭位必须可被反制**：Barclay 准则——"室内空间必须有多个出口，对手永远能 flank/ambush/把玩家 flush 出来"；制高点要能"侦察后再制定计划"，但侦察者自己也要能被绕。
4. **垂直层作隐蔽机动通道**：Halo Bazaar 的最低层暗道完全绕过中央战场、直达双方基地后方——垂直最底层反而是最强的奇袭层。
5. **boost 位 = 一次性奇袭资产**：价值来自"对手没练过这个清点"，被发现后价值衰减（与 ddk 的信息贬值律一致）→ 小图里应布置多个轮换使用的奇袭位，而不是一个"最强位"。

---

## 五、小图中垂直层的密度建议

| 建议 | 依据 |
|---|---|
| **可玩垂直层 ≤3 层**（底/中/顶），第 4 层无新动态 | Level Design Book：floor planes 理论 |
| 小图共识 **2–3 层**；层数过多稀释玩家密度、制造死区与混乱视线 | Black Shell Media（小规模 FPS 设计）、综合共识 |
| 垂直是**空间复用器**：小图用垂直层"塞进更多玩法"，但先画 flow 图再动几何 | On Game Design Part 2 |
| 高频小幅高差变化会挫败精确瞄准——**把高差整合进明确的楼层**，而不是连续小台阶 | Level Design Book |
| 每个功能区 **2–3 个出入口**；垂直通道也算出入口 | On Game Design |
| CS 经典结构：**3 条大环形回路叠加，Z 轴交叉点有限**——垂直连接是稀缺资源，不是越多越好 | Celia Wagar 对 CS 地图的分析 |
| 垂直交战角 **±30° 以内**；超出的高差改为不可交战的结构（纯装饰/纯通道） | CS 社区关卡指南 |
| 参考模型：R6 Siege 式"层与层之间的隔板可被改变"是小图垂直的终极形态（本项目无破坏系统，可用"多个可被控制的层间开口"近似） | Black Shell Media |

**对 3400㎡ 级小图（回声集市）的推论**：东西两翼各 1 个垂直层（1.4m 跳跃屋顶 + 2.5m 坡道屋顶）+ 地面层 = 恰好 3 层结构，符合上限；两层高度差都在 ±30° 交战角可消化范围内；关键是保证每个屋顶有 ≥2 上下方式 + 反制路线。

---

## 六、数值速查表（CS → 米 → Trigger Echo）

| 参数 | CS 值 | 米制 | 本项目现状 |
|---|---|---|---|
| 标准跳高 | 54u | 1.37m | 实测 1.39–1.45m ✅ |
| 蹲跳高 | 64u | 1.63m | 未实测（建议 T 任务补测） |
| 静默落地阈值 | 46u | 1.17m | 西屋顶 1.4m/矮墙 1.2m 均超过→跳落有声 ✅ 符合"奇袭定价" |
| 障碍可跨上限 | 18u | 0.46m | 街区路缘/门槛应 ≤0.46m |
| 走廊/通道宽 | 128–256u | 3.25–6.5m | 西街 3m 窄巷低于下限——有意为之需确认不卡位（玩家碰撞宽 1.0m，双人并排需 2m+，3m 可过但拥挤=设计意图内的交战巷） |
| head peek 推荐 | ≈56u / ≈72u | 1.42m / 1.83m | 矮墙 1.2m ≈47u 是全身掩体非 head peek；若要 head peek 位，用 1.42m 或 1.83m |
| 梯子速度 | 195u/s | 4.95m/s | 若加梯子，按 78% 移速实现 |
| 交战到达 | 5–12s | — | 60m 横穿 9.5s ✅ |
| 转点 | 10–15s | — | 60×58m 对角≈8.3s ✅ 宽裕 |
| 垂直交战角 | ±30° 内 | — | 2.5m 屋顶若用斜坡，坡角需 ≤30° 且能侧 peek |

---

## 七、反面教材 / 常见错误清单

1. **过度垂直**：高频小高差、层层叠叠——挫败瞄准、稀释密度、读不懂地图（Level Design Book + 小图共识）。
2. **垂直交战角 >±30°**：准星垂直行程不一致，高打低变成单向屠杀或双方都打不中。
3. **无代价高地**：全掩体顶面 + 单一上下口 + 不怕雷 =  degeneracy，全场蹲一个点。
4. **64u head peek**：蹲下全藏站起全露的二元掩体，视线关系差。
5. **未封堵的意外 boost**：小装饰物实体化导致踩灯上房——CS 指南点名要用 clip/非实体处理。
6. **梯子当主路线**：慢 22%、有声、不能还手，主路线走梯子 = 送。
7. **坡道只露头或只露脚**：上下坡视线设计失误，攻方完全被动。
8. **小图堆 4+ 垂直层**：死区、迷路、遭遇密度崩坏。
9. **20 秒转点**：retake 不可能，防守方永远以多打少。
10. **奇袭位只有一个**：被学会后价值归零；应成组布置、轮换使用。
11. **单向跳落通向死胡同**：one-way drop 的价值是"推向战斗"，落入无出口空间 = 陷阱 bug。
12. **优势不对称**：只有一侧有高台/屋顶，另一方无对等反制——镜像对称是 TDM 小图的铁律。

---

## 八、来源清单

1. [The Level Design Book — Verticality（垂直流）](https://book.leveldesignbook.com/process/layout/flow/verticality)
2. [Steam 社区：Counter-Strike 关卡设计的 Do's and Don'ts](https://steamcommunity.com/sharedfiles/filedetails/?id=1110438811)（数值主来源）
3. [Refrag：CS2 最佳 Boost 位](https://refrag.gg/blog/best-cs2-boost-spots-2/)
4. [Halo Infinite 多人图设计分析：BAZAAR（Ketul Majmudar）](https://ketul1776.medium.com/halo-infinite-multiplayer-level-design-series-bazaar-a69fb9828762)
5. [Michael Barclay — My Level Design Guidelines](https://mikebarclay.co.uk/my-level-design-guidelines/)
6. [On Game Design — Designing FPS Multiplayer Maps Part 2（flow/连通性）](https://www.ongamedesign.net/designing-fps-multiplayer-maps-part-2/)
7. [Black Shell Media — Importance of Small Scale FPS Level Design](https://blackshellmedia.com/2017/01/importance-small-scale-fps-level-design-mainstream-development/)
8. [Gamasutra — Multiplayer Level Design In-Depth Part 2（Pascal Luban，第三维度规则）](https://www.gamedeveloper.com/design/multiplayer-level-design-in-depth-part-2-the-rules-of-map-design)
9. [Mapcore — CS2 Ladder Movementspeed（梯子 195u/s 数据）](https://www.mapcore.org/forums/thread/30280-cs2-ladder-movementspeed/)
10. [ddk — How To Think About Tactical FPS（信息/时机/站位框架）](https://ddkesports.medium.com/how-to-think-about-tactical-fps-by-ddk-f1b84d6bfcbb)
11. [Celia Wagar — Good FPS Map Design（CS 三环回路）](https://critpoints.net/2018/02/18/good-fps-map-design/)
12. [r/apexuniversity — High ground?（高地风险社区实证）](https://www.reddit.com/r/apexuniversity/comments/10uasna/high_ground/) + [r/OverwatchUniversity — How does high ground work?（抛物线反制）](https://www.reddit.com/r/OverwatchUniversity/comments/1sa2smu/how_does_high_ground_work/)
13. [Reddit — CS2 静默快速下梯 tech](https://www.reddit.com/r/GlobalOffensive/comments/1pj8j2u/theres_a_new_tech_to_descending_ladders_faster/)（梯子声音博弈佐证）
