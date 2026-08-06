# Trigger Echo — 项目约束

> 纯离线 3D 第一人称 5v5 竞技枪战游戏（玩家 + 9 AI）| Godot 4 | macOS 原生 App

## 项目路径
- 本地：`/Users/elanyi/Projects/Trigger-Echo/`
- 参考文档（Craft Drawing Search 四文档范本）：`/Users/elanyi/docs/项目核心参考四文档/`
- 项目企划书（最终设计规格，开发全程对照）：`docs/2026-08-06-trigger-echo-design.md`

## 开发约束
- **铁律遵守**：开发方法论（Superpowers：brainstorming → writing-plans → 子代理驱动 → TDD → 审查）见全局 `~/CLAUDE.md`，本项目文档不得与其冲突
- **纯离线**：不联网、不依赖服务器、无账号系统；不允许任何运行时网络请求
- **文档各司其职**：CLAUDE.md / FEATURES.md / PROGRESS.md / README.md 按文件名分工，同一信息不重复更新到多文档，除非确需跨文档引用；CLAUDE.md 只保留全局约束，保持最少 tokens 占用
- **改动同步文档**：功能完成或变更后，同步更新 FEATURES.md / PROGRESS.md / README.md（按各自职责，不重复）

## 技术栈
- Godot 4.2+（LTS 锁定，MIT）——引擎/寻路（NavigationAgent3D）/ 原生 macOS 导出
- 自研 GDScript：玩家控制器（参考 Whimfoome/godot-FirstPersonStarter）、武器系统（参考 chafmere/Godot4-FPS-Template）、AI 决策层（行为树 + 分层状态机）
- 测试：GUT 框架（TDD 全程）
- 参考项目索引：企划书第三节（直接组装 / AI 系统参考 / 机制学习参考 / 架构参考 / Web 参考）

## 合规红线（全链路许可证）
- 引擎 MIT（Godot 4）✅ 可内嵌
- 可直接内嵌代码：MIT / Zlib / BSD-3-Clause 参考项目
- **只读不抄**：GPL / AGPL / Valve 版权（泄露源码）项目，仅学习机制，不得复制代码与资产
- **资产合规**：美术/音频全部自产或 CC0；gdquest 4-FPS-arms 美术资产为 CC-BY-NC-SA 不可商用，仅可参考其代码
- 所有依赖与引用必须在 README.md 的"许可证合规"章节登记，新增借鉴必须同步登记

## 当前状态（2026-08-06）
企划阶段：设计文档（v0.1 草案）已产出，待用户确认 → 确认后进入 writing-plans 拆解 M0 任务 → 建 git 工作树 → 子代理驱动开发。
**里程碑规划**：M0 引擎骨架 → M1 武器系统 → M2 地图与模式 → M3 AI 基础 → M4 AI 进阶 → M5 武器全品类 → M6 打磨与发布。

## 技术陷阱（开发必读）
1. Godot 版本锁定 4.2+ LTS，勿跟随 master 分支 API 演进
2. NavigationAgent3D 需要先完成 navmesh 烘焙（地图几何完成后），否则寻路回退为直线
3. 武器数值唯一来源是 `weapon_*.tres` 资源配置（Weapon_Resource），测试与调参作用于资源文件，禁止硬编码数值
4. 霰弹枪为逐弹丸独立 raycast + 独立衰减结算，勿用单射线模拟
5. hitscan 命中判定用射线对物理层检测（参考 q1k3），投掷物走物理弹道
6. AI 感知层（视线/遮挡/听觉）与决策层分离，事件通过信号/黑板上报，禁止感知逻辑内嵌状态机
7. 回合状态机参考 CS gamerules 结构（读源码不抄代码），模式层为薄封装，共享移动/射击/回合核心
8. GUT 测试：数值断言（伤害/衰减/倍率）用容差或精确十进制，避免浮点误差误判
9. macOS 导出前清理：无许可证资产、未引用场景、调试输出
