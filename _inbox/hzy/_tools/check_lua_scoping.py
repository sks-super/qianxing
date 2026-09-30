# -*- coding: utf-8 -*-
"""
千星 Lua 工程 · 局部变量「先用后声明」静态检查

为什么需要它
------------
Lua 的 `local` 从**声明那一行**起才可见。如果文件靠上的函数用了 `PLAYER_BODY_RATIO`，
而 `local PLAYER_BODY_RATIO = 0.94` 写在文件靠下的位置，Lua **不会报错** ——
它会把这个名字当成**全局变量**去读，值是 `nil`。
2026-09-30 就踩过一次：`浮岛借木/level.lua:85` 静默读到 nil，
`_check_blocks.py` / `_check_refs.py` 全绿，只有真正跑模拟器才炸出来：

    OnUpdate: level:85: attempt to perform arithmetic on a nil value (global 'PLAYER_BODY_RATIO')

它检查什么
----------
对每个 `.lua` 文件，剥掉注释与字符串后做一次「声明位置 vs 引用位置」比对。

**声明**（任一都算，取它在文件里出现的最早行号）：
    · `local NAME` / `local NAME, NAME2` / `local function NAME`
    · 函数形参      `function f(NAME, NAME2)` / `local function g(NAME)` / 匿名函数同理
    · for 循环变量  `for NAME = ...` / `for NAME, NAME2 in ...`

**引用**（只认真正的「读」）：
    · 排除字段访问 `p.h` / `item.art` / `ctrl:SetSize(...)`
    · 排除表键与赋值左值 `{ h = 1 }` / `h = 0`（标识符后面紧跟着非 `==` 的 `=`）
    · 排除关键字

**判据**：某个名字的**最早声明行**晚于它某次引用行 → 那一刻它就是个 nil 全局 → 报一处。
（名字在文件里从没被声明过 = 本来就该是全局，不管。）

另附一条**提示**（不影响退出码）：缩进 0 的 `local NAME = ...` 声明后全文再没用过 → 死代码。

用法
----
    python _tools/check_lua_scoping.py 浮岛借木        # 参数是**游戏目录**
    python _tools/check_lua_scoping.py 浮岛借木/world.lua
退出码：0 = 无「先用后声明」；1 = 有
"""
import io
import os
import re
import sys

KEYWORDS = {
    "and", "break", "do", "else", "elseif", "end", "false", "for", "function",
    "goto", "if", "in", "local", "nil", "not", "or", "repeat", "return",
    "then", "true", "until", "while", "self",
}

NAME = r"[A-Za-z_][A-Za-z_0-9]*"
LHS = r"%s(?:\s*,\s*%s)*" % (NAME, NAME)


def strip_comments_and_strings(src):
    """把注释与字符串**等长**替换成空格（保留换行），免得误判。"""
    out = []
    i, n = 0, len(src)
    while i < n:
        ch = src[i]
        # 长注释 --[[ ... ]] / --[==[ ... ]==]
        if src.startswith("--", i):
            m = re.match(r"--\[(=*)\[", src[i:])
            if m:
                close = "]" + m.group(1) + "]"
                j = src.find(close, i)
                j = n if j < 0 else j + len(close)
                out.append(re.sub(r"[^\n]", " ", src[i:j]))
                i = j
                continue
            j = src.find("\n", i)
            j = n if j < 0 else j
            out.append(" " * (j - i))
            i = j
            continue
        # 长字符串 [[ ... ]] / [==[ ... ]==]
        m = re.match(r"\[(=*)\[", src[i:])
        if m:
            close = "]" + m.group(1) + "]"
            j = src.find(close, i + m.end())
            j = n if j < 0 else j + len(close)
            out.append(re.sub(r"[^\n]", " ", src[i:j]))
            i = j
            continue
        # 普通字符串
        if ch == '"' or ch == "'":
            j = i + 1
            while j < n:
                if src[j] == "\\":
                    j += 2
                    continue
                if src[j] == ch:
                    j += 1
                    break
                j += 1
            out.append(re.sub(r"[^\n]", " ", src[i:j]))
            i = j
            continue
        out.append(ch)
        i += 1
    return "".join(out)


def check_text(src):
    clean = strip_comments_and_strings(src)

    def line_of(off):
        return clean.count("\n", 0, off) + 1

    decl_line = {}   # name -> 最早声明行

    def declare(name, ln):
        if name and name not in KEYWORDS:
            decl_line[name] = min(decl_line.get(name, ln), ln)

    # ---- 收集声明 ----
    # ① local / local function
    for m in re.finditer(r"(?m)^[ \t]*local\s+(?:function\s+)?(%s)" % LHS, clean):
        ln = line_of(m.start())
        for nm in m.group(1).split(","):
            declare(nm.strip(), ln)
    # ② 函数形参（含匿名函数；函数名可能带点，如 `function M.applyImage(...)`）
    for m in re.finditer(r"\bfunction\b\s*[A-Za-z_0-9.:\[\]\"']*\s*\(([^)]*)\)", clean):
        ln = line_of(m.start())
        for nm in m.group(1).split(","):
            nm = nm.strip()
            if re.fullmatch(NAME, nm):
                declare(nm, ln)
    # ③ for 循环变量（注意 `=` 后面不能再要求 \b，否则 `for i = 1` 匹配不上）
    for m in re.finditer(r"\bfor\s+([^=]+?)\s*(?:=|\bin\b)", clean):
        ln = line_of(m.start())
        for nm in m.group(1).split(","):
            nm = nm.strip()
            if re.fullmatch(NAME, nm):
                declare(nm, ln)

    if not decl_line:
        return [], []

    # ---- 收集引用 ----
    problems = []
    for m in re.finditer(r"(?<![\w.:])%s(?![\w])" % NAME, clean):
        name = m.group(0)
        if name in KEYWORDS or name not in decl_line:
            continue
        if re.match(r"\s*=(?!=)", clean[m.end():]):     # 表键 / 赋值左值，不是读
            continue
        ln = line_of(m.start())
        if ln < decl_line[name]:
            problems.append((ln, name, decl_line[name], _snippet(clean, ln)))
    problems = sorted(set(problems))

    # ---- 死代码提示：缩进 0 的 local 声明，全文只出现这一次 ----
    unused = []
    for m in re.finditer(r"(?m)^local\s+(?:function\s+)?(%s)" % LHS, clean):
        ln = line_of(m.start())
        for nm in (s.strip() for s in m.group(1).split(",")):
            if nm == "_" or nm in KEYWORDS:
                continue
            if len(re.findall(r"\b%s\b" % re.escape(nm), clean)) <= 1:
                unused.append((ln, nm))
    return problems, sorted(set(unused))


def _snippet(clean, ln):
    lines = clean.split("\n")
    return lines[ln - 1].strip()[:78] if ln <= len(lines) else ""


def main():
    if len(sys.argv) < 2:
        print("用法：python _tools/check_lua_scoping.py <游戏目录 | 单个 .lua>")
        return 2
    target = sys.argv[1]

    files = []
    if os.path.isdir(target):
        for dirpath, _dirs, names in os.walk(target):
            for fn in sorted(names):
                if fn.endswith(".lua"):
                    files.append(os.path.join(dirpath, fn))
    elif os.path.isfile(target):
        files.append(target)
    else:
        print("找不到：%s" % target)
        return 2
    files.sort()

    print("=== Lua 局部变量作用域检查：%s（%d 个 .lua） ===" % (target, len(files)))
    bad_files, warn_total = 0, 0
    for path in files:
        problems, unused = check_text(io.open(path, encoding="utf-8").read())
        rel = os.path.relpath(path).replace("\\", "/")
        if not problems and not unused:
            print("[OK ] %-22s" % os.path.basename(path))
            continue
        if problems:
            bad_files += 1
            print("[BAD] %s" % rel)
            for ln, name, dln, text in problems:
                print("        L%-5d 读 `%s`，但它到 L%d 才声明 → 此刻是 nil 全局"
                      % (ln, name, dln))
                print("              %s" % text)
        if unused:
            warn_total += len(unused)
            print("[WARN] %s" % rel)
            for ln, name in unused:
                print("        L%-5d `%s` 声明后全文再没用过（死代码？）" % (ln, name))

    print("-" * 60)
    if bad_files:
        print("合计: %d 个文件有「先用后声明」—— 必须修" % bad_files)
        return 1
    print("合计: 0 处「先用后声明」；%d 处「声明后未使用」（提示，不阻塞）" % warn_total)
    return 0


if __name__ == "__main__":
    sys.exit(main())
