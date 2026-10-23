-- ================================================================
-- 皮耶罗：赴死 · 玩家（物理 + 鬼魂）
-- ================================================================
-- ★ 物理数值与原版逐项一致（game.js updatePlay）：
--   水平加速度 地面 2600 / 空中 1800，最大速度 265，
--   起跳 -645，重力 2150，最大下落 980，松手截断到 -220，
--   土狼时间 0.10，跳跃缓冲 0.12。
-- ★ 碰撞用「分轴解算」：先水平推进并解算，再垂直推进并解算。
--   原版单帧一次解算，这里再按 8ms 细分，避免高速穿过薄平台。
-- ★ 坐标一律是世界坐标（y 向下为正），只有 sync() 里翻转成 UI 坐标。
-- ================================================================

---@diagnostic disable: undefined-global

local M = {}
local state = require("default_import_file/state")
local config = require("default_import_file/config")
local utils = require("default_import_file/utils")
local audio = require("default_import_file/audio")
local fx = require("default_import_file/fx")

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
-- ★ 创建玩家控件（本体 + 两只眼睛），只建一次，之后靠位置/缩放驱动
-- ================================================================
function M.build()
    local p = state.player
    if not p then return end
    if p.ctrl then return end
    p.ctrl = utils.createRectWorld(p.x, p.y, p.w, p.h, utils.pal("ink"), 255,
        state.containerPlayer)
    local ew = math.max(4, p.w * 0.17)
    local eh = math.max(5, p.h * 0.20)
    p.eyeW = ew
    p.eyeH = eh
    p.eye1 = utils.createRectAtWorld(p.x + p.w / 2 - 5, p.y + 11, ew, eh,
        utils.pal("bg"), 255, state.containerPlayer)
    p.eye2 = utils.createRectAtWorld(p.x + p.w / 2 + 6, p.y + 11, ew, eh,
        utils.pal("bg"), 255, state.containerPlayer)
    -- ★ 必须显式定序：模拟器是「后创建 = 更靠下」，不提层的话眼睛会被身体盖住
    utils.raise(p.ctrl)
    utils.raise(p.eye1)
    utils.raise(p.eye2)
end

function M.destroy()
    local p = state.player
    if not p then return end
    utils.destroy(p.ctrl)
    utils.destroy(p.eye1)
    utils.destroy(p.eye2)
end

-- ================================================================
-- ★ 出生 / 复位
-- ================================================================
function M.spawn(sp)
    local w = config.DEFAULT_PLAYER_W or 26
    local h = config.DEFAULT_PLAYER_H or 32
    local p = state.player
    if not p then
        p = { w = w, h = h, eyeW = 4, eyeH = 6 }
        state.player = p
    end
    p.x = sp.x
    p.y = sp.y
    p.vx = 0
    p.vy = 0
    p.grounded = false
    p.coyote = 0
    p.jumping = false
    p.squash = 0
    p.face = 1
    state.jumpBuffer = 0
    state.ghost = false
    state.ghostFailT = 0
    M.build()
    M.sync()
end

function M.hide()
    local p = state.player
    if not p then return end
    utils.setVisible(p.ctrl, false)
    utils.setVisible(p.eye1, false)
    utils.setVisible(p.eye2, false)
end

function M.show()
    local p = state.player
    if not p then return end
    utils.setVisible(p.ctrl, true)
    utils.setVisible(p.eye1, true)
    utils.setVisible(p.eye2, true)
end

-- ================================================================
-- ★ 化鬼（不死诅咒生效）
-- ================================================================
function M.enterGhost()
    local p = state.player
    if not p then return end
    state.ghost = true
    state.ghostFailT = 0
    p.vx = 0
    p.vy = 0
    p.grounded = false
    p.coyote = 0
    p.jumping = false
    p.squash = 0
    state.jumpBuffer = 0
    audio.playDeath()
    fx.poof(p.x + p.w / 2, p.y + p.h / 2)
    M.sync()
end

function M.ghostFail()
    state.ghostFailT = config.DEFAULT_GHOST_FAIL_TIME or 0.35
    audio.playPop()
end

-- ★ 复活检测：脚下不能卡在实体里、也不能压在致死区上
function M.canRespawn(solids, kills)
    local p = state.player
    if not p then return false end
    local bx, by = p.x + 2, p.y + 2
    local bw, bh = p.w - 4, p.h - 4
    for i = 1, #solids do
        local s = solids[i]
        if utils.aabb(bx, by, bw, bh, s.x, s.y, s.w, s.h) then return false end
    end
    for i = 1, #kills do
        local k = kills[i]
        if utils.aabb(bx, by, bw, bh, k.x, k.y, k.w, k.h) then return false end
    end
    return true
end

function M.tryRespawn(solids, kills)
    if not state.ghost then return false end
    local p = state.player
    if not p then return false end
    -- 掉出世界的话先把人提回画面内
    if p.y > 540 - p.h then p.y = 540 - p.h - 4 end
    if p.y < 0 then p.y = 4 end
    p.x = utils.clamp(p.x, 0, 960 - p.w)
    if not M.canRespawn(solids, kills) then
        M.ghostFail()
        return false
    end
    state.ghost = false
    state.ghostFailT = 0
    p.vx = 0
    p.vy = 0
    p.grounded = false
    p.coyote = 0
    p.jumping = false
    p.squash = 0
    audio.playPop()
    fx.poof(p.x + p.w / 2, p.y + p.h / 2)
    M.sync()
    return true
end

-- ================================================================
-- ★ 鬼魂漂浮（不参与任何碰撞）
-- ================================================================
local function updateGhost(dt)
    local p = state.player
    if not p then return end
    local spd = config.DEFAULT_GHOST_SPEED or 320
    local dx, dy = 0, 0
    if state.keyLeft then dx = dx - 1 end
    if state.keyRight then dx = dx + 1 end
    if state.keyUp then dy = dy - 1 end
    if state.keyDown then dy = dy + 1 end
    if dx ~= 0 then p.face = dx end
    p.x = p.x + dx * spd * dt
    p.y = p.y + dy * spd * dt
    p.x = utils.clamp(p.x, 0, 960 - p.w)
    p.y = utils.clamp(p.y, 0, 540 - p.h)
    p.vx = 0
    p.vy = 0
    p.grounded = false
end

-- ================================================================
-- ★ 单个物理子步
-- ================================================================
local function substep(dt, solids)
    local p = state.player
    if not p then return end

    -- 水平输入
    local dir = 0
    if state.keyLeft then dir = dir - 1 end
    if state.keyRight then dir = dir + 1 end
    if state.invertNow then dir = -dir end
    if dir ~= 0 then p.face = dir end

    local speed = config.DEFAULT_MOVE_SPEED or 265
    local accel
    if p.grounded then accel = config.DEFAULT_GROUND_ACCEL or 2600
    else accel = config.DEFAULT_AIR_ACCEL or 1800 end
    if dir ~= 0 then
        p.vx = approach(p.vx, dir * speed, accel * dt)
    else
        p.vx = approach(p.vx, 0, accel * dt)
    end

    -- 跳跃（缓冲 + 土狼时间）
    state.jumpBuffer = math.max(0, (state.jumpBuffer or 0) - dt)
    if p.grounded then
        p.coyote = config.DEFAULT_COYOTE_TIME or 0.10
    else
        p.coyote = math.max(0, (p.coyote or 0) - dt)
    end
    if state.jumpBuffer > 0 and p.coyote > 0 then
        p.vy = config.DEFAULT_JUMP_SPEED or -645
        p.grounded = false
        p.coyote = 0
        p.jumping = true
        state.jumpBuffer = 0
        audio.playJump()
        fx.dust(p.x + p.w / 2, p.y + p.h, 4)
    end
    if p.vy >= 0 then p.jumping = false end
    -- 可变跳跃高度：松手时把上升速度截断一次（原版只截一次，不是每帧乘）
    if (not state.keyJump) and p.jumping and p.vy < (config.DEFAULT_JUMP_CUT or -220) then
        p.vy = config.DEFAULT_JUMP_CUT or -220
        p.jumping = false
    end

    local g = config.DEFAULT_GRAVITY or 2150
    p.vy = p.vy + g * dt
    local maxFall = config.DEFAULT_MAX_FALL or 980
    if p.vy > maxFall then p.vy = maxFall end

    local wasGrounded = p.grounded

    -- ---- X 轴 ----
    p.x = p.x + p.vx * dt
    for i = 1, #solids do
        local s = solids[i]
        if utils.aabb(p.x, p.y, p.w, p.h, s.x, s.y, s.w, s.h) then
            if p.vx > 0 then
                p.x = s.x - p.w
            elseif p.vx < 0 then
                p.x = s.x + s.w
            else
                if p.x + p.w / 2 < s.x + s.w / 2 then
                    p.x = s.x - p.w
                else
                    p.x = s.x + s.w
                end
            end
            p.vx = 0
        end
    end

    -- ---- Y 轴 ----
    p.y = p.y + p.vy * dt
    p.grounded = false
    for i = 1, #solids do
        local s = solids[i]
        if utils.aabb(p.x, p.y, p.w, p.h, s.x, s.y, s.w, s.h) then
            if p.vy > 0 then
                p.y = s.y - p.h
                p.grounded = true
                if not wasGrounded and p.vy > 350 then
                    audio.playJump()
                    fx.dust(p.x + p.w / 2, p.y + p.h, 4)
                    p.squash = 0.12
                end
                p.vy = 0
            elseif p.vy < 0 then
                p.y = s.y + s.h
                p.vy = 0
            end
        end
    end
    p.squash = math.max(0, (p.squash or 0) - dt)
end

-- ================================================================
-- ★ 每帧更新
--   solids 由 level 汇总后传进来（静态实体 + 陷阱实心体）
-- ================================================================
function M.update(dt, solids)
    local p = state.player
    if not p or not dt or dt <= 0 then return end

    if state.ghostFailT and state.ghostFailT > 0 then
        state.ghostFailT = math.max(0, state.ghostFailT - dt)
    end

    if state.ghost then
        updateGhost(dt)
        M.sync()
        return
    end

    local sub = config.DEFAULT_PHYS_SUBSTEP or 0.008
    local steps = math.ceil(dt / sub)
    if steps < 1 then steps = 1 end
    if steps > 12 then steps = 12 end
    local sdt = dt / steps
    for i = 1, steps do
        substep(sdt, solids)
    end

    -- 跑动扬尘
    if p.grounded and math.abs(p.vx) > 180 and math.random() < 0.25 then
        fx.dust(p.x + p.w / 2 - p.face * 10, p.y + p.h, 1)
    end

    M.sync()
end

-- ================================================================
-- ★ 把逻辑坐标同步到控件（含压扁 / 拉伸与鬼魂半透明）
-- ================================================================
function M.sync()
    local p = state.player
    if not p or not p.ctrl then return end

    local squashY = 1
    if (p.squash or 0) > 0 then squashY = 1 - p.squash * 2.2 end
    local stretchY = squashY
    if not p.grounded then
        stretchY = 1 + math.abs(p.vy) / 2600
        if stretchY > 1.18 then stretchY = 1.18 end
        if stretchY < 1 then stretchY = 1 end
    end
    local sx = 1 / stretchY

    local cx = p.x + p.w / 2
    local cy = p.y + p.h / 2
    utils.setPos(p.ctrl, utils.toUIX(cx), utils.toUIY(cy))
    utils.setSize(p.ctrl, p.w, p.h)
    utils.setScaleXY(p.ctrl, sx, stretchY)

    local alpha = 255
    if state.ghost then
        alpha = config.DEFAULT_GHOST_ALPHA or 130
        if (state.ghostFailT or 0) > 0 then
            local blink = math.floor(state.ghostFailT * 24) % 2
            alpha = blink == 0 and 235 or 60
        end
    end
    utils.setColor(p.ctrl, utils.pal("ink"), alpha)

    local lookX = (p.face or 1) * 3
    local ew = p.eyeW or 4
    local eh = p.eyeH or 6
    utils.setPos(p.eye1, utils.toUIX(cx - 5 + lookX), utils.toUIY(p.y + 11))
    utils.setPos(p.eye2, utils.toUIX(cx + 6 + lookX), utils.toUIY(p.y + 11))
    utils.setSize(p.eye1, ew, eh)
    utils.setSize(p.eye2, ew, eh)
    local eyeAlpha = state.ghost and math.floor(alpha * 0.9) or 255
    utils.setColor(p.eye1, utils.pal("bg"), eyeAlpha)
    utils.setColor(p.eye2, utils.pal("bg"), eyeAlpha)
    if state.ghost then
        utils.setVisible(p.eye1, true)
        utils.setVisible(p.eye2, true)
    end
end

return M
