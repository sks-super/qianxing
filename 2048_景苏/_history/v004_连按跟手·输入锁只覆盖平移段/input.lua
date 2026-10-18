-- ================================================================
-- 2048 · 输入（键盘 / 点击按钮 / 滑动屏幕）
--
--   三条输入路径最终都汇到同一个出口：M.actions.onDir(dir)，
--   由 game.lua 统一做「锁输入判定 → 落子 → 播动画」，
--   所以这里不做任何玩法判断，只负责把「物理输入」翻译成「方向」。
--
--   ★ 键盘必须做「边沿触发」：按住不放时引擎/系统会连续送 KeyDown，
--     不判边沿就会出现「按住 D 一路狂滑」。
--   ★ 滑动用 CursorDown 记起点、CursorDrag 判阈值 —— 这样
--     「按住鼠标左键一路滑」与「手指一划」都能用，不必等抬起。
-- ================================================================

---@diagnostic disable: undefined-global

local M = {}

local state = require("default_import_file/state")
local config = require("default_import_file/config")
local utils = require("default_import_file/utils")

-- 由 game.lua 注入
--   M.actions.onDir(dir)        dir = "up" | "down" | "left" | "right"
--   M.actions.onRestart()
--   M.actions.onUndo()
--   M.actions.onContinue()
M.actions = {}

-- 按住状态（边沿触发用）
local held = {}

local function enabled()
    return state.keysEnabled == true and state.paused ~= true
end

-- ================================================================
-- ★ 滑动
-- ================================================================
local function trySwipe(dx, dy)
    local min = config.DEFAULT_SWIPE_MIN_DISTANCE or 42
    if math.abs(dx) < min and math.abs(dy) < min then return end
    local dir
    if math.abs(dx) >= math.abs(dy) then
        dir = (dx > 0) and "right" or "left"
    else
        dir = (dy > 0) and "up" or "down"
    end
    state.swipeConsumed = true
    if M.actions.onDir then M.actions.onDir(dir) end
end

local function onCursorDown(data)
    local x, y = utils.cursorPos(data, "press")
    if not x then x, y = utils.cursorPos(data, "pos") end
    if not x then return end
    if not enabled() then
        state.swiping = false
        return
    end
    state.swipeStartX = x
    state.swipeStartY = y
    state.swiping = true
    state.swipeConsumed = false
end

local function onCursorDrag(data)
    if not enabled() or not state.swiping or state.swipeConsumed then return end
    local x, y = utils.cursorPos(data, "pos")
    if not x then return end
    trySwipe(x - state.swipeStartX, y - state.swipeStartY)
end

local function onCursorUp(data)
    if enabled() and state.swiping and not state.swipeConsumed then
        local x, y = utils.cursorPos(data, "pos")
        if x then trySwipe(x - state.swipeStartX, y - state.swipeStartY) end
    end
    state.swiping = false
    state.swipeConsumed = false
end

-- ================================================================
-- ★ 键盘
-- ================================================================
local function bindKeys(root)
    local K = Enum.KeyEventType

    -- 方向：按下即走一步；抬起只清「按住」标记
    --   guard = 1 时做边沿触发（默认），= 0 时按住可连发（不推荐）
    local function bindDir(downEvt, upEvt, dir)
        pcall(function()
            root:AddKeyEventListener(downEvt, function()
                local guard = (config.DEFAULT_KEY_GUARD or 1) ~= 0
                if guard then
                    if held[dir] then return false end
                    held[dir] = true
                end
                if enabled() and M.actions.onDir then M.actions.onDir(dir) end
                return true
            end)
        end)
        if upEvt then
            pcall(function()
                root:AddKeyEventListener(upEvt, function()
                    held[dir] = false
                    return true
                end)
            end)
        end
    end

    local function bindFn(downEvt, fn)
        pcall(function()
            root:AddKeyEventListener(downEvt, function()
                if enabled() then fn() end
                return true
            end)
        end)
    end

    -- 上：W / ↑
    bindDir(K.KeyboardMoveForwardKeyDown,  K.KeyboardMoveForwardKeyUp,  "up")
    bindDir(K.KeyboardCraftspersonKey36Down, K.KeyboardCraftspersonKey36Up, "up")
    -- 下：S / ↓
    bindDir(K.KeyboardMoveBackwardKeyDown, K.KeyboardMoveBackwardKeyUp, "down")
    bindDir(K.KeyboardCraftspersonKey37Down, K.KeyboardCraftspersonKey37Up, "down")
    -- 左：A / ←
    bindDir(K.KeyboardMoveLeftKeyDown,     K.KeyboardMoveLeftKeyUp,     "left")
    bindDir(K.KeyboardCraftspersonKey38Down, K.KeyboardCraftspersonKey38Up, "left")
    -- 右：D / →
    bindDir(K.KeyboardMoveRightKeyDown,    K.KeyboardMoveRightKeyUp,    "right")
    bindDir(K.KeyboardCraftspersonKey39Down, K.KeyboardCraftspersonKey39Up, "right")

    -- 功能键：R 重开 / Z 撤销 / 空格 继续
    bindFn(K.KeyboardCharacterSkill3KeyDown, function()
        if M.actions.onRestart then M.actions.onRestart() end
    end)
    bindFn(K.KeyboardCraftspersonKey12Down, function()
        if M.actions.onUndo then M.actions.onUndo() end
    end)
    bindFn(K.KeyboardJumpKeyDown, function()
        if M.actions.onContinue then M.actions.onContinue() end
    end)
end

-- ================================================================
-- ★ 初始化
-- ================================================================
function M.init()
    -- 滑动面（预设按钮/光标检测区域才能收到光标事件；图片控件会静默失败）
    if state.swipeArea and (config.DEFAULT_SWIPE_ENABLED or 1) ~= 0 then
        utils.onCursor(state.swipeArea, Enum.CursorEventType.CursorDown, onCursorDown)
        utils.onCursor(state.swipeArea, Enum.CursorEventType.CursorDrag, onCursorDrag)
        utils.onCursor(state.swipeArea, Enum.CursorEventType.CursorUp, onCursorUp)
        utils.onCursor(state.swipeArea, Enum.CursorEventType.CursorExit, onCursorUp)
    end

    if state.parent then bindKeys(state.parent) end
    return true
end

-- ================================================================
-- ★ 复位（重开一局时清掉「按住」残留，避免卡键）
-- ================================================================
function M.reset()
    held = {}
    state.swiping = false
    state.swipeConsumed = false
end

return M
