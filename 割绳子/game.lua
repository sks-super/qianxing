-- ================================================================
-- 主脚本（包含尖刺、失败处理）
-- ================================================================

---@diagnostic disable: undefined-global

local config = require("config")
local state = require("state")
local utils = require("utils")
local rope = require("rope")
local physics = require("physics")
local render = require("render")
local objectUI = require("objectUI")   -- 物品 UI 显示模块（像素序列帧动画 / 像素对象挂载）
local tunshi = require("吞噬")        -- 吞食动画（60x60）：第 1 帧=等待投喂姿态，第 2-6 帧=吞噬动画
local cake = require("蛋糕")           -- 糖果/蛋糕像素画（60x60，挂到糖果容器上）
local bladeTrail = require("bladeTrail") -- 刀光拖尾（鼠标按住移动时产生）
local audio = require("audio")            -- 音效管理模块
local signal = require("signal")          -- 客户端事件信号模块
local fadeScreen = require("fadeScreen")  -- 全屏黑幕过渡模块（关卡切换时遮罩）

_G.getLevelConfig = config.getLevelConfig
_G.getLevelCount = config.getLevelCount
_G.createCandyNode = rope.createCandyNode
_G.createRope = rope.createRope
_G.updateRopeNodesAll = rope.updateRopeNodesAll
_G.updateCandyPhysics = physics.updateCandyPhysics
_G.updateRopeVisualSpline = render.updateRopeVisualSpline

-- ================================================================
local doLoadLevel  -- ★ 前置声明：loadLevel 的 onPeak 闭包在运行时引用 doLoadLevel，
                   --   必须先在此声明 local，否则会被解析为全局 nil
-- ★ 创建一个透明容器父节点（定位于世界原点，子节点坐标即世界坐标）
local function createContainer()
    if not state.parent then return nil end
    if not state.fruitPrefabId or state.fruitPrefabId <= 0 then return nil end
    local ok, c = pcall(game.InstantiateClientUIControl, state.fruitPrefabId, state.parent)
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

-- ★ 检查 8 个层级容器，缺失的补建。
--   返回 (全部就绪?, 仍然缺失的容器名列表)。
local function ensureContainers()
    local missing = {}
    local order = {
        { key = "containerRope",   label = "①绳子" },
        { key = "containerBoard",  label = "②木板" },
        { key = "containerWorld",  label = "③关卡物件" },
        { key = "containerCandy",  label = "④糖果" },
        { key = "containerTarget", label = "⑤人物" },
        { key = "containerText",   label = "⑥文本框" },
        { key = "containerBlade",  label = "⑦刀光" },
        { key = "containerFade",   label = "⑧黑幕" },
    }
    for _, item in ipairs(order) do
        if not state[item.key] then
            state[item.key] = createContainer()
            if not state[item.key] then
                missing[#missing + 1] = item.key .. "(" .. item.label .. ")"
            end
        end
    end
    return #missing == 0, missing
end

-- ★ 加载指定关卡
--   返回值：true=已排程或直接加载成功；false=关卡序号非法或关卡不存在
function loadLevel(levelIndex)
    -- ① 序号归一化：兼容数字、数字字符串、浮点
    local idx = tonumber(levelIndex)
    if not idx then return false end
    idx = math.floor(idx)
    if idx < 1 then return false end

    -- ② 取关卡配置
    local okCfg, configData = pcall(getLevelConfig, idx)
    if not okCfg or not configData then return false end

    -- ③ 顶层显示黑色矩形 3000x3000：透明度 0 → maxAlpha 渐显 → 维持 → 渐隐回 0。
    --    在渐隐开始前（onPeak 回调，即渐显完成的瞬间）完成关卡加载，
    --    新关卡在黑幕掩护下就位，再渐隐露出。
    --    若黑幕不可用，fadeScreen.start 内部会同步执行 onPeak（关卡已加载），
    --    此处无需区分，直接按成功处理。
    fadeScreen.start({
        onPeak = function()
            doLoadLevel(idx, configData)
        end,
    })
    return true
end

-- ★ 实际关卡加载（fadeScreen 渐显完成、渐隐开始前调用）
--   注意：这里赋值给上面前置声明的 local，不能用 local function（那会重新声明一个
--   local 遮蔽前置声明，loadLevel 的闭包仍拿到 nil）
doLoadLevel = function(levelIndex, configData)
    state.currentLevelIndex = levelIndex
    state.currentLevelConfig = configData

    state.GRAVITY = configData.gravity
    state.CANDY_DAMPING = configData.candy_damping
    state.CONSTRAINT_ITERATIONS = configData.constraint_iterations
    state.SUB_STEPS = configData.sub_steps
    state.MAX_DRAG_FACTOR = configData.max_drag_factor or 1.0

    -- 重置状态
    state.isMouseDown = false -- 交互状态
    state.candyWrapped = false
    state.wrappedGravity = 0
    state.gameFailed = false
    state.gameWon = false
    state.score = 0

    -- ★ 容器检查/修复：所有物件都挂在容器下，容器缺失会导致创建出来的控件无处可挂
    --   （表现就是“关卡没加载出来”），这里集中校验并在缺失时重建。
    ensureContainers()

    -- 切关/重置前清理可能残留的刀光拖尾
    bladeTrail.clearTrail()

    local targetX = configData.target.x
    local targetY = configData.target.y
    local targetWidth = configData.target.width
    local targetHeight = configData.target.height

    -- 清理旧对象
    for _, r in ipairs(state.ropes) do
        for _, node in ipairs(r.nodes) do
            if node.ctrl then node.ctrl:SetActive(false) end
        end
        for _, seg in ipairs(r.segments) do
            if seg.ctrl then seg.ctrl:SetActive(false) end
        end
        for _, dot in ipairs(r.dots) do
            if dot then dot:SetActive(false) end
        end
    end
    state.ropes = {}
    if state.candyNode then
        if state.candyNode.cakeUI then
            objectUI.destroy(state.candyNode.cakeUI)
            state.candyNode.cakeUI = nil
        end
        if state.candyNode.ctrl then
            state.candyNode.ctrl:SetActive(false)
        end
        state.candyNode = nil
    end
    if state.target and state.target.ctrl then
        objectUI.destroy(state.target.ctrl)
        state.target = nil
    end

    -- 清除星星、泡泡、尖刺
    for _, star in ipairs(state.stars) do
        if star.ctrl then star.ctrl:SetActive(false) end
    end
    state.stars = {}
    for _, bubble in ipairs(state.bubbles) do
        if bubble.ctrl then bubble.ctrl:SetActive(false) end
    end
    state.bubbles = {}
    for _, spike in ipairs(state.spikes) do
        if spike.ctrl then spike.ctrl:SetActive(false) end
    end
    state.spikes = {}
    for _, t in ipairs(state.texts) do
        if t.ctrl then t.ctrl:SetActive(false) end
    end
    state.texts = {}
    for _, b in ipairs(state.boards) do
        if b.ctrl then b.ctrl:SetActive(false) end
    end
    state.boards = {}

    -- 创建糖果（透明容器）
    local candyPos = configData.candy_position
    if candyPos then
        state.candyNode = createCandyNode(candyPos.x, candyPos.y)
    else
        local totalX, totalY = 0, 0
        local count = 0
        for _, r in ipairs(configData.ropes) do
            totalX = totalX + r.fixed.x
            totalY = totalY + r.fixed.y
            count = count + 1
        end
        local candyStartX = totalX / count
        local candyStartY = totalY / count - 30
        state.candyNode = createCandyNode(candyStartX, candyStartY)
    end

    -- 把蛋糕像素画挂到糖果容器上，随糖果整体移动
    local candySize = 50--config.CANDY_RADIUS * 2--这里可以调整蛋糕显示大小保证显示与碰撞一致
    state.candyNode.cakeUI = objectUI.createPixelObject(
        state.candyNode.ctrl, cake, 0, 0,
        candySize, candySize,
        { prefabId = state.fruitPrefabId, block = 1 }
    )

    -- 创建绳子
    for _, ropeConfig in ipairs(configData.ropes) do
        local newRope = createRope(ropeConfig, state.candyNode)
        table.insert(state.ropes, newRope)
    end

    -- 创建目标区域（吃糖小怪兽）：常态显示"等待投喂"姿态 = 吞噬.lua 第 1 帧（静态单帧）
    -- 显示区域取正方形 targetWidth，Pixel 模式复用 fruitPrefabId 可染色方块
    local idleAnim = objectUI.createPixelSequence(
        state.containerTarget,
        { GRID = tunshi.GRID, FRAME_MS = tunshi.FRAME_MS, PALETTE = tunshi.PALETTE, FRAMES = { tunshi.FRAMES[1] } },
        targetX, targetY,
        targetWidth, targetWidth,
        { prefabId = state.fruitPrefabId, block = 1 }   -- 等待投喂姿态：吞噬.lua 第 1 帧（60x60 静态）
    )
    state.target = {
        ctrl = idleAnim,
        x = targetX,
        y = targetY,
        width = targetWidth,
        height = targetHeight,
        mode = "idle"
    }

    -- 创建星星（优先使用星星模板 starPrefabId，保留模板外观不染色；未配置回退 fruitPrefabId 染黄）
    state.stars = {}
    local starRadius = config.STAR_RADIUS or 15
    local starPrefabId = config.starPrefabId or state.starPrefabId or 0
    local starColor = Color.FromRGB(255, 215, 0)
    if starPrefabId <= 0 then
        starPrefabId = state.fruitPrefabId
    else
        starColor = nil   -- 使用模板时不再染色，保留模板自身外观
    end
    for _, pos in ipairs(configData.stars) do
        local ctrl = utils.createControl(starPrefabId, pos.x, pos.y, starRadius*2, starRadius*2, starColor, state.containerWorld)
        if ctrl then
            table.insert(state.stars, {
                ctrl = ctrl,
                x = pos.x,
                y = pos.y,
                active = true,
            })
        end
    end

    -- 创建泡泡（使用泡泡模板，未配置时回退到水果模板）
    state.bubbles = {}
    local defaultRadius = config.DEFAULT_BUBBLE_RADIUS or 22
    local defaultUpwardGravity = config.DEFAULT_UPWARD_GRAVITY or 400
    local bubblePrefabId = config.bubblePrefabId or state.bubblePrefabId or 0
    if bubblePrefabId <= 0 then bubblePrefabId = state.fruitPrefabId end
    for _, bub in ipairs(configData.bubbles) do
        local radius = bub.radius or defaultRadius
        local upwardGravity = bub.upward_gravity or defaultUpwardGravity
        -- 使用泡泡模板，不再强制蓝色染色，让模板自身外观生效
        local ctrl = utils.createControl(bubblePrefabId, bub.x, bub.y, radius*2, radius*2, nil, state.containerWorld)
        if ctrl then
            table.insert(state.bubbles, {
                ctrl = ctrl,
                x = bub.x,
                y = bub.y,
                radius = radius,
                upward_gravity = upwardGravity,
                active = true,
                isWrapping = false,
            })
        end
    end

    -- 创建尖刺（矩形：width 宽 / length 长 / rotation 旋转°）
    --   优先使用尖刺模板 spikePrefabId（保留模板外观，再按关卡参数设尺寸与旋转）；
    --   未配置时回退 fruitPrefabId 染黑。
    state.spikes = {}
    local defSpikeW = config.DEFAULT_SPIKE_WIDTH or 24
    local defSpikeL = config.DEFAULT_SPIKE_LENGTH or 40
    local defSpikeR = config.DEFAULT_SPIKE_ROTATION or 0
    local spikePrefabId = config.spikePrefabId or state.spikePrefabId or 0
    for _, sp in ipairs(configData.spikes) do
        local width = sp.width or defSpikeW
        local length = sp.length or defSpikeL
        local rotation = sp.rotation or defSpikeR
        local ctrl
        if spikePrefabId > 0 then
            ctrl = utils.createTemplateSizedControl(spikePrefabId, sp.x, sp.y, width, length, rotation, state.containerWorld)
        else
            ctrl = utils.createControl(state.fruitPrefabId, sp.x, sp.y, width, length, Color.FromRGB(0, 0, 0), state.containerWorld)
            if ctrl then ctrl:SetLocalRotation(0, 0, rotation) end
        end
        if ctrl then
            table.insert(state.spikes, {
                ctrl = ctrl,
                x = sp.x,
                y = sp.y,
                width = width,
                length = length,
                rotation = rotation,
                active = true,
            })
        end
    end

    -- 创建文本框（优先使用文本框模板 textboxPrefabId；支持 text/fontSize/自适应最小字号/旋转）
    state.texts = {}
    local defTextW = config.DEFAULT_TEXT_WIDTH or 200
    local defTextL = config.DEFAULT_TEXT_LENGTH or 60
    local defTextR = config.DEFAULT_TEXT_ROTATION or 0
    local defTextFont = config.DEFAULT_TEXT_FONT_SIZE or 30
    local textboxPrefabId = config.textboxPrefabId or state.textboxPrefabId or 0
    if textboxPrefabId > 0 then
        for _, t in ipairs(configData.texts or {}) do
            local w = t.width or defTextW
            local l = t.length or defTextL
            local rot = t.rotation or defTextR
            local fontSize = t.font_size or defTextFont
            local ctrl = game.InstantiateClientUIControl(textboxPrefabId, state.containerText)
            if ctrl then
                ctrl:SetAnchorMin(0.5, 0.5)
                ctrl:SetAnchorMax(0.5, 0.5)
                ctrl:SetPivot(0.5, 0.5)
                ctrl:SetSizeDelta(w, l)
                ctrl:SetAnchoredPosition(t.x, t.y)
                ctrl:SetLocalRotation(0, 0, rot)
                -- 文本/字号等字段用 pcall 保护：模板类型不符也不应中断加载
                pcall(function()
                    if t.text ~= nil then ctrl.text = t.text end
                    ctrl.fontSize = fontSize
                    if t.min_font_size and t.min_font_size > 0 then
                        ctrl.adaptiveFontSize = true
                        ctrl.minimumFontSize = t.min_font_size
                    end
                end)
                ctrl:SetActive(true)
                table.insert(state.texts, { ctrl = ctrl, x = t.x, y = t.y, text = t.text, active = true })
            end
        end
    end

    -- 创建木板（矩形障碍：width 宽 / length 长 / rotation 旋转°）
    --   优先使用木板模板 boardPrefabId（保留模板外观，再按关卡参数设尺寸与旋转）；
    --   未配置时回退 fruitPrefabId 染棕。木板固定不动，糖果可碰撞。
    state.boards = {}
    local defBoardW = config.DEFAULT_BOARD_WIDTH or 160
    local defBoardL = config.DEFAULT_BOARD_LENGTH or 24
    local defBoardR = config.DEFAULT_BOARD_ROTATION or 0
    local boardPrefabId = config.boardPrefabId or state.boardPrefabId or 0
    for _, b in ipairs(configData.boards or {}) do
        local width = b.width or defBoardW
        local length = b.length or defBoardL
        local rotation = b.rotation or defBoardR
        local ctrl
        if boardPrefabId > 0 then
            ctrl = utils.createTemplateSizedControl(boardPrefabId, b.x, b.y, width, length, rotation, state.containerBoard)
        else
            ctrl = utils.createControl(state.fruitPrefabId, b.x, b.y, width, length, Color.FromRGB(139, 90, 43), state.containerBoard)
            if ctrl then ctrl:SetLocalRotation(0, 0, rotation) end
        end
        if ctrl then
            table.insert(state.boards, {
                ctrl = ctrl,
                x = b.x,
                y = b.y,
                width = width,
                length = length,
                rotation = rotation,
                active = true,
            })
        end
    end

    utils.updateScoreDisplay()
    utils.setMessage("关卡 "..tostring(levelIndex)..": "..configData.name.."  拖动糖果进入绳子范围以连接")

    utils.checkConnections()
    updateRopeNodesAll()

    return true
end

function nextLevel()
    if state.gameFailed then return end
    local count = getLevelCount()
    if state.currentLevelIndex < count then
        signal.send("进入下一关")
        loadLevel(state.currentLevelIndex + 1)
    else
        utils.setMessage("已到达最后一关！")
    end
end

function prevLevel()
    if state.gameFailed then return end
    if state.currentLevelIndex > 1 then
        signal.send("进入上一关")
        loadLevel(state.currentLevelIndex - 1)
    else
        utils.setMessage("已在第一关！")
    end
end

function reloadLevel()
    signal.send("重置关卡")
    loadLevel(state.currentLevelIndex)
end

-- ★ 响应服务器信号“进入关卡”：参数为整数关卡序号（0 起始； 起始自动 +1）
local function onEnterLevel(name, params)
    local idx = signal.getIntParam(params, 1)
    if not idx  then return end
    loadLevel(idx + 1)
end

-- ★ 响应服务器事件“服务器事件”：字符串参数 “开挂” / “关闭开挂” 切换开挂模式
local function onServerEvent(name, params)
    local cmd = signal.getStringParam(params, 1)
    if cmd == "开挂" then
        state.cheatMode = true
        utils.setMessage("开挂模式已开启：可拖拽糖果，边界/尖刺会弹开")
    elseif cmd == "关闭开挂" then
        state.cheatMode = false
        if state.isDragging then state.isDragging = false end
        utils.setMessage("开挂模式已关闭")
    end
end

-- ★ 响应服务器信号“文本显/隐”：每次收到翻转代码提示文本（MessageText）显隐。
--   config 中配置的关卡消息框（state.texts）不受影响。
local function onTextVisibleToggle()
    state.hintTextVisible = not state.hintTextVisible
    if state.messageText then
        state.messageText:SetActive(state.hintTextVisible)
    end
end

-- ★ 响应服务器信号“按键绑定开/关”：每次收到翻转键盘按键绑定是否生效
local function onKeyBindToggle()
    state.keysEnabled = not state.keysEnabled
end

-- ★ 键盘按键守卫：state.keysEnabled 为 false 时按键监听不响应（返回 false 放行事件）
local function keyGuard(fn)
    return function(...)
        if not state.keysEnabled then return false end
        return fn(...)
    end
end

-- ================================================================
-- ★ 生命周期
-- ================================================================
function OnStart()
    math.randomseed(os.time())

    local root = script.object
    state.parent = root
    if not root then
        printerr("错误：script.object 为 nil，请确认本脚本已挂载在【客户端控件容器】的容器节点上")
        return
    end

    state.fruitPrefabId = getParamNumber("fruitPrefabId", 0)
    if state.fruitPrefabId <= 0 then
        printerr("错误：请设置脚本参数 fruitPrefabId")
        return
    end

    -- ★ 先启用 OnUpdate：输入监听与后续初始化都依赖脚本更新被引擎驱动
    script:EnableUpdate(true)

    -- ★ 泡泡模板：从本脚本的脚本变量读取，并写回 config 记录
    state.bubblePrefabId = getParamNumber("bubblePrefabId", 0)
    config.bubblePrefabId = state.bubblePrefabId

    -- ★ 绳桩（锚点）模板
    state.anchorPrefabId = getParamNumber("anchorPrefabId", 0)
    config.anchorPrefabId = state.anchorPrefabId

    -- ★ 刀光拖尾模板
    state.bladePrefabId = getParamNumber("bladePrefabId", 0)
    config.bladePrefabId = state.bladePrefabId

    -- ★ 星星模板
    state.starPrefabId = getParamNumber("starPrefabId", 0)
    config.starPrefabId = state.starPrefabId

    -- ★ 尖刺模板
    state.spikePrefabId = getParamNumber("spikePrefabId", 0)
    config.spikePrefabId = state.spikePrefabId

    -- ★ 文本框模板
    state.textboxPrefabId = getParamNumber("textboxPrefabId", 0)
    config.textboxPrefabId = state.textboxPrefabId

    -- ★ 木板模板
    state.boardPrefabId = getParamNumber("boardPrefabId", 0)
    config.boardPrefabId = state.boardPrefabId

    -- ★ 创建各容器父节点：游戏启动时一次性创建，顺序即显示层级（从下到上）
    --   rope → board → world → candy → target → text → blade → fade
    --   容器本身透明、定位于世界原点、不占面积；游玩阶段所有 UI 展示都在
    --   容器内部子节点上进行，父节点不移动、不重排 → 全程无需 SetAsLastSibling。
    ensureContainers()

    -- ★ 预创建刀光拖尾节点池（一次性，顺序固定，层级稳定：删除只隐藏容器、不重排）
    bladeTrail.init()

    -- ★ 预创建全屏黑幕过渡节点（一次性，初始隐藏；关卡切换时渐变遮罩）
    fadeScreen.init()

    -- ★ 预热音效：把首次解码成本前置到 OnStart，切割/戳破等事件触发时走热路径
    audio.prewarm()

    -- ★ 音效预设 ID：从本脚本的脚本变量读取，并写回 config/state
    state.cutAudioId    = getParamNumber("cutAudioId", 0)
    state.bubbleAudioId = getParamNumber("bubbleAudioId", 0)
    state.winAudioId    = getParamNumber("winAudioId", 0)
    state.failAudioId   = getParamNumber("failAudioId", 0)
    state.tenseAudioId  = getParamNumber("tenseAudioId", 0)
    state.starAudioId   = getParamNumber("starAudioId", 0)
    config.cutAudioId    = state.cutAudioId
    config.bubbleAudioId = state.bubbleAudioId
    config.winAudioId    = state.winAudioId
    config.failAudioId   = state.failAudioId
    config.tenseAudioId  = state.tenseAudioId
    config.starAudioId   = state.starAudioId
    audio.init({
        cut    = state.cutAudioId,
        bubble = state.bubbleAudioId,
        win    = state.winAudioId,
        fail   = state.failAudioId,
        tense  = state.tenseAudioId,
        star   = state.starAudioId,
    })

    state.canvasW, state.canvasH = game.GetUICanvasSize()
    if not state.canvasW or state.canvasW <= 0 then state.canvasW = 800 end
    if not state.canvasH or state.canvasH <= 0 then state.canvasH = 600 end
    local margin = 30
    state.LEFT = -state.canvasW/2 + margin
    state.RIGHT = state.canvasW/2 - margin
    state.BOTTOM = -state.canvasH/2 + margin
    state.TOP = state.canvasH/2 - margin

    -- ★ 输入设备判断：手机触屏启用“单指切割锁 + 事件驱动坐标”；
    --   键鼠/手柄保持每帧轮询系统光标的原逻辑（GetDevice 拿不到时按键鼠处理，不影响 PC 行为）
    local okDev, dev = pcall(function() return game.GetDevice() end)
    state.deviceIsTouch = okDev and dev ~= nil
        and (dev == Enum.Device.Mobile or dev == Enum.Device.MobileController)

    state.messageText = root:GetChild("MessageText")
    state.scoreText = root:GetChild("ScoreText")
    -- 按当前显隐开关同步 MessageText 可见性（默认可见；若收到过“文本显/隐”则保持隐藏）
    if state.messageText then
        state.messageText:SetActive(state.hintTextVisible)
    end

    local dropArea = root:GetChild("DropArea")
    if dropArea then
        dropArea:AddCursorEventListener(Enum.CursorEventType.CursorDown, utils.onMouseDown)
        -- ★ 拖动跟随：触屏切割时每帧坐标由该事件写入（配合单指锁，只跟随切割手指）
        dropArea:AddCursorEventListener(Enum.CursorEventType.CursorDrag, utils.onCursorDrag)
        dropArea:AddCursorEventListener(Enum.CursorEventType.CursorUp, utils.onMouseUp)
    else
        printerr("错误：未找到 DropArea")
    end

    -- 键盘事件（受「按键绑定开/关」信号控制）
    root:AddKeyEventListener(Enum.KeyEventType.KeyboardCharacterSkill3KeyDown, keyGuard(function()
        reloadLevel()
        return true
    end))
    root:AddKeyEventListener(Enum.KeyEventType.KeyboardCharacterSkill4KeyDown, keyGuard(function()
        nextLevel()
        return true
    end))
    root:AddKeyEventListener(Enum.KeyEventType.KeyboardCraftspersonKey18Down, keyGuard(function()
        prevLevel()
        return true
    end))
    -- L 键：发起“选择关卡”客户端事件（具体下发哪一关由服务器响应“进入关卡”信号驱动）
    root:AddKeyEventListener(Enum.KeyEventType.KeyboardCraftspersonKey21Down, keyGuard(function()
        signal.send("选择关卡")
        return true
    end))

    -- ★ 监听服务器信号“进入关卡”，参数为整数关卡序号（1 起始）
    if not signal.register("进入关卡", onEnterLevel) then
        printerr("错误：注册服务器信号监听失败: 进入关卡")
    end

    -- ★ 监听服务器事件“服务器事件”，字符串参数 “开挂”/“关闭开挂” 切换开挂模式
    if not signal.register("服务器事件", onServerEvent) then
        printerr("错误：注册服务器信号监听失败: 服务器事件")
    end

    -- ★ 监听服务器信号“文本显/隐”，切换代码提示文本（MessageText）显隐
    if not signal.register("文本显/隐", onTextVisibleToggle) then
        printerr("错误：注册服务器信号监听失败: 文本显/隐")
    end

    -- ★ 监听服务器信号“按键绑定开/关”，切换键盘按键绑定是否生效
    if not signal.register("按键绑定开/关", onKeyBindToggle) then
        printerr("错误：注册服务器信号监听失败: 按键绑定开/关")
    end

    local okFirst = loadLevel(config.CURRENT_LEVEL)
    if not okFirst then
        printerr("加载关卡失败")
        -- 即使首关排程失败也要开启 Update，保证后续加载/过渡逻辑能推进
        script:EnableUpdate(true)
        return
    end

    script:EnableUpdate(true)
end

-- 胜利时：常态"等待投喂"（吞噬第 1 帧）切换为吞食动画（吞噬第 2-6 帧循环）
local function playEatAnimation()
    if not state.target or state.target.mode ~= "idle" then return end
    objectUI.destroy(state.target.ctrl)
    -- 只播放第 2-6 帧（第 1 帧为等待姿态，不参与吞噬循环）
    local eatFrames = {}
    for i = 2, #tunshi.FRAMES do
        eatFrames[#eatFrames + 1] = tunshi.FRAMES[i]
    end
    local eatAnim = { GRID = tunshi.GRID, FRAME_MS = tunshi.FRAME_MS, PALETTE = tunshi.PALETTE, FRAMES = eatFrames }
    local eatAnimInst = objectUI.createPixelSequence(
        state.containerTarget, eatAnim, state.target.x, state.target.y,
        state.target.width, state.target.width,   -- 与闲置态一致：正方形 targetWidth×targetWidth
        { prefabId = state.fruitPrefabId, block = 1 }
    )
    state.target.ctrl = eatAnimInst
    state.target.mode = "eat"
end

function OnUpdate(dt)
    if dt > 0.05 then dt = 0.05 end
    state.lastDt = dt

    -- ★ 推进物品 UI 序列帧动画（即使胜利/失败也继续播放）
    objectUI.update(dt)

    -- ★ 当前活动点刷新：键鼠每帧轮询系统光标（保留原 hover 语义）；
    --   触屏不在此轮询，坐标由 Down/Drag 事件按锁定触点写入 state.curUX/curUY，
    --   避免多指时系统光标被非切割手指带走导致切割位置跳变。
    if not state.deviceIsTouch then
        local ux, uy = game.GetCursorUIPos()
        if ux and uy then
            state.curUX = ux
            state.curUY = uy
        end
    end

    -- ★ 刀光拖尾：淡出每帧都必须运行（即使胜利/失败，已存在的刀光也要继续消散）；
    --    新片段生成仅在“按住且非拖拽且未结束”时进行。
    local playing = not (state.gameWon or state.gameFailed)
    local spawn = state.isMouseDown and not state.isDragging and playing
    local curX, curY
    if state.curUX ~= nil and state.curUY ~= nil then
        curX = state.curUX - state.canvasW/2
        curY = state.curUY - state.canvasH/2
    end
    if spawn and curX then
        bladeTrail.updateTrail(curX, curY, dt, true)
        utils.checkCut(state.lastMouseX, state.lastMouseY, curX, curY)
        state.lastMouseX = curX
        state.lastMouseY = curY
    else
        -- 未按住 / 不在游玩 / 活动点缺失：仅推进淡出，坐标不参与
        bladeTrail.updateTrail(curX or 0, curY or 0, dt, false)
    end

    utils.checkConnections()
    utils.checkBubblePop()-- 检测鼠标按下时戳破泡泡
    utils.updateDragging()

    if not state.isDragging then
        physics.updateCandyPhysics(dt)
    end

    -- 检测尖刺碰撞
    utils.checkSpikeCollision()

    -- 检测泡泡碰撞
    utils.checkBubbleCollision()

    -- 更新绳子形状
    rope.updateRopeNodesAll()

    -- 收集星星
    utils.collectStars()

    utils.checkWin()

    -- 糖果进入嘴巴瞬间，切换到吞食动画
    if state.gameWon and state.target and state.target.mode == "idle" then
        playEatAnimation()
    end

    -- ★ 全屏黑幕过渡：黑幕容器创建顺序最靠后（天然最顶），每帧推进即可
    fadeScreen.update(dt)
end

function OnDestroy()
    -- 清理
end

function getParamNumber(name, default)
    local v = script:GetParam(name)
    if type(v) == "number" then return v end
    if type(v) == "string" then
        local n = tonumber(v)
        if n then return n end
    end
    return default
end
