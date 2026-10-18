-- ================================================================
-- 点灯迷题 16 · 8×8 小关模型（纯计算，不碰控件）
-- ================================================================
-- 盘面用一维数组 1..64，下标 = y*8 + x（0 基），即 board[y*8+x+1]。
-- 按一格：翻转自身 + 上下左右（越界只翻存在的）。
--
-- ★ 8×8 十字核满秩（64/64）⇒ 解唯一，最优步数 = |A|。
--   所以本作不需要解方程：生成时把 A 记下来，它既是答案也是最优解。
-- ================================================================

---@diagnostic disable: undefined-global

local M = {}
local config = require("default_import_file/config")

local N = 8

function M.size()
    return math.floor(tonumber(config.DEFAULT_ROWS) or N)
end

function M.count()
    local n = M.size()
    return n * n
end

-- x,y（1 基）→ 0 基下标
function M.idx(x, y)
    local n = M.size()
    if x < 1 or x > n or y < 1 or y > n then return -1 end
    return (y - 1) * n + (x - 1)
end

-- 0 基下标 → x,y（1 基）
function M.xy(i)
    local n = M.size()
    if i < 0 or i >= n * n then return -1, -1 end
    return (i % n) + 1, math.floor(i / n) + 1
end

function M.valid(i)
    return i >= 0 and i < M.count()
end

-- ================================================================
-- ★ 被牵动的格子：{ {idx=, dist=}, ... }，dist 0=中心 1=四邻
-- ================================================================
function M.toggleSetOf(i)
    local out = {}
    if not M.valid(i) then return out end
    local n = M.size()
    local x, y = M.xy(i)
    local dirs = { { 0, 0 }, { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }
    for k = 1, 5 do
        local nx, ny = x + dirs[k][1], y + dirs[k][2]
        if nx >= 1 and nx <= n and ny >= 1 and ny <= n then
            out[#out + 1] = { idx = M.idx(nx, ny), dist = (k == 1) and 0 or 1 }
        end
    end
    table.sort(out, function(a, b)
        if a.dist ~= b.dist then return a.dist < b.dist end
        return a.idx < b.idx
    end)
    return out
end

function M.press(b, i)
    if type(b) ~= "table" then return b end
    local list = M.toggleSetOf(i)
    for k = 1, #list do
        local j = list[k].idx + 1
        b[j] = (b[j] == 1) and 0 or 1
    end
    return b
end

-- 由 8×8 象限（1 基二维数组）建盘面
function M.fromQuad(quad)
    local n = M.size()
    local b = {}
    for y = 1, n do
        for x = 1, n do
            b[(y - 1) * n + x] = (quad[y] and quad[y][x] == 1) and 1 or 0
        end
    end
    return b
end

function M.copy(b)
    local out = {}
    for i = 1, #b do out[i] = b[i] end
    return out
end

function M.litCount(b)
    local n = 0
    for i = 1, #b do
        if b[i] == 1 then n = n + 1 end
    end
    return n
end

function M.equals(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    for i = 1, #a do
        if (a[i] or 0) ~= (b[i] or 0) then return false end
    end
    return true
end

function M.isBlank(b)
    for i = 1, #b do
        if b[i] == 1 then return false end
    end
    return true
end

-- ================================================================
-- 确定性随机（Lehmer LCG，纯整数运算，Lua 5.1 也能跑）
-- ================================================================
function M.seedOf(text, salt)
    local s = 2166136261
    local str = tostring(text or "") .. "|" .. tostring(salt or 0)
    for i = 1, #str do
        s = (s * 131 + str:byte(i)) % 2147483647
    end
    return s
end

function M.newRng(seed)
    local s = math.floor(tonumber(seed) or 1) % 2147483647
    if s <= 0 then s = s + 2147483646 end
    return function(n)
        s = (s * 48271) % 2147483647
        if n <= 1 then return 1 end
        return (s - 1) % n
    end
end

-- ================================================================
-- ★ 生成一关：先有目标 P，再随机 A，S = P ⊕ R(A)（逆向构造，必然可解）
--   返回 { start = 盘面, a = {下标...}, target = 盘面 }
-- ================================================================
function M.genLevel(quad, k, seed)
    local target = M.fromQuad(quad)
    local start = M.copy(target)
    local n = M.count()
    k = math.max(0, math.min(n, math.floor(tonumber(k) or 0)))

    local cells = {}
    for i = 0, n - 1 do cells[i + 1] = i end

    local rnd = M.newRng(seed)
    -- Fisher-Yates 取前 k 个
    for i = n, 2, -1 do
        local j = rnd(i)
        cells[i], cells[j] = cells[j], cells[i]
    end

    local a = {}
    for i = 1, k do
        a[i] = cells[i]
        M.press(start, cells[i])
    end
    table.sort(a)

    return { start = start, a = a, target = target }
end

-- ================================================================
-- 剩余解（A ⊕ 已按），升序数组；用于「提示」
-- ================================================================
function M.remaining(a, history)
    local set = {}
    for i = 1, #a do set[a[i]] = not set[a[i]] and true or nil end
    for i = 1, #history do
        local idx = history[i]
        set[idx] = not set[idx] and true or nil
    end
    local out = {}
    for i = 0, M.count() - 1 do
        if set[i] then out[#out + 1] = i end
    end
    table.sort(out)
    return out
end

function M.hintCell(a, history)
    local rest = M.remaining(a, history)
    if #rest == 0 then return -1 end
    return rest[1]
end

return M
