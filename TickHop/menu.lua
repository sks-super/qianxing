-- ================================================================
-- TickHop 菜单与结算面板
--   三种模式复用同一批控件（一次性创建，之后只改文字与显隐）：
--     select —— 选关：关卡卡片网格 + 分页
--     win    —— 通关：剩余时间 + 「重玩本关 / 下一关」
--     fail   —— 失败：失败原因 + 「重玩本关 / 返回选关」
--
--   ★ 打开面板时冻结玩法（state.paused）并关闭玩法输入（state.keysEnabled），
--     键盘与点击统一走本模块。
--   ★ 关卡切换通过 setActions 注入的回调执行，避免与 game.lua 循环依赖。
--   ★ 面板挂在 containerMenu（HUD 之上、黑幕之下），因此关卡切换的黑幕
--     仍然能盖住面板，不会出现「黑幕下还露着半张结算界面」。
-- ================================================================

---@diagnostic disable: undefined-global

local M = {}
local state = require("state")
local config = require("config")
local utils = require("utils")

-- 由 game.lua 注入：{ onSelect = f(idx), onReload = f(), onNext = f() }
M.actions = {}

-- 网格布局缓存（init 时按关卡总数算一次）
M.grid = nil

-- ================================================================
-- 布局与查询
-- ================================================================

-- 面板尺寸：不超过配置值，且在画布内留出 40px 边距
local function panelSize()
    local cw = state.canvasW or config.DEFAULT_VIEW_WIDTH or 800
    local ch = state.canvasH or config.DEFAULT_VIEW_HEIGHT or 600
    local pw = math.min(config.DEFAULT_MENU_PANEL_W or 600, cw - 40)
    local ph = math.min(config.DEFAULT_MENU_PANEL_H or 420, ch - 40)
    if pw < 200 then pw = cw end
    if ph < 160 then ph = ch end
    return pw, ph
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

-- 返回 列数, 行数, 每页关卡数, 总页数
local function gridLayout()
    local total = math.max(1, config.getLevelCount())
    local maxCols = math.max(1, math.floor(config.DEFAULT_MENU_COLS or 4))
    local maxRows = math.max(1, math.floor(config.DEFAULT_MENU_ROWS or 2))
    local perPage = maxCols * maxRows
    local pages = math.max(1, math.ceil(total / perPage))
    local cols = math.min(maxCols, total)
    local rows = math.min(maxRows, math.ceil(total / cols))
    return cols, rows, perPage, pages
end

local function clampPage(p)
    local _, _, _, pages = gridLayout()
    p = math.floor(tonumber(p) or 1)
    if p < 1 then p = 1 end
    if p > pages then p = pages end
    return p
end

local function addNode(ctrl)
    if ctrl then
        state.menuNodes[#state.menuNodes + 1] = ctrl
    end
    return ctrl
end

-- ================================================================
-- 动作（供按钮与键盘共用）
-- ================================================================

local function doReload()
    M.close()
    if M.actions.onReload then M.actions.onReload() end
end

local function doNext()
    M.close()
    if M.actions.onNext then M.actions.onNext() end
end

local function doClose()
    M.close()
end

local function doBackToSelect()
    M.open("select")
end

-- 底部两个按钮的文案 / 动作；primary 决定是否用高亮色
local function buttonSpecs(mode)
    local reload = { text = "重玩本关", action = doReload }
    local nextLv = { text = "下一关 →", action = doNext, primary = true }
    local back   = { text = "返回选关", action = doBackToSelect }
    local resume = { text = "继续游戏", action = doClose, primary = true }

    if mode == "win" then
        if config.getLevelConfig((state.currentLevelIndex or 1) + 1) then
            return { reload, nextLv }
        end
        return { reload, back }
    elseif mode == "fail" then
        return { reload, back }
    end
    -- select：结算态下不提供「继续游戏」（否则会回到一个已经结束的画面）
    if state.gameWon or state.gameFailed then
        return { reload, back }
    end
    return { resume, reload }
end

-- ================================================================
-- 控件构造
-- ================================================================

local function makeButton(x, y, w, h, pal, slot, fontSize)
    local bg = addNode(utils.createControl(
        state.rectPrefabId, x, y, w, h,
        utils.hexToColor(pal.card), state.containerMenu))
    local label = addNode(utils.createText(
        x, y, w, h, "",
        utils.hexToColor(pal.panelText),
        fontSize or (config.DEFAULT_MENU_TEXT_SIZE or 24),
        state.containerMenu))
    if bg then
        pcall(function()
            bg:AddCursorEventListener(Enum.CursorEventType.CursorDown, function()
                M.invokeButton(slot)
            end)
        end)
    end
    return { bg = bg, label = label, action = nil }
end

-- 固定回调的按钮（分页用）
local function makeRawButton(x, y, w, h, text, onClick, pal, fontSize)
    local bg = addNode(utils.createControl(
        state.rectPrefabId, x, y, w, h,
        utils.hexToColor(pal.card), state.containerMenu))
    local label = addNode(utils.createText(
        x, y, w, h, text,
        utils.hexToColor(pal.panelText),
        fontSize or (config.DEFAULT_MENU_HINT_SIZE or 18),
        state.containerMenu))
    if bg then
        pcall(function()
            bg:AddCursorEventListener(Enum.CursorEventType.CursorDown, function()
                if state.menuOpen and onClick then onClick() end
            end)
        end)
    end
    return { bg = bg, label = label }
end

local function makeCard(x, y, w, h, pal, slot)
    local bg = addNode(utils.createControl(
        state.rectPrefabId, x, y, w, h,
        utils.hexToColor(pal.card), state.containerMenu))
    local label = addNode(utils.createText(
        x, y, w, h, "",
        utils.hexToColor(pal.panelText),
        config.DEFAULT_MENU_CARD_TEXT_SIZE or 20,
        state.containerMenu))
    if bg then
        pcall(function()
            bg:AddCursorEventListener(Enum.CursorEventType.CursorDown, function()
                M.invokeCard(slot)
            end)
        end)
    end
    return { bg = bg, label = label, index = 0 }
end

-- ================================================================
-- ★ 预创建（OnStart 调用一次）
-- ================================================================
function M.init()
    if state.menuPanel then return true end
    if not state.containerMenu then return false end
    if not state.rectPrefabId or state.rectPrefabId <= 0 then return false end

    local pal = utils.resolvePalette(state.currentLevelConfig)
    local pw, ph = panelSize()
    local cw = state.canvasW or config.DEFAULT_VIEW_WIDTH or 800
    local ch = state.canvasH or config.DEFAULT_VIEW_HEIGHT or 600
    local hintSize = config.DEFAULT_MENU_HINT_SIZE or 18
    local overlayAlpha = config.DEFAULT_MENU_OVERLAY_ALPHA or 215

    -- 全屏遮罩（比画布更大，避免边缘露缝）
    state.menuOverlay = addNode(utils.createControl(
        state.rectPrefabId, 0, 0, cw + 400, ch + 400,
        utils.hexToColorA(pal.overlay, overlayAlpha), state.containerMenu))

    -- 面板底
    state.menuPanel = addNode(utils.createControl(
        state.rectPrefabId, 0, 0, pw, ph,
        utils.hexToColor(pal.panel), state.containerMenu))

    -- 标题 / 副标题 / 底部操作提示
    state.menuTitle = addNode(utils.createText(
        0, ph / 2 - 54, pw - 40, 62, "",
        utils.hexToColor(pal.panelText), config.DEFAULT_MENU_TITLE_SIZE or 44,
        state.containerMenu))
    state.menuSubtitle = addNode(utils.createText(
        0, ph / 2 - 98, pw - 40, 34, "",
        utils.hexToColor(pal.dim), hintSize, state.containerMenu))
    state.menuFooter = addNode(utils.createText(
        0, -ph / 2 + 18, pw - 40, 26, "",
        utils.hexToColor(pal.dim), hintSize, state.containerMenu))

    -- ---- 选关卡片网格 ----
    local cols, rows, perPage = gridLayout()
    local cardW = config.DEFAULT_MENU_CARD_W or 118
    local cardH = config.DEFAULT_MENU_CARD_H or 54
    local gx = config.DEFAULT_MENU_CARD_GAP_X or 14
    local gy = config.DEFAULT_MENU_CARD_GAP_Y or 14
    M.grid = { cols = cols, rows = rows, perPage = perPage,
               cardW = cardW, cardH = cardH, gx = gx, gy = gy }

    local gridW = cols * cardW + (cols - 1) * gx
    local gridH = rows * cardH + (rows - 1) * gy
    -- 网格中心固定在这条「内容带」的中点：上方留给标题/副标题，下方留给按钮/提示
    local gridCY = 4
    for i = 1, cols * rows do
        local col = (i - 1) % cols
        local row = math.floor((i - 1) / cols)
        local x = -gridW / 2 + cardW / 2 + col * (cardW + gx)
        local y = gridCY + gridH / 2 - cardH / 2 - row * (cardH + gy)
        state.menuCards[i] = makeCard(x, y, cardW, cardH, pal, i)
    end

    -- ---- 分页：网格左右两侧的方形箭头（页码并进底部提示）----
    local pbw = config.DEFAULT_MENU_PAGE_BTN_W or 44
    local pbh = config.DEFAULT_MENU_PAGE_BTN_H or 44
    local pagerX = gridW / 2 + pbw / 2 + 4
    state.menuPagePrev = makeRawButton(-pagerX, gridCY, pbw, pbh, "←",
        function() M.setPage((state.menuPage or 1) - 1) end, pal, hintSize)
    state.menuPageNext = makeRawButton(pagerX, gridCY, pbw, pbh, "→",
        function() M.setPage((state.menuPage or 1) + 1) end, pal, hintSize)

    -- ---- 底部按钮 ----
    local by = -ph / 2 + 72
    local bw = config.DEFAULT_MENU_BTN_W or 200
    local bh = config.DEFAULT_MENU_BTN_H or 60
    local bgap = config.DEFAULT_MENU_BTN_GAP or 24
    state.menuButtons[1] = makeButton(-(bw + bgap) / 2, by, bw, bh, pal, 1)
    state.menuButtons[2] = makeButton((bw + bgap) / 2, by, bw, bh, pal, 2)

    M.close()
    return true
end

-- ================================================================
-- ★ 刷新（打开时 / 翻页 / 移动光标时调用）
--   只改文字与颜色，不重建控件。
-- ================================================================
function M.refresh()
    if not state.menuPanel then return end
    local pal = utils.resolvePalette(state.currentLevelConfig)
    local mode = state.menuMode or "select"
    local total = config.getLevelCount()
    local hintSize = config.DEFAULT_MENU_HINT_SIZE or 18

    -- 先全部显示，再按模式把不适用的藏起来
    for _, c in ipairs(state.menuNodes) do utils.setVisible(c, true) end

    utils.setAlpha(state.menuOverlay, pal.overlay, config.DEFAULT_MENU_OVERLAY_ALPHA or 215)
    utils.setAlpha(state.menuPanel, pal.panel, 255)

    -- ---- 标题 / 副标题 ----
    local title, subtitle
    if mode == "win" then
        title = "关卡完成！"
        subtitle = string.format("%s · 剩余 %s 秒",
            levelName(state.currentLevelIndex), utils.formatTime(state.winTimeLeft))
    elseif mode == "fail" then
        title = (state.failReason == "time_out") and "时间到！" or "掉出关卡了！"
        subtitle = levelName(state.currentLevelIndex)
    else
        title = "选择关卡"
        subtitle = string.format("共 %d 关 · 已通关 %d 关", total, clearedCount())
    end
    utils.setText(state.menuTitle, title)
    utils.setText(state.menuSubtitle, subtitle)
    utils.setTextColor(state.menuTitle,
        (mode == "fail") and (pal.danger or pal.panelText) or pal.panelText, 255)
    utils.setTextColor(state.menuSubtitle, pal.dim, 255)

    -- ---- 选关卡片 ----
    local grid = M.grid or {}
    local perPage = grid.perPage or 8
    local showGrid = (mode == "select")
    local page = clampPage(state.menuPage)
    state.menuPage = page
    local first = (page - 1) * perPage + 1

    for i, card in ipairs(state.menuCards) do
        local idx = first + i - 1
        if not showGrid or idx > total then
            utils.setVisible(card.bg, false)
            utils.setVisible(card.label, false)
            card.index = 0
        else
            local isCleared = state.clearedLevels[idx] == true
            local isCursor = (idx == state.menuCursor)
            local isCurrent = (idx == state.currentLevelIndex)
            local text = levelName(idx)
            -- ★ 用 √（U+221A）而非 ✓（U+2713）：中文字体普遍缺后者，会渲染成豆腐块
            if isCleared then text = text .. " √" end
            utils.setText(card.label, text)
            if isCursor then
                utils.setAlpha(card.bg, pal.accent, 255)
                utils.setTextColor(card.label, pal.accentText, 255)
            elseif isCurrent then
                utils.setAlpha(card.bg, pal.dim, 255)
                utils.setTextColor(card.label, pal.panel, 255)
            else
                utils.setAlpha(card.bg, pal.card, 255)
                utils.setTextColor(card.label, isCleared and pal.clear or pal.panelText, 255)
            end
            card.index = idx
        end
    end

    -- ---- 分页箭头（网格左右两侧）----
    local pages = grid.pages or 1
    local showPager = showGrid and pages > 1
    local function applyPager(btn)
        if not btn then return end
        utils.setVisible(btn.bg, showPager)
        utils.setVisible(btn.label, showPager)
        if showPager then
            utils.setAlpha(btn.bg, pal.card, 255)
            utils.setTextColor(btn.label, pal.panelText, 255)
        end
    end
    applyPager(state.menuPagePrev)
    applyPager(state.menuPageNext)

    -- ---- 底部操作提示（选关模式下带上页码）----
    local footer
    if mode == "win" then
        footer = "空格 / T 进入下一关　·　R 重玩本关"
    elseif mode == "fail" then
        footer = "R 重玩本关　·　L 打开选关"
    elseif showPager then
        footer = string.format("第 %d/%d 页　← → 选择　空格进入　L 关闭", page, pages)
    else
        footer = "← → 选择　空格进入　L 关闭"
    end
    utils.setText(state.menuFooter, footer)
    utils.setTextColor(state.menuFooter, pal.dim, 255)

    -- ---- 底部按钮 ----
    local specs = buttonSpecs(mode)
    for i, btn in ipairs(state.menuButtons) do
        local spec = specs[i]
        if not spec then
            utils.setVisible(btn.bg, false)
            utils.setVisible(btn.label, false)
            btn.action = nil
        else
            utils.setVisible(btn.bg, true)
            utils.setVisible(btn.label, true)
            utils.setText(btn.label, spec.text)
            btn.action = spec.action
            if spec.primary then
                utils.setAlpha(btn.bg, pal.accent, 255)
                utils.setTextColor(btn.label, pal.accentText, 255)
            else
                utils.setAlpha(btn.bg, pal.card, 255)
                utils.setTextColor(btn.label, pal.panelText, 255)
            end
        end
    end

    utils.setVisible(state.menuFooter, true)
end

-- ================================================================
-- ★ 点击分发
-- ================================================================
function M.invokeButton(slot)
    if not state.menuOpen then return end
    local btn = state.menuButtons[slot]
    if btn and btn.action then btn.action() end
end

function M.invokeCard(slot)
    if not state.menuOpen or state.menuMode ~= "select" then return end
    local card = state.menuCards[slot]
    if card and card.index and card.index >= 1 then
        state.menuCursor = card.index
        M.enterLevel(card.index)
    end
end

function M.enterLevel(idx)
    if not config.getLevelConfig(idx) then return false end
    M.close()
    if M.actions.onSelect then M.actions.onSelect(idx) end
    return true
end

-- ================================================================
-- ★ 开关
-- ================================================================
function M.isOpen()
    return state.menuOpen == true
end

function M.open(mode)
    if not state.menuPanel and not M.init() then return false end
    mode = mode or "select"
    state.menuMode = mode
    state.menuOpen = true
    state.paused = true
    state.keysEnabled = false

    if mode == "select" then
        local total = math.max(1, config.getLevelCount())
        local cur = math.floor(tonumber(state.currentLevelIndex) or 1)
        if cur < 1 then cur = 1 elseif cur > total then cur = total end
        state.menuCursor = cur
        local per = (M.grid and M.grid.perPage) or 8
        state.menuPage = clampPage(math.floor((cur - 1) / per) + 1)
    end

    M.refresh()
    return true
end

function M.close()
    state.menuOpen = false
    state.menuMode = nil
    state.paused = false
    -- 结算态下不恢复输入：此时应通过面板按钮进入下一步
    if not state.gameWon and not state.gameFailed then
        state.keysEnabled = true
    end
    for _, c in ipairs(state.menuNodes) do utils.setVisible(c, false) end
end

-- L 键：游戏中开/关选关；结算面板不允许直接关掉
function M.toggle(mode)
    if M.isOpen() then
        if state.gameWon or state.gameFailed then return false end
        M.close()
        return false
    end
    return M.open(mode or "select")
end

-- ================================================================
-- ★ 键盘交互
-- ================================================================
function M.setPage(p)
    if state.menuMode ~= "select" then return end
    local np = clampPage(p)
    if np == state.menuPage then return end
    state.menuPage = np
    local per = (M.grid and M.grid.perPage) or 8
    local total = math.max(1, config.getLevelCount())
    local cursor = (np - 1) * per + 1
    if cursor > total then cursor = total end
    state.menuCursor = cursor
    M.refresh()
end

function M.moveCursor(d)
    if state.menuMode ~= "select" then return end
    local total = math.max(1, config.getLevelCount())
    local per = (M.grid and M.grid.perPage) or 8
    local idx = (state.menuCursor or 1) + (d or 0)
    if idx < 1 then idx = total elseif idx > total then idx = 1 end
    state.menuCursor = idx
    state.menuPage = clampPage(math.floor((idx - 1) / per) + 1)
    M.refresh()
end

function M.confirm()
    local mode = state.menuMode
    if mode == "select" then
        M.enterLevel(state.menuCursor or 1)
    elseif mode == "win" then
        if config.getLevelConfig((state.currentLevelIndex or 1) + 1) then
            doNext()
        else
            doBackToSelect()
        end
    elseif mode == "fail" then
        doReload()
    end
end

function M.back()
    if state.menuMode == "select" then M.close() end
end

-- ================================================================
-- ★ 外部接口
-- ================================================================
function M.setActions(t)
    if type(t) == "table" then M.actions = t end
end

function M.markCleared(idx)
    idx = math.floor(tonumber(idx) or 0)
    if idx >= 1 then state.clearedLevels[idx] = true end
end

-- 触屏设备的常驻「选关」入口（挂在 HUD，不受面板显隐影响）
function M.createEntryButton()
    if state.menuEntryButton then return state.menuEntryButton end
    if not state.rectPrefabId or state.rectPrefabId <= 0 then return nil end
    local cw = state.canvasW or config.DEFAULT_VIEW_WIDTH or 800
    local ch = state.canvasH or config.DEFAULT_VIEW_HEIGHT or 600
    local pal = utils.resolvePalette(state.currentLevelConfig)
    local size = config.DEFAULT_TOUCH_BTN_SIZE or 88
    local margin = config.DEFAULT_TOUCH_BTN_MARGIN or 60
    local x = cw / 2 - margin
    local y = ch / 2 - margin

    local bg = utils.createControl(state.rectPrefabId, x, y, size, size,
        utils.hexToColorA(pal.accent, config.DEFAULT_TOUCH_BTN_ALPHA or 110),
        state.containerHud)
    local label = utils.createText(x, y, size, size, "关",
        utils.hexToColor(pal.accentText), 30, state.containerHud)
    if bg then
        pcall(function()
            bg:AddCursorEventListener(Enum.CursorEventType.CursorDown, function()
                M.toggle("select")
            end)
        end)
    end
    state.menuEntryButton = { bg = bg, label = label }
    return state.menuEntryButton
end

return M
