-- ================================================================
-- 绘卷修复师 · 图文教程 + 操作高亮
-- ================================================================
--  ★ 教程是一本「纸卷」：深色遮罩 + 纸面面板 + 示意图 + 两行正文。
--  ★ 关闭教程后进入「引导模式」：在需要操作的位置画脉动金环 + 下滑箭头，
--    直到猫猫关第一块（左上）通关为止。
--
--  分层（containerGuide，自下而上）：
--    遮罩 → 投影 → 牌沿 → 纸面 → 卷轴轴头 → 标题/页码 → 示意图凹槽
--    → 示意图格子 → 图注 → 正文两行 → 圆点 → 按钮 → 全屏挡板
-- ================================================================

---@diagnostic disable: undefined-global

local M = {}

local state = require("default_import_file/state")
local config = require("default_import_file/config")
local utils = require("default_import_file/utils")
local anim = require("default_import_file/anim")
local audio = require("default_import_file/audio")

local TAG = "guide"

-- ---------------- 配色（跟画册一致） ----------------
local PAPER = "FBF6EA"
local PAPER_EDGE = "E4D8C3"
local PAPER_DEEP = "F1E6CF"
local INK = "3B2E22"
local INK_DIM = "9A8B78"
local ACCENT = "C8643C"
local GOLD = "D9A441"
local RING = "E8A33D"

-- ---------------- 版式 ----------------
local PW, PH = 780, 560
local BG_W, BG_H = 2400, 1400
local TITLE_Y = PH / 2 - 46
local STAGE_CY = 44
local STAGE_W, STAGE_H = 400, 240
local CAPTION_Y = -104
local LINE1_Y = -142
local LINE2_Y = -178

-- ================================================================
-- 教程内容
--   art.kind : map（四块） / grid（单张 5×5） / two（左右对照）
--              chips（顶部进度） / quad（单张 + 高亮环）
-- ================================================================
local PAGES = {
    {
        title = "序章 · 残卷",
        caption = "千星书阁 · 绘卷修复师",
        lines = {
            "夜风把书阁的绘卷吹散了，四角散落成碎片。",
            "你是新上任的修复师，要把它们一一拼回原样。",
        },
        art = { kind = "map", lit = { 1 } },
    },
    {
        title = "每幅绘卷 · 分四块",
        caption = "左上 / 右上 / 左下 / 右下",
        lines = {
            "一幅绘卷被分成四块，每块都是一道小谜题。",
            "四块全部复原，绘卷才会合拢、重新上色。",
        },
        art = { kind = "map", lit = { 1, 2, 3, 4 } },
    },
    {
        title = "怎么翻",
        caption = "点一格 = 自己和上下左右一起翻",
        lines = {
            "格子只有「亮」和「暗」两面，点一下翻过来。",
            "点中间那格，十字上的五格会同时翻面。",
        },
        art = { kind = "grid", ring = { 3, 3 },
                lit = { ".....", "..o..", ".oOo.", "..o..", "....." } },
    },
    {
        title = "复原的标准",
        caption = "左边是样子，右边是你的盘面",
        lines = {
            "把右边的盘面翻得和左边的图案一模一样，这块就复原了。",
            "从边缘试起，一格往往会牵动一片。",
        },
        art = { kind = "two" },
    },
    {
        title = "界面上有什么",
        caption = "顶部进度 · 底部工具",
        lines = {
            "顶上的四颗星是四块的进度，亮一颗就是复原一块。",
            "底部可以撤销、重置、看提示，也能随时回画册选关。",
        },
        art = { kind = "chips" },
    },
    {
        title = "开始修复",
        caption = "先去点左上那一块",
        lines = {
            "跟着金色高亮走：它指哪儿，就点哪儿。",
            "第一块复原之后，剩下的就交给你了。",
        },
        art = { kind = "map", lit = {}, ring = 1 },
    },
}

local pageIndex = 1
local root
local nodes = {}
local diagramNodes = {}
local titleText, captionText, pageText, bodyText = {}, {}, nil, {}
local dots = {}
local btnPrev, btnNext
local actions = {}

-- 高亮（引导模式）
local hintRoot
local hintBars = {}
local hintArrow = {}
local hintPulse = 0
local hintOn = false
local hintBase = 1      -- ★ 不能存在引擎控件对象上（userdata，写自定义字段会丢）

local function add(c)
    if c then nodes[#nodes + 1] = c end
    return c
end

local function rect(parent, x, y, w, h, hex, alpha)
    local c = utils.createControl(state.rectPrefabId, x, y, w, h,
        utils.hexToColorA(hex, alpha or 255), parent)
    if c then utils.raise(c) end
    return add(c)
end

local function text(parent, x, y, w, h, s, hex, size, align)
    local c = utils.createText(x, y, w, h, s, utils.hexToColor(hex), size, parent, align)
    if c then utils.raise(c) end
    return add(c)
end

-- ================================================================
-- 示意图
-- ================================================================
local DG = 26          -- 示意图格子边长（5 行 = 26*5 + 5*4 = 150，正好塞进凹槽）
local DGG = 5          -- 格间距

-- ch: "." = 不参与  /  "o" = 会被翻转  /  "O" = 你按下的那一格
local function drawCell(cx, cy, i, j, ch, size)
    size = size or DG
    local x = cx + (j - 3) * (size + DGG)
    local y = cy - (i - 3) * (size + DGG)
    local col = (ch == "o") and INK or ((ch == "O") and ACCENT or PAPER_DEEP)
    local c = utils.createControl(state.rectPrefabId, x, y,
        size - 2, size - 2, utils.hexToColorA(col, 255), root)
    if c then utils.raise(c); diagramNodes[#diagramNodes + 1] = c end
end

local function drawPattern(cx, cy, rows, size)
    for i = 1, #rows do
        local row = rows[i]
        for j = 1, #row do
            drawCell(cx, cy, i, j, row:sub(j, j), size)
        end
    end
end

local function drawRing(cx, cy, size, color)
    local th = 4
    local S = size + 10
    local half = S / 2 - th / 2
    local run = S - th * 2
    local parts = {
        { 0, half, S, th }, { 0, -half, S, th },
        { -half, 0, th, run }, { half, 0, th, run },
    }
    for k = 1, 4 do
        local p = parts[k]
        local c = utils.createControl(state.rectPrefabId,
            cx + p[1], cy + p[2], p[3], p[4],
            utils.hexToColorA(color or RING, 255), root)
        if c then utils.raise(c); diagramNodes[#diagramNodes + 1] = c end
    end
end

-- ★ 示意图专用：只登记到 diagramNodes（翻页会被销毁），不能进 nodes（那是常驻层）
local function dcell(x, y, w, h, hex, alpha)
    local c = utils.createControl(state.rectPrefabId, x, y, w, h,
        utils.hexToColorA(hex, alpha or 255), root)
    if c then
        utils.raise(c)
        diagramNodes[#diagramNodes + 1] = c
    end
    return c
end

local function clearDiagram()
    for i = 1, #diagramNodes do utils.destroy(diagramNodes[i]) end
    diagramNodes = {}
end

local function buildDiagram(page)
    clearDiagram()
    local art = page.art or { kind = "grid" }
    if art.kind == "map" then
        -- 四块拼图：中间留 4px 缝
        local s = 54
        local lit = art.lit or { 1 }
        local pos = { { -1, 1 }, { 1, 1 }, { -1, -1 }, { 1, -1 } }
        for i = 1, 4 do
            local on = false
            for k = 1, #lit do if lit[k] == i then on = true end end
            local x = pos[i][1] * (s + 4) / 2
            local y = pos[i][2] * (s + 4) / 2
            diagramNodes[#diagramNodes + 1] = dcell(x, y, s, s, on and "F7AF6D" or "C9B08A", 255)
            if on then
                diagramNodes[#diagramNodes + 1] = dcell(x, y, s - 8, s - 8, "FCC98B", 255)
            end
        end
        if art.ring then
            local k = math.max(1, math.min(4, art.ring))
            local rx = pos[k][1] * (s + 4) / 2
            local ry = pos[k][2] * (s + 4) / 2
            drawRing(rx, ry, s, RING)
        end

    elseif art.kind == "grid" or art.kind == "quad" then
        local rows = art.lit or { "ooooo" }
        local cx = (art.kind == "quad") and 0 or -30
        drawPattern(cx, 0, rows, DG)
        if art.ring then
            local j, i = art.ring[1], art.ring[2]
            drawRing(cx + (j - 3) * (DG + DGG), -(i - 3) * (DG + DGG), DG, RING)
        elseif art.kind == "quad" then
            drawRing(cx, 0, DG * 5 + DGG * 4, RING)
        end
    elseif art.kind == "two" then
        local rowsA = art.aRows or { ".oo..", "o..o.", "o..o.", ".oo..", "....." }
        local rowsB = art.bRows or { ".....", "oo...", "o.ooo", ".o.o.", "..o.." }
        drawPattern(-132, 0, rowsA, 24)
        drawPattern(132, 0, rowsB, 24)
        -- 中间的箭头：杆 + 两个 45° 斜条做箭头
        diagramNodes[#diagramNodes + 1] = dcell(0, 0, 34, 5, INK_DIM, 255)
        local h1 = dcell(18, 7, 22, 5, INK_DIM, 255)
        if h1 then utils.setRotationZ(h1, 45) end
        local h2 = dcell(18, -7, 22, 5, INK_DIM, 255)
        if h2 then utils.setRotationZ(h2, -45) end
        -- 左「目标」右「盘面」的小标签
    elseif art.kind == "chips" then
        -- 上排：四个拼图槽（前两个点亮）
        local n, s1, gap = 4, 52, 14
        local total = n * s1 + (n - 1) * gap
        for i = 1, n do
            local x = -total / 2 + s1 / 2 + (i - 1) * (s1 + gap)
            local done = i <= 2
            diagramNodes[#diagramNodes + 1] = dcell(x, 34, s1, s1,
                done and "E6C98A" or "E3D5BA", 255)
            diagramNodes[#diagramNodes + 1] = dcell(x, 34, s1 - 10, s1 - 10,
                done and GOLD or "EFE4CC", 255)
            if done then
                -- 十字 + 斜十字 = 一颗像素星
                for _, ang in ipairs({ 0, 45, 90, 135 }) do
                    local bar = dcell(x, 34, 26, 6, "FFF6E0", 255)
                    if bar then utils.setRotationZ(bar, ang) end
                end
            end
        end
        -- 下排：四颗底部按钮
        local bw, bh, bg2 = 62, 24, 10
        local tw = n * bw + (n - 1) * bg2
        for i = 1, n do
            local x = -tw / 2 + bw / 2 + (i - 1) * (bw + bg2)
            diagramNodes[#diagramNodes + 1] = dcell(x, -46, bw, bh, "E3D5BA", 255)
            diagramNodes[#diagramNodes + 1] = dcell(x, -46, bw - 6, bh - 6, "F3E9D2", 255)
        end
        -- 顶部提示条（标题/步数）
        diagramNodes[#diagramNodes + 1] = dcell(0, 96, tw + 10, 12, "E3D5BA", 255)
    end
end

-- ================================================================
-- 初始化
-- ================================================================
function M.init(a)
    actions = a or {}
    if root then return true end
    if not state.containerGuide then return false end
    if (state.rectPrefabId or 0) <= 0 then return false end

    root = add(utils.createContainer(state.containerGuide))
    if not root then return false end
    utils.setVisible(root, false)

    -- 遮罩
    rect(root, 0, 0, BG_W, BG_H, "0B0E16", 170)

    -- 纸卷：投影 → 牌沿 → 纸面
    rect(root, 10, -12, PW + 20, PH + 20, "2A1A10", 70)
    rect(root, 0, 0, PW + 14, PH + 14, PAPER_EDGE, 255)
    rect(root, 0, 0, PW, PH, PAPER, 255)

    -- 上下两条「卷轴轴头」
    rect(root, 0, PH / 2 - 6, PW + 8, 14, "D8C9AF", 255)
    rect(root, 0, -PH / 2 + 6, PW + 8, 14, "D8C9AF", 255)
    rect(root, 0, PH / 2 - 6, PW + 8, 4, "C6B598", 160)
    rect(root, 0, -PH / 2 + 6, PW + 8, 4, "C6B598", 160)

    -- 全屏挡板：挡住面板下面的书页/棋盘，避免误点（按钮在它上面）
    local blocker = utils.createHit(0, 0, BG_W, BG_H, root, true)
    if blocker then nodes[#nodes + 1] = blocker end

    -- 标题 / 页码
    titleText = text(root, 0, TITLE_Y, PW - 120, 44, "", INK, 28)
    pageText = text(root, PW / 2 - 74, TITLE_Y, 60, 30, "", INK_DIM, 15, "right")

    -- 示意图凹槽
    rect(root, 0, STAGE_CY, STAGE_W, STAGE_H, "F7EEDA", 255)
    rect(root, 0, STAGE_CY + STAGE_H / 2 - 2, STAGE_W, 3, "E5D7B9", 255)

    captionText = text(root, 0, CAPTION_Y, PW - 120, 26, "", INK_DIM, 15)
    bodyText[1] = text(root, 0, LINE1_Y, PW - 120, 30, "", INK, 17)
    bodyText[2] = text(root, 0, LINE2_Y, PW - 120, 30, "", INK, 17)

    -- 圆点
    for i = 1, #PAGES do
        dots[i] = rect(root, (i - (#PAGES + 1) / 2) * 20, -212, 9, 9, PAPER_EDGE, 255)
    end

    -- 按钮
    local bw, bh, bgap = 168, 50, 18
    btnPrev = utils.createButton(-(bw + bgap) / 2, -246, bw, bh, root, {
        text = "上一页", fontSize = 18,
        bg = "E9DCC2", bgDown = "D3C2A2", textColor = "5B4A38",
        onClick = function() M.prev() end,
    })
    btnNext = utils.createButton((bw + bgap) / 2, -246, bw, bh, root, {
        text = "下一页", fontSize = 18,
        bg = ACCENT, bgDown = "A34E2E", textColor = "FFF6E8",
        onClick = function() M.next() end,
    })
    if btnPrev then
        utils.raise(btnPrev.base); utils.raise(btnPrev.label); utils.raise(btnPrev.hit)
    end
    if btnNext then
        utils.raise(btnNext.base); utils.raise(btnNext.label); utils.raise(btnNext.hit)
    end

    return true
end

-- ================================================================
-- 翻页
-- ================================================================
local function refreshPage()
    local page = PAGES[pageIndex]
    if not page then return end
    if titleText then utils.setText(titleText, page.title) end
    if captionText then utils.setText(captionText, page.caption or "") end
    if pageText then utils.setText(pageText, pageIndex .. " / " .. #PAGES) end
    for i = 1, 2 do
        if bodyText[i] then utils.setText(bodyText[i], page.lines[i] or "") end
    end
    for i = 1, #dots do
        local on = (i == pageIndex)
        utils.setColor(dots[i], on and ACCENT or PAPER_EDGE, 255)
        utils.setSize(dots[i], on and 12 or 9, on and 12 or 9)
    end
    if btnPrev then utils.setButtonEnabled(btnPrev, pageIndex > 1) end
    if btnNext then
        utils.setText(btnNext.label, (pageIndex >= #PAGES) and "开始修复" or "下一页")
    end
    buildDiagram(page)
end

function M.setPage(i)
    if i < 1 then i = 1 end
    if i > #PAGES then i = #PAGES end
    pageIndex = i
    refreshPage()
end

function M.next()
    if pageIndex >= #PAGES then M.close() return end
    M.setPage(pageIndex + 1)
end

function M.prev()
    if pageIndex <= 1 then return end
    M.setPage(pageIndex - 1)
end

-- ================================================================
-- 开关
-- ================================================================
function M.open(startPage)
    if not root then return false end
    pageIndex = startPage or 1
    state.guideOpen = true
    utils.setVisible(root, true)
    utils.raise(root)
    refreshPage()

    -- 入场：整卷从 0.94 弹到 1
    utils.setScale(root, 0.94)
    anim.tween(0.24, function(p)
        utils.setScale(root, 0.94 + 0.06 * anim.Ease.outBack(p))
    end, { ease = "linear", tag = TAG, onDone = function() utils.setScale(root, 1) end })
    audio.playOpen()
    return true
end

function M.close(silent)
    if not root then return false end
    state.guideOpen = false
    utils.setVisible(root, false)
    utils.setScale(root, 1)
    if not silent then
        state.tutorialDone = true
        local cb = actions.onClose
        if cb then pcall(cb) end
    end
    return true
end

function M.isOpen()
    return state.guideOpen == true
end

-- ================================================================
-- 引导高亮：脉动金环 + 下滑箭头（场景坐标）
-- ================================================================
function M.setHint(x, y, size)
    if not state.containerGuide then return end
    if not hintRoot then
        hintRoot = utils.createContainer(state.containerGuide)
        if not hintRoot then return end
        hintBars = {}
        local th = 5
        local S = 78
        local half = S / 2 - th / 2
        local run = S - th * 2
        local spec = {
            { 0, half, S, th }, { 0, -half, S, th },
            { -half, 0, th, run }, { half, 0, th, run },
        }
        for i = 1, 4 do
            local p = spec[i]
            local c = utils.createControl(state.rectPrefabId, p[1], p[2], p[3], p[4],
                utils.hexToColorA(RING, 255), hintRoot)
            if c then utils.raise(c); hintBars[#hintBars + 1] = c end
        end
        -- 箭头（三根逐渐变窄的横条，像像素箭头）
        hintArrow = {}
        for i = 1, 3 do
            local c = utils.createControl(state.rectPrefabId, 0, 44 + i * 5, 30 - i * 8, 6,
                utils.hexToColorA(GOLD, 235), hintRoot)
            if c then utils.raise(c); hintArrow[#hintArrow + 1] = c end
        end
    end
    hintOn = true
    utils.setVisible(hintRoot, true)
    utils.raise(hintRoot)
    hintBase = (size or 60) / 78
    utils.setScale(hintRoot, hintBase)
    utils.setPos(hintRoot, x, y)
end

function M.clearHint()
    hintOn = false
    if hintRoot then utils.setVisible(hintRoot, false) end
end

function M.update(dt)
    if not hintOn or not hintRoot then return end
    hintPulse = hintPulse + dt
    local s = 1 + 0.07 * math.sin(hintPulse * 6.0)
    utils.setScale(hintRoot, hintBase * s)
    -- 箭头上下轻跳
    local bob = 4 * math.sin(hintPulse * 6.0)
    for i = 1, #hintArrow do
        utils.setPos(hintArrow[i], 0, 44 + i * 5 + bob)
    end
end

-- ================================================================
-- 对外
-- ================================================================
M.PAGES = PAGES
M.pageCount = #PAGES

return M
