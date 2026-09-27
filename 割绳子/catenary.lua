-- ================================================================
-- 悬链线求解模块
-- ================================================================

local M = {}

-- 自定义双曲函数
local function sinh(x)
    return (math.exp(x) - math.exp(-x)) / 2
end

local function cosh(x)
    return (math.exp(x) + math.exp(-x)) / 2
end

function M.solve_catenary(p1, p2, length, num_points)
    local x1, y1 = p1.x, p1.y
    local x2, y2 = p2.x, p2.y

    local reverse = (x1 > x2)

    local x_left, y_left, x_right, y_right
    if x1 < x2 then
        x_left, y_left = x1, y1
        x_right, y_right = x2, y2
    else
        x_left, y_left = x2, y2
        x_right, y_right = x1, y1
    end

    local dx = x_right - x_left
    local dy = y_right - y_left
    local dist = math.sqrt(dx*dx + dy*dy)

    if length <= dist + 1e-9 then
        local pts = {}
        for i = 0, num_points do
            local t = i / num_points
            table.insert(pts, {x = x_left + dx * t, y = y_left + dy * t})
        end
        if reverse then
            local rev = {}
            for i = #pts, 1, -1 do
                table.insert(rev, pts[i])
            end
            return rev
        end
        return pts
    end

    if math.abs(dx) < 1e-12 then
        local pts = {}
        for i = 0, num_points do
            local t = i / num_points
            local y = y_left + (y_right - y_left) * t
            table.insert(pts, {x = x_left, y = y})
        end
        if reverse then
            local rev = {}
            for i = #pts, 1, -1 do
                table.insert(rev, pts[i])
            end
            return rev
        end
        return pts
    end

    local C = math.sqrt(length*length - dy*dy) / dx
    if C <= 1 then
        local pts = {}
        for i = 0, num_points do
            local t = i / num_points
            local x = x_left + dx * t
            local y = y_left + dy * t
            table.insert(pts, {x = x, y = y})
        end
        if reverse then
            local rev = {}
            for i = #pts, 1, -1 do
                table.insert(rev, pts[i])
            end
            return rev
        end
        return pts
    end

    local r
    if C < 10 then
        r = math.sqrt(6 * (C - 1))
    else
        r = math.log(2 * C)
    end

    for _ = 1, 30 do
        local sinh_r = sinh(r)
        local cosh_r = cosh(r)
        local f = sinh_r / r - C
        local f_prime = (r * cosh_r - sinh_r) / (r * r)
        if math.abs(f_prime) < 1e-15 then break end
        local r_new = r - f / f_prime
        if math.abs(r_new - r) < 1e-14 then
            r = r_new
            break
        end
        r = r_new
    end

    if r < 1e-12 then
        local pts = {}
        for i = 0, num_points do
            local t = i / num_points
            local x = x_left + dx * t
            local y = y_left + dy * t
            table.insert(pts, {x = x, y = y})
        end
        if reverse then
            local rev = {}
            for i = #pts, 1, -1 do
                table.insert(rev, pts[i])
            end
            return rev
        end
        return pts
    end

    local a = dx / (2 * r)
    local ratio = dy / length
    if ratio > 0.999999 then ratio = 0.999999 end
    if ratio < -0.999999 then ratio = -0.999999 end
    local k = 0.5 * math.log((1 + ratio) / (1 - ratio))
    local b = (x_left + x_right) / 2 - k * a
    local c = y_left - a * cosh((x_left - b) / a)

    local pts = {}
    for i = 0, num_points do
        local t = i / num_points
        local x = x_left + dx * t
        local y = a * cosh((x - b) / a) + c
        table.insert(pts, {x = x, y = y})
    end

    if reverse then
        local rev = {}
        for i = #pts, 1, -1 do
            table.insert(rev, pts[i])
        end
        return rev
    end
    return pts
end

_G.solve_catenary = M.solve_catenary  -- 备选

function OnStart()
    print("catenary模块已加载")
end

return M