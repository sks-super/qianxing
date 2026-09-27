-- ================================================================
-- 浮岛借木 · 客户端信号模块
--   出站：向服务器发送「客户端事件」，参数为事件名字符串
--         （如：撞断树木 / 推起木桩 / 铺好桥 / 到达终点 / 重置关卡 等）。
--   入站：监听服务器下发的信号（如「进入关卡」，参数为整数关卡序号）。
-- ================================================================

---@diagnostic disable: undefined-global

local M = {}

-- 客户端事件信号名（与服务器约定）
M.SIGNAL_NAME = "客户端事件"

-- ================================================================
-- ★ 出站：发送一个客户端事件
--   eventName : 事件名字符串
--   signalName: 可选，覆盖默认信号名
-- ================================================================
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

-- ================================================================
-- ★ 出站：通关上报（关卡序号 + 已走步数）
-- ================================================================
function M.sendLevelWin(levelIndex, steps)
    local ok = pcall(function()
        local sig = game.ServerSignal("关卡胜利")
        if not sig then return end
        sig:AddInt(math.floor(tonumber(levelIndex) or 0))
        sig:AddInt(math.floor(tonumber(steps) or 0))
        sig:SendSignal()
    end)
    return ok
end

-- ================================================================
-- ★ 入站：注册服务器信号监听
--   name   : 信号名（如 "进入关卡"）
--   handler: 回调，签名 (signalName, signalParams)
-- ================================================================
function M.register(name, handler)
    if not name or type(handler) ~= "function" then return false end
    local ok = pcall(function()
        script:RegisterServerSignalHandler(name, handler)
    end)
    return ok == true
end

-- ================================================================
-- ★ 入站参数提取：第 index 个整数
--   兼容：整包即数字 / 数组 [index] / 数字字符串 / 包裹 userdata
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

-- ================================================================
-- ★ 入站参数提取：第 index 个字符串
-- ================================================================
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
