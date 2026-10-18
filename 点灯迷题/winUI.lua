-- ================================================================
-- 点灯迷题 胜利结算面板（夏日三星版）
-- ================================================================
-- 收到服务器「关卡胜利」后弹出：遮罩 → 光晕 → 面板 → 三颗星逐颗弹出
-- （每颗弹出时迸溅一把果汁粒子）→ 星下跑马灯小灯格开始循环走灯。
--
-- ★ 动效全部用基础图元（纯色矩形 + 文本）+ 逐帧驱动：
--   · 星星用 ★（U+2605，中文字体有字形；✓ 那种才会变豆腐块），
--     弹出靠逐帧改 fontSize 实现缩放；
--   · 迸溅粒子由 fx 模块的矩形粒子池提供。
-- ★★ 分层（与 TickHop 一致）：只用 containerWin 一个容器，容器内按
--    「遮罩 → 光晕 → 投影 → 面板 → 装饰 → 文字 → 星星 → 灯格 → 按钮」创建。
-- ================================================================

---@diagnostic disable: undefined-global

local M = {}
local state = require("default_import_file/state")
local config = require("default_import_file/config")
local utils = require("default_import_file/utils")
local fx = require("default_import_file/fx")

-- 由 game.lua 注入：{ onReplay = f(), onNext = f(), onBackToSelect = f() }
M.actions = {}

local ANIM_CELLS = 12        -- 跑马灯灯格数（= 6 列 × 2）
local RISE = 0.10            -- 单格亮起用时（秒）
local FALL = 0.42            -- 单格熄灭用时（秒）
local INTRO = 0.20           -- 面板入场淡入时长（秒）
local STAR_POP = 0.16        -- 单颗星放大用时（秒）
local STAR_SETTLE = 0.18     -- 单颗星回落到正常大小用时（秒）
local STAR_OVERSHOOT = 1.55  -- 弹出时的放大倍数

local function addNode(ctrl)
    if ctrl then
        state.winNodes[#state.winNodes + 1] = ctrl
    end
    return ctrl
end

local function panelSize()
    local cw = state.canvasW or config.DEFAULT_VIEW_WIDTH or 800
    local ch = state.canvasH or config.DEFAULT_VIEW_HEIGHT or 600
    local pw = math.min(config.DEFAULT_WIN_PANEL_W or 660, cw - 40)
    local ph = math.min(config.DEFAULT_WIN_PANEL_H or 440, ch - 40)
    if pw < 300 then pw = cw end
    if ph < 260 then ph = ch end
    return pw, ph
end

-- ================================================================
-- ★ 预创建（OnStart 调用一次）
-- ================================================================
function M.init()
    if state.winPanel then return true end
    if not state.containerWin then return false end
    if not state.rectPrefabId or state.rectPrefabId <= 0 then return false end

    local pal = utils.resolvePalette(state.currentLevelConfig)
    local pw, ph = panelSize()
    local cw = state.canvasW or config.DEFAULT_VIEW_WIDTH or 800
    local ch = state.canvasH or config.DEFAULT_VIEW_HEIGHT or 600
    local titleSize = config.DEFAULT_WIN_TITLE_SIZE or 46
    local textSize = config.DEFAULT_WIN_TEXT_SIZE or 22
    local hintSize = textSize - 6
    local starSize = config.DEFAULT_WIN_STAR_SIZE or 54
    local starGap = config.DEFAULT_WIN_STAR_GAP or 86
    local starY = config.DEFAULT_WIN_STAR_Y or 78

    -- ① 遮罩 → 光晕 → 投影 → 面板
    state.winOverlay = addNode(utils.createControl(state.rectPrefabId, 0, 0, cw + 500, ch + 500,
        utils.hexToColorA(pal.overlay, config.DEFAULT_WIN_OVERLAY_ALPHA or 150),
        state.containerWin))
    state.winGlow = addNode(utils.createControl(state.rectPrefabId, 0, 0, pw + 56, ph + 56,
        utils.hexToColorA(pal.accent, 30), state.containerWin))
    state.winPanelShadow = addNode(utils.createControl(state.rectPrefabId, 6, -8, pw, ph,
        utils.hexToColorA(pal.shadow, 120), state.containerWin))
    state.winPanelEdge = addNode(utils.createControl(state.rectPrefabId, 0, 0, pw + 12, ph + 12,
        utils.hexToColor(pal.line), state.containerWin))
    state.winPanel = addNode(utils.createControl(state.rectPrefabId, 0, 0, pw, ph,
        utils.hexToColor(pal.panel), state.containerWin))
    -- 顶部橙汁横带 + 两颗角落气泡
    addNode(utils.createControl(state.rectPrefabId, 0, ph / 2 - 9, pw - 40, 10,
        utils.hexToColor(pal.accent), state.containerWin))
    addNode(utils.createControl(state.rectPrefabId, -pw / 2 + 34, -ph / 2 + 34, 18, 18,
        utils.hexToColorA(pal.juice2, 120), state.containerWin))
    addNode(utils.createControl(state.rectPrefabId, pw / 2 - 42, -ph / 2 + 46, 12, 12,
        utils.hexToColorA(pal.juice3, 110), state.containerWin))

    -- ② 文字
    state.winTitle = addNode(utils.createText(0, 182, pw - 60, 60, "关卡完成！",
        utils.hexToColor(pal.accent), titleSize, state.containerWin))
    state.winSubtitle = addNode(utils.createText(0, 144, pw - 60, 30, "",
        utils.hexToColor(pal.text), textSize, state.containerWin))
    state.winStats = addNode(utils.createText(0, -28, pw - 60, 30, "",
        utils.hexToColor(pal.ok), textSize - 2, state.containerWin))
    state.winFooter = addNode(utils.createText(0, -154, pw - 40, 26, "",
        utils.hexToColor(pal.dim), hintSize, state.containerWin))

    -- ③ 三星：先光晕底，再三颗星（★ 用文本，中文字体有字形）
    local glowW = starGap * 2 + 90
    state.winStarGlow = addNode(utils.createControl(state.rectPrefabId, 0, starY, glowW, 104,
        utils.hexToColorA(pal.starEdge, 40), state.containerWin))
    for i = 1, 3 do
        local x = (i - 2) * starGap
        local ctrl = addNode(utils.createText(x, starY, 80, 80, "★",
            utils.hexToColor(pal.star), starSize, state.containerWin))
        state.winStars[i] = {
            ctrl = ctrl, baseX = x, baseY = starY, order = i - 1,
            size = starSize, burst = false,
        }
    end

    -- ④ 跑马灯灯格（三星全部弹完才开始走）
    local cs = config.DEFAULT_WIN_ANIM_CELL or 30
    local gap = config.DEFAULT_WIN_ANIM_GAP or 10
    local rowW = ANIM_CELLS * cs + (ANIM_CELLS - 1) * gap
    for i = 1, ANIM_CELLS do
        local x = -rowW / 2 + cs / 2 + (i - 1) * (cs + gap)
        local ctrl = addNode(utils.createControl(state.rectPrefabId, x, 18, cs, cs,
            utils.hexToColorA(pal.lit, 60), state.containerWin))
        state.winAnimCells[i] = { ctrl = ctrl, order = i - 1, baseX = x, cs = cs }
    end

    -- ⑤ 底部三个按钮：底 → 字 → 点击区
    local bw = config.DEFAULT_WIN_BTN_W or 176
    local bh = config.DEFAULT_WIN_BTN_H or 56
    local bgap = config.DEFAULT_WIN_BTN_GAP or 16
    local by = -90
    for i = 1, 3 do
        local x = (i - 2) * (bw + bgap)
        local bg = addNode(utils.createControl(state.rectPrefabId, x, by, bw, bh,
            utils.hexToColor(pal.card), state.containerWin))
        local label = addNode(utils.createText(x, by, bw, bh, "",
            utils.hexToColor(pal.text), textSize, state.containerWin))
        local hit = utils.createHit(x, by, bw, bh, state.containerWin, nil, bg)
        if hit then
            state.winNodes[#state.winNodes + 1] = hit
            pcall(function()
                hit:AddCursorEventListener(Enum.CursorEventType.CursorDown, function()
                    if not state.winOpen then return end
                    local us = utils.uiScale()   -- ★ 本层容器整体放大过，粒子世界坐标要跟着乘
                    fx.spawn(x * us, by * us, { n = 10, keys = { "juice1", "juice2", "juice4" },
                                      speed = 230 * us, life = 0.5, size = 8 * us })
                    M.invokeButton(i)
                end)
            end)
            utils.bindHover(hit,
                function() pcall(function() bg:SetSizeDelta(bw + 6, bh + 6) end) end,
                function() pcall(function() bg:SetSizeDelta(bw, bh) end) end)
        end
        state.winButtons[i] = { bg = bg, label = label, hit = hit, action = nil,
                                bgKey = "card", labelKey = "text" }
    end

    M.setVisible(false)
    return true
end

-- ================================================================
-- ★ 刷新静态内容（打开时调用一次；动效由 update 每帧刷新）
-- ================================================================
function M.refresh()
    if not state.winPanel then return end
    local pal = utils.resolvePalette(state.currentLevelConfig)
    local idx = math.floor(tonumber(state.winLevelIndex or state.currentLevelIndex) or 1)
    local steps = config.getLevelSteps(idx)
    local total = math.max(1, config.getLevelCount())
    local cleared = 0
    for _, v in pairs(state.clearedLevels or {}) do
        if v then cleared = cleared + 1 end
    end

    utils.setText(state.winTitle, "关卡完成！")
    utils.setTextColor(state.winTitle, pal.accent, 255)
    utils.setText(state.winSubtitle, string.format("第 %02d 关 · 难度 %d 步", idx, steps))
    utils.setText(state.winStats, string.format("已通关 %d / %d 关", cleared, total))
    utils.setText(state.winFooter, "R 重玩本关 · 空格 下一关 · L 返回选关")

    local hasNext = config.getLevelConfig(idx + 1) ~= nil
    local specs = {
        { text = "重玩本关", action = function() M.doReplay() end, bgKey = "card", labelKey = "text" },
        { text = hasNext and "下一关 →" or "已是最后一关",
          action = hasNext and function() M.doNext() end or nil,
          bgKey = hasNext and "accent" or "line",
          labelKey = hasNext and "accentText" or "dim" },
        { text = "返回选关", action = function() M.doBack() end, bgKey = "card", labelKey = "text" },
    }
    for i, btn in ipairs(state.winButtons) do
        local sp = specs[i]
        utils.setText(btn.label, sp.text)
        btn.action = sp.action
        btn.bgKey = sp.bgKey
        btn.labelKey = sp.labelKey
    end
    utils.setAlpha(state.winOverlay, pal.overlay, config.DEFAULT_WIN_OVERLAY_ALPHA or 150)
    utils.setAlpha(state.winGlow, pal.accent, 30)
    utils.setAlpha(state.winPanelShadow, pal.shadow, 120)
    utils.setAlpha(state.winPanel, pal.panel, 255)
    utils.setAlpha(state.winPanelEdge, pal.line, 255)
    utils.setAlpha(state.winStarGlow, pal.starEdge, 40)
    for _, s in ipairs(state.winStars) do
        s.burst = false
        utils.setTextColor(s.ctrl, pal.star, 0)
        utils.setFontSize(s.ctrl, 2)
    end
    -- ★ 用 k=0 起手：紧接着的第一次 update 会按真实 dt 往上爬，
    --   避免「先满亮一帧再变暗」的闪一下。
    M.applyFrame(0)
end

-- ================================================================
-- ★ 按入场进度 k（0..1）上色：文本与按钮的透明度一起淡入
-- ================================================================
function M.applyFrame(k)
    local pal = utils.resolvePalette(state.currentLevelConfig)
    utils.setTextColor(state.winTitle, pal.accent, 255 * k)
    utils.setTextColor(state.winSubtitle, pal.text, 240 * k)
    utils.setTextColor(state.winStats, pal.ok, 240 * k)
    utils.setTextColor(state.winFooter, pal.dim, 220 * k)
    for _, btn in ipairs(state.winButtons) do
        utils.setAlpha(btn.bg, pal[btn.bgKey] or pal.card, 255 * k)
        utils.setTextColor(btn.label, pal[btn.labelKey] or pal.text, 250 * k)
    end
end

-- ================================================================
-- ★ 每帧动效（面板打开期间调用）
-- ================================================================
function M.update(dt)
    if not state.winOpen or not state.winPanel then return end
    dt = tonumber(dt) or 0
    if dt <= 0 then return end
    state.winAnimT = (state.winAnimT or 0) + dt
    local t = state.winAnimT
    local pal = utils.resolvePalette(state.currentLevelConfig)

    -- 入场淡入
    local k = t / INTRO
    if k > 1 then k = 1 end
    utils.setAlpha(state.winOverlay, pal.overlay, (config.DEFAULT_WIN_OVERLAY_ALPHA or 150) * k)
    utils.setAlpha(state.winPanel, pal.panel, 255 * k)
    utils.setAlpha(state.winPanelEdge, pal.line, 255 * k)
    utils.setAlpha(state.winPanelShadow, pal.shadow, 120 * k)
    -- 光晕脉动
    local pulse = 0.5 + 0.5 * math.sin(t * 3.4)
    utils.setAlpha(state.winGlow, pal.accent, (24 + 30 * pulse) * k)
    M.applyFrame(k)

    -- ---- 三星逐颗弹出（每颗弹出瞬间迸溅一把果汁）----
    local interval = config.DEFAULT_WIN_STAR_INTERVAL or 0.24
    local burstN = math.floor(config.DEFAULT_WIN_STAR_BURST or 12)
    for _, s in ipairs(state.winStars) do
        local lt = t - s.order * interval
        if lt < 0 then
            utils.setTextColor(s.ctrl, pal.star, 0)
        elseif lt < STAR_POP then
            -- ★ 弹出段用 glow（比 starEdge 深、在奶白面板上看得清），
            --   否则浅黄近透明 → 这几帧星星等于没画出来，弹出感全丢。
            local kk = lt / STAR_POP
            utils.setFontSize(s.ctrl, math.max(2, s.size * (STAR_OVERSHOOT * kk)))
            utils.setTextColor(s.ctrl, pal.glow or pal.star, 255 * k)
        elseif lt < STAR_POP + STAR_SETTLE then
            local kk = (lt - STAR_POP) / STAR_SETTLE
            utils.setFontSize(s.ctrl, s.size * (STAR_OVERSHOOT - (STAR_OVERSHOOT - 1) * kk))
            utils.setTextColor(s.ctrl, pal.star, 255 * k)
        else
            utils.setFontSize(s.ctrl, s.size)
            utils.setTextColor(s.ctrl, pal.star, 255 * k)
        end
        if not s.burst and lt >= STAR_POP * 0.85 then
            s.burst = true
            local us = utils.uiScale()      -- ★ 星星坐标在放大过的层里，粒子要换算到世界坐标
            fx.spawn(s.baseX * us, s.baseY * us, {
                n = burstN, keys = { "star", "juice4", "juice1" },
                dir = 90, spread = 360, speed = 300 * us, life = 0.62, size = 9 * us,
            })
        end
    end
    -- 星区光晕呼吸
    local starGlowA = 26 + 24 * (0.5 + 0.5 * math.sin(t * 2.6))
    utils.setAlpha(state.winStarGlow, pal.starEdge, starGlowA * k)

    -- ---- 跑马灯：三星弹完之后才开始，每格按顺序亮起再熄灭并微微放大 ----
    local starsDone = t > (2 * interval + STAR_POP + STAR_SETTLE)
    local step = config.DEFAULT_WIN_ANIM_STEP or 0.10
    local hold = config.DEFAULT_WIN_ANIM_HOLD or (ANIM_CELLS * step)
    if hold <= 0 then hold = ANIM_CELLS * step end
    if hold <= 0 then hold = 1.2 end
    for _, cell in ipairs(state.winAnimCells) do
        local a = 0
        if starsDone then
            local tp = (t - (2 * interval + STAR_POP + STAR_SETTLE) - cell.order * step) % hold
            if tp < RISE then
                a = tp / RISE
            elseif tp < RISE + FALL then
                a = 1 - (tp - RISE) / FALL
            else
                a = 0
            end
        end
        utils.setAlpha(cell.ctrl, pal.lit, (46 + a * 209) * k)
        local sz = cell.cs * (1 + 0.16 * a)
        utils.setSize(cell.ctrl, sz, sz)
    end
end

-- ================================================================
-- ★ 显隐
-- ================================================================
function M.setVisible(v)
    state.winOpen = v and true or false
    utils.setVisibleAll(state.winNodes, v)
    if v then
        state.winAnimT = 0
        M.refresh()
        local pw, ph = panelSize()
        -- 开场：面板顶部中心迸溅一把果汁
        local us = utils.uiScale()
        fx.spawn(0, (ph / 2 - 20) * us, { n = 20, keys = { "juice1", "juice2", "juice4", "juice3" },
                                   dir = 270, spread = 150, speed = 380 * us, life = 0.8, size = 11 * us })
    else
        fx.cancelAll()
    end
end

-- ================================================================
-- ★ 打开 / 关闭
-- ================================================================
function M.open(levelIndex)
    if not state.winPanel and not M.init() then return false end
    state.winLevelIndex = math.floor(tonumber(levelIndex) or state.currentLevelIndex or 1)
    M.setVisible(true)
    return true
end

function M.close()
    M.setVisible(false)
end

function M.isOpen()
    return state.winOpen == true
end

-- ================================================================
-- ★ 按钮动作
-- ================================================================
function M.invokeButton(slot)
    if not state.winOpen then return end
    local btn = state.winButtons[slot]
    if btn and btn.action then btn.action() end
end

-- 空格 / W 的默认动作：有下一关就走下一关，否则返回选关
function M.confirmPrimary()
    if not state.winOpen then return end
    local btn = state.winButtons[2]
    if btn and btn.action then
        btn.action()
    else
        M.doBack()
    end
end

function M.doReplay()
    M.close()
    if M.actions.onReplay then M.actions.onReplay() end
end

function M.doNext()
    M.close()
    if M.actions.onNext then M.actions.onNext() end
end

function M.doBack()
    M.close()
    if M.actions.onBackToSelect then M.actions.onBackToSelect() end
end

-- ================================================================
-- ★ 注入动作回调（由 game.lua 调用，避免与 game.lua 循环依赖）
-- ================================================================
function M.setActions(t)
    if type(t) == "table" then M.actions = t end
end

return M
