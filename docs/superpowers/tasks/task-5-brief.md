# Task Brief — 任务 5：M0 文档与交付检查（最终任务）

> 工作目录: `/Users/elanyi/Projects/Trigger-Echo-m0`（分支 feat/m0-engine-skeleton）
> 计划来源: `docs/superpowers/plans/2026-08-06-m0-engine-skeleton.md` 任务 5

## 目标

M0 收尾：更新文档（README 复核 + PROGRESS.md M0 完成记录）、落实任务 4 的观察项说明、全量验证。

## 前置事实（已就位，不要重做）

- 任务 0：README.md 快速开始已更新（4 步命令）+ M0 行 `🟡 开发中`
- 任务 1：test/unit/.gitkeep 已删除（已有真实测试）
- 任务 2/3：Player 控制器 + L_Main 场景 + 6 测试全绿，均已提交

## 任务内容

### 1. `/Users/elanyi/Projects/Trigger-Echo-m0/docs/PROGRESS.md` 更新

读取当前文件（工作树版本 = 54f591a 时的最新版），完成以下修改：

a. **项目状态行**更新为：
   `**项目状态：** M0 引擎骨架 **完成**（2026-08-06）→ 待进入 M1 武器系统计划`

b. **里程碑路线图表** M0 行：
   - 状态列改为 `🟢 完成（2026-08-06）`
   - 交付物列改为 `可移动/跳跃/观察的 FPS 场景 + GUT 测试体系（6/6 全绿）`

c. **新增"已完成工作"小节**（追加到现有 ✅ 已完成工作列表末尾，编号 5）：
   ```
   ### 5. M0 引擎骨架（2026-08-06 完成）
   - ✅ Godot 4.7.1 项目初始化（project.godot：输入映射 11 动作 / 物理层 Objects+Player / mobile 渲染）
   - ✅ FirstPersonStarter 控制器移植（MIT）：Player/ 6 文件逐字拷贝 + NOTICE + 测试场景 L_Main（地面+四面墙+灯光+天空）
   - ✅ GUT 9.7.1 测试体系：冒烟 + MovementController 行为测试（TDD，6/6 全绿）
   - ✅ 环境脚本 tools/setup_env.sh + .gutconfig.json
   - 关键决策：Godot 4.7.1（最新稳定）+ GUT 9.7.1 成对锁定；输入动作名保留 FirstPersonStarter 原名；控制器源码逐字移植不做"优化"
   ```

d. **下一步**更新为：
   ```
   1. ✅ M0 引擎骨架完成（全部 6 任务 + 两阶段审查）
   2. M1 武器系统：writing-plans 拆解（资源驱动武器 + hitscan + 后坐力）→ 新工作树 → 子代理驱动开发
   ```

### 2. `/Users/elanyi/Projects/Trigger-Echo-m0/README.md` 复核

- 确认快速开始 4 步命令存在且准确（任务 0 已做）
- **补充一行**（任务 4 观察项 O2）：在"开发文档"列表或项目结构处注明 L_Main.tscn 为自建简化测试场景（参考副本场景引用的 Geometry/Materials 资源未随副本提供，故按 M0 规格重写）
- 检查"项目状态"表格 M0 行已是 🟡 开发中（**不改**——PROGRESS.md 才是完成记录，README 保持开发中直至合并后由控制器统一调整）

### 3. 全量验证（必须真实执行）

```bash
cd /Users/elanyi/Projects/Trigger-Echo-m0
bash tools/setup_env.sh            # EXIT=0
godot --headless --path . --quit-after 60   # EXIT=0 无错误
godot --headless -s addons/gut/gut_cmdln.gd # EXIT=0 全绿
```

### 4. 报告交付清单

列出所有改动文件 + 验证输出。

## 硬性约束

- 只改 README.md 与 docs/PROGRESS.md（及可能的 docs/CLAUDE.md 技术陷阱——**本次不需要**，任务 1 已记）
- 不改任何 Player/ Levels/ test/ 代码
- 中文文档，沿用既有文风（状态标记 🟢🟡🔴、✅、表格）

## 报告格式

- 状态：DONE / DONE_WITH_CONCERNS / NEEDS_CONTEXT / BLOCKED
- 改动文件清单（含 diff 摘要）
- 验证步骤逐条真实输出
- 偏离说明