-- ================================================================
-- 音效管理模块
--   通过预设音效 ID 播放 2D 音效；ID<=0 视为未配置，跳过播放。
--   音效 ID 由 game.lua 脚本变量（cutAudioId / bubbleAudioId /
--   winAudioId / failAudioId）在 OnStart 读入并写入本模块。
-- ================================================================

---@diagnostic disable: undefined-global

local M = {}

-- 预设音效 ID（=0 表示不播放）
M.ids = {
    cut    = 0,   -- 切割音效：切断绳子触发
    bubble = 0,   -- 戳破泡泡：泡泡破裂触发
    win    = 0,   -- 胜利音效：蛋糕投喂成功触发
    fail   = 0,   -- 失败音效：糖果出界或碰到尖刺触发
    tense  = 0,   -- 绷直音效：绳子由松弛变为绷直（直线）状态时触发
    star   = 0,   -- 收集星星音效：糖果收集星星时触发
}

-- 由 game.lua 在 OnStart 调用，传入脚本变量读取到的音效 ID
function M.init(ids)
    if type(ids) ~= "table" then return end
    M.ids.cut    = ids.cut    or M.ids.cut
    M.ids.bubble = ids.bubble or M.ids.bubble
    M.ids.win    = ids.win    or M.ids.win
    M.ids.fail   = ids.fail   or M.ids.fail
    M.ids.tense  = ids.tense  or M.ids.tense
    M.ids.star   = ids.star   or M.ids.star
end

-- 通用播放：ID 非法或未配置时安全跳过；pcall 防止引擎异常中断脚本
local function play(id)
    if not id or id <= 0 then return end
    local ok, err = pcall(function()
        game.PlayAudio2D(id)
    end)
    if not ok then
        printerr("音效播放失败 (id=" .. tostring(id) .. "): " .. tostring(err))
    end
end

-- ================================================================
-- 预热：在 OnStart 调用一次，把首次解码/加载的成本前置，
--       真正触发时（切割/戳破/胜利/失败）就不必再等。
--   做法：PlayAudio2D 一次拿到实例 ID，立即 StopAudio —— 资源
--         已进音频引擎缓存，下次再 PlayAudio2D 同一 id 就是热路径。
--   pcall 容错，未配置或引擎无此 id 时静默跳过。
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

function M.playCut()    play(M.ids.cut) end
function M.playBubble() play(M.ids.bubble) end
function M.playWin()    play(M.ids.win) end
function M.playFail()   play(M.ids.fail) end
function M.playTense()  play(M.ids.tense) end
function M.playStar()   play(M.ids.star) end

return M
