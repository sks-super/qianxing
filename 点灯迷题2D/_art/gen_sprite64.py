# -*- coding: utf-8 -*-
"""
点灯迷题 16 · 64×64 像素画生成器（先精细、后派生）

用户反馈"彩图太丑"后的新管线（v3）：
  ① 先在 64×64 上画一张**真正好看的像素画**——参考 MC / 泰拉瑞亚 / 蔚蓝：
       · 硬边色阶：每种材质只有 亮/中/暗 三档，绝不做平滑渐变（渐变=糊）
       · 2px 粗描边 + 1px 内侧深色环（贴纸感，小图也立得住）
       · 受光在左上：高光团 + 右下内缘投影
       · 特征区（眼/鼻/嘴/耳内/腮红/口鼻）各自纯色，边界干净
  ② 再从成品**反推 16×16**：4×4 块里"墨色"像素（描边/深环/眼/鼻/嘴）
     占比 ≥50% → 黑格，否则白格。轮廓和彩图因此永远是同一张图。

产物：
  out/sprite64/cat64.png / cat64_big.png   64×64 成品 + 9× 预览
  out/sprite64/cat16.png / cat16_big.png   派生 16×16 + 8× 预览
  out/sprite64/_sprite.lua                 ART64.cat 的 pal/rows
  out/sprite64/_pic16.lua                  CAT 的 16 行点阵

用法: python gen_sprite64.py
"""
import os

from PIL import Image, ImageDraw, ImageFont

S = 64
N = 16
K = S // N

# ================================================================
# 调色板（字符 → 颜色）；INK = 参与 16×16 轮廓派生的"墨色"
# ================================================================
PAL = {
    "O": "232A3C",   # 描边（2px）
    "d": "465173",   # 描边内侧深色环（1px）
    "h": "E9F0FA",   # 毛·亮（高光团）
    "f": "A9B8D2",   # 毛·中
    "s": "76859F",   # 毛·暗（右下投影）
    "t": "8E9DBB",   # 额头浅纹
    "P": "FFAEBE",   # 耳内·亮
    "p": "F08CA2",   # 耳内·暗
    "M": "FBF3E4",   # 口鼻奶白
    "B": "FFA9B6",   # 腮红
    "E": "1E3A5C",   # 眼
    "W": "FFFFFF",   # 眼睛高光
    "N": "E06A82",   # 鼻
    "T": "3A4257",   # 嘴
}
INK = {"O", "d", "E", "N", "T"}

RGB = {k: tuple(int(v[i:i + 2], 16) for i in (0, 2, 4)) for k, v in PAL.items()}


# ================================================================
# 基础图元
# ================================================================
def fill_ellipse(grid, cx, cy, rx, ry, ch):
    for y in range(S):
        for x in range(S):
            if ((x - cx) / float(rx)) ** 2 + ((y - cy) / float(ry)) ** 2 <= 1.0:
                if 0 <= x < S and 0 <= y < S:
                    grid[y][x] = ch


def fill_poly(grid, pts, ch):
    """偶数奇偶扫描线填充（pts = [(x,y), ...] 浮点也可）"""
    ys = [p[1] for p in pts]
    y0, y1 = int(max(0, min(ys))), int(min(S - 1, max(ys)))
    for y in range(y0, y1 + 1):
        xs = []
        for i in range(len(pts)):
            x1, y1_ = pts[i]
            x2, y2 = pts[(i + 1) % len(pts)]
            if y1_ == y2:
                continue
            if min(y1_, y2) <= y < max(y1_, y2):
                xs.append(x1 + (y - y1_) * (x2 - x1) / float(y2 - y1_))
        xs.sort()
        for i in range(0, len(xs) - 1, 2):
            for x in range(int(xs[i]), int(xs[i + 1]) + 1):
                if 0 <= x < S:
                    grid[y][x] = ch


def fill_line(grid, p0, p1, ch, thick=2):
    """粗折线：沿线逐步画 thick×thick 方块"""
    x0, y0 = p0
    x1, y1 = p1
    steps = int(max(abs(x1 - x0), abs(y1 - y0)) * 2) + 1
    for i in range(steps + 1):
        t = i / float(steps)
        cx = x0 + (x1 - x0) * t
        cy = y0 + (y1 - y0) * t
        r = thick // 2
        for dy in range(-r, r + 1):
            for dx in range(-r, r + 1):
                x, y = int(round(cx)) + dx, int(round(cy)) + dy
                if 0 <= x < S and 0 <= y < S:
                    grid[y][x] = ch


# ================================================================
# 头部轮廓（手调的行边界；右半由镜像得到）
#   ★ 两侧刻意留平：左右边在 x=10 / x=53 各平 20 行，4×4 分块时
#     描边才能整块吃满 → 派生 16×16 的轮廓不断线。斜边只留在头顶与下巴。
# ================================================================
HEAD_LEFT = {
    14: 26, 15: 24, 16: 22, 17: 20, 18: 18, 19: 16, 20: 15, 21: 13,
    22: 12, 23: 11, 24: 11, 25: 10, 26: 10, 27: 10, 28: 10, 29: 10,
    30: 10, 31: 10, 32: 10, 33: 10, 34: 10, 35: 10, 36: 10, 37: 10,
    38: 10, 39: 10, 40: 10, 41: 10, 42: 10, 43: 10, 44: 10, 45: 11,
    46: 11, 47: 12, 48: 13, 49: 14, 50: 15, 51: 17, 52: 19, 53: 21,
    54: 23, 55: 26, 56: 28,
}

EAR_L = [(9, 4), (28, 14), (16, 28)]      # 左耳：尖 / 内基 / 外基
EAR_R = [(S - 1 - 9, 4), (S - 1 - 28, 14), (S - 1 - 16, 28)]


def build_silhouette():
    sil = [[False] * S for _ in range(S)]
    for y, xl in HEAD_LEFT.items():
        xr = S - 1 - xl
        for x in range(xl, xr + 1):
            sil[y][x] = True
    for ear in (EAR_L, EAR_R):
        pts = [(float(x), float(y)) for x, y in ear]
        tmp = [["."] * S for _ in range(S)]
        fill_poly(tmp, pts, "x")
        for y in range(S):
            for x in range(S):
                if tmp[y][x] == "x":
                    sil[y][x] = True
    return sil


def dist_to_edge(sil):
    """剪影内每个像素到最近"非剪影"的距离（BFS，4 邻）"""
    INF = 999
    dist = [[INF] * S for _ in range(S)]
    stack = []
    for y in range(S):
        for x in range(S):
            if not sil[y][x]:
                dist[y][x] = 0
                stack.append((x, y))
    head = 0
    while head < len(stack):
        x, y = stack[head]
        head += 1
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = x + dx, y + dy
            if 0 <= nx < S and 0 <= ny < S and dist[ny][nx] > dist[y][x] + 1:
                dist[ny][nx] = dist[y][x] + 1
                stack.append((nx, ny))
    return dist


# ================================================================
# 主绘制
# ================================================================
def build():
    sil = build_silhouette()
    dist = dist_to_edge(sil)

    # ① 打底：描边 + 深环 + 毛中色
    #   ★ dist=1 就是最外层剪影像素（BFS 从"非剪影"的 0 开始扩），所以
    #     dist<=2 → 2px 描边，dist==3 → 1px 内侧深环，合计 3px 墨边
    grid = [[None] * S for _ in range(S)]
    for y in range(S):
        for x in range(S):
            if not sil[y][x]:
                continue
            if dist[y][x] <= 2:
                grid[y][x] = "O"
            elif dist[y][x] == 3:
                grid[y][x] = "d"
            else:
                grid[y][x] = "f"

    def paint_region(mask_ch, ch, need_dist=True, min_dist=4):
        for y in range(S):
            for x in range(S):
                if mask_ch[y][x] and sil[y][x] and (not need_dist or dist[y][x] >= min_dist):
                    grid[y][x] = ch

    def new_mask():
        return [[False] * S for _ in range(S)]

    # ② 明暗：左上高光团 + 右下投影（硬边，两档）
    hi = new_mask()
    fill_ellipse(hi, 23, 25, 11, 9, True)
    paint_region(hi, "h")
    sh = new_mask()
    for y in range(S):
        for x in range(S):
            if x + y > 84 or (y >= 48 and x >= 22):
                sh[y][x] = True
    paint_region(sh, "s")

    # ③ 耳内粉：耳多边形 ∩ 头部以外 ∩ 距边界≥4；上亮下暗
    for ear in (EAR_L, EAR_R):
        m = new_mask()
        fill_poly(m, [(float(a), float(b)) for a, b in ear], True)
        head_only = new_mask()
        for y, xl in HEAD_LEFT.items():
            for x in range(xl, S - xl):
                head_only[y][x] = True
        for y in range(S):
            for x in range(S):
                if m[y][x] and sil[y][x] and not head_only[y][x] and dist[y][x] >= 4:
                    grid[y][x] = "p" if y >= 13 else "P"

    # ④ 口鼻浅色区（奶白，比脸亮一档；眼睛之后画，避免盖住眼）
    mz = new_mask()
    fill_ellipse(mz, 32, 50, 10, 6.5, True)
    paint_region(mz, "M")

    # ⑤ 腮红
    for cx in (17, 47):
        bl = new_mask()
        fill_ellipse(bl, cx, 46, 4.0, 3.0, True)
        paint_region(bl, "B")

    # ⑥ 眼睛（深蓝椭圆 + 左上 3×3 高光 + 右下 2×2 小高光）
    for cx in (22, 42):
        ey = new_mask()
        fill_ellipse(ey, cx, 34, 5.0, 6.0, True)
        paint_region(ey, "E")
        gl = new_mask()
        fill_ellipse(gl, cx - 3, 31, 2.0, 2.0, True)
        paint_region(gl, "W", need_dist=False)
        gl2 = new_mask()
        fill_ellipse(gl2, cx + 2.5, 37.5, 1.4, 1.4, True)
        paint_region(gl2, "W", need_dist=False)

    # ⑦ 额头三道浅纹（MC 猫的条纹感，2px 宽）
    for sx in (27, 31, 35):
        st = new_mask()
        for yy in range(17, 23):
            for xx in (sx, sx + 1):
                if 0 <= xx < S:
                    st[yy][xx] = True
        paint_region(st, "t")

    # ⑧ 鼻（小三角）+ 嘴（ω 两条 2px 短线）
    nose = new_mask()
    fill_poly(nose, [(29.0, 42.0), (35.0, 42.0), (32.0, 47.0)], True)
    paint_region(nose, "N")
    mouth = new_mask()
    fill_line(mouth, (31, 48), (29, 51), True)
    fill_line(mouth, (33, 48), (35, 51), True)
    paint_region(mouth, "T")

    return grid, sil


# ================================================================
# 派生 16×16：4×4 块内墨色占比 ≥50% → 黑
# ================================================================
def derive16(grid):
    out = []
    for by in range(N):
        row = []
        for bx in range(N):
            n = 0
            for yy in range(K):
                for xx in range(K):
                    if grid[by * K + yy][bx * K + xx] in INK:
                        n += 1
            row.append(1 if n * 2 >= K * K else 0)
        out.append(row)
    return out


# ================================================================
# 输出
# ================================================================
def to_png(grid, path, scale, bg=None):
    w, h = S * scale, S * scale
    im = Image.new("RGBA", (w, h), bg if bg else (0, 0, 0, 0))
    dr = ImageDraw.Draw(im)
    for y in range(S):
        for x in range(S):
            ch = grid[y][x]
            if not ch:
                continue
            c = RGB[ch]
            dr.rectangle([x * scale, y * scale, (x + 1) * scale - 1, (y + 1) * scale - 1],
                         fill=(c[0], c[1], c[2], 255))
    im.save(path)
    return im


def mask_to_png(mask, path, scale, on=(26, 30, 42), off=(255, 255, 255)):
    im = Image.new("RGB", (N * scale, N * scale), off)
    dr = ImageDraw.Draw(im)
    for y in range(N):
        for x in range(N):
            if mask[y][x]:
                dr.rectangle([x * scale, y * scale, (x + 1) * scale - 1, (y + 1) * scale - 1], fill=on)
    im.save(path)
    return im


def ascii_preview(grid):
    """字符画预览（终端/日志里直接看剪影）"""
    return "\n".join("".join(grid[y][x] or "." for x in range(S)) for y in range(S))


CH = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"
TRANSPARENT = 35


def rle_rows(grid, idx_of):
    """idx_of: 字符 → 调色板下标；None（透明）→ 35。连续段 >35 拆多段。"""
    rows = []
    for y in range(S):
        runs, prev, cnt = [], None, 0
        for x in range(S):
            key = grid[y][x]
            if key == prev:
                cnt += 1
            else:
                if prev is not None:
                    runs.append((prev, cnt))
                prev, cnt = key, 1
        runs.append((prev, cnt))
        s = ""
        for (ch, c) in runs:
            i = TRANSPARENT if ch is None else idx_of[ch]
            left = c
            while left > 0:
                n = min(left, 35)
                s += CH[i] + CH[n]
                left -= n
        rows.append(s)
    return rows


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    out = os.path.join(here, "out", "sprite64")
    os.makedirs(out, exist_ok=True)

    grid, sil = build()
    mask16 = derive16(grid)

    # 预览
    to_png(grid, os.path.join(out, "cat64.png"), 1)
    to_png(grid, os.path.join(out, "cat64_big.png"), 9)
    mask_to_png(mask16, os.path.join(out, "cat16.png"), 8)
    mask_to_png(mask16, os.path.join(out, "cat16_big.png"), 16)

    # 64 与 16 并排对照
    try:
        font = ImageFont.truetype(r"C:/Windows/Fonts/msyh.ttc", 14)
    except Exception:
        font = ImageFont.load_default()
    a = Image.open(os.path.join(out, "cat64_big.png")).convert("RGBA")
    b = Image.open(os.path.join(out, "cat16_big.png")).convert("RGBA")
    W = a.size[0] + b.size[0] + 48
    H = max(a.size[1], b.size[1]) + 56
    c = Image.new("RGBA", (W, H), (18, 22, 34, 255))
    c.paste(a, (8, 40), a)
    c.paste(b, (a.size[0] + 24, 40), b)
    dr = ImageDraw.Draw(c)
    dr.text((8, 12), "64×64 像素画（MC/泰拉瑞亚/蔚硬边风格）", font=font, fill=(220, 230, 245))
    dr.text((a.size[0] + 24, 12), "派生 16×16 轮廓（墨块≥50%）", font=font, fill=(220, 230, 245))
    c.save(os.path.join(out, "_compare.png"))

    # ART64 Lua（pal + RLE）；透明 = 35
    used, pal = {}, []
    for y in range(S):
        for x in range(S):
            ch = grid[y][x]
            if ch is None:
                continue
            if ch not in used:
                used[ch] = len(pal)
                pal.append(PAL[ch])
    rows = rle_rows(grid, used)
    with open(os.path.join(out, "_sprite.lua"), "w", encoding="utf-8") as f:
        f.write("M.ART64.cat = {\n")
        f.write("    pal = { %s },\n" % ", ".join('"%s"' % p for p in pal))
        f.write("    rows = {\n")
        for r in rows:
            f.write('        "%s",\n' % r)
        f.write("    },\n}\n")

    # 16×16 点阵（替换 config 的 CAT）
    with open(os.path.join(out, "_pic16.lua"), "w", encoding="utf-8") as f:
        f.write("local CAT = {\n")
        for row in mask16:
            f.write('"%s",\n' % "".join("#" if v else "." for v in row))
        f.write("}\n")

    print("调色板 %d 色 | RLE 字符 %d" % (len(pal), sum(len(r) for r in rows)))
    print("16×16 黑格 %d / 256" % sum(sum(r) for r in mask16))
    print("\n--- 16×16 派生轮廓 ---")
    for row in mask16:
        print("".join("#" if v else "." for v in row))


if __name__ == "__main__":
    main()
