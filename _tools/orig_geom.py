# -*- coding: utf-8 -*-
"""原版《滴答咔哒 / Tick Hop》关卡截图 → 矩形几何（工程世界坐标）

用法:
  python _tools/orig_geom.py <png> [--bright 200] [--dim 95] [--min 8] [--ds 4] [--json]
  python _tools/orig_geom.py <png> --region 0,0,1280,720
  python _tools/orig_geom.py <png> --kind ghost        # 只输出灰(虚化)块

流程:
  1. 读图 (期望 1280x720 游戏画面)
  2. 亮度分类: 亮(实体结构) / 灰(虚化计时平台) / 黑(背景)
  3. 降采样(ds) 抑噪 → 连通块清洗(丢标题字/水印/噪点) → 填洞(平台上的数字是洞)
  4. 「水平行程 + 同跨度纵向合并」拆成轴对齐矩形，再合并相邻同宽矩形
  5. 输出: 原版像素矩形 + 工程世界矩形

换算: world_x = (px - 640) * 0.625 , world_y = (360 - py) * 0.625
      (原版 1280x720 → 可见世界 800x450，居中，y 向上为正)
"""
import sys
import json
from collections import deque

import numpy as np
from PIL import Image

PX_CX, PX_CY = 640.0, 360.0
SCALE = 0.625


def to_world(px, py):
    return (px - PX_CX) * SCALE, (PX_CY - py) * SCALE


def rect_to_world(r):
    x0, y0, x1, y1 = r
    wl = (x0 - PX_CX) * SCALE
    wr = (x1 + 1 - PX_CX) * SCALE
    yt = (PX_CY - y0) * SCALE
    yb = (PX_CY - (y1 + 1)) * SCALE
    return dict(x=round((wl + wr) / 2, 1), y=round((yt + yb) / 2, 1),
                w=round(wr - wl, 1), h=round(yt - yb, 1))


def bfs(mask, seeds, H, W):
    out = np.zeros((H, W), bool)
    q = deque()
    for y, x in seeds:
        if mask[y, x] and not out[y, x]:
            out[y, x] = True
            q.append((y, x))
    while q:
        y, x = q.popleft()
        for ny, nx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
            if 0 <= ny < H and 0 <= nx < W and mask[ny, nx] and not out[ny, nx]:
                out[ny, nx] = True
                q.append((ny, nx))
    return out


def denoise_and_fill(mask, ds, max_w=14, max_h=11):
    """ds: 降采样倍数(像素/格)。max_w/max_h 用「格」为单位。"""
    H, W = mask.shape
    Hc, Wc = H // ds, W // ds
    small = mask[:Hc * ds, :Wc * ds].reshape(Hc, ds, Wc, ds).mean(axis=(1, 3)) >= 0.5
    lab = np.zeros((Hc, Wc), np.int32)
    comps = []
    for sy in range(Hc):
        for sx in range(Wc):
            if small[sy, sx] and lab[sy, sx] == 0:
                sel = bfs(small, [(sy, sx)], Hc, Wc)
                lab[sel] = len(comps) + 1
                comps.append(sel)
    keep = np.zeros((Hc, Wc), bool)
    dropped = []
    for sel in comps:
        ys, xs = np.nonzero(sel)
        y0, y1, x0, x1 = ys.min(), ys.max(), xs.min(), xs.max()
        bw, bh = x1 - x0 + 1, y1 - y0 + 1
        if bw <= max_w and bh <= max_h:
            dropped.append((int(x0 * ds), int(y0 * ds), int(x1 * ds), int(y1 * ds)))
            continue
        keep |= fill_holes(sel)
    return keep, ds, dropped


def fill_holes(sel):
    H, W = sel.shape
    ys, xs = np.nonzero(sel)
    y0, y1, x0, x1 = ys.min(), ys.max(), xs.min(), xs.max()
    sub = sel[y0:y1 + 1, x0:x1 + 1]
    h, w = sub.shape
    inv = ~sub
    outside = np.zeros((h, w), bool)
    q = deque()
    for x in range(w):
        for y in (0, h - 1):
            if inv[y, x] and not outside[y, x]:
                outside[y, x] = True; q.append((y, x))
    for y in range(h):
        for x in (0, w - 1):
            if inv[y, x] and not outside[y, x]:
                outside[y, x] = True; q.append((y, x))
    while q:
        y, x = q.popleft()
        for ny, nx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
            if 0 <= ny < h and 0 <= nx < w and inv[ny, nx] and not outside[ny, nx]:
                outside[ny, nx] = True; q.append((ny, nx))
    filled = sub | (inv & ~outside)
    out = sel.copy()
    out[y0:y1 + 1, x0:x1 + 1] = filled
    return out


def runs_to_rects(mask, min_len=2, min_thick=2):
    H, W = mask.shape
    rects = []
    open_runs = {}
    for y in range(H):
        row = mask[y].astype(np.int8)
        idx = np.nonzero(np.diff(np.concatenate(([0], row, [0]))))[0]
        cur = {}
        for a, b in zip(idx[0::2], idx[1::2]):
            if b - a >= min_len:
                cur[(int(a), int(b - 1))] = True
        for k in list(open_runs.keys()):
            if k in cur:
                open_runs[k][1] = y
            else:
                ys, ye = open_runs.pop(k)
                if ye - ys + 1 >= min_thick:
                    rects.append((k[0], ys, k[1], ye))
        for k in cur:
            if k not in open_runs:
                open_runs[k] = [y, y]
    for k, (ys, ye) in open_runs.items():
        if ye - ys + 1 >= min_thick:
            rects.append((k[0], ys, k[1], ye))
    return sorted(rects, key=lambda r: (r[1], r[0]))


def merge_rects(rects, gap=1):
    """把垂直相邻、同跨度的矩形合并（消除降采样造成的锯齿台阶）。"""
    changed = True
    rs = [list(r) for r in rects]
    while changed:
        changed = False
        out = []
        used = [False] * len(rs)
        for i in range(len(rs)):
            if used[i]:
                continue
            a = rs[i]
            for j in range(i + 1, len(rs)):
                if used[j]:
                    continue
                b = rs[j]
                if a[0] == b[0] and a[2] == b[2] and abs(a[3] + 1 - b[1]) <= gap:
                    a = [a[0], a[1], a[2], max(a[3], b[3])]
                    used[j] = True
                    changed = True
            out.append(a)
        rs = out
    return [tuple(r) for r in rs]


def main():
    args = sys.argv[1:]
    path = args[0]

    def opt(k, d):
        return type(d)(args[args.index('--' + k) + 1]) if ('--' + k) in args else d
    thr_b = opt('bright', 200)
    thr_d = opt('dim', 95)
    ds = opt('ds', 4)
    as_json = '--json' in args
    region = opt('region', None)
    kind = opt('kind', 'both')

    img = Image.open(path).convert('RGB')
    a = np.asarray(img).astype(float)
    lum = a[:, :, 0] * 0.299 + a[:, :, 1] * 0.587 + a[:, :, 2] * 0.114
    H, W = lum.shape

    solid = lum >= thr_b
    ghost = (lum >= thr_d) & (lum < thr_b)
    if region:
        x0, y0, x1, y1 = [int(v) for v in region.split(',')]
        keep = np.zeros_like(solid)
        keep[y0:y1, x0:x1] = True
        solid &= keep
        ghost &= keep

    res = {'file': path, 'size': [W, H], 'solid': [], 'ghost': []}
    if not as_json:
        print(f'# {path}  {W}x{H}  亮={int(solid.sum())}  灰={int(ghost.sum())}  ds={ds}')
    for key, mask in (('solid', solid), ('ghost', ghost)):
        if kind not in ('both', key):
            continue
        keep, ds, dropped = denoise_and_fill(mask, ds)
        rects = merge_rects(runs_to_rects(keep, 2, 2))
        px_rects = []
        for (x0, y0, x1, y1) in rects:
            px_rects.append((x0 * ds, y0 * ds, x1 * ds + ds - 1, y1 * ds + ds - 1))
        px_rects.sort(key=lambda r: (r[1], r[0]))
        res[key] = [dict(px=list(r), world=rect_to_world(r)) for r in px_rects]
        if not as_json:
            print(f'\n## {key}  ({len(px_rects)} 块, 丢弃小件 {len(dropped)})')
            print('   px(x0,y0,x1,y1)'.ljust(28) + 'world(x,y,w,h)')
            for r in px_rects:
                wd = rect_to_world(r)
                print(f'   {str(list(r)):26s} {wd["x"]:8.1f} {wd["y"]:8.1f} {wd["w"]:7.1f} {wd["h"]:6.1f}')
    if as_json:
        print(json.dumps(res, ensure_ascii=False, indent=1))


if __name__ == '__main__':
    main()
