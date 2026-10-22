-- ================================================================
-- 瓦雷莎的果园救急 · 胜利结算
-- ================================================================
-- 收到服务器「服客关卡胜利」后弹出，整段演出 2 秒左右：
--
--   0.00  遮罩淡入 + 面板「过冲」弹入（0.72 → 1.06 → 1.00）
--   0.10  标题弹入，副标题淡入
--   0.26  三颗星先以「暗星」出现（还没点亮）
--   0.52  ★ 第 1 颗：星心先亮一点光 → 光环一圈圈荡开 → 星体过冲弹出、由白转金 → 迸一把果汁
--   0.84  ★ 第 2 颗（同上）
--   1.16  ★ 第 3 颗 + **全屏白光一闪** + 大爆（三颗齐亮的仪式感）
--   1.56  四个按钮错峰弹入
--   之后  星星上下浮动、光晕呼吸、彩带波点流动、星尘飘落，一直循环
--
-- ★ 全部用基础图元（矩形 / 圆 / 环 / 三角 / ★ 文本）+ 逐帧驱动。
-- ★ 分层（同一容器内按创建顺序，后建在上）：
--   遮罩 → 柔光 → 投影 → 牌沿 → 牌面 → 彩带波点 → 角落装饰 → 星尘
--   → 标题/正文 → 暗星 → 星环 → 星心亮点 → 星 → 闪光 → 跑马灯 → 按钮
-- ================================================================

---@diagnostic disable: undefined-global

local M = {}
local state = require("default_import_file/state")
local config = require("default_import_file/config")
local utils = require("default_import_file/utils")
local fx = require("default_import_file/fx")

M.actions = {}

-- ================================================================
-- ★ 时间轴（秒）
-- ================================================================
local ANIM_CELLS = 12
local INTRO = 0.30          -- 遮罩 / 面板入场
local GHOST_AT = 0.26       -- 三颗暗星浮现
local STAR0 = 0.52          -- 第一颗星点亮
local STAR_GAP = 0.32       -- 逐颗间隔
local SPARK_T = 0.10        -- 星心亮点亮起用时
local POP_T = 0.16          -- 星体弹出用时
local RING_T = 0.55         -- 光环扩散用时
local BTN0 = 1.56           -- 第一个按钮弹入
local BTN_GAP = 0.08
local CONFETTI_FROM = 1.2   -- 星尘开始飘落
local OVERSHOOT = 1.18      -- 星体过冲倍率

local RISE = 0.10
local FALL = 0.42
local STAR_SETTLE = 0.16
local STAR_OVERSHOOT = 1.5

-- ================================================================
-- 装饰节点（只在本模块内部用，不进 state，避免污染跨模块状态表）
-- ================================================================
local deco = {
    ribbonA = {},   -- 上弧彩带（小圆点）
    ribbonB = {},   -- 下弧彩带
    sparkles = {},  -- 角落里慢慢闪的小星
    ghosts = {},    -- 三颗暗星（点亮前的空星）
    rings = {},     -- 每颗星 3 圈光环
    sparks = {},    -- 星心亮点
    confetti = {},  -- 飘落的星尘
    flash = nil,    -- 第三颗星的全屏白光
    bursts = {},    -- 每颗星是否已经迸过粒子
}

local function addNode(ctrl)
    if ctrl then state.winNodes[#state.winNodes + 1] = ctrl end
    return ctrl
end

local function addBox(box)
    if not box then return nil end
    addNode(box.root)
    for i = 1, #box.parts do addNode(box.parts[i]) end
    return box
end

local function panelSize()
    local cw = state.canvasW or config.DEFAULT_VIEW_WIDTH or 800
    local ch = state.canvasH or config.DEFAULT_VIEW_HEIGHT or 600
    local pw = math.min(config.DEFAULT_WIN_PANEL_W or 680, cw - 40)
    local ph = math.min(config.DEFAULT_WIN_PANEL_H or 462, ch - 40)
    if pw < 300 then pw = cw end
    if ph < 280 then ph = ch end
    return pw, ph
end

-- ================================================================
-- 缓动
-- ================================================================
local function clamp01(x)
    if x < 0 then return 0 elseif x > 1 then return 1 end
    return x
end

local function easeOut(x)
    local u = 1 - x
    return 1 - u * u * u
end

local function backOut(x, s)
    s = tonumber(s) or 1.7
    local u = x - 1
    return 1 + u * u * ((s + 1) * u + s)
end

-- ================================================================
-- 初始化
-- ================================================================
function M.init()
    if state.winPanel then return true end
    if not state.containerWin then return false end
    if not state.rectPrefabId or state.rectPrefabId <= 0 then return false end

    local pal = utils.palette()
    local pw, ph = panelSize()
    local cw = state.canvasW or config.DEFAULT_VIEW_WIDTH or 800
    local ch = state.canvasH or config.DEFAULT_VIEW_HEIGHT or 600
    local titleSize = config.DEFAULT_WIN_TITLE_SIZE or 44
    local textSize = config.DEFAULT_WIN_TEXT_SIZE or 21
    local hintSize = textSize - 5
    local starSize = config.DEFAULT_WIN_STAR_SIZE or 52
    local starGap = config.DEFAULT_WIN_STAR_GAP or 82
    local starY = config.DEFAULT_WIN_STAR_Y or 84

    state.winOverlay = addNode(utils.createControl(state.rectPrefabId, 0, 0, cw + 520, ch + 520,
        utils.hexToColorA(pal.overlay, config.DEFAULT_WIN_OVERLAY_ALPHA or 168), state.containerWin))

    -- 柔光：三层同心椭圆（外淡内浓）
    state.winGlow = {}
    for i = 1, 3 do
        local c = addNode(utils.circleC(0, 0, pw + 60 + (3 - i) * 46, ph + 50 + (3 - i) * 40,
            pal.starEdge, 0, state.containerWin))
        state.winGlow[i] = { ctrl = c, base = 8 + (i - 1) * 8 }
    end

    -- 面板三层圆角（投影 → 牌沿 → 牌面）
    local pr = math.min(26, ph * 0.09)
    state.winPanelShadow = addBox(utils.roundBox(7, -9, pw, ph, pr,
        utils.mixHex(pal.overlay, pal.shadow, 0.40), state.containerWin))
    state.winPanelEdge = addBox(utils.roundBox(0, 0, pw + 12, ph + 12, pr + 4, pal.line, state.containerWin))
    state.winPanel = addBox(utils.roundBox(0, 0, pw, ph, pr, pal.panel, state.containerWin))

    -- ------------------------------------------------------------
    -- 彩带波点：面板上下各一条弧（点在面板外，像系了花环）
    -- ------------------------------------------------------------
    local N_DOT = 15
    for band = 1, 2 do
        local list = (band == 1) and deco.ribbonA or deco.ribbonB
        local dir = (band == 1) and 1 or -1        -- 上弧朝上、下弧朝下
        local baseY = dir * (ph / 2 + 30)
        for i = 1, N_DOT do
            local u = (i - 1) / (N_DOT - 1)
            local x = (u - 0.5) * (pw - 40)
            local hump = math.sin(u * math.pi) * 20
            local hex = (i % 3 == 0) and pal.leaf or ((i % 3 == 1) and pal.fruit or pal.juice)
            local r = 5 + math.sin(u * math.pi) * 3
            list[i] = {
                ctrl = addNode(utils.circleC(x, baseY + dir * hump, r * 2, r * 2, hex, 210, state.containerWin)),
                x = x, y = baseY + dir * hump, r = r, phase = i * 0.5,
            }
        end
    end

    -- 角落装饰：果子 + 小星（保留原设计），再加两颗对称的
    addNode(utils.circleC(-pw / 2 + 36, -ph / 2 + 36, 18, 18, pal.fruit, 150, state.containerWin))
    addNode(utils.starC(pw / 2 - 44, -ph / 2 + 48, 15, 15, pal.star, 150, state.containerWin, true))
    addNode(utils.circleC(pw / 2 - 34, ph / 2 - 34, 15, 15, pal.juice, 140, state.containerWin))
    addNode(utils.starC(-pw / 2 + 46, ph / 2 - 40, 13, 13, pal.star, 140, state.containerWin, true))

    -- 星尘：从面板上方慢慢飘下来（常驻，很淡）
    for i = 1, 14 do
        local x = -pw / 2 + 30 + ((i * 97) % math.max(1, pw - 60))
        local hex = (i % 4 == 0) and pal.leaf or ((i % 2 == 0) and pal.juice or pal.star)
        local sz = 6 + (i % 3) * 3
        deco.confetti[i] = {
            ctrl = addNode(utils.circleC(x, ph / 2, sz, sz, hex, 0, state.containerWin)),
            x = x, sz = sz, phase = (i * 0.37) % 1, speed = 0.35 + (i % 5) * 0.05,
        }
    end

    -- ------------------------------------------------------------
    -- 文字
    -- ------------------------------------------------------------
    state.winTitle = addNode(utils.createText(0, 186, pw - 60, 56, "这片果园救回来了！",
        utils.hexToColor(pal.accent), titleSize, state.containerWin))
    state.winSubtitle = addNode(utils.createText(0, 146, pw - 60, 30, "",
        utils.hexToColor(pal.text), textSize, state.containerWin))
    state.winStats = addNode(utils.createText(0, -30, pw - 60, 30, "",
        utils.hexToColor(pal.ok), textSize - 2, state.containerWin))
    state.winFooter = addNode(utils.createText(0, -172, pw - 40, 26, "",
        utils.hexToColor(pal.dim), hintSize, state.containerWin))

    -- ------------------------------------------------------------
    -- 三颗星：暗星 → 星环 → 星心亮点 → 星
    -- ★ 创建顺序就是叠放顺序：暗星最下，星在最上
    -- ------------------------------------------------------------
    local glowW = starGap * 2 + 90
    state.winStarGlow = addNode(utils.circleC(0, starY, glowW, 112, pal.starEdge, 0, state.containerWin))
    -- 第三颗星点亮时从星排中心荡开的两圈冲击波（「魔法点亮」的仪式感）
    deco.shock = {}
    for j = 1, 2 do
        deco.shock[j] = addNode(utils.ringShape(0, starY, 60, 60, utils.hexToColorA(pal.starEdge, 0),
            state.containerWin))
    end
    state.winStars = {}
    for i = 1, 3 do
        local x = (i - 2) * starGap
        local ghost = addNode(utils.createText(x, starY, 80, 80, "★",
            utils.hexToColor(pal.starOff), starSize, state.containerWin))
        local rings = {}
        for j = 1, 3 do
            rings[j] = addNode(utils.ringShape(x, starY, 24, 24, utils.hexToColorA(pal.starEdge, 0),
                state.containerWin))
        end
        local spark = addNode(utils.circleC(x, starY, 2, 2, pal.wave, 0, state.containerWin))
        local glowDot = addNode(utils.circleC(x, starY, 56, 56, pal.starEdge, 0, state.containerWin))
        local star = addNode(utils.createText(x, starY, 80, 80, "★",
            utils.hexToColor(pal.star), starSize, state.containerWin))
        state.winStars[i] = {
            ctrl = star, ghost = ghost, rings = rings, spark = spark, glowDot = glowDot,
            baseX = x, baseY = starY, order = i - 1, size = starSize, burst = false,
        }
    end

    -- 第三颗星点亮时的全屏白光
    deco.flash = addNode(utils.createControl(state.rectPrefabId, 0, 0, cw + 520, ch + 520,
        utils.hexToColorA(pal.wave, 0), state.containerWin))

    -- ------------------------------------------------------------
    -- 跑马灯（水果 / 果汁交替）
    -- ------------------------------------------------------------
    local cs = config.DEFAULT_WIN_ANIM_CELL or 30
    local gap = config.DEFAULT_WIN_ANIM_GAP or 9
    local rowW = ANIM_CELLS * cs + (ANIM_CELLS - 1) * gap
    state.winAnimCells = {}
    for i = 1, ANIM_CELLS do
        local x = -rowW / 2 + cs / 2 + (i - 1) * (cs + gap)
        local ctrl = addNode(utils.circleC(x, 16, cs, cs,
            (i % 2 == 0) and pal.fruit or pal.juice, 150, state.containerWin))
        state.winAnimCells[i] = { ctrl = ctrl, order = i - 1, baseX = x, cs = cs }
    end

    -- ------------------------------------------------------------
    -- 四个按钮：上一片 / 重玩 / 下一片 / 回果园地图
    -- ★ 宽度按面板自适应：4 个按钮 + 3 个间距必须塞进面板（写死 172 会顶出左右边框）
    -- ------------------------------------------------------------
    local bgap = config.DEFAULT_WIN_BTN_GAP or 12
    local bw = config.DEFAULT_WIN_BTN_W or 172
    local fitW = (pw - 56 - 3 * bgap) / 4
    if bw > fitW then bw = fitW end
    local bh = config.DEFAULT_WIN_BTN_H or 54
    local by = -100
    for i = 1, 4 do
        local x = (i - 2.5) * (bw + bgap)
        local btn = addNode(utils.createContainer(state.containerWin, bw + 28, bh + 28))
        utils.setPos(btn, x, by)
        addBox(utils.roundBox(2, -6, bw, bh, bh * 0.42,
            utils.mixHex(pal.card, pal.shadow, 0.34), btn))
        local bg = addBox(utils.roundBox(0, 0, bw - 6, bh - 6, (bh - 6) * 0.42, pal.card, btn))
        local label = addNode(utils.createText(0, 0, bw, bh, "",
            utils.hexToColor(pal.text), textSize - 3, btn))
        local hit = utils.createHit(x, by, bw + 10, bh + 10, state.containerWin)
        if hit then
            state.winNodes[#state.winNodes + 1] = hit
            utils.bindHover(hit,
                function() utils.setScale(btn, 1.06) end,
                function() utils.setScale(btn, 1.0) end)
            pcall(function()
                hit:AddCursorEventListener(Enum.CursorEventType.CursorDown, function()
                    if not state.winOpen then return end
                    -- 演出还没到按钮出场就别响应，免得「看不见却能点」
                    if (state.winAnimT or 0) < BTN0 * 0.9 then return end
                    local us = utils.uiScale()
                    fx.spawn(x * us, by * us, { n = 10, keys = { "juice1", "juice2", "juice4" },
                        speed = 220 * us, life = 0.48, size = 8 * us })
                    M.invokeButton(i)
                end)
            end)
        end
        state.winButtons[i] = { bg = bg, label = label, hit = hit, root = btn,
            bgKey = "card", labelKey = "text" }
    end

    M.setVisible(false)
    return true
end

-- ================================================================
-- 刷新静态内容
-- ================================================================
function M.refresh()
    if not state.winPanel then return end
    local pal = utils.palette()
    local idx = math.max(1, math.floor(tonumber(state.winLevelIndex or state.currentLevelIndex) or 1))
    local steps = config.getLevelSteps(idx)
    local total = math.max(1, config.getLevelCount())
    local cleared = 0
    for i = 1, total do
        if state.clearedLevels[i] then cleared = cleared + 1 end
    end
    local stars = math.max(1, math.min(3, math.floor(tonumber(state.levelStars[idx]) or 3)))

    utils.setText(state.winTitle, "这片果园救回来了！")
    utils.setTextColor(state.winTitle, pal.accent, 255)
    utils.setText(state.winSubtitle, string.format("第 %02d 片果园 · 难度 %d 步 · %d 星", idx, steps, stars))
    utils.setText(state.winStats, string.format("已还原 %d / %d 片果园", cleared, total))
    utils.setText(state.winFooter, "R 重玩 · ← → 换片 · L 回果园")

    local hasPrev = idx > 1 and config.getLevelConfig(idx - 1) ~= nil
    local hasNext = config.getLevelConfig(idx + 1) ~= nil
    local specs = {
        { text = "← 上一片",
          action = hasPrev and function() M.doPrev() end or nil,
          bgKey = hasPrev and "card" or "line",
          labelKey = hasPrev and "text" or "dim" },
        { text = "重玩这片", action = function() M.doReplay() end, bgKey = "card", labelKey = "text" },
        { text = hasNext and "下一片 →" or "已是最后一片",
          action = hasNext and function() M.doNext() end or nil,
          bgKey = hasNext and "accent" or "line",
          labelKey = hasNext and "accentText" or "dim" },
        { text = "回果园地图", action = function() M.doBack() end, bgKey = "card", labelKey = "text" },
    }
    for i, btn in ipairs(state.winButtons) do
        local sp = specs[i]
        if sp then
            utils.setText(btn.label, sp.text)
            btn.action = sp.action
            btn.bgKey = sp.bgKey
            btn.labelKey = sp.labelKey
        end
    end

    utils.setColor(state.winOverlay, pal.overlay, config.DEFAULT_WIN_OVERLAY_ALPHA or 168)
    for i = 1, #(state.winGlow or {}) do
        utils.setColor(state.winGlow[i].ctrl, pal.starEdge, state.winGlow[i].base)
    end
    utils.setBoxColor(state.winPanelShadow, utils.mixHex(pal.overlay, pal.shadow, 0.40), 255)
    utils.setBoxColor(state.winPanel, pal.panel, 255)
    utils.setBoxColor(state.winPanelEdge, pal.line, 255)
    utils.setColor(state.winStarGlow, pal.starEdge, 0)

    -- 星星复位：暗星出来、星体隐藏、光环收掉、亮点归零
    for i, s in ipairs(state.winStars) do
        s.burst = false
        deco.bursts[i] = false
        utils.setFontSize(s.ctrl, s.size)
        utils.setTextColor(s.ctrl, pal.star, 0)
        utils.setPos(s.ctrl, s.baseX, s.baseY)
        utils.setPos(s.ghost, s.baseX, s.baseY)
        utils.setTextColor(s.ghost, pal.starOff, 0)
        utils.setSize(s.spark, 2, 2)
        utils.setColor(s.spark, pal.wave, 0)
        utils.setPos(s.spark, s.baseX, s.baseY)
        for j = 1, #s.rings do
            utils.setSize(s.rings[j], 24, 24)
            utils.setColor(s.rings[j], pal.starEdge, 0)
            utils.setPos(s.rings[j], s.baseX, s.baseY)
        end
    end

    for _, c in ipairs(deco.confetti) do
        utils.setColor(c.ctrl, pal.star, 0)
    end
    for j = 1, #(deco.shock or {}) do
        utils.setSize(deco.shock[j], 60, 60)
        utils.setColor(deco.shock[j], pal.starEdge, 0)
    end
    if deco.flash then utils.setColor(deco.flash, pal.wave, 0) end

    M.applyFrame(0)
end

-- 面板 / 文字 / 按钮的入场（k = 0..1）
function M.applyFrame(k)
    local pal = utils.palette()
    local e = easeOut(clamp01(k))
    -- 面板：0.72 → 1（带过冲）
    if state.winPanel then
        local s = 0.72 + 0.28 * backOut(clamp01(k), 1.7)
        utils.setScale(state.winPanel.root, s)
        if state.winPanelEdge then utils.setScale(state.winPanelEdge.root, s) end
        if state.winPanelShadow then utils.setScale(state.winPanelShadow.root, s) end
    end
    utils.setTextColor(state.winTitle, pal.accent, 255 * e)
    utils.setTextColor(state.winSubtitle, pal.text, 240 * e)
    utils.setTextColor(state.winStats, pal.ok, 240 * e)
    utils.setTextColor(state.winFooter, pal.dim, 220 * e)
end

-- ================================================================
-- 每帧
-- ================================================================
function M.update(dt)
    if not state.winOpen or not state.winPanel then return end
    dt = tonumber(dt) or 0
    if dt <= 0 then return end
    state.winAnimT = (state.winAnimT or 0) + dt
    local t = state.winAnimT
    local pal = utils.palette()

    -- ---------- 遮罩 + 面板 ----------
    local k = clamp01(t / INTRO)
    utils.setColor(state.winOverlay, pal.overlay, (config.DEFAULT_WIN_OVERLAY_ALPHA or 168) * k)
    M.applyFrame(clamp01(t / INTRO))

    local pulse = 0.5 + 0.5 * math.sin(t * 3.4)
    for i = 1, #(state.winGlow or {}) do
        local g = state.winGlow[i]
        utils.setColor(g.ctrl, pal.starEdge, g.base * (0.75 + 0.75 * pulse) * k)
    end

    -- ---------- 彩带波点（一直流动） ----------
    local bandT = t * 1.6
    for _, list in ipairs({ deco.ribbonA, deco.ribbonB }) do
        for _, d in ipairs(list) do
            local w = math.sin(bandT + d.phase) * 3.2
            utils.setPos(d.ctrl, d.x, d.y + w)
            utils.setColor(d.ctrl, pal.juice, 150 + 70 * (0.5 + 0.5 * math.sin(bandT * 1.7 + d.phase)))
        end
    end

    -- ---------- 星尘 ----------
    local _, ph = panelSize()
    local confettiOn = t > CONFETTI_FROM
    for i, c in ipairs(deco.confetti) do
        if confettiOn then
            local life = ((t - CONFETTI_FROM) * c.speed + c.phase) % 1
            local y = ph / 2 - life * (ph + 60)
            local x = c.x + math.sin(life * 6.28 * 2 + c.phase * 6) * 12
            local a = math.sin(life * math.pi) * 200
            utils.setPos(c.ctrl, x, y)
            utils.setColor(c.ctrl, pal.star, a)
        else
            utils.setColor(c.ctrl, pal.star, 0)
        end
    end

    -- ---------- 三颗星 ----------
    for i, s in ipairs(state.winStars) do
        local lt = t - (STAR0 + s.order * STAR_GAP)
        local ghostA = 130 * clamp01((t - GHOST_AT) / 0.18)

        if lt < 0 then
            utils.setTextColor(s.ghost, pal.starOff, ghostA)
            utils.setTextColor(s.ctrl, pal.star, 0)
            utils.setColor(s.spark, pal.wave, 0)
            utils.setSize(s.spark, 2, 2)
            utils.setColor(s.glowDot, pal.starEdge, 0)
            for j = 1, #s.rings do utils.setColor(s.rings[j], pal.starEdge, 0) end
        elseif lt < SPARK_T then
            -- 星心先亮一点光（亮核 + 一圈柔光）
            utils.setTextColor(s.ghost, pal.starOff, ghostA)
            utils.setTextColor(s.ctrl, pal.star, 0)
            local q = lt / SPARK_T
            local sz = 8 + 30 * easeOut(q)
            utils.setSize(s.spark, sz, sz)
            utils.setColor(s.spark, pal.wave, 255 * q)
            utils.setPos(s.glowDot, s.baseX, s.baseY)
            utils.setColor(s.glowDot, pal.starEdge, 150 * q)
        else
            local pk = clamp01((lt - SPARK_T) / POP_T)
            -- 亮点炸开 → 收掉
            utils.setColor(s.spark, pal.wave, 255 * (1 - clamp01((lt - SPARK_T) / 0.12)))
            utils.setSize(s.spark, 38, 38)
            utils.setColor(s.glowDot, pal.starEdge, 150 * (1 - pk))

            -- 星体：0.25 → 过冲 → 1
            local sc = 0.25 + 0.75 * backOut(pk, 2.2)
            utils.setFontSize(s.ctrl, s.size * sc)
            utils.setTextColor(s.ctrl, (pk < 0.55) and pal.wave or pal.star, 255)
            -- 暗星在被点亮的同时退场
            utils.setTextColor(s.ghost, pal.starOff, ghostA * (1 - pk))

            -- 光环一圈圈荡开
            for j = 1, #s.rings do
                local rt = lt - SPARK_T - (j - 1) * 0.07
                local rk = clamp01(rt / RING_T)
                if rk <= 0 or rk >= 1 then
                    utils.setColor(s.rings[j], pal.starEdge, 0)
                else
                    local sz = 26 + 168 * easeOut(rk)
                    utils.setSize(s.rings[j], sz, sz)
                    utils.setColor(s.rings[j], pal.starEdge, 230 * (1 - rk))
                end
                utils.setPos(s.rings[j], s.baseX, s.baseY)
            end

            -- 点亮瞬间迸一把果汁粒子
            if not s.burst and pk > 0.30 then
                s.burst = true
                local us = utils.uiScale()
                fx.spawn(s.baseX * us, s.baseY * us, {
                    n = math.floor(config.DEFAULT_WIN_STAR_BURST or 12), keys = { "star", "juice4", "juice1" },
                    dir = 90, spread = 360, speed = 300 * us, life = 0.6, size = 9 * us,
                })
                -- 第三颗：全屏白光 + 大爆
                if s.order == 2 then
                    local us2 = utils.uiScale()
                    fx.spawn(0, 0, { n = 26, keys = { "star", "juice4", "juice1", "juice2" },
                        dir = 90, spread = 360, speed = 520 * us2, life = 0.9, size = 12 * us2 })
                end
            end
        end

        -- 点亮之后：上下轻轻浮 + 跟随呼吸
        if lt > SPARK_T + POP_T then
            local bob = math.sin(t * 2.2 + s.order * 0.9) * 3
            utils.setPos(s.ctrl, s.baseX, s.baseY + bob)
        end
    end

    -- 第三颗星点亮时从星排中心荡开的两圈冲击波
    for j = 1, #deco.shock do
        local st = t - (STAR0 + 2 * STAR_GAP + SPARK_T) - (j - 1) * 0.10
        if st <= 0 or st >= 0.72 then
            utils.setColor(deco.shock[j], pal.starEdge, 0)
        else
            local q = st / 0.72
            local sz = 70 + 520 * easeOut(q)
            utils.setSize(deco.shock[j], sz, sz)
            utils.setColor(deco.shock[j], pal.starEdge, 190 * (1 - q))
        end
    end

    -- 第三颗星的全屏白光（★ 别给纯白 170：会把整块面板冲成一片白纸 0.3 秒，实测太刺眼）
    if deco.flash then
        local ft = t - (STAR0 + 2 * STAR_GAP + SPARK_T)
        if ft > 0 and ft < 0.30 then
            local fk = ft / 0.30
            local a = 120 * math.sin(fk * math.pi)
            utils.setColor(deco.flash, pal.starEdge, a)
        else
            utils.setColor(deco.flash, pal.starEdge, 0)
        end
    end

    utils.setColor(state.winStarGlow, pal.starEdge, (30 + 22 * pulse) * k)

    -- ---------- 跑马灯 ----------
    local starsDone = t > (STAR0 + 2 * STAR_GAP + SPARK_T + POP_T + STAR_SETTLE)
    local step = config.DEFAULT_WIN_ANIM_STEP or 0.10
    local hold = config.DEFAULT_WIN_ANIM_HOLD or (ANIM_CELLS * step)
    if hold <= 0 then hold = ANIM_CELLS * step end
    if hold <= 0 then hold = 1.2 end
    for _, cell in ipairs(state.winAnimCells) do
        local a = 0
        if starsDone then
            local tp = (t - (STAR0 + 2 * STAR_GAP + SPARK_T + POP_T + STAR_SETTLE) - cell.order * step) % hold
            if tp < RISE then
                a = tp / RISE
            elseif tp < RISE + FALL then
                a = 1 - (tp - RISE) / FALL
            else
                a = 0
            end
        end
        local hex = (a > 0.55) and pal.fruit or pal.juice
        utils.setColor(cell.ctrl, hex, (90 + a * 165) * k)
        local sz = cell.cs * (1 + 0.16 * a)
        utils.setSize(cell.ctrl, sz, sz)
    end

    -- ---------- 按钮错峰弹入 ----------
    for i, btn in ipairs(state.winButtons) do
        local bt = t - (BTN0 + (i - 1) * BTN_GAP)
        if bt < 0 then
            utils.setScale(btn.root, 0.01)
            utils.setBoxColor(btn.bg, pal[btn.bgKey] or pal.card, 255)
            utils.setTextColor(btn.label, pal[btn.labelKey] or pal.text, 0)
        else
            local q = backOut(clamp01(bt / 0.22), 2.0)
            utils.setScale(btn.root, 0.75 + 0.25 * q)
            utils.setBoxColor(btn.bg, pal[btn.bgKey] or pal.card, 255)
            utils.setTextColor(btn.label, pal[btn.labelKey] or pal.text, 255 * clamp01(bt / 0.12))
        end
    end
end

-- ================================================================
-- 显隐 / 开关
-- ================================================================
function M.setVisible(v)
    state.winOpen = v and true or false
    utils.setVisibleAll(state.winNodes, v)
    if v then
        state.winAnimT = 0
        M.refresh()
        local _, ph = panelSize()
        local us = utils.uiScale()
        fx.spawn(0, (ph / 2 - 20) * us, { n = 20, keys = { "juice1", "juice2", "juice4", "juice3" },
            dir = 270, spread = 150, speed = 380 * us, life = 0.8, size = 11 * us })
    else
        fx.cancelAll()
    end
end

function M.open(levelIndex)
    if not state.winPanel and not M.init() then return false end
    state.winLevelIndex = math.max(1, math.floor(tonumber(levelIndex) or state.currentLevelIndex or 1))
    M.setVisible(true)
    return true
end

function M.close()
    M.setVisible(false)
end

function M.isOpen()
    return state.winOpen == true
end

function M.invokeButton(slot)
    if not state.winOpen then return end
    local btn = state.winButtons[slot]
    if btn and btn.action then btn.action() end
end

function M.confirmPrimary()
    if not state.winOpen then return end
    local btn = state.winButtons[3]
    if btn and btn.action then btn.action() else M.doBack() end
end

function M.doReplay()
    M.close()
    if M.actions.onReplay then M.actions.onReplay() end
end

function M.doPrev()
    M.close()
    if M.actions.onPrev then M.actions.onPrev() end
end

function M.doNext()
    M.close()
    if M.actions.onNext then M.actions.onNext() end
end

function M.doBack()
    M.close()
    if M.actions.onBackToSelect then M.actions.onBackToSelect() end
end

function M.setActions(t)
    if type(t) == "table" then M.actions = t end
end

return M
