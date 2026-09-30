-- ================================================================
-- 浮岛借木（Float & Fathom）主脚本
--   玩法内核：撞倒立着的树 → 侧面推着树干滑一格 / 正面推让它在前一格立起来
--             → 让树干落进水道当桥，把两座浮岛连起来。
--   架构沿用本工作区「割绳子 / TickHop」工程的既有分层：
--     容器化父节点管理层级 → 黑幕过渡掩护关卡切换 → 模块各司其职。
--   ★ 挂载位置：客户端控件容器的「容器节点」上（script.object 即父节点）。
-- ================================================================

---@diagnostic disable: undefined-global

local config = require("config")
local state = require("state")
local utils = require("utils")
local world = require("world")
local level = require("level")
local audio = require("audio")
local signal = require("signal")
local fadeScreen = require("fadeScreen")

-- ================================================================
-- ★ 前置声明：loadLevel 的 onPeak 闭包会在运行时引用 doLoadLevel，
--   必须先在此声明 local；实现处写成赋值形式（不能写 local function，
--   否则会新建一个 local 遮蔽前置声明，闭包仍拿到 nil）。
-- ================================================================
local doLoadLevel

-- ================================================================
-- ★ 创建一个透明容器父节点（定位于世界原点，子节点坐标即世界坐标）
--   ★ 优先用「容器节点」元件（1073741876 / 内部名 SoloTurnPoolHost）创建：
--     它本身不绘制任何图形、也不需要图源，天生就是用来组织子控件的，
--     比拿「图片」元件当父节点干净（图片元件在真机上没配图会画成「?」占位框，
--     虽然 alpha=0 看不见，但白占一层渲染）。
--   ★ 容器节点模板缺失时（老存档 / 没在编辑器里登记）回退用矩形元件，
--     保证任何情况下都能跑起来。
-- ================================================================
local function createContainer()
    if not state.parent then return nil end

    -- ① 首选：容器节点元件
    local cid = state.containerPrefabId or 0
    if cid > 0 then
        local ok, c = pcall(game.InstantiateClientUIControl, cid, state.parent)
        if ok and c then
            pcall(function()
                c:SetAnchorMin(0.5, 0.5)
                c:SetAnchorMax(0.5, 0.5)
                c:SetPivot(0.5, 0.5)
                c:SetAnchoredPosition(0, 0)   -- 容器定位于世界原点，子节点坐标即世界坐标
                c:SetSizeDelta(1, 1)          -- 自身不占可视面积
            end)
            c:SetActive(true)
            return c
        end
    end

    -- ② 回退：矩形元件（染成全透明，视觉上等价于容器）
    --    也走两级回退（矩形 → 图片），别裸调 InstantiateClientUIControl
    local c = utils.instantiateRect(state.parent)
    if not c then return nil end
    utils.applyImage(c, state.rectImageId)
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
-- ★ 检查 5 个层级容器，缺失的补建（创建顺序即显示层级，从下到上）
-- ================================================================
local function ensureContainers()
    local order = {
        "containerBg",        -- ① 海面（整屏底）
        "containerWorld",     -- ② 世界：地块（网格线/岛缘/顶面）+ 物体 + 小人（按深度显式排序）
        "containerFx",        -- ③ 特效（涟漪）
        "containerHud",       -- ④ HUD（关卡名 / 步数 / 消息 / 提示）
        "containerFade",      -- ⑤ 黑幕过渡（最顶）
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
-- ★ 走一步（输入层 → 规则层 → 表现层）
-- ================================================================
local function tryMove(key)
    if not state.keysEnabled then return end
    if state.pendingStart then return end          -- 黑幕还没散尽，先别动
    if state.won then return end                   -- 已通关，锁住输入
    if (state.actionLock or 0) > 0 then return end -- 动作冷却中

    local act = world.step(key)
    local kind = act.kind or "invalid"

    if act.ok then
        state.steps = (state.steps or 0) + 1
        state.lastAction = kind
        if act.moved then
            local dur = config.DEFAULT_STEP_ANIM_TIME
            if kind ~= "move" then dur = config.DEFAULT_ACTION_ANIM_TIME end
            level.beginPlayerMove(dur)
        end
        if act.changed then level.rebuildObjects() end
        level.spawnRipple(act.c, act.r)
        level.updateHudDisplay()

        if kind == "move" then
            utils.setMessage("")
            audio.playStep()
        else
            utils.setMessage(act.msg or "")
            -- 撞倒立着的树是「砰」，推动树干是「咕咚」—— 两套音效
            if kind == "knock" then audio.playKnock() else audio.playPush() end
            if act.changed then state.actionLock = config.DEFAULT_ACTION_COOLDOWN or 0.1 end
        end

        -- 出站：把玩家的关键动作报给服务器（便于外部统计/成就/关卡校验）
        if kind == "knock" then
            signal.send("撞倒树木")
        elseif kind == "slide" then
            signal.send("推滑树干")
        elseif kind == "raise" then
            signal.send("树干立起")
        end

        if world.isWin() then state.won = true end
    else
        -- 撞石头 / 前方是水 / 端面推不动 —— 给一次短冷却，避免连按刷屏
        utils.setMessage(act.msg or "")
        audio.playBlocked()
        state.actionLock = config.DEFAULT_ACTION_COOLDOWN or 0.1
    end
end

-- ================================================================
-- ★ HUD
-- ================================================================
local function createHud()
    local cw = state.canvasW or config.DEFAULT_VIEW_WIDTH
    local ch = state.canvasH or config.DEFAULT_VIEW_HEIGHT
    local barH = config.DEFAULT_HUD_BAR_HEIGHT or 74
    local palette = utils.resolvePalette(nil)
    local barY = ch / 2 - barH / 2

    -- 顶部信息条底
    state.hudBar = utils.createControl(
        state.rectPrefabId, 0, barY, cw + 80, barH,
        utils.hexToColorA(palette.hudBar, config.DEFAULT_HUD_ALPHA or 130),
        state.containerHud)

    -- 关卡名（左半区居中）
    state.hudTitle = utils.createText(
        -cw * 0.26, barY, cw * 0.46, barH - 8, "",
        utils.hexToColor(palette.hud), config.DEFAULT_HUD_TITLE_SIZE or 30,
        state.containerHud)

    -- 步数 / 状态（右半区居中）
    state.hudInfo = utils.createText(
        cw * 0.28, barY, cw * 0.38, barH - 8, "",
        utils.hexToColor(palette.hud), config.DEFAULT_HUD_INFO_SIZE or 22,
        state.containerHud)

    -- 底部一次性消息
    state.hudMessage = utils.createText(
        0, -ch / 2 + 30, cw - 140, 36, "",
        utils.hexToColor(palette.hud), config.DEFAULT_HUD_INFO_SIZE or 22,
        state.containerHud)

    -- 底部提示文本（按 F 开关；多条各占一行，每条按 hint_wrap 折行）
    state.hudHint = utils.createText(
        0, -ch / 2 + 88, cw - 140, 72, "",
        utils.hexToColor(palette.hint), config.DEFAULT_HUD_HINT_SIZE or 20,
        state.containerHud)
    utils.setVisible(state.hudHint, false)
end

-- ================================================================
-- ★ 触屏方向键（仅触屏设备创建）
--   直接用光标事件驱动 tryMove，与键盘走同一条路径。
-- ================================================================
local function createTouchButton(x, y, label, key)
    local size = config.DEFAULT_TOUCH_BTN_SIZE or 84
    local alpha = config.DEFAULT_TOUCH_BTN_ALPHA or 120
    local ctrl = utils.createControl(
        state.rectPrefabId, x, y, size, size,
        utils.hexToColorA("FFFFFF", alpha), state.containerHud)
    if not ctrl then return nil end

    if (state.textPrefabId or 0) > 0 then
        utils.createText(x, y, size, size, label,
            utils.hexToColor("111114"), math.floor(size * 0.42), state.containerHud)
    end

    pcall(function()
        ctrl:AddCursorEventListener(Enum.CursorEventType.CursorDown, function()
            if not state.keysEnabled then return end
            tryMove(key)
        end)
    end)

    state.touchButtons[#state.touchButtons + 1] = { ctrl = ctrl, key = key }
    return ctrl
end

local function createTouchControls()
    local cw = state.canvasW or config.DEFAULT_VIEW_WIDTH
    local ch = state.canvasH or config.DEFAULT_VIEW_HEIGHT
    local size = config.DEFAULT_TOUCH_BTN_SIZE or 84
    local gap = 12
    local margin = config.DEFAULT_TOUCH_BTN_MARGIN or 56
    local btn = size + gap

    -- 左下角十字布局
    local left0 = -cw / 2 + margin
    local bottom0 = -ch / 2 + margin
    createTouchButton(left0,              bottom0 + btn, "←", "A")
    createTouchButton(left0 + btn,        bottom0,       "↓", "S")
    createTouchButton(left0 + btn * 2,    bottom0 + btn, "→", "D")
    createTouchButton(left0 + btn,        bottom0 + btn * 2, "↑", "W")
end

-- ================================================================
-- ★ 键盘绑定
--   ★ 长按连发：只在「按下的那一刻」走一步，靠 held* 标记吞掉重复的 KeyDown。
--   ★ 抬起始终处理，避免开关关闭时按键卡在按下态。
-- ================================================================
local function bindKeys(root)
    local K = Enum.KeyEventType

    local function bindMove(downEvt, upEvt, key, field)
        if not downEvt then return end
        pcall(function()
            root:AddKeyEventListener(downEvt, function()
                if state[field] then return true end     -- 长按重复触发：吞掉
                state[field] = true
                tryMove(key)
                return true
            end)
        end)
        if upEvt then
            pcall(function()
                root:AddKeyEventListener(upEvt, function()
                    state[field] = false
                    return true
                end)
            end)
        end
    end

    -- 全局键：不受 keysEnabled 限制（重开 / 换关 / 提示开关必须随时可用）
    local function bindGlobal(evt, fn)
        if not evt then return end
        pcall(function()
            root:AddKeyEventListener(evt, function()
                fn()
                return true
            end)
        end)
    end

    -- 主键：W / A / S / D
    bindMove(K.KeyboardMoveForwardKeyDown,  K.KeyboardMoveForwardKeyUp,  "W", "heldW")
    bindMove(K.KeyboardMoveLeftKeyDown,     K.KeyboardMoveLeftKeyUp,     "A", "heldA")
    bindMove(K.KeyboardMoveBackwardKeyDown, K.KeyboardMoveBackwardKeyUp, "S", "heldS")
    bindMove(K.KeyboardMoveRightKeyDown,    K.KeyboardMoveRightKeyUp,    "D", "heldD")
    -- 备用键：方向键 ↑ ↓ ← →
    bindMove(K.KeyboardCraftspersonKey36Down, K.KeyboardCraftspersonKey36Up, "W", "heldW")
    bindMove(K.KeyboardCraftspersonKey37Down, K.KeyboardCraftspersonKey37Up, "S", "heldS")
    bindMove(K.KeyboardCraftspersonKey38Down, K.KeyboardCraftspersonKey38Up, "A", "heldA")
    bindMove(K.KeyboardCraftspersonKey39Down, K.KeyboardCraftspersonKey39Up, "D", "heldD")

    -- R：重开本关
    bindGlobal(K.KeyboardCharacterSkill3KeyDown, function() reloadLevel() end)
    -- T：下一关
    bindGlobal(K.KeyboardCharacterSkill4KeyDown, function() nextLevel() end)
    -- P：上一关
    bindGlobal(K.KeyboardCraftspersonKey18Down, function() prevLevel() end)
    -- F：显示 / 隐藏提示
    bindGlobal(K.KeyboardInteractKeyDown, function()
        state.hintsOn = not state.hintsOn
        level.updateHudDisplay()
    end)
end

-- ================================================================
-- ★ 加载指定关卡（1 起始）：黑幕掩护下重建
-- ================================================================
function loadLevel(levelIndex)
    local idx = math.floor(tonumber(levelIndex) or 0)
    if idx < 1 then return false end
    local data = config.getLevelConfig(idx)
    if not data then return false end
    if not ensureContainers() then return false end

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
    state.levelIndex = idx
    state.levelConfig = data

    -- 输入与节奏复位
    state.keysEnabled = true
    state.pendingStart = true      -- 等黑幕散尽再放开输入
    state.actionLock = 0
    state.heldW, state.heldA, state.heldS, state.heldD = false, false, false, false

    if not level.build(data) then
        printerr("错误：关卡构建失败，index=" .. tostring(idx))
        return
    end

    state.hintsOn = false
    level.syncPlayerNow()
    level.updateHudDisplay()
    utils.setMessage("")
end

-- ================================================================
-- ★ 关卡切换入口
-- ================================================================
function reloadLevel()
    signal.send("重置关卡")
    loadLevel(state.levelIndex)
end

function nextLevel()
    local n = (state.levelIndex or 1) + 1
    if config.getLevelConfig(n) then
        signal.send("进入下一关")
        loadLevel(n)
    else
        utils.setMessage("已经是最后一关啦")
    end
end

function prevLevel()
    local p = (state.levelIndex or 1) - 1
    if config.getLevelConfig(p) then
        signal.send("进入上一关")
        loadLevel(p)
    end
end

-- ================================================================
-- ★ 通关结算（只执行一次）
-- ================================================================
local function resolveWin()
    if not state.won or state.winHandled then return end
    state.winHandled = true
    audio.playWin()

    if (state.levelIndex or 1) >= config.getLevelCount() then
        utils.setMessage("全部通关！按 R 重玩本关")
    else
        utils.setMessage("过关！按 T 进入下一关，按 R 重玩本关")
    end

    signal.send("到达终点")
    signal.sendLevelWin(state.levelIndex, state.steps)
    level.updateHudDisplay()
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

-- ================================================================
-- ★ 生命周期
-- ================================================================
function OnStart()
    local root = script.object
    if not root then
        printerr("错误：script.object 为 nil，请确认本脚本已挂在【客户端控件容器】的容器节点上")
        return
    end
    state.parent = root

    -- ★ 容器节点模板（可选）：5 个层级容器由它创建；留空则回退到矩形元件
    --   真机内置模板索引 1073741876（内部名 SoloTurnPoolHost），零配置即可命中
    state.containerPrefabId = getParamNumber("containerPrefabId", config.DEFAULT_PREFAB_CONTAINER)
    -- ★ 纯色底图模板：沙滩 / 树根 / 倒下的树 / 石头 / 终点旗 / HUD 底衬 / 涟漪 / 黑幕
    --   全靠它 + imageColor 染色画出来。
    --   首选「矩形」元件（1073741894，自带矩形图元，真机不需要再配白图）；
    --   当前存档里没有它时，utils.instantiateRect 会自动回退「图片」元件（1073741870）。
    state.rectPrefabId = getParamNumber("rectPrefabId", config.DEFAULT_PREFAB_RECT)
    if state.rectPrefabId <= 0 then
        state.rectPrefabId = config.DEFAULT_PREFAB_IMAGE
    end
    if state.rectPrefabId <= 0 then
        printerr("错误：请设置脚本参数 rectPrefabId（纯色底图元件）")
        return
    end
    -- ★ 纯色底图的回退备胎（可选）：只在「矩形」拿不到控件时顶上来。
    --   ⚠️ 它是官方内置的「图片」元件，默认不带图源，真机会画成彩色「?」
    --      → 真机上要么给它配一张纯白图，要么填 rectImageId。
    state.imagePrefabId = getParamNumber("imagePrefabId", config.DEFAULT_PREFAB_IMAGE)
    -- ★ 文本模板（可选）：关卡名 / 步数 / 消息 / 提示
    --   真机内置模板索引 1073741868（文本框）
    state.textPrefabId = getParamNumber("textPrefabId", config.DEFAULT_PREFAB_TEXT)
    -- ★ 纯色底图的图源（可选）：真机若出现「?」缺失框，填编辑器图库里的图片 ID 即可，
    --   脚本会在创建每个底图控件后 SetImage 指定；留空/0 则沿用元件自带图源。
    state.rectImageId = getParamNumber("rectImageId", config.DEFAULT_RECT_IMAGE_ID)

    -- ★ 美术素材元件（海水 / 草地 / 树木 / 人物）
    --   这 4 个元件里**已经关联好美术素材**，脚本只管把它们摆到位置上，
    --   创建时**不写 imageColor** —— 一写就把素材乘上去了（变暗、串色）。
    --   总开关 useArt = 0（或任一索引填 0）→ 该类退回矩形 + 调色板染色，
    --   画面与加入素材之前完全一致，方便对照排查。
    state.useArt = (getParamNumber("useArt", config.DEFAULT_USE_ART) or 0) > 0
    state.waterPrefabId  = getParamNumber("waterPrefabId",  config.DEFAULT_PREFAB_WATER)
    state.landPrefabId   = getParamNumber("landPrefabId",   config.DEFAULT_PREFAB_LAND)
    state.treePrefabId   = getParamNumber("treePrefabId",   config.DEFAULT_PREFAB_TREE)
    state.playerPrefabId = getParamNumber("playerPrefabId", config.DEFAULT_PREFAB_PLAYER)

    -- ★ 2.5D 视角（可选）：地块厚度 + 岛缘投影 + 水面细网格线
    --   view25d = 0 → 退回改动前的平面正交画法（沙边改用 DEFAULT_COAST_PAD 像素）
    --   waterGridLines = 0 → 水面只留旧的水下深色棋盘（不画细网格线）
    state.view25d = (getParamNumber("view25d", config.DEFAULT_VIEW_25D) or 0) > 0
    state.waterGridLines = (getParamNumber("waterGridLines", config.DEFAULT_WATER_GRID_LINES) or 0) > 0

    -- ★ 先启用 OnUpdate：输入监听与初始化都依赖脚本更新被引擎驱动
    script:EnableUpdate(true)

    -- ★ 音效
    state.stepAudioId    = getParamNumber("stepAudioId", 0)
    state.knockAudioId   = getParamNumber("knockAudioId", 0)
    state.pushAudioId    = getParamNumber("pushAudioId", 0)
    state.winAudioId     = getParamNumber("winAudioId", 0)
    state.blockedAudioId = getParamNumber("blockedAudioId", 0)
    audio.init({
        step    = state.stepAudioId,
        knock   = state.knockAudioId,
        push    = state.pushAudioId,
        win     = state.winAudioId,
        blocked = state.blockedAudioId,
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

    -- ★ 层级容器 + 黑幕（一次性创建）
    ensureContainers()
    fadeScreen.init()

    -- ★ HUD
    createHud()

    -- ★ 输入设备：触屏额外创建方向键
    state.deviceIsTouch = detectTouchDevice()
    if state.deviceIsTouch then
        createTouchControls()
    end

    -- ★ 键盘绑定
    bindKeys(root)

    -- ★ 监听服务器信号「进入关卡」
    if not signal.register("进入关卡", onEnterLevel) then
        printerr("警告：注册服务器信号监听失败（进入关卡）")
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

    -- 黑幕散尽后再放开输入（避免玩家看不见关卡就能走）
    if state.pendingStart and not fadeScreen.active then
        state.pendingStart = false
    end

    if (state.actionLock or 0) > 0 then
        state.actionLock = math.max(0, state.actionLock - dt)
    end

    level.updateVisuals(dt)
    resolveWin()
    fadeScreen.update(dt)
end

function OnDestroy()
    -- 引擎回收脚本时无需额外清理：控件随容器一并释放
end
