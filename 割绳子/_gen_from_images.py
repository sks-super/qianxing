#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
千星奇域像素 Lua 生成器
从源图/源 GIF 提取 60x60 像素数据，按项目约定输出 Lua 表：
  M.GRID = 60
  M.FRAME_MS = ...
  M.PALETTE = { [1] = {r,g,b}, ... }
  M.FRAMES = { { {x,y,w,h,colorIndex,alpha}, ... }, ... }
处理流程：
  1) 背景剔除 / 读取 alpha；
  2) 计算全局包围盒（多帧取并集），等比 contain 居中到 60x60；
  3) LANCZOS 平滑缩小；
  4) MEDIANCUT 64 色调色板量化（无抖动）；
  5) alpha 硬二值化（>128 为实心）；
  6) 同行/同列相邻同色合并为矩形。
"""

import os
import sys
import math
from collections import deque
from PIL import Image
import numpy as np

GRID = 60
N_COLORS = 64
ALPHA_THRESHOLD = 128


def add_bom(text: str) -> bytes:
    return "\ufeff".encode("utf-8") + text.encode("utf-8")


def remove_bg_floodfill(img: Image.Image, threshold: int = 240) -> Image.Image:
    """从四角 flood-fill 移除近白背景（适用于 JPG 白底）。"""
    img = img.convert("RGBA").copy()
    w, h = img.size
    pixels = img.load()

    # 候选背景：像素接近白色
    def is_bg_candidate(x, y):
        r, g, b, a = pixels[x, y]
        return a < ALPHA_THRESHOLD or (r > threshold and g > threshold and b > threshold)

    visited = bytearray(w * h)
    q = deque()
    seeds = [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)]
    for sx, sy in seeds:
        if is_bg_candidate(sx, sy) and not visited[sy * w + sx]:
            visited[sy * w + sx] = 1
            q.append((sx, sy))

    while q:
        x, y = q.popleft()
        pixels[x, y] = (0, 0, 0, 0)
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = x + dx, y + dy
            if 0 <= nx < w and 0 <= ny < h:
                idx = ny * w + nx
                if not visited[idx] and is_bg_candidate(nx, ny):
                    visited[idx] = 1
                    q.append((nx, ny))
    return img


def load_frames(path: str, bg_threshold: int | None = None) -> list[Image.Image]:
    """读取源文件，返回 RGBA 帧列表（单帧文件返回 1 个元素）。"""
    img = Image.open(path)
    frames = []
    if getattr(img, "is_animated", False):
        for i in range(img.n_frames):
            img.seek(i)
            frame = img.convert("RGBA").copy()
            frames.append(frame)
    else:
        if bg_threshold is not None:
            frames.append(remove_bg_floodfill(img, bg_threshold))
        else:
            frames.append(img.convert("RGBA").copy())
    return frames


def global_bbox(frames: list[Image.Image]) -> tuple[int, int, int, int]:
    """所有帧非透明像素的并集包围盒。"""
    min_x, min_y, max_x, max_y = math.inf, math.inf, -math.inf, -math.inf
    for frame in frames:
        bbox = frame.getbbox()
        if bbox:
            x0, y0, x1, y1 = bbox
            min_x = min(min_x, x0)
            min_y = min(min_y, y0)
            max_x = max(max_x, x1)
            max_y = max(max_y, y1)
    if math.isinf(min_x):
        return (0, 0, 1, 1)
    return (int(min_x), int(min_y), int(max_x), int(max_y))


def resize_frame_to_grid(frame: Image.Image, bbox: tuple[int, int, int, int], grid: int) -> Image.Image:
    """把 frame 按 bbox 裁剪、等比 contain 缩放到 grid×grid 并居中。"""
    x0, y0, x1, y1 = bbox
    bw, bh = x1 - x0, y1 - y0
    scale = min(grid / bw, grid / bh)
    new_w = max(1, int(round(bw * scale)))
    new_h = max(1, int(round(bh * scale)))
    cropped = frame.crop((x0, y0, x1, y1))
    resized = cropped.resize((new_w, new_h), Image.Resampling.LANCZOS)
    # 居中贴到 grid×grid 透明画布
    canvas = Image.new("RGBA", (grid, grid), (0, 0, 0, 0))
    paste_x = (grid - new_w) // 2
    paste_y = (grid - new_h) // 2
    canvas.paste(resized, (paste_x, paste_y), resized)
    return canvas


def build_palette(frames: list[Image.Image], n_colors: int) -> tuple[list[tuple[int, int, int]], list[Image.Image]]:
    """
    对所有帧统一量化，返回 (palette_rgb_list, quantized_index_frames)。
    索引帧中每个像素为调色板下标（P 模式）。
    """
    grid = frames[0].size[0]
    n = len(frames)
    # 拼成一张大图做统一量化
    strip = Image.new("RGBA", (grid * n, grid), (0, 0, 0, 0))
    for i, frame in enumerate(frames):
        strip.paste(frame, (grid * i, 0), frame)

    # 为避免透明像素影响调色板，用平均不透明色填充它们
    arr = np.array(strip)
    alpha_mask = arr[:, :, 3] >= ALPHA_THRESHOLD
    if np.any(alpha_mask):
        mean_color = tuple(arr[alpha_mask, :3].mean(axis=0).astype(int).tolist())
    else:
        mean_color = (128, 128, 128)

    filled = Image.new("RGB", strip.size, mean_color)
    filled.paste(strip, (0, 0), strip)

    quantized = filled.quantize(colors=n_colors, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    pal = quantized.getpalette()
    assert pal is not None
    pal = pal[:n_colors * 3]
    palette = [(pal[i], pal[i + 1], pal[i + 2]) for i in range(0, len(pal), 3)]

    # 把量化索引按原 alpha 切回各帧
    qdata = np.array(quantized)
    index_frames = []
    for i in range(n):
        sub = qdata[:, grid * i: grid * (i + 1)].copy()
        idx_img = Image.fromarray(sub, mode="P")
        index_frames.append(idx_img)
    return palette, index_frames


def build_grid(canvas: Image.Image, idx_img: Image.Image) -> list[list[int]]:
    """返回 grid×grid 的颜色索引表；索引为 1-based，透明处为 -1。"""
    rgba = np.array(canvas)
    idx = np.array(idx_img)
    h, w = rgba.shape[:2]
    grid = []
    for y in range(h):
        row = []
        for x in range(w):
            if rgba[y, x, 3] > ALPHA_THRESHOLD:
                row.append(int(idx[y, x]) + 1)  # PIL 是 0-based，Lua 调色板是 1-based
            else:
                row.append(-1)
        grid.append(row)
    return grid


def merge_rectangles(grid: list[list[int]]) -> list[list[int]]:
    """把颜色网格合并为同色矩形列表。返回 [{x,y,w,h,colorIndex,alpha}, ...]。"""
    h = len(grid)
    w = len(grid[0]) if h else 0
    rects = []

    # 统计出现的颜色
    colors = set()
    for y in range(h):
        for x in range(w):
            c = grid[y][x]
            if c >= 0:
                colors.add(c)

    for c in colors:
        # open[(x, width)] = [y_start, h]
        open_rects: dict[tuple[int, int], list[int]] = {}
        for y in range(h):
            # 收集当前行颜色 c 的水平段
            runs = []
            x = 0
            while x < w:
                if grid[y][x] == c:
                    start = x
                    while x < w and grid[y][x] == c:
                        x += 1
                    runs.append((start, x - start))
                else:
                    x += 1

            extended_keys = set()
            for x, width in runs:
                key = (x, width)
                if key in open_rects:
                    rect = open_rects[key]
                    if rect[0] + rect[1] == y:
                        rect[1] += 1
                        extended_keys.add(key)
                    else:
                        # 不连续，关闭旧矩形并开新
                        rects.append([x, rect[0], width, rect[1], c, 255])
                        open_rects[key] = [y, 1]
                        extended_keys.add(key)
                else:
                    open_rects[key] = [y, 1]
                    extended_keys.add(key)

            # 未被延续的矩形关闭
            closed = [k for k in open_rects if k not in extended_keys]
            for k in closed:
                rect = open_rects[k]
                rects.append([k[0], rect[0], k[1], rect[1], c, 255])
                del open_rects[k]

        # 扫尾
        for k, rect in open_rects.items():
            rects.append([k[0], rect[0], k[1], rect[1], c, 255])

        # 断言：本颜色矩形无重叠且完全覆盖本色像素
        coverage = [[-1] * w for _ in range(h)]
        for xr, yr, wr, hr, cr, _ in [r for r in rects if r[4] == c]:
            for yy in range(yr, yr + hr):
                for xx in range(xr, xr + wr):
                    if coverage[yy][xx] != -1:
                        raise ValueError(f"颜色 {c} 内部矩形重叠 at ({xx},{yy})")
                    if grid[yy][xx] != c:
                        raise ValueError(f"颜色 {c} 的矩形覆盖非本色像素 at ({xx},{yy})")
                    coverage[yy][xx] = c

    return rects


def format_lua(
    palette: list[tuple[int, int, int]],
    frames_rects: list[list[list[int]]],
    frame_ms: int,
    title: str,
    description: str,
) -> str:
    lines = []
    lines.append("-- " + "=" * 60)
    lines.append(f"-- {title}")
    lines.append(f"-- {description}")
    lines.append("-- 处理：等比 contain 居中 + 64 色中位切分调色板量化（无抖动）+ alpha 硬二值化")
    lines.append("-- 格式：GRID=60，PALETTE，FRAMES。配合 objectUI.createPixelSequence / createPixelObject 使用。")
    lines.append("-- " + "=" * 60)
    lines.append("")
    lines.append("local M = {}")
    lines.append("")
    lines.append("M.GRID = 60")
    lines.append(f"M.FRAME_MS = {frame_ms}")
    lines.append("")
    lines.append("M.PALETTE = {")
    for i, (r, g, b) in enumerate(palette, start=1):
        lines.append(f"    [{i}] = {{{r}, {g}, {b}}},")
    lines.append("}")
    lines.append("")
    lines.append("M.FRAMES = {")
    for fi, rects in enumerate(frames_rects, start=1):
        lines.append(f"    -- 第 {fi} 帧（{len(rects)} 个矩形）")
        lines.append("    {")
        for r in rects:
            lines.append(f"        {{{r[0]}, {r[1]}, {r[2]}, {r[3]}, {r[4]}, {r[5]}}},")
        lines.append("    },")
    lines.append("}")
    lines.append("")
    lines.append("return M")
    lines.append("")
    return "\n".join(lines)


def reconstruct_grid_from_rects(rects: list[list[int]], grid: int) -> list[list[int]]:
    """根据矩形列表重建颜色网格，透明处为 -1；同时检查无重叠。"""
    g = [[-1] * grid for _ in range(grid)]
    for ri, (x, y, w, h, c, _) in enumerate(rects):
        for yy in range(y, y + h):
            for xx in range(x, x + w):
                if not (0 <= xx < grid and 0 <= yy < grid):
                    raise ValueError(f"矩形越界: ({x},{y},{w},{h})")
                if g[yy][xx] != -1:
                    # 找到重叠的另一个矩形
                    other = None
                    other_color = -1
                    for rj, (x2, y2, w2, h2, c2, _) in enumerate(rects):
                        if rj != ri and x2 <= xx < x2 + w2 and y2 <= yy < y2 + h2:
                            other = rj
                            other_color = c2
                            break
                    raise ValueError(f"矩形重叠 at ({xx},{yy}): rect {ri} color={c} ({x},{y},{w},{h}) vs rect {other} color={other_color}")
                g[yy][xx] = c
    return g


def save_preview(preview_path: str, palette: list[tuple[int, int, int]], rects_list: list[list[list[int]]], grid: int):
    """把矩形渲染为预览图，多帧横向拼接。"""
    n = len(rects_list)
    preview = Image.new("RGBA", (grid * n, grid), (255, 255, 255, 255))
    for fi, rects in enumerate(rects_list):
        for x, y, w, h, c, a in rects:
            r, g, b = palette[c - 1]
            for yy in range(y, y + h):
                for xx in range(x, x + w):
                    preview.putpixel((fi * grid + xx, yy), (r, g, b, a))
    preview.save(preview_path)


def process(
    src_path: str,
    out_path: str,
    frame_ms: int,
    title: str,
    description: str,
    bg_threshold: int | None = None,
) -> dict:
    frames = load_frames(src_path, bg_threshold=bg_threshold)
    bbox = global_bbox(frames)
    grid_frames = [resize_frame_to_grid(f, bbox, GRID) for f in frames]
    palette, idx_frames = build_palette(grid_frames, N_COLORS)

    all_rects = []
    grids = []
    for canvas, idx_img in zip(grid_frames, idx_frames):
        grid = build_grid(canvas, idx_img)
        rects = merge_rectangles(grid)
        # 验证矩形合并正确性（无重叠、无遗漏）
        reconstructed = reconstruct_grid_from_rects(rects, GRID)
        if reconstructed != grid:
            raise ValueError("矩形合并结果与原网格不一致")
        # 按 y、x 排序，输出更规整
        rects.sort(key=lambda r: (r[0], r[1]))
        all_rects.append(rects)
        grids.append(grid)

    lua_text = format_lua(palette, all_rects, frame_ms, title, description)
    with open(out_path, "wb") as f:
        f.write(add_bom(lua_text))

    # 保存预览图
    preview_path = out_path + ".preview.png"
    save_preview(preview_path, palette, all_rects, GRID)

    return {
        "src": src_path,
        "out": out_path,
        "preview": preview_path,
        "n_frames": len(frames),
        "palette_size": len(palette),
        "rect_counts": [len(r) for r in all_rects],
        "bbox": bbox,
    }


def main():
    base = r"E:\千星\千星游戏"
    clip = r"C:\Users\Twinkle\.workbuddy\clipboard-images"

    jobs = [
        {
            "src": f"{clip}\\clipboard-2026-08-22T18-02-25-420Z-fd766e8c.jpg",
            "out": f"{base}\\蛋糕.lua",
            "frame_ms": 100,
            "title": "蛋糕.lua —— 糖果/蛋糕像素画（60x60）",
            "desc": "数据来源：用户上传蛋糕图片（JPG，白色背景已剔除）。",
            "bg_threshold": 240,
        },
        {
            "src": f"{clip}\\clipboard-2026-08-22T18-02-25-424Z-d60327ee.gif",
            "out": f"{base}\\吞噬.lua",
            "frame_ms": 40,
            "title": "吞噬.lua —— 吃糖小怪兽序列帧像素动画（60x60）",
            "desc": "数据来源：用户上传 GIF 序列帧（透明背景）。",
            "bg_threshold": None,
        },
        {
            "src": f"{clip}\\clipboard-2026-08-22T18-02-25-427Z-0535da1b.png",
            "out": f"{base}\\等待投喂.lua",
            "frame_ms": 100,
            "title": "等待投喂.lua —— 小怪兽常态等待像素画（60x60）",
            "desc": "数据来源：用户上传图片（透明背景 PNG）。",
            "bg_threshold": None,
        },
    ]

    for job in jobs:
        info = process(
            job["src"],
            job["out"],
            job["frame_ms"],
            job["title"],
            job["desc"],
            job["bg_threshold"],
        )
        print(f"生成: {info['out']}")
        print(f"  预览: {info['preview']}")
        print(f"  帧数: {info['n_frames']}, 调色板: {info['palette_size']} 色")
        print(f"  每帧矩形数: {info['rect_counts']}")
        print(f"  源图全局包围盒: {info['bbox']}")


if __name__ == "__main__":
    main()
