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
