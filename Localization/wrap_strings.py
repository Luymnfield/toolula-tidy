#!/usr/bin/env python3
"""把 Swift 源码里所有带中文的字符串改成 L("...") 调用 (一次性工具, 也可以对新代码重复运行)。
   "已选 \\(n) 项" -> L("已选 %@ 项", "\\(n)")
跳过: 注释、已经在 L( 里的、enum 的原始值 (case x = "...")。"""
import re, sys, pathlib

CJK = re.compile(r'[一-鿿（），。：？「」]')

def parse_literal(s, i):
    """s[i] == '"'. 返回 (end_index_after_closing_quote, parts) ; parts: [('t', text) | ('e', expr_src)]"""
    assert s[i] == '"'
    i += 1; parts = []; buf = ''
    while True:
        c = s[i]
        if c == '\\' and s[i+1] == '(':
            if buf: parts.append(('t', buf)); buf = ''
            j = i + 2; depth = 1; start = j
            while depth:
                ch = s[j]
                if ch == '"':
                    j, _ = parse_literal(s, j); continue
                if ch == '(': depth += 1
                elif ch == ')': depth -= 1
                j += 1
            parts.append(('e', s[start:j-1])); i = j; continue
        if c == '\\':
            buf += s[i:i+2]; i += 2; continue
        if c == '"':
            if buf: parts.append(('t', buf))
            return i + 1, parts
        if c == '\n': raise ValueError('unterminated literal')
        buf += c; i += 1

def convert(src):
    out = []; i = 0; n = len(src); changed = 0
    while i < n:
        c = src[i]
        if src.startswith('//', i):                      # 行注释
            j = src.find('\n', i); j = n if j < 0 else j
            out.append(src[i:j]); i = j; continue
        if src.startswith('/*', i):
            j = src.find('*/', i) + 2; out.append(src[i:j]); i = j; continue
        if src.startswith('"""', i):
            j = src.find('"""', i + 3) + 3; out.append(src[i:j]); i = j; continue
        if c == '"':
            end, parts = parse_literal(src, i)
            lit = src[i:end]
            text = ''.join(p[1] for p in parts if p[0] == 't')
            before = ''.join(out)[-40:]
            already = re.search(r'\bL\(\s*$', before)
            enum_raw = re.search(r'\bcase\s+\w+\s*=\s*$', before) or re.search(r',\s*\w+\s*=\s*$', before)
            if CJK.search(text) and not already and not enum_raw:
                key = ''; args = []
                for kind, v in parts:
                    if kind == 't': key += v.replace('%', '%%')
                    else:
                        key += '%@'
                        inner, k = convert(v); changed += k
                        args.append('"\\(' + inner + ')"')
                out.append('L("' + key + '"' + ''.join(', ' + a for a in args) + ')'); changed += 1
            else:
                # 插值里可能还有中文
                if any(p[0] == 'e' and CJK.search(p[1]) for p in parts):
                    rebuilt = '"'
                    for kind, v in parts:
                        if kind == 't': rebuilt += v
                        else:
                            inner, k = convert(v); changed += k; rebuilt += '\\(' + inner + ')'
                    out.append(rebuilt + '"')
                else:
                    out.append(lit)
            i = end; continue
        out.append(c); i += 1
    return ''.join(out), changed

if __name__ == "__main__":
  for p in sys.argv[1:]:
      path = pathlib.Path(p); s = path.read_text()
      s = re.sub(r'String\(localized:\s*("(?:[^"\\]|\\.)*")\)', r'\1', s)   # String(localized: "x") -> "x"
      new, k = convert(s)
      if new != s: path.write_text(new)
      print(f'{path.name}: {k}')
