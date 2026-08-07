# Task 7 Brief — 文档同步（FEATURES / PROGRESS / README）

> 分支: `feat/m1-weapon-system`（工作树 `/Users/elanyi/Projects/Trigger-Echo-m1`）
> 计划: `docs/superpowers/plans/2026-08-06-m1-weapon-system.md` 任务 7（先读 §5 任务 7 + 文档职责分工）
> 前置: 任务 0-6 全部完成（武器系统实现完毕，测试 100+ 全绿）
> 方法: 无 TDD（文档任务），但必须**基于实际实现**（读代码/测试确认真实行为，不臆造）

## 工作环境
- 工作树: `/Users/elanyi/Projects/Trigger-Echo-m1`
- 参考: `/Users/elanyi/Projects/Trigger-Echo-m1/docs/CLAUDE.md`（文档职责分工：CLAUDE.md 全局约束 / FEATURES.md 功能清单 / PROGRESS.md 进度 / README.md 项目介绍，同一信息不重复更新到多文档）

## 交付内容（严格按计划 §5 任务 7）

### 1. `docs/FEATURES.md` 更新
- **M1 武器系统功能标记 🟢 已完成**：
  - 🟢 Weapon_Resource 资源配置（CS2 对齐数值：AK 36/×4.0/600RPM/30+120；Glock 30/×4.0/400RPM/20+80；匕首 40/背刺180；M67 98/引信1.5s/半径6m）
  - 🟢 四槽位携带体系 + 武器切换状态机（主×1 + 副×1 + 近战默认 + 投掷附加；HOLSTERED/DEPLOYING/ACTIVE/RELOADING/THROWING）
  - 🟢 hitscan 命中判定 + 伤害结算（头 ×4.0 / 躯干 ×1 / 四肢 ×0.8；分段阶梯衰减）
  - 🟢 后坐力系统（CS2 Recoil Pattern：固定弹道 Set Pattern + Random + 恢复）
  - 🟢 开镜/机瞄 ADS 框架（AK 机瞄 ×1.5，AWP 预留）
  - 🟢 移速联动（mobility/250：AK 0.86 / Glock 0.96 / 刀 1.0 / M67 0.98；下蹲豁免）
  - 🟢 投掷物（M67 抛物线 + 爆炸衰减 98/60/30 + 右键取消 + 切枪取消返还）
  - 🟢 拼装视模型资产体系（Assets/Models 分类：Weapons/Hands/Characters，零外部资产）
  - 🟢 弹药 HUD（CS 式 "30 / 120"）
- **配件系统标 🔴 待开发**（用户决策：瞄准镜/弹夹等枪械配件可自由装配，**后续环节**）：Weapon_Resource.attachments 槽位已预留，M1 默认基础款不带配件

### 2. `docs/PROGRESS.md` 更新
- M1 里程碑记录：任务完成表（0-7）+ 测试全绿数（以实际为准）+ 提交链
- **决策 9：配件系统（瞄准镜/弹夹）列入后续环节**（用户 2026-08-07）：Weapon_Resource.attachments 槽位预留，M1 AK-47 默认基础款
- **决策 10：全资产拼装化**（用户 2026-08-07）：武器视模型/手部/未来角色全部 BoxMesh/CylinderMesh 拼装，Assets/Models 分类，零版权风险，未来精细化原位替换
- 里程碑路线图：M1 🟢 完成
- 下一步：M2 地图与模式（小图团战 + 大图占点）

### 3. `README.md` 更新
- 武器系统段落：四款武器（AK-47/MP5/Glock-18/匕首/M67 每类一款，数值对齐 CS2）
- **操作键位表**（新增）：WASD 移动 / Space 跳 / Shift 下蹲 / 左键开火 / R 换弹 / 右键机瞄（AK）/ 1-4 切枪 / 滚轮循环 / M67 右键取消投掷
- 里程碑状态：M1 🟢

### 4. 许可证登记（README 合规章节）
- m1-src 参考（MIT）：Godot4-FPS-Template（chafmere）+ godot4-fps-prototype（Dodoveloper）——已登记为参考（本地副本 docs/superpowers/reference/m1-src/）

## 验证步骤
1. 三文档更新内容与**实际实现一致**（抽查关键数值：AK 36 / Glock 30 / M67 98；键位：fire 左键/reload R/aim 右键/weapon_1-4 数字）
2. 同一信息不重复跨文档（FEATURES 记功能 / PROGRESS 记进度决策 / README 记介绍）
3. git commit（工作树内）：`git add -A && git commit -m "docs: M1 任务7 文档同步（FEATURES/PROGRESS/README + 决策9/10）"`

## 完成报告
返回：DONE / DONE_WITH_CONCERNS / NEEDS_CONTEXT / BLOCKED
- 报告内容：更新的文件清单、关键数值抽查结果、与 brief 的偏差
