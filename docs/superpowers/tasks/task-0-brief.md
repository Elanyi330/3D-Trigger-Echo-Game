# Task Brief — 任务 0：环境与骨架

> 实现工作目录: `/Users/elanyi/Projects/Trigger-Echo-m0`（git 分支 feat/m0-engine-skeleton）
> 计划来源: `/Users/elanyi/Projects/Trigger-Echo/docs/superpowers/plans/2026-08-06-m0-engine-skeleton.md` 任务 0

## 目标

在工作目录创建 Godot 4.7.1 项目骨架：`project.godot` 配置、`tools/setup_env.sh` 环境检查脚本、`.gutconfig.json`、`test/unit/` 目录、README.md 快速开始更新。

## 环境事实（已核验，不要怀疑）

- `godot` 命令可用（4.7.1.stable.official）—— 软链 `~/.local/bin/godot` → /Applications/Godot.app
- GUT 9.7.1 插件**已就位**：工作目录 `addons/gut/`（勿重复下载，禁止联网拉取）
- 参考源码副本：`/Users/elanyi/Projects/Trigger-Echo/docs/superpowers/reference/fps-starter-src/`（含 project.godot 原始文件，含完整 [input] 段）

## 交付文件（5 项）

### 1. `/Users/elanyi/Projects/Trigger-Echo-m0/project.godot`（新建）

- `[application]`：
  - `config/name="Trigger Echo"`
  - `run/main_scene="res://Levels/Main/L_Main.tscn"`
  - `config/features=PackedStringArray("4.2")`
  - `config/icon`：省略（无自绘图标）
- `[input]`：**从参考副本 `fps-starter-src/project.godot` 的 `[input]` 段完整复制**（move_forward/move_back/move_left/move_right/jump/sprint/change_mouse_input/look_up/look_down/look_left/look_right 共 11 个动作，一个不落，保持原键位）
- `[layer_names]`：
  - `3d_physics/layer_1="Objects"`
  - `3d_physics/layer_2="Player"`
- `[rendering]`：
  - `renderer/rendering_method="mobile"`
  - `anti_aliasing/quality/msaa_3d=1`
- `[editor_plugins]`：
  - `enabled=PackedStringArray("res://addons/gut/plugin.cfg")`
- 纯离线约束：配置中不得出现任何网络相关设置

### 2. `/Users/elanyi/Projects/Trigger-Echo-m0/tools/setup_env.sh`（新建，chmod +x）

```bash
#!/bin/bash
# Trigger Echo M0 环境检查
set -u
FAIL=0

if ! command -v godot >/dev/null 2>&1; then
    echo "❌ godot 命令未找到。安装指引："
    echo "   https://github.com/godotengine/godot/releases/download/4.7.1-stable/Godot_v4.7.1-stable_macos.universal.zip"
    echo "   解压后软链: ln -s /Applications/Godot.app/Contents/MacOS/Godot ~/.local/bin/godot"
    FAIL=1
else
    echo "✅ godot: $(godot --version 2>/dev/null || echo '(版本获取失败)')"
fi

if [ ! -d "addons/gut" ]; then
    echo "❌ addons/gut 不存在。GUT 9.7.1 安装指引见 docs/superpowers/reference/gut-install.md"
    FAIL=1
else
    echo "✅ GUT 插件: addons/gut 已就位"
fi

if [ $FAIL -eq 0 ]; then
    echo "✅ 环境检查通过"
else
    echo "❌ 环境检查失败，请按上述指引修复"
fi
exit $FAIL
```

### 3. `/Users/elanyi/Projects/Trigger-Echo-m0/.gutconfig.json`（新建）

```json
{
  "dirs": ["res://test/unit"],
  "log_level": 1,
  "should_exit": true
}
```

### 4. `/Users/elanyi/Projects/Trigger-Echo-m0/test/unit/.gitkeep`（新建空文件）

### 5. `/Users/elanyi/Projects/Trigger-Echo-m0/README.md`（更新"快速开始"段）

将现有"快速开始"代码块更新为：

```
# 1. 克隆仓库
git clone git@github.com-trigger-echo:Elanyi330/3D-Trigger-Echo-Game.git

# 2. 环境检查（需要 Godot 4.7.1）
bash tools/setup_env.sh

# 3. 运行游戏（M0 后：WASD 移动 / Space 跳 / Shift 冲刺）
godot --path .

# 4. 运行测试（GUT，headless）
godot --headless -s addons/gut/gut_cmdln.gd
```

同时更新"项目状态"表格 M0 行状态为 `🟡 开发中`。

## 验证步骤（必须全部真实执行）

1. `cd /Users/elanyi/Projects/Trigger-Echo-m0 && bash tools/setup_env.sh` → 退出码 0，输出两条 ✅
2. `cd /Users/elanyi/Projects/Trigger-Echo-m0 && godot --headless --path . --quit` → 退出码 0
   - ⚠️ 预期行为：主场景 `Levels/Main/L_Main.tscn` 尚不存在会打印错误告警——**这是预期，属正常**（任务 2 后复验消失）；但 `project.godot` 解析错误、输入映射报错则是真问题，必须修复
3. `godot --headless --path . --quit-after 60` → 退出码 0
4. 确认 `test/unit/` 目录存在且含 `.gitkeep`

## 报告格式

完成后报告（中文）：
- 状态：`DONE` / `DONE_WITH_CONCERNS` / `NEEDS_CONTEXT` / `BLOCKED`
- 每个交付文件的落实情况
- 验证步骤逐条输出（真实命令 + 退出码 + 关键输出）
- 任何偏离计划的说明
