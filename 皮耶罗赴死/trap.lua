-- ================================================================
-- 皮耶罗：赴死 · 陷阱模块（19 种，与原版 trap 逐项对应）
-- ================================================================
-- 每种陷阱 = 一个纯逻辑状态机 + 一组复用的图元控件：
--   update(ins, dt)  推进状态
--   sols(ins, out)   当前实心矩形（可站 / 可撞），世界坐标
--   kills(ins, out)  当前致死矩形，世界坐标
--   sync(ins)        把逻辑状态推到控件（只在值变化时真的动控件）
--   reset(ins)       复位到初始状态
--
-- ★ 坐标系：全部沿用原版（960×540，y 向下，重力为正），
--   只有 sync 里通过 utils.toUIX / toUIY 翻转一次。
-- ★ 原版 draw() 的画笔效果在这里换成「图元组合」：
--   三角形尖刺 → 45° 旋转的小方块（菱形）；圆弧 → 方块/菱形近似。
-- ================================================================

---@diagnostic disable: undefined-global

local M = {}
local state = require("default_import_file/state")
local config = require("default_import_file/config")
local utils = require("default_import_file/utils")
local audio = require("default_import_file/audio")
local fx = require("default_import_file/fx")

local function num(v, d)
    local n = tonumber(v)
    if n == nil then return d end
    return n
end

-- ★ 前置声明：moveer 的位置插值被 M.create 与 KIND.mover 同时引用，
--   必须先在文件顶部声明成 local，实现处再赋值（写 local function 会新建
--   一个局部遮蔽前置声明 → 闭包拿到 nil）。
local moverPosAt

local function hasTrig(ins)
    return type(ins.trig) == "table"
end

-- 玩家 AABB 与矩形相交
local function ph(ins, r)
    local p = state.player
    if not p or not r then return false end
    return utils.aabb(p.x, p.y, p.w, p.h, r.x, r.y, r.w, r.h)
end

-- 建一个 45° 旋转的方块（= 菱形 / 尖刺）
local function diamond(wx, wy, s, hex, alpha, parent)
    local c = utils.createRectAtWorld(wx, wy, s, s, hex, alpha, parent)
    if c then utils.setRot(c, 45) end
    return c
end

local KIND = {}

-- ================================================================
-- 1. 塌陷地板 CollapseFloor
-- ================================================================
KIND.collapse = {
    init = function(ins, s)
        ins.rect = s.rect
        ins.trig = s.trig
        ins.shakeTime = num(s.shakeTime, config.DEFAULT_COLLAPSE_SHAKE)
        ins.delay = num(s.delay, 0)
        ins.mode = "idle"
        ins.t = 0
        ins.dy = 0
        ins.vy = 0
    end,
    reset = function(ins)
        ins.mode = "idle"; ins.t = 0; ins.dy = 0; ins.vy = 0
        if ins.ctrl then
            utils.setSize(ins.ctrl, ins.rect.w, ins.rect.h)
            local cx, cy = utils.rectCenter(ins.rect.x, ins.rect.y, ins.rect.w, ins.rect.h)
            utils.setPos(ins.ctrl, cx, cy)
            utils.setVisible(ins.ctrl, true)
        end
        ins.lastDy = 0
    end,
    build = function(ins)
        local r = ins.rect
        ins.ctrl = utils.createRectWorld(r.x, r.y, r.w, r.h,
            utils.pal("ink"), 255, state.containerWorld)
        ins.lastDy = 0
    end,
    update = function(ins, dt)
        if ins.mode == "idle" then
            if hasTrig(ins) and ph(ins, ins.trig) then
                ins.mode = "wait"; ins.t = 0
            end
        elseif ins.mode == "wait" then
            ins.t = ins.t + dt
            if ins.t >= ins.delay then
                ins.mode = "shake"; ins.t = 0
                audio.playPop()
                fx.shake(4, 0.18)
            end
        elseif ins.mode == "shake" then
            ins.t = ins.t + dt
            if ins.t >= ins.shakeTime then
                ins.mode = "fall"
                audio.playPop()
            end
        elseif ins.mode == "fall" then
            ins.vy = ins.vy + 2400 * dt
            ins.dy = ins.dy + ins.vy * dt
        end
    end,
    sols = function(ins, out)
        if ins.mode ~= "fall" then out[#out + 1] = ins.rect end
    end,
    kills = function() end,
    sync = function(ins)
        if not ins.ctrl then return end
        if ins.mode == "fall" and ins.dy > 600 then
            if ins.shown ~= false then utils.setVisible(ins.ctrl, false); ins.shown = false end
            return
        end
        local jitter = 0
        if ins.mode == "shake" then
            jitter = fx.random(-2.5, 2.5)
        end
        if ins.mode == "shake" or ins.dy ~= ins.lastDy or jitter ~= 0 then
            local cx, cy = utils.rectCenter(ins.rect.x + jitter, ins.rect.y + ins.dy, ins.rect.w, ins.rect.h)
            utils.setPos(ins.ctrl, cx, cy)
            ins.lastDy = ins.dy
        end
    end,
}

-- ================================================================
-- 2. 弹出尖刺 PopSpikes（触发型 / 周期型）
-- ================================================================
local function spikePieces(ins)
    local n = math.floor(ins.w / 18 + 0.5)
    if n < 2 then n = 2 end
    if n > 6 then n = 6 end
    ins.pieces = {}
    ins.pw = ins.w / n
    ins.s0 = math.min(ins.pw * 1.05, ins.size * 0.74)
    for i = 1, n do
        local px = ins.x + (i - 0.5) * ins.pw
        local c = diamond(px, ins.y, ins.s0, utils.pal("ink"), 255, state.containerWorld)
        if c then
            ins.pieces[#ins.pieces + 1] = { ctrl = c, px = px }
            utils.setVisible(c, false)
        end
    end
end

local function spikeSync(ins)
    if not ins.pieces then return end
    local out = ins.out or 0
    local half = ins.s0 * 0.7071 * out
    local sign = (ins.dir == "down") and 1 or -1
    for i = 1, #ins.pieces do
        local p = ins.pieces[i]
        if out <= 0.02 then
            if p.on ~= false then utils.setVisible(p.ctrl, false); p.on = false end
        else
            if p.on ~= true then utils.setVisible(p.ctrl, true); p.on = true end
            utils.setPos(p.ctrl, utils.toUIX(p.px), utils.toUIY(ins.y + sign * half))
            utils.setScale(p.ctrl, out)
        end
    end
end

KIND.pop = {
    init = function(ins, s)
        ins.x = num(s.x, 0); ins.y = num(s.y, 0); ins.w = num(s.w, 60)
        ins.dir = s.dir or "up"
        ins.size = num(s.size, config.DEFAULT_SPIKE_SIZE)
        ins.delay = num(s.delay, 0)
        ins.trig = s.trig
        ins.period = num(s.period, 0)
        ins.phase = num(s.phase, 0)
        ins.holdOut = num(s.holdOut, config.DEFAULT_SPIKE_HOLD)
        ins.speed = num(s.speed, config.DEFAULT_SPIKE_SPEED)
        if not hasTrig(ins) and ins.period <= 0 then ins.period = 2.0 end
        ins.out = 0
        ins.mode = hasTrig(ins) and "idle" or "cycle"
        ins.t = -ins.delay
        ins.ct = ins.phase
        ins.wasOut = false
    end,
    build = spikePieces,
    reset = function(ins)
        ins.out = 0
        ins.mode = hasTrig(ins) and "idle" or "cycle"
        ins.t = -ins.delay
        ins.ct = ins.phase
        ins.wasOut = false
        spikeSync(ins)
    end,
    update = function(ins, dt)
        if ins.mode == "idle" then
            if ph(ins, ins.trig) then
                ins.mode = "popping"
                ins.t = -ins.delay
            end
        elseif ins.mode == "popping" then
            ins.t = ins.t + dt
            if ins.t >= 0 then
                ins.out = utils.clamp(ins.out + ins.speed * dt, 0, 1)
            end
        elseif ins.mode == "cycle" then
            ins.ct = ins.ct + dt
            local cyc = ins.ct % ins.period
            if cyc < ins.holdOut then
                ins.out = utils.clamp(ins.out + ins.speed * dt, 0, 1)
            else
                ins.out = utils.clamp(ins.out - ins.speed * 0.6 * dt, 0, 1)
            end
        end
        local nowOut = (ins.out or 0) > 0.12
        if nowOut and not ins.wasOut then audio.playPop() end
        ins.wasOut = nowOut
    end,
    sols = function() end,
    kills = function(ins, out)
        if (ins.out or 0) < 0.45 then return end
        local h = ins.size * ins.out - 6
        if h <= 0 then return end
        if ins.dir == "up" then
            out[#out + 1] = { x = ins.x + 4, y = ins.y - h, w = ins.w - 8, h = h }
        else
            out[#out + 1] = { x = ins.x + 4, y = ins.y, w = ins.w - 8, h = h }
        end
    end,
    sync = spikeSync,
}

-- ================================================================
-- 3. 静止尖刺 StaticSpikes
-- ================================================================
KIND.spikes = {
    init = function(ins, s)
        ins.x = num(s.x, 0); ins.y = num(s.y, 0); ins.w = num(s.w, 60)
        ins.dir = s.dir or "up"
        ins.size = num(s.size, config.DEFAULT_SPIKE_SIZE)
        ins.out = 1
    end,
    build = spikePieces,
    reset = function(ins)
        ins.out = 1
        spikeSync(ins)
    end,
    update = function() end,
    sols = function() end,
    kills = function(ins, out)
        local h = ins.size - 8
        if h <= 0 then h = ins.size end
        if ins.dir == "up" then
            out[#out + 1] = { x = ins.x + 4, y = ins.y - ins.size + 8, w = ins.w - 8, h = h }
        else
            out[#out + 1] = { x = ins.x + 4, y = ins.y, w = ins.w - 8, h = h }
        end
    end,
    sync = spikeSync,
}

-- ================================================================
-- 4. 落石 FallBlock
-- ================================================================
KIND.fallblock = {
    init = function(ins, s)
        ins.home = s.rect
        ins.rect = { x = s.rect.x, y = s.rect.y, w = s.rect.w, h = s.rect.h }
        ins.trig = s.trig
        ins.shakeT = num(s.shakeTime, config.DEFAULT_FALLBLOCK_SHAKE)
        ins.floorY = num(s.floorY, config.DEFAULT_FALLBLOCK_FLOOR)
        ins.mode = "idle"; ins.t = 0; ins.vy = 0
    end,
    build = function(ins)
        local r = ins.rect
        ins.ctrl = utils.createRectWorld(r.x, r.y, r.w, r.h,
            utils.pal("ink"), 255, state.containerWorld)
        -- 裂缝
        ins.crack = utils.createRectWorld(r.x + r.w * 0.42, r.y + 2, 2, r.h - 4,
            utils.pal("crack"), 200, state.containerWorld)
    end,
    reset = function(ins)
        ins.rect.x = ins.home.x
        ins.rect.y = ins.home.y
        ins.mode = "idle"; ins.t = 0; ins.vy = 0
        ins.lastY = nil
        if ins.ctrl then utils.setVisible(ins.ctrl, true) end
        if ins.crack then utils.setVisible(ins.crack, true) end
    end,
    update = function(ins, dt)
        if ins.mode == "idle" then
            if hasTrig(ins) and ph(ins, ins.trig) then
                ins.mode = "shake"; ins.t = 0
                audio.playPop()
            end
        elseif ins.mode == "shake" then
            ins.t = ins.t + dt
            if ins.t > ins.shakeT then ins.mode = "fall" end
        elseif ins.mode == "fall" then
            ins.vy = ins.vy + 3000 * dt
            ins.rect.y = ins.rect.y + ins.vy * dt
            if ins.rect.y + ins.rect.h >= ins.floorY then
                ins.rect.y = ins.floorY - ins.rect.h
                ins.mode = "landed"
                audio.playDeath()
                fx.shake(7, 0.22)
                fx.dust(ins.rect.x + ins.rect.w / 2, ins.floorY, 8)
            end
        end
    end,
    sols = function(ins, out)
        if ins.mode ~= "fall" then out[#out + 1] = ins.rect end
    end,
    kills = function(ins, out)
        if ins.mode == "fall" then
            out[#out + 1] = { x = ins.rect.x + 3, y = ins.rect.y + 4,
                              w = ins.rect.w - 6, h = ins.rect.h - 4 }
        end
    end,
    sync = function(ins)
        if not ins.ctrl then return end
        local jx = 0
        if ins.mode == "shake" then jx = fx.random(-2, 2) end
        local r = ins.rect
        if jx ~= 0 or ins.lastY ~= r.y then
            local cx, cy = utils.rectCenter(r.x + jx, r.y, r.w, r.h)
            utils.setPos(ins.ctrl, cx, cy)
            if ins.crack then
                utils.setPos(ins.crack, utils.toUIX(r.x + jx + r.w * 0.42 + 1), utils.toUIY(r.y + r.h / 2))
            end
            ins.lastY = r.y
        end
    end,
}

-- ================================================================
-- 5. 压路机 Crusher
-- ================================================================
KIND.crusher = {
    init = function(ins, s)
        ins.x = num(s.x, 0); ins.w = num(s.w, 90)
        ins.topY = num(s.topY, 0)
        ins.headH = num(s.headH, config.DEFAULT_CRUSHER_HEAD)
        ins.floorY = num(s.floorY, 480)
        ins.period = num(s.period, config.DEFAULT_CRUSHER_PERIOD)
        ins.phase = num(s.phase, 0)
        ins.trig = s.trig
        ins.slamSpeed = num(s.slamSpeed, config.DEFAULT_CRUSHER_SLAM)
        ins.upSpeed = num(s.upSpeed, config.DEFAULT_CRUSHER_UP)
        ins.holdT = num(s.hold, config.DEFAULT_CRUSHER_HOLD)
        ins.y = ins.topY
        ins.mode = hasTrig(ins) and "armed" or "waiting"
        ins.t = ins.phase
        ins.slammed = false
    end,
    build = function(ins)
        ins.shaft = utils.createRectWorld(ins.x + ins.w / 2 - 9, ins.topY, 18, 10,
            utils.pal("metal"), 255, state.containerWorld)
        ins.head = utils.createRectWorld(ins.x, ins.topY, ins.w, ins.headH,
            utils.pal("ink"), 255, state.containerWorld)
        local n = math.min(5, math.max(2, math.floor(ins.w / 20)))
        ins.teeth = {}
        local pw = ins.w / n
        for i = 1, n do
            local c = diamond(ins.x + (i - 0.5) * pw, ins.topY + ins.headH, math.min(pw * 0.9, 16),
                utils.pal("accent"), 255, state.containerWorld)
            if c then ins.teeth[#ins.teeth + 1] = { ctrl = c, px = ins.x + (i - 0.5) * pw } end
        end
    end,
    reset = function(ins)
        ins.y = ins.topY
        ins.mode = hasTrig(ins) and "armed" or "waiting"
        ins.t = ins.phase
        ins.slammed = false
        ins.lastY = nil
    end,
    update = function(ins, dt)
        local maxY = ins.floorY - ins.headH
        if ins.mode == "armed" then
            if ph(ins, ins.trig) then ins.mode = "slam" end
        elseif ins.mode == "waiting" then
            ins.t = ins.t + dt
            if ins.t >= ins.period then
                ins.t = 0
                ins.mode = "slam"
            end
        elseif ins.mode == "slam" then
            ins.y = ins.y + ins.slamSpeed * dt
            if ins.y >= maxY then
                ins.y = maxY
                ins.mode = "hold"; ins.t = 0
                if not ins.slammed then
                    audio.playDeath()
                    fx.shake(6, 0.18)
                    fx.dust(ins.x + ins.w / 2, ins.floorY, 7)
                end
                ins.slammed = true
            end
        elseif ins.mode == "hold" then
            ins.t = ins.t + dt
            if ins.t >= ins.holdT then ins.mode = "rise" end
        elseif ins.mode == "rise" then
            ins.y = ins.y - ins.upSpeed * dt
            if ins.y <= ins.topY then
                ins.y = ins.topY
                ins.slammed = false
                ins.mode = hasTrig(ins) and "spent" or "waiting"
                ins.t = 0
            end
        end
    end,
    sols = function(ins, out)
        out[#out + 1] = { x = ins.x, y = ins.y, w = ins.w, h = ins.headH }
    end,
    kills = function(ins, out)
        if ins.mode == "slam" then
            out[#out + 1] = { x = ins.x + 2, y = ins.y + ins.headH - 14, w = ins.w - 4, h = 16 }
        end
    end,
    sync = function(ins)
        if not ins.head then return end
        if ins.lastY == ins.y then return end
        ins.lastY = ins.y
        local cx, cy = utils.rectCenter(ins.x, ins.y, ins.w, ins.headH)
        utils.setPos(ins.head, cx, cy)
        if ins.shaft then
            local sh = math.max(4, ins.y - ins.topY + 4)
            utils.setSize(ins.shaft, 18, sh)
            utils.setPos(ins.shaft, utils.toUIX(ins.x + ins.w / 2), utils.toUIY(ins.topY + sh / 2))
        end
        for i = 1, #ins.teeth do
            local t = ins.teeth[i]
            utils.setPos(t.ctrl, utils.toUIX(t.px), utils.toUIY(ins.y + ins.headH))
        end
    end,
}

-- ================================================================
-- 6. 碎裂平台 CrumblePlatform
-- ================================================================
KIND.crumble = {
    init = function(ins, s)
        ins.home = s.rect
        ins.rect = { x = s.rect.x, y = s.rect.y, w = s.rect.w, h = s.rect.h }
        ins.delay = num(s.delay, config.DEFAULT_CRUMBLE_DELAY)
        ins.mode = "idle"; ins.t = 0; ins.vy = 0
    end,
    build = function(ins)
        local r = ins.rect
        ins.ctrl = utils.createRectWorld(r.x, r.y, r.w, r.h,
            utils.pal("ink"), 255, state.containerWorld)
        ins.cracks = {}
        for i = 1, 2 do
            local c = utils.createRectWorld(r.x + (r.w / 3) * i - 1, r.y + 2, 2, r.h - 4,
                utils.pal("crack"), 200, state.containerWorld)
            if c then ins.cracks[#ins.cracks + 1] = c end
        end
    end,
    reset = function(ins)
        ins.rect.x = ins.home.x
        ins.rect.y = ins.home.y
        ins.mode = "idle"; ins.t = 0; ins.vy = 0
        ins.lastY = nil
        if ins.ctrl then utils.setVisible(ins.ctrl, true) end
        for i = 1, #(ins.cracks or {}) do utils.setVisible(ins.cracks[i], true) end
    end,
    update = function(ins, dt)
        if ins.mode == "idle" then
            local p = state.player
            if p and p.grounded
               and math.abs(p.y + p.h - ins.rect.y) < 3
               and p.x + p.w > ins.rect.x and p.x < ins.rect.x + ins.rect.w then
                ins.mode = "shaking"; ins.t = 0
                audio.playPop()
            end
        elseif ins.mode == "shaking" then
            ins.t = ins.t + dt
            if ins.t >= ins.delay then ins.mode = "fall" end
        elseif ins.mode == "fall" then
            ins.vy = ins.vy + 2400 * dt
            ins.rect.y = ins.rect.y + ins.vy * dt
        end
    end,
    sols = function(ins, out)
        if ins.mode ~= "fall" then out[#out + 1] = ins.rect end
    end,
    kills = function() end,
    sync = function(ins)
        if not ins.ctrl then return end
        if ins.rect.y > 620 then
            if ins.shown ~= false then
                utils.setVisible(ins.ctrl, false); ins.shown = false
                for i = 1, #(ins.cracks or {}) do utils.setVisible(ins.cracks[i], false) end
            end
            return
        end
        local jx = 0
        if ins.mode == "shaking" then jx = fx.random(-2, 2) end
        local r = ins.rect
        if jx ~= 0 or ins.lastY ~= r.y then
            local cx, cy = utils.rectCenter(r.x + jx, r.y, r.w, r.h)
            utils.setPos(ins.ctrl, cx, cy)
            for i = 1, #(ins.cracks or {}) do
                utils.setPos(ins.cracks[i],
                    utils.toUIX(r.x + jx + (r.w / 3) * i - 1 + 1), utils.toUIY(r.y + r.h / 2))
            end
            ins.lastY = r.y
        end
    end,
}

-- ================================================================
-- 7. 移动缺口 SlidingHole
-- ================================================================
KIND.hole = {
    init = function(ins, s)
        ins.x0 = num(s.x0, 0)
        ins.x1 = num(s.x1, 960)
        ins.y = num(s.y, config.DEFAULT_HOLE_Y)
        ins.h = num(s.h, config.DEFAULT_HOLE_H)
        ins.gapW = num(s.gapW, config.DEFAULT_HOLE_GAP)
        ins.startGap = num(s.startGap, ins.x1 - 100)
        ins.speed = num(s.speed, config.DEFAULT_HOLE_SPEED)
        ins.trig = s.trig
        ins.gx = ins.startGap
        ins.active = not hasTrig(ins)
    end,
    build = function(ins)
        ins.left = utils.createRectWorld(ins.x0, ins.y, 10, ins.h,
            utils.pal("ink"), 255, state.containerWorld)
        ins.right = utils.createRectWorld(ins.x1 - 10, ins.y, 10, ins.h,
            utils.pal("ink"), 255, state.containerWorld)
        -- 缺口两侧的「向内箭头」提示
        ins.edgeL = diamond(ins.x0, ins.y + ins.h / 2, 14, utils.pal("accent"), 255, state.containerWorld)
        ins.edgeR = diamond(ins.x1, ins.y + ins.h / 2, 14, utils.pal("accent"), 255, state.containerWorld)
    end,
    reset = function(ins)
        ins.gx = ins.startGap
        ins.active = not hasTrig(ins)
        ins.lastG = nil
        if ins.left then utils.setVisible(ins.left, true) end
        if ins.right then utils.setVisible(ins.right, true) end
        if ins.edgeL then utils.setVisible(ins.edgeL, true) end
        if ins.edgeR then utils.setVisible(ins.edgeR, true) end
    end,
    update = function(ins, dt)
        if not ins.active and hasTrig(ins) then
            if ph(ins, ins.trig) then ins.active = true; audio.playPop() end
        end
        if not ins.active then return end
        local p = state.player
        if not p then return end
        local target = utils.clamp(p.x + p.w / 2,
            ins.x0 + ins.gapW / 2 + 4, ins.x1 - ins.gapW / 2 - 4)
        local d = target - ins.gx
        local step = utils.clamp(d, -ins.speed * dt, ins.speed * dt)
        ins.gx = ins.gx + step
    end,
    sols = function(ins, out)
        if not ins.active then
            out[#out + 1] = { x = ins.x0, y = ins.y, w = ins.x1 - ins.x0, h = ins.h }
            return
        end
        local gl = ins.gx - ins.gapW / 2
        local gr = ins.gx + ins.gapW / 2
        if gl > ins.x0 + 2 then
            out[#out + 1] = { x = ins.x0, y = ins.y, w = gl - ins.x0, h = ins.h }
        end
        if gr < ins.x1 - 2 then
            out[#out + 1] = { x = gr, y = ins.y, w = ins.x1 - gr, h = ins.h }
        end
    end,
    kills = function() end,
    sync = function(ins)
        if not ins.left then return end
        if ins.lastG == ins.gx and ins.lastActive == ins.active then return end
        ins.lastG = ins.gx
        ins.lastActive = ins.active
        local gl = ins.gx - ins.gapW / 2
        local gr = ins.gx + ins.gapW / 2
        local lw = math.max(0, gl - ins.x0)
        local rw = math.max(0, ins.x1 - gr)
        utils.setSize(ins.left, lw, ins.h)
        utils.setPos(ins.left, utils.toUIX(ins.x0 + lw / 2), utils.toUIY(ins.y + ins.h / 2))
        utils.setSize(ins.right, rw, ins.h)
        utils.setPos(ins.right, utils.toUIX(gr + rw / 2), utils.toUIY(ins.y + ins.h / 2))
        if ins.edgeL then
            utils.setPos(ins.edgeL, utils.toUIX(gl), utils.toUIY(ins.y + ins.h / 2))
            utils.setVisible(ins.edgeL, lw > 6)
        end
        if ins.edgeR then
            utils.setPos(ins.edgeR, utils.toUIX(gr), utils.toUIY(ins.y + ins.h / 2))
            utils.setVisible(ins.edgeR, rw > 6)
        end
    end,
}

-- ================================================================
-- 8. 反向操作区 InvertZone
-- ================================================================
KIND.invert = {
    init = function(ins, s)
        ins.rect = s.rect
    end,
    build = function(ins)
        local r = ins.rect
        ins.ctrl = utils.createRectWorld(r.x, r.y, r.w, r.h,
            utils.pal("accent"), 22, state.containerWorld)
        ins.mark = utils.createTextWorld(r.x + r.w / 2, r.y + 60, 80, 40, "?",
            utils.pal("accent"), 30, state.containerWorld)
        if ins.mark then
            utils.setRot(ins.mark, 180)
            pcall(function() ins.mark.fontColor = utils.hexToColorA(utils.pal("accent"), 110) end)
        end
    end,
    reset = function() end,
    update = function(ins)
        if ph(ins, ins.rect) then state.invertNow = true end
    end,
    sols = function() end,
    kills = function() end,
    sync = function() end,
}

-- ================================================================
-- 9. 移动平台 MovingPlatform
-- ================================================================
KIND.mover = {
    init = function(ins, s)
        local r = s.rect
        ins.w = r.w; ins.h = r.h
        ins.ax = r.x; ins.ay = r.y
        ins.bx = num(s.toX, r.x); ins.by = num(s.toY, r.y)
        ins.speed = num(s.speed, config.DEFAULT_MOVER_SPEED)
        ins.phase = num(s.phase, 0)
        ins.pause = num(s.pause, 0)
        local dist = math.sqrt((ins.bx - ins.ax) ^ 2 + (ins.by - ins.ay) ^ 2)
        if dist < 1 then dist = 1 end
        ins.travel = dist / ins.speed
        ins.cycle = ins.travel * 2 + ins.pause * 2
        ins.t = ins.phase * ins.cycle
        local px, py = ins:posAt(ins.t)
        ins.px = px; ins.py = py
        ins.lastX = nil
    end,
    build = function(ins)
        ins.ctrl = utils.createRectWorld(ins.px, ins.py, ins.w, ins.h,
            utils.pal("ink"), 255, state.containerWorld)
        ins.notches = {}
        for i = 1, 3 do
            local c = utils.createRectWorld(ins.px + ins.w / 2 - 14 + (i - 1) * 12,
                ins.py + ins.h / 2 - 1.5, 6, 3, utils.pal("bg"), 255, state.containerWorld)
            if c then ins.notches[#ins.notches + 1] = c end
        end
    end,
    reset = function(ins)
        ins.t = ins.phase * ins.cycle
        local px, py = ins:posAt(ins.t)
        ins.px = px; ins.py = py
        ins.lastX = nil
        if ins.ctrl then utils.setVisible(ins.ctrl, true) end
        for i = 1, #(ins.notches or {}) do utils.setVisible(ins.notches[i], true) end
    end,
    update = function(ins, dt)
        local prevx, prevy = ins.px, ins.py
        ins.t = ins.t + dt
        local px, py = ins:posAt(ins.t)
        ins.px = px; ins.py = py
        local p = state.player
        if p then
            local onTop = p.vy >= -1
                and p.x + p.w > prevx + 2 and p.x < prevx + ins.w - 2
                and math.abs((p.y + p.h) - prevy) <= 8
            if onTop then
                p.x = p.x + (px - prevx)
                p.y = p.y + (py - prevy)
            end
        end
    end,
    sols = function(ins, out)
        out[#out + 1] = { x = ins.px, y = ins.py, w = ins.w, h = ins.h }
    end,
    kills = function() end,
    sync = function(ins)
        if not ins.ctrl then return end
        if ins.lastX == ins.px and ins.lastY2 == ins.py then return end
        ins.lastX = ins.px
        ins.lastY2 = ins.py
        local cx, cy = utils.rectCenter(ins.px, ins.py, ins.w, ins.h)
        utils.setPos(ins.ctrl, cx, cy)
        for i = 1, #(ins.notches or {}) do
            utils.setPos(ins.notches[i],
                utils.toUIX(ins.px + ins.w / 2 - 14 + (i - 1) * 12 + 3),
                utils.toUIY(ins.py + ins.h / 2))
        end
    end,
}

-- ================================================================
-- 10. 传送带 Conveyor
-- ================================================================
KIND.conveyor = {
    init = function(ins, s)
        ins.rect = s.rect
        ins.dir = num(s.dir, 1)
        ins.force = num(s.force, config.DEFAULT_CONVEYOR_FORCE)
        ins.t = 0
    end,
    build = function(ins)
        local r = ins.rect
        ins.ctrl = utils.createRectWorld(r.x, r.y, r.w, r.h,
            utils.pal("ink"), 255, state.containerWorld)
        ins.arrows = {}
        local n = math.min(5, math.max(2, math.floor(r.w / 70)))
        ins.arrowN = n
        for i = 1, n do
            local c = diamond(r.x, r.y + r.h / 2, 12, utils.pal("bg"), 255, state.containerWorld)
            if c then ins.arrows[#ins.arrows + 1] = c end
        end
    end,
    reset = function(ins)
        ins.t = 0
        if ins.ctrl then utils.setVisible(ins.ctrl, true) end
        for i = 1, #(ins.arrows or {}) do utils.setVisible(ins.arrows[i], true) end
    end,
    update = function(ins, dt)
        ins.t = ins.t + dt * ins.dir
        local p = state.player
        local r = ins.rect
        if not p then return end
        local standing = p.grounded and math.abs((p.y + p.h) - r.y) < 4
            and p.x + p.w > r.x and p.x < r.x + r.w
        if standing then p.x = p.x + ins.dir * ins.force * dt end
    end,
    sols = function(ins, out) out[#out + 1] = ins.rect end,
    kills = function() end,
    sync = function(ins)
        if not ins.arrows then return end
        local r = ins.rect
        local span = r.w - 24
        local off = (ins.t * 70) % 40
        for i = 1, #ins.arrows do
            local base = ((i - 1) * (span / math.max(1, ins.arrowN - 1)) + off) % math.max(1, span)
            utils.setPos(ins.arrows[i], utils.toUIX(r.x + 12 + base), utils.toUIY(r.y + r.h / 2))
        end
    end,
}

-- ================================================================
-- 11. 弹簧 Spring
-- ================================================================
KIND.spring = {
    init = function(ins, s)
        ins.x = num(s.x, 0); ins.y = num(s.y, 0)
        ins.w = num(s.w, config.DEFAULT_SPRING_W)
        ins.h = num(s.h, config.DEFAULT_SPRING_H)
        ins.power = num(s.power, config.DEFAULT_SPRING_POWER)
        ins.c = 0
    end,
    build = function(ins)
        ins.plate = utils.createRectWorld(ins.x, ins.y, ins.w, 7,
            utils.pal("accent"), 255, state.containerWorld)
        ins.coilA = utils.createRectWorld(ins.x + 6, ins.y + 8, 3, ins.h,
            utils.pal("accent"), 200, state.containerWorld)
        ins.coilB = utils.createRectWorld(ins.x + ins.w - 9, ins.y + 8, 3, ins.h,
            utils.pal("accent"), 200, state.containerWorld)
    end,
    reset = function(ins)
        ins.c = 0
        ins.lastC = nil
    end,
    update = function(ins, dt)
        ins.c = math.max(0, ins.c - dt * 5)
        local p = state.player
        if not p then return end
        local overX = p.x + p.w > ins.x + 3 and p.x < ins.x + ins.w - 3
        local bottom = p.y + p.h
        if overX and p.vy >= 0 and bottom >= ins.y - 6 and bottom <= ins.y + 40 then
            p.y = ins.y - p.h
            p.vy = ins.power
            p.grounded = false
            ins.c = 1
            audio.playJump()
            fx.dust(ins.x + ins.w / 2, ins.y, 5)
        end
    end,
    sols = function() end,
    kills = function() end,
    sync = function(ins)
        if not ins.plate then return end
        if ins.lastC == ins.c then return end
        ins.lastC = ins.c
        local comp = ins.c * 6
        utils.setPos(ins.plate, utils.toUIX(ins.x + ins.w / 2), utils.toUIY(ins.y + comp + 3.5))
        local coilH = math.max(2, ins.h - comp)
        utils.setSize(ins.coilA, 3, coilH)
        utils.setSize(ins.coilB, 3, coilH)
        utils.setPos(ins.coilA, utils.toUIX(ins.x + 7.5), utils.toUIY(ins.y + comp + 8 + coilH / 2))
        utils.setPos(ins.coilB, utils.toUIX(ins.x + ins.w - 7.5), utils.toUIY(ins.y + comp + 8 + coilH / 2))
    end,
}

-- ================================================================
-- 12. 锯片 Saw（沿折线往返）
-- ================================================================
KIND.saw = {
    init = function(ins, s)
        ins.path = s.path or { { x = 0, y = 0 }, { x = 0, y = 0 } }
        ins.r = num(s.r, config.DEFAULT_SAW_R)
        ins.speed = num(s.speed, config.DEFAULT_SAW_SPEED)
        ins.seg = 1
        ins.dir = 1
        ins.f = 0
        ins.spin = 0
        ins.x = ins.path[1].x
        ins.y = ins.path[1].y
    end,
    build = function(ins)
        ins.a = diamond(ins.x, ins.y, ins.r * 1.30, utils.pal("ink"), 255, state.containerWorld)
        ins.b = diamond(ins.x, ins.y, ins.r * 1.30, utils.pal("ink"), 255, state.containerWorld)
        if ins.b then utils.setRot(ins.b, 90) end
        ins.core = utils.createRectAtWorld(ins.x, ins.y, ins.r * 0.5, ins.r * 0.5,
            utils.pal("bg"), 255, state.containerWorld)
    end,
    reset = function(ins)
        ins.seg = 1; ins.dir = 1; ins.f = 0; ins.spin = 0
        ins.x = ins.path[1].x; ins.y = ins.path[1].y
        if ins.a then utils.setVisible(ins.a, true) end
        if ins.b then utils.setVisible(ins.b, true) end
        if ins.core then utils.setVisible(ins.core, true) end
        ins.lastSpin = nil
    end,
    update = function(ins, dt)
        ins.spin = ins.spin + dt * 300
        local n = #ins.path
        if n < 2 then return end
        local a = ins.path[ins.seg]
        local b = ins.path[ins.seg + ins.dir]
        if not b then ins.dir = -ins.dir; return end
        local dx = b.x - a.x
        local dy = b.y - a.y
        local len = math.sqrt(dx * dx + dy * dy)
        if len < 1 then len = 1 end
        ins.f = ins.f + (ins.speed * dt) / len
        local guard = 0
        while ins.f >= 1 and guard < 8 do
            guard = guard + 1
            ins.f = ins.f - 1
            ins.seg = ins.seg + ins.dir
            if ins.seg + ins.dir < 1 or ins.seg + ins.dir > n then
                ins.dir = -ins.dir
            end
            if ins.seg < 1 then ins.seg = 1; ins.dir = 1 end
            if ins.seg > n then ins.seg = n; ins.dir = -1 end
        end
        local a2 = ins.path[ins.seg]
        local b2 = ins.path[ins.seg + ins.dir] or a2
        ins.x = a2.x + (b2.x - a2.x) * ins.f
        ins.y = a2.y + (b2.y - a2.y) * ins.f
    end,
    sols = function() end,
    kills = function(ins, out)
        local rr = ins.r * 0.66
        out[#out + 1] = { x = ins.x - rr, y = ins.y - rr, w = rr * 2, h = rr * 2 }
    end,
    sync = function(ins)
        if not ins.a then return end
        local ux, uy = utils.toUIX(ins.x), utils.toUIY(ins.y)
        utils.setPos(ins.a, ux, uy)
        utils.setPos(ins.b, ux, uy)
        utils.setPos(ins.core, ux, uy)
        if ins.lastSpin ~= ins.spin then
            ins.lastSpin = ins.spin
            utils.setRot(ins.a, ins.spin)
            utils.setRot(ins.b, ins.spin + 45)
        end
    end,
}

-- ================================================================
-- 13. 激光 Laser（预告 → 开火）
-- ================================================================
local function laserState(ins)
    local u = ins.t % ins.period
    if u < ins.period - ins.warn - ins.fire then return "off" end
    if u < ins.period - ins.fire then return "warn" end
    return "fire"
end

KIND.laser = {
    init = function(ins, s)
        ins.x = num(s.x, 0); ins.y = num(s.y, 0)
        ins.len = num(s.len, config.DEFAULT_LASER_LEN)
        ins.vertical = s.vertical and true or false
        ins.thick = num(s.thick, config.DEFAULT_LASER_THICK)
        ins.period = num(s.period, config.DEFAULT_LASER_PERIOD)
        ins.warn = num(s.warn, config.DEFAULT_LASER_WARN)
        ins.fire = num(s.fire, config.DEFAULT_LASER_FIRE)
        ins.phase = num(s.phase, 0)
        ins.t = ins.phase * ins.period
        ins.st = "off"
    end,
    build = function(ins)
        if ins.vertical then
            ins.nub1 = utils.createRectWorld(ins.x - 8, ins.y - 8, 16, 8,
                utils.pal("metal"), 255, state.containerWorld)
            ins.nub2 = utils.createRectWorld(ins.x - 8, ins.y + ins.len, 16, 8,
                utils.pal("metal"), 255, state.containerWorld)
            ins.beam = utils.createRectWorld(ins.x - ins.thick / 2, ins.y, ins.thick, ins.len,
                utils.pal("danger"), 255, state.containerWorld)
        else
            ins.nub1 = utils.createRectWorld(ins.x - 8, ins.y - 8, 8, 16,
                utils.pal("metal"), 255, state.containerWorld)
            ins.nub2 = utils.createRectWorld(ins.x + ins.len, ins.y - 8, 8, 16,
                utils.pal("metal"), 255, state.containerWorld)
            ins.beam = utils.createRectWorld(ins.x, ins.y - ins.thick / 2, ins.len, ins.thick,
                utils.pal("danger"), 255, state.containerWorld)
        end
        if ins.beam then utils.setVisible(ins.beam, false) end
        ins.st = "off"
    end,
    reset = function(ins)
        ins.t = ins.phase * ins.period
        ins.st = "off"
        if ins.beam then utils.setVisible(ins.beam, false) end
    end,
    update = function(ins, dt)
        ins.t = ins.t + dt
        local st = laserState(ins)
        if st ~= ins.st then
            if st == "warn" then audio.playPop() end
            if st == "fire" then audio.playDeath() end
        end
        ins.st = st
    end,
    sols = function() end,
    kills = function(ins, out)
        if ins.st ~= "fire" then return end
        if ins.vertical then
            out[#out + 1] = { x = ins.x - ins.thick / 2, y = ins.y, w = ins.thick, h = ins.len }
        else
            out[#out + 1] = { x = ins.x, y = ins.y - ins.thick / 2, w = ins.len, h = ins.thick }
        end
    end,
    sync = function(ins)
        if not ins.beam then return end
        local st = ins.st
        if st == "off" then
            if ins.shown ~= false then utils.setVisible(ins.beam, false); ins.shown = false end
        elseif st == "warn" then
            if ins.shown ~= "w" then utils.setVisible(ins.beam, true); ins.shown = "w" end
            utils.setColor(ins.beam, utils.pal("danger"), 70)
        else
            if ins.shown ~= "f" then utils.setVisible(ins.beam, true); ins.shown = "f" end
            utils.setColor(ins.beam, utils.pal("danger"), 255)
        end
    end,
}

-- ================================================================
-- 14. 传送门 Teleporter
-- ================================================================
KIND.teleport = {
    init = function(ins, s)
        local w = num(s.w, config.DEFAULT_TELE_W)
        local h = num(s.h, config.DEFAULT_TELE_H)
        ins.a = { x = num(s.ax, 0), y = num(s.ay, 0), w = w, h = h }
        ins.b = { x = num(s.bx, 0), y = num(s.by, 0), w = w, h = h }
        ins.twoWay = s.twoWay ~= false
        ins.cool = 0
        ins.t = 0
    end,
    build = function(ins)
        ins.da = diamond(ins.a.x + ins.a.w / 2, ins.a.y + ins.a.h / 2, 34,
            utils.pal("accent"), 90, state.containerWorld)
        ins.db = diamond(ins.b.x + ins.b.w / 2, ins.b.y + ins.b.h / 2, 34,
            utils.pal("accent"), 90, state.containerWorld)
        ins.ia = diamond(ins.a.x + ins.a.w / 2, ins.a.y + ins.a.h / 2, 18,
            utils.pal("accent"), 200, state.containerWorld)
        ins.ib = diamond(ins.b.x + ins.b.w / 2, ins.b.y + ins.b.h / 2, 18,
            utils.pal("accent"), 200, state.containerWorld)
    end,
    reset = function(ins)
        ins.cool = 0
        ins.t = 0
        if ins.da then utils.setVisible(ins.da, true) end
        if ins.db then utils.setVisible(ins.db, true) end
        if ins.ia then utils.setVisible(ins.ia, true) end
        if ins.ib then utils.setVisible(ins.ib, true) end
    end,
    update = function(ins, dt)
        ins.t = ins.t + dt
        ins.cool = math.max(0, ins.cool - dt)
        if ins.cool > 0 then return end
        local p = state.player
        if not p then return end
        local function warp(from, to)
            fx.poof(from.x + from.w / 2, from.y + from.h / 2)
            p.x = to.x + to.w / 2 - p.w / 2
            p.y = to.y + to.h - p.h
            p.vx = 0
            ins.cool = 0.45
            audio.playPop()
            fx.poof(to.x + to.w / 2, to.y + to.h / 2)
        end
        if utils.aabb(p.x, p.y, p.w, p.h, ins.a.x, ins.a.y, ins.a.w, ins.a.h) then
            warp(ins.a, ins.b)
        elseif ins.twoWay
            and utils.aabb(p.x, p.y, p.w, p.h, ins.b.x, ins.b.y, ins.b.w, ins.b.h) then
            warp(ins.b, ins.a)
        end
    end,
    sols = function() end,
    kills = function() end,
    sync = function(ins)
        if not ins.da then return end
        local s = 1 + 0.08 * math.sin(ins.t * 4)
        utils.setScale(ins.da, s)
        utils.setScale(ins.db, s)
    end,
}

-- ================================================================
-- 15. 按钮 Button
-- ================================================================
KIND.button = {
    init = function(ins, s)
        ins.x = num(s.x, 0); ins.y = num(s.y, 0)
        ins.w = num(s.w, config.DEFAULT_BUTTON_W)
        ins.key = s.key or "k"
        ins.momentary = s.momentary and true or false
        ins.pressed = false
        ins.dip = 0
    end,
    build = function(ins)
        ins.base = utils.createRectWorld(ins.x + 4, ins.y + 4, ins.w - 8, 10,
            utils.pal("metal"), 255, state.containerWorld)
        ins.cap = utils.createRectWorld(ins.x, ins.y, ins.w, 7,
            utils.pal("ink"), 255, state.containerWorld)
    end,
    reset = function(ins)
        ins.pressed = false
        ins.dip = 0
        ins.lastDip = nil
        state.flags[ins.key] = false
    end,
    update = function(ins, dt)
        local p = state.player
        if not p then return end
        local on = utils.aabb(p.x, p.y, p.w, p.h, ins.x, ins.y - 8, ins.w, 22)
        if ins.momentary then
            ins.pressed = on
        elseif on then
            if not ins.pressed then audio.playClick() end
            ins.pressed = true
        end
        state.flags[ins.key] = ins.pressed
        local target = ins.pressed and 1 or 0
        ins.dip = utils.clamp(ins.dip + (target - ins.dip > 0 and 1 or -1) * dt * 8, 0, 1)
    end,
    sols = function() end,
    kills = function() end,
    sync = function(ins)
        if not ins.cap then return end
        if ins.lastDip == ins.dip and ins.lastPressed == ins.pressed then return end
        ins.lastDip = ins.dip
        ins.lastPressed = ins.pressed
        utils.setPos(ins.cap, utils.toUIX(ins.x + ins.w / 2), utils.toUIY(ins.y + ins.dip * 5 + 3.5))
        utils.setColor(ins.cap, ins.pressed and utils.pal("accent") or utils.pal("ink"), 255)
    end,
}

-- ================================================================
-- 16. 闸门 Gate
-- ================================================================
KIND.gate = {
    init = function(ins, s)
        ins.rect = s.rect
        ins.key = s.key or "k"
        ins.invert = s.invert and true or false
        ins.open = 0
    end,
    build = function(ins)
        local r = ins.rect
        ins.ctrl = utils.createRectWorld(r.x, r.y, r.w, r.h,
            utils.pal("ink"), 255, state.containerWorld)
        ins.holes = {}
        for i = 1, 3 do
            local c = utils.createRectWorld(r.x + r.w / 2 - 2, r.y + 10 + (i - 1) * (r.h / 3), 4, r.h / 6,
                utils.pal("accent"), 255, state.containerWorld)
            if c then ins.holes[#ins.holes + 1] = c end
        end
    end,
    reset = function(ins)
        ins.open = 0
        ins.lastOpen = nil
        if ins.ctrl then utils.setVisible(ins.ctrl, true) end
        for i = 1, #(ins.holes or {}) do utils.setVisible(ins.holes[i], true) end
    end,
    update = function(ins, dt)
        local want = state.flags[ins.key] and true or false
        if ins.invert then want = not want end
        ins.open = utils.clamp(ins.open + (want and 1 or -1) * dt * config.DEFAULT_GATE_OPEN_SPEED, 0, 1)
    end,
    sols = function(ins, out)
        if ins.open <= 0.92 then
            local r = ins.rect
            local shift = ins.open * (r.h + 4)
            out[#out + 1] = { x = r.x, y = r.y - shift, w = r.w, h = r.h }
        end
    end,
    kills = function() end,
    sync = function(ins)
        if not ins.ctrl then return end
        if ins.lastOpen == ins.open then return end
        ins.lastOpen = ins.open
        local r = ins.rect
        local shift = ins.open * (r.h + 4)
        if ins.open >= 0.995 then
            utils.setVisible(ins.ctrl, false)
            for i = 1, #(ins.holes or {}) do utils.setVisible(ins.holes[i], false) end
            return
        end
        utils.setVisible(ins.ctrl, true)
        local cx, cy = utils.rectCenter(r.x, r.y - shift, r.w, r.h)
        utils.setPos(ins.ctrl, cx, cy)
        for i = 1, #(ins.holes or {}) do
            utils.setVisible(ins.holes[i], true)
            utils.setPos(ins.holes[i],
                utils.toUIX(r.x + r.w / 2),
                utils.toUIY(r.y - shift + 10 + (i - 1) * (r.h / 3) + r.h / 12))
        end
    end,
}

-- ================================================================
-- 17. 闪烁平台 BlinkPlatform
-- ================================================================
KIND.blink = {
    init = function(ins, s)
        ins.rect = s.rect
        ins.period = num(s.period, config.DEFAULT_BLINK_PERIOD)
        ins.onFrac = num(s.onFrac, config.DEFAULT_BLINK_ON)
        ins.phase = num(s.phase, 0)
        ins.t = ins.phase * ins.period
        ins.on = true
    end,
    build = function(ins)
        local r = ins.rect
        ins.ctrl = utils.createRectWorld(r.x, r.y, r.w, r.h,
            utils.pal("ink"), 255, state.containerWorld)
    end,
    reset = function(ins)
        ins.t = ins.phase * ins.period
        ins.on = true
        if ins.ctrl then
            utils.setVisible(ins.ctrl, true)
            utils.setColor(ins.ctrl, utils.pal("ink"), 255)
        end
        ins.lastOn = nil
    end,
    update = function(ins, dt)
        ins.t = ins.t + dt
        ins.on = ((ins.t % ins.period) < ins.period * ins.onFrac)
    end,
    sols = function(ins, out)
        if ins.on then out[#out + 1] = ins.rect end
    end,
    kills = function() end,
    sync = function(ins)
        if not ins.ctrl then return end
        if ins.lastOn == ins.on then return end
        ins.lastOn = ins.on
        if ins.on then
            utils.setColor(ins.ctrl, utils.pal("ink"), 255)
        else
            utils.setColor(ins.ctrl, utils.pal("ink"), 46)
        end
    end,
}

-- ================================================================
-- 18. 摆锤 Pendulum
-- ================================================================
KIND.pendulum = {
    init = function(ins, s)
        ins.px = num(s.px, 0); ins.py = num(s.py, 0)
        ins.len = num(s.len, config.DEFAULT_PEND_LEN)
        ins.amp = num(s.amp, config.DEFAULT_PEND_AMP)
        ins.speed = num(s.speed, config.DEFAULT_PEND_SPEED)
        ins.r = num(s.r, config.DEFAULT_PEND_R)
        ins.phase = num(s.phase, 0)
        ins.t = ins.phase
        ins.bx = ins.px; ins.by = ins.py + ins.len
        ins.ang = 0
    end,
    build = function(ins)
        ins.rope = utils.createRectWorld(ins.px - 1.5, ins.py, 3, ins.len,
            utils.pal("metal"), 255, state.containerWorld)
        ins.bobA = diamond(ins.bx, ins.by, ins.r * 1.5, utils.pal("ink"), 255, state.containerWorld)
        ins.bobB = diamond(ins.bx, ins.by, ins.r * 1.5, utils.pal("ink"), 255, state.containerWorld)
        if ins.bobB then utils.setRot(ins.bobB, 90) end
        ins.pin = utils.createRectAtWorld(ins.px, ins.py, 10, 10, utils.pal("ink"), 255, state.containerWorld)
    end,
    reset = function(ins)
        ins.t = ins.phase
        ins.lastAng = nil
    end,
    update = function(ins, dt)
        ins.t = ins.t + dt
        local a = math.sin(ins.t * ins.speed) * ins.amp
        ins.ang = a
        ins.bx = ins.px + math.sin(a) * ins.len
        ins.by = ins.py + math.cos(a) * ins.len
    end,
    sols = function() end,
    kills = function(ins, out)
        local rr = ins.r * 0.66
        out[#out + 1] = { x = ins.bx - rr, y = ins.by - rr, w = rr * 2, h = rr * 2 }
    end,
    sync = function(ins)
        if not ins.rope then return end
        if ins.lastAng == ins.ang then return end
        ins.lastAng = ins.ang
        -- 绳子：中心放在支点与锤头的中点，长度按当前投影算，再整体旋转
        local mx = (ins.px + ins.bx) / 2
        local my = (ins.py + ins.by) / 2
        utils.setSize(ins.rope, 3, ins.len)
        utils.setPos(ins.rope, utils.toUIX(mx), utils.toUIY(my))
        utils.setRot(ins.rope, ins.ang * 57.29578)
        local ux, uy = utils.toUIX(ins.bx), utils.toUIY(ins.by)
        utils.setPos(ins.bobA, ux, uy)
        utils.setPos(ins.bobB, ux, uy)
        utils.setRot(ins.bobA, ins.ang * 57.29578)
        utils.setRot(ins.bobB, ins.ang * 57.29578 + 45)
    end,
}

-- ================================================================
-- 19. 炮台 Turret
-- ================================================================
KIND.turret = {
    init = function(ins, s)
        ins.x = num(s.x, 0); ins.y = num(s.y, 0)
        ins.dir = num(s.dir, -1)
        ins.period = num(s.period, config.DEFAULT_TURRET_PERIOD)
        ins.speed = num(s.speed, config.DEFAULT_TURRET_SPEED)
        ins.phase = num(s.phase, 0)
        ins.r = num(s.r, config.DEFAULT_TURRET_R)
        ins.t = ins.phase * ins.period
        ins.shots = {}
    end,
    build = function(ins)
        ins.body = utils.createRectWorld(ins.x - 14, ins.y - 11, 18, 22,
            utils.pal("metal"), 255, state.containerWorld)
        ins.barrel = utils.createRectWorld(ins.x + (ins.dir < 0 and -14 or 6), ins.y - 4, 10, 8,
            utils.pal("metal"), 255, state.containerWorld)
        local n = math.floor(config.DEFAULT_TURRET_BULLETS or 5)
        ins.bullets = {}
        for i = 1, n do
            local c = utils.createRectAtWorld(-100, -100, ins.r * 2, ins.r * 2,
                utils.pal("danger"), 255, state.containerWorld)
            if c then
                utils.setVisible(c, false)
                ins.bullets[#ins.bullets + 1] = c
            end
        end
    end,
    reset = function(ins)
        ins.t = ins.phase * ins.period
        ins.shots = {}
        for i = 1, #(ins.bullets or {}) do utils.setVisible(ins.bullets[i], false) end
    end,
    update = function(ins, dt)
        ins.t = ins.t + dt
        if ins.t >= ins.period then
            ins.t = ins.t - ins.period
            ins.shots[#ins.shots + 1] = { x = ins.x, y = ins.y }
            audio.playPop()
        end
        for i = 1, #ins.shots do
            ins.shots[i].x = ins.shots[i].x + ins.dir * ins.speed * dt
        end
        -- 回收出界子弹
        local keep = {}
        for i = 1, #ins.shots do
            local s = ins.shots[i]
            if s.x > -40 and s.x < 1000 then keep[#keep + 1] = s end
        end
        ins.shots = keep
    end,
    sols = function() end,
    kills = function(ins, out)
        for i = 1, #ins.shots do
            local s = ins.shots[i]
            out[#out + 1] = { x = s.x - ins.r, y = s.y - ins.r, w = ins.r * 2, h = ins.r * 2 }
        end
    end,
    sync = function(ins)
        if not ins.bullets then return end
        for i = 1, #ins.bullets do
            local c = ins.bullets[i]
            local s = ins.shots[i]
            if s then
                utils.setVisible(c, true)
                utils.setPos(c, utils.toUIX(s.x), utils.toUIY(s.y))
            else
                utils.setVisible(c, false)
            end
        end
    end,
}

-- ================================================================
-- 20. 假门 FakeDoor
-- ================================================================
local function buildDoorShape(ins, parent, x, y, w, h, hex, alpha)
    -- 门体（去掉顶部圆角高度的部分）+ 顶盖 + 门把手
    local capH = 14
    ins.body = utils.createRectWorld(x, y + capH, w, h - capH, hex, alpha, parent)
    ins.cap = utils.createRectWorld(x + 3, y + 3, w - 6, capH, hex, alpha, parent)
    ins.capTop = utils.createRectWorld(x + 8, y, w - 16, 5, hex, alpha, parent)
    ins.knob = utils.createRectAtWorld(x + w - 9, y + h / 2 + 4, 7, 7,
        utils.pal("bg"), alpha, parent)
end

KIND.fakedoor = {
    init = function(ins, s)
        ins.x = num(s.x, 0); ins.y = num(s.y, 0)
        ins.w = config.DEFAULT_DOOR_W or 38
        ins.h = config.DEFAULT_DOOR_H or 64
        ins.label = s.label
        ins.sprung = false
        ins.out = 0
    end,
    build = function(ins)
        buildDoorShape(ins, state.containerWorld, ins.x, ins.y, ins.w, ins.h,
            utils.pal("door"), 255)
        if ins.label and ins.label ~= "" then
            ins.lab = utils.createTextWorld(ins.x + ins.w / 2, ins.y - 12, 190, 24,
                ins.label, utils.pal("ink"), 13, state.containerWorld)
            if ins.lab then pcall(function() ins.lab.fontColor = utils.hexToColorA(utils.pal("ink"), 120) end) end
        end
    end,
    reset = function(ins)
        ins.sprung = false
        ins.out = 0
        ins.lastOut = nil
    end,
    update = function(ins, dt)
        if not ins.sprung then
            local p = state.player
            if p and utils.aabb(p.x, p.y, p.w, p.h, ins.x - 2, ins.y, ins.w + 4, ins.h) then
                ins.sprung = true
                audio.playDeath()
            end
        end
        if ins.sprung then ins.out = utils.clamp(ins.out + 16 * dt, 0, 1) end
    end,
    sols = function() end,
    kills = function(ins, out)
        if ins.out > 0.4 then
            out[#out + 1] = { x = ins.x - 6, y = ins.y, w = ins.w + 12, h = ins.h }
        end
    end,
    sync = function(ins)
        if not ins.body then return end
        if ins.lastOut == ins.out then return end
        ins.lastOut = ins.out
        if ins.out > 0.02 then
            -- 中招：整扇门变红（原版会向两侧张开獠牙，图元版用换色 + 抖动代替）
            local jx = fx.random(-3, 3)
            utils.setColor(ins.body, utils.pal("danger"), 255)
            utils.setColor(ins.cap, utils.pal("danger"), 255)
            utils.setColor(ins.capTop, utils.pal("danger"), 255)
            local cx, cy = utils.rectCenter(ins.x + jx, ins.y, ins.w, ins.h)
            utils.setPos(ins.body, cx, utils.toUIY(ins.y + 14 + (ins.h - 14) / 2))
            utils.setPos(ins.cap, cx, utils.toUIY(ins.y + 3 + 7))
            utils.setPos(ins.capTop, cx, utils.toUIY(ins.y + 2.5))
            utils.setPos(ins.knob, utils.toUIX(ins.x + jx + ins.w - 9), utils.toUIY(ins.y + ins.h / 2 + 4))
        end
    end,
}

-- ================================================================
-- 21. 旁白文字 Note（纯装饰）
-- ================================================================
KIND.note = {
    init = function(ins, s)
        ins.x = num(s.x, 0); ins.y = num(s.y, 0)
        ins.text = tostring(s.text or "")
        ins.size = num(s.size, 15)
        ins.angle = num(s.angle, 0)
    end,
    build = function(ins)
        ins.ctrl = utils.createTextWorld(ins.x, ins.y, 400, 26, ins.text,
            utils.pal("ink"), ins.size, state.containerWorld)
        if ins.ctrl then
            pcall(function() ins.ctrl.fontColor = utils.hexToColorA(utils.pal("ink"), 92) end)
            if ins.angle ~= 0 then utils.setRot(ins.ctrl, ins.angle * 57.29578) end
        end
    end,
    reset = function() end,
    update = function() end,
    sols = function() end,
    kills = function() end,
    sync = function() end,
}

-- ================================================================
-- 移动平台的位置插值（放在 KIND.mover 定义之后，避免闭包引用 nil）
-- ================================================================
moverPosAt = function(ins, t)
    local cyc = ins.cycle
    if cyc <= 0 then return ins.ax, ins.ay end
    local u = ((t % cyc) + cyc) % cyc
    local f
    if u < ins.travel then
        f = u / ins.travel
    elseif u < ins.travel + ins.pause then
        f = 1
    elseif u < ins.travel * 2 + ins.pause then
        f = 1 - (u - ins.travel - ins.pause) / ins.travel
    else
        f = 0
    end
    local e = utils.easeInOut(f)
    return utils.lerp(ins.ax, ins.bx, e), utils.lerp(ins.ay, ins.by, e)
end

-- ================================================================
-- 对外接口
-- ================================================================
function M.create(spec)
    local kind = spec and spec.kind or "note"
    local impl = KIND[kind]
    if not impl then
        printerr("[trap] 未知陷阱类型: " .. tostring(kind))
        return nil
    end
    local ins = { kind = kind, impl = impl }
    if kind == "mover" then
        ins.posAt = moverPosAt
    end
    impl.init(ins, spec)
    return ins
end

function M.buildAll()
    for i = 1, #state.traps do
        local ins = state.traps[i]
        if ins.impl and ins.impl.build then
            pcall(ins.impl.build, ins)
        end
    end
end

function M.resetAll()
    for i = 1, #state.traps do
        local ins = state.traps[i]
        if ins.impl and ins.impl.reset then
            pcall(ins.impl.reset, ins)
        end
    end
end

function M.updateAll(dt)
    for i = 1, #state.traps do
        local ins = state.traps[i]
        if ins.impl and ins.impl.update then
            pcall(ins.impl.update, ins, dt)
        end
    end
end

function M.syncAll()
    for i = 1, #state.traps do
        local ins = state.traps[i]
        if ins.impl and ins.impl.sync then
            pcall(ins.impl.sync, ins)
        end
    end
end

function M.collectSolids(out)
    for i = 1, #state.traps do
        local ins = state.traps[i]
        if ins.impl and ins.impl.sols then
            pcall(ins.impl.sols, ins, out)
        end
    end
end

function M.collectKills(out)
    for i = 1, #state.traps do
        local ins = state.traps[i]
        if ins.impl and ins.impl.kills then
            pcall(ins.impl.kills, ins, out)
        end
    end
end

-- ================================================================
-- ★ 所有陷阱可能使用的控件字段名（按「下 → 上」的叠放顺序排列）
--   destroyAll / raiseAll 共用这一张表，新增陷阱时记得在这里登记。
-- ================================================================
local WKEYS = {
    "ctrl",
    "body", "barrel", "cap", "capTop", "knob",
    "shaft", "head",
    "plate", "coilA", "coilB",
    "nub1", "nub2", "beam",
    "left", "right", "edgeL", "edgeR",
    "base", "holes",
    "a", "b", "core",
    "rope", "pin", "bobA", "bobB",
    "da", "db", "ia", "ib",
    "bullets", "pieces", "cracks", "teeth",
    "notches", "arrows",
    "crack", "mark", "lab",
}

local function eachWidget(ins, fn)
    for i = 1, #WKEYS do
        local v = ins[WKEYS[i]]
        if type(v) == "table" then
            -- 可能是「{ctrl=, ...}」包装（pieces / teeth），
            -- 也可能是「控件数组」（cracks / notches / arrows / holes / bullets）
            local isWrapped = (v.ctrl ~= nil) or (v.px ~= nil)
            local arr = isWrapped and { v } or v
            for j = 1, #arr do
                local e = arr[j]
                if type(e) == "table" then
                    if e.ctrl then fn(e.ctrl) end
                elseif e then
                    fn(e)
                end
            end
        elseif v then
            fn(v)
        end
    end
end

-- 销毁所有陷阱控件（换关时）
function M.destroyAll()
    for i = 1, #state.traps do
        local ins = state.traps[i]
        if ins then eachWidget(ins, utils.destroy) end
    end
    state.traps = {}
end

-- ★ 把所有陷阱控件按「下 → 上」重新提层
--   模拟器与真机的「创建顺序 → 叠放顺序」正好相反，所以建完必须显式定序。
function M.raiseAll()
    for i = 1, #state.traps do
        local ins = state.traps[i]
        if ins then eachWidget(ins, utils.raise) end
    end
end

return M
