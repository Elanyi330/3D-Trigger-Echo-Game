#!/bin/bash
# Trigger Echo 会话结束自动提交+推送 hook
# 由 Stop 事件触发，提交全部变更并推送到 GitHub（Elanyi330/3D-Trigger-Echo-Game）

set -u
PROJECT_DIR="$HOME/Projects/Trigger-Echo"

# 1. 确保在项目目录（防止其他项目触发时误提交）
cd "$PROJECT_DIR" || { echo "自动推送：找不到项目目录 $PROJECT_DIR" >&2; exit 0; }

# 2. 无 git 仓库则跳过
[ -d .git ] || { echo "自动推送：$PROJECT_DIR 不是 git 仓库，跳过" >&2; exit 0; }

# 3. 提交全部变更
git add -A
if git diff --cached --quiet; then
    echo "自动推送：工作区无变更，跳过提交" >&2
else
    git commit -m "feat: 更新 Trigger Echo 项目文件" >/dev/null 2>&1 && \
        echo "自动推送：已提交 $(git rev-parse --short HEAD)" >&2
fi

# 4. 推送到 GitHub（专用 deploy key，无本地提交也推，保持远程同步）
if git push >/dev/null 2>&1; then
    echo "自动推送：已推送 $(git rev-parse --short origin/main) 到 GitHub" >&2
else
    echo "自动推送：推送失败，请检查网络或 SSH key" >&2
fi

exit 0
