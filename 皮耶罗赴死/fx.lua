-- ================================================================
-- 皮耶罗：赴死 · 特效模块
--   ① 粒子池：血花 / 落尘 / 传送烟雾，控件一次建好反复复用
--      （原版每次死亡炸 26 个粒子；逐次创建销毁在真机上会抖）
--   ② 血渍池：死亡残留在地面，复活时清空（与原版 stains 行为一致）
--   ③ 震屏：只改 containerScene 的偏移，不改任何子控件
--   ★ 坐标一律传【世界坐标】（960×540，y 向下），本模块内部再换算。
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
        pcall(function() math.randomseed(os.time() + 5171) end)
    end
    if b <= a then return a end
    return a + (b - a) * math.random()
end

-- 对外暴露的随机数（trap / comic 也会用到）
function M.random(a, b)
    return rnd(a, b)
end

-- ================================================================
-- 粒子池
-- ================================================================
local pool = {}          -- { ctrl, busy, x, y, vx, vy, t, life, hex, size, grav }
local poolReady = false

local function ensurePool()
    if poolReady then return end
    poolReady = true
    local n = math.floor(config.DEFAULT_FX_POOL or 44)
    for i = 1, n do
        local ctrl = utils.createControl(state.rectPrefabId, 0, 0, 8, 8,
            utils.hexToColorA("FFFFFF", 255), state.containerFx)
        if ctrl then
            ctrl:SetActive(false)
            pool[#pool + 1] = { ctrl = ctrl, busy = false }
        end
    end
end

local function take()
    for i = 1, #pool do
        if not pool[i].busy then return pool[i] end
    end
    return nil
end

-- 弹出一颗粒子
--   wx, wy : 世界坐标
--   vx, vy : 速度（世界单位/秒，y 向下为正）
--   size   : 边长
--   life   : 存活秒数
--   hex    : 颜色
--   grav   : 每秒重力加速度（0 = 无重力；负数 = 往上飘）
local function emit(wx, wy, vx, vy, size, life, hex, grav)
    ensurePool()
    local p = take()
    if not p then return end
    p.busy = true
    p.x = wx
    p.y = wy
    p.vx = vx
    p.vy = vy
    p.t = 0
    p.life = life
    p.hex = hex or "FF5D52"
    p.size = size
    p.grav = grav or 0
    utils.setPos(p.ctrl, utils.toUIX(wx), utils.toUIY(wy))
    utils.setSize(p.ctrl, size, size)
    utils.setColor(p.ctrl, p.hex, 255)
    utils.setVisible(p.ctrl, true)
end

-- 血花：向上喷散 + 重力
function M.blood(wx, wy)
    local n = math.floor(config.DEFAULT_BLOOD_COUNT or 12)
    local pal = config.DEFAULT_PALETTE or {}
    for i = 1, n do
        local ang = rnd(math.pi, math.pi * 2)     -- 世界 y 向下 → 上半圆的角度
        local spd = rnd(120, 420)
        local s = rnd(3, 7)
        local hex = pal.blood or "FF5D52"
        if math.random() < 0.25 then hex = pal.bloodDark or "B83A31" end
        emit(wx, wy, math.cos(ang) * spd, math.sin(ang) * spd, s,
            rnd(0.5, 1.1), hex, 1300)
    end
end

-- 落尘 / 脚步 / 落地
function M.dust(wx, wy, count)
    local n = math.floor(count or config.DEFAULT_DUST_COUNT or 6)
    local pal = config.DEFAULT_PALETTE or {}
    for i = 1, n do
        emit(wx + rnd(-10, 10), wy,
            rnd(-60, 60), rnd(-90, -20),
            rnd(2, 5), rnd(0.25, 0.5), pal.dust or "565B69", 0)
    end
end

-- 传送 / 化鬼 / 复活
function M.poof(wx, wy)
    local n = math.floor(config.DEFAULT_POOF_COUNT or 8)
    local pal = config.DEFAULT_PALETTE or {}
    for i = 1, n do
        local ang = rnd(0, math.pi * 2)
        local spd = rnd(40, 170)
        emit(wx, wy, math.cos(ang) * spd, math.sin(ang) * spd,
            rnd(3, 7), rnd(0.3, 0.55), pal.accent or "FFB24D", 0)
    end
end

-- ================================================================
-- 血渍池
-- ================================================================
local stains = {}
local stainReady = false
local stainIdx = 0

local function ensureStains()
    if stainReady then return end
    stainReady = true
    local n = math.floor(config.DEFAULT_STAIN_POOL or 24)
    for i = 1, n do
        local ctrl = utils.createControl(state.rectPrefabId, 0, 0, 8, 8,
            utils.hexToColorA("FF5D52", 140), state.containerStain)
        if ctrl then
            ctrl:SetActive(false)
            stains[#stains + 1] = ctrl
        end
    end
end

-- 在（世界坐标）地面上留一摊血
function M.stain(wx, wy)
    ensureStains()
    if #stains == 0 then return end
    local pal = config.DEFAULT_PALETTE or {}
    for i = 1, 3 do
        stainIdx = stainIdx % #stains + 1
        local ctrl = stains[stainIdx]
        if ctrl then
            local r = rnd(4, 10)
            utils.setPos(ctrl, utils.toUIX(wx + rnd(-24, 24)), utils.toUIY(wy + rnd(-3, 3)))
            utils.setSize(ctrl, r * 2, r * 2)
            utils.setColor(ctrl, pal.blood or "FF5D52", 120)
            utils.setVisible(ctrl, true)
        end
    end
end

function M.clearStains()
    for i = 1, #stains do
        utils.setVisible(stains[i], false)
    end
    stainIdx = 0
end

-- ================================================================
-- 震屏
-- ================================================================
function M.shake(amt, t)
    if (amt or 0) > (state.shakeAmt or 0) then state.shakeAmt = amt end
    if (t or 0) > (state.shakeT or 0) then state.shakeT = t end
end

-- ================================================================
-- 每帧推进
--   ★ dt 的单位是秒；粒子位置是世界坐标
-- ================================================================
function M.update(dt)
    if not dt or dt <= 0 then return end

    for i = 1, #pool do
        local p = pool[i]
        if p.busy then
            p.t = p.t + dt
            if p.t >= p.life then
                p.busy = false
                utils.setVisible(p.ctrl, false)
            else
                p.vy = p.vy + p.grav * dt
                p.x = p.x + p.vx * dt
                p.y = p.y + p.vy * dt
                local a = 1 - p.t / p.life
                utils.setPos(p.ctrl, utils.toUIX(p.x), utils.toUIY(p.y))
                utils.setSize(p.ctrl, p.size * (0.4 + 0.6 * a), p.size * (0.4 + 0.6 * a))
                utils.setColor(p.ctrl, p.hex, math.floor(255 * a))
            end
        end
    end

    -- 震屏衰减 + 作用到场景容器
    if (state.shakeT or 0) > 0 then
        state.shakeT = state.shakeT - dt
        if state.shakeT <= 0 then
            state.shakeT = 0
            state.shakeAmt = 0
            utils.setPos(state.containerScene, 0, 0)
        else
            local a = state.shakeAmt or 0
            utils.setPos(state.containerScene, rnd(-a, a), rnd(-a, a))
        end
    end
end

-- 清空所有活动粒子（换关时）
function M.clear()
    for i = 1, #pool do
        local p = pool[i]
        if p.busy then
            p.busy = false
            utils.setVisible(p.ctrl, false)
        end
    end
end

-- 重置全部（换关）：粒子 + 血渍 + 震屏
function M.resetAll()
    M.clear()
    M.clearStains()
    state.shakeT = 0
    state.shakeAmt = 0
    utils.setPos(state.containerScene, 0, 0)
end

return M
