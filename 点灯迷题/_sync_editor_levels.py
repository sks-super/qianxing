#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把 _levels.json 内嵌进 编辑器.html 的 `const INIT_LEVELS = [...];`。

为什么需要它：关卡数据的唯一真源是 _gen_levels.py → config.lua 的标记区；
编辑器要离线可用，就必须自带一份同样的数据。两份一旦漂移，
`node _verify_levels.mjs` 的第一项校验（config vs 编辑器内嵌）会报错。

用法：
    python _gen_levels.py --write config.lua --json _levels.json
    python _sync_editor_levels.py
    node _verify_levels.mjs
"""
import io
import json
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
JSON_PATH = HERE / "_levels.json"
HTML_PATH = HERE / "编辑器.html"

# 匹配 `const INIT_LEVELS = [` 到第一个「可缩进的」独占一行 `];`（原文件里是 4 空格缩进）。
# 等号后的空白用 \s* 容忍，避免历史误写（`=     [`）导致匹配失败。
PATTERN = re.compile(r"const INIT_LEVELS =\s*\[.*?\n[ \t]*\];", re.S)


def main() -> int:
    if not JSON_PATH.exists():
        print(f"[FAIL] 找不到 {JSON_PATH.name}，先跑 python _gen_levels.py --json _levels.json")
        return 1
    if not HTML_PATH.exists():
        print(f"[FAIL] 找不到 {HTML_PATH.name}")
        return 1

    payload = json.loads(JSON_PATH.read_text(encoding="utf-8"))
    # _levels.json 形如 { rows, cols, kernel_dim, levels: [...] }
    levels = payload["levels"] if isinstance(payload, dict) else payload

    # 字段顺序固定为 name / steps / flips / tip，与编辑器里原有的排版一致，
    # 且整体再缩进 4 格 —— 这样只有真正变化的内容才会出现在 diff 里。
    slim = []
    for lv in levels:
        item = {"name": lv["name"], "steps": int(lv["steps"]),
                "flips": [int(f) for f in lv["flips"]]}
        if lv.get("tip"):
            item["tip"] = lv["tip"]
        slim.append(item)
    body = json.dumps(slim, ensure_ascii=False, indent=4)
    body_lines = body.split("\n")
    # 首行就是 `[`，紧跟在 `const INIT_LEVELS = ` 后面；其余行整体缩进 4 格
    body = body_lines[0] + "".join(
        ("\n    " + ln) if ln.strip() else "\n" for ln in body_lines[1:]
    )
    block = "const INIT_LEVELS = " + body + ";"

    html = HTML_PATH.read_text(encoding="utf-8")
    if not PATTERN.search(html):
        print("[FAIL] 编辑器.html 里没找到 `const INIT_LEVELS = [` 区段")
        return 1
    new_html = PATTERN.sub(lambda _m: block, html, count=1)
    if new_html == html:
        print(f"[OK ] 编辑器内嵌已是最新（{len(levels)} 关），无需改动")
        return 0
    HTML_PATH.write_text(new_html, encoding="utf-8")
    print(f"[OK ] 已把 {len(levels)} 关写进 编辑器.html 的 INIT_LEVELS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
