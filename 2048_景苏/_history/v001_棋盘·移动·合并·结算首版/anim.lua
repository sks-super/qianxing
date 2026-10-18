-- ================================================================
-- 2048 · 逐帧补间引擎
--   全工程的所有动效（方块平移/缩放、分数滚动、结算面板滑入、粒子…）
--   都通过本模块驱动，不用引擎自带的 Tween —— 这样在真机与模拟器里
--   行为完全一致，也方便用「动画期间锁输入」判定 anim.isBusy()。
-- ================================================================

---@diagnostic disable: undefined-global

local M = {}

-- ================================================================
-- ★ 缓动函数（t ∈ [0,1] → 进度）
-- ================================================================
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

-- 回弹缓出：冲过终点再退回来一点点（新方块出现用它最有「弹」感）
function E.outBack(t)
    local c1 = 1.70158
    local c3 = c1 + 1
    local u = t - 1
    return 1 + c3 * u * u * u + c1 * u * u
end

-- 弹性缓出：多次小幅震荡（合并时的「碰撞感」）
function E.outElastic(t)
    if t <= 0 then return 0 end
    if t >= 1 then return 1 end
    local c4 = (2 * math.pi) / 3
    return (2 ^ (-10 * t)) * math.sin((t * 10 - 0.75) * c4) + 1
end

function E.outBounce(t)
    local n1, d1 = 7.5625, 2.75
    if t < 1 / d1 then return n1 * t * t end
    if t < 2 / d1 then
        t = t - 1.5 / d1
        return n1 * t * t + 0.75
    end
    if t < 2.5 / d1 then
        t = t - 2.25 / d1
        return n1 * t * t + 0.9375
    end
    t = t - 2.625 / d1
    return n1 * t * t + 0.984375
end

-- 脉冲：0 → 1 → 0 的一条山丘（合并弹跳、呼吸效果）
function E.pulse(t)
    if t < 0.5 then return E.outQuad(t / 0.5) end
    return E.outQuad((1 - t) / 0.5)
end

M.Ease = E

-- ================================================================
-- ★ 活动补间列表
--   item = { t, dur, delay, ease, onUpdate(p, raw), onDone, tag, dead }
-- ================================================================
local items = {}
local nextId = 1

-- 创建一条补间
--   dur     : 时长（秒），<=0 时立即完成
--   onUpdate: fun(progressEased, progressRaw)
--   opts    : { ease = 函数 或 名字, delay = 秒, tag = 字符串, onDone = 函数,
--               from = number, to = number }   ← 给了 from/to 时 onUpdate 收的是插值
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

-- 插值补间：把 from→to 按缓动喂给 fn(v)
function M.value(from, to, dur, fn, opts)
    opts = opts or {}
    opts.from = from
    opts.to = to
    return M.tween(dur, fn, opts)
end

-- 延时回调
function M.delay(sec, fn, tag)
    return M.tween(sec, nil, { tag = tag, onDone = fn })
end

function M.kill(item)
    if item then item.dead = true end
end

-- 清掉带某 tag 的全部补间（用于「重开一局」时打扫战场）
function M.clear(tag)
    if tag == nil then
        items = {}
        return
    end
    for _, it in ipairs(items) do
        if it.tag == tag then it.dead = true end
    end
end

function M.clearAll()
    items = {}
end

-- 是否还有补间在跑（锁输入判定用）
function M.isBusy(tag)
    for _, it in ipairs(items) do
        if not it.dead and (tag == nil or it.tag == tag) then return true end
    end
    return false
end

-- 单条补间推进；返回 true 表示本条已经结束（调用方回收）
-- ★ 注意：这里刻意不用 goto（部分 Lua 运行时是 5.1/LuaJIT，不支持 goto 语句）
local function step(it, dt)
    if it.delay > 0 then
        it.delay = it.delay - dt
        if it.delay > 0 then return false end
        dt = -it.delay          -- 把多出来的时间补进本次推进
        it.delay = 0
    end
    it.t = it.t + dt
    local raw = (it.dur > 0) and (it.t / it.dur) or 1
    local done = raw >= 1
    if done then raw = 1 end
    local p = it.ease(raw)
    if it.onUpdate then
        local ok = pcall(function()
            if it.from ~= nil and it.to ~= nil then
                it.onUpdate(it.from + (it.to - it.from) * p, raw)
            else
                it.onUpdate(p, raw)
            end
        end)
        if not ok then it.dead = true end
    end
    if done and not it.dead then
        it.dead = true
        if it.onDone then pcall(it.onDone) end
    end
    return it.dead
end

-- 每帧推进（由 game.OnUpdate 调用）
function M.update(dt)
    if not dt or dt <= 0 then return end
    if #items == 0 then return end
    local keep = {}
    for i = 1, #items do
        local it = items[i]
        if not it.dead then
            step(it, dt)
            if not it.dead then keep[#keep + 1] = it end
        end
    end
    items = keep
end

return M
