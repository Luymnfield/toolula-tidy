#!/bin/zsh
# 把 build/Toolula Cleaner.app 安装到 /Applications 并重新注册 (启动台、聚焦搜索里就能找到)
set -e
cd "$(dirname "$0")/.."
osascript -e 'quit app "Toolula Cleaner"' 2>/dev/null || true
for i in {1..20}; do pgrep -x ToolulaCleaner >/dev/null || break; sleep 0.5; done
rm -rf "/Applications/Toolula Cleaner.app"
ditto "build/Toolula Cleaner.app" "/Applications/Toolula Cleaner.app"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "/Applications/Toolula Cleaner.app"
echo "installed /Applications/Toolula Cleaner.app"
