# -*- coding: utf-8 -*-
"""
点灯迷题 16 · 64×64 彩色画生成器（矢量重绘版）

为什么不直接把 16×16 放大 4 倍：
  1×1 的线放大到 4×4 会变成 4px 粗黑边，成品像"描边框"而不是插画；
  小图的直角折线放大后也还是台阶。所以这里在 64 分辨率上用矢量形体**重绘**，
  轮廓与 16×16 线稿大致一致（可对照预览确认），但曲线是真正的 64px 曲线。

产物：
  out/art64/<key>.png        64×64 成品
  out/art64/<key>_big.png    8× 放大预览
  out/art64/_art64.lua       可直接贴进 config.lua 的调色板 + RLE 数据

用法: python gen_art64.py
"""
import os

from PIL import Image

from gen_art import (
    _ellipse_mask, _poly_mask, _union, _diff,
)

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "out", "art64")
os.makedirs(OUT, exist_ok=True)

N = 64


def _shade(c, f):
    return tuple(max(0, min(255, int(round(v * f)))) for v in c)


def _mix(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def _ramp(hexes):
    return [tuple(int(h[i:i + 2], 16) for i in (0, 2, 4)) for h in hexes]


def _pick(ramp, t):
    """在色阶上按 t∈[0,1] 取色（连续插值，最后统一量化）"""
    t = 0.0 if t < 0 else (1.0 if t > 1 else t)
    pos = t * (len(ramp) - 1)
    i = int(pos)
    if i >= len(ramp) - 1:
        return ramp[-1]
    return _mix(ramp[i], ramp[i + 1], pos - i)


# ================================================================
# 主体：每个函数返回 [(mask, key), ...]，后面的覆盖前面的
# ================================================================
def subject_mushroom(n=N):
    """蘑菇：菌柄 + 伞盖 + 菌褶 + 白斑
    ★ 形体坐标一律用 16 单位空间（gen_art 的 _ellipse_mask 等会按 n/16 自动放大）"""
    parts = []

    stem = _union(
        _poly_mask(n, [(7.05, 6.4), (8.95, 6.4), (9.35, 11.9), (6.65, 11.9)]),
        _ellipse_mask(n, 6.75, 11.9, 0.55, 0.45),
        _ellipse_mask(n, 9.25, 11.9, 0.55, 0.45),
    )
    parts.append((stem, "stem"))

    cap = _ellipse_mask(n, 8.0, 6.25, 6.5, 3.9)
    cap = _diff(cap, _poly_mask(n, [(-1, 6.95), (17, 6.95), (17, 17), (-1, 17)]))
    for i, cx in enumerate((2.5, 4.5, 6.4, 8.2, 10.0, 11.8, 13.5)):
        cap = _union(cap, _ellipse_mask(n, cx, 6.85, 1.15, 0.55 + (i % 2) * 0.15))
    parts.append((cap, "cap"))

    for (cx, cy, rx, ry) in ((5.25, 4.4, 1.2, 1.05), (8.35, 3.6, 0.95, 0.85),
                             (10.9, 4.9, 1.0, 0.9), (3.35, 5.8, 0.7, 0.6)):
        parts.append((_ellipse_mask(n, cx, cy, rx, ry), "dot"))
    return parts


def subject_cat(n=N):
    """猫脸：耳 + 头 + 耳内 + 口鼻 + 眼 + 鼻 + 腮红（同样用 16 单位空间）"""
    parts = []

    ear_l = _poly_mask(n, [(2.85, 7.6), (3.25, 2.1), (6.9, 5.0)])
    ear_r = _poly_mask(n, [(13.15, 7.6), (12.75, 2.1), (9.1, 5.0)])
    parts.append((_union(ear_l, ear_r), "fur"))

    head = _union(
        _ellipse_mask(n, 8.0, 8.0, 5.5, 5.05),
        _poly_mask(n, [(2.85, 7.6), (13.15, 7.6), (13.15, 10.2), (2.85, 10.2)]),
    )
    parts.append((head, "fur"))

    parts.append((_poly_mask(n, [(3.75, 6.8), (3.9, 3.5), (6.0, 5.4)]), "inner"))
    parts.append((_poly_mask(n, [(12.25, 6.8), (12.1, 3.5), (10.0, 5.4)]), "inner"))

    parts.append((_ellipse_mask(n, 8.0, 10.85, 3.5, 2.55), "muzzle"))

    parts.append((_ellipse_mask(n, 5.9, 8.25, 0.85, 1.05), "eye"))
    parts.append((_ellipse_mask(n, 10.1, 8.25, 0.85, 1.05), "eye"))
    parts.append((_ellipse_mask(n, 5.6, 7.9, 0.28, 0.32), "glint"))
    parts.append((_ellipse_mask(n, 9.8, 7.9, 0.28, 0.32), "glint"))
    parts.append((_poly_mask(n, [(7.45, 10.0), (8.55, 10.0), (8.0, 10.8)]), "nose"))

    parts.append((_ellipse_mask(n, 4.4, 10.5, 0.85, 0.5), "blush"))
    parts.append((_ellipse_mask(n, 11.6, 10.5, 0.85, 0.5), "blush"))
    return parts


RAMPS = {
    "mushroom": {
        "cap":   _ramp(["6B1308", "9C2A11", "C63E1B", "E4572E", "F5804E", "FFAE7A", "FFD2AE"]),
        "stem":  _ramp(["9C8768", "BCAA88", "D8C9AC", "ECE2CB", "FBF5E6", "FFFDF6"]),
        "gills": _ramp(["A9795A", "C79A78", "E2BE9C"]),
        "dot":   _ramp(["FFF3DF", "FFFCF3", "FFFFFF"]),
    },
    "cat": {
        "fur":    _ramp(["46505F", "5D6A7C", "77869B", "93A2B6", "B2BFD0", "D2DCE8", "ECF1F7"]),
        "inner":  _ramp(["B85C6B", "E07C88", "FF9AA2", "FFC2C7"]),
        "muzzle": _ramp(["C8D5E3", "E2EBF4", "F6FAFE", "FFFFFF"]),
        "stripe": _ramp(["3C4553", "556072", "6E7A8C"]),
        "eye":    _ramp(["0E1620", "1B2A3A", "2C4159", "3E6187", "6E96BE"]),
        "nose":   _ramp(["B84B60", "D9627A", "FF8FA3", "FFB3C1"]),
        "blush":  _ramp(["D96A78", "F08A96", "FFAEB6"]),
        "glint":  _ramp(["FFFFFF", "FFFFFF"]),
    },
}


SOFT_PARTS = {"muzzle", "glint", "blush", "dot"}


def paint(parts, ramps, outline_f=0.55):
    """分区上色 + 体积感 + 1px 描边"""
    owner = [[-1] * N for _ in range(N)]
    for idx, (mask, _key) in enumerate(parts):
        for y in range(N):
            for x in range(N):
                if mask[y][x]:
                    owner[y][x] = idx

    boxes = []
    for idx, _ in enumerate(parts):
        ys = [y for y in range(N) for x in range(N) if owner[y][x] == idx]
        xs = [x for y in range(N) for x in range(N) if owner[y][x] == idx]
        boxes.append((min(ys), max(ys), min(xs), max(xs)) if ys else (0, N - 1, 0, N - 1))

    dist = [[99] * N for _ in range(N)]
    stack = []
    for y in range(N):
        for x in range(N):
            if owner[y][x] < 0:
                dist[y][x] = 0
                stack.append((x, y))
    head = 0
    while head < len(stack):
        x, y = stack[head]
        head += 1
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = x + dx, y + dy
            if 0 <= nx < N and 0 <= ny < N and dist[ny][nx] > dist[y][x] + 1:
                dist[ny][nx] = dist[y][x] + 1
                stack.append((nx, ny))

    img = [[None] * N for _ in range(N)]
    for y in range(N):
        for x in range(N):
            idx = owner[y][x]
            if idx < 0:
                continue
            key = parts[idx][1]
            ramp = ramps.get(key) or [(255, 255, 255)]
            y0, y1, x0, x1 = boxes[idx]
            ty = 0.0 if y1 <= y0 else (y - y0) / float(y1 - y0)
            t = 0.18 + 0.62 * (1.0 - ty) + 0.14 * (1.0 - x / float(N))
            t -= 0.18 * max(0.0, 1.0 - dist[y][x] / 6.0)
            img[y][x] = _pick(ramp, t)

    for y in range(N):
        for x in range(N):
            idx = owner[y][x]
            if idx < 0:
                continue
            key = parts[idx][1]
            ramp = ramps.get(key) or [(255, 255, 255)]
            is_edge = False
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if nx < 0 or ny < 0 or nx >= N or ny >= N or owner[ny][nx] != idx:
                    is_edge = True
                    break
            if is_edge:
                outer = False
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if nx < 0 or ny < 0 or nx >= N or ny >= N or owner[ny][nx] < 0:
                        outer = True
                        break
                if outer:
                    img[y][x] = _shade(ramp[0], outline_f + 0.30)
                elif key in SOFT_PARTS:
                    pass                     # 柔软件：内部边保持原渐变
                else:
                    img[y][x] = _pick(ramp, 0.30)

    for y in range(N):
        for x in range(N):
            idx = owner[y][x]
            if idx < 0 or dist[y][x] != 1:
                continue
            above_open = (y == 0) or owner[y - 1][x] != idx
            if above_open and (x + y) < N * 1.15:
                key = parts[idx][1]
                ramp = ramps.get(key) or [(255, 255, 255)]
                img[y][x] = _pick(ramp, 0.92)
    return img


# ================================================================
# 量化 + RLE
# ================================================================
def quantize(img, maxcolors=30):
    SENT = (255, 0, 255)
    im = Image.new("RGB", (N, N), SENT)
    px = im.load()
    for y in range(N):
        for x in range(N):
            if img[y][x] is not None:
                px[x, y] = img[y][x]
    q = im.quantize(colors=maxcolors, method=Image.MEDIANCUT, dither=Image.NONE)
    pal_img = q.getpalette()
    idx = q.load()
    grid = [[None] * N for _ in range(N)]
    used, pal = {}, []
    for y in range(N):
        for x in range(N):
            if img[y][x] is None:
                continue
            i = idx[x, y]
            if i not in used:
                used[i] = len(pal)
                pal.append("%02X%02X%02X" % (pal_img[i * 3], pal_img[i * 3 + 1], pal_img[i * 3 + 2]))
            grid[y][x] = used[i]
    return pal, grid


def rle_rows(grid):
    CH = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    rows = []
    for y in range(N):
        runs, prev, cnt = [], None, 0
        for x in range(N):
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
            s += CH[35 if i < 0 else i] + CH[min(c, 35)]
        rows.append(s)
    return rows


def save(img, path, scale=9):
    im = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    px = im.load()
    for y in range(N):
        for x in range(N):
            c = img[y][x]
            if c:
                px[x, y] = (c[0], c[1], c[2], 255)
    im.save(path)
    im.resize((N * scale, N * scale), Image.NEAREST).save(path.replace(".png", "_big.png"))
    return im


def main():
    arts = {
        "mushroom": (subject_mushroom(), RAMPS["mushroom"]),
        "cat": (subject_cat(), RAMPS["cat"]),
    }
    lua = ["M.ART64 = {"]
    for key, (parts, ramps) in arts.items():
        img = paint(parts, ramps)
        save(img, os.path.join(OUT, key + ".png"))
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
    print("写出 _art64.lua")


if __name__ == "__main__":
    main()
