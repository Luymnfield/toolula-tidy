# Toolula Tidy

安全、快速的 macOS 清理工具（SwiftUI 原生 App，macOS 14+）。
先扫描给你看，确认了才清理；默认移到废纸篓，随时能撤销。

## 功能

- **清理**：应用缓存、日志与崩溃报告、开发者垃圾（Xcode / Homebrew / npm / pip 等）、浏览器缓存、下载里的旧文件、废纸篓、大文件
- **开发项目里的垃圾**：旧项目里的 `node_modules`、`.venv`、`target`、`build` 等（旁边要有对应的项目文件才算；30 天内改过的项目默认不勾选）
- **空间地图**：方块图显示空间都被谁占了，一层层点进去
- **重复文件**：先比大小，再比完整内容（SHA-256），每组至少留一份；开发项目里的文件默认不勾选
- **启动项**：列出登录 / 开机时自动运行的后台程序，一键开关；程序已经不存在的可以删掉
- **卸载应用**：连同设置、缓存、数据一起移到废纸篓；也能找出已删除应用留下的残留
- **内存**：内存压力、内存都用在哪、占用最多的应用（可退出）
- **撤销**：每次清理 / 卸载都能放回原处；没处理成功的项目逐项列出原因
- **10 种语言**，跟随系统或在设置里自己选，马上切换
- **快**：并行的 `getattrlistbulk` 扫描，完整扫描约 0.3 秒

## 安全原则

- 只动个人文件夹里允许的位置（缓存、日志等），系统文件和受保护的应用（如 Safari）不碰
- 删除前每一项都再检查一次位置
- 正在运行的应用和浏览器自动取消勾选；下载和大文件默认不勾选，永远只移到废纸篓

## 编译和安装

```bash
./build_app.sh          # 生成 build/Toolula Tidy.app
./scripts/install.sh    # 安装到「应用程序」
./scripts/make_dmg.sh   # 打包成 build/ToolulaTidy-<版本>.dmg
```

默认编译通用版（Apple 芯片 + Intel）；`FAST=1 ./build_app.sh` 只编译本机芯片，快一点。版本号写在 `VERSION` 文件里。

## 下载安装

在 GitHub 的 [Releases](../../releases) 里下载 DMG，打开后把 Toolula Tidy 拖进「应用程序」。
App 还没有苹果开发者签名，第一次打开会被拦下：到「系统设置 › 隐私与安全性」点「仍要打开」即可。

## 测试

```bash
./scripts/test.sh           # 单元测试 (在临时的假个人文件夹里进行) + 翻译检查
swift scripts/e2e.swift     # 真实打开 App、真实点击按钮的端到端测试 (需要「辅助功能」权限)
```

## 翻译

界面文字在代码里写成 `L("中文原文")`，翻译在 `Localization/translations.json`。
`Localization/extract.py --check` 检查缺少的翻译，编译时会自动提醒。

## 图标

图标由 `scripts/make_icon.swift` 生成（变色龙的形状取自 `Resources/icon_source.png`）：

```bash
swift scripts/make_icon.swift Resources/icon_source.png Resources   # 生成 Resources/toolula_tidy_icon.png
```

再用 `sips` 缩放成各个尺寸、`iconutil -c icns` 打包成 `Resources/AppIcon.icns`。

