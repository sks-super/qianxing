-- ================================================================
-- 2048 · 棋盘视图
--   把 board.lua 的数据模型画出来，并把每一次 action 演成动画。
--
--   每个方块 = 一个「方块容器」+ 它的两个子控件（色块图片 / 数字文本）。
--   ★ 把两件东西放进同一个容器，是为了能用一次 SetAnchoredPosition /
--     SetLocalScale 同时驱动「色块与数字」——平移和缩放永远不会脱节。
--   ★ 数字必须 SetAsLastSibling 提到色块之上（真机「后创建的在上」、
--     模拟器渲染顺序相反，只有这个调用在两个引擎里效果一致）。
-- ================================================================

---@diagnostic disable: undefined-global

local M = {}

local state = require("default_import_file/state")
local config = require("default_import_file/config")
local utils = require("default_import_file/utils")
local anim = require("default_import_file/anim")
local fx = require("default_import_file/fx")

local TAG = "view"

-- 「+N」飘字颜色（浅色，在深浅底色上都看得见）
local FLOAT_HEX = "F9F6F2"

-- ================================================================
-- 底板与空格（只建一次）
-- ================================================================
function M.init()
    if not state.containerBoardBg then return false end
    if state.rectPrefabId <= 0 then return false end

    local pal = config.DEFAULT_PALETTE or {}
    local cell = config.DEFAULT_BOARD_CELL or 104
    local size = utils.boardSize()

    -- ★ 底板与空格都按「相对棋盘中心」的局部坐标摆放（0,0 = 棋盘正中心），
    --   因为 containerBoardBg 自己已经被放到棋盘中心上了。
    state.boardFrame = utils.createControl(state.rectPrefabId, 0, 0, size, size,
        utils.hexToColor(pal.boardBg or "BBADA0"), state.containerBoardBg)

    state.cellBacks = {}
    for r = 1, 4 do
        for c = 1, 4 do
            local x, y = utils.cellCenter(r, c)
            state.cellBacks[#state.cellBacks + 1] = utils.createControl(
                state.rectPrefabId, x, y, cell, cell,
                utils.hexToColor(pal.cellEmpty or "CDC1B4"), state.containerBoardBg)
        end
    end
    -- ★ 空格底板要压在棋盘底板之上：底板是「后创建 = 在真机在上、在模拟器在下」，
    --   所以显式把它沉到同级最下层（SetAsFirstSibling 两引擎一致），绝不赌创建顺序。
    utils.sink(state.boardFrame)
    return true
end

-- ================================================================
-- ★ 棋盘根（containerBoard）的变换复位
--   静止态 = 位置(boardCX, boardCY) / 缩放 1 / 不旋转。
--   结算动效会把它改成「相片态」，回到游戏时必须复位。
-- ================================================================
function M.resetBoardTransform()
    local root = state.containerBoard
    if not root then return end
    utils.setPos(root, state.boardCX or 0, state.boardCY or 0)
    utils.setScale(root, 1)
    utils.setRotationZ(root, 0)
end

-- ================================================================
-- 方块视图
-- ================================================================
function M.viewOf(tileId)
    for i = 1, #state.tileViews do
        if state.tileViews[i].id == tileId then return state.tileViews[i] end
    end
    return nil
end

local function applyLook(v, value)
    local bg, fg = utils.tileColor(value)
    v.value = value
    utils.setColor(v.img, bg, 255)
    utils.setText(v.label, tostring(value))
    utils.setFontSize(v.label, utils.tileFontSize(value))
    utils.setTextColor(v.label, fg, 255)
end

-- 新建一个方块视图（value=0 表示「还没定值」，仅用于占位）
local function createView(tile, value)
    local root = utils.createContainer(state.containerTile)
    if not root then return nil end
    local cell = config.DEFAULT_BOARD_CELL or 104
    local x, y = utils.cellCenter(tile.r, tile.c)
    pcall(function()
        root:SetAnchoredPosition(x, y)
        root:SetSizeDelta(cell, cell)
    end)

    local img = utils.createControl(state.rectPrefabId, 0, 0, cell, cell,
        utils.hexToColor("CDC1B4"), root)
    local label = utils.createText(0, 0, cell, cell, "", utils.hexToColor("776E65"),
        utils.tileFontSize(value or 2), root)
    utils.raise(label)          -- ★ 数字压住色块

    local v = {
        id = tile.id, root = root, img = img, label = label,
        value = 0, r = tile.r, c = tile.c,
    }
    applyLook(v, value or 2)
    state.tileViews[#state.tileViews + 1] = v
    return v
end

function M.removeView(tileId)
    for i = #state.tileViews, 1, -1 do
        if state.tileViews[i].id == tileId then
            local v = table.remove(state.tileViews, i)
            utils.destroy(v.root)
            return true
        end
    end
    return false
end

function M.clearTiles()
    for i = 1, #state.tileViews do utils.destroy(state.tileViews[i].root) end
    state.tileViews = {}
end

-- 依据 state.tiles 无动画地重建全部方块视图（开局 / 撤销 / 重开后调用）
function M.syncInstant()
    M.clearTiles()
    for i = 1, #state.tiles do
        local t = state.tiles[i]
        local v = createView(t, t.value)
        if v then
            utils.setScale(v.root, 1)
            utils.setRotationZ(v.root, 0)
        end
    end
end

-- ================================================================
-- ★ 播放一次移动的全部动效
--   action   : board.tryMove() 的返回值
--   onDone   : 全部动画结束后的回调（game.lua 在这里解锁输入并判定结束）
-- ================================================================
function M.playAction(action, onDone)
    if not action then
        if onDone then onDone() end
        return
    end

    local moveTime = config.DEFAULT_ANIM_MOVE_TIME or 0.12
    local mergeTime = config.DEFAULT_ANIM_MERGE_TIME or 0.14
    local spawnTime = config.DEFAULT_ANIM_SPAWN_TIME or 0.16
    local popScale = config.DEFAULT_ANIM_MERGE_SCALE or 1.18
    local overshoot = config.DEFAULT_ANIM_SPAWN_OVERSHOOT or 1.12

    state.animating = true
    anim.clear(TAG)

    -- ------------------------------------------------------------
    -- ① 平移：逐帧改 SetAnchoredPosition（需求指定的做法，位移时长 100–150ms）
    -- ------------------------------------------------------------
    for i = 1, #action.moves do
        local mv = action.moves[i]
        local v = M.viewOf(mv.id)
        if v then
            local x0, y0 = utils.cellCenter(mv.fr, mv.fc)
            local x1, y1 = utils.cellCenter(mv.tr, mv.tc)
            v.r, v.c = mv.tr, mv.tc
            anim.tween(moveTime, function(p)
                pcall(function()
                    v.root:SetAnchoredPosition(x0 + (x1 - x0) * p, y0 + (y1 - y0) * p)
                end)
            end, { ease = "outQuad", tag = TAG })
        end
    end

    -- ------------------------------------------------------------
    -- ② 被吸收的方块：滑到目标格之后销毁
    -- ------------------------------------------------------------
    for i = 1, #action.removed do
        local id = action.removed[i]
        anim.delay(moveTime + 0.01, function() M.removeView(id) end, TAG)
    end

    -- ------------------------------------------------------------
    -- ③ 合并：改值 + 先放大到 1.18 再回弹到 1 + 粒子迸溅 + 「+N」飘字
    -- ------------------------------------------------------------
    for i = 1, #action.merges do
        local mg = action.merges[i]
        local v = M.viewOf(mg.id)
        -- ★ 粒子/飘字挂在 containerFx（场景坐标），而 cellCenter 是棋盘局部坐标
        --   → 必须显式换算，否则特效会整体偏掉一个棋盘中心。
        local mx, my = utils.boardToScene(utils.cellCenter(mg.r, mg.c))
        local bg = utils.tileColor(mg.value)
        anim.delay(moveTime, function()
            if v then
                utils.raise(v.root)          -- ★ 弹跳的方块提到最上层，免得被邻居压住
                applyLook(v, mg.value)
                anim.tween(mergeTime, function(p)
                    local s = 1 + (popScale - 1) * p     -- 0→1 山丘 → 1→1.18→1
                    utils.setScale(v.root, s)
                end, { ease = "pulse", tag = TAG })
            end
            fx.burst(mx, my, bg)
            fx.floatText(mx, my + utils.MIN_TEXT_H * 0.9, "+" .. tostring(mg.gained), FLOAT_HEX)
        end, TAG)
    end

    -- ------------------------------------------------------------
    -- ④ 新方块：从 0 放大到 overshoot 再回落到 1（轻微回弹）
    -- ------------------------------------------------------------
    if action.spawn then
        local sp = action.spawn
        local v = createView({ id = sp.id, r = sp.r, c = sp.c }, sp.value)
        if v then
            utils.setScale(v.root, 0)
            local delay = moveTime * 0.45
            anim.delay(delay, function()
                anim.value(0, overshoot, spawnTime * 0.6, function(s)
                    utils.setScale(v.root, s)
                end, { ease = "outQuad", tag = TAG })
                anim.delay(spawnTime * 0.6, function()
                    anim.value(overshoot, 1, spawnTime * 0.4, function(s)
                        utils.setScale(v.root, s)
                    end, { ease = "inOutQuad", tag = TAG })
                end, TAG)
            end, TAG)
        end
    end

    -- ------------------------------------------------------------
    -- ⑤ 收尾
    -- ------------------------------------------------------------
    local finish = moveTime + math.max(mergeTime, spawnTime) + 0.02
    anim.delay(finish, function()
        state.animating = false
        if onDone then onDone() end
    end, TAG)
end

-- ================================================================
-- ★ 撤销 / 重开后的表现：整盘直接归位，再给一个整体「呼吸」
-- ================================================================
function M.syncWithPop()
    M.clearTiles()
    anim.clear(TAG)
    for i = 1, #state.tiles do
        local t = state.tiles[i]
        local v = createView(t, t.value)
        if v then
            utils.setScale(v.root, 0)
            local d = 0.03 * (i - 1)
            anim.delay(d, function()
                anim.value(0, 1, config.DEFAULT_ANIM_UNDO_TIME or 0.20, function(s)
                    utils.setScale(v.root, s)
                end, { ease = "outBack", tag = TAG })
            end, TAG)
        end
    end
end

return M
