-- ================================================================
-- 点灯迷题 16 · 图案数据
--   ① 把 config 里的 16 行字符串解析成 0/1 点阵
--   ② 切出某个小关的 8×8 象限
--   ③ 分区上色：把白区按「从上到下」分配 主色/辅色/高光色（供通关上色演出用）
-- ================================================================

---@diagnostic disable: undefined-global

local M = {}

local N = 16

-- 解析 16 行字符串 → 16×16 数组（pic[y+1][x+1] = 0/1，1 基）
function M.parse(pic)
    local out = {}
    for y = 1, N do
        local row = pic[y] or ""
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

return M
