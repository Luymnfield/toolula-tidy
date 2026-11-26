#!/bin/zsh
# 运行全部测试: 单元测试 + 翻译检查. 改代码后、发布前都跑一遍
set -e
cd "$(dirname "$0")/.."
echo "== 单元测试 (在临时的假个人文件夹里进行, 不碰真实文件) =="
swift test 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -E "error:|Executed .* tests|Fatal" | tail -20
swift test >/dev/null 2>&1 || { echo "❌ 单元测试没通过"; exit 1; }
echo "== 翻译检查 =="
/usr/bin/python3 Localization/extract.py --check | tail -1
echo "✅ 全部通过"
