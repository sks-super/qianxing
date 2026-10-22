# -*- coding: utf-8 -*-
"""生成《瓦雷莎的果园救急》的 50 关解序列（纯标准库，可复现）。

规则沿用 5 行 × 6 列 Lights Out：idx = 行 * 6 + 列（0 基），
按下 idx 会翻转「自身 + 上下左右」，越界忽略。
5×6 棋盘满秩 ⇒ 任何点集都是某个盘面的唯一最优解，
所以「解序列」可以直接当关卡数据用（steps = 点集大小）。

用法：
    python _gen_levels.py            # 打印 Lua 片段
    python _gen_levels.py --write config.lua   # 覆盖 config.lua 的标记区
"""

from __future__ import annotations

import argparse
import random
import re
from pathlib import Path

ROWS, COLS = 5, 6
N = ROWS * COLS
HERE = Path(__file__).resolve().parent

# 难度曲线：前 5 关是教学关（1/2/2/3/4），之后平滑抬到 12
PLAN = ([1, 2, 2, 3, 4]
        + [5] * 4
        + [6] * 6
        + [7] * 6
        + [8] * 6
        + [9] * 6
        + [10] * 7
        + [11] * 6
        + [12] * 4)
assert len(PLAN) == 50, len(PLAN)

# 前 5 关手工排布 —— 每一关都对应一堂课：
#   01 十字五格 / 点两次等于没点
#   02 边缘 4 格 / 角落 3 格
#   03 对角两点的十字重叠两格（重叠处白翻）
#   04 三点叠加，重叠更多
#   05 边角优先的推理起手式
FIXED = [
    [19],
    [1, 24],
    [13, 20],
    [7, 14, 21],
    [1, 13, 19, 22],
]

TIPS = {
    1: "点一格，十字五格一起翻",
    2: "靠边少翻一格，靠角少两格",
    3: "对角两点，重叠两格白翻",
    4: "三点叠加，先算重叠",
    5: "先定边角，再往里推",
}


def press_mask(i: int) -> int:
    r, c = divmod(i, COLS)
    m = 1 << i
    for dr, dc in ((-1, 0), (1, 0), (0, -1), (0, 1)):
        nr, nc = r + dr, c + dc
        if 0 <= nr < ROWS and 0 <= nc < COLS:
            m |= 1 << (nr * COLS + nc)
    return m


PRESS = [press_mask(i) for i in range(N)]


def board_of(flips) -> int:
    b = 0
    for i in flips:
        b ^= PRESS[i]
    return b


def spread_ok(flips) -> bool:
    """别让解全挤在同一行/同一列，盘面才好看。"""
    rs = {i // COLS for i in flips}
    cs = {i % COLS for i in flips}
    return len(rs) >= 2 and len(cs) >= 2


def build():
    rng = random.Random(20261019)
    levels = []
    used_boards = set()
    for i, flips in enumerate(FIXED):
        levels.append({"steps": PLAN[i], "flips": list(flips)})
        used_boards.add(board_of(flips))

    for idx in range(5, 50):
        steps = PLAN[idx]
        picked = None
        for _ in range(6000):
            cand = sorted(rng.sample(range(N), steps))
            b = board_of(cand)
            if b in used_boards or not spread_ok(cand):
                continue
            picked = cand
            used_boards.add(b)
            break
        if picked is None:                     # 极端情况下的兜底：顺序滑窗
            start = (idx * 7) % (N - steps + 1)
            picked = list(range(start, start + steps))
            used_boards.add(board_of(picked))
        levels.append({"steps": steps, "flips": picked})
    return levels


def render(levels) -> str:
    out = ["M.LEVELS = {"]
    for i, lv in enumerate(levels, start=1):
        tag = "教程" if i <= 5 else "挑战"
        out.append(f"    -- ===== 第{i:02d}片果园（{tag} · {lv['steps']} 步）=====")
        out.append("    {")
        out.append(f'        name = "果园 {i:02d}",')
        out.append(f"        steps = {lv['steps']},")
        if i in TIPS:
            out.append(f'        tip = "{TIPS[i]}",')
        out.append("        flips = {" + ", ".join(str(v) for v in lv["flips"]) + "},")
        out.append("    },")
    out.append("}")
    return "\n".join(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--write", default="", help="把结果写回该文件的 LEVELS_BEGIN/END 标记区")
    args = ap.parse_args()

    levels = build()
    block = render(levels)
    if not args.write:
        print(block)
        return

    path = HERE / args.write
    src = path.read_text(encoding="utf-8")
    new = re.sub(r"(?s)(-- >>> LEVELS_BEGIN\n).*?(\n-- <<< LEVELS_END)",
                 lambda m: m.group(1) + block + m.group(2), src)
    path.write_text(new, encoding="utf-8")
    print(f"[ok] 已写入 {path}（{len(levels)} 关）")


if __name__ == "__main__":
    main()
