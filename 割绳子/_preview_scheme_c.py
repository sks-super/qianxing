# -*- coding: utf-8 -*-
"""方案C：直接由吞噬动画各帧稳定像素推导等待投喂帧。
规则：每个像素格，动画 5 帧中至少 4 帧的颜色“基本相近”（每通道差 <= TAU），
      取这些相近颜色的 RGB 平均值作为等待投喂帧该格的像素；否则该格透明。
并对比当前吞噬.lua 已有第 1 帧（疑似同法生成），给出差异统计。
仅生成预览，不修改任何 Lua 源文件。
"""
import re
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

WS = Path(r"E:\千星\千星游戏")
DEV_PATH = WS / "吞噬.lua"
GRID = 60
SCALE = 10
TAU = 32       # 每通道最大差，视为“基本相近”
MIN_AGREE = 4  # 至少 4 帧相近


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


def derive_waiting(dev_imgs, tau=TAU, min_agree=MIN_AGREE):
    """逐格统计 5 帧颜色，保留至少 min_agree 帧相近的颜色并取平均。"""
    out = Image.new("RGBA", (GRID, GRID), (0, 0, 0, 0))
    opx = out.load()
    frames_px = [im.load() for im in dev_imgs]
    stats = {k: 0 for k in range(min_agree, len(dev_imgs) + 1)}
    kept = 0
    for y in range(GRID):
        for x in range(GRID):
            colors = []
            for fp in frames_px:
                r, g, b, a = fp[x, y]
                if a > 128:
                    colors.append((r, g, b))
            if len(colors) < min_agree:
                continue
            best_count = 0
            best_members = []
            for c in colors:
                members = [c2 for c2 in colors
                           if abs(c[0] - c2[0]) <= tau and abs(c[1] - c2[1]) <= tau and abs(c[2] - c2[2]) <= tau]
                if len(members) > best_count:
                    best_count = len(members)
                    best_members = members
            if best_count < min_agree:
                continue
            ar = sum(m[0] for m in best_members) // len(best_members)
            ag = sum(m[1] for m in best_members) // len(best_members)
            ab = sum(m[2] for m in best_members) // len(best_members)
            opx[x, y] = (ar, ag, ab, 255)
            stats[best_count] += 1
            kept += 1
    return out, stats, kept


def nearest_palette(rgb, pal_list):
    r, g, b = rgb
    best, best_d = None, None
    for pr, pg, pb in pal_list:
        d = (r - pr) ** 2 + (g - pg) ** 2 + (b - pb) ** 2
        if best_d is None or d < best_d:
            best_d = d
            best = (pr, pg, pb)
    return best


def bbox(img):
    data = img.load()
    xs, ys = [], []
    for y in range(GRID):
        for x in range(GRID):
            if data[x, y][3] > 10:
                xs.append(x)
                ys.append(y)
    if not xs:
        return None
    return (min(xs), min(ys), max(xs), max(ys))


def up(img):
    return img.resize((GRID * SCALE, GRID * SCALE), Image.NEAREST)


def save_gif(derived, dev_imgs, path):
    loop = [derived] + dev_imgs + dev_imgs
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


def main():
    dev_pal, dev_frames = parse_lua(DEV_PATH)
    n = len(dev_frames)
    print(f"[吞噬.lua] 当前总帧数 = {n}")

    if n >= 6:
        anim_rects = dev_frames[1:]          # 第 2-6 帧 = 动画
        existing_f1 = dev_frames[0]          # 第 1 帧 = 已有等待姿态
    else:
        anim_rects = dev_frames
        existing_f1 = None

    dev_imgs = [frame_to_image(f, dev_pal) for f in anim_rects]
    print(f"[推导] 使用动画帧数 = {len(dev_imgs)}")

    derived, stats, kept = derive_waiting(dev_imgs)
    print(f"[方案C] 稳定像素数 = {kept}, 相近帧数分布 = {dict(sorted(stats.items()))}")
    db = bbox(derived)
    print(f"[方案C] 推导帧包围盒 x[{db[0]},{db[2]}] y[{db[1]},{db[3]}] 尺寸 {db[2]-db[0]+1}x{db[3]-db[1]+1}")

    # 与已有第 1 帧对比
    if existing_f1 is not None:
        exist_img = frame_to_image(existing_f1, dev_pal)
        pal_list = list(dev_pal.values())
        dpx = derived.load()
        epx = exist_img.load()
        diff_cnt = 0
        same_cnt = 0
        max_diff = 0
        for y in range(GRID):
            for x in range(GRID):
                a1 = dpx[x, y][3]
                a2 = epx[x, y][3]
                if (a1 > 128) != (a2 > 128):
                    diff_cnt += 1
                    continue
                if a1 <= 128:
                    same_cnt += 1
                    continue
                m = nearest_palette((dpx[x, y][0], dpx[x, y][1], dpx[x, y][2]), pal_list)
                d = abs(m[0] - epx[x, y][0]) + abs(m[1] - epx[x, y][1]) + abs(m[2] - epx[x, y][2])
                if d > 0:
                    diff_cnt += 1
                else:
                    same_cnt += 1
                max_diff = max(max_diff, d)
        print(f"[对比] 与已有第1帧: 一致格 {same_cnt}, 差异格 {diff_cnt}, 最大RGB差 {max_diff}")

    save_gif(derived, dev_imgs, WS / "吞噬_融合预览_动画派生.gif")
    print("[输出] GIF -> 吞噬_融合预览_动画派生.gif")

    # 静态对比图
    pad = 12
    cell = GRID * SCALE
    cols = [up(derived)]
    labels = ["方案C-动画派生等待"]
    for i in range(min(4, len(dev_imgs))):
        cols.append(up(dev_imgs[i]))
        labels.append(f"吞噬第{i+2}帧")
    if existing_f1 is not None:
        cols.insert(1, up(frame_to_image(existing_f1, dev_pal)))
        labels.insert(1, "现有吞噬第1帧")
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
    png_path = WS / "吞噬_融合对比_方案C.png"
    row.convert("RGB").save(png_path)
    print(f"[输出] 静态对比 -> {png_path}")
    print("[完成] 仅生成预览，未修改任何 Lua 文件。")


if __name__ == "__main__":
    main()
