# M0 实施计划 — 引擎骨架（第一人称移动 + 相机 + GUT）

> 日期: 2026-08-06
> 上游: 企划书 v1.0（定稿）→ 里程碑 M0
> 前置: 无（本计划即 M0 全部内容）

---

## 1. 目标

建立 Godot 4 项目骨架，集成 FirstPersonStarter 第一人称控制器（MIT），让玩家可在测试场景中移动、跳跃、观察，并建立 GUT 测试体系（TDD 贯穿后续全部里程碑）。**本里程碑不引入任何武器/地图/AI。**

## 2. 架构

```
Trigger Echo（Godot 4.7.1 项目）
├── project.godot            ← 应用配置：名称/主场景/输入映射/物理层/渲染
├── addons/gut/              ← GUT 9.7.1 测试框架插件
├── Player/
│   ├── MovementController.tscn/gd  ← CharacterBody3D 控制器（移植自 FirstPersonStarter，MIT）
│   ├── Head.tscn/gd                ← Node3D 头部（含 Camera3D），鼠标视角
│   ├── Sprint.gd                   ← 冲刺 + FOV 扩展
│   └── Player.tscn                 ← 组合场景（MC + Head + Sprint）
├── Levels/Main/
│   └── L_Main.tscn/gd              ← 测试场景：地面/墙/灯光/相机模式
├── test/unit/                      ← GUT 测试（每功能模块一个文件）
├── .gutconfig.json                 ← GUT 配置（测试目录/命令行退出码）
└── tools/setup_env.sh              ← 环境检查（Godot 二进制 / GUT 插件）
```

**端口说明**：ProjectSettings 全局输入映射（move_forward 等），控制层无自定义全局单例。

## 3. 技术栈与版本锁定

| 组件 | 版本 | 来源 | 说明 |
|------|------|------|------|
| Godot | **4.7.1-stable** | godotengine/godot 官方 release | macOS universal 包，LTS 系最新稳定版，锁定不用 dev 版 |
| GUT | **9.7.1** | bitwes/Gut release | 明确兼容 Godot 4.7 |
| FirstPersonStarter | **main (2026-08 拉取)** | Whimfoome/godot-FirstPersonStarter | MIT；Kenney 贴图 CC0，合规 |
| GDScript | 4.x（随 Godot 4.7） | — | — |

## 4. 全局约束（逐字复制，不得偏离）

- 项目名称必须为 `Trigger Echo`；主场景 `res://Levels/Main/L_Main.tscn`
- 纯离线：工程内不得出现任何网络调用（HTTP/TCP/WebSocket）
- 物理层：`1=Objects`（默认层，地面/墙）、`2=Player`（玩家，源自 FirstPersonStarter）
- 输入动作名（保留 FirstPersonStarter 原名，不重命名）：`move_forward` `move_back` `move_left` `move_right` `jump` `sprint` `change_mouse_input` `look_up` `look_down` `look_left` `look_right`
- 按键：WASD 移动 / Space 跳 / Shift 冲刺 / Esc 退出 / Shift+F1 释放鼠标 / 左键点击重新捕获（HTML5 兜底，保留）
- 移动手感参数（FirstPersonStarter 默认值）：`speed=10` `acceleration=8` `deceleration=10` `jump_height=10` `gravity_multiplier=3.0` `air_control=0.3` `mouse_sensitivity=2.0` `y_limit=90.0`
- GUT 测试目录 `res://test/unit/`；命令行运行：`godot --headless -s addons/gut/gut_cmdln.gd`，退出码 0=全部通过
- `.gitignore` 保持现有内容（`.godot/` 等），godot 4.7 生成的 `.godot/` 目录不提交
- 许可证：FirstPersonStarter 源码内嵌需保留其 MIT LICENSE 头；新增原创代码无版权问题

## 5. 环境搭建（一次性）

### 5.1 Godot 安装（手动，不在子代理任务内）
```bash
# 下载 Godot_v4.7.1-stable_macos.universal.zip
# 解压后拖入 /Applications/ 或保留在本地，确保 `godot` 命令可执行：
#   ln -s /Applications/Godot.app/Contents/MacOS/Godot /usr/local/bin/godot
godot --version   # 验证输出 v4.7.1-stable
```

### 5.2 GUT 插件获取（拉取任务）
- 下载 `https://github.com/bitwes/Gut/releases/download/v9.7.1/Gut-v9.7.1.zip`（或 repo main 的 addons/gut 目录）
- 解压出 `addons/gut/` 放入项目根

### 5.3 工具脚本
- `tools/setup_env.sh`（本计划自带，任务 0 实现）：
  - 检查 `godot` 命令存在（缺失则打印安装指引并以非零退出）
  - 检查 `addons/gut/` 存在（缺失则打印拉取指引并以非零退出）

---

## 6. 任务分解（每任务 2-5 分钟粒度）

### 任务 0：环境与骨架
**输出接口**：`project.godot`（配置正确）、`tools/setup_env.sh`（可执行）、`res://addons/gut/`（已放置）、`.gutconfig.json`、`README.md` 开发部分更新

**步骤**：
1. 创建 `project.godot`：
   - `[application]`：`config/name="Trigger Echo"`、`run/main_scene="res://Levels/Main/L_Main.tscn"`、`config/features=PackedStringArray("4.2")`、`config/icon` 用 Godot 默认图标（若无自绘图标先省略）
   - `[input]`：`move_forward`（W/↑/手柄轴-1）、`move_back`（S/↓/手柄轴+1）、`move_left`（A/←/手柄轴-1）、`move_right`（D/→/手柄轴+1）、`jump`（Space/手柄A）、`sprint`（Shift/手柄RB）、`change_mouse_input`（Shift+F1）、`look_up/look_down/look_left/look_right`（手柄右摇杆，键位同 FirstPersonStarter 默认）
   - `[layer_names]`：`3d_physics/layer_1="Objects"`、`3d_physics/layer_2="Player"`
   - `[rendering]`：`renderer/rendering_method="mobile"`、`anti_aliasing/quality/msaa_3d=1`
2. 放置 GUT：`addons/gut/` 完整目录 + `project.godot` 的 `[editor_plugins] enabled=PackedStringArray("res://addons/gut/plugin.cfg")`
3. 创建 `tools/setup_env.sh`（见 5.3），`chmod +x`
4. 创建 `.gutconfig.json`：
   ```json
   {
     "dirs": ["res://test/unit"],
     "log_level": 1,
     "should_exit": true
   }
   ```
   （`should_exit=true` 保证命令行跑完即退出、以测试结果作为退出码）
5. 创建空 `test/unit/.gitkeep`

**验证**：
- `bash tools/setup_env.sh` 退出码 0
- `godot --headless --path . --quit` 无报错退出 0（此时主场景尚不存在会告警，属预期，见任务 2 后复验）

### 任务 1：GUT 冒烟测试（TDD 首个 RED→GREEN）
**消费接口**：任务 0 的 `.gutconfig.json`、`addons/gut/`
**输出接口**：`test/unit/test_smoke.gd`（GUT 可运行）

**步骤**：
1. 写测试（RED，先于一切实现）：
   ```gdscript
   # test/unit/test_smoke.gd
   extends GutTest

   func test_smoke() -> void:
       assert_eq(2 + 2, 4, "GUT 冒烟：基础断言可运行")
   ```
2. 运行：`godot --headless -s addons/gut/gut_cmdln.gd` → 确认测试被收集并**通过**（GUT 自证可运行）
3. 若失败：排查 GUT 安装/配置，不得跳过

**验证**：
- 命令退出码 0，输出包含 `test_smoke` 通过记录

### 任务 2：FirstPersonStarter 控制器移植（M0 核心）
**消费接口**：任务 0 的 project.godot（输入映射/物理层/渲染已配）
**输出接口**：
- `Player/MovementController.tscn`（CharacterBody3D，collision_layer=2，collision_mask=3，capsule 碰撞）
- `Player/MovementController.gd`（`class_name MovementController`，`@export speed=10` 等 6 参数）
- `Player/Head.tscn` + `Player/Head.gd`（`class_name` 不冲突；`@export mouse_sensitivity=2.0`、`@export y_limit=90.0`；`cam` 对外可读）
- `Player/Sprint.gd`（`@export sprint_speed=16`、`@export fov_multiplier=1.05`）
- `Player/Player.tscn`（组合 MC + Head + Sprint）
- `Levels/Main/L_Main.tscn` + `L_Main.gd`（测试场景）
- **移植路径 `res://Player/`、`res://Levels/Main/`，场景文件名与结构保持与原项目一致**

**步骤**（源码依 `docs/superpowers/reference/fps-starter-src/` 已存副本，逐字核对移植）：
1. `Player/MovementController.gd`：完整拷贝（类名/导出参数/物理过程/加速度模型全保留），确认 `class_name MovementController`
2. `Player/MovementController.tscn`：完整拷贝，capsule 碰撞 + collision_layer=2/mask=3 + floor 参数
3. `Player/Head.gd`/`Head.tscn`：完整拷贝（`extends Node3D`，`cam_path` 默认 `Camera`，`_ready` 中灵敏度/限位转换，`_input` 鼠标视角 + 手柄视角）
4. `Player/Sprint.gd`：完整拷贝（`@onready` 依赖 Head.cam）
5. `Player/Player.tscn`：完整拷贝组合
6. `Levels/Main/L_Main.tscn`：创建测试场景——地面（BoxMesh，Objects 层）+ 4 面墙围合 + DirectionalLight3D + 实例化 Player + `L_Main.gd`（鼠标捕获逻辑）
7. 将 `L_Main.gd` 的 `OS.is_debug_build()` 判断保留（导出包不启用 Esc 退出）
8. 确认输入动作名与脚本一致（move_forward/jump/sprint/change_mouse_input）

**验证**（每项必须真实运行）：
- `godot --headless --path . --quit` 退出 0，无场景加载错误
- `godot --headless --path . --quit-after 60`（运行 60 物理帧）退出 0，无运行时脚本错误
- 有头模式手动冒烟（用户执行）：运行 `godot --path .`，WASD 移动 / Space 跳 / Shift 冲刺 / 鼠标环视 / Esc 退出正常

### 任务 3：控制器行为测试（TDD：RED → GREEN，控制层只测纯逻辑）
**消费接口**：任务 2 的 `Player/MovementController.gd`
**输出接口**：`test/unit/test_controller.gd`（通过，退出码 0）

**步骤**：
1. **先写失败测试**（RED）——测试通过 `Input.action_press()` 注入输入 + `MovementController._physics_process(delta)` 单帧推进：
   ```gdscript
   # test/unit/test_controller.gd
   extends GutTest

   var controller: MovementController

   func before_each() -> void:
       controller = MovementController.new()
       add_child_autofree(controller)

   func test_initial_state() -> void:
       assert_eq(controller.speed, 10, "默认移动速度 = 10")
       assert_eq(controller.jump_height, 10, "默认跳跃高度 = 10")

   func test_jump_impulse() -> void:
       # 无条件分支先行测试：跳跃只影响 velocity.y，不依赖 is_on_floor
       Input.action_press("jump")
       controller._physics_process(1.0 / 60.0)
       assert_eq(controller.velocity.y, 10.0, "jump 按下时 velocity.y = jump_height")
   ```
   - 测试先于被测试代码的完整实现；GUT `add_child_autofree` 自动清理节点
   - 若 `_physics_process` 依赖 `is_on_floor()` 分支导致 jump 不触发，**测试改为通过 `add_child` 真实物理场景（加入测试地面）**，不修改控制器逻辑
   - 此测试先运行**必须失败**（控制器尚未移植或跳转条件未满足），确认失败原因正确（不是拼写错误）
2. **最小实现使通过**（GREEN）：移植控制器完整实现（若尚未完成则补全）
3. 运行全部测试：`godot --headless -s addons/gut/gut_cmdln.gd` → 全绿

**验证**：
- `test_jump_impulse` 先失败、后通过，且失败原因正确
- 全部测试通过，退出码 0

### 任务 4：性能与配置审查
**消费接口**：任务 2 全部产物
**输出接口**：审查记录（无代码变更）

**步骤**：
1. 运行时检查：任务 2 的 `--quit-after 60` 输出无性能告警、无脚本错误
2. `project.godot` 检查：渲染 mobile / msaa_3d=1（移动平台稳妥，macOS 可接受）
3. 输入映射复核：8 个动作键位与 FirstPersonStarter 默认一致
4. 检查 `.godot/` 被 gitignore 排除，`addons/gut/` 已提交

**验证**：以上各项逐一确认，无遗留

### 任务 5：M0 文档与交付检查
**消费接口**：任务 0-4 全部产物
**输出接口**：`README.md`（快速开始补实际命令）、`docs/PROGRESS.md`（M0 完成状态更新）

**步骤**：
1. `README.md`：更新"快速开始"为可执行命令：
   ```bash
   godot --path .                 # 运行游戏（WASD 移动 / Space 跳 / Shift 冲刺）
   godot --headless -s addons/gut/gut_cmdln.gd   # 运行全部测试
   ```
2. `docs/PROGRESS.md`：M0 行标记 🟢 完成 + 记录关键决策（Godot 4.7.1 锁定、GUT 9.7.1、控制器移植保留原输入动作名）
3. 删除本计划中任务 0 创建的 `test/unit/.gitkeep`（已有测试文件时不再需要）

**验证**：README 命令真实可运行；PROGRESS 更新正确

---

## 7. 里程碑验收标准（M0 完成定义）

1. `bash tools/setup_env.sh` 退出码 0
2. `godot --headless --path . --quit-after 60` 退出码 0，无脚本错误
3. `godot --headless -s addons/gut/gut_cmdln.gd` 退出码 0，测试全绿
4. 有头模式：玩家可移动/跳跃/观察/冲刺/退出（用户手动确认）
5. 无任何运行时网络调用（纯离线约束）

## 8. 风险与回退

| 风险 | 对策 |
|------|------|
| Godot 4.7.1 与 FirstPersonStarter（4.2 时代）API 不兼容 | 源码仅用稳定 API（CharacterBody3D/Input/Camera3D），4.2→4.7 无破坏性变更；若遇报错，按错误逐条修正（4.3+ 无相关破坏性变更） |
| GUT 9.7.1 与 4.7.1 有边界问题 | 回退 GUT 9.7.0；仍不行则回退 Godot 4.6.x + GUT 9.6.1（成对锁定） |
| Godot 未安装 | 任务 0 前手动安装（见 5.1），`tools/setup_env.sh` 会显式报错引导 |
| 测试环境无显示器（CI/headless） | 全部测试用 `--headless` 运行，无头可覆盖 |

## 9. 参考源码副本

- FirstPersonStarter 完整源码已保存至 `docs/superpowers/reference/fps-starter-src/`（7 文件：MovementController.gd/tscn、Head.gd/tscn、Sprint.gd、Player.tscn、L_Main.gd/tscn、project.godot 输入段），实现时以副本为准，禁止在线拉取
- GUT 安装说明（v9.7.1）：`docs/superpowers/reference/gut-install.md`
