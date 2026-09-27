# -*- coding: utf-8 -*-
"""融合预览：把等待投喂人物对齐后作为吞噬动画第一帧，生成 GIF 预览。
仅用于确认对齐关系，不修改任何 Lua 源文件。
"""
import re
from pathlib import Path
from PIL import Image

WS = Path(r"E:\千星\千星游戏")
DEV_PATH = WS / "吞噬.lua"
WAIT_PATH = WS / "等待投喂.lua"
GRID = 60
SCALE = 10  # 预览放大倍数


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


def frame_to_image(rects, pal, grid=GRID):
    img = Image.new("RGBA", (grid, grid), (0, 0, 0, 0))
    px = img.load()
    for x, y, w, h, c, a in rects:
        col = pal[c]
        for yy in range(y, y + h):
            for xx in range(x, x + w):
                px[xx, yy] = (col[0], col[1], col[2], a)
    return img


def bbox(img):
    data = img.load()
    w, h = img.size
    xs, ys = [], []
    for y in range(h):
        for x in range(w):
            if data[x, y][3] > 10:
                xs.append(x)
                ys.append(y)
    if not xs:
        return None
    return (min(xs), min(ys), max(xs), max(ys))


def recolor_to_palette(img, pal):
    """把 img 中不透明像素颜色替换为 devour 调色板里最近的颜色，保证融合后母体配色一致。"""
    data = img.load()
    w, h = img.size
    pal_list = list(pal.values())
    for y in range(h):
        for x in range(w):
            r, g, b, a = data[x, y]
            if a <= 10:
                continue
            best = None
            best_d = None
            for pr, pg, pb in pal_list:
                d = (r - pr) ** 2 + (g - pg) ** 2 + (b - pb) ** 2
                if best_d is None or d < best_d:
                    best_d = d
                    best = (pr, pg, pb)
            data[x, y] = (best[0], best[1], best[2], a)
    return img


def align_waiting(wait_img, target_bbox, dev_pal):
    """把等待投喂角色等比 contain 到目标包围盒，居中放置，并重新着色到 dev_pal。"""
    tx0, ty0, tx1, ty1 = target_bbox
    tw_box = tx1 - tx0 + 1
    th_box = ty1 - ty0 + 1

    wb = bbox(wait_img)
    wx0, wy0, wx1, wy1 = wb
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
    aligned = recolor_to_palette(aligned, dev_pal)
    return aligned, (s, tx, ty, tw, th)


def up(img):
    return img.resize((GRID * SCALE, GRID * SCALE), Image.NEAREST)


def save_gif(aligned, dev_imgs, path):
    fusion = [aligned] + dev_imgs
    loop = fusion + dev_imgs  # 播放两遍以便循环效果可见
    loop_up = [up(f) for f in loop]
    dur = [500] + [120] * len(dev_imgs) + [120] * len(dev_imgs)
    loop_up[0].save(
        path,
        save_all=True,
        append_images=loop_up[1:],
        duration=dur[1:] + [dur[0]],
        loop=0,
        disposal=2,
        transparency=0,
        background=0,
    )


def frame_rgb_grid(rects, pal, grid=GRID):
    """把一帧矩形还原为 60×60 RGB 网格，透明处为 None。"""
    g = [[None] * grid for _ in range(grid)]
    for x, y, w, h, c, a in rects:
        if a <= 128:
            continue
        col = pal[c]
        for yy in range(y, y + h):
            for xx in range(x, x + w):
                if 0 <= xx < grid and 0 <= yy < grid:
                    g[yy][xx] = col
    return g


def derive_consensus_waiting(dev_frames, dev_pal, grid=GRID, min_frames=4, tau=16):
    """方案 C（相近取平均版）：
    每格收集 5 帧不透明像素；找出“>=4 帧颜色相近(每通道差<=tau)”的子集，
    取这些相近帧的平均色，再映射到吞噬调色板，作为等待姿态像素。
    返回 (rgb_grid, n_stable)。
    """
    rgb_grids = [frame_rgb_grid(f, dev_pal, grid) for f in dev_frames]
    n = len(rgb_grids)
    out = [[None] * grid for _ in range(grid)]
    n_stable = 0
    for y in range(grid):
        for x in range(grid):
            cols = [rgb_grids[k][y][x] for k in range(n) if rgb_grids[k][y][x] is not None]
            if len(cols) < min_frames:
                continue
            # 找最大的“相近簇”
            best = None
            for seed in cols:
                cluster = [c for c in cols
                           if abs(c[0] - seed[0]) <= tau
                           and abs(c[1] - seed[1]) <= tau
                           and abs(c[2] - seed[2]) <= tau]
                if best is None or len(cluster) > len(best):
                    best = cluster
            if len(best) >= min_frames:
                ar = sum(c[0] for c in best) // len(best)
                ag = sum(c[1] for c in best) // len(best)
                ab = sum(c[2] for c in best) // len(best)
                out[y][x] = (ar, ag, ab)
                n_stable += 1
    return out, n_stable


def rgb_to_palette_image(rgb_grid, pal, grid=GRID):
    """把平均 RGB 网格映射到最近调色板色，渲染成图像。"""
    pal_list = list(pal.values())
    img = Image.new("RGBA", (grid, grid), (0, 0, 0, 0))
    px = img.load()
    for y in range(grid):
        for x in range(grid):
            c = rgb_grid[y][x]
            if c is None:
                continue
            best = min(pal_list, key=lambda p: (c[0] - p[0]) ** 2 + (c[1] - p[1]) ** 2 + (c[2] - p[2]) ** 2)
            px[x, y] = (best[0], best[1], best[2], 255)
    return img


def frame_index_grid(rects, grid=GRID):
    """把一帧矩形还原为 60×60 颜色索引网格，透明处为 -1。"""
    g = [[-1] * grid for _ in range(grid)]
    for x, y, w, h, c, a in rects:
        if a <= 128:
            continue
        for yy in range(y, y + h):
            for xx in range(x, x + w):
                if 0 <= xx < grid and 0 <= yy < grid:
                    g[yy][xx] = c
    return g


def derive_consensus_waiting_index(dev_frames, dev_pal, grid=GRID, min_frames=4):
    """方案 C（原始严格版）：>=4 帧同调色板索引。"""
    from collections import Counter
    grids = [frame_index_grid(f, grid) for f in dev_frames]
    n = len(grids)
    wait = [[-1] * grid for _ in range(grid)]
    n_stable = 0
    for y in range(grid):
        for x in range(grid):
            present = [grids[k][y][x] for k in range(n) if grids[k][y][x] != -1]
            if len(present) < min_frames:
                continue
            cnt = Counter(present)
            color, count = cnt.most_common(1)[0]
            if count >= min_frames:
                wait[y][x] = color
                n_stable += 1
    return wait, n_stable


def grid_to_image(index_grid, pal, grid=GRID):
    img = Image.new("RGBA", (grid, grid), (0, 0, 0, 0))
    px = img.load()
    for y in range(grid):
        for x in range(grid):
            c = index_grid[y][x]
            if c != -1:
                col = pal[c]
                px[x, y] = (col[0], col[1], col[2], 255)
    return img


def main():
    dev_pal, dev_frames = parse_lua(DEV_PATH)
    wait_pal, wait_frames = parse_lua(WAIT_PATH)
    wait_img = frame_to_image(wait_frames[0], wait_pal)
    dev_imgs = [frame_to_image(f, dev_pal) for f in dev_frames]

    print(f"[吞噬] 帧数 = {len(dev_frames)}")
    print(f"[等待投喂] 帧数 = {len(wait_frames)}")

    # 各帧包围盒
    dev_bboxes = [bbox(im) for im in dev_imgs]
    for i, b in enumerate(dev_bboxes, 1):
        print(f"[吞噬] 第{i}帧包围盒 x[{b[0]},{b[2]}] y[{b[1]},{b[3]}] 尺寸 {b[2]-b[0]+1}x{b[3]-b[1]+1}")

    # 并集（角色整体活动范围）
    union = [dev_bboxes[0][0], dev_bboxes[0][1], dev_bboxes[0][2], dev_bboxes[0][3]]
    for b in dev_bboxes[1:]:
        union[0] = min(union[0], b[0])
        union[1] = min(union[1], b[1])
        union[2] = max(union[2], b[2])
        union[3] = max(union[3], b[3])
    print(f"[并集包围盒] x[{union[0]},{union[2]}] y[{union[1]},{union[3]}] 尺寸 {union[2]-union[0]+1}x{union[3]-union[1]+1}")

    # 交集（各帧都存在的稳定身体区域）
    inter = [max(b[0] for b in dev_bboxes), max(b[1] for b in dev_bboxes),
             min(b[2] for b in dev_bboxes), min(b[3] for b in dev_bboxes)]
    if inter[0] <= inter[2] and inter[1] <= inter[3]:
        print(f"[交集包围盒] x[{inter[0]},{inter[2]}] y[{inter[1]},{inter[3]}] 尺寸 {inter[2]-inter[0]+1}x{inter[3]-inter[1]+1}")
    else:
        inter = union
        print("[交集包围盒] 为空，退化为并集")

    # 方案 A：以并集为基准 —— 等待角色填充整个动画活动范围
    aligned_union, info_union = align_waiting(wait_img, union, dev_pal)
    save_gif(aligned_union, dev_imgs, WS / "吞噬_融合预览_并集.gif")
    print(f"[方案A-并集] 缩放={info_union[0]:.4f}, 左上角=({info_union[1]},{info_union[2]}), 尺寸={info_union[3]}x{info_union[4]}")

    # 方案 B：以交集为基准 —— 等待角色只匹配稳定身体，嘴部作为后续动画出现
    aligned_inter, info_inter = align_waiting(wait_img, inter, dev_pal)
    save_gif(aligned_inter, dev_imgs, WS / "吞噬_融合预览_交集.gif")
    print(f"[方案B-交集] 缩放={info_inter[0]:.4f}, 左上角=({info_inter[1]},{info_inter[2]}), 尺寸={info_inter[3]}x{info_inter[4]}")

    # 方案 C：直接从吞噬各帧投票出稳定身体作为等待姿态（相近取平均版）
    rgb_grid_c, n_stable = derive_consensus_waiting(dev_frames, dev_pal, min_frames=4, tau=16)
    wait_img_c = rgb_to_palette_image(rgb_grid_c, dev_pal)
    save_gif(wait_img_c, dev_imgs, WS / "吞噬_融合预览_共识.gif")
    print(f"[方案C-共识] 稳定像素格 {n_stable} 个（相近取平均），已写为融合第1帧")

    # 静态对比图（聚焦方案 C）：原始等待投喂 / 方案C共识等待 / 吞噬第1帧 / 吞噬第3帧
    pad = 12
    cell = GRID * SCALE
    imgs_row = [up(wait_img), up(wait_img_c), up(dev_imgs[0]), up(dev_imgs[2])]
    row = Image.new("RGBA", (len(imgs_row) * (cell + pad) + pad, cell + pad * 2), (255, 255, 255, 255))
    for i, im in enumerate(imgs_row):
        row.paste(im, (pad + i * (cell + pad), pad), im)
    png_path = WS / "吞噬_融合对比_共识.png"
    row.convert("RGB").save(png_path)
    print(f"[输出] 方案C静态对比 -> {png_path}")
    print("[完成] 仅生成预览，未修改任何 Lua 文件。")


if __name__ == "__main__":
    main()
