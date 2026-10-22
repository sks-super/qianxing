-- ================================================================
-- 点灯迷题 16 · 画册式选关（主界面）
-- ================================================================
--  封面 = 游戏信息页；每个大关一页；底部书签条可跳页；左右箭头翻页。
--  每页主体视觉 = 4 块 8×8 线稿（该小关未通关）/ 对应 64 图的 32×32 角（已通关，彩色）
--  周边用基础图元拼花朵 / 星星 / 雪花 / 风车 / 草：
--    · 未通关 → 灰白静态
--    · 已通关 → 彩色 + 动效（摇晃 / 旋转 / 呼吸 / 飘浮）
-- ================================================================

---@diagnostic disable: undefined-global

local state = require("default_import_file/state")
local config = require("default_import_file/config")
local utils = require("default_import_file/utils")
local anim = require("default_import_file/anim")
local art = require("default_import_file/art")
local audio = require("default_import_file/audio")

local M = {}

local TAG = "book"
local TAG_TURN = "book:turn"

-- ---------------- 布局（设计坐标，y 向上） ----------------
local BOOK_W, BOOK_H = 900, 540
local QS = 150                      -- 每块 8×8 的边长
local QGAP = 0            -- ★ 四块严丝合缝（用户要求：中间不要留缝）
local PIC_CX, PIC_CY = 0, -18

local PAPER = "FBF6EA"
local PAPER_EDGE = "E4D8C3"
local INK = "3B2E22"
local INK_DIM = "9A8B78"
local GREY_ON = "B9B2A6"
local GREY_OFF = "EFE9DC"
local ACCENT = "C8643C"
local GOLD = "D9A441"

local root          -- 画册根容器
local pageLayer     -- 当前页容器
local bookBody      -- 书本底板（含纸、脊）
local chips = {}    -- 书签
local chipKinds = {}
local arrowL, arrowR
local pageKind = 0  -- 0=封面 1..N=大关页
local decos = {}    -- { ctrl=, upd= }
local tGlobal = 0
local actions = {}
local busy = false
local sheetPaper          -- 前置声明：一张纸的纸边/纸面/书脊（实现在 buildShell 附近）
local greyDeco = false    -- true：装饰按灰版建（等 celebrate() 逐个变彩）

-- ---------------- 装饰色板 ----------------
local DECO_COLORS = {
    petal = { "E8735A", "F0A15C", "E85D75", "F2C14E" },
    leaf = "6FA96B",
    star = "F4C542",
    flake = "8FC7E8",
    wheel = { "E8735A", "6FA96B", "5B9BD5", "F2C14E" },
    grass = "7FB069",
}

local function doneMask(chIdx)
    state.chapterDone = state.chapterDone or {}
    local d = state.chapterDone[chIdx]
    if not d then
        d = { false, false, false, false }
        state.chapterDone[chIdx] = d
    end
    return d
end

local function chapterCleared(chIdx)
    local d = doneMask(chIdx)
    for i = 1, 4 do
        if not d[i] then return false end
    end
    return true
end

-- ================================================================
-- 装饰：花朵 / 星星 / 雪花 / 风车 / 草 / 光点
--   统一返回 (容器, 更新函数)
-- ================================================================
-- ★★ 本引擎：同级数组下标越小 = 越靠上（绘制时按 z 降序画）。
--   所以「建完就 raise 到末位（= 下标 0）」就等价于「后建的在上」，
--   与真机语义一致。所有图元都走下面这三个包装，别再直接调 utils.createXxx。
-- ★★ 卷页（条带法）要求页面上的图元能「按 x 分条各自变形」，
--   所以页内每个图元都要登记自己的 页内 x / 宽度 / 原色 / 原位置。
--   只在 recordOn = true 且父节点就是当前 pageLayer 时登记。
local pageMeta = { sheets = {}, elems = {} }
local recordOn = false
-- ★ 旧页不在翻页回调里一次性销毁（那是几百个控件，必然卡一帧）：
--   先整页隐藏（一次 setVisible 就够），再每帧销毁 72 个，分几帧清干净。
local trash = {}

local function pumpTrash()
    local t = trash[1]
    if not t then return end
    local m = t.meta
    local ns, ne = #m.sheets, #m.elems
    local budget = 48
    while budget > 0 and t.si < ns do
        t.si = t.si + 1
        utils.destroy(m.sheets[t.si].c)
        budget = budget - 1
    end
    while budget > 0 and t.ei < ne do
        t.ei = t.ei + 1
        utils.destroy(m.elems[t.ei].c)
        budget = budget - 1
    end
    if t.si >= ns and t.ei >= ne then
        utils.destroy(t.page)
        table.remove(trash, 1)
    end
end

local function pushTrash(meta, page)
    if not page then return end
    utils.setVisible(page, false)      -- 立刻看不见（一次调用），随后分帧销毁
    trash[#trash + 1] = { meta = meta, page = page, si = 0, ei = 0 }
end

local function reg(c, x, y, w, hex)
    if not (recordOn and c and pageLayer) then return end
    if type(w) ~= "number" or w <= 0 then return end
    pageMeta.elems[#pageMeta.elems + 1] = {
        c = c, x = x, y = y or 0, w = w,
        hex = hex or "FFFFFF", flat = true,
    }
end

local function rect(par, x, y, w, h, hex, alpha)
    local c = utils.createControl(state.rectPrefabId, x, y, w, h,
        utils.hexToColorA(hex, alpha or 255), par)
    if c then
        utils.raise(c)
        if par == pageLayer then reg(c, x, y, w, hex) end
    end
    return c
end

local function C(par)
    local c = utils.createContainer(par)
    if c then utils.raise(c) end
    return c
end

-- 容器类图元（花朵/星星/书本封面的小图…）：摆好位置再登记
local function place(c, x, y, w, hex)
    if not c then return nil end
    utils.setPos(c, x, y)
    reg(c, x, y, w, hex)
    return c
end

local function T(x, y, w, h, txt, hex, size, par, align)
    -- ★ 一律传 hex 字符串：卷页时要用 setTextColor 复原，Color 对象取不回原色
    local c = utils.createText(x, y, w, h, txt, utils.hexToColor(hex), size, par, align)
    if c then
        utils.raise(c)
        if par == pageLayer then
            reg(c, x, y, w, hex)
            local e = pageMeta.elems[#pageMeta.elems]
            if e then e.text = true end
        end
    end
    return c
end

local function petalRing(par, n, rad, len, wid, hex, alpha, phase0)
    local list = {}
    for i = 1, n do
        local a = (i - 1) * (360 / n) + (phase0 or 0)
        local r = math.rad(a)
        local c = rect(par, math.cos(r) * rad, math.sin(r) * rad, len, wid, hex, alpha)
        if c then
            utils.setRotationZ(c, a)
            list[#list + 1] = c
        end
    end
    return list
end

local function decoFlower(par, x, y, s, col, baby)
    local c = C(par)
    if not c then return nil end
    place(c, x, y, s)
    local petals = petalRing(c, 5, s * 0.34, s * 0.62, s * 0.30, col[1], 255)
    local core = rect(c, 0, 0, s * 0.34, s * 0.34, col[2] or GOLD, 255)
    if core then utils.setRotationZ(core, 45) end
    local stem = rect(c, 0, -s * 0.6, s * 0.10, s * 0.55, DECO_COLORS.leaf, 255)
    return c, function(t)
        local k = 1 + 0.05 * math.sin(t * 2.1 + x * 0.01)
        utils.setScale(c, k)
        utils.setRotationZ(c, math.sin(t * 1.3 + y * 0.02) * 7)
        if stem then utils.setRotationZ(stem, 0) end
        return petals
    end
end

local function decoStar(par, x, y, s, hex)
    local c = C(par)
    if not c then return nil end
    place(c, x, y, s)
    rect(c, 0, 0, s, s * 0.22, hex, 255)
    rect(c, 0, 0, s * 0.22, s, hex, 255)
    rect(c, 0, 0, s * 0.72, s * 0.16, hex, 255)
    local d1 = rect(c, 0, 0, s * 0.72, s * 0.16, hex, 255)
    if d1 then utils.setRotationZ(d1, 45) end
    local d2 = rect(c, 0, 0, s * 0.72, s * 0.16, hex, 255)
    if d2 then utils.setRotationZ(d2, -45) end
    return c, function(t)
        utils.setRotationZ(c, t * 14 + x * 0.05)
        utils.setScale(c, 1 + 0.10 * math.sin(t * 2.6 + y * 0.03))
    end
end

local function decoSnow(par, x, y, s, hex)
    local c = C(par)
    if not c then return nil end
    place(c, x, y, s)
    for i = 0, 2 do
        local a = i * 60
        local r = rect(c, 0, 0, s, s * 0.16, hex, 255)
        if r then utils.setRotationZ(r, a) end
        for _, sgn in ipairs({ 1, -1 }) do
            local rr = math.rad(a)
            local tip = rect(c, math.cos(rr) * s * 0.42 * sgn, math.sin(rr) * s * 0.42 * sgn,
                s * 0.24, s * 0.14, hex, 255)
            if tip then utils.setRotationZ(tip, a + 40 * sgn) end
        end
    end
    return c, function(t)
        utils.setRotationZ(c, -t * 10 + x * 0.04)
        utils.setScale(c, 1 + 0.06 * math.sin(t * 1.9 + x * 0.02))
    end
end

local function decoWheel(par, x, y, s, cols)
    local c = C(par)
    if not c then return nil end
    place(c, x, y, s)
    for i = 1, 4 do
        local a = (i - 1) * 90
        local r = math.rad(a + 40)
        local blade = rect(c, math.cos(r) * s * 0.26, math.sin(r) * s * 0.26,
            s * 0.52, s * 0.20, cols[i], 255)
        if blade then utils.setRotationZ(blade, a + 40) end
    end
    rect(c, 0, 0, s * 0.16, s * 0.16, INK, 200)
    return c, function(t)
        utils.setRotationZ(c, t * 55 + x * 0.1)
    end
end

local function decoGrass(par, x, y, s, hex)
    local c = C(par)
    if not c then return nil end
    place(c, x, y, s)
    local blades = {}
    for i = 1, 3 do
        local b = rect(c, (i - 2) * s * 0.22, s * 0.18, s * 0.12, s * (0.55 + 0.18 * i), hex, 255)
        if b then
            utils.setRotationZ(b, (i - 2) * 12)
            blades[#blades + 1] = b
        end
    end
    return c, function(t)
        utils.setRotationZ(c, math.sin(t * 1.8 + x * 0.03) * 5)
    end
end

local function decoDot(par, x, y, s, hex)
    local c = rect(par, x, y, s, s, hex, 255)
    if not c then return nil end
    return c, function(t)
        local a = 120 + 110 * (0.5 + 0.5 * math.sin(t * 2.2 + x * 0.05))
        utils.setColor(c, hex, math.floor(a))
        utils.setScale(c, 0.85 + 0.25 * math.sin(t * 2.2 + x * 0.05))
    end, true   -- 第三个返回值：非容器，动画直接作用在自身
end

-- 一页的装饰布置（x, y, 类型, 尺寸, 相位）
local PAGE_DECO = {
    { -352, 96, "flower", 54 }, { 336, 176, "star", 40 },
    { -356, -108, "snow", 44 }, { 352, -112, "wheel", 58 },
    { -286, -208, "grass", 42 }, { 300, -206, "grass", 38 },
    { 268, 40, "flower", 32 }, { -268, -30, "dot", 11 },
    { -430, 116, "dot", 9 }, { 424, 176, "dot", 9 },   -- 左上的小点挪开：别顶在副标题前面当“圆点”
    { -424, -176, "dot", 9 }, { 424, -176, "dot", 9 },
    { -96, 242, "star", 22 }, { 168, 214, "dot", 10 },
}

-- 造一个装饰；colored=true 出彩色版，false 出灰版
local function createDeco(par, kind, x, y, s, i, colored)
    local fn, upd, direct
    if kind == "flower" then
        local col = { colored and DECO_COLORS.petal[(i % 4) + 1] or GREY_ON,
                      colored and GOLD or GREY_ON }
        local c, u = decoFlower(par, x, y, s, col)
        fn, upd = c, u
    elseif kind == "star" then
        fn, upd = decoStar(par, x, y, s, colored and DECO_COLORS.star or GREY_ON)
    elseif kind == "snow" then
        fn, upd = decoSnow(par, x, y, s, colored and DECO_COLORS.flake or GREY_ON)
    elseif kind == "wheel" then
        local cols = {}
        for k = 1, 4 do
            cols[k] = colored and DECO_COLORS.wheel[k] or GREY_ON
        end
        fn, upd = decoWheel(par, x, y, s, cols)
    elseif kind == "grass" then
        fn, upd = decoGrass(par, x, y, s, colored and DECO_COLORS.grass or GREY_ON)
    else
        local c, u, dr = decoDot(par, x, y, s, colored and DECO_COLORS.star or GREY_ON)
        fn, upd, direct = c, u, dr
    end
    return fn, upd, direct
end

local function buildDeco(par, cleared)
    decos = {}
    for i = 1, #PAGE_DECO do
        local d = PAGE_DECO[i]
        local x, y, kind, s = d[1], d[2], d[3], d[4]
        local fn, upd, direct = createDeco(par, kind, x, y, s, i, cleared)
        if fn then
            decos[#decos + 1] = {
                ctrl = fn, upd = upd, direct = direct or false, phase = i * 0.7,
                kind = kind, x = x, y = y, s = s, idx = i, colored = cleared,
            }
        end
    end
end

-- ================================================================
-- 一块 8×8：已通关画 32×32 彩图角，否则画 8×8 黑白格
-- ================================================================
local function buildQuarter(par, cx, cy, chIdx, pieceIdx, done)
    local ch = config.getChapter(chIdx)
    if not ch then return nil end

    -- ★ 所有格子直接挂在页面上（不套 box 容器）：卷页时才能按列各自变形
    if done then
        local rects = art.artRects(ch.key)
        if rects then
            local P = QS / 32.0
            local qx = (pieceIdx == 2 or pieceIdx == 4) and 32 or 0
            local qy = (pieceIdx == 3 or pieceIdx == 4) and 32 or 0
            for i = 1, #rects do
                local r = rects[i]
                local x0, x1 = math.max(r.x, qx), math.min(r.x + r.w, qx + 32)
                local y0, y1 = math.max(r.y, qy), math.min(r.y + r.h, qy + 32)
                if x1 > x0 and y1 > y0 then
                    local lw, lh = (x1 - x0), (y1 - y0)
                    local lx = (x0 - qx) + lw / 2.0 - 16.0
                    local ly = 16.0 - ((y0 - qy) + lh / 2.0)
                    rect(par, cx + lx * P, cy + ly * P, lw * P + 0.8, lh * P + 0.8, r.hex, 255)
                end
            end
        end
    else
        local grid = art.parse(ch.pic, ch.noNormalize)
        local pc = config.PIECES[pieceIdx]
        local quad = art.quad(grid, pc.ox, pc.oy)
        local cell = QS / 8.0
        for y = 1, 8 do
            for x = 1, 8 do
                local on = quad[y][x] == 1
                local px = cx - QS / 2 + cell / 2 + (x - 1) * cell
                local py = cy + QS / 2 - cell / 2 - (y - 1) * cell
                rect(par, px, py, cell - 2, cell - 2, on and INK or GREY_OFF, on and 235 or 255)
            end
        end
    end

    -- ★ 以前这里有个 45° 的金色小方块当「已通关角标」，
    --   四块各一个、正好压在图上像四颗卡住的粒子 → 去掉（彩图角本身就是通关标记）

    -- 命中区（卷页期间 busy，不会被误点）
    local hit = utils.createHit(cx, cy, QS + QGAP, QS + QGAP, par, true)
    if hit then
        utils.onCursor(hit, Enum.CursorEventType.CursorClick, function()
            if busy then return false end
            audio.playClick()
            if actions.onEnterPiece then actions.onEnterPiece(chIdx, pieceIdx, cx, cy, QS) end
            return true
        end)
    end
    return nil
end

-- ================================================================
-- 页面构建
-- ================================================================
local function clearPage()
    if pageLayer then pushTrash(pageMeta, pageLayer); pageLayer = nil end
    pageMeta = { sheets = {}, elems = {} }
    recordOn = false
    decos = {}
end

local function buildCover()
    local pal = config.DEFAULT_PALETTE or {}
    pageLayer = C(bookBody)
    sheetPaper(pageLayer)

    local t1 = T(0, 150, 760, 76, "绘卷修复师", INK, 62, pageLayer)
    local t2 = T(0, 92, 760, 40, "把散落的绘卷拼回原样", INK_DIM, 22, pageLayer)
    local t3 = T(0, 34, 700, 32, "四块一图 · 合拢上色 · 复原绘卷",
        INK_DIM, 16, pageLayer)

    -- 封面主视觉：四块小方格拼成的大图（未通关时的线稿）
    local ch = config.getChapter(1)
    if ch then
        local grid = art.parse(ch.pic, ch.noNormalize)
        local cell = 13
        local span = 16 * cell
        local holder = C(pageLayer)
        place(holder, 0, -108, span)
        for y = 1, 16 do
            for x = 1, 16 do
                if grid[y][x] == 1 then
                    rect(holder, -span / 2 + cell / 2 + (x - 1) * cell,
                        span / 2 - cell / 2 - (y - 1) * cell, cell - 2, cell - 2, INK, 210)
                end
            end
        end
        utils.setRotationZ(holder, -6)
    end

    local wrap = C(pageLayer)
    place(wrap, 0, -232, 240)
    local btn = utils.createButton(0, 0, 240, 56, wrap, {
        text = "翻开画册  →", fontSize = 20,
        bg = ACCENT, bgDown = "A34E2E", textColor = "FFF6E8",
        onClick = function()
            if busy then return end
            M.open(1, 1)
        end,
    })
    if btn then utils.raise(btn.base); utils.raise(btn.label); utils.raise(btn.hit) end
    M._btnStart = btn
    return pageLayer
end

local function buildChapterPage(chIdx)
    pageLayer = C(bookBody)
    sheetPaper(pageLayer)
    local ch = config.getChapter(chIdx)
    if not ch then return pageLayer end
    local done = doneMask(chIdx)
    local cleared = chapterCleared(chIdx)
    local nDone = 0
    for i = 1, 4 do if done[i] then nDone = nDone + 1 end end

    -- ★ 左对齐文本框是从「框的左边缘」开始排字的：
    --   想让它贴着页面左边距（-420），框心必须写 -420 + w/2，而不是 -420
    local TX, TW = -420 + 210, 420
    T(TX, 220, TW, 56, ch.name or "", INK, 40, pageLayer, "left")
    T(TX, 180, TW, 30,
        "第 " .. chIdx .. " 大关 · 已点亮 " .. nDone .. "/4",
        cleared and ACCENT or INK_DIM, 17, pageLayer, "left")

    -- 图片外框（chrome：翻页瞬间藏起来，避免整块刚性压缩）
    local frame = rect(pageLayer, PIC_CX, PIC_CY, QS * 2 + 26, QS * 2 + 26, PAPER_EDGE, 255)
    if frame then
        local fe = pageMeta.elems[#pageMeta.elems]
        if fe then fe.chrome = true end
    end

    local half = QS / 2 + QGAP / 2
    local slots = {
        { -half, half, 1 }, { half, half, 2 },
        { -half, -half, 3 }, { half, -half, 4 },
    }
    for i = 1, 4 do
        local s = slots[i]
        buildQuarter(pageLayer, PIC_CX + s[1], PIC_CY + s[2], chIdx, s[3], done[s[3]])
    end

    buildDeco(pageLayer, cleared and not greyDeco)

    T(0, -238, 600, 30,
        cleared and "全部点亮 · 再次进入任意一块重玩" or "点一块 8×8 开始",
        cleared and ACCENT or INK_DIM, 15, pageLayer)
    return pageLayer
end

-- ================================================================
-- 书本底板 / 书签 / 箭头
-- ================================================================
local function buildShell()
    bookBody = C(root)

    -- 书影
    rect(bookBody, 20, -28, BOOK_W + 56, BOOK_H + 40, "2A1A10", 72)
    -- 书页堆：翻页时露出的是「下面还有纸」，而不是一块空洞
    rect(bookBody, 4, -8, BOOK_W + 12, BOOK_H + 12, "D5C6AC", 255)
    rect(bookBody, 2, -4, BOOK_W + 7, BOOK_H + 7, "EFE6D5", 255)
end

-- ================================================================
-- ★ 一张纸 = 纸边 + 纸面 + 书脊 + 页口，全部属于这一页自己的容器。
--   这样翻页时「整张纸」一起翻转（而不是书页上的图元各自滑动）。
-- ================================================================
local NS = 40                     -- 纸带数：40 条 ≈ 22px 一条，卷边够顺滑
local SW = BOOK_W / NS

sheetPaper = function(p)
    pageMeta.sheets = {}
    local keep = recordOn
    recordOn = false              -- 纸带不登记成「内容元素」
    for i = 1, NS do
        local x = -BOOK_W / 2 + SW / 2 + (i - 1) * SW
        local cont = C(p)
        utils.setPos(cont, x, 0)
        local base = utils.createControl(state.rectPrefabId, 0, 0, SW + 0.8, BOOK_H,
            utils.hexToColor(PAPER), cont)
        if base then utils.raise(base) end
        if i == 1 then            -- 书脊（页根）只在最左一条
            local sp = utils.createControl(state.rectPrefabId, -SW / 2 + 8.5, 0, 17, BOOK_H - 4,
                utils.hexToColor("D8C9AF"), cont)
            if sp then utils.raise(sp) end
            local sp2 = utils.createControl(state.rectPrefabId, -SW / 2 + 21.5, 0, 3, BOOK_H - 12,
                utils.hexToColorA("C6B598", 110), cont)
            if sp2 then utils.raise(sp2) end
        end
        if i == NS then           -- 页口厚度只在最右一条
            local eg = utils.createControl(state.rectPrefabId, SW / 2 - 4, 0, 7, BOOK_H - 8,
                utils.hexToColorA("F3EBDA", 210), cont)
            if eg then utils.raise(eg) end
        end
        pageMeta.sheets[#pageMeta.sheets + 1] = {
            c = cont, base = base, x = x, w = SW, flat = true,
        }
    end
    recordOn = keep
    return p
end

local function buildChips()
    chips, chipKinds = {}, {}
    local n = config.chapterCount() + 1
    local cw, chh = 54, 40
    local gap = 8
    local total = cw * n + gap * (n - 1)
    for i = 1, n do
        local kind = i - 1          -- 0 = 封面
        local x = -total / 2 + cw / 2 + (i - 1) * (cw + gap)
        local label = (kind == 0) and "封" or tostring(kind)
        local btn = utils.createButton(x, -BOOK_H / 2 - 46, cw, chh, root, {
            text = label, fontSize = 17,
            bg = "D8C9AF", bgDown = "C2B193", textColor = "5B4A38",
            onClick = function()
                if busy or kind == pageKind then return false end
                M.open(kind, kind > pageKind and 1 or -1)
            end,
        })
        if btn then
            chips[kind] = btn
            chipKinds[#chipKinds + 1] = kind
        end
    end
end

local function buildArrows()
    local bx = BOOK_W / 2 + 58
    arrowR = utils.createButton(bx, 0, 56, 92, root, {
        text = "→", fontSize = 34,
        bg = "E6DAC2", bgDown = "CDBD9F", textColor = "6B5A46",
        onClick = function()
            if busy then return end
            if pageKind < config.chapterCount() then M.open(pageKind + 1, 1) end
        end,
    })
    arrowL = utils.createButton(-bx, 0, 56, 92, root, {
        text = "←", fontSize = 34,
        bg = "E6DAC2", bgDown = "CDBD9F", textColor = "6B5A46",
        onClick = function()
            if busy then return end
            if pageKind > 0 then M.open(pageKind - 1, -1) end
        end,
    })
end

local function refreshChips()
    for kind, btn in pairs(chips) do
        local on = (kind == pageKind)
        local cleared = (kind > 0) and chapterCleared(kind)
        utils.setColor(btn.base, on and ACCENT or (cleared and "E6C98A" or "D8C9AF"), 255)
        utils.setTextColor(btn.label, on and "FFF6E8" or "5B4A38", 255)
    end
    -- ★ 到头了就整个藏起来（只关 enabled 会留下一个没有箭头的灰方块）
    local function setArrow(btn, on)
        if not btn then return end
        utils.setButtonEnabled(btn, on)
        if btn.base then utils.setVisible(btn.base, on) end
        if btn.label then utils.setVisible(btn.label, on) end
        if btn.hit then utils.setVisible(btn.hit, on) end
    end
    setArrow(arrowL, pageKind > 0)
    setArrow(arrowR, pageKind < config.chapterCount())
end

-- ================================================================
-- 翻页
-- ================================================================
local function makePage(kind)
    pageMeta = { sheets = {}, elems = {} }
    recordOn = true
    local pg
    if kind == 0 then pg = buildCover() else pg = buildChapterPage(kind) end
    recordOn = false
    return pg, pageMeta
end

-- ================================================================
-- ★★ 条带法卷页（参考 Canvas 2D 卷页：θ = d / R）
--   页面从右缘卷起，纸带按 θ 做「水平压缩 + 下坠 + 明暗」，卷过 90° 变纸背。
--   页内容（格子/文字/装饰）按自己所在的 x 跟着同一条曲线走，
--   卷进去的部分（θ→90°）逐渐淡出——纸一卷起来，正面本来就看不见了。
-- ================================================================
local CURL_R = BOOK_W * 0.26          -- 卷曲半径（0.22~0.35，越小卷越紧）
local CURL_DY = 0.28                  -- 下坠系数（0.2~0.35，太大卷边会耷拉到书外）

local function mixHex(a, b, t)
    local function c(h, i) return tonumber(h:sub(i, i + 1), 16) or 0 end
    local r = c(a, 1) + (c(b, 1) - c(a, 1)) * t
    local g = c(a, 3) + (c(b, 3) - c(a, 3)) * t
    local bl = c(a, 5) + (c(b, 5) - c(a, 5)) * t
    return string.format("%02X%02X%02X",
        math.floor(r + 0.5), math.floor(g + 0.5), math.floor(bl + 0.5))
end

local function curlPage(meta, foldX)
    if not meta then return end
    local folding = foldX < BOOK_W / 2 - 0.5
    -- ★ 末尾 150px 渐隐：折线贴到最左后，残留的纸边/内容淡出，
    --   而不是"啪"地一下消失（用户反馈的最后一帧顿挫，一半是这个突变）
    local fade = 1
    if foldX < -(BOOK_W / 2 - 150) then
        fade = (foldX + BOOK_W / 2) / 150
        if fade < 0 then fade = 0 end
    end

    -- ① 纸带：用「左边缘 / 右边缘」各自的 θ 算，相邻两条的边严格重合
    --    （只按条心算会有台阶感；按边缘算等于把曲面切成连续的条）
    for i = 1, #meta.sheets do
        local sh = meta.sheets[i]
        local xl = sh.x - sh.w / 2
        local xr = sh.x + sh.w / 2
        local dr = xr - foldX
        if dr <= 0 then
            if not sh.flat then
                sh.flat = true
                if not sh.vis then sh.vis = true; utils.setVisible(sh.c, true) end
                utils.setPos(sh.c, sh.x, 0)
                utils.setScaleXY(sh.c, 1, 1)
                if sh.base and (sh.shade ~= 0 or sh.alpha ~= 255) then
                    sh.shade, sh.alpha = 0, 255
                    utils.setColor(sh.base, PAPER, 255)
                end
                if sh.up then sh.up = false; utils.sink(sh.c) end
            end
        else
            sh.flat = false
            if not sh.up then sh.up = true; utils.raise(sh.c) end
            local thL = math.max(0, (xl - foldX) / CURL_R)
            local a8 = math.floor(255 * fade)
            if thL >= math.pi / 2 or a8 <= 3 then
                if sh.vis ~= false then sh.vis = false; utils.setVisible(sh.c, false) end
            else
                if sh.vis ~= true then sh.vis = true; utils.setVisible(sh.c, true) end
                local thR = math.min(dr / CURL_R, math.pi / 2)
                local nl = foldX + CURL_R * math.sin(thL)
                local nr = foldX + CURL_R * math.sin(thR)
                local wpx = math.max(0.35, nr - nl)
                local thm = (thL + thR) / 2
                local cs = math.cos(thm)
                utils.setScaleXY(sh.c, wpx / sh.w, 1)
                utils.setPos(sh.c, (nl + nr) / 2, -CURL_R * (1 - cs) * CURL_DY)
                local k = math.min(0.86, 0.58 * (1 - cs) + 0.06 * thm)
                if thm < 0.5 then
                    k = k - 0.30 * (1 - thm / 0.5)       -- 折线附近提亮（等价于混白）
                end
                local q = math.floor(k * 26 + 0.5) / 26  -- 26 档：够细，又不会每帧重算
                if q ~= sh.shade or a8 ~= sh.alpha then
                    sh.shade, sh.alpha = q, a8
                    local hex = (k >= 0) and mixHex(PAPER, "6B5238", k) or PAPER
                    if k < 0 then hex = mixHex(PAPER, "FFFDF4", -k) end
                    if sh.base then utils.setColor(sh.base, hex, a8) end
                end
            end
        end
    end

    -- ② 页内元素
    for i = 1, #meta.elems do
        local e = meta.elems[i]
        if e.chrome then
            if e.hidden ~= folding then
                e.hidden = folding
                utils.setVisible(e.c, not folding)
            end
        else
            local d = e.x - foldX
            if d <= 0 then
                if not e.flat then
                    e.flat = true
                    if e.vis == false then e.vis = true; utils.setVisible(e.c, true) end
                    utils.setPos(e.c, e.x, e.y)
                    utils.setScaleXY(e.c, 1, 1)
                    if e.text then utils.setTextColor(e.c, e.hex, 255)
                    else utils.setColor(e.c, e.hex, 255) end
                    e.lastA = 255
                end
            else
                e.flat = false
                local th = d / CURL_R
                local LIMIT = math.pi / 3
                if th >= LIMIT then
                    if e.vis ~= false then e.vis = false; utils.setVisible(e.c, false) end
                else
                    if e.vis ~= true then e.vis = true; utils.setVisible(e.c, true) end
                    local cs, sn = math.cos(th), math.sin(th)
                    utils.setScaleXY(e.c, math.max(0.03, cs), 1)
                    utils.setPos(e.c, foldX + CURL_R * sn + (e.w * cs) / 2,
                        e.y - CURL_R * (1 - cs) * CURL_DY)
                    local a = math.floor(255 * math.max(0, 1 - th / LIMIT) ^ 1.25 * fade)
                    if math.abs(a - (e.lastA or -1)) > 10 then
                        e.lastA = a
                        if e.text then utils.setTextColor(e.c, e.hex, a)
                        else utils.setColor(e.c, e.hex, a) end
                    end
                end
            end
        end
    end
end

local function turnTo(kind, dir, force)
    if pageLayer and kind == pageKind and not force then
        -- 同页（刷新）：直接重建
        clearPage()
        makePage(kind)
        refreshChips()
        return
    end
    busy = true
    local oldPage = pageLayer
    local oldMeta = pageMeta
    pageLayer = nil
    pageMeta = { sheets = {}, elems = {} }

    -- 新页先建（压在旧页下面）
    local newPage, newMeta = makePage(kind)

    if not oldPage then
        utils.setScale(newPage, 0.965)
        anim.tween(0.34, function(p)
            utils.setScale(newPage, 0.965 + 0.035 * anim.Ease.outCubic(p))
        end, { ease = "linear", tag = TAG_TURN, onDone = function()
            utils.setScale(newPage, 1)
            pageKind = kind
            refreshChips()
            busy = false
        end })
        return
    end

    local DUR = 0.54
    if dir > 0 then
        -- 旧页在上：从右缘卷到左边
        utils.raise(oldPage)
        anim.tween(DUR, function(p)
            local e = anim.Ease.inOutCubic(p)
            curlPage(oldMeta, BOOK_W / 2 - BOOK_W * e)
        end, { ease = "linear", tag = TAG_TURN, onDone = function()
            -- ★ 不在回调里 destroy（几百个控件一次性销毁 = 卡一帧）：
            --   整页隐藏 + 进队列，之后每帧销毁 72 个
            pushTrash(oldMeta, oldPage)
            utils.setScale(newPage, 1)
            utils.setPos(newPage, 0, 0)
            pageKind = kind
            refreshChips()
            busy = false
        end })
    else
        -- 新页在上：从卷曲状态展开
        utils.raise(newPage)
        curlPage(newMeta, -BOOK_W / 2)
        anim.tween(DUR, function(p)
            local e = anim.Ease.inOutCubic(p)
            curlPage(newMeta, -BOOK_W / 2 + BOOK_W * e)
        end, { ease = "linear", tag = TAG_TURN, onDone = function()
            curlPage(newMeta, BOOK_W / 2)     -- 收尾：全部摆正
            pushTrash(oldMeta, oldPage)
            pageKind = kind
            refreshChips()
            busy = false
        end })
    end
end

-- ================================================================
-- 对外
-- ================================================================
M.PAPER = PAPER
M.PIC = { cx = PIC_CX, cy = PIC_CY, size = QS * 2 }
M.QUAD = { size = QS, centers = {
    { PIC_CX - QS / 2, PIC_CY + QS / 2 },
    { PIC_CX + QS / 2, PIC_CY + QS / 2 },
    { PIC_CX - QS / 2, PIC_CY - QS / 2 },
    { PIC_CX + QS / 2, PIC_CY - QS / 2 },
} }

function M.init(a)
    actions = a or {}
    if not state.containerBook then return false end
    if root then return true end
    root = C(state.containerBook)
    if not root then return false end

    -- 深色背景（盖住游戏界面）
    local pal = config.DEFAULT_PALETTE or {}
    rect(root, 0, 0, 2200, 1300, pal.bg or "070A12", 255)
    rect(root, 0, 40, 1500, 900, pal.bgGlow or "152348", 40)

    buildShell()
    buildChips()
    buildArrows()

    utils.setVisible(root, false)
    pageKind = 0
    return true
end

function M.open(kind, dir, force)
    if not root then return false end
    dir = dir or 1
    utils.setScale(root, 1)
    utils.setPos(root, 0, 0)
    utils.setVisible(root, true)
    utils.raise(root)
    turnTo(kind, dir, force)
    return true
end

-- ★ 进关时把整本书「收起来」：缩一下 + 下沉，然后隐藏（飞行块在 containerWin 上，不受影响）
function M.dismiss(dur)
    if not root then return false end
    local d = dur or 0.28
    anim.clear(TAG_TURN)
    busy = false
    anim.tween(d, function(p)
        local e = anim.Ease.inCubic(p)
        utils.setScale(root, 1 - 0.12 * e)
        utils.setPos(root, 0, -46 * e)
    end, { ease = "linear", tag = TAG_TURN, onDone = function()
        utils.setVisible(root, false)
        utils.setScale(root, 1)
        utils.setPos(root, 0, 0)
    end })
    return true
end

-- ★ 直接显示某一页（不做翻页动画）：通关演出回到画册时，蒙版盖住的那一下用它
function M.showPage(kind, grey)
    if not root then return false end
    anim.clear(TAG_TURN)
    busy = false
    clearPage()
    utils.setVisible(root, true)
    utils.raise(root)
    utils.setScale(root, 1)
    utils.setPos(root, 0, 0)
    greyDeco = grey and true or false
    pageKind = kind
    makePage(kind)
    greyDeco = false
    refreshChips()
    return true
end

-- ★★ 魔法星命中：装饰逐個从灰变彩 + 开启动效
local TAG_CELE = "book:cele"

local function starShape(par, s, hex)
    local c = C(par)
    if not c then return nil end
    for _, a in ipairs({ 0, 45, 90, 135 }) do
        local bar = rect(c, 0, 0, s, s * 0.19, hex, 255)
        if bar then utils.setRotationZ(bar, a) end
    end
    return c
end

function M.celebrate()
    if not pageLayer then return false end
    audio.playWin()      -- 星星开始命中 = 大关胜利的那一刻

    for i = 1, #decos do
        local d = decos[i]
        if not d.colored then
            anim.delay(0.075 * (i - 1), function()
                local sx = d.x + ((d.x >= 0) and 230 or -230)
                local sy = d.y + 190
                local star = starShape(pageLayer, d.s * 0.85, "FFE9A8")
                if not star then return end
                utils.setPos(star, sx, sy)
                utils.setScale(star, 0.65)
                anim.tween(0.28, function(p)
                    local e = anim.Ease.inQuad(p)
                    utils.setPos(star, utils.lerp(sx, d.x, e), utils.lerp(sy, d.y, e))
                    utils.setRotationZ(star, 200 * e)
                end, { ease = "linear", tag = TAG_CELE, onDone = function()
                    utils.destroy(star)
                    local ctrl, upd, direct = createDeco(pageLayer, d.kind, d.x, d.y, d.s, d.idx, true)
                    if not ctrl then return end
                    utils.setScale(ctrl, 0.25)
                    anim.tween(0.34, function(p)
                        utils.setScale(ctrl, 0.25 + 0.75 * anim.Ease.outBack(p))
                    end, { ease = "linear", tag = TAG_CELE, onDone = function()
                        utils.setScale(ctrl, 1)
                    end })
                    if d.ctrl then utils.setVisible(d.ctrl, false) end
                    d.ctrl = ctrl
                    d.upd = upd
                    d.direct = direct or false
                    d.colored = true

                    local fl = rect(pageLayer, d.x, d.y, d.s * 0.9, d.s * 0.9, "FFF4C8", 210)
                    if fl then
                        anim.tween(0.26, function(pp)
                            utils.setScale(fl, 1 + 1.1 * anim.Ease.outCubic(pp))
                            utils.setColor(fl, "FFF4C8", math.floor(210 * (1 - pp)))
                        end, { ease = "linear", tag = TAG_CELE, onDone = function() utils.destroy(fl) end })
                    end
                    audio.playStar()
                end })
            end, TAG_CELE)
        end
    end
    return true
end

function M.close(done)
    if not root then return false end
    anim.clear(TAG_TURN)
    busy = false
    clearPage()
    utils.setVisible(root, false)
    if done then pcall(done) end
    return true
end

function M.isOpen()
    return root and root.active == true
end

function M.getPage()
    return pageKind
end

function M.refresh()
    if not root then return end
    clearPage()
    makePage(pageKind)
    refreshChips()
end

function M.update(dt)
    pumpTrash()
    if not root or not pageLayer then return end
    tGlobal = tGlobal + dt
    for i = 1, #decos do
        local d = decos[i]
        if d.upd then
            local ok = pcall(d.upd, tGlobal + d.phase)
            if not ok then d.upd = nil end
        end
    end
end

function M.setVisible(v)
    if root then utils.setVisible(root, v) end
end

return M
