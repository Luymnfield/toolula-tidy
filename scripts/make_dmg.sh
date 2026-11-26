#!/bin/zsh
# 把 build/Toolula Tidy.app 打包成 DMG 安装包 (打开后把 App 拖进「应用程序」)
# 用法: ./build_app.sh && ./scripts/make_dmg.sh    → build/ToolulaTidy-<版本>.dmg
set -e
cd "$(dirname "$0")/.."
APP="build/Toolula Tidy.app"
[[ -d "$APP" ]] || { echo "先运行 ./build_app.sh"; exit 1; }
VERSION="$(cat VERSION)"
DMG="build/ToolulaTidy-$VERSION.dmg"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/Toolula Tidy.app"
ln -s /Applications "$STAGE/Applications"   # 拖到这里就是安装
rm -f "$DMG"
hdiutil create -quiet -volname "Toolula Tidy $VERSION" -srcfolder "$STAGE" -fs APFS -format ULFO "$DMG"
echo "dmg: $DMG ($(du -h "$DMG" | cut -f1))"
