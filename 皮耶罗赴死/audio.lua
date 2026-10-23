-- ================================================================
-- 皮耶罗：赴死 · 音效模块
--   通过预设音效 ID 播放 2D 音效；ID <= 0 视为未配置，安全跳过。
--   音效 ID 由 game.lua 在 OnStart 从脚本参数读入后调用 init() 写入。
-- ================================================================

---@diagnostic disable: undefined-global

local M = {}

M.ids = {
    click = 0,   -- 按钮点击
    jump  = 0,   -- 跳跃
    death = 0,   -- 死亡 / 化鬼
    win   = 0,   -- 穿过门
    pop   = 0,   -- 陷阱弹出 / 尖刺
    open  = 0,   -- 进入关卡
}

function M.init(ids)
    if type(ids) ~= "table" then return end
    for k, v in pairs(ids) do
        if M.ids[k] ~= nil and v then M.ids[k] = v end
    end
end

local function play(id)
    if not id or id <= 0 then return end
    pcall(function()
        game.PlayAudio2D(id)
    end)
end

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

function M.playClick() play(M.ids.click) end
function M.playJump()  play(M.ids.jump) end
function M.playDeath() play(M.ids.death) end
function M.playWin()   play(M.ids.win) end
function M.playPop()   play(M.ids.pop) end
function M.playOpen()  play(M.ids.open) end

return M
