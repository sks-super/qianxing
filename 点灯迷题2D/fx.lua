-- ================================================================
-- 点灯迷题 2D · 特效模块
--   ① 粒子迸溅：点亮时从格心炸出一把暖色小方块（重力 + 自转 + 缩小 + 淡出）
--   ② 熄灭轻烟：熄灭时往上飘一小撮冷色碎屑（无重力、更快消失）
--   ③ 方形冲击波：以被按的格子为中心，四条边组成的方框向外扩散
--      —— 灯阵本来就是方格，用方波比圆环更贴题
--   ④ 飘字：连击 / 提示 / 三星等短提示
--   ⑤ 彩带：通关时从顶部撒下
--   全部挂在 containerFx（棋盘之上、HUD 之下），坐标用**场景设计坐标**。
--   ★ 棋盘内部控件用「棋盘中心」当原点，喂进 fx 前必须 utils.boardToScene()。
-- ================================================================

---@diagnostic disable: undefined-global

local M = {}

local state = require("default_import_file/state")
local config = require("default_import_file/config")
local utils = require("default_import_file/utils")

local seeded = false
local function rnd(a, b)
    if not seeded then
        seeded = true
        pcall(function() math.randomseed(os.time() + 7717) end)
    end
    if b <= a then return a end
    return a + (b - a) * math.random()
end

M.random = rnd

-- ================================================================
-- ★ 粒子迸溅
-- ================================================================
function M.burst(x, y, hex, count)
    if not state.containerFx then return end
    if (state.rectPrefabId or 0) <= 0 then return end

    local n = math.floor(count or config.DEFAULT_FX_PARTICLE_COUNT or 9)
    local max = math.floor(config.DEFAULT_FX_PARTICLE_MAX or 200)
    local speed = config.DEFAULT_FX_PARTICLE_SPEED or 250
    local size = config.DEFAULT_FX_PARTICLE_SIZE or 9
    local life = config.DEFAULT_FX_PARTICLE_LIFE or 0.46
    local cr, cg, cb = utils.hexToRGB(hex or "FFCB6B")

    for i = 1, n do
        if #state.particles >= max then break end
        local s = size * rnd(0.5, 1.15)
        local ctrl = utils.createControl(state.rectPrefabId, x, y, s, s,
            utils.hexToColor(hex or "FFCB6B"), state.containerFx)
        if ctrl then
            local ang = (i / n) * math.pi * 2 + rnd(-0.3, 0.3)
            local spd = speed * rnd(0.5, 1.3)
            state.particles[#state.particles + 1] = {
                ctrl = ctrl,
                r = cr, g = cg, b = cb,
                x = x, y = y,
                vx = math.cos(ang) * spd,
                vy = math.sin(ang) * spd,
                t = 0,
                life = life * rnd(0.7, 1.25),
                size = s,
                rot = rnd(-25, 25),
                spin = (config.DEFAULT_FX_PARTICLE_SPIN or 240) * rnd(-1, 1),
                gravity = config.DEFAULT_FX_PARTICLE_GRAVITY or 760,
            }
        end
    end
end

-- ================================================================
-- ★ 熄灭轻烟：往上飘、无重力、更快淡出
-- ================================================================
function M.puff(x, y, hex, count)
    if not state.containerFx then return end
    if (state.rectPrefabId or 0) <= 0 then return end
    local n = math.floor(count or 5)
    local max = math.floor(config.DEFAULT_FX_PARTICLE_MAX or 200)
    local life = (config.DEFAULT_FX_PARTICLE_LIFE or 0.46) * 0.8
    local cr, cg, cb = utils.hexToRGB(hex or "8296B8")

    for i = 1, n do
        if #state.particles >= max then break end
        local s = (config.DEFAULT_FX_PARTICLE_SIZE or 9) * rnd(0.35, 0.8)
        local ctrl = utils.createControl(state.rectPrefabId, x, y, s, s,
            utils.hexToColor(hex or "8296B8"), state.containerFx)
        if ctrl then
            state.particles[#state.particles + 1] = {
                ctrl = ctrl,
                r = cr, g = cg, b = cb,
                x = x, y = y,
                vx = rnd(-70, 70),
                vy = rnd(50, 150),
                t = 0,
                life = life * rnd(0.6, 1.0),
                size = s,
                rot = rnd(-20, 20),
                spin = rnd(-120, 120),
                gravity = -60,
            }
        end
    end
end

-- ================================================================
-- ★ 方形冲击波：四条细边组成一个方框，向外扩散并淡出
--   x, y   : 中心（场景设计坐标）
--   size   : 起始边长（一般给格子边长）
-- ================================================================
function M.ring(x, y, size, hex)
    if not state.containerFx then return end
    if (state.rectPrefabId or 0) <= 0 then return end
    local w = config.DEFAULT_FX_RING_WIDTH or 3
    local s0 = size or (config.DEFAULT_CELL or 100)
    local bars = {}
    for i = 1, 4 do
        local b = utils.createControl(state.rectPrefabId, x, y, s0, w,
            utils.hexToColor(hex or "4CC9F0"), state.containerFx)
        if b then bars[i] = b end
    end
    if #bars < 4 then
        for i = 1, #bars do utils.destroy(bars[i]) end
        return
    end
    state.rings[#state.rings + 1] = {
        bars = bars,
        x = x, y = y, s0 = s0, w = w,
        t = 0,
        life = config.DEFAULT_FX_RING_TIME or 0.40,
        hex = hex or "4CC9F0",
    }
end

-- ================================================================
-- ★ 飘字
-- ================================================================
function M.floatText(x, y, text, hex, size)
    if not state.containerFx then return end
    local fs = size or config.DEFAULT_FX_FLOAT_SIZE or 26
    local ctrl = utils.createText(x, y, 260, utils.textBoxHeight(fs * 1.6, fs), text,
        utils.hexToColor(hex or "E9F0FF"), fs, state.containerFx)
    if not ctrl then return end
    utils.raise(ctrl)
    local r, g, b = utils.hexToRGB(hex or "E9F0FF")
    state.floaters[#state.floaters + 1] = {
        ctrl = ctrl,
        r = r, g = g, b = b,
        x = x, y = y,
        t = 0,
        life = config.DEFAULT_FX_FLOAT_LIFE or 0.72,
        rise = config.DEFAULT_FX_FLOAT_RISE or 72,
    }
end

-- ================================================================
-- ★ 彩带：从画面上方撒下，左右摇摆 + 自转
-- ================================================================
function M.confetti(count)
    if not state.containerFx then return end
    if (state.rectPrefabId or 0) <= 0 then return end
    local n = math.floor(count or config.DEFAULT_FX_CONFETTI_COUNT or 40)
    local max = math.floor(config.DEFAULT_FX_PARTICLE_MAX or 200)
    local pal = config.DEFAULT_PALETTE or {}
    local pool = { pal.star or "FFD166", pal.accent or "4CC9F0",
                   pal.good or "5BE7A9", pal.cellOn or "FFCB6B" }
    local top = (state.canvasH or 720) / 2
    local halfW = (state.designW or 1280) / 2

    for i = 1, n do
        if #state.particles >= max then break end
        local hex = pool[math.random(#pool)]
        local s = rnd(6, 12)
        local x = rnd(-halfW, halfW)
        local ctrl = utils.createControl(state.rectPrefabId, x, top + rnd(0, 40),
            s, s * rnd(1.2, 2.2), utils.hexToColor(hex), state.containerFx)
        if ctrl then
            local cr, cg, cb = utils.hexToRGB(hex)
            state.particles[#state.particles + 1] = {
                ctrl = ctrl,
                r = cr, g = cg, b = cb,
                x = x, y = top + rnd(0, 40),
                vx = rnd(-60, 60),
                vy = -rnd(60, 220),
                t = 0,
                life = (config.DEFAULT_FX_CONFETTI_LIFE or 1.3) * rnd(0.8, 1.25),
                size = s,
                rot = rnd(0, 360),
                spin = rnd(-420, 420),
                gravity = (config.DEFAULT_FX_CONFETTI_SPEED or 420) * 2.2,
                sway = rnd(0.6, 1.8),
            }
        end
    end
end

-- ================================================================
-- ★ 屏幕微震（由 game 读取 state.shakeT 做位移衰减）
-- ================================================================
function M.shake()
    state.shakeT = config.DEFAULT_ANIM_SHAKE_TIME or 0.16
end

-- ================================================================
-- 每帧推进
-- ================================================================
function M.update(dt)
    if not dt or dt <= 0 then return end

    -- ---- 粒子 ----
    if #state.particles > 0 then
        local keep = {}
        for i = 1, #state.particles do
            local p = state.particles[i]
            p.t = p.t + dt
            local raw = p.t / p.life
            if raw >= 1 then
                utils.destroy(p.ctrl)
            else
                p.vy = p.vy - (p.gravity or 0) * dt
                if p.sway then
                    p.x = p.x + (p.vx + math.sin(p.t * 6 * p.sway) * 46) * dt
                else
                    p.x = p.x + p.vx * dt
                end
                p.y = p.y + p.vy * dt
                p.rot = p.rot + p.spin * dt
                local k = 1 - raw * 0.85
                local a = 255 * (1 - raw * raw)
                pcall(function()
                    p.ctrl:SetAnchoredPosition(p.x, p.y)
                    p.ctrl:SetLocalScale(k, k, 1)
                    p.ctrl:SetLocalRotation(0, 0, p.rot)
                    p.ctrl.imageColor = Color.FromRGBA(p.r, p.g, p.b, math.floor(a))
                end)
                keep[#keep + 1] = p
            end
        end
        state.particles = keep
    end

    -- ---- 飘字 ----
    if #state.floaters > 0 then
        local keep = {}
        for i = 1, #state.floaters do
            local f = state.floaters[i]
            f.t = f.t + dt
            local raw = f.t / f.life
            if raw >= 1 then
                utils.destroy(f.ctrl)
            else
                local p = 1 - (1 - raw) * (1 - raw)
                local a = 255 * (1 - raw * raw)
                pcall(function()
                    f.ctrl:SetAnchoredPosition(f.x, f.y + f.rise * p)
                    local s = 1 + 0.20 * (1 - raw)
                    f.ctrl:SetLocalScale(s, s, 1)
                    f.ctrl.fontColor = Color.FromRGBA(f.r, f.g, f.b, math.floor(a))
                end)
                keep[#keep + 1] = f
            end
        end
        state.floaters = keep
    end

    -- ---- 方形冲击波 ----
    if #state.rings > 0 then
        local keep = {}
        for i = 1, #state.rings do
            local r = state.rings[i]
            r.t = r.t + dt
            local raw = r.t / r.life
            if raw >= 1 then
                for j = 1, #r.bars do utils.destroy(r.bars[j]) end
            else
                local e = 1 - (1 - raw) * (1 - raw)
                local s = r.s0 * (1 + ((config.DEFAULT_FX_RING_SCALE or 3.2) - 1) * e)
                local a = math.floor(255 * (1 - raw) * (1 - raw))
                local w = r.w
                local cr, cg, cb = utils.hexToRGB(r.hex)
                pcall(function()
                    -- 上 / 下
                    r.bars[1]:SetSizeDelta(s, w)
                    r.bars[1]:SetAnchoredPosition(r.x, r.y + s / 2)
                    r.bars[2]:SetSizeDelta(s, w)
                    r.bars[2]:SetAnchoredPosition(r.x, r.y - s / 2)
                    -- 左 / 右
                    r.bars[3]:SetSizeDelta(w, s)
                    r.bars[3]:SetAnchoredPosition(r.x - s / 2, r.y)
                    r.bars[4]:SetSizeDelta(w, s)
                    r.bars[4]:SetAnchoredPosition(r.x + s / 2, r.y)
                    local col = Color.FromRGBA(cr, cg, cb, a)
                    for j = 1, 4 do r.bars[j].imageColor = col end
                end)
                keep[#keep + 1] = r
            end
        end
        state.rings = keep
    end
end

-- ================================================================
-- 清空（切关 / 重开时打扫战场）
-- ================================================================
function M.clear()
    for i = 1, #state.particles do utils.destroy(state.particles[i].ctrl) end
    for i = 1, #state.floaters do utils.destroy(state.floaters[i].ctrl) end
    for i = 1, #state.rings do
        for j = 1, #state.rings[i].bars do utils.destroy(state.rings[i].bars[j]) end
    end
    state.particles = {}
    state.floaters = {}
    state.rings = {}
    state.shakeT = 0
end

return M
