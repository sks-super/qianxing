# -*- coding: utf-8 -*-
"""
浮岛借木 · 素材路径离线预览（不是游戏的一部分，只用来「看」）

为什么需要它：
  模拟器只代理 100001–100006 六种基础图元，画不出「草地 / 树木 / 人物」这几张真美术，
  所以在模拟器里验证不了「素材有没有严丝合缝压在格子上」。
  这个脚本用**同一套几何规则**（与 level.lua 一一对应）把第01关画出来：

    cellSize / boardCy / cellCenterX / cellCenterY / cellFootY
    草地 = 一张 1.138×1.138 格的立绘（顶面在素材里是正方形，正好铺满一格）
    树木 = 内容 1 格宽 × 1 格高，脚踩在脚线上（控件按 DEFAULT_ART_FIT 放大到 1.819 格）
    人物 = **像素画**（COLS × ROWS 网格，用纯色矩形拼出来，正好 1 格高、脚踩在脚线上）
           数据读 heroArt.lua，与 level.lua 的 repaintPlayerArt() 同源；
           换朝向 = 换一套矩形（这就是游戏里「转身」的全部实现）
    其余 = 纯色矩形 + 调色板（与回退路径一致）
           · 树根 0.25 格高、倒下的树按 dir 分东西躺 / 南北躺（长而扁 1.00 × 0.50 格、
             受光边与背光边成对、两端带年轮的切口，
             顶面按水陆取 DEFAULT_H_LOG_LAND / DEFAULT_H_LOG_FLOAT）、
             石头按 h 取 1 / 2 格、终点旗 1.24 格高
  ⚠️ 只画**关卡数据里有的物件**（真树 + 倒下的木头）。「立着的无叶树干」是运行时状态
     （正面推出来的，见 world.lua），离线预览里没有它 —— 想看它请跑模拟器。

用法：
  python _tools/preview_art_浮岛借木.py [关卡号, 默认 1] [S|W|A|D 朝向, 默认 S] [--all]
    --all = 四方向拼成一张 2×2 对照图（看「转身」最直观）
输出：
  浮岛借木/预览_素材路径_第NN关.png          （朝向 S 时不带后缀）
  浮岛借木/预览_素材路径_第NN关_left.png 等   （其他朝向）
  浮岛借木/预览_四向立绘_第NN关.png          （--all）
"""
import io
import os
import re
import sys

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))   # 千星割绳子游戏/
GAME = os.path.join(ROOT, "浮岛借木")
ART = os.path.join(GAME, "素材")

VIEW_W, VIEW_H = 1280, 720

# 四向「像素画」：数据来自 heroArt.lua（由 _tools/make_hero_pixels.py 从四张立绘生成）。
#   ★ 预览必须读同一份数据 —— 否则它会「说假话」：游戏里早就不贴 PNG 了。
#   ★ 四张共用同一个网格与调色板，换朝向时脚底不动、配色不跳。
FACING_LABEL = {"S": "front", "W": "back", "A": "left", "D": "right"}


# ---------------------------------------------------------------- 读 config.lua
def read_cfg():
    src = io.open(os.path.join(GAME, "config.lua"), encoding="utf-8").read()

    def num(name):
        m = re.search(r"M\.%s\s*=\s*([-\d.]+)" % name, src)
        return float(m.group(1))

    palette_src = re.search(r"M\.DEFAULT_PALETTE\s*=\s*\{(.*?)\n\}", src, re.S).group(1)
    palette = {k: v for k, v in re.findall(r"(\w+)\s*=\s*\"([0-9A-Fa-f]{6})\"", palette_src)}

    fit_src = re.search(r"M\.DEFAULT_ART_FIT\s*=\s*\{(.*?)\n\}", src, re.S).group(1)
    fit = {}
    for kind, body in re.findall(r"(\w+)\s*=\s*\{([^}]*)\}", fit_src):
        fit[kind] = {k: float(v) for k, v in re.findall(r"(\w+)\s*=\s*(-?[\d.]+)", body)}

    # 第 n 关：从 M.LEVELS 里按最外层大括号切出每个关卡块
    levels = src.split("M.LEVELS = {", 1)[1]
    blocks, depth, cur, started = [], 0, [], False
    for ch in levels:
        if ch == "{":
            depth += 1
            if depth == 1:
                started, cur = True, []
                continue
        elif ch == "}":
            if depth == 1:
                blocks.append("".join(cur))
                started = False
            depth -= 1
            if depth < 0:
                break
            if depth == 0:
                continue
        if started:
            cur.append(ch)

    def table_body(block, key):
        """取 `key = { ... }` 的表体：花括号配对扫描，不用惰性正则。
        （惰性正则在 `trees = { },` 这种空表上会一路吞到后面某个 `},` 为止）"""
        m = re.search(r"\b%s\s*=\s*\{" % key, block)
        if not m:
            return ""
        depth, i = 0, m.end() - 1
        start = i + 1
        while i < len(block):
            ch = block[i]
            if ch == "{":
                depth += 1
            elif ch == "}":
                depth -= 1
                if depth == 0:
                    return block[start:i]
            i += 1
        return ""

    def parse_level(block):
        lv = {}
        lv["name"] = re.search(r'name\s*=\s*"([^"]*)"', block).group(1)
        lv["map"] = re.findall(r'"([#.]{2,})"', block)
        for key in ("spawn", "goal"):
            m = re.search(r"%s\s*=\s*\{\s*c\s*=\s*(\d+)\s*,\s*r\s*=\s*(\d+)" % key, block)
            lv[key] = (int(m.group(1)), int(m.group(2)))
        for key in ("trees", "roots", "rocks", "logs"):
            body = table_body(block, key)
            if key == "logs":
                lv[key] = [(int(a), int(b), d) for a, b, d in
                           re.findall(r"c\s*=\s*(\d+)\s*,\s*r\s*=\s*(\d+)\s*,\s*dir\s*=\s*\"(\w)\"", body)]
            else:
                lv[key] = [(int(a), int(b)) for a, b in re.findall(r"c\s*=\s*(\d+)\s*,\s*r\s*=\s*(\d+)", body)]
            if key == "rocks":
                hs = re.findall(r"h\s*=\s*(\d+)", body)
                lv["rockH"] = [int(h) for h in hs]
        return lv

    cfg = {
        "palette": palette,
        "fit": fit,
        "cell_min": num("DEFAULT_CELL_MIN"),
        "cell_max": num("DEFAULT_CELL_MAX"),
        "board_scale": num("DEFAULT_BOARD_SCALE"),
        "board_margin_x": num("DEFAULT_BOARD_MARGIN_X"),
        "hud_bottom_reserve": num("DEFAULT_HUD_BOTTOM_RESERVE"),
        "hud_bar_height": num("DEFAULT_HUD_BAR_HEIGHT"),
        "tile_side_ratio": num("DEFAULT_TILE_SIDE_RATIO"),
        "tile_rim_ratio": num("DEFAULT_TILE_RIM_RATIO"),
        "tile_shadow_alpha": num("DEFAULT_TILE_SHADOW_ALPHA"),
        "tile_foot_ratio": num("DEFAULT_TILE_FOOT_RATIO"),
        "obj_shadow_alpha": num("DEFAULT_OBJ_SHADOW_ALPHA"),
        "water_line_alpha": num("DEFAULT_WATER_LINE_ALPHA"),
        "h_root": num("DEFAULT_H_ROOT"),
        "h_log_land": num("DEFAULT_H_LOG_LAND"),
        "h_log_float": num("DEFAULT_H_LOG_FLOAT"),
        "h_tree": num("DEFAULT_H_TREE"),
        "h_rock1": num("DEFAULT_H_ROCK1"),
        "h_rock2": num("DEFAULT_H_ROCK2"),
        "levels": [parse_level(b) for b in blocks],
    }
    return cfg


# ---------------------------------------------------------------- 几何（与 level.lua 一致）
class Geo(object):
    def __init__(self, cfg, lv):
        self.cfg = cfg
        self.rows = len(lv["map"])
        self.cols = max(len(s) for s in lv["map"])
        rim = cfg["tile_rim_ratio"]
        side = cfg["tile_side_ratio"]
        avail_w = (VIEW_W - cfg["board_margin_x"] * 2) * cfg["board_scale"]
        avail_h = (VIEW_H - cfg["hud_bar_height"] - cfg["hud_bottom_reserve"]) * cfg["board_scale"]
        cell = min(avail_w / (self.cols + 2 * rim), avail_h / (self.rows + 2 * rim + side))
        cell = max(cfg["cell_min"], min(cfg["cell_max"], int(cell)))
        self.cell = cell
        band_cy = ((VIEW_H / 2 - cfg["hud_bar_height"]) + (-VIEW_H / 2 + cfg["hud_bottom_reserve"])) / 2
        self.board_cy = band_cy + side * cell / 2          # UI 坐标（y 向上）
        self.board_cx = 0

    # UI 坐标（y 向上，原点画布中心）
    def cx(self, c):
        return (c - (self.cols + 1) / 2) * self.cell

    def cy(self, r):
        return self.board_cy - (r - (self.rows + 1) / 2) * self.cell

    def bottom(self, r):
        return self.cy(r) - self.cell / 2

    def foot(self, r):
        return self.cy(r) - self.cell * self.cfg["tile_foot_ratio"]

    # 画布坐标（y 向下）
    def px(self, c):
        return VIEW_W / 2 + self.cx(c)

    def py(self, ui_y):
        return VIEW_H / 2 - ui_y

    def land(self, lv, c, r):
        if r < 1 or r > self.rows or c < 1 or c > self.cols:
            return False
        return lv["map"][r - 1][c - 1] == "#"


# ---------------------------------------------------------------- 绘制
def hex2rgb(h):
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def scaled(path, w, h):
    im = Image.open(path).convert("RGBA")
    return im.resize((max(1, int(round(w))), max(1, int(round(h)))), Image.LANCZOS)


def paste_center(canvas, img, x, y):
    canvas.alpha_composite(img, (int(round(x - img.width / 2)), int(round(y - img.height / 2))))


def rect(canvas, d, cx, cy, w, h, hexcol, alpha=255):
    d.rectangle([cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2],
                fill=hex2rgb(hexcol) + (int(alpha),))


def read_hero_art():
    """读 heroArt.lua（_tools/make_hero_pixels.py 生成）→ 网格尺寸 + 调色板 + 各朝向矩形。

    与 level.lua 的 repaintPlayerArt() 同源：网格坐标（左上原点、y 向下）→ 画布像素。
    """
    path = os.path.join(GAME, "heroArt.lua")
    if not os.path.exists(path):
        return None
    s = io.open(path, encoding="utf-8").read()

    def num(name):
        m = re.search(r"M\.%s = (\d+)" % name, s)
        return int(m.group(1)) if m else 0

    colors = re.findall(r'^\s*"([0-9A-Fa-f]{6})",', s, re.M)
    sprites = {}
    for f in ("S", "W", "A", "D"):
        m = re.search(r"    %s = \{(.*?)\n    \}," % f, s, re.S)
        sprites[f] = ([tuple(int(v) for v in g)
                       for g in re.findall(r"\{ (\d+), (\d+), (\d+), (\d+), (\d+) \}", m.group(1))]
                      if m else [])
    return {"cols": num("COLS"), "rows": num("ROWS"), "colors": colors, "sprites": sprites}


def render(cfg, lv, idx, facing="S", save=True):
    p = cfg["palette"]
    g = Geo(cfg, lv)
    cell = g.cell
    rim = cell * cfg["tile_rim_ratio"]
    side = cell * cfg["tile_side_ratio"]

    canvas = Image.new("RGBA", (VIEW_W, VIEW_H), hex2rgb(p["water"]) + (255,))
    d = ImageDraw.Draw(canvas, "RGBA")

    # ① 水面细网格线（铺满可见水面）
    lw = max(1, int(cell * 0.035))
    la = int(cfg["water_line_alpha"])
    left = g.px(1) - cell / 2
    top = g.py(g.cy(1) + cell / 2)
    n = 0
    while left - n * cell > -cell:
        n += 1
    for c in range(-n, g.cols + n + 1):
        x = left + c * cell
        d.rectangle([x - lw / 2, 0, x + lw / 2, VIEW_H], fill=hex2rgb(p["waterLine"]) + (la,))
    for r in range(-n, g.rows + n + 1):
        y = top + r * cell
        d.rectangle([0, y - lw / 2, VIEW_W, y + lw / 2], fill=hex2rgb(p["waterLine"]) + (la,))

    shadow_a = int(cfg["tile_shadow_alpha"])

    # ② 地块装饰趟：投影 → 侧面 → 岛缘描边（整趟画完再画顶面，岛内才不会露描边）
    for r in range(1, g.rows + 1):
        for c in range(1, g.cols + 1):
            if not g.land(lv, c, r):
                continue
            x, yb = g.px(c), g.py(g.bottom(r))
            sh = side * 0.5
            rect(canvas, d, x, yb + rim + side + sh / 2, cell + rim * 2 + 4, sh, p["waterShade"], shadow_a)
            rect(canvas, d, x, yb + rim + side / 2, cell + rim * 2, side, p["soil"])
            rect(canvas, d, x, g.py(g.cy(r)), cell + rim * 2, cell + rim * 2, p["sand"])

    # ③ 草地顶面 / 素材立绘（行号升序 = 由远到近，近处后画压住远处）
    fit = cfg["fit"]["land"]
    tiles = scaled(os.path.join(ART, "草地.png"), cell * fit["w"], cell * fit["h"])
    for r in range(1, g.rows + 1):
        for c in range(1, g.cols + 1):
            if g.land(lv, c, r):
                paste_center(canvas, tiles, g.px(c), g.py(g.cy(r) + fit["dy"] * cell))
    d = ImageDraw.Draw(canvas, "RGBA")

    obj_a = int(cfg["obj_shadow_alpha"])

    def obj_shadow(c, r, wcells):
        rect(canvas, d, g.px(c), g.py(g.foot(r)) + cell * 0.01, cell * wcells, cell * 0.13,
             p["shadowLand"], obj_a)

    # ④ 物体（与 level.lua 同序：树根 → 倒下的树 → 石头 → 树 → 旗 → 小人）
    #    ★ 一切物体都只占一格：树 1 格高、倒下的树 0.5 格厚、树根 0.25 格高。
    for (c, r) in lv["roots"]:
        x, fy = g.px(c), g.py(g.foot(r))
        rect(canvas, d, x, fy - cell * 0.035, cell * 0.74, cell * 0.07, p["rootRing"])
        rect(canvas, d, x, fy - cell * 0.14, cell * 0.60, cell * 0.21, p["rootTop"])

    # 倒下的木头：长而扁（A/D 东西躺 → 长 1.00 格 × 厚 0.50 格；
    # W/S 南北躺 → 宽 0.50 格 × 长 1.00 格）+ 贴地暗边 + 两端带年轮的切口。
    # 顶面高度按脚下水陆取 0.5 / 0.25 格。
    #   ★ 与 level.lua 顶部的 LOG_THICK / LOG_LEN / LOG_UNDER / LOG_CAP 同源，改一处要一起改。
    for (c, r, ldir) in lv["logs"]:
        h = cfg["h_log_land"] if g.land(lv, c, r) else cfg["h_log_float"]
        x, fy = g.px(c), g.py(g.foot(r))
        thick = cell * 0.50
        cy = fy - (h - 0.25) * cell
        along_x = ldir in ("A", "D")
        w = cell * 1.00 if along_x else thick
        hh = thick if along_x else cell * 1.00
        cap = cell * 0.09
        obj_shadow(c, r, 0.80)
        # ① 主体（偏灰的旧木色）
        rect(canvas, d, x, cy, w, hh, p["logSide"])
        # ② 背光暗边：永远贴在受光边的对侧。横躺时落在下沿（= 贴地那一面），
        #    竖躺时落在右沿 —— 画布 y 向下，所以「下沿」是 cy + …
        if along_x:
            rect(canvas, d, x, cy + hh / 2 - hh * 0.13, w * 0.98, hh * 0.24, p["logEnd"], 190)
        else:
            rect(canvas, d, x + w / 2 - w * 0.13, cy, w * 0.24, hh * 0.94, p["logEnd"], 190)
        # ③ 受光边：横躺 → 上沿横带；竖躺 → 左侧竖带
        if along_x:
            rect(canvas, d, x, cy - hh * 0.26, w * 0.98, hh * 0.30, p["logTop"])
        else:
            rect(canvas, d, x - w * 0.22, cy, w * 0.28, hh * 0.94, p["logTop"])
        # ④ 两端切口：外圈深色 + 内芯年轮
        for s in (-1, 1):
            if along_x:
                ex = x + s * (w / 2 - cap / 2)
                rect(canvas, d, ex, cy, cap, hh, p["logEnd"])
                rect(canvas, d, ex, cy, cap * 0.42, hh * 0.44, p["logTop"])
            else:
                ey = cy + s * (hh / 2 - cap / 2)
                rect(canvas, d, x, ey, w, cap, p["logEnd"])
                rect(canvas, d, x, ey, w * 0.42, cap * 0.42, p["logTop"])

    for (c, r) in lv["rocks"]:
        hh = cfg["h_rock1"]
        idx_h = lv.get("rockH")
        if idx_h and len(idx_h) > lv["rocks"].index((c, r)):
            hh = cfg["h_rock2"] if idx_h[lv["rocks"].index((c, r))] >= 2 else cfg["h_rock1"]
        hexcol = p["rock2Top"] if hh >= 2 else p["rock1Top"]
        x, fy = g.px(c), g.py(g.foot(r))
        obj_shadow(c, r, 0.80)
        rect(canvas, d, x, fy - hh * cell / 2, cell * 0.86, hh * cell, p["rockSide"])
        rect(canvas, d, x, fy - hh * cell + cell * 0.11, cell * 0.70, cell * 0.22, hexcol)

    # 树（1 格高）：素材模式 = 一张立绘，脚踩在脚线上
    ft = cfg["fit"]["tree"]
    tree_img = scaled(os.path.join(ART, "树木.png"), cell * ft["w"], cell * ft["h"])
    for (c, r) in lv["trees"]:
        obj_shadow(c, r, 0.72)
        paste_center(canvas, tree_img, g.px(c), g.py(g.foot(r) + ft["dy"] * cell))
    d = ImageDraw.Draw(canvas, "RGBA")

    # 终点旗（1.24 格高：比小人高一点，远处一眼认得出）
    gc, gr = lv["goal"]
    x, fy = g.px(gc), g.py(g.foot(gr))
    rect(canvas, d, x, fy - cell * 0.07, cell * 0.92, cell * 0.14, p["goalFlag"], 90)
    rect(canvas, d, x - cell * 0.20, fy - cell * 0.62, cell * 0.08, cell * 1.24, p["goalPole"])
    rect(canvas, d, x + cell * 0.08, fy - cell * 1.02, cell * 0.50, cell * 0.32, p["goalFlag"])

    # 小人：纯色矩形拼出来的像素画（与 level.lua 的 repaintPlayerArt 同源）
    #   画布 = COLS × ROWS 的网格，正好 1 格高；画布底边压在脚线上。
    hero = read_hero_art()
    sc, sr = lv["spawn"]
    obj_shadow(sc, sr, 0.70)
    if hero and hero["sprites"].get(facing):
        px = cell / float(hero["rows"])                  # 一个像素格的边长
        bx = g.px(sc) - hero["cols"] * px / 2.0          # 画布左边
        by = g.py(g.foot(sr)) - hero["rows"] * px        # 画布顶边（屏幕 y 向下）
        colors = hero["colors"]
        for (x, y, w, h, ci) in hero["sprites"][facing]:
            d.rectangle([bx + x * px, by + y * px,
                         bx + (x + w) * px - 0.02, by + (y + h) * px - 0.02],
                        fill=hex2rgb(colors[ci]))

    # ⑤ HUD 参考条
    d.rectangle([0, 0, VIEW_W, cfg["hud_bar_height"] / 2], fill=hex2rgb(p["hudBar"]) + (130,))

    if save:
        name = "预览_素材路径_第%02d关.png" % idx
        if facing != "S":
            name = "预览_素材路径_第%02d关_%s.png" % (idx, FACING_LABEL[facing])
        out = os.path.join(GAME, name)
        canvas.convert("RGB").save(out)
        print("格子边长 = %d px；输出 %s" % (cell, out))
    return canvas


def render_sheet(cfg, lv, idx):
    """四方向拼成一张 1×4 对照图，每格**裁到角色周围再放大** —— 一屏看清「转身」。"""
    out = os.path.join(GAME, "预览_四向立绘_第%02d关.png" % idx)
    g = Geo(cfg, lv)
    cell = g.cell
    sc, sr = lv["spawn"]
    # 裁 2.4 格 × 2.4 格（小人 + 脚下那块地），放大 5 倍看清边缘
    halfw = cell * 1.2
    x0 = int(round(g.px(sc) - halfw))
    y1 = int(round(g.py(g.foot(sr) + cell * 0.45) + halfw))   # y 向下：脚线往下留一点
    size = int(round(halfw * 2))
    Z = 5
    tiles = []
    for f in ("S", "W", "A", "D"):
        full = render(cfg, lv, idx, f, save=False).convert("RGB")
        tiles.append(full.crop((x0, y1 - size, x0 + size, y1)).resize(
            (size * Z, size * Z), Image.LANCZOS))
    tw, th = tiles[0].size
    sheet = Image.new("RGB", (tw * 4, th + 26), (30, 34, 38))
    d2 = ImageDraw.Draw(sheet)
    for i, f in enumerate(("S", "W", "A", "D")):
        sheet.paste(tiles[i], (i * tw, 26))
        d2.text((i * tw + 8, 7), "%-2s %s" % (f, FACING_LABEL[f]), fill=(255, 255, 255))
        d2.rectangle([i * tw, 26, (i + 1) * tw - 1, th + 25], outline=(70, 76, 84))
    sheet.save(out)
    print("四向拼图输出 %s（%dx%d，每格裁 %d px 放大 %d 倍，格子 %d px）"
          % (out, sheet.width, sheet.height, size, Z, cell))


def main():
    args = sys.argv[1:]
    nums = [a for a in args if a.isdigit()]
    idx = int(nums[0]) if nums else 1
    cfg = read_cfg()
    lv = cfg["levels"][idx - 1]
    print("关卡:", lv["name"])
    if "--all" in args:
        render_sheet(cfg, lv, idx)
        return
    facing = "S"
    for a in args:
        if a in FACING_LABEL:
            facing = a
    render(cfg, lv, idx, facing)


if __name__ == "__main__":
    main()
