-- ================================================================
-- 瓦雷莎的果园救急 · 客户端主脚本
-- ================================================================
-- 分工：3D 果园棋盘与点击判定在服务器节点图里，本脚本只负责客户端 UI：
--   果园地图（横向长图选关）→ 发「进入果园」→ 游玩 HUD
--   → 等服务器「果园还原」→ 结算面板（三星 + 跑马灯 + 果汁乱飞）
--
-- 分层（一个图层一个容器，从下到上）：
--   containerScene → containerHud → containerMap → containerWin
--   → containerGuide → containerFx → containerFade
-- ★ 每个容器内按「底图 → 文字 → 点击区」创建，叠放靠创建顺序（真机后建在上），
--   每帧 raiseLayers() 把 7 个容器按 LAYER_ORDER 从下到上提一遍（模拟器顺序相反）。
-- ★ 所有可点 / 可拖区域都用「光标检测区域」元件（cursorPrefabId）。
-- ================================================================

---@diagnostic disable: undefined-global

local config = require("default_import_file/config")
local state = require("default_import_file/state")
local utils = require("default_import_file/utils")
local puzzle = require("default_import_file/puzzle")
local audio = require("default_import_file/audio")
local signal = require("default_import_file/signal")
local fadeScreen = require("default_import_file/fadeScreen")
local transition = require("default_import_file/transition")
local fx = require("default_import_file/fx")
local scene = require("default_import_file/scene")
local map = require("default_import_file/map")
local guide = require("default_import_file/guide")
local hud = require("default_import_file/hud")
local winUI = require("default_import_file/winUI")
local anim = require("default_import_file/anim")

-- 调试 / 模拟器探针用的便捷入口
_G.getOrchardLevel = config.getLevelConfig
_G.getOrchardCount = config.getLevelCount
_G.orchardBoardOfLevel = function(index)
    return puzzle.boardFromFlips(config.getLevelFlips(index))
end
_G.openLesson = function(i) return guide.openLesson(i) end
_G.openTutorial = function(from, upto) return guide.openTutorial(from, upto) end

-- 前向声明（实现处写成赋值形式，避免 local function 遮蔽）
local setScreen
local enterLevel
local sendLevelParamsNow
local flushLevelParams
local openPrologueIfNew

-- ================================================================
-- 7 层容器
-- ================================================================
local LAYER_ORDER = {
    "containerScene",     -- ① 果园背景（天空 / 远山 / 草坡 / 云 / 飘叶）
    "containerHud",       -- ② 游玩期极简 HUD
    "containerMap",       -- ③ 果园地图选关
    "containerWin",       -- ④ 胜利结算
    "containerGuide",     -- ⑤ 教学卡 / 玩法手册
    "containerFx",        -- ⑥ 果汁粒子
    "containerFade",      -- ⑦ 黑幕过渡
}

local function raiseLayers()
    for _, key in ipairs(LAYER_ORDER) do
        local c = state[key]
        if c then pcall(function() c:SetAsLastSibling() end) end
    end
end

-- ================================================================
-- UI 缩放：只放大「居中」的结算 / 教学卡两层
--   HUD 贴边、地图按画布重排，都不整体缩放。
-- ================================================================
local function computeUiScale()
    local cw = state.canvasW or config.DEFAULT_VIEW_WIDTH or 800
    local ch = state.canvasH or config.DEFAULT_VIEW_HEIGHT or 600
    local bw = config.DEFAULT_VIEW_WIDTH or 800
    local bh = config.DEFAULT_VIEW_HEIGHT or 600
    local k = math.min(cw / bw, ch / bh)
    if k < 1 then k = 1 end
    if k > 1.6 then k = 1.6 end
    return k
end

local function applyUiScale()
    state.uiScale = computeUiScale()
    for _, key in ipairs({ "containerWin", "containerGuide" }) do
        local c = state[key]
        if c then pcall(function() c:SetLocalScale(state.uiScale, state.uiScale, 1) end) end
    end
end

local function ensureContainers()
    local okAll = true
    for _, key in ipairs(LAYER_ORDER) do
        if not state[key] then
            state[key] = utils.createContainer(state.parent)
            if not state[key] then okAll = false end
        end
    end
    raiseLayers()
    applyUiScale()
    return okAll
end

-- ================================================================
-- 屏幕切换（统一走转场：先盖住 → 在盖住那一刻切界面 → 再揭开）
-- ================================================================
setScreen = function(name)
    state.screen = name
    -- ★ 离开游玩态就丢掉「还没发出去的关卡参数」：
    --   否则玩家在教程里直接回果园，稍后 flushLevelParams 会把上一关的参数补发出去，
    --   服务器就会凭空摆出一盘没人要的果园。
    if name ~= "play" then state.pendingLevelParams = 0 end
    -- ★ 游玩期必须收掉果园背景：它是盖满画布的**不透明**底色，
    --   不收会把节点图摆出来的 3D 果园整片盖住（真机实测现象）。
    scene.setVisible(name ~= "play")
    map.setVisible(name == "select")
    hud.setVisible(name == "play")
    raiseLayers()
end

-- ================================================================
-- ★「客服关卡参数」的发送时机
-- ================================================================
-- 教程关（前 5 关）进关时会先摊开教学卡。旧写法在转场揭幕那一刻就发信号，
-- 服务器于是**在玩家还在读教程时**就把果园摆出来了 —— 玩家一关教程，
-- 棋盘已经在那儿、动画也放完了，感觉像「还没开始就快进了一段」。
-- 现在改成：
--   · 需要弹教程 → 只记 pendingLevelParams，等教程关闭（真正露出游玩界面）再发；
--   · 不弹教程   → 当场发。
-- 「等服务器摆盘」的 4 秒兜底计时也从**真正发出去**那一刻才开始算，
-- 否则读教程超过 4 秒就会先把「正在摆果园…」清掉。
sendLevelParamsNow = function(idx)
    state.pendingEnterLevel = idx
    state.pendingT = 0
    if not signal.sendLevelParams(idx) then
        printerr("警告：「客服关卡参数」信号发送失败（第 " .. tostring(idx) .. " 片）")
        return false
    end
    return true
end

-- 每帧调一次：教程已关 + 仍在游玩态 + 有待发关卡 → 发出去
flushLevelParams = function()
    local idx = state.pendingLevelParams or 0
    if idx <= 0 then return false end
    if state.screen ~= "play" then return false end
    if guide.isOpen() then return false end
    state.pendingLevelParams = 0
    hud.setHint("小龙正在摆果园…")
    return sendLevelParamsNow(idx)
end

-- ★ 转场只用两种：
--   选关 → 游玩：split open（天空向上移出屏幕、地面向下移出屏幕）
--   游玩 → 选关：split close（天空自上、地面自下滑入合拢，再整体淡出）
--   关卡之间换片 / 重玩：fade（最快，不打断节奏）
local TRANS_SPLIT = "split"

-- 关内换片（上一片 / 下一片，界面还是游玩）：用黑幕，短促一点
local TRANS_SWAP = "fade"
local TRANS_SWAP_OPTS = { cover = 0.14, hold = 0.02, reveal = 0.16 }

-- 转场播不了（缺模板 / 没建出来）时 transition.play 会同步执行 onPeak，流程不会卡住。
local function playTransition(kind, onPeak, opts)
    return transition.play(kind, onPeak, opts)
end

-- ================================================================
-- 进入 / 重玩 / 下一关 / 上一关
-- ================================================================
enterLevel = function(levelIndex)
    local idx = math.floor(tonumber(levelIndex) or 0)
    local data = config.getLevelConfig(idx)
    if not data then return false end
    if not map.isUnlocked(idx) then return false end

    guide.close()
    winUI.close()
    -- ★ 从地图进关 → 天地撕开；从结算面板换片（界面仍是 play）→ 快速黑幕
    local fromSelect = (state.screen ~= "play")
    local kind = fromSelect and TRANS_SPLIT or TRANS_SWAP
    local opts = fromSelect and { mode = "open" } or TRANS_SWAP_OPTS
    playTransition(kind, function()
        state.currentLevelIndex = idx
        state.currentLevelConfig = data
        state.hudHintOverride = ""
        state.juiceLeft = -1
        setScreen("play")
        hud.setJuice(-1)
        audio.playOpen()
        -- ★ 教程关：新界面揭开的同时把本课摊在画面上（本局只弹一次）
        --   ★ 打开的是「第 1..本课」整叠教程页，当前停在本课，可往前翻看之前的课。
        --   ★★ 已通关的关卡重进**不再弹**（用户要求）：那些课他早就打过了，
        --      再拦一次纯属打扰。判定用服务器存档灌进来的 state.clearedLevels。
        local showLesson = (config.DEFAULT_GUIDE_AUTO_SHOW or 1) ~= 0
            and config.getLesson(idx)
            and not state.lessonSeen[idx]
            and not state.clearedLevels[idx]
        if showLesson then
            -- ★ 先不发「客服关卡参数」：玩家还在读教程，服务器不该现在摆盘。
            --   记 pending，等教程关闭后由 flushLevelParams（OnUpdate 每帧）补发。
            state.pendingLevelParams = idx
            state.pendingEnterLevel = 0   -- 兜底计时也一起推迟到真正发出去之后
            state.pendingT = 0
            guide.openLevelLessons(idx)
            state.lessonSeen[idx] = true
            raiseLayers()
        else
            -- 没有教程挡着 → 摆盘提示与信号都当场走
            state.pendingLevelParams = 0
            hud.setHint("小龙正在摆果园…")
            -- ★「客服关卡参数」：关卡序号 + 最小步数 + 点位序列 + 状态数组
            --   （选关进入 / 下一关 / 上一关 / 重玩都发同一条；报文构造在 signal.sendLevelParams）
            sendLevelParamsNow(idx)
        end
    end, opts)
    return true
end

-- 重玩：不换界面，只用最快的淡入淡出，避免「又是 1 秒转场」
-- ★ 重玩不会再弹教程（lessonSeen 已置位），所以参数照旧当场发。
local function replayLevel()
    local idx = state.currentLevelIndex or 1
    guide.close()
    winUI.close()
    playTransition("fade", function()
        state.hudHintOverride = ""
        state.juiceLeft = -1
        state.pendingLevelParams = 0
        setScreen("play")
        hud.setJuice(-1)
        hud.setHint("小龙重新摆这一片…")
        audio.playOpen()
        sendLevelParamsNow(idx)
    end, TRANS_SWAP_OPTS)
end

local function nextLevel()
    local n = (state.currentLevelIndex or 1) + 1
    if not config.getLevelConfig(n) then return false end
    return enterLevel(n)
end

-- ★ 上一关：只有前面还有解锁的关卡才走（第 1 片时返回 false，按钮是灰的）
local function prevLevel()
    local n = (state.currentLevelIndex or 1) - 1
    if n < 1 or not config.getLevelConfig(n) then return false end
    return enterLevel(n)
end

local function backToSelect()
    guide.close()
    winUI.close()
    -- ★ 回地图就别再补发还没发出去的关卡参数（见 setScreen 里的同样处理）
    state.pendingLevelParams = 0
    playTransition(TRANS_SPLIT, function()
        state.hudHintOverride = ""
        setScreen("select")
    end, { mode = "close" })
end

-- ================================================================
-- 教程
-- ================================================================
-- 打开「教程 / 图册」：
--   · 进关（教程关）→ guide.openLevelLessons：从本课第一页开始，可往前翻看之前的课；
--   · 点「教程」按钮 / 按 H → guide.openHandbook：从序章开始，一直可翻到「已解锁到的那一课」。
-- ★ 为什么图册开头要有序章：新手第一次进来根本不知道「红格是什么、为什么要清掉」，
--   序章用 3 页把背景（小龙把果子撞成果汁）和选关方式讲清楚，再进第 1 课讲操作。
local function handbookDepth()
    local total = math.max(1, config.getLessonCount())
    local lv = math.floor(tonumber(state.currentLevelIndex) or 1)
    for i = 1, total do
        if map.isUnlocked(i) then lv = math.max(lv, i) end
    end
    return utils.clamp(lv, 1, total)
end

local function openTutorial(fromFirst)
    local idx = handbookDepth()
    if fromFirst then
        guide.openHandbook(idx)       -- 完整图册：序章 + 第 1..idx 课
    else
        guide.openLevelLessons(idx)   -- 只看本课（可往前翻）
    end
    raiseLayers()
end

local function toggleGuide()
    if guide.isOpen() then
        guide.close()
    else
        openTutorial(true)
    end
end

-- ================================================================
-- ★★ 首屏序章：只给「新玩家」弹
-- ----------------------------------------------------------------
--   客户端不落盘，判断「是不是老玩家」只能看服务器存档：
--   已通关最新关卡 = 0 → 新玩家；> 0 → 老玩家（已通关的那一关也不再弹本课教程，
--   见 enterLevel 里的 clearedLevels 判定）。
--   ★ 存档比 OnStart 晚到（几十 ~ 几百毫秒），所以 OnStart 里**不立刻弹**：
--     先记 state.prologueDelay，等「存档到了」或「等超时」再一次性定下来 ——
--     这样老玩家不会看到序章闪一下又消失。
--     · 存档到了且 latestCleared > 0 → 什么都不弹
--     · 存档到了且 latestCleared = 0 → 弹序章
--     · 一直等不到存档（节点图没接这条信号）→ 当新玩家，弹
--   ★ prologueSeen 的语义改成「本局已经处理过这件事」，处理过就不再重复决策。
openPrologueIfNew = function()
    if state.prologueSeen then return end
    state.prologueSeen = true
    if (state.latestCleared or 0) > 0 then return end
    if guide.openPrologue() then raiseLayers() end
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

    -- 教程 / 手册打开时：← → 翻页
    bind(K.KeyboardMoveLeftKeyDown, function()
        if not guide.isOpen() then return false end
        guide.prev()
        return true
    end)
    bind(K.KeyboardCraftspersonKey38Down, function()
        if not guide.isOpen() then return false end
        guide.prev()
        return true
    end)
    bind(K.KeyboardMoveRightKeyDown, function()
        if not guide.isOpen() then return false end
        guide.next()
        return true
    end)
    bind(K.KeyboardCraftspersonKey39Down, function()
        if not guide.isOpen() then return false end
        guide.next()
        return true
    end)

    -- 空格 / W：确认
    local function confirmKey()
        if guide.isOpen() then
            guide.next()
            return true
        end
        if winUI.isOpen() then
            winUI.confirmPrimary()
            return true
        end
        if state.screen == "select" then
            map.confirm()
            return true
        end
        return false
    end
    bind(K.KeyboardJumpKeyDown, confirmKey)
    bind(K.KeyboardMoveForwardKeyDown, confirmKey)

    -- 选关：← → 换果园（游玩期不消费，留给 3D 玩法）
    local function step(dx)
        if guide.isOpen() or winUI.isOpen() then return false end
        if state.screen ~= "select" then return false end
        map.moveCursor(dx)
        return true
    end
    bind(K.KeyboardMoveLeftKeyDown, function() return step(-1) end)
    bind(K.KeyboardCraftspersonKey38Down, function() return step(-1) end)
    bind(K.KeyboardMoveRightKeyDown, function() return step(1) end)
    bind(K.KeyboardCraftspersonKey39Down, function() return step(1) end)

    -- T：教程
    bind(K.KeyboardCharacterSkill4KeyDown, function()
        toggleGuide()
        return true
    end)

    -- H：教程（任何屏幕）
    bind(K.KeyboardCharacterSkill2KeyDown, function()
        if guide.isOpen() then
            guide.close()
        else
            openTutorial(true)
        end
        return true
    end)

    -- ← → ：结算面板里换上一片 / 下一片（教程、选关各有自己的处理，互不打架）
    bind(K.KeyboardCraftspersonKey38Down, function()
        if not winUI.isOpen() then return false end
        winUI.doPrev()
        return true
    end)
    bind(K.KeyboardCraftspersonKey39Down, function()
        if not winUI.isOpen() then return false end
        winUI.doNext()
        return true
    end)

    -- R：重玩
    bind(K.KeyboardCharacterSkill3KeyDown, function()
        if guide.isOpen() then return false end
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

    -- L：回果园（★ 仅调试后门）/ 关闭覆盖层
    --   ★ 正式环境回果园由服务器信号「服客进入选关」驱动（onServerSelect），
    --     客户端不再提供按钮。这个键只为模拟器里没有节点图时能验界面而留。
    bind(K.KeyboardCraftspersonKey21Down, function()
        if guide.isOpen() then
            guide.close()
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
-- 入站信号（服客 = 服务器 → 客户端）
-- ================================================================
-- ①「服客进入关卡」关卡序号 : 整数 —— 节点图摆好棋盘了
local function onServerEnter(name, params)
    local idx = signal.getIntParam(params, 1)
    if idx and config.getLevelConfig(idx) then
        state.currentLevelIndex = idx
        state.currentLevelConfig = config.getLevelConfig(idx)
    end
    state.pendingEnterLevel = 0
    state.pendingT = 0
    state.pendingLevelParams = 0   -- 服务器已经说「进关」了，别再补发参数
    winUI.close()
    if state.screen ~= "play" then
        -- 正常流程客户端已经先进游玩态了（点果实当场转场），这里只是兜底
        setScreen("play")
    end
    hud.setHint("")
    raiseLayers()
end

-- ②「服客关卡胜利」关卡序号 : 整数 —— 3D 端判定全部还原
local function onServerWin(name, params)
    local idx = signal.getIntParam(params, 1)
    if not idx or not config.getLevelConfig(idx) then
        idx = state.currentLevelIndex
    end
    if not config.getLevelConfig(idx) then return end

    state.currentLevelIndex = idx
    state.currentLevelConfig = config.getLevelConfig(idx)
    state.pendingEnterLevel = 0
    state.pendingT = 0
    state.pendingLevelParams = 0   -- 已经赢了，不需要再通知服务器摆盘
    audio.playWin()
    guide.close()
    -- ★ 协议里「关卡胜利」只带关卡序号，星级由客户端记（默认满星；后续要按步数扣星只改这里）
    local stars = 3
    map.markCleared(idx, stars)

    if (config.DEFAULT_WIN_AUTO_SHOW or 1) ~= 0 then
        setScreen("play")
        -- ★ 结算期间把游玩 HUD 收掉：它是贴在四角的实色卡片，
        --   透过奶油遮罩还能看见，和结算面板抢注意力（实拍确认）。
        --   离开结算的所有路径（重玩 / 上下一片 / 回地图）都会重新 setScreen，HUD 自然回来。
        hud.setVisible(false)
        hud.setHint("")
        winUI.open(idx)
        raiseLayers()
    else
        hud.setHint("这片果园救回来了！")
    end
end

-- ③「服客进入选关」（无参数）—— 服务器要求回果园地图
local function onServerSelect(name, params)
    if state.screen == "select" and not winUI.isOpen() then return end
    winUI.close()
    guide.close()
    state.hudHintOverride = ""
    -- ★ 转场揭幕前 screen 还是 "play"，必须先把待发参数丢掉，
    --   否则 flushLevelParams 会在这几帧里把上一关的盘面补发出去。
    state.pendingLevelParams = 0
    playTransition(TRANS_SPLIT, function()
        setScreen("select")
    end, { mode = "close" })
end

-- ④「服客同步存档信息」已通关的最新关卡序号 : 整数（1 基；0 = 一片都没通关）
--   ★ 协议只有一个参数：通关是直线（进第 2 片的前提是第 1 片已通关），
--     所以「已通关到第 N 片」= 第 1..N 片全部通关，解锁上限由客户端按 N+1 推出。
--   存档（进度 / 星级）只在服务器上，客户端收到就覆盖本地，
--   并把选关光标自动对齐到「刚解锁的那一片」。
local function onServerSave(name, params)
    local latest = signal.getIntParam(params, 1)
    if not latest then
        printerr("提示：「服客同步存档信息」缺少参数（已通关最新关卡序号），已忽略")
        return
    end
    -- ★ 旧协议（第 2 参 = 已通关列表）不再支持，但要**吵一声**：
    --   节点图没改时静默按新口径解析，会把「已解锁」当成「已通关」，进度整体错一位。
    local stale = signal.getIntListParam(params, 2)
    if #stale > 0 then
        printerr("警告：「服客同步存档信息」还在发旧协议（第 2 参 = 已通关列表），已被忽略；" ..
                 "新协议只发 1 个整数「已通关最新关卡序号」—— 请改节点图")
    end
    -- ★ 这一条也是「是不是老玩家」的唯一依据 → 收到就立刻定序章的命运
    state.saveSynced = true
    state.latestCleared = math.max(0, latest)
    local cursor = map.applySave(latest)
    -- ★ 老玩家：万一序章已经弹出来了（存档来得特别晚），当场收掉。
    --   先把 guideKind 摘掉，否则「关闭」会走成「序章读完了」→ 反而去点亮「进入果园」。
    if state.latestCleared > 0 and guide.isOpen() and state.guideKind == "prologue" then
        state.guideKind = ""
        guide.close()
    end
    print("已同步存档：已通关到第 " .. tostring(math.min(latest, config.getLevelCount())) ..
          " 片，光标对齐第 " .. tostring(cursor) .. " 片")
end

-- ================================================================
-- 生命周期
-- ================================================================
function OnStart()
    local root = script.object
    if not root then
        printerr("错误：script.object 为 nil，请把本脚本挂在【客户端控件容器】的容器节点上")
        return
    end
    state.parent = root

    -- ★★ 清掉挂载节点自带的示例控件：模拟器的「Lua实例化面板」会在 parent 下
    --   预置一个写着「文本」的文本框 + 按钮 + 文本窗口 + 图片，正正地画在画布中央
    --   （2026-10-19 实测；存档里 n1.children 已清空，是 studio 打开时自动补的）。
    --   真机上 parent 是干净的，这里是空操作。
    --   ★ API 是 GetChildren()，不是 .children 字段（写成字段名静默拿到 nil）。
    pcall(function()
        local kids = root:GetChildren() or {}
        for i = #kids, 1, -1 do
            pcall(function() kids[i]:SetActive(false) end)
        end
    end)

    state.rectPrefabId = getParamNumber("rectPrefabId", 0)
    if state.rectPrefabId <= 0 then
        printerr("错误：请设置脚本参数 rectPrefabId（纯色矩形底图）")
        return
    end
    state.textPrefabId = getParamNumber("textPrefabId", 0)
    -- ★ 可选：圆形 / 圆环图元。不配就退化成矩形（形状变方，功能不受影响）。
    state.circlePrefabId = getParamNumber("circlePrefabId", 0)
    state.ringPrefabId = getParamNumber("ringPrefabId", 0)
    state.trianglePrefabId = getParamNumber("trianglePrefabId", 0)
    state.star4PrefabId = getParamNumber("star4PrefabId", 0)
    state.star5PrefabId = getParamNumber("star5PrefabId", 0)
    state.cursorPrefabId = getParamNumber("cursorPrefabId", 0)
    if state.cursorPrefabId <= 0 then
        printerr("警告：未配置 cursorPrefabId（光标检测区域）—— 地图拖拽与所有点击都不可用。" ..
                 "键盘仍可操作。")
    end
    -- ★ 可选：真容器模板。模拟器的命中测试只下钻真容器，配了它跨端一致。
    state.containerPrefabId = getParamNumber("containerPrefabId", 0)

    script:EnableUpdate(true)

    state.clickAudioId = getParamNumber("clickAudioId", 0)
    -- ★ 拖动音效：没单独配 dragAudioId 时**复用点击音**（用户要求「拖动地图也要有声音」，
    --   但不想为此再多配一个元件）。两者都 <=0 时静默。
    state.dragAudioId = getParamNumber("dragAudioId", 0)
    if state.dragAudioId <= 0 then state.dragAudioId = state.clickAudioId end
    state.openAudioId = getParamNumber("openAudioId", 0)
    state.winAudioId = getParamNumber("winAudioId", 0)
    audio.init({
        click = state.clickAudioId,
        drag  = state.dragAudioId,
        open  = state.openAudioId,
        win   = state.winAudioId,
    })
    audio.prewarm()

    local okSize, w, h = pcall(function() return game.GetUICanvasSize() end)
    if okSize and type(w) == "number" and w > 0 then state.canvasW = w else state.canvasW = config.DEFAULT_VIEW_WIDTH end
    if okSize and type(h) == "number" and h > 0 then state.canvasH = h else state.canvasH = config.DEFAULT_VIEW_HEIGHT end
    state.LEFT = -state.canvasW / 2
    state.RIGHT = state.canvasW / 2
    state.BOTTOM = -state.canvasH / 2
    state.TOP = state.canvasH / 2

    ensureContainers()
    fadeScreen.init()
    transition.init()
    local pal = utils.resolvePalette(state.currentLevelConfig)
    scene.init(pal)
    fx.init(pal)

    if not map.init() then printerr("警告：果园地图初始化失败") end
    if not guide.init() then printerr("警告：教学卡初始化失败") end
    if not hud.init() then printerr("警告：游玩 HUD 初始化失败") end
    if not winUI.init() then printerr("警告：胜利结算初始化失败") end

    map.setActions({
        onEnter = function(idx) enterLevel(idx) end,
        onTutorial = function() openTutorial(true); raiseLayers() end,
    })
    -- ★ 游玩 HUD 已无按钮（用户要求）：不再需要 setActions。
    --   回果园只认服务器信号「服客进入选关」（onServerSelect）。
    --   游玩期看教程走键盘 H / T（openTutorial 仍由 key 绑定调用）。
    winUI.setActions({
        onReplay = function() replayLevel() end,
        onPrev = function() prevLevel() end,
        onNext = function() nextLevel() end,
        onBackToSelect = function() backToSelect() end,
    })

    state.deviceIsTouch = detectTouchDevice()
    bindKeys(root)

    if not signal.register(signal.SIGNAL_S2C_ENTER, onServerEnter) then
        printerr("错误：注册信号失败: " .. signal.SIGNAL_S2C_ENTER)
    end
    if not signal.register(signal.SIGNAL_S2C_WIN, onServerWin) then
        printerr("错误：注册信号失败: " .. signal.SIGNAL_S2C_WIN)
    end
    if not signal.register(signal.SIGNAL_S2C_SELECT, onServerSelect) then
        printerr("错误：注册信号失败: " .. signal.SIGNAL_S2C_SELECT)
    end
    if not signal.register(signal.SIGNAL_S2C_SAVE, onServerSave) then
        printerr("错误：注册信号失败: " .. signal.SIGNAL_S2C_SAVE)
    end

    -- 首屏：果园地图
    setScreen("select")

    -- ★★ 序章：**不在这里立刻弹**，先挂一个「最多等多久存档」的倒计时。
    --   序章 2 页 = 小龙闯了什么祸（背景）→ 你是谁（魂附小龙）；
    --   原第 3 页「怎么挑果园」已删，改成「关掉序章后点亮『进入果园』按钮」。
    --   ★ 老玩家（服务器说已通关 > 0）不该再被拦一次，但存档比 OnStart 晚到，
    --     所以真正的决策在 OnUpdate（见 openPrologueIfNew）。
    state.prologueDelay = config.DEFAULT_PROLOGUE_WAIT or 0.6
end

-- ================================================================
-- 每帧
-- ================================================================
function OnUpdate(dt)
    if dt > 0.05 then dt = 0.05 end
    state.lastDt = dt
    fx.update(dt)          -- 先推进全局时间，其它模块的呼吸/飘动都读 state.fxTime
    anim.update(dt)
    scene.update(dt)
    map.update(dt)
    guide.update(dt)
    hud.update(dt)
    winUI.update(dt)
    fadeScreen.update(dt)
    transition.update(dt)   -- 转场放在最后：它是 7 层里最顶的那层，晚一帧也没关系但要压在别人上面

    -- ★ 教程关：玩家关掉教程、真正露出游玩界面的这一帧，才通知服务器摆盘。
    --   放在 transition.update 之后，保证「转场已经揭开 + 教程已关」两者都成立。
    flushLevelParams()

    -- ★★ 序章决策（只做一次）：存档到了立刻定，等超时就当新玩家。
    --   ★ 必须在 map.update / guide.update 之后、且只用一次 → 倒计时清零即不再进来。
    if (state.prologueDelay or 0) > 0 then
        state.prologueDelay = math.max(0, state.prologueDelay - dt)
        if state.saveSynced or state.prologueDelay <= 0 then
            state.prologueDelay = 0
            openPrologueIfNew()
        end
    end

    -- ★★ 序章读完 → 在地图上点亮「进入果园」按钮并指向它。
    --   触发条件三者同时成立：① guide 关掉序章时置了 pending；
    --   ② 教程确实已经关掉（不是还有别的教程盖着）；③ 当前就在选关页。
    --   消费一次即清零（map.guideEnter(false) 也会顺手清，见 map.lua）。
    if state.prologueGuidePending and not guide.isOpen() and state.screen == "select" then
        state.prologueGuidePending = false
        map.guideEnter(true)
    end

    -- 等服务器布置果园的超时兜底：4 秒还没回话就别一直显示「正在布置」
    if (state.pendingEnterLevel or 0) > 0 then
        state.pendingT = (state.pendingT or 0) + dt
        if state.pendingT > 4 then
            state.pendingEnterLevel = 0
            hud.setHint("")
        end
    end
end

function OnDestroy()
    -- 控件随容器释放，无需额外清理
end

-- ================================================================
-- 工具
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

function detectTouchDevice()
    local ok, dev = pcall(function() return game.GetDevice() end)
    if not ok then return false end
    return dev == Enum.Device.Mobile or dev == Enum.Device.MobileController
end
