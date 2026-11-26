#!/bin/zsh
# 编译并打包成 build/Toolula Tidy.app
set -e
cd "$(dirname "$0")"
# 默认编译通用版 (Apple 芯片 + Intel 都能用); FAST=1 ./build_app.sh 只编译本机芯片, 快一点
if [[ -n "$FAST" ]]; then ARCHS=(); else ARCHS=(--arch arm64 --arch x86_64); fi
swift build -c release "${ARCHS[@]}"
BIN="$(swift build -c release "${ARCHS[@]}" --show-bin-path)/ToolulaCleaner"
VERSION="$(cat VERSION)"
APP="build/Toolula Tidy.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/ToolulaCleaner"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# 界面翻译: 先检查有没有缺的翻译 (只提醒, 不中断), 再生成各语言的 Localizable.strings
/usr/bin/python3 Localization/extract.py --check >/dev/null 2>&1 || echo "⚠️  有缺少或不对的翻译，运行 Localization/extract.py --check 查看"
/usr/bin/python3 Localization/make_strings.py "$APP/Contents/Resources" >/dev/null
for f in "$APP"/Contents/Resources/*.lproj/Localizable.strings; do plutil -lint "$f" >/dev/null || { echo "翻译文件格式错误: $f"; exit 1; }; done
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Toolula Tidy</string>
  <key>CFBundleDisplayName</key><string>Toolula Tidy</string>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleLocalizations</key><array><string>zh-Hans</string><string>zh-Hant</string><string>en</string><string>ja</string><string>ko</string><string>de</string><string>fr</string><string>es</string><string>pt</string><string>ru</string></array>
  <key>CFBundleAllowMixedLocalizations</key><true/>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleIdentifier</key><string>com.toolula.cleaner</string>
  <key>CFBundleExecutable</key><string>ToolulaCleaner</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSDownloadsFolderUsageDescription</key><string>Find old files in Downloads that you haven’t used for a long time.</string>
  <key>NSDocumentsFolderUsageDescription</key><string>Find large files that take up space.</string>
  <key>NSAppleEventsUsageDescription</key><string>When an app needs administrator permission to uninstall, Finder is asked to move it to the Trash.</string>
  <key>NSDesktopFolderUsageDescription</key><string>Find large files that take up space.</string>
</dict></plist>
PLIST
# 有本地签名证书就用它: 签名固定, 重新编译后「完全磁盘访问权限」不会失效
SIGN_ID="-"
if security find-certificate -c "Toolula Local Signing" >/dev/null 2>&1; then SIGN_ID="Toolula Local Signing"; fi
codesign --force -s "$SIGN_ID" "$APP"
echo "signed with: $SIGN_ID"
echo "built: $APP ($VERSION, $(lipo -archs "$APP/Contents/MacOS/ToolulaCleaner"))"
