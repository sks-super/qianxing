#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把 make_hero_pixels.py 产出的像素数据转成一个**独立**的模拟器实验脚本。

用途：不改游戏代码，只在模拟器里用基础图形模板（矩形 1073741894 / 文本 1073741868）
把四张立绘「拼」出来，看纯控件能还原到什么程度。

用法：
    python _tmp/proto/gen_proto.py _tmp/proto/hi.lua _tmp/proto/proto.lua --px 4.5
"""
import argparse
import re
import sys

ap = argparse.ArgumentParser()
ap.add_argument("src")
ap.add_argument("dst")
ap.add_argument("--px", type=float, default=4.5, help="一个网格像素占几屏幕像素")
ap.add_argument("--gap", type=float, default=34.0, help="四向之间的水平间距")
ap.add_argument("--bottom", type=float, default=64.0, help="脚底线距离屏幕底部的像素")
ap.add_argument("--grow", type=float, default=0.5, help="每块向外扩多少像素（盖住相邻块之间的缝）")
args = ap.parse_args()

src = open(args.src, encoding="utf-8").read()
cols = int(re.search(r"M\.COLS = (\d+)", src).group(1))
rows = int(re.search(r"M\.ROWS = (\d+)", src).group(1))
colors = re.findall(r'^\s*"([0-9A-Fa-f]{6})",\s*--\s*\d+', src, re.M)

body = src.split("M.SPRITES = {", 1)[1]
order = ["S", "W", "A", "D"]
label = {"S": "S 向下·正面", "W": "W 向上·背面", "A": "A 向左·左视", "D": "D 向右·右视"}
sprites = {}
for f in order:
    seg = body.split("\n    %s = {" % f, 1)[1].split("\n    },", 1)[0]
    sprites[f] = re.findall(r"\{ (-?\d+), (-?\d+), (\d+), (\d+), (\d+) \}", seg)

W, H = 1280, 720
px = args.px
hero_w = cols * px
hero_h = rows * px
total_w = len(order) * hero_w + (len(order) - 1) * args.gap
x0 = -total_w / 2 + hero_w / 2                      # 第一向的中心 x
base_y = -H / 2 + args.bottom                       # 脚底线（UI y 向上）

L = []
A = L.append
A("-- 独立实验脚本（_tmp/proto/gen_proto.py 生成，别手改）")
A("-- 只用基础图形模板把四张立绘拼出来：矩形 %d 个 / 文本 %d 个，不碰任何游戏代码。"
  % (sum(len(v) for v in sprites.values()), len(order)))
A("")
A("local COLORS = {")
for i, c in enumerate(colors):
    A('    "%s",   -- %d' % (c.upper(), i))
A("}")
A("")
A("local COLS, ROWS = %d, %d" % (cols, rows))
A("local PX = %s" % args.px)
A("local GROW = %s" % args.grow)
A("local GAP = %s" % args.gap)
A("local BASE_X0 = %s" % round(x0, 3))
A("local BASE_Y = %s" % round(base_y, 3))
A("local ORDER = { \"S\", \"W\", \"A\", \"D\" }")
A("local LABELS = { S = \"S 向下·正面\", W = \"W 向上·背面\", A = \"A 向左·左视\", D = \"D 向右·右视\" }")
A("")
A("local SPRITES = {")
for f in order:
    A("    %s = {   -- %d 块" % (f, len(sprites[f])))
    for r in sprites[f]:
        A("        { %s, %s, %s, %s, %s }," % r)
    A("    },")
A("}")
A("")
A("-- 矩形 / 文本元件（官方内置模板）")
A("local PREFAB_RECT = 1073741894")
A("local PREFAB_BOX = 1073741876")
A("local PREFAB_TEXT = 1073741868")
A("")
A("local function hexToColor(h)")
A("    local r = tonumber(h:sub(1, 2), 16)")
A("    local g = tonumber(h:sub(3, 4), 16)")
A("    local b = tonumber(h:sub(5, 6), 16)")
A("    return Color.FromRGB(r or 255, g or 255, b or 255)")
A("end")
A("")
A("local COLOR_CACHE = {}")
A("local function colorOf(i)")
A("    local c = COLOR_CACHE[i]")
A("    if not c then")
A("        c = hexToColor(COLORS[i + 1] or \"FFFFFF\")")
A("        COLOR_CACHE[i] = c")
A("    end")
A("    return c")
A("end")
A("")
A("-- 模拟器的 --fix-zorder 靠 state.container* 认「游戏自己的控件」")
A("-- （没有这张表，它会把模拟器自带的「文本」标签 / 星星 / 蓝条一起留在画面上）")
A("state = {}")
A("")
A("local host")
A("local made = 0")
A("local failed = 0")
A("")
A("local function mkRect(px, py, w, h, ci)")
A("    local ok, c = pcall(game.InstantiateClientUIControl, PREFAB_RECT, host)")
A("    if not ok or not c then failed = failed + 1; return nil end")
A("    c:SetAnchorMin(0.5, 0.5)")
A("    c:SetAnchorMax(0.5, 0.5)")
A("    c:SetPivot(0.5, 0.5)")
A("    c:SetSizeDelta(w, h)")
A("    pcall(function() c.imageColor = colorOf(ci) end)")
A("    c:SetAnchoredPosition(px, py)")
A("    c:SetActive(true)")
A("    made = made + 1")
A("    return c")
A("end")
A("")
A("local function mkText(px, py, w, h, txt, size)")
A("    local ok, c = pcall(game.InstantiateClientUIControl, PREFAB_TEXT, host)")
A("    if not ok or not c then return nil end")
A("    c:SetAnchorMin(0.5, 0.5)")
A("    c:SetAnchorMax(0.5, 0.5)")
A("    c:SetPivot(0.5, 0.5)")
A("    c:SetSizeDelta(w, h)")
A("    c:SetAnchoredPosition(px, py)")
A("    pcall(function() c.text = txt end)")
A("    pcall(function() c.fontSize = size end)")
A("    pcall(function() c.fontColor = Color.FromRGB(240, 244, 250) end)")
A("    c:SetActive(true)")
A("    return c")
A("end")
A("")
A("local built = false")
A("")
A("local function build()")
A("    if built then return end")
A("    built = true")
A("    local root = script.object")
A("    if not root then return end")
A("    -- ★ 所有矩形装进一个「容器节点」再挂 root：模拟器的 --fix-zorder 只认")
A("    --   state 里登记过的容器，裸挂在 root 下的控件会被当成脚手架全部隐藏。")
A("    local okBox, box = pcall(game.InstantiateClientUIControl, PREFAB_BOX, root)")
A("    if not okBox or not box then box = root end")
A("    if box ~= root then")
A("        box:SetAnchorMin(0.5, 0.5)")
A("        box:SetAnchorMax(0.5, 0.5)")
A("        box:SetPivot(0.5, 0.5)")
A("        box:SetSizeDelta(1, 1)")
A("        box:SetAnchoredPosition(0, 0)")
A("        box:SetActive(true)")
A("    end")
A("    host = box")
A("    state.containerWorld = box")
A("    state.selfOrderedContainers = { containerWorld = true }")
A("    if not host then")
A("        if type(printerr) == \"function\" then printerr(\"[PROTO] script.object 为 nil\") end")
A("        return")
A("    end")
A("    local heroW, heroH = COLS * PX, ROWS * PX")
A("    for i, f in ipairs(ORDER) do")
A("        local cx = BASE_X0 + (i - 1) * (heroW + GAP)")
A("        local sp = SPRITES[f]")
A("        for k = 1, #sp do")
A("            local b = sp[k]")
A("            local bx, by, bw, bh, ci = b[1], b[2], b[3], b[4], b[5]")
A("            -- 网格（左上原点 / y 向下）→ UI（中心原点 / y 向上）")
A("            local sx = cx + (bx + bw * 0.5) * PX - heroW * 0.5")
A("            local sy = BASE_Y + (ROWS - by - bh * 0.5) * PX")
A("            mkRect(sx, sy, bw * PX + GROW, bh * PX + GROW, ci)")
A("        end")
A("        mkText(cx, BASE_Y - 26, heroW + 40, 26, LABELS[f] or f, 18)")
A("    end")
A("    mkText(0, BASE_Y + ROWS * PX + 46, 1000, 30,")
A("        \"拼图实验：只用基础图形模板，未改任何游戏代码\", 20)")
A("    if type(print) == \"function\" then")
A("        pcall(print, string.format(\"[PROTO] 矩形=%d 失败=%d 网格=%dx%d 每块=%.2fpx\",")
A("            made, failed, COLS, ROWS, PX))")
A("    end")
A("end")
A("")
A("function OnStart()")
A("    script:EnableUpdate(true)")
A("    build()")
A("end")
A("")
A("function OnUpdate(dt)")
A("    if not built then build() end")
A("end")
A("")

open(args.dst, "w", encoding="utf-8", newline="\n").write("\n".join(L))
print("-> %s（%d 行）矩形合计 %d 块，尺寸 %.0f×%.0f"
      % (args.dst, len(L), sum(len(v) for v in sprites.values()), hero_w, hero_h))
