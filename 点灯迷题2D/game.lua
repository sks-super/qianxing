-- ================================================================
-- 点灯迷题 2D · 入口
-- ================================================================
-- 挂载位置：客户端控件容器的【容器节点】（script.object）。
--
-- 层级（从下到上）：
--   containerScene（承载整体缩放 k）
--   ├─ containerBg     背景与装饰光斑
--   ├─ containerBoard  棋盘根 ★ 通关时整体缩成「战利品照片」
--   │   ├─ containerBoardBg  底板 / 描边 / 30 个格位底
--   │   └─ containerTile     30 个灯格
--   ├─ containerFx     粒子 / 冲击波 / 飘字
--   ├─ containerHud    右侧信息栏
--   ├─ containerMenu   选关
--   ├─ containerWin    通关结算
--   └─ containerFade   黑幕（永远最顶）
--
-- 脚本参数：
--   rectPrefabId   ★必填  纯色矩形（图片控件）—— 一切色块的基础
--   textPrefabId   ★必填  文本框
--   cursorPrefabId ★必填  光标检测区域（没有它鼠标点不动）
--   flipAudioId / clickAudioId / openAudioId / winAudioId / starAudioId  可选
-- ================================================================

---@diagnostic disable: undefined-global

local state = require("default_import_file/state")
local config = require("default_import_file/config")
local utils = require("default_import_file/utils")
local anim = require("default_import_file/anim")
local board = require("default_import_file/board")
local view = require("default_import_file/view")
local fx = require("default_import_file/fx")
local hud = require("default_import_file/hud")
local menu = require("default_import_file/menu")
local winUI = require("default_import_file/winUI")
local fadeScreen = require("default_import_file/fadeScreen")
local audio = require("default_import_file/audio")
local signal = require("default_import_file/signal")

local TAG_TICK = "game:tick"

-- ★ 前置声明：这些函数互相引用（按钮回调在运行时才用），
--   必须先 local 声明、后面写 foo = function() 赋值（不能写 local function，会遮蔽）。
local setScreen, buildLevel, enterLevel, replayLevel, nextLevel
local backToSelect, openSelect, resumePlay, pressCell, flushPending, onCleared

-- 开发用自动点击（无头截图验证；正式不传 autoPress 就是 -1）
local devAutoPress = -1
local devAutoPressAt = 0

-- ================================================================
-- 脚本参数
--   ★ 刻意写成【全局函数】：沙箱模拟器的参数兜底是「在入口脚本末尾覆盖全局
--     getParamNumber」实现的（见 _tools/_sim_common.mjs）。写成 local 就覆盖不到，
--     本地试玩会一直报「请设置 rectPrefabId」。真机上全局多一个函数无副作用。
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
-- 层级容器
-- ================================================================
local function ensureContainers()
    local root = state.parent
    if not root then return false end

    if not state.containerScene then
        state.containerScene = utils.createContainer(root)
        if not state.containerScene then return false end
        utils.setScale(state.containerScene, state.k or 1)
    end
    local scene = state.containerScene

    if not state.containerBg then
        state.containerBg = utils.createContainer(scene)
    end
    if not state.containerBoard then
        state.containerBoard = utils.createContainer(scene)
        if state.containerBoard then
            utils.setPos(state.containerBoard, state.boardCX or 0, state.boardCY or 0)
        end
    end
    if not state.containerBoardBg then
        state.containerBoardBg = utils.createContainer(state.containerBoard)
        if state.containerBoardBg then utils.setPos(state.containerBoardBg, 0, 0) end
    end
    if not state.containerTile then
        state.containerTile = utils.createContainer(state.containerBoard)
        if state.containerTile then utils.setPos(state.containerTile, 0, 0) end
    end
    if state.containerTile then utils.raise(state.containerTile) end

    if not state.containerFx then state.containerFx = utils.createContainer(scene) end
    if not state.containerHud then state.containerHud = utils.createContainer(scene) end
    if not state.containerMenu then state.containerMenu = utils.createContainer(scene) end
    if not state.containerWin then state.containerWin = utils.createContainer(scene) end
    if not state.containerFade then state.containerFade = utils.createContainer(scene) end

    utils.applyLayerOrder({
        state.containerBg, state.containerBoard, state.containerFx,
        state.containerHud, state.containerMenu, state.containerWin, state.containerFade,
    })
    return true
end

-- ================================================================
-- 背景与标题
-- ================================================================
local function createBackground()
    local par = state.containerBg
    if not par or (state.rectPrefabId or 0) <= 0 then return end
    local pal = config.DEFAULT_PALETTE or {}

    -- 铺满（比设计画布大很多，宽屏也不露底）
    utils.createControl(state.rectPrefabId, 0, 0, 2400, 1400,
        utils.hexToColor(pal.bg or "0A0E1A"), par)

    -- 三块大光斑：低透明度 + 旋转，给纯色背景一点层次
    local blobs = {
        { -520, 300, 760, 760, pal.bgGlow or "14224A", 26, 18 },
        { 560, -260, 900, 900, pal.bgGlow2 or "2A1550", 22, -12 },
        { 120, 420, 620, 620, pal.bgGlow or "14224A", 14, 40 },
    }
    for i = 1, #blobs do
        local b = blobs[i]
        local c = utils.createControl(state.rectPrefabId, b[1], b[2], b[3], b[4],
            utils.hexToColorA(b[5], b[6]), par)
        if c then utils.setRotationZ(c, b[7]) end
    end

    -- 标题（左上，棋盘正上方）
    if (state.textPrefabId or 0) > 0 then
        local t = utils.createText(-410, 320, 420, 44, "点灯迷题",
            utils.hexToColor(pal.text or "E9F0FF"), 30, par, "left")
        utils.raise(t)
        local s = utils.createText(-410, 290, 420, 24, "LIGHTS OUT · 全灭即通关",
            utils.hexToColorA(pal.textDim or "8296B8", 190), 14, par, "left")
        utils.raise(s)
        local bar = utils.createControl(state.rectPrefabId, -566, 320, 4, 34,
            utils.hexToColor(pal.accent or "4CC9F0"), par)
        if bar then utils.raise(bar) end
    end
end

-- ================================================================
-- 切屏
-- ================================================================
setScreen = function(name)
    state.screen = name
    if name == "play" then
        menu.close()
        hud.setVisible(true)
        hud.restore()
        view.setVisible(true)
    else
        hud.setVisible(false)
        view.setVisible(true)
        menu.open()
    end
end

-- ================================================================
-- 装载关卡（重建盘面与视图）
--   silent = true 时不播入场动画（首屏在选关面板后面静默准备）
-- ================================================================
buildLevel = function(index, silent)
    local cfg = config.getLevel(index)
    if not cfg then return false end

    state.currentLevelIndex = index
    state.currentLevelConfig = cfg
    state.board = board.boardFromFlips(cfg.flips)
    state.moves = 0
    state.history = {}
    state.litCount = board.litCount(state.board)
    state.hintIndex = -1
    state.pendingPress = nil
    state.winOpen = false
    state.comboCount = 0
    state.lastPressAt = -99

    anim.clearAll()
    fx.clear()
    view.clearAnim()
    view.resetTransform()
    view.snapAll(state.board)
    hud.restore()
    hud.refresh(index, cfg, 0, state.litCount)

    if silent then
        state.inputReady = true
    else
        state.inputReady = false
        local d = view.spawnIn(state.board)
        anim.delay(d, function() state.inputReady = true end, TAG_TICK)
    end
    return true
end

-- ================================================================
-- 进入关卡（黑幕掩护下切屏 + 装载）
-- ================================================================
enterLevel = function(index)
    if not config.getLevel(index) then return false end
    winUI.close()
    fadeScreen.start({
        onPeak = function()
            state.screen = "play"
            menu.close()
            hud.setVisible(true)
            view.setVisible(true)
            buildLevel(index)
            audio.playOpen()
        end,
    })
    return true
end

replayLevel = function()
    if state.screen ~= "play" then return false end
    fadeScreen.start({
        onPeak = function()
            winUI.close()
            hud.setVisible(true)
            buildLevel(state.currentLevelIndex)
        end,
    })
    return true
end

nextLevel = function()
    local n = (state.currentLevelIndex or 0) + 1
    if not config.getLevel(n) then
        backToSelect()
        return false
    end
    return enterLevel(n)
end

backToSelect = function()
    winUI.close()
    fadeScreen.start({
        onPeak = function()
            state.screen = "select"
            hud.setVisible(false)
            view.setVisible(true)
            menu.open()
        end,
    })
    return true
end

openSelect = function()
    if state.winOpen then return false end
    state.screen = "select"
    state.inputReady = false
    hud.setVisible(false)
    menu.open()
    return true
end

resumePlay = function()
    if state.winOpen then return false end
    menu.close()
    state.screen = "play"
    hud.setVisible(true)
    hud.restore()
    state.inputReady = true
    return true
end

-- ================================================================
-- 通关
-- ================================================================
onCleared = function()
    if state.winOpen then return false end
    state.winOpen = true
    state.inputReady = false
    state.pendingPress = nil

    local index = state.currentLevelIndex
    local cfg = state.currentLevelConfig or {}
    local best = math.floor(tonumber(cfg.steps) or 0)
    local stars = config.starsFor(index, state.moves)

    -- 记录（只升不降）
    local prev = state.cleared[index]
    if not prev or (stars > (prev.stars or 0)) then
        state.cleared[index] = { stars = stars, steps = state.moves }
    end
    if index > (state.maxCleared or 0) then state.maxCleared = index end

    audio.playWin()
    fx.confetti()
    if signal.enabled() then signal.reportWin(index, state.moves) end

    -- ① 一道光斜扫过棋盘 → ② 棋盘缩成照片飞走 → ③ 结果卡滑入
    view.celebrate(function()
        hud.fadeOut()
        view.toPhoto()
        anim.delay(0.30, function()
            winUI.open(index, { stars = stars, moves = state.moves, best = best })
            for i = 1, math.min(3, stars) do
                anim.delay(0.30 + (i - 1) * (config.DEFAULT_WIN_STAR_DELAY or 0.13), function()
                    audio.playStar()
                end, TAG_TICK)
            end
        end, TAG_TICK)
    end)
    return true
end

-- ================================================================
-- 按一格
-- ================================================================
flushPending = function()
    local p = state.pendingPress
    if p == nil then return end
    state.pendingPress = nil
    if state.inputReady and state.screen == "play" and not state.winOpen then
        pressCell(p)
    end
end

pressCell = function(idx)
    if state.screen ~= "play" or state.winOpen then return false end
    if not board.valid(idx) then return false end
    if not state.inputReady then
        if (config.DEFAULT_INPUT_BUFFER or 1) ~= 0 then state.pendingPress = idx end
        return false
    end
    if not state.currentLevelConfig then return false end

    -- 连击判定（快按快翻，手感更「跟手」）
    local now = state.time
    local combo = (now - (state.lastPressAt or -99)) <= (config.DEFAULT_COMBO_WINDOW or 0.62)
    state.lastPressAt = now
    if combo then state.comboCount = (state.comboCount or 0) + 1
    else state.comboCount = 0 end

    -- ① 逻辑先行（视图随后追）
    -- ★ 先把翻转前的盘面复制一份交给视图：翻牌的「起始色」必须来自它，
    --   否则视图会拿新盘面当起点，5 格灯「瞬间变色」而不翻牌。
    local prev = {}
    for i = 1, #state.board do prev[i] = state.board[i] end

    board.press(state.board, idx)
    state.moves = state.moves + 1
    state.history[#state.history + 1] = idx
    state.litCount = board.litCount(state.board)

    -- ② 视图动效
    local speed = combo and (config.DEFAULT_COMBO_FAST or 0.72) or 1
    local dur = view.playPress(idx, state.board, {
        prev = prev,
        speed = speed,
        shake = (state.litCount == 0) and 1 or 0,
    })
    audio.playFlip()

    -- ③ HUD
    hud.setMoves(state.moves)
    hud.popMoves()
    hud.setLit(state.litCount)
    hud.popLit()
    hud.setHoverState(state.moves, state.litCount)

    -- ④ 锁输入 + 解锁 + 看门狗
    state.inputReady = false
    anim.delay(dur, function()
        state.inputReady = true
        flushPending()
    end, TAG_TICK)
    anim.delay(dur + (config.DEFAULT_SETTLE_GUARD or 0.55), function()
        if not state.inputReady and not state.winOpen then
            state.inputReady = true
            flushPending()
        end
    end, TAG_TICK)

    -- ⑤ 判定
    if state.litCount == 0 then
        anim.delay(dur + 0.06, function() onCleared() end, TAG_TICK)
    end
    return true
end

-- ================================================================
-- 撤销 / 提示
-- ================================================================
local function undo()
    if state.screen ~= "play" or state.winOpen then return false end
    if (config.DEFAULT_UNDO_ENABLED or 1) == 0 then return false end
    if not state.inputReady then return false end
    local n = #state.history
    if n < 1 then return false end

    local idx = state.history[n]
    state.history[n] = nil
    -- 按压是对合：再按一次即回退
    local prev = {}
    for i = 1, #state.board do prev[i] = state.board[i] end
    board.press(state.board, idx)
    state.moves = math.max(0, state.moves - 1)
    state.litCount = board.litCount(state.board)

    local dur = view.playPress(idx, state.board, {
        prev = prev, speed = 0.85, ringHex = "B388FF",
    })
    audio.playClick()
    hud.setMoves(state.moves)
    hud.popMoves()
    hud.setLit(state.litCount)
    hud.popLit()
    hud.setHoverState(state.moves, state.litCount)

    state.inputReady = false
    anim.delay(dur, function()
        state.inputReady = true
        flushPending()
    end, TAG_TICK)
    return true
end

local function showHint()
    if state.screen ~= "play" or state.winOpen then return false end
    if (config.DEFAULT_HINT_ENABLED or 1) == 0 then return false end
    local cfg = state.currentLevelConfig
    if not cfg then return false end
    local idx = board.hintCell(cfg.flips, state.history)
    if idx < 0 then return false end
    view.showHint(idx)
    audio.playClick()
    return true
end

-- ================================================================
-- 键盘
-- ================================================================
local function bindKeys(root)
    local K = Enum.KeyEventType
    local function bind(evt, fn)
        pcall(function()
            root:AddKeyEventListener(evt, function()
                return fn() == true
            end)
        end)
    end

    -- 空格 / 前进键：结算下一关
    local function confirm()
        if winUI.isOpen() then
            nextLevel()
            return true
        end
        return false
    end
    bind(K.KeyboardJumpKeyDown, confirm)
    bind(K.KeyboardMoveForwardKeyDown, confirm)

    -- R：重玩
    bind(K.KeyboardCharacterSkill3KeyDown, function()
        if state.screen == "play" then return replayLevel() end
        return false
    end)

    -- T：提示
    bind(K.KeyboardCharacterSkill4KeyDown, function()
        return showHint()
    end)

    -- L：返回选关
    bind(K.KeyboardCraftspersonKey21Down, function()
        if state.screen == "play" and not state.winOpen then return openSelect() end
        return false
    end)

    -- ← →：选关翻页（游玩中不消费）
    bind(K.KeyboardMoveLeftKeyDown, function()
        if state.screen == "select" then menu.turn(-1); return true end
        return false
    end)
    bind(K.KeyboardMoveRightKeyDown, function()
        if state.screen == "select" then menu.turn(1); return true end
        return false
    end)

    -- S：撤销
    bind(K.KeyboardMoveBackwardKeyDown, function()
        return undo()
    end)
end

-- ================================================================
-- 生命周期
-- ================================================================
function OnStart()
    local root = script.object
    if not root then
        printerr("错误：script.object 为 nil，请把 game.lua 挂到【客户端控件容器】的容器节点上")
        return
    end
    state.parent = root

    state.rectPrefabId = getParamNumber("rectPrefabId", 0)
    if state.rectPrefabId <= 0 then
        printerr("错误：请设置脚本参数 rectPrefabId（纯色矩形 / 图片控件元件）")
        return
    end
    state.textPrefabId = getParamNumber("textPrefabId", 0)
    state.cursorPrefabId = getParamNumber("cursorPrefabId", 0)
    if state.textPrefabId <= 0 then
        printerr("警告：未配置 textPrefabId —— 所有文字都不会显示")
    end
    if state.cursorPrefabId <= 0 then
        printerr("警告：未配置 cursorPrefabId（光标检测区域）—— 键盘仍可操作，但鼠标点不动")
    end

    script:EnableUpdate(true)

    state.clickAudioId = getParamNumber("clickAudioId", 0)
    state.openAudioId = getParamNumber("openAudioId", 0)
    state.winAudioId = getParamNumber("winAudioId", 0)
    state.starAudioId = getParamNumber("starAudioId", 0)
    local flipAudioId = getParamNumber("flipAudioId", 0)
    audio.init({
        click = state.clickAudioId,
        open = state.openAudioId,
        win = state.winAudioId,
        star = state.starAudioId,
        flip = flipAudioId,
    })
    audio.prewarm()

    -- 画布
    local okSize, w, h = pcall(function() return game.GetUICanvasSize() end)
    if okSize and type(w) == "number" and w > 0 then state.canvasW = w
    else state.canvasW = config.DEFAULT_VIEW_WIDTH end
    if okSize and type(h) == "number" and h > 0 then state.canvasH = h
    else state.canvasH = config.DEFAULT_VIEW_HEIGHT end

    local layout = utils.computeLayout()
    state.designW = config.DEFAULT_DESIGN_WIDTH
    state.designH = config.DEFAULT_DESIGN_HEIGHT

    if not ensureContainers() then
        printerr("错误：层级容器创建失败（检查 rectPrefabId 是否为可实例化的客户端控件）")
        return
    end
    fadeScreen.init()

    createBackground()

    if not view.init() then
        printerr("警告：棋盘初始化失败（rectPrefabId / 容器异常）")
    end
    if not hud.init() then
        printerr("警告：信息栏初始化失败")
    end
    if not menu.init() then
        printerr("警告：选关界面初始化失败")
    end
    if not winUI.init() then
        printerr("警告：结算界面初始化失败")
    end

    -- 回调注入（避免模块反向 require 造成循环依赖）
    hud.setActions({
        onHint = showHint,
        onUndo = undo,
        onReset = replayLevel,
        onSelect = openSelect,
    })
    menu.setActions({
        onPick = function(idx) enterLevel(idx) end,
        onClose = resumePlay,
    })
    winUI.setActions({
        onReplay = replayLevel,
        onNext = nextLevel,
        onSelect = backToSelect,
    })
    view.setActions({
        onPress = function(idx) pressCell(idx) end,
    })

    state.deviceIsTouch = (state.cursorPrefabId or 0) > 0
    bindKeys(root)

    -- 进度（可选：服务端变量存在才读得到）
    local saved = signal.parseProgress(signal.readProgressString())
    if next(saved) ~= nil then state.cleared = saved end
    local maxC = 0
    for idx in pairs(state.cleared) do
        if idx > maxC then maxC = idx end
    end
    state.maxCleared = maxC

    -- 首屏：先在选关面板后面静默备好第 1 关
    buildLevel(1, true)
    state.screen = "select"
    hud.setVisible(false)
    view.setVisible(true)
    menu.open()

    -- 开发开关：autoStart=1 时直接进第 1 关（无头截图 / 冒烟测试用；正式不传）
    if getParamNumber("autoStart", 0) > 0 then
        state.screen = "play"
        hud.setVisible(true)
        enterLevel(1)
    end

    -- 开发开关：autoPress=<格子下标 0 基> 时自动按一格（验证翻牌与通关链路）
    -- ★ 不用 anim.delay 注册：进关时 buildLevel 会 clearAll()，把这条补间一起清掉。
    --   改由 OnUpdate 按时间触发，天然免疫。
    devAutoPress = getParamNumber("autoPress", -1)
    devAutoPressAt = 1.40

    if (layout and layout.k or 1) < 1 then
        -- 极窄的画布只提示一次，不阻断
        print("[点灯迷题2D] 自适应缩放 k = " .. tostring(layout.k))
    end
end

-- ================================================================
-- 每帧
-- ================================================================
function OnUpdate(dt)
    if not dt or dt <= 0 then return end
    if dt > 0.05 then dt = 0.05 end
    state.lastDt = dt

    anim.update(dt)
    view.update(dt)
    fx.update(dt)
    fadeScreen.update(dt)

    -- 开发用自动点击（无头截图验证翻牌 / 通关；正式不触发）
    if devAutoPress >= 0 then
        devAutoPressAt = devAutoPressAt - dt
        if devAutoPressAt <= 0 and state.inputReady and state.screen == "play"
           and not state.winOpen then
            local p = devAutoPress
            devAutoPress = -1
            pressCell(p)
        end
    end
end

function OnDestroy()
    pcall(function() script:EnableUpdate(false) end)
end
