-- ================================================================
-- 物理模块（支持泡泡包裹，边界碰撞触发失败）
-- ================================================================

local M = {}
local state = require("state")
local config = require("config")   -- ★ 反弹参数：DEFAULT_CANDY_BOUNCE_MIN_VEL / FACTOR
local utils = require("utils")   -- 需要 utils 的失败函数，但为了避免循环，我们直接在 physics 中设置 state.gameFailed
local audio = require("audio")     -- 音效管理模块
local signal = require("signal")   -- 客户端事件信号模块

function M.updateCandyPhysics(dt)
    if state.gameWon or state.gameFailed or not state.candyNode or not state.candyNode.isActive then return end
    if state.isDragging then return end

    local subDt = dt / state.SUB_STEPS
    for _ = 1, state.SUB_STEPS do
        -- 重力
        if state.candyWrapped then
            state.candyNode.vy = state.candyNode.vy + state.wrappedGravity * subDt
        else
            state.candyNode.vy = state.candyNode.vy - state.GRAVITY * subDt
        end

        state.candyNode.vx = state.candyNode.vx * state.CANDY_DAMPING
        state.candyNode.vy = state.candyNode.vy * state.CANDY_DAMPING

        state.candyNode.x = state.candyNode.x + state.candyNode.vx * subDt
        state.candyNode.y = state.candyNode.y + state.candyNode.vy * subDt

        -- 泡泡跟随
        if state.candyWrapped then
            for _, bubble in ipairs(state.bubbles) do
                if bubble.isWrapping and bubble.active then
                    bubble.ctrl:SetAnchoredPosition(state.candyNode.x, state.candyNode.y)
                end
            end
        end

        -- 绳子长度约束
        for iter = 1, state.CONSTRAINT_ITERATIONS do
            for _, rope in ipairs(state.ropes) do
                if rope.isCut or not rope.isConnected or #rope.constraints == 0 then goto skip_rope end
                local fixedNode = rope.nodes[rope.fixedIndex]
                local candy = rope.nodes[rope.candyIndex]
                if fixedNode and candy and candy.isActive then
                    local dx = candy.x - fixedNode.x
                    local dy = candy.y - fixedNode.y
                    local dist = math.sqrt(dx*dx + dy*dy)
                    local maxLen = rope.totalLength
                    if dist > maxLen and dist > 0.001 then
                        local ratio = maxLen / dist
                        candy.x = fixedNode.x + dx * ratio
                        candy.y = fixedNode.y + dy * ratio
                        local nx = dx / dist
                        local ny = dy / dist
                        local vn = state.candyNode.vx * nx + state.candyNode.vy * ny
                        if vn > 0 then
                            -- ★ 绳边反弹：糖果被绷紧绳子拽住时
                            --   vn >= MIN_VEL → 反弹（速度反转 + 系数 = -k * vn）
                            --   vn <  MIN_VEL → 置 0（保持旧版行为）
                            local minV = config.DEFAULT_CANDY_BOUNCE_MIN_VEL or 80
                            local k    = config.DEFAULT_CANDY_BOUNCE_FACTOR  or 0.4
                            if vn >= minV and k > 0 then
                                -- 反弹：径向分量由 +vn 变成 -k*vn，即减去 (1+k)*vn
                                state.candyNode.vx = state.candyNode.vx - (1 + k) * vn * nx
                                state.candyNode.vy = state.candyNode.vy - (1 + k) * vn * ny
                            else
                                -- 原逻辑：仅消除外向径向分量，切向保留
                                state.candyNode.vx = state.candyNode.vx - vn * nx
                                state.candyNode.vy = state.candyNode.vy - vn * ny
                            end
                        end
                    end
                end
                ::skip_rope::
            end
        end

        -- ★ 木板碰撞（静态 OBB 障碍）：把糖果推出木板并沿法线反弹
        --   与尖刺碰撞同理先把糖果点变换到木板局部坐标系判定，
        --   取最小穿透轴作为法线方向，推出糖果后按 DEFAULT_BOARD_BOUNCE_FACTOR 反弹。
        local br = state.candyNode.radius
        for _, board in ipairs(state.boards) do
            local dx = state.candyNode.x - board.x
            local dy = state.candyNode.y - board.y
            local rad = (board.rotation or 0) * math.pi / 180
            local cosr = math.cos(rad)
            local sinr = math.sin(rad)
            -- 世界→局部（与 SetLocalRotation(0,0,rotation) 对应：局部 = R(-rot)·(dx,dy)）
            local lx = dx * cosr + dy * sinr
            local ly = -dx * sinr + dy * cosr
            local halfW = (board.width or 160) / 2 + br
            local halfL = (board.length or 24) / 2 + br
            if math.abs(lx) <= halfW and math.abs(ly) <= halfL then
                local penX = halfW - math.abs(lx)
                local penY = halfL - math.abs(ly)
                local nx, ny, pushLx, pushLy
                if penX < penY then
                    -- 法线沿局部 x 轴
                    local sign = lx >= 0 and 1 or -1
                    nx = cosr * sign
                    ny = sinr * sign
                    pushLx = lx + sign * penX
                    pushLy = ly
                else
                    -- 法线沿局部 y 轴
                    local sign = ly >= 0 and 1 or -1
                    nx = -sinr * sign
                    ny = cosr * sign
                    pushLx = lx
                    pushLy = ly + sign * penY
                end
                -- 局部→世界，写回糖果位置（推出木板）
                state.candyNode.x = board.x + pushLx * cosr - pushLy * sinr
                state.candyNode.y = board.y + pushLx * sinr + pushLy * cosr
                -- 沿世界法线反弹（vn<0 表示正撞向木板）
                local vn = state.candyNode.vx * nx + state.candyNode.vy * ny
                if vn < 0 then
                    local k = config.DEFAULT_BOARD_BOUNCE_FACTOR or 0.3
                    state.candyNode.vx = state.candyNode.vx - (1 + k) * vn * nx
                    state.candyNode.vy = state.candyNode.vy - (1 + k) * vn * ny
                end
            end
        end

        -- ★ 边界处理：开挂模式弹性反弹，否则触发失败
        local r = state.candyNode.radius
        if state.cheatMode then
            -- 弹性反弹：贴边并沿法线反转速度（按 DEFAULT_CHEAT_BOUNCE_FACTOR 衰减）
            local k = config.DEFAULT_CHEAT_BOUNCE_FACTOR or 0.8
            if state.candyNode.x - r < state.LEFT then
                state.candyNode.x = state.LEFT + r
                if state.candyNode.vx < 0 then state.candyNode.vx = -state.candyNode.vx * k end
            elseif state.candyNode.x + r > state.RIGHT then
                state.candyNode.x = state.RIGHT - r
                if state.candyNode.vx > 0 then state.candyNode.vx = -state.candyNode.vx * k end
            end
            if state.candyNode.y - r < state.BOTTOM then
                state.candyNode.y = state.BOTTOM + r
                if state.candyNode.vy < 0 then state.candyNode.vy = -state.candyNode.vy * k end
            elseif state.candyNode.y + r > state.TOP then
                state.candyNode.y = state.TOP - r
                if state.candyNode.vy > 0 then state.candyNode.vy = -state.candyNode.vy * k end
            end
        else
            local failed = false
            if state.candyNode.x - r < state.LEFT then
                state.candyNode.x = state.LEFT + r
                failed = true
            elseif state.candyNode.x + r > state.RIGHT then
                state.candyNode.x = state.RIGHT - r
                failed = true
            end
            if state.candyNode.y - r < state.BOTTOM then
                state.candyNode.y = state.BOTTOM + r
                failed = true
            elseif state.candyNode.y + r > state.TOP then
                state.candyNode.y = state.TOP - r
                failed = true
            end
            if failed then
                state.gameFailed = true
                state.isDragging = false
                audio.playFail()
                signal.send("游戏失败")
                if state.messageText then
                    state.messageText.text = "💀 糖果掉出边界了！按 R 重新开始"
                end
                -- 停止速度
                state.candyNode.vx = 0
                state.candyNode.vy = 0
                -- 由于失败，直接退出物理循环
                return
            end
        end
    end

    state.candyNode.ctrl:SetAnchoredPosition(state.candyNode.x, state.candyNode.y)
end

_G.updateCandyPhysics = M.updateCandyPhysics

function OnStart()
    print("physics模块已加载")
end

return M