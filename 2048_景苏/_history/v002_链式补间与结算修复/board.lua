-- ================================================================
-- 2048 · 棋盘逻辑（纯数据，不碰任何控件）
--   数据模型：4×4 = 16 格，用「方块对象数组」表示（空格即没有方块）。
--     每个方块 = { id, r, c, value }，id 唯一且终身不变 —— 视图靠 id
--     把「同一个方块」从旧位置动到新位置，这是平移动画的前提。
--
--   ★ 一次移动的产物叫 action，视图只认这个结构，逻辑与表现彻底解耦：
--       action.moves   = { {id, fr, fc, tr, tc}, ... }   位移
--       action.merges  = { {tile, id, r, c, value, gained}, ... }   合并后的新值
--       action.removed = { id, ... }                      被吸收的方块
--       action.spawn   = { tile, id, r, c, value }        新出现的方块
--       action.gained / scoreBefore / scoreAfter / steps / dir
-- ================================================================

---@diagnostic disable: undefined-global

local M = {}
local state = require("default_import_file/state")
local config = require("default_import_file/config")

local SIZE = 4

local seeded = false
local function ensureSeed()
    if seeded then return end
    seeded = true
    pcall(function() math.randomseed(os.time()) end)
end

-- ================================================================
-- 查询
-- ================================================================
function M.tileAt(r, c)
    for i = 1, #state.tiles do
        local t = state.tiles[i]
        if t.r == r and t.c == c then return t end
    end
    return nil
end

function M.emptyCells()
    local out = {}
    for r = 1, SIZE do
        for c = 1, SIZE do
            if not M.tileAt(r, c) then out[#out + 1] = { r = r, c = c } end
        end
    end
    return out
end

function M.maxValue()
    local m = 0
    for i = 1, #state.tiles do
        if state.tiles[i].value > m then m = state.tiles[i].value end
    end
    return m
end

-- ★ 无空位且四邻没有相同值 → 无路可走
function M.canMoveAny()
    if #M.emptyCells() > 0 then return true end
    for r = 1, SIZE do
        for c = 1, SIZE do
            local v = M.tileAt(r, c)
            if v then
                local right = M.tileAt(r, c + 1)
                local down = M.tileAt(r + 1, c)
                if (right and right.value == v.value) or (down and down.value == v.value) then
                    return true
                end
            end
        end
    end
    return false
end

-- ================================================================
-- 生成新方块
-- ================================================================
local function newTile(r, c, value)
    local t = { id = state.nextTileId, r = r, c = c, value = value }
    state.nextTileId = state.nextTileId + 1
    state.tiles[#state.tiles + 1] = t
    if value > (state.maxReached or 0) then state.maxReached = value end
    return t
end

function M.rollValue()
    ensureSeed()
    local ratio = config.DEFAULT_SPAWN_2_RATIO or 90
    local roll = math.random(1, 100)
    if roll <= ratio then return 2 end
    return 4
end

-- 在随机空位生成一个数字（返回新方块，棋盘已满时返回 nil）
function M.spawn()
    local cells = M.emptyCells()
    if #cells == 0 then return nil end
    ensureSeed()
    local pick = cells[math.random(1, #cells)]
    return newTile(pick.r, pick.c, M.rollValue())
end

-- ================================================================
-- 快照 / 撤销
-- ================================================================
local function snapshot()
    local snap = {
        tiles = {},
        score = state.score,
        steps = state.steps,
        maxReached = state.maxReached,
        nextTileId = state.nextTileId,
    }
    for i = 1, #state.tiles do
        local t = state.tiles[i]
        snap.tiles[i] = { id = t.id, r = t.r, c = t.c, value = t.value }
    end
    return snap
end

local function restore(snap)
    state.tiles = {}
    for i = 1, #snap.tiles do
        local s = snap.tiles[i]
        state.tiles[i] = { id = s.id, r = s.r, c = s.c, value = s.value }
    end
    state.score = snap.score
    state.steps = snap.steps
    state.maxReached = snap.maxReached
    state.nextTileId = snap.nextTileId
end

local function pushUndo()
    if (config.DEFAULT_UNDO_ENABLED or 1) == 0 then return end
    local depth = math.max(1, math.floor(config.DEFAULT_UNDO_DEPTH or 32))
    local st = state.undoStack
    st[#st + 1] = snapshot()
    while #st > depth do table.remove(st, 1) end
end

function M.canUndo()
    return (config.DEFAULT_UNDO_ENABLED or 1) ~= 0 and #state.undoStack > 0
end

-- ★ 撤销一步：整盘回到上一步之前（分数/步数/最大方块一并回退）
function M.undo()
    if not M.canUndo() then return false end
    local snap = table.remove(state.undoStack)
    if not snap then return false end
    restore(snap)
    return true
end

-- ================================================================
-- 移动与合并
-- ================================================================

-- 遍历顺序：每条「线」按「靠目标边最近 → 最远」排列
local function lineFor(dir, i)
    local line = {}
    if dir == "left" then
        for c = 1, SIZE do line[#line + 1] = { r = i, c = c } end
    elseif dir == "right" then
        for c = SIZE, 1, -1 do line[#line + 1] = { r = i, c = c } end
    elseif dir == "up" then
        for r = 1, SIZE do line[#line + 1] = { r = r, c = i } end
    else -- "down"
        for r = SIZE, 1, -1 do line[#line + 1] = { r = r, c = i } end
    end
    return line
end

-- ★ 核心：算出这一方向移动后的全部变化
--   返回 action；若这一步没有任何变化（棋盘纹丝不动）则返回 nil。
function M.move(dir)
    local moves, merges, removed = {}, {}, {}
    local gained = 0
    local scoreBefore = state.score

    for i = 1, SIZE do
        local line = lineFor(dir, i)

        -- 取这条线上的方块（按遍历顺序）
        local onLine = {}
        for k = 1, #line do
            local t = M.tileAt(line[k].r, line[k].c)
            if t then
                onLine[#onLine + 1] = t
                t.merged = false          -- 每次移动前清标记
            end
        end

        local slot = 1                    -- 下一个可落的位置（line 的下标）
        local last = nil                  -- 上一个已落位的方块
        for k = 1, #onLine do
            local t = onLine[k]
            if last and last.value == t.value and not last.merged then
                -- ---- 合并：t 飞向 last 所在格并被吸收 ----
                moves[#moves + 1] = { id = t.id, fr = t.r, fc = t.c, tr = last.r, tc = last.c }
                last.merged = true
                local nv = last.value * 2
                gained = gained + nv
                merges[#merges + 1] = {
                    tile = last, id = last.id, r = last.r, c = last.c,
                    value = nv, gained = nv,
                }
                removed[#removed + 1] = t.id
            else
                -- ---- 平移：落到 slot ----
                local pos = line[slot]
                if t.r ~= pos.r or t.c ~= pos.c then
                    moves[#moves + 1] = { id = t.id, fr = t.r, fc = t.c, tr = pos.r, tc = pos.c }
                end
                t.r, t.c = pos.r, pos.c
                last = t
                slot = slot + 1
            end
        end
    end

    if #moves == 0 and #merges == 0 then return nil end

    -- ---- 结算：先把被吸收的方块从棋盘摘掉 ----
    if #removed > 0 then
        local dead = {}
        for _, id in ipairs(removed) do dead[id] = true end
        local keep = {}
        for i = 1, #state.tiles do
            local t = state.tiles[i]
            if not dead[t.id] then keep[#keep + 1] = t end
        end
        state.tiles = keep
    end

    -- ---- 再把合并结果写进存活方块（放在移除之后，避免被误删）----
    for i = 1, #merges do
        local m = merges[i]
        m.tile.value = m.value
        if m.value > (state.maxReached or 0) then state.maxReached = m.value end
    end

    state.score = state.score + gained
    state.steps = state.steps + 1

    -- ---- 每次有效移动后补一个新数字 ----
    local spawnTile = M.spawn()
    local spawnInfo = nil
    if spawnTile then
        spawnInfo = { tile = spawnTile, id = spawnTile.id, r = spawnTile.r,
                      c = spawnTile.c, value = spawnTile.value }
    end

    return {
        dir = dir,
        moves = moves,
        merges = merges,
        removed = removed,
        spawn = spawnInfo,
        gained = gained,
        scoreBefore = scoreBefore,
        scoreAfter = state.score,
        steps = state.steps,
    }
end

-- ================================================================
-- 开局 / 重开
-- ================================================================
function M.reset()
    state.tiles = {}
    state.score = 0
    state.steps = 0
    state.nextTileId = 1
    state.undoStack = {}
    state.maxReached = 0
    state.won = false
    state.winHandled = false
    state.dead = false
    state.deadHandled = false
    state.phase = "playing"
    state.scoreShown = 0

    local n = math.max(1, math.floor(config.DEFAULT_START_TILES or 2))
    for _ = 1, n do M.spawn() end
end

-- ================================================================
-- ★ 对外唯一入口：先记历史，再移动；若纹丝不动则把刚记的历史丢掉
--   （撤销栈里只有「真正的有效移动」，这样「撤销一步」不会空转）
-- ================================================================
function M.tryMove(dir)
    pushUndo()
    local action = M.move(dir)
    if not action then
        table.remove(state.undoStack)     -- 无效移动：撤回刚压入的快照
        return nil
    end
    return action
end

return M
