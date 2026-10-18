-- ================================================================
-- 点灯迷题 2D · 棋盘视图
--   把 board 的数据画出来，并把「按一格」演成一整套动效：
--
--   点击 → ① 该格下压回弹 + 方形冲击波从格心扩散
--          ② 十字五格按「距中心远近」错峰【横向翻牌】（X 轴压扁→展开，中点换色）
--          ③ 翻成亮的格子迸溅暖色粒子；翻成灭的冒一缕冷色轻烟
--          ④ 全部翻完后解锁输入
--
--   ★ 每个灯格 = 一个容器 + 5 个子控件（光晕 / 灯体 / 闪光 / 顶面高光 / 命中区）。
--     用容器统一驱动缩放，灯体与高光永远不会脱节。
--   ★ 亮灯有「光晕呼吸」（错相位），整屏像灯海在呼吸；剩 ≤3 盏时呼吸加剧。
-- ================================================================

---@diagnostic disable: undefined-global

local M = {}

local state = require("default_import_file/state")
local config = require("default_import_file/config")
local utils = require("default_import_file/utils")
local anim = require("default_import_file/anim")
local fx = require("default_import_file/fx")
local board = require("default_import_file/board")

-- ★ 三个 tag 的分工（沿用 2048 踩坑后的结论）：
--   TAG_MOVE：翻牌链（下一次按压会整体打断并 snap）
--   TAG_FX  ：装饰（闪光 / 庆祝 / 入场），可被整体清掉
--   TAG_TICK：关键时序（解锁输入、结算回调），只有整局重置才清
local TAG_MOVE = "view:move"
local TAG_FX = "view:fx"
local TAG_TICK = "view:tick"

-- 每个灯格自己的装饰动画 tag：闪光 / 顶面高光 / 按压都用独立 tag，
-- 否则「A 格翻牌时清 TAG_FX」会把 B 格还在播的闪光一起掐掉。
local function fxTag(tv)
    return "view:fx:" .. tv.idx
end

-- 棋盘根的基础变换（静止态）；冲击波/照片态都改它
local baseX, baseY, baseScale, baseRot = 0, 0, 1, 0

-- 呼吸计时（20fps 刷一次就够，省掉大量 setter）
local breathAcc = 0

local actions = { onPress = nil }

function M.setActions(a)
    actions = a or {}
end

-- ================================================================
-- ★ 建棋盘（只建一次）
-- ================================================================
function M.init()
    if not state.containerBoardBg or not state.containerTile then return false end
    if (state.rectPrefabId or 0) <= 0 then return false end

    local pal = config.DEFAULT_PALETTE or {}
    local cell = utils.cellSize()
    local gap = utils.cellGap()
    local W, H = utils.boardW(), utils.boardH()
    local pad = config.DEFAULT_BOARD_PAD or 14

    -- 描边（外扩一圈）先建，底板压在它上面，看起来就是一圈细边
    state.boardEdge = utils.createControl(state.rectPrefabId, 0, 0,
        W + pad * 2 + 4, H + pad * 2 + 4,
        utils.hexToColor(pal.boardEdge or "1B2A4A"), state.containerBoardBg)
    state.boardFrame = utils.createControl(state.rectPrefabId, 0, 0,
        W + pad * 2, H + pad * 2,
        utils.hexToColor(pal.boardBg or "0F1730"), state.containerBoardBg)
    utils.raise(state.boardFrame)

    -- 30 个格位底（静止不动，翻牌时在它上面换色）
    state.cellBacks = {}
    local inset = config.DEFAULT_CELL_INSET or 7
    local rows, cols = board.rows(), board.cols()
    for r = 1, rows do
        for c = 1, cols do
            local x, y = utils.cellCenter(r, c)
            local back = utils.createControl(state.rectPrefabId, x, y,
                cell - inset * 2, cell - inset * 2,
                utils.hexToColorA(pal.cellOff or "18223A", 120), state.containerBoardBg)
            state.cellBacks[#state.cellBacks + 1] = back
        end
    end

    -- 灯格
    state.tileViews = {}
    for r = 1, rows do
        for c = 1, cols do
            local idx = board.index(r, c)
            local root = utils.createContainer(state.containerTile)
            if root then
                local x, y = utils.cellCenter(r, c)
                local bodyW = cell - inset * 2
                pcall(function()
                    root:SetAnchoredPosition(x, y)
                    root:SetSizeDelta(cell, cell)
                end)

                -- ① 光晕（在灯体后面，比灯体大一圈）
                local halo = utils.createControl(state.rectPrefabId, 0, 0,
                    cell * 1.26, cell * 1.26,
                    utils.hexToColorA(pal.glow or "FFB020", 0), root)
                -- ② 灯体
                local body = utils.createControl(state.rectPrefabId, 0, 0,
                    bodyW, bodyW, utils.hexToColor(pal.cellOff or "18223A"), root)
                -- ③ 闪光（翻成亮的一瞬间闪一下，平时 alpha=0）
                local flash = utils.createControl(state.rectPrefabId, 0, 0,
                    bodyW, bodyW, utils.hexToColorA("FFFFFF", 0), root)
                -- ④ 顶面高光（一条横杠，做出厚度感）
                local top = utils.createControl(state.rectPrefabId, 0,
                    bodyW / 2 - 11, bodyW - 18, 6,
                    utils.hexToColorA(pal.cellOffTop or "1F2B48", 70), root)
                -- ⑤ 命中区（最上层，自身透明）
                local hit = utils.createHit(0, 0, cell, cell, root, true)

                utils.applyLayerOrder({ halo, body, flash, top, hit })

                local tv = {
                    root = root, halo = halo, body = body, flash = flash, top = top, hit = hit,
                    r = r, c = c, idx = idx, on = 0, flipping = false,
                }
                state.tileViews[#state.tileViews + 1] = tv

                if hit then
                    M.bindHit(tv)
                end
            end
        end
    end

    M.resetTransform()
    return #state.tileViews == rows * cols
end

-- ================================================================
-- ★ 单个灯格的点击反馈（按下变暗、抬起还原、点击才算数）
-- ================================================================
function M.bindHit(tv)
    local hit = tv.hit
    local E = Enum.CursorEventType
    if not hit or not E then return end

    local pressed = false
    local function down()
        if not state.inputReady then return end
        pressed = true
        anim.clear("view:press" .. tv.idx)
        anim.tween(config.DEFAULT_ANIM_PRESS_TIME or 0.085, function(p)
            if tv.flipping then return end
            utils.setScale(tv.root, 1 - (1 - (config.DEFAULT_ANIM_PRESS_SCALE or 0.90)) * p)
        end, { ease = "outQuad", tag = "view:press" .. tv.idx })
    end
    local function up()
        if not pressed then return end
        pressed = false
        anim.clear("view:press" .. tv.idx)
        anim.tween(config.DEFAULT_ANIM_PRESS_TIME or 0.085, function(p)
            if tv.flipping then return end
            local from = config.DEFAULT_ANIM_PRESS_SCALE or 0.90
            utils.setScale(tv.root, from + (1 - from) * p)
        end, { ease = "outBack", tag = "view:press" .. tv.idx })
    end

    utils.onCursor(hit, E.CursorDown, down)
    utils.onCursor(hit, E.CursorUp, up)
    utils.onCursor(hit, E.CursorClick, function()
        pressed = false
        anim.clear("view:press" .. tv.idx)
        if not tv.flipping then utils.setScale(tv.root, 1) end
        if actions.onPress then actions.onPress(tv.idx) end
    end)
end

-- ================================================================
-- ★ 视觉状态（亮 / 灭）
-- ================================================================
local function applyLook(tv, on)
    local bodyHex, topHex, glowHex = utils.tileLook(on == 1)
    utils.setColor(tv.body, bodyHex, 255)
    utils.setColor(tv.top, topHex, on == 1 and 150 or 70)
    if tv.halo then
        if on == 1 then
            utils.setVisible(tv.halo, true)
            utils.setColor(tv.halo, glowHex or "FFB020", 0)
        else
            utils.setVisible(tv.halo, false)
        end
    end
    tv.on = on
end

-- ================================================================
-- ★ 无动画同步（进关 / 撤销 / 打断后兜底）
-- ================================================================
function M.snapAll(bd)
    local cell = utils.cellSize()
    for i = 1, #state.tileViews do
        local tv = state.tileViews[i]
        tv.flipping = false
        local x, y = utils.cellCenter(tv.r, tv.c)
        pcall(function()
            tv.root:SetAnchoredPosition(x, y)
            tv.root:SetLocalScale(1, 1, 1)
            tv.root:SetSizeDelta(cell, cell)
        end)
        if tv.flash then utils.setColor(tv.flash, "FFFFFF", 0) end
        applyLook(tv, board.get(bd, tv.idx))
    end
end

-- ================================================================
-- ★ 单个灯格翻牌：压扁 → 中点换色 → 展开
--   toOn   : 0/1
--   delay  : 错峰延迟
--   speed  : 时长系数（连击时 <1 更快）
--   onMid  : 中点回调（撒粒子）
-- ================================================================
local function flipTile(tv, toOn, delay, speed, onMid)
    local half = (config.DEFAULT_ANIM_FLIP_HALF or 0.072) * speed
    local back = (config.DEFAULT_ANIM_FLIP_BACK or 0.155) * speed
    local key = fxTag(tv)

    anim.delay(delay, function()
        tv.flipping = true
        anim.clear("view:press" .. tv.idx)
        anim.clear(key)

        -- 第一步：横向压扁（翻牌的「侧面转到看不见」那半程）
        anim.tween(half, function(p)
            utils.setScale(tv.root, 1 - (1 - 0.045) * p)
        end, { ease = "inQuad", tag = TAG_MOVE })

        -- 第二步：中点换色 + 展开
        anim.delay(half, function()
            applyLook(tv, toOn)
            tv.flipping = false

            local bodyHex, topHex = utils.tileLook(toOn == 1)

            -- 换色瞬间的白色闪光：alpha 峰值 → 0
            if tv.flash then
                local peak = toOn == 1 and 165 or 80
                utils.setColor(tv.flash, "FFFFFF", peak)
                anim.tween(0.22, function(p)
                    utils.setColor(tv.flash, "FFFFFF", math.floor(peak * (1 - p)))
                end, { ease = "outQuad", tag = key })
            end

            -- 顶面高光：先推到最亮再回落，做出「刚被点亮」的余晖
            if tv.top then
                local peak = toOn == 1 and 235 or 110
                local baseA = toOn == 1 and 150 or 70
                utils.setColor(tv.top, topHex, peak)
                anim.tween(0.30, function(p)
                    utils.setColor(tv.top, topHex, math.floor(peak + (baseA - peak) * p))
                end, { ease = "outQuad", tag = key })
            end

            if onMid then onMid(tv) end

            anim.tween(back, function(p)
                utils.setScale(tv.root, 0.045 + (1 - 0.045) * p)
            end, { ease = "outBack", tag = TAG_MOVE })
        end, TAG_MOVE)
    end, TAG_MOVE)
end

-- ================================================================
-- ★ 播放一次按压（数据已由 game 更新完毕）
--   返回本次动画总时长（秒），供输入锁与看门狗使用
-- ================================================================
function M.playPress(idx, bd, opts)
    opts = opts or {}
    local speed = opts.speed or 1
    local list = board.toggleSetWithDist(idx)
    local stagger = (config.DEFAULT_ANIM_STAGGER or 0.032) * speed

    -- ★★ 关键：先用【按下前】的盘面把视图落定。
    --   调用方已经先把逻辑盘面翻转过了，如果这里用新盘面 snap，
    --   待会要翻的那 5 格颜色已经是终态，翻牌就「看不出变化」。
    anim.clear(TAG_MOVE)
    M.snapAll(opts.prev or bd)

    -- ★ 不再单独播「下压回弹」：翻牌的首段本身就是压扁，
    --   两段同时写 scale 会互相打架（谁后写谁生效，画面会抖）。
    --   按压反馈交给「冲击波 + 翻牌压扁」两件事，已经足够。

    -- 方形冲击波（从被按格子的场景坐标发出）
    local cx, cy = utils.cellCenter(board.rowOf(idx) + 1, board.colOf(idx) + 1)
    local sx, sy = utils.boardToScene(cx, cy)
    fx.ring(sx, sy, utils.cellSize() * 0.92, opts.ringHex or "4CC9F0")
    if (opts.shake or 0) ~= 0 then fx.shake() end

    local maxDelay = 0
    for i = 1, #list do
        local item = list[i]
        local d = (item.dist == 0) and 0 or stagger
        if d > maxDelay then maxDelay = d end
        local tv = M.tileOf(item.idx)
        if tv then
            local toOn = board.get(bd, item.idx)
            -- 每格给一点随机偏移，涟漪才不像机器
            local jitter = (i > 1) and (math.random() * stagger * 0.45) or 0
            flipTile(tv, toOn, d + jitter, speed, function(t)
                local px, py = utils.cellCenter(t.r, t.c)
                local wx, wy = utils.boardToScene(px, py)
                if toOn == 1 then
                    fx.burst(wx, wy, config.DEFAULT_PALETTE.cellOn or "FFCB6B", 6)
                else
                    fx.puff(wx, wy, config.DEFAULT_PALETTE.textDim or "8296B8", 3)
                end
            end)
        end
    end

    local total = maxDelay + (config.DEFAULT_ANIM_FLIP_HALF or 0.072) * speed
                + (config.DEFAULT_ANIM_FLIP_BACK or 0.155) * speed
    return total
end

-- ================================================================
-- ★ 进关入场：灯格从「缩到 0 + 略偏下」逐格弹出来
-- ================================================================
function M.spawnIn(bd)
    anim.clear(TAG_MOVE)
    anim.clear(TAG_FX)
    local stagger = config.DEFAULT_ANIM_SPAWN_STAGGER or 0.021
    local dur = config.DEFAULT_ANIM_SPAWN_TIME or 0.34
    local rows, cols = board.rows(), board.cols()

    for i = 1, #state.tileViews do
        local tv = state.tileViews[i]
        tv.flipping = false
        local x, y = utils.cellCenter(tv.r, tv.c)
        local order = (tv.r - 1) + (tv.c - 1)          -- 左上 → 右下斜向
        local d = order * stagger * 0.5 + math.random() * stagger

        applyLook(tv, board.get(bd, tv.idx))
        if tv.flash then utils.setColor(tv.flash, "FFFFFF", 0) end
        pcall(function()
            tv.root:SetAnchoredPosition(x, y + 26)
            tv.root:SetLocalScale(0.001, 0.001, 1)
        end)

        anim.delay(d, function()
            anim.tween(dur, function(p)
                local s = anim.Ease.outBack(p)
                pcall(function()
                    tv.root:SetLocalScale(s, s, 1)
                    tv.root:SetAnchoredPosition(x, y + 26 * (1 - p))
                end)
            end, { ease = "linear", tag = TAG_FX })
        end, TAG_FX)
    end

    return (rows + cols) * stagger * 0.5 + dur
end

-- ================================================================
-- ★ 通关庆祝：一道光斜着扫过整块棋盘（每格亮一下再暗下去）
-- ================================================================
function M.celebrate(onDone)
    local stagger = config.DEFAULT_WIN_WAVE_STAGGER or 0.034
    local dur = config.DEFAULT_WIN_WAVE_TIME or 0.30
    local accent = config.DEFAULT_PALETTE.good or "5BE7A9"
    local offHex = config.DEFAULT_PALETTE.cellOff or "18223A"
    local rows, cols = board.rows(), board.cols()
    local maxD = 0

    for i = 1, #state.tileViews do
        local tv = state.tileViews[i]
        local d = ((tv.r - 1) + (tv.c - 1)) * stagger
        if d > maxD then maxD = d end
        anim.delay(d, function()
            if tv.halo then
                utils.setVisible(tv.halo, true)
                utils.setColor(tv.halo, accent, 130)
            end
            utils.setColor(tv.body, accent, 255)
            anim.tween(dur, function(p)
                local a = math.floor(130 * (1 - p))
                utils.setColor(tv.body, offHex, 255)
                if tv.halo then utils.setColor(tv.halo, accent, a) end
            end, { ease = "outQuad", tag = TAG_FX })
            if tv.halo then
                anim.delay(dur, function()
                    if tv.on ~= 1 then utils.setVisible(tv.halo, false) end
                end, TAG_FX)
            end
        end, TAG_FX)
    end

    anim.delay(maxD + dur, function()
        if onDone then onDone() end
    end, TAG_TICK)
    return maxD + dur
end

-- ================================================================
-- ★ 提示高亮
-- ================================================================
function M.showHint(idx)
    state.hintIndex = idx
    state.hintUntil = state.time + (config.DEFAULT_ANIM_HINT_TIME or 1.10)
    local tv = M.tileOf(idx)
    if not tv then return end
    local accent = config.DEFAULT_PALETTE.accent or "4CC9F0"
    local cx, cy = utils.cellCenter(tv.r, tv.c)
    local wx, wy = utils.boardToScene(cx, cy)
    fx.ring(wx, wy, utils.cellSize() * 0.86, accent)
    fx.floatText(wx, wy + utils.cellSize() * 0.72, "按这一格", accent, 20)
end

-- ================================================================
-- ★ 棋盘根变换（静止 / 照片态）
-- ================================================================
function M.setBase(x, y, s, rot)
    baseX, baseY, baseScale, baseRot = x, y, s, rot
    M.applyTransform()
end

function M.applyTransform()
    local root = state.containerBoard
    if not root then return end
    local ox, oy = 0, 0
    if (state.shakeT or 0) > 0 then
        local amp = (config.DEFAULT_ANIM_SHAKE or 4) * (state.shakeT / (config.DEFAULT_ANIM_SHAKE_TIME or 0.16))
        ox = (math.random() * 2 - 1) * amp
        oy = (math.random() * 2 - 1) * amp
    end
    pcall(function()
        root:SetAnchoredPosition(baseX + ox, baseY + oy)
        root:SetLocalScale(baseScale, baseScale, 1)
        root:SetLocalRotation(0, 0, baseRot)
    end)
end

function M.resetTransform()
    M.setBase(state.boardCX or 0, state.boardCY or 0, 1, 0)
end

-- ★ 缩成「战利品照片」：缩小 + 平移 + 轻微倾斜
function M.toPhoto(onDone)
    local x0, y0, s0, r0 = baseX, baseY, baseScale, baseRot
    local tx = config.DEFAULT_WIN_PHOTO_X or -330
    local ty = config.DEFAULT_WIN_PHOTO_Y or 8
    local ts = config.DEFAULT_WIN_PHOTO_SCALE or 0.60
    local tr = config.DEFAULT_WIN_PHOTO_TILT or -3.5
    anim.tween(config.DEFAULT_WIN_PHOTO_TIME or 0.52, function(p)
        baseX = x0 + (tx - x0) * p
        baseY = y0 + (ty - y0) * p
        baseScale = s0 + (ts - s0) * p
        baseRot = r0 + (tr - r0) * p
        M.applyTransform()
    end, { ease = "inOutCubic", tag = TAG_TICK, onDone = onDone })
end

-- ================================================================
-- ★ 每帧：呼吸 + 提示脉冲 + 震屏衰减
-- ================================================================
function M.update(dt)
    if not dt or dt <= 0 then return end
    state.time = state.time + dt

    if (state.shakeT or 0) > 0 then
        state.shakeT = state.shakeT - dt
        if state.shakeT < 0 then state.shakeT = 0 end
        M.applyTransform()
    end

    -- 提示脉冲：把提示格的灯体推亮一点
    if state.hintIndex >= 0 then
        local tv = M.tileOf(state.hintIndex)
        if state.time > state.hintUntil then
            if tv then applyLook(tv, tv.on) end   -- ★ 到期必须把颜色还回去
            state.hintIndex = -1
        elseif tv then
            local ph = (state.time * 6.0) % (math.pi * 2)
            local k = 0.5 + 0.5 * math.sin(ph)
            utils.setColor(tv.body, config.DEFAULT_PALETTE.accent or "4CC9F0",
                math.floor(60 + 90 * k))
        end
    end

    -- 呼吸：20fps 刷新
    breathAcc = breathAcc + dt
    if breathAcc < 0.05 then return end
    local step = breathAcc
    breathAcc = 0

    local lit = 0
    for i = 1, #state.tileViews do
        if state.tileViews[i].on == 1 then lit = lit + 1 end
    end
    local near = (lit > 0 and lit <= (config.DEFAULT_NEARWIN_LIT or 3))
    local gain = near and (config.DEFAULT_NEARWIN_GAIN or 1.55) or 1
    local spd = (config.DEFAULT_BREATH_SPEED or 1.25) * gain
    local lo = config.DEFAULT_BREATH_MIN or 0.42
    local hi = config.DEFAULT_BREATH_MAX or 1.0
    local phaseStep = config.DEFAULT_BREATH_PHASE or 0.55

    for i = 1, #state.tileViews do
        local tv = state.tileViews[i]
        if tv.on == 1 and tv.halo then
            local ph = state.time * spd + (tv.r + tv.c) * phaseStep
            local k = lo + (hi - lo) * (0.5 + 0.5 * math.sin(ph))
            local base = near and 138 or 92
            utils.setColor(tv.halo, config.DEFAULT_PALETTE.glow or "FFB020", math.floor(base * k))
            local s = 1 + 0.04 * (k - 0.5)
            utils.setScale(tv.halo, s)
        end
    end
end

-- ================================================================
-- 查询 / 显隐
-- ================================================================
function M.tileOf(idx)
    for i = 1, #state.tileViews do
        if state.tileViews[i].idx == idx then return state.tileViews[i] end
    end
    return nil
end

function M.setVisible(v)
    if state.containerBoard then utils.setVisible(state.containerBoard, v) end
end

function M.clearAnim()
    anim.clear(TAG_MOVE)
    anim.clear(TAG_FX)
end

return M
