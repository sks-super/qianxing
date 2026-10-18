# -*- coding: utf-8 -*-
"""
玩法样张：P（目标） → S = P ⊕ R(A)（初始状态） → 差异图
用来检查「16x16 勾线画在被打乱后还认不认得出来」。
"""

import os
import random

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "out")
S = 16
ROWS, COLS = 16, 16


def load_mask(path):
    img = Image.open(path).convert("RGB")
    px = img.load()
    m = [[1 if px[x, y][0] < 128 else 0 for x in range(S)] for y in range(S)]
    return m


def press(m, x, y):
    for dx, dy in ((0, 0), (-1, 0), (1, 0), (0, -1), (0, 1)):
        nx, ny = x + dx, y + dy
        if 0 <= nx < COLS and 0 <= ny < ROWS:
            m[ny][nx] ^= 1


def apply_a(m, a):
    out = [row[:] for row in m]
    for (x, y) in a:
        press(out, x, y)
    return out


def render(m, scale, highlight=None, bg=(255, 255, 255), fg=(16, 16, 16)):
    img = Image.new("RGB", (S, S), bg)
    px = img.load()
    for y in range(S):
        for x in range(S):
            if m[y][x]:
                px[x, y] = fg
    if highlight:
        for (x, y) in highlight:
            px[x, y] = (232, 92, 122)
    return img.resize((S * scale, S * scale), Image.NEAREST)


def main():
    font_path = r"C:/Windows/Fonts/msyh.ttc"
    try:
        font = ImageFont.truetype(font_path, 18)
    except Exception:
        font = ImageFont.load_default()

    random.seed(20261018)

    cases = [
        ("flower", 8),
        ("tree", 12),
        ("cow", 10),
    ]

    panels = []
    for name, k in cases:
        p = load_mask(os.path.join(OUT, "16", f"{name}_raw16.png"))
        cells = [(x, y) for y in range(ROWS) for x in range(COLS)]
        a = random.sample(cells, k)
        s = apply_a(p, a)
        diff = [[p[y][x] ^ s[y][x] for x in range(COLS)] for y in range(ROWS)]
        diff_cells = [(x, y) for y in range(ROWS) for x in range(COLS) if diff[y][x]]

        sc = 12
        img_p = render(p, sc)
        img_s = render(s, sc)
        img_d = render(diff, sc, bg=(255, 255, 255), fg=(232, 92, 122))
        panels.append((name, k, len(diff_cells), img_p, img_s, img_d))

    cell_w = S * 12
    cell_h = S * 12
    gap = 14
    label_h = 30
    cols = 3
    width = gap + cols * (cell_w + gap)
    height = gap + len(panels) * (label_h + cell_h + gap)
    canvas = Image.new("RGB", (width, height), (18, 22, 34))
    d = ImageDraw.Draw(canvas)

    for i, (name, k, ndiff, img_p, img_s, img_d) in enumerate(panels):
        y0 = gap + i * (label_h + cell_h + gap)
        d.text((gap, y0 + 4),
               f"{name}   |A|={k}   差异格={ndiff}   （十字规则，S = P ⊕ R(A)）",
               font=font, fill=(210, 222, 240))
        for j, img in enumerate((img_p, img_s, img_d)):
            x0 = gap + j * (cell_w + gap)
            canvas.paste(img, (x0, y0 + label_h))
            d.rectangle([x0 - 1, y0 + label_h - 1, x0 + cell_w, y0 + label_h + cell_h],
                        outline=(52, 64, 90))
        d.text((gap, y0 + label_h + cell_h + 2), "P 目标", font=font, fill=(150, 200, 170))
        d.text((gap + cell_w + gap, y0 + label_h + cell_h + 2), "S 初始", font=font, fill=(220, 190, 120))
        d.text((gap + 2 * (cell_w + gap), y0 + label_h + cell_h + 2), "P⊕S 差异", font=font, fill=(232, 122, 152))

    path = os.path.join(OUT, "demo_puzzle.png")
    canvas.save(path)
    print("saved", path, canvas.size)


if __name__ == "__main__":
    main()
