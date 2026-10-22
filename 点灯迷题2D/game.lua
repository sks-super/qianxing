-- ================================================================
-- 点灯迷题 16 · 入口
-- ================================================================
-- 挂载：客户端控件容器的【容器节点】（script.object）
--
-- 参数：rectPrefabId（必填·纯色矩形）、textPrefabId（必填·文本框）、
--       cursorPrefabId（必填·光标检测区域）
--       可选音效：flipAudioId / clickAudioId / winAudioId
--       开发用：autoStart=1 直接进第 1 块；autoPress=<0..63> 自动按一格
--
-- 流程：大关（16×16 图）→ 4 个 8×8 小关 → 4/4 → 合拢 + 上色演出
-- ================================================================

---@diagnostic disable: undefined-global

local state = require("default_import_file/state")
local config = require("default_import_file/config")
local utils = require("default_import_file/utils")
local anim = require("default_import_file/anim")
local art = require("default_import_file/art")
local board = require("default_import_file/board")
local view = require("default_import_file/view")
local fx = require("default_import_file/fx")
local hud = require("default_import_file/hud")
local book = require("default_import_file/book")
local guide = require("default_import_file/guide")
local signal = require("default_import_file/signal")
local fadeScreen = require("default_import_file/fadeScreen")
local audio = require("default_import_file/audio")

local SETTLE_SEC = config.DEFAULT_SETTLE_SEC or 90
local settleModal = nil

local TAG_TICK = "game:tick"
local TAG_FIN = "game:finale"
local finaleRoot = nil

local startPiece, pressCell, onCleared, doFinale, switchChapter, finaleToBook
local devAutoPress, devAt = -1, 0
local devSolve = false

-- ================================================================
-- ★★ 真机（千星客户端）的接口是 script:GetParam(name)；
--    本工程早期误写成 GetParamValue（只有模拟器认），真机读不到参数 →
--    直接报「请设置脚本参数 rectPrefabId」。这里以 GetParam 为准，旧名做兜底。
function getParamNumber(name, default)
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
-- ★ 存档（服务器信号）与结算
-- ================================================================
local function pushSave()
    signal.sendSave(signal.buildSave(state, config.chapterCount()))
end

-- 服务器下发的存档：一维 bool 列表 → state.chapterDone
local function applySave(list)
    if type(list) ~= "table" then return end
    state.chapterDone = state.chapterDone or {}
    local k = 1
    for c = 1, config.chapterCount() do
        local dm = state.chapterDone[c]
        if not dm then
            dm = { false, false, false, false }
            state.chapterDone[c] = dm
        end
        for p = 1, 4 do
            dm[p] = list[k] == true
            k = k + 1
        end
    end
    if state.chapterIndex and state.chapterDone[state.chapterIndex] then
        state.slotDone = state.chapterDone[state.chapterIndex]
    end
    if book.isOpen() then book.refresh() end
end

local function closeSettleModal()
    if settleModal then
        utils.destroy(settleModal)
        settleModal = nil
    end
end

-- legal = 已满 90 秒（安全退出：置逃跑合法性 + 胜利）；否则提前结算
local function doSettle(legal)
    if state.settling then return end
    state.settling = true
    closeSettleModal()
    signal.sendSettle(legal, legal)
    hud.setVisible(false)
    view.setPlayVisible(false)
    view.setRefVisible(false)
    fx.clear()
    anim.clearAll()
    state.phase = "book"
    state.inputReady = false
    book.open(state.chapterIndex or 1, 1, true)
    state.settling = false
end

-- ★ 结算按钮是**常驻**的：挂在 containerTop（画册之上），
--   倒计时从进入游戏开始一直走，换关/回画册都不重置。
local settleBtn = nil
local showSettleConfirm          -- 前置声明（buildSettleBtn 的点击闭包要用）

local function refreshSettle()
    if not settleBtn then return end
    local pal = config.DEFAULT_PALETTE or {}
    local left = SETTLE_SEC - (state.playTime or 0)
    if left <= 0 then
        utils.setText(settleBtn.label, "结算 ✓")
        utils.setColor(settleBtn.base, pal.accent or "1E4A63", 255)
        utils.setTextColor(settleBtn.label, pal.star or "FFD166", 255)
    else
        local sec = math.max(0, math.ceil(left))
        utils.setText(settleBtn.label, string.format("结算 %d:%02d", math.floor(sec / 60), sec % 60))
        utils.setColor(settleBtn.base, pal.btn or "1C2740", 255)
        utils.setTextColor(settleBtn.label, pal.textDim or "8296B8", 255)
    end
end

local function buildSettleBtn()
    if settleBtn or not state.containerTop then return end
    settleBtn = utils.createButton(432, 300,
        config.DEFAULT_SETTLE_BTN_W or 122, config.DEFAULT_SETTLE_BTN_H or 38,
        state.containerTop, {
        text = "结算 1:30", fontSize = 16,
        bg = (config.DEFAULT_PALETTE or {}).btn, bgDown = (config.DEFAULT_PALETTE or {}).btnDown,
        textColor = (config.DEFAULT_PALETTE or {}).textDim,
        onClick = function()
            if state.settling then return end
            if state.phase ~= "play" and state.phase ~= "book" then return end
            if (state.playTime or 0) >= SETTLE_SEC then
                doSettle(true)
            else
                showSettleConfirm()
            end
        end,
    })
    if settleBtn then
        utils.raise(settleBtn.base); utils.raise(settleBtn.label); utils.raise(settleBtn.hit)
    end
    refreshSettle()
end

showSettleConfirm = function()
    if settleModal then return end
    local pal = config.DEFAULT_PALETTE or {}
    local par = utils.createContainer(state.containerFade)
    if not par then return end
    settleModal = par

    local ov = utils.createControl(state.rectPrefabId, 0, 0, 2400, 1400,
        utils.hexToColorA(pal.overlay or "05070C", 190), par)
    utils.raise(ov)
    local panel = utils.createControl(state.rectPrefabId, 0, 0, 560, 260,
        utils.hexToColor(pal.panel or "101828"), par)
    utils.raise(panel)
    local edge = utils.createControl(state.rectPrefabId, 0, 0, 570, 270,
        utils.hexToColor(pal.panelEdge or "1E2A47"), par)
    utils.sink(edge)

    local t1 = utils.createText(0, 72, 520, 40, "此时退出，本关不会记为通关",
        utils.hexToColor(pal.text or "E9F0FF"), 24, par)
    utils.raise(t1)
    local t2 = utils.createText(0, 22, 520, 32, "确定要直接结算吗？",
        utils.hexToColor(pal.textDim or "8296B8"), 18, par)
    utils.raise(t2)

    local bw, bh, gap = 176, 52, 24
    local cancel = utils.createButton(-(bw + gap) / 2, -66, bw, bh, par, {
        text = "继续游玩", fontSize = 19,
        bg = pal.btn, bgDown = pal.btnDown, textColor = pal.text,
        onClick = function() closeSettleModal() end,
    })
    local ok = utils.createButton((bw + gap) / 2, -66, bw, bh, par, {
        text = "确认结算", fontSize = 19,
        bg = pal.accent or "1E4A63", bgDown = pal.btnDown, textColor = "FFF6E8",
        onClick = function() doSettle(false) end,
    })
    for _, b in ipairs({ cancel, ok }) do
        if b then
            utils.raise(b.base); utils.raise(b.label); utils.raise(b.hit)
        end
    end
end

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
    if not state.containerRef then state.containerRef = utils.createContainer(s) end
    if not state.containerBoard then state.containerBoard = utils.createContainer(s) end
    if not state.containerFx then state.containerFx = utils.createContainer(s) end
    if not state.containerHud then state.containerHud = utils.createContainer(s) end
    if not state.containerChips then state.containerChips = utils.createContainer(s) end
    if not state.containerBook then state.containerBook = utils.createContainer(s) end
    if not state.containerWin then state.containerWin = utils.createContainer(s) end
    if not state.containerFade then state.containerFade = utils.createContainer(s) end
    if not state.containerTop then state.containerTop = utils.createContainer(s) end
    if not state.containerGuide then state.containerGuide = utils.createContainer(s) end

    utils.applyLayerOrder({
        state.containerBg, state.containerRef, state.containerBoard, state.containerFx,
        state.containerHud, state.containerChips, state.containerBook,
        state.containerWin, state.containerTop, state.containerGuide, state.containerFade,
    })
    return true
end

local function createBackground()
    local par = state.containerBg
    local pal = config.DEFAULT_PALETTE or {}
    if not par or (state.rectPrefabId or 0) <= 0 then return end
    utils.createControl(state.rectPrefabId, 0, 0, 2400, 1400, utils.hexToColor(pal.bg or "070A12"), par)
    local blobs = {
        { -560, 320, 820, 820, pal.bgGlow or "152348", 26, 16 },
        { 560, -300, 900, 900, pal.bgGlow2 or "2A1550", 20, -12 },
    }
    for i = 1, #blobs do
        local b = blobs[i]
        local c = utils.createControl(state.rectPrefabId, b[1], b[2], b[3], b[4],
            utils.hexToColorA(b[5], b[6]), par)
        if c then utils.setRotationZ(c, b[7]) end
    end
end

-- ================================================================
-- 开一个小关
-- ================================================================
startPiece = function(pieceIdx, silent, hideView)
    local ch = config.getChapter(state.chapterIndex)
    if not ch then return false end
    pieceIdx = math.floor(tonumber(pieceIdx) or 1)
    if pieceIdx < 1 or pieceIdx > 4 then pieceIdx = 1 end

    local grid = art.parse(ch.pic, ch.noNormalize)
    state.pic = grid
    local p = config.PIECES[pieceIdx]
    state.quadTarget = art.quad(grid, p.ox, p.oy)
    state.pieceIndex = pieceIdx

    local k = (config.DEFAULT_A_BY_PIECE or {})[pieceIdx] or 3
    local seed = board.seedOf(ch.key, pieceIdx * 97 + state.chapterIndex * 13)
    local lv = board.genLevel(state.quadTarget, k, seed)

    state.board = lv.start
    state.targetBoard = lv.target
    state.aSet = lv.a
    state.bestSteps = #lv.a
    state.moves = 0
    state.history = {}
    state.hintIndex = -1
    state.pieceOpen = true
    state.phase = "play"

    anim.clearAll()
    fx.clear()
    view.setRef(state.quadTarget)
    view.syncPlay(state.board)
    view.setVisible(not hideView)
    -- ★ 进关演出期间左侧目标图也必须藏住（否则「还没飞过去图就在了」）
    view.setRefVisible(not hideView)
    hud.refresh()
    state.inputReady = false

    if silent then
        state.inputReady = true
    else
        local d = view.spawn()
        anim.delay(d, function() state.inputReady = true end, TAG_TICK)
    end
    return true
end

-- ================================================================
-- ★ 从画册进入小关（整套演出）
--   ① 书页上那块（已通关则先把 32×32 化成 8×8）飞到左侧目标位
--   ② 落定那一刻目标图才出现（此前左侧必须是空的）
--   ③ 目标图上叠一张拷贝，按 (a) 序列逐格十字翻转 → 演示「目标图 → 初始图」
--   ④ 拷贝再滑到右侧成为当前盘面，随后解锁输入
-- ================================================================

-- 按棋盘几何画一个 8×8（与右侧盘面逐格对齐）
local function boardBlock(par, vals, withPaper)
    local cs, gap = utils.cellSize(), utils.cellGap()
    local W = utils.boardW()
    local pal = config.DEFAULT_PALETTE or {}
    local paper = nil
    if withPaper then
        paper = utils.createControl(state.rectPrefabId, 0, 0, W + gap * 2, W + gap * 2,
            utils.hexToColorA(pal.paper or "F7F8FA", 255), par)
    end
    local x0 = -W / 2 + gap + cs / 2
    local y0 = W / 2 - gap - cs / 2
    local cells = {}
    for i = 0, 63 do
        local r, c = math.floor(i / 8) + 1, (i % 8) + 1
        local v = ((vals[i + 1] or 0) == 1) and 1 or 0
        local hex = (v == 1) and (pal.ink or "111318") or (pal.paper or "F7F8FA")
        local ctrl = utils.createControl(state.rectPrefabId,
            x0 + (c - 1) * (cs + gap), y0 - (r - 1) * (cs + gap), cs, cs,
            utils.hexToColorA(hex, 255), par)
        if ctrl then
            cells[#cells + 1] = { ctrl = ctrl, idx = i, v = v }
        end
    end
    -- ★ 后建的在下面（引擎按 z 降序画），纸底要显式沉到最底层
    if paper then utils.sink(paper) end
    return cells
end

local function paintBlockCell(cell, v)
    local pal = config.DEFAULT_PALETTE or {}
    local hex = (v == 1) and (pal.ink or "111318") or (pal.paper or "F7F8FA")
    utils.setColor(cell.ctrl, hex, 255)
    cell.v = v
end

-- 与玩家点击完全一致的翻牌：压到 0.045 再展开，中点换色
local function flipBlockCell(cell, toV, delay)
    local half = config.DEFAULT_ANIM_FLIP_HALF or 0.07
    local back = config.DEFAULT_ANIM_FLIP_BACK or 0.15
    anim.delay(delay, function()
        anim.tween(half, function(p)
            utils.setScale(cell.ctrl, 1 - 0.955 * p)
        end, { ease = "inQuad", tag = TAG_TICK })
        anim.delay(half, function()
            paintBlockCell(cell, toV)
            anim.tween(back, function(p)
                utils.setScale(cell.ctrl, 0.045 + 0.955 * p)
            end, { ease = "outBack", tag = TAG_TICK })
        end, TAG_TICK)
    end, TAG_TICK)
end

-- 目标图 → 初始图：按 (a) 顺序逐个「按一格」，画面/音效与玩家点击一致
local function demoPresses(cells, baseX, baseY)
    local order = {}
    for i = 1, #(state.aSet or {}) do order[#order + 1] = state.aSet[i] end
    table.sort(order)
    local vals = {}
    for i = 1, #cells do vals[cells[i].idx] = cells[i].v end
    local pal = config.DEFAULT_PALETTE or {}
    local STEP = 0.30
    local last = 0
    for i = 1, #order do
        local idx = order[i]
        local d0 = (i - 1) * STEP
        last = d0
        local r, c = math.floor(idx / 8) + 1, (idx % 8) + 1
        local lx, ly = utils.cellCenter(r, c)
        anim.delay(d0, function()
            fx.ring(baseX + lx, baseY + ly, utils.cellSize() * 0.9, pal.accent or "4CC9F0")
            fx.burst(baseX + lx, baseY + ly, pal.ink or "111318", 5)
            audio.playFlip()
        end, TAG_TICK)
        local list = board.toggleSetOf(idx)
        for k = 1, #list do
            local it = list[k]
            local cell = cells[it.idx + 1]
            if cell then
                local toV = (vals[it.idx] == 1) and 0 or 1
                vals[it.idx] = toV
                flipBlockCell(cell, toV, d0 + ((it.dist == 0) and 0 or 0.028))
            end
        end
    end
    return last + 0.32
end

-- 已通关的块：把 64 图的 32×32 一角铺在 8×8 之上（飞出去之前先淡出成线稿）
local function colorQuadOn(par, chKey, pieceIdx, span)
    local rects = art.artRects(chKey)
    if not rects then return {} end
    local out = {}
    local P = span / 32.0
    local qx = (pieceIdx == 2 or pieceIdx == 4) and 32 or 0
    local qy = (pieceIdx == 3 or pieceIdx == 4) and 32 or 0
    local ox = -span / 2
    for i = 1, #rects do
        local r = rects[i]
        local x0, x1 = math.max(r.x, qx), math.min(r.x + r.w, qx + 32)
        local y0, y1 = math.max(r.y, qy), math.min(r.y + r.h, qy + 32)
        if x1 > x0 and y1 > y0 then
            local lw, lh = (x1 - x0), (y1 - y0)
            local c = utils.createControl(state.rectPrefabId,
                ox + (x0 - qx) * P + lw * P / 2,
                span / 2 - (y0 - qy) * P - lh * P / 2,
                lw * P + 0.6, lh * P + 0.6, utils.hexToColorA(r.hex, 255), par)
            if c then
                utils.raise(c)
                out[#out + 1] = { ctrl = c, hex = r.hex }
            end
        end
    end
    return out
end

local function enterPiece(chIdx, pieceIdx, fromX, fromY, fromSize)
    if state.bookBusy then return false end
    state.bookBusy = true

    state.chapterIndex = chIdx
    state.chapterDone = state.chapterDone or {}
    local dm = state.chapterDone[chIdx]
    if not dm then
        dm = { false, false, false, false }
        state.chapterDone[chIdx] = dm
    end
    state.slotDone = dm
    state.slotStars = state.slotStars or { 0, 0, 0, 0 }

    hud.setVisible(false)
    hud.setButtonsVisible(true)          -- 回到游玩界面：按钮恢复
    startPiece(pieceIdx, true, true)     -- 先算关，但两侧都藏着
    -- ★★ 必须放在 startPiece 之后：startPiece 里 anim.clearAll() 会把退场补间一起清掉，
    --   书就再也藏不住了（之前的表现：整场演出书页一直盖在下面）。
    audio.playOpen()                      -- 进入关卡：openAudioId
    book.dismiss(0.26)                    -- 整本书收缩退场（飞行块在 containerWin 上，不受影响）
    -- ★★ 以前 startPiece 末尾会 setRefVisible(mode==1) 把左侧目标图直接点亮，
    --   于是还没飞过去，目标图就已经在那儿了。进关演出期间一律藏住。
    view.setPlayVisible(false)
    view.setRefVisible(false)
    state.phase = "enter"

    local W = utils.boardW()
    local pal = config.DEFAULT_PALETTE or {}
    local refX, refY = config.DEFAULT_REF_CX or -236, config.DEFAULT_REF_CY or -34
    local bdX, bdY = config.DEFAULT_BOARD_CX or 236, config.DEFAULT_BOARD_CY or -34

    -- 飞行块：用棋盘几何来画，落定时与左侧目标图逐格重合
    local holder = utils.createContainer(state.containerWin)
    if not holder then state.bookBusy = false; return false end
    local ch = config.getChapter(chIdx)
    local isDone = (dm[pieceIdx] == true) and ch ~= nil
    local cells = {}
    local colorRects = {}
    if isDone then
        -- 已通关：先只铺 32×32 彩图角（不画线稿、不铺纸）
        colorRects = colorQuadOn(holder, ch.key, pieceIdx, W - utils.cellGap() * 2)
        if #colorRects == 0 then isDone = false end
    end
    if not isDone then
        cells = boardBlock(holder, state.targetBoard, true)
    end
    utils.setPos(holder, fromX, fromY)
    local s0 = (fromSize or 150) / W
    utils.setScale(holder, s0)
    utils.setRotationZ(holder, 6)

    -- ④ 拷贝滑到右侧，交接成当前盘面
    local function toBoard(copy)
        local revealed = false
        anim.tween(0.58, function(p)
            local e = anim.Ease.inOutCubic(p)
            utils.setPos(copy, utils.lerp(refX, bdX, e),
                utils.lerp(refY, bdY, e) + math.sin(e * math.pi) * 24)
            utils.setRotationZ(copy, -3.5 * math.sin(e * math.pi))
            utils.setScale(copy, 1 - 0.05 * math.sin(e * math.pi))
            if not revealed and p > 0.72 then
                revealed = true
                -- 右侧盘面提前显形：拷贝正好落在它身上，交接看不出接缝
                view.setPlayVisible(true)
                hud.setVisible(true)
                hud.refresh()
                utils.setPos(state.containerHud, 0, 96)
                anim.tween(0.30, function(q)
                    utils.setPos(state.containerHud, 0, 96 * (1 - anim.Ease.outBack(q)))
                end, { ease = "linear", tag = TAG_TICK })
            end
        end, { ease = "linear", tag = TAG_TICK, onDone = function()
            utils.destroy(copy)
            utils.setPos(state.containerHud, 0, 0)
            fx.ring(bdX, bdY, W * 0.46, pal.accent or "4CC9F0")
            fx.burst(bdX, bdY, pal.accent or "4CC9F0", 12)
            audio.playClick()
            state.phase = "play"
            state.bookBusy = false
            state.inputReady = true
        end })
    end

    -- ② 落定：目标图出现 + ③ 拷贝演示「目标图 → 初始图」
    local function onLanded()
        utils.destroy(holder)
        view.setRefVisible(true)
        fx.ring(refX, refY, W * 0.46, pal.accent or "4CC9F0")
        audio.playClick()

        local copy = utils.createContainer(state.containerWin)
        if not copy then
            view.setPlayVisible(true)
            hud.setVisible(true)
            state.phase = "play"
            state.bookBusy = false
            state.inputReady = true
            return
        end
        utils.setPos(copy, refX, refY)
        local cells = boardBlock(copy, state.targetBoard, true)
        utils.setScale(copy, 0.88)
        anim.tween(0.24, function(p)
            utils.setScale(copy, 0.88 + 0.12 * anim.Ease.outBack(p))
        end, { ease = "linear", tag = TAG_TICK })

        local dur = demoPresses(cells, refX, refY)
        anim.delay(dur, function()
            -- 兜底：拷贝必须与右侧盘面逐格一致（不同步就露馅）
            for i = 1, #cells do
                paintBlockCell(cells[i], state.board[cells[i].idx + 1])
            end
            utils.setScale(copy, 1)
            anim.delay(0.12, function() toBoard(copy) end, TAG_TICK)
        end, TAG_TICK)
    end

    -- ① 从点击位置飞到左侧目标位
    local function fly()
        anim.tween(0.58, function(p)
            local e = anim.Ease.outCubic(p)
            utils.setPos(holder, utils.lerp(fromX, refX, e), utils.lerp(fromY, refY, e))
            utils.setScale(holder, utils.lerp(s0, 1, e) * (1 + 0.07 * math.sin(e * math.pi)))
            utils.setRotationZ(holder, 6 * (1 - e))
        end, { ease = "linear", tag = TAG_TICK, onDone = onLanded })
    end

    if isDone then
        -- 已通关：先亮着彩图 0.3s（让人看清这块已经上色），再化成本关的 8×8 线稿起飞
        anim.delay(0.30, function()
            anim.tween(0.22, function(p)
                for i = 1, #colorRects do
                    utils.setColor(colorRects[i].ctrl, colorRects[i].hex, math.floor(255 * (1 - p)))
                end
            end, { ease = "inQuad", tag = TAG_TICK, onDone = function()
                for i = 1, #colorRects do utils.destroy(colorRects[i].ctrl) end
                colorRects = {}
                cells = boardBlock(holder, state.targetBoard, true)
                for i = 1, #cells do utils.setScale(cells[i].ctrl, 1.14) end
                anim.tween(0.18, function(p)
                    local k = 1 + 0.14 * (1 - anim.Ease.outBack(p))
                    for i = 1, #cells do utils.setScale(cells[i].ctrl, k) end
                end, { ease = "linear", tag = TAG_TICK, onDone = function()
                    for i = 1, #cells do utils.setScale(cells[i].ctrl, 1) end
                    fly()
                end })
            end })
        end, TAG_TICK)
    else
        fly()
    end

    return true
end

-- ================================================================
-- 按一格
-- ================================================================
pressCell = function(idx)
    if state.phase ~= "play" or not state.pieceOpen then return false end
    if not state.inputReady then
        state.pendingPress = idx
        return false
    end
    if not board.valid(idx) then return false end

    local prev = board.copy(state.board)
    board.press(state.board, idx)
    state.moves = state.moves + 1
    state.history[#state.history + 1] = idx

    local dur = view.playPress(idx, prev, { board = state.board })
    audio.playFlip()
    hud.setSteps(state.moves)
    hud.popSteps()

    state.inputReady = false
    anim.delay(dur + (config.DEFAULT_ANIM_INPUT_LOCK or 0.1), function()
        state.inputReady = true
        local p = state.pendingPress
        state.pendingPress = nil
        if p then pressCell(p) end
    end, TAG_TICK)

    -- ★ 只保留「找不同」：盘面与目标完全一致才算复原
    local win = board.equals(state.board, state.targetBoard)
    if win then
        state.pieceOpen = false
        anim.delay(dur + 0.08, function() onCleared() end, TAG_TICK)
    end
    return true
end

-- ================================================================
-- 小关完成
-- ================================================================
onCleared = function()
    if state.phase ~= "play" then return false end
    state.phase = "finish"
    state.inputReady = false

    local i = state.pieceIndex
    local best = state.bestSteps or 0
    local stars = 1
    if state.moves <= best then stars = 3
    elseif state.moves <= best + (config.DEFAULT_STAR_TWO_EXTRA or 2) then stars = 2 end

    state.slotDone[i] = true
    state.slotStars[i] = math.max(state.slotStars[i] or 0, stars)
    hud.setChipDone(i)
    audio.playWin()
    pushSave()

    local all = true
    for k = 1, 4 do
        if not state.slotDone[k] then all = false end
    end

    -- ★ 引导模式：要带着玩家走完整个「猫猫」大关（4 块全通）才收掉
    if state.chapterIndex == 1 and all then
        state.tutorialHint = false
        guide.clearHint()
    end

    -- ★ 大关全通：发一次成就（成就序号 = 大关号 + 1，计数由服务器按约定累加）
    if all then
        state.achDone = state.achDone or {}
        local c = state.chapterIndex or 1
        if not state.achDone[c] then
            state.achDone[c] = true
            signal.sendAchievement(c)
        end
        pushSave()
    end

    if all then
        anim.delay(0.55, function() doFinale() end, TAG_TICK)
    else
        anim.delay(0.85, function()
            local nxt = nil
            for k = 1, 4 do
                local j = (i + k - 1) % 4 + 1
                if not state.slotDone[j] then nxt = j; break end
            end
            if nxt then
                fadeScreen.start({ onPeak = function() startPiece(nxt) end })
            else
                state.phase = "pick"
            end
        end, TAG_TICK)
    end
    return true
end

-- ================================================================
-- ★ 通关演出：四块撞击合拢 → 64×64 上色
--   ① 四块分别从上 / 右 / 下 / 左飞入，依次撞进自己的槽位（outBack 冲过头再回弹）
--   ② 落位瞬间：压扁—回弹（squash & stretch）+ 冲击环 + 镜头轻震
--   ③ 四块齐 → 白闪 → 64×64 彩图按对角线错峰淡入
--      ★ 彩图用「同色矩形合并」绘制，像素边界严格相邻并留 1px 重叠 → 中间绝不留行/列缝
-- ================================================================
doFinale = function()
    state.phase = "finish"
    state.inputReady = false
    view.setVisible(false)
    hud.setVisible(false)
    fx.clear()
    audio.playWin()

    local ch = config.getChapter(state.chapterIndex)
    local pal = config.DEFAULT_PALETTE or {}
    local accent = pal.accent or "4CC9F0"
    local cell, gap = 24, 2
    local Q = 8 * cell + 7 * gap          -- 单块边长 206
    local total = 2 * Q + gap             -- 合起来 414
    local half = total / 2
    local off = (Q + gap) / 2             -- 每块中心到整体中心的偏移 104

    local par = utils.createContainer(state.containerWin)
    if not par then return end
    finaleRoot = par

    local edge = utils.createControl(state.rectPrefabId, 0, 0, total + 30, total + 30,
        utils.hexToColor(pal.panelEdge or "1E2A47"), par)
    local paperC = utils.createControl(state.rectPrefabId, 0, 0, total + 22, total + 22,
        utils.hexToColor(pal.paper or "F7F8FA"), par)

    -- ---- 四块：各自一个容器 + 8×8 线稿 ----
    --   sx/sy = 目标槽位；fx0/fy0 = 屏外起点偏移；rot0 = 飞入时的初始角度
    local quads = {
        { ox = 0, oy = 0, sx = -off, sy =  off, fx0 =    0, fy0 =  780, rot0 =  -7 },  -- 左上 ← 上
        { ox = 8, oy = 0, sx =  off, sy =  off, fx0 =  980, fy0 =    0, rot0 =   9 },  -- 右上 ← 右
        { ox = 0, oy = 8, sx = -off, sy = -off, fx0 =    0, fy0 = -780, rot0 =   6 },  -- 左下 ← 下
        { ox = 8, oy = 8, sx =  off, sy = -off, fx0 = -980, fy0 =    0, rot0 =  -9 },  -- 右下 ← 左
    }

    for qi = 1, 4 do
        local q = quads[qi]
        local holder = utils.createContainer(par)
        q.ctrl = holder
        if holder then
            utils.setPos(holder, q.sx + q.fx0, q.sy + q.fy0)
            utils.setScaleXY(holder, 0.88, 0.88)
            utils.setRotationZ(holder, q.rot0)
            for y = 1, 8 do
                for x = 1, 8 do
                    local px = -Q / 2 + cell / 2 + (x - 1) * (cell + gap)
                    local py = Q / 2 - cell / 2 - (y - 1) * (cell + gap)
                    local v = art.at(state.pic, q.ox + x, q.oy + y)
                    utils.createControl(state.rectPrefabId, px, py, cell - gap, cell - gap,
                        utils.hexToColor(v == 1 and (pal.ink or "111318") or (pal.paper or "F7F8FA")), holder)
                end
            end
        end
    end

    -- ---- 64×64 彩图：同色矩形合并后逐块建控件（初始 alpha 0）----
    local colorLayer = utils.createContainer(par)
    local colorRects = {}
    local rects, S = art.artRects(ch.key)
    S = S or 64
    local P = total / S                   -- 一个"像素"在屏幕上的边长
    if colorLayer and rects then
        for i = 1, #rects do
            local r = rects[i]
            -- ★ 宽高各 +1：相邻矩形互相压 1px，栅格化时接缝不会透出底色（这就是"中间不留缝"）
            local px = -half + (r.x + r.w / 2) * P
            local py = half - (r.y + r.h / 2) * P
            local c = utils.createControl(state.rectPrefabId, px, py,
                r.w * P + 1.0, r.h * P + 1.0, utils.hexToColorA(r.hex, 0), colorLayer)
            if c then
                colorRects[#colorRects + 1] = {
                    ctrl = c, hex = r.hex,
                    d = (r.x + r.y) / (2.0 * S),   -- 对角线归一化，用来做错峰
                }
            end
        end
    end

    -- 白闪：四块落齐时"咔嚓"一下（★ 建在彩图之后 = 压在彩图之上）
    local flash = utils.createControl(state.rectPrefabId, 0, 0, total + 22, total + 22,
        utils.hexToColorA("FFFFFF", 0), par)

    -- ---- 标题 ----
    local titleC = utils.createText(0, -half - 44, 560, 44, "「" .. (ch.name or "") .. "」完成",
        utils.hexToColor(pal.text or "E9F0FF"), 26, par)

    -- ★★ 显式钉死同层顺序（从下往上逐个 SetAsLastSibling）
    --   真机：后创建的在上；模拟器：它内部把 SetSiblingIndex(i) 插到 len-1-i，
    --   于是"默认创建顺序"在模拟器里正好反过来 —— 底板会盖住彩图（实测过：
    --   通关面板只剩一块深蓝）。SetAsLastSibling 两边语义一致（=最上层），
    --   所以按「底板→纸→四块→彩图→白闪→标题」逐个提层，两个引擎都能对齐。
    utils.raise(edge)
    utils.raise(paperC)
    for qi = 1, 4 do utils.raise(quads[qi].ctrl) end
    utils.raise(colorLayer)
    utils.raise(flash)
    utils.raise(titleC)

    -- ---- 上色 ----
    local function colorize()
        anim.tween(0.10, function(p)
            utils.setColor(flash, "FFFFFF", math.floor(160 * p))
        end, { ease = "outQuad", tag = TAG_FIN, onDone = function()
            anim.tween(0.32, function(p)
                utils.setColor(flash, "FFFFFF", math.floor(160 * (1 - p)))
            end, { ease = "inQuad", tag = TAG_FIN })
        end })

        for i = 1, #colorRects do
            local rc = colorRects[i]
            anim.delay(0.08 + rc.d * 0.34, function()
                anim.tween(0.30, function(p)
                    utils.setColor(rc.ctrl, rc.hex, math.floor(255 * p))
                end, { ease = "outQuad", tag = TAG_FIN })
            end, TAG_FIN)
        end

        -- 彩图盖满后把线稿收起来（否则两层轮廓会叠）
        anim.delay(0.52, function()
            for qi = 1, 4 do
                if quads[qi].ctrl then utils.setVisible(quads[qi].ctrl, false) end
            end
        end, TAG_FIN)

        for i = 1, 7 do
            anim.delay(0.24 + i * 0.07, function() audio.playStar() end, TAG_FIN)
        end

        anim.delay(0.62, function()
            fx.confetti()
            audio.playWin()
            hud.setVisible(true)
            hud.setButtonsVisible(false)     -- ★ 结算页只要信息，按钮全撤
            hud.refresh()
            state.phase = "finish"
        end, TAG_FIN)

        -- 彩图看够了 → 飞去书页
        anim.delay(1.60, function() finaleToBook(total) end, TAG_FIN)
    end

    -- ---- 飞入 ----
    local FLY, STAG, BASE = 0.46, 0.17, 0.14
    local landed = 0

    local function impact(q)
        landed = landed + 1
        utils.setPos(q.ctrl, q.sx, q.sy)
        utils.setRotationZ(q.ctrl, 0)
        -- 压扁 → 欠阻尼回弹（振幅指数衰减 + 余弦振荡）
        anim.tween(0.62, function(p)
            local damp = (1 - p) * (1 - p)
            local a = 0.22 * damp * math.cos(p * math.pi * 6.5)
            utils.setScaleXY(q.ctrl, 1 + a, 1 - a)
        end, { ease = "linear", tag = TAG_FIN, onDone = function()
            utils.setScaleXY(q.ctrl, 1, 1)
        end })
        fx.ring(q.sx, q.sy, Q * 0.9, accent)
        fx.shake()
        audio.playStar()
        if landed >= 4 then
            anim.delay(0.28, colorize, TAG_FIN)
        end
    end

    for qi = 1, 4 do
        local q = quads[qi]
        if q.ctrl then
            anim.delay(BASE + (qi - 1) * STAG, function()
                audio.playFlip()
                anim.tween(FLY, function(p)
                    utils.setPos(q.ctrl, q.sx + q.fx0 * (1 - p), q.sy + q.fy0 * (1 - p))
                    local s = 0.88 + 0.12 * p
                    utils.setScaleXY(q.ctrl, s, s)
                    utils.setRotationZ(q.ctrl, q.rot0 * (1 - p))
                end, { ease = "outBack", tag = TAG_FIN, onDone = function() impact(q) end })
            end, TAG_FIN)
        end
    end
end

-- ================================================================
-- ★ 通关演出 → 画册：彩图飞到书页图片位 → 扇形蒙版 → 魔法星命中变彩
-- ================================================================
finaleToBook = function(total)
    local ch = config.getChapter(state.chapterIndex)
    if not ch then return end
    local pic = book.PIC or { cx = 0, cy = -18, size = 300 }
    state.phase = "book"
    state.inputReady = false
    hud.setVisible(false)

    -- ① 彩图副本：从面板中心起飞
    local rects = art.artRects(ch.key)
    local fly = utils.createContainer(state.containerWin)
    if fly and rects then
        local P = total / 64
        for i = 1, #rects do
            local r = rects[i]
            utils.createControl(state.rectPrefabId,
                -total / 2 + (r.x + r.w / 2) * P,
                total / 2 - (r.y + r.h / 2) * P,
                r.w * P + 1.0, r.h * P + 1.0, utils.hexToColor(r.hex), fly)
        end
    end

    -- ② 扇形蒙版：16 片扇叶从中心放射展开（每片宽度按最大半径处的弦长取，能盖满屏）
    local N = 20
    local R = 900
    -- 宽度取「最大半径处弦长」再多 35%：扇叶之间不留缝，边缘也不会露出尖角
    local wide = 2 * R * math.tan(math.pi / N) * 1.35 + 8
    local blades = {}
    for i = 1, N do
        local a = (i - 1) * (360 / N)
        local c = utils.createControl(state.rectPrefabId, 0, 0, wide, 2 * R,
            utils.hexToColor(book.PAPER or "FBF6EA"), state.containerFade)
        if c then
            utils.setRotationZ(c, a - 90)
            utils.setScaleXY(c, 0.001, 0.001)
            blades[#blades + 1] = { c = c, a = math.rad(a) }
        end
    end
    local function setFan(s)
        if s < 0.001 then s = 0.001 end
        for i = 1, #blades do
            local b = blades[i]
            utils.setScaleXY(b.c, s, s)
            utils.setPos(b.c, math.cos(b.a) * R * s, math.sin(b.a) * R * s)
        end
    end

    local s1 = pic.size / total

    local function startFly()
        if not fly then return end
        anim.tween(0.55, function(p)
            local e = anim.Ease.inOutCubic(p)
            utils.setPos(fly, utils.lerp(0, pic.cx, e), utils.lerp(0, pic.cy, e))
            utils.setScale(fly, utils.lerp(1, s1, e))
            utils.setRotationZ(fly, -5 * math.sin(e * math.pi))
        end, { ease = "linear", tag = TAG_FIN, onDone = function()
            utils.setRotationZ(fly, 0)
            -- ③ 扇叶合拢（蒙版盖住全屏的那一刻切场景）
            anim.tween(0.34, function(p)
                setFan(anim.Ease.inQuad(p))
            end, { ease = "linear", tag = TAG_FIN, onDone = function()
                if finaleRoot then utils.destroy(finaleRoot); finaleRoot = nil end
                if fly then utils.destroy(fly); fly = nil end
                view.setPlayVisible(false)
                view.setRefVisible(false)
                book.showPage(state.chapterIndex, true)      -- 装饰先灰，等星星
                anim.delay(0.12, function()
                    -- ④ 扇叶打开 → 魔法星逐个命中，装饰变彩
                    anim.tween(0.46, function(p)
                        setFan(1 - anim.Ease.outCubic(p))
                    end, { ease = "linear", tag = TAG_FIN, onDone = function()
                        for i = 1, #blades do utils.destroy(blades[i].c) end
                        book.celebrate()
                    end })
                end, TAG_FIN)
            end })
        end })
    end
    anim.delay(0.08, startFly, TAG_FIN)
end

-- ================================================================
-- 换大关
-- ================================================================
switchChapter = function()
    local nextIdx = (state.chapterIndex or 1) % config.chapterCount() + 1
    state.chapterIndex = nextIdx
    state.slotDone = { false, false, false, false }
    state.slotStars = { 0, 0, 0, 0 }
    if finaleRoot then utils.destroy(finaleRoot); finaleRoot = nil end
    fadeScreen.start({ onPeak = function()
        hud.setVisible(true)
        startPiece(1)
    end })
end

-- ================================================================
-- 撤销 / 提示
-- ================================================================
local function undo()
    if state.phase ~= "play" or not state.inputReady then return false end
    if (config.DEFAULT_UNDO_ENABLED or 1) == 0 then return false end
    local n = #state.history
    if n < 1 then return false end
    local idx = state.history[n]
    state.history[n] = nil
    local prev = board.copy(state.board)
    board.press(state.board, idx)
    state.moves = math.max(0, state.moves - 1)
    view.playPress(idx, prev, { board = state.board, speed = 0.85 })
    hud.setSteps(state.moves)
    return true
end

local function showHint()
    if state.phase ~= "play" then return false end
    if (config.DEFAULT_HINT_ENABLED or 1) == 0 then return false end
    local idx = board.hintCell(state.aSet, state.history)
    if idx < 0 then return false end
    view.showHint(idx)
    return true
end

-- ================================================================
-- 键盘
-- ================================================================
local function bindKeys(root)
    local K = Enum.KeyEventType
    local function bind(evt, fn)
        pcall(function()
            root:AddKeyEventListener(evt, function() return fn() == true end)
        end)
    end
    bind(K.KeyboardCharacterSkill3KeyDown, function()
        if state.phase == "play" then
            fadeScreen.start({ onPeak = function() startPiece(state.pieceIndex) end })
            return true
        end
        return false
    end)
    bind(K.KeyboardCharacterSkill4KeyDown, showHint)
    bind(K.KeyboardMoveBackwardKeyDown, undo)
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
    if state.rectPrefabId <= 0 then
        printerr("错误：请设置脚本参数 rectPrefabId（纯色矩形 / 图片控件）")
        return
    end

    script:EnableUpdate(true)

    state.clickAudioId = getParamNumber("clickAudioId", 0)
    state.flipAudioId = getParamNumber("flipAudioId", 0)
    if state.flipAudioId <= 0 then state.flipAudioId = getParamNumber("openAudioId", 0) end
    state.winAudioId = getParamNumber("winAudioId", 0)
    state.openAudioId = getParamNumber("openAudioId", 0)
    state.starAudioId = getParamNumber("starAudioId", 0)
    audio.init({
        click = state.clickAudioId, flip = state.flipAudioId,
        win = state.winAudioId, star = state.starAudioId,
        open = state.openAudioId,
    })
    audio.prewarm()

    local okSize, w, h = pcall(function() return game.GetUICanvasSize() end)
    state.canvasW = (okSize and type(w) == "number" and w > 0) and w or config.DEFAULT_VIEW_WIDTH
    state.canvasH = (okSize and type(h) == "number" and h > 0) and h or config.DEFAULT_VIEW_HEIGHT
    utils.computeLayout()
    state.designW = config.DEFAULT_DESIGN_WIDTH
    state.designH = config.DEFAULT_DESIGN_HEIGHT

    if not ensureContainers() then
        printerr("错误：层级容器创建失败（检查 rectPrefabId）")
        return
    end
    fadeScreen.init()
    createBackground()

    if not view.init() then printerr("警告：棋盘初始化失败") end
    if not hud.init() then printerr("警告：信息栏初始化失败") end
    signal.init({ onSave = applySave })
    guide.init({
        onClose = function()
            -- 关掉教程 → 进入「跟着高亮走」的引导模式
            state.tutorialHint = true
            -- 还在封面就先翻到大关 1，让玩家一眼看到被高亮的那一块
            if book.getPage() == 0 then book.open(1, 1) end
        end,
    })

    hud.setActions({
        onUndo = undo,
        onReset = function()
            fadeScreen.start({ onPeak = function() startPiece(state.pieceIndex) end })
        end,
        onHint = showHint,
        onChapter = function()
            if state.bookBusy then return end
            if state.phase ~= "play" then return end
            state.bookBusy = true
            state.phase = "book"
            state.inputReady = false
            anim.clear(TAG_TICK)
            fx.clear()
            -- ★ 游玩界面先退场（棋盘下沉缩小、HUD 往上飘），再翻页，避免"啪"地切走
            local b = state.containerBoard
            local h = state.containerHud
            local bx, by = config.DEFAULT_BOARD_CX or 236, config.DEFAULT_BOARD_CY or -34
            anim.tween(0.18, function(p)
                local e = anim.Ease.inQuad(p)
                if b then
                    utils.setScale(b, 1 - 0.10 * e)
                    utils.setPos(b, bx, by - 26 * e)
                end
                if h then utils.setPos(h, 0, 34 * e) end
            end, { ease = "linear", tag = TAG_TICK, onDone = function()
                if b then utils.setScale(b, 1); utils.setPos(b, bx, by) end
                if h then utils.setPos(h, 0, 0) end
                hud.setVisible(false)
                view.setPlayVisible(false)
                view.setRefVisible(false)
                state.bookBusy = false
                -- ★ 从游玩回到书页 = 一次「翻页」：同一个大关页重新翻开
                book.open(state.chapterIndex or 1, 1, true)
            end })
        end,
    })
    view.setActions({ onPress = function(idx) pressCell(idx) end })

    state.mode = 1                     -- 只保留「找不同」
    state.chapterIndex = 1
    state.chapterDone = state.chapterDone or {
        { false, false, false, false },
        { false, false, false, false },
    }
    state.slotDone = state.chapterDone[1]
    state.slotStars = { 0, 0, 0, 0 }

    finaleRoot = nil
    buildSettleBtn()
    startPiece(1, true)
    hud.setVisible(true)
    hud.setButtonsVisible(true)
    hud.refresh()

    -- 画册（主界面）
    if book.init({ onEnterPiece = enterPiece }) then
        -- 开发用：bookDone=1 把所有大关标成已通关，看彩色书页
        if getParamNumber("bookDone", 0) > 0 then
            state.chapterDone = state.chapterDone or {}
            for c = 1, config.chapterCount() do
                state.chapterDone[c] = { true, true, true, true }
            end
            state.slotDone = state.chapterDone[1]
        end
        local devPage = getParamNumber("bookPage", -1)
        if devPage >= 0 then
            state.phase = "book"
            hud.setVisible(false)
            book.open(devPage, 1)
        elseif getParamNumber("autoStart", 0) > 0 then
            book.setVisible(false)
        else
            state.phase = "book"
            hud.setVisible(false)
            book.open(0, 1)
            if getParamNumber("skipTutorial", 0) <= 0 then
                anim.delay(0.55, function()
                    if not state.tutorialDone then guide.open(1) end
                end, TAG_TICK)
            end
        end
    end

    bindKeys(root)

    if getParamNumber("autoStart", 0) > 0 then
        state.inputReady = true
        startPiece(1)
    end
    -- 开发用：强制打开引导高亮（跳过教程也能看）
    if getParamNumber("hintOn", 0) > 0 then state.tutorialHint = true end
    devAutoPress = getParamNumber("autoPress", -1)
    devSolve = getParamNumber("autoSolve", 0) > 0
    devAt = 1.0
end


-- ================================================================
-- ★ 引导高亮：教程关掉后一直指路，直到「猫猫关第一块」复原
--   书页阶段 → 指左上那一块；游玩阶段 → 指下一个该点的格子
-- ================================================================
local hintKey = nil

function updateTutorialHint()
    if not state.tutorialHint or state.guideOpen then
        if hintKey then hintKey = nil; guide.clearHint() end
        return
    end
    local dm = (state.chapterDone or {})[1]
    local doneAll = dm and dm[1] and dm[2] and dm[3] and dm[4]

    local key, hx, hy, hs
    if state.phase == "book" and book.getPage() == 1 and not doneAll then
        -- 书页：指向下一块还没点亮的
        local nxt = 1
        if dm then
            for i = 1, 4 do
                if not dm[i] then nxt = i; break end
            end
        end
        local c = book.QUAD.centers[nxt]
        key, hx, hy, hs = "book" .. nxt, c[1], c[2], book.QUAD.size + 16
    elseif state.phase == "play" and state.chapterIndex == 1 and not doneAll then
        local idx = board.hintCell(state.aSet, state.history)
        if idx and idx >= 0 then
            local r, c = math.floor(idx / 8) + 1, idx % 8 + 1
            local lx, ly = utils.cellCenter(r, c)
            local bx, by = config.DEFAULT_BOARD_CX or 236, config.DEFAULT_BOARD_CY or -34
            key = "cell" .. state.pieceIndex .. "_" .. idx
            hx, hy, hs = bx + lx, by + ly, utils.cellSize() + 14
        end
    end
    if not key then
        if hintKey then hintKey = nil; guide.clearHint() end
        return
    end
    if key ~= hintKey then
        hintKey = key
        guide.setHint(hx, hy, hs)
    end
end

function OnUpdate(dt)
    if not dt or dt <= 0 then return end
    if dt > 0.05 then dt = 0.05 end
    state.lastDt = dt

    -- ★ 结算倒计时：**全局只走一次**（换关、回画册都不重置）
    if not state.settling then
        state.playTime = (state.playTime or 0) + dt
        local left = SETTLE_SEC - state.playTime
        local sec = math.max(0, math.ceil(left))
        if sec ~= state.settleSec then
            state.settleSec = sec
            refreshSettle()
        end
    end

    anim.update(dt)
    guide.update(dt)
    updateTutorialHint()
    view.update(dt)
    fx.update(dt)
    fadeScreen.update(dt)
    book.update(dt)

    -- 开发用：按 A 自动解题，用来把 4 块跑穿、验证通关演出
    if devSolve and state.phase == "play" and state.inputReady and state.pieceOpen then
        local rest = board.remaining(state.aSet, state.history)
        if #rest > 0 then pressCell(rest[1]) end
    end

    if devAutoPress >= 0 then
        devAt = devAt - dt
        if devAt <= 0 and state.inputReady and state.phase == "play" then
            local p = devAutoPress
            devAutoPress = -1
            pressCell(p)
        end
    end
end

function OnDestroy()
    pcall(function() script:EnableUpdate(false) end)
end
