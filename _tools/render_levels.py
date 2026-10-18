# -*- coding: utf-8 -*-
"""把 config.lua 的 M.LEVELS 按工程配色规则离线渲染成 PNG，用于视觉核对复刻效果。

用法:
  python _tools/render_levels.py [outDir] [t=8] [--overlay 第04关=t73_0_00.png]

  outDir        输出目录（默认 _simulator/levels_preview）
  t             预览秒数（决定哪些计时平台亮起），默认 8
  --overlay     额外产出「原版帧 + 复刻轮廓」叠加核对图：
                --overlay "第04关=_simulator/orig/full/t73_0_00.png"
                叠加时把工程世界按 world = (px-640)*0.625 逆换算回原版像素空间。

纯 PIL 实现（本机没有 @napi-rs/canvas）。
"""
import os
import re
import sys

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CFG = os.path.join(ROOT, 'TickHop', 'config.lua')

FONT_CANDIDATES = (
    'C:/Windows/Fonts/msyh.ttc',      # 微软雅黑
    'C:/Windows/Fonts/simhei.ttf',    # 黑体
    '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
)


def load_font(size):
    for p in FONT_CANDIDATES:
        if os.path.exists(p):
            try:
                return ImageFont.truetype(p, size)
            except Exception:
                pass
    return ImageFont.load_default()

PAL_KEYS = ('bg', 'platform', 'ghost', 'label', 'labelGhost', 'player', 'goal',
            'hud', 'pickup', 'reverse', 'danger')
SCALE = 0.625          # 原版 px → 工程世界
PX_CX, PX_CY = 640.0, 360.0


def hexc(s):
    return tuple(int(s[i:i + 2], 16) for i in (0, 2, 4))


def parse():
    src = open(CFG, encoding='utf-8').read()
    D = {m.group(1): float(m.group(2))
         for m in re.finditer(r'M\.DEFAULT_([A-Z_]+)\s*=\s*(-?[\d.]+)', src)}
    palette = {}
    for m in re.finditer(r'^\s{4}(\w+)\s*=\s*"([0-9A-Fa-f]{6})"', src, re.M):
        if m.group(1) in PAL_KEYS:
            palette[m.group(1)] = m.group(2)
    body = src[src.index('M.LEVELS = {'):]
    levels = []
    for ch in body.split('name = "')[1:]:
        lv = {'name': ch[:ch.index('"')]}
        m = re.search(r'time\s*=\s*(-?[\d.]+)', ch)
        lv['time'] = float(m.group(1)) if m else D.get('TIME_LIMIT', 10.0)
        m = re.search(r'spawn\s*=\s*\{x\s*=\s*(-?[\d.]+)\s*,\s*y\s*=\s*(-?[\d.]+)', ch)
        lv['spawn'] = (float(m.group(1)), float(m.group(2))) if m else (0, 0)
        m = re.search(r'goal\s*=\s*\{x\s*=\s*(-?[\d.]+)\s*,\s*y\s*=\s*(-?[\d.]+)'
                      r'\s*,\s*width\s*=\s*(-?[\d.]+)\s*,\s*height\s*=\s*(-?[\d.]+)', ch)
        lv['goal'] = tuple(float(m.group(i)) for i in range(1, 5)) if m else None
        lp = dict(palette)
        pb = ch[ch.index('palette'):ch.index('platforms')] if 'palette' in ch else ''
        for m in re.finditer(r'(\w+)\s*=\s*"([0-9A-Fa-f]{6})"', pb):
            if m.group(1) in PAL_KEYS:
                lp[m.group(1)] = m.group(2)
        lv['palette'] = lp
        pblock = ch[ch.index('platforms'):ch.index('pickups')]
        lv['platforms'] = [dict(x=float(a), y=float(b), w=float(c), h=float(d), tick=int(float(e)))
                           for a, b, c, d, e in re.findall(
                               r'\{x\s*=\s*(-?[\d.]+)\s*,\s*y\s*=\s*(-?[\d.]+)\s*,'
                               r'\s*width\s*=\s*(-?[\d.]+)\s*,\s*height\s*=\s*(-?[\d.]+)'
                               r'\s*,\s*tick\s*=\s*(-?[\d.]+)\s*\}', pblock)]
        tb = ch[ch.index('texts'):] if 'texts' in ch else ''
        lv['texts'] = [(float(a), float(b), c) for a, b, c in re.findall(
            r'\{x\s*=\s*(-?[\d.]+)\s*,\s*y\s*=\s*(-?[\d.]+)\s*,\s*text\s*=\s*"([^"]*)"', tb)]
        levels.append(lv)
    return D, levels


def render(lv, t, D, path, pad=40, show_view=True):
    """1 世界单位 = 1 像素；画布自动适配关卡包围盒。"""
    xs, ys = [], []
    for p in lv['platforms']:
        xs += [p['x'] - p['w'] / 2, p['x'] + p['w'] / 2]
        ys += [p['y'] - p['h'] / 2, p['y'] + p['h'] / 2]
    if lv['goal']:
        gx, gy, gw, gh = lv['goal']
        xs += [gx - gw / 2, gx + gw / 2]
        ys += [gy - gh / 2, gy + gh / 2]
    x0, x1 = min(xs) - pad, max(xs) + pad
    y0, y1 = min(ys) - pad, max(ys) + pad
    W, H = int(x1 - x0), int(y1 - y0)
    img = Image.new('RGB', (W, H), hexc(lv['palette']['bg']))
    d = ImageDraw.Draw(img)

    def sx(x):
        return x - x0

    def sy(y):
        return y1 - y          # 世界 y 向上 → 画布 y 向下

    def rect(x, y, w, h, fill, outline=None):
        d.rectangle([sx(x - w / 2), sy(y + h / 2), sx(x + w / 2), sy(y - h / 2)],
                    fill=fill, outline=outline)

    label_size = D.get('PLATFORM_LABEL_SIZE', 0)
    solid_a = D.get('PLATFORM_ALPHA', 255) / 255
    ghost_a = D.get('PLATFORM_GHOST_ALPHA', 40) / 255
    font_label = load_font(max(8, int(label_size * 0.62)))
    font_text = load_font(18)
    for p in lv['platforms']:
        solid = (p['tick'] < 0) or (p['tick'] == t)
        col = hexc(lv['palette']['platform'] if solid else lv['palette']['ghost'])
        a = solid_a if solid else ghost_a
        rect(p['x'], p['y'], p['w'], p['h'], col if a >= 0.99 else mix(col, hexc(lv['palette']['bg']), a))
        if p['tick'] >= 0 and label_size > 0:
            s = str(p['tick'])
            bb = d.textbbox((0, 0), s, font=font_label)
            d.text((sx(p['x']) - (bb[2] - bb[0]) / 2, sy(p['y']) - (bb[3] - bb[1]) / 2 - 2), s,
                   font=font_label,
                   fill=hexc(lv['palette']['label'] if solid else lv['palette']['labelGhost']))
    if lv['goal']:
        gx, gy, gw, gh = lv['goal']
        rect(gx, gy, gw, gh, hexc(lv['palette']['goal']))
    px, py = lv['spawn']
    rect(px, py, D.get('PLAYER_WIDTH', 34), D.get('PLAYER_HEIGHT', 44), hexc(lv['palette']['player']))
    for tx, ty, s in lv['texts']:
        bb = d.textbbox((0, 0), s, font=font_text)
        d.text((sx(tx) - (bb[2] - bb[0]) / 2, sy(ty) - (bb[3] - bb[1]) / 2), s,
               font=font_text, fill=hexc(lv['palette']['hud']))

    # 相机可视框
    if show_view:
        vw, vh = D.get('VIEW_WIDTH', 800), D.get('VIEW_HEIGHT', 600)
        # 复算相机夹取（与 level.computeCameraBounds 一致）
        margin, half = D.get('CAMERA_MARGIN', 30), vh / 2
        top, bot = max(ys), min(ys)
        lo, hi = bot - margin + half, top + margin - half
        locked = lo > hi
        cy = 0 if locked else min(max(py, lo), hi)
        d.rectangle([sx(-vw / 2), sy(cy + half), sx(vw / 2), sy(cy - half)],
                    outline=(255, 90, 90))
    img.save(path)
    return img.size, (W, H), (x0, x1, y0, y1)


def mix(c1, c2, a):
    return tuple(int(c1[i] * a + c2[i] * (1 - a)) for i in range(3))


def overlay(lv, frame_path, out_path):
    """把复刻轮廓按 0.625 逆向换算叠加到原版帧上，用于核对几何。"""
    src = Image.open(frame_path).convert('RGB')
    d = ImageDraw.Draw(src)
    GREEN = (0, 255, 90)

    def box(cx, cy, w, h):
        px = cx / SCALE + PX_CX
        py = PX_CY - cy / SCALE
        return [px - w / 2 / SCALE, py - h / 2 / SCALE, px + w / 2 / SCALE, py + h / 2 / SCALE]

    for p in lv['platforms']:
        d.rectangle(box(p['x'], p['y'], p['w'], p['h']), outline=GREEN)
        if p['tick'] >= 0:
            d.rectangle(box(p['x'], p['y'], p['w'], p['h']), outline=(255, 210, 0))
    if lv['goal']:
        gx, gy, gw, gh = lv['goal']
        d.rectangle(box(gx, gy, gw, gh), outline=(255, 90, 90))
    sx_, sy_ = lv['spawn']
    d.rectangle(box(sx_, sy_, 34, 44), outline=(0, 200, 255))
    src.save(out_path)
    return src.size


def compose(lv, render_png, bounds, Y0, frame_path, out_path):
    """并排对照图：左＝原版帧，右＝原版帧 + 复刻渲染（按 1/0.625 放大后精确贴合）。

    Y0 是这一帧的换算基准：world_y = (Y0 - py) * 0.625（单屏关卡 Y0=360；
    第06关那种相机跟随的关卡，把 Y0 取成「该帧画面 y=0 对应的关卡 y」）。
    """
    k = 1.0 / SCALE                      # 世界 → 原版像素
    r = Image.open(render_png).convert('RGB')
    rs = r.resize((int(round(r.width * k)), int(round(r.height * k))), Image.NEAREST)
    x0, x1, y0, y1 = bounds              # 渲染图覆盖的世界范围
    left_px = x0 / SCALE + PX_CX         # 渲染图左边对应的原版像素 x
    top_py = Y0 - y1 / SCALE             # 渲染图顶边对应的原版像素 y
    canvas = Image.new('RGBA', (1280, 720), (0, 0, 0, 0))
    canvas.paste(rs, (int(round(left_px)), int(round(top_py))))
    base = Image.open(frame_path).convert('RGB')
    over = base.copy()
    over.paste(canvas, (0, 0), canvas)
    both = Image.new('RGB', (2576, 720), (60, 60, 60))
    both.paste(base, (0, 0))
    both.paste(over, (1296, 0))
    both.save(out_path)
    return both.size


def main():
    args = sys.argv[1:]
    pos = [a for a in args if not a.startswith('--')]
    outdir = pos[0] if pos else os.path.join(ROOT, '_simulator', 'levels_preview')
    t = float(pos[1]) if len(pos) > 1 else 8.0
    os.makedirs(outdir, exist_ok=True)
    D, levels = parse()
    print(f'# 解析到 {len(levels)} 关  t={t}')
    rendered = {}
    for lv in levels:
        p = os.path.join(outdir, f'{lv["name"]}.png')
        size, content, bounds = render(lv, t, D, p)
        rendered[lv['name']] = (p, bounds)
        print(f'  {lv["name"]:8s} 图 {size[0]}x{size[1]}  内容 {content[0]}x{content[1]}  → {p}')
    if '--overlay' in args:
        for spec in args[args.index('--overlay') + 1:]:
            if spec.startswith('--'):
                break
            if '=' not in spec:
                continue
            name, frame = spec.split('=', 1)
            Y0 = 360.0
            if '@' in frame:
                frame, y0s = frame.rsplit('@', 1)
                Y0 = float(y0s)
            lv = next((x for x in levels if x['name'] == name), None)
            if not lv or name not in rendered:
                print('  [跳过]', name, '无此关卡')
                continue
            fp = frame if os.path.isabs(frame) else os.path.join(ROOT, frame)
            png, bounds = rendered[name]
            op = os.path.join(outdir, f'{name}_对照.png')
            print('  对照图', compose(lv, png, bounds, Y0, fp, op), '→', op)
            op2 = os.path.join(outdir, f'{name}_叠加核对.png')
            print('  叠加核对', overlay(lv, fp, op2), '→', op2)


if __name__ == '__main__':
    main()
