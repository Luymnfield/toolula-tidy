#!/usr/bin/env python3
"""从源码里找出所有 L("...") 的中文原文 (翻译表的键), 带上出现的位置和那一行代码 (给翻译参考)。
用法: extract.py            -> 写 keys.json
      extract.py --check    -> 和 translations.json 对比, 列出缺少的翻译 / 不再使用的键 / 占位符数量不对的翻译"""
import json, pathlib, re, sys
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from wrap_strings import parse_literal

ROOT = pathlib.Path(__file__).resolve().parent.parent
LANGS = ["en", "zh-Hant", "ja", "ko", "de", "fr", "es", "pt", "ru"]
# 左侧栏 / 小标签: 空间很小, 译文要短
SHORT = {"应用缓存", "日志", "开发者", "浏览器", "下载", "废纸篓", "大文件", "卸载", "内存", "未扫描", "扫描中", 
         "很干净", "应用", "%@ 个", "压力%@", "正常", "偏高", "紧张", "剩 %@", "概览", "项目", "启动项", "登录时", "重复项", "空间", "清理", "%@ 个开启"}

def decode(raw):  # Swift 字符串字面量里的转义 -> 真实文字
    return json.loads('"' + raw.replace('\\(', '(') + '"')

def keys():
    found = {}
    for f in sorted((ROOT / "Sources").rglob("*.swift")):
        src = f.read_text()
        for m in re.finditer(r'\bL\(\s*"', src):
            q = m.end() - 1
            end, parts = parse_literal(src, q)
            raw = ''.join(p[1] for p in parts if p[0] == 't')
            k = decode(raw)
            line = src.count('\n', 0, q) + 1
            ctx = src.splitlines()[line - 1].strip()
            e = found.setdefault(k, {"key": k, "where": [], "context": ctx, "short": k in SHORT})
            e["where"].append(f"{f.name}:{line}")
    return list(found.values())

def placeholders(s):
    return len(re.findall(r'%(?:\d+\$)?@', s))

if __name__ == "__main__":
    ks = keys()
    if "--check" not in sys.argv:
        (ROOT / "Localization/keys.json").write_text(json.dumps(ks, ensure_ascii=False, indent=1))
        print(f"{len(ks)} keys -> Localization/keys.json ({sum(k['short'] for k in ks)} short)")
        sys.exit(0)
    tr = json.loads((ROOT / "Localization/translations.json").read_text())
    names = {k["key"] for k in ks}
    bad = 0
    for k in ks:
        for lang in LANGS:
            v = tr.get(k["key"], {}).get(lang)
            if not v:
                print(f"缺少翻译 [{lang}] {k['key']}  ({k['where'][0]})"); bad += 1
            elif placeholders(v) != placeholders(k["key"]):
                print(f"占位符数量不对 [{lang}] {k['key']} -> {v}"); bad += 1
    for k in tr:
        if k not in names: print(f"不再使用的键: {k}")
    print(f"检查完成: {len(ks)} 个键 × {len(LANGS)} 种语言, {bad} 个问题")
    sys.exit(1 if bad else 0)
