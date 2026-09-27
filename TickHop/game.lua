-- ================================================================
-- TickHop（滴答咔哒）主脚本
--   玩法内核：倒计时 + 计时平台 + 平台跳跃
--   架构沿用「割绳子」工程分层：容器化父节点管理层级，
--   黑幕过渡掩护关卡切换，模块各司其职、状态集中在 state.lua。
-- ================================================================

---@diagnostic disable: undefined-global

local config = require("config")
local state = require("state")
local utils = require("utils")
local timeSystem = require("timeSystem")
local level = require("level")
local physics = require("physics")
local audio = require("audio")
local signal = require("signal")
local fadeScreen = require("fadeScreen")
local menu = require("menu")

_G.getLevelConfig = config.getLevelConfig
_G.getLevelCount = config.getLevelCount

-- ================================================================
-- ★ 前置声明：loadLevel 的 onPeak 闭包会在运行时引用 doLoadLevel，
--   必须先在此声明 local；实现处写成赋值形式（不能写 local function，
--   否则会新建一个 local 遮蔽前置声明，闭包仍拿到 nil）。
-- ================================================================
local doLoadLevel

-- ================================================================
-- ★ 创建一个透明容器父节点（定位于世界原点，子节点坐标即世界坐标）
-- ================================================================
local function createContainer()
    if not state.parent then return nil end
    if not state.rectPrefabId or state.rectPrefabId <= 0 then return nil end
    local ok, c = pcall(game.InstantiateClientUIControl, state.rectPrefabId, state.parent)
    if not ok or not c then return nil end
    pcall(function()
        c:SetAnchorMin(0.5, 0.5)
        c:SetAnchorMax(0.5, 0.5)
        c:SetPivot(0.5, 0.5)
        c:SetAnchoredPosition(0, 0)   -- 容器定位于世界原点，子节点坐标即世界坐标
        c:SetSizeDelta(1, 1)          -- 自身不占可视面积
        c.imageColor = Color.FromRGBA(255, 255, 255, 0)  -- 透明
    end)
    c:SetActive(true)
    return c
end

-- ================================================================
-- ★ 检查 7 个层级容器，缺失的补建（创建顺序即显示层级，从下到上）
-- ================================================================
local function ensureContainers()
    local order = {
        "containerBg",        -- ① 背景
        "containerPlatform",  -- ② 计时平台 + 秒数标签
        "containerGoal",      -- ③ 终点门
        "containerPickup",    -- ④ 道具
        "containerPlayer",    -- ⑤ 玩家
        "containerHud",       -- ⑥ HUD（倒计时 / 提示 / 虚拟按钮）
        "containerMenu",      -- ⑦ 菜单 / 结算面板（覆盖 HUD，位于黑幕之下）
        "containerFade",      -- ⑧ 黑幕过渡（最顶）
    }
    local okAll = true
    for _, key in ipairs(order) do
        if not state[key] then
            state[key] = createContainer()
            if not state[key] then okAll = false end
        end
    end
    return okAll
end

-- ================================================================
-- ★ 加载指定关卡（1 起始）
-- ================================================================
function loadLevel(levelIndex)
    local idx = math.floor(tonumber(levelIndex) or 0)
    if idx < 1 then return false end
    local data = config.getLevelConfig(idx)
    if not data then return false end
    if not ensureContainers() then return false end

    -- ★ 进关前先收掉菜单 / 结算面板（否则会盖在新关卡上）
    menu.close()

    fadeScreen.start({
        onPeak = function()
            doLoadLevel(idx, data)
        end,
    })
    return true
end

-- ================================================================
-- ★ 实际关卡重建（黑幕渐显完成、渐隐开始前调用）
-- ================================================================
doLoadLevel = function(idx, data)
    state.currentLevelIndex = idx
    state.currentLevelConfig = data

    -- 重置结束状态与输入
    state.gameWon = false
    state.gameFailed = false
    state.failReason = nil
    state.failHandled = false
    state.winHandled = false
    state.keyLeft = false
    state.keyRight = false
    state.keyJump = false
    state.jumpBufferTimer = 0
    state.coyoteTimer = 0
    state.switchCooldown = 0
    state.landCooldown = 0
    state.winTimeLeft = 0
    -- ★ 面板可能是从结算态（gameWon/gameFailed 仍为 true）点「下一关 / 重玩」关掉的，
    --   那时 close() 不会恢复输入，所以这里必须显式复位暂停与输入开关。
    state.paused = false
    state.keysEnabled = true
    menu.close()

    -- 构建关卡可视对象
    if not level.build(data) then
        printerr("错误：关卡构建失败，index=" .. tostring(idx))
        return
    end

    -- 时间系统就位，并按当前秒数刷新平台实体状态
    timeSystem.reset(data.time or config.DEFAULT_TIME_LIMIT, config.DEFAULT_TIME_DIRECTION)
    level.refreshPlatforms()
    level.updateTimerDisplay()
    physics.syncVisualNow()
    utils.setMessage("")

    -- 黑幕尚未散尽，暂不开始计时；待过渡结束再启动，避免玩家看不到关卡就被扣时
    timeSystem.setRunning(false)
    state.pendingStart = true
end

-- ================================================================
-- ★ HUD：倒计时、消息文本
-- ================================================================
local function createHud()
    local cw = state.canvasW or 800
    local ch = state.canvasH or 600

    -- 倒计时：顶部居中，大号等宽感数字
    state.timerText = utils.createText(
        0, ch / 2 - 80, 420, 100, "0.00",
        utils.hexToColor(config.DEFAULT_PALETTE.hud), 72, state.containerHud)

    -- 提示消息：底部居中
    state.messageText = utils.createText(
        0, -ch / 2 + 60, cw - 120, 56, "",
        utils.hexToColor(config.DEFAULT_PALETTE.hud), 26, state.containerHud)
end

-- ================================================================
-- ★ 触屏虚拟按钮（仅触屏设备创建）
--   按钮自身监听按下/抬起，映射到与键盘一致的输入状态，
--   因此物理层无需区分输入来源。
-- ================================================================
local function createTouchButton(x, y, label, key)
    local size = config.DEFAULT_TOUCH_BTN_SIZE or 88
    local alpha = config.DEFAULT_TOUCH_BTN_ALPHA or 110
    local ctrl = utils.createControl(
        state.rectPrefabId, x, y, size, size,
        utils.hexToColorA("FFFFFF", alpha), state.containerHud)
    if not ctrl then return nil end

    if (state.textPrefabId or 0) > 0 then
        utils.createText(x, y, size, size, label,
            utils.hexToColor("111114"), 34, state.containerHud)
    end

    local function press()
        if not state.keysEnabled then return end
        if key == "keyJump" then
            state.keyJump = true
            state.jumpBufferTimer = state.JUMP_BUFFER_TIME or 0.12
        else
            state[key] = true
        end
    end
    local function release()
        state[key] = false
    end

    pcall(function()
        ctrl:AddCursorEventListener(Enum.CursorEventType.CursorDown, press)
        ctrl:AddCursorEventListener(Enum.CursorEventType.CursorUp, release)
        ctrl:AddCursorEventListener(Enum.CursorEventType.CursorExit, release)
    end)

    state.touchButtons[#state.touchButtons + 1] = { ctrl = ctrl, key = key }
    return ctrl
end

local function createTouchControls()
    local cw = state.canvasW or 800
    local ch = state.canvasH or 600
    local size = config.DEFAULT_TOUCH_BTN_SIZE or 88
    local margin = config.DEFAULT_TOUCH_BTN_MARGIN or 60
    local baseY = -ch / 2 + margin

    -- ★ 字形用 ← / → 而非 ◀ / ▶：雅黑/宋体/黑体均缺 U+25C0/U+25B6，会渲染成豆腐块
    createTouchButton(-cw / 2 + margin, baseY, "←", "keyLeft")
    createTouchButton(-cw / 2 + margin + size + 16, baseY, "→", "keyRight")
    createTouchButton(cw / 2 - margin, baseY, "跳", "keyJump")
end

-- ================================================================
-- ★ 键盘绑定
--   Down 受 keysEnabled 总开关控制；Up 始终执行，避免开关关闭时按键卡住。
-- ================================================================
local function bindKeys(root)
    local K = Enum.KeyEventType

    -- 玩法输入：受 keysEnabled 总开关控制；菜单打开时让位给菜单
    local function bindPair(downEvt, upEvt, onDown, onUp)
        pcall(function()
            root:AddKeyEventListener(downEvt, function()
                if state.menuOpen then return false end
                if not state.keysEnabled then return false end
                onDown()
                return true
            end)
        end)
        if upEvt then
            pcall(function()
                root:AddKeyEventListener(upEvt, function()
                    onUp()
                    return true
                end)
            end)
        end
    end

    -- ★ 菜单输入：与玩法键复用同一批物理键，靠 state.menuOpen 分流。
    --   面板打开时 keysEnabled 已被置 false，所以两边绝不会同时响应。
    local function bindMenuKey(evt, fn)
        pcall(function()
            root:AddKeyEventListener(evt, function()
                if not state.menuOpen then return false end
                if (config.DEFAULT_MENU_INPUT_ENABLED or 1) == 0 then return false end
                fn()
                return true
            end)
        end)
    end

    -- ★ 全局键：不受 keysEnabled 限制。
    --   面板打开时 keysEnabled 为 false，但「关闭面板 / 关卡切换」必须仍然可用。
    local function bindGlobal(evt, fn)
        pcall(function()
            root:AddKeyEventListener(evt, function()
                fn()
                return true
            end)
        end)
    end

    local function pressLeft()  state.keyLeft = true end
    local function pressRight() state.keyRight = true end
    local function releaseLeft()  state.keyLeft = false end
    local function releaseRight() state.keyRight = false end
    local function pressJump()
        -- ★ 边界触发：按住时引擎/系统会重复送 KeyDown，这里必须只认「按下的那一刻」，
        --   否则缓冲会被反复续期，落地瞬间自动再跳 → 表现为「按住持续跳跃」。
        if state.JUMP_EDGE_TRIGGER ~= 0 and state.keyJump then return end
        state.keyJump = true
        state.jumpBufferTimer = state.JUMP_BUFFER_TIME or 0.12
    end
    local function releaseJump() state.keyJump = false end

    -- 左：A / ←
    bindPair(K.KeyboardMoveLeftKeyDown, K.KeyboardMoveLeftKeyUp, pressLeft, releaseLeft)
    bindPair(K.KeyboardCraftspersonKey38Down, K.KeyboardCraftspersonKey38Up, pressLeft, releaseLeft)
    -- 右：D / →
    bindPair(K.KeyboardMoveRightKeyDown, K.KeyboardMoveRightKeyUp, pressRight, releaseRight)
    bindPair(K.KeyboardCraftspersonKey39Down, K.KeyboardCraftspersonKey39Up, pressRight, releaseRight)
    -- 跳：空格 / W / ↑
    bindPair(K.KeyboardJumpKeyDown, K.KeyboardJumpKeyUp, pressJump, releaseJump)
    bindPair(K.KeyboardMoveForwardKeyDown, K.KeyboardMoveForwardKeyUp, pressJump, releaseJump)
    bindPair(K.KeyboardCraftspersonKey36Down, K.KeyboardCraftspersonKey36Up, pressJump, releaseJump)

    -- ★ 菜单导航（仅在面板打开时生效）
    bindMenuKey(K.KeyboardMoveLeftKeyDown,       function() menu.moveCursor(-1) end)
    bindMenuKey(K.KeyboardCraftspersonKey38Down, function() menu.moveCursor(-1) end)
    bindMenuKey(K.KeyboardMoveRightKeyDown,      function() menu.moveCursor(1) end)
    bindMenuKey(K.KeyboardCraftspersonKey39Down, function() menu.moveCursor(1) end)
    bindMenuKey(K.KeyboardJumpKeyDown,           function() menu.confirm() end)
    bindMenuKey(K.KeyboardMoveForwardKeyDown,    function() menu.confirm() end)
    bindMenuKey(K.KeyboardCraftspersonKey36Down, function() menu.confirm() end)

    -- R：重开本关（选关面板打开时不响应，走面板按钮）
    bindGlobal(K.KeyboardCharacterSkill3KeyDown, function()
        if menu.isOpen() and state.menuMode == "select" then return end
        reloadLevel()
    end)
    -- T：下一关（调试用）
    bindGlobal(K.KeyboardCharacterSkill4KeyDown, function()
        if menu.isOpen() and state.menuMode == "select" then return end
        nextLevel()
    end)
    -- P：上一关（调试用）
    bindGlobal(K.KeyboardCraftspersonKey18Down, function()
        if menu.isOpen() then return end
        prevLevel()
    end)
    -- L：开关选关面板（★ 必须绕过 keysEnabled —— 面板打开时它是 false，否则关不掉）
    bindGlobal(K.KeyboardCraftspersonKey21Down, function()
        signal.send("选择关卡")
        menu.toggle("select")
    end)
end

-- ================================================================
-- ★ 关卡切换入口
-- ================================================================
function reloadLevel()
    signal.send("重置关卡")
    loadLevel(state.currentLevelIndex)
end

function nextLevel()
    local n = state.currentLevelIndex + 1
    if config.getLevelConfig(n) then
        signal.send("进入下一关")
        loadLevel(n)
    end
end

function prevLevel()
    local p = state.currentLevelIndex - 1
    if config.getLevelConfig(p) then
        signal.send("进入上一关")
        loadLevel(p)
    end
end

-- ================================================================
-- ★ 响应服务器信号「进入关卡」：参数为整数关卡序号
--   兼容 0 起始（若该序号无配置、而 +1 后有配置，则视为 0 起始自动 +1）
-- ================================================================
local function onEnterLevel(name, params)
    local idx = signal.getIntParam(params, 1)
    if not idx then return end
    local use = idx
    if not config.getLevelConfig(use) and config.getLevelConfig(idx + 1) then
        use = idx + 1
    end
    loadLevel(use)
end

-- ================================================================
-- ★ 结束时序
-- ================================================================
local function checkGoal()
    if state.gameWon or state.gameFailed then return end
    local pl, g = state.player, state.goal
    if not pl or not g then return end
    if utils.aabbOverlap(pl.x, pl.y, pl.halfW, pl.halfH, g.x, g.y, g.halfW, g.halfH) then
        state.gameWon = true
    end
end

local function checkTimeOut()
    if state.gameWon or state.gameFailed then return end
    if (config.DEFAULT_TIME_EXPIRE_FAIL or 1) <= 0 then return end
    if timeSystem.isExpired() then
        state.gameFailed = true
        state.failReason = "time_out"
    end
end

local function resolveEnd()
    if state.gameWon and not state.winHandled then
        state.winHandled = true
        timeSystem.setRunning(false)
        state.winTimeLeft = state.timeNow
        audio.playWin()
        utils.setMessage("到达终点！")
        menu.markCleared(state.currentLevelIndex)
        signal.send("到达终点")
        signal.sendLevelWin(state.currentLevelIndex, state.timeNow)
        -- ★ 通关展示：剩余时间 + 「重玩本关 / 下一关」
        if (config.DEFAULT_MENU_AUTO_WIN or 1) ~= 0 then
            menu.open("win")
        end
    end
    if state.gameFailed and not state.failHandled then
        state.failHandled = true
        timeSystem.setRunning(false)
        state.keyLeft = false
        state.keyRight = false
        state.keyJump = false
        audio.playFail()
        if state.failReason == "time_out" then
            utils.setMessage("时间到！按 R 重新开始")
        else
            utils.setMessage("掉出关卡了！按 R 重新开始")
        end
        signal.send("游戏失败")
        -- ★ 失败面板：失败原因 + 「重玩本关 / 返回选关」
        menu.open("fail")
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

    -- ★ 矩形底图模板（必填）：背景 / 平台 / 玩家 / 门 / 道具均用它染色
    state.rectPrefabId = getParamNumber("rectPrefabId", 0)
    if state.rectPrefabId <= 0 then
        printerr("错误：请设置脚本参数 rectPrefabId（纯色矩形底图元件）")
        return
    end
    -- ★ 文本模板（可选）：倒计时 / 平台秒数 / 提示
    state.textPrefabId = getParamNumber("textPrefabId", 0)
    state.playerPrefabId = getParamNumber("playerPrefabId", 0)
    state.goalPrefabId = getParamNumber("goalPrefabId", 0)

    -- ★ 先启用 OnUpdate：输入监听与初始化都依赖脚本更新被引擎驱动
    script:EnableUpdate(true)

    -- ★ 音效
    state.jumpAudioId   = getParamNumber("jumpAudioId", 0)
    state.landAudioId   = getParamNumber("landAudioId", 0)
    state.switchAudioId = getParamNumber("switchAudioId", 0)
    state.pickupAudioId = getParamNumber("pickupAudioId", 0)
    state.winAudioId    = getParamNumber("winAudioId", 0)
    state.failAudioId   = getParamNumber("failAudioId", 0)
    audio.init({
        jump   = state.jumpAudioId,
        land   = state.landAudioId,
        switch = state.switchAudioId,
        pickup = state.pickupAudioId,
        win    = state.winAudioId,
        fail   = state.failAudioId,
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

    -- ★ 物理参数：以 config 的真源写入 state
    state.GRAVITY            = config.DEFAULT_GRAVITY
    state.FALL_GRAVITY_MULT  = config.DEFAULT_FALL_GRAVITY_MULT
    state.MAX_FALL_SPEED     = config.DEFAULT_MAX_FALL_SPEED
    state.MOVE_SPEED         = config.DEFAULT_MOVE_SPEED
    state.GROUND_ACCEL       = config.DEFAULT_GROUND_ACCEL
    state.GROUND_FRICTION    = config.DEFAULT_GROUND_FRICTION
    state.AIR_ACCEL          = config.DEFAULT_AIR_ACCEL
    state.AIR_FRICTION       = config.DEFAULT_AIR_FRICTION
    state.JUMP_SPEED         = config.DEFAULT_JUMP_SPEED
    state.JUMP_CUT_MULT      = config.DEFAULT_JUMP_CUT_MULT
    state.JUMP_EDGE_TRIGGER  = config.DEFAULT_JUMP_EDGE_TRIGGER
    state.COYOTE_TIME        = config.DEFAULT_COYOTE_TIME
    state.JUMP_BUFFER_TIME   = config.DEFAULT_JUMP_BUFFER_TIME
    state.PHYSICS_SUBSTEPS   = config.DEFAULT_PHYSICS_SUBSTEPS

    -- ★ 层级容器 + 黑幕（一次性创建）
    ensureContainers()
    fadeScreen.init()

    -- ★ HUD
    createHud()

    -- ★ 菜单 / 结算面板：预创建 + 注入关卡切换回调
    --   （用回调注入而非让 menu 反向 require game，避免循环依赖）
    if not menu.init() then
        printerr("警告：菜单面板初始化失败（选关 / 结算界面将不可用）")
    end
    menu.setActions({
        onSelect = function(idx) loadLevel(idx) end,
        onReload = function() reloadLevel() end,
        onNext   = function() nextLevel() end,
    })

    -- ★ 输入设备：触屏额外创建虚拟按钮
    state.deviceIsTouch = detectTouchDevice()
    if state.deviceIsTouch then
        createTouchControls()
        menu.createEntryButton()   -- 触屏没有 L 键，需要屏幕上的常驻「选关」入口
    end

    -- ★ 键盘绑定
    bindKeys(root)

    -- ★ 监听服务器信号「进入关卡」
    if not signal.register("进入关卡", onEnterLevel) then
        printerr("错误：注册服务器信号监听失败: 进入关卡")
    end

    -- ★ 首关
    loadLevel(1)
end

-- ================================================================
-- ★ 每帧更新
-- ================================================================
function OnUpdate(dt)
    if dt > 0.05 then dt = 0.05 end
    state.lastDt = dt

    -- 黑幕散尽后再开始计时（避免玩家看不到关卡就被扣时）
    if state.pendingStart and not fadeScreen.active then
        state.pendingStart = false
        timeSystem.setRunning(true)
    end

    -- ★ 面板打开时冻结玩法（计时 / 物理 / 拾取 / 结束判定全停）；
    --   黑幕与 HUD 仍需每帧推进，否则过渡动画会卡住。
    if state.paused then
        level.updateTimerDisplay()
        fadeScreen.update(dt)
        return
    end

    -- ① 时间推进；秒数切换时刷新平台实体状态
    if not state.gameWon and not state.gameFailed then
        local flipped = timeSystem.update(dt)
        if flipped then
            level.refreshPlatforms()
            if (state.switchCooldown or 0) <= 0 then
                audio.playSwitch()
                state.switchCooldown = config.DEFAULT_SWITCH_COOLDOWN or 0.06
            end
        end
    end

    -- ② 玩家物理
    physics.update(dt)

    -- ③ 道具拾取与效果
    if not state.gameWon and not state.gameFailed then
        local picked = level.checkPickup()
        for _, k in ipairs(picked) do
            if k.kind == "time" then
                timeSystem.add(k.value)
            elseif k.kind == "reverse" then
                timeSystem.reverse()
            end
            audio.playPickup()
            level.refreshPlatforms()
        end
    end

    -- ④ 结束判定
    checkGoal()
    checkTimeOut()
    resolveEnd()

    -- ⑤ HUD 与黑幕
    level.updateTimerDisplay()
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
