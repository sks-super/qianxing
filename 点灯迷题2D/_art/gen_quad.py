# -*- coding: utf-8 -*-
"""大关卡 = 16x16 图 = 4 个 8x8 小关。
本图验证：每个象限单独做成关卡时，P / S 长什么样、还认不认得。
"""

import os
import random

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "out")
S = 8


def load_mask(path):
    img = Image.open(path).convert("RGB")
    px = img.load()
    return [[1 if px[x, y][0] < 128 else 0 for x in range(S * 2)] for y in range(S * 2)]


def press(m, x, y, n=8):
    for dx, dy in ((0, 0), (-1, 0), (1, 0), (0, -1), (0, 1)):
        nx, ny = x + dx, y + dy
        if 0 <= nx < n and 0 <= ny < n:
            m[ny][nx] ^= 1


def apply_a(m, a):
    out = [row[:] for row in m]
    for (x, y) in a:
        press(out, x, y)
    return out


def render(m, scale, sep=False, bg=(255, 255, 255), fg=(16, 16, 16)):
    n = len(m)
    img = Image.new("RGB", (n, n), bg)
    px = img.load()
    for y in range(n):
        for x in range(n):
            if m[y][x]:
                px[x, y] = fg
    big = img.resize((n * scale, n * scale), Image.NEAREST)
    if sep:
        d = ImageDraw.Draw(big)
        h = (n // 2) * scale
        d.line([(h, 0), (h, n * scale)], fill=(210, 120, 150), width=1)
        d.line([(0, h), (n * scale, h)], fill=(210, 120, 150), width=1)
    return big


def main():
    try:
        font = ImageFont.truetype(r"C:/Windows/Fonts/msyh.ttc", 15)
        head = ImageFont.truetype(r"C:/Windows/Fonts/msyh.ttc", 19)
    except Exception:
        font = head = ImageFont.load_default()

    name = "tree"
    full = load_mask(os.path.join(OUT, "16", f"{name}_raw16.png"))

    quads = [("左上", 0, 0), ("右上", 1, 0), ("左下", 0, 1), ("右下", 1, 1)]
    ks = [3, 4, 4, 5]
    random.seed(11)

    sc = 10
    cw = S * sc
    gap = 12
    left = 78
    row_h = cw + 30
    right_w = 16 * 14 + 60

    width = left + 3 * (cw + gap) + 56 + right_w
    height = 52 + 4 * row_h + gap
    canvas = Image.new("RGB", (width, height), (18, 22, 34))
    d = ImageDraw.Draw(canvas)
    d.text((gap, 14), f"大关卡「{name}」= 4 个 8×8 小关（每块单独是一个关卡）",
           font=head, fill=(210, 222, 240))
    for j, t in enumerate(("P 目标", "S 初始", "P⊕S 差异")):
        d.text((left + j * (cw + gap), 36), t, font=font, fill=(150, 160, 185))

    assembled = [row[:] for row in full]      # 用来在右侧画「已完成」
    total_flips = 0

    for i, (label, qx, qy) in enumerate(quads):
        p = [[full[qy * S + y][qx * S + x] for x in range(S)] for y in range(S)]
        cells = [(x, y) for y in range(S) for x in range(S)]
        a = random.sample(cells, ks[i])
        s = apply_a(p, a)
        diff = [[p[y][x] ^ s[y][x] for x in range(S)] for y in range(S)]
        total_flips += len(a)

        y0 = 52 + i * row_h
        d.text((gap, y0 + cw // 2 - 8), label, font=font, fill=(210, 222, 240))
        for j, (m, fg) in enumerate(((p, (16, 16, 16)), (s, (16, 16, 16)), (diff, (232, 92, 122)))):
            img = render(m, sc, fg=fg)
            x0 = left + j * (cw + gap)
            canvas.paste(img, (x0, y0))
            d.rectangle([x0 - 1, y0 - 1, x0 + cw, y0 + cw], outline=(52, 64, 90))
        d.text((left + 3 * (cw + gap) + 2, y0 + cw // 2 - 8), f"|A|={ks[i]}", font=font, fill=(232, 190, 120))

    # 右侧：拼好的 16x16（带象限分隔）
    ax = left + 3 * (cw + gap) + 56
    d.text((ax, 14), "四块合拢 = 16×16", font=font, fill=(150, 160, 185))
    img = render(full, 14, sep=True)
    canvas.paste(img, (ax, 52))
    d.rectangle([ax - 1, 51, ax + 16 * 14, 52 + 16 * 14], outline=(70, 84, 116))
    d.text((ax, 52 + 16 * 14 + 6), f"总步数 = Σ|A| = {total_flips}", font=font, fill=(150, 200, 170))

    path = os.path.join(OUT, "demo_quad.png")
    canvas.save(path)
    print("saved", path, canvas.size)


if __name__ == "__main__":
    main()
