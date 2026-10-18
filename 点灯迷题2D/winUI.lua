-- ================================================================
-- 点灯迷题 2D · 通关结算
--   棋盘会先缩成「战利品照片」飞到左侧（由 view.toPhoto 完成），
--   随后结果卡从右侧滑入 → 三星逐颗弹出 → 步数滚动增长 → 按钮依次落位。
-- ================================================================

---@diagnostic disable: undefined-global

local M = {}

local state = require("default_import_file/state")
local config = require("default_import_file/config")
local utils = require("default_import_file/utils")
local anim = require("default_import_file/anim")

local TAG_WIN = "win:main"
local TAG_STAR = "win:star"

local actions = {}

function M.setActions(a)
    actions = a or {}
end

-- ================================================================
-- 建（只建一次）
-- ================================================================
function M.init()
    local par = state.containerWin
    if not par or (state.rectPrefabId or 0) <= 0 then return false end

    local pal = config.DEFAULT_PALETTE or {}
    local CW = config.DEFAULT_WIN_CARD_W or 620
    local CH = config.DEFAULT_WIN_CARD_H or 520
    local CX = config.DEFAULT_WIN_CARD_X or 250

    M.scrim = utils.createControl(state.rectPrefabId, 0, 0,
        (state.canvasW or 1280) + 40, (state.canvasH or 720) + 40,
        utils.hexToColorA(pal.scrim or "05070F", 0), par)
    M.scrimHit = utils.createHit(0, 0, (state.canvasW or 1280) + 40, (state.canvasH or 720) + 40, par, true)

    -- 结果卡用容器承载，整体做「滑入 + 缩放」
    M.card = utils.createContainer(par)
    if not M.card then return false end
    utils.setPos(M.card, CX, 0)

    M.edge = utils.createControl(state.rectPrefabId, 0, 0, CW + 4, CH + 4,
        utils.hexToColor(pal.panelEdge or "1E2A47"), M.card)
    M.bg = utils.createControl(state.rectPrefabId, 0, 0, CW, CH,
        utils.hexToColor(pal.winCard or "101A30"), M.card)
    M.bgTop = utils.createControl(state.rectPrefabId, 0, CH / 2 - 5, CW - 40, 3,
        utils.hexToColorA(pal.star or "FFD166", 170), M.card)

    M.title = utils.createText(0, CH / 2 - 58, CW - 60, 56, "通关！",
        utils.hexToColor(pal.text or "E9F0FF"), config.DEFAULT_WIN_TITLE_SIZE or 38, M.card)

    -- 三星
    M.stars = {}
    local ssize = config.DEFAULT_WIN_STAR_SIZE or 58
    local sgap = config.DEFAULT_WIN_STAR_GAP or 14
    local totalW = ssize * 3 + sgap * 2
    for i = 1, 3 do
        local x = -totalW / 2 + ssize / 2 + (i - 1) * (ssize + sgap)
        local t = utils.createText(x, 96, ssize, ssize,
            "★", utils.hexToColor(pal.star or "FFD166"), ssize, M.card)
        M.stars[i] = t
    end

    M.line = utils.createText(0, 30, CW - 80, 34, "",
        utils.hexToColor(pal.textDim or "8296B8"), config.DEFAULT_WIN_TEXT_SIZE or 20, M.card)

    M.numLabel = utils.createText(0, -26, CW - 80, 24, "本关步数",
        utils.hexToColor(pal.textDim or "8296B8"), 15, M.card)
    M.num = utils.createText(0, -70, CW - 80, 64, "0",
        utils.hexToColor(pal.star or "FFD166"), config.DEFAULT_WIN_NUM_SIZE or 40, M.card)

    M.best = utils.createText(0, -116, CW - 80, 28, "",
        utils.hexToColorA(pal.textDim or "8296B8", 190), 15, M.card)

    -- 三个按钮
    local bw = config.DEFAULT_WIN_BTN_W or 168
    local bh = config.DEFAULT_WIN_BTN_H or 52
    local bgap = 16
    local by = -CH / 2 + 62
    local bx0 = -(bw * 3 + bgap * 2) / 2 + bw / 2
    M.btnReplay = utils.createButton(bx0, by, bw, bh, M.card, {
        text = "再来一次", fontSize = 19,
        bg = pal.btn, bgDown = pal.btnDown, textColor = pal.btnText,
        onClick = function() if actions.onReplay then actions.onReplay() end end,
    })
    M.btnNext = utils.createButton(bx0 + bw + bgap, by, bw, bh, M.card, {
        text = "下一关", fontSize = 19,
        bg = pal.star, bgDown = pal.cellOn, textColor = "1A1206",
        onClick = function() if actions.onNext then actions.onNext() end end,
    })
    M.btnSelect = utils.createButton(bx0 + (bw + bgap) * 2, by, bw, bh, M.card, {
        text = "返回选关", fontSize = 19,
        bg = pal.btn, bgDown = pal.btnDown, textColor = pal.btnText,
        onClick = function() if actions.onSelect then actions.onSelect() end end,
    })

    utils.applyLayerOrder({ M.scrim, M.scrimHit, M.card })
    -- ★ 卡片内部也显式排一次（列表里不能有 nil，否则 #list 会提前截断）
    local inner = { M.edge, M.bg, M.bgTop, M.title,
                    M.stars[1], M.stars[2], M.stars[3],
                    M.line, M.numLabel, M.num, M.best }
    local function addBtn(b)
        if b then
            inner[#inner + 1] = b.base
            inner[#inner + 1] = b.label
            inner[#inner + 1] = b.hit
        end
    end
    addBtn(M.btnReplay)
    addBtn(M.btnNext)
    addBtn(M.btnSelect)
    utils.applyLayerOrder(inner)

    M.setVisible(false)
    return true
end

-- ================================================================
-- 打开
-- ================================================================
function M.open(index, info)
    if not M.card then return false end
    info = info or {}
    state.winOpen = true
    state.winStars = math.floor(info.stars or 1)
    state.winSteps = math.floor(info.moves or 0)
    state.winBest = math.floor(info.best or 0)

    local pal = config.DEFAULT_PALETTE or {}
    M.setVisible(true)

    -- 文案
    utils.setText(M.line, "第 " ..
        string.format("%02d", index or 1) .. " 关完成")
    utils.setText(M.num, "0")
    utils.setText(M.best, state.winBest > 0 and ("最优 " .. state.winBest .. " 步") or "")
    for i = 1, 3 do
        utils.setTextColor(M.stars[i], i <= state.winStars and (pal.star or "FFD166")
            or (pal.starOff or "2A3550"), 255)
        utils.setScale(M.stars[i], 0.001)
        utils.setRotationZ(M.stars[i], -35)
    end
    utils.setScale(M.btnReplay and M.btnReplay.base or nil, 0.001)
    utils.setScale(M.btnNext and M.btnNext.base or nil, 0.001)
    utils.setScale(M.btnSelect and M.btnSelect.base or nil, 0.001)

    -- 遮罩淡入
    local target = config.DEFAULT_WIN_OVERLAY_ALPHA or 172
    utils.setColor(M.scrim, pal.scrim or "05070F", 0)
    anim.tween(0.26, function(p)
        utils.setColor(M.scrim, pal.scrim or "05070F", math.floor(target * p))
    end, { ease = "outQuad", tag = TAG_WIN })

    -- 结果卡从右侧滑入（带一点过冲）
    local CX = config.DEFAULT_WIN_CARD_X or 250
    utils.setPos(M.card, CX + 680, 0)
    utils.setScale(M.card, 0.86)
    anim.tween(config.DEFAULT_WIN_CARD_TIME or 0.46, function(p)
        local e = anim.Ease.outBack(p)
        utils.setPos(M.card, CX + 680 * (1 - e), 0)
        utils.setScale(M.card, 0.86 + 0.14 * math.min(1, p * 1.15))
    end, { ease = "linear", tag = TAG_WIN })

    -- 星星逐颗弹出
    local base = config.DEFAULT_WIN_CARD_TIME or 0.46
    local sd = config.DEFAULT_WIN_STAR_DELAY or 0.13
    local st = config.DEFAULT_WIN_STAR_TIME or 0.34
    for i = 1, state.winStars do
        anim.delay(base * 0.55 + (i - 1) * sd, function()
            anim.tween(st, function(p)
                local k = anim.Ease.outBack(p)
                utils.setScale(M.stars[i], k)
                utils.setRotationZ(M.stars[i], -35 * (1 - p))
            end, { ease = "linear", tag = TAG_STAR })
        end, TAG_STAR)
    end

    -- 步数滚动
    anim.delay(base * 0.7, function()
        anim.value(0, state.winSteps, 0.55, function(v)
            utils.setText(M.num, tostring(math.floor(v + 0.5)))
        end, { ease = "outCubic", tag = TAG_STAR })
    end, TAG_STAR)

    -- 按钮依次落位
    local btnStart = base + (state.winStars - 1) * sd + st * 0.6
    local list = { M.btnReplay, M.btnNext, M.btnSelect }
    for i = 1, #list do
        local b = list[i]
        if b then
            anim.delay(btnStart + (i - 1) * 0.09, function()
                anim.tween(0.28, function(p)
                    local k = anim.Ease.outBack(p)
                    utils.setScale(b.base, k)
                    utils.setScale(b.label, k)
                end, { ease = "linear", tag = TAG_WIN })
            end, TAG_WIN)
        end
    end

    return true
end

-- ================================================================
-- 关闭
-- ================================================================
function M.close()
    state.winOpen = false
    anim.clear(TAG_WIN)
    anim.clear(TAG_STAR)
    M.setVisible(false)
end

function M.isOpen()
    return state.winOpen == true
end

function M.setVisible(v)
    if M.scrim then utils.setVisible(M.scrim, v) end
    if M.scrimHit then utils.setVisible(M.scrimHit, v) end
    if M.card then utils.setVisible(M.card, v) end
    if M.btnReplay then utils.setVisible(M.btnReplay, v) end
    if M.btnNext then utils.setVisible(M.btnNext, v) end
    if M.btnSelect then utils.setVisible(M.btnSelect, v) end
end

-- 键盘：空格 / 回车 = 下一关
function M.confirmPrimary()
    if actions.onNext then actions.onNext() end
end

return M
