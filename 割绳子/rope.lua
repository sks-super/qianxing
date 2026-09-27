-- ================================================================
-- 绳子模块（弧长等分 + 正确隐藏节点）
-- ================================================================

---@diagnostic disable: undefined-global

local M = {}
local config = require("config")
local catenary = require("catenary")
local state = require("state")
local utils = require("utils")
local render = require("render")   -- ★ 关键：加载 render 模块
local audio = require("audio")     -- 音效管理模块（绷直音效触发）

-- 创建绳子节点（挂到绳子容器 containerRope）
function M.createRopeNode(x, y, invMass, radius, color, visible, prefabId)
    prefabId = prefabId or state.fruitPrefabId
    local ctrl = utils.createControl(prefabId, x, y, radius*2, radius*2, color or Color.FromRGB(128,128,128), state.containerRope)
    if visible == false then
        if ctrl then
            ctrl:SetActive(false)
        end
    end
    local node = {
        x = x, y = y,
        radius = radius,
        ctrl = ctrl,
        isActive = true,
        invMass = invMass,
        visible = (visible ~= false),
    }
    return node
end

function M.createCandyNode(x, y)
    -- 糖果容器：透明、不渲染，作为蛋糕像素画的父级容器；挂到糖果容器 containerCandy
    -- 物理/拖拽逻辑继续移动此 control，整组像素子控件会一起跟随。
    local ctrl = utils.createControl(state.fruitPrefabId, x, y,
                                     config.CANDY_RADIUS*2, config.CANDY_RADIUS*2,
                                     Color.FromRGBA(0, 0, 0, 0), state.containerCandy)
    local node = {
        x = x, y = y,
        vx = 0, vy = 0,
        radius = config.CANDY_RADIUS,
        ctrl = ctrl,
        isActive = true,
        mass = 1.0,
        visible = true,
    }
    return node
end

-- 创建单个绳子对象
function M.createRope(ropeConfig, sharedCandy)
    local fixedX = ropeConfig.fixed.x
    local fixedY = ropeConfig.fixed.y
    local totalLength = ropeConfig.total_length
    local segLength = ropeConfig.seg_length
    -- trigger_radius 已合并进 total_length（绳长即连接触发半径）
    local triggerRadius = totalLength

    local numSegments = math.floor(totalLength / segLength + 0.5)
    if numSegments < 1 then numSegments = 1 end
    local actualTotal = numSegments * segLength

    local rope = {}
    rope.nodes = {}
    rope.constraints = {}
    rope.segments = {}
    rope.fixedX = fixedX
    rope.fixedY = fixedY
    rope.isCut = false
    rope.isConnected = false
    rope.totalLength = actualTotal
    rope.segLength = segLength
    rope.triggerRadius = triggerRadius
    rope.fixedCtrl = nil
    rope.dots = {}
    -- ★ 绷直音效追踪：上一帧糖果-固定点直线距离（dist）。
    --   触发条件 = (上一帧 dist < ratio*L) 且 (本帧 dist >= L)
    rope.prevDist = 0
    rope.tenseCooldown = 0

    -- 固定点（绳桩）：优先使用专用绳桩/容器节点模板（anchorPrefabId）。
    -- 绳桩是已做好的模板，仅在其位置创建即可，不额外设置大小、颜色。
    local anchorPrefabId = config.anchorPrefabId or 0
    local fixedNode
    if anchorPrefabId and anchorPrefabId > 0 then
        local anchorCtrl = utils.createTemplateControl(anchorPrefabId, fixedX, fixedY, state.containerRope)
        fixedNode = {
            x = fixedX, y = fixedY,
            radius = config.FIXED_POINT_RADIUS,
            ctrl = anchorCtrl,
            isActive = true,
            invMass = 0,
            visible = true,
        }
    else
        -- 未配置专用模板时回退：用 fruitPrefabId 并染红（保持旧行为）
        fixedNode = M.createRopeNode(fixedX, fixedY, 0, config.FIXED_POINT_RADIUS, Color.FromRGB(255, 50, 50), true)
    end
    table.insert(rope.nodes, fixedNode)
    rope.fixedCtrl = fixedNode.ctrl
    rope.fixedIndex = 1

    -- 中间节点（隐藏）
    for i = 1, numSegments - 1 do
        local t = i / numSegments
        local y = fixedY - t * actualTotal
        local x = fixedX + (i % 2 == 0 and -1 or 1) * 0.5
        local node = M.createRopeNode(x, y, 1, config.NODE_RADIUS, Color.FromRGB(80,80,80), false)
        table.insert(rope.nodes, node)
    end

    -- 末端节点：共享糖果
    local candy = sharedCandy or M.createCandyNode(fixedX, fixedY - actualTotal)
    table.insert(rope.nodes, candy)
    rope.candyIndex = #rope.nodes

    -- 距离约束
    for i = 1, #rope.nodes - 1 do
        table.insert(rope.constraints, {
            indexA = i-1,
            indexB = i,
            restLength = segLength
        })
    end

    -- 虚线圆点
    local dotRadius = config.DOT_RADIUS or 2
    local dotCount = config.DOT_COUNT or 24
    local alpha = config.UNCONNECTED_ALPHA or 0.6
    local color = Color.FromRGBA(255, 255, 255, math.floor(alpha * 255))
    for i = 1, dotCount do
        local angle = (i - 1) / dotCount * 2 * math.pi
        local dx = math.cos(angle) * triggerRadius
        local dy = math.sin(angle) * triggerRadius
        local dotX = fixedX + dx
        local dotY = fixedY + dy
        local ctrl = utils.createControl(state.fruitPrefabId, dotX, dotY, dotRadius*2, dotRadius*2, color, state.containerRope)
        if ctrl then
            table.insert(rope.dots, ctrl)
        end
    end

    return rope
end

-- ★ 更新单条绳子的形状（弧长等分）
function M.updateRopeShape(rope)
    if rope.isCut then
        -- 隐藏一切
        for idx, node in ipairs(rope.nodes) do
            if idx ~= rope.fixedIndex and idx ~= rope.candyIndex then
                if node.ctrl then node.ctrl:SetActive(false) end
                node.isActive = false
            end
        end
        for _, seg in ipairs(rope.segments) do
            if seg.ctrl then seg.ctrl:SetActive(false) end
        end
        for _, dot in ipairs(rope.dots) do
            if dot then dot:SetActive(false) end
        end
        return
    end

    if not rope.isConnected then
        -- 未连接：显示虚线圆，隐藏节点和线段
        for idx, node in ipairs(rope.nodes) do
            if idx ~= rope.fixedIndex and idx ~= rope.candyIndex then
                if node.ctrl then node.ctrl:SetActive(false) end
                node.isActive = false
            end
        end
        for _, seg in ipairs(rope.segments) do
            if seg.ctrl then seg.ctrl:SetActive(false) end
        end
        for _, dot in ipairs(rope.dots) do
            if dot then dot:SetActive(true) end
        end
        if rope.fixedCtrl then rope.fixedCtrl:SetActive(true) end
        return
    end

    -- 已连接：隐藏虚线圆，显示绳子
    for _, dot in ipairs(rope.dots) do
        if dot then dot:SetActive(false) end
    end

    if #rope.constraints == 0 then
        for _, seg in ipairs(rope.segments) do
            if seg.ctrl then seg.ctrl:SetActive(false) end
        end
        return
    end

    local nodes = rope.nodes
    local fixedIdx = rope.fixedIndex
    local candyIdx = rope.candyIndex
    local fixedNode = nodes[fixedIdx]
    local candy = nodes[candyIdx]

    if not fixedNode or not candy then return end

    local p1 = {x = fixedNode.x, y = fixedNode.y}
    local p2 = {x = candy.x, y = candy.y}
    local L = rope.totalLength

    local dx = p2.x - p1.x
    local dy = p2.y - p1.y
    local dist = math.sqrt(dx*dx + dy*dy)

    local function distributeStraight()
        if dist < 0.001 then
            for i = 2, #nodes - 1 do
                local t = (i - 1) / (#nodes - 1)
                nodes[i].x = p1.x + 0.1 * (i - 1)
                nodes[i].y = p1.y - t * L * 0.5
                if nodes[i].ctrl then
                    nodes[i].ctrl:SetAnchoredPosition(nodes[i].x, nodes[i].y)
                    nodes[i].ctrl:SetActive(false)   -- 隐藏节点
                end
            end
        else
            local nx = dx / dist
            local ny = dy / dist
            for i = 2, #nodes - 1 do
                local t = (i - 1) / (#nodes - 1)
                nodes[i].x = p1.x + nx * t * dist
                nodes[i].y = p1.y + ny * t * dist
                if nodes[i].ctrl then
                    nodes[i].ctrl:SetAnchoredPosition(nodes[i].x, nodes[i].y)
                    nodes[i].ctrl:SetActive(false)
                end
            end
        end
    end

    -- ★ 绷直音效触发：上一帧 prevDist < ratio*L，且本帧 dist >= L（拉满）
    --   ratio 默认 0.98，需从“明显松弛”状态被拉成直线才触发，避免小幅抖动反复播
    if L <= dist + 1e-6 then
        local ratio = config.DEFAULT_ROPE_TENSE_RATIO or 0.98
        if (rope.prevDist or 0) < ratio * L then
            if rope.tenseCooldown > 0 then rope.tenseCooldown = rope.tenseCooldown - 1 end
            if (rope.tenseCooldown <= 0) then
                audio.playTense()
                rope.tenseCooldown = config.DEFAULT_ROPE_TENSE_COOLDOWN or 0.5
            end
        end
        rope.prevDist = dist
        distributeStraight()
        return
    end
    -- 松弛分支：记录本帧 dist 供下次判定；连续绷直后会保留 >= L，下一帧不会重复触发
    rope.prevDist = dist

    local numSamples = 100
    local pts = catenary.solve_catenary(p1, p2, L, numSamples)
    if not pts or #pts < 2 then
        distributeStraight()
        return
    end

    -- 计算累计弧长
    local arcLengths = {0}
    for i = 2, #pts do
        local dx_ = pts[i].x - pts[i-1].x
        local dy_ = pts[i].y - pts[i-1].y
        local segLen = math.sqrt(dx_*dx_ + dy_*dy_)
        table.insert(arcLengths, arcLengths[#arcLengths] + segLen)
    end
    local totalArc = arcLengths[#arcLengths]
    if totalArc < 0.001 then
        distributeStraight()
        return
    end

    local numSegments = #nodes - 1
    local step = totalArc / numSegments

    local newPts = {}
    table.insert(newPts, pts[1])
    for seg = 1, numSegments - 1 do
        local targetArc = seg * step
        local idx = 1
        while idx < #arcLengths and arcLengths[idx+1] < targetArc do
            idx = idx + 1
        end
        if idx >= #arcLengths then
            table.insert(newPts, pts[#pts])
        else
            local frac = (targetArc - arcLengths[idx]) / (arcLengths[idx+1] - arcLengths[idx])
            local x = pts[idx].x + (pts[idx+1].x - pts[idx].x) * frac
            local y = pts[idx].y + (pts[idx+1].y - pts[idx].y) * frac
            table.insert(newPts, {x = x, y = y})
        end
    end
    table.insert(newPts, pts[#pts])

    -- ★ 赋值给中间节点，并隐藏控件
    for i = 2, #nodes - 1 do
        local pt = newPts[i]
        if pt then
            nodes[i].x = pt.x
            nodes[i].y = pt.y
            if nodes[i].ctrl then
                nodes[i].ctrl:SetAnchoredPosition(pt.x, pt.y)
                nodes[i].ctrl:SetActive(false)   -- ★ 隐藏节点控件
            end
        end
    end

    fixedNode.x = p1.x
    fixedNode.y = p1.y
    candy.x = p2.x
    candy.y = p2.y
    if fixedNode.ctrl then
        fixedNode.ctrl:SetActive(true)
        fixedNode.ctrl:SetAnchoredPosition(p1.x, p1.y)
    end
    if candy.ctrl then
        candy.ctrl:SetActive(true)
        candy.ctrl:SetAnchoredPosition(p2.x, p2.y)
    end
end

-- 更新所有绳子的形状，并触发样条渲染
function M.updateRopeNodesAll()
    for _, rope in ipairs(state.ropes) do
        M.updateRopeShape(rope)
    end
    -- ★ 调用 render 模块的样条渲染
    render.updateRopeVisualSpline()
end

-- 暴露给全局
_G.createCandyNode = M.createCandyNode
_G.createRope = M.createRope
_G.updateRopeNodesAll = M.updateRopeNodesAll

function OnStart()
    print("rope模块已加载")
end

return M

