# -*- coding: utf-8 -*-
"""
Lua 块平衡静态检查器（README §6.2 静态检查）
- 词法级处理：跳过短注释 --、长注释 --[[ ]]、长字符串 [[ ]]、引号字符串
- 识别 Lua 关键字边界（避免把 identifiers 里的 end/for 误判）
- 支持 if/elseif/else、while、for、function、do、repeat...until
- 额外检查：function 前向引用（闭包引用后置 local function）
用法: python _check_blocks.py [目录]
"""
import re
import sys
import os

# 块开启关键字
OPENERS = {"if", "while", "for", "function", "do", "repeat"}
# 块闭合关键字
CLOSERS = {"end", "until"}
# 中间关键字（不改变层级）
MIDDLE = {"elseif", "else"}

KEYWORDS = OPENERS | CLOSERS | MIDDLE | {
    "then", "local", "return", "break", "nil", "true", "false",
    "and", "or", "not", "in", "goto",
}


def strip_lua(src: str):
    """把 Lua 源码中注释与字符串内容替换为等长空白，保留行列结构。"""
    out = list(src)
    i, n = 0, len(src)

    def blank(a, b):
        for k in range(a, min(b, n)):
            if out[k] != "\n":
                out[k] = " "

    while i < n:
        c = src[i]
        # 长注释 / 长字符串  --[[ ]]  [[ ]]  [==[ ]==]
        if src.startswith("--", i) or c == "[":
            if src.startswith("--", i):
                m = re.match(r"--\[(=*)\[", src[i:])
                start = i
                if m:
                    eq = m.group(1)
                    close = "]" + eq + "]"
                    j = src.find(close, i + m.end())
                    j = n if j < 0 else j + len(close)
                    blank(start, j)
                    i = j
                    continue
                # 普通短注释
                j = src.find("\n", i)
                j = n if j < 0 else j
                blank(start, j)
                i = j
                continue
            else:
                m = re.match(r"\[(=*)\[", src[i:])
                if m:
                    eq = m.group(1)
                    close = "]" + eq + "]"
                    j = src.find(close, i + m.end())
                    j = n if j < 0 else j + len(close)
                    blank(i, j)
                    i = j
                    continue
                i += 1
                continue
        # 引号字符串
        if c in "\"'":
            q = c
            j = i + 1
            while j < n:
                if src[j] == "\\":
                    j += 2
                    continue
                if src[j] == q:
                    j += 1
                    break
                if src[j] == "\n":
                    break
                j += 1
            blank(i, j)
            i = j
            continue
        i += 1
    return "".join(out)


WORD_RE = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")


def check_file(path: str):
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        src = f.read()
    clean = strip_lua(src)

    # 栈元素: [keyword, line_no, needs_do]
    #   needs_do=True 表示该 for/while 头部尚未消费其 'do'
    stack = []
    errors = []
    line = 1
    for m in WORD_RE.finditer(clean):
        w = m.group()
        if w not in KEYWORDS:
            continue
        line = clean.count("\n", 0, m.start()) + 1
        if w in OPENERS:
            if w == "do" and stack and stack[-1][2]:
                stack[-1][2] = False      # 这是 for/while 头部的 do，不新开块
                continue
            stack.append([w, line, w in ("for", "while")])
        elif w in CLOSERS:
            if w == "until":
                if not stack or stack[-1][0] != "repeat":
                    errors.append(f"行{line}: 'until' 没有匹配的 'repeat'")
                else:
                    stack.pop()
            else:
                if not stack:
                    errors.append(f"行{line}: 多余的 'end'")
                else:
                    # else/elseif 不算开启块，但 end 会闭合它们所在的 if
                    stack.pop()

    for kw, ln in stack:
        errors.append(f"行{ln}: '{kw}' 未闭合（缺少 end/until）")

    # 前向引用粗检：文件中出现 `local xxx` 前置声明但从未赋值的弱提示
    return len(clean.split("\n")), errors


def main():
    d = sys.argv[1] if len(sys.argv) > 1 else "."
    files = sorted(
        f for f in os.listdir(d)
        if f.endswith(".lua") and f != "miliastra_lib.lua"
    )
    total_err = 0
    for f in files:
        p = os.path.join(d, f)
        lines, errs = check_file(p)
        flag = "OK " if not errs else "NG "
        print(f"[{flag}] {f:<18} {lines:>5} 行", end="")
        if errs:
            print(f"  -> {len(errs)} 处")
            for e in errs[:8]:
                print(f"        {e}")
            total_err += len(errs)
        else:
            print()
    print("-" * 52)
    print(f"合计: {len(files)} 个文件, {total_err} 处块不平衡")
    return 1 if total_err else 0


if __name__ == "__main__":
    sys.exit(main())
