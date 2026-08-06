# Task Brief — 任务 4：性能与配置审查

> 工作目录: `/Users/elanyi/Projects/Trigger-Echo-m0`（分支 feat/m0-engine-skeleton）
> 计划来源: `docs/superpowers/plans/2026-08-06-m0-engine-skeleton.md` 任务 4

## 目标

对 M0 全部产物做静态审查与运行时检查（无代码变更，仅审查记录）。输出审查结论供控制器决策。

## 审查范围

| 项 | 检查内容 | 判定标准 |
|----|----------|----------|
| 1. 运行时检查 | `godot --headless --path . --quit-after 60` 输出 | 无性能告警、无脚本错误，EXIT=0 |
| 2. project.godot 配置 | rendering 段 | `renderer/rendering_method="mobile"`、`anti_aliasing/quality/msaa_3d=1`（符合企划书"移动平台稳妥"决策） |
| 3. 输入映射 | project.godot [input] 段 | 11 个动作键位与 FirstPersonStarter 默认一致（对照 reference/fps-starter-src/project.godot） |
| 4. git 管理 | .gitignore | `.godot/` 被排除；addons/gut 已提交（任务 0 已提交 264 文件）；`git status` 无意外未跟踪文件 |
| 5. 纯离线 | 全目录 grep 网络相关 | 源码/场景无 HTTP/TCP/WebSocket 等运行时网络调用（NOTICE 中的 GitHub 链接文本除外，属文档） |
| 6. 许可证 | Player/NOTICE + 拷贝文件来源 | NOTICE 存在且内容正确；拷贝文件与参考副本一致（任务 2 已核，抽查即可） |
| 7. 目录结构 | 项目根 | 符合计划 §2 架构图（Player/ Levels/ test/unit/ tools/ addons/gut/） |

## 方法

- 静态检查用 grep/diff/ls 完成
- 运行时检查真实执行（命令 + 退出码）
- **不修改任何文件**（本任务是审查任务，唯一输出是报告）

## 报告格式

- 状态：PASS（全部通过）/ FAIL（列出问题）
- 7 项逐条：检查方式 / 证据 / 结论
- 问题按严重级排序（关键/重要/次要），附修复建议
