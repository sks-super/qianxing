-- ================================================================
-- TickHop 关卡构建与刷新
--   ★ build(data)        依据关卡配置创建背景/平台/门/道具/玩家/提示文本
--   ★ refreshPlatforms() 按当前 tick 刷新每个平台的「实体 / 虚化」状态
--   ★ checkPickup()      返回本帧被玩家拾取的道具（效果由 game.lua 施加）
--   所有可视对象均创建一次并在关卡间复用（隐藏而非销毁）。
-- ================================================================

---@diagnostic disable: undefined-global

local M = {}
local state = require("state")
local config = require("config")
local utils = require("utils")

-- ================================================================
-- ★ 合并配色：关卡 palette 覆盖 DEFAULT_PALETTE
--   实现已收敛到 utils.resolvePalette（level 与 menu 共用同一份真源）
-- ================================================================
local function resolvePalette(data)
    return utils.resolvePalette(data)
end

-- ================================================================
-- ★ 创建背景
-- ================================================================
local function createBackground(palette)
    local w = (state.canvasW or 800) + 600
    local h = (state.canvasH or 600) + 600
    state.bgCtrl = utils.createControl(
        state.rectPrefabId, 0, 0, w, h,
        utils.hexToColor(palette.bg), state.containerBg)
    return state.bgCtrl
end

-- ================================================================
-- ★ 创建一个计时平台
--   solid 字段表示当前是否实体（参与碰撞）；
--   实体/虚化只改颜色与 alpha，不销毁重建。
-- ================================================================
local function createPlatform(p, palette)
    local w = p.width or config.DEFAULT_PLATFORM_WIDTH
    local h = p.height or config.DEFAULT_PLATFORM_HEIGHT
    local tick = p.tick
    if tick == nil then tick = config.DEFAULT_PLATFORM_TICK end
    tick = math.floor(tonumber(tick) or -1)

    local ctrl = utils.createControl(
        state.rectPrefabId, p.x, p.y, w, h,
        utils.hexToColor(palette.ghost), state.containerPlatform)
    if not ctrl then return nil end

    -- 秒数标签（仅计时平台显示；永驻平台不显示）
    local labelCtrl = nil
    local labelSize = config.DEFAULT_PLATFORM_LABEL_SIZE or 0
    if tick >= 0 and labelSize > 0 and (state.textPrefabId or 0) > 0 then
        labelCtrl = utils.createText(
            p.x, p.y, math.max(w, 40), math.max(h, labelSize + 8),
            tostring(tick), utils.hexToColor(palette.label), labelSize,
            state.containerPlatform)
    end

    local item = {
        x = p.x, y = p.y,
        halfW = w / 2, halfH = h / 2,
        tick = tick,
        solid = false,
        ctrl = ctrl,
        label = labelCtrl,
    }
    return item
end

-- ================================================================
-- ★ 创建终点门
-- ================================================================
local function createGoal(g, palette)
    local w = g.width or config.DEFAULT_GOAL_WIDTH
    local h = g.height or config.DEFAULT_GOAL_HEIGHT
    local pid = state.goalPrefabId
    if not pid or pid <= 0 then pid = state.rectPrefabId end
    local ctrl = utils.createControl(
        pid, g.x, g.y, w, h,
        utils.hexToColor(palette.goal), state.containerGoal)
    if not ctrl then return nil end
    return {
        x = g.x, y = g.y,
        halfW = w / 2, halfH = h / 2,
        ctrl = ctrl,
    }
end

-- ================================================================
-- ★ 创建道具（time=加时 / reverse=时间反转）
-- ================================================================
local function createPickup(k, palette)
    local size = config.DEFAULT_PICKUP_SIZE or 30
    local kind = k.type or "time"
    local color = palette.pickup
    if kind == "reverse" then color = palette.reverse end
    local ctrl = utils.createControl(
        state.rectPrefabId, k.x, k.y, size, size,
        utils.hexToColor(color), state.containerPickup)
    if not ctrl then return nil end
    return {
        x = k.x, y = k.y,
        halfW = size / 2, halfH = size / 2,
        kind = kind,
        value = tonumber(k.value) or config.DEFAULT_PICKUP_TIME_VALUE,
        taken = false,
        ctrl = ctrl,
    }
end

-- ================================================================
-- ★ 创建玩家（极简方块 + 两只眼睛）
--   眼睛用背景色绘制，在浅色方块上呈深色点，贴合原作极简风格。
-- ================================================================
local function createPlayer(spawn, palette)
    local w = config.DEFAULT_PLAYER_WIDTH or 34
    local h = config.DEFAULT_PLAYER_HEIGHT or 44
    local pid = state.playerPrefabId
    if not pid or pid <= 0 then pid = state.rectPrefabId end

    local body = utils.createControl(
        pid, spawn.x, spawn.y, w, h,
        utils.hexToColor(palette.player), state.containerPlayer)
    if not body then return nil end

    local eyeW = math.max(3, w * 0.16)
    local eyeH = math.max(4, h * 0.20)
    local eyeDX = w * 0.20
    local eyeDY = h * 0.24
    local eyeColor = utils.hexToColor(palette.bg)
    local eye1 = utils.createControl(state.rectPrefabId,
        spawn.x - eyeDX, spawn.y + eyeDY, eyeW, eyeH, eyeColor, state.containerPlayer)
    local eye2 = utils.createControl(state.rectPrefabId,
        spawn.x + eyeDX, spawn.y + eyeDY, eyeW, eyeH, eyeColor, state.containerPlayer)

    return {
        x = spawn.x, y = spawn.y,
        vx = 0, vy = 0,
        halfW = w / 2, halfH = h / 2,
        sizeW = w, sizeH = h,
        face = 1,
        onGround = false,
        ctrl = body,
        eye1 = eye1,
        eye2 = eye2,
        eyeDX = eyeDX, eyeDY = eyeDY,
    }
end

-- ================================================================
-- ★ 创建关卡提示文本
-- ================================================================
local function createTexts(list, palette)
    state.texts = {}
    if (state.textPrefabId or 0) <= 0 then return end
    for _, t in ipairs(list or {}) do
        local ctrl = utils.createText(
            t.x, t.y, t.width or 460, t.height or 46,
            t.text or "", utils.hexToColor(palette.hud), 22, state.containerHud)
        if ctrl then
            state.texts[#state.texts + 1] = { ctrl = ctrl, x = t.x, y = t.y }
        end
    end
end

-- ================================================================
-- ★ 清空上一关的全部可视对象（隐藏 + 清表，控件留作复用）
-- ================================================================
function M.clear()
    for _, p in ipairs(state.platforms) do
        utils.setVisible(p.ctrl, false)
        utils.setVisible(p.label, false)
    end
    state.platforms = {}

    for _, k in ipairs(state.pickups) do
        utils.setVisible(k.ctrl, false)
    end
    state.pickups = {}

    for _, t in ipairs(state.texts) do
        utils.setVisible(t.ctrl, false)
    end
    state.texts = {}

    if state.goal and state.goal.ctrl then
        utils.setVisible(state.goal.ctrl, false)
    end
    state.goal = nil

    if state.player then
        utils.setVisible(state.player.ctrl, false)
        utils.setVisible(state.player.eye1, false)
        utils.setVisible(state.player.eye2, false)
    end
    state.player = nil
end

-- ================================================================
-- ★ 构建一关
-- ================================================================
function M.build(data)
    M.clear()
    if not data then return false end

    local palette = resolvePalette(data)
    state.currentLevelConfig = data

    createBackground(palette)

    for _, p in ipairs(data.platforms or {}) do
        local item = createPlatform(p, palette)
        if item then state.platforms[#state.platforms + 1] = item end
    end

    if data.goal then
        state.goal = createGoal(data.goal, palette)
    end

    for _, k in ipairs(data.pickups or {}) do
        local item = createPickup(k, palette)
        if item then state.pickups[#state.pickups + 1] = item end
    end

    if data.spawn then
        state.player = createPlayer(data.spawn, palette)
    end

    createTexts(data.texts, palette)

    M.computeStageBounds()
    M.refreshPlatforms()

    return state.player ~= nil
end

-- ================================================================
-- ★ 计算关卡包围盒（用于「掉出关卡」判定）
--   以玩家出生点 + 全部平台 + 门为基准，向外扩 DEFAULT_KILL_MARGIN。
-- ================================================================
function M.computeStageBounds()
    local margin = config.DEFAULT_KILL_MARGIN or 260
    local minX, maxX, minY, maxY
    local function include(x, y)
        if not minX then
            minX, maxX, minY, maxY = x, x, y, y
            return
        end
        if x < minX then minX = x end
        if x > maxX then maxX = x end
        if y < minY then minY = y end
        if y > maxY then maxY = y end
    end

    if state.player then include(state.player.x, state.player.y) end
    for _, p in ipairs(state.platforms) do include(p.x, p.y) end
    if state.goal then include(state.goal.x, state.goal.y) end

    if not minX then
        -- 关卡没有任何物件时退化为画布边界
        minX, maxX = -(state.canvasW or 800) / 2, (state.canvasW or 800) / 2
        minY, maxY = -(state.canvasH or 600) / 2, (state.canvasH or 600) / 2
    end

    state.stageLeft   = minX - margin
    state.stageRight  = maxX + margin
    state.stageBottom = minY - margin
    state.stageTop    = maxY + margin
end

-- ================================================================
-- ★ 按当前 tick 刷新所有平台的实体状态与外观
--   平台本体（图片控件）：
--       实体 → palette.platform + DEFAULT_PLATFORM_ALPHA
--       虚化 → palette.ghost    + DEFAULT_PLATFORM_GHOST_ALPHA
--   秒数标签（文本控件）随平台一起「反色」，两种状态下都保持对比度：
--       实体（平台亮起）→ palette.label      压在亮色平台上
--       虚化（平台熄灭）→ palette.labelGhost 压在暗色平台上
-- ================================================================
function M.refreshPlatforms()
    local tickNow = state.timeTick or 0
    local data = state.currentLevelConfig
    local palette = resolvePalette(data or {})
    local solidAlpha = config.DEFAULT_PLATFORM_ALPHA or 255
    local ghostAlpha = config.DEFAULT_PLATFORM_GHOST_ALPHA or 40
    local labelGhostAlpha = config.DEFAULT_PLATFORM_LABEL_GHOST_ALPHA or 130
    local labelGhostColor = palette.labelGhost or palette.hud

    for _, p in ipairs(state.platforms) do
        local solid = (p.tick < 0) or (p.tick == tickNow)
        p.solid = solid
        if solid then
            utils.setAlpha(p.ctrl, palette.platform, solidAlpha)
            if p.label then
                utils.setTextColor(p.label, palette.label, solidAlpha)
            end
        else
            utils.setAlpha(p.ctrl, palette.ghost, ghostAlpha)
            if p.label then
                utils.setTextColor(p.label, labelGhostColor, labelGhostAlpha)
            end
        end
    end
end

-- ================================================================
-- ★ 刷新倒计时显示
-- ================================================================
function M.updateTimerDisplay()
    if not state.timerText then return end
    utils.setText(state.timerText, utils.formatTime(state.timeNow))
    local data = state.currentLevelConfig
    local palette = resolvePalette(data or {})
    utils.setTextColor(state.timerText, palette.hud, 255)
end

-- ================================================================
-- ★ 检查玩家是否拾取道具
--   返回被拾取的道具列表（可能同帧多个），并把它们标记为已拾取。
--   效果（加时/反转）由 game.lua 施加，level 只负责判定与显隐。
-- ================================================================
function M.checkPickup()
    local picked = {}
    local pl = state.player
    if not pl then return picked end
    for _, k in ipairs(state.pickups) do
        if not k.taken then
            if utils.aabbOverlap(pl.x, pl.y, pl.halfW, pl.halfH,
                                 k.x, k.y, k.halfW, k.halfH) then
                k.taken = true
                utils.setVisible(k.ctrl, false)
                picked[#picked + 1] = k
            end
        end
    end
    return picked
end

-- ================================================================
-- ★ 重置全部道具为未拾取（关卡重开时调用）
-- ================================================================
function M.resetPickups()
    for _, k in ipairs(state.pickups) do
        k.taken = false
        utils.setVisible(k.ctrl, true)
    end
end

return M
