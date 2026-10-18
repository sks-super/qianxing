-- ================================================================
-- 2048 · 信号模块（与服务端的唯一通道）
--
--   出站：game.ServerSignal(名字) → AddInt/AddString → SendSignal()
--         · "客户端事件"      ：玩法事件（开始 / 胜利 / 失败 / 撤销 …）
--         · config.DEFAULT_HIGHSCORE_SIGNAL（默认「保存最高分」）
--                             ：请服务器把新纪录写进全局自定义变量
--
--   入站：script:RegisterServerSignalHandler(名字, 回调)
--         · "进入游戏"        ：服务器要求重开一局
--
--   ★ 客户端【不能写】服务器变量，只能「读」+「发信号请服务器写」。
--     所以最高分的持久化 = 读 game.GetGlobalCustomVariableValue
--                         + 破纪录时发一次整型信号。
-- ================================================================

---@diagnostic disable: undefined-global

local M = {}
local config = require("default_import_file/config")

-- 客户端事件信号名（与服务器约定）
M.SIGNAL_NAME = "客户端事件"

-- ================================================================
-- ★ 出站：发送一个客户端事件（纯事件名，不带参数）
-- ================================================================
function M.send(eventName, signalName)
    if not eventName then return false end
    local ok = pcall(function()
        local sig = game.ServerSignal(signalName or M.SIGNAL_NAME)
        if not sig then return end
        sig:AddString(tostring(eventName))
        sig:SendSignal()
    end)
    return ok == true
end

-- ================================================================
-- ★ 出站：上报最高分（整型）
--   服务器侧收到这个信号后，把参数写进 config.DEFAULT_HIGHSCORE_VAR 变量即可。
-- ================================================================
function M.sendHighScore(value)
    local v = math.floor(tonumber(value) or 0)
    if v <= 0 then return false end
    local name = config.DEFAULT_HIGHSCORE_SIGNAL or "保存最高分"
    local ok = pcall(function()
        local sig = game.ServerSignal(name)
        if not sig then return end
        sig:AddInt(v)
        sig:SendSignal()
    end)
    return ok == true
end

-- ================================================================
-- ★ 入站：注册服务器信号监听
--   name    : 信号名
--   handler : 回调，签名 (signalName, signalParams)
-- ================================================================
function M.register(name, handler)
    if not name or type(handler) ~= "function" then return false end
    local ok = pcall(function()
        script:RegisterServerSignalHandler(name, handler)
    end)
    return ok == true
end

-- ================================================================
-- 入站参数提取
--   兼容：整包即值 / 数组 [index] / 数字或字符串 / 包裹 userdata
-- ================================================================
local function pick(params, index)
    if params == nil then return nil end
    if type(params) == "table" then
        return params[index] or params[tostring(index)]
    end
    return params
end

local function unwrap(candidate)
    if candidate == nil then return nil end
    if type(candidate) == "number" or type(candidate) == "string" then return candidate end
    if type(candidate) == "userdata" or type(candidate) == "table" then
        local v
        pcall(function()
            if candidate.GetInt then v = candidate:GetInt() end
            if v == nil and candidate.GetNumber then v = candidate:GetNumber() end
            if v == nil and candidate.GetString then v = candidate:GetString() end
        end)
        if v ~= nil then return v end
    end
    return nil
end

function M.getIntParam(params, index)
    local c = unwrap(pick(params, index))
    if type(c) == "number" then return math.floor(c) end
    if type(c) == "string" then
        local n = tonumber(c)
        if n then return math.floor(n) end
    end
    return nil
end

function M.getStringParam(params, index)
    local c = unwrap(pick(params, index))
    if c == nil then return nil end
    return tostring(c)
end

-- ================================================================
-- ★ 最高分读取
--   客户端只能【读】服务器变量。依次尝试几个实体作用域，取第一个数字结果。
--   （做单人存档时用 PlayerSelf；若策划把变量挂在关卡上，Level 也能兜住。）
-- ================================================================
local function entityTypes()
    local E = Enum.CustomVariableEntityType
    local out = {}
    if E then
        if E.PlayerSelf then out[#out + 1] = E.PlayerSelf end
        if E.AvatarSelf then out[#out + 1] = E.AvatarSelf end
        if E.Level then out[#out + 1] = E.Level end
    end
    return out
end

-- 返回值：最高分（number，读不到时为 nil）
function M.readHighScore()
    if (config.DEFAULT_HIGHSCORE_SYNC or 1) == 0 then return nil end
    local varName = config.DEFAULT_HIGHSCORE_VAR
    if type(varName) ~= "string" or varName == "" then return nil end

    local best = nil
    for _, et in ipairs(entityTypes()) do
        if best == nil then
            pcall(function()
                local raw = game.GetGlobalCustomVariableValue(et, varName)
                local v = unwrap(raw)
                if type(v) == "string" then v = tonumber(v) end
                if type(v) == "number" and v > 0 then
                    best = math.floor(v)
                end
            end)
        end
    end
    return best
end

-- ================================================================
-- ★ 监听最高分变量变化（服务器写完变量后回推，界面可以跟着刷新）
--   fn(value) —— value 为读回来的新最高分（读不到就不回调）
-- ================================================================
function M.watchHighScore(fn)
    if type(fn) ~= "function" then return false end
    if (config.DEFAULT_HIGHSCORE_SYNC or 1) == 0 then return false end
    local varName = config.DEFAULT_HIGHSCORE_VAR
    if type(varName) ~= "string" or varName == "" then return false end

    local ok = false
    for _, et in ipairs(entityTypes()) do
        pcall(function()
            script:RegisterCustomVariableChangedHandler(et, varName, function()
                local v = M.readHighScore()
                if v then pcall(fn, v) end
            end)
            ok = true
        end)
        if ok then break end
    end
    return ok
end

return M
