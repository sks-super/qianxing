-- ================================================================
-- 浮岛借木 · 音效模块
--   通过预设音效 ID 播放 2D 音效；ID<=0 视为未配置，安全跳过。
--   音效 ID 由 game.lua 在 OnStart 从脚本变量读入后调用 init() 写入。
-- ================================================================

---@diagnostic disable: undefined-global

local M = {}

-- 预设音效 ID（=0 表示不播放）
M.ids = {
    step    = 0,   -- 走一格
    knock   = 0,   -- 撞断树木
    push    = 0,   -- 推木桩 / 立起 / 倒下
    win     = 0,   -- 到达终点
    blocked = 0,   -- 撞墙 / 撞石头 / 过不去
}

-- 由 game.lua 在 OnStart 调用
function M.init(ids)
    if type(ids) ~= "table" then return end
    for k, v in pairs(ids) do
        if M.ids[k] ~= nil and v then M.ids[k] = v end
    end
end

-- 通用播放：ID 非法或未配置时静默跳过；pcall 防止引擎异常中断脚本
local function play(id)
    if not id or id <= 0 then return end
    pcall(function()
        game.PlayAudio2D(id)
    end)
end

-- ================================================================
-- 预热：把首次解码成本前置到 OnStart，事件触发时走热路径
-- ================================================================
function M.prewarm()
    for _, id in pairs(M.ids) do
        if id and id > 0 then
            pcall(function()
                local inst = game.PlayAudio2D(id)
                if inst then game.StopAudio(inst) end
            end)
        end
    end
end

function M.playStep()    play(M.ids.step) end
function M.playKnock()   play(M.ids.knock) end
function M.playPush()    play(M.ids.push) end
function M.playWin()     play(M.ids.win) end
function M.playBlocked() play(M.ids.blocked) end

return M
