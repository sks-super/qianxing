# -*- coding: utf-8 -*-
"""
浮岛借木 · 规则参考实现 + 解法验证（不是游戏的一部分，只用来「验」）

为什么需要它：
  「浮岛借木」的玩法内核 world.lua 有一份定版规则，改规则时若只靠肉眼看代码，
  很容易设计出「走不通」或者「步数和预期对不上」的关卡 —— 而端到端脚本
  (_tools/e2e_浮岛借木.sh) 里的按键口令是写死的，改关卡就必须同步改口令。
  这个脚本把 world.lua 的规则**逐条**抄成 Python，于是可以：
    ① 回放一条 WASD 口令，看它到底能不能通关、走了几步（口令自检）；
    ② BFS 搜出最短解，直接把口令喂给 e2e 脚本。

规则（与 world.lua 逐条对应，2026-09-30 版）：
  单位：1 格。小岛地面 = 0；人物高 1 格；立着的树高 1 格；
        倒下的树 0.5 格（压陆地）/ 0.25 格（浮在水面，吃水一半）；
        留下的树根 0.25 格高；石头 1 / 2 格高。
  小人每步最多向上跨 DEFAULT_MAX_STEP（0.25 格），下落不限。
  一切可视物体都只占**一格**（1×1）。

  ★ 「推」与「踩」的分工（本作的关键）：
      能不能踩 = 顶面高度 − 脚下高度 ≤ 0.25。
      于是：树根（0.25）、浮在水面的树干（0.25）够低 → 直接踩过去；
            压在陆地上的树干（0.5）、立着的树、石头 → 跨不上去 → 撞上去就是「推」。

  ① 树（立着，占 1 格）
     小人朝它移动 → 树倒进「原格的下一格」，原格留下一个树根。
     倒向的那一格被占或越界 → 撞不动。
  ② 倒下的树（占 1 格，带躺向 axis）
     · 从**侧面**推（推动方向 ⊥ 它的躺向）→ 整根滑一格，躺向不变。
     · 从**正面**推（推动方向 ∥ 它的躺向）→ 在「原格的下一格」重新立起来。
  ③ 石头不可移动、不可攀爬。
  ④ 胜利：小人所在格 == 终点格。

用法：
  python _tools/solve_浮岛借木.py             # 跑内置口令自检（三关）
  python _tools/solve_浮岛借木.py <关号>       # 只自检一关，并搜索最短解
  python _tools/solve_浮岛借木.py --bfs 2     # 只搜索最短解（不跑内置口令）
  python _tools/solve_浮岛借木.py --trace DDDDDDDSSSDDDD 2   # 逐步打印某一串口令的动作
"""
import io
import os
import re
import sys
from collections import deque

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))   # 千星割绳子游戏/
GAME = os.path.join(ROOT, "浮岛借木")

DIRS = [("W", (0, -1)), ("S", (0, 1)), ("A", (-1, 0)), ("D", (1, 0))]
DIRV = dict(DIRS)
AXIS = {"W": 0, "S": 0, "A": 1, "D": 1}      # 0 = 竖（南北向）；1 = 横（东西向）

# 内置口令自检：与 _tools/e2e_浮岛借木.sh 里的按键序列**必须一致**
#   （e2e 用的是同一串字母，改了这里也要改那边）
#   三串都是脚本搜出来的**最短解**，所以 e2e 里的期望步数也直接取这里的步数。
BUILTIN = {
    1: "DDDDDDDSSSDDDD",       # 14 步：向右撞倒 (13,4) 的树 → 踩着落进水道的树干过桥
    2: "SDDDDDDDDDDSSDDDD",    # 17 步：把 (11,5) 那根南北向树干侧面推滑 3 次进水道
    3: "SDDDDDDDDSSDDDD",      # 15 步：正面推 (12,5) 的东西向树干 → 它立起来 → 再撞倒
}


# ---------------------------------------------------------------- 读 config.lua
def table_body(block, key):
    """取出 `key = { ... }` 里面那一层的内容（花括号配对扫描）。

    ★ 不能简单用正则 .*? 去截 —— 表里还有一层 `{ c = .., r = .. }`，
      而且空表 `trees = { }` 写成一行时会一路吃到后面 rocks 的表尾。
    """
    m = re.search(r"\b%s\s*=\s*\{" % re.escape(key), block)
    if not m:
        return ""
    i = m.end()                      # 紧跟在 '{' 之后
    depth, out = 1, []
    while i < len(block):
        ch = block[i]
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                break
        out.append(ch)
        i += 1
    return "".join(out)


def read_cfg():
    src = io.open(os.path.join(GAME, "config.lua"), encoding="utf-8").read()

    def num(name, default=None):
        m = re.search(r"M\.%s\s*=\s*([-\d.]+)" % name, src)
        return float(m.group(1)) if m else default

    levels_src = src.split("M.LEVELS = {", 1)[1]
    blocks, depth, cur, started = [], 0, [], False
    for ch in levels_src:
        if ch == "{":
            depth += 1
            if depth == 1:
                started, cur = True, []
                continue
        elif ch == "}":
            if depth == 1:
                blocks.append("".join(cur))
                started = False
            depth -= 1
            if depth < 0:
                break
            if depth == 0:
                continue
        if started:
            cur.append(ch)

    def parse_level(block):
        lv = {"name": re.search(r'name\s*=\s*"([^"]*)"', block).group(1),
              "map": re.findall(r'"([#.]{2,})"', block)}
        for key in ("spawn", "goal"):
            m = re.search(r"%s\s*=\s*\{\s*c\s*=\s*(\d+)\s*,\s*r\s*=\s*(\d+)" % key, block)
            lv[key] = (int(m.group(1)), int(m.group(2)))
        for key in ("trees", "roots", "logs"):
            body = table_body(block, key)
            if key == "logs":
                lv[key] = [(int(a), int(b), s) for a, b, s in
                           re.findall(r"c\s*=\s*(\d+)\s*,\s*r\s*=\s*(\d+)\s*,\s*dir\s*=\s*\"([WSAD])\"", body)]
            else:
                lv[key] = [(int(a), int(b)) for a, b in
                           re.findall(r"c\s*=\s*(\d+)\s*,\s*r\s*=\s*(\d+)", body)]
        body = table_body(block, "rocks")
        rocks = re.findall(r"c\s*=\s*(\d+)\s*,\s*r\s*=\s*(\d+)\s*,\s*h\s*=\s*(\d+)", body)
        lv["rocks"] = {(int(a), int(b)): int(h) for a, b, h in rocks}
        return lv

    return {
        "h_tree": num("DEFAULT_H_TREE", 1.0),
        "h_log_land": num("DEFAULT_H_LOG_LAND", 0.5),
        "h_log_float": num("DEFAULT_H_LOG_FLOAT", 0.25),
        "h_root": num("DEFAULT_H_ROOT", 0.25),
        "h_rock1": num("DEFAULT_H_ROCK1", 1.0),
        "h_rock2": num("DEFAULT_H_ROCK2", 2.0),
        "max_step": num("DEFAULT_MAX_STEP", 0.25),
        "levels": [parse_level(b) for b in blocks],
    }


# ---------------------------------------------------------------- 规则参考实现
class Ref(object):
    def __init__(self, cfg, lv):
        self.cfg = cfg
        self.lv = lv
        self.rows = len(lv["map"])
        self.cols = max(len(s) for s in lv["map"])
        self.rocks = dict(lv["rocks"])
        self.reset()

    def reset(self):
        self.trees = set(self.lv["trees"])
        self.logs = set(self.lv["logs"])           # {(c, r, dir)}
        self.roots = set(self.lv["roots"])
        self.p = tuple(self.lv["spawn"])
        self.steps = 0
        self.actions = []

    # ---- 基础查询
    def land(self, c, r):
        if r < 1 or r > self.rows or c < 1 or c > self.cols:
            return False
        return self.lv["map"][r - 1][c - 1] == "#"

    def log_at(self, c, r):
        for (lc, lr, d) in self.logs:
            if lc == c and lr == r:
                return (lc, lr, d)
        return None

    def height(self, c, r):
        """脚能踩上去的顶面高度；None = 不可站立（水 / 被占）"""
        if r < 1 or r > self.rows or c < 1 or c > self.cols:
            return None
        if (c, r) in self.trees or (c, r) in self.rocks:
            return None
        if self.log_at(c, r):
            # ★ 压在陆地上的树干半格高（跨不上去，只能推）；浮在水面的吃水一半（能踩）
            return self.cfg["h_log_land"] if self.land(c, r) else self.cfg["h_log_float"]
        if (c, r) in self.roots:
            return self.cfg["h_root"]
        if self.land(c, r):
            return 0.0
        return None

    def free(self, c, r):
        """能不能落东西（只问「有没有东西占着」，不看水陆 —— 树可以倒进水里）"""
        if r < 1 or r > self.rows or c < 1 or c > self.cols:
            return False
        if (c, r) in self.trees or (c, r) in self.rocks:
            return False
        if self.log_at(c, r):
            return False
        return True   # 树根不挡：它只有 0.25 格高，可以被倒下的树盖住

    # ---- 走一步
    def step(self, key):
        d = DIRV.get(key)
        if d is None:
            return ("invalid", False)
        pc, pr = self.p
        hp = self.height(pc, pr)
        if hp is None:
            return ("invalid", False)
        q = (pc + d[0], pr + d[1])
        eps = 1e-9

        # ① 目标是立着的树 → 倒进「原格 + 推动方向」那一格，原格留树根
        if q in self.trees:
            dest = (q[0] + d[0], q[1] + d[1])
            if not self.free(*dest):
                return ("blocked", False)
            self.trees.discard(q)
            self.logs.add((dest[0], dest[1], key))
            self.roots.add(q)
            nh = self.height(*q)
            if nh is not None and nh - hp <= self.cfg["max_step"] + eps:
                self.p = q                      # 顺手往前挪一步（踩在新的树根上）
            return ("knock", True)

        # ② 能踩就踩：顶面高度差在 0.25 之内 → 走上去（树根 / 浮在水面的树干）
        h = self.height(*q)
        if h is not None and h - hp <= self.cfg["max_step"] + eps:
            self.p = q
            return ("move", True)

        # ③ 踩不上去、又是倒下的树 → 推它
        lg = self.log_at(*q)
        if lg:
            _, _, ldir = lg
            dest = (q[0] + d[0], q[1] + d[1])
            if not self.free(*dest):
                return ("blocked", False)
            if AXIS[ldir] == AXIS[key]:
                # 正面推（推动方向 ∥ 树的躺向）→ 在下一格重新立起来
                self.logs.discard(lg)
                self.trees.add(dest)
                return ("raise", True)
            # 侧面推（推动方向 ⊥ 树的躺向）→ 整根滑一格，躺向不变
            self.logs.discard(lg)
            self.logs.add((dest[0], dest[1], ldir))
            return ("slide", True)

        # ④ 石头
        if q in self.rocks:
            return ("rock", False)

        # ⑤ 水 / 台阶太高
        if h is None:
            return ("water", False)
        return ("step_too_high", False)

    def won(self):
        return self.p == tuple(self.lv["goal"])

    def play(self, seq):
        self.reset()
        for ch in seq:
            if ch not in DIRV:
                continue
            kind, ok = self.step(ch)
            if ok:
                self.steps += 1
            self.actions.append((ch, kind))
        return self.steps, self.won()


# ---------------------------------------------------------------- 搜最短解
#   ★ 为什么用 IDA* 而不是 BFS：
#     每推倒一棵树都会在它原来的格子上**新增**一个树根，树根会越积越多，
#     状态里「树根集合」这一维几乎是发散的 —— BFS 会先把状态表撑爆。
#     关卡解都很短（十几二十步），迭代加深刚好合适；启发式取「小人到终点的曼哈顿距离」
#     （每步最多走一格 → 一定不高估），既保证最优，又把搜索量压到很小。
def search(ref, max_depth=60):
    ref.reset()
    goal = tuple(ref.lv["goal"])
    eps = 1e-9

    def h(p):
        return abs(p[0] - goal[0]) + abs(p[1] - goal[1])

    snapshot = lambda: (ref.p, set(ref.trees), set(ref.logs), set(ref.roots))
    restore = lambda s: (setattr(ref, "p", s[0]), setattr(ref, "trees", s[1]),
                         setattr(ref, "logs", s[2]), setattr(ref, "roots", s[3]))

    seen = {}                       # 状态 → 已访问过的最大剩余预算（剪枝用）

    def dfs(g, limit):
        if ref.p == goal:
            return ""
        if g + h(ref.p) > limit:
            return None
        key = (ref.p, tuple(sorted(ref.trees)), tuple(sorted(ref.logs)), tuple(sorted(ref.roots)))
        left = limit - g
        if seen.get(key, -1) >= left:
            return None
        seen[key] = left
        for k, _ in DIRS:
            snap = snapshot()
            kind, ok = ref.step(k)
            if ok:
                sub = dfs(g + 1, limit)
                if sub is not None:
                    return k + sub
            restore(snap)
        return None

    limit = h(ref.p)
    while limit <= max_depth:
        seen.clear()
        got = dfs(0, limit)
        if got is not None:
            return got
        limit += 1
    return None


# ---------------------------------------------------------------- 逐步回放
def trace(ref, seq):
    """把一串口令一步步走一遍并打出来 —— 排查「第几步开始不对」用。"""
    ref.reset()
    print("   逐步回放 %s" % seq)
    n = 0
    for i, ch in enumerate(seq, 1):
        kind, ok = ref.step(ch)
        if ok:
            n += 1
        print("     %2d  %s  %-14s p=(%2d,%2d)  树%d 倒树%d 根%d%s"
              % (i, ch, kind, ref.p[0], ref.p[1], len(ref.trees), len(ref.logs),
                 len(ref.roots), "  ★通关" if ref.won() else ""))
    print("   终点 %s  通关=%s  有效步数=%d" % (ref.lv["goal"], ref.won(), n))


# ---------------------------------------------------------------- main
def main():
    cfg = read_cfg()
    only = None
    do_bfs = False
    trace_seq = None
    args = sys.argv[1:]
    i = 0
    while i < len(args):
        a = args[i]
        if a == "--bfs":
            do_bfs = True
        elif a == "--trace":
            i += 1
            trace_seq = args[i] if i < len(args) else ""
        elif a.isdigit():
            only = int(a)
        i += 1

    print("高度模型：树 %.2f / 倒树·陆 %.2f / 倒树·水 %.2f / 树根 %.2f / 石头 %g·%g / 最大跨步 %.2f"
          % (cfg["h_tree"], cfg["h_log_land"], cfg["h_log_float"], cfg["h_root"],
             cfg["h_rock1"], cfg["h_rock2"], cfg["max_step"]))
    print()

    bad = 0
    for idx, lv in enumerate(cfg["levels"], 1):
        if only and idx != only:
            continue
        ref = Ref(cfg, lv)
        nland = sum(row.count("#") for row in lv["map"])
        print("第%02d关 %s" % (idx, lv["name"]))
        print("   地图 %d×%d，陆地 %d 格；树 %d，倒树 %d，树根 %d，石头 %d"
              % (ref.cols, ref.rows, nland, len(ref.trees), len(ref.logs),
                 len(ref.roots), len(ref.rocks)))
        for (lc, lr, ld) in sorted(ref.logs):
            print("     预置倒树 (%d,%d) 躺向=%s %s" % (lc, lr, ld, "横" if AXIS[ld] else "竖"))

        # ① 内置口令自检
        if not do_bfs and idx in BUILTIN:
            seq = BUILTIN[idx]
            steps, won = ref.play(seq)
            flag = "OK" if won else "★失败"
            print("   内置口令 %-22s → %2d 步  通关=%s  [%s]" % (seq, steps, won, flag))
            if not won:
                bad += 1
                print("       终止位置 (%d,%d)，终点 %s" % (ref.p[0], ref.p[1], lv["goal"]))

        # ② IDA* 最短解
        ref.reset()
        sol = search(ref)
        if sol is None:
            print("   ★ 搜不到解（关卡不可解，或超出搜索深度上限）")
            bad += 1
        else:
            ref.play(sol)
            print("   最短解 %-24s → %d 步" % (sol, ref.steps))
            # ★ 内置口令必须是「最优长度」—— e2e 脚本里的期望步数就取这个数，
            #   两边不一致说明改了关卡却没同步口令。
            if idx in BUILTIN and not do_bfs and len(BUILTIN[idx]) != len(sol):
                print("   ★ 内置口令 %d 步 ≠ 最短解 %d 步 —— 两边不同步了"
                      % (len(BUILTIN[idx]), len(sol)))
                bad += 1

        # ③ 逐步回放（--trace）
        if trace_seq is not None:
            trace(ref, trace_seq)

        # ③ 地图字符画（每格标注：S 出生 / G 终点 / T 树 / L 倒树 / o 树根 / X 石头）
        ov = {}
        for (c, r) in lv["trees"]:
            ov[(c, r)] = "T"
        for (c, r, _d) in lv["logs"]:
            ov[(c, r)] = "L"
        for (c, r) in lv["roots"]:
            ov[(c, r)] = "o"
        for (c, r) in lv["rocks"]:
            ov[(c, r)] = "X"
        ov[tuple(lv["spawn"])] = "S"
        ov[tuple(lv["goal"])] = "G"
        print("   地图（上排＝远端，下排＝近端）：")
        for r, line in enumerate(lv["map"], 1):
            row = "".join(ov.get((c, r), line[c - 1]) for c in range(1, ref.cols + 1))
            print("     %2d %s" % (r, row))
        print()

    print("===== 结论：%s =====" % ("全部通过" if bad == 0 else "有 %d 处问题" % bad))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
