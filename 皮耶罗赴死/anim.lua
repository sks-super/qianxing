-- ================================================================
-- 皮耶罗：赴死 · 逐帧补间引擎
--   全工程动效（结算漫画、伤害数字、面板滑入、淡入淡出）都走这里，
--   不用引擎自带 Tween —— 真机与模拟器行为一致，也方便用 isBusy 锁输入。
-- ================================================================

---@diagnostic disable: undefined-global

local M = {}

local E = {}

function E.linear(t) return t end
function E.inQuad(t) return t * t end
function E.outQuad(t) return 1 - (1 - t) * (1 - t) end
function E.inOutQuad(t)
    if t < 0.5 then return 2 * t * t end
    return 1 - 2 * (1 - t) * (1 - t)
end
function E.inCubic(t) return t * t * t end
function E.outCubic(t) local u = 1 - t; return 1 - u * u * u end
function E.inOutCubic(t)
    if t < 0.5 then return 4 * t * t * t end
    local u = 1 - t; return 1 - 4 * u * u * u
end

function E.outBack(t)
    local c1 = 1.70158
    local c3 = c1 + 1
    local u = t - 1
    return 1 + c3 * u * u * u + c1 * u * u
end

function E.outElastic(t)
    if t <= 0 then return 0 end
    if t >= 1 then return 1 end
    local c4 = (2 * math.pi) / 3
    return (2 ^ (-10 * t)) * math.sin((t * 10 - 0.75) * c4) + 1
end

function E.pulse(t)
    if t < 0.5 then return E.outQuad(t / 0.5) end
    return E.outQuad((1 - t) / 0.5)
end

M.Ease = E

-- ================================================================
-- 活动补间
-- ================================================================
local items = {}
local nextId = 1

function M.tween(dur, onUpdate, opts)
    opts = opts or {}
    local ease = opts.ease
    if type(ease) == "string" then ease = E[ease] end
    if type(ease) ~= "function" then ease = E.linear end

    local it = {
        id = nextId,
        t = 0,
        dur = math.max(0, tonumber(dur) or 0),
        delay = math.max(0, tonumber(opts.delay) or 0),
        ease = ease,
        onUpdate = onUpdate,
        onDone = opts.onDone,
        tag = opts.tag,
        from = opts.from,
        to = opts.to,
        dead = false,
    }
    nextId = nextId + 1
    items[#items + 1] = it
    return it
end

function M.value(from, to, dur, fn, opts)
    opts = opts or {}
    opts.from = from
    opts.to = to
    return M.tween(dur, fn, opts)
end

function M.delay(sec, fn, tag)
    return M.tween(sec, nil, { tag = tag, onDone = fn })
end

function M.kill(item)
    if item then item.dead = true end
end

function M.clear(tag)
    if tag == nil then
        items = {}
        return
    end
    for i = 1, #items do
        if items[i].tag == tag then items[i].dead = true end
    end
end

function M.clearAll()
    items = {}
end

function M.isBusy(tag)
    for i = 1, #items do
        local it = items[i]
        if not it.dead and (tag == nil or it.tag == tag) then return true end
    end
    return false
end

local function step(it, dt)
    if it.delay > 0 then
        it.delay = it.delay - dt
        if it.delay > 0 then return false end
        dt = -it.delay
        it.delay = 0
    end
    it.t = it.t + dt
    local raw = (it.dur > 0) and (it.t / it.dur) or 1
    local done = raw >= 1
    if done then raw = 1 end
    local p = it.ease(raw)
    if it.onUpdate then
        local ok, err = pcall(function()
            if it.from ~= nil and it.to ~= nil then
                it.onUpdate(it.from + (it.to - it.from) * p, raw)
            else
                it.onUpdate(p, raw)
            end
        end)
        if not ok then
            it.dead = true
            M.lastError = tostring(err)
            M.errorCount = (M.errorCount or 0) + 1
            if printerr and M.errorCount <= 5 then
                printerr("[anim] 补间回调出错(已丢弃该补间): " .. tostring(err))
            end
        end
    end
    if done and not it.dead then
        it.dead = true
        if it.onDone then
            local ok, err = pcall(it.onDone)
            if not ok then
                M.lastError = tostring(err)
                M.errorCount = (M.errorCount or 0) + 1
                if printerr and M.errorCount <= 5 then
                    printerr("[anim] 补间结束回调出错: " .. tostring(err))
                end
            end
        end
    end
    return it.dead
end

-- ★★ 不要写成 items = keep：step() 里可能新建补间（链式），
--    整体覆盖会把本帧新建的补间丢掉（表现为「第一段能动、后面全不动」且不报错）。
function M.update(dt)
    if not dt or dt <= 0 then return end
    if #items == 0 then return end

    local n = #items
    for i = 1, n do
        local it = items[i]
        if not it.dead then step(it, dt) end
    end

    local w = 0
    for i = 1, #items do
        local it = items[i]
        if not it.dead then
            w = w + 1
            items[w] = it
        end
    end
    for i = #items, w + 1, -1 do items[i] = nil end
end

return M
