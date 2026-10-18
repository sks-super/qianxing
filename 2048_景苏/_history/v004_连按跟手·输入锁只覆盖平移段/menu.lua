-- ================================================================
-- 2048 · 结算展示（「给棋盘拍张照」）
--
--   ★ 这一套版式是本工程【原创】的，不复用旧项目的结算样式。
--     造型：把整块棋盘缩小、带一点倾角飞到屏幕中右 → 落定转正 →
--     四周长出「拍立得」相框（上/左/右窄边、下方宽留白，
--     留白里写一行说明）→ 屏幕左侧滑入信息面板，
--     面板内分数数字滚动增长、按钮依次弹出。
--
--   ★ 层级关键点：棋盘必须在「遮罩 + 信息面板」之上，才能当那张「相片」。
--     containerBoard 平时在 containerMenu 之下，开始结算时
--     用 utils.applyLayerOrder 把它抬上去（黑幕仍在最顶），
--     回到游戏时再按同一张表还原。
-- ================================================================

---@diagnostic disable: undefined-global

local M = {}

local state = require("default_import_file/state")
local config = require("default_import_file/config")
local utils = require("default_import_file/utils")
local anim = require("default_import_file/anim")
local hud = require("default_import_file/hud")

local TAG = "menu"

-- 所有结算控件（统一显隐）
local nodes = {}

-- 由 game.lua 注入
--   M.actions.continue()  胜利后继续挑战
--   M.actions.restart()   重开一局
--   M.actions.undo()      撤销一步（失败结算里的「后悔药」）
M.actions = {}

-- ================================================================
-- ★ 层级编排（list 从下到上）
-- ================================================================
local function layersPlay()
    utils.applyLayerOrder({
        state.containerBg,
        state.containerBoard,
        state.containerFx,
        state.containerHud,
        state.containerMenu,
        state.containerFade,
    })
end

local function layersSettle()
    utils.applyLayerOrder({
        state.containerBg,
        state.containerFx,
        state.containerHud,
        state.containerMenu,
        state.containerBoard,   -- ★ 棋盘抬到遮罩与信息面板之上
        state.containerFade,
    })
end

-- ================================================================
-- ★ containerMenu 的内部层级（list 从下到上）
--   ★★ 为什么必须统一重排一次、只靠建控件时的 sink/raise 不够：
--       sink/raise 只改「当时」的顺序，之后再创建任何一个子控件，
--       相对顺序就又变了。实测：只在建遮罩时 sink 了一次，等 4 条相框
--       边条 + 相片说明建完，遮罩已经跑到中间 —— 结果就是
--       「遮罩盖住相框和结算面板」，整屏发灰、面板文字发闷。
--   → 一律等所有子控件建完，再用这张表一次性重排。
-- ================================================================
local function layersMenu()
    local list = { state.menuOverlay, state.menuPhotoMatte }
    local bars = state.menuPhotoBars or {}
    for i = 1, #bars do list[#list + 1] = bars[i] end
    list[#list + 1] = state.menuPhotoCap
    list[#list + 1] = state.containerInfo    -- 面板整组压在最上
    utils.applyLayerOrder(list)
end

M.layersPlay = layersPlay
M.layersSettle = layersSettle
M.layersMenu = layersMenu

local function pal(k, fb) return utils.pal(k, fb) end

local function add(ctrl)
    if ctrl then nodes[#nodes + 1] = ctrl end
    return ctrl
end

-- ★ 建文本并提层。
--   ★★ 真机「后创建在上」、模拟器「先创建在上」（实测），所以文字压在
--      图片/按钮之上这件事必须显式声明：SetAsLastSibling 两引擎一致。
local function addText(x, y, w, h, text, color, size, parent)
    local c = utils.createText(x, y, w, h, text, color, size, parent or state.containerMenu)
    if c then
        utils.raise(c)
        nodes[#nodes + 1] = c
    end
    return c
end

-- ================================================================
-- ★ 相框几何（只在 init 时算一次）
--   inner = 棋盘边长 * 结算缩放（相片内沿边长）
--   outer = inner + 左右边宽 + 下边宽（拍立得）
-- ================================================================
local function frameGeom()
    local s = config.DEFAULT_SETTLE_PHOTO_SCALE or 0.46
    local pad = config.DEFAULT_SETTLE_FRAME_PAD or 16
    local padB = config.DEFAULT_SETTLE_FRAME_PAD_BOTTOM or 48
    local inner = utils.boardSize() * s
    return {
        inner = inner,
        pad = pad,
        padB = padB,
        outerW = inner + pad * 2,
        outerH = inner + pad + padB,
    }
end

-- ================================================================
-- ★ 预创建（OnStart 调用一次）
-- ================================================================
function M.init()
    if state.menuOverlay then return true end
    if not state.containerMenu then return false end
    if not state.rectPrefabId or state.rectPrefabId <= 0 then return false end

    local px = config.DEFAULT_SETTLE_PHOTO_X or 232
    local py = config.DEFAULT_SETTLE_PHOTO_Y or -18
    local ix = config.DEFAULT_SETTLE_INFO_CX or -350
    local iy = config.DEFAULT_SETTLE_INFO_CY or 0
    local iw = config.DEFAULT_SETTLE_INFO_W or 560
    local ih = config.DEFAULT_SETTLE_INFO_H or 460
    local geom = frameGeom()
    local matte = config.DEFAULT_SETTLE_MATTE or 5

    -- ------------------------------------------------------------
    -- ① 全屏遮罩（负责把背景与 HUD 压暗，必须待在本层最底下）
    -- ------------------------------------------------------------
    state.menuOverlay = add(utils.createControl(state.rectPrefabId, 0, 0, 4000, 4000,
        utils.hexToColorA(pal("overlay", "2B2724"), 0), state.containerMenu))
    utils.sink(state.menuOverlay)   -- ★ 沉到同级最下层（两引擎一致）

    -- ------------------------------------------------------------
    -- ② 相片内衬（比棋盘略大一圈的深色细线；在棋盘之下 → 只剩一圈边）
    -- ------------------------------------------------------------
    state.menuPhotoMatte = add(utils.createControl(state.rectPrefabId, px, py,
        geom.inner + matte * 2, geom.inner + matte * 2,
        utils.hexToColor(pal("frameMat", "5A4F47")), state.containerMenu))

    -- ------------------------------------------------------------
    -- ③ 相框四条边条（不覆住棋盘中心，所以放在哪一层都不会挡住相片）
    -- ------------------------------------------------------------
    local bars = {
        { px - geom.inner / 2 - geom.pad / 2, py + (geom.padB - geom.pad) / 2,
          geom.pad, geom.outerH },                                    -- 左
        { px + geom.inner / 2 + geom.pad / 2, py + (geom.padB - geom.pad) / 2,
          geom.pad, geom.outerH },                                    -- 右
        { px, py + geom.inner / 2 + geom.pad / 2, geom.inner, geom.pad },   -- 上
        { px, py - geom.inner / 2 - geom.padB / 2, geom.inner, geom.padB }, -- 下
    }
    state.menuPhotoBars = {}
    for i = 1, #bars do
        local b = bars[i]
        local ctrl = add(utils.createControl(state.rectPrefabId, b[1], b[2], b[3], b[4],
            utils.hexToColorA(pal("frame", "FFFDF7"), 0), state.containerMenu))
        state.menuPhotoBars[#state.menuPhotoBars + 1] = ctrl
    end

    -- 相片说明文字（写在拍立得的下方宽留白里）—— addText 已提层，压在下边条之上
    state.menuPhotoCap = addText(px, py - geom.inner / 2 - geom.padB / 2,
        geom.outerW - 24, 40, "", utils.hexToColorA(pal("textDark", "776E65"), 0),
        config.DEFAULT_SETTLE_CAP_SIZE or 22)

    -- ------------------------------------------------------------
    -- ④ 左侧信息面板（整组放在 containerInfo 里，滑入只动这一个容器）
    -- ------------------------------------------------------------
    state.containerInfo = utils.createContainer(state.containerMenu)
    if state.containerInfo then
        pcall(function()
            state.containerInfo:SetAnchoredPosition(ix, iy)
            state.containerInfo:SetSizeDelta(1, 1)
        end)
    end
    local ip = state.containerInfo or state.containerMenu

    state.menuInfoEdge = add(utils.createControl(state.rectPrefabId, 0, 0, iw + 10, ih + 10,
        utils.hexToColor(pal("panelEdge", "E6DFD3")), ip))
    state.menuInfoPanel = add(utils.createControl(state.rectPrefabId, 0, 0, iw, ih,
        utils.hexToColor(pal("panel", "FBF9F4")), ip))
    utils.sink(state.menuInfoEdge)   -- ★ 描边沉到最下层，只露出四周一圈
    utils.raise(state.menuInfoPanel) -- ★ 面板底板提到描边之上

    local cText = utils.hexToColor(pal("panelText", "5A4F47"))
    local cDim = utils.hexToColor(pal("panelDim", "9C8F86"))

    state.menuTitle = addText(0, 170, iw - 60, 56, "",
        cText, config.DEFAULT_SETTLE_TITLE_SIZE or 40, ip)
    state.menuSubtitle = addText(0, 122, iw - 60, utils.MIN_TEXT_H, "",
        cDim, config.DEFAULT_SETTLE_SUB_SIZE or 20, ip)
    state.menuScoreLabel = addText(0, 78, 300, utils.MIN_TEXT_H, "本次得分",
        cDim, config.DEFAULT_SETTLE_STAT_SIZE or 20, ip)
    state.menuScoreValue = addText(0, 30, iw - 60, 72, "0",
        cText, config.DEFAULT_SETTLE_SCORE_SIZE or 60, ip)
    state.menuStatMax = addText(0, -24, iw - 80, 40, "",
        cText, config.DEFAULT_SETTLE_STAT_SIZE or 20, ip)
    state.menuStatBest = addText(0, -64, iw - 80, 40, "",
        cText, config.DEFAULT_SETTLE_STAT_SIZE or 20, ip)
    state.menuStatSteps = addText(0, -104, iw - 80, 40, "",
        cText, config.DEFAULT_SETTLE_STAT_SIZE or 20, ip)

    -- 两个按钮：文案与动作在 open() 里按结算模式改写
    -- ★ 自绘按钮（底图 + 文本 + 光标命中区），不依赖「预设按钮」模板
    local bw = config.DEFAULT_SETTLE_BTN_W or 240
    local bh = config.DEFAULT_SETTLE_BTN_H or 54
    local bdx = config.DEFAULT_SETTLE_BTN_DX or 134
    local by = config.DEFAULT_SETTLE_BTN_Y or -178
    local bsize = (config.DEFAULT_SETTLE_STAT_SIZE or 20) + 2
    local btnBg = pal("btn", "D6CCC2")
    local btnBgDown = pal("btnDown", "C4B8AC")
    local btnFg = pal("btnText", "776E65")

    state.menuButtons = {}
    for i = 1, 2 do
        local dx = (i == 1) and -bdx or bdx
        local btn = { dx = dx, dy = by, action = nil }
        btn.ctl = utils.createButton(dx, by, bw, bh, ip, {
            text = "",
            fontSize = bsize,
            bg = btnBg,
            bgDown = btnBgDown,
            textColor = btnFg,
        })
        if btn.ctl then
            add(btn.ctl)
            utils.onClick(btn.ctl, function()
                if not state.menuOpen then return end
                local a = btn.action
                if a and M.actions[a] then M.actions[a]() end
            end)
            state.menuButtons[#state.menuButtons + 1] = btn
        end
    end

    M.setVisible(false)
    layersMenu()          -- ★ 所有子控件建完后再统一排一次层（见 layersMenu 注释）
    return true
end

-- ================================================================
-- 显隐（逐控件，不用容器一把梭）
-- ================================================================
function M.setVisible(v)
    for i = 1, #nodes do
        utils.setVisible(nodes[i], v and true or false)
    end
end

function M.isOpen()
    return state.menuOpen == true
end

-- ================================================================
-- ★ 打开结算
-- ================================================================
function M.open(mode)
    if not state.menuOverlay and not M.init() then return false end
    mode = mode or (state.dead and "dead" or "win")
    state.menuMode = mode
    state.menuOpen = true
    state.paused = true
    state.keysEnabled = false
    state.phase = "settled"

    anim.clear(TAG)

    -- 冻结结算数据（后面所有动画都读这三个数，不再受棋盘影响）
    state.menuFinalScore = math.max(0, math.floor(tonumber(state.score) or 0))
    state.menuFinalMax = math.max(0, math.floor(tonumber(state.maxReached) or 0))
    state.menuFinalSteps = math.max(0, math.floor(tonumber(state.steps) or 0))
    state.menuScoreShown = 0

    -- 文案与按钮按模式改写
    local winValue = config.DEFAULT_WIN_VALUE or 2048
    if mode == "win" then
        utils.setText(state.menuTitle, "达成 " .. tostring(winValue) .. " ！")
        utils.setText(state.menuSubtitle, "记录已经刷新，可以继续挑战更大的方块")
    else
        utils.setText(state.menuTitle, "无路可走")
        utils.setText(state.menuSubtitle, "棋盘已满，且没有可以合并的相邻方块")
    end
    utils.setText(state.menuScoreValue, "0")
    utils.setText(state.menuStatMax, "最大方块 " .. utils.comma(state.menuFinalMax))
    utils.setText(state.menuStatBest, "最高分 " .. utils.comma(state.best or 0))
    utils.setText(state.menuStatSteps, "步数 " .. utils.comma(state.menuFinalSteps))
    utils.setText(state.menuPhotoCap,
        "第 " .. tostring(state.menuFinalSteps) .. " 步 · 最大 " .. tostring(state.menuFinalMax))

    -- 按钮文案 / 动作
    local canUndo = (config.DEFAULT_UNDO_ENABLED or 1) ~= 0 and #state.undoStack > 0
    local b1, b2 = state.menuButtons[1], state.menuButtons[2]
    if b1 and b2 then
        if mode == "win" then
            b1.action = "continue"; b2.action = "restart"
            utils.setText(b1.ctl.label, "继续游戏")
            utils.setText(b2.ctl.label, "重新开始")
            utils.setButtonEnabled(b1.ctl, (config.DEFAULT_CONTINUE_AFTER_WIN or 1) ~= 0)
            utils.setButtonEnabled(b2.ctl, true)
        else
            b1.action = canUndo and "undo" or nil
            b2.action = "restart"
            utils.setText(b1.ctl.label, "撤销一步")
            utils.setText(b2.ctl.label, "重新开始")
            utils.setButtonEnabled(b1.ctl, canUndo)   -- 不可用时底图与文字一起变淡
            utils.setButtonEnabled(b2.ctl, true)
        end
    end

    -- 初始状态
    M.setVisible(true)
    local px = config.DEFAULT_SETTLE_PHOTO_X or 232
    local py = config.DEFAULT_SETTLE_PHOTO_Y or -18
    local ix = config.DEFAULT_SETTLE_INFO_CX or -350

    utils.setColor(state.menuOverlay, pal("overlay", "2B2724"), 0)
    utils.setColor(state.menuPhotoMatte, pal("frameMat", "5A4F47"), 0)
    for i = 1, #state.menuPhotoBars do
        utils.setColor(state.menuPhotoBars[i], pal("frame", "FFFDF7"), 0)
    end
    utils.setTextColor(state.menuPhotoCap, pal("textDark", "776E65"), 0)
    for i = 1, #state.menuButtons do
        local b = state.menuButtons[i]
        utils.setScale(b.ctl, 0)
    end
    -- 信息面板整组停在屏幕左外侧
    if state.containerInfo then
        utils.setPos(state.containerInfo, ix - 760, config.DEFAULT_SETTLE_INFO_CY or 0)
    end

    -- 收掉 HUD、把棋盘抬到遮罩之上
    hud.setVisible(false)
    layersSettle()
    layersMenu()      -- ★ 再保险一次：容器菜单内部的「遮罩必须在最底」不能靠记忆

    -- ------------------------------------------------------------
    -- 时间线
    -- ------------------------------------------------------------
    local tBoard   = config.DEFAULT_SETTLE_BOARD_TIME or 0.55
    local tOverlay = config.DEFAULT_SETTLE_OVERLAY_TIME or 0.30
    local dPhoto   = config.DEFAULT_SETTLE_PHOTO_DELAY or 0.30
    local tPhoto   = config.DEFAULT_SETTLE_PHOTO_TIME or 0.30
    local dInfo    = config.DEFAULT_SETTLE_INFO_DELAY or 0.30
    local tInfo    = config.DEFAULT_SETTLE_INFO_TIME or 0.42
    local tCount   = config.DEFAULT_SETTLE_COUNT_TIME or 0.75
    local tBtn     = config.DEFAULT_SETTLE_BTN_TIME or 0.24
    local dBtn     = config.DEFAULT_SETTLE_BTN_DELAY or 0.16

    -- ⓪ 遮罩淡入
    anim.value(0, config.DEFAULT_SETTLE_OVERLAY_ALPHA or 188, tOverlay,
        function(a) utils.setColor(state.menuOverlay, pal("overlay", "2B2724"), a) end,
        { ease = "outQuad", tag = TAG })

    -- ① 棋盘定格 → 缩小 → 带倾角飞到相片位 → 转正
    local root = state.containerBoard
    if root then
        local x0, y0 = state.boardCX or 0, state.boardCY or 0
        local s = config.DEFAULT_SETTLE_PHOTO_SCALE or 0.46
        local tilt = config.DEFAULT_SETTLE_PHOTO_TILT or -8
        anim.tween(tBoard, function(p)
            utils.setPos(root, x0 + (px - x0) * p, y0 + (py - y0) * p)
            utils.setScale(root, 1 + (s - 1) * p)
            utils.setRotationZ(root, tilt * math.sin(math.pi * p))
        end, {
            ease = "inOutCubic", tag = TAG,
            onDone = function()
                utils.setRotationZ(root, 0)     -- ★ 落定必须转正，否则相框对不上
                utils.setPos(root, px, py)
                utils.setScale(root, s)
            end,
        })
    end

    -- ② 相框淡入 + 相片内衬浮现 + 说明文字
    anim.delay(dPhoto, function()
        for i = 1, #state.menuPhotoBars do
            anim.value(0, 255, tPhoto, function(a)
                utils.setColor(state.menuPhotoBars[i], pal("frame", "FFFDF7"), a)
            end, { ease = "outQuad", tag = TAG })
        end
        anim.value(0, 255, tPhoto, function(a)
            utils.setColor(state.menuPhotoMatte, pal("frameMat", "5A4F47"), a)
        end, { ease = "outQuad", tag = TAG })
        anim.value(0, 255, tPhoto, function(a)
            utils.setTextColor(state.menuPhotoCap, pal("textDark", "776E65"), a)
        end, { ease = "outQuad", tag = TAG })
    end, TAG)

    -- ③ 信息面板从屏幕左外侧滑入（带一点点过冲）
    if state.containerInfo then
        local cy = config.DEFAULT_SETTLE_INFO_CY or 0
        anim.delay(dInfo, function()
            anim.value(ix - 760, ix, tInfo, function(x)
                utils.setPos(state.containerInfo, x, cy)
            end, { ease = "outBack", tag = TAG })
        end, TAG)
    end

    -- ④ 分数数字滚动增长（面板滑入完成后再开始，视线正好落上去）
    anim.delay(dInfo + tInfo * 0.72, function()
        anim.value(0, state.menuFinalScore, tCount, function(x)
            state.menuScoreShown = x
            utils.setText(state.menuScoreValue, utils.comma(x))
        end, {
            ease = "outCubic", tag = TAG,
            onDone = function()
                state.menuScoreShown = state.menuFinalScore
                utils.setText(state.menuScoreValue, utils.comma(state.menuFinalScore))
                -- 收尾弹一下，像计分器到位
                anim.tween(0.20, function(p)
                    utils.setScale(state.menuScoreValue, 1 + 0.10 * p)
                end, { ease = "pulse", tag = TAG })
            end,
        })
    end, TAG)

    -- ⑤ 按钮依次弹出（scale 0 → 1，回弹缓动）
    local btnStart = dInfo + tInfo * 0.72 + tCount * 0.55
    for i = 1, #state.menuButtons do
        local b = state.menuButtons[i]
        anim.delay(btnStart + (i - 1) * dBtn, function()
            anim.value(0, 1, tBtn, function(k)
                utils.setScale(b.ctl, k)
            end, { ease = "outBack", tag = TAG })
        end, TAG)
    end

    return true
end

-- ================================================================
-- ★ 关闭结算（棋盘归位、层级还原、HUD 复现）
-- ================================================================
function M.close()
    if not state.menuOpen then return true end
    anim.clear(TAG)
    state.menuOpen = false
    state.menuMode = nil
    state.paused = false
    state.phase = "playing"

    M.setVisible(false)
    layersPlay()

    -- 棋盘变换复位（把它从「相片位」请回牌桌）
    local root = state.containerBoard
    if root then
        utils.setPos(root, state.boardCX or 0, state.boardCY or 0)
        utils.setScale(root, 1)
        utils.setRotationZ(root, 0)
    end
    if state.containerInfo then
        utils.setPos(state.containerInfo,
            config.DEFAULT_SETTLE_INFO_CX or -350, config.DEFAULT_SETTLE_INFO_CY or 0)
    end

    hud.setVisible(true)
    hud.refresh()
    state.keysEnabled = true
    return true
end

return M
