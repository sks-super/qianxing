-- ================================================================
-- 瓦雷莎的果园救急 粒子 / 补间动效模块（纯基础图元）
-- ================================================================
-- ★ 为什么不用 Tween 组件 / 序列帧：
--   本工程的动效资源只有一种 —— rectPrefabId（纯色矩形）。所有「果汁迸溅」「星星火花」
--   「面板弹入」「按钮回弹」都用矩形控件 + 逐帧改属性实现，任何设备上表现一致，
--   也不会因为缺资源而静默失效。
--
-- ★ 粒子池：OnStart 一次性建好 fx_count 个矩形，之后只改位置 / 尺寸 / 旋转 / 颜色，
--   不活跃时 SetActive(false)（同时也不再参与更新），避免每帧遍历一堆死控件。
--
-- ★ 补间：M.to(ctrl, 时长, 目标表, 起始表, 缓动, 完成回调)
--   目标表可含 x / y / w / h / a（透明度 0-255）/ hex（配色键或 RRGGBB）。
--   只补间「目标表里出现过的键」，所以一个控件可以叠加多个独立补间
--   （例如面板先弹尺寸、再叠一个纯淡出）。
-- ================================================================

---@diagnostic disable: undefined-global

local M = {}
local state = require("default_import_file/state")
local config = require("default_import_file/config")
local utils = require("default_import_file/utils")

-- ================================================================
-- 缓动
-- ================================================================
local function easeLinear(t) return t end
local function easeOut(t) local u = 1 - t; return 1 - u * u * u end
local function easeIn(t) return t * t end
local function easeBack(t)
    local c1 = 1.70158
    local c3 = c1 + 1
    local u = t - 1
    return 1 + c3 * u * u * u + c1 * u * u
end
local function easeElastic(t)
    if t <= 0 then return 0 end
    if t >= 1 then return 1 end
    local p = 0.36
    return 2 ^ (-10 * t) * math.sin((t - p / 4) * (2 * math.pi) / p) + 1
end

M.EASES = {
    linear = easeLinear,
    out    = easeOut,
    ["in"] = easeIn,
    back   = easeBack,
    elastic = easeElastic,
}

local function resolve(fn)
    if type(fn) == "function" then return fn end
    return M.EASES[fn] or easeOut
end

local function hexOf(key, fallback)
    local pal = state.fxPalette or {}
    local v = pal[key] or key
    if type(v) ~= "string" or #v ~= 6 then return fallback or "FFFFFF" end
    return v
end
M.hexOf = hexOf

-- ================================================================
-- ★ 初始化：建粒子池（挂在 containerFx，位于所有面板之上、黑幕之下）
-- ================================================================
function M.init(palette)
    if palette then state.fxPalette = palette end
    if #state.fxStates > 0 then return true end
    if not state.containerFx then return false end
    if not state.rectPrefabId or state.rectPrefabId <= 0 then return false end

    local n = math.max(8, math.floor(config.DEFAULT_FX_COUNT or 64))
    for i = 1, n do
        local c = utils.createControl(state.rectPrefabId, 0, 0, 1, 1,
            utils.hexToColorA("FFFFFF", 0), state.containerFx)
        state.fxNodes[i] = c
        state.fxStates[i] = { active = false }
        if c then c:SetActive(false) end
    end
    return true
end

-- ================================================================
-- ★ 取一颗粒子（找不到空闲的直接放弃这一颗，不扩容）
-- ================================================================
local cursor = 0
local function takeParticle()
    local n = #state.fxNodes
    if n == 0 then return nil, nil end
    for k = 1, n do
        cursor = cursor % n + 1
        local st = state.fxStates[cursor]
        if st and not st.active and state.fxNodes[cursor] then
            return state.fxNodes[cursor], st
        end
    end
    return nil, nil
end

-- ================================================================
-- ★ 迸溅：在 (x, y) 炸出一簇果汁
--   opt = {
--     n     粒子数（缺省 12）
--     keys  配色键数组（缺省四色果汁 juice1..juice4）
--     dir   中心方向角（度，0=右 90=上，缺省 90）
--     spread 扇形张角（度，缺省 config.DEFAULT_FX_SPREAD）
--     speed / life / size / gravity / spin  覆盖默认值
--     base  基准不透明度（缺省 255）
--   }
-- ================================================================
function M.spawn(x, y, opt)
    opt = opt or {}
    local n = math.max(1, math.floor(opt.n or 12))
    local keys = opt.keys or { "juice1", "juice2", "juice3", "juice4" }
    if #keys == 0 then keys = { "juice1" } end
    local dir    = opt.dir or 90
    local spread = opt.spread or (config.DEFAULT_FX_SPREAD or 150)
    local speed  = opt.speed or (config.DEFAULT_FX_SPEED or 340)
    local life   = opt.life or (config.DEFAULT_FX_LIFE or 0.72)
    local size   = opt.size or (config.DEFAULT_FX_SIZE or 9)
    local grav   = opt.gravity or (config.DEFAULT_FX_GRAVITY or 1500)
    local spin   = opt.spin or 220
    local base   = opt.base or 255

    for i = 1, n do
        local ctrl, st = takeParticle()
        if not ctrl then break end
        local ang = (dir + (math.random() - 0.5) * spread) * math.pi / 180
        local sp  = speed * (0.45 + math.random() * 0.85)
        local sz  = math.max(3, size * (0.55 + math.random() * 0.95))
        st.active = true
        st.x = x
        st.y = y
        st.vx = math.cos(ang) * sp
        st.vy = math.sin(ang) * sp
        st.age = 0
        st.life = life * (0.7 + math.random() * 0.6)
        st.size0 = sz
        st.size = sz
        st.grav = grav
        st.spin = (math.random() - 0.5) * 2 * spin
        st.rot = math.random() * 360
        st.base = base
        st.hex = hexOf(keys[(i - 1) % #keys + 1], "FF9F45")
        utils.setPos(ctrl, st.x, st.y)
        utils.setSize(ctrl, sz, sz)
        utils.setScale(ctrl, 1)
        pcall(function() ctrl:SetLocalRotation(0, 0, st.rot) end)
        utils.setAlpha(ctrl, st.hex, base)
        utils.setVisible(ctrl, true)
    end
end

-- ================================================================
-- ★ 每帧推进粒子
-- ================================================================
local function updateParticles(dt)
    local damp = config.DEFAULT_FX_DAMP or 0.90
    local keep = 1 - (1 - damp) * dt
    if keep < 0 then keep = 0 end
    for i = 1, #state.fxNodes do
        local st = state.fxStates[i]
        local ctrl = state.fxNodes[i]
        if st and st.active and ctrl then
            st.age = st.age + dt
            if st.age >= st.life then
                st.active = false
                utils.setVisible(ctrl, false)
            else
                st.vy = st.vy - st.grav * dt
                st.vx = st.vx * keep
                st.x = st.x + st.vx * dt
                st.y = st.y + st.vy * dt
                st.rot = st.rot + st.spin * dt
                local k = st.age / st.life
                local s = st.size0 * (1 - 0.55 * k)
                utils.setPos(ctrl, st.x, st.y)
                utils.setSize(ctrl, s, s)
                pcall(function() ctrl:SetLocalRotation(0, 0, st.rot) end)
                utils.setAlpha(ctrl, st.hex, st.base * (1 - k * k))
            end
        end
    end
end

-- ================================================================
-- ★ 补间
--   M.to(ctrl, dur, to, from, ease, onDone)
--   to   = { x=, y=, w=, h=, a=, hex= }     只处理出现过的键
--   from = 同上，缺省时 x/y/w/h 取控件当前值；a 缺省视为当前不变（不补间 alpha）
-- ================================================================
function M.to(ctrl, dur, to, from, ease, onDone)
    if not ctrl or type(to) ~= "table" then
        if onDone then pcall(onDone) end
        return nil
    end
    dur = tonumber(dur) or 0
    if dur <= 0 then
        -- 直接落到终点
        M.applyKeys(ctrl, to)
        if onDone then pcall(onDone) end
        return nil
    end
    from = from or {}
    local start = {}
    if to.x ~= nil then
        if from.x == nil then
            local x = 0
            pcall(function() x = ctrl:GetAnchoredPosition() end)
            start.x = x
        else
            start.x = from.x
        end
    end
    if to.y ~= nil then
        if from.y == nil then
            local _, y = 0, 0
            pcall(function() _, y = ctrl:GetAnchoredPosition() end)
            start.y = y
        else
            start.y = from.y
        end
    end
    if to.w ~= nil then
        if from.w == nil then
            local w = 1
            pcall(function() w = ctrl:GetSizeDelta() end)
            start.w = w
        else
            start.w = from.w
        end
    end
    if to.h ~= nil then
        if from.h == nil then
            local _, h = 1, 1
            pcall(function() _, h = ctrl:GetSizeDelta() end)
            start.h = h
        else
            start.h = from.h
        end
    end
    if to.a ~= nil then start.a = from.a or 0 end
    if to.hex ~= nil then start.hex = from.hex or to.hex end

    local tw = { ctrl = ctrl, t = 0, dur = dur, from = start, to = to,
                 ease = resolve(ease), onDone = onDone, done = false }
    state.fxTweens[#state.fxTweens + 1] = tw
    return tw
end

-- 把一组键直接写到控件上（补间终点 / 立即生效用）
function M.applyKeys(ctrl, to)
    if not ctrl or type(to) ~= "table" then return end
    if to.x ~= nil or to.y ~= nil then
        local x, y = 0, 0
        pcall(function() x, y = ctrl:GetAnchoredPosition() end)
        utils.setPos(ctrl, to.x ~= nil and to.x or x, to.y ~= nil and to.y or y)
    end
    if to.w ~= nil or to.h ~= nil then
        local w, h = 1, 1
        pcall(function() w, h = ctrl:GetSizeDelta() end)
        utils.setSize(ctrl, to.w ~= nil and to.w or w, to.h ~= nil and to.h or h)
    end
    if to.a ~= nil or to.hex ~= nil then
        utils.setAlpha(ctrl, to.hex or "FFFFFF", to.a or 255)
    end
end

-- ================================================================
-- ★ 取消某控件上的全部补间（面板重开时避免旧补间把控件拽回去）
-- ================================================================
function M.cancel(ctrl)
    local list = state.fxTweens
    for i = #list, 1, -1 do
        if list[i].ctrl == ctrl then
            list[i].done = true
            table.remove(list, i)
        end
    end
end

function M.cancelAll()
    state.fxTweens = {}
end

local function updateTweens(dt)
    local list = state.fxTweens
    for i = #list, 1, -1 do
        local tw = list[i]
        if tw.done then
            table.remove(list, i)
        else
            tw.t = tw.t + dt
            local k = tw.t / tw.dur
            if k > 1 then k = 1 end
            local e = tw.ease(k)
            local from, to = tw.from, tw.to
            local c = tw.ctrl
            if to.x ~= nil or to.y ~= nil then
                local x, y = 0, 0
                pcall(function() x, y = c:GetAnchoredPosition() end)
                local fx = from.x or x
                local fy = from.y or y
                utils.setPos(c,
                    to.x ~= nil and (fx + (to.x - fx) * e) or x,
                    to.y ~= nil and (fy + (to.y - fy) * e) or y)
            end
            if to.w ~= nil or to.h ~= nil then
                local w, h = 1, 1
                pcall(function() w, h = c:GetSizeDelta() end)
                local fw = from.w or w
                local fh = from.h or h
                utils.setSize(c,
                    to.w ~= nil and (fw + (to.w - fw) * e) or w,
                    to.h ~= nil and (fh + (to.h - fh) * e) or h)
            end
            if to.a ~= nil then
                local fa = from.a or 0
                utils.setAlpha(c, to.hex or from.hex or "FFFFFF", fa + ((to.a - fa) * e))
            end
            if k >= 1 then
                tw.done = true
                table.remove(list, i)
                if tw.onDone then pcall(tw.onDone) end
            end
        end
    end
end

-- ================================================================
-- ★ 周期动效小工具：呼吸不透明度（每帧调用）
-- ================================================================
function M.breath(ctrl, hex, base, amp, speed)
    if not ctrl then return end
    local a = base + amp * (0.5 + 0.5 * math.sin(state.fxTime * (speed or 3.2)))
    utils.setAlpha(ctrl, hexOf(hex, hex), a)
end

-- ================================================================
-- ★ 每帧总入口
-- ================================================================
function M.update(dt)
    dt = tonumber(dt) or 0
    if dt <= 0 then return end
    if dt > 0.05 then dt = 0.05 end
    state.fxTime = (state.fxTime or 0) + dt
    updateTweens(dt)
    updateParticles(dt)
end

-- ================================================================
-- ★ 全部粒子立即回收（切屏 / 关面板时调用）
-- ================================================================
function M.clear()
    for i = 1, #state.fxNodes do
        local st = state.fxStates[i]
        if st then st.active = false end
        utils.setVisible(state.fxNodes[i], false)
    end
end

return M
