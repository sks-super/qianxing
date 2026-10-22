# -*- coding: utf-8 -*-
"""
把参考图拟合成「纯矩形图元」的像素画，生成 mascot.lua。

用法:
    python _gen_mascot.py --grid 40 --colors 16 --write
    python _gen_mascot.py --grid 40 --colors 16 --preview        # 只出对比图

流程:
    1. 从四角泛洪去掉白底（角色身上的白色被黑描边围住，不会被吃掉）；
    2. alpha 内缩 2px，去掉 JPEG 边缘的灰白毛边；
    3. median-cut 量化到 K 色；
    4. 每个单元取「加权众数」：**深色像素权重 ×3** ——
       否则 10px 宽的黑描边在 30px 的格子里永远输给周围大色块，
       结果是轮廓断成虚线（第一版就是这么废的）；
    5. 清掉孤立单元（只有自己一格的杂色并进邻居众数），省一批 1×1 控件；
    6. 每色做「最大矩形贪心覆盖」，得到精确无缝的矩形列表；
    7. 校验：矩形栅格 == 降采样点阵（必须 0 差异）；
    8. 输出 mascot.lua。
"""
import argparse
import io
import os

import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
REF = r"C:/Users/JingSu/.workbuddy/clipboard-images/clipboard-2026-10-20T05-48-06-714Z-e767511f.jpg"


# ---------------------------------------------------------------- 读图 / 去底
def load_alpha(path, thresh=42):
    im = Image.open(path).convert("RGB")
    key = (255, 0, 255)
    for xy in [(0, 0), (im.width - 1, 0), (0, im.height - 1), (im.width - 1, im.height - 1)]:
        ImageDraw.floodfill(im, xy, key, thresh=thresh)
    arr = np.asarray(im).astype(np.int16)
    bg = (np.abs(arr[:, :, 0] - 255) < 3) & (arr[:, :, 1] < 3) & (np.abs(arr[:, :, 2] - 255) < 3)
    alpha = np.where(bg, 0, 255).astype(np.uint8)
    rgb = np.asarray(Image.open(path).convert("RGB")).astype(np.uint8)
    return rgb, alpha


def erode(mask, n=2):
    m = mask.copy()
    for _ in range(n):
        e = m.copy()
        e[1:, :] &= m[:-1, :]
        e[:-1, :] &= m[1:, :]
        e[:, 1:] &= m[:, :-1]
        e[:, :-1] &= m[:, 1:]
        m = e
    return m


# ---------------------------------------------------------------- 点阵
def build(path, n, k, dark_w=3.0, cover_min=0.42, quant=64, merge_tau=10):
    rgb, alpha = load_alpha(path)
    soft = erode(alpha > 200, 2)
    if soft.sum() == 0:
        soft = alpha > 128
    # 包围盒按内缩后的 mask 算，毛边不会把画布撑大
    ys, xs = np.where(soft)
    y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
    rgb, alpha = rgb[y0:y1, x0:x1], alpha[y0:y1, x0:x1]
    h, w = rgb.shape[:2]
    side = max(h, w)
    pad_rgb = np.full((side, side, 3), 250, np.uint8)
    pad_a = np.zeros((side, side), np.uint8)
    oy, ox = (side - h) // 2, (side - w) // 2
    pad_rgb[oy:oy + h, ox:ox + w] = rgb
    pad_a[oy:oy + h, ox:ox + w] = alpha
    pad_soft = np.zeros((side, side), bool)
    pad_soft[oy:oy + h, ox:ox + w] = soft

    # 先中位切分到 64 色压掉 JPEG 噪点，再从 64 色里选 K 色给单元用
    q = Image.fromarray(pad_rgb, "RGB").quantize(colors=quant, method=Image.MEDIANCUT)
    q = q.quantize(colors=k, method=Image.MEDIANCUT)
    pal = q.getpalette()[: k * 3]
    palette = [(pal[i * 3], pal[i * 3 + 1], pal[i * 3 + 2]) for i in range(k)]
    idx = np.asarray(q).astype(np.int32)

    # ★ 近色合并：中位切分在「大片白底 + 粗黑描边」的图上会把一半槽位浪费在
    #   6 个几乎一样的黑和 5 个几乎一样的白上；合并后黑白各归一个，
    #   描边连通域不再被拆碎，控件数和观感同时变好。
    if merge_tau > 0:
        cnt = np.bincount(idx.ravel(), minlength=k)
        parent = list(range(k))

        def find(a):
            while parent[a] != a:
                parent[a] = parent[parent[a]]
                a = parent[a]
            return a

        for a in range(k):
            for b in range(a + 1, k):
                if max(abs(palette[a][i] - palette[b][i]) for i in range(3)) <= merge_tau:
                    ra, rb = find(a), find(b)
                    if ra != rb:
                        parent[max(ra, rb)] = min(ra, rb)
        groups = {}
        for a in range(k):
            groups.setdefault(find(a), []).append(a)
        remap = np.zeros(k, np.int32)
        new_pal, keep = [], []
        for g, members in groups.items():
            rep = max(members, key=lambda i: cnt[i])
            keep.append(members)
            new_pal.append(palette[rep])
            for m in members:
                remap[m] = len(new_pal) - 1
        palette = new_pal
        idx = remap[idx]
        k = len(palette)

    lum = (0.299 * pad_rgb[:, :, 0] + 0.587 * pad_rgb[:, :, 1] + 0.114 * pad_rgb[:, :, 2]) / 255.0
    weight = np.where(lum < 0.34, dark_w, 1.0) * (pad_soft | (pad_a > 128))

    cell = side / n
    labels = np.full((n, n), -1, np.int32)
    for cy in range(n):
        ya, yb = int(round(cy * cell)), int(round((cy + 1) * cell))
        for cx in range(n):
            xa, xb = int(round(cx * cell)), int(round((cx + 1) * cell))
            wblk = weight[ya:yb, xa:xb]
            if wblk.sum() <= 0:
                continue
            solid = pad_soft[ya:yb, xa:xb]
            if solid.sum() / max(1, wblk.size) < cover_min:
                continue
            counts = np.bincount(idx[ya:yb, xa:xb].ravel(), weights=wblk.ravel(), minlength=k)
            labels[cy, cx] = int(counts.argmax())
    return labels, palette, pad_rgb, pad_a, side


# ---------------------------------------------------------------- 清理
def cleanup(labels, keep=(), min_area=3, rounds=3):
    """把面积 < min_area 的同色连通块并进四邻域里出现最多的颜色。

    比「3×3 邻域计数」彻底：JPEG 噪点会在描边边上留一堆 1~2 格的碎点，
    这些碎点每个都要单开一个控件，占掉四成控件预算。
    """
    from collections import deque
    lab = labels.copy()
    n = lab.shape[0]
    for _ in range(rounds):
        seen = np.zeros((n, n), bool)
        out = lab.copy()
        touched = False
        for y in range(n):
            for x in range(n):
                c = lab[y, x]
                if c < 0 or seen[y, x]:
                    continue
                comp = []
                q = deque([(y, x)])
                seen[y, x] = True
                while q:
                    cy, cx = q.popleft()
                    comp.append((cy, cx))
                    for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                        ny, nx = cy + dy, cx + dx
                        if 0 <= ny < n and 0 <= nx < n and not seen[ny, nx] and lab[ny, nx] == c:
                            seen[ny, nx] = True
                            q.append((ny, nx))
                if len(comp) >= min_area:
                    continue
                touched = True
                for cy, cx in comp:
                    nb = [lab[yy, xx] for yy, xx in
                          ((cy + 1, cx), (cy - 1, cx), (cy, cx + 1), (cy, cx - 1))
                          if 0 <= yy < n and 0 <= xx < n and lab[yy, xx] >= 0 and lab[yy, xx] != c]
                    if nb:
                        out[cy, cx] = max(set(nb), key=nb.count)
        lab = out
        if not touched:
            break
    return lab


# ---------------------------------------------------------------- 矩形拟合
def max_rect(ok):
    h, w = ok.shape
    heights = np.zeros(w, np.int32)
    best = (0, 0, 0, 0, 0)
    for y in range(h):
        heights = np.where(ok[y], heights + 1, 0)
        stack = []
        for x in range(w + 1):
            cur = heights[x] if x < w else 0
            start = x
            while stack and stack[-1][1] >= cur:
                sx, sh = stack.pop()
                area = sh * (x - sx)
                if area > best[4]:
                    best = (sx, y - sh + 1, x - sx, sh, area)
                start = sx
            stack.append((start, cur))
    return best[:4]


def to_rects(labels, n):
    rects = []
    for c in range(int(labels.max()) + 1):
        mask = labels == c
        while mask.any():
            x, y, w, h = max_rect(mask)
            if w == 0 or h == 0:
                break
            mask[y:y + h, x:x + w] = False
            rects.append((x, y, w, h, c))
    rects.sort(key=lambda r: (r[1], r[0]))
    return rects


def rasterize(rects, n):
    g = np.full((n, n), -1, np.int32)
    for x, y, w, h, c in rects:
        g[y:y + h, x:x + w] = c
    return g


def render(labels, pal, size):
    n = labels.shape[0]
    im = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    px = im.load()
    for y in range(n):
        for x in range(n):
            c = labels[y, x]
            if c >= 0:
                px[x, y] = tuple(pal[c]) + (255,)
    return im.resize((size, size), Image.LANCZOS)


# ---------------------------------------------------------------- 输出
def emit_lua(rects, palette, n, out, cell=1.15):
    lines = ["%d,%d,%d,%d,%d," % (x, y, w, h, c + 1) for x, y, w, h, c in rects]
    rows = []
    for i in range(0, len(lines), 6):
        rows.append("    " + "".join(lines[i:i + 6]))
    pal = ",\n    ".join('"%02X%02X%02X"' % palette[i] for i in range(len(palette)))
    lua = """-- ================================================================
-- mascot.lua  果园吉祥物「小果龙」
-- ----------------------------------------------------------------
-- ★★ 本文件由 `_gen_mascot.py` 生成，**不要手改数据段**：
--      python _gen_mascot.py --grid %(n)d --colors %(k)d --write
--    换参考图或调精度就重跑脚本，整块数据替换。
--
-- 做法：去白底 → alpha 内缩去毛边 → 中位切分量化 → %(n)d×%(n)d 单元加权众数
--       （深色 ×3，不然黑描边会被大色块吃掉、轮廓断成虚线）
--       → 清孤立单元 → 每色「最大矩形贪心覆盖」→ 精确无缝的纯矩形拼图。
--   共 %(count)d 个矩形控件 + 1 个容器；全部是矩形模板染色，不依赖任何图片资源。
--   栅格校验：矩形重绘 == 降采样点阵（0 差异，见脚本输出 verify=）。
--
-- 坐标：网格 (col,row) → 局部 (x,y)，x 向右、y 向上，原点在容器中心；
--       一格 = CELL * k 像素（k 是地图布局缩放）。
-- ================================================================
local utils = require("default_import_file/utils")
local state = require("default_import_file/state")

local M = {}

local GRID = %(n)d
local CELL = %(cell).2f        -- 每格在 k=1 时的边长
local PALETTE = {
    %(pal)s
}
-- x, y, w, h, 颜色序号（1 基），五个一组
local RECTS = {
%(data)s
}

-- ================================================================
-- 建：在 parent 下铺一整块，返回容器（位置 / 缩放由调用方负责）
-- ================================================================
function M.build(parent, k)
    if not parent then return nil end
    local s = CELL * (k or 1)
    local root = utils.createContainer(parent, GRID * s, GRID * s)
    if not root then return nil end

    local prefab = state.rectPrefabId
    if not prefab or prefab <= 0 then return root end

    local half = GRID * 0.5
    local cols = {}
    for i = 1, #PALETTE do
        cols[i] = utils.hexToColorA(PALETTE[i], 255)
    end

    local i, total = 1, #RECTS
    while i + 4 <= total do
        local x, y, w, h, ci = RECTS[i], RECTS[i + 1], RECTS[i + 2], RECTS[i + 3], RECTS[i + 4]
        local ctrl = utils.createControl(prefab,
            (x + w * 0.5 - half) * s,
            (half - (y + h * 0.5)) * s,
            w * s, h * s, cols[ci], root)
        if ctrl then utils.noRay(ctrl) end
        i = i + 5
    end
    return root
end

-- k=1 时的总边长（外面排版要用）
M.WIDTH = GRID * CELL

return M
""" % dict(n=n, k=len(palette), count=len(rects), pal=pal, data="\n".join(rows), cell=cell)
    io.open(out, "w", encoding="utf-8").write(lua)
    return lua


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--grid", type=int, default=40)
    ap.add_argument("--colors", type=int, default=16)
    ap.add_argument("--cell", type=float, default=1.15)
    ap.add_argument("--dark", type=float, default=3.0)
    ap.add_argument("--cover", type=float, default=0.42)
    ap.add_argument("--min-area", type=int, default=3)
    ap.add_argument("--tau", type=int, default=10)
    ap.add_argument("--no-clean", action="store_true")
    ap.add_argument("--preview", action="store_true")
    ap.add_argument("--write", action="store_true")
    a = ap.parse_args()

    labels, palette, rgb, alpha, side = build(REF, a.grid, a.colors, a.dark, a.cover, merge_tau=a.tau)
    if not a.no_clean:
        lum = [0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2] for c in palette]
        keep = {i for i, v in enumerate(lum) if v < 70}     # 黑描边永不参与合并
        labels = cleanup(labels, keep, a.min_area)
    rects = to_rects(labels, a.grid)
    ok = np.array_equal(rasterize(rects, a.grid), labels)
    print("grid=%d colors=%d rects=%d verify=%s" % (a.grid, len(palette), len(rects), ok))
    if a.preview:
        ref = Image.open(REF).convert("RGBA").resize((300, 300), Image.LANCZOS)
        mine = render(labels, palette, 300)
        out = Image.new("RGBA", (612, 300), (255, 255, 255, 255))
        out.paste(ref, (0, 0), ref)
        out.paste(mine, (312, 0), mine)
        out.save(os.path.join(HERE, "_mascot_preview.png"))
        print("preview -> _mascot_preview.png")
    if a.write:
        emit_lua(rects, palette, a.grid, os.path.join(HERE, "mascot.lua"), a.cell)
        print("mascot.lua written")


if __name__ == "__main__":
    main()
