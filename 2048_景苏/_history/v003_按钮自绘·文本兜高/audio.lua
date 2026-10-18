-- ================================================================
-- 2048 · 音效模块
--   通过预设音效 ID 播放 2D 音效；ID<=0 视为未配置，安全跳过。
--   音效 ID 由 game.lua 在 OnStart 从脚本变量读入后调用 init() 写入。
--   ★ 全部 pcall 包裹：音效缺失/引擎异常绝不能打断玩法。
-- ================================================================

---@diagnostic disable: undefined-global

local M = {}

-- 预设音效 ID（=0 表示不播放）
M.ids = {
    move  = 0,   -- 方块平移
    merge = 0,   -- 方块合并
    spawn = 0,   -- 新方块出现
    undo  = 0,   -- 撤销一步
    win   = 0,   -- 达成 2048
    fail  = 0,   -- 无路可走
    click = 0,   -- 按钮点击
}

-- 由 game.lua 在 OnStart 调用
function M.init(ids)
    if type(ids) ~= "table" then return end
    for k, v in pairs(ids) do
        if M.ids[k] ~= nil and v then M.ids[k] = v end
    end
end

-- 通用播放：ID 非法或未配置时静默跳过
local function play(id, volume)
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

function M.playMove()  play(M.ids.move) end
function M.playMerge() play(M.ids.merge) end
function M.playSpawn() play(M.ids.spawn) end
function M.playUndo()  play(M.ids.undo) end
function M.playWin()   play(M.ids.win) end
function M.playFail()  play(M.ids.fail) end
function M.playClick() play(M.ids.click) end

-- ================================================================
-- ★ 一次移动的音效编排
--   合并 > 平移 的优先级：有合并就只放合并音（否则两层音叠在一起很吵）。
-- ================================================================
function M.playAction(action)
    if not action then return end
    if #action.merges > 0 then
        play(M.ids.merge)
    elseif #action.moves > 0 then
        play(M.ids.move)
    end
end

return M
