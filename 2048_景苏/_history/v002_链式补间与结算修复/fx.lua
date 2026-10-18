-- ================================================================
-- 2048 · 特效模块
--   ① 粒子迸溅：合并时从格子中心炸出一把彩色小方块（会被重力拉下、自转、淡出）
--   ② 飘字：「+N」从格子上方浮起并淡出
--   两者都挂在 containerFx（在棋盘之上、HUD 之下），坐标用场景设计坐标。
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

-- ================================================================
-- ★ 粒子迸溅
--   x, y   : 迸溅中心（场景设计坐标）
--   hex    : 粒子颜色（取合并后方块的底色）
--   count  : 数量（缺省用 config）
-- ================================================================
function M.burst(x, y, hex, count)
    if not state.containerFx then return end
    if state.rectPrefabId <= 0 then return end

    local n = math.floor(count or config.DEFAULT_FX_PARTICLE_COUNT or 12)
    local max = math.floor(config.DEFAULT_FX_PARTICLE_MAX or 160)
    local speed = config.DEFAULT_FX_PARTICLE_SPEED or 300
    local size = config.DEFAULT_FX_PARTICLE_SIZE or 12
    local life = config.DEFAULT_FX_PARTICLE_LIFE or 0.50
    local cr, cg, cb = utils.hexToRGB(hex or "FFFFFF")

    for i = 1, n do
        if #state.particles >= max then break end
        local s = size * rnd(0.55, 1.15)
        local ctrl = utils.createControl(state.rectPrefabId, x, y, s, s,
            utils.hexToColor(hex or "FFFFFF"), state.containerFx)
        if ctrl then
            -- 均匀铺满一圈再抖一点，视觉上像「炸开」而不是「喷成一条线」
            local ang = (i / n) * math.pi * 2 + rnd(-0.28, 0.28)
            local spd = speed * rnd(0.55, 1.25)
            state.particles[#state.particles + 1] = {
                ctrl = ctrl,
                r = cr, g = cg, b = cb,
                x = x, y = y,
                vx = math.cos(ang) * spd,
                vy = math.sin(ang) * spd,
                t = 0,
                life = life * rnd(0.7, 1.2),
                size = s,
                rot = rnd(-20, 20),
                spin = (config.DEFAULT_FX_PARTICLE_SPIN or 260) * rnd(-1, 1),
            }
        end
    end
end

-- ================================================================
-- ★ 飘字（「+4」「+16」…）
-- ================================================================
function M.floatText(x, y, text, hex)
    if not state.containerFx then return end
    local size = config.DEFAULT_FX_FLOAT_SIZE or 30
    local ctrl = utils.createText(x, y, 220, utils.MIN_TEXT_H, text,
        utils.hexToColor(hex or "776E65"), size, state.containerFx)
    if not ctrl then return end
    utils.raise(ctrl)      -- ★ 飘字要压在粒子之上（模拟器渲染顺序与真机相反）
    local r, g, b = utils.hexToRGB(hex or "776E65")
    state.floaters[#state.floaters + 1] = {
        ctrl = ctrl,
        r = r, g = g, b = b,
        x = x, y = y,
        t = 0,
        life = config.DEFAULT_FX_FLOAT_LIFE or 0.70,
        rise = config.DEFAULT_FX_FLOAT_RISE or 76,
    }
end

-- ================================================================
-- ★ 每帧推进
-- ================================================================
function M.update(dt)
    if not dt or dt <= 0 then return end

    -- ---- 粒子 ----
    if #state.particles > 0 then
        local keep = {}
        local g = config.DEFAULT_FX_PARTICLE_GRAVITY or 1100
        for i = 1, #state.particles do
            local p = state.particles[i]
            p.t = p.t + dt
            if p.t >= p.life then
                utils.destroy(p.ctrl)
            else
                p.vy = p.vy + g * dt
                p.x = p.x + p.vx * dt
                p.y = p.y + p.vy * dt
                p.rot = p.rot + p.spin * dt
                local k = 1 - (p.t / p.life)          -- 逐渐缩小
                local a = 255 * (1 - (p.t / p.life) * (p.t / p.life))
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
            if f.t >= f.life then
                utils.destroy(f.ctrl)
            else
                local raw = f.t / f.life
                local p = 1 - (1 - raw) * (1 - raw)   -- outQuad
                local a = 255 * (1 - raw * raw)
                pcall(function()
                    f.ctrl:SetAnchoredPosition(f.x, f.y + f.rise * p)
                    f.ctrl:SetLocalScale(1 + 0.18 * (1 - raw), 1 + 0.18 * (1 - raw), 1)
                    f.ctrl.fontColor = Color.FromRGBA(f.r, f.g, f.b, math.floor(a))
                end)
                keep[#keep + 1] = f
            end
        end
        state.floaters = keep
    end
end

-- ================================================================
-- ★ 清空（重开一局时打扫战场）
-- ================================================================
function M.clear()
    for i = 1, #state.particles do utils.destroy(state.particles[i].ctrl) end
    for i = 1, #state.floaters do utils.destroy(state.floaters[i].ctrl) end
    state.particles = {}
    state.floaters = {}
end

return M
