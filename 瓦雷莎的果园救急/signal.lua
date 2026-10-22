-- ================================================================
-- 瓦雷莎的果园救急 · 信号模块（客户端 ↔ 节点图 唯一对接面）
-- ================================================================
-- ★ 分工：客户端只做 UI（果园地图 / 教程 / HUD / 结算），
--   3D 果园棋盘、点击判定、是否全部还原，全部在服务器节点图里。
--
-- ★★ 协议（名字、顺序、类型都必须逐字一致，改名前先改这里）
--
--   【服客 · 服务器 → 客户端】
--     ①「服客进入关卡」   关卡序号 : 整数（第一关 = 1）
--        —— 节点图把这一片果园摆好了，客户端清掉「正在摆果园…」并进游玩态。
--     ②「服客关卡胜利」   关卡序号 : 整数（第一关 = 1）
--        —— 3D 端判定全部还原；客户端记进度并播胜利结算。
--     ③「服客进入选关」   （无参数）
--        —— 节点图要求客户端回果园地图（例如玩家中途退出 / 服务器重开）。
--     ④「服客同步存档信息」 已通关的最新关卡序号 : 整数（1 基；0 = 一片都没通关）
--        —— 存档（进度 / 星级）只记在服务器上。客户端收到后**覆盖本地进度**：
--           「已通关最新关卡 = N」⇒ 第 1..N 片全部通关（红苹果 + 三颗亮星），
--          解锁上限 = N + DEFAULT_MAP_LOCK_AHEAD（所以 N=0 时仍只有第 1 片可进），
--           选关光标自动对齐到「刚解锁的那一片」。
--           ★ 只带一个整数：通关是一条直线（想进第 2 片必须先通关第 1 片），
--             所以「已通关到第几片」这一个数就足以还原整份进度，不必再传列表。
--           ★ 进游戏后节点图应先发这一条，再发「服客进入关卡」。
--
--   【客服 · 客户端 → 服务器】
--     ⑤「客服关卡参数」   关卡序号 : 整数（第一关 = 1）
--                        最小步数 : 整数（= 该关解的步数，也是难度标签）
--                        点位序列 : 整数列表
--                        状态数组 : 整数列表（30 项）
--        —— 玩家在选关页进入关卡 / 进下一关 / 回上一关 / 重玩 后触发。
--        ★ 教程关（前 5 关，本局还没看过本课）会**延迟**到玩家关掉教程、
--          真正露出游玩界面之后才发（game.lua 的 pendingLevelParams →
--          flushLevelParams）。对节点图无影响，只是这条请求晚到。
--        点位序列每项是 0 基一维下标：idx = 行 * 6 + 列
--        （例：第 0 行第 0 列 = 0；第 1 行第 1 列 = 1*6+1 = 7）。
--        状态数组记录**初始游玩棋盘**全部 30 格的状态，列表序号 0..29 即
--        idx（行 * 6 + 列），内容 1 = 水果、-1 = 果汁。
--        —— 节点图可以直接照状态数组摆盘（不必自己反推）；点位序列仍然要给，
--           它是这一关的解法（= 最小步数的答案）。
--
--   ★ 入站参数都做了兼容解析：不给 / 给错类型 / 用字符串传数字都不会报错。
-- ================================================================

---@diagnostic disable: undefined-global

local M = {}
local config = require("default_import_file/config")
local puzzle = require("default_import_file/puzzle")

-- ================================================================
-- ★ 信号名常量（与节点图约定；改名只动这里）
--   S2C = 服客（服务器 → 客户端）   C2S = 客服（客户端 → 服务器）
-- ================================================================
M.SIGNAL_S2C_ENTER  = "服客进入关卡"
M.SIGNAL_S2C_WIN    = "服客关卡胜利"
M.SIGNAL_S2C_SELECT = "服客进入选关"
M.SIGNAL_S2C_SAVE   = "服客同步存档信息"
M.SIGNAL_C2S_LEVEL  = "客服关卡参数"

-- 旧名保留（只作为别名，避免旧调用点漏改时静默失败）
M.SIGNAL_ENTER_LEVEL  = M.SIGNAL_C2S_LEVEL
M.SIGNAL_REPLAY_LEVEL = M.SIGNAL_C2S_LEVEL
M.SIGNAL_SERVER_ENTER = M.SIGNAL_S2C_ENTER
M.SIGNAL_SERVER_WIN   = M.SIGNAL_S2C_WIN
M.SIGNAL_SERVER_SELECT = M.SIGNAL_S2C_SELECT
M.SIGNAL_SERVER_SAVE   = M.SIGNAL_S2C_SAVE

-- ================================================================
-- ★ 出站：「客服关卡参数」
--   levelIndex 缺省时用 config 里的当前关；flips/states 一律从 config 取，
--   保证「客户端算的盘面」和「发给服务器的盘面」是同一份数据。
-- ================================================================
-- 这几个入口语义不同，但**报文完全一致**（服务端只认参数，不认来路）：
--   进入关卡 / 下一关 / 上一关 / 重玩
--
--   ★ 报文（顺序不能变）：
--     ① 关卡序号 : int      1 基（第一关 = 1）
--     ② 最小步数 : int
--     ③ 点位序列 : intList  0 基，idx = 行 * 6 + 列（这一关的解法）
--     ④ 状态数组 : intList  30 项，1 = 水果 / -1 = 果汁（初始盘面）
-- ================================================================
function M.sendLevelParams(levelIndex)
    local idx = math.floor(tonumber(levelIndex) or 0)
    if idx < 1 then return false end
    if not config.getLevelConfig(idx) then return false end
    local steps = math.floor(tonumber(config.getLevelSteps(idx)) or 0)
    local flips = config.getLevelFlips(idx)
    local states = puzzle.initStatesFromFlips(flips)
    local ok, sent = pcall(function()
        local sig = game.ServerSignal(M.SIGNAL_C2S_LEVEL)
        if not sig then return false end
        sig:AddInt(idx)           -- ① 关卡序号（1 基）
        sig:AddInt(steps)         -- ② 最小步数
        sig:AddIntList(flips)     -- ③ 点位序列（0 基，idx = 行*6 + 列）
        sig:AddIntList(states)    -- ④ 状态数组（30 项，1 = 水果 / -1 = 果汁）
        sig:SendSignal()
        return true
    end)
    return ok == true and sent == true
end

-- 语义别名：四个触发点都发同一条信号
M.sendEnterLevel = M.sendLevelParams
M.sendReplayLevel = M.sendLevelParams
M.sendNextLevel = M.sendLevelParams
M.sendPrevLevel = M.sendLevelParams

-- ================================================================
-- ★ 出站：通用（纯字符串，留给日后扩展）
-- ================================================================
function M.send(eventName, signalName)
    if not eventName then return false end
    local ok = pcall(function()
        local sig = game.ServerSignal(signalName or eventName)
        if not sig then return end
        sig:AddString(tostring(eventName))
        sig:SendSignal()
    end)
    return ok == true
end

-- ================================================================
-- ★ 入站：注册监听
-- ================================================================
function M.register(name, handler)
    if not name or type(handler) ~= "function" then return false end
    local ok = pcall(function()
        script:RegisterServerSignalHandler(name, handler)
    end)
    return ok == true
end

-- ================================================================
-- ★ 参数解析（兼容 整包标量 / 数组 / 数字字符串 / userdata）
-- ================================================================
function M.getIntParam(params, index)
    if params == nil then return nil end
    local candidate
    if type(params) == "table" then
        candidate = params[index] or params[tostring(index)]
    else
        candidate = params
    end
    if candidate == nil then return nil end
    if type(candidate) == "number" then return math.floor(candidate) end
    if type(candidate) == "string" then
        local n = tonumber(candidate)
        if n then return math.floor(n) end
        return nil
    end
    if type(candidate) == "userdata" then
        local ok, v = pcall(function()
            if candidate.GetInt then return candidate:GetInt() end
            if candidate.GetNumber then return candidate:GetNumber() end
            return nil
        end)
        if ok and type(v) == "number" then return math.floor(v) end
    end
    return nil
end

function M.getIntListParam(params, index)
    local out = {}
    if params == nil then return out end
    local candidate
    if type(params) == "table" then
        candidate = params[index] or params[tostring(index)]
    else
        candidate = params
    end
    if candidate == nil then return out end
    if type(candidate) == "table" then
        for i = 1, #candidate do
            local v = tonumber(candidate[i])
            if v then out[#out + 1] = math.floor(v) end
        end
        return out
    end
    if type(candidate) == "userdata" then
        pcall(function()
            if candidate.GetIntList then
                local lst = candidate:GetIntList()
                if type(lst) == "table" then
                    for i = 1, #lst do out[#out + 1] = math.floor(tonumber(lst[i]) or 0) end
                    return
                end
            end
            local n = candidate.Count
            if type(n) == "number" and candidate.Get then
                for i = 1, n do
                    out[#out + 1] = math.floor(tonumber(candidate:Get(i)) or 0)
                end
            end
        end)
    end
    return out
end

function M.getStringParam(params, index)
    if params == nil then return nil end
    local candidate
    if type(params) == "table" then
        candidate = params[index] or params[tostring(index)]
    else
        candidate = params
    end
    if candidate == nil then return nil end
    if type(candidate) == "string" then return candidate end
    if type(candidate) == "number" then return tostring(candidate) end
    if type(candidate) == "userdata" then
        local ok, v = pcall(function()
            if candidate.GetString then return candidate:GetString() end
            if candidate.ToString then return candidate:ToString() end
            return nil
        end)
        if ok and type(v) == "string" then return v end
    end
    return tostring(candidate)
end

return M
