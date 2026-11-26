#!/bin/zsh
# 把 build/Toolula Tidy.app 安装到 /Applications 并重新注册 (启动台、聚焦搜索里就能找到)
set -e
cd "$(dirname "$0")/.."
osascript -e 'quit app "Toolula Tidy"' 2>/dev/null || true
for i in {1..20}; do pgrep -x ToolulaCleaner >/dev/null || break; sleep 0.5; done
rm -rf "/Applications/Toolula Tidy.app"
ditto "build/Toolula Tidy.app" "/Applications/Toolula Tidy.app"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "/Applications/Toolula Tidy.app"
echo "installed /Applications/Toolula Tidy.app"
