-- ================================================================
-- 点灯迷题 16 · 入口
-- ================================================================
-- 挂载：客户端控件容器的【容器节点】（script.object）
--
-- 参数：rectPrefabId（必填·纯色矩形）、textPrefabId（必填·文本框）、
--       cursorPrefabId（必填·光标检测区域）
--       可选音效：flipAudioId / clickAudioId / winAudioId
--       开发用：autoStart=1 直接进第 1 块；autoPress=<0..63> 自动按一格
--
-- 流程：大关（16×16 图）→ 4 个 8×8 小关 → 4/4 → 合拢 + 上色演出
-- ================================================================

---@diagnostic disable: undefined-global

local state = require("default_import_file/state")
local config = require("default_import_file/config")
local utils = require("default_import_file/utils")
local anim = require("default_import_file/anim")
local art = require("default_import_file/art")
local board = require("default_import_file/board")
local view = require("default_import_file/view")
local fx = require("default_import_file/fx")
local hud = require("default_import_file/hud")
local fadeScreen = require("default_import_file/fadeScreen")
local audio = require("default_import_file/audio")

local TAG_TICK = "game:tick"
local TAG_FIN = "game:finale"
local finaleRoot = nil

local startPiece, pressCell, onCleared, doFinale, switchChapter
local devAutoPress, devAt = -1, 0
local devSolve = false

-- ================================================================
function getParamNumber(name, default)
    local ok, v = pcall(function() return script:GetParamValue(name) end)
    if ok and type(v) == "number" then return v end
    if ok and type(v) == "string" then
        local n = tonumber(v)
        if n then return n end
    end
    return default or 0
end

-- ================================================================
local function ensureContainers()
    local root = state.parent
    if not root then return false end
    if not state.containerScene then
        state.containerScene = utils.createContainer(root)
        if not state.containerScene then return false end
        utils.setScale(state.containerScene, state.k or 1)
    end
    local s = state.containerScene
    if not state.containerBg then state.containerBg = utils.createContainer(s) end
    if not state.containerRef then state.containerRef = utils.createContainer(s) end
    if not state.containerBoard then state.containerBoard = utils.createContainer(s) end
    if not state.containerFx then state.containerFx = utils.createContainer(s) end
    if not state.containerHud then state.containerHud = utils.createContainer(s) end
    if not state.containerChips then state.containerChips = utils.createContainer(s) end
    if not state.containerWin then state.containerWin = utils.createContainer(s) end
    if not state.containerFade then state.containerFade = utils.createContainer(s) end

    utils.applyLayerOrder({
        state.containerBg, state.containerRef, state.containerBoard, state.containerFx,
        state.containerHud, state.containerChips, state.containerWin, state.containerFade,
    })
    return true
end

local function createBackground()
    local par = state.containerBg
    local pal = config.DEFAULT_PALETTE or {}
    if not par or (state.rectPrefabId or 0) <= 0 then return end
    utils.createControl(state.rectPrefabId, 0, 0, 2400, 1400, utils.hexToColor(pal.bg or "070A12"), par)
    local blobs = {
        { -560, 320, 820, 820, pal.bgGlow or "152348", 26, 16 },
        { 560, -300, 900, 900, pal.bgGlow2 or "2A1550", 20, -12 },
    }
    for i = 1, #blobs do
        local b = blobs[i]
        local c = utils.createControl(state.rectPrefabId, b[1], b[2], b[3], b[4],
            utils.hexToColorA(b[5], b[6]), par)
        if c then utils.setRotationZ(c, b[7]) end
    end
end

-- ================================================================
-- 开一个小关
-- ================================================================
startPiece = function(pieceIdx, silent)
    local ch = config.getChapter(state.chapterIndex)
    if not ch then return false end
    pieceIdx = math.floor(tonumber(pieceIdx) or 1)
    if pieceIdx < 1 or pieceIdx > 4 then pieceIdx = 1 end

    local grid = art.parse(ch.pic)
    state.pic = grid
    local p = config.PIECES[pieceIdx]
    state.quadTarget = art.quad(grid, p.ox, p.oy)
    state.pieceIndex = pieceIdx

    local k = (config.DEFAULT_A_BY_PIECE or {})[pieceIdx] or 3
    local seed = board.seedOf(ch.key, pieceIdx * 97 + state.chapterIndex * 13)
    local lv = board.genLevel(state.quadTarget, k, seed)

    state.board = lv.start
    state.targetBoard = lv.target
    state.aSet = lv.a
    state.bestSteps = #lv.a
    state.moves = 0
    state.history = {}
    state.hintIndex = -1
    state.pieceOpen = true
    state.phase = "play"

    anim.clearAll()
    fx.clear()
    view.setRef(state.quadTarget)
    view.syncPlay(state.board)
    view.setVisible(true)
    view.setRefVisible(state.mode == 1)
    hud.refresh()
    state.inputReady = false

    if silent then
        state.inputReady = true
    else
        local d = view.spawn()
        anim.delay(d, function() state.inputReady = true end, TAG_TICK)
    end
    return true
end

-- ================================================================
-- 按一格
-- ================================================================
pressCell = function(idx)
    if state.phase ~= "play" or not state.pieceOpen then return false end
    if not state.inputReady then
        state.pendingPress = idx
        return false
    end
    if not board.valid(idx) then return false end

    local prev = board.copy(state.board)
    board.press(state.board, idx)
    state.moves = state.moves + 1
    state.history[#state.history + 1] = idx

    local dur = view.playPress(idx, prev, { board = state.board })
    audio.playFlip()
    hud.setSteps(state.moves)
    hud.popSteps()

    state.inputReady = false
    anim.delay(dur + (config.DEFAULT_ANIM_INPUT_LOCK or 0.1), function()
        state.inputReady = true
        local p = state.pendingPress
        state.pendingPress = nil
        if p then pressCell(p) end
    end, TAG_TICK)

    local win
    if state.mode == 1 then
        win = board.equals(state.board, state.targetBoard)
    else
        win = board.isBlank(state.board)
    end
    if win then
        state.pieceOpen = false
        anim.delay(dur + 0.08, function() onCleared() end, TAG_TICK)
    end
    return true
end

-- ================================================================
-- 小关完成
-- ================================================================
onCleared = function()
    if state.phase ~= "play" then return false end
    state.phase = "finish"
    state.inputReady = false

    local i = state.pieceIndex
    local best = state.bestSteps or 0
    local stars = 1
    if state.moves <= best then stars = 3
    elseif state.moves <= best + (config.DEFAULT_STAR_TWO_EXTRA or 2) then stars = 2 end

    state.slotDone[i] = true
    state.slotStars[i] = math.max(state.slotStars[i] or 0, stars)
    hud.setChipDone(i)
    audio.playWin()

    local all = true
    for k = 1, 4 do
        if not state.slotDone[k] then all = false end
    end

    if all then
        anim.delay(0.55, function() doFinale() end, TAG_TICK)
    else
        anim.delay(0.85, function()
            local nxt = nil
            for k = 1, 4 do
                local j = (i + k - 1) % 4 + 1
                if not state.slotDone[j] then nxt = j; break end
            end
            if nxt then
                fadeScreen.start({ onPeak = function() startPiece(nxt) end })
            else
                state.phase = "pick"
            end
        end, TAG_TICK)
    end
    return true
end

-- ================================================================
-- ★ 通关演出：16×16 合拢 + 上色
-- ================================================================
doFinale = function()
    state.phase = "finish"
    state.inputReady = false
    view.setVisible(false)
    hud.setVisible(false)
    fx.clear()
    audio.playWin()

    local ch = config.getChapter(state.chapterIndex)
    local pal = config.DEFAULT_PALETTE or {}
    local cell, gap = 24, 2
    local total = 16 * cell + 17 * gap

    local par = utils.createContainer(state.containerWin)
    if not par then return end
    finaleRoot = par

    -- 底板
    local edge = utils.createControl(state.rectPrefabId, 0, 0, total + 24, total + 24,
        utils.hexToColor(pal.panelEdge or "1E2A47"), par)
    local paperC = utils.createControl(state.rectPrefabId, 0, 0, total + 16, total + 16,
        utils.hexToColor(pal.paper or "F7F8FA"), par)

    local regions = art.regions(state.pic)
    local cells = {}
    for y = 1, 16 do
        for x = 1, 16 do
            local px = -total / 2 + gap + cell / 2 + (x - 1) * (cell + gap)
            local py = total / 2 - gap - cell / 2 - (y - 1) * (cell + gap)
            local v = art.at(state.pic, x, y)
            local c = utils.createControl(state.rectPrefabId, px, py, cell - gap, cell - gap,
                utils.hexToColor(v == 1 and (pal.ink or "111318") or (pal.paper or "F7F8FA")), par)
            cells[#cells + 1] = { ctrl = c, x = x, y = y, slot = regions[y][x], v = v }
        end
    end

    -- ① 描边发光 → ② 上色
    for i = 1, #cells do
        local c = cells[i]
        if c.slot and c.slot > 0 then
            local hex = (ch.colors and ch.colors[c.slot]) or pal.accent
            anim.delay(0.55 + i * (config.DEFAULT_ANIM_COLOR_STAGGER or 0.006), function()
                anim.tween(config.DEFAULT_ANIM_COLOR_TIME or 0.42, function(p)
                    utils.setColor(c.ctrl, hex, math.floor(60 + 195 * p))
                end, { ease = "outQuad", tag = TAG_FIN })
            end, TAG_FIN)
        end
    end

    fx.confetti()
    for i = 1, 10 do
        anim.delay(0.7 + i * 0.09, function() audio.playStar() end, TAG_FIN)
    end

    -- ★ 一次性排全层：描边 → 白纸 → 256 个色块 → 文字
    --   漏了这步，模拟器会把白纸画在色块之上（面板一片空）。
    local order = { edge, paperC }
    for i = 1, #cells do order[#order + 1] = cells[i].ctrl end
    utils.applyLayerOrder(order)

    local t = utils.createText(0, -total / 2 - 46, 520, 40, "「" .. (ch.name or "") .. "」完成",
        utils.hexToColor(pal.text or "E9F0FF"), 26, par)
    utils.raise(t)

    anim.delay(1.9, function()
        state.phase = "finish"
        hud.setVisible(true)
        hud.refresh()
    end, TAG_TICK)
end

-- ================================================================
-- 换大关
-- ================================================================
switchChapter = function()
    local nextIdx = (state.chapterIndex or 1) % config.chapterCount() + 1
    state.chapterIndex = nextIdx
    state.slotDone = { false, false, false, false }
    state.slotStars = { 0, 0, 0, 0 }
    if finaleRoot then utils.destroy(finaleRoot); finaleRoot = nil end
    fadeScreen.start({ onPeak = function()
        hud.setVisible(true)
        startPiece(1)
    end })
end

-- ================================================================
-- 撤销 / 提示
-- ================================================================
local function undo()
    if state.phase ~= "play" or not state.inputReady then return false end
    if (config.DEFAULT_UNDO_ENABLED or 1) == 0 then return false end
    local n = #state.history
    if n < 1 then return false end
    local idx = state.history[n]
    state.history[n] = nil
    local prev = board.copy(state.board)
    board.press(state.board, idx)
    state.moves = math.max(0, state.moves - 1)
    view.playPress(idx, prev, { board = state.board, speed = 0.85 })
    hud.setSteps(state.moves)
    return true
end

local function showHint()
    if state.phase ~= "play" then return false end
    if (config.DEFAULT_HINT_ENABLED or 1) == 0 then return false end
    local idx = board.hintCell(state.aSet, state.history)
    if idx < 0 then return false end
    view.showHint(idx)
    return true
end

-- ================================================================
-- 键盘
-- ================================================================
local function bindKeys(root)
    local K = Enum.KeyEventType
    local function bind(evt, fn)
        pcall(function()
            root:AddKeyEventListener(evt, function() return fn() == true end)
        end)
    end
    bind(K.KeyboardCharacterSkill3KeyDown, function()
        if state.phase == "play" then
            fadeScreen.start({ onPeak = function() startPiece(state.pieceIndex) end })
            return true
        end
        return false
    end)
    bind(K.KeyboardCharacterSkill4KeyDown, showHint)
    bind(K.KeyboardMoveBackwardKeyDown, undo)
end

-- ================================================================
-- 生命周期
-- ================================================================
function OnStart()
    local root = script.object
    if not root then
        printerr("错误：script.object 为 nil，请把 game.lua 挂到客户端控件容器的容器节点上")
        return
    end
    state.parent = root

    state.rectPrefabId = getParamNumber("rectPrefabId", 0)
    state.textPrefabId = getParamNumber("textPrefabId", 0)
    state.cursorPrefabId = getParamNumber("cursorPrefabId", 0)
    state.containerPrefabId = getParamNumber("containerPrefabId", 0)
    if state.rectPrefabId <= 0 then
        printerr("错误：请设置脚本参数 rectPrefabId（纯色矩形 / 图片控件）")
        return
    end

    script:EnableUpdate(true)

    state.clickAudioId = getParamNumber("clickAudioId", 0)
    state.flipAudioId = getParamNumber("flipAudioId", 0)
    state.winAudioId = getParamNumber("winAudioId", 0)
    state.starAudioId = getParamNumber("starAudioId", 0)
    audio.init({
        click = state.clickAudioId, flip = state.flipAudioId,
        win = state.winAudioId, star = state.starAudioId,
    })
    audio.prewarm()

    local okSize, w, h = pcall(function() return game.GetUICanvasSize() end)
    state.canvasW = (okSize and type(w) == "number" and w > 0) and w or config.DEFAULT_VIEW_WIDTH
    state.canvasH = (okSize and type(h) == "number" and h > 0) and h or config.DEFAULT_VIEW_HEIGHT
    utils.computeLayout()
    state.designW = config.DEFAULT_DESIGN_WIDTH
    state.designH = config.DEFAULT_DESIGN_HEIGHT

    if not ensureContainers() then
        printerr("错误：层级容器创建失败（检查 rectPrefabId）")
        return
    end
    fadeScreen.init()
    createBackground()

    if not view.init() then printerr("警告：棋盘初始化失败") end
    if not hud.init() then printerr("警告：信息栏初始化失败") end

    hud.setActions({
        onUndo = undo,
        onReset = function()
            fadeScreen.start({ onPeak = function() startPiece(state.pieceIndex) end })
        end,
        onHint = showHint,
        onMode = function()
            state.mode = (state.mode == 1) and 2 or 1
            hud.refresh()
            view.setRefVisible(state.mode == 1)
        end,
        onChapter = switchChapter,
    })
    view.setActions({ onPress = function(idx) pressCell(idx) end })

    state.mode = config.DEFAULT_MODE or 1
    state.chapterIndex = 1
    state.slotDone = { false, false, false, false }
    state.slotStars = { 0, 0, 0, 0 }

    finaleRoot = nil
    startPiece(1, true)
    hud.setVisible(true)
    hud.refresh()

    bindKeys(root)

    if getParamNumber("autoStart", 0) > 0 then
        state.inputReady = true
        startPiece(1)
    end
    devAutoPress = getParamNumber("autoPress", -1)
    devSolve = getParamNumber("autoSolve", 0) > 0
    devAt = 1.0
end


function OnUpdate(dt)
    if not dt or dt <= 0 then return end
    if dt > 0.05 then dt = 0.05 end
    state.lastDt = dt

    anim.update(dt)
    view.update(dt)
    fx.update(dt)
    fadeScreen.update(dt)

    -- 开发用：按 A 自动解题，用来把 4 块跑穿、验证通关演出
    if devSolve and state.phase == "play" and state.inputReady and state.pieceOpen then
        local rest = board.remaining(state.aSet, state.history)
        if #rest > 0 then pressCell(rest[1]) end
    end

    if devAutoPress >= 0 then
        devAt = devAt - dt
        if devAt <= 0 and state.inputReady and state.phase == "play" then
            local p = devAutoPress
            devAutoPress = -1
            pressCell(p)
        end
    end
end

function OnDestroy()
    pcall(function() script:EnableUpdate(false) end)
end
