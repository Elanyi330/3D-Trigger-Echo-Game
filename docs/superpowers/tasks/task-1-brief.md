# Task Brief — 任务 1：GUT 冒烟测试

> 实现工作目录: `/Users/elanyi/Projects/Trigger-Echo-m0`（分支 feat/m0-engine-skeleton）
> 计划来源: `docs/superpowers/plans/2026-08-06-m0-engine-skeleton.md` 任务 1

## 目标

创建第一个 GUT 测试文件并跑通命令行测试流程（TDD 首个 RED→GREEN，自证 GUT 可运行）。

## 前置（已就位，不要重做）

- project.godot 含 `[editor_plugins] enabled=PackedStringArray("res://addons/gut/plugin.cfg")`
- addons/gut/ 完整插件（9.7.1）
- .gutconfig.json：`{"dirs": ["res://test/unit"], "log_level": 1, "should_exit": true}`

## 步骤

### 1. 写测试（这是第一个测试，先于任何游戏代码）

创建 `/Users/elanyi/Projects/Trigger-Echo-m0/test/unit/test_smoke.gd`：

```gdscript
# test/unit/test_smoke.gd
# GUT 冒烟测试：验证测试框架可运行、测试被收集、断言生效
extends GutTest

func test_smoke() -> void:
    assert_eq(2 + 2, 4, "GUT 冒烟：基础断言可运行")
```

### 2. 运行测试

```bash
cd /Users/elanyi/Projects/Trigger-Echo-m0 && godot --headless -s addons/gut/gut_cmdln.gd
```

期望：退出码 0，输出包含 test_smoke 通过记录（如 `Test: test_smoke` / `1 passed` / `[PASS]`）。

### 3. 若失败

- 排查 GUT 安装/配置（plugin.cfg 是否生效、.gutconfig.json 路径），不得跳过本任务
- 这是自证框架可用的关键环节

### 4. 清理

- 删除 `test/unit/.gitkeep`（任务 0 占位文件，已有真实测试文件后不再需要）—— 这是 brief 明确要求的一部分

## 验证步骤（必须真实执行）

1. `cd /Users/elanyi/Projects/Trigger-Echo-m0 && godot --headless -s addons/gut/gut_cmdln.gd; echo "EXIT=$?"` → EXIT=0，测试全绿
2. 连续运行两次确认稳定（无随机失败）
3. `ls test/unit/` → 无 .gitkeep，仅 test_smoke.gd
4. 有头模式冒烟（若环境支持）：`godot --path .` 按一次 Esc 退出，确认 GUT 插件在编辑器中无加载错误（可选，headless 已验证即可跳过）

## 报告格式

- 状态：`DONE` / `DONE_WITH_CONCERNS` / `NEEDS_CONTEXT` / `BLOCKED`
- 验证步骤逐条输出（真实命令 + 退出码 + 关键输出片段）
- 任何偏离计划说明
