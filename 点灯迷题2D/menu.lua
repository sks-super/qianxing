-- ================================================================
-- 点灯迷题 2D · 选关界面
--   50 关分页网格（5 列 × 4 行 = 每页 20 关），卡片带星级。
--
--   动效：
--   · 打开：遮罩淡入 → 面板轻微放大落定 → 卡片按「左上→右下」错峰弹出
--   · 翻页：整页横向滑入 + 卡片再次错峰弹出
--   · 卡片：按下微缩，选中格描边变强调色
-- ================================================================

---@diagnostic disable: undefined-global

local M = {}

local state = require("default_import_file/state")
local config = require("default_import_file/config")
local utils = require("default_import_file/utils")
local anim = require("default_import_file/anim")

local TAG_MENU = "menu:main"
local TAG_CARD = "menu:card"

local actions = {}

function M.setActions(a)
    actions = a or {}
end

local function perPage()
    return (config.DEFAULT_SELECT_COLS or 5) * (config.DEFAULT_SELECT_ROWS or 4)
end

local function pageCount()
    local n = config.levelCount()
    local pp = perPage()
    return math.max(1, math.ceil(n / pp))
end

function M.pageCount()
    return pageCount()
end

-- ================================================================
-- 建（只建一次）
-- ================================================================
function M.init()
    local par = state.containerMenu
    if not par or (state.rectPrefabId or 0) <= 0 then return false end

    local pal = config.DEFAULT_PALETTE or {}
    local W = config.DEFAULT_SELECT_PANEL_W or 1040
    local H = config.DEFAULT_SELECT_PANEL_H or 640

    -- 全屏遮罩（压暗背后的游玩画面）
    M.scrim = utils.createControl(state.rectPrefabId, 0, 0,
        (state.canvasW or 1280) + 40, (state.canvasH or 720) + 40,
        utils.hexToColorA(pal.scrim or "05070F", 0), par)
    M.scrimHit = utils.createHit(0, 0, (state.canvasW or 1280) + 40, (state.canvasH or 720) + 40, par, true)

    -- 面板
    M.edge = utils.createControl(state.rectPrefabId, 0, 0, W + 4, H + 4,
        utils.hexToColor(pal.panelEdge or "1E2A47"), par)
    M.panel = utils.createControl(state.rectPrefabId, 0, 0, W, H,
        utils.hexToColor(pal.panel or "121A2E"), par)
    M.inner = utils.createControl(state.rectPrefabId, 0, 0, W - 24, H - 24,
        utils.hexToColor(pal.boardBg or "0F1730"), par)

    M.title = utils.createText(0, H / 2 - 58, W - 160, 56, "点灯迷题",
        utils.hexToColor(pal.text or "E9F0FF"), config.DEFAULT_SELECT_TITLE_SIZE or 40, par)
    M.sub = utils.createText(0, H / 2 - 104, W - 160, 28, "",
        utils.hexToColor(pal.textDim or "8296B8"), 18, par)

    -- 返回按钮
    M.btnClose = utils.createButton(W / 2 - 64, H / 2 - 56, 96, 40, par, {
        text = "返回", fontSize = 18,
        bg = pal.btn, bgDown = pal.btnDown, textColor = pal.btnText,
        onClick = function() if actions.onClose then actions.onClose() end end,
    })

    -- 翻页箭头
    local gridW = (config.DEFAULT_SELECT_COLS or 5) * (config.DEFAULT_SELECT_CARD_W or 150)
                + ((config.DEFAULT_SELECT_COLS or 5) - 1) * (config.DEFAULT_SELECT_CARD_GAP_X or 16)
    local ax = gridW / 2 + 46
    M.btnPrev = utils.createButton(-ax, -46, 44, 76, par, {
        text = "←", fontSize = 26,
        bg = pal.btn, bgDown = pal.btnDown, textColor = pal.btnText,
        onClick = function() M.turn(-1) end,
    })
    M.btnNext = utils.createButton(ax, -46, 44, 76, par, {
        text = "→", fontSize = 26,
        bg = pal.btn, bgDown = pal.btnDown, textColor = pal.btnText,
        onClick = function() M.turn(1) end,
    })

    M.dots = utils.createText(0, -H / 2 + 34, W - 200, 26, "",
        utils.hexToColor(pal.textDim or "8296B8"), 16, par)

    -- 卡片容器（翻页时整体横移）
    M.grid = utils.createContainer(par)
    if M.grid then utils.setPos(M.grid, 0, -46) end

    M.cards = {}

    -- ★ 一次性定层（底 → 顶）。创建顺序在两个引擎里渲染方向相反，
    --   所以不能靠「谁后建谁在上」，必须显式排一次。
    utils.applyLayerOrder({
        M.scrim, M.scrimHit, M.edge, M.panel, M.inner,
        M.title, M.sub, M.btnClose, M.btnPrev, M.btnNext, M.dots, M.grid,
    })

    M.setVisible(false)
    return true
end

-- ================================================================
-- 卡片
-- ================================================================
local function destroyCards()
    for i = 1, #M.cards do
        local c = M.cards[i]
        utils.destroy(c.base)
        utils.destroy(c.num)
        for j = 1, #c.stars do utils.destroy(c.stars[j]) end
        utils.destroy(c.hit)
    end
    M.cards = {}
end

local function buildCards(page)
    destroyCards()
    if not M.grid then return end

    local pal = config.DEFAULT_PALETTE or {}
    local cols = config.DEFAULT_SELECT_COLS or 5
    local rows = config.DEFAULT_SELECT_ROWS or 4
    local cw = config.DEFAULT_SELECT_CARD_W or 150
    local ch = config.DEFAULT_SELECT_CARD_H or 96
    local gx = config.DEFAULT_SELECT_CARD_GAP_X or 16
    local gy = config.DEFAULT_SELECT_CARD_GAP_Y or 16
    local total = config.levelCount()
    local pp = perPage()
    local first = (page - 1) * pp + 1

    local gw = cols * cw + (cols - 1) * gx
    local gh = rows * ch + (rows - 1) * gy
    local x0 = -gw / 2 + cw / 2
    local y0 = gh / 2 - ch / 2

    for slot = 1, pp do
        local index = first + slot - 1
        if index > total then break end
        local col = (slot - 1) % cols
        local row = math.floor((slot - 1) / cols)
        local x = x0 + col * (cw + gx)
        local y = y0 - row * (ch + gy)

        local rec = state.cleared[index]
        local stars = rec and (rec.stars or 0) or 0
        local done = rec ~= nil

        local base = utils.createControl(state.rectPrefabId, x, y, cw, ch,
            utils.hexToColor(done and (pal.accentSoft or "1E4A63") or (pal.btn or "1C2740")), M.grid)
        local num = utils.createText(x, y + 16, cw - 20, 40,
            string.format("%02d", index),
            utils.hexToColor(done and (pal.accent or "4CC9F0") or (pal.text or "E9F0FF")),
            config.DEFAULT_SELECT_CARD_NUM_SIZE or 26, M.grid)

        local starCtls = {}
        local starColor = pal.star or "FFD166"
        local offColor = pal.starOff or "2A3550"
        local sw = 18
        for s = 1, 3 do
            local sx = x - sw + (s - 1) * sw
            local t = utils.createText(sx, y - 26, sw, 22, "★",
                utils.hexToColor(s <= stars and starColor or offColor),
                config.DEFAULT_SELECT_CARD_SUB_SIZE or 14, M.grid)
            starCtls[s] = t
        end

        local hit = utils.createHit(x, y, cw, ch, M.grid, true)

        utils.applyLayerOrder({ base, num, starCtls[1], starCtls[2], starCtls[3], hit })

        local card = {
            index = index, base = base, num = num, stars = starCtls, hit = hit,
            x = x, y = y, w = cw, h = ch, done = done,
        }
        M.cards[#M.cards + 1] = card

        if hit then
            local E = Enum.CursorEventType
            local function tint(active)
                local hex = active and (pal.accentSoft or "1E4A63")
                          or (card.done and (pal.accentSoft or "1E4A63") or (pal.btn or "1C2740"))
                utils.setColor(card.base, hex, 255)
            end
            if E then
                utils.onCursor(hit, E.CursorDown, function()
                    tint(true)
                    utils.setScale(card.base, 0.94)
                    utils.setScale(card.num, 0.94)
                end)
                utils.onCursor(hit, E.CursorUp, function()
                    tint(false)
                    utils.setScale(card.base, 1)
                    utils.setScale(card.num, 1)
                end)
                utils.onCursor(hit, E.CursorClick, function()
                    tint(false)
                    utils.setScale(card.base, 1)
                    utils.setScale(card.num, 1)
                    if actions.onPick then actions.onPick(card.index) end
                end)
            end
        end
    end
end

-- ================================================================
-- 卡片入场：从缩到 0 逐张弹出
-- ================================================================
local function popCards()
    anim.clear(TAG_CARD)
    local stagger = config.DEFAULT_SELECT_CARD_STAGGER or 0.018
    local dur = 0.26
    for i = 1, #M.cards do
        local c = M.cards[i]
        utils.setScale(c.base, 0.001)
        utils.setScale(c.num, 0.001)
        local d = (i - 1) * stagger
        anim.delay(d, function()
            anim.tween(dur, function(p)
                local k = anim.Ease.outBack(p)
                utils.setScale(c.base, k)
                utils.setScale(c.num, k)
                for j = 1, #c.stars do utils.setScale(c.stars[j], k) end
            end, { ease = "linear", tag = TAG_CARD })
        end, TAG_CARD)
    end
end

-- ================================================================
-- 刷新（星级 / 进度）
-- ================================================================
function M.refresh()
    if not M.panel then return end
    local cleared = 0
    for _ in pairs(state.cleared) do cleared = cleared + 1 end
    utils.setText(M.sub, "共 " .. config.levelCount() .. " 关 · 已通关 " .. cleared .. " 关")
    utils.setText(M.dots, "第 " .. state.selectPage .. " / " .. pageCount() .. " 页")
    buildCards(state.selectPage)
end

-- ================================================================
-- 翻页
-- ================================================================
function M.turn(delta)
    local n = pageCount()
    local target = (state.selectPage or 1) + (delta or 1)
    if target < 1 then target = n end
    if target > n then target = 1 end
    M.setPage(target, delta or 1)
end

function M.setPage(page, dir)
    state.selectPage = page
    M.refresh()
    local slide = config.DEFAULT_SELECT_PAGE_SLIDE or 90
    if M.grid then
        utils.setPos(M.grid, -slide * (dir or 1), -46)
        anim.tween(config.DEFAULT_SELECT_PAGE_TIME or 0.20, function(p)
            utils.setPos(M.grid, -slide * (dir or 1) * (1 - p), -46)
        end, { ease = "outCubic", tag = TAG_MENU })
    end
    popCards()
end
function M.open()
    if not M.panel then return false end
    state.selectOpen = true
    M.setVisible(true)
    M.refresh()

    local pal = config.DEFAULT_PALETTE or {}
    local target = config.DEFAULT_SELECT_OVERLAY_ALPHA or 186
    if M.scrim then
        utils.setColor(M.scrim, pal.scrim or "05070F", 0)
        anim.tween(0.22, function(p)
            utils.setColor(M.scrim, pal.scrim or "05070F", math.floor(target * p))
        end, { ease = "outQuad", tag = TAG_MENU })
    end
    -- 面板「由小托起」落定
    utils.setScale(M.panel, 0.96)
    utils.setScale(M.edge, 0.96)
    utils.setScale(M.inner, 0.96)
    anim.tween(0.26, function(p)
        local k = 0.96 + 0.04 * anim.Ease.outBack(p)
        utils.setScale(M.panel, k)
        utils.setScale(M.edge, k)
        utils.setScale(M.inner, k)
    end, { ease = "linear", tag = TAG_MENU })

    popCards()
    return true
end

function M.close()
    state.selectOpen = false
    M.setVisible(false)
end

function M.setVisible(v)
    if M.scrim then utils.setVisible(M.scrim, v) end
    if M.scrimHit then utils.setVisible(M.scrimHit, v) end
    if M.edge then utils.setVisible(M.edge, v) end
    if M.panel then utils.setVisible(M.panel, v) end
    if M.inner then utils.setVisible(M.inner, v) end
    if M.title then utils.setVisible(M.title, v) end
    if M.sub then utils.setVisible(M.sub, v) end
    if M.btnClose then utils.setVisible(M.btnClose, v) end
    if M.btnPrev then utils.setVisible(M.btnPrev, v) end
    if M.btnNext then utils.setVisible(M.btnNext, v) end
    if M.dots then utils.setVisible(M.dots, v) end
    if M.grid then utils.setVisible(M.grid, v) end
end

function M.isOpen()
    return state.selectOpen == true
end

return M
