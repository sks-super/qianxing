-- ================================================================
-- 2048 · HUD（标题 / 分数 / 最高分 / 说明 / 方向键 / 功能按钮 / 滑动面）
--
--   ★ 可点控件的两条铁律（真机踩过）：
--     ① 一律用「预设按钮」（utils.createButton）—— 图片控件没有
--        AddCursorEventListener 能力，用 pcall 包着会【静默失败】，
--        表现为「按钮画得出来但点不动」。
--     ② 文字标签永远在按钮【之后】创建，并再 raise() 一次 ——
--        真机「后创建的在上」，模拟器渲染顺序相反，raise 才是两引擎通吃的做法。
--   ★ 显隐：逐控件 SetActive，不用容器 SetActive 一把梭（避免子控件不跟随）。
-- ================================================================

---@diagnostic disable: undefined-global

local M = {}

local state = require("default_import_file/state")
local config = require("default_import_file/config")
local utils = require("default_import_file/utils")
local anim = require("default_import_file/anim")

local TAG_SCORE = "hud:score"
local TAG_POP = "hud:pop"

-- 分数框内两段文字的宽度（框宽 300，左右各留 20）
local BOX_TEXT_W = 260
-- 临时提示的位置（固定设计坐标：设计高度就是 720，-310 永远在屏内）
local TOAST_Y = -310

-- 所有 HUD 控件（统一显隐）
local nodes = {}

-- 由 game.lua 注入，避免 hud 反向 require game 造成循环依赖
--   M.actions.onDir(dir)      dir = "up" | "down" | "left" | "right"
--   M.actions.onButton(name)  name = "restart" | "undo" | "continue"
M.actions = {}

local function pal(k, fb) return utils.pal(k, fb) end

local function add(ctrl)
    if ctrl then nodes[#nodes + 1] = ctrl end
    return ctrl
end

-- ================================================================
-- 「分数 / 最高分」框：小标题在上、数值在下的两段式
--   ★ 之所以这样排：文本框有最小高度（36），一个 84 高的框
--     刚好能竖着放下 36 + 46 两段，不会出现「下面那段一个字都不画」。
-- ================================================================
local function makeBox(cx, cy)
    local w = config.DEFAULT_SCORE_W or 300
    local h = config.DEFAULT_SCORE_H or 84
    local bg = add(utils.createControl(state.rectPrefabId, cx, cy, w, h,
        utils.hexToColor(pal("box", "BBADA0")), state.containerHud))
    local label = add(utils.createText(cx, cy + (config.DEFAULT_SCORE_LABEL_DY or 23),
        BOX_TEXT_W, utils.MIN_TEXT_H, "", utils.hexToColor(pal("boxLabel", "EEE4DA")),
        config.DEFAULT_SCORE_LABEL_SIZE or 20, state.containerHud))
    local value = add(utils.createText(cx, cy + (config.DEFAULT_SCORE_VALUE_DY or -21),
        BOX_TEXT_W, 46, "0", utils.hexToColor(pal("boxValue", "FFFFFF")),
        config.DEFAULT_SCORE_VALUE_SIZE or 34, state.containerHud))
    return { bg = bg, label = label, value = value }
end

-- ================================================================
-- 方向键（D-Pad）
--   ★ 字形只用 ↑ ↓ ← → —— ◀ ▶ 在中文常用字体里没有字形，会渲染成豆腐块。
-- ================================================================
local DIR_GLYPH = { up = "↑", down = "↓", left = "←", right = "→" }

local function createDpad(cx, cy)
    local b = config.DEFAULT_DPAD_BTN or 60
    local g = config.DEFAULT_DPAD_GAP or 6
    local off = b + g
    local size = config.DEFAULT_DPAD_SIZE or 26
    local glyphColor = utils.hexToColor(pal("hud", "776E65"))

    local defs = {
        { dir = "up",    x = cx,       y = cy + off },
        { dir = "down",  x = cx,       y = cy - off },
        { dir = "left",  x = cx - off, y = cy },
        { dir = "right", x = cx + off, y = cy },
    }

    state.dpad = {}
    for i = 1, #defs do
        local d = defs[i]
        local hit = utils.createButton(d.x, d.y, b, b, state.containerHud, state.clickAudioId)
        if hit then
            add(hit)
            local dir = d.dir
            utils.onClick(hit, function()
                if M.actions.onDir then M.actions.onDir(dir) end
            end)
            local label = utils.createText(d.x, d.y, b, b, DIR_GLYPH[dir],
                glyphColor, size, state.containerHud)
            add(label)
            utils.raise(label)
            state.dpad[#state.dpad + 1] = { hit = hit, label = label, dir = dir }
        end
    end
end

-- ================================================================
-- 功能按钮（重新开始 / 撤销一步 / 继续游戏）
-- ================================================================
local FUNC_DEFS = {
    { action = "restart",  text = "重新开始", y = "DEFAULT_FUNC_Y1" },
    { action = "undo",     text = "撤销一步", y = "DEFAULT_FUNC_Y2" },
    { action = "continue", text = "继续游戏", y = "DEFAULT_FUNC_Y3" },
}

local function createFuncButtons(cx)
    local w = config.DEFAULT_FUNC_W or 300
    local h = config.DEFAULT_FUNC_H or 52
    local size = config.DEFAULT_FUNC_SIZE or 22
    local color = utils.hexToColor(pal("hud", "776E65"))

    state.funcButtons = {}
    for i = 1, #FUNC_DEFS do
        local def = FUNC_DEFS[i]
        local y = config[def.y] or -176
        local hit = utils.createButton(cx, y, w, h, state.containerHud, state.clickAudioId)
        if hit then
            add(hit)
            local label = utils.createText(cx, y, w, h, def.text, color, size, state.containerHud)
            add(label)
            utils.raise(label)
            local action = def.action
            utils.onClick(hit, function()
                if M.actions.onButton then M.actions.onButton(action) end
            end)
            state.funcButtons[#state.funcButtons + 1] = {
                hit = hit, label = label, action = action, enabled = true,
            }
        end
    end
end

-- ================================================================
-- ★ 预创建（OnStart 调用一次）
-- ================================================================
function M.init()
    if state.titleText then return true end
    if not state.containerHud then return false end
    if not state.rectPrefabId or state.rectPrefabId <= 0 then return false end

    local cx = config.DEFAULT_PANEL_CX or 340

    -- ① 滑动命中区：最先创建 → 永远压在同层最下面，按钮压在它上面，
    --    这样「点按钮」不会被「滑动」抢走事件。
    state.swipeArea = utils.createHit(0, 0, 4000, 4000, state.containerHud, true)
    if state.swipeArea then
        add(state.swipeArea)
        utils.sink(state.swipeArea)
    end

    -- ② 标题
    state.titleText = add(utils.createText(cx, config.DEFAULT_TITLE_Y or 312, 360, 76,
        "2048", utils.hexToColor(pal("textDark", "776E65")),
        config.DEFAULT_TITLE_SIZE or 62, state.containerHud))

    -- ③ 分数 / 最高分
    state.scoreBox = makeBox(cx, config.DEFAULT_SCORE_Y or 230)
    state.bestBox = makeBox(cx, config.DEFAULT_BEST_Y or 140)
    utils.setText(state.scoreBox.label, "分数")
    utils.setText(state.bestBox.label, "最高分")
    utils.setText(state.scoreBox.value, "0")
    utils.setText(state.bestBox.value, "0")

    -- ④ 操作说明
    state.hintText = add(utils.createText(cx, config.DEFAULT_HINT_Y or 76, 360,
        utils.MIN_TEXT_H, "WASD / 方向键 / 滑动屏幕",
        utils.hexToColor(pal("dim", "9C8F86")),
        config.DEFAULT_HINT_SIZE or 18, state.containerHud))

    -- ⑤ 方向键 + 功能按钮
    createDpad(cx, config.DEFAULT_DPAD_CY or -48)
    createFuncButtons(cx)

    -- ⑥ 临时提示（撤销失败、胜负播报 …）
    state.toastText = add(utils.createText(state.boardCX or -230, TOAST_Y, 640, 40, "",
        utils.hexToColor(pal("dim", "9C8F86")), 22, state.containerHud))

    M.refresh()
    return true
end

-- ================================================================
-- ★ 显隐（结算面板打开时收掉整个 HUD）
-- ================================================================
function M.setVisible(v)
    for i = 1, #nodes do
        utils.setVisible(nodes[i], v and true or false)
    end
end

-- ================================================================
-- ★ 按钮可用性：撤销需要历史、继续需要已达成目标、
--   重开则任何时候都可用
-- ================================================================
function M.refresh()
    local playable = state.phase == "playing"
    for i = 1, #state.funcButtons do
        local b = state.funcButtons[i]
        local enabled = true
        if b.action == "undo" then
            enabled = playable
                and (config.DEFAULT_UNDO_ENABLED or 1) ~= 0
                and #state.undoStack > 0
        elseif b.action == "continue" then
            enabled = playable
                and state.won
                and (config.DEFAULT_CONTINUE_AFTER_WIN or 1) ~= 0
        end
        b.enabled = enabled
        utils.setButtonEnabled(b.hit, enabled)
        local a = enabled and (config.DEFAULT_FUNC_TEXT_ALPHA or 255)
                          or (config.DEFAULT_FUNC_DISABLED_ALPHA or 96)
        utils.setTextColor(b.label, pal("hud", "776E65"), a)
    end
end

-- ================================================================
-- ★ 分数
--   animate = true  → 数字滚动 + 数值弹一下（需求指定的「滚动或弹跳」）
--   animate = false → 直接跳到目标值（重开 / 撤销时用）
-- ================================================================
function M.setScore(v, animate)
    local target = math.max(0, math.floor(tonumber(v) or 0))
    local box = state.scoreBox
    if not box or not box.value then
        state.scoreShown = target
        return
    end

    anim.clear(TAG_SCORE)
    anim.clear(TAG_POP)

    local from = math.floor(tonumber(state.scoreShown) or 0)
    if (not animate) or from == target then
        state.scoreShown = target
        utils.setText(box.value, utils.comma(target))
        utils.setScale(box.value, 1)
        return
    end

    -- 数值弹一下（pulse：0 → 1 → 0 的山丘，峰值用 DEFAULT_ANIM_SCORE_POP）
    local pop = config.DEFAULT_ANIM_SCORE_POP or 1.14
    anim.tween(0.18, function(p)
        utils.setScale(box.value, 1 + (pop - 1) * p)
    end, { ease = "pulse", tag = TAG_POP })

    anim.value(from, target, config.DEFAULT_ANIM_SCORE_TIME or 0.35, function(x)
        state.scoreShown = x
        utils.setText(box.value, utils.comma(x))
    end, {
        ease = "outCubic", tag = TAG_SCORE,
        onDone = function()
            state.scoreShown = target
            utils.setText(box.value, utils.comma(target))
        end,
    })
end

-- 最高分：不滚数字（它基本不动），只在刷新纪录时弹一下
function M.setBest(v, animate)
    local target = math.max(0, math.floor(tonumber(v) or 0))
    local box = state.bestBox
    state.bestShown = target
    if not box or not box.value then return end
    utils.setText(box.value, utils.comma(target))
    if animate and target > 0 then
        anim.tween(0.22, function(p)
            utils.setScale(box.value, 1 + 0.12 * p)
        end, { ease = "pulse", tag = TAG_POP })
    end
end

-- ================================================================
-- ★ 临时提示
-- ================================================================
function M.toast(msg, sec)
    if not state.toastText then return end
    utils.setText(state.toastText, msg or "")
    state.toastTimer = sec or 1.6
end

function M.update(dt)
    if (state.toastTimer or 0) > 0 then
        state.toastTimer = state.toastTimer - (dt or 0)
        if state.toastTimer <= 0 then
            state.toastTimer = 0
            utils.setText(state.toastText, "")
        end
    end
end

return M
