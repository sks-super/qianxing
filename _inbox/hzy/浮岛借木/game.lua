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
local openSign, closeSign, advanceSign, renderSign
local doUndo

-- ================================================================
-- ★ 创建一个透明容器父节点（定位于世界原点，子节点坐标即世界坐标）
--   ★ 优先用「容器节点」元件（1073741876 / 内部名 SoloTurnPoolHost）创建：
--     它本身不绘制任何图形、也不需要图源，天生就是用来组织子控件的，
--     比拿「图片」元件当父节点干净（图片元件在真机上没配图会画成「?」占位框，
--     虽然 alpha=0 看不见，但白占一层渲染）。
--   ★ 容器节点模板缺失时（老存档 / 没在编辑器里登记）回退用矩形元件，
--     保证任何情况下都能跑起来。
-- ================================================================
local function createContainer(host)
    host = host or state.parent       -- ★ 第 22 批：允许指定父容器（世界层里再分层）
    if not host then return nil end

    -- ① 首选：容器节点元件
    local cid = state.containerPrefabId or 0
    if cid > 0 then
        local ok, c = pcall(game.InstantiateClientUIControl, cid, host)
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
    local c = utils.instantiateRect(host)
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
-- ★ 固定图层（第 22 批，按用户要求改成纯控件容器分层）
--   从下到上：**地面 → 石头 → 树木 → 角色**，再往上是特效 / HUD / 黑幕。
--     containerBg       海面整屏底
--     containerGround   地面层（内部再分 侧面 / 描边 / 顶面 / 树桩 四个子层）
--     containerWorld    世界总层（不画东西，只是下面几层的父节点 + 镜头平移对象）
--       containerRock   石头层（站在小人**后面**的柱子）
--       containerTree   树木层（立树 / 倒木 / 木筏 / 木牌 / 过渡代理）
--       containerPlayer 角色层
--       containerRockFront ★ 第 42 批：石头·前景层（站在小人**前面**的柱子，会挡住角色）
--     containerFx / containerHud / containerFade
--   ★ 层级 = **容器创建顺序**，一次建好后不再变；不靠 SetAsLastSibling，
--     所以对象池扩容、窗口重铺都不会把角色埋进地图里。
--   ★ 层与层之间不再做深度穿插；层**内部**仍按深度键排序。
--   ★ 第 42 批唯一的例外是石头：要「挡住角色」就必须跨到角色上下两侧，
--     于是拆成 rock / rockFront 两个固定层（两个池也分开了，见 state.rockFrontCtrls）。
-- ================================================================
local function ensureContainers()
    local order = {
        "containerBg",        -- ① 海面（整屏底）
        "containerGround",    -- ② 地面层：水面网格 / 地块侧面 / 岛缘描边 / 草地顶面 / 树桩
        "containerWorld",     -- ③ 世界总层（下面四个固定物体层的父节点）
        "containerFx",        -- ④ 特效（涟漪）
        "containerHud",       -- ⑤ HUD（关卡名 / 步数 / 消息 / 提示）
        "containerFade",      -- ⑥ 黑幕过渡（最顶）
    }
    local okAll = true
    local changed = false
    for _, key in ipairs(order) do
        if not state[key] then
            state[key] = createContainer()
            changed = true
            if not state[key] then okAll = false end
        end
    end
    -- ★ 四个固定物体层：**必须按 石头 → 树木 → 角色 → 石头(前景) 的顺序建**（这就是层序）。
    --   挂在世界总层下面，镜头只平移世界总层，几层一起跟着走。
    for _, key in ipairs({ "containerRock", "containerTree", "containerPlayer", "containerRockFront" }) do
        if not state[key] then
            state[key] = createContainer(state.containerWorld)
            changed = true
            if not state[key] then okAll = false end
        end
    end
    -- ★ 图层顺序日志（第 22 批追加）：容器**新建 / 补建**才是「图层变更」——
    --   ensureContainers 会被多个入口反复调，层级没变就不打（否则一屏重复六次）。
    --   此刻地面四个子层尚未建，会如实标「未建」；它们在 level.build →
    --   ensureGroundLayers 里补齐后由「关卡构建完成」再打一次。
    if okAll and changed then
        pcall(function() level.logLayerOrder("容器创建/补建") end)
    end
    return okAll
end

-- ================================================================
-- ★ 走一步（输入层 → 规则层 → 表现层）
-- ================================================================
local function tryMove(key)
    if not state.keysEnabled then return end
    if state.signOpen then return end              -- 正在读牌子：先按空格翻页 / 关掉
    if state.pendingStart then return end          -- 黑幕还没散尽，先别动
    if state.won then return end                   -- 已通关，锁住输入
    if (state.actionLock or 0) > 0 then return end -- 动作冷却中

    -- ★ 转身：先换朝向（= 换一张立绘），再判能不能走。
    --   放在 world.step 之前，是为了「撞墙 / 被挡住也会转过去」——
    --   否则按了左键人还是面朝下，会显得不受控。
    level.setPlayerFacing(key)

    world.pushUndo()                               -- ★ 走之前压一份快照（Z 撤销用）
    local act = world.step(key)
    local kind = act.kind or "invalid"

    -- ★ 读到木牌：弹面板。读到「终点牌」= 通关 —— MExp 的胜利条件就是**读它**，
    --   不是走到某一格。所以这里要在「走 / 推」那套分支之前单独接住。
    if act.interact then
        openSign(act.signPages)
        if world.isWin() then
            state.won = true
            level.updateHudDisplay()
        end
        state.actionLock = config.DEFAULT_ACTION_COOLDOWN or 0.1
        return
    end

    if act.ok then
        state.steps = (state.steps or 0) + 1
        state.lastAction = kind
        if act.moved then
            local dur = config.DEFAULT_STEP_ANIM_TIME
            if kind ~= "move" then dur = config.DEFAULT_ACTION_ANIM_TIME end
            -- ★ 第 37 批：单纯走路按**实际距离**缩放时长（连按不会忽快忽慢）；
            --   推 / 撞 / 滑那几种仍用固定时长 —— 它们要读的是动作本身。
            level.beginPlayerMove(dur, kind == "move")
        end
        if act.changed then
            -- ★ 先登记「倒 / 立 / 侧推」的过渡，再重建：
            --   rebuild 会跳过终点格上的真实木头，把那一格让给过渡代理逐帧画。
            level.setObjectAnim(act)
            level.rebuildObjects()
        end
        level.spawnRipple(act.c, act.r)
        -- ★ 木头落点补一圈扬尘：撞倒砸得重（大圈），立起 / 侧推轻（小圈）
        if act.animTo then
            if kind == "knock" then
                level.spawnDust(act.animTo.c, act.animTo.r, 1.5)
            elseif kind == "raise" or kind == "slide" then
                level.spawnDust(act.animTo.c, act.animTo.r, 0.85)
            end
        end
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
        utils.hexToColorA(palette.hudBar, config.DEFAULT_HUD_ALPHA or 230),
        state.containerHud)

    -- ★ 底部信息条底（第 14 批新增）
    --   放大之后地图会铺到屏幕下沿，消息 / 提示文字会直接压在草地上
    --   （白字压深绿，勉强能看但很脏）→ 补一条与顶部同款的底色带。
    --   高度 = 底部预留高度，正好覆盖「一步一报」的消息行与三行提示。
    local reserveH = config.DEFAULT_HUD_BOTTOM_RESERVE or 124
    state.hudBottomBar = utils.createControl(
        state.rectPrefabId, 0, -ch / 2 + reserveH / 2, cw + 80, reserveH,
        utils.hexToColorA(palette.hudBar, config.DEFAULT_HUD_ALPHA or 230),
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

    -- ★ 木牌对话框（读到牌子时弹出）
    --   MExp 的「通关」是**读牌子**，不是走到某一格 —— 没有这块面板，
    --   玩家只会觉得自己撞在了一块牌子上。所以牌面必须能看清正文。
    local pw, phh = cw * 0.66, ch * 0.46
    state.signPanel = utils.createControl(
        state.rectPrefabId, 0, ch * 0.03, pw, phh,
        utils.hexToColorA(palette.hudBar, 246), state.containerHud)
    state.signText = utils.createText(
        0, ch * 0.03 + 12, pw - 72, phh - 78, "",
        utils.hexToColor(palette.hint), config.DEFAULT_SIGN_FONT or 26,
        state.containerHud)
    state.signPageText = utils.createText(
        0, ch * 0.03 - phh * 0.5 + 22, pw - 72, 30, "",
        utils.hexToColor(palette.hud), config.DEFAULT_HUD_HINT_SIZE or 20,
        state.containerHud)
    utils.setVisible(state.signPanel, false)
    utils.setVisible(state.signText, false)
    utils.setVisible(state.signPageText, false)
end

-- ================================================================
-- ★ 木牌对话框
--   空格 = 翻页（最后一页再按一次就关）；任何换图 / 重开也会自动关掉。
-- ================================================================
renderSign = function()
    if not state.signOpen then
        utils.setVisible(state.signPanel, false)
        utils.setVisible(state.signText, false)
        utils.setVisible(state.signPageText, false)
        return
    end
    local pages = state.signPages or {}
    local i = state.signPage or 1
    if i > #pages then i = #pages end
    if i < 1 then i = 1 end
    state.signPage = i
    local palette = utils.resolvePalette(state.levelConfig)
    utils.setVisible(state.signPanel, true)
    utils.setVisible(state.signText, true)
    utils.setVisible(state.signPageText, true)
    utils.setText(state.signText, pages[i] or "")
    utils.setTextColor(state.signText, palette.hint, 255)
    utils.setTextColor(state.signPageText, palette.hud, 200)
    utils.setText(state.signPageText,
        (#pages > 1) and string.format("%d / %d　空格继续", i, #pages)
                     or "空格关闭")
end

openSign = function(pages)
    state.signPages = pages or { "（牌子上的字已经看不清了）" }
    state.signPage = 1
    state.signOpen = true
    renderSign()
end

closeSign = function()
    state.signOpen = false
    state.signPages = nil
    state.signPage = 1
    renderSign()
end

-- 空格：翻到下一页；已经在最后一页就关掉
advanceSign = function()
    if not state.signOpen then return end
    local n = #(state.signPages or {})
    if (state.signPage or 1) < n then
        state.signPage = (state.signPage or 1) + 1
        renderSign()
    else
        closeSign()
    end
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

    -- R：只重置玩家脚下的这座岛（第 24 批；原来的「重开本关」已去掉）
    bindGlobal(K.KeyboardCharacterSkill3KeyDown, function() resetCurrentIsland() end)
    -- T：下一关
    bindGlobal(K.KeyboardCharacterSkill4KeyDown, function() nextLevel() end)
    -- P：上一关
    bindGlobal(K.KeyboardCraftspersonKey18Down, function() prevLevel() end)
    -- F：显示 / 隐藏提示
    bindGlobal(K.KeyboardInteractKeyDown, function()
        state.hintsOn = not state.hintsOn
        level.updateHudDisplay()
    end)
    -- 空格：木牌翻页 / 关闭（读到牌子时唯一能用的键）
    bindGlobal(K.KeyboardJumpKeyDown, function()
        advanceSign()
    end)
    -- Z：撤销一步（奇匠 12 = 物理键 Z）—— MExp 原版里就是 ALPHA 键
    bindGlobal(K.KeyboardCraftspersonKey12Down, function()
        doUndo()
    end)
end

-- ================================================================
-- ★ 关卡序号 → 关卡数据
--   ★ 两种来源，序号统一走「真实地图优先」：
--     ① 有 mexp_maps  → 序号就是 M.ORDER 的下标
--     ② 没有 mexp_maps → 退回 config.LEVELS（编辑器自制关）
--   ★ 第 24 批：`M.ORDER` 里只留了第一大关「沙洲群岛」。
--     于是「序号越界」不再意味着「回退到教程关」—— 那样按 T 会掉进
--     config.LEVELS 的旧教程关里。这里改成：**有真实地图就只在真实地图里循环**，
--     序号超界一律回绕到第 1 关（这样 T / P / startMap 都不会跑出沙洲群岛）。
-- ================================================================
local function levelAt(idx)
    local i = math.floor(tonumber(idx) or 0)
    local total = world.mapCount()
    if total > 0 then
        -- 回绕（1 起始）：i=0 → 最后一关，i=total+1 → 第 1 关
        local k = (i - 1) % total + 1
        local key = world.mapKeyAt(k)
        if key then return { mapKey = key, name = world.mapName(key) }, key, k end
        return nil
    end
    local data = config.getLevelConfig(i)
    if not data then return nil end
    return data, nil, i
end

local function levelTotal()
    local n = world.mapCount()
    if n > 0 then return n end
    return config.getLevelCount()
end

-- ================================================================
-- ★ 加载指定关卡（1 起始）：黑幕掩护下重建
-- ================================================================
function loadLevel(levelIndex)
    local idx = math.floor(tonumber(levelIndex) or 0)
    local data, mapKey, realIdx = levelAt(idx)
    if not data then return false end
    idx = realIdx or idx            -- ★ 越界已回绕，用实际落入的序号
    if not ensureContainers() then return false end

    fadeScreen.start({
        onPeak = function()
            doLoadLevel(idx, data, mapKey)
        end,
    })
    return true
end

-- ================================================================
-- ★ 实际关卡重建（黑幕渐显完成、渐隐开始前调用）
-- ================================================================
doLoadLevel = function(idx, data, mapKey)
    state.levelIndex = idx
    state.levelConfig = data
    closeSign()

    -- 输入与节奏复位
    state.keysEnabled = true
    state.pendingStart = true      -- 等黑幕散尽再放开输入
    state.actionLock = 0
    state.heldW, state.heldA, state.heldS, state.heldD = false, false, false, false

    if not level.build(data, mapKey) then
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

-- ================================================================
-- ★ R：只重置**玩家脚下的这座岛**（第 24 批）
--   语义 = MExp 原版的 RSTI（见 World:resetIsland）：
--     该岛的树 / 木头 / 木筏全部还原，玩家回到该岛的出生点。
--   ★ 和「重开本关」的区别：其它岛不动、全局步数不动、地图不重建
--     —— 所以黑幕都不用拉，当场就复位了。
--   ★ 撤销栈由 world.resetIsland 清空并重压基准快照：复位前的快照
--     记的是旧布局，留着退回去会和现状打架。
-- ================================================================
function resetCurrentIsland()
    if not state.keysEnabled then return end
    if state.pendingStart then return end
    local d = world.playerIsland()
    if not d or d <= 0 then
        utils.setMessage("脚下不是岛，没有可重置的东西")
        return
    end
    closeSign()
    state.objAnimActive = false
    state.objAnimFrom, state.objAnimTo = nil, nil
    if not world.resetIsland(d) then
        utils.setMessage("这座岛已经是最初的样子了")
        return
    end
    level.rebuildObjects()
    level.syncPlayerNow()
    level.updateHudDisplay()
    audio.playStep()
    utils.setMessage("已重置脚下的岛屿")
end

function nextLevel()
    -- ★ 第 24 批：只留了沙洲群岛一张图，T / P 没有意义，明确提示一下
    if levelTotal() <= 1 then
        utils.setMessage("现在只有「沙洲群岛」一张图")
        return
    end
    local n = (state.levelIndex or 1) + 1
    if levelAt(n) then
        signal.send("进入下一关")
        loadLevel(n)
    else
        utils.setMessage("已经是最后一张图啦（T 回不去，用 P 往前）")
    end
end

function prevLevel()
    if levelTotal() <= 1 then
        utils.setMessage("现在只有「沙洲群岛」一张图")
        return
    end
    local p = (state.levelIndex or 1) - 1
    if levelAt(p) then
        signal.send("进入上一关")
        loadLevel(p)
    end
end

-- ================================================================
-- ★ 撤销一步（Z）
--   ★ 快照栈在 world 里，本函数只负责「把表现层也一起退回去」：
--     物体重画、小人吸附、HUD 步数、关掉可能开着的木牌面板。
-- ================================================================
doUndo = function()
    if not state.keysEnabled then return end
    if state.pendingStart then return end
    if not world.canUndo() then
        utils.setMessage("没有可撤销的步骤了")
        return
    end
    -- 正在播的「倒 / 立」补间要丢掉：它画的是撤销之后不存在的形态
    state.objAnimActive = false
    state.objAnimFrom, state.objAnimTo = nil, nil
    if not world.undo() then return end
    closeSign()
    level.rebuildObjects()
    level.syncPlayerNow()
    level.updateHudDisplay()
    audio.playStep()
    utils.setMessage("撤销了一步")
end

-- ================================================================
-- ★ 通关结算（只执行一次）
-- ================================================================
local function resolveWin()
    if not state.won or state.winHandled then return end
    state.winHandled = true
    audio.playWin()

    -- ★ 第 24 批：R 已从「重开本关」改成「只重置脚下的岛屿」，这里的话术跟着改。
    --   只有一张图时不再提 T（T 会提示「只有一张图」）。
    if levelTotal() <= 1 then
        utils.setMessage("全部通关！按 R 重置脚下的岛屿")
    elseif (state.levelIndex or 1) >= levelTotal() then
        utils.setMessage("全部通关！按 R 重置脚下的岛屿")
    else
        utils.setMessage("过关！按 T 进入下一关，按 R 重置脚下的岛屿")
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
    if not levelAt(use) and levelAt(idx + 1) then
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
-- ★ 开关型 / 索引型参数的「没配」兜底
--   ⚠️ 真机脚本参数面板里**没填的数字参数会返回 0**（不是 nil）——
--      而 `getParamNumber` 的默认值只对「非数字」生效，数字 0 会原样透出。
--      于是所有「默认开」的可选项（useArt / heroPixelOn / view25d / waterGridLines）
--      在真机上全被判成 false：画面退回纯色块（小人 = F2A03C 橙色身体矩形）。
--      ★ 这就是「导入脚本后像素小人不见了、只剩一个橙色块」的真正原因。
--   约定（改这里就要改 README 参数表）：
--     · 开关：**-1 = 明确关闭**；0 / 空 = 没配 = 用 config 默认
--       （多数默认开；`waterGridLines` 第 32 批起默认**关**）
--     · 索引：0 / 空 = 无效 = 用 config 默认（0 从来不是合法元件索引）
-- ================================================================
local function paramSwitch(name, dflt)
    local v = getParamNumber(name, dflt)
    if v == nil or v == 0 then return (tonumber(dflt) or 0) > 0 end
    return v > 0
end

local function paramId(name, dflt)
    local v = getParamNumber(name, dflt)
    if v == nil or v <= 0 then return tonumber(dflt) or 0 end
    return v
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
    state.containerPrefabId = paramId("containerPrefabId", config.DEFAULT_PREFAB_CONTAINER)
    -- ★ 纯色底图模板：沙滩 / 树根 / 倒下的树 / 石头 / 终点旗 / HUD 底衬 / 涟漪 / 黑幕
    --   全靠它 + imageColor 染色画出来。
    --   首选「矩形」元件（1073741894，自带矩形图元，真机不需要再配白图）；
    --   当前存档里没有它时，utils.instantiateRect 会自动回退「图片」元件（1073741870）。
    state.rectPrefabId = paramId("rectPrefabId", config.DEFAULT_PREFAB_RECT)
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
    state.imagePrefabId = paramId("imagePrefabId", config.DEFAULT_PREFAB_IMAGE)
    -- ★ 文本模板（可选）：关卡名 / 步数 / 消息 / 提示
    --   真机内置模板索引 1073741868（文本框）
    state.textPrefabId = paramId("textPrefabId", config.DEFAULT_PREFAB_TEXT)
    -- ★ 纯色底图的图源（可选）：真机若出现「?」缺失框，填编辑器图库里的图片 ID 即可，
    --   脚本会在创建每个底图控件后 SetImage 指定；留空/0 则沿用元件自带图源。
    state.rectImageId = getParamNumber("rectImageId", config.DEFAULT_RECT_IMAGE_ID)

    -- ★ 美术素材元件（海水 / 草地 / 树木 / 人物）
    --   这 4 个元件里**已经关联好美术素材**，脚本只管把它们摆到位置上，
    --   创建时**不写 imageColor** —— 一写就把素材乘上去了（变暗、串色）。
    --   总开关 useArt 填 **-1** 才关闭（0 / 空 = 没配 = 用 DEFAULT_USE_ART）；
    --   ⚠️ 不能拿 0 当「关」：真机面板里**没填**的数字参数就是 0，会把默认开的东西全关掉。
    state.useArt = paramSwitch("useArt", config.DEFAULT_USE_ART)
    state.waterPrefabId  = paramId("waterPrefabId",  config.DEFAULT_PREFAB_WATER)
    state.landPrefabId   = paramId("landPrefabId",   config.DEFAULT_PREFAB_LAND)
    state.treePrefabId   = paramId("treePrefabId",   config.DEFAULT_PREFAB_TREE)
    state.playerPrefabId = paramId("playerPrefabId", config.DEFAULT_PREFAB_PLAYER)

    -- ★ 小人用「像素矩形绘画」而不是引用图片：
    --   数据在 heroArt.lua，运行时用几十块纯色矩形拼出角色，按朝向换一套矩形 = 转身。
    --   所以**不需要任何图片 ID**，只需要这个开关（**-1** = 退回「人物」元件自带立绘）。
    state.heroPixelOn = paramSwitch("heroPixelOn", config.DEFAULT_HERO_PIXEL_ON)
    state.playerFacing = "S"     -- 出生时面朝下（正面），第一帧就是正确的画

    -- ★ 立绘图片路径（可选，第 15 批）：填**图库图片 ID** 就用「图片」元件直接显示原画，
    --   比像素画清晰得多；一个都不填就退回像素画（保证真机不会出现一排「?」占位框）。
    --   元件默认 1073741870（官方内置「图片」）；四向共用一个控件，换朝向只换图源。
    --   缺的朝向自动回退正面（只填 heroImageS 也能跑，只是转身不变图）。
    state.heroImagePrefabId = paramId("heroImagePrefabId", config.DEFAULT_PREFAB_IMAGE)
    state.heroImageIds = {
        S = paramId("heroImageS", 0),
        W = paramId("heroImageW", 0),
        A = paramId("heroImageA", 0),
        D = paramId("heroImageD", 0),
    }
    state.heroImageOn = (state.heroImageIds.S or 0) > 0

    -- ★ 图元笔触路径（第 16 批）：把「图元拟合拼图」的四视角脚本接进来画小人。
    --   每一笔 = 一个「图片」控件 + 内置椭圆图源(100002) + imageColor 染色 + Z 轴旋转。
    --   **不需要图库、不需要上传图片** —— 纯脚本复现，且四视角可切换。
    --   heroPrimsOn 填 -1 关闭；元件/图源留空就用 config 默认（1073741870 / 100002）。
    state.heroPrSwitch = paramSwitch("heroPrimsOn", config.DEFAULT_HERO_PRIMS_ON)
    state.heroPrPrefabId = paramId("heroPrimsPrefabId", config.DEFAULT_PREFAB_HERO_PRIMS)
    state.heroPrImageId = paramId("heroPrimsImageId", config.DEFAULT_HERO_PRIMS_IMAGE)
    -- ★ 走路摆动（第 17 批）：椭圆已按部件（头/躯干/两臂/两腿）分组，
    --   每个部件绕自己的关节旋转 —— 走路时腿前后摆、手臂反相摆，加一点重心起伏。
    --   填 -1 关掉，小人退回「整体滑行」。
    state.heroWalkOn = paramSwitch("heroWalkOn", config.DEFAULT_HERO_WALK_ON)

    -- ★ 部件修饰（第 38 批 · 第 39 批改了 ①）
    --   ① 远侧手臂（第 39 批，取代第 38 批的「飘带固定」）：
    --      侧面视角摆臂时，只摆靠近镜头那条手臂；另一条被身体挡住的**钉在躯干上**。
    --      它就是用户说的「身前 / 身后那条类似领带的带状物」—— 只露贴着身体边缘的
    --      一小条，转 30° 就扫出轮廓之外。实现在 level.updateHeroWalk。
    --      取值 0~1（0 = 完全不摆，默认；1 = 两条一起摆，回到第 37 批的行为）。
    --      ⚠️ 真机没填的数字参数返回 0（不是 nil）—— 这里把 0 也当成「没配」，
    --         让 config.DEFAULT_HERO_FAR_ARM 永远是唯一真源（改成别的值也生效）。
    local fa = getParamNumber("heroFarArm", config.DEFAULT_HERO_FAR_ARM)
    if fa == nil or fa == 0 then fa = tonumber(config.DEFAULT_HERO_FAR_ARM) or 0 end
    state.heroFarArm = utils.clamp(fa, 0, 1)

    -- ★ 2.5D 视角（可选）：地块厚度 + 岛缘投影
    --   view25d = 0 → 退回改动前的平面正交画法（沙边改用 DEFAULT_COAST_PAD 像素）
    --   waterGridLines = 0 → 水面**不画格子线**（★ 第 32 批改为默认；填 1 可恢复）
    state.view25d = paramSwitch("view25d", config.DEFAULT_VIEW_25D)
    state.waterGridLines = paramSwitch("waterGridLines", config.DEFAULT_WATER_GRID_LINES)

    -- ★ 石头 → 图腾柱（第 40 批）
    --   rockPillar = -1 → 回到「两块纯色矩形」的旧石块（0 / 空 = 按 config 默认，即柱子）。
    --   pillarGlow = -1 / 0 → 只画核心层（少 38% 控件，柱子会闷一点）。
    --   ⚠️ 只是画法：石头照样不可通行、推不动，规则层一行没动。
    state.rockPillar = paramSwitch("rockPillar", config.DEFAULT_ROCK_PILLAR)
    state.rockPillarGlow = paramSwitch("pillarGlow", config.DEFAULT_PILLAR_GLOW)
    --   pillarOcclude = -1 → 柱子不再遮挡角色（石头层退回单层，控件数略省）。
    --   ★ 第 42 批：柱子按「脚线比小人更靠下」分到前景层（在小人之上），
    --     于是「小人站在柱子后面」会被柱子挡住。关掉就没有这个遮挡。
    state.pillarOcclude = paramSwitch("pillarOcclude", config.DEFAULT_PILLAR_OCCLUDE)

    -- ★ 地图主题（第 34 批加入，第 35 批默认回退到海面）
    --   skyIsland = 1 → 空中岛屿；0 / 空 / -1 → 原来的海面主题（★ 现在默认这一支）。
    --   ⚠️ 写 "sky"/"sea" 字符串而不是布尔：下游要按主题分支（背景 / 岛底 / 顶面画法），
    --     以后加第三种（夜空 / 熔岩）只需要再加一个字符串，不用改一堆 if。
    state.theme = paramSwitch("skyIsland", config.DEFAULT_SKY_ISLAND) and "sky" or "sea"

    -- ★ 镜头放大（可选）：地块 / 树 / 石头 / 小人 / 旗子一律按倍数放大；海面与 HUD 不放大。
    --   0 / 空 = 没配 = 用 config 默认（DEFAULT_VIEW_ZOOM = 4.5 倍）；
    --   填 1 = 退回「整张地图正好一屏」的老样子。
    --   ⚠️ 不能写 0 当「关」：真机里没填的数字参数就是 0。
    --   ★ 第 33 批：上限 4 → 6 —— 默认值已经是 4.5，旧上限会把它夹回 4（放大 1.5 倍失效）。
    local vz = getParamNumber("viewZoom", config.DEFAULT_VIEW_ZOOM)
    if vz == nil or vz <= 0 then vz = config.DEFAULT_VIEW_ZOOM end
    state.viewZoom = utils.clamp(vz, 0.5, 6)
    state.camFollow = config.DEFAULT_CAM_FOLLOW or 1

    -- ★ 参数快照：真机「为什么全是纯色块 / 小人是个橙块」时，先看这一行。
    --   只打一次；print 被裁掉就跳过。
    if type(print) == "function" then
        pcall(print, string.format(
            "[浮岛借木] 参数 useArt=%s heroPixelOn=%s heroPrimsOn=%s view25d=%s zoom=%s theme=%s | 元件 rect=%s container=%s player=%s prims=%s | 立绘图 S=%s W=%s A=%s D=%s",
            tostring(state.useArt), tostring(state.heroPixelOn),
            tostring(state.heroPrSwitch),
            tostring(state.view25d), tostring(state.viewZoom),
            tostring(state.theme),
            tostring(state.rectPrefabId), tostring(state.containerPrefabId),
            tostring(state.playerPrefabId), tostring(state.heroPrPrefabId),
            tostring(state.heroImageIds.S), tostring(state.heroImageIds.W),
            tostring(state.heroImageIds.A), tostring(state.heroImageIds.D)))
        -- ★ 版本戳：一眼看出编辑器里 level 脚本是不是最新那份。
        --   level=b11 且 heroArt=有/无 都正常（像素画已经内置，不依赖 heroArt.lua）。
        --   如果这里打的是「旧版」，说明 level.lua 还是老的，重新导入它。
        pcall(print, string.format(
            "[浮岛借木] 版本 level=%s | heroArt 脚本=%s",
            tostring(level.BUILD or "旧版（请重新导入 level.lua）"),
            level.HERO_ART_LOADED and "有" or "无（不影响，用内置数据）"))
    end

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
    --   startMap 是给调试用的：填 N 就直接进第 N 张图（0 / 空 = 第 1 张）。
    --   12 张真实地图跨度很大（lake 全是水、cliffs 高差上百层），
    --   没有这个入口，验一张图就得连按 9 次「下一关」。
    local sm = getParamNumber("startMap", 0)
    if sm == nil or sm < 1 then sm = 1 end
    if sm > levelTotal() then sm = levelTotal() end
    loadLevel(sm)
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
