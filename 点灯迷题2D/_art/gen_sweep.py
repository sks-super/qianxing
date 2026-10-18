# -*- coding: utf-8 -*-
"""难度扫描：同一张 P，改变 |A|，看 S 还可不可辨认。

结论直接决定 GDD 里「十字翻转下 |A| 该取多大」和「模式一要不要用仅翻自身」。
"""

import os
import random

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "out")
S = 16


def load_mask(path):
    img = Image.open(path).convert("RGB")
    px = img.load()
    return [[1 if px[x, y][0] < 128 else 0 for x in range(S)] for y in range(S)]


def press(m, x, y):
    for dx, dy in ((0, 0), (-1, 0), (1, 0), (0, -1), (0, 1)):
        nx, ny = x + dx, y + dy
        if 0 <= nx < S and 0 <= ny < S:
            m[ny][nx] ^= 1


def apply_a(m, a):
    out = [row[:] for row in m]
    for (x, y) in a:
        press(out, x, y)
    return out


def render(m, scale):
    img = Image.new("RGB", (S, S), (255, 255, 255))
    px = img.load()
    for y in range(S):
        for x in range(S):
            if m[y][x]:
                px[x, y] = (16, 16, 16)
    return img.resize((S * scale, S * scale), Image.NEAREST)


def main():
    try:
        font = ImageFont.truetype(r"C:/Windows/Fonts/msyh.ttc", 15)
        head = ImageFont.truetype(r"C:/Windows/Fonts/msyh.ttc", 18)
    except Exception:
        font = head = ImageFont.load_default()

    names = ["flower", "tree", "cow"]
    ks = [4, 6, 8, 12, 16]
    sc = 9
    tw = S * sc
    gap = 10
    left = 74
    row_h = tw + 26

    width = left + len(ks) * (tw + gap) + gap
    height = 46 + len(names) * row_h + gap
    canvas = Image.new("RGB", (width, height), (18, 22, 34))
    d = ImageDraw.Draw(canvas)
    d.text((gap, 12), "同一张 P，不同 |A| 下的初始状态 S（十字翻转）", font=head, fill=(210, 222, 240))
    for j, k in enumerate(ks):
        d.text((left + j * (tw + gap), 34), f"|A|={k}", font=font, fill=(150, 160, 185))

    random.seed(7)
    for i, name in enumerate(names):
        p = load_mask(os.path.join(OUT, "16", f"{name}_raw16.png"))
        y0 = 46 + i * row_h
        d.text((gap, y0 + tw // 2 - 8), name, font=font, fill=(210, 222, 240))
        for j, k in enumerate(ks):
            cells = [(x, y) for y in range(S) for x in range(S)]
            a = random.sample(cells, k)
            s = apply_a(p, a)
            img = render(s, sc)
            x0 = left + j * (tw + gap)
            canvas.paste(img, (x0, y0))
            d.rectangle([x0 - 1, y0 - 1, x0 + tw, y0 + tw], outline=(52, 64, 90))

    path = os.path.join(OUT, "demo_sweep.png")
    canvas.save(path)
    print("saved", path, canvas.size)


if __name__ == "__main__":
    main()
