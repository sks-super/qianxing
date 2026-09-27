-- ================================================================
-- TickHop 物理模块：玩家运动 + 计时平台 AABB 碰撞
--   采用「分轴解算」：先水平移动并解算碰撞，再垂直移动并解算碰撞，
--   可稳定处理贴墙、贴顶、落地等边界，不会在角落卡住。
--   平台只有 solid=true（当前秒数亮起）时才参与碰撞。
-- ================================================================

---@diagnostic disable: undefined-global

local M = {}
local state = require("state")
local config = require("config")
local audio = require("audio")

-- ================================================================
-- 数值逼近：把 cur 以最大步长 maxDelta 推向 target
-- ================================================================
local function approach(cur, target, maxDelta)
    if cur < target then
        cur = cur + maxDelta
        if cur > target then cur = target end
    elseif cur > target then
        cur = cur - maxDelta
        if cur < target then cur = target end
    end
    return cur
end

-- ================================================================
-- ★ 把玩家逻辑坐标同步到控件（含眼睛与朝向）
-- ================================================================
local function syncVisual()
    local pl = state.player
    if not pl then return end
    if pl.ctrl then
        pcall(function() pl.ctrl:SetAnchoredPosition(pl.x, pl.y) end)
    end
    local face = pl.face or 1
    if pl.eye1 then
        pcall(function() pl.eye1:SetAnchoredPosition(pl.x - pl.eyeDX * face, pl.y + pl.eyeDY) end)
    end
    if pl.eye2 then
        pcall(function() pl.eye2:SetAnchoredPosition(pl.x + pl.eyeDX * face, pl.y + pl.eyeDY) end)
    end
end

-- ================================================================
-- ★ 单个物理子步
-- ================================================================
local function step(subDt)
    local pl = state.player
    if not pl then return end

    -- ---------- 水平输入 → 速度 ----------
    local dir = 0
    if state.keyLeft then dir = dir - 1 end
    if state.keyRight then dir = dir + 1 end
    if dir ~= 0 then pl.face = dir end

    local target = dir * (state.MOVE_SPEED or 260)
    local accel = (pl.onGround and state.GROUND_ACCEL or state.AIR_ACCEL) or 2000
    local friction = (pl.onGround and state.GROUND_FRICTION or state.AIR_FRICTION) or 2000
    if dir ~= 0 then
        pl.vx = approach(pl.vx, target, accel * subDt)
    else
        pl.vx = approach(pl.vx, 0, friction * subDt)
    end

    -- ---------- 跳跃（缓冲 + 土狼时间） ----------
    if state.jumpBufferTimer > 0 and state.coyoteTimer > 0 then
        pl.vy = state.JUMP_SPEED or 520
        pl.onGround = false
        state.jumpBufferTimer = 0
        state.coyoteTimer = 0
        audio.playJump()
    end
    if state.jumpBufferTimer > 0 then
        state.jumpBufferTimer = state.jumpBufferTimer - subDt
        if state.jumpBufferTimer < 0 then state.jumpBufferTimer = 0 end
    end

    -- ---------- 重力 ----------
    local g = state.GRAVITY or 1600
    if pl.vy < 0 then g = g * (state.FALL_GRAVITY_MULT or 1.35) end
    pl.vy = pl.vy - g * subDt
    local maxFall = state.MAX_FALL_SPEED or 1000
    if pl.vy < -maxFall then pl.vy = -maxFall end

    -- ---------- X 轴移动 + 碰撞解算 ----------
    pl.x = pl.x + pl.vx * subDt
    for _, p in ipairs(state.platforms) do
        if p.solid then
            if math.abs(pl.x - p.x) < (pl.halfW + p.halfW)
               and math.abs(pl.y - p.y) < (pl.halfH + p.halfH) then
                if pl.vx > 0 then
                    pl.x = p.x - p.halfW - pl.halfW
                elseif pl.vx < 0 then
                    pl.x = p.x + p.halfW + pl.halfW
                end
                pl.vx = 0
            end
        end
    end

    -- ---------- Y 轴移动 + 碰撞解算 ----------
    local wasOnGround = pl.onGround
    pl.y = pl.y + pl.vy * subDt
    pl.onGround = false
    for _, p in ipairs(state.platforms) do
        if p.solid then
            if math.abs(pl.x - p.x) < (pl.halfW + p.halfW)
               and math.abs(pl.y - p.y) < (pl.halfH + p.halfH) then
                if pl.vy <= 0 then
                    -- 落到平台顶面
                    pl.y = p.y + p.halfH + pl.halfH
                    pl.vy = 0
                    pl.onGround = true
                else
                    -- 顶到平台底面
                    pl.y = p.y - p.halfH - pl.halfH
                    pl.vy = 0
                end
            end
        end
    end

    -- 土狼时间：离地后仍在宽限窗口内可起跳
    if pl.onGround then
        state.coyoteTimer = state.COYOTE_TIME or 0.10
    else
        state.coyoteTimer = math.max(0, (state.coyoteTimer or 0) - subDt)
    end

    -- 落地音效（带冷却，避免抖动时连播）
    if pl.onGround and not wasOnGround then
        if (state.landCooldown or 0) <= 0 then
            audio.playLand()
            state.landCooldown = config.DEFAULT_LAND_COOLDOWN or 0.10
        end
    end
end

-- ================================================================
-- ★ 每帧更新
-- ================================================================
function M.update(dt)
    local pl = state.player
    if not pl then return end
    if state.gameWon or state.gameFailed then return end
    if not dt or dt <= 0 then return end

    -- 冷却计时
    if (state.switchCooldown or 0) > 0 then
        state.switchCooldown = math.max(0, state.switchCooldown - dt)
    end
    if (state.landCooldown or 0) > 0 then
        state.landCooldown = math.max(0, state.landCooldown - dt)
    end

    -- 可变跳跃高度：松开跳跃键时截断上升速度（★ 只截断一次；
    -- 之前写成每帧乘 0.45，轻点一下会被连续削成几乎跳不起来）
    if not state.keyJump and pl.vy > 0 and not state.jumpCutDone then
        pl.vy = pl.vy * (state.JUMP_CUT_MULT or 0.45)
        state.jumpCutDone = true
    end

    -- 固定子步长推进，降低高速穿透风险
    local steps = math.max(1, math.floor(state.PHYSICS_SUBSTEPS or 4))
    local subDt = dt / steps
    for _ = 1, steps do
        step(subDt)
    end

    -- 掉出关卡边界 → 失败
    if pl.y < (state.stageBottom or -1000)
       or pl.y > (state.stageTop or 10000)
       or pl.x < (state.stageLeft or -10000)
       or pl.x > (state.stageRight or 10000) then
        state.gameFailed = true
        state.failReason = "fall_out"
    end

    syncVisual()
end

-- ================================================================
-- ★ 把玩家重置到出生点（关卡重开 / 角色死亡时调用）
-- ================================================================
function M.resetPlayer()
    local pl = state.player
    local data = state.currentLevelConfig
    if not pl or not data or not data.spawn then return end
    pl.x = data.spawn.x
    pl.y = data.spawn.y
    pl.vx = 0
    pl.vy = 0
    pl.onGround = false
    pl.face = 1
    state.coyoteTimer = 0
    state.jumpBufferTimer = 0
    state.jumpCutDone = false
    syncVisual()
end

-- ================================================================
-- ★ 手动同步外观（关卡加载后立即调用一次，避免首帧跳动）
-- ================================================================
function M.syncVisualNow()
    syncVisual()
end

return M
