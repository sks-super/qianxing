-- ================================================================
-- 工具模块（包含尖刺、失败等）
-- ================================================================

---@diagnostic disable: undefined-global


local M = {}
local state = require("state")
local config = require("config")
local bladeTrail = require("bladeTrail")
local audio = require("audio")     -- 音效管理模块
local signal = require("signal")   -- 客户端事件信号模块

-- ★ 创建UI控件（parent 可选：指定容器父节点；缺省挂到 state.parent 根）
function M.createControl(ctrlId, x, y, w, h, color, parent)
    local ctrl = game.InstantiateClientUIControl(ctrlId, parent or state.parent)
    if not ctrl then return nil end
    ctrl:SetAnchorMin(0.5, 0.5)
    ctrl:SetAnchorMax(0.5, 0.5)
    ctrl:SetPivot(0.5, 0.5)
    ctrl:SetSizeDelta(w, h)
    if color then ctrl.imageColor = color end
    ctrl:SetAnchoredPosition(x, y)
    ctrl:SetActive(true)
    return ctrl
end

-- ★ 仅按模板创建控件（用于已做好的模板，如绳桩/容器节点）：
--    只在其位置实例化并定位，不额外设置大小、颜色等，保留模板自身外观。
--    parent 可选：指定容器父节点；缺省挂到 state.parent 根。
function M.createTemplateControl(ctrlId, x, y, parent)
    local ctrl = game.InstantiateClientUIControl(ctrlId, parent or state.parent)
    if not ctrl then return nil end
    ctrl:SetAnchorMin(0.5, 0.5)
    ctrl:SetAnchorMax(0.5, 0.5)
    ctrl:SetPivot(0.5, 0.5)
    ctrl:SetAnchoredPosition(x, y)
    ctrl:SetActive(true)
    return ctrl
end

-- ★ 按模板创建控件并应用尺寸与旋转（用于带几何参数的模板：尖刺/木板等矩形）。
--    实例化后设置宽高（SetSizeDelta）与旋转（SetLocalRotation），位置不变；
--    保留模板自身外观，仅把其缩放到关卡参数给定的矩形框内。
--    parent 可选：指定容器父节点；缺省挂到 state.parent 根。
function M.createTemplateSizedControl(ctrlId, x, y, w, h, rotation, parent)
    local ctrl = game.InstantiateClientUIControl(ctrlId, parent or state.parent)
    if not ctrl then return nil end
    ctrl:SetAnchorMin(0.5, 0.5)
    ctrl:SetAnchorMax(0.5, 0.5)
    ctrl:SetPivot(0.5, 0.5)
    ctrl:SetSizeDelta(w, h)
    ctrl:SetAnchoredPosition(x, y)
    ctrl:SetLocalRotation(0, 0, rotation or 0)
    ctrl:SetActive(true)
    return ctrl
end

-- UI辅助
function M.setMessage(text)
    if state.messageText then state.messageText.text = text end
end

-- ★ 更新得分显示
function M.updateScoreDisplay()
    if state.scoreText then
        state.scoreText.text = "⭐ " .. state.score
    end
end

-- ★ 收集星星检测
function M.collectStars()
    if state.gameWon or state.gameFailed then return end
    if not state.candyNode or not state.candyNode.isActive then return end
    local cx, cy = state.candyNode.x, state.candyNode.y
    local collectDist = config.COLLECT_DIST or 25
    local collected = 0
    for _, star in ipairs(state.stars) do
        if star.active then
            local dx = cx - star.x
            local dy = cy - star.y
            if dx*dx + dy*dy <= collectDist*collectDist then
                star.active = false
                if star.ctrl then star.ctrl:SetActive(false) end
                state.score = state.score + 1
                collected = collected + 1
            end
        end
    end
    if collected > 0 then
        M.updateScoreDisplay()
        M.setMessage("收集了 "..collected.." 颗星星！")
        audio.playStar()   -- ★ 收集星星音效
        signal.send("收集到星星", "客户端事件")   -- ★ 收集星星事件上报：信号名“客户端事件”，参数“收集到星星”
    end
end

-- ★ 泡泡碰撞检测
function M.checkBubbleCollision()
    if state.gameWon or state.gameFailed then return end
    if not state.candyNode or not state.candyNode.isActive then return end
    local cx, cy = state.candyNode.x, state.candyNode.y
    local candyRadius = state.candyNode.radius
    for _, bubble in ipairs(state.bubbles) do
        if bubble.active and not bubble.isWrapping then
            local dx = cx - bubble.x
            local dy = cy - bubble.y
            local dist = math.sqrt(dx*dx + dy*dy)
            if dist <= bubble.radius + candyRadius then
                bubble.isWrapping = true
                state.candyWrapped = true
                state.wrappedGravity = bubble.upward_gravity
                M.setMessage("糖果被泡泡包裹！")
                break
            end
        end
    end
end

-- ★ 点击泡泡戳破
function M.popBubble(bubble)
    if not bubble or not bubble.active then return end
    bubble.active = false
    bubble.isWrapping = false
    if bubble.ctrl then bubble.ctrl:SetActive(false) end
    state.candyWrapped = false
    state.wrappedGravity = 0
    M.setMessage("泡泡被戳破！")
    audio.playBubble()
    signal.send("戳破泡泡")
end

-- ★ 尖刺碰撞检测（矩形 OBB：将糖果点变换到尖刺局部坐标系判定）
function M.checkSpikeCollision()
    if state.gameWon or state.gameFailed then return end
    if not state.candyNode or not state.candyNode.isActive then return end
    local cx, cy = state.candyNode.x, state.candyNode.y
    local candyRadius = state.candyNode.radius
    for _, spike in ipairs(state.spikes) do
        if spike.active then
            -- 把糖果点变换到尖刺（矩形）局部坐标系，做 OBB 碰撞检测
            local dx = cx - spike.x
            local dy = cy - spike.y
            local rad = (spike.rotation or 0) * math.pi / 180
            local cosr = math.cos(rad)
            local sinr = math.sin(rad)
            -- 逆旋转（与 SetLocalRotation(0,0,rotation) 对应：局部 = R(-rot)·(dx,dy)）
            local lx = dx * cosr + dy * sinr
            local ly = -dx * sinr + dy * cosr
            local halfW = (spike.width or 24) / 2 + candyRadius
            local halfL = (spike.length or 40) / 2 + candyRadius
            if math.abs(lx) <= halfW and math.abs(ly) <= halfL then
                if state.cheatMode then
                    -- 弹性反弹：沿最小穿透轴推出并重定向速度
                    local penX = halfW - math.abs(lx)
                    local penY = halfL - math.abs(ly)
                    local nx, ny, pushLx, pushLy
                    if penX < penY then
                        local sign = lx >= 0 and 1 or -1
                        nx = cosr * sign
                        ny = sinr * sign
                        pushLx = lx + sign * penX
                        pushLy = ly
                    else
                        local sign = ly >= 0 and 1 or -1
                        nx = -sinr * sign
                        ny = cosr * sign
                        pushLx = lx
                        pushLy = ly + sign * penY
                    end
                    state.candyNode.x = spike.x + pushLx * cosr - pushLy * sinr
                    state.candyNode.y = spike.y + pushLx * sinr + pushLy * cosr
                    local vn = state.candyNode.vx * nx + state.candyNode.vy * ny
                    if vn < 0 then
                        local k = config.DEFAULT_CHEAT_BOUNCE_FACTOR or 0.8
                        state.candyNode.vx = state.candyNode.vx - (1 + k) * vn * nx
                        state.candyNode.vy = state.candyNode.vy - (1 + k) * vn * ny
                    end
                    cx, cy = state.candyNode.x, state.candyNode.y
                else
                    M.failGame("💀 糖果碰到尖刺了！")
                    return
                end
            end
        end
    end
end

-- ★ 失败处理
function M.failGame(reason)
    if state.gameFailed then return end
    state.gameFailed = true
    state.isDragging = false
    M.setMessage(reason .. " 按 R 重新开始")
    audio.playFail()
    signal.send("游戏失败")
end

-- 连接绳子
function M.connectRope(rope)
    if rope.isConnected or rope.isCut then return end
    rope.isConnected = true
    for _, dot in ipairs(rope.dots) do
        if dot then dot:SetActive(false) end
    end
    if rope.fixedCtrl then rope.fixedCtrl:SetActive(true) end
    for idx, node in ipairs(rope.nodes) do
        if idx ~= rope.fixedIndex and idx ~= rope.candyIndex then
            node.isActive = true
        end
    end
    M.setMessage("绳子已连接！")
end

function M.disconnectRope(rope)
    if not rope.isConnected or rope.isCut then return end
    rope.isConnected = false
    for _, dot in ipairs(rope.dots) do
        if dot then dot:SetActive(true) end
    end
    for idx, node in ipairs(rope.nodes) do
        if idx ~= rope.fixedIndex and idx ~= rope.candyIndex then
            if node.ctrl then node.ctrl:SetActive(false) end
            node.isActive = false
        end
    end
    for _, seg in ipairs(rope.segments) do
        if seg.ctrl then seg.ctrl:SetActive(false) end
    end
    M.setMessage("绳子已断开")
end

-- 连接检测
function M.checkConnections()
    for _, rope in ipairs(state.ropes) do
        if not rope.isCut and not rope.isConnected then
            local fixedNode = rope.nodes[rope.fixedIndex]
            if fixedNode then
                local dx = state.candyNode.x - fixedNode.x
                local dy = state.candyNode.y - fixedNode.y
                local dist = math.sqrt(dx*dx + dy*dy)
                if dist <= rope.triggerRadius then
                    M.connectRope(rope)
                end
            end
        end
    end
end

-- 切割检测
function M.checkCut(prevX, prevY, curX, curY)
    if state.gameWon or state.gameFailed then return end
    local cutCount = 0
    for _, rope in ipairs(state.ropes) do
        if not rope.isCut and rope.isConnected and #rope.constraints > 0 then
            for i, con in ipairs(rope.constraints) do
                local a = rope.nodes[con.indexA + 1]
                local b = rope.nodes[con.indexB + 1]
                if a.isActive and b.isActive then
                    local ax, ay = a.x, a.y
                    local bx, by = b.x, b.y

                    local function cross(ox, oy, px, py, qx, qy)
                        return (px - ox) * (qy - oy) - (py - oy) * (qx - ox)
                    end

                    local d1 = cross(ax, ay, bx, by, prevX, prevY)
                    local d2 = cross(ax, ay, bx, by, curX, curY)
                    local d3 = cross(prevX, prevY, curX, curY, ax, ay)
                    local d4 = cross(prevX, prevY, curX, curY, bx, by)

                    if ((d1 > 0 and d2 < 0) or (d1 < 0 and d2 > 0)) and
                       ((d3 > 0 and d4 < 0) or (d3 < 0 and d4 > 0)) then
                        rope.isCut = true
                        rope.isConnected = false
                        rope.constraints = {}
                        for idx, node in ipairs(rope.nodes) do
                            if idx ~= rope.fixedIndex and idx ~= rope.candyIndex then
                                if node.ctrl then node.ctrl:SetActive(false) end
                                node.isActive = false
                            end
                        end
                        for _, seg in ipairs(rope.segments) do
                            if seg.ctrl then seg.ctrl:SetActive(false) end
                        end
                        -- ★ 割断后绳桩(固定点)保持显示，不随绳子一起消失
                        for _, dot in ipairs(rope.dots) do
                            if dot then dot:SetActive(false) end
                        end
                        cutCount = cutCount + 1
                        break
                    end
                end
            end
        end
    end
    if cutCount > 0 then
        M.setMessage("切断了 "..cutCount.." 根绳子！")
        audio.playCut()
        signal.send("切断绳子")
    end
end

-- 胜利检测
function M.checkWin()
    if state.gameWon or state.gameFailed then return end
    if not state.isDragging and state.candyNode and state.candyNode.isActive then
        if state.candyNode.x > state.target.x - state.target.width/2 and state.candyNode.x < state.target.x + state.target.width/2
           and state.candyNode.y > state.target.y - state.target.height/2 and state.candyNode.y < state.target.y + state.target.height/2 then
            state.gameWon = true
            M.setMessage("🎉 糖果掉入嘴巴！按 R 重置，T 下一关，P 上一关")
            audio.playWin()
            -- ★ 关卡胜利信号：参数为两整数（关卡序号、本关收集星星数）
            signal.sendLevelWin(state.currentLevelIndex, state.score)
        end
    end
end

-- ================================================================
-- ★ 输入事件辅助（引擎把鼠标与手机触屏统一为 Cursor 事件）
--   CursorEventData: touchId(触点 ID) / GetUIPos()(当前 UI 坐标) /
--                    GetPressUIPos()(按下时 UI 坐标)
-- ================================================================

-- 取事件携带的触点 ID；拿不到返回 nil
local function eventTouchId(data)
    if not data then return nil end
    local ok, v = pcall(function() return data.touchId end)
    if ok and v ~= nil then return v end
    return nil
end

-- 取事件携带的 UI 坐标：GetUIPos → GetPressUIPos → game.GetCursorUIPos 逐级兜底
local function eventUIPos(data)
    local x, y
    if data then
        local ok
        ok, x, y = pcall(function() return data:GetUIPos() end)
        if not ok or type(x) ~= "number" or type(y) ~= "number" then
            ok, x, y = pcall(function() return data:GetPressUIPos() end)
            if not ok or type(x) ~= "number" or type(y) ~= "number" then
                x, y = nil, nil
            end
        end
    end
    if type(x) ~= "number" or type(y) ~= "number" then
        x, y = game.GetCursorUIPos()
    end
    return x, y
end

-- ★ 鼠标/触屏按下（增加点击泡泡检测）。
--   触屏：只认第一根手指为“切割手指”，其余触点按下直接忽略；
--   坐标优先取事件数据（不依赖系统光标，避免多指时跟错手指）。
function M.onMouseDown(data)
    if state.gameWon or state.gameFailed then return end

    -- ★ 触屏单指切割锁：已有手指在操作时，后续触点不参与
    if state.deviceIsTouch then
        if state.activeTouchId ~= nil then return end
        state.activeTouchId = eventTouchId(data)
    end

    local ux, uy = eventUIPos(data)
    if not ux or not uy then
        if state.deviceIsTouch then state.activeTouchId = nil end
        return
    end
    state.isMouseDown = true
    state.curUX = ux
    state.curUY = uy
    local worldX = ux - state.canvasW/2
    local worldY = uy - state.canvasH/2
    state.lastMouseX = worldX
    state.lastMouseY = worldY

    -- ★ 启动刀光拖尾：只要按住，就先记录起点；后续若进入拖拽状态则不再生成新片段
    bladeTrail.startTrail(worldX, worldY)

    -- 检测是否点击到泡泡（包括包裹中的）
    for _, bubble in ipairs(state.bubbles) do
        if bubble.active then
            local bx, by
            if bubble.isWrapping and state.candyNode then
                bx, by = state.candyNode.x, state.candyNode.y
            else
                bx, by = bubble.x, bubble.y
            end
            local dx = worldX - bx
            local dy = worldY - by
            if dx*dx + dy*dy <= (bubble.radius * 1.5)^2 then
                M.popBubble(bubble)
                return
            end
        end
    end

    -- 检测是否点击到糖果（拖拽）—— 仅开挂模式可用
    if state.cheatMode and state.candyNode and state.candyNode.isActive then
        local dx = worldX - state.candyNode.x
        local dy = worldY - state.candyNode.y
        if dx*dx + dy*dy <= (state.candyNode.radius * 1.5)^2 then
            state.isDragging = true
            state.candyNode.vx = 0
            state.candyNode.vy = 0
            state.candyNode.x = worldX
            state.candyNode.y = worldY
            state.candyNode.ctrl:SetAnchoredPosition(worldX, worldY)
            M.setMessage("拖拽糖果中...")
        end
    end
end

-- ★ 拖动中：把“当前活动触点”坐标刷成事件坐标（割绳判定在 OnUpdate 里消费）。
--   触屏上若引擎把系统光标跟到别的触点，这里用锁定的触点 ID 保证只跟随切割手指。
function M.onCursorDrag(data)
    if not state.isMouseDown then return end
    if state.deviceIsTouch then
        local tid = eventTouchId(data)
        if tid ~= nil and state.activeTouchId ~= nil and tid ~= state.activeTouchId then return end
    end
    local ux, uy = eventUIPos(data)
    if not ux or not uy then return end
    state.curUX = ux
    state.curUY = uy
end

-- ★ 鼠标/触屏抬起。
--   触屏：只有抬起“切割手指”才结束本次操作；其他触点抬起不影响当前切割。
function M.onMouseUp(data)
    if state.gameWon or state.gameFailed then return end

    -- ★ 触屏单指锁释放：校验抬起的是当前切割手指
    if state.deviceIsTouch then
        local tid = eventTouchId(data)
        if tid ~= nil and state.activeTouchId ~= nil and tid ~= state.activeTouchId then
            return
        end
        state.activeTouchId = nil
    end

    state.isMouseDown = false
    if state.isDragging then
        state.isDragging = false
        M.setMessage("按住鼠标划过绳子以切断它")
    end
    -- ★ 停止生成新刀光片段，已存在片段会继续淡出
    bladeTrail.stopTrail()
end

-- ★ 在按下期间检测泡泡戳破（持续检测，跟随当前活动点）
function M.checkBubblePop()
    if state.gameWon or state.gameFailed then return end
    if not state.isMouseDown then return end
    local ux, uy = state.curUX, state.curUY
    if not ux or not uy then return end
    local worldX = ux - state.canvasW/2
    local worldY = uy - state.canvasH/2

    for _, bubble in ipairs(state.bubbles) do
        if bubble.active then
            local bx, by
            if bubble.isWrapping and state.candyNode then
                bx, by = state.candyNode.x, state.candyNode.y
            else
                bx, by = bubble.x, bubble.y
            end
            local dx = worldX - bx
            local dy = worldY - by
            if dx*dx + dy*dy <= (bubble.radius * 1.5)^2 then
                M.popBubble(bubble)
                return true
            end
        end
    end
    return false
end

-- 拖拽更新
function M.updateDragging()
    if state.gameWon or state.gameFailed then return end
    -- 开挂模式关闭时，终止进行中的拖拽（糖果回到物理接管）
    if not state.cheatMode then
        if state.isDragging then state.isDragging = false end
        return
    end
    if not state.isDragging or not state.candyNode or state.gameWon then return end
    local ux, uy = state.curUX, state.curUY
    if not ux or not uy then return end
    local worldX = ux - state.canvasW/2
    local worldY = uy - state.canvasH/2
    for _, rope in ipairs(state.ropes) do
        if rope.isCut or not rope.isConnected or #rope.constraints == 0 then goto nextRope end
        local fixedNode = rope.nodes[rope.fixedIndex]
        if fixedNode then
            local dx = worldX - fixedNode.x
            local dy = worldY - fixedNode.y
            local dist = math.sqrt(dx*dx + dy*dy)
            local maxLen = rope.totalLength
            if dist > maxLen * state.MAX_DRAG_FACTOR then
                local ratio = maxLen * state.MAX_DRAG_FACTOR / dist
                worldX = fixedNode.x + dx * ratio
                worldY = fixedNode.y + dy * ratio
            end
        end
        ::nextRope::
    end
    state.candyNode.x = worldX
    state.candyNode.y = worldY
    state.candyNode.vx = 0
    state.candyNode.vy = 0
    state.candyNode.ctrl:SetAnchoredPosition(worldX, worldY)
    state.lastMouseX = worldX
    state.lastMouseY = worldY
end

return M