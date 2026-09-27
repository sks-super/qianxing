# -*- coding: utf-8 -*-
"""最终融合：方案 B（交集对齐）写入吞噬.lua。
第 1 帧 = 等待投喂角色等比 contain 缩放并居中到吞噬动画各帧稳定身体交集区域，
        颜色映射回吞噬调色板；第 2-6 帧 = 原吞噬动画。
"""
import re
import sys
from pathlib import Path

import numpy as np
from PIL import Image

WS = Path(r"E:\千星\千星游戏")
sys.path.insert(0, str(WS))
import _gen_from_images as gen

WAIT_SRC = r"C:\Users\Twinkle\.workbuddy\clipboard-images\clipboard-2026-08-22T18-02-25-427Z-0535da1b.png"
DEV_PATH = WS / "吞噬.lua"
GRID = 60
SCALE = 10


def extract_block(text, name):
    prefix = f"M.{name} = {{"
    start = text.find(prefix)
    assert start != -1, f"{name} not found"
    start += len(prefix)
    depth = 1
    i = start
    while i < len(text) and depth > 0:
        if text[i] == '{':
            depth += 1
        elif text[i] == '}':
            depth -= 1
        i += 1
    return text[start:i - 1]


def parse_lua(path):
    text = Path(path).read_text(encoding="utf-8-sig")
    pal_block = extract_block(text, "PALETTE")
    pal = {}
    for i, r, g, b in re.findall(r"\[(\d+)\]\s*=\s*\{(\d+),\s*(\d+),\s*(\d+)\}", pal_block):
        pal[int(i)] = (int(r), int(g), int(b))
    fr_block = extract_block(text, "FRAMES")
    fbs = re.findall(r"\{\s*((?:\{[^}]+\},?\s*)+)\s*\}", fr_block)
    frames = []
    for fb in fbs:
        rects = []
        for xs, ys, ws, hs, cs, als in re.findall(
                r"\{(\d+),\s*(\d+),\s*(\d+),\s*(\d+),\s*(\d+),\s*(\d+)\}", fb):
            rects.append((int(xs), int(ys), int(ws), int(hs), int(cs), int(als)))
        frames.append(rects)
    return pal, frames


def per_frame_bbox(rects):
    xs, ys, x2, y2 = [], [], [], []
    for x, y, w, h, c, a in rects:
        xs.append(x)
        ys.append(y)
        x2.append(x + w - 1)
        y2.append(y + h - 1)
    return (min(xs), min(ys), max(x2), max(y2))


def rebuild_waiting_grid():
    """复现等待投喂 60x60 网格（与旧等待投喂.lua 同一管线）。返回 1-based 索引网格。"""
    frames = gen.load_frames(WAIT_SRC)
    bbox = gen.global_bbox(frames)
    canvas = gen.resize_frame_to_grid(frames[0], bbox, GRID)
    palette, idx_frames = gen.build_palette([canvas], 64)
    grid = gen.build_grid(canvas, idx_frames[0])
    return grid, palette


def grid_to_image(grid, palette):
    img = Image.new("RGBA", (GRID, GRID), (0, 0, 0, 0))
    px = img.load()
    for y in range(GRID):
        for x in range(GRID):
            c = grid[y][x]
            if c >= 1:
                r, g, b = palette[c - 1]
                px[x, y] = (r, g, b, 255)
    return img


def image_bbox(img):
    px = img.load()
    xs, ys = [], []
    for y in range(GRID):
        for x in range(GRID):
            if px[x, y][3] > 128:
                xs.append(x)
                ys.append(y)
    return (min(xs), min(ys), max(xs), max(ys))


def align_waiting(wait_img, target_box):
    """等比 contain 居中缩放，NEAREST。返回 (aligned_raw_rgba, info)。"""
    tx0, ty0, tx1, ty1 = target_box
    tw_box = tx1 - tx0 + 1
    th_box = ty1 - ty0 + 1
    wx0, wy0, wx1, wy1 = image_bbox(wait_img)
    ww = wx1 - wx0 + 1
    wh = wy1 - wy0 + 1
    s = min(tw_box / ww, th_box / wh)
    tw = max(1, round(ww * s))
    th = max(1, round(wh * s))
    tx = round(tx0 + (tw_box - tw) / 2)
    ty = round(ty0 + (th_box - th) / 2)
    crop = wait_img.crop((wx0, wy0, wx1 + 1, wy1 + 1))
    crop_r = crop.resize((tw, th), Image.NEAREST)
    aligned = Image.new("RGBA", (GRID, GRID), (0, 0, 0, 0))
    aligned.paste(crop_r, (tx, ty), crop_r)
    return aligned, (round(s, 4), tx, ty, tw, th)


def recolor_to_palette(img, pal_list):
    px = img.load()
    for y in range(GRID):
        for x in range(GRID):
            r, g, b, a = px[x, y]
            if a <= 128:
                continue
            best_i, best_d = 0, None
            for i, (pr, pg, pb) in enumerate(pal_list):
                d = (r - pr) ** 2 + (g - pg) ** 2 + (b - pb) ** 2
                if best_d is None or d < best_d:
                    best_d = d
                    best_i = i
            px[x, y] = (pal_list[best_i][0], pal_list[best_i][1], pal_list[best_i][2], 255)
    return img


def aligned_to_grid(aligned, pal_list):
    """把重着色后的对齐图转成 1-based 索引网格。"""
    px = aligned.load()
    grid = [[-1] * GRID for _ in range(GRID)]
    for y in range(GRID):
        for x in range(GRID):
            r, g, b, a = px[x, y]
            if a <= 128:
                continue
            best_i, best_d = 0, None
            for i, (pr, pg, pb) in enumerate(pal_list):
                d = (r - pr) ** 2 + (g - pg) ** 2 + (b - pb) ** 2
                if best_d is None or d < best_d:
                    best_d = d
                    best_i = i
            grid[y][x] = best_i + 1
    return grid


def render_rects(rects, pal_list):
    img = Image.new("RGBA", (GRID, GRID), (0, 0, 0, 0))
    px = img.load()
    for x, y, w, h, c, a in rects:
        r, g, b = pal_list[c - 1]
        for yy in range(y, y + h):
            for xx in range(x, x + w):
                px[xx, yy] = (r, g, b, a)
    return img


def up(img):
    return img.resize((GRID * SCALE, GRID * SCALE), Image.NEAREST)


def write_lua(out_path, pal, frames, title, description):
    lines = []
    lines.append("-- " + "=" * 60)
    lines.append(f"-- {title}")
    for dl in description.splitlines():
        lines.append(f"-- {dl}")
    lines.append("-- 格式：GRID=60，PALETTE，FRAMES。配合 objectUI.createPixelSequence / createPixelObject 使用。")
    lines.append("-- " + "=" * 60)
    lines.append("")
    lines.append("local M = {}")
    lines.append("")
    lines.append("M.GRID = 60")
    lines.append("M.FRAME_MS = 40")
    lines.append("")
    lines.append("M.PALETTE = {")
    for i in range(1, len(pal) + 1):
        r, g, b = pal[i]
        lines.append(f"    [{i}] = {{{r}, {g}, {b}}},")
    lines.append("}")
    lines.append("")
    lines.append("M.FRAMES = {")
    for fi, rects in enumerate(frames, start=1):
        lines.append(f"    -- 第 {fi} 帧（{len(rects)} 个矩形）")
        lines.append("    {")
        for r in rects:
            lines.append(f"        {{{r[0]}, {r[1]}, {r[2]}, {r[3]}, {r[4]}, {r[5]}}},")
        lines.append("    },")
    lines.append("}")
    lines.append("")
    lines.append("return M")
    lines.append("")
    text = "\n".join(lines)
    with open(out_path, "wb") as f:
        f.write(gen.add_bom(text))


def main():
    # 1) 重建等待投喂网格
    wait_grid, wait_palette = rebuild_waiting_grid()
    wait_img = grid_to_image(wait_grid, wait_palette)
    wb = image_bbox(wait_img)
    print(f"[等待投喂] 重建网格包围盒 x[{wb[0]},{wb[2]}] y[{wb[1]},{wb[3]}] 尺寸 {wb[2]-wb[0]+1}x{wb[3]-wb[1]+1}")

    # 2) 解析当前吞噬.lua
    dev_pal, dev_frames = parse_lua(DEV_PATH)
    n = len(dev_frames)
    print(f"[吞噬.lua] 当前帧数 = {n}")
    assert n >= 6, "吞噬.lua 应至少 6 帧"
    assert len(dev_pal) == 64 and set(dev_pal.keys()) == set(range(1, 65)), "调色板必须为 64 色连续 1-based"

    anim_frames = dev_frames[1:]  # 第 2-6 帧
    dev_pal_list = [dev_pal[i] for i in range(1, 65)]

    # 3) 交集包围盒（稳定身体区域）
    boxes = [per_frame_bbox(f) for f in anim_frames]
    inter = (max(b[0] for b in boxes), max(b[1] for b in boxes),
             min(b[2] for b in boxes), min(b[3] for b in boxes))
    print(f"[交集包围盒] x[{inter[0]},{inter[2]}] y[{inter[1]},{inter[3]}] 尺寸 {inter[2]-inter[0]+1}x{inter[3]-inter[1]+1}")
    assert inter[0] <= inter[2] and inter[1] <= inter[3]

    # 4) 对齐 + 重着色
    aligned_raw, info = align_waiting(wait_img, inter)
    print(f"[对齐] 缩放={info[0]}, 左上角=({info[1]},{info[2]}), 尺寸={info[3]}x{info[4]}")
    aligned = recolor_to_palette(aligned_raw, dev_pal_list)

    # 5) 转网格 + 合并矩形
    grid1 = aligned_to_grid(aligned, dev_pal_list)
    frame1 = gen.merge_rectangles(grid1)
    gen.reconstruct_grid_from_rects(frame1, GRID)  # 验证无重叠
    if gen.reconstruct_grid_from_rects(frame1, GRID) != grid1:
        raise ValueError("第 1 帧矩形合并结果与原网格不一致")
    frame1.sort(key=lambda r: (r[0], r[1]))
    print(f"[方案B] 第 1 帧矩形数 = {len(frame1)}")

    # 6) 写入最终吞噬.lua
    title = "吞噬.lua —— 吃糖小怪兽序列帧像素动画（60x60，融合等待投喂姿态·方案B）"
    desc = (
        "数据来源：用户上传 GIF 序列帧（透明背景）与等待投喂 PNG（透明背景）。\n"
        "第 1 帧：等待投喂姿态（方案 B·交集对齐）。等待投喂 PNG 复现 60x60 网格后，"
        "等比 contain 缩放并居中到吞噬动画各帧稳定身体交集区域\n"
        f"          x[{inter[0]},{inter[2]}] y[{inter[1]},{inter[3]}]（{inter[2]-inter[0]+1}x{inter[3]-inter[1]+1}），"
        "颜色映射回本调色板；喂糖时第 1 帧切到第 2-6 帧身体无跳变。\n"
        "第 2-6 帧：原吞噬动画，FRAME_MS=40 循环播放。"
    )
    final_frames = [frame1] + anim_frames
    write_lua(DEV_PATH, dev_pal, final_frames, title, desc)
    print(f"[写入] {DEV_PATH}")

    # 7) 校验写入结果
    pal2, frames2 = parse_lua(DEV_PATH)
    assert len(frames2) == 6
    for fi, rects in enumerate(frames2, 1):
        for x, y, w, h, c, a in rects:
            assert 0 <= x and x + w <= GRID, f"帧{fi} x 越界"
            assert 0 <= y and y + h <= GRID, f"帧{fi} y 越界"
            assert 1 <= c <= 64, f"帧{fi} 颜色越界"
            assert a == 255
        g = gen.reconstruct_grid_from_rects(rects, GRID)
        print(f"  校验帧{fi}: {len(rects)} 矩形, {sum(1 for row in g for v in row if v >= 0)} 像素")
    print("[校验] 结构完整，无重叠，坐标/颜色/alpha 合法。")

    # 8) 最终预览
    anim_imgs = [render_rects(f, dev_pal_list) for f in anim_frames]
    f1_img = render_rects(frame1, dev_pal_list)
    loop = [f1_img] + anim_imgs + anim_imgs
    loop_up = [up(f) for f in loop]
    dur = [500] + [120] * len(anim_imgs) + [120] * len(anim_imgs)
    loop_up[0].save(
        WS / "吞噬_最终预览.gif",
        save_all=True, append_images=loop_up[1:], duration=dur[1:] + [dur[0]],
        loop=0, disposal=2, transparency=0, background=0,
    )
    print("[输出] 吞噬_最终预览.gif")

    from PIL import ImageDraw, ImageFont
    pad = 12
    cell = GRID * SCALE
    cols = [up(f1_img)] + [up(im) for im in anim_imgs]
    labels = ["第1帧-等待(方案B)", "第2帧", "第3帧", "第4帧", "第5帧", "第6帧"]
    W = len(cols) * (cell + pad) + pad
    H = cell + pad * 2 + 80
    row = Image.new("RGBA", (W, H), (255, 255, 255, 255))
    draw = ImageDraw.Draw(row)
    font = None
    for fp in [r"C:\Windows\Fonts\msyh.ttc", r"C:\Windows\Fonts\simhei.ttf"]:
        try:
            font = ImageFont.truetype(fp, 40)
            break
        except Exception:
            continue
    for i, (im, lab) in enumerate(zip(cols, labels)):
        row.paste(im, (pad + i * (cell + pad), pad + 80), im)
        if font:
            draw.text((pad + i * (cell + pad) + 8, pad + 20), lab, fill=(30, 30, 30), font=font)
    row.convert("RGB").save(WS / "吞噬_最终对比.png")
    print("[输出] 吞噬_最终对比.png")
    print("[完成] 方案 B 已写入吞噬.lua。")


if __name__ == "__main__":
    main()
