# -*- coding: utf-8 -*-
"""
把用户给的 64×64 像素画（棋盘底 JPG）抽成 config.lua 用的 ART64 RLE 数据。

① 棋盘底 = 两种浅色交替；先做浅色掩码，从四边泛洪得到外部背景，
   再把内部封闭的小浅色块（钥匙孔那种）也当背景删掉。
② 取主体 bbox，铺 64×64，每格 5×5 子采样取众数（只统计非背景像素）。
③ 颜色聚类到 ≤ 28 色（先贪心合并，超了就合并最近的一对）。
④ RLE：字符 0-9A-Z，索引 35 = 透明。
"""
import os
from collections import Counter, deque

from PIL import Image

S = 64
SUB = 5
CH = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"
TRANSPARENT = 35
MAX_COLORS = 28

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "out", "set64")

ROOT = r"E:\聊天信息\QQ信息\Tencent Files\2902922874\nt_qq\nt_data\Pic\2026-10"
SRC = [
    ("mushroom", ROOT + r"\Thumb\92a4f759e6da7191125017e3152ec9c3_720.jpg"),
    ("balloon", ROOT + r"\Ori\07606eeb124449da038cfdc19c0a8691.jpg"),
    ("key", ROOT + r"\Thumb\2e6f60a610c4f0fee07a7366c378c1fa_720.jpg"),
    ("chest", ROOT + r"\Thumb\c6dc84ae65ee0ce558df2de1a6bddf3b_720.jpg"),
    ("ghost", ROOT + r"\Thumb\db6b7539988dbce91772b11e57e5a003_720.jpg"),
    ("rocket", ROOT + r"\Thumb\304b8e7471711d6f9ba427c98e6680b8_720.jpg"),
]


def dist(a, b):
    return abs(a[0] - b[0]) + abs(a[1] - b[1]) + abs(a[2] - b[2])


def is_light(c, tol=236):
    return min(c[0], c[1], c[2]) >= tol and (max(c) - min(c)) <= 16


def build_bg(px, W, H):
    bg = [[False] * W for _ in range(H)]
    q = deque()
    for x in range(W):
        for y in (0, H - 1):
            if is_light(px[x, y]):
                bg[y][x] = True
                q.append((x, y))
    for y in range(H):
        for x in (0, W - 1):
            if is_light(px[x, y]) and not bg[y][x]:
                bg[y][x] = True
                q.append((x, y))
    while q:
        cx, cy = q.popleft()
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = cx + dx, cy + dy
            if 0 <= nx < W and 0 <= ny < H and not bg[ny][nx] and is_light(px[nx, ny]):
                bg[ny][nx] = True
                q.append((nx, ny))

    seen = [[False] * W for _ in range(H)]
    for y in range(H):
        for x in range(W):
            if bg[y][x] or seen[y][x] or not is_light(px[x, y]):
                continue
            comp = []
            q = deque([(x, y)])
            seen[y][x] = True
            while q:
                cx, cy = q.popleft()
                comp.append((cx, cy))
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = cx + dx, cy + dy
                    if (0 <= nx < W and 0 <= ny < H and not seen[ny][nx]
                            and not bg[ny][nx] and is_light(px[nx, ny])):
                        seen[ny][nx] = True
                        q.append((nx, ny))
            if len(comp) < 0.02 * W * H:
                for (cx, cy) in comp:
                    bg[cy][cx] = True
    return bg


def cluster(counts):
    palette, weights = [], []
    for c, n in counts.most_common():
        best = None
        for i, p in enumerate(palette):
            d = dist(c, p)
            if d <= 30 and (best is None or d < best[0]):
                best = (d, i)
        if best:
            weights[best[1]] += n
        else:
            palette.append(c)
            weights.append(n)
    while len(palette) > MAX_COLORS:
        bi, bj, bd = 0, 1, 10 ** 9
        for i in range(len(palette)):
            for j in range(i + 1, len(palette)):
                d = dist(palette[i], palette[j])
                if d < bd:
                    bi, bj, bd = i, j, d
        w = weights[bi] + weights[bj]
        palette[bi] = tuple(
            (palette[bi][k] * weights[bi] + palette[bj][k] * weights[bj]) // max(1, w)
            for k in range(3))
        weights[bi] = w
        del palette[bj]
        del weights[bj]
    return palette


def nearest(palette, c):
    bi, bd = 0, 10 ** 9
    for i, p in enumerate(palette):
        d = dist(c, p)
        if d < bd:
            bi, bd = i, d
    return bi


def rle(rows_idx):
    out = []
    for y in range(S):
        runs, prev, cnt = [], "INIT", 0
        for x in range(S):
            k = rows_idx[y][x]
            if k == prev:
                cnt += 1
            else:
                if prev != "INIT":
                    runs.append((prev, cnt))
                prev, cnt = k, 1
        runs.append((prev, cnt))
        s = ""
        for (k, c) in runs:
            ci = TRANSPARENT if k is None else k
            left = c
            while left > 0:
                n = min(left, 35)
                s += CH[ci] + CH[n]
                left -= n
        out.append(s)
    return out


def extract(path, key):
    im = Image.open(path).convert("RGB")
    W, H = im.size
    px = im.load()
    bg = build_bg(px, W, H)
    # ★ 右下角有「豆包 AI 生成」水印：整块当背景，否则会被算进主体 bbox
    for y in range(int(H * 0.88), H):
        for x in range(int(W * 0.72), W):
            bg[y][x] = True

    xs = [x for y in range(H) for x in range(W) if not bg[y][x]]
    ys = [y for y in range(H) for x in range(W) if not bg[y][x]]
    if not xs:
        raise SystemExit("%s: 没找到主体" % key)
    x0, x1, y0, y1 = min(xs), max(xs) + 1, min(ys), max(ys) + 1
    side = max(x1 - x0, y1 - y0)
    cx, cy = (x0 + x1) / 2.0, (y0 + y1) / 2.0
    bx0 = int(round(cx - side / 2))
    by0 = int(round(cy - side / 2))

    raw = [[None] * S for _ in range(S)]
    counts = Counter()
    for gy in range(S):
        for gx in range(S):
            cnt = Counter()
            total = hit = 0
            for sy in range(SUB):
                for sx in range(SUB):
                    X = int(bx0 + (gx + (sx + 0.5) / SUB) * side / S)
                    Y = int(by0 + (gy + (sy + 0.5) / SUB) * side / S)
                    if not (0 <= X < W and 0 <= Y < H):
                        continue
                    total += 1
                    if bg[Y][X]:
                        continue
                    hit += 1
                    cnt[px[X, Y]] += 1
            if total and hit * 2 >= total:
                c = cnt.most_common(1)[0][0]
                raw[gy][gx] = c
                counts[c] += 1

    # ★ 轮廓平滑：先补单格凹坑（3×3 里 6 个实心），再去掉孤立毛刺（≤1 个邻居）
    #   面积采样 + JPEG 噪点会让边缘出现锯齿和小凸起，这两步能把轮廓抹顺，
    #   又不会吃掉细结构（阈值卡得很紧，只处理 1 格级的缺陷）。
    def nb_colors(y, x):
        out = []
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                if dx == 0 and dy == 0:
                    continue
                nx, ny = x + dx, y + dy
                if 0 <= nx < S and 0 <= ny < S and raw[ny][nx] is not None:
                    out.append(raw[ny][nx])
        return out

    for y in range(S):
        for x in range(S):
            if raw[y][x] is None:
                nb = nb_colors(y, x)
                if len(nb) >= 6:
                    raw[y][x] = Counter(nb).most_common(1)[0][0]
                    counts[raw[y][x]] += 1
    for y in range(S):
        for x in range(S):
            if raw[y][x] is not None and len(nb_colors(y, x)) <= 1:
                raw[y][x] = None

    palette = cluster(counts)
    idx = [[None if raw[y][x] is None else nearest(palette, raw[y][x]) for x in range(S)]
           for y in range(S)]
    return palette, rle(idx), (bx0, by0, side)


def decode(rows):
    g = [[None] * S for _ in range(S)]
    for y, s in enumerate(rows):
        x = i = 0
        while i < len(s) and x < S:
            k = CH.index(s[i])
            n = CH.index(s[i + 1])
            for _ in range(n):
                if x < S:
                    g[y][x] = None if k >= TRANSPARENT else k
                    x += 1
            i += 2
    return g


def main():
    os.makedirs(OUT, exist_ok=True)
    lua = ["M.ART64 = {"]
    for key, path in SRC:
        pal, rows, box = extract(path, key)
        assert len(pal) <= TRANSPARENT, (key, len(pal))
        print("%-9s 调色板 %2d 色  bbox=%s" % (key, len(pal), box))
        lua.append("    %s = {" % key)
        lua.append("        pal = { %s }," % ", ".join('"%02X%02X%02X"' % c for c in pal))
        lua.append("        rows = {")
        for r in rows:
            lua.append('            "%s",' % r)
        lua.append("        },")
        lua.append("    },")

        prev = Image.new("RGB", (S * 8, S * 8), (250, 248, 240))
        pp = prev.load()
        g = decode(rows)
        for y in range(S):
            for x in range(S):
                k = g[y][x]
                if k is None:
                    continue
                c = pal[k]
                for yy in range(8):
                    for xx in range(8):
                        pp[x * 8 + xx, y * 8 + yy] = c
        prev.save(os.path.join(OUT, key + ".png"))

    lua.append("}")
    with open(os.path.join(OUT, "_set64.lua"), "w", encoding="utf-8") as f:
        f.write("\n".join(lua) + "\n")
    print("写出", os.path.join(OUT, "_set64.lua"))


if __name__ == "__main__":
    main()
