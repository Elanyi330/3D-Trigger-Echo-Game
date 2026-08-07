# M1 设计文档 — 武器系统（四槽位各一款 + CS2 数值对齐）

> 日期: 2026-08-06
> 上游: 企划书 v1.0（定稿，§4.2 已修订为 CS2 对齐）→ 里程碑 M1
> 前置: M0 完成（FirstPersonStarter 控制器 + CS 移动数值 + GUT 14/14）
> 状态: 设计定稿（用户确认范围与方案）

---

## 1. 目标

建立资源驱动武器系统（Weapon_Resource），实现**四槽位携带体系**——主武器 AK-47「铁幕」+ 副武器 Glock-18「迅捷」+ 近战战术匕首「回声」+ 投掷 M67「轰鸣」，支持切换、开火、换弹、开镜、后坐力（CS2 固定弹道模型）、移速联动（CS2 数值），全部武器数值对齐 CS2（2026-03-18 补丁）。武器切换状态机 + 携带规则一并实现。

**本里程碑不做**：霰弹/狙击（M5）、配件系统（瞄准镜/弹夹，后续环节）、AI 持枪、回合状态机、投掷物物理弹道（M67 引信与爆炸逻辑列入，投掷抛物线轨迹简化实现）。

## 2. 架构

### 2.1 整体结构

```
Trigger Echo（Godot 4.7.1 项目）
├── project.godot            ← 新增输入动作 fire / reload / aim / weapon_1..4
├── Assets/                  ← 拼装模型资产（决策：全资产拼装化，独立分类，未来精化）
│   ├── Models/Weapons/      ← 第一人称武器视模型（AK47_view.tscn / Glock18_view.tscn …）
│   ├── Models/Hands/        ← 第一人称手部（FpHands.tscn，各武器共用）
│   ├── Models/Characters/   ← 全身模型（M3 AI 启用，本次仅建目录）
│   └── Materials/           ← 共享材质库（枪身金属 / 手部肤色 / 瞄准框）
├── Weapons/                 ← 武器系统（代码 + 数值资源）
│   ├── Weapon_Resource.gd   ← 纯数据类：伤害/RPM/弹匣/后坐力表/移速/开火模式…
│   ├── WeaponManager.gd     ← 四槽位总控：切换状态机 + 弹药总账 + 动作分发
│   ├── WeaponCore.gd        ← 射击核心：hitscan 发射 + 后坐力应用 + 换弹计时 + 开镜
│   ├── weapon_ak47.tres     ← 数值唯一来源（CS2 对齐：36 伤 / ×4.0 / 600RPM / 30+120）
│   ├── weapon_glock18.tres  ← 30 伤 / ×4.0 / 400RPM / 20+80
│   ├── weapon_knife.tres    ← 首击 40 / 背刺 180 / 0.4s+1.0s
│   └── weapon_m67.tres      ← 中心 98 / 引信 1.5s / 半径 6m
├── Player/
│   ├── MovementController.gd  ← 新增 speed_modifier（武器移速联动）
│   ├── Head.gd                ← 新增 add_recoil() / set_ads() 接口（后坐力 + 开镜接管）
│   └── WeaponAnchor.tscn      ← 第一人称武器挂点（Head 下，持枪视模型容器）
└── test/unit/               ← 新增武器测试（test_weapon_manager / test_weapon_core / …）
```

### 2.2 代码与资产分离

- **数值资源**（`weapon_*.tres`）在 `Weapons/`，为武器数值唯一来源（企划书 §4.2.5，硬性约束）
- **视觉模型**（`Assets/Models/`）与代码解耦：M1 用 BoxMesh/CylinderMesh 拼装占位（AK47_view 等），M5/M6 精化时原位替换，代码零改动
- **配件系统**（瞄准镜/弹夹，用户已确认列入后续）：`Weapon_Resource` 预留 `attachments` 槽位（默认空），M1 不实现装配逻辑

### 2.3 输入动作（新增，照搬 CS2 键位）

| 动作 | 键位 | 说明 |
|------|------|------|
| `fire` | 鼠标左键 | 开火（按住连发/单发按模式） |
| `reload` | R | 换弹 |
| `aim` | 鼠标右键 | 开镜/机瞄（按住） |
| `weapon_1` | 1 | 切主武器（AK-47） |
| `weapon_2` | 2 | 切副武器（Glock-18） |
| `weapon_3` | 3 | 切近战（匕首） |
| `weapon_4` | 4 | 切投掷（M67） |
| `next_weapon` | 滚轮 | 循环切换（CS 式） |

### 2.4 武器切换状态机（WeaponManager）

**槽位**：`primary`（AK-47）/ `secondary`（Glock-18）/ `melee`（匕首）/ `throwable`（M67）——固定四槽（对应企划书 §4.2.4 携带规则）。

**状态**：`HOLSTERED`（未持有）/ `DEPLOYING`（切换动画延迟，CS 式切枪时间）/ `ACTIVE`（可操作）/ `RELOADING`（换弹中，不可开火）/ `THROWING`（手雷投掷中）。

**规则（对齐 CS2）**：
- 切枪 = 旧武器收枪（收枪时间 0）+ 新武器部署（deploy 时间）；部署期间不可开火/换弹/开镜
- 切枪动作可中断换弹（CS 式：换弹中切枪立即中断，弹药不返还）
- 移动/跳跃/下蹲不中断任何武器状态
- 开火中切枪：立即中断开火

**M67 投掷流程**：按 `fire` → 进入 THROWING（引信 1.5s 开始计时）→ 引信结束抛出弹道体（抛物线简化）→ 撞击时爆炸（半径 6m 内距离衰减伤害 98→57→30）→ 回到 ACTIVE。按住 `aim`（右键）可取消投掷（保留弹药，企划书 §4.2.3⑦）。

### 2.5 射击核心（WeaponCore，资源驱动）

**开火流程**（hitscan）：
1. 检查弹药（弹匣 = 0 → 自动换弹或空仓声）
2. 射速节流（RPM → 单发间隔；全自动按住连发 / 半自动每击一发 / 泵动/栓动手动）
3. 后坐力应用（见 2.6）
4. 射线检测：从 Head 相机原点沿视向发射，物理层 `Objects`（层 1），命中最远 `max_range`
5. 命中判定：碰撞体 → 取所属单位（Area/Group）→ 部位判定（头部层/躯干/四肢，参考企划 §4.2.1）→ 伤害结算（`伤害 × 部位倍率`，全自动武器爆头 ×4.0）
6. 弹着反馈：弹孔标记（占位）、命中特效（占位）

**伤害结算**：`最终伤害 = 基础伤害 × 部位倍率 × 距离衰减`（分段阶梯曲线：0-有效=1.0 → 递降 → 下限 0.96，AK 表）；四肢 ×0.8（企划差异化字段）；穿甲恒全额（v1.0 无护甲）。

**换弹（对齐 CS2 2026-03 规则）**：战术换弹/空仓换弹单值（AK 2.4s / Glock 2.3s）；**换弹丢弃弹匣剩余**（CS2 规则）；换弹可被打断（切枪/开火中断，弹药不返还）。

### 2.6 后坐力（CS2 Recoil Pattern 模型）

**三要素**（对齐 CS2 架构）：
1. **固定弹道（Set Pattern）**：`pattern` = 逐发偏移数组（Vector2 数组：每发垂直+水平角度）。AK-47 前 3-5 发垂直上升 → 向左/右摆动（M1 按 CS2 弹道表近似拟合，见 §4 待校准）
2. **随机（Random）**：单发/半自动武器每发在 `recoil_amount ± amount_variance` 范围内随机偏移（Glock 用此模型）
3. **恢复（Recovery）**：停止射击后准星回正速度（°/s，CS2 隐含于固定弹道 reset；M1 参数化 `recovery_speed`）

**接口**：`WeaponCore.recoil_offset()` → 累计角度；`Head.add_recoil(offset)` → 叠加到相机 `rotation.x`，随恢复衰减回零（M0 审查建议的 Head 接口，本次落地）。

**首发精度**：独立于弹道表（AK 极高首发精度 = 首发偏移极小；Glock 随机模型）。

### 2.7 开镜/机瞄（ADS 框架）

- **通用框架**（为 M5 AWP 预留）：`Weapon_Resource.ads` 字段（倍率/散布收窄/灵敏度系数）→ WeaponCore 读取 → Head 应用
- **AK-47 机瞄 ×1.5**：按住 `aim` → FOV 缩放 1.5 倍 + 散布收窄 + 灵敏度联动缩放；松开恢复（CS 式按住开镜）
- **散布模型**：腰射散布（站立）vs 开镜散布（机瞄收窄）——M1 用简单圆内均匀随机，M5 霰弹再引入高斯分布
- **Glock**：无开镜（照搬 CS2，手枪无右键）；M67 右键 = 取消投掷（见 2.4）
- **灵敏度联动**：开镜时 `mouse_sensitivity × (1/ads_magnification)`（CS 式，保持手眼一致）

### 2.8 移速联动（CS2 数值，M1 实现）

- `Weapon_Resource.mobility`（u/s）→ 换算 `speed_modifier = mobility / 250`
- `MovementController.speed_effective = base_speed(6.35) × speed_modifier`
- 武器切换时 WeaponManager 写入 modifier；默认刀 250u=1.0 / Glock 240u=0.96 / M67 245u=0.98 / AK 215u=0.86
- **下蹲速度固定 2.59 不受影响**（CS 规则）；空中无加速（已实现）不受影响

### 2.9 持枪视模型与手部（拼装资产）

- `Assets/Models/Weapons/AK47_view.tscn`：3-4 个 Box/Cylinder 拼装（枪管/枪身/握把），挂在 `WeaponAnchor`（Head 下），右下角 CS 式持枪位
- `Assets/Models/Hands/FpHands.tscn`：Box 拼装手部（左右手），持枪时显示
- 后坐力视觉反馈：开火时视模型沿 Z 轴小幅后坐位移 + 相机 recoil（2.6）
- 切枪时视模型部署动画占位（位移/旋转插值，简单 tween）

## 3. 技术栈与版本锁定

与 M0 一致：Godot 4.7.1 / GUT 9.7.1 / GDScript 4.x。无新依赖。

## 4. 全局约束（逐字复制，不得偏离）

- 项目名称 `Trigger Echo`；主场景 `res://Levels/Main/L_Main.tscn`
- 纯离线：工程内不得出现任何网络调用
- 物理层：`1=Objects` / `2=Player`（命中判定只对 Objects 层，玩家/队友/AI 在 Player 层不被打）
- 输入动作：保留 M0 全部 11 个原名，新增 `fire reload aim weapon_1 weapon_2 weapon_3 weapon_4 next_weapon`
- 武器数值唯一来源 `weapon_*.tres`（Weapon_Resource），测试与调参作用于资源文件，**禁止硬编码**（企划书 §4.2.5）
- CS2 数值基准：AK 36/×4.0/600RPM/30+120/2.4s/215u；Glock 30/×4.0/400RPM/20+80/2.3s/240u；匕首 40/25/65/背刺180/0.4s+1.0s/250u；M67 98/57/引信1.5s/半径6m/245u（全部对齐 CS2 2026-03-18 补丁，参考 cs2-weapon-data.md）
- GUT 浮点断言用容差（陷阱 #8）；新代码不引入网络/外部资源
- 许可证：所有代码 MIT 兼容（参考 Godot4-FPS-Template 思路）；拼装模型全部自产（BoxMesh/CylinderMesh），零外部资产

## 5. 任务分解（每任务 2-5 分钟粒度，TDD）

### 任务 0：输入动作 + 武器资源骨架
- 新增 8 个输入动作（fire/reload/aim/weapon_1-4/next_weapon）到 project.godot
- `Weapon_Resource.gd`：字段（伤害/部位倍率/RPM/弹匣/备弹/换弹时间/射程/衰减曲线/后坐力表/移速/开火模式/ads/穿透/穿甲）+ 类型校验
- 四个 `weapon_*.tres` 数值文件（CS2 对齐值）
- 测试：资源字段默认值 + 文件加载（AK 36 伤等）
- **接口**：`Weapon_Resource`（可加载 .tres）

### 任务 1：WeaponCore 射击核心（TDD 核心）
- 开火流程：弹药检查 → 射速节流 → 后坐力应用 → hitscan 射线 → 命中部位判定 → 伤害结算（×4.0 头部/×1 躯干/×0.8 四肢）→ 距离衰减 → 弹着反馈
- 换弹：计时 + 丢弃弹匣剩余（CS2 规则）+ 可打断
- 后坐力：Set Pattern 表 / Random / 恢复
- 测试：单发伤害、爆头 144、衰减 0.96、换弹计时、弹匣空自动换弹、切枪打断换弹、后坐力偏移累计
- **接口**：`WeaponCore`（consumes Weapon_Resource；produces hit 事件）

### 任务 2：WeaponManager 切换状态机 + 移速联动
- 四槽位 + 状态机（HOLSTERED/DEPLOYING/ACTIVE/RELOADING/THROWING）
- 切枪（deploy 时间 / 中断换弹）+ 滚轮循环
- 弹药总账（各槽位独立备弹）
- 移速联动：`speed_modifier` 写入 MovementController（新增属性）
- 测试：切枪状态流、滚轮循环、移速联动值（AK 0.86/Glock 0.96/刀 1.0/M67 0.98）、换弹切枪中断
- **接口**：`WeaponManager`（consumes 4 资源；produces `weapon_switched` 事件）

### 任务 3：Head 接口扩展 + 开镜（ADS）
- `Head.add_recoil()` / `Head.set_ads()` / 灵敏度联动缩放
- AK 机瞄 ×1.5（FOV 缩放 + 散布收窄）
- 测试：recoil 叠加恢复、ads FOV 变化、灵敏度缩放
- **接口**：`Head`（add_recoil/set_ads）

### 任务 4：M67 投掷 + 爆炸
- 投掷流程：THROWING 状态 + 引信 + 抛物线弹道（简化）+ 爆炸（半径 6m 距离衰减 98/57/30）
- 右键取消投掷
- 测试：投掷计时、爆炸伤害衰减（2m 内 98 / 边缘 30）、取消投掷保留弹药
- **接口**：`Grenade`（物理体，爆炸后释放）

### 任务 5：持枪视模型 + 手部拼装
- `Assets/Models/Weapons/AK47_view.tscn` / `Glock18_view.tscn` / 匕首占位 / 手部
- WeaponAnchor 挂载 + 切枪视觉切换
- 测试：场景加载冒烟、Anchor 挂载、切枪时视模型切换
- **接口**：`WeaponAnchor`（承载视模型，切换信号）

### 任务 6：场景集成 + 手动冒烟
- L_Main 集成玩家持枪（WeaponManager 挂到 Player，预装载 4 资源）
- 添加测试靶子（Box + 命中反馈占位）
- 手动冒烟：WASD + 左键开火 + R 换弹 + 右键机瞄 + 1-4 切枪 + 滚轮
- 测试：集成冒烟（场景可加载、4 槽位资源挂载、开火触发命中）
- **接口**：L_Main（可玩场景）

### 任务 7：文档同步
- FEATURES.md（M1 功能标记 🟢 + 配件系统待开发项）/ PROGRESS.md（M1 记录 + 决策 9 配件策略）/ README.md（武器系统简介）
- 许可证登记（新引用：CS2 数值为机制参考不涉版权；无新代码借鉴）

## 6. 验证与测试

- 全部任务 TDD：RED → GREEN → REFACTOR
- 测试命令：`godot --headless -s addons/gut/gut_cmdln.gd`，退出码 0 = 全绿（保持 M0 14/14 不回归）
- 手动冒烟：有头模式验证（开火/换弹/切枪/机瞄/投掷手感）
- 数值验证：AK 爆头 144、躯干 4 发（36×4）；Glock 爆头 120、躯干 4 发（30×4）；M67 中心 98 不秒杀；移速 AK 0.86

## 7. 风险与对策

| 风险 | 等级 | 对策 |
|------|------|------|
| 后坐力表逐发分布公开数据缺失 | 中 | M1 采用 CS2 固定弹道近似拟合（前 3-5 发垂直 → 水平摆动），数值在 `weapon_*.tres` 可调 |
| 切枪/部署时间无实据 | 低 | CS2 惯例 0.3s（AK）±，参数化可调 |
| 配件系统后续加挂与现有资源冲突 | 低 | `Weapon_Resource` 预留 attachments 槽位（默认空），M1 不实现 |
| 手雷抛物线简化与企划物理弹道偏差 | 低 | 简化实现（重力抛体），物理弹道留 M5 |
| 拼装模型观感粗糙 | 低 | 已知取舍（决策：拼装化），M6 精化原位替换 |

## 8. 待校准项（M1 开发时定，写进任务 brief）

- AK-47 固定弹道逐发数组（前 3-5 发垂直上升量 / 水平摆动幅度，按 CS2 弹道图表近似）
- 切枪 deploy 时间（AK 0.3s 实测参考，其余按手感）
- 首发精度数值（AK 极高 = 首发射击散布极小角）
- 恢复速度 recovery_speed（° /s，按手感）
- 移动散布惩罚系数 move_spread_multiplier（CS2 running inaccuracy 参考：AK 182 vs standing 7，惩罚显著；具体值 .tres 参数化）
- 下蹲散布收窄系数 crouch_spread_multiplier（CS2 crouch tighter；建议 0.7，可调）

## 9. 体验改进增补（2026-08-07 用户体验反馈后定稿）

> 用户实机体验反馈：射击反馈差/换弹僵硬/切枪无动画/刀雷不可用/模型质感差。
> 参考学习：Dragon20C（程序化三通道动画，仅理念）/ MucurataFPS（MIT，投掷/爆炸结构）/ 本地 m1-src（动画驱动/反馈）。

### 9.1 投掷交互重构：M67 长按投掷 + 抛物线预览（**无限持雷**）

| 状态 | 输入 | 表现 |
|------|------|------|
| 切到 M67 | — | 手持手雷，可移动/跳跃 |
| **按住左键** | 持续按住 | **抛物线预览**（虚线弧线，实时预测落点）+ 引信计时；**无限持雷，无超时自动投出**（用户拍板） |
| 松开左键 | 释放 | 沿预览抛物线投出（真实 Grenade） |
| 按住右键 | 取消 | 抛物线隐藏 + 弹药返还 |
| 点击（按下即松） | — | 天然投出（按下瞬间持雷→松开出手，消除点击无反应竞态） |

- 抛物线预览：每物理帧沿投掷方向积分弹道（重力抛体），生成点列（30 点虚线），终点为落点；持雷时实时更新
- 参考：CS2 手雷抛物线预测（长按蓄力）/ Mucurata grenade 投掷结构

### 9.2 弹孔与命中反馈（30s 生命周期）

- **弹孔位置 = 实际射线命中点**——弹道已含全部"稳定性综合因素"（见 9.3），弹孔天然符合武器设定
- 弹孔 decal：命中点生成（贴合表面），**存在 30s 后自动消失**（用户拍板）；上限防刷屏（如 200 个，超出移除最旧）
- 命中反馈：靶子受击闪红 + 枪口闪光（0.1s 衰减）
- 参考：Dragon20C bullet_hole decal / prototype decal_requested

### 9.3 精度稳定性模型（弹孔"综合因素"落地）

| 状态 | 散布影响 | CS2 依据 |
|------|---------|---------|
| 静止站立 | 基础（first_shot_spread） | standing inaccuracy |
| **移动中** | **散布 ×N 惩罚**（速度 > 阈值；AK 惩罚明显，参考 CS2 running inaccuracy 182 vs 7） | CS2 running inaccuracy |
| **下蹲** | **散布收窄**（×0.7） | CS2 crouch tighter |
| 开镜（机瞄） | 散布 ÷ads_multiplier（已有） | CS2 scoped |
| 连发后坐力 | pattern/random 漂移（已有） | CS2 recoil pattern |

- 惩罚系数入 .tres 参数化（`move_spread_multiplier` / `crouch_spread_multiplier`）
- MovementController 提供 `is_moving`/`is_crouching` 状态供 WeaponCore 查询（接口扩展）

### 9.4 程序化武器动画（自研三通道，Dragon20C 理念）

- **kickback**：开火时视模型位移（Z 推近）+ 旋转（pitch 上跳），多通道合成，回弹可感知（已优化 0.2m/s）
- **sway**：鼠标移动时视模型位置/旋转跟随（摆动）
- **bob**：移动时步幅节奏上下/左右起伏
- 三通道独立计算后**合成**到 WeaponAnchor（position + rotation）
- 换弹动画：视模型下移+旋转换弹动作（与 reload_time 时长联动）
- 切枪部署动画：新旧武器位移/旋转插值过渡（deploy_time 联动）

### 9.5 近战完整实现（匕首）

- 左键挥击：前挥（0.15s）+ 后摇（0.3s）动画（视模型绕 Y 旋转）
- 伤害判定：扇形 1.5m/60°（躯干 40/连击 25/重刺 65/背刺 180）
- 挥击间隔 0.4s 轻 / 1.0s 重（右键重刺）

### 9.6 模型质感提升（几何拼装框架内）

- 枪模 3-4 部件 → **8-12 部件**（枪管/护木/机匣/弹匣/握把/枪托/准星/导轨），按真实枪械轮廓
- **多材质**：金属高光 / 深色聚合物 / 握把纹理 2-3 材质混用
- **手模**：手掌 + 5 指关节，持枪位贴合
- **统一标准**：即未来角色/敌人/队友/地图建模规范（Assets/Models 规范）

### 9.7 参考合规

- 🟢 MucurataFPS（MIT，已复制 m1-src）：投掷/爆炸结构
- 🟢 本地 m1-src（MIT）：动画驱动/反馈模式
- ⚪ Dragon20C（无许可证）：**仅学习三通道合成理念，代码自研**

### 9.8 手雷爆炸效果（完整实现）

- **爆炸视觉**（参考 Mucurata explosion.gd，MIT）：
  - GPUParticles3D 火花粒子（短时喷射，0.5s）
  - OmniLight3D 闪光（light_energy 8.0 → 0 衰减，1.5s 生命周期）
  - 冲击波环（扩散圆环 mesh，0.3s 放大+淡出）
- 爆炸生命周期 1.5s 后 queue_free；位置 = Grenade 爆炸点
- 伤害结算保持（98/60/30 + collider 去重）

### 9.9 测试环境：无限弹药/手雷（供测试版）

- `cheats` 调试开关（L_Main 默认开启，正式版关闭）：**弹药无限**（弹匣打空自动补满、备弹无穷）+ **手雷无限**（投出后自动补 1 枚）
- 目的：反复体验射击/投掷手感不打断测试流
- 实现：WeaponCore 加 `infinite_ammo` 标志（切枪/换弹路径时自动补弹）；M67 投出后自动 `refund_throw` 等价补弹
- 正式版（M6 导出）关闭该开关

### 9.10 敌人模型资产 + 靶场训练场景（2026-08-07 用户追加）

**敌人模型**（几何拼装，同质提升标准）：
- 参考：成熟项目敌人建模（几何风 FPS 项目——polyblast-arena 程序化几何资产管线 / MucurataFPS enemy 结构，MIT 可参考）
- 拼装：躯干 + 头 + 四肢（Box/Capsule 组合），多材质（服装色/肤色/装备）
- **手持各种武器表现**：敌人模型带武器挂点，可持 4 种武器（AK/Glock/刀/M67 视模型复用或简化版），持枪姿态（双臂前伸持枪）

**靶场训练场景**（测试用，独立于 L_Main）：
- 进入即**随机生成 3 个敌人**，各持**随机武器**（4 种中随机）
- **敌人有血条**（头顶 UI 或 HUD 列表，100HP，受击更新）
- **不移动**（训练桩，无 AI 寻路/行为——M3 才做 AI）
- **碰撞体积**：每个敌人有碰撞体（胶囊），**敌人之间不可重叠**（生成时碰撞检测排布）
- **刷新排布**：生成时分散排布（间隔 ≥ 1.5m，避免重叠）
- **全倒后 1s 刷新**：3 个敌人全部被击倒（HP ≤ 0）→ 1 秒后随机再生成 3 个（新位置 + 新武器）
- 训练场景目的：体验射击/换弹/切枪/投掷对目标的效果 + 测试武器伤害平衡

**与 M3 的关系**：训练场敌人是**静态桩**（无 AI），M3 才实现寻路/感知/对枪；但敌人模型/血条/伤害结算层在此建立，M3 复用。

## 10. 改进任务分解（TDD，在 M1 分支继续）
