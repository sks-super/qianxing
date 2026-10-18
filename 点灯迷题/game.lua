-- ================================================================
-- 点灯迷题（Lights Out）主脚本
-- ================================================================
-- 分工：3D 棋盘与玩法在服务器节点图里，本脚本只负责客户端 UI：
--   选关界面 → 发「进入关卡」信号 → 游玩期极简 HUD → 等服务器「关卡胜利」→ 结算面板
--
-- 架构沿用本工程既有分层约定（与 TickHop 同构）：
--   · config.lua 是参数唯一真源；state.lua 集中托管全部状态；
--   · 容器化父节点管理层级（bg → hud → menu → win → tutorial → fx → fade）；
--   · ★ 每个图层**只用一个容器**，容器内的叠放完全由「创建顺序」决定
--     （真机渲染规则 = 后创建的在上），所以每个组件都按
--     「底图 → 文字 → 点击区域」的顺序创建，文字必然压在底图之上；
--   · ★ 所有可点击区域都用「光标检测区域」元件（cursorPrefabId）承接 ——
--     图片控件没有 AddCursorEventListener，绑在底图上真机点不动；
--   · 黑幕过渡掩护切屏；关卡切换以注入回调下发给各面板，避免循环依赖。
-- ================================================================

---@diagnostic disable: undefined-global

local config = require("default_import_file/config")
local state = require("default_import_file/state")
local utils = require("default_import_file/utils")
local puzzle = require("default_import_file/puzzle")
local audio = require("default_import_file/audio")
local signal = require("default_import_file/signal")
local fadeScreen = require("default_import_file/fadeScreen")
local fx = require("default_import_file/fx")
local bg = require("default_import_file/bg")
local menu = require("default_import_file/menu")
local tutorial = require("default_import_file/tutorial")
local hud = require("default_import_file/hud")
local winUI = require("default_import_file/winUI")

-- 供外部（模拟器探针 / 服务器）调用的便捷入口
_G.getLevelConfig = config.getLevelConfig
_G.getLevelCount = config.getLevelCount
-- 本地复算某关初始盘面（30 个 0/1，下标 1..30 对应 0 基 idx 0..29）：
-- 便于调试时和节点图摆出来的盘面对账。
_G.puzzleBoardOfLevel = function(index)
    return puzzle.boardFromFlips(config.getLevelFlips(index))
end

-- 前向声明：loadLevel 的 onPeak 闭包会引用 setScreen / enterLevel，
-- 必须先声明 local，实现处写成赋值形式（写 local function 会遮蔽前置声明）。
local setScreen
local enterLevel

-- ================================================================
-- ★ 创建透明容器父节点（定位于世界原点）
--   ★ 显式关掉遮罩：容器只用来分组，绝不能裁剪子控件。
--     底图预制体若带了 enableMask，而容器尺寸只有 1×1，子控件会被整片裁掉。
-- ================================================================
local function createContainer(parent)
    if not state.parent then return nil end
    if not state.rectPrefabId or state.rectPrefabId <= 0 then return nil end
    local ok, c = pcall(game.InstantiateClientUIControl, state.rectPrefabId, parent or state.parent)
    if not ok or not c then return nil end
    pcall(function()
        c:SetAnchorMin(0.5, 0.5)
        c:SetAnchorMax(0.5, 0.5)
        c:SetPivot(0.5, 0.5)
        c:SetAnchoredPosition(0, 0)
        c:SetSizeDelta(1, 1)
        c.imageColor = Color.FromRGBA(255, 255, 255, 0)   -- 容器自身透明
        c.enableMask = false                              -- ★ 不裁剪子控件
    end)
    c:SetActive(true)
    return c
end

-- ================================================================
-- ★ 层级结构（与 TickHop 完全一致的「容器节点分层模式」）
--   第一层（从下到上）：bg → hud → menu → win → tutorial → fx → fade
--   ★★ 没有第二层「图片组 / 文字组」子容器：一个图层就是一个容器，
--      容器内部完全靠**创建顺序**决定叠放（真机渲染规则 = 后创建的在上）。
--      于是每个组件只要按「底图 → 文字 → 点击区域」的顺序建，
--      文字就必然压在自己的底图之上，不依赖任何 SetAsLastSibling 之类的重排。
--      （旧版把图片和文字拆进两个兄弟子容器，整层文字是否被遮住取决于
--        这两个子容器谁在后面 —— 一旦不是预期顺序，文字会被同层底图与
--        全屏遮罩一起盖住，连点击也一并丢掉。）
-- ================================================================
local LAYER_ORDER = {
    "containerBg",        -- ① 夏日背景（天空 / 海 / 沙滩 / 波浪 / 气泡）
    "containerHud",       -- ② 游玩期极简 HUD
    "containerMenu",      -- ③ 选关界面
    "containerWin",       -- ④ 胜利结算（覆盖 HUD / 选关）
    "containerTutorial",  -- ⑤ 图文教程（覆盖一切面板）
    "containerFx",        -- ⑥ 果汁粒子（溅在所有面板之上）
    "containerFade",      -- ⑦ 黑幕过渡（最顶）
}

-- ================================================================
-- ★ 把容器层级摆正（幂等）
--   SetAsLastSibling() = 移到同级末位；按「从下到上」的顺序依次调用，
--   真机上净效果为空操作（创建顺序本就正确），模拟器渲染顺序相反时正好抵消。
-- ================================================================
local function raiseLayers()
    for _, key in ipairs(LAYER_ORDER) do
        local c = state[key]
        if c then pcall(function() c:SetAsLastSibling() end) end
    end
end

-- ================================================================
-- ★ UI 自适应放大系数
--   以 DEFAULT_VIEW_WIDTH × HEIGHT 为「设计基准」；画布更大时把**居中的面板层**
--   整层等比放大，免得在 1600×900 这类大画布上界面还是按 800×600 设计的大小，
--   四周留一大片空白（真机实测：画布约 1600×900，而面板只有 700 宽 → 面板仅占 44%）。
--   ★ 只放大 containerTutorial / containerWin 这两个**居中**的层：
--     · HUD 贴着画布边缘定位（坐标由画布尺寸算出），放大会把它推出屏幕；
--     · 选关层要在层内重排卡片，放大由 menu.lua 自己按 k 完成。
--   ★ 这两层里所有 fx.spawn 的坐标都要乘这个系数（粒子挂在未放大的 containerFx 上），
--     否则粒子会错位到面板的左上角 —— 各模块通过 utils.uiScale() 取用。
-- ================================================================
local function computeUiScale()
    local cw = state.canvasW or config.DEFAULT_VIEW_WIDTH or 800
    local ch = state.canvasH or config.DEFAULT_VIEW_HEIGHT or 600
    local bw = config.DEFAULT_VIEW_WIDTH or 800
    local bh = config.DEFAULT_VIEW_HEIGHT or 600
    local k = math.min(cw / bw, ch / bh)
    if k < 1 then k = 1 end        -- 小画布不缩小，避免内容挤成一团
    if k > 1.6 then k = 1.6 end    -- 上限：别把面板撑出画布
    return k
end

local function applyUiScale()
    state.uiScale = computeUiScale()
    for _, key in ipairs({ "containerTutorial", "containerWin" }) do
        local c = state[key]
        if c then pcall(function() c:SetLocalScale(state.uiScale, state.uiScale, 1) end) end
    end
end

-- ================================================================
-- ★ 检查 7 个图层容器，缺失的补建（创建顺序即显示层级）
-- ================================================================
local function ensureContainers()
    local okAll = true
    for _, key in ipairs(LAYER_ORDER) do
        if not state[key] then
            state[key] = createContainer()
            if not state[key] then okAll = false end
        end
    end
    raiseLayers()
    applyUiScale()
    return okAll
end

-- ================================================================
-- ★ 屏幕切换（选关 / 游玩）
--   tutorial 与 win 是「覆盖层」，不改 screen，只各自显隐。
-- ================================================================
setScreen = function(name)
    state.screen = name
    -- ★★ 游玩期必须收掉全屏夏日背景：它是盖满画布的**不透明**色块，
    --    不收就会把节点图摆出来的 3D 棋盘整片盖住（真机实测现象）。
    --    3D 场景本身就是游玩期的画面，客户端只留薄薄一层 HUD。
    bg.setVisible(name ~= "play")
    menu.setVisible(name == "select")
    hud.setVisible(name == "play")
    if name == "select" then menu.refresh() end
    raiseLayers()
end

-- ================================================================
-- ★ 进入关卡：黑幕掩护 → 切屏 → 发「进入关卡」信号
--   关卡号（1 起始）+ 点位序列（0 基下标数组）一起交给节点图。
-- ================================================================
enterLevel = function(levelIndex)
    local idx = math.floor(tonumber(levelIndex) or 0)
    local data = config.getLevelConfig(idx)
    if not data then return false end
    -- 进关前先收掉覆盖层，避免盖在新画面上
    tutorial.close()
    winUI.close()
    fadeScreen.start({
        onPeak = function()
            state.currentLevelIndex = idx
            state.currentLevelConfig = data
            state.hudHintOverride = ""
            setScreen("play")
            hud.setHint("正在加载关卡…")
            audio.playOpen()
            -- ★ 出站信号：关卡号 + 点位序列
            state.pendingEnterLevel = idx
            if not signal.sendEnterLevel(idx, config.getLevelFlips(idx)) then
                printerr("警告：「进入关卡」信号发送失败（关卡 " .. tostring(idx) .. "）")
            end
        end,
    })
    return true
end

-- ================================================================
-- ★ 返回选关
-- ================================================================
local function backToSelect()
    tutorial.close()
    winUI.close()
    fadeScreen.start({
        onPeak = function()
            state.hudHintOverride = ""
            setScreen("select")
        end,
    })
end

-- ================================================================
-- ★ 重玩本关：重发「重玩本关」信号让节点图重置棋盘
-- ================================================================
local function replayLevel()
    tutorial.close()
    winUI.close()
    local idx = state.currentLevelIndex or 1
    fadeScreen.start({
        onPeak = function()
            state.hudHintOverride = ""
            setScreen("play")
            hud.setHint("正在重置棋盘…")
            audio.playOpen()
            state.pendingEnterLevel = idx
            if not signal.sendReplayLevel(idx, config.getLevelFlips(idx)) then
                printerr("警告：「重玩本关」信号发送失败（关卡 " .. tostring(idx) .. "）")
            end
        end,
    })
end

-- ================================================================
-- ★ 下一关（结算面板用）
-- ================================================================
local function nextLevel()
    local n = (state.currentLevelIndex or 1) + 1
    if not config.getLevelConfig(n) then return false end
    return enterLevel(n)
end

-- ================================================================
-- ★ 教程开关
-- ================================================================
local function openTutorial()
    tutorial.open(1)
    state.tutorialSeen = true
    raiseLayers()
end

local function toggleTutorial()
    if tutorial.isOpen() then
        tutorial.close()
    else
        openTutorial()
    end
end

-- ================================================================
-- ★ 键盘绑定
--   按键分三档：
--     · 覆盖层键（教程 / 结算打开时）：优先接管
--     · 选关键（screen == "select"）：方向键选择、空格进入、T 教程
--     · 游玩键（screen == "play"）：只留 T 教程 / L 返回选关 / R 重玩本关
--   ★ 游玩期刻意不绑方向键与空格 —— 3D 场景那边可能也要用它们，
--     客户端 UI 只保留这三个「功能键」，避免和玩法抢输入。
--   ★★ 回调用「返回值」表示是否消费该按键：凡是本次不适用的键一律 return false，
--      这样游玩期按方向键不会被 UI 吞掉，能照常传给 3D 玩法。
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

    -- ---- 教程打开时：← ↑ 上一页，→ ↓ 下一页 ----
    local function tutPrev()
        if not tutorial.isOpen() then return false end
        tutorial.prev()
        return true
    end
    local function tutNext()
        if not tutorial.isOpen() then return false end
        tutorial.next()
        return true
    end
    bind(K.KeyboardMoveLeftKeyDown,       tutPrev)
    bind(K.KeyboardCraftspersonKey38Down, tutPrev)
    bind(K.KeyboardCraftspersonKey36Down, tutPrev)
    bind(K.KeyboardMoveRightKeyDown,      tutNext)
    bind(K.KeyboardCraftspersonKey39Down, tutNext)
    bind(K.KeyboardCraftspersonKey37Down, tutNext)

    -- ---- 空格 / W：确认（教程翻页 > 结算下一关 > 选关进入）----
    local function confirmKey()
        if tutorial.isOpen() then
            tutorial.next()
            return true
        end
        if winUI.isOpen() then
            winUI.confirmPrimary()
            return true
        end
        if state.screen == "select" then
            menu.confirm()
            return true
        end
        return false
    end
    bind(K.KeyboardJumpKeyDown,        confirmKey)
    bind(K.KeyboardMoveForwardKeyDown, confirmKey)

    -- ---- 选关界面：方向键移动（游玩期不消费，让给 3D 玩法）----
    local function moveKey(dx, dy)
        if tutorial.isOpen() or winUI.isOpen() then return false end
        if state.screen ~= "select" then return false end
        menu.moveCursor(dx, dy)
        return true
    end
    bind(K.KeyboardMoveLeftKeyDown,       function() return moveKey(-1, 0) end)
    bind(K.KeyboardCraftspersonKey38Down, function() return moveKey(-1, 0) end)
    bind(K.KeyboardMoveRightKeyDown,      function() return moveKey(1, 0) end)
    bind(K.KeyboardCraftspersonKey39Down, function() return moveKey(1, 0) end)
    bind(K.KeyboardMoveBackwardKeyDown,   function() return moveKey(0, -1) end)
    bind(K.KeyboardCraftspersonKey37Down, function() return moveKey(0, -1) end)
    bind(K.KeyboardCraftspersonKey36Down, function() return moveKey(0, 1) end)

    -- ---- T：教程开关（任何屏幕都可开关；已打开时点 T 关闭）----
    bind(K.KeyboardCharacterSkill4KeyDown, function()
        toggleTutorial()
        return true
    end)

    -- ---- R：重玩本关（游玩中或结算面板里）----
    bind(K.KeyboardCharacterSkill3KeyDown, function()
        if tutorial.isOpen() then return false end
        if winUI.isOpen() then
            winUI.doReplay()
            return true
        end
        if state.screen == "play" then
            replayLevel()
            return true
        end
        return false
    end)

    -- ---- L：返回选关 / 关闭教程 ----
    bind(K.KeyboardCraftspersonKey21Down, function()
        if tutorial.isOpen() then
            tutorial.close()
            return true
        end
        if winUI.isOpen() then
            winUI.doBack()
            return true
        end
        if state.screen == "play" then
            backToSelect()
            return true
        end
        return false
    end)
end

-- ================================================================
-- ★ 入站信号 ①：让客户端进入关卡
--   节点图把 3D 场景摆好后下发 → 客户端切到游玩画面并解除「加载中」提示。
-- ================================================================
local function onServerEnter(name, params)
    local idx = signal.getIntParam(params, 1)
    if idx and config.getLevelConfig(idx) then
        state.currentLevelIndex = idx
        state.currentLevelConfig = config.getLevelConfig(idx)
    end
    state.pendingEnterLevel = 0
    -- ★ 服务器已经把 3D 场景摆好、可以开始操作了：此时收掉教程等覆盖层，
    --   否则首次启动自动摊开的图文教程会挡住游玩 HUD（玩家仍可按 T 再唤出）。
    tutorial.close()
    winUI.close()
    setScreen("play")
    hud.setHint("")
    raiseLayers()
end

-- ================================================================
-- ★ 入站信号 ②：关卡胜利
--   3D 端判定全部熄灭 → 客户端记通关、放音效、弹结算（带动效）。
-- ================================================================
local function onServerWin(name, params)
    local idx = signal.getIntParam(params, 1)
    if not idx or not config.getLevelConfig(idx) then
        idx = state.currentLevelIndex
    end
    if not config.getLevelConfig(idx) then return end

    state.currentLevelIndex = idx
    state.currentLevelConfig = config.getLevelConfig(idx)
    state.pendingEnterLevel = 0
    menu.markCleared(idx)
    tutorial.close()
    audio.playWin()

    if (config.DEFAULT_WIN_AUTO_SHOW or 1) ~= 0 then
        setScreen("play")
        hud.setHint("")
        winUI.open(idx)
        raiseLayers()
    else
        hud.setHint("本关完成！按 L 返回选关")
    end
end

-- ================================================================
-- ★ 生命周期
-- ================================================================
function OnStart()
    local root = script.object
    if not root then
        printerr("错误：script.object 为 nil，请确认本脚本已挂载在【客户端控件容器】的容器节点上")
        return
    end
    state.parent = root

    -- ★ 矩形底图模板（必填）：面板 / 卡片 / 按钮 / 灯格 / 粒子全部用它染色
    state.rectPrefabId = getParamNumber("rectPrefabId", 0)
    if state.rectPrefabId <= 0 then
        printerr("错误：请设置脚本参数 rectPrefabId（纯色矩形底图元件）")
        return
    end
    -- ★ 文本模板（可选）：所有界面文字；缺省则只剩色块
    state.textPrefabId = getParamNumber("textPrefabId", 0)
    -- ★★ 点击区域模板（必填，否则鼠标点不动）：
    --   千星里只有「预设按钮 / 光标检测区域」带 AddCursorEventListener，
    --   图片控件没有这个方法，所以必须单独配一个「光标检测区域」元件。
    state.cursorPrefabId = getParamNumber("cursorPrefabId", 0)
    if state.cursorPrefabId <= 0 then
        printerr("警告：未配置 cursorPrefabId（光标检测区域元件）—— " ..
                 "键盘仍可操作，但鼠标点击全部无效。" ..
                 "请在沙箱里新增一个「光标检测区域」客户端控件，把它的元件索引填进本参数。")
    end

    -- ★ 先启用 OnUpdate：动效与黑幕过渡都依赖脚本更新被引擎驱动
    script:EnableUpdate(true)

    -- ★ 音效
    state.clickAudioId = getParamNumber("clickAudioId", 0)
    state.openAudioId  = getParamNumber("openAudioId", 0)
    state.winAudioId   = getParamNumber("winAudioId", 0)
    audio.init({
        click = state.clickAudioId,
        open  = state.openAudioId,
        win   = state.winAudioId,
    })
    audio.prewarm()

    -- ★ 画布尺寸与逻辑边界
    local okSize, w, h = pcall(function() return game.GetUICanvasSize() end)
    if okSize and type(w) == "number" and w > 0 then state.canvasW = w else state.canvasW = config.DEFAULT_VIEW_WIDTH end
    if okSize and type(h) == "number" and h > 0 then state.canvasH = h else state.canvasH = config.DEFAULT_VIEW_HEIGHT end
    state.LEFT   = -state.canvasW / 2
    state.RIGHT  = state.canvasW / 2
    state.BOTTOM = -state.canvasH / 2
    state.TOP    = state.canvasH / 2

    -- ★ 层级容器（一次性创建）+ 黑幕 + 夏日背景
    ensureContainers()
    fadeScreen.init()
    local pal = utils.resolvePalette(state.currentLevelConfig)
    bg.init(pal)
    fx.init(pal)

    -- ★ 各面板预创建
    if not menu.init() then
        printerr("警告：选关界面初始化失败")
    end
    if not hud.init() then
        printerr("警告：游玩 HUD 初始化失败")
    end
    if not tutorial.init() then
        printerr("警告：图文教程初始化失败")
    end
    if not winUI.init() then
        printerr("警告：胜利结算初始化失败")
    end

    -- ★ 用回调注入把「切屏 / 关卡切换」下发给各面板（避免反向 require 造成循环依赖）
    menu.setActions({
        onEnter    = function(idx) enterLevel(idx) end,
        onTutorial = function() openTutorial() end,
    })
    hud.setActions({
        onTutorial = function() openTutorial() end,
        onExit     = function() backToSelect() end,
    })
    winUI.setActions({
        onReplay       = function() replayLevel() end,
        onNext         = function() nextLevel() end,
        onBackToSelect = function() backToSelect() end,
    })

    -- ★ 输入设备
    state.deviceIsTouch = detectTouchDevice()

    -- ★ 键盘绑定
    bindKeys(root)

    -- ★ 注册服务器信号监听（入站）
    if not signal.register(signal.SIGNAL_SERVER_ENTER, onServerEnter) then
        printerr("错误：注册服务器信号监听失败: " .. signal.SIGNAL_SERVER_ENTER)
    end
    if not signal.register(signal.SIGNAL_SERVER_WIN, onServerWin) then
        printerr("错误：注册服务器信号监听失败: " .. signal.SIGNAL_SERVER_WIN)
    end

    -- ★ 首屏：选关；首次启动自动把图文教程摊开，介绍玩法
    setScreen("select")
    if (config.DEFAULT_TUTORIAL_AUTO_SHOW or 1) ~= 0 and not state.tutorialSeen then
        state.tutorialSeen = true
        tutorial.open(1)
        raiseLayers()
    end
end

-- ================================================================
-- ★ 每帧更新：推进各面板动效 / 粒子 / 背景气泡 / 黑幕过渡
--   （界面文字与配色都是事件驱动的静态刷新，不需要每帧重算）
-- ================================================================
function OnUpdate(dt)
    if dt > 0.05 then dt = 0.05 end
    state.lastDt = dt
    fx.update(dt)            -- 先跑全局时间，其余模块的动效都读 state.fxTime
    bg.update(dt)
    menu.update(dt)
    tutorial.update(dt)
    hud.update(dt)
    winUI.update(dt)
    fadeScreen.update(dt)
end

function OnDestroy()
    -- 引擎回收脚本时无需额外清理：控件随容器一并释放
end

-- ================================================================
-- ★ 工具：读取脚本参数（数字）
-- ================================================================
function getParamNumber(name, default)
    local v = script:GetParam(name)
    if type(v) == "number" then return v end
    if type(v) == "string" then
        local n = tonumber(v)
        if n then return n end
    end
    return default
end

-- ================================================================
-- ★ 工具：判断当前设备是否触屏
-- ================================================================
function detectTouchDevice()
    local ok, dev = pcall(function() return game.GetDevice() end)
    if not ok then return false end
    return dev == Enum.Device.Mobile or dev == Enum.Device.MobileController
end
