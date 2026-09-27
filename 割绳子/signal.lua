-- ================================================================
-- 客户端事件信号模块
--   在关键玩法事件发生时，向服务器发送信号，信号名为“客户端事件”，
--   参数为事件名字符串（如：切断绳子 / 戳破泡泡 / 选择关卡 / 进入下一关 /
--   重置关卡 / 进入上一关 / 游戏失败 等）。
--   另支持“关卡胜利”信号：参数为两个整数（关卡序号、本关收集星星数）。
-- ================================================================

---@diagnostic disable: undefined-global

local M = {}

-- 信号名（与服务器约定）
M.SIGNAL_NAME = "客户端事件"

-- 发送一个客户端事件信号
--   eventName:  字符串，事件名
--   signalName: 可选字符串，信号名；缺省用 M.SIGNAL_NAME（"客户端事件"）
function M.send(eventName, signalName)
    if not eventName then return false end
    local ok = pcall(function()
        local sig = game.ServerSignal(signalName or M.SIGNAL_NAME)
        if not sig then return end
        sig:AddString(tostring(eventName))
        sig:SendSignal()
    end)
    return ok
end

-- 发送关卡胜利信号："关卡胜利" + 两个整数参数（关卡序号、本关收集星星数）
--   levelIndex: 关卡序号；starCount: 收集到的星星数量
function M.sendLevelWin(levelIndex, starCount)
    local ok = pcall(function()
        local sig = game.ServerSignal("关卡胜利")
        if not sig then return end
        sig:AddInt(math.floor(tonumber(levelIndex) or 0))
        sig:AddInt(math.floor(tonumber(starCount) or 0))
        sig:SendSignal()
    end)
    return ok
end

-- ================================================================
-- ★ 入站信号：监听服务器→客户端事件
-- ================================================================

-- 注册服务器信号监听
--   name:    信号名（与服务器约定，如 "进入关卡"）
--   handler: 回调，签名 (signalName, signalParams)，signalParams 为参数数组 any[]
--   返回 true 表示注册成功
function M.register(name, handler)
    if not name or type(handler) ~= "function" then return false end
    local ok = pcall(function()
        script:RegisterServerSignalHandler(name, handler)
    end)
    return ok == true
end

-- 从信号参数数组中取出第 index 个整数
--   兼容：整包即为数字 / 数组 {[1]=n} / 数字字符串 / 包裹 userdata（GetInt / GetNumber）
--   取不到返回 nil
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

-- 从信号参数数组中取出第 index 个字符串参数
--   兼容：整包即为字符串 / 数组 {[1]=s} / 数字（转字符串）/ 包裹 userdata（GetString / ToString）
--   取不到返回 nil
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
