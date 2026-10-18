-- ================================================================
-- 点灯迷题 16 · 棋盘视图
--   左：目标图案 P（静态，黑线白底）
--   右：当前盘面 S（可点，翻牌动效）
--
--   动效：点一格 → 十字五格按距离错峰【横向翻牌】（压到 0.045 再展开，中点换色）
--         + 方形冲击波 + 点亮/熄灭粒子
-- ================================================================

---@diagnostic disable: undefined-global

local M = {}

local state = require("default_import_file/state")
local config = require("default_import_file/config")
local utils = require("default_import_file/utils")
local anim = require("default_import_file/anim")
local fx = require("default_import_file/fx")
local board = require("default_import_file/board")

local TAG_FLIP = "view:flip"
local TAG_FX = "view:fx"
local TAG_TICK = "view:tick"

local actions = { onPress = nil }

function M.setActions(a)
    actions = a or {}
end

local function cellSize()
    return config.DEFAULT_CELL or 46
end

local function cellGap()
    return config.DEFAULT_GAP or 5
end

local function boardW()
    local n = board.size()
    return n * cellSize() + (n + 1) * cellGap()
end

-- 相对棋盘中心的格心坐标
local function cellPos(i)
    local n = board.size()
    local x, y = board.xy(i)
    local W = boardW()
    local x0 = -W / 2 + cellGap() + cellSize() / 2
    local y0 = W / 2 - cellGap() - cellSize() / 2
    return x0 + (x - 1) * (cellSize() + cellGap()),
           y0 - (y - 1) * (cellSize() + cellGap())
end

local function paint(cell, v)
    local pal = config.DEFAULT_PALETTE or {}
    local hex = (v == 1) and (pal.ink or "111318") or (pal.paper or "F7F8FA")
    utils.setColor(cell.body, hex, 255)
    cell.v = v
end

-- ================================================================
-- 建一个 8×8 棋盘（ref 或 play）
-- ================================================================
local function buildBoard(parent, cx, cy, interactive)
    local par = utils.createContainer(parent)
    if not par then return nil, nil end
    utils.setPos(par, cx, cy)

    local pal = config.DEFAULT_PALETTE or {}
    local W = boardW()
    local pad = config.DEFAULT_BOARD_PAD or 10

    local edge = utils.createControl(state.rectPrefabId, 0, 0, W + pad * 2 + 4, W + pad * 2 + 4,
        utils.hexToColor(pal.panelEdge or "1E2A47"), par)
    local paper = utils.createControl(state.rectPrefabId, 0, 0, W + pad * 2, W + pad * 2,
        utils.hexToColor(pal.paper or "F7F8FA"), par)
    utils.raise(paper)

    local cells = {}
    for i = 0, board.count() - 1 do
        local x, y = cellPos(i)
        local cs = cellSize()
        local body = utils.createControl(state.rectPrefabId, x, y, cs, cs,
            utils.hexToColor(pal.paper or "F7F8FA"), par)
        local hit = nil
        if interactive then
            hit = utils.createHit(x, y, cs, cs, par, true)
            utils.raise(hit)
        end
        local cell = { body = body, hit = hit, idx = i, v = 0, flip = false }
        cells[#cells + 1] = cell
        if hit then
            local E = Enum.CursorEventType
            if E then
                utils.onCursor(hit, E.CursorClick, function()
                    if actions.onPress then actions.onPress(cell.idx) end
                end)
                utils.onCursor(hit, E.CursorDown, function()
                    anim.clear("view:press" .. cell.idx)
                    anim.tween(0.07, function(p)
                        if cell.flip then return end
                        utils.setScale(cell.body, 1 - 0.10 * p)
                    end, { ease = "outQuad", tag = "view:press" .. cell.idx })
                end)
                utils.onCursor(hit, E.CursorUp, function()
                    anim.clear("view:press" .. cell.idx)
                    anim.tween(0.10, function(p)
                        if cell.flip then return end
                        utils.setScale(cell.body, 0.90 + 0.10 * p)
                    end, { ease = "outBack", tag = "view:press" .. cell.idx })
                end)
            end
        end
    end

    -- ★ 必须一次性排全层：edge → paper → 64 个格子 → 命中区。
    --   只写 applyLayerOrder({edge, paper}) 会把白纸底板提到最上层，把格子全盖掉（白板一片）。
    local order = { edge, paper }
    for i = 1, #cells do order[#order + 1] = cells[i].body end
    utils.applyLayerOrder(order)
    for i = 1, #cells do
        if cells[i].hit then utils.raise(cells[i].hit) end
    end

    return par, cells
end

-- ================================================================
-- 初始化两块棋盘
-- ================================================================
function M.init()
    if not state.containerRef or not state.containerBoard then return false end
    if (state.rectPrefabId or 0) <= 0 then return false end

    state.refContainer, state.refCells = buildBoard(
        state.containerRef,
        config.DEFAULT_REF_CX or -236, config.DEFAULT_REF_CY or -34, false)

    -- ★ containerBoard 自己就放在棋盘中心（震屏时只动它），内层容器必须归零，
    --   否则偏移叠加两次 → 棋盘飞到屏幕外。
    if state.containerBoard then
        utils.setPos(state.containerBoard,
            config.DEFAULT_BOARD_CX or 236, config.DEFAULT_BOARD_CY or -34)
    end
    state.playContainer, state.playCells = buildBoard(state.containerBoard, 0, 0, true)

    return state.refContainer ~= nil and state.playContainer ~= nil
end

-- ================================================================
-- 同步
-- ================================================================
function M.setRef(quad)
    for i = 1, #state.refCells do
        local cell = state.refCells[i]
        local x, y = board.xy(cell.idx)
        paint(cell, (quad[y] and quad[y][x] == 1) and 1 or 0)
        utils.setScale(cell.body, 1)
    end
end

function M.syncPlay(bd)
    for i = 1, #state.playCells do
        local cell = state.playCells[i]
        cell.flip = false
        paint(cell, (bd[cell.idx + 1] == 1) and 1 or 0)
        utils.setScale(cell.body, 1)
    end
end

-- ================================================================
-- ★ 播放一次按压：效果按「距中心远近」错峰
-- ================================================================
local function flipCell(cell, toV, delay, speed)
    local half = (config.DEFAULT_ANIM_FLIP_HALF or 0.07) * speed
    local back = (config.DEFAULT_ANIM_FLIP_BACK or 0.15) * speed

    anim.delay(delay, function()
        cell.flip = true
        anim.clear("view:press" .. cell.idx)

        anim.tween(half, function(p)
            utils.setScale(cell.body, 1 - (1 - 0.045) * p)
        end, { ease = "inQuad", tag = TAG_FLIP })

        anim.delay(half, function()
            paint(cell, toV)
            cell.flip = false
            anim.tween(back, function(p)
                utils.setScale(cell.body, 0.045 + (1 - 0.045) * p)
            end, { ease = "outBack", tag = TAG_FLIP })
        end, TAG_FLIP)
    end, TAG_FLIP)
end

function M.playPress(idx, prevBoard, opts)
    opts = opts or {}
    local speed = opts.speed or 1
    local list = board.toggleSetOf(idx)
    local stagger = (config.DEFAULT_ANIM_STAGGER or 0.03) * speed

    anim.clear(TAG_FLIP)
    M.syncPlay(prevBoard)          -- 先用「按下前」的盘面落定，翻牌才有起点色

    -- 冲击波
    local x, y = cellPos(idx)
    local sx = x + (config.DEFAULT_BOARD_CX or 236)
    local sy = y + (config.DEFAULT_BOARD_CY or -34)
    fx.ring(sx, sy, cellSize() * 0.9, config.DEFAULT_PALETTE.accent or "4CC9F0")
    fx.shake()

    local maxDelay = 0
    for k = 1, #list do
        local item = list[k]
        local d = (item.dist == 0) and 0 or stagger
        if d > maxDelay then maxDelay = d end
        local cell = state.playCells[item.idx + 1]
        if cell then
            flipCell(cell, (opts.board and opts.board[item.idx + 1] == 1) and 1 or 0, d, speed)
        end
    end

    return maxDelay + (config.DEFAULT_ANIM_FLIP_HALF or 0.07) * speed
                 + (config.DEFAULT_ANIM_FLIP_BACK or 0.15) * speed
end

-- ================================================================
-- 入场 / 提示 / 显隐
-- ================================================================
function M.spawn()
    local stagger = config.DEFAULT_ANIM_INTRO_STAGGER or 0.012
    local dur = config.DEFAULT_ANIM_INTRO_TIME or 0.36
    for i = 1, #state.refCells do
        utils.setScale(state.refCells[i].body, 0.001)
        utils.setScale(state.playCells[i].body, 0.001)
    end
    for i = 1, #state.refCells do
        local d = ((i - 1) % board.size() + math.floor((i - 1) / board.size())) * stagger
        local r, pl = state.refCells[i], state.playCells[i]
        anim.delay(d, function()
            anim.tween(dur, function(p)
                local k = anim.Ease.outBack(p)
                utils.setScale(r.body, k)
                utils.setScale(pl.body, k)
            end, { ease = "linear", tag = TAG_FX })
        end, TAG_FX)
    end
    return (board.size() * 2) * stagger + dur
end

function M.showHint(idx)
    state.hintIndex = idx
    state.hintUntil = state.time + (config.DEFAULT_ANIM_HINT_TIME or 1.2)
    local x, y = cellPos(idx)
    local sx = x + (config.DEFAULT_BOARD_CX or 236)
    local sy = y + (config.DEFAULT_BOARD_CY or -34)
    fx.ring(sx, sy, cellSize() * 0.85, config.DEFAULT_PALETTE.good or "5BE7A9")
end

function M.setVisible(v)
    if state.containerRef then utils.setVisible(state.containerRef, v) end
    if state.containerBoard then utils.setVisible(state.containerBoard, v) end
end

function M.setRefVisible(v)
    if state.containerRef then utils.setVisible(state.containerRef, v) end
end

function M.update(dt)
    if not dt or dt <= 0 then return end
    state.time = state.time + dt

    if (state.shakeT or 0) > 0 then
        state.shakeT = state.shakeT - dt
        if state.shakeT < 0 then state.shakeT = 0 end
        local amp = (config.DEFAULT_ANIM_SHAKE or 3) * (state.shakeT / (config.DEFAULT_ANIM_SHAKE_TIME or 0.14))
        local dx = (math.random() * 2 - 1) * amp
        local dy = (math.random() * 2 - 1) * amp
        if state.containerBoard then
            utils.setPos(state.containerBoard,
                (config.DEFAULT_BOARD_CX or 236) + dx,
                (config.DEFAULT_BOARD_CY or -34) + dy)
        end
        if state.shakeT <= 0 and state.containerBoard then
            utils.setPos(state.containerBoard,
                config.DEFAULT_BOARD_CX or 236, config.DEFAULT_BOARD_CY or -34)
        end
    end

    -- 提示脉冲：把提示格描成橙色再还原
    if state.hintIndex >= 0 then
        local cell = state.playCells[state.hintIndex + 1]
        if state.time > state.hintUntil then
            if cell then paint(cell, cell.v) end
            state.hintIndex = -1
        elseif cell then
            local k = 0.5 + 0.5 * math.sin(state.time * 7)
            utils.setColor(cell.body, config.DEFAULT_PALETTE.good or "5BE7A9",
                math.floor(70 + 90 * k))
        end
    end
end

function M.cellOf(idx)
    return state.playCells[idx + 1]
end

return M
