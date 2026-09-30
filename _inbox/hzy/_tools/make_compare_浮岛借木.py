# -*- coding: utf-8 -*-
"""把同一次 e2e 的「素材路径」与「纯色回退」两张截图拼成 A/B 对照图。

用法：
    python _tools/make_compare_浮岛借木.py <A_素材.png> <B_回退.png> [输出路径]

默认输出 浮岛借木/对照_素材路径_vs_纯色回退.png。
两张图必须来自**同一次 e2e** 的 L1art / L1rect 两轮（同一关、同一解法、同一帧），
否则对照就不成立。e2e 脚本跑完会把这两张图的路径打在 stdout 里。
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DEFAULT = os.path.join(ROOT, "浮岛借木", "对照_素材路径_vs_纯色回退.png")

MSYH = "C:/Windows/Fonts/msyh.ttc"
MSYHBD = "C:/Windows/Fonts/msyhbd.ttc"

PANEL_W = 640                       # 每张截图的显示宽度（原图 1280 → 0.5 倍）
MARGIN = 20
CAP_H = 30                          # 每块图上方那行小标题的高度
HEAD_H = 92                         # 顶部标题区
NOTE_H = 150                        # 底部说明区
RED = (198, 40, 40)
BLUE = (40, 82, 160)
INK = (26, 26, 26)
GRAY = (105, 105, 105)
LINE = (218, 218, 218)

# 四个素材元件各自的落点说明（真机上什么、回退时什么）
NOTES = [
    "海水 1073741879   →  整屏青蓝底（改用素材元件）",
    "草地 1073741881   →  逐格平铺草坪，格间留细缝（改用素材元件，不再用深浅棋盘）",
    "树木 1073741883   →  1 块深绿立绘，高 2.5 格，脚踩脚线（改用素材元件）",
    "人物 1073741886   →  1 块橙围巾立绘，高 2 格，脚踩脚线（改用素材元件）",
    "2.5D 三层（沙滩描边 / 土壤侧面 / 水下投影）由脚本绘制，A、B 两条路径完全一样",
    "B 的树冠 / 石头比 A 小一点，是回退路径用「矩形 + 调色板」拼形状，不是 bug",
]


def font(size, bold=False):
    return ImageFont.truetype(MSYHBD if bold else MSYH, size)


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    pa, pb = sys.argv[1], sys.argv[2]
    out = sys.argv[3] if len(sys.argv) > 3 else OUT_DEFAULT

    a = Image.open(pa).convert("RGB")
    b = Image.open(pb).convert("RGB")
    if a.size != b.size:
        print("两张图尺寸不一致：%s vs %s" % (a.size, b.size))
        return 1
    panel_h = int(round(a.size[1] * PANEL_W / a.size[0]))
    a = a.resize((PANEL_W, panel_h), Image.LANCZOS)
    b = b.resize((PANEL_W, panel_h), Image.LANCZOS)

    W = MARGIN * 3 + PANEL_W * 2
    H = HEAD_H + CAP_H + panel_h + NOTE_H
    canvas = Image.new("RGB", (W, H), (255, 255, 255))
    d = ImageDraw.Draw(canvas)

    # ── 顶部标题 ─────────────────────────────────────────────
    d.text((MARGIN, 14), "浮岛借木 · 美术素材路径 vs 纯色回退", font=font(25, True), fill=INK)
    d.text((MARGIN + 1, 50), "同一关、同一解法、都是 17 步通关；2.5D 地块两种路径共用同一套几何",
           font=font(15), fill=GRAY)

    # ── 两块图 ───────────────────────────────────────────────
    for idx, (img, cap, color) in enumerate(
            ((a, "A  素材路径（默认 useArt = 1）", RED),
             (b, "B  回退路径（--params useArt=0）", BLUE))):
        x = MARGIN + idx * (PANEL_W + MARGIN)
        y = HEAD_H
        d.text((x, y + 6), cap, font=font(16, True), fill=color)
        iy = y + CAP_H
        canvas.paste(img, (x, iy))
        d.rectangle([x - 2, iy - 2, x + PANEL_W + 1, iy + panel_h + 1], outline=color, width=2)

    # ── 底部说明 ─────────────────────────────────────────────
    ny = HEAD_H + CAP_H + panel_h + 14
    for i, text in enumerate(NOTES):
        d.text((MARGIN, ny + i * 21), text, font=font(15), fill=INK if i < 5 else GRAY)

    os.makedirs(os.path.dirname(out), exist_ok=True)
    canvas.save(out)
    print("已生成 %s（%dx%d）" % (out, W, H))
    return 0


if __name__ == "__main__":
    sys.exit(main())
