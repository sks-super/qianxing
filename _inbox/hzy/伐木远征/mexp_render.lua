-- ================================================================
-- 伐木远征 · 渲染层
--   把原版 canvas 的 2.5D 画法搬到「纯色块 + 内置图元」上：
--     · 地块顶面按高度取色（低/中/高三段色带），整行同色同崖高**合并成一条**长条，
--       控件数量因此从「每格一个」降到「每段一个」——这是能在千星里跑起来的关键。
--     · 南侧崖面按高差向下拉一条竖条；北边的崖面因为绘制在后，正好压住南邻的顶面，
--       立体感全靠这个绘制顺序（和原版一模一样）。
--     · 水不逐格画：整屏一张底色打底，水面本身就是背景，省掉上千个控件。
--     · 实体用「一个容器 + 最多 8 个子图元」表示，每帧只移动容器，
--       所以平滑跟随不会退化成每帧改几十个控件。
--
--   ★ 坐标约定：子控件用「世界坐标」——x 向右增大；y 向上增大，所以格坐标要取负。
--     容器自身的位置 = (-cam.x, +cam.y)，平移容器就等于移动镜头（O(1)）。
-- ================================================================

---@diagnostic disable: undefined-global

local M = {}
local state = require("state")
local config = require("config")
local utils = require("utils")
local eng = require("mexp_engine")

local hasBit = eng.hasBit

-- ---------------- 本模块持有的私有数据 ----------------
local pool = {}            -- 地块 / 崖面 / 装饰 的控件池
local used = 0             -- 本帧用到几个
local boxes = {}           -- 实体容器池
local boxN = 0             -- 用到几个
local entDisp = {}         -- key -> {x,y,z} 平滑显示位置
local hmin, hmax = 0, 1
local bg = nil             -- 整屏水色

-- ================================================================
-- ★ 尺寸
-- ================================================================
function M.tilePx()
    return (state.tilePx or config.DEFAULT_TILE) * (state.viewZoom or 1)
end

function M.heightPx()
    return (state.heightPx or config.DEFAULT_HEIGHT_PX) * (state.viewZoom or 1)
end

-- ================================================================
-- ★ 控件池
-- ================================================================
local function take(w, h, colorHex, imageId, alpha)
    used = used + 1
    local c = pool[used]
    if not c then
        c = utils.createControl(0, 0, w, h, nil, state.containerWorld, imageId)
        pool[used] = c
        if not c then return nil end
    end
    utils.setSize(c, w, h)
    if colorHex then
        utils.setColor(c, utils.hexToColorA(colorHex, alpha or 255))
    end
    utils.setVisible(c, true)
    -- ★ 池子复用会打乱兄弟顺序：每次取用都压到最上层，
    --   于是「后取的在上」= 「后画的在上」，和原版 canvas 的绘制顺序一致。
    utils.toLast(c)
    return c
end

local function beginFrame()
    used = 0
    boxN = 0
end

local function endFrame()
    for i = used + 1, #pool do
        if pool[i] then utils.setVisible(pool[i], false) end
    end
end

-- ================================================================
-- ★ 初始化：底色 + 世界容器
-- ================================================================
function M.init()
    bg = utils.createControl(0, 0, (state.canvasW or 1280) + 8, (state.canvasH or 720) + 8,
        utils.hexToColor(utils.shade(config.THEMES[config.DEFAULT_THEME].water, -0.35)),
        state.containerBg)
    -- 屏幕最外圈再压一圈更暗的水，避免镜头到边界时露出背景色
    if bg then
        pcall(function() bg:SetAnchorMin(0.5, 0.5); bg:SetAnchorMax(0.5, 0.5) end)
    end
end

-- ================================================================
-- ★ 换地图：重算高度区间与每格颜色
-- ================================================================
function M.setWorld(world, themeKey)
    state.world = world
    state.themeKey = themeKey or config.DEFAULT_THEME
    state.theme = config.THEMES[state.themeKey] or config.THEMES[config.DEFAULT_THEME]
    local th = state.theme

    if bg then
        -- ★ 屏内水面在原版是 mix(water, waterVar, hash) 的一族亮色，
        --   shade(water,-0.35) 只用于地图外的深水。整屏底色取中间值最接近。
        utils.setColor(bg, utils.hexToColor(th.water))
    end

    -- 树桩格在高度图里自带 +1，它站的那块地其实低一格
    local w = world
    local gH = function(x, y)
        local p = w:props(x, y)
        local h = w:ghat(x, y)
        if hasBit(p, 4) and not hasBit(p, 2) then return h - 1 end
        return h
    end

    local lo, hi = nil, nil
    for y = 0, w.H - 1 do
        for x = 0, w.W - 1 do
            if not hasBit(w:props(x, y), 2) then
                local h = gH(x, y)
                if not lo or h < lo then lo = h end
                if not hi or h > hi then hi = h end
            end
        end
    end
    if not lo then lo, hi = 0, 1 end
    hmin = lo
    hmax = (hi == lo) and (lo + 1) or hi

    M._gH = gH
    -- 每格顶面颜色缓存（无随机抖动，才敢按相等合并）
    local col = {}
    for y = 0, w.H - 1 do
        for x = 0, w.W - 1 do
            local p = w:props(x, y)
            if hasBit(p, 2) then
                col[y * w.W + x] = nil
            else
                local t = (gH(x, y) - hmin) / (hmax - hmin)
                local base = utils.ramp({ th.low, th.mid, th.high }, t)
                -- ★ 原版没有「整格往沙色偏」这一手（沙岸只靠贴水那条窄边），
                --   这里也只在石头格上往 wall 偏，别把整片岛都洗白。
                if hasBit(p, 8) then base = utils.mix(base, th.wall, 0.78) end
                col[y * w.W + x] = base
            end
        end
    end
    M._col = col

    state.winKey = nil
    entDisp = {}
    -- 清空实体容器
    for i = 1, #boxes do
        utils.setVisible(boxes[i].ctrl, false)
        boxes[i].sig = nil
        boxes[i].key = nil
    end
end

-- ================================================================
-- ★ 镜头：把玩家放在屏幕正中，并夹在地图里；地图比屏幕小就居中
--   ★ 返回的是「屏幕正中对应的世界坐标」（camX, camY）：
--     屏幕上某点的偏移 = (ux - camX, camY - uy)，uy 是 y 向上的世界坐标。
--     所以 camX 是视口中心的 x，camY 是视口中心的 y（行号越大越负）。
--     别返回左上角 —— 实体剔除和容器平移都按「中心」写。
-- ================================================================
function M.focus(w, px, py)
    local T = M.tilePx()
    local vw = state.canvasW or 1280
    local vh = state.canvasH or 720
    local wpx = w.W * T
    local hpx = w.H * T

    local function axis(p, span, total)
        if total <= span then return total / 2 end
        return utils.clamp(p, span / 2, total - span / 2)
    end

    -- ★ 传进来的 py 是「行空间」（向下为正，= 行号×T 那一套）；
    --   世界坐标是 y 向上（行号越大越负）→ 先在行空间夹紧，再翻回世界坐标。
    local R = axis(py, vh, hpx)
    return axis(px, vw, wpx), -R
end

-- 把容器摆到镜头上（子控件用世界坐标，容器平移即镜头）
-- ★ 世界坐标是 y 向上（行号越大越负），屏幕 y 也向上 →
--   屏幕偏移 = 子坐标 - 镜头中心，所以容器位置是 (-camX, -camY)。
--   camY 是「屏幕正中那一点的世界 y」（负数），减它 = 往上抬，写反就整屏空白。
local function applyCamera()
    if state.containerWorld then
        utils.setPosition(state.containerWorld, -(state.camX or 0), -(state.camY or 0))
    end
end

-- ================================================================
-- ★ 地形：只铺「可视窗口」那一片，窗口按整格对齐
--   ★ 为什么按整格对齐：镜头是平滑的，但地形网格对齐到格，
--     所以只有跨格时才需要重铺；格内的位移由容器平移承担。
-- ================================================================
local function buildTerrain()
    local w = state.world
    if not w then return end
    local T = M.tilePx()
    local HZ = M.heightPx()
    local th = state.theme
    local col = M._col
    local gH = M._gH
    local vw = state.canvasW or 1280
    local vh = state.canvasH or 720
    local margin = config.DEFAULT_WIN_MARGIN

    -- ★ 可视窗口以「视口中心」为基准（camX 是中心，不是左上角）
    local cx = state.camX or 0
    local cyR = -(state.camY or 0)          -- 行空间（向下为正）的视口中心
    local x0 = math.max(0, math.floor((cx - vw / 2) / T) - margin)
    local x1 = math.min(w.W - 1, math.ceil((cx + vw / 2) / T) + margin)
    local y0 = math.max(0, math.floor((cyR - vh / 2) / T) - config.DEFAULT_WIN_TOP_PAD)
    local y1 = math.min(w.H - 1, math.ceil((cyR + vh / 2) / T) + margin)

    state.winX0, state.winY0 = x0, y0

    -- 从南往北画：北边那格的崖面要压住南邻的顶面
    for y = y1, y0, -1 do
        local x = x0
        while x <= x1 do
            local p = w:props(x, y)
            if hasBit(p, 2) then
                x = x + 1     -- 水不画，整屏底色就是水
            else
                local h = gH(x, y)
                -- 与南邻的高差（南邻是水也照算，水面的 ghat 就是水面高度）
                local sp = w:props(x, y + 1)
                local sh = (y + 1 < w.H) and gH(x, y + 1) or h
                local dh = h - sh
                local key = (col[y * w.W + x] or "") .. "|" .. tostring(dh) .. "|" .. tostring(h)

                -- 向右合并「顶面颜色 + 高差 + 高度」都相同的一整段
                local rx = x
                while rx + 1 <= x1 do
                    local np = w:props(rx + 1, y)
                    if hasBit(np, 2) then break end
                    local nh = gH(rx + 1, y)
                    local nsp = w:props(rx + 1, y + 1)
                    local nsh = (y + 1 < w.H) and gH(rx + 1, y + 1) or nh
                    local nkey = (col[y * w.W + rx + 1] or "") .. "|" .. tostring(nh - nsh) .. "|" .. tostring(nh)
                    if nkey ~= key then break end
                    rx = rx + 1
                end

                local span = rx - x + 1
                local runW = span * T
                local rc = x * T + runW / 2       -- 整段的中点 x（别用 cx，那是镜头）
                local topEdge = h * HZ - y * T          -- 这一格顶面的上沿（世界坐标，y 向上）
                local cy = topEdge - T / 2

                -- 崖面（南侧立面）：原版是竖向三段渐变，这里用三条色带近似
                if dh > 0 then
                    local wh = math.min(dh * HZ, T * config.DEFAULT_CLIFF_MAX)
                    local yTop = topEdge - T
                    local h1 = math.max(2, wh * 0.30)
                    local h2 = math.max(2, wh * 0.52)
                    local h3 = math.max(2, wh - h1 - h2)
                    local c1 = take(runW + 1, h1, th.wallTop, nil, 255)
                    if c1 then utils.setPosition(c1, rc, yTop - h1 / 2) end
                    local c2 = take(runW + 1, h2, th.wall, nil, 255)
                    if c2 then utils.setPosition(c2, rc, yTop - h1 - h2 / 2) end
                    local c3 = take(runW + 1, h3, utils.shade(th.wall, -0.3), nil, 255)
                    if c3 then utils.setPosition(c3, rc, yTop - h1 - h2 - h3 / 2) end
                end

                -- ★ 砖缝：整段先铺一层 edge 色，再逐格压内缩 2.8px 的顶面 →
                --   格子之间自然露出 2.8px 的缝，就是原版那种「一格一块地砖」的观感。
                --   合并只用来省控制数（颜色相同的段落一次铺底），顶面仍要逐格。
                local grout = take(runW + 1, T + 1, th.edge, nil, 255)
                if grout then utils.setPosition(grout, rc, cy) end
                for dx = x, rx do
                    local jc = utils.shade(col[y * w.W + dx] or th.mid,
                        (utils.hash2(dx, y) - 0.5) * 0.07)
                    local tile = take(T - 2.8, T - 2.8, jc, nil, 255)
                    local tcx = dx * T + T / 2
                    if tile then utils.setPosition(tile, tcx, cy) end
                    -- ★ 沙岸：靠水的每条边压一条 beach 色窄条（原版同款）
                    local bw = math.max(3, T * 0.075)
                    local ins = 1.4
                    if hasBit(w:props(dx, y - 1), 2) then
                        local e = take(T - 6, bw, th.beach, nil, 255)
                        if e then utils.setPosition(e, tcx, cy + T / 2 - ins - bw / 2) end
                    end
                    if hasBit(w:props(dx, y + 1), 2) then
                        local e = take(T - 6, bw, th.beach, nil, 255)
                        if e then utils.setPosition(e, tcx, cy - T / 2 + ins + bw / 2) end
                    end
                    if hasBit(w:props(dx - 1, y), 2) then
                        local e = take(bw, T - 6, th.beach, nil, 255)
                        if e then utils.setPosition(e, tcx - T / 2 + ins + bw / 2, cy) end
                    end
                    if hasBit(w:props(dx + 1, y), 2) then
                        local e = take(bw, T - 6, th.beach, nil, 255)
                        if e then utils.setPosition(e, tcx + T / 2 - ins - bw / 2, cy) end
                    end
                end

                -- 逐格装饰（稀疏，不合并）
                for dx = x, rx do
                    local dp = w:props(dx, y)
                    local dcx = dx * T + T / 2
                    local dTop = gH(dx, y) * HZ - y * T
                    if hasBit(dp, 8) then
                        -- 石头：一块厚石墩
                        local rh = math.min(math.max(dh, 0.4), 4) * HZ
                        local rb = take(T * 0.6, math.max(2, rh * 2), config.OBJ.stone, nil, 255)
                        if rb then utils.setPosition(rb, dcx, dTop - T * 0.5 - rh) end
                        local rt = take(T * 0.62, T * 0.2, utils.shade(config.OBJ.stone, 0.35), nil, 255)
                        if rt then utils.setPosition(rt, dcx, dTop - T * 0.5 - rh * 2 + 1) end
                    elseif hasBit(dp, 4) then
                        -- 树桩：一小截木桩
                        local body = take(T * 0.3, T * 0.34, config.OBJ.woodDark, nil, 255)
                        if body then utils.setPosition(body, dcx, dTop - T * 0.62) end
                        local cap = take(T * 0.32, T * 0.11, config.OBJ.woodLight, nil, 255)
                        if cap then utils.setPosition(cap, dcx, dTop - T * 0.45) end
                    end
                end

                x = rx + 1
            end
        end
    end
end

-- ================================================================
-- ★ 实体：一个容器 + 最多 8 个子图元
-- ================================================================
local SLOT_MAX = 8

local function getBox(i)
    local b = boxes[i]
    if b then return b end
    local ctrl = utils.createControl(0, 0, 1, 1, nil, state.containerWorld, nil)
    if not ctrl then return nil end
    -- ★ 容器必须 1×1：子控件的坐标是相对容器轴心的
    pcall(function()
        ctrl:SetAnchorMin(0.5, 0.5)
        ctrl:SetAnchorMax(0.5, 0.5)
        ctrl:SetPivot(0.5, 0.5)
        ctrl:SetSizeDelta(1, 1)
    end)
    b = { ctrl = ctrl, slots = {}, sig = nil }
    boxes[i] = b
    return b
end

-- 配置一个子图元：dx/dy 相对脚点，w/h 尺寸，imageId 传圆就画椭圆
local function slot(b, k, dx, dy, w, h, colorHex, imageId, alpha)
    local c = b.slots[k]
    if not c then
        c = utils.createControl(0, 0, w, h, nil, b.ctrl, imageId)
        if not c then return end
        b.slots[k] = c
    end
    utils.setSize(c, w, h)
    utils.setPosition(c, dx, dy)
    -- ★ 必须每次都写图元：同一个槽上一帧是圆的，这一帧当矩形用时不能还是圆的
    utils.applyImage(c, imageId or config.PRIM.rect)
    -- ★ 颜色缺省时退回阴影色：真机不写 imageColor 就是纯白，会顶出一块白斑
    --   （config.OBJ.shadow 漏定义时踩过，见 2026-10-23 记录）
    utils.setColor(c, utils.hexToColorA(colorHex or config.PALETTE.shadow, alpha or 255))
    -- ★ 每写一个图元就压到最上层：槽位是 1..8 按「影子→身体→眼睛」的顺序画的，
    --   压上层 = 后画的盖住先画的。两条路径都成立：
    --     真机 SetAsLastSibling = 最后一个 = 最上层；
    --     模拟器 = 数组下标 0 = 最后绘制 = 最上层（见 _sim_common 的说明）。
    --   不压的话模拟器会把同级倒着画 → 影子糊在身体上面。
    utils.toLast(c)
    utils.setVisible(c, true)
end

local function hideSlots(b, from)
    for k = from, SLOT_MAX do
        if b.slots[k] then utils.setVisible(b.slots[k], false) end
    end
end

local function disc(w, h)
    return config.PRIM.circle      -- 内置圆图元 100002
end

-- 画某个实体（相对脚点 (0,0)，y 向上）
local function paintEntity(b, e)
    local T = M.tilePx()
    local O = config.OBJ
    local k = 0

    if e.type == 0 then
        -- 玩家：影子 / 身体 / 两只耳朵 / 两只眼睛 / 两只脚
        local r = T * 0.29
        k = k + 1; slot(b, k, 0, 1, r * 1.9, r * 0.72, O.shadow, disc(), 56)
        -- ★ dy 一律「从脚点往上量」：原版是 canvas 的「从脚点往下减」，
        --   换算 = 1.05r（身体圆心）+ 原版偏移。耳朵/眼睛漏加 1.05r 就会跑到脚面上。
        k = k + 1; slot(b, k, 0, r * 1.05, r * 2, r * 2.04, O.body, disc(), 255)
        k = k + 1; slot(b, k, -r * 0.62, r * 1.91, r * 0.6, r * 0.68, O.body, disc(), 255)
        k = k + 1; slot(b, k, r * 0.62, r * 1.91, r * 0.6, r * 0.68, O.body, disc(), 255)
        local lx = (state.lookX or 0) * r * 0.16
        local ly = (state.lookY or 0) * r * 0.14
        k = k + 1; slot(b, k, -r * 0.36 + lx, r * 1.17 + ly, r * 0.28, r * 0.34, O.eye, disc(), 255)
        k = k + 1; slot(b, k, r * 0.36 + lx, r * 1.17 + ly, r * 0.28, r * 0.34, O.eye, disc(), 255)
        k = k + 1; slot(b, k, -r * 0.37, r * 0.32, r * 0.5, r * 0.3, O.bodyDark, nil, 255)
        k = k + 1; slot(b, k, r * 0.37, r * 0.32, r * 0.5, r * 0.3, O.bodyDark, nil, 255)

    elseif e.type == 1 then
        -- 立着的木头：一根圆木戳在地上（两格高）
        local bw, bh = T * 0.34, T * 0.52
        k = k + 1; slot(b, k, 0, 1, bw * 1.15 * 2, bw * 0.5 * 2, O.shadow, disc(), 51)
        k = k + 1; slot(b, k, 0, bh / 2, bw, bh, O.wood, nil, 255)
        k = k + 1; slot(b, k, 0, bh, bw * 1.06, bw * 0.28, O.woodLight, disc(), 255)

    elseif e.type == 2 then
        -- 立树：树干 + 树冠
        local bw, bh = T * 0.26, T * 0.42
        k = k + 1; slot(b, k, 0, 1, T * 0.68, T * 0.32, O.shadow, disc(), 56)
        k = k + 1; slot(b, k, 0, bh / 2, bw, bh, O.woodDark, nil, 255)
        k = k + 1; slot(b, k, 0, bh + T * 0.12, T * 0.84, T * 0.72, O.leafDark, disc(), 255)
        k = k + 1; slot(b, k, -T * 0.06, bh + T * 0.17, T * 0.66, T * 0.56, O.leaf, disc(), 255)

    elseif e.type == 3 or e.type == 4 then
        -- 横木 / 竖木：一根躺在地上的圆木
        local L, W = T * 0.84, T * 0.46
        local hx = (e.type == 3) and L or W
        local hy = (e.type == 3) and W or L
        local cy = hy * 0.42
        k = k + 1; slot(b, k, 0, 1, hx * 1.04, hy * 0.6, O.shadow, disc(), 51)
        k = k + 1; slot(b, k, 0, cy, hx, hy, O.wood, nil, 255)
        if e.type == 3 then
            k = k + 1; slot(b, k, -hx / 2 + hy * 0.18, cy, hy * 0.32, hy * 0.8, O.woodLight, disc(), 255)
            k = k + 1; slot(b, k, hx / 2 - hy * 0.18, cy, hy * 0.32, hy * 0.8, O.woodLight, disc(), 255)
        else
            k = k + 1; slot(b, k, 0, cy - hy / 2 + hx * 0.18, hx * 0.8, hx * 0.32, O.woodLight, disc(), 255)
            k = k + 1; slot(b, k, 0, cy + hy / 2 - hx * 0.18, hx * 0.8, hx * 0.32, O.woodLight, disc(), 255)
        end

    elseif e.type == 5 or e.type == 6 then
        -- 木筏：一捆木板 + 两道绳子
        local L, W = T * 0.9, T * 0.62
        local hx = (e.type == 5) and L or W
        local hy = (e.type == 5) and W or L
        local cy = hy * 0.3
        k = k + 1; slot(b, k, 0, 1, hx * 1.1, hy * 0.52, O.shadow, disc(), 46)
        k = k + 1; slot(b, k, 0, cy, hx, hy, O.woodLight, nil, 255)
        k = k + 1; slot(b, k, 0, cy + hy * 0.26, hx, math.max(2, hy * 0.09), O.woodDark, nil, 255)
        k = k + 1; slot(b, k, 0, cy - hy * 0.26, hx, math.max(2, hy * 0.09), O.woodDark, nil, 255)
        if e.type == 5 then
            k = k + 1; slot(b, k, -hx * 0.28, cy, math.max(2, hy * 0.1), hy, O.rope, nil, 255)
            k = k + 1; slot(b, k, hx * 0.28, cy, math.max(2, hy * 0.1), hy, O.rope, nil, 255)
        else
            k = k + 1; slot(b, k, 0, cy - hy * 0.28, hx, math.max(2, hx * 0.1), O.rope, nil, 255)
            k = k + 1; slot(b, k, 0, cy + hy * 0.28, hx, math.max(2, hx * 0.1), O.rope, nil, 255)
        end

    elseif e.type == 7 then
        -- 雪人
        local r = T * 0.3
        k = k + 1; slot(b, k, 0, 1, r * 2.1, r * 0.8, O.shadow, disc(), 56)
        k = k + 1; slot(b, k, 0, r * 1.0, r * 2, r * 1.9, O.snow, disc(), 255)
        k = k + 1; slot(b, k, 0, r * 2.0, r * 1.36, r * 1.28, O.snow, disc(), 255)
        k = k + 1; slot(b, k, r * 0.36, r * 1.9, r * 0.34, r * 0.16, "E07A3A", nil, 255)
        k = k + 1; slot(b, k, -r * 0.22, r * 2.06, r * 0.16, r * 0.18, O.eye, disc(), 255)
        k = k + 1; slot(b, k, r * 0.22, r * 2.06, r * 0.16, r * 0.18, O.eye, disc(), 255)

    elseif e.type == 8 then
        -- 木牌：一根柱子 + 一块牌子；终点牌（"You win!" 那块）是金色的
        local top = T * 0.62
        local isGoal = state.goalSigns and state.goalSigns[e.isl .. ":" .. e.num]
        if isGoal then
            k = k + 1; slot(b, k, 0, top, T * 1.5, T * 1.5, O.gold, disc(), 70)
        end
        k = k + 1; slot(b, k, 0, 1, T * 0.48, T * 0.2, O.shadow, disc(), 56)
        k = k + 1; slot(b, k, 0, top * 0.45, T * 0.07, top * 0.9, "8A5C33", nil, 255)
        k = k + 1; slot(b, k, 0, top, T * 0.5, T * 0.34, isGoal and O.gold or "C99A63", nil, 255)
        k = k + 1; slot(b, k, 0, top, T * 0.4, math.max(1.5, T * 0.03), "5A3C1E", nil, 200)

    else
        local L, W = T * 0.84, T * 0.46
        k = k + 1; slot(b, k, 0, W * 0.42, L, W, O.wood, nil, 255)
    end

    hideSlots(b, k + 1)
end

-- ================================================================
-- ★ 每帧：更新平滑位置 + 镜头 + 重铺地形 + 重排实体
-- ================================================================
function M.update(dt)
    local w = state.world
    if not w then return end
    if dt > 0.05 then dt = 0.05 end
    state.time = (state.time or 0) + dt

    local T = M.tilePx()
    local HZ = M.heightPx()

    -- ---- 实体平滑显示（只用于把「逻辑坐标」过渡成「显示坐标」）----
    local smooth = config.DEFAULT_SMOOTH
    local k = 1 - (1 - smooth) ^ (dt * 30)

    for _, e in ipairs(w.entities) do
        local key = e.isl .. ":" .. e.num
        local d = entDisp[key]
        if not d then
            d = { x = e.x, y = e.y, z = e.z }
            entDisp[key] = d
        else
            d.x = d.x + (e.x - d.x) * k
            d.y = d.y + (e.y - d.y) * k
            d.z = d.z + (e.z - d.z) * k
            if math.abs(e.x - d.x) < 0.004 then d.x = e.x end
            if math.abs(e.y - d.y) < 0.004 then d.y = e.y end
            if math.abs(e.z - d.z) < 0.004 then d.z = e.z end
        end
    end

    -- ---- 镜头 ----
    local p = w.player
    local pd = entDisp[p.isl .. ":" .. p.num] or { x = p.x, y = p.y, z = p.z }
    local px = pd.x * T + T / 2
    local py = pd.y * T - (pd.z - 1) * HZ + T * 0.72
    local tx, ty = M.focus(w, px, py)
    if not state.camInit then
        state.camX, state.camY = tx, ty
        state.camInit = true
    else
        local ck = 1 - (1 - config.DEFAULT_CAM_SMOOTH) ^ (dt * 30)
        state.camX = state.camX + (tx - state.camX) * ck
        state.camY = state.camY + (ty - state.camY) * ck
    end
    applyCamera()

    -- ---- 地形：跨格才重铺（格内位移交给容器平移）----
    local key = math.floor(state.camX / T) .. "," .. math.floor(state.camY / T) .. "," .. w.W .. "x" .. w.H
    if state.winKey ~= key then
        state.winKey = key
        beginFrame()
        buildTerrain()
        endFrame()
    end

    -- ---- 实体 ----
    M.updateEntities(dt, T, HZ)
end

function M.updateEntities(dt, T, HZ)
    local w = state.world
    -- 视口半宽 / 半高，外加一圈余量（实体在屏幕外一点点也不该突然消失）
    local hw = (state.canvasW or 1280) / 2 + T * 3
    local hh = (state.canvasH or 720) / 2 + T * 4

    -- 挑出视野内的实体，按「行号 → 高度」排序
    local list = {}
    for _, e in ipairs(w.entities) do
        local d = entDisp[e.isl .. ":" .. e.num]
        if d then
            local ux = d.x * T + T / 2
            local uy = (d.z - 1) * HZ - d.y * T - T * 0.72
            -- 屏幕坐标（y 向下）做粗略裁剪
            local sx = ux - state.camX
            local sy = -uy + state.camY
            if sx > -hw and sx < hw and sy > -hh and sy < hh then
                list[#list + 1] = { e = e, d = d, ux = ux, uy = uy }
            end
        end
    end
    table.sort(list, function(a, b)
        if a.d.y ~= b.d.y then return a.d.y < b.d.y end
        return a.d.z < b.d.z
    end)

    boxN = 0
    for _, it in ipairs(list) do
        local e = it.e
        boxN = boxN + 1
        local b = getBox(boxN)
        if b then
            utils.setPosition(b.ctrl, it.ux, it.uy)
            utils.setVisible(b.ctrl, true)
            local sig = tostring(e.type) .. "|" .. tostring(e.ebIsl) .. "|" .. tostring(e.ebNum)
            if e.type == 0 then sig = sig .. "|" .. tostring(state.lookX) .. "," .. tostring(state.lookY) end
            if b.sig ~= sig then
                b.sig = sig
                paintEntity(b, e)
            end
            utils.toLast(b.ctrl)
        end
    end
    for i = boxN + 1, #boxes do
        utils.setVisible(boxes[i].ctrl, false)
        boxes[i].sig = nil
    end
end

-- ================================================================
-- ★ 清场（切地图 / 回标题时用）
-- ================================================================
function M.clear()
    state.world = nil
    state.winKey = nil
    for i = 1, #pool do
        if pool[i] then utils.setVisible(pool[i], false) end
    end
    for i = 1, #boxes do
        utils.setVisible(boxes[i].ctrl, false)
        boxes[i].sig = nil
    end
    entDisp = {}
end

return M
