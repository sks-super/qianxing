# -*- coding: utf-8 -*-
"""
最终融合：把「投票推导的等待姿态」写为吞噬.lua 第 1 帧（第 2-6 帧 = 原吞噬动画）。
等待姿态算法（用户确认版）：
  每格收集 5 帧不透明像素；若存在 >=4 帧颜色相近（每通道差 <= tau=16）的子集，
  则取该子集的 R、G、B 逐通道平均，合成平均色，再映射回吞噬调色板最近色。
输出：
  吞噬.lua               —— 6 帧（第 1 帧等待姿态 + 第 2-6 帧吞噬动画），FRAME_MS=40
  吞噬_融合完成.gif       —— 完成的融合动图预览
  吞噬_最终帧条.png       —— 6 帧横向帧条
  吞噬.lua.preview.png    —— 覆盖旧预览
"""
import sys
from pathlib import Path
from PIL import Image

sys.path.insert(0, r"E:\千星\千星游戏")
from _gen_from_images import merge_rectangles, reconstruct_grid_from_rects, add_bom
from _preview_fusion import parse_lua, frame_to_image, up, derive_consensus_waiting

WS = Path(r"E:\千星\千星游戏")
DEV_PATH = WS / "吞噬.lua"
GRID = 60
TAU = 16
MIN_FRAMES = 4


def nearest_palette_index(rgb, palette_list):
    best_i, best_d = None, None
    for i, p in enumerate(palette_list, 1):
        d = (rgb[0] - p[0]) ** 2 + (rgb[1] - p[1]) ** 2 + (rgb[2] - p[2]) ** 2
        if best_d is None or d < best_d:
            best_d, best_i = d, i
    return best_i


def main():
    dev_pal, dev_frames = parse_lua(DEV_PATH)
    pal_list = [dev_pal[i] for i in sorted(dev_pal)]
    assert len(pal_list) == 64, f"调色板应为 64 色，实际 {len(pal_list)}"
    print(f"[吞噬] 解析完成：{len(dev_frames)} 帧，调色板 {len(pal_list)} 色")

    # 1) 投票推导等待姿态（相近取平均）
    rgb_grid, n_stable = derive_consensus_waiting(dev_frames, dev_pal, min_frames=MIN_FRAMES, tau=TAU)
    print(f"[等待姿态] 稳定像素格 {n_stable} 个（≥{MIN_FRAMES} 帧相近，每通道差≤{TAU}，逐通道平均）")

    # 2) 平均色 -> 最近调色板索引
    idx_grid = [[-1] * GRID for _ in range(GRID)]
    for y in range(GRID):
        for x in range(GRID):
            c = rgb_grid[y][x]
            if c is not None:
                idx_grid[y][x] = nearest_palette_index(c, pal_list)

    # 3) 合并矩形 + 校验
    frame1_rects = merge_rectangles(idx_grid)
    recon = reconstruct_grid_from_rects(frame1_rects, GRID)
    assert recon == idx_grid, "第 1 帧矩形合并校验失败（与原网格不一致）"
    frame1_rects.sort(key=lambda r: (r[0], r[1]))
    print(f"[第1帧] 矩形数 {len(frame1_rects)}，合并校验通过")

    # 4) 最终帧序：第 1 帧等待姿态 + 第 2-6 帧原吞噬动画
    final_rects = [frame1_rects] + dev_frames
    rect_counts = [len(r) for r in final_rects]
    print(f"[最终] 总帧数 {len(final_rects)}，每帧矩形数 {rect_counts}")

    # 5) 写 Lua（UTF-8 BOM，格式与旧文件一致）
    lines = []
    lines.append("-- " + "=" * 60)
    lines.append("-- 吞噬.lua —— 吃糖小怪兽序列帧像素动画（60x60，融合等待投喂姿态）")
    lines.append("-- 数据来源：用户上传 GIF 序列帧（透明背景）。")
    lines.append("-- 第 1 帧：等待投喂姿态，由 5 帧投票推导（每格取 >=4 帧相近色，逐通道平均后映射回本调色板）；")
    lines.append("--          与游戏内常态等待姿态完全一致，喂糖时第 1 帧切到第 2-6 帧无跳变。")
    lines.append("-- 第 2-6 帧：原吞噬动画，FRAME_MS=40 循环播放。")
    lines.append("-- 格式：GRID=60，PALETTE，FRAMES。配合 objectUI.createPixelSequence / createPixelObject 使用。")
    lines.append("-- " + "=" * 60)
    lines.append("")
    lines.append("local M = {}")
    lines.append("")
    lines.append("M.GRID = 60")
    lines.append("M.FRAME_MS = 40")
    lines.append("")
    lines.append("M.PALETTE = {")
    for i, (r, g, b) in enumerate(pal_list, 1):
        lines.append(f"    [{i}] = {{{r}, {g}, {b}}},")
    lines.append("}")
    lines.append("")
    lines.append("M.FRAMES = {")
    for fi, rects in enumerate(final_rects, 1):
        tag = "等待投喂姿态（投票推导）" if fi == 1 else "吞噬动画"
        lines.append(f"    -- 第 {fi} 帧 {tag}（{len(rects)} 个矩形）")
        lines.append("    {")
        for r in rects:
            lines.append(f"        {{{r[0]}, {r[1]}, {r[2]}, {r[3]}, {r[4]}, {r[5]}}},")
        lines.append("    },")
    lines.append("}")
    lines.append("")
    lines.append("return M")
    lines.append("")
    lua_text = "\n".join(lines)
    with open(WS / "吞噬.lua", "wb") as f:
        f.write(add_bom(lua_text))
    print("[写入] 吞噬.lua 完成")

    # 6) 渲染全部 6 帧
    all_imgs = [frame_to_image(r, dev_pal) for r in final_rects]

    # 7) 完成 GIF：第 1 帧停留，第 2-6 帧循环两遍
    seq = [all_imgs[0]] + all_imgs[1:] + all_imgs[1:]
    up_seq = [up(im) for im in seq]
    durations = [600] + [120] * (len(all_imgs) - 1) * 2
    gif_path = WS / "吞噬_融合完成.gif"
    up_seq[0].save(
        gif_path,
        save_all=True,
        append_images=up_seq[1:],
        duration=durations,
        loop=0,
        disposal=2,
        transparency=0,
        background=0,
    )
    print(f"[输出] 完成 GIF -> {gif_path}")

    # 8) 6 帧帧条 + 覆盖旧 preview
    strip = Image.new("RGBA", (GRID * len(all_imgs), GRID), (255, 255, 255, 255))
    for i, im in enumerate(all_imgs):
        strip.paste(im, (GRID * i, 0), im)
    strip_big = strip.resize((GRID * len(all_imgs) * 6, GRID * 6), Image.NEAREST)
    strip_big.save(WS / "吞噬_最终帧条.png")
    strip_big.save(WS / "吞噬.lua.preview.png")
    print("[输出] 帧条 -> 吞噬_最终帧条.png / 吞噬.lua.preview.png")
    print("[完成] 最终融合完成（等待投喂姿态已并入吞噬.lua 第 1 帧）")


if __name__ == "__main__":
    main()
