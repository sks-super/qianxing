# -*- coding: utf-8 -*-
"""把参考图重建的 64×64 猫 + 派生 16×16 写进 config.lua。

只改两处：
  ① `local CAT = { ... }` 的 16 行点阵
  ② `M.ART64` 里的 `cat = { ... }` 条目（mushroom 保持不动）
其余一字不动。
"""
import io
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
CFG = HERE / "config.lua"
PIC = HERE / "_art" / "out" / "refcat" / "_pic16.lua"
GLUA = HERE / "_art" / "out" / "refcat" / "_glua.lua"


def main() -> int:
    cfg = io.open(CFG, encoding="utf-8").read()
    pic = io.open(PIC, encoding="utf-8").read()
    glua = io.open(GLUA, encoding="utf-8").read()

    # ① 16×16 点阵
    body = re.search(r"local CAT = \{(.*?)\n\}", pic, re.S).group(1).strip("\n")
    m = re.search(r"local CAT = \{.*?\n\}", cfg, re.S)
    if not m:
        print("找不到 local CAT 段")
        return 1
    old_rows = m.group(0).count('"')
    cfg = cfg[:m.start()] + "local CAT = {\n" + body + "\n}" + cfg[m.end():]
    new_rows = cfg[m.start():].split("local MUSHROOM")[0].count('"')

    # ② ART64.cat 条目
    entry = glua.strip()
    entry = re.sub(r"^M\.ART64\.cat = \{", "    cat = {", entry)
    entry = "\n".join("    " + ln if ln.strip() else ln for ln in entry.split("\n")[1:-1])
    entry = "    cat = {\n" + entry + "\n    },"
    m2 = re.search(r"\n    cat = \{.*?\n    \},", cfg, re.S)
    if not m2:
        print("找不到 ART64.cat 段")
        return 1
    cfg = cfg[:m2.start()] + "\n" + entry + cfg[m2.end():]

    io.open(CFG, "w", encoding="utf-8", newline="\n").write(cfg)

    def rows_of(s):
        return len(re.findall(r'^\s*"[0-9A-Z]+",\s*$', s, re.M))

    print("16×16 行数 %d→%d" % (old_rows // 2, new_rows // 2))
    print("ART64.cat 数据行 %d" % rows_of(entry))
    print("config.lua 现在 %d 行" % len(cfg.splitlines()))
    return 0


if __name__ == "__main__":
    sys.exit(main())
