-- ================================================================
-- 点灯迷题 16 · 图案数据
--   ① 把 config 里的 16 行字符串解析成 0/1 点阵
--   ② 切出某个小关的 8×8 象限
--   ③ 分区上色：把白区按「从上到下」分配 主色/辅色/高光色（供通关上色演出用）
-- ================================================================

---@diagnostic disable: undefined-global

local M = {}

-- ★ artGrid 要读 config.ART64：漏了这条 require，artRects 一调就
--   「attempt to index a nil value (global 'config')」→ 通关演出建完四块
--   线稿后整段中断（飞入动画都没排上），表现为「演出一片空白」
local config = require("default_import_file/config")

local N = 16

-- 解析 16 行字符串 → 16×16 数组（pic[y+1][x+1] = 0/1，1 基）
-- ★★ 16×16 草图归一化：按墨迹 bbox 居中；能整除 16 时整数倍放大（最多 2 倍）。
--   手画的草图常常偏在一角、只占 10 格左右，直接铺进框里会显得又小又歪。
local function normalize(pic)
    local minx, maxx, miny, maxy = N + 1, 0, N + 1, 0
    for y = 1, N do
        local row = pic[y] or ""
        for x = 1, N do
            if row:sub(x, x) == "#" then
                if x < minx then minx = x end
                if x > maxx then maxx = x end
                if y < miny then miny = y end
                if y > maxy then maxy = y end
            end
        end
    end
    if maxx < minx then return pic end           -- 空图

    local w, h = maxx - minx + 1, maxy - miny + 1
    local s = 1
    if w * 2 <= N and h * 2 <= N then s = 2 end   -- 等比整数放大
    local nw, nh = w * s, h * s
    local ox = math.floor((N - nw) / 2)            -- 0 基偏移
    local oy = math.floor((N - nh) / 2)

    local out = {}
    for y = 1, N do out[y] = string.rep(".", N) end
    for y = 0, nh - 1 do
        local sy = miny + math.floor(y / s)
        local src = (pic[sy] or ""):sub(minx, maxx)
        local line = {}
        for x = 0, nw - 1 do
            local ch = src:sub(math.floor(x / s) + 1, math.floor(x / s) + 1)
            line[#line + 1] = (ch == "#") and "#" or "."
        end
        local body = table.concat(line)
        local row = out[oy + y + 1]
        out[oy + y + 1] = row:sub(1, ox) .. body .. row:sub(ox + nw + 1)
    end
    return out
end

function M.parse(pic, noNormalize)
    local src = pic
    if not noNormalize then src = normalize(pic) end
    local out = {}
    for y = 1, N do
        local row = src[y] or ""
        local line = {}
        for x = 1, N do
            line[x] = (row:sub(x, x) == "#") and 1 or 0
        end
        out[y] = line
    end
    return out
end

-- 取某像素（1 基）
function M.at(grid, x, y)
    local row = grid and grid[y]
    if not row then return 0 end
    return row[x] or 0
end

-- 切 8×8 象限：pieceIndex 1..4（左上/右上/左下/右下），原点 0 基
function M.quad(grid, ox, oy)
    local out = {}
    for y = 1, 8 do
        local row = {}
        for x = 1, 8 do
            row[x] = M.at(grid, ox + x, oy + y)
        end
        out[y] = row
    end
    return out
end

-- ================================================================
-- ★ 分区：白格四连通成区，外区与黑线记 0；内部区按质心从上到下编号 1..3
--   返回 16×16 的 slot（0 = 不染色，1..3 = 主色/辅色/高光色）
-- ================================================================
function M.regions(grid)
    local lab = {}
    for y = 1, N do
        lab[y] = {}
        for x = 1, N do lab[y][x] = -1 end
    end

    local labels = {}
    local cur = 0
    for y = 1, N do
        for x = 1, N do
            if M.at(grid, x, y) == 0 and lab[y][x] == -1 then
                cur = cur + 1
                local qx, qy = { x }, { y }
                local head = 1
                lab[y][x] = cur
                local cells = { { x, y } }
                while head <= #qx do
                    local cx, cy = qx[head], qy[head]
                    head = head + 1
                    local dirs = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
                    for i = 1, 4 do
                        local nx, ny = cx + dirs[i][1], cy + dirs[i][2]
                        if nx >= 1 and nx <= N and ny >= 1 and ny <= N
                           and M.at(grid, nx, ny) == 0 and lab[ny][nx] == -1 then
                            lab[ny][nx] = cur
                            qx[#qx + 1] = nx
                            qy[#qy + 1] = ny
                            cells[#cells + 1] = { nx, ny }
                        end
                    end
                end
                labels[cur] = cells
            end
        end
    end

    -- 外区 = 边界上那一区，不染色
    local outside = lab[1][1]
    local slots = {}
    for i = 1, cur do
        if i ~= outside and labels[i] and #labels[i] > 0 then
            local sy = 0
            for k = 1, #labels[i] do sy = sy + labels[i][k][2] end
            slots[#slots + 1] = { id = i, cy = sy / #labels[i] }
        end
    end
    table.sort(slots, function(a, b) return a.cy < b.cy end)

    local slotOf = {}
    for order, item in ipairs(slots) do
        slotOf[item.id] = ((order - 1) % 3) + 1
    end

    local out = {}
    for y = 1, N do
        out[y] = {}
        for x = 1, N do
            local l = lab[y][x]
            out[y][x] = (l >= 0 and slotOf[l]) or 0
        end
    end
    return out
end

-- ================================================================
-- ★ 64×64 彩色画：RLE 解码 + 无缝合矩形合并
--   为什么要合并：4096 个色块控件太重；同色水平段 + 同色矩形合并后一般只剩
--   一两百个，既轻又【绝不留缝】——每个矩形按像素整数边界摆放，相邻矩形之间
--   再叠 0.6px，避免引擎栅格化时在接缝处透出底色。
-- ================================================================
local CH = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"
local TRANSPARENT = 35

local function charIndex(c)
    if not c or c == "" then return nil end
    local i = CH:find(c, 1, true)
    if not i then return nil end
    return i - 1
end

local artCache = {}

-- 解码成 64×64 的调色板下标表（nil = 透明）
function M.artGrid(key)
    if artCache[key] ~= nil then return artCache[key] end
    local data = (config.ART64 or {})[key]
    if not data then
        artCache[key] = false
        return false
    end
    local rows = {}
    local S = 64
    for y = 1, S do
        local s = data.rows[y] or ""
        local line = {}
        local x = 1
        local i = 1
        while i <= #s and x <= S do
            local idx = charIndex(s:sub(i, i))
            local n = charIndex(s:sub(i + 1, i + 1))
            if not idx or not n then break end
            for _ = 1, n do
                if x <= S then
                    line[x] = (idx >= TRANSPARENT) and nil or idx
                    x = x + 1
                end
            end
            i = i + 2
        end
        rows[y] = line
    end
    local out = { rows = rows, pal = data.pal or {}, size = S }
    artCache[key] = out
    return out
end

-- 贪心合并：先向右扩展同色，再整段向下扩展 → 得到少量大矩形
function M.artRects(key)
    local g = M.artGrid(key)
    if not g then return nil end
    local S = g.size
    local used = {}
    for y = 1, S do used[y] = {} end
    local out = {}
    for y = 1, S do
        for x = 1, S do
            local idx = g.rows[y][x]
            if idx and not used[y][x] then
                local w = 0
                while x + w <= S and g.rows[y][x + w] == idx and not used[y][x + w] do
                    w = w + 1
                end
                local h = 1
                while y + h <= S do
                    local ok = true
                    for k = 0, w - 1 do
                        if g.rows[y + h][x + k] ~= idx or used[y + h][x + k] then
                            ok = false
                            break
                        end
                    end
                    if not ok then break end
                    h = h + 1
                end
                for yy = y, y + h - 1 do
                    for xx = x, x + w - 1 do used[yy][xx] = true end
                end
                out[#out + 1] = {
                    x = x - 1, y = y - 1,          -- 0 基像素坐标
                    w = w, h = h,
                    hex = g.pal[idx + 1] or "FFFFFF",
                }
            end
        end
    end
    return out, S
end

return M
