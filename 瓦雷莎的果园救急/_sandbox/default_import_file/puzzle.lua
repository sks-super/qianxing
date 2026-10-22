-- ================================================================
-- 瓦雷莎的果园救急 棋盘模型（纯计算，不碰任何控件）
-- ================================================================
-- 棋盘固定 5 行 × 6 列 = 30 格，一维下标 idx = 行 * 6 + 列
--   （行从上往下 0..4，列从左往右 0..5）
-- 按下 idx：同时翻转「它自己」与「上下左右四个邻居」，越界忽略。
--
-- ★ 客户端并不负责玩法结算（那是服务器节点图的活），
--   这个模块只给两处用：
--     ① 图文教程：把「按一个格子会怎样」画出来；
--     ② 胜利结算：驱动那排小灯格的亮灭动效。
--   顺带提供一个「按 flips 反推初始盘面」的本地实现，
--   便于调试时和节点图对账。
-- ================================================================

---@diagnostic disable: undefined-global

local M = {}
local config = require("default_import_file/config")

-- ================================================================
-- ★ 几何
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

-- 一维下标 → 行（0 基）；越界返回 -1
function M.rowOf(idx)
    idx = math.floor(tonumber(idx) or -1)
    if idx < 0 or idx >= M.cellCount() then return -1 end
    return math.floor(idx / M.cols())
end

-- 一维下标 → 列（0 基）；越界返回 -1
function M.colOf(idx)
    idx = math.floor(tonumber(idx) or -1)
    if idx < 0 or idx >= M.cellCount() then return -1 end
    return idx % M.cols()
end

-- ================================================================
-- ★ 与外部（信号 / 节点图 / 编辑器）交换用：数值 → 行列
--   为方便 3D 端做「第 idx 个方块」的映射，这里同时给出 1 基行列（行 1..5 / 列 1..6）
-- ================================================================
function M.row1Of(idx)
    local r = M.rowOf(idx)
    if r < 0 then return -1 end
    return r + 1
end

function M.col1Of(idx)
    local c = M.colOf(idx)
    if c < 0 then return -1 end
    return c + 1
end

-- ================================================================
-- ★ 被 idx 牵动的格子（自己 + 上下左右，越界忽略）
--   返回升序数组
-- ================================================================
function M.toggleSetOf(idx)
    local out = {}
    local r, c = M.rowOf(idx), M.colOf(idx)
    if r < 0 then return out end
    local rows, cols = M.rows(), M.cols()
    local deltas = { {0, 0}, {-1, 0}, {1, 0}, {0, -1}, {0, 1} }
    for _, d in ipairs(deltas) do
        local nr, nc = r + d[1], c + d[2]
        if nr >= 0 and nr < rows and nc >= 0 and nc < cols then
            out[#out + 1] = nr * cols + nc
        end
    end
    table.sort(out)
    return out
end

-- ================================================================
-- ★ 新盘面：30 个 0，下标 1..30 对应 idx 0..29（Lua 数组 1 基，内部偏移 1）
-- ================================================================
function M.newBoard(fill)
    local n = M.cellCount()
    local b = {}
    for i = 1, n do b[i] = tonumber(fill) or 0 end
    return b
end

-- 取 / 置（以 0 基 idx 访问）
function M.get(board, idx)
    if type(board) ~= "table" then return 0 end
    return tonumber(board[idx + 1]) or 0
end

function M.set(board, idx, v)
    if type(board) ~= "table" then return end
    if idx < 0 or idx >= M.cellCount() then return end
    board[idx + 1] = tonumber(v) or 0
end

-- ================================================================
-- ★ 按一次 idx（原地翻转 board）
-- ================================================================
function M.press(board, idx)
    if type(board) ~= "table" then return board end
    for _, t in ipairs(M.toggleSetOf(idx)) do
        board[t + 1] = (tonumber(board[t + 1]) or 0) == 0 and 1 or 0
    end
    return board
end

-- ================================================================
-- ★ 由解序列反推初始盘面
--   对「全灭盘」依次按下 flips 里每个格子 —— 这就是该关的初始局面。
--   （玩家再把这串格子各按一次即回到全灭，因为同一点按两次等于没按。）
-- ================================================================
function M.boardFromFlips(flips)
    local b = M.newBoard(0)
    if type(flips) ~= "table" then return b end
    for i = 1, #flips do
        local idx = math.floor(tonumber(flips[i]) or -1)
        if idx >= 0 and idx < M.cellCount() then
            M.press(b, idx)
        end
    end
    return b
end

-- ================================================================
-- ★ 初始棋盘的 30 格状态（信号「客服关卡参数」第 4 参 · 状态数组）
--   值域与信号一致：1 = 水果，-1 = 果汁。
--   推导：从「全水果」出发，依次踩 flips —— 得到的正是进关时的盘面；
--         玩家照 flips 再踩一遍就必定回到全水果。
--   （内部仍用 0/1 盘做异或，最后统一映射成 1/-1，避免 press 吃错值域。）
--   返回 1..30，下标 i 对应 idx = i - 1。
-- ================================================================
function M.initStatesFromFlips(flips)
    local b = M.newBoard(1)   -- 全水果起步
    if type(flips) == "table" then
        for i = 1, #flips do
            local idx = math.floor(tonumber(flips[i]) or -1)
            if idx >= 0 and idx < M.cellCount() then
                M.press(b, idx)
            end
        end
    end
    local out = {}
    for i = 1, M.cellCount() do
        out[i] = (tonumber(b[i]) or 0) ~= 0 and 1 or -1
    end
    return out
end

-- 状态数组 → 水果 / 果汁 个数（调试与校验用）
function M.countStates(states)
    local fruit, juice = 0, 0
    for i = 1, M.cellCount() do
        local v = tonumber(states and states[i]) or 0
        if v > 0 then fruit = fruit + 1 elseif v < 0 then juice = juice + 1 end
    end
    return fruit, juice
end

-- ================================================================
-- ★ 盘面是否全灭 / 亮灯数量
-- ================================================================
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

return M
