-- ================================================================
-- 浮岛借木 · 关卡视觉层
--   把 world 的网格状态画成千星图片控件：
--     ① 地形层（海面 → 水面网格线 → 岛缘投影/侧面厚度/沙滩描边 → 草地顶面）
--     ② 物体层（树根 → 木桩 → 立桩 → 石头 → 树木 → 终点旗）
--     ③ 小人层（立绘 或 身体 + 头）
--     ④ 特效层（动作涟漪）
--
--   ★★ 2.5D 视角（本文件的核心，照参考图那种「斜俯视」）
--     参考图的两个特征：
--       ① 水面网格是**屏幕水平 / 垂直**的细线 → 格子不做等距菱形旋转，仍是正交网格；
--       ② 每块地有**厚度**：草地顶面 + 一圈岛缘沙滩描边 + 侧面（土）。
--     立体感完全由「绘制顺序」给出来，而不是靠投影数学：
--       · 描边与侧面按「同层分批画」——先铺满所有描边，再盖所有顶面，
--         于是描边只露在岛的外缘，岛内相邻格之间不会出现一条条缝；
--       · **行号越大 = 越靠近镜头 = 越晚绘制**，于是近处一行的顶面天然盖住
--         远处一行露出来的侧面 —— 这就是「厚度」能看见的原因；
--       · 因此地形 / 物体 / 小人必须混在**同一个容器**里，用深度键统一排序。
--
--     深度键（见 restackWorld）：
--       0xxx 水面网格线 → 1xxx 地块装饰（投影 / 侧面 / 描边）→ 2xxx 草地顶面
--       → 3xxx 物体与小人（同格内：树根 < 木桩 < 立桩 < 石头 < 树木 < 旗 < 小人）
--     每一段都用 `行号 × 10 + 层内次序`，行号是主序。
--
--   ★ 视觉槽位（素材优先、失败当场回退）
--     每一类可视对象都先问一句「有没有专用美术素材元件」（海水/草地/树木/人物）：
--       有  → 用它，并且**绝不写 imageColor** —— 一写就把素材乘上去了（变暗、串色）
--       没有 → 退回通用矩形元件 + 调色板染色（= 加入素材之前的画面）
--     素材是 1024×1024 但内容只占中间一块，所以控件要按 config.DEFAULT_ART_FIT
--     放大，才能让「内容」严丝合缝压住格子。
--
--   所有控件都走「对象池」：一次创建、反复复用，只改位置/尺寸/显隐/颜色，
--   不在关卡切换与每次动作时反复创建销毁。
-- ================================================================

---@diagnostic disable: undefined-global

local M = {}
local state = require("state")
local config = require("config")
local utils = require("utils")
local world = require("world")

-- ================================================================
-- ★ 格子 → UI 坐标（正交网格，不做菱形投影）
--   UI 坐标原点在画布中心，Y 向上为正；row 1 在最上，row 越大越靠下 = 越靠近镜头。
-- ================================================================
local function cellCenterX(c)
    local cols = state.mapCols or 1
    return (state.boardCx or 0) + (c - (cols + 1) / 2) * (state.cellSize or 1)
end

local function cellCenterY(r)
    local rows = state.mapRows or 1
    return (state.boardCy or 0) - (r - (rows + 1) / 2) * (state.cellSize or 1)
end

-- 格子的下边缘：草地顶面的前沿，地块的侧面从这里往下挂
local function cellBottomY(r)
    return cellCenterY(r) - (state.cellSize or 1) / 2
end

-- ★ 物体的「脚线」：站立物（树 / 石头 / 立桩 / 小人）踩在顶面**靠前**的位置，
--   而不是格子正中心 —— 这一点偏移就是「站在方块上面」的错觉来源。
local function cellFootY(r)
    return cellCenterY(r) - (state.cellSize or 1) * (config.DEFAULT_TILE_FOOT_RATIO or 0.18)
end

-- 素材模式下，控件中心相对「它踩的那条脚线」要抬高多少像素
--   （素材内容只占画布中间一块，脚本按 config.DEFAULT_ART_FIT.dy 补偿）
local function artFootOffset(kind)
    local fit = (config.DEFAULT_ART_FIT or {})[kind]
    local dy = (fit and fit.dy) or 0
    return dy * (state.cellSize or 1)
end

-- 小人身体当前形态的「中心 → 脚下」距离
local function playerFootOffset()
    if state.playerCtrlArt then
        return artFootOffset("player")
    end
    local cell = state.cellSize or 1
    local bodyH = state.playerBodyH
    if not bodyH or bodyH <= 0 then bodyH = cell * 1.88 end
    return bodyH / 2
end

-- 小人身体中心：站在高度 h（格）之上
local function playerAnchor()
    local p = state.player
    local cell = state.cellSize or 1
    local foot = cellFootY(p.r) + (p.h or 0) * cell
    return cellCenterX(p.c), foot + playerFootOffset()
end

-- ================================================================
-- ★ 几何：按画布与地图尺寸算出格子边长与棋盘中心
--   2.5D 下格子之外还多出「岛缘描边 + 侧面厚度」，一并计入可用区域，
--   否则最上 / 最下 / 最左 / 最右会被画到画布外面去。
-- ================================================================
function M.computeGeometry()
    local cw = state.canvasW or config.DEFAULT_VIEW_WIDTH
    local ch = state.canvasH or config.DEFAULT_VIEW_HEIGHT
    local barH = config.DEFAULT_HUD_BAR_HEIGHT or 74
    local reserve = config.DEFAULT_HUD_BOTTOM_RESERVE or 88
    local marginX = config.DEFAULT_BOARD_MARGIN_X or 40
    local scale = config.DEFAULT_BOARD_SCALE or 0.9

    local cols = math.max(1, state.mapCols or 1)
    local rows = math.max(1, state.mapRows or 1)

    -- ① 画法决定「格子的外扩量」
    local rimRatio, sideRatio, padPx = 0, 0, 0
    if state.view25d then
        rimRatio = config.DEFAULT_TILE_RIM_RATIO or 0.17    -- 单位：格
        sideRatio = config.DEFAULT_TILE_SIDE_RATIO or 0.30  -- 单位：格
    else
        padPx = 2 * (config.DEFAULT_COAST_PAD or 5)         -- 旧画法：描边是固定像素
    end

    -- ② 求格子边长：横竖各解一遍，取小的
    local spanX = cols + 2 * rimRatio
    local spanY = rows + 2 * rimRatio + sideRatio
    local availW = (cw - marginX * 2) * scale - padPx
    local availH = (ch - barH - reserve) * scale - padPx
    local cell = math.floor(math.min(availW / spanX, availH / spanY))
    cell = utils.clamp(cell, config.DEFAULT_CELL_MIN or 22, config.DEFAULT_CELL_MAX or 64)

    state.cellSize = cell
    state.boardW = cols * cell
    state.boardH = rows * cell
    state.boardCx = 0
    -- 在「HUD 下沿」与「消息栏上沿」之间竖直居中。
    -- 2.5D 下棋盘的可视范围是「上方多一圈描边、下方多一圈描边 + 侧面厚度」，
    -- 所以把棋盘中心再往上抬 side/2，让多出来的那块不至于压到底部消息栏。
    local bandCy = ((ch / 2 - barH) + (-ch / 2 + reserve)) / 2
    state.boardCy = bandCy + sideRatio * cell / 2
    return cell
end

-- ================================================================
-- ★ 深度键：2.5D 的排序依据
--   行号是主序（row 越大越靠近镜头 → 越晚绘制 → 压住后面的一切），
--   同一行内再分「层」，层内再用小数次序微调。
-- ================================================================
local BAND_GRID = 0       -- 水面网格线
local BAND_TILE = 1000    -- 地块装饰：岛缘投影 → 侧面厚度 → 沙滩描边
local BAND_TOP  = 2000    -- 草地顶面
local BAND_OBJ  = 3000    -- 站位物体与小人

-- 同一格上的站立物自下而上的固定次序
local SUB_SHADOW = -0.5
local SUB_ROOT   = 1
local SUB_LOG    = 2
local SUB_STUMP  = 3
local SUB_ROCK   = 4
local SUB_TREE   = 5
local SUB_GOAL   = 6
local SUB_PLAYER = 7

local function depthKey(band, r, sub)
    return band + (tonumber(r) or 0) * 10 + (tonumber(sub) or 0)
end

-- ================================================================
-- ★ 视觉槽位
--   makeSlot(素材元件索引)：打算用哪个预制体 + 是否素材
--     · 总开关关掉 / 索引为 0 → 直接退回通用矩形（art = false）
--     · 索引 > 0 → art = true，真正的成败要等控件建出来才知道
-- ================================================================
local function makeSlot(prefabId)
    local pid = tonumber(prefabId) or 0
    if state.useArt and pid > 0 then
        return { prefab = pid, art = true }
    end
    return { prefab = state.rectPrefabId, art = false }
end

-- 通用矩形槽位（沙滩 / 水下网格 / 木桩 / 立桩 / 树根 / 石头 / 终点旗 …）
local function rectSlot()
    return { prefab = state.rectPrefabId, art = false }
end

-- ================================================================
-- ★ 对象池：从池里取第 i 个控件，不够就新建
--   池里每一项是 { c = 控件, art = 是否素材元件 }。
--   ★ 「是不是素材」只在建出来的那一刻确定：素材元件拿不到控件就当场回退通用矩形，
--     并把 art 记为 false —— 之后这类控件一律按调色板染色。
-- ================================================================
local function poolGet(pool, i, parent, slot)
    local item = pool[i]
    if item then return item end

    local ctrl = utils.createControl(slot.prefab, 0, 0, 1, 1, nil, parent)
    local art = (slot.art == true) and (ctrl ~= nil)
    if not ctrl then
        -- 素材元件不可用（老存档里没有这几种元件）→ 回退通用矩形元件，并恢复染色
        ctrl = utils.createControl(state.rectPrefabId, 0, 0, 1, 1, nil, parent)
        art = false
        if not ctrl then return nil end
    end

    item = { c = ctrl, art = art }
    pool[i] = item
    return item
end

local function poolTrim(pool, used)
    for i = used + 1, #pool do
        local item = pool[i]
        utils.setVisible(item and item.c, false)
    end
end

-- ================================================================
-- ★ 显式层级：按深度键把世界容器里所有控件重排一遍（由底到顶）
--   ★ 为什么不能靠创建顺序：
--     引擎的同级绘制顺序确实等于「创建顺序」（越晚创建越靠上），但
--       ① 对象池会**复用**控件 —— 树冠、石头顶面这些「同一物体里后画的那一块」
--          在池里换过位置之后，就可能反过来压住先画的那一块（树干盖住树冠）；
--       ② 2.5D 要求「近处一行盖住远处一行」「近处的树挡住后面的小人」——
--          这只能靠显式点名顺序，创建顺序给不出来。
--   ★ 用 SetAsLastSibling 而非 SetSiblingIndex：它的语义在真机与模拟器上一致
--     （移到同级末位 = 显示在最上）；反过来 SetSiblingIndex 在模拟器里方向是反的。
--   ★ 老的编辑器 / 桩里没有这个方法时 pcall 会静默失败 —— 那时退化成「按创建顺序」，
--     不会更糟。
-- ================================================================
local RESTACK_POOLS = {
    { "decoCtrls",    "decoUsed" },
    { "terrainCtrls", "terrainUsed" },
    { "objectCtrls",  "objectUsed" },
    { "treeCtrls",    "treeUsed" },
    { "goalCtrls",    "goalUsed" },
}

function M.restackWorld()
    local list, seq = {}, 0
    for _, pair in ipairs(RESTACK_POOLS) do
        local pool = state[pair[1]]
        local used = state[pair[2]] or 0
        for i = 1, used do
            local item = pool and pool[i]
            if item and item.c then
                seq = seq + 1
                list[#list + 1] = { c = item.c, k = tonumber(item.key) or 999999, s = seq }
            end
        end
    end

    -- 小人（身体 / 头 / 脚下阴影）不在池里，按它**当前所在行**插进物体之间，
    -- 这样「前面的树挡住后面的小人」才会成立。
    local function pushPlayer(ctrl, sub)
        if not ctrl then return end
        seq = seq + 1
        list[#list + 1] = {
            c = ctrl,
            k = depthKey(BAND_OBJ, state.player and state.player.r, sub),
            s = seq,
        }
    end
    pushPlayer(state.playerShadowCtrl, SUB_SHADOW)
    pushPlayer(state.playerCtrl, SUB_PLAYER)
    pushPlayer(state.playerHeadCtrl, SUB_PLAYER + 0.1)

    table.sort(list, function(a, b)
        if a.k ~= b.k then return a.k < b.k end
        return a.s < b.s
    end)
    for _, it in ipairs(list) do
        pcall(function() it.c:SetAsLastSibling() end)
    end
end

-- 池内第 i 个控件：摆成一块矩形
--   hex / alpha 只在**非素材**控件上生效（素材控件的配色交给元件自己）
--   key 是 2.5D 深度键，交给 restackWorld 排序用
local function paint(pool, i, parent, slot, cx, cy, w, h, hex, alpha, key)
    local item = poolGet(pool, i, parent, slot)
    if not item then return i end
    item.key = key
    utils.setVisible(item.c, true)
    utils.setSize(item.c, w, h)
    if not item.art and hex then
        utils.setAlpha(item.c, hex, alpha or 255)
    end
    utils.setPosition(item.c, cx, cy)
    return i + 1
end

-- 探一次：这个槽位在当前存档里**实际**能建成素材控件吗？
--   （素材元件实例化失败会当场回退，所以问池子里的第 1 个控件最准）
local function slotUsesArt(pool, parent, slot)
    if not slot.art then return false end
    local item = poolGet(pool, 1, parent, slot)
    return (item ~= nil) and item.art
end

-- ================================================================
-- ★ 地形层（2.5D 地块）
--   绘制顺序（深度键由小到大）：
--     水面网格线 → 每格的「投影 → 侧面厚度 → 沙滩描边」→ 每格的「草地顶面」
--   ★ 为什么描边要和顶面分两趟画：
--     描边比格子大一圈，如果「一格一格地画（描边+顶面）」，相邻格的描边就会露在
--     岛内部，看起来像铺了带缝的地砖。先铺满所有描边、再统一盖顶面，描边就只在
--     岛的外缘露出一圈 —— 与参考图一致。
--   ★ 为什么侧面能显出来：
--     侧面挂在草地顶面的下沿往下 side 格；近处一行（row 更大）更晚绘制，
--     它的描边+顶面正好盖住远处一行露出来的侧面。岛外是水，没人盖 → 侧面可见。
-- ================================================================
local function buildTerrain(palette)
    local parent = state.containerWorld
    local cell = state.cellSize
    local cols, rows = state.mapCols or 1, state.mapRows or 1
    local v25 = state.view25d and true or false
    local rim = cell * (config.DEFAULT_TILE_RIM_RATIO or 0.17)
    local sideH = cell * (config.DEFAULT_TILE_SIDE_RATIO or 0.30)
    local rect = rectSlot()
    local landSlot = makeSlot(state.landPrefabId)
    local waterSlot = makeSlot(state.waterPrefabId)

    -- ① 海面整屏底（bg 层，跨关卡复用，只在第一次创建）
    --    ★ 水面在参考图里是均匀色块，所以整屏铺一张最稳，也不会出现「棋盘内外接缝」。
    if not state.bgCtrl then
        local bg = utils.createControl(waterSlot.prefab, 0, 0,
            (state.canvasW or 800) + 800, (state.canvasH or 600) + 800, nil, state.containerBg)
        state.bgCtrlArt = (bg ~= nil) and waterSlot.art
        state.bgCtrl = bg
    end
    if state.bgCtrl and not state.bgCtrlArt then
        utils.setAlpha(state.bgCtrl, palette.water, 255)   -- 回退：通用矩形 + 调色板
    end

    -- ② 水面网格
    local di = 1
    if v25 and state.waterGridLines then
        -- 参考图那种细网格线：屏幕水平 / 垂直，且**铺满可见水面**（不只棋盘范围，
        -- 否则会看见网格方形区域的边界，很出戏）。它压在陆地下面，被地块盖住。
        local lw = math.max(1, math.floor(cell * 0.035))
        local alpha = config.DEFAULT_WATER_LINE_ALPHA or 70
        local over = 8                                   -- 向四周多铺的格数
        local left = cellCenterX(1) - cell / 2 - over * cell
        local top = cellCenterY(1) + cell / 2 + over * cell
        local spanX = (cols + over * 2) * cell
        local spanY = (rows + over * 2) * cell
        for c = 0, (cols + over * 2) do
            di = paint(state.decoCtrls, di, parent, rect, left + c * cell, top - spanY / 2,
                       lw, spanY, palette.waterLine, alpha, depthKey(BAND_GRID, 0, 0.1))
        end
        for r = 0, (rows + over * 2) do
            di = paint(state.decoCtrls, di, parent, rect, left + spanX / 2, top - r * cell,
                       spanX, lw, palette.waterLine, alpha, depthKey(BAND_GRID, 0, 0.2))
        end
    else
        -- 旧的水下深色棋盘（view25d / waterGridLines 关掉时的画法）
        local gridAlpha = config.DEFAULT_WATER_GRID_ALPHA or 110
        for r = 1, rows do
            for c = 1, cols do
                if (c % 2 == 1) and (r % 2 == 1) and not world.landAt(c, r) then
                    di = paint(state.decoCtrls, di, parent, rect, cellCenterX(c), cellCenterY(r),
                               cell - 1, cell - 1, palette.waterDeep, gridAlpha,
                               depthKey(BAND_GRID, 0, 0.3))
                end
            end
        end
    end

    -- ③ 陆地：装饰趟（两种模式**完全一样**）→ 顶面趟（素材立绘 或 色块）
    --   ★ 岛缘的轮廓（投影 / 侧面 / 描边）一律由脚本画，不依赖素材 ——
    --     于是「素材路径」与「纯色路径」的岛形逐像素同源，换素材只影响顶面。
    --   ★ 侧面挂在「沙滩描边的下沿」而不是格子下沿：描边是板块顶面的一圈边，
    --     侧面是板块的厚度，两者上下相接才读得出「一块有厚度的地」。
    local landArt = slotUsesArt(state.terrainCtrls, parent, landSlot)
    local shadowAlpha = config.DEFAULT_TILE_SHADOW_ALPHA or 0
    for r = 1, rows do
        for c = 1, cols do
            if world.landAt(c, r) then
                local cx, cy = cellCenterX(c), cellCenterY(r)
                if v25 then
                    -- 岛缘落进水里的投影（贴在侧面下沿，是「浮」在海上那口气）
                    if shadowAlpha > 0 then
                        local sh = sideH * 0.5
                        di = paint(state.decoCtrls, di, parent, rect,
                                   cx, cellBottomY(r) - rim - sideH - sh / 2,
                                   cell + rim * 2 + 4, sh, palette.waterShade, shadowAlpha,
                                   depthKey(BAND_TILE, r, 0.1))
                    end
                    -- 侧面（厚度）：完整露出，不被描边压
                    di = paint(state.decoCtrls, di, parent, rect,
                               cx, cellBottomY(r) - rim - sideH / 2,
                               cell + rim * 2, sideH, palette.soil, 255,
                               depthKey(BAND_TILE, r, 0.2))
                end
                -- 岛缘沙滩描边（放大一圈；岛内会被邻格的顶面盖住）
                local pad = v25 and rim or (config.DEFAULT_COAST_PAD or 5)
                di = paint(state.decoCtrls, di, parent, rect, cx, cy,
                           cell + pad * 2, cell + pad * 2, palette.sand, 255,
                           depthKey(BAND_TILE, r, 0.3))
            end
        end
    end

    -- ④ 草地顶面
    --    素材模式：一格一张立绘（不染色）；顶面在素材里是正方形，正好铺满一格
    --    纯色模式：棋盘式深浅交替（深浅就是玩家数格子的依据）
    local ti = 1
    if landArt then
        local fit = (config.DEFAULT_ART_FIT or {}).land or { w = 1, h = 1, dy = 0 }
        for r = 1, rows do
            for c = 1, cols do
                if world.landAt(c, r) then
                    ti = paint(state.terrainCtrls, ti, parent, landSlot,
                               cellCenterX(c), cellCenterY(r) + (fit.dy or 0) * cell,
                               cell * (fit.w or 1), cell * (fit.h or 1), nil, nil,
                               depthKey(BAND_TOP, r, 0.5))
                end
            end
        end
    else
        for r = 1, rows do
            for c = 1, cols do
                if world.landAt(c, r) then
                    local hex = palette.land
                    if (c + r) % 2 == 0 then hex = palette.landDark end
                    ti = paint(state.terrainCtrls, ti, parent, landSlot,
                               cellCenterX(c), cellCenterY(r), cell, cell, hex, 255,
                               depthKey(BAND_TOP, r, 0.5))
                end
            end
        end
    end

    poolTrim(state.decoCtrls, di - 1)
    state.decoUsed = di - 1
    poolTrim(state.terrainCtrls, ti - 1)
    state.terrainUsed = ti - 1
end

-- ================================================================
-- ★ 物体层：树根 → 木桩 → 立桩 → 石头 → 树木 → 终点旗
--   world 每次发生结构变化后重建（对象池复用，控件不销毁）。
--   2.5D 下所有物体都站在「脚线」（cellFootY）上，并且每个都带一格深度键 ——
--   同一行内由下到上排，跨行则由行号决定谁压谁（见 restackWorld）。
-- ================================================================
function M.rebuildObjects()
    local data = state.levelConfig or {}
    local palette = utils.resolvePalette(data)
    local pool = state.objectCtrls
    local parent = state.containerWorld
    local rect = rectSlot()
    local treeSlot = makeSlot(state.treePrefabId)
    local cell = state.cellSize
    local shadowAlpha = config.DEFAULT_OBJ_SHADOW_ALPHA or 0
    local i = 1

    local function keyOf(r, sub) return depthKey(BAND_OBJ, r, sub) end

    -- 脚下的接触阴影：让物体真的「贴」在草地上，而不是浮着
    local function shadow(cx, footY, w, r)
        if shadowAlpha <= 0 then return end
        i = paint(pool, i, parent, rect, cx, footY - cell * 0.01,
                  w, cell * 0.13, palette.shadowLand, shadowAlpha, keyOf(r, SUB_SHADOW))
    end

    -- ① 树根（半格高，贴地）
    for _, rt in ipairs(state.roots) do
        local bx, foot = cellCenterX(rt.c), cellFootY(rt.r)
        i = paint(pool, i, parent, rect, bx, foot + cell * 0.06,
                  cell * 0.84, cell * 0.12, palette.rootRing, 255, keyOf(rt.r, SUB_ROOT))
        i = paint(pool, i, parent, rect, bx, foot + cell * 0.25,
                  cell * 0.72, cell * 0.34, palette.rootTop, 255, keyOf(rt.r, SUB_ROOT + 0.1))
    end

    -- ② 倒地木桩（横躺两格；顶面高度 = 压陆地 1.0 格 / 浮水 0.0 格）
    for _, lg in ipairs(state.logs) do
        local h = world.logHeight(lg)
        local cx = (cellCenterX(lg.c1) + cellCenterX(lg.c2)) / 2
        local foot = math.min(cellFootY(lg.r1), cellFootY(lg.r2))
        local nr = math.max(lg.r1, lg.r2)          -- 深度键用更靠近镜头的那一行
        local thick = cell * 0.52
        local top = foot + h * cell
        local cy = top - thick / 2
        local len = cell * 2 - cell * 0.12
        shadow(cx, foot, len * 0.94, nr)
        i = paint(pool, i, parent, rect, cx, cy, len, thick, palette.logSide, 255, keyOf(nr, SUB_LOG))
        i = paint(pool, i, parent, rect, cx, cy + thick * 0.26, len, thick * 0.36,
                  palette.logTop, 255, keyOf(nr, SUB_LOG + 0.1))
        -- 两端切口
        i = paint(pool, i, parent, rect, cx - len / 2, cy, cell * 0.09, thick,
                  palette.logEnd, 255, keyOf(nr, SUB_LOG + 0.2))
        i = paint(pool, i, parent, rect, cx + len / 2, cy, cell * 0.09, thick,
                  palette.logEnd, 255, keyOf(nr, SUB_LOG + 0.3))
    end

    -- ③ 立起的木桩（1×1 占地、2 格高）
    for _, st in ipairs(state.stumps) do
        local x, foot = cellCenterX(st.c), cellFootY(st.r)
        shadow(x, foot, cell * 0.8, st.r)
        i = paint(pool, i, parent, rect, x, foot + cell, cell * 0.78, cell * 2,
                  palette.stumpSide, 255, keyOf(st.r, SUB_STUMP))
        i = paint(pool, i, parent, rect, x, foot + cell * 1.88, cell * 0.86, cell * 0.24,
                  palette.stumpTop, 255, keyOf(st.r, SUB_STUMP + 0.1))
    end

    -- ④ 石头（1 格 / 2 格高，不可移动、不可攀爬）
    for _, rk in ipairs(state.rocks) do
        local hh = tonumber(rk.h) or 1
        local x, foot = cellCenterX(rk.c), cellFootY(rk.r)
        local hex = palette.rock1Top
        if hh >= 2 then hex = palette.rock2Top end
        shadow(x, foot, cell * 0.8, rk.r)
        i = paint(pool, i, parent, rect, x, foot + hh * cell / 2, cell * 0.86, hh * cell,
                  palette.rockSide, 255, keyOf(rk.r, SUB_ROCK))
        i = paint(pool, i, parent, rect, x, foot + hh * cell - cell * 0.11,
                  cell * 0.70, cell * 0.22, hex, 255, keyOf(rk.r, SUB_ROCK + 0.1))
    end

    -- ⑤ 树木（2.5 格高）
    --    素材模式：一张立绘（内容 1 格宽 × 2.5 格高），不染色，脚踩在顶面上
    --    回退模式：树干 + 树冠两块纯色矩形
    local treeArt = slotUsesArt(state.treeCtrls, parent, treeSlot)
    local ti = 1
    for _, tr in ipairs(state.trees) do
        local x, foot = cellCenterX(tr.c), cellFootY(tr.r)
        shadow(x, foot, cell * 0.72, tr.r)
        if treeArt then
            local fit = (config.DEFAULT_ART_FIT or {}).tree or { w = 1, h = 2.5, dy = 0 }
            ti = paint(state.treeCtrls, ti, parent, treeSlot,
                       x, foot + (fit.dy or 0) * cell,
                       cell * (fit.w or 1), cell * (fit.h or 1), nil, nil, keyOf(tr.r, SUB_TREE))
        else
            ti = paint(state.treeCtrls, ti, parent, treeSlot, x, foot + cell * 1.10,
                       cell * 0.30, cell * 2.20, palette.treeTrunk, 255, keyOf(tr.r, SUB_TREE))
            ti = paint(state.treeCtrls, ti, parent, treeSlot, x, foot + cell * 2.02,
                       cell * 0.96, cell * 1.05, palette.treeCanopy, 255, keyOf(tr.r, SUB_TREE + 0.1))
        end
    end
    poolTrim(state.treeCtrls, ti - 1)
    state.treeUsed = ti - 1

    -- ⑥ 终点旗（单独一个池：同格内它必须压在木桩 / 石头 / 树木之上）
    local gi = 1
    local gx, gfoot = cellCenterX(state.goal.c), cellFootY(state.goal.r)
    gi = paint(state.goalCtrls, gi, parent, rect, gx, gfoot + cell * 0.12,
               cell * 1.02, cell * 0.24, palette.goalFlag, 90, keyOf(state.goal.r, SUB_GOAL))
    gi = paint(state.goalCtrls, gi, parent, rect, gx - cell * 0.24, gfoot + cell * 1.05,
               cell * 0.11, cell * 2.10, palette.goalPole, 255, keyOf(state.goal.r, SUB_GOAL + 0.1))
    gi = paint(state.goalCtrls, gi, parent, rect, gx + cell * 0.08, gfoot + cell * 1.72,
               cell * 0.66, cell * 0.52, palette.goalFlag, 255, keyOf(state.goal.r, SUB_GOAL + 0.2))
    poolTrim(state.goalCtrls, gi - 1)
    state.goalUsed = gi - 1

    poolTrim(pool, i - 1)
    state.objectUsed = i - 1

    -- ⑦ 全局重排：地块 → 物体 → 小人，全部按深度键点名顺序
    M.restackWorld()
end

-- ================================================================
-- ★ 小人
--   素材模式：一张人物立绘（内容 1 格宽 × 2 格高），不染色
--   回退模式：身体 + 头两块纯色矩形（头是深色块，小尺寸下也能认出朝向）
--   两种模式都配一块脚下滑影（就是那一点点接触阴影，站在方块上才不飘）
--   ★ 控件跨关卡复用（形态在建出来的那一刻定死），否则连按 R 会留下一层层残影。
-- ================================================================
local function buildPlayer(palette)
    local cell = state.cellSize
    local slot = makeSlot(state.playerPrefabId)

    if not state.playerCtrl then
        local ctrl = utils.createControl(slot.prefab, 0, 0, 1, 1, nil, state.containerWorld)
        state.playerCtrlArt = (ctrl ~= nil) and slot.art
        if not ctrl then
            ctrl = utils.createControl(state.rectPrefabId, 0, 0, 1, 1, nil, state.containerWorld)
            state.playerCtrlArt = false
        end
        state.playerCtrl = ctrl
    end
    if not state.playerCtrl then return end

    -- 脚下滑影（只是个很淡的深色块，紧贴脚线）
    if not state.playerShadowCtrl then
        state.playerShadowCtrl = utils.createControl(
            state.rectPrefabId, 0, 0, cell * 0.7, cell * 0.16, nil, state.containerWorld)
    end
    local shadowAlpha = config.DEFAULT_OBJ_SHADOW_ALPHA or 0
    utils.setSize(state.playerShadowCtrl, cell * 0.70, cell * 0.13)
    if shadowAlpha > 0 then
        utils.setAlpha(state.playerShadowCtrl, palette.shadowLand, shadowAlpha)
        utils.setVisible(state.playerShadowCtrl, true)
    else
        utils.setVisible(state.playerShadowCtrl, false)
    end

    if state.playerCtrlArt then
        local fit = (config.DEFAULT_ART_FIT or {}).player or { w = 1, h = 2, dy = 1 }
        state.playerBodyH = cell * (fit.h or 2.0)      -- 控件的实际高度（锚点换算用得到）
        utils.setSize(state.playerCtrl, cell * (fit.w or 1), cell * (fit.h or 2))
        utils.setVisible(state.playerCtrl, true)
        utils.setVisible(state.playerHeadCtrl, false)   -- 立绘自带头部，不需要额外色块
    else
        state.playerBodyH = cell * 1.88
        utils.setSize(state.playerCtrl, cell * 0.62, state.playerBodyH)
        utils.setAlpha(state.playerCtrl, palette.playerBody, 255)
        utils.setVisible(state.playerCtrl, true)
        if not state.playerHeadCtrl then
            state.playerHeadCtrl = utils.createControl(
                state.rectPrefabId, 0, 0, cell * 0.50, cell * 0.34, nil, state.containerWorld)
        end
        utils.setSize(state.playerHeadCtrl, cell * 0.50, cell * 0.34)
        utils.setAlpha(state.playerHeadCtrl, palette.playerHead, 255)
        utils.setVisible(state.playerHeadCtrl, true)
    end

    state.playerVisX = 0
    state.playerVisY = 0
    state.playerAnimT = 0
    state.playerAnimDur = 0
    M.syncPlayerNow()      -- 立刻吸附到出生格，别让第一帧从 (0,0) 滑进来
    M.restackWorld()       -- 首帧就要有正确的遮挡关系
end

-- ================================================================
-- ★ 涟漪特效控件（常驻隐藏，跨关卡复用）
-- ================================================================
local function buildRipple(palette)
    if not state.rippleCtrl then
        state.rippleCtrl = utils.createControl(
            state.rectPrefabId, 0, 0,
            config.DEFAULT_RIPPLE_SIZE or 70, config.DEFAULT_RIPPLE_SIZE or 70,
            utils.hexToColorA(palette.ripple or "FFFFFF", 0), state.containerFx)
    end
    state.rippleActive = false
    state.rippleT = 0
    utils.setVisible(state.rippleCtrl, false)
end

-- ================================================================
-- ★ 清空上一关（控件全部隐藏，池保留复用）
--   海面底（bgCtrl）跨关卡复用，不在这里处理。
-- ================================================================
function M.clear()
    poolTrim(state.terrainCtrls, 0)
    poolTrim(state.decoCtrls, 0)
    poolTrim(state.objectCtrls, 0)
    poolTrim(state.treeCtrls, 0)
    poolTrim(state.goalCtrls, 0)
    utils.setVisible(state.playerCtrl, false)
    utils.setVisible(state.playerHeadCtrl, false)
    utils.setVisible(state.playerShadowCtrl, false)
    utils.setVisible(state.rippleCtrl, false)
    state.terrainUsed = 0
    state.decoUsed = 0
    state.objectUsed = 0
    state.treeUsed = 0
    state.goalUsed = 0
    state.rippleActive = false
end

-- ================================================================
-- ★ 构建一关
-- ================================================================
function M.build(data)
    if not data then return false end
    if not world.load(data) then return false end

    M.computeGeometry()
    local palette = utils.resolvePalette(data)

    M.clear()                 -- 先把上一关的可见控件收起来（池子保留复用）
    buildTerrain(palette)
    M.rebuildObjects()
    buildPlayer(palette)
    buildRipple(palette)
    M.updateHudDisplay()
    return state.playerCtrl ~= nil
end

-- ================================================================
-- ★ 小人的视觉位置：立刻同步到当前格（关卡重建 / 重开时用）
-- ================================================================
function M.syncPlayerNow()
    local px, py = playerAnchor()
    state.playerVisX = px
    state.playerVisY = py
    state.playerAnimFromX = px
    state.playerAnimFromY = py
    state.playerAnimT = 0
    state.playerAnimDur = 0
    utils.setPosition(state.playerCtrl, px, py)
    utils.setPosition(state.playerShadowCtrl, px, py - playerFootOffset() - (state.cellSize or 1) * 0.01)
    local cell = state.cellSize or 1
    local bodyH = state.playerBodyH
    if not bodyH or bodyH <= 0 then bodyH = cell * 1.88 end
    utils.setPosition(state.playerHeadCtrl, px, py + bodyH * 0.5 - cell * 0.20)
end

-- ================================================================
-- ★ 开始一次位移动画（从当前位置走向新位置）
--   ★ 顺手重排一次世界：小人换行之后，「前面的树挡不挡得住它」会变。
-- ================================================================
function M.beginPlayerMove(duration)
    state.playerAnimFromX = state.playerVisX
    state.playerAnimFromY = state.playerVisY
    state.playerAnimT = 0
    state.playerAnimDur = math.max(0.001, tonumber(duration) or config.DEFAULT_STEP_ANIM_TIME or 0.1)
    M.restackWorld()
end

-- ================================================================
-- ★ 每帧推进：小人位移补间 + 涟漪特效
-- ================================================================
function M.updateVisuals(dt)
    local cell = state.cellSize or 1
    local bodyH = state.playerBodyH
    if not bodyH or bodyH <= 0 then bodyH = cell * 1.88 end

    -- ① 小人
    local tx, ty = playerAnchor()
    if state.playerAnimT < state.playerAnimDur then
        state.playerAnimT = state.playerAnimT + (dt or 0)
        local k = utils.smoothstep(utils.clamp(state.playerAnimT / state.playerAnimDur, 0, 1))
        state.playerVisX = utils.lerp(state.playerAnimFromX, tx, k)
        state.playerVisY = utils.lerp(state.playerAnimFromY, ty, k)
    else
        state.playerVisX = tx
        state.playerVisY = ty
    end
    utils.setPosition(state.playerCtrl, state.playerVisX, state.playerVisY)
    utils.setPosition(state.playerShadowCtrl, state.playerVisX,
                      state.playerVisY - playerFootOffset() - cell * 0.01)
    utils.setPosition(state.playerHeadCtrl, state.playerVisX, state.playerVisY + bodyH * 0.5 - cell * 0.20)

    -- ② 涟漪
    if state.rippleActive and state.rippleCtrl then
        local dur = state.rippleDur or config.DEFAULT_RIPPLE_TIME or 0.45
        state.rippleT = state.rippleT + (dt or 0)
        local k = utils.clamp(state.rippleT / dur, 0, 1)
        local base = config.DEFAULT_RIPPLE_SIZE or 70
        local size = base * (1 + 0.9 * k)
        local data = state.levelConfig or {}
        local palette = utils.resolvePalette(data)
        local hex = palette.ripple or "FFFFFF"
        utils.setSize(state.rippleCtrl, size, size * 0.42)
        utils.setAlpha(state.rippleCtrl, hex, math.floor((config.DEFAULT_FX_ALPHA or 170) * (1 - k)))
        if k >= 1 then
            state.rippleActive = false
            utils.setVisible(state.rippleCtrl, false)
        end
    end
end

-- ================================================================
-- ★ 在某格脚下放一圈涟漪（动作反馈）
-- ================================================================
function M.spawnRipple(c, r)
    if not state.rippleCtrl then return end
    local data = state.levelConfig or {}
    local palette = utils.resolvePalette(data)
    state.rippleX = cellCenterX(c)
    state.rippleY = cellFootY(r) + (state.cellSize or 1) * 0.10
    state.rippleT = 0
    state.rippleDur = config.DEFAULT_RIPPLE_TIME or 0.45
    state.rippleActive = true
    local base = config.DEFAULT_RIPPLE_SIZE or 70
    utils.setSize(state.rippleCtrl, base, base * 0.42)
    utils.setAlpha(state.rippleCtrl, palette.ripple or "FFFFFF", config.DEFAULT_FX_ALPHA or 170)
    utils.setPosition(state.rippleCtrl, state.rippleX, state.rippleY)
    utils.setVisible(state.rippleCtrl, true)
end

-- ================================================================
-- ★ 按「UTF-8 字符数」折行
--   ★ 不依赖 utf8 库（沙箱里不一定有）：靠首字节判断字符长度，
--     绝不会把一个汉字 / emoji 从中间切开。
-- ================================================================
local function charBytes(b)
    if b < 0x80 then return 1 end
    if b < 0xE0 then return 2 end
    if b < 0xF0 then return 3 end
    return 4
end

local function wrapByChars(s, width)
    local text = tostring(s or "")
    local w = tonumber(width) or 0
    if w <= 0 or #text == 0 then return text end
    local out, line, count = {}, {}, 0
    local i = 1
    while i <= #text do
        local b = text:byte(i)
        local n = charBytes(b or 0)
        -- 保护：截断处若落在半个字符上，直接收尾
        if i + n - 1 > #text then n = #text - i + 1 end
        local ch = text:sub(i, i + n - 1)
        if ch == "\n" then
            out[#out + 1] = table.concat(line)
            line, count = {}, 0
        else
            line[#line + 1] = ch
            count = count + 1
            if count >= w then
                out[#out + 1] = table.concat(line)
                line, count = {}, 0
            end
        end
        i = i + n
    end
    if #line > 0 then out[#out + 1] = table.concat(line) end
    return table.concat(out, "\n")
end

-- ================================================================
-- ★ HUD 文本刷新（关卡名 / 步数 / 状态）
-- ================================================================
function M.updateHudDisplay()
    local data = state.levelConfig or {}
    local palette = utils.resolvePalette(data)
    local alpha = config.DEFAULT_HUD_TEXT_ALPHA or 255
    utils.setText(state.hudTitle, data.name or "浮岛借木")
    -- ★ 禁用缺字形的符号（✓ ▶ 等）：雅黑/宋体/黑体里没有，会渲染成豆腐块
    local info = string.format("步数 %d", state.steps or 0)
    if state.won then info = info .. "   （已通关）" end
    utils.setText(state.hudInfo, info)
    utils.setTextColor(state.hudTitle, palette.hud, alpha)
    utils.setTextColor(state.hudInfo, palette.hud, alpha)
    utils.setTextColor(state.hudHint, palette.hint, alpha)
    -- 提示文本按 F 开关；每条按 DEFAULT_HINT_WRAP 字符数折行，多条各占一行
    local hintLines = data.hints or {}
    local parts = {}
    for _, line in ipairs(hintLines) do
        parts[#parts + 1] = wrapByChars(line, config.DEFAULT_HINT_WRAP)
    end
    utils.setText(state.hudHint, state.hintsOn and table.concat(parts, "\n") or "")
    utils.setVisible(state.hudHint, state.hintsOn and #hintLines > 0)
end

return M
