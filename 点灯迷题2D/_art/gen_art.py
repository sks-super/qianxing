# -*- coding: utf-8 -*-
"""
点灯迷题 2D · 关卡图生成器
============================================================
同一套「矢量形体」同时产出两种图，保证轮廓严格对应：

  16x16  黑白勾线画  = 所有形体并集的【外轮廓】（1px）
  64x64  精细彩色画  = 同一套形体按 4 倍精度重绘 + 分区上色 + 描边 + 纵向明暗 + 高光

坐标一律写在 16 单位设计空间里，渲染时乘以 n/16 映射到目标网格，
所以 16 与 64 两版在几何上是同一张画，只是精度不同。

用法：
  python gen_art.py
产物：
  out/16/<name>.png   原尺寸 16x16（最近邻放大 16 倍存 preview）
  out/64/<name>.png   原尺寸 64x64（最近邻放大 4 倍存 preview）
  out/sheet_16.png    6 张勾线画拼版
  out/sheet_64.png    6 张彩色画拼版
"""

import os
import math

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "out")

# ============================================================
# 基础光栅器（n = 目标网格边长；坐标仍用 16 单位制）
# ============================================================


def _k(n):
    return n / 16.0


def _ellipse_mask(n, cx, cy, rx, ry):
    k = _k(n)
    m = [[False] * n for _ in range(n)]
    for y in range(n):
        py = (y + 0.5) / k
        for x in range(n):
            px = (x + 0.5) / k
            if ((px - cx) / rx) ** 2 + ((py - cy) / ry) ** 2 <= 1.0:
                m[y][x] = True
    return m


def _rect_mask(n, x0, y0, x1, y1):
    k = _k(n)
    m = [[False] * n for _ in range(n)]
    for y in range(n):
        py = (y + 0.5) / k
        for x in range(n):
            px = (x + 0.5) / k
            if x0 <= px <= x1 and y0 <= py <= y1:
                m[y][x] = True
    return m


def _poly_mask(n, pts):
    k = _k(n)
    m = [[False] * n for _ in range(n)]
    p = [(x, y) for x, y in pts]
    for y in range(n):
        py = (y + 0.5) / k
        for x in range(n):
            px = (x + 0.5) / k
            inside = False
            j = len(p) - 1
            for i in range(len(p)):
                xi, yi = p[i]
                xj, yj = p[j]
                if (yi > py) != (yj > py):
                    xc = xi + (py - yi) * (xj - xi) / (yj - yi)
                    if px < xc:
                        inside = not inside
                j = i
            m[y][x] = inside
    return m


def _line_mask(n, x0, y0, x1, y1, width=1.0):
    """粗线段：按到线段的距离判定（width 用 16 单位制）"""
    k = _k(n)
    m = [[False] * n for _ in range(n)]
    dx, dy = x1 - x0, y1 - y0
    L2 = dx * dx + dy * dy or 1e-9
    for y in range(n):
        py = (y + 0.5) / k
        for x in range(n):
            px = (x + 0.5) / k
            t = ((px - x0) * dx + (py - y0) * dy) / L2
            t = max(0.0, min(1.0, t))
            qx, qy = x0 + dx * t, y0 + dy * t
            if (px - qx) ** 2 + (py - qy) ** 2 <= (width / 2.0) ** 2:
                m[y][x] = True
    return m


def _union(*masks):
    n = len(masks[0])
    out = [[False] * n for _ in range(n)]
    for m in masks:
        for y in range(n):
            for x in range(n):
                if m[y][x]:
                    out[y][x] = True
    return out


def _diff(a, b):
    n = len(a)
    return [[a[y][x] and not b[y][x] for x in range(n)] for y in range(n)]


def _erode(mask):
    n = len(mask)
    out = [[False] * n for _ in range(n)]
    for y in range(n):
        for x in range(n):
            if not mask[y][x]:
                continue
            ok = True
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if nx < 0 or ny < 0 or nx >= n or ny >= n or not mask[ny][nx]:
                    ok = False
                    break
            if ok:
                out[y][x] = True
    return out


def contour(mask):
    """填充区 → 1px 外轮廓"""
    return _diff(mask, _erode(mask))


# ============================================================
# 形体定义（16 单位制）
#   每个 part = (mask 工厂, 颜色)
#   line_extra = 额外的纯线条（如腿、胡须），在 16 版里也画出来
# ============================================================


def subject_sun(n):
    parts = []
    disc = _ellipse_mask(n, 8, 8, 3.3, 3.3)
    parts.append((disc, "sun"))
    rays = []
    for i in range(8):
        a = math.pi * 2 * i / 8
        rays.append(_line_mask(n, 8 + math.cos(a) * 5.0, 8 + math.sin(a) * 5.0,
                               8 + math.cos(a) * 7.2, 8 + math.sin(a) * 7.2, 1.3))
    parts.append((_union(*rays), "ray"))
    return parts


def subject_flower(n):
    petals = []
    for i in range(5):
        a = -math.pi / 2 + math.pi * 2 * i / 5
        petals.append(_ellipse_mask(n, 8 + math.cos(a) * 2.55, 5.4 + math.sin(a) * 2.55, 2.0, 2.0))
    stem = _line_mask(n, 7.5, 8.4, 7.5, 15.2, 1.1)
    leaf1 = _ellipse_mask(n, 5.4, 11.2, 2.4, 1.1)
    leaf2 = _ellipse_mask(n, 10.6, 12.6, 2.4, 1.1)
    return [
        (_union(*petals), "petal"),
        (_ellipse_mask(n, 8, 5.4, 1.5, 1.5), "core"),
        (stem, "stem"),
        (leaf1, "leaf"),
        (leaf2, "leaf"),
    ]


def subject_tree(n):
    canopy = _union(
        _ellipse_mask(n, 8, 5.4, 4.4, 3.9),
        _ellipse_mask(n, 4.9, 7.6, 2.9, 2.7),
        _ellipse_mask(n, 11.1, 7.6, 2.9, 2.7),
    )
    trunk = _union(
        _rect_mask(n, 7.0, 9.4, 9.0, 14.6),
        _line_mask(n, 7.2, 12.2, 5.4, 14.2, 0.9),
        _line_mask(n, 8.8, 12.2, 10.6, 14.2, 0.9),
    )
    return [(canopy, "canopy"), (trunk, "trunk")]


def subject_chick(n):
    body = _ellipse_mask(n, 7.2, 10.0, 4.5, 3.9)
    head = _ellipse_mask(n, 10.6, 5.4, 2.9, 2.9)
    beak = _poly_mask(n, [(13.2, 5.2), (15.6, 6.1), (13.2, 6.9)])
    legs = _union(
        _line_mask(n, 6.2, 13.6, 5.6, 15.2, 0.9),
        _line_mask(n, 8.6, 13.6, 9.2, 15.2, 0.9),
        _line_mask(n, 5.6, 15.2, 4.4, 15.2, 0.9),
        _line_mask(n, 9.2, 15.2, 10.4, 15.2, 0.9),
    )
    wing = _ellipse_mask(n, 6.2, 10.2, 2.0, 1.5)
    eye = _ellipse_mask(n, 11.4, 4.6, 0.42, 0.42)
    return [(body, "body"), (wing, "wing"), (head, "body"), (beak, "beak"),
            (legs, "beak"), (eye, "eye")]


def subject_duck(n):
    body = _ellipse_mask(n, 7.8, 10.2, 5.0, 3.4)
    head = _ellipse_mask(n, 11.4, 5.0, 2.7, 2.7)
    bill = _poly_mask(n, [(13.6, 4.4), (15.7, 5.3), (13.6, 6.2)])
    tail = _poly_mask(n, [(2.8, 9.4), (1.0, 7.6), (3.4, 8.0)])
    legs = _union(
        _line_mask(n, 7.0, 13.2, 6.6, 15.0, 0.9),
        _line_mask(n, 9.4, 13.2, 9.8, 15.0, 0.9),
    )
    wing = _ellipse_mask(n, 6.6, 10.4, 2.2, 1.4)
    eye = _ellipse_mask(n, 12.2, 4.2, 0.42, 0.42)
    return [(body, "body"), (wing, "wing"), (head, "body"), (bill, "beak"),
            (tail, "tail"), (legs, "beak"), (eye, "eye")]


def subject_cow(n):
    """正面牛脸：16px 上比侧身好认太多（侧身的身体+头会糊成一块）"""
    head = _ellipse_mask(n, 8.0, 8.0, 4.7, 5.0)
    ears = _union(
        _ellipse_mask(n, 3.3, 6.2, 1.9, 1.1),
        _ellipse_mask(n, 12.7, 6.2, 1.9, 1.1),
    )
    horns = _union(
        _line_mask(n, 5.3, 3.6, 4.3, 1.5, 0.9),
        _line_mask(n, 10.7, 3.6, 11.7, 1.5, 0.9),
    )
    muzzle = _ellipse_mask(n, 8.0, 11.4, 2.9, 1.9)
    eyes = _union(
        _ellipse_mask(n, 6.1, 6.8, 0.45, 0.45),
        _ellipse_mask(n, 9.9, 6.8, 0.45, 0.45),
    )
    return [(head, "body"), (ears, "body"), (horns, "horn"),
            (muzzle, "muzzle"), (eyes, "eye")]


SUBJECTS = {
    "sun":    (subject_sun,    "太阳"),
    "flower": (subject_flower, "花朵"),
    "tree":   (subject_tree,   "大树"),
    "chick":  (subject_chick,  "小鸡"),
    "duck":   (subject_duck,   "鸭子"),
    "cow":    (subject_cow,    "奶牛"),
}

# 16 版额外保留「内部轮廓」的部件（key）
INNER_KEYS = {
    "sun":    set(),
    "flower": {"core"},
    "tree":   set(),
    "chick":  {"wing", "eye"},
    "duck":   {"wing", "eye"},
    "cow":    {"spot", "muzzle", "eye"},
}

# ============================================================
# 调色板（暗色主题里也能看清的饱和度；每个题材一套语义色）
# ============================================================
PALETTES = {
    "sun":    {"sun": (255, 210, 74),  "ray": (255, 176, 32), "bg": (26, 34, 56)},
    "flower": {"petal": (255, 123, 169), "core": (255, 210, 74), "stem": (76, 175, 80),
               "leaf": (102, 187, 106), "bg": (26, 34, 56)},
    "tree":   {"canopy": (62, 155, 79), "trunk": (141, 90, 59), "bg": (26, 34, 56)},
    "chick":  {"body": (255, 224, 102), "wing": (255, 200, 61), "beak": (255, 138, 0),
               "bg": (26, 34, 56)},
    "duck":   {"body": (242, 245, 247), "wing": (214, 222, 229), "beak": (255, 192, 46),
               "tail": (229, 235, 240), "bg": (26, 34, 56)},
    "cow":    {"body": (245, 245, 245), "spot": (43, 43, 43), "hoof": (214, 190, 160),
               "horn": (224, 214, 195), "muzzle": (255, 180, 162),
               "eye": (36, 32, 30), "bg": (26, 34, 56)},
}


# ============================================================
# 渲染
# ============================================================


def render_line(n, parts, inner_keys=None):
    """16 版：每个形体各自取轮廓再并起来。
    ★ 不能只取「并集」的外轮廓 —— 那样头/身/翅/腿的边界全被吞掉，
      16px 小图上就只剩一坨剪影（奶牛、花朵都试过，认不出来）。
      逐形体取轮廓才会留下「脖子线、翅膀线、腿线」这些勾线该有的线。
    """
    c = [[False] * n for _ in range(n)]
    for mask, key in parts:
        pc = contour(mask)
        for y in range(n):
            for x in range(n):
                if pc[y][x]:
                    c[y][x] = True
    img = Image.new("RGB", (n, n), (255, 255, 255))
    px = img.load()
    for y in range(n):
        for x in range(n):
            if c[y][x]:
                px[x, y] = (16, 16, 16)
    return img


def _shade(color, f):
    r = max(0, min(255, int(color[0] * f)))
    g = max(0, min(255, int(color[1] * f)))
    b = max(0, min(255, int(color[2] * f)))
    return (r, g, b)


def render_color(n, parts, pal, spots_noise=True):
    """64 版：分区上色 + 描边 + 纵向明暗 + 高光"""
    k = _k(n)
    bg = pal.get("bg", (26, 34, 56))
    img = Image.new("RGB", (n, n), bg)
    px = img.load()

    # 记录每个像素属于哪个 part（后画的覆盖先画的）
    owner = [[-1] * n for _ in range(n)]
    for idx, (mask, key) in enumerate(parts):
        for y in range(n):
            for x in range(n):
                if mask[y][x]:
                    owner[y][x] = idx

    # 每个 part 的纵向包围盒，用于明暗渐变
    boxes = []
    for idx, (mask, key) in enumerate(parts):
        ys = [y for y in range(n) for x in range(n) if owner[y][x] == idx]
        xs = [x for y in range(n) for x in range(n) if owner[y][x] == idx]
        boxes.append((min(ys), max(ys), min(xs), max(xs)) if ys else (0, n - 1, 0, n - 1))

    for y in range(n):
        for x in range(n):
            idx = owner[y][x]
            if idx < 0:
                continue
            key = parts[idx][1]
            base = pal.get(key, (255, 255, 255))
            y0, y1, x0, x1 = boxes[idx]
            t = 0.0 if y1 <= y0 else (y - y0) / float(y1 - y0)
            f = 1.14 - 0.26 * t          # 上亮下暗
            # 极轻的棋盘抖动，避免大色块死板
            if spots_noise and ((x + y) % 4 == 0) and t > 0.55:
                f *= 0.965
            px[x, y] = _shade(base, f)

    # 描边：不同 part 的边界 & 与背景的边界，用「本色压暗」而不是纯黑
    edge = [[False] * n for _ in range(n)]
    for y in range(n):
        for x in range(n):
            a = owner[y][x]
            if a < 0:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if nx < 0 or ny < 0 or nx >= n or ny >= n:
                    continue
                b = owner[ny][nx]
                if b != a:
                    edge[y][x] = True
                    break
    for y in range(n):
        for x in range(n):
            if edge[y][x] and owner[y][x] >= 0:
                key = parts[owner[y][x]][1]
                base = pal.get(key, (255, 255, 255))
                px[x, y] = _shade(base, 0.42)

    return img


# ============================================================
# 输出
# ============================================================


def save_scaled(img, path, scale):
    w, h = img.size
    img.resize((w * scale, h * scale), Image.NEAREST).save(path)


def label(img, text, font, pad=8):
    w, h = img.size
    canvas = Image.new("RGB", (w, h + 26), (18, 22, 34))
    canvas.paste(img, (0, 26))
    d = ImageDraw.Draw(canvas)
    d.text((pad, 7), text, font=font, fill=(220, 230, 245))
    return canvas


def main():
    os.makedirs(os.path.join(OUT, "16"), exist_ok=True)
    os.makedirs(os.path.join(OUT, "64"), exist_ok=True)

    font_path = r"C:/Windows/Fonts/msyh.ttc"
    try:
        font = ImageFont.truetype(font_path, 16)
    except Exception:
        font = ImageFont.load_default()

    tiles16, tiles64 = [], []
    report = []
    for name, (fn, cn) in SUBJECTS.items():
        parts16 = fn(16)
        parts64 = fn(64)
        pal = PALETTES[name]

        img16 = render_line(16, parts16, INNER_KEYS.get(name, set()))
        img64 = render_color(64, parts64, pal)

        save_scaled(img16, os.path.join(OUT, "16", f"{name}.png"), 16)
        save_scaled(img64, os.path.join(OUT, "64", f"{name}.png"), 4)
        img16.save(os.path.join(OUT, "16", f"{name}_raw16.png"))
        img64.save(os.path.join(OUT, "64", f"{name}_raw64.png"))

        # 统计：勾线像素数（难度相关）
        black = sum(1 for y in range(16) for x in range(16) if img16.load()[x, y][0] < 128)
        report.append((name, cn, black))
        tiles16.append(label(img16.resize((16 * 12, 16 * 12), Image.NEAREST), f"{cn} {name}", font))
        tiles64.append(label(img64.resize((64 * 3, 64 * 3), Image.NEAREST), f"{cn} {name}", font))

    def sheet(tiles, cols, path):
        tw, th = tiles[0].size
        row_n = math.ceil(len(tiles) / cols)
        canvas = Image.new("RGB", (cols * (tw + 10) + 10, row_n * (th + 10) + 10), (12, 15, 24))
        for i, t in enumerate(tiles):
            cx = 10 + (i % cols) * (tw + 10)
            cy = 10 + (i // cols) * (th + 10)
            canvas.paste(t, (cx, cy))
        canvas.save(path)
        return canvas.size

    s1 = sheet(tiles16, 3, os.path.join(OUT, "sheet_16.png"))
    s2 = sheet(tiles64, 3, os.path.join(OUT, "sheet_64.png"))
    print("sheet_16:", s1, " sheet_64:", s2)
    for name, cn, black in report:
        print(f"{cn}({name}): 勾线像素 {black} / 256")


if __name__ == "__main__":
    main()
