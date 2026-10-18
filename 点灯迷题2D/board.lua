-- ================================================================
-- 点灯迷题 2D · 棋盘模型（纯计算，不碰任何控件）
-- ================================================================
-- 棋盘 5 行 × 6 列 = 30 格，一维下标 idx = 行 * 6 + 列（0 基）
--   （行从上往下 0..4，列从左往右 0..5）
-- 按下 idx：同时翻转「它自己」与「上下左右四个邻居」，越界忽略。
--
-- ★ 数学性质（本作两个功能的基石）：
--   ① 每次按压是「对合」：同一格按两次等于没按 → 撤销 = 再按一次；
--   ② 按压可交换：结果只与「按过的格子集合」有关，与顺序无关。
--   ⇒ 关卡由 flips 从全灭盘生成，那么
--      当前盘面全灭  ⟺  玩家按过的集合 ≡ flips 集合（模 2）
--   ⇒ 剩余解 = flips 集合 XOR 已按集合（对称差），**精确**，不用解方程。
--     提示与星级判定都直接用它。
-- ================================================================

---@diagnostic disable: undefined-global

local M = {}
local config = require("default_import_file/config")

-- ================================================================
-- 几何
-- ================================================================
function M.rows()
    return math.floor(tonumber(config.DEFAULT_ROWS) or 5)
end

function M.cols()
    return math.floor(tonumber(config.DEFAULT_COLS) or 6)
end

function M.cellCount()
    return M.rows() * M.cols()
end

-- 行列 → 一维下标（0 基）；越界返回 -1
function M.index(r, c)
    local rows, cols = M.rows(), M.cols()
    r = math.floor(tonumber(r) or -1)
    c = math.floor(tonumber(c) or -1)
    if r < 0 or r >= rows or c < 0 or c >= cols then return -1 end
    return r * cols + c
end

function M.rowOf(idx)
    idx = math.floor(tonumber(idx) or -1)
    if idx < 0 or idx >= M.cellCount() then return -1 end
    return math.floor(idx / M.cols())
end

function M.colOf(idx)
    idx = math.floor(tonumber(idx) or -1)
    if idx < 0 or idx >= M.cellCount() then return -1 end
    return idx % M.cols()
end

function M.valid(idx)
    idx = math.floor(tonumber(idx) or -1)
    return idx >= 0 and idx < M.cellCount()
end

-- ================================================================
-- ★ 被 idx 牵动的格子（自己 + 上下左右，越界忽略），返回升序数组
-- ================================================================
function M.toggleSetOf(idx)
    local out = {}
    local r, c = M.rowOf(idx), M.colOf(idx)
    if r < 0 then return out end
    local rows, cols = M.rows(), M.cols()
    local deltas = { { 0, 0 }, { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }
    for i = 1, #deltas do
        local nr, nc = r + deltas[i][1], c + deltas[i][2]
        if nr >= 0 and nr < rows and nc >= 0 and nc < cols then
            out[#out + 1] = nr * cols + nc
        end
    end
    table.sort(out)
    return out
end

-- ================================================================
-- ★ 带「涟漪距离」的牵动集合
--   dist = 0 → 被按的那格；1 → 上下左右
--   视觉层按 dist 错峰播放翻转，才有「光波扩散」的感觉。
--   返回 { { idx = , dist = }, ... }，按 dist 升序、同 dist 按 idx 升序。
-- ================================================================
function M.toggleSetWithDist(idx)
    local center = math.floor(tonumber(idx) or -1)
    local out = {}
    local list = M.toggleSetOf(center)
    for i = 1, #list do
        out[i] = { idx = list[i], dist = (list[i] == center) and 0 or 1 }
    end
    table.sort(out, function(a, b)
        if a.dist ~= b.dist then return a.dist < b.dist end
        return a.idx < b.idx
    end)
    return out
end

-- ================================================================
-- 盘面（Lua 数组 1..30，对应 idx 0..29）
-- ================================================================
function M.newBoard(fill)
    local n = M.cellCount()
    local b = {}
    for i = 1, n do b[i] = tonumber(fill) or 0 end
    return b
end

function M.get(board, idx)
    if type(board) ~= "table" then return 0 end
    return tonumber(board[idx + 1]) or 0
end

function M.set(board, idx, v)
    if type(board) ~= "table" then return end
    if not M.valid(idx) then return end
    board[idx + 1] = tonumber(v) or 0
end

-- ★ 按一次（原地翻转）
function M.press(board, idx)
    if type(board) ~= "table" then return board end
    if not M.valid(idx) then return board end
    local list = M.toggleSetOf(idx)
    for i = 1, #list do
        local k = list[i] + 1
        board[k] = (tonumber(board[k]) or 0) == 0 and 1 or 0
    end
    return board
end

-- 由解序列反推初始盘面（对全灭盘依次按下）
function M.boardFromFlips(flips)
    local b = M.newBoard(0)
    if type(flips) ~= "table" then return b end
    for i = 1, #flips do
        local idx = math.floor(tonumber(flips[i]) or -1)
        if M.valid(idx) then M.press(b, idx) end
    end
    return b
end

function M.isCleared(board)
    if type(board) ~= "table" then return true end
    for i = 1, M.cellCount() do
        if (tonumber(board[i]) or 0) ~= 0 then return false end
    end
    return true
end

function M.litCount(board)
    local n = 0
    if type(board) ~= "table" then return 0 end
    for i = 1, M.cellCount() do
        if (tonumber(board[i]) or 0) ~= 0 then n = n + 1 end
    end
    return n
end

-- ================================================================
-- ★ 集合工具：把「点位序列 / 按压历史」折成「按过的格子」标记表
-- ================================================================
function M.setOf(list)
    local set = {}
    if type(list) ~= "table" then return set end
    for i = 1, #list do
        local idx = math.floor(tonumber(list[i]) or -1)
        if M.valid(idx) then
            if set[idx] then set[idx] = nil else set[idx] = true end
        end
    end
    return set
end

-- ★ 剩余解 = flips 集合 XOR 已按集合（对称差），返回升序数组
function M.remaining(flips, history)
    local a = M.setOf(flips)
    local b = M.setOf(history)
    local out = {}
    for i = 0, M.cellCount() - 1 do
        if (a[i] and not b[i]) or (b[i] and not a[i]) then
            out[#out + 1] = i
        end
    end
    table.sort(out)
    return out
end

-- ★ 提示：剩余解里的第一格；已通关返回 -1
function M.hintCell(flips, history)
    local rest = M.remaining(flips, history)
    if #rest == 0 then return -1 end
    return rest[1]
end

return M
