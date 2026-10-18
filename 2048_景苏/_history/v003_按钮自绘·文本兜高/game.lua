-- ================================================================
-- 2048 · 主脚本（千星奇域 客户端控件 + Lua 客户端脚本）
--
--   玩法：4×4 棋盘，方向操作合并同数字，撞出 2048。
--   架构（沿用本工作台的分层约定）：
--     config/state/utils  参数真源 · 状态集中 · 无副作用工具
--     board  纯数据逻辑（不碰控件）        view   棋盘视图与移动动效
--     fx     粒子与飘字                    anim   逐帧补间引擎
--     hud    分数/方向键/功能按钮          menu   结算「拍照」展示
--     input  键盘 / 点击 / 滑动            audio  音效
--     signal 与服务端通信 + 最高分持久化   fadeScreen 黑幕过渡
--
--   ★ 层级（从下到上）：
--     bg → board(底板→方块) → fx → hud → menu → fade
--     结算时 menu 会把 board 临时抬到 menu 之上（黑幕仍在最顶），
--     让整块棋盘变成「相片」；关闭结算时按同一张表还原。
-- ================================================================

---@diagnostic disable: undefined-global

local config = require("default_import_file/config")
local state = require("default_import_file/state")
local utils = require("default_import_file/utils")
local anim = require("default_import_file/anim")
local board = require("default_import_file/board")
local view = require("default_import_file/view")
local fx = require("default_import_file/fx")
local hud = require("default_import_file/hud")
local menu = require("default_import_file/menu")
local input = require("default_import_file/input")
local audio = require("default_import_file/audio")
local signal = require("default_import_file/signal")
local fadeScreen = require("default_import_file/fadeScreen")

-- ================================================================
-- ★ 前置声明：doReset / restart 互相引用（结算面板的按钮回调在运行时才用），
--   必须先 local 声明、在实现处写【赋值】形式。
--   写成 local function 会新建一个 local 遮蔽这里的声明，闭包只会拿到 nil。
-- ================================================================
local doReset
local restart
local onDir

-- ================================================================
-- 工具：读脚本参数（数字）
-- ================================================================
local function getParamNumber(name, default)
    local v = script:GetParam(name)
    if type(v) == "number" then return v end
    if type(v) == "string" then
        local n = tonumber(v)
        if n then return n end
    end
    return default
end

-- 工具：当前设备是否触屏（触屏靠屏幕上的方向键 + 滑动操作）
local function detectTouchDevice()
    local ok, dev = pcall(function() return game.GetDevice() end)
    if not ok then return false end
    return dev == Enum.Device.Mobile or dev == Enum.Device.MobileController
end

-- ================================================================
-- ★ 层级容器
-- ================================================================
local function createContainer(parent)
    return utils.createContainer(parent)
end

local function ensureContainers()
    local root = state.parent
    if not root then return false end

    -- ⓪ 设计空间根：承载自适应缩放 k。
    --    ★ 挂在它身上而不是逐个控件上 —— 于是下面所有子控件都能
    --      直接写「设计坐标」（1280×720 基准），PC / 手机共用一套排版。
    --    ★ 背景与黑幕都是 4000×4000 的居中矩形，缩放后依然铺满画布。
    if not state.containerScene then
        state.containerScene = createContainer(root)
        if not state.containerScene then return false end
        utils.setScale(state.containerScene, state.k or 1)
    end
    local scene = state.containerScene

    -- 第一层：按【物品种类】分
    if not state.containerBg     then state.containerBg     = createContainer(scene) end
    if not state.containerBoard  then state.containerBoard  = createContainer(scene) end
    if not state.containerFx     then state.containerFx     = createContainer(scene) end
    if not state.containerHud    then state.containerHud    = createContainer(scene) end
    if not state.containerMenu   then state.containerMenu   = createContainer(scene) end
    if not state.containerFade   then state.containerFade   = createContainer(scene) end

    -- 第二层：棋盘内部再分「底板 / 方块」。
    -- ★ 它们必须待在【棋盘根的局部原点 (0,0)】上：
    --   子控件坐标 = utils.cellCenter() 的返回值（也以棋盘中心为原点），
    --   于是 containerBoard 的轴心正好落在棋盘中心 ——
    --   结算时对它整体 SetLocalScale / SetLocalRotation 才不会跑偏。
    --   ★ 棋盘的中心只由 containerBoard 自己的 anchoredPosition 表达，
    --     千万不要在子容器上再设一次（会叠加成两倍偏移）。
    if not state.containerBoardBg then
        state.containerBoardBg = createContainer(state.containerBoard)
    end
    if not state.containerTile then
        state.containerTile = createContainer(state.containerBoard)
    end
    for _, c in ipairs({ state.containerBoardBg, state.containerTile }) do
        if c then utils.setPos(c, 0, 0) end
    end
    -- ★ 方块必须压在底板上：SetAsLastSibling 是唯一在两引擎里效果一致的提层手段
    utils.raise(state.containerTile)

    local root0 = state.containerBoard
    if root0 then
        utils.setPos(root0, state.boardCX or 0, state.boardCY or 0)
        utils.setScale(root0, 1)
        utils.setRotationZ(root0, 0)
    end

    menu.layersPlay()
    return state.containerBg ~= nil and state.containerBoard ~= nil
end

-- ================================================================
-- ★ 背景（铺满画布的纯色 —— 本作画面全部是 UI，不需要看 3D 场景）
-- ================================================================
local function createBackground()
    if state.bgCtrl then return end
    if not state.containerBg then return end
    state.bgCtrl = utils.createControl(state.rectPrefabId, 0, 0, 4000, 4000,
        utils.hexToColor(utils.pal("bg", "FAF8EF")), state.containerBg)
end

-- ================================================================
-- ★ 最高分
-- ================================================================
local function syncBestFromServer()
    local v = signal.readHighScore()
    if v and v > (state.best or 0) then
        state.best = v
        state.highScoreLoaded = true
        state.highScoreSent = v        -- 已经落库过，不必再上报一次
        hud.setBest(v, false)
    elseif v then
        state.highScoreLoaded = true
        state.highScoreSent = math.max(state.highScoreSent or 0, v)
    end
end

local function maybeSendHighScore()
    if (config.DEFAULT_HIGHSCORE_SYNC or 1) == 0 then return end
    local best = math.floor(state.best or 0)
    if best > (state.highScoreSent or 0) then
        signal.sendHighScore(best)
        state.highScoreSent = best
    end
end

-- ================================================================
-- ★ 开局 / 重开
--   animated = true 时方块逐个「弹」出来
-- ================================================================
doReset = function(animated)
    if state.menuOpen then menu.close() end
    anim.clearAll()
    fx.clear()
    input.reset()

    state.animating = false
    state.lockTimer = 0
    state.keysEnabled = true
    state.phase = "playing"

    board.reset()                 -- 一并复位 won / winHandled / dead / deadHandled
    view.resetBoardTransform()

    hud.setScore(0, false)
    hud.setBest(state.best or 0, false)
    if animated then
        view.syncWithPop()
    else
        view.syncInstant()
    end
    hud.refresh()
end

restart = function()
    if state.pendingRestart then return end
    state.pendingRestart = true
    audio.playClick()
    signal.send("重新开始")
    fadeScreen.start({
        onPeak = function()
            state.pendingRestart = false
            doReset(true)
        end,
    })
end

-- ================================================================
-- ★ 撤销一步（结算面板里也能用：无路可走时的「后悔药」）
-- ================================================================
local function undo()
    if not board.canUndo() then
        hud.toast("没有可以撤销的步骤了")
        hud.refresh()
        return
    end
    if state.menuOpen then menu.close() end

    anim.clearAll()
    fx.clear()
    state.animating = false
    state.lockTimer = 0
    state.phase = "playing"
    state.keysEnabled = true

    board.undo()

    -- 撤销之后，胜负判定都要重新放开
    state.dead = false
    state.deadHandled = false
    local winValue = config.DEFAULT_WIN_VALUE or 2048
    local reachWin = (state.maxReached or 0) >= winValue
    state.won = reachWin
    state.winHandled = reachWin

    view.resetBoardTransform()
    view.syncWithPop()
    hud.setScore(state.score, false)
    hud.refresh()
    audio.playUndo()
    hud.toast("已撤销一步")
    signal.send("撤销一步")
end

-- ================================================================
-- ★ 胜利后继续游戏
-- ================================================================
local function continueGame()
    if not state.menuOpen or state.menuMode ~= "win" then return end
    if (config.DEFAULT_CONTINUE_AFTER_WIN or 1) == 0 then return end
    state.winHandled = true          -- 同一局不再重复弹胜利结算
    menu.close()
    hud.refresh()
    hud.toast("继续挑战更大的方块", 2.2)
    signal.send("继续游戏")
end

-- ================================================================
-- ★ 落子
-- ================================================================
local function checkEnd()
    if state.phase ~= "playing" then return end

    local winValue = config.DEFAULT_WIN_VALUE or 2048
    if not state.won and (state.maxReached or 0) >= winValue then
        state.won = true
        state.winHandled = true
        audio.playWin()
        signal.send("达成2048")
        hud.toast("达成 " .. tostring(winValue) .. " ！", 2.4)
        -- 让玩家先看清那一下合并的粒子与数字，再「拍照」
        if (config.DEFAULT_AUTO_SETTLE or 1) ~= 0 then
            anim.delay(0.45, function()
                if state.won and state.phase == "playing" and not state.menuOpen then
                    menu.open("win")
                end
            end)
        end
        return
    end

    if not state.dead and not board.canMoveAny() then
        state.dead = true
        state.deadHandled = true
        audio.playFail()
        signal.send("游戏失败")
        hud.toast("无路可走了", 2.4)
        if (config.DEFAULT_AUTO_SETTLE or 1) ~= 0 then
            anim.delay(0.45, function()
                if state.dead and state.phase == "playing" and not state.menuOpen then
                    menu.open("dead")
                end
            end)
        end
    end
end

local function onActionDone()
    -- 动画结束后再额外锁一小会儿，防「连点两次方向键」把两次移动叠在一起
    state.lockTimer = config.DEFAULT_ANIM_INPUT_LOCK_EXTRA or 0.03
    hud.refresh()
    checkEnd()
end

local function doMove(dir)
    if state.phase ~= "playing" then return end
    if state.animating or (state.lockTimer or 0) > 0 then return end

    local action = board.tryMove(dir)
    if not action then
        -- 这个方向纹丝不动：不扣分、不生成新块，给个轻微提示即可
        hud.toast("这个方向动不了")
        return
    end

    audio.playAction(action)

    -- 最高分
    if state.score > (state.best or 0) then
        state.best = state.score
        hud.setBest(state.best, true)
        maybeSendHighScore()
    end

    hud.setScore(action.scoreAfter, true)
    hud.refresh()
    view.playAction(action, onActionDone)
end

onDir = function(dir)
    if not state.keysEnabled then return end
    if state.phase ~= "playing" then return end
    if state.animating or (state.lockTimer or 0) > 0 then return end
    doMove(dir)
end

local function onButton(action)
    if action == "restart" then
        restart()
    elseif action == "undo" then
        if state.phase == "playing" or state.menuOpen then undo() end
    elseif action == "continue" then
        continueGame()
    end
end

-- ================================================================
-- ★ 生命周期
-- ================================================================
function OnStart()
    local root = script.object
    if not root then
        printerr("错误：script.object 为 nil，请确认本脚本挂在【客户端控件容器】的容器节点上")
        return
    end
    state.parent = root

    -- ★ 元件模板
    state.rectPrefabId = getParamNumber("rectPrefabId", 0)
    if state.rectPrefabId <= 0 then
        printerr("错误：请设置脚本参数 rectPrefabId（纯色矩形底图元件）")
        return
    end
    state.textPrefabId = getParamNumber("textPrefabId", 0)
    if state.textPrefabId <= 0 then
        printerr("错误：请设置脚本参数 textPrefabId（文本框元件）")
        return
    end
    state.cursorPrefabId = getParamNumber("cursorPrefabId", 0)
    state.buttonPrefabId = getParamNumber("buttonPrefabId", 0)
    -- ★ 按钮外观由脚本自绘（图片底 + 文本），只把「点击」交给光标检测区域。
    --   所以真正必须配的是 cursorPrefabId；buttonPrefabId 可以不填。
    --   两者都没有时，命中区会退化成图片控件 —— 图片控件没有光标事件能力，
    --   表现为「按钮画得出来但点不动」。
    if state.cursorPrefabId <= 0 and state.buttonPrefabId <= 0 then
        printerr("错误：请设置脚本参数 cursorPrefabId（光标检测区域元件），否则方向键与功能按钮无法点击")
    end

    -- ★ 先启用 OnUpdate：补间引擎与输入监听都依赖脚本更新被引擎驱动
    script:EnableUpdate(true)

    -- ★ 音效
    state.moveAudioId  = getParamNumber("moveAudioId", 0)
    state.mergeAudioId = getParamNumber("mergeAudioId", 0)
    state.spawnAudioId = getParamNumber("spawnAudioId", 0)
    state.undoAudioId  = getParamNumber("undoAudioId", 0)
    state.winAudioId   = getParamNumber("winAudioId", 0)
    state.failAudioId  = getParamNumber("failAudioId", 0)
    state.clickAudioId = getParamNumber("clickAudioId", 0)
    audio.init({
        move  = state.moveAudioId,
        merge = state.mergeAudioId,
        spawn = state.spawnAudioId,
        undo  = state.undoAudioId,
        win   = state.winAudioId,
        fail  = state.failAudioId,
        click = state.clickAudioId,
    })
    audio.prewarm()

    -- ★ 画布与自适应布局
    local okSize, w, h = pcall(function() return game.GetUICanvasSize() end)
    if okSize and type(w) == "number" and w > 0 then state.canvasW = w else state.canvasW = config.DEFAULT_VIEW_WIDTH end
    if okSize and type(h) == "number" and h > 0 then state.canvasH = h else state.canvasH = config.DEFAULT_VIEW_HEIGHT end
    utils.computeLayout()

    -- ★ 层级容器 → 背景 → 棋盘 → HUD → 结算 → 黑幕 → 输入
    if not ensureContainers() then
        printerr("错误：层级容器创建失败（rectPrefabId 是否有效？）")
        return
    end
    createBackground()
    if not view.init() then
        printerr("警告：棋盘底板创建失败")
    end
    if not hud.init() then
        printerr("警告：HUD 创建失败（分数 / 方向键可能不可见）")
    end
    if not menu.init() then
        printerr("警告：结算面板创建失败（胜负结算将不可用）")
    end
    fadeScreen.init()

    -- ★ 回调注入（用注入而非让子模块反向 require game，避免循环依赖）
    hud.actions = {
        onDir = function(dir) onDir(dir) end,
        onButton = function(name) onButton(name) end,
    }
    input.actions = {
        onDir = onDir,
        onRestart = function() restart() end,
        onUndo = function() undo() end,
        onContinue = function() continueGame() end,
    }
    menu.actions = {
        restart = function() restart() end,
        undo = function() if board.canUndo() then undo() else hud.toast("没有可以撤销的步骤了") end end,
        continue = function() continueGame() end,
    }

    state.deviceIsTouch = detectTouchDevice()
    if not input.init() then
        printerr("警告：输入初始化失败")
    end

    -- ★ 最高分：先从服务器读一次，之后再监听变量变化
    syncBestFromServer()
    signal.watchHighScore(function(v)
        if v > (state.best or 0) then
            state.best = v
            hud.setBest(v, true)
        end
    end)

    -- ★ 服务器要求重开
    if not signal.register("进入游戏", function() restart() end) then
        printerr("警告：注册服务器信号监听失败: 进入游戏")
    end

    state.ready = true
    signal.send("开始游戏")

    -- ★ 首局：黑幕掩护下建盘，方块逐个弹出
    doReset(false)
    fadeScreen.start({
        onPeak = function()
            view.syncWithPop()
        end,
    })
end

-- ================================================================
-- ★ 每帧更新
--   ★ 顺序有讲究：补间 → 特效 → HUD → 黑幕。
--     结算动画必须继续跑，所以这里【不】因 paused 提前 return。
-- ================================================================
function OnUpdate(dt)
    if dt > 0.05 then dt = 0.05 end
    if dt <= 0 then return end
    state.lastDt = dt

    if (state.lockTimer or 0) > 0 then
        state.lockTimer = state.lockTimer - dt
        if state.lockTimer < 0 then state.lockTimer = 0 end
    end

    anim.update(dt)
    fx.update(dt)
    hud.update(dt)
    fadeScreen.update(dt)
end

function OnDestroy()
    -- 控件随容器一并回收，这里无需额外清理
end
