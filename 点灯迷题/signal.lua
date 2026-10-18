-- ================================================================
-- 点灯迷题 客户端信号模块
-- ================================================================
-- ★ 分工：客户端只做 UI（选关 / 教程 / HUD / 结算），3D 棋盘与玩法在服务器节点图里。
--   本模块是两边唯一的对接面，共 4 条信号：
--
--   【出站 · 客户端 → 服务器】
--     ①「进入关卡」 参数：AddInt 关卡号(1 起始) + AddIntList 点位序列(0 基下标数组)
--        —— 玩家在选关界面点了某一关时发出，节点图据此摆出初始盘面。
--     ②「重玩本关」 参数：AddInt 关卡号 + AddIntList 点位序列
--        —— 玩家在胜利结算面板点「重玩本关」时发出，节点图重置该关棋盘。
--        （与 ① 参数完全一致，节点图可复用同一处理逻辑；若只需关卡号，忽略第 2 个参数即可）
--
--   【入站 · 服务器 → 客户端】
--     ③「让客户端进入关卡」 参数：AddInt 关卡号（可选）
--        —— 节点图把 3D 场景摆好、可以开始操作了，通知客户端切到游玩 HUD。
--     ④「关卡胜利」       参数：AddInt 关卡号（可选）
--        —— 3D 端判定全部灯熄灭，客户端弹出胜利结算（带基础图元动效）。
-- ================================================================

---@diagnostic disable: undefined-global

local M = {}
local config = require("default_import_file/config")

-- ================================================================
-- ★ 信号名常量（与服务器节点图约定；改这里即可整体改名）
-- ================================================================
M.SIGNAL_ENTER_LEVEL   = "进入关卡"          -- 出站：请求进入某关
M.SIGNAL_REPLAY_LEVEL  = "重玩本关"          -- 出站：请求重置当前关
M.SIGNAL_SERVER_ENTER  = "让客户端进入关卡"   -- 入站：可以开始游玩了
M.SIGNAL_SERVER_WIN    = "关卡胜利"          -- 入站：本关通关

-- ================================================================
-- ★ 出站：请求进入关卡
--   levelIndex : 关卡号（1 起始）
--   flips      : 点位序列（0 基下标整数数组；省略则自动从 config 取）
--   返回是否发送成功
-- ================================================================
function M.sendEnterLevel(levelIndex, flips)
    local idx = math.floor(tonumber(levelIndex) or 0)
    if idx < 1 then return false end
    local list = flips
    if type(list) ~= "table" then
        list = config.getLevelFlips(idx)
    end
    local ok, sent = pcall(function()
        local sig = game.ServerSignal(M.SIGNAL_ENTER_LEVEL)
        if not sig then return false end
        sig:AddInt(idx)
        sig:AddIntList(list)
        sig:SendSignal()
        return true
    end)
    return ok == true and sent == true
end

-- ================================================================
-- ★ 出站：请求重玩本关（参数与「进入关卡」一致，便于节点图复用）
-- ================================================================
function M.sendReplayLevel(levelIndex, flips)
    local idx = math.floor(tonumber(levelIndex) or 0)
    if idx < 1 then return false end
    local list = flips
    if type(list) ~= "table" then
        list = config.getLevelFlips(idx)
    end
    local ok, sent = pcall(function()
        local sig = game.ServerSignal(M.SIGNAL_REPLAY_LEVEL)
        if not sig then return false end
        sig:AddInt(idx)
        sig:AddIntList(list)
        sig:SendSignal()
        return true
    end)
    return ok == true and sent == true
end

-- ================================================================
-- ★ 出站：通用（纯字符串事件，留给日后扩展；当前未使用）
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
-- ★ 入站：注册服务器信号监听
--   name    : 信号名（如 M.SIGNAL_SERVER_WIN）
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
-- ★ 入站参数提取：第 index 个整数列表
--   兼容：Lua 数组 / 带 Count+Get 的 userdata / GetIntList 的 userdata
--   ★ 客户端通常不需要它（点位序列本地 config 就有），保留以备节点图回传。
-- ================================================================
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
