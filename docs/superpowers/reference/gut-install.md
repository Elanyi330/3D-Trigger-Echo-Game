# GUT 9.7.1 安装与运行（Godot 4.7）

> 来源：https://github.com/bitwes/Gut （MIT）| 2026-08-06 核验

## 版本对应

| Godot | GUT |
|-------|-----|
| 4.7 | 9.7.1（推荐）/ 9.7.0 |
| 4.6 | 9.6.1 / 9.6.0 |
| 4.5 | 9.5.0 |
| 4.4 | 9.4.0 |

## 安装步骤

1. 下载：`https://github.com/bitwes/Gut/releases/download/v9.7.1/Gut-v9.7.1.zip`
   （或直接取 repo main 分支的 `addons/gut/` 目录）
2. 解压，将 `addons/gut/` 放入项目根目录
3. `project.godot` 启用插件：
   ```
   [editor_plugins]
   enabled=PackedStringArray("res://addons/gut/plugin.cfg")
   ```
4. 重启 Godot 使插件生效

## 命令行运行

```bash
godot --headless -s addons/gut/gut_cmdln.gd
```

- 退出码 0 = 全部测试通过（`--headless` 无头可跑，CI 友好）
- 测试目录配置 `.gutconfig.json`：
  ```json
  {
    "dirs": ["res://test/unit"],
    "log_level": 1,
    "should_exit": true
  }
  ```
- `should_exit=true`：跑完自动退出，结果作为退出码

## 测试语法要点（GDScript 4）

```gdscript
extends GutTest

func before_each() -> void:   # 每个测试前执行
    pass

func test_example() -> void:
    assert_eq(actual, expected, "消息")
```

- 测试函数必须以 `test_` 开头才会被发现
- `add_child_autofree(node)`：测试结束自动释放节点
- 断言：`assert_eq` / `assert_true` / `assert_false` / `assert_gt` / `assert_lt` 等
- 浮点断言注意精度：数值断言前先 round 或使用容差
