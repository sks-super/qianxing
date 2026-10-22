-- ================================================================
-- 绘卷修复师 · 服务器信号
-- ================================================================
--  ★ 客户端 API 里没有「退出游戏 / 结算 / 成就」这类函数（只有 ServerSignal），
--    所以这些能力都由**服务器脚本**落地，客户端只负责收发信号：
--
--    客服存档信息   客户端 → 服务器   参数：bool 列表（7 大关 × 4 块 = 28 个，
--                                     true = 该小块已通关）
--    服客存档信息   服务器 → 客户端   同上；进游戏时由服务器下发
--    客服关卡结算   客户端 → 服务器   参数：bool 胜利 / bool 逃跑合法
--                                     （服务器据此调平台结算：置逃跑合法性、置胜利、结算关卡）
--    客服成就达成   客户端 → 服务器   参数：int 大关号
--                                     （服务器：成就序号 = 大关号 + 1，计数 +10，目标 = 发送者自身）
-- ================================================================

---@diagnostic disable: undefined-global

local M = {}

local config = require("default_import_file/config")

local SAVE_UP = (config.SIGNAL_SAVE_UP or "客服存档信息")
local SAVE_DOWN = (config.SIGNAL_SAVE_DOWN or "服客存档信息")
local SETTLE = (config.SIGNAL_SETTLE or "客服关卡结算")
local ACH = (config.SIGNAL_ACH or "客服成就达成")

local onSave = nil

-- 注册「服客存档信息」监听（进游戏时服务器会推一次）
function M.init(handlers)
    handlers = handlers or {}
    onSave = handlers.onSave
    pcall(function()
        script:RegisterServerSignalHandler(SAVE_DOWN, function(name, params)
            local list = params and params[1]
            if type(list) == "table" and onSave then
                pcall(onSave, list)
            end
        end)
    end)
end

-- 关卡通关状态（打平成一维 bool 列表：大关1-块1..4、大关2-块1..4 ……）
function M.buildSave(state, chapterCount)
    local out = {}
    for c = 1, chapterCount do
        local dm = (state.chapterDone or {})[c] or {}
        for p = 1, 4 do
            out[#out + 1] = dm[p] == true
        end
    end
    return out
end

-- 客户端 → 服务器：存档
function M.sendSave(list)
    if type(list) ~= "table" or #list == 0 then return false end
    local ok = pcall(function()
        local sig = game.ServerSignal(SAVE_UP)
        sig:AddBoolList(list)
        sig:SendSignal()
    end)
    return ok
end

-- 客户端 → 服务器：结算（win = 胜利，legal = 逃跑合法性）
function M.sendSettle(win, legal)
    pcall(function()
        local sig = game.ServerSignal(SETTLE)
        sig:AddBool(win and true or false)
        sig:AddBool(legal and true or false)
        sig:SendSignal()
    end)
    return true
end

-- 客户端 → 服务器：成就（大关号；序号与计数由服务器按约定算）
function M.sendAchievement(chapterIndex)
    pcall(function()
        local sig = game.ServerSignal(ACH)
        sig:AddInt(math.floor(tonumber(chapterIndex) or 1))
        sig:SendSignal()
    end)
    return true
end

return M
