# -*- coding: utf-8 -*-
"""网格拟合：在 (单元边长 s, 原点 ox, oy) 上搜索使重建误差最小的一组。
评估点用单元 1/4、3/4 位置（与取色点不同，避免自证）。"""
import sys

from PIL import Image

SRC = r"E:\聊天信息\QQ信息\Tencent Files\2902922874\nt_qq\nt_data\Pic\2026-10\Thumb\c5253f2493abaf630999641508e46d7b_720.jpg"

im = Image.open(SRC).convert("RGB")
W, H = im.size
px = im.load()

# 只统计主体区域（去掉右下角水印）
X0, X1 = 100, 1080
Y0, Y1 = 150, 1160


def med(vals):
    vals = sorted(vals)
    return vals[len(vals) // 2]


def cell_color(s, ox, oy, cx, cy):
    """单元内部（收缩 30%）的中位色"""
    x0 = ox + cx * s + int(s * 0.3)
    x1 = ox + (cx + 1) * s - int(s * 0.3)
    y0 = oy + cy * s + int(s * 0.3)
    y1 = oy + (cy + 1) * s - int(s * 0.3)
    rs, gs, bs = [], [], []
    for y in range(y0, y1, 2):
        for x in range(x0, x1, 2):
            r, g, b = px[x, y]
            rs.append(r); gs.append(g); bs.append(b)
    if not rs:
        return px[ox + cx * s + s // 2, oy + cy * s + s // 2]
    return (med(rs), med(gs), med(bs))


def score(s, ox, oy):
    """重建误差：在单元 1/5,4/5 处比较"""
    err = 0
    n = 0
    nx = (X1 - ox) // s
    ny = (Y1 - oy) // s
    for cy in range(ny):
        for cx in range(nx):
            c = cell_color(s, ox, oy, cx, cy)
            for fx, fy in ((0.2, 0.2), (0.8, 0.2), (0.2, 0.8), (0.8, 0.8)):
                x = int(ox + (cx + fx) * s)
                y = int(oy + (cy + fy) * s)
                if not (X0 <= x < X1 and Y0 <= y < Y1):
                    continue
                p = px[x, y]
                err += abs(p[0] - c[0]) + abs(p[1] - c[1]) + abs(p[2] - c[2])
                n += 1
    return err / max(1, n)


best = []
for s in range(12, 30):
    for ox in (0, s // 4, s // 2, 3 * s // 4):
        for oy in (0, s // 4, s // 2, 3 * s // 4):
            best.append((score(s, ox, oy), s, ox, oy))
best.sort()
print("前 10 组 (误差, 单元, ox, oy):")
for e, s, ox, oy in best[:10]:
    print("  err=%7.2f  s=%2d  ox=%2d oy=%2d" % (e, s, ox, oy))
