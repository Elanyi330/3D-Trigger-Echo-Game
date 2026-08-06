# Task Brief — 任务 2：FirstPersonStarter 控制器移植（M0 核心）

> 实现工作目录: `/Users/elanyi/Projects/Trigger-Echo-m0`（分支 feat/m0-engine-skeleton）
> 计划来源: `docs/superpowers/plans/2026-08-06-m0-engine-skeleton.md` 任务 2

## 目标

将 FirstPersonStarter（MIT）第一人称控制器完整移植到项目：Player 组合场景（MovementController + Head + Sprint）+ 测试场景 L_Main，实现 WASD 移动 / Space 跳 / Shift 冲刺 / 鼠标环视。

## 环境事实（已核验）

- godot 4.7.1 可用；GUT 9.7.1 已就位；project.godot 已含全部输入映射（move_forward 等 11 个动作）与物理层（1=Objects / 2=Player）与渲染配置
- **移植唯一来源**：`/Users/elanyi/Projects/Trigger-Echo/docs/superpowers/reference/fps-starter-src/`（8 个文件 + project.godot + LICENSE）。**以副本为准，禁止在线拉取、禁止凭记忆改写**
- 副本内容（已核验与 upstream main 一致）：
  - `Player/MovementController.gd` + `.tscn`（CharacterBody3D，collision_layer=2, collision_mask=3, capsule）
  - `Player/Head.gd` + `.tscn`（Node3D + Camera3D，鼠标/手柄视角）
  - `Player/Sprint.gd`（冲刺 + FOV 缩放）
  - `Player/Player.tscn`（组合 MC + Head + Sprint）
  - `Levels/Main/L_Main.gd`（鼠标捕获/退出逻辑）

## 交付文件（全部在 /Users/elanyi/Projects/Trigger-Echo-m0/ 下新建）

| 文件 | 来源 | 说明 |
|------|------|------|
| `Player/MovementController.gd` | 副本逐字拷贝 | 保持 `class_name MovementController` |
| `Player/MovementController.tscn` | 副本逐字拷贝 | capsule 碰撞 + layer 配置 |
| `Player/Head.gd` | 副本逐字拷贝 | |
| `Player/Head.tscn` | 副本逐字拷贝 | |
| `Player/Sprint.gd` | 副本逐字拷贝 | |
| `Player/Player.tscn` | 副本逐字拷贝 | |
| `Levels/Main/L_Main.gd` | 副本逐字拷贝 | |
| `Levels/Main/L_Main.tscn` | **新建**（副本无现成可用；参考副本同目录无 L_Main.tscn 时，按下述规格创建） | 测试场景 |

### L_Main.tscn 规格（新建）

- 根节点 `L_Main`（Node3D）挂 `L_Main.gd`
- **地面**：StaticBody3D（collision_layer=1, collision_mask=0）+ CollisionShape3D（BoxShape3D 尺寸约 20×1×20，位置 y=-0.5）+ MeshInstance3D（BoxMesh 20×1×20）
- **四周墙**：4 面 StaticBody3D 围合（建议高 4m），防止玩家走出地面——布局自定，确保 20×20 区域内无空隙
- **DirectionalLight3D**：rotation 约 (-45°, -30°, 0)，阴影开启（可选）
- **WorldEnvironment**：可选，无则跳过
- 实例化 `Player/Player.tscn`，位置 (0, 1, 0)（胶囊底部落地）

### 移植硬性要求

1. **源码逐字拷贝**：MovementController.gd / Head.gd / Sprint.gd 的代码与副本**逐字节一致**（grep 不搞创新、不"优化"原代码）
2. 场景文件（.tscn）中除 L_Main.tscn 外与副本逐字一致
3. **不改输入动作名**（副本已与 project.godot 完全对应）
4. 许可证：在 `Player/` 目录下添加 `NOTICE` 文件（内容见下），说明移植来源与 MIT 许可
   ```
   This directory contains code ported from:
   godot-FirstPersonStarter (https://github.com/Whimfoome/godot-FirstPersonStarter)
   License: MIT (see docs/superpowers/reference/fps-starter-src/LICENSE)
   Ported on 2026-08-06 for Trigger Echo (MIT)
   ```
5. 纯离线：无任何网络调用

## 验证步骤（必须全部真实执行）

1. `cd /Users/elanyi/Projects/Trigger-Echo-m0 && godot --headless --import` → 退出码 0（注册场景/脚本）
2. `godot --headless --path . --quit` → 退出码 0，**L_Main.tscn 缺失告警必须消失**（主场景现在存在）
3. `godot --headless --path . --quit-after 60` → 退出码 0，无脚本错误（60 物理帧模拟运行）
4. `godot --headless -s addons/gut/gut_cmdln.gd` → 退出码 0（冒烟测试仍全绿，1/1）
5. **逐字校验**：对每个拷贝的 .gd/.tscn 文件跑 `diff` 对照副本，报告差异（应为 0 或仅说明）
6. 有头模式手动冒烟（用户最后执行，不在本任务内）：运行游戏 WASD/Space/Shift/鼠标 正常

## 报告格式

- 状态：`DONE` / `DONE_WITH_CONCERNS` / `NEEDS_CONTEXT` / `BLOCKED`
- 交付文件清单 + 逐字校验 diff 结果
- 验证步骤逐条输出（真实命令 + 退出码 + 关键输出）
- L_Main.tscn 布局说明（尺寸/墙高/玩家位置）
- 任何偏离计划说明
