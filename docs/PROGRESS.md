# Trigger Echo — 开发进度报告

**报告日期：** 2026-08-06
**项目状态：** 企划书 **v1.0 定稿**（2026-08-06 用户确认）→ M0 实施计划已产出 → 待环境安装后进入子代理驱动开发

---

## 📋 开发约定

- 项目路径：`/Users/elanyi/Projects/Trigger-Echo/`
- 开发方法论（Superpowers）见全局 `~/CLAUDE.md`，流程不可跳过：brainstorming → using-git-worktrees → writing-plans → 子代理驱动开发 → TDD → code-review → finishing-branch
- 每个里程碑开发前，先精读企划书第三节参考项目主索引中对应模块的参考项目，写进任务 brief
- 企划书是最终设计规格，开发全程对照，数值以 `weapon_*.tres` 资源文件为准
- 许可证红线：只读 GPL/AGPL/Valve 版权项目（不抄代码），仅内嵌 MIT/Zlib/BSD 代码，资产自产或 CC0

### ⚠️ 技术陷阱（开发时必读）
1. **Godot 版本锁定 4.2+ LTS**：勿跟随 master 分支 API 演进，参考官方 godot-demo-projects 对应版本
2. **navmesh 先烘焙再寻路**：NavigationAgent3D 依赖地图烘焙完成的 navmesh，未烘焙会回退直线寻路；地图几何完成后第一时间烘焙
3. **武器数值唯一来源是资源文件**：`weapon_*.tres`（Weapon_Resource），测试与调参均作用于资源，禁止硬编码
4. **霰弹枪逐弹丸独立结算**：每颗弹丸独立 raycast + 独立衰减（0-8m=11 / 8-15m=8 / 15-20m=5），远距（>10m）命中弹丸数收缩至 3-4 颗，禁止单射线模拟
5. **hitscan 用射线对物理层检测**（参考 q1k3），投掷物走物理弹道，两类命中判定不混用
6. **AI 感知与决策分离**：感知（视线/遮挡/听觉）结果通过信号/黑板上报决策层，感知逻辑禁止内嵌状态机（参考 mtrebi/AI_FPS Sense-Think-Act）
7. **回合状态机读源码不抄代码**：CS gamerules 结构仅学习（Valve 版权），自研实现；模式层薄封装共享核心
8. **GUT 浮点断言**：伤害/衰减/倍率断言用容差或精确十进制（如 `assert_eq(damage, 100.0)` 前先 round），避免浮点误差误判
9. **macOS 导出前清理**：无许可证资产、未引用场景、调试输出；导出产物不得含网络调用
10. **FPS 手感参数单独成资源**：后坐力曲线/移动手感参数化（参考 godot4-fps-prototype），调参不碰代码

---

## ✅ 已完成工作

### 1. 企划调研（2026-08-06）
- 5 个方向并行 GitHub API 调研，约 50 个项目全部经过 star 数/许可证/更新时间实时核验
- 产出参考项目主索引（五类）：
  - 🏗️ 第一梯队（MIT 可内嵌）：FirstPersonStarter、Godot4-FPS-Template、BoomerShooter、godot4-fps-prototype、godot-demo-projects、godot-4-FPS-arms（代码）、FPS-Multiplayer-Template（剥离多人）
  - 🧠 AI 参考：recastnavigation、AI_FPS、yapb、BehaviorTree.CPP、Raven（Buckland）
  - ⚖️ 机制学习（只读）：Kisak-Strike、cstrike15_src、CS2-Bot-Improver、q3a_bot_backport、OpenArena、OpenJK、Quake3e、SmokinGuns
  - 🏗️ 架构参考（BSD）：Daemon、sour
  - 🌐 Web 思路：Claude-of-Duty、q1k3、enari-engine、pvp

### 2. 核心玩法设计（2026-08-06，已定稿）
- 双模式：目标点占点（可复活，先达 7 分胜）+ 经典团战（无复活，打满 7 局先胜 4 局）
- 七大武器类完整数值：AK-47「铁幕」/ MP5「蜂鸟」/ M870「碎颅」/ AWM「远山」/ Glock 17「迅捷」/ 战术匕首「回声」/ M67「轰鸣」
- 战斗基础规则：统一 100 HP、部位倍率（头 ×2.5 上限，狙击/霰弹 ×1.5 例外）、分段阶梯衰减、hitscan + 弹道
- 霰弹枪精细化规格：逐弹丸独立 raycast / 高斯锥角分布 / 逐弹丸独立衰减 / 远距弹丸收缩 / 近距 2m 全中
- 两张地图规格：大图「回声哨站」（占点）/ 小图「弹痕仓库」（团战）
- AI 分层设计：导航/感知/决策/反应/团队 五层 + 三档难度参数表
- 里程碑规划 M0-M6（引擎骨架 → 武器 → 地图模式 → AI 基础 → AI 进阶 → 武器全品类 → 打磨发布）

### 3. 交付物
- ✅ 设计文档 `docs/2026-08-06-trigger-echo-design.md`（**v1.0 定稿**，2026-08-06 用户确认）
- ✅ 核心四文档 `CLAUDE.md` / `FEATURES.md` / `PROGRESS.md` / `README.md` 初始化
- ✅ Git 仓库初始化（含 auto-push 钩子）

### 4. M0 实施计划（writing-plans，2026-08-06）
- ✅ 计划文档 `docs/superpowers/plans/2026-08-06-m0-engine-skeleton.md`：6 个任务（环境骨架 → GUT 冒烟 → 控制器移植 → 控制器测试 → 性能审查 → 文档交付），每任务带接口块与验证步骤
- ✅ 参考源码本地副本 `docs/superpowers/reference/fps-starter-src/`（FirstPersonStarter 8 文件 + LICENSE + project.godot，实现时禁止在线拉取）
- ✅ GUT 安装参考 `docs/superpowers/reference/gut-install.md`（版本对应表 4.2→9.x 全链路核验）
- ✅ 版本锁定：**Godot 4.7.1-stable**（官方最新稳定，2026-07-14 发布）+ **GUT 9.7.1**（明确兼容 4.7）+ FirstPersonStarter main（2026-08-06 拉取）

---

## 🔧 关键技术决策

### 决策 1: Godot 4 引擎（MIT）
- 对比：自研引擎（工作量爆炸）/ Unity（许可证收紧）/ Unreal（权重与许可复杂）
- 结论：Godot 4 MIT 零授权费、原生导出 macOS .app、NavigationAgent3D 官方寻路、GDScript 快速迭代

### 决策 2: 混合式 AI 而非纯行为树
- 对比：纯行为树（团队协同表达弱）/ 纯状态机（决策树膨胀难维护）
- 结论：五层分层（导航/感知/决策/反应/团队），决策层行为树 + 分层状态机结合，团队层参考 Q3 ai_team.c 角色分配思路

### 决策 3: 资源驱动武器（Weapon_Resource）
- 对比：代码硬编码数值（调参改代码）/ 外部 JSON（类型安全差）
- 结论：参考 Godot4-FPS-Template 资源驱动方案，`weapon_*.tres` 为数值唯一来源，测试与调参作用于资源文件，扩展新武器零代码改动

### 决策 4: 拟人化参数化实现三档难度
- 对比：独立 AI 逻辑三套（开发量 ×3）/ 调参复制三份配置
- 结论：难度 = 参数（反应时间/瞄准误差/压枪精度/感知范围），参考 CS2-Bot-Improver 人格参数思路，天然支持多档扩展

### 决策 5: hitscan 为主 + 投掷物弹道
- 结论：枪械统一 hitscan（参考 q1k3 射线判定），性能好、判定稳定；投掷物物理弹道（可反弹、可取消），两类判定严格分离

### 决策 6: 回合状态机自研（读源码不抄代码）
- 结论：CS gamerules 结构（Kisak-Strike/cstrike15_src）仅学习设计（倒计时/准备/进行/结算），自研实现规避 Valve 版权；模式层薄封装共享核心，双模式不翻倍开发量

---

## 📅 里程碑路线图

| 阶段 | 内容 | 交付物 | 状态 |
|------|------|--------|------|
| M0 引擎骨架 | Godot 4.7.1 项目 + FirstPersonStarter 集成 + GUT | 可移动/跳跃/观察的 FPS 场景 | 🔴 待开始（计划已产出，待环境安装） |
| M1 武器系统 | 资源驱动武器 + 射击判定 + 后坐力 | 可射击/换弹的 1 种主武器 | 🔴 待开始 |
| M1 武器系统 | 资源驱动武器 + 射击判定 + 后坐力 | 可射击/换弹的 1 种主武器 | 🔴 待开始 |
| M2 地图与模式 | 小图（团战）+ 大图（占点）基础布局 + 两种模式框架 | 双模式核心循环可玩 | 🔴 待开始 |
| M3 AI 基础 | 9 个 bot 寻路 + 感知 + 基础对枪（普通难度） | 可与 AI 对战 | 🔴 待开始 |
| M4 AI 进阶 | 团队协同 + 拟人化瞄准 + 三档难度 | AI 三档表现差异化 | 🔴 待开始 |
| M5 武器全品类 | 七大武器类各一款 + 携带规则 | 完整武器体系可玩 | 🔴 待开始 |
| M6 打磨与发布 | 平衡性调优 + macOS .app 导出 + 资产清理 | 可双击即玩的离线 App | 🔴 待开始 |

---

## 风险与对策跟踪

| 风险 | 等级 | 对策 | 状态 |
|------|------|------|------|
| AI 表现不真实（9 个 bot 是核心体验） | 高 | 分层 AI + 拟人化参数化，从简单到复杂迭代，参考项目提供现成思路 | 🟡 设计中已覆盖 |
| 双模式开发量翻倍 | 中 | 共享核心（移动/射击/回合框架），模式层薄封装 | 🟢 已定方案 |
| 武器七大类数值平衡 | 中 | 全部参数化配置，TDD 测试驱动调参 | 🟢 已定方案 |
| 资产合规 | 低 | 全部自产/CC0，规避 GPL 资产；代码层只读 GPL 项目 | 🟢 已定方案 |
| Godot 4 API 演进 | 低 | 锁定 4.2+ LTS 版本，参考官方 demo 项目 | 🟢 已定方案 |

---

## 下一步

1. ~~用户确认企划书~~ ✅ **已定稿（2026-08-06）**
2. ~~调用 writing-plans 技能拆解 M0 任务~~ ✅ **计划已产出**
3. **安装 Godot 4.7.1 环境**（手动，见计划 §5.1：下载 universal 包 → 软链 `godot` 命令 → `godot --version` 验证）
4. 建立 git 工作树 → 按计划任务 0-5 子代理驱动开发（TDD 贯穿，每任务两阶段审查）
