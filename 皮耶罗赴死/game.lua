-- ================================================================
-- 皮耶罗：赴死（I wanna weigh the life）· 入口
-- ================================================================
-- 挂载：客户端控件容器的【容器节点】（script.object）
--
-- 参数：
--   rectPrefabId      必填 · 纯色矩形（图片控件），所有图元都由它染色
--   textPrefabId      必填 · 文本框
--   cursorPrefabId    必填 · 光标检测区域（没有它菜单点不动）
--   containerPrefabId 可选 · 真容器模板（模拟器里建议配）
--   音效（可选）：clickAudioId / jumpAudioId / deathAudioId / winAudioId /
--                 popAudioId / openAudioId
--   开发用：
--     ghost=0/1   不死诅咒（鬼魂模式），默认 1
--     comic=0/1   过关结算漫画，默认 1
--     start=0     0 = 进菜单（默认）；N = 直接进第 N 关
--
-- 流程：菜单 → 关卡（30 关）→ 穿过门 → 献祭演出 → 下一关 → 轮回
-- ================================================================

---@diagnostic disable: undefined-global

local state = require("default_import_file/state")
local config = require("default_import_file/config")
local utils = require("default_import_file/utils")
local anim = require("default_import_file/anim")
local level = require("default_import_file/level")
local player = require("default_import_file/player")
local hud = require("default_import_file/hud")
local menu = require("default_import_file/menu")
local comic = require("default_import_file/comic")
local fadeScreen = require("default_import_file/fadeScreen")
local audio = require("default_import_file/audio")
local fx = require("default_import_file/fx")

-- ★ 前置声明：这些函数互相引用（startLevel ↔ advance ↔ showEnd ↔ backToMenu）
local startLevel, doWin, doDie, advance, backToMenu, showEnd, hideEnd, bindKeys

local jumpPrev = false
local endParts = {}

-- ================================================================
-- ★ 真机的接口是 script:GetParam(name)（GetParamValue 只有模拟器认）
-- ================================================================
local function getParamNumber(name, default)
    local v = nil
    local ok = pcall(function() v = script:GetParam(name) end)
    if not ok or v == nil then
        pcall(function() v = script:GetParamValue(name) end)
    end
    if type(v) == "number" then return v end
    if type(v) == "string" then
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
    local s = state.containerScene
    if not state.containerBg then state.containerBg = utils.createContainer(s) end
    if not state.containerStain then state.containerStain = utils.createContainer(s) end
    if not state.containerWorld then state.containerWorld = utils.createContainer(s) end
    if not state.containerPlayer then state.containerPlayer = utils.createContainer(s) end
    if not state.containerFx then state.containerFx = utils.createContainer(s) end
    if not state.containerHud then state.containerHud = utils.createContainer(s) end
    if not state.containerMenu then state.containerMenu = utils.createContainer(s) end
    if not state.containerTop then state.containerTop = utils.createContainer(s) end
    if not state.containerFade then state.containerFade = utils.createContainer(s) end

    utils.applyLayerOrder({
        state.containerBg, state.containerStain, state.containerWorld,
        state.containerPlayer, state.containerFx, state.containerHud,
        state.containerMenu, state.containerTop, state.containerFade,
    })
    return true
end

local function createBackground()
    if not state.containerBg or (state.rectPrefabId or 0) <= 0 then return end
    utils.createControl(state.rectPrefabId, 0, 0, 2600, 1600,
        utils.hexToColor(utils.pal("bg")), state.containerBg)
    utils.createControl(state.rectPrefabId, 0, 250, 2600, 130,
        utils.hexToColorA(utils.pal("bg2"), 90), state.containerBg)
    utils.createControl(state.rectPrefabId, 0, -250, 2600, 130,
        utils.hexToColorA(utils.pal("wipe"), 120), state.containerBg)
end

-- ================================================================
local function resetInput()
    state.keyLeft = false
    state.keyRight = false
    state.keyUp = false
    state.keyDown = false
    state.keyJump = false
    state.jumpBuffer = 0
    jumpPrev = false
end

-- ================================================================
-- 关卡流程
-- ================================================================
startLevel = function(idx)
    local def = config.getLevel(idx)
    if not def then return end
    comic.stop()
    hideEnd()

    state.levelIndex = idx
    level.build(def)
    fx.resetAll()

    resetInput()
    player.spawn(def.spawn)
    player.show()

    -- 开发用：把玩家直接放到门前，用来验证「走到门 → 过关」这条链路
    --   ★ 用 door[1]（门的初始位置）：会逃走的多段门必须从第一格开始追，
    --     直接放到最后一格的话 doorWin 永远不会成立（i < #positions）。
    if (state.devNear or 0) > 0 and def.door and def.door[1] then
        local d = def.door[1]
        local p = state.player
        if p and d then
            p.x = d.x - 70
            p.y = d.y + (config.DEFAULT_DOOR_H or 64) - p.h
            player.sync()
        end
    end

    state.state = "play"
    state.stateT = 0
    state.keysEnabled = true

    hud.setVisible(true)
    hud.setLevel(def.name, idx)
    hud.setDeaths(state.deaths)
    hud.setMessage("")
    hud.hideBig()
    hud.hideSub()
    menu.setVisible(false)

    audio.playOpen()
end

doDie = function(wx, wy)
    if state.state ~= "play" then return end
    state.deaths = state.deaths + 1
    hud.setDeaths(state.deaths)

    fx.blood(wx, wy)
    fx.stain(wx, math.min(wy + 20, 478))
    fx.shake(9, 0.30)

    if state.ghostOn then
        -- ★ 不死诅咒：不会真死，化成鬼魂，可自由漂浮后原地复活
        player.enterGhost()
        hud.setMessage("鬼魂：方向键漂浮 · 空格在当前位置复活")
        return
    end

    audio.playDeath()
    state.state = "dead"
    state.stateT = 0
    local lines = config.DEATH_LINES or {}
    state.deathLine = (#lines > 0) and lines[math.random(1, #lines)] or "OUCH."
    hud.showBig(state.deathLine, utils.pal("danger"), config.DEFAULT_DEATH_LINE_SIZE)
    hud.showSub("")
end

doWin = function()
    if state.state ~= "play" then return end
    state.state = "win"
    state.stateT = 0
    state.keysEnabled = false
    resetInput()
    audio.playWin()

    state.done[state.levelIndex] = true
    if state.levelIndex + 1 > (state.unlocked or 1) then
        state.unlocked = state.levelIndex + 1
    end

    local last = state.levelIndex >= config.levelCount()
    hud.showBig(last and "WHAT?!" or "FINE. NEXT.",
        utils.pal("accent"), config.DEFAULT_WIN_LINE_SIZE)
    hud.setMessage("")
end

advance = function()
    if state.state ~= "win" then return end
    -- ★ 必须立刻离开 win 态：否则每帧都会再进一次本函数，
    --   反复重启黑幕 → onPeak 永远等不到，看起来就是「过关后卡住不换关」。
    state.state = "wait"
    state.stateT = 0
    local nextIdx = (state.levelIndex or 1) + 1
    hud.hideBig()
    hud.hideSub()
    if nextIdx > config.levelCount() then
        showEnd()
        return
    end
    if state.comicOn then
        state.state = "comic"
        hud.setVisible(false)
        comic.play(function() startLevel(nextIdx) end)
    else
        fadeScreen.start({ onPeak = function() startLevel(nextIdx) end })
    end
end

backToMenu = function()
    comic.stop()
    hideEnd()
    level.clear()
    player.hide()
    fx.resetAll()
    anim.clearAll()
    resetInput()
    state.state = "menu"
    state.stateT = 0
    state.keysEnabled = false
    hud.setVisible(false)
    menu.setVisible(true)
end

-- ================================================================
-- 通关结算面板
-- ================================================================
hideEnd = function()
    for i = 1, #endParts do utils.destroy(endParts[i]) end
    endParts = {}
end

showEnd = function()
    hideEnd()
    state.state = "end"
    state.stateT = 0
    state.keysEnabled = false
    hud.setVisible(false)
    local par = state.containerMenu
    if not par or (state.rectPrefabId or 0) <= 0 then return end

    local function push(c)
        if not c then return end
        endParts[#endParts + 1] = c
        -- ★ 按「创建顺序 = 下 → 上」显式提层，否则半透明遮罩会把文字压暗
        if type(c) == "table" and c.__group then
            utils.raise(c.base); utils.raise(c.label); utils.raise(c.hit)
        else
            utils.raise(c)
        end
    end
    push(utils.createControl(state.rectPrefabId, 0, 0, 2600, 1600,
        utils.hexToColorA(utils.pal("wipe"), 235), par))
    push(utils.createText(0, 120, 900, 80, "三十道门之后",
        utils.hexToColor(utils.pal("accent")), 44, par))
    push(utils.createText(0, 62, 900, 30, "丑角仍站在生死之间。",
        utils.hexToColor(utils.pal("textDim")), 17, par))
    push(utils.createText(0, 4, 900, 44,
        string.format("本次轮回 · 死亡 %d 次", math.floor(state.deaths or 0)),
        utils.hexToColor(utils.pal("text")), 22, par))
    push(utils.createText(0, -48, 900, 32, config.roastFor(state.deaths),
        utils.hexToColor(utils.pal("textDim")), 16, par))

    local b = utils.createButton(0, -142, 300, 52, par, {
        text = "再次赴死",
        fontSize = 21,
        bg = utils.pal("accent"),
        bgDown = utils.pal("btnDown"),
        textColor = "1A1206",
        onClick = function()
            audio.playClick()
            backToMenu()
        end,
    })
    if b then push(b) end
end

-- ================================================================
-- ★ 游玩中的一帧
-- ================================================================
local function updatePlay(dt)
    local solids = level.collectSolids()

    if state.ghost then
        -- 鬼魂：原版作弊态 —— 不推陷阱、不判死、也不判赢
        player.update(dt, solids)
        if state.keyJump and not jumpPrev then
            if player.tryRespawn(solids, level.collectKills()) then
                hud.setMessage("")
            end
        end
        jumpPrev = state.keyJump
        return
    end
    jumpPrev = state.keyJump

    -- ① 陷阱与门
    level.update(dt)

    -- ② 玩家物理
    solids = level.collectSolids()
    player.update(dt, solids)

    local p = state.player
    if not p then return end

    -- ③ 被实体夹住（原版用收缩 4px 的内盒判定）
    local ins = config.DEFAULT_CRUSH_INSET or 4
    for i = 1, #solids do
        local s = solids[i]
        if utils.aabb(p.x + ins, p.y + ins, p.w - ins * 2, p.h - ins * 2,
                      s.x, s.y, s.w, s.h) then
            doDie(p.x + p.w / 2, p.y + p.h / 2)
            return
        end
    end

    -- ④ 陷阱致死区
    local kills = level.collectKills()
    for i = 1, #kills do
        local k = kills[i]
        if utils.aabb(p.x, p.y, p.w, p.h, k.x, k.y, k.w, k.h) then
            doDie(p.x + p.w / 2, p.y + p.h / 2)
            return
        end
    end

    -- ⑤ 掉出世界
    if p.y > (config.DEFAULT_WORLD_H or 540) + 40 then
        state.deaths = state.deaths + 1
        hud.setDeaths(state.deaths)
        if state.ghostOn then
            p.y = (config.DEFAULT_WORLD_H or 540) - p.h - 4
            player.enterGhost()
            hud.setMessage("鬼魂：方向键漂浮 · 空格在当前位置复活")
            return
        end
        audio.playDeath()
        state.state = "dead"
        state.stateT = 0
        fx.shake(6, 0.25)
        local lines = config.DEATH_LINES or {}
        state.deathLine = (#lines > 0) and lines[math.random(1, #lines)] or "OUCH."
        hud.showBig(state.deathLine, utils.pal("danger"), config.DEFAULT_DEATH_LINE_SIZE)
        return
    end

    -- ⑥ 穿过门
    if level.doorWin(state.door) then
        doWin()
    end
end

-- ================================================================
-- ★ 键盘
-- ================================================================
local function pressJump()
    -- 边界触发：引擎会重复送 KeyDown，按住时必须只认第一下
    if state.keyJump then return end
    state.keyJump = true
    state.jumpBuffer = config.DEFAULT_JUMP_BUFFER or 0.12
end

local function releaseJump()
    state.keyJump = false
end

bindKeys = function(root)
    local K = Enum.KeyEventType
    local function bind(evt, fn)
        pcall(function()
            root:AddKeyEventListener(evt, function()
                fn()
                return true
            end)
        end)
    end

    -- 左 / 右
    bind(K.KeyboardMoveLeftKeyDown, function() state.keyLeft = true end)
    bind(K.KeyboardMoveLeftKeyUp, function() state.keyLeft = false end)
    bind(K.KeyboardCraftspersonKey38Down, function() state.keyLeft = true end)
    bind(K.KeyboardCraftspersonKey38Up, function() state.keyLeft = false end)

    bind(K.KeyboardMoveRightKeyDown, function() state.keyRight = true end)
    bind(K.KeyboardMoveRightKeyUp, function() state.keyRight = false end)
    bind(K.KeyboardCraftspersonKey39Down, function() state.keyRight = true end)
    bind(K.KeyboardCraftspersonKey39Up, function() state.keyRight = false end)

    -- 跳：空格
    bind(K.KeyboardJumpKeyDown, pressJump)
    bind(K.KeyboardJumpKeyUp, releaseJump)

    -- 上：正常模式 = 跳；鬼魂模式 = 向上漂浮
    local function upDown()
        if state.ghost then
            state.keyUp = true
        else
            pressJump()
        end
    end
    local function upUp()
        state.keyUp = false
        releaseJump()
    end
    bind(K.KeyboardMoveForwardKeyDown, upDown)
    bind(K.KeyboardMoveForwardKeyUp, upUp)
    bind(K.KeyboardCraftspersonKey36Down, upDown)
    bind(K.KeyboardCraftspersonKey36Up, upUp)

    -- 下：只在鬼魂模式有意义
    bind(K.KeyboardMoveBackwardKeyDown, function() state.keyDown = true end)
    bind(K.KeyboardMoveBackwardKeyUp, function() state.keyDown = false end)
    bind(K.KeyboardCraftspersonKey37Down, function() state.keyDown = true end)
    bind(K.KeyboardCraftspersonKey37Up, function() state.keyDown = false end)

    -- R：重来本关
    bind(K.KeyboardCharacterSkill3KeyDown, function()
        if state.state == "play" or state.state == "dead" then
            startLevel(state.levelIndex)
        end
    end)

    -- L：回菜单
    bind(K.KeyboardCraftspersonKey21Down, function()
        if state.state ~= "menu" then backToMenu() end
    end)

    -- N：跳关（开发用）
    bind(K.KeyboardCraftspersonKey20Down, function()
        if state.state == "play" or state.state == "win" then
            local n = (state.levelIndex or 1) + 1
            if n <= config.levelCount() then startLevel(n) end
        end
    end)
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
    state.buttonPrefabId = getParamNumber("buttonPrefabId", 0)
    if state.rectPrefabId <= 0 then
        printerr("错误：请设置脚本参数 rectPrefabId（纯色矩形 / 图片控件）")
        return
    end
    if state.textPrefabId <= 0 then
        printerr("警告：未设置 textPrefabId，所有文字都不会显示")
    end
    if state.cursorPrefabId <= 0 then
        printerr("警告：未设置 cursorPrefabId，菜单可能点不动")
    end

    script:EnableUpdate(true)

    -- 音效
    state.clickAudioId = getParamNumber("clickAudioId", 0)
    state.jumpAudioId = getParamNumber("jumpAudioId", 0)
    state.deathAudioId = getParamNumber("deathAudioId", 0)
    state.winAudioId = getParamNumber("winAudioId", 0)
    state.popAudioId = getParamNumber("popAudioId", 0)
    state.openAudioId = getParamNumber("openAudioId", 0)
    audio.init({
        click = state.clickAudioId, jump = state.jumpAudioId,
        death = state.deathAudioId, win = state.winAudioId,
        pop = state.popAudioId, open = state.openAudioId,
    })
    audio.prewarm()

    -- 画布
    local okSize, w, h = pcall(function() return game.GetUICanvasSize() end)
    state.canvasW = (okSize and type(w) == "number" and w > 0) and w or 960
    state.canvasH = (okSize and type(h) == "number" and h > 0) and h or 540
    utils.computeLayout()

    if not ensureContainers() then
        printerr("错误：层级容器创建失败（检查 rectPrefabId / containerPrefabId）")
        return
    end
    fadeScreen.init()
    createBackground()
    hud.init()

    -- 开关
    state.ghostParam = getParamNumber("ghost", (config.DEFAULT_GHOST_ON or 1) > 0 and 1 or 0)
    state.ghostOn = state.ghostParam ~= 0
    state.comicOn = getParamNumber("comic", (config.DEFAULT_COMIC_ON or 1) > 0 and 1 or 0) ~= 0
    state.deaths = 0
    state.done = {}
    state.unlocked = 1
    state.devWin = getParamNumber("devwin", 0)
    state.devNear = getParamNumber("devnear", 0)

    if not menu.init({
        onStart = function(idx)
            audio.playClick()
            startLevel(idx)
        end,
        onToggleGhost = function()
            state.ghostOn = not state.ghostOn
            state.ghostParam = state.ghostOn and 1 or 0
            if not state.ghostOn and state.ghost then
                state.ghost = false
                startLevel(state.levelIndex)
            end
            menu.refresh()
        end,
    }) then
        printerr("警告：菜单初始化失败")
    end

    bindKeys(root)

    local startAt = getParamNumber("start", 0)
    if startAt and startAt >= 1 then
        startLevel(math.floor(startAt))
    else
        state.state = "menu"
        state.keysEnabled = false
        hud.setVisible(false)
        menu.setVisible(true)
    end
end

-- ================================================================
-- 每帧
-- ================================================================
function OnUpdate(dt)
    if not dt or dt <= 0 then return end
    if dt > 0.05 then dt = 0.05 end
    state.lastDt = dt
    state.time = state.time + dt

    anim.update(dt)
    fadeScreen.update(dt)
    comic.update(dt)

    if state.state == "play" then
        state.stateT = state.stateT + dt
        updatePlay(dt)
        -- 开发用：进关若干秒后自动过关，用来跑穿「过关 → 献祭演出 → 下一关」
        local dw = tonumber(state.devWin) or 0
        if dw > 0 and state.state == "play" and state.stateT >= dw then
            doWin()
        end
    elseif state.state == "dead" then
        state.stateT = state.stateT + dt
        level.update(dt)
        if state.stateT >= (config.DEFAULT_DEATH_HOLD or 0.85) then
            local idx = state.levelIndex
            fadeScreen.start({ onPeak = function() startLevel(idx) end })
            hud.hideBig()
            hud.hideSub()
            state.state = "wait"
            state.stateT = 0
        end
    elseif state.state == "win" then
        state.stateT = state.stateT + dt
        level.syncOnly()
        if state.stateT >= (config.DEFAULT_WIN_HOLD or 0.80) then
            advance()
        end
    end

    fx.update(dt)
end

function OnDestroy()
    pcall(function() script:EnableUpdate(false) end)
end

-- ★ 这里不要写 return：入口脚本的末尾会被追加引擎/模拟器的补丁代码，
--   return 之后不能再有语句，否则整份脚本报 "<eof> expected"。
