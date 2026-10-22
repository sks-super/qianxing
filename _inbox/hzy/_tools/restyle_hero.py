# -*- coding: utf-8 -*-
"""只换颜色、不动几何 —— 给小人「补上头发色」。

为什么需要这一步：
  make_hero_pixels.py 的量化目标是「整身浅色不出错」，代价是把银灰发和白裙白脸
  压成了同一个 DCE2EE。于是真机上整颗头看起来像没头发（发色 = 肤色），认不出是银发角色。
  量化调色板里虽然钉了一只肤色 10 号 F2D8C4，但那是「暖白」，跟冷调的头发不是一回事。

做法（刻意保守）：
  1. **一块都不增不减**：只改 rect 的颜色索引，形状/块数/控件数 100% 不变 → 清晰度零回归。
  2. 只认「头部 + 浅色 + 非暖色」的格当作头发：
     - 头部 = 网格前 HEAD_ROWS 行（长发只处理到肩，裙子不碰）
     - 浅色 = 当前索引属于 SHALLOW_IDX（避免把深蓝头冠、描边、眼睛改掉）
     - 非暖 = 源图该格 (R - B) < WARM_TOL（源图脸是暖白，头发是冷灰，用它护住脸）
  3. 发色分两档：源图该格亮度 >= HAIR_LUM_SPLIT 用亮档，否则用暗档 —— 保住立体感。
     两档色追加在调色板末尾（不重排索引），所以 heroArt.lua 的 diff 只有颜色号。

用法：
  python _tools/restyle_hero.py                                  # 默认银灰发，写回游戏目录
  python _tools/restyle_hero.py --hair C2C9DC --hair-dark 9AA3BE --out _tmp/heroA.lua
  python _tools/restyle_hero.py --dry                            # 只报统计，不写文件
  python _tools/restyle_hero.py --preview _tmp/previewA.png      # 顺带出预览图
"""
import argparse
import os
import re
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import make_hero_pixels as mhp   # 复用素材加载、并集裁剪、预览渲染

GAME = os.path.join(HERE, "..", "浮岛借木")
ART_LUA = os.path.join(GAME, "heroArt.lua")

HEAD_ROWS = 15          # 头发只改前 15 行（头部；再往下是脖子与裙子）
SHALLOW_IDX = {6, 8, 9, 11, 12}   # 量化调色板里的浅色（9BA2BD/ADB3CB/9DC4E6/DCE2EE/F8F7F6）
WARM_TOL = 12           # 源图 (R - B) >= 它 → 判定为「暖 = 脸/皮肤」，护住不改
SOLID_ALPHA = 100
COVER_MIN = 0.34
HAIR_LUM_SPLIT = 200    # 源图格亮度分档线

# 背面朝上没有脸（只有后脑勺的头发），硬编码这一条比任何颜色判据都可靠
FACES_WITH_FACE = {"S", "A", "D"}
FACE_ROWS = (9, 14)     # 脸可能的行区间（含）；只在这个区间里才认肤色
FACE_COLS = (0.18, 0.80)  # 脸可能的列区间（占网格宽的比例）
FACE_WARM = 6           # 源图 (R - B) >= 它 → 这格是皮肤（头发是负值，分得很开）


def parse(path):
    src = open(path, encoding="utf-8").read()
    cols = int(re.search(r"M\.COLS\s*=\s*(\d+)", src).group(1))
    rows = int(re.search(r"M\.ROWS\s*=\s*(\d+)", src).group(1))
    m = re.search(r"M\.COLORS\s*=\s*\{(.*?)\n\}", src, re.S)
    colors = re.findall(r'"([0-9A-Fa-f]{6})"', m.group(1))
    sprites = {}
    for key in ("S", "W", "A", "D"):
        km = re.search(r"\b%s\s*=\s*\{[^\n]*\n(.*?)\n    \}" % key, src, re.S)
        if not km:
            raise SystemExit("找不到朝向 %s 的矩形表" % key)
        rects = re.findall(r"\{\s*(-?\d+)\s*,\s*(-?\d+)\s*,\s*(-?\d+)\s*,\s*(-?\d+)\s*,\s*(\d+)\s*\}",
                           km.group(1))
        sprites[key] = [[int(v) for v in r] for r in rects]
    return cols, rows, colors, sprites


def cell_colors():
    """每朝向一张「源图逐格平均色」表，用于判断这一格是头发还是脸。"""
    imgs = {f: mhp.load_face(f) for f in mhp.FACES}
    x0, x1, y0, y1 = mhp.union_bbox(imgs)
    bw, bh = x1 - x0 + 1, y1 - y0 + 1
    out = {}
    for f in mhp.FACES:
        im = imgs[f]
        rgb = np.zeros((mhp.ROWS_REF, mhp.COLS_REF, 3))
        for r in range(mhp.ROWS_REF):
            sy0 = y0 + int(round(r * bh / mhp.ROWS_REF))
            sy1 = y0 + int(round((r + 1) * bh / mhp.ROWS_REF))
            for c in range(mhp.COLS_REF):
                sx0 = x0 + int(round(c * bw / mhp.COLS_REF))
                sx1 = x0 + int(round((c + 1) * bw / mhp.COLS_REF))
                p = im[sy0:max(sy1, sy0 + 1), sx0:max(sx1, sx0 + 1)]
                solid = p[:, :, 3] > SOLID_ALPHA
                if solid.mean() < COVER_MIN:
                    rgb[r, c] = np.nan
                    continue
                rgb[r, c] = p[:, :, :3][solid].mean(axis=0)
        out[f] = rgb
    return out


def restyle(colors, sprites, cells, hair_light, hair_dark, skin=""):
    """返回 (新调色板, 新 sprites, 统计)。

    ★ 按「格」判色、再重新做行 RLE 合并 —— 不按原块整块投票。
      整块投票时，一块里混着脸和头发就只能二选一，结果脸整个被头发吞掉（试过，只剩 4 格脸）。
      按格判色后几何完全不变（哪些格是实心由原数据决定），只是同块内不同色的格会拆成两块。
    """
    pal = [c.upper() for c in colors]

    def add_color(hexv):
        hexv = hexv.upper()
        if hexv in pal:
            return pal.index(hexv)
        pal.append(hexv)
        return len(pal) - 1

    i_light = add_color(hair_light)
    i_dark = add_color(hair_dark) if hair_dark and hair_dark.upper() != hair_light.upper() else i_light
    if skin.strip().lower() == "keep":
        i_skin = -2            # -2 = 只保护脸、不改脸色
    elif skin:
        i_skin = add_color(skin)
    else:
        i_skin = -1            # -1 = 不认脸（整颗头都算头发）

    shallow = set(SHALLOW_IDX) | {i_light, i_dark}
    stats = {"hair": 0, "face": 0, "kept": 0, "blocks": {}}
    new_sprites = {}
    for f, rects in sprites.items():
        rgb = cells[f]
        rows, cols = rgb.shape[:2]
        grid = np.full((rows, cols), -1, dtype=np.int32)
        for (x, y, w, h, c) in rects:
            for yy in range(y, y + h):
                if 0 <= yy < rows:
                    for xx in range(x, x + w):
                        if 0 <= xx < cols:
                            grid[yy, xx] = c
        has_face = f in FACES_WITH_FACE
        fc_lo = int(round(cols * FACE_COLS[0]))
        fc_hi = int(round(cols * FACE_COLS[1]))
        for yy in range(rows):
            for xx in range(cols):
                c = int(grid[yy, xx])
                if c < 0 or c not in shallow:
                    continue
                v = rgb[yy, xx]
                if np.isnan(v[0]):
                    continue
                warm = (v[0] - v[2]) >= WARM_TOL
                in_face = has_face and FACE_ROWS[0] <= yy <= FACE_ROWS[1] \
                    and fc_lo <= xx <= fc_hi and (v[0] - v[2]) >= FACE_WARM
                if in_face and i_skin != -1:
                    if i_skin >= 0:
                        grid[yy, xx] = i_skin
                        stats["face"] += 1
                    else:
                        stats["face"] += 1
                        stats["kept"] += 1
                elif yy < HEAD_ROWS and not warm:
                    lum = 0.299 * v[0] + 0.587 * v[1] + 0.114 * v[2]
                    grid[yy, xx] = i_light if lum >= HAIR_LUM_SPLIT else i_dark
                    stats["hair"] += 1
                else:
                    stats["kept"] += 1
        # 重新做一次「行 RLE + 向下合并」，块数仍然接近最小
        merged = mhp.to_rects(grid, None, 0.0)
        stats["blocks"][f] = (len(rects), len(merged))
        new_sprites[f] = [[x, y, w, h, c] for (x, y, w, h, c) in merged]
    return pal, new_sprites, stats


def write_lua(pal, sprites, counts, out_path):
    L = []
    L.append("-- ================================================================")
    L.append("-- 浮岛借木 · 小人的「像素画」数据（由 _tools/make_hero_pixels.py 与")
    L.append("-- _tools/restyle_hero.py 接力生成；两个脚本都别手改，改发色只改 13/14 两行 hex）")
    L.append("--")
    L.append("-- ★ 为什么要这样存：千星脚本只能实例化矩形 / 图片 / 文本 / 容器控件，")
    L.append("--   没有「把一张 PNG 画出来」的接口。所以角色不是引用图片，而是")
    L.append("--   **用 %d 种颜色、几百块纯色矩形拼出来的像素画** —— 换朝向就是换一套矩形。" % len(pal))
    L.append("--")
    L.append("-- ★ 坐标单位：网格格（不是像素）。整个网格 = COLS × ROWS 格，")
    L.append("--   运行时一块的边长 = cellSize / ROWS，于是内容正好 1 格高，")
    L.append("--   而且格子边长怎么自适应都不会把角色拉变形（像素恒为正方形）。")
    L.append("-- ★ 四张共用同一个网格与同一套调色板：转身时脚底不动、配色不跳。")
    L.append("--")
    L.append("-- ★ 调色板 0-12 是量化出的原色（按亮度排序）；13 起是 _tools/restyle_hero.py")
    L.append("--   后补的「头发色」—— 量化会把银灰发和白裙压成同一个白，补两档才看得出是头发。")
    L.append("--   补发色时按「格」判色、再重做行 RLE 合并，块数会略增（S 146→165），")
    L.append("--   但「哪些格是实心」完全不变 —— 轮廓与清晰度零改动。")
    L.append("--   要调发色只改 13/14 两行 hex；脸按 FACE_ROWS/FACE_COLS 保护、保持原色。")
    L.append("--")
    L.append("-- RECT 项 = { x, y, w, h, c }：左上角格坐标 + 宽高（格）+ 调色板索引。")
    L.append("--   y 从上往下数（0 = 头顶那行）；绘制时脚本再翻成 UI 的向上为正。")
    L.append("-- ================================================================")
    L.append("")
    L.append("local M = {}")
    L.append("")
    L.append("M.COLS = %d   -- 网格宽（格）" % mhp.COLS_REF)
    L.append("M.ROWS = %d   -- 网格高（格）；角色内容高 = 1 格 → 每格像素 = cellSize / ROWS"
             % mhp.ROWS_REF)
    L.append("")
    L.append("-- 调色板：0-12 按亮度排序（量化原色），13+ 为后补的头发色")
    L.append("M.COLORS = {")
    for i, hx in enumerate(pal):
        L.append('    "%s",%s-- %d' % (hx, " " * (11 - len(hx)), i))
    L.append("}")
    L.append("")
    L.append("-- 每个朝向的矩形块")
    L.append("M.SPRITES = {")
    for f in ("S", "W", "A", "D"):
        L.append("    %s = {   -- %d 块" % (f, len(sprites[f])))
        for (x, y, w, h, c) in sprites[f]:
            L.append("        { %d, %d, %d, %d, %d }," % (x, y, w, h, c))
        L.append("    },")
    L.append("}")
    L.append("")
    L.append("return M")
    with open(out_path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(L) + "\n")


def grid_from_rects(cols, rows, rects):
    g = np.full((rows, cols), -1, dtype=np.int32)
    for x, y, w, h, c in rects:
        for yy in range(y, y + h):
            if 0 <= yy < rows:
                for xx in range(x, x + w):
                    if 0 <= xx < cols:
                        g[yy, xx] = c
    return g


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", default=ART_LUA, help="heroArt.lua 输入")
    ap.add_argument("--out", default=ART_LUA, help="输出路径")
    ap.add_argument("--hair", default="C2C9DC", help="头发亮档色")
    ap.add_argument("--hair-dark", default="9AA3BE", help="头发暗档色")
    ap.add_argument("--skin", default="keep",
                    help="脸怎么处理：keep = 原样不动（默认）；空串 = 不认脸，整颗头都算头发；"
                         "或给一个 hex（如 F5DFD4）把脸涂成肤色")
    ap.add_argument("--preview", default="", help="顺带渲染预览 PNG")
    ap.add_argument("--dry", action="store_true", help="只统计不写文件")
    args = ap.parse_args()

    cols, rows, colors, sprites = parse(args.src)
    mhp.COLS_REF, mhp.ROWS_REF = cols, rows
    cells = cell_colors()
    pal, new_sprites, stats = restyle(colors, sprites, cells,
                                      args.hair, args.hair_dark, args.skin)
    print("调色板 %d → %d 色；头发 %d 格，按脸保护 %d 格，未动 %d 格"
          % (len(colors), len(pal), stats["hair"], stats["face"], stats["kept"]))
    for f in ("S", "W", "A", "D"):
        b0, b1 = stats["blocks"][f]
        print("  块数 %s: %d → %d（%+d）" % (f, b0, b1, b1 - b0))
    print("后补色：" + " ".join(pal[len(colors):]))

    if not args.dry:
        write_lua(pal, new_sprites, None, args.out)
        print("-> %s" % args.out)
        if args.preview:
            grids = {f: grid_from_rects(cols, rows, new_sprites[f]) for f in mhp.FACES}
            arr = np.array([[int(h[i:i + 2], 16) for i in (0, 2, 4)] for h in pal], dtype=float)
            mhp.render_preview(grids, arr, args.preview)
            print("-> %s" % args.preview)


if __name__ == "__main__":
    main()
