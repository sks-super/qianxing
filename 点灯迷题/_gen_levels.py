# -*- coding: utf-8 -*-
"""
点灯迷题 · 关卡数据生成器（可复现，无第三方依赖）

棋盘固定 5 行 × 6 列 = 30 格，一维下标 idx = 行 * 6 + 列（行从上往下 0..4，列从左往右 0..5）。

翻转规则：按下 idx 这一格，会同时翻转「它自己」与「上下左右四个邻居」（越界忽略）。

每关的数据 = 一组「需要按下的格子」（flips）。初始盘面由该解「反推」得到：
    初始盘面 = 对「全灭盘」依次按下 flips 后的结果
于是玩家把这串格子各按一次即回到全灭，关卡必然可解。

难度递进只改「需要按下 / 翻转的不同格子数」：
    第 1~5 关 = 教程关，步数 1,2,3,4,5（逐关引入新概念）
    第 6~50 关 = 从 5 步平滑递增到 12 步

★ 最小性保证：5×6 点灯谜题存在非平凡「零效果按键组合」（核空间），
  因此同一盘面可能有多个解。生成器会把「权重最小的那个解」作为关卡答案，
  保证玩家用更少的步数无解 → 步数标签即真实难度。

用法：
    python _gen_levels.py                 # 只打印统计与预览
    python _gen_levels.py --write         # 把生成的 M.LEVELS 写回 config.lua
    python _gen_levels.py --json out.json # 额外导出 JSON（编辑器/其他工具可读）
"""
import argparse
import json
import os
import random
import sys

ROWS, COLS = 5, 6
N = ROWS * COLS
MAX_STEPS = 12          # 难度上限（第 50 关）
TUTORIAL_LEVELS = 5     # 前 5 关为教程关
SEED = 20261013

# 每关的教程提示（仅前 5 关）
# 教程关的一行提示。
# ★ 长度受约束：HUD 左上信息条只有一行，字号 16，实用宽度约 470px；
#   提示会在前面拼上「难度 N 步 · 」，所以正文请控制在 14 个汉字以内，
#   否则真机会被裁掉首尾（模拟器不裁，属于「模拟器看不出来」的坑）。
TUTORIAL_TIPS = {
    1: "点一格，连上下左右一起翻转",
    2: "同一格按两次，等于没按",
    3: "边角牵动少，先定边角",
    4: "先数亮着的灯，逐个抵消",
    5: "步数更多，一层层往下推",
}


def bit(i):
    return 1 << i


def build_press_masks():
    """PRESS_MASK[i] = 按下格子 i 所翻转的全部格子的位掩码。"""
    masks = []
    for r in range(ROWS):
        for c in range(COLS):
            m = bit(r * COLS + c)
            for dr, dc in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nr, nc = r + dr, c + dc
                if 0 <= nr < ROWS and 0 <= nc < COLS:
                    m |= bit(nr * COLS + nc)
            masks.append(m)
    return masks


PRESS_MASK = build_press_masks()


def popcount(x):
    return bin(x).count("1")


def bits_of(mask):
    out, i = [], 0
    while mask:
        if mask & 1:
            out.append(i)
        mask >>= 1
        i += 1
    return out


def mask_of(indices):
    m = 0
    for i in indices:
        m |= bit(i)
    return m


def apply_presses(s):
    """按位掩码 s 表示的一组格子 → 翻转后的盘面位掩码。"""
    board = 0
    i = 0
    while s:
        if s & 1:
            board ^= PRESS_MASK[i]
        s >>= 1
        i += 1
    return board


def kernel_basis():
    """求「零效果按键组合」的一组基（每个元素是按键位掩码）。"""
    basis = {}       # 主元位 -> (向量, 组合)
    kernel = []
    for j in range(N):
        vec, comb = PRESS_MASK[j], bit(j)
        while vec:
            lb = vec.bit_length() - 1
            if lb in basis:
                bv, bc = basis[lb]
                vec ^= bv
                comb ^= bc
            else:
                basis[lb] = (vec, comb)
                break
        else:
            if comb:
                kernel.append(comb)
    return kernel


KERNEL = kernel_basis()


def all_solutions(s):
    """返回与按键组合 s 等价的全部解（含 s 自身）。"""
    out = [s]
    for k in KERNEL:
        out += [t ^ k for t in out]
    # 去重
    return sorted(set(out))


def min_weight_solution(s):
    best, best_w = s, popcount(s)
    for t in all_solutions(s):
        w = popcount(t)
        if w < best_w:
            best, best_w = t, w
    return best, best_w


def target_steps(level_index):
    """第 level_index 关（1 起始）需要翻转的点位数。单调不减。"""
    i = level_index
    if i <= TUTORIAL_LEVELS:
        return i
    t = (i - TUTORIAL_LEVELS) / float(50 - TUTORIAL_LEVELS)
    return int(round(TUTORIAL_LEVELS + t * (MAX_STEPS - TUTORIAL_LEVELS)))


def generate_level(k, rng, used_boards):
    """随机找一个「最小解恰为 k 步」且盘面未出现过的关卡。"""
    for _ in range(60000):
        cells = rng.sample(range(N), k)
        s = mask_of(cells)
        board = apply_presses(s)
        if board == 0:
            continue
        best, best_w = min_weight_solution(s)
        if best_w != k:
            continue
        if board in used_boards:
            continue
        if popcount(board) < max(3, k):     # 太稀疏的盘面不好看
            continue
        return board, best, best_w
    raise RuntimeError("找不到满足条件的关卡: steps=%d" % k)


def generate_all():
    rng = random.Random(SEED)
    used_boards = set()
    levels = []
    for i in range(1, 51):
        k = target_steps(i)
        board, flips, steps = generate_level(k, rng, used_boards)
        used_boards.add(board)
        lv = {
            "index": i,
            "name": "第%02d关" % i,
            "steps": steps,
            "flips": bits_of(flips),
            "board": bits_of(board),
            "kernel_dim": len(KERNEL),
        }
        if i in TUTORIAL_TIPS:
            lv["tip"] = TUTORIAL_TIPS[i]
        levels.append(lv)
    return levels


def verify(levels):
    """独立复算校验（不依赖生成时的中间量）。"""
    problems = []
    boards = {}
    prev_steps = 0
    non_unique = []
    for lv in levels:
        s = mask_of(lv["flips"])
        # ① 由解反推初始盘面：对「全灭盘」依次按下 flips
        board0 = apply_presses(s)
        if bits_of(board0) != sorted(lv["board"]):
            problems.append("[%d] board 字段与「由解反推」不符" % lv["index"])
        # ② 真·模拟：从初始盘面出发，把 flips 各按一次，必须回到全灭
        b = board0
        for f in lv["flips"]:
            b ^= PRESS_MASK[f]
        if b != 0:
            problems.append("[%d] 从初始盘面按 flips 后未回到全灭" % lv["index"])
        # ③ 解的唯一性 / 最小解权重必须等于标注步数
        sols = all_solutions(s)
        if len(sols) != 1:
            non_unique.append(lv["index"])
        min_w = min(popcount(t) for t in sols)
        if min_w != lv["steps"]:
            problems.append("[%d] 步数标注 %d 但最小解为 %d 步"
                            % (lv["index"], lv["steps"], min_w))
        # ④ flips 本身权重 = steps，且无重复
        if len(set(lv["flips"])) != len(lv["flips"]):
            problems.append("[%d] flips 有重复下标" % lv["index"])
        if len(lv["flips"]) != lv["steps"]:
            problems.append("[%d] flips 个数与步数不符" % lv["index"])
        # ⑤ 下标范围
        for f in lv["flips"]:
            if not (0 <= f < N):
                problems.append("[%d] 下标越界: %d" % (lv["index"], f))
        # ⑥ 盘面唯一
        if board0 in boards:
            problems.append("[%d] 盘面与第 %d 关重复" % (lv["index"], boards[board0]))
        boards[board0] = lv["index"]
        # ⑦ 难度单调不减
        if lv["steps"] < prev_steps:
            problems.append("[%d] 步数递减 (%d -> %d)"
                            % (lv["index"], prev_steps, lv["steps"]))
        prev_steps = lv["steps"]
    if non_unique:
        problems.append("以下关卡解不唯一（核空间非平凡）: %s" % non_unique)
    return problems


def lua_levels_block(levels):
    out = []
    out.append("M.LEVELS = {")
    for lv in levels:
        tag = "教程" if lv["index"] <= TUTORIAL_LEVELS else "挑战"
        out.append("    -- ===== %s（%s · %d 步）=====" % (lv["name"], tag, lv["steps"]))
        out.append("    {")
        out.append('        name = "%s",' % lv["name"])
        out.append("        steps = %d," % lv["steps"])
        if lv.get("tip"):
            out.append('        tip = "%s",' % lv["tip"])
        out.append("        flips = {%s}," % ", ".join(str(x) for x in lv["flips"]))
        out.append("    },")
    out.append("}")
    return "\n".join(out)


BEGIN = "-- >>> LEVELS_BEGIN"
END = "-- <<< LEVELS_END"


def write_config(config_path, block):
    with open(config_path, "r", encoding="utf-8") as f:
        src = f.read()
    if BEGIN not in src or END not in src:
        raise RuntimeError("config.lua 中找不到 %s / %s 标记" % (BEGIN, END))
    head, rest = src.split(BEGIN, 1)
    _, tail = rest.split(END, 1)
    new_src = head + BEGIN + "\n" + block + "\n" + END + tail
    with open(config_path, "w", encoding="utf-8", newline="\n") as f:
        f.write(new_src)
    print("[写回] %s（%d 关）" % (config_path, block.count("steps = ")))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--write", metavar="CONFIG", nargs="?", const="config.lua",
                    help="把生成的 M.LEVELS 写回指定 config.lua（默认 config.lua）")
    ap.add_argument("--json", metavar="OUT", help="额外导出 JSON")
    args = ap.parse_args()

    levels = generate_all()
    problems = verify(levels)

    print("核空间维数 = %d（零效果按键组合有 %d 种）" % (len(KERNEL), 2 ** len(KERNEL)))
    print("难度曲线:", " ".join(str(lv["steps"]) for lv in levels))
    print("关卡数 =", len(levels))
    for lv in levels[:6] + levels[-3:]:
        print("  %s  步数=%2d  解=%s  初始盘面亮灯=%s"
              % (lv["name"], lv["steps"], lv["flips"], lv["board"]))

    if problems:
        print("\n[校验失败] %d 处：" % len(problems))
        for p in problems:
            print("   " + p)
        sys.exit(1)
    print("\n[校验通过] 解正确性 / 最小性 / 盘面唯一 / 难度单调 全部 OK")

    if args.write:
        write_config(args.write, lua_levels_block(levels))
    if args.json:
        with open(args.json, "w", encoding="utf-8") as f:
            json.dump({"rows": ROWS, "cols": COLS, "kernel_dim": len(KERNEL),
                       "levels": levels}, f, ensure_ascii=False, indent=2)
        print("[导出] %s" % args.json)


if __name__ == "__main__":
    main()
