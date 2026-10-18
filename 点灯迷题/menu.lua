-- ================================================================
-- 点灯迷题 选关界面（夏日版 · 自适应放大 v2）
-- ================================================================
-- 50 关按「每页 COLS × ROWS 关」分页；每张卡片显示「关卡名 + 难度步数 + 难度条」，
-- **已通关的卡片带绿色底 + 绿色难度条 + 右上角 √ 徽标，步数行直接写「√ 已通关」**。
--
-- ★★ 尺寸完全由「可用空间」反推，而不是写死卡片尺寸：
--    面板尺寸 = 画布 × RATIO（再由 MAX 封顶）→ 定出卡片区上下留白比例
--    → 卡片高 = (可用高 - 行间距) / 行数。**行数/列数会自动退让**：
--    卡片太矮就少一行、太窄就少一列，永远保证每张卡片放得下两行字。
--    （为什么必须这样：真机文本框太矮会**一个字都不画**，见 utils.MIN_TEXT_H；
--      所以卡片高度不是「好看就行」，而是有硬下界 —— 底边要容得下两行 36px 的文本框。）
--
-- ★ 本模块是「进入关卡」的唯一发起点：点卡片 / 按空格 → 调 onEnter(关卡号)，
--   由 game.lua 负责发信号 + 切屏。
-- ★ 全部控件一次性创建，之后只改文字与颜色（不重建）。
--
-- ★★ 分层与 TickHop 一致：**只用 containerMenu 一个容器**，容器内按
--   「遮罩 → 面板 → 标题 → 卡片（底 → 难度条 → 关卡名 → 步数 → 徽标 → 点击区）
--    → 按钮」的创建顺序摆放。真机渲染规则是「后创建的在上」，
--   于是面板压在遮罩之上、文字压在卡片底之上、点击区在最后（吃得到光标）。
-- ================================================================

---@diagnostic disable: undefined-global

local M = {}
local state = require("default_import_file/state")
local config = require("default_import_file/config")
local utils = require("default_import_file/utils")
local fx = require("default_import_file/fx")

-- 由 game.lua 注入：{ onEnter = f(idx), onTutorial = f() }
M.actions = {}

local function addNode(ctrl)
    if ctrl then
        state.menuNodes[#state.menuNodes + 1] = ctrl
    end
    return ctrl
end

-- ================================================================
-- 布局：面板尺寸 / 放大系数 / 网格几何
-- ================================================================
local function panelSize()
    local cw = state.canvasW or config.DEFAULT_VIEW_WIDTH or 800
    local ch = state.canvasH or config.DEFAULT_VIEW_HEIGHT or 600
    local pw = cw * (config.DEFAULT_SELECT_PANEL_W_RATIO or 0.84)
    local ph = ch * (config.DEFAULT_SELECT_PANEL_H_RATIO or 0.94)
    pw = math.min(pw, config.DEFAULT_SELECT_PANEL_MAX_W or 1220)
    ph = math.min(ph, config.DEFAULT_SELECT_PANEL_MAX_H or 800)
    pw = math.min(pw, cw - 40)
    ph = math.min(ph, ch - 40)
    if pw < 240 then pw = cw end
    if ph < 200 then ph = ch end
    return pw, ph
end

-- ★ 一次算清所有几何。返回 table（顺便给 gridLayout 复用）。
local function layout()
    local pw, ph = panelSize()

    -- 放大系数 k：相对设计基准高（DEFAULT_SELECT_PANEL_H），字号 / 控件尺寸都乘它
    local k = ph / (config.DEFAULT_SELECT_PANEL_H or 500)
    if k < 0.80 then k = 0.80 end
    if k > 2.40 then k = 2.40 end

    local gx = (config.DEFAULT_SELECT_CARD_GAP_X or 14) * k
    local gy = (config.DEFAULT_SELECT_CARD_GAP_Y or 12) * k
    local gridTop = ph * (config.DEFAULT_SELECT_GRID_TOP_RATIO or 0.27)   -- 网格上方留给标题
    local gridBottom = ph * (config.DEFAULT_SELECT_GRID_BOTTOM_RATIO or 0.19) -- 下方留给按钮+页脚
    local availH = ph - gridTop - gridBottom

    -- 行数：先按「舒适高度」缩行（但不会缩到 3 行以下），再按「不重叠硬下界」兜底
    local prefH = config.DEFAULT_SELECT_CARD_PREF_H or 96
    local minH = config.DEFAULT_SELECT_CARD_MIN_H or 84
    local rows = math.max(1, math.floor(config.DEFAULT_SELECT_ROWS or 4))
    local cardH = (availH - (rows - 1) * gy) / rows
    while rows > 3 and cardH < prefH do
        rows = rows - 1
        cardH = (availH - (rows - 1) * gy) / rows
    end
    while rows > 1 and cardH < minH do
        rows = rows - 1
        cardH = (availH - (rows - 1) * gy) / rows
    end

    -- 列数：同理，卡片窄于下界就减一列
    local gridAreaW = pw * (config.DEFAULT_SELECT_GRID_W_RATIO or 0.80)
    local minW = config.DEFAULT_SELECT_CARD_MIN_W or 110
    local cols = math.max(2, math.floor(config.DEFAULT_SELECT_COLS or 5))
    local cardW = (gridAreaW - (cols - 1) * gx) / cols
    while cols > 2 and cardW < minW do
        cols = cols - 1
        cardW = (gridAreaW - (cols - 1) * gx) / cols
    end
    if cardW < 24 then cardW = 24 end
    if cardH < 24 then cardH = 24 end

    local perPage = cols * rows
    local total = math.max(1, config.getLevelCount())
    return {
        pw = pw, ph = ph, k = k,
        cols = cols, rows = rows, perPage = perPage,
        pages = math.max(1, math.ceil(total / perPage)),
        cardW = cardW, cardH = cardH, gx = gx, gy = gy,
        gridW = cols * cardW + (cols - 1) * gx,
        gridH = rows * cardH + (rows - 1) * gy,
        gridCY = (gridBottom - gridTop) / 2,
        gridTop = gridTop, gridBottom = gridBottom,
        topEdge = ph / 2 - gridTop,          -- 网格上沿
        bottomEdge = -ph / 2 + gridBottom,   -- 网格下沿
    }
end

local function gridLayout()
    local L = layout()
    return L.cols, L.rows, L.perPage, L.pages
end

local function clampPage(p)
    local _, _, _, pages = gridLayout()
    p = math.floor(tonumber(p) or 1)
    if p < 1 then p = 1 end
    if p > pages then p = pages end
    return p
end

local function levelName(idx)
    local d = config.getLevelConfig(idx)
    if d and type(d.name) == "string" and d.name ~= "" then return d.name end
    return string.format("第%02d关", idx)
end

local function clearedCount()
    local n = 0
    for _, v in pairs(state.clearedLevels or {}) do
        if v then n = n + 1 end
    end
    return n
end

-- ================================================================
-- 动作
-- ================================================================
local function doEnterCursor()
    M.enterLevel(state.menuCursor or 1)
end

local function doTutorial()
    if M.actions.onTutorial then M.actions.onTutorial() end
end

-- ================================================================
-- 控件构造
-- ================================================================
-- 卡片：底 → 难度条（轨 + 填） → 关卡名 → 步数 → √ 徽标 → 点击区
-- ★ 版式（相对卡片中心，世界单位）：
--     关卡名   y + 0.24h    左侧 2/3
--     步数行   y - 0.18h    左侧 2/3   ← 「N 步」或「√ 已通关」
--     √ 徽标   右上角（通关才显示）
--     难度条   y - 0.44h    贴下沿
--   两行文字中心相距 0.42h ⇒ 只要 h ≥ 84，两行 36px 文本框就不会叠在一起；
--   难度条再往下压到 -0.44h，避开被 MIN_TEXT_H 撑高的步数行盒子。
local function makeCard(x, y, w, h, pal, slot)
    local labSize = math.max(14, h * 0.30)
    local subSize = math.max(11, h * 0.21)
    local badgeSize = math.max(12, h * 0.24)
    local barH = math.max(6, h * 0.06)

    local bg = addNode(utils.createControl(state.rectPrefabId, x, y, w, h,
        utils.hexToColor(pal.card), state.containerMenu))

    local textW = w * 0.66
    local textDX = -w * 0.11
    local label = addNode(utils.createText(x + textDX, y + h * 0.24, textW, h * 0.38, "",
        utils.hexToColor(pal.text), labSize, state.containerMenu))
    local sub = addNode(utils.createText(x + textDX, y - h * 0.18, textW, h * 0.34, "",
        utils.hexToColor(pal.dim), subSize, state.containerMenu))
    -- ★ 已通关徽标（右上角）
    local badge = addNode(utils.createText(x + w / 2 - w * 0.14, y + h / 2 - h * 0.30,
        w * 0.22, h * 0.28, "√",
        utils.hexToColor(pal.ok), badgeSize, state.containerMenu))

    -- 难度条：轨道 + 填充（填充在轨道之后创建 ⇒ 压在上面）
    -- ★ 条的 y 取「-0.44h」与「步数行盒子下沿再留 2」中更靠下的一个：
    --   步数行的盒子会被 utils.MIN_TEXT_H 兜高（矮卡片上尤其明显），
    --   按给定高度算的位置会和它打架，这样取就不会重叠。
    local textMinH = utils.MIN_TEXT_H or 36
    local subBoxH = math.max(textMinH, h * 0.34)
    local barW = w * 0.72
    local barY = y - h * 0.44
    local barLimit = (y - h * 0.18) - subBoxH / 2 - 2 - barH / 2
    if barLimit < barY then barY = barLimit end
    local barTrack = addNode(utils.createControl(state.rectPrefabId, x, barY, barW, barH,
        utils.hexToColor(pal.panelDeep), state.containerMenu))
    local barFill = addNode(utils.createControl(state.rectPrefabId, x, barY, 6, barH,
        utils.hexToColor(pal.accent), state.containerMenu))

    local hit = utils.createHit(x, y, w, h, state.containerMenu, nil, bg)
    if hit then
        state.menuNodes[#state.menuNodes + 1] = hit
        pcall(function()
            hit:AddCursorEventListener(Enum.CursorEventType.CursorDown, function()
                M.invokeCard(slot)
            end)
        end)
        utils.bindHover(hit,
            function()
                pcall(function() bg:SetSizeDelta(w + 8, h + 8) end)
            end,
            function()
                pcall(function() bg:SetSizeDelta(w, h) end)
            end)
    end
    return { bg = bg, label = label, sub = sub, badge = badge, hit = hit,
             barTrack = barTrack, barFill = barFill,
             barX = x, barY = barY, barW = barW, barH = barH, index = 0,
             baseW = w, baseH = h }
end

-- 通用按钮：底 → 字 → 点击区
local function makeButton(x, y, w, h, text, pal, fontSize, onPress, enabledCheck)
    local bg = addNode(utils.createControl(state.rectPrefabId, x, y, w, h,
        utils.hexToColor(pal.card), state.containerMenu))
    local label = addNode(utils.createText(x, y, w, h, text,
        utils.hexToColor(pal.text), fontSize, state.containerMenu))
    local hit = utils.createHit(x, y, w, h, state.containerMenu, nil, bg)
    if hit then
        state.menuNodes[#state.menuNodes + 1] = hit
        pcall(function()
            hit:AddCursorEventListener(Enum.CursorEventType.CursorDown, function()
                if enabledCheck and not enabledCheck() then return end
                fx.spawn(x, y, { n = 10, keys = { "juice1", "juice2", "juice4" },
                                 speed = 240, life = 0.5, size = 8 })
                if onPress then onPress() end
            end)
        end)
        utils.bindHover(hit,
            function()
                if enabledCheck and not enabledCheck() then return end
                pcall(function() bg:SetSizeDelta(w + 7, h + 7) end)
            end,
            function()
                pcall(function() bg:SetSizeDelta(w, h) end)
            end)
    end
    return { bg = bg, label = label, hit = hit, baseW = w, baseH = h }
end

-- ================================================================
-- ★ 预创建（OnStart 调用一次）
-- ================================================================
function M.init()
    if state.menuPanel then return true end
    if not state.containerMenu then return false end
    if not state.rectPrefabId or state.rectPrefabId <= 0 then return false end

    local pal = utils.resolvePalette(state.currentLevelConfig)
    local L = layout()
    local pw, ph, k = L.pw, L.ph, L.k
    state.selectGrid = { cols = L.cols, rows = L.rows, perPage = L.perPage,
                         pages = L.pages, cardW = L.cardW, cardH = L.cardH,
                         gx = L.gx, gy = L.gy, k = k, gridCY = L.gridCY }

    local hintSize = (config.DEFAULT_SELECT_HINT_SIZE or 16) * k
    local titleSize = (config.DEFAULT_SELECT_TITLE_SIZE or 40) * k
    local btnSize = (config.DEFAULT_SELECT_TEXT_SIZE or 20) * k
    local hintBoxH = math.max(36, hintSize * 2.2)
    local titleBoxH = math.max(36, titleSize * 1.7)

    -- ① 全屏遮罩（比画布更大，避免边缘露缝）
    state.menuOverlay = addNode(utils.createControl(state.rectPrefabId, 0, 0, L.pw + 900, L.ph + 900,
        utils.hexToColorA(pal.overlay, config.DEFAULT_SELECT_OVERLAY_ALPHA or 160),
        state.containerMenu))

    -- ② 面板投影 + 描边 + 面板底
    state.menuPanelShadow = addNode(utils.createControl(state.rectPrefabId, 7 * k, -9 * k, pw, ph,
        utils.hexToColorA(pal.shadow, 120), state.containerMenu))
    state.menuPanelEdge = addNode(utils.createControl(state.rectPrefabId, 0, 0, pw + 14 * k, ph + 14 * k,
        utils.hexToColor(pal.line), state.containerMenu))
    state.menuPanel = addNode(utils.createControl(state.rectPrefabId, 0, 0, pw, ph,
        utils.hexToColor(pal.panel), state.containerMenu))

    -- ③ 面板顶部装饰：一条橙汁横带 + 右上三颗小气泡
    addNode(utils.createControl(state.rectPrefabId, 0, ph / 2 - 10 * k, pw - 44 * k, 10 * k,
        utils.hexToColor(pal.accent), state.containerMenu))
    for i = 1, 3 do
        local d = (10 + i * 4) * k
        addNode(utils.createControl(state.rectPrefabId,
            pw / 2 - (26 + i * 22) * k, ph / 2 - (34 + (i % 2) * 10) * k, d, d,
            utils.hexToColorA(pal.juice2, 190 - i * 40), state.containerMenu))
    end

    -- ④ 标题 / 副标题 / 页脚（位置按「网格上沿 / 下沿」反推，不再用固定偏移）
    local subCY = L.topEdge + 10 + hintBoxH / 2
    local titleCY = subCY + hintBoxH / 2 + 10 + titleBoxH / 2
    state.menuTitle = addNode(utils.createText(0, titleCY, pw - 60 * k, titleBoxH, "点灯迷题",
        utils.hexToColor(pal.accent), titleSize, state.containerMenu))
    state.menuSubtitle = addNode(utils.createText(0, subCY, pw - 60 * k, hintBoxH, "",
        utils.hexToColor(pal.dim), hintSize, state.containerMenu))
    state.menuFooter = addNode(utils.createText(0, -ph / 2 + 12 + hintBoxH / 2, pw - 24 * k, hintBoxH, "",
        utils.hexToColor(pal.dim), hintSize, state.containerMenu))

    -- ⑤ 关卡卡片网格（尺寸由可用空间算出）
    for i = 1, L.perPage do
        local col = (i - 1) % L.cols
        local row = math.floor((i - 1) / L.cols)
        local x = -L.gridW / 2 + L.cardW / 2 + col * (L.cardW + L.gx)
        local y = L.gridCY + L.gridH / 2 - L.cardH / 2 - row * (L.cardH + L.gy)
        state.menuCards[i] = makeCard(x, y, L.cardW, L.cardH, pal, i)
    end

    -- ⑥ 分页箭头（面板左右两侧）
    local pbw = (config.DEFAULT_SELECT_PAGE_BTN_W or 46) * k
    local pbh = (config.DEFAULT_SELECT_PAGE_BTN_H or 46) * k
    local pagerX = pw / 2 - pbw / 2 - 12 * k
    local function pageEnabledCheck()
        return function() return state.screen == "select" and not state.tutorialOpen and not state.winOpen end
    end
    state.menuPagePrev = makeButton(-pagerX, L.gridCY, pbw, pbh, "←", pal, 24 * k,
        function() M.setPage((state.menuPage or 1) - 1) end, pageEnabledCheck())
    state.menuPageNext = makeButton(pagerX, L.gridCY, pbw, pbh, "→", pal, 24 * k,
        function() M.setPage((state.menuPage or 1) + 1) end, pageEnabledCheck())

    -- ⑦ 底部按钮：左「教程 / 玩法」、右「进入关卡 →」
    local bw = (config.DEFAULT_SELECT_BTN_W or 186) * k
    local bh = (config.DEFAULT_SELECT_BTN_H or 54) * k
    local bgap = (config.DEFAULT_SELECT_BTN_GAP or 22) * k
    local footCY = -ph / 2 + 12 + hintBoxH / 2
    local btnCY = footCY + hintBoxH / 2 + 10 + bh / 2
    local function selectEnabledCheck()
        return state.screen == "select" and not state.tutorialOpen and not state.winOpen
    end
    state.menuButtons[1] = makeButton(-(bw + bgap) / 2, btnCY, bw, bh, "教程 / 玩法", pal,
        btnSize, doTutorial, selectEnabledCheck)
    state.menuButtons[2] = makeButton((bw + bgap) / 2, btnCY, bw, bh, "进入关卡 →", pal,
        btnSize, doEnterCursor, selectEnabledCheck)

    M.setVisible(false)
    return true
end

-- ================================================================
-- ★ 刷新（打开 / 翻页 / 移动光标时调用）：只改文字与颜色
-- ================================================================
function M.refresh()
    if not state.menuPanel then return end
    local pal = utils.resolvePalette(state.currentLevelConfig)
    local total = config.getLevelCount()
    local grid = state.selectGrid or {}
    local perPage = grid.perPage or 20
    local pages = grid.pages or 1
    local page = clampPage(state.menuPage)
    state.menuPage = page
    local first = (page - 1) * perPage + 1

    utils.setText(state.menuSubtitle, string.format("共 %d 关 · 已通关 %d 关", total, clearedCount()))
    utils.setTextColor(state.menuSubtitle, pal.dim, 255)
    utils.setTextColor(state.menuTitle, pal.accent, 255)
    utils.setAlpha(state.menuPanel, pal.panel, 255)
    utils.setAlpha(state.menuPanelShadow, pal.shadow, 120)
    utils.setAlpha(state.menuPanelEdge, pal.line, 255)

    -- 卡片
    local maxSteps = math.max(1, config.getMaxSteps())
    for i, card in ipairs(state.menuCards) do
        local idx = first + i - 1
        if idx > total then
            utils.setVisible(card.bg, false)
            utils.setVisible(card.label, false)
            utils.setVisible(card.sub, false)
            utils.setVisible(card.badge, false)
            utils.setVisible(card.barTrack, false)
            utils.setVisible(card.barFill, false)
            utils.setVisible(card.hit, false)
            card.index = 0
            card.isCursor = false
        else
            local d = config.getLevelConfig(idx)
            local steps = math.floor(tonumber(d and d.steps) or 0)
            local isCleared = state.clearedLevels[idx] == true
            local isCursor = (idx == state.menuCursor)
            local isCurrent = (idx == state.currentLevelIndex)
            utils.setVisible(card.bg, true)
            utils.setVisible(card.label, true)
            utils.setVisible(card.sub, true)
            utils.setVisible(card.barTrack, true)
            utils.setVisible(card.barFill, true)
            utils.setVisible(card.hit, true)
            utils.setText(card.label, levelName(idx))
            -- ★ 步数行直接写明通关状态：已通关显示「√ 已通关」，否则显示「N 步」
            utils.setText(card.sub, isCleared and "√ 已通关" or string.format("%d 步", steps))
            utils.setVisible(card.badge, isCleared)

            -- 难度条：填充宽度按步数归一化
            local barH = card.barH or math.max(6, card.baseH * 0.06)
            local fillW = math.max(6, card.barW * steps / maxSteps)
            local fillX = card.barX - (card.barW - fillW) / 2
            pcall(function()
                card.barFill:SetSizeDelta(fillW, barH)
                card.barFill:SetAnchoredPosition(fillX, card.barY)
            end)
            local trackKey, fillKey
            if isCursor then
                utils.setAlpha(card.bg, pal.accent, 255)
                utils.setTextColor(card.label, pal.accentText, 255)
                utils.setTextColor(card.sub, pal.accentText, 235)
                utils.setTextColor(card.badge, pal.accentText, 255)
                -- ★ 选中卡：轨道用浅色底、填充用深色，难度条仍然读得出来
                trackKey, fillKey = pal.card, pal.accentText
            elseif isCurrent then
                utils.setAlpha(card.bg, pal.line, 255)
                utils.setTextColor(card.label, pal.text, 255)
                utils.setTextColor(card.sub, pal.ok, 255)
                utils.setTextColor(card.badge, pal.ok, 255)
                trackKey, fillKey = pal.panelDeep, pal.ok
            elseif isCleared then
                -- ★ 已通关：整卡淡绿底 + 绿色文字 + 绿色难度条（一眼能扫出来）
                utils.setAlpha(card.bg, pal.ok, 84)
                utils.setTextColor(card.label, pal.text, 255)
                utils.setTextColor(card.sub, pal.ok, 255)
                utils.setTextColor(card.badge, pal.ok, 255)
                trackKey = pal.card
                fillKey = pal.ok
            else
                utils.setAlpha(card.bg, pal.card, 255)
                utils.setTextColor(card.label, pal.text, 255)
                utils.setTextColor(card.sub, pal.dim, 255)
                utils.setTextColor(card.badge, pal.ok, 255)
                trackKey = pal.panelDeep
                fillKey = pal.accent
            end
            utils.setAlpha(card.barTrack, trackKey, isCursor and 110 or 220)
            utils.setAlpha(card.barFill, fillKey, 255)
            card.index = idx
            card.isCursor = isCursor
        end
    end

    -- 分页箭头
    local showPager = pages > 1
    local function applyPager(btn, enabled)
        if not btn then return end
        utils.setVisible(btn.bg, showPager)
        utils.setVisible(btn.label, showPager)
        utils.setVisible(btn.hit, showPager)
        if showPager then
            utils.setAlpha(btn.bg, enabled and pal.card or pal.panelDeep, 255)
            utils.setTextColor(btn.label, enabled and pal.text or pal.line, 255)
        end
    end
    applyPager(state.menuPagePrev, page > 1)
    applyPager(state.menuPageNext, page < pages)

    -- 底部按钮
    local b1 = state.menuButtons[1]
    local b2 = state.menuButtons[2]
    if b1 then
        utils.setVisible(b1.bg, true); utils.setVisible(b1.label, true); utils.setVisible(b1.hit, true)
        utils.setAlpha(b1.bg, pal.panelDeep, 255)
        utils.setTextColor(b1.label, pal.text, 255)
        utils.setText(b1.label, "教程 / 玩法")
    end
    if b2 then
        utils.setVisible(b2.bg, true); utils.setVisible(b2.label, true); utils.setVisible(b2.hit, true)
        utils.setAlpha(b2.bg, pal.accent, 255)
        utils.setTextColor(b2.label, pal.accentText, 255)
        utils.setText(b2.label, "进入关卡 →")
    end

    -- 页脚
    local footer
    if showPager then
        footer = string.format("第 %d/%d 页 · 方向键选择 · 空格进入 · T 教程", page, pages)
    else
        footer = "方向键选择 · 空格进入 · T 教程"
    end
    utils.setText(state.menuFooter, footer)
    utils.setTextColor(state.menuFooter, pal.dim, 255)

    -- 入场进度：k=0 起手，由 update 往上爬（避免「先满亮一帧」）
    if state.menuAnimT and state.menuAnimT < (config.DEFAULT_ANIM_POP_TIME or 0.34) then
        M.applyIntro(state.menuAnimT / (config.DEFAULT_ANIM_POP_TIME or 0.34))
    end
end

-- ================================================================
-- ★ 入场进度 k（0..1）：遮罩淡入 + 面板从小弹到大
-- ================================================================
function M.applyIntro(k)
    if k < 0 then k = 0 elseif k > 1 then k = 1 end
    local pal = utils.resolvePalette(state.currentLevelConfig)
    local pw, ph = panelSize()
    local s0 = (state.selectGrid and state.selectGrid.k) or 1
    local u = 1 - k
    local e = 1 - u * u
    local e2 = 1 - u * u * u            -- 略带回弹的手感
    local s = 0.90 + 0.10 * e2
    utils.setAlpha(state.menuOverlay, pal.overlay, (config.DEFAULT_SELECT_OVERLAY_ALPHA or 140) * e)
    utils.setAlpha(state.menuPanel, pal.panel, 255 * e)
    utils.setAlpha(state.menuPanelShadow, pal.shadow, 120 * e)
    utils.setAlpha(state.menuPanelEdge, pal.line, 255 * e)
    utils.setSize(state.menuPanel, pw * s, ph * s)
    utils.setPos(state.menuPanel, 0, -20 * s0 * u)
    utils.setSize(state.menuPanelEdge, (pw + 14 * s0) * s, (ph + 14 * s0) * s)
    utils.setPos(state.menuPanelEdge, 0, -20 * s0 * u)
    utils.setSize(state.menuPanelShadow, pw * s, ph * s)
    utils.setPos(state.menuPanelShadow, 7 * s0, -9 * s0 - 20 * s0 * u)
end

-- ================================================================
-- ★ 每帧：入场推进 + 选中卡片的呼吸难度条
-- ================================================================
function M.update(dt)
    if not state.menuPanel or not state.menuOpen then return end
    dt = tonumber(dt) or 0
    if dt <= 0 then return end
    local dur = config.DEFAULT_ANIM_POP_TIME or 0.34
    if (state.menuAnimT or 0) < dur then
        state.menuAnimT = math.min(dur, (state.menuAnimT or 0) + dt)
        M.applyIntro(state.menuAnimT / dur)
    end
    -- 选中卡片的难度条轨道轻微呼吸（颜色与 refresh 里选的浅色底一致），画面不死板
    local pulse = 0.5 + 0.5 * math.sin((state.fxTime or 0) * 4.2)
    local pal = utils.resolvePalette(state.currentLevelConfig)
    for _, card in ipairs(state.menuCards) do
        if card.isCursor and card.barTrack then
            utils.setAlpha(card.barTrack, pal.card, 80 + 70 * pulse)
        end
    end
end

-- ================================================================
-- ★ 点击分发
-- ================================================================
function M.invokeCard(slot)
    if state.screen ~= "select" then return end
    if state.tutorialOpen or state.winOpen then return end
    local card = state.menuCards[slot]
    if card and card.index and card.index >= 1 then
        state.menuCursor = card.index
        M.enterLevel(card.index)
    end
end

function M.invokeButton(slot)
    if state.screen ~= "select" then return end
    if state.tutorialOpen or state.winOpen then return end
    if slot == 1 then
        doTutorial()
    elseif slot == 2 then
        doEnterCursor()
    end
end

-- 请求进入某关（真正切屏与发信号由 game.lua 的回调完成）
function M.enterLevel(idx)
    if not config.getLevelConfig(idx) then return false end
    if M.actions.onEnter then M.actions.onEnter(idx) end
    return true
end

-- ================================================================
-- ★ 显隐 / 开关
-- ================================================================
function M.setVisible(v)
    state.menuOpen = v and true or false
    utils.setVisibleAll(state.menuNodes, v)
    if v then
        state.menuAnimT = 0
        M.applyIntro(0)
        -- 打开时在标题附近崩一把果汁，给一点「夏日清凉」的开场
        local _, ph = panelSize()
        local k = state.selectGrid and state.selectGrid.k or 1
        fx.spawn(0, ph / 2 - 30 * k, { n = 18, keys = { "juice1", "juice2", "juice4", "juice3" },
                                       dir = 270, spread = 140, speed = 300, life = 0.7, size = 10 })
    else
        fx.cancelAll()
    end
end

function M.isVisible()
    return state.menuOpen == true
end

function M.setActions(t)
    if type(t) == "table" then M.actions = t end
end

function M.markCleared(idx)
    idx = math.floor(tonumber(idx) or 0)
    if idx >= 1 then state.clearedLevels[idx] = true end
end

function M.isCleared(idx)
    return state.clearedLevels[math.floor(tonumber(idx) or 0)] == true
end

-- ================================================================
-- ★ 键盘交互
-- ================================================================
function M.setPage(p)
    if state.screen ~= "select" then return end
    local np = clampPage(p)
    if np == state.menuPage then return end
    state.menuPage = np
    -- 翻页后把光标落到本页第一关，避免光标停在别的页上
    local per = (state.selectGrid and state.selectGrid.perPage) or 20
    local total = math.max(1, config.getLevelCount())
    local cursor = (np - 1) * per + 1
    if cursor > total then cursor = total end
    state.menuCursor = cursor
    M.refresh()
end

-- dx: -1 左 / +1 右；dy: +1 上 / -1 下（一次跨一整行）
--   左右到边界时循环到另一端；上下到边界时停住（比循环更可预期）。
function M.moveCursor(dx, dy)
    if state.screen ~= "select" then return end
    local total = math.max(1, config.getLevelCount())
    local grid = state.selectGrid or {}
    local per = grid.perPage or 20
    local cols = grid.cols or 5
    local idx = state.menuCursor or 1
    if dx and dx ~= 0 then
        idx = idx + dx
        if idx < 1 then idx = total elseif idx > total then idx = 1 end
    end
    if dy and dy ~= 0 then
        local cand = idx - dy * cols
        if cand >= 1 and cand <= total then idx = cand end
    end
    state.menuCursor = idx
    state.menuPage = clampPage(math.floor((idx - 1) / per) + 1)
    M.refresh()
end

function M.confirm()
    if state.screen ~= "select" then return end
    doEnterCursor()
end

return M
