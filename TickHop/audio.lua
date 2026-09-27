-- ================================================================
-- TickHop 音效模块
--   通过预设音效 ID 播放 2D 音效；ID<=0 视为未配置，安全跳过。
--   音效 ID 由 game.lua 在 OnStart 从脚本变量读入后调用 init() 写入。
-- ================================================================

---@diagnostic disable: undefined-global

local M = {}

-- 预设音效 ID（=0 表示不播放）
M.ids = {
    jump   = 0,   -- 起跳
    land   = 0,   -- 落地
    switch = 0,   -- 平台随秒数亮起 / 熄灭
    pickup = 0,   -- 拾取道具
    win    = 0,   -- 到达终点
    fail   = 0,   -- 时间耗尽 / 掉出关卡
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

function M.playJump()   play(M.ids.jump) end
function M.playLand()   play(M.ids.land) end
function M.playSwitch() play(M.ids.switch) end
function M.playPickup() play(M.ids.pickup) end
function M.playWin()    play(M.ids.win) end
function M.playFail()   play(M.ids.fail) end

return M
