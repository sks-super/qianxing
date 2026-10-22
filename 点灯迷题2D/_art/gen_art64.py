# -*- coding: utf-8 -*-
"""
点灯迷题 16 · 64×64 彩色画生成器（轮廓对齐版 v2）

v1（矢量重绘）的教训：形体是另画的，跟 16×16 勾线对不上——
猫耳高低、蘑菇伞形全跑偏，用户一眼看出「彩图跟轮廓不是一张图」。

v2 改成【从 16×16 草图直接放大上色】，轮廓逐格严格一致：
  ① 16→64：每格 4×4，剪影与草图完全相同（四块合拢演出时也严丝合缝）
  ② 黑格 = 勾线 → 用主体色暗部（彩色线稿，不是纯黑）
  ③ 白格 = 填色 → 按连通分区上色：纵向渐变 + 左上来光 + 边缘内阴影
  ④ 特征格（眼/鼻/耳内/菇斑/菌柄）按坐标表覆盖专属色
  ⑤ 柔软件（口鼻/腮红）径向混色，仍留在轮廓内 → 不破坏剪影
  ⑥ PIL 中位切量化到 30 色 + RLE，直接贴进 config.lua 的 M.ART64

产物：
  out/art64/<key>.png        64×64 成品
  out/art64/<key>_big.png    9× 放大预览
  out/art64/_overlay_big.png 草图轮廓 × 彩图叠图（一眼核对是否对齐）
  out/art64/_art64.lua       调色板 + RLE 数据

用法: python gen_art64.py
"""
import os
from collections import deque

from PIL import Image, ImageDraw, ImageFont

from from_sketch import SKETCHES, CN, parse

K = 4                      # 16 → 64 的放大倍数
S = 64
N = 16

# ================================================================
# 特征格表（0 基坐标；None = 用谓词，见 roles_of）
# ================================================================
FEATURES = {
    "cat": {
        "eye":   [(5, 6), (5, 7), (10, 6), (10, 7)],   # 两道竖瞳
        "nose":  [(7, 8), (8, 8)],                     # 小鼻
        "inner": [(3, 3), (13, 3)],                    # 耳廓内侧
    },
    "mushroom": {
        "dot":  [(6, 4), (9, 4)],                      # 伞盖两枚斑点
        "stem": None,                                  # y>=7 的黑格全是菌柄
    },
}

# ================================================================
# 配色（RGB）
# ================================================================
CAT = dict(
    fur_top=(199, 213, 233), fur_bot=(141, 159, 189),
    outline=(63, 76, 99),
    inner=(255, 159, 176), inner_dk=(238, 128, 148),
    eye=(34, 53, 78), glint=(255, 255, 255),
    nose=(238, 126, 148), nose_hi=(255, 158, 175),
)
CAT_SOFT = [                       # (cx, cy, r, color, k) 16 单位空间
    (8.0, 10.7, 3.10, (246, 250, 255), 0.62),   # 口鼻受光
    (4.0, 10.6, 1.80, (255, 150, 165), 0.45),   # 左腮红
    (12.0, 10.6, 1.80, (255, 150, 165), 0.45),  # 右腮红
]

MSH = dict(
    cap_top=(255, 162, 96), cap_mid=(238, 106, 47), cap_bot=(190, 60, 25),
    outline=(124, 42, 17),
    dot=(255, 246, 227), dot_rim=(233, 213, 180),
    stem_top=(246, 236, 215), stem_bot=(212, 195, 158),
    stem_edge=(163, 138, 98),
)


def clamp(v, lo=0.0, hi=1.0):
    return lo if v < lo else (hi if v > hi else v)


def mix(a, b, t):
    t = clamp(t)
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def shade(c, f):
    return tuple(max(0, min(255, int(round(v * f)))) for v in c)


# ================================================================
# 角色表：bg（外背景·透明）/ fill（内部白）/ outline / 特征名
# ================================================================
def white_regions(mask):
    lab = [[-1] * N for _ in range(N)]
    cur = 0
    for y in range(N):
        for x in range(N):
            if mask[y][x] == 0 and lab[y][x] == -1:
                q = deque([(x, y)])
                lab[y][x] = cur
                while q:
                    cx, cy = q.popleft()
                    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                        nx, ny = cx + dx, cy + dy
                        if 0 <= nx < N and 0 <= ny < N and mask[ny][nx] == 0 and lab[ny][nx] == -1:
                            lab[ny][nx] = cur
                            q.append((nx, ny))
                cur += 1
    return lab, cur


def roles_of(name, mask):
    lab, _nreg = white_regions(mask)
    # 外区 = 贴着边框的那个白格连通区 → 透明背景
    outside = -1
    for x in range(N):
        for y in (0, N - 1):
            if mask[y][x] == 0:
                outside = lab[y][x]
    for y in range(N):
        for x in (0, N - 1):
            if mask[y][x] == 0:
                outside = lab[y][x]

    feat_cells = {}
    for key, cells in FEATURES.get(name, {}).items():
        if cells:
            for (x, y) in cells:
                feat_cells[(x, y)] = key
    roles = [[None] * N for _ in range(N)]
    for y in range(N):
        for x in range(N):
            if (x, y) in feat_cells:
                roles[y][x] = feat_cells[(x, y)]
            elif mask[y][x] == 1:
                if name == "mushroom" and y >= 7:
                    roles[y][x] = "stem"
                else:
                    roles[y][x] = "outline"
            elif lab[y][x] == outside:
                roles[y][x] = "bg"
            else:
                roles[y][x] = "fill"
    return roles


# ================================================================
# 主绘制
# ================================================================
def ramp_mix(stops, t):
    """多 STOP 渐变：stops = [(pos0..1, color), ...] 按 pos 升序。"""
    t = clamp(t)
    for i in range(len(stops) - 1):
        p0, c0 = stops[i]
        p1, c1 = stops[i + 1]
        if t <= p1 or i == len(stops) - 2:
            span = max(1e-6, p1 - p0)
            return mix(c0, c1, (t - p0) / span)
    return stops[-1][1]


def build(name, mask):
    roles16 = roles_of(name, mask)

    # 剪影 = 除背景以外的所有格 → 渐变基准
    sil = [(x, y) for y in range(N) for x in range(N) if roles16[y][x] != "bg"]
    top_y = min(y for _, y in sil)
    bot_y = max(y for _, y in sil)

    # 放大到 64：角色逐格复制
    roles = [[None] * S for _ in range(S)]
    for y in range(N):
        for x in range(N):
            for yy in range(K):
                for xx in range(K):
                    roles[y * K + yy][x * K + xx] = roles16[y][x]

    # 距离变换：到最近「非 fill」的 64 像素（勾线/背景/特征）→ 内阴影
    INF = 999
    dist = [[INF] * S for _ in range(S)]
    q = deque()
    for y in range(S):
        for x in range(S):
            if roles[y][x] != "fill":
                dist[y][x] = 0
                q.append((x, y))
    head = 0
    while head < len(q):
        x, y = q[head]
        head += 1
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = x + dx, y + dy
            if 0 <= nx < S and 0 <= ny < S and dist[ny][nx] > dist[y][x] + 1:
                dist[ny][nx] = dist[y][x] + 1
                q.append((nx, ny))

    # 菌柄描边预计算（蘑菇）：64 像素级，左右边缘压暗
    stem_edge_px = set()
    if name == "mushroom":
        for y in range(S):
            for x in range(S):
                if roles[y][x] != "stem":
                    continue
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if not (0 <= nx < S and 0 <= ny < S) or roles[ny][nx] != "stem":
                        stem_edge_px.add((x, y))
                        break
        stem_top = top_y * K
        stem_h = max(1, (bot_y - top_y) * K)

    img = [[None] * S for _ in range(S)]
    for y in range(S):
        for x in range(S):
            role = roles[y][x]
            if role == "fill":
                # ---- 填色：渐变 + 来光 + 内阴影 ----
                if name == "cat":
                    t = clamp((y - top_y * K) / max(1.0, (bot_y - top_y) * K))
                    c = mix(CAT["fur_top"], CAT["fur_bot"], t)
                    c = mix(c, (255, 255, 255), 0.07 * (1 - x / float(S)))
                else:  # mushroom 伞盖
                    t = clamp((y - top_y * K) / 20.0)
                    c = ramp_mix([(0.0, MSH["cap_top"]), (0.55, MSH["cap_mid"]), (1.0, MSH["cap_bot"])], t)
                    c = mix(c, (255, 255, 255), 0.10 * (1 - (x / float(S) * 0.55 + y / float(S) * 0.45)))
                if dist[y][x] <= 3:
                    c = shade(c, 1.0 - 0.17 * (4 - dist[y][x]) / 3.0)
                img[y][x] = c
            elif role == "outline":
                img[y][x] = CAT["outline"] if name == "cat" else MSH["outline"]
            elif role == "eye":
                # 每枚眼占两格（4×8）；高光只落在上格的左上 1px
                cell_y = y // K
                sub_y = y - cell_y * K
                img[y][x] = CAT["glint"] if (x % K == 1 and sub_y == 1 and cell_y % 2 == 0) else CAT["eye"]
            elif role == "nose":
                sub_y = y - (y // K) * K
                img[y][x] = CAT["nose_hi"] if sub_y == 0 else CAT["nose"]
            elif role == "inner":
                sub_y = y - (y // K) * K
                img[y][x] = CAT["inner"] if sub_y < 3 else CAT["inner_dk"]
            elif role == "dot":
                lx, ly = x % K, y % K
                if lx in (0, 3) or ly in (0, 3):
                    img[y][x] = MSH["dot_rim"]
                else:
                    img[y][x] = MSH["dot"]
            elif role == "stem":
                t = clamp((y - stem_top) / float(stem_h))
                c = mix(MSH["stem_top"], MSH["stem_bot"], t)
                if (x, y) in stem_edge_px:
                    c = mix(c, MSH["stem_edge"], 0.75)
                img[y][x] = c
            # 其余（背景）保持 None = 透明

    # ---- 柔软件：径向混色，只作用于 fill 像素（不碰勾线和特征）----
    if name == "cat":
        for (cx, cy, r, col, k) in CAT_SOFT:
            ccx, ccy = cx * K, cy * K
            rr = r * K
            y0 = max(0, int(ccy - rr) - 1)
            y1 = min(S - 1, int(ccy + rr) + 1)
            x0 = max(0, int(ccx - rr) - 1)
            x1 = min(S - 1, int(ccx + rr) + 1)
            for y in range(y0, y1 + 1):
                for x in range(x0, x1 + 1):
                    if roles[y][x] != "fill":
                        continue
                    d = ((x + 0.5 - ccx) ** 2 + (y + 0.5 - ccy) ** 2) ** 0.5 / rr
                    if d < 1.0:
                        img[y][x] = mix(img[y][x], col, k * (1.0 - d) ** 1.5)
    return img


# ================================================================
# 量化 + RLE
# ================================================================
def quantize(img, maxcolors=30):
    SENT = (255, 0, 255)
    im = Image.new("RGB", (S, S), SENT)
    px = im.load()
    for y in range(S):
        for x in range(S):
            if img[y][x] is not None:
                px[x, y] = img[y][x]
    q = im.quantize(colors=maxcolors, method=Image.MEDIANCUT, dither=Image.NONE)
    pal_img = q.getpalette()
    idx = q.load()
    grid = [[None] * S for _ in range(S)]
    used, pal = {}, []
    for y in range(S):
        for x in range(S):
            if img[y][x] is None:
                continue
            i = idx[x, y]
            if i not in used:
                used[i] = len(pal)
                pal.append("%02X%02X%02X" % (pal_img[i * 3], pal_img[i * 3 + 1], pal_img[i * 3 + 2]))
            grid[y][x] = used[i]
    return pal, grid


def rle_rows(grid):
    """每行整行 64 px 全覆盖；连续段 >35 拆成多段（CH 只有 36 个字符）。"""
    CH = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    rows = []
    for y in range(S):
        runs, prev, cnt = [], None, 0
        for x in range(S):
            key = -1 if grid[y][x] is None else grid[y][x]
            if key == prev:
                cnt += 1
            else:
                if prev is not None:
                    runs.append((prev, cnt))
                prev, cnt = key, 1
        runs.append((prev, cnt))
        s = ""
        for (i, c) in runs:
            left = c
            while left > 0:
                n = min(left, 35)
                s += CH[35 if i < 0 else i] + CH[n]
                left -= n
        rows.append(s)
    return rows


def to_image(img, path, scale=9):
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    px = im.load()
    for y in range(S):
        for x in range(S):
            c = img[y][x]
            if c:
                px[x, y] = (c[0], c[1], c[2], 255)
    im.save(path)
    im.resize((S * scale, S * scale), Image.NEAREST).save(path.replace(".png", "_big.png"))
    return im


def overlay(mask, img, path, scale=9):
    """草图轮廓（红）× 彩图剪影（白）叠图：一眼核对两者是否对齐。"""
    W, H = S * scale, S * scale
    c = Image.new("RGBA", (W, H), (24, 28, 40, 255))
    d = ImageDraw.Draw(c)
    # 彩图剪影（放大最近邻）
    sil = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    sp = sil.load()
    for y in range(S):
        for x in range(S):
            if img[y][x] is not None:
                sp[x, y] = (120, 200, 255, 255)
    c.paste(sil.resize((W, H), Image.NEAREST), (0, 0), sil.resize((W, H), Image.NEAREST))
    # 草图黑格（红）
    for y in range(N):
        for x in range(N):
            if mask[y][x]:
                d.rectangle([x * K * scale, y * K * scale, (x + 1) * K * scale - 1, (y + 1) * K * scale - 1],
                            fill=(255, 80, 80, 255))
    c.save(path)


def main():
    HERE = os.path.dirname(os.path.abspath(__file__))
    OUT = os.path.join(HERE, "out", "art64")
    os.makedirs(OUT, exist_ok=True)
    try:
        font = ImageFont.truetype(r"C:/Windows/Fonts/msyh.ttc", 15)
    except Exception:
        font = ImageFont.load_default()

    keys = ["mushroom", "cat"]
    lua = ["M.ART64 = {"]
    for key in keys:
        mask = parse(SKETCHES[key])
        img = build(key, mask)
        to_image(img, os.path.join(OUT, key + ".png"))
        overlay(mask, img, os.path.join(OUT, "_overlay_" + key + ".png"))

        pal, grid = quantize(img, 30)
        rows = rle_rows(grid)
        lua.append("    %s = {" % key)
        lua.append("        pal = { %s }," % ", ".join('"%s"' % p for p in pal))
        lua.append("        rows = {")
        for r in rows:
            lua.append('            "%s",' % r)
        lua.append("        },")
        lua.append("    },")
        print("%-9s 调色板 %2d 色 | RLE 字符 %d" % (key, len(pal), sum(len(r) for r in rows)))
    lua.append("}")
    with open(os.path.join(OUT, "_art64.lua"), "w", encoding="utf-8") as f:
        f.write("\n".join(lua) + "\n")

    # 16 草图 vs 64 彩图 对照拼版（左 16 放大 / 右 64 放大）
    tiles = []
    for key in keys:
        mask = parse(SKETCHES[key])
        img = build(key, mask)
        left = Image.new("RGB", (16 * 8, 16 * 8), (255, 255, 255))
        lp = left.load()
        for y in range(N):
            for x in range(N):
                if mask[y][x]:
                    for yy in range(8):
                        for xx in range(8):
                            lp[x * 8 + xx, y * 8 + yy] = (20, 20, 20)
        right = to_image(img, os.path.join(OUT, "_tmp.png"), scale=4)
        c = Image.new("RGB", (16 * 8 + 16 + 64 * 4 + 16, 64 * 4 + 40), (18, 22, 34))
        c.paste(left, (8, 40))
        c.paste(right, (16 * 8 + 24, 8))
        d = ImageDraw.Draw(c)
        d.text((8, 10), "%s 16×16 勾线" % CN[key], font=font, fill=(220, 230, 245))
        d.text((16 * 8 + 24, 10), "%s 64×64 彩图（轮廓对齐）" % CN[key], font=font, fill=(220, 230, 245))
        tiles.append(c)
    W = max(t.size[0] for t in tiles)
    H = sum(t.size[1] for t in tiles) + 8
    sheet = Image.new("RGB", (W, H), (12, 15, 24))
    yy = 0
    for t in tiles:
        sheet.paste(t, (0, yy))
        yy += t.size[1] + 4
    sheet.save(os.path.join(OUT, "_compare.png"))
    print("写出 _compare.png / _overlay_*.png")


if __name__ == "__main__":
    main()
