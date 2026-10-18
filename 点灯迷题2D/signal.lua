-- ================================================================
-- 点灯迷题 2D · 可选的服务端对接
-- ================================================================
-- ★ 本作是纯客户端 2D，**默认不依赖任何节点图**（DEFAULT_SIGNAL_ENABLED = 0）。
--   下面这层只在你想「跨设备保留通关进度 / 上报战绩」时才有用。
--
--   进度编码：一条 50 字符的字符串，第 i 位 = 第 i 关的星数（'0' 未通关）。
--   服务端要做的只有两件事：
--     ① 全局自定义变量 `点灯迷题进度`（字符串）存这条串；
--     ② 收到信号 `保存点灯进度`（1 个字符串 = 新的进度串）时，写回该变量。
--   ★ 客户端不能写服务器变量，只能「读」+「发信号请服务器写」。
-- ================================================================

---@diagnostic disable: undefined-global

local M = {}

local state = require("default_import_file/state")
local config = require("default_import_file/config")

function M.enabled()
    return (config.DEFAULT_SIGNAL_ENABLED or 0) ~= 0
end

-- 变量挂在玩家 / 化身 / 关卡上都行，按顺序试
local function entityTypes()
    local out = {}
    local ok, E = pcall(function() return Enum.CustomVariableEntityType end)
    if ok and E then
        if E.PlayerSelf then out[#out + 1] = E.PlayerSelf end
        if E.AvatarSelf then out[#out + 1] = E.AvatarSelf end
        if E.Level then out[#out + 1] = E.Level end
    end
    return out
end

local function unwrap(raw)
    if raw == nil then return nil end
    if type(raw) == "string" or type(raw) == "number" then return raw end
    local v
    pcall(function()
        if raw.GetString then v = raw:GetString()
        elseif raw.GetValue then v = raw:GetValue() end
    end)
    return v
end

-- ================================================================
-- ★ 读出进度串（读不到返回 nil）
-- ================================================================
function M.readProgressString()
    if not M.enabled() then return nil end
    local varName = config.DEFAULT_SIGNAL_VAR
    if type(varName) ~= "string" or varName == "" then return nil end
    local list = entityTypes()
    for i = 1, #list do
        local got = nil
        pcall(function()
            got = unwrap(game.GetGlobalCustomVariableValue(list[i], varName))
        end)
        if got ~= nil and tostring(got) ~= "" then
            return tostring(got)
        end
    end
    return nil
end

-- ================================================================
-- ★ 把进度串解析成 cleared 表
-- ================================================================
function M.parseProgress(str)
    local out = {}
    if type(str) ~= "string" then return out end
    local n = config.levelCount()
    for i = 1, n do
        local ch = str:sub(i, i)
        local v = tonumber(ch)
        if v and v > 0 then
            out[i] = { stars = math.min(3, v), steps = 0 }
        end
    end
    return out
end

-- ================================================================
-- ★ 把 cleared 表编码成进度串
-- ================================================================
function M.encodeProgress(cleared)
    local n = config.levelCount()
    local buf = {}
    for i = 1, n do
        local rec = cleared and cleared[i]
        local s = 0
        if rec and rec.stars then s = math.max(0, math.min(3, rec.stars)) end
        buf[i] = tostring(s)
    end
    return table.concat(buf)
end

-- ================================================================
-- ★ 上报通关（节点图收到后写变量；没接也无害）
-- ================================================================
function M.reportWin(index, moves)
    if not M.enabled() then return false end
    local name = config.DEFAULT_SIGNAL_WIN
    if type(name) ~= "string" or name == "" then return false end
    local payload = M.encodeProgress(state.cleared)
    local ok = pcall(function()
        local sig = game.ServerSignal(name)
        if not sig then return end
        sig:AddInt(math.floor(index or 0))
        sig:AddInt(math.floor(moves or 0))
        sig:AddString(payload)
        sig:SendSignal()
    end)
    return ok == true
end

-- ================================================================
-- 入站监听（预留：服务端可回推进度串）
-- ================================================================
function M.register(name, handler)
    if not name or type(handler) ~= "function" then return false end
    local ok = pcall(function()
        script:RegisterServerSignalHandler(name, handler)
    end)
    return ok == true
end

return M
