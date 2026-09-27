-- ================================================================
-- TickHop 时间系统（玩法内核）
--   倒计时从 limit 递减到 0；显示为「秒.百分秒」（如 9.01）。
--   ★ tick 定义：math.floor(now)，即显示值的整数部分。
--     平台绑定秒数 tick 与当前 tick 相等时，该平台为实体。
--   支持：加时（add）、方向反转（reverse）、暂停（setRunning）。
-- ================================================================

---@diagnostic disable: undefined-global

local M = {}
local state = require("state")
local config = require("config")

-- ================================================================
-- 运行时状态
-- ================================================================
M.now = 0             -- 当前剩余时间（秒，浮点）
M.limit = 0           -- 本关初始时间（也是反转时的上限）
M.direction = -1      -- -1=递减（常规） / +1=递增（反转后）
M.running = false     -- 计时是否推进
M.expired = false     -- 时间是否已耗尽（递减到 0）
M.tick = 0            -- 当前秒数（floor(now)），平台实体判定依据
M.justFlippedTick = false  -- 本次 update 内 tick 是否发生变化

-- ================================================================
-- ★ 重置：关卡加载时调用
--   limit     : 初始时间（秒）
--   direction : 可选，缺省 config.DEFAULT_TIME_DIRECTION（-1 递减）
-- ================================================================
function M.reset(limit, direction)
    local v = tonumber(limit) or config.DEFAULT_TIME_LIMIT or 10.0
    if v < 0 then v = 0 end
    M.limit = v
    M.now = v
    M.direction = tonumber(direction) or config.DEFAULT_TIME_DIRECTION or -1
    if M.direction ~= 1 then M.direction = -1 end
    M.running = true
    M.expired = (v <= 0)
    M.tick = math.floor(M.now + (config.DEFAULT_TIME_TICK_EPSILON or 0))
    M.justFlippedTick = false
    M.syncState()
end

-- ================================================================
-- ★ 每帧推进
--   返回：本帧 tick 是否发生变化（变化则平台需要刷新实体状态）
-- ================================================================
function M.update(dt)
    M.justFlippedTick = false
    if not M.running or M.expired then return false end
    if not dt or dt <= 0 then return false end

    local prevTick = M.tick

    M.now = M.now + M.direction * dt

    -- 递减到 0：停住并标记耗尽
    if M.direction < 0 and M.now <= 0 then
        M.now = 0
        M.expired = true
        M.running = false
    end

    -- 递增到上限：停住（反转不能超过本关初始时间）
    if M.direction > 0 and M.now >= M.limit then
        M.now = M.limit
    end

    M.tick = math.floor(M.now + (config.DEFAULT_TIME_TICK_EPSILON or 0))
    M.syncState()

    if M.tick ~= prevTick then
        M.justFlippedTick = true
        return true
    end
    return false
end

-- ================================================================
-- ★ 加时：剩余时间增加 seconds（受 [0, limit] 夹取）
--   若此前已耗尽，加时后重新启动计时，让「濒死加时」成立。
-- ================================================================
function M.add(seconds)
    local v = tonumber(seconds) or 0
    if v <= 0 then return end
    M.now = M.now + v
    if M.now > M.limit then M.now = M.limit end
    if M.now < 0 then M.now = 0 end
    if M.expired and M.now > 0 then
        M.expired = false
        M.running = true
    end
    M.tick = math.floor(M.now + (config.DEFAULT_TIME_TICK_EPSILON or 0))
    M.syncState()
end

-- ================================================================
-- ★ 时间反转：翻转流向（递减 ⇄ 递增）
-- ================================================================
function M.reverse()
    M.direction = -M.direction
    if M.direction ~= 1 then M.direction = -1 end
    -- 反转回递减且当前为 0 时视为已耗尽
    if M.direction < 0 and M.now <= 0 then
        M.expired = true
        M.running = false
    end
    M.syncState()
end

-- ================================================================
-- ★ 暂停 / 恢复计时
-- ================================================================
function M.setRunning(running)
    M.running = running and true or false
    M.syncState()
end

-- ================================================================
-- ★ 只读查询
-- ================================================================
function M.getNow()       return M.now end
function M.getTick()      return M.tick end
function M.getDirection() return M.direction end
function M.isExpired()    return M.expired end
function M.isRunning()    return M.running end

-- ================================================================
-- ★ 把时间快照写入 state（供其它模块只读使用）
-- ================================================================
function M.syncState()
    state.timeNow = M.now
    state.timeLimit = M.limit
    state.timeDirection = M.direction
    state.timeTick = M.tick
    state.timeRunning = M.running
end

return M
