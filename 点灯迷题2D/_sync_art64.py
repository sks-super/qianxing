# -*- coding: utf-8 -*-
"""把 _art/out/art64/_art64.lua 合进 config.lua 的 M.ART64 段。

只替换 `M.ART64 = {` 到紧随的独立 `}` 那一整段，其余一字不动。
用法: python _sync_art64.py
"""
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
CFG = HERE / "config.lua"
ART = HERE / "_art" / "out" / "art64" / "_art64.lua"


def main() -> int:
    cfg = CFG.read_text(encoding="utf-8")
    art = ART.read_text(encoding="utf-8").strip("\n")

    m = re.search(r"M\.ART64 = \{.*?\n\}\n", cfg, re.S)
    if not m:
        print("找不到 M.ART64 段")
        return 1
    old = m.group(0)
    # 头尾对齐：保留原有的注释头（在 M.ART64 之前），只换数据段
    new = art + "\n"
    if old == new:
        print("config.lua 已是最新，无需改动")
        return 0
    cfg = cfg[: m.start()] + new + cfg[m.end():]
    CFG.write_text(cfg, encoding="utf-8", newline="\n")

    old_rows = len(re.findall(r'^\s*"[0-9A-Z]+",\s*$', old, re.M))
    new_rows = len(re.findall(r'^\s*"[0-9A-Z]+",\s*$', new, re.M))
    old_pal = len(re.findall(r'"[0-9A-F]{6}"', old.split("rows")[0]))
    new_pal = len(re.findall(r'"[0-9A-F]{6}"', new.split("rows")[0]))
    print(f"已合入 config.lua：调色板 {old_pal}→{new_pal} 项，RLE 行 {old_rows}→{new_rows} 行")
    print(f"config.lua 现在 {len(cfg.splitlines())} 行")
    return 0


if __name__ == "__main__":
    sys.exit(main())
