-- ================================================================
-- 渲染模块（增强调试版）
-- ================================================================

---@diagnostic disable: undefined-global


local M = {}
local config = require("config")
local state = require("state")
local utils = require("utils")

function M.updateRopeVisualSpline()
    for _, rope in ipairs(state.ropes) do
        -- 跳过未连接或已切断的绳子
        if rope.isCut or not rope.isConnected or #rope.constraints == 0 then
            for _, seg in ipairs(rope.segments) do
                if seg.ctrl then seg.ctrl:SetActive(false) end
            end
            goto continue
        end

        -- 收集活动节点坐标
        local pts = {}
        for _, node in ipairs(rope.nodes) do
            if node.isActive then
                table.insert(pts, {x = node.x, y = node.y})
            end
        end

        -- 如果节点数少于2，无法生成样条
        if #pts < 2 then
            for _, seg in ipairs(rope.segments) do
                if seg.ctrl then seg.ctrl:SetActive(false) end
            end
            goto continue
        end

        -- Catmull-Rom 插值函数
        local function catmullRom(p0, p1, p2, p3, t)
            local t2 = t * t
            local t3 = t2 * t
            local x = 0.5 * ((2*p1.x) + (-p0.x + p2.x)*t + (2*p0.x - 5*p1.x + 4*p2.x - p3.x)*t2 + (-p0.x + 3*p1.x - 3*p2.x + p3.x)*t3)
            local y = 0.5 * ((2*p1.y) + (-p0.y + p2.y)*t + (2*p0.y - 5*p1.y + 4*p2.y - p3.y)*t2 + (-p0.y + 3*p1.y - 3*p2.y + p3.y)*t3)
            return {x = x, y = y}
        end

        -- 生成样条点
        local splinePts = {}
        local n = #pts
        for i = 1, n-1 do
            local p0 = pts[math.max(i-1, 1)]
            local p1 = pts[i]
            local p2 = pts[i+1]
            local p3 = pts[math.min(i+2, n)]
            for s = 0, config.SPLINE_SUBDIVISIONS-1 do
                local t = s / config.SPLINE_SUBDIVISIONS
                local pt = catmullRom(p0, p1, p2, p3, t)
                table.insert(splinePts, pt)
            end
        end
        table.insert(splinePts, pts[n])

        local numSegs = #splinePts - 1
        -- ★ 调试输出：确认样条线段数
        -- print("[render] 样条线段数:", numSegs, " 已有线段控件:", #rope.segments)

        -- 确保线段控件数量足够
        while #rope.segments < numSegs do
            local ctrl = utils.createControl(state.fruitPrefabId, 0, 0, config.ROPE_THICKNESS, 10, Color.FromRGB(255, 255, 255), state.containerRope)
            if ctrl then
                table.insert(rope.segments, {ctrl = ctrl})
            else
                print("[render] 创建控件失败！")
                break
            end
        end
        -- 多余的线段隐藏
        while #rope.segments > numSegs do
            local seg = table.remove(rope.segments)
            if seg.ctrl then seg.ctrl:SetActive(false) end
        end

        -- 更新每个线段控件
        for i = 1, numSegs do
            local a = splinePts[i]
            local b = splinePts[i+1]
            local seg = rope.segments[i]
            if seg and seg.ctrl then
                local dx = b.x - a.x
                local dy = b.y - a.y
                local dist = math.sqrt(dx*dx + dy*dy)
                if dist > 0.001 then
                    local midX = (a.x + b.x) / 2
                    local midY = (a.y + b.y) / 2
                    local angle = math.atan(dy, dx) * 180 / math.pi
                    seg.ctrl:SetAnchoredPosition(midX, midY)
                    seg.ctrl:SetLocalRotation(0, 0, angle)
                    seg.ctrl:SetSizeDelta(dist, config.ROPE_THICKNESS)
                    seg.ctrl:SetActive(true)
                else
                    seg.ctrl:SetActive(false)
                end
            end
        end

        ::continue::
    end
end

_G.updateRopeVisualSpline = M.updateRopeVisualSpline

function OnStart()
    print("render模块已加载")
end

return M