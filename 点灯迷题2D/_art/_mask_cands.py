# -*- coding: utf-8 -*-
"""16×16 猫脸候选对照：同一套棋盘渲染方式（格子 + 缝）放大看谁最像猫。"""
import os

from PIL import Image, ImageDraw, ImageFont

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "out", "refcat")

CANDS = {
"E 大三角耳+3×2眼+笑脸": """
................
.##..........##.
.###........###.
.####......####.
.#..########..#.
.#............#.
.#..###..###..#.
.#..###..###..#.
.#............#.
.#.....##.....#.
.#....#..#....#.
.#............#.
..##........##..
....########....
................
................
""",
"F E+胡须(笑脸收窄)": """
................
.##..........##.
.####......####.
.#..########..#.
.#............#.
.#..###..###..#.
.#..###..###..#.
.#............#.
.#.....##.....#.
##...#..#...##..
.#............#.
..##........##..
....########....
................
................
................
""",
"G 猫头剪影(白眼看洞)": """
................
..#..........#..
.###........###.
.#####....#####.
.##############.
.##############.
.###..####..###.
.###..####..###.
.##############.
.#####.##.#####.
.##############.
.##############.
..############..
....########....
................
................
""",
"H 圆脸大耳+高光眼": """
................
.##..........##.
.####......####.
.#..########..#.
.#............#.
.#..##.#..##..#.
.#..##.#..##..#.
.#............#.
##.....##.....##
.#...#..#.....#.
.#............#.
..##........##..
...##########...
................
................
................
""",
}


def render(mask, cell=20, gap=3):
    W = 16 * (cell + gap)
    im = Image.new("RGB", (W, W), (240, 242, 246))
    d = ImageDraw.Draw(im)
    for y in range(16):
        for x in range(16):
            if mask[y][x]:
                d.rectangle([x * (cell + gap), y * (cell + gap),
                             x * (cell + gap) + cell - 1, y * (cell + gap) + cell - 1],
                            fill=(26, 30, 42))
    return im


def main():
    tiles = []
    for name, txt in CANDS.items():
        rows = txt.strip("\n").split("\n")
        if len(rows) != 16 or any(len(r) != 16 for r in rows):
            print("!! %s 尺寸不对" % name)
            for i, r in enumerate(rows):
                if len(r) != 16:
                    print("   row", i, len(r), repr(r))
            continue
        mask = [[ch == "#" for ch in r] for r in rows]
        tiles.append((name, render(mask), sum(sum(r) for r in mask)))
    try:
        font = ImageFont.truetype(r"C:/Windows/Fonts/msyh.ttc", 15)
    except Exception:
        font = ImageFont.load_default()
    tw = tiles[0][1].size[0]
    W = tw * 2 + 36
    H = (tiles[0][1].size[1] + 34) * ((len(tiles) + 1) // 2) + 8
    c = Image.new("RGB", (W, H), (250, 251, 253))
    d = ImageDraw.Draw(c)
    for i, (name, im, n) in enumerate(tiles):
        x = 8 + (i % 2) * (tw + 20)
        y = 8 + (i // 2) * (im.size[1] + 34)
        c.paste(im, (x, y + 22))
        d.text((x, y + 2), "%s  (%d格)" % (name, n), font=font, fill=(30, 36, 50))
    c.save(os.path.join(OUT, "_mask16_cands.png"))
    print("saved", c.size)


if __name__ == "__main__":
    main()
