-- ================================================================
-- 瓦雷莎的果园救急 · 果园地图选关（横向长图 · 可拖拽）
-- ================================================================
-- 视觉参考「开心消消乐」的关卡地图，改成横着的长卷：
--   · 50 片果园沿一条蜿蜒土路从左往右排开，果实即关卡节点；
--   · 青苹果 = 已解锁待挑战，红苹果 = 已还原（熟了），灰绿暗果 = 未解锁；
--   · 当前节点套金圈，吉祥物「小果龙」站在上面待命（会呼吸、上下浮、轻晃）。
-- 交互：
--   · 在地图区按住拖动 → 长图跟手；松手按惯性滑一段，再吸附到最近的果园；
--   · 左右箭头 / ← → 键 → 换一片果园并把长图平移过去；
--   · 点果实 / 空格 / 「进入果园」→ 进入该关（未解锁只会选中，不进入）。
--
-- ★ 层级（只用 containerMap 一个容器）：
--     [地图拖动命中区] → [mapWorld 长图（土路石子 → 装饰 → 果园节点 → 吉祥物）]
--     → [顶部标题 / 进度条 / 底部按钮]
--   mapWorld 整条长图靠 SetAnchoredPosition 平移，一帧只需一次调用。
-- ★ 所有纯装饰控件都 utils.noRay()：装吃点击会把拖拽吞掉。
-- ★ 关于「点哪个果园」：真机上节点自带的命中区在最上面，直接用；
--   若某个引擎把整块拖动区判在上面，则退化为「按坐标找最近的节点」——
--   坐标约定用三种候选自动校准（state.mapPointerMap），不写死。
-- ================================================================

---@diagnostic disable: undefined-global

local M = {}
local state = require("default_import_file/state")
local config = require("default_import_file/config")
local utils = require("default_import_file/utils")
local fx = require("default_import_file/fx")
local audio = require("default_import_file/audio")
local mascot = require("default_import_file/mascot")

-- 由 game.lua 注入：{ onEnter = f(idx), onTutorial = f() }
M.actions = {}

local TAG = "map"

-- ★ 底部提示条常年只显示这一句「操作方法」。
--   以前点未解锁的果园会把它改成「这片果园还锁着 —— 先把前面的果园还原了」，
--   改完却不还原 —— 玩家之后再进来，操作方法就被那句红字永久顶掉了。
--   现在：任何刷新都把文案写回本常量，操作方法始终在。
local MAP_HINT = "拖动地图 · 点果实进入 · ← → 换果园 · 空格开始 · H 教程"

-- ★ 序章读完后的气泡文案（≤ 7 字：气泡宽 186 只够放 7 个 16 号汉字）
local ENTER_HINT = "点这里开始救援"

-- ================================================================
-- 布局
-- ================================================================
local function geom()
    local cw = state.canvasW or config.DEFAULT_VIEW_WIDTH or 800
    local ch = state.canvasH or config.DEFAULT_VIEW_HEIGHT or 600
    local k = math.min(cw / (config.DEFAULT_VIEW_WIDTH or 800), ch / (config.DEFAULT_VIEW_HEIGHT or 600))
    k = utils.clamp(k, 0.85, 2.2)

    local topReserve = ch * (config.DEFAULT_MAP_TOP_RATIO or 0.22)
    local bottomReserve = ch * (config.DEFAULT_MAP_BOTTOM_RATIO or 0.20)
    local topEdge = ch / 2 - topReserve
    local bottomEdge = -ch / 2 + bottomReserve

    -- ★ 地平线（和 scene 模块同一套算法）：装饰必须「种」在这条线以下，
    --   否则就是飘在天上的树（900p 下特别明显）。
    local groundTop = -ch / 2 + (config.DEFAULT_SCENE_GROUND_H or 310) * 0.88

    local n = math.max(1, config.getLevelCount())
    local spacing = (config.DEFAULT_MAP_NODE_SPACING or 196) * k
    local edgePad = (config.DEFAULT_MAP_EDGE_PAD or 300) * k
    local amp = (config.DEFAULT_MAP_WAVE_AMP or 62) * k
    local phase = config.DEFAULT_MAP_WAVE_PHASE or 0.62
    -- 装饰可落的范围：上不顶到果园节点，下不压到底部按钮
    local fieldTop = math.min(groundTop + 30 * k, (topEdge + bottomEdge) / 2 - amp - 16 * k)
    local fieldBottom = math.max(groundTop - 96 * k, -ch / 2 + 150 * k)
    local worldW = edgePad * 2 + (n - 1) * spacing
    -- ★ 滚动上限要允许「第一片 / 最后一片果园停在正中」：
    --   只按 worldW/2 - cw/2 算的话，第 1 关永远偏左半屏，左边一大片空天。
    local maxScroll = math.max(0, worldW / 2 - cw / 2 + 30 * k, worldW / 2 - edgePad)

    return {
        cw = cw, ch = ch, k = k, n = n,
        topReserve = topReserve, bottomReserve = bottomReserve,
        groundTop = groundTop, fieldTop = fieldTop, fieldBottom = fieldBottom,
        topEdge = topReserve and topEdge or 0, bottomEdge = bottomEdge,
        bandCY = (topEdge + bottomEdge) / 2,
        bandH = topEdge - bottomEdge,
        spacing = spacing, edgePad = edgePad, amp = amp, phase = phase,
        worldW = worldW, maxScroll = maxScroll,
        nodeSize = (config.DEFAULT_MAP_NODE_SIZE or 66) * k,
        nodeInner = (config.DEFAULT_MAP_NODE_INNER or 52) * k,
        nodeHit = (config.DEFAULT_MAP_NODE_HIT or 92) * k,
        ringSize = (config.DEFAULT_MAP_CURSOR_RING or 98) * k,
    }
end

local function nodeX(G, i)
    return -G.worldW / 2 + G.edgePad + (i - 1) * G.spacing
end

local function nodeY(G, i)
    return G.bandCY + G.amp * math.sin((i - 1) * G.phase)
        + G.amp * 0.18 * math.sin((i - 1) * 0.23 + 1.1)
end

local function clampScroll(v)
    local G = geom()
    return utils.clamp(v, -G.maxScroll, G.maxScroll)
end

local function scrollOfLevel(i)
    local G = geom()
    if not state.mapNodeX[i] then return 0 end
    return utils.clamp(-state.mapNodeX[i], -G.maxScroll, G.maxScroll)
end

local function nearestIndexForScroll(scroll)
    local G = geom()
    local best, bestD = 1, math.huge
    for i = 1, G.n do
        local d = math.abs(scroll + (state.mapNodeX[i] or 0))
        if d < bestD then best, bestD = i, d end
    end
    return best
end

-- ================================================================
-- ★ 拖动地图的音效（用户要求「拖动地图时也加上音效」）
--   两处发声：① 真的开始拖（越过点击阈值）时一声；② 拖过一片果园时一声。
--   用最小间隔节流（DEFAULT_MAP_DRAG_SOUND_GAP），否则快速滑动会连成机关枪。
--   ★ 只是轻点（没越过阈值）不出拖动音 —— 那种情况走 tap，由 playClick 负责。
-- ================================================================
local dragSndT = -99          -- 上次发声时刻（state.fxTime）
local dragSndIdx = nil        -- 上次发声时离得最近的果园序号
local dragSndArmed = false    -- 按下过、还没真正拖动

local function playDragTick(force)
    local now = state.fxTime or 0
    local gap = config.DEFAULT_MAP_DRAG_SOUND_GAP or 0.09
    if not force and (now - dragSndT) < gap then return end
    dragSndT = now
    audio.playDrag()
end

local function armDragSound()
    dragSndArmed = true
    dragSndIdx = nil
end

-- ================================================================
-- 进度 / 解锁
-- ================================================================
local function clearedCount()
    local n = 0
    for i = 1, config.getLevelCount() do
        if state.clearedLevels[i] then n = n + 1 end
    end
    return n
end

local function recomputeUnlock()
    local total = math.max(1, config.getLevelCount())
    local maxCleared = 0
    for i = 1, total do
        if state.clearedLevels[i] and i > maxCleared then maxCleared = i end
    end
    local ahead = math.max(1, math.floor(config.DEFAULT_MAP_LOCK_AHEAD or 1))
    -- ★ 解锁上限三路取最大：
    --   ① 本地通关推出来的「最大通关号 + ahead」（过关那一刻立刻解锁下一片）；
    --   ② 服务器存档给的上限（「服客同步存档信息」按「已通关最新 + ahead」算，跨会话的唯一真相）；
    --   ③ 保底 1（一开始只有第 1 片可进）。
    local fromSave = math.floor(tonumber(state.mapUnlockHint) or 0)
    state.mapUnlockMax = math.min(total, math.max(1, maxCleared + ahead, fromSave))
    -- ★ 教程关（前 5 片）也要逐关解锁：以前这里硬抬到 5，等于一开局全都能进，已删除。
end

local function isUnlocked(i)
    return i <= (state.mapUnlockMax or 1) or state.clearedLevels[i] == true
end

-- ================================================================
-- 节点配色
-- ================================================================
-- ★ 颜色语义（用户要求）：
--   已通关          → 【红】苹果（熟了）+ 三颗亮金星；
--   已解锁 · 未通关  → 【青翠绿】苹果（还能进去摘）+ 三颗暗金星；
--   未解锁          → 灰绿暗果 + 三颗黑星；
--   光标选中        → 在以上基础上提亮（只在「已解锁」的节点上生效）。
local function nodeColors(i)
    local pal = utils.palette()
    local cleared = state.clearedLevels[i] == true
    local unlocked = isUnlocked(i)
    local cursor = (state.mapCursor == i)
    local base, inner, label, starA
    if cleared then
        base = pal.fruit
        inner = utils.mixHex(pal.fruit, "FFFFFF", 0.34)
        label = pal.accentText
        starA = 255
    elseif unlocked then
        base = utils.mixHex(pal.ok, pal.gold, 0.10)
        inner = utils.mixHex(pal.ok, "FFFFFF", 0.34)
        label = pal.accentText
        starA = 0
    else
        base = utils.mixHex(pal.locked, pal.shadow, 0.16)
        inner = utils.mixHex(pal.lockedDeep, pal.shadow, 0.16)
        label = utils.mixHex(pal.dim, "FFFFFF", 0.25)
        starA = 0
    end
    -- ★ 光标高亮只作用于「已解锁」的节点：未解锁的节点必须保持暗淡，
    --   否则划到 10 号时它被提亮，看着像「可以进」（用户要求：未解锁 = 暗淡）。
    --   未解锁节点的「当前选中」只靠外面的金圈表达。
    --   ★ 提亮用「同色加白」而不是橙红：橙红一染会和「已通关的红苹果」撞色。
    if cursor and unlocked and not cleared then
        base = utils.mixHex(base, "FFFFFF", 0.24)
        inner = utils.mixHex(base, "FFFFFF", 0.42)
    end
    return base, inner, label, starA, cleared, unlocked, cursor
end

-- ================================================================
-- 造控件的小包装
-- ================================================================
local function rect(par, x, y, w, h, hex, alpha)
    local c = utils.createControl(state.rectPrefabId, x, y, w, h,
        utils.hexToColorA(hex, alpha or 255), par)
    if c then
        utils.noRay(c)
        utils.raise(c)
    end
    return c
end

local function label(par, x, y, w, h, text, hex, size, align)
    local c = utils.createText(x, y, w, h, text, utils.hexToColor(hex), size, par, align)
    if c then utils.raise(c) end
    return c
end

-- ================================================================
-- 长图：土路石子
-- ================================================================
local function buildPath(G)
    local step = (config.DEFAULT_MAP_DOT_STEP or 88) * G.k
    local dotS = (config.DEFAULT_MAP_DOT_SIZE or 10) * G.k
    local pal = utils.palette()
    state.mapDots = {}
    for i = 1, G.n - 1 do
        local x0, y0 = nodeX(G, i), nodeY(G, i)
        local x1, y1 = nodeX(G, i + 1), nodeY(G, i + 1)
        local dx, dy = x1 - x0, y1 - y0
        local len = math.sqrt(dx * dx + dy * dy)
        local cnt = math.max(1, math.floor(len / step))
        for j = 1, cnt do
            local t = j / (cnt + 1)
            local c = rect(state.mapWorld, x0 + dx * t, y0 + dy * t, dotS, dotS,
                (j % 2 == 0) and pal.sand or pal.soil, 210)
            if c then
                utils.setRotationZ(c, 45)
                state.mapDots[#state.mapDots + 1] = { ctrl = c, x = x0 + dx * t, y = y0 + dy * t, s = dotS }
            end
        end
    end
end

-- ================================================================
-- 长图：装饰（果树 / 灌木 / 小花 / 果串）
--   ★ 形状一律用圆形模板拼（宽高不等就是椭圆）：方块拼的树太像积木。
--   ★ y 传的是「根部接地点」，树冠一律往上长 —— 这样树才种在地上，
--     不会飘到天上（早期版本按 bandCY ± bandH*0.4 撒，900p 下全在半空）。
--   ★ 越靠近屏幕下沿的东西越大：远小近大，透视才站得住。
-- ================================================================
local seed = 987654321
local function rnd()
    seed = (seed * 1103515245 + 12345) % 2147483648
    return seed / 2147483648
end

local function buildDecos(G)
    local pal = utils.palette()
    state.mapDecos = {}

    -- 一颗苹果：圆果身 + 高光 + 小把 + 叶
    local function apple(par, x, y, s, hex)
        hex = hex or pal.fruit
        utils.circleC(x, y, s, s * 0.94, hex, 250, par)
        utils.circleC(x - s * 0.24, y + s * 0.18, s * 0.32, s * 0.24,
            utils.mixHex(hex, "FFFFFF", 0.48), 205, par)
        rect(par, x + s * 0.02, y + s * 0.50, s * 0.10, s * 0.26, pal.wood, 240)
        utils.circleC(x + s * 0.26, y + s * 0.60, s * 0.36, s * 0.17, pal.leaf, 240, par)
    end

    local function placeTree(x, y, s)
        local holder = utils.createContainer(state.mapWorld)
        if not holder then return end
        utils.raise(holder)
        utils.setPos(holder, x, y)
        -- 根部投影
        utils.circleC(0, s * 0.04, s * 0.74, s * 0.17, pal.shadow, 60, holder)
        -- 树干
        rect(holder, 0, s * 0.34, s * 0.13, s * 0.68, pal.wood, 240)
        -- 树冠：三个圆叠出蓬松轮廓（最上面那颗最亮）
        utils.circleC(-s * 0.26, s * 0.52, s * 0.62, s * 0.58, pal.leaf, 240, holder)
        utils.circleC(s * 0.27, s * 0.47, s * 0.56, s * 0.52,
            utils.mixHex(pal.leaf, "FFFFFF", 0.10), 240, holder)
        utils.circleC(0, s * 0.72, s * 0.80, s * 0.72, pal.leaf, 245, holder)
        utils.circleC(-s * 0.17, s * 0.90, s * 0.36, s * 0.26,
            utils.mixHex(pal.leaf, "FFFFFF", 0.32), 215, holder)
        -- 树上只挂苹果（早期版本还挂过葡萄串，看着太怪）
        apple(holder, -s * 0.24, s * 0.56, s * 0.30, pal.fruit)
        -- 每棵树第二颗果换着颜色：橙汁 / 青梨，果园才不会一片红
        apple(holder, s * 0.26, s * 0.40, s * 0.25, (rnd() < 0.5) and pal.juice or pal.pear)
        if rnd() < 0.45 then apple(holder, s * 0.02, s * 0.76, s * 0.22, pal.fruit) end
        state.mapDecos[#state.mapDecos + 1] = { ctrl = holder, kind = "tree", phase = rnd() * 6.28, s = s }
    end

    local function placeBush(x, y, s)
        local holder = utils.createContainer(state.mapWorld)
        if not holder then return end
        utils.raise(holder)
        utils.setPos(holder, x, y)
        utils.circleC(0, s * 0.02, s * 0.80, s * 0.16, pal.shadow, 55, holder)
        utils.circleC(-s * 0.24, s * 0.18, s * 0.62, s * 0.44, pal.leaf, 235, holder)
        utils.circleC(s * 0.23, s * 0.15, s * 0.56, s * 0.40,
            utils.mixHex(pal.leaf, "FFFFFF", 0.13), 235, holder)
        utils.circleC(0, s * 0.30, s * 0.54, s * 0.43, pal.leaf, 240, holder)
        utils.circleC(s * 0.12, s * 0.41, s * 0.28, s * 0.19,
            utils.mixHex(pal.leaf, "FFFFFF", 0.30), 210, holder)
        state.mapDecos[#state.mapDecos + 1] = { ctrl = holder, kind = "bush", phase = rnd() * 6.28, s = s }
    end

    local function placeFlower(x, y, s)
        local holder = utils.createContainer(state.mapWorld)
        if not holder then return end
        utils.raise(holder)
        utils.setPos(holder, x, y)
        rect(holder, 0, s * 0.48, s * 0.10, s * 0.90, pal.leaf, 235)
        local petal = (rnd() < 0.5) and pal.star or utils.mixHex(pal.fruit, "FFFFFF", 0.38)
        for i = 1, 5 do
            local a = math.rad((i - 1) * 72 + 16)
            local rr = s * 0.44
            utils.circleC(math.cos(a) * rr, s * 1.06 + math.sin(a) * rr,
                s * 0.48, s * 0.48, petal, 240, holder)
        end
        utils.circleC(0, s * 1.06, s * 0.42, s * 0.42, pal.accent, 245, holder)
        state.mapDecos[#state.mapDecos + 1] = { ctrl = holder, kind = "flower", phase = rnd() * 6.28, s = s }
    end

    -- 风车：叶片用三角形模板，装进一个会自转的小容器
    local function placeWindmill(x, y, s)
        local holder = utils.createContainer(state.mapWorld)
        if not holder then return end
        utils.raise(holder)
        utils.setPos(holder, x, y)
        utils.circleC(0, s * 0.03, s * 0.62, s * 0.16, pal.shadow, 55, holder)
        rect(holder, 0, s * 0.30, s * 0.10, s * 0.62, pal.wood, 240)
        local head = utils.createContainer(holder)
        if head then
            utils.raise(head)
            utils.setPos(head, 0, s * 0.70)
            -- ★ 四片三角要「斜着搭在轴上」才像风车：尖端朝外、再斜 32°、并沿切向错开。
            --   直接 a-90 摆正会拼成一颗四角星（踩过）；白+金也太淡，改成红+金。
            for i = 1, 4 do
                local a = (i - 1) * 90
                local ar = math.rad(a)
                local rr = s * 0.24
                local bx = math.cos(ar) * rr - math.sin(ar) * s * 0.07
                local by = math.sin(ar) * rr + math.cos(ar) * s * 0.07
                local blade = utils.triangleC(bx, by, s * 0.30, s * 0.46,
                    (i % 2 == 0) and pal.fruit or pal.star, 245, head)
                if blade then
                    utils.noRay(blade)
                    utils.setRotationZ(blade, a - 58)
                end
            end
            utils.circleC(0, 0, s * 0.15, s * 0.15, pal.cream, 255, head)
            utils.circleC(0, 0, s * 0.07, s * 0.07, pal.wood, 255, head)
        end
        state.mapDecos[#state.mapDecos + 1] = {
            ctrl = holder, head = head, kind = "windmill",
            phase = rnd() * 6.28, spin = 95 + rnd() * 85, s = s,
        }
    end

    -- 小草丛：三片三角形叶子，每片按同一阵风摆
    local function placeGrassTuft(x, y, s)
        local holder = utils.createContainer(state.mapWorld)
        if not holder then return end
        utils.raise(holder)
        utils.setPos(holder, x, y)
        -- 根部一小块投影，草才不是「浮在田上」
        utils.circleC(0, s * 0.04, s * 0.56, s * 0.15, pal.shadow, 40, holder)
        local blades = {}
        for i = 1, 5 do
            local b = utils.triangleC((i - 3) * s * 0.21, s * 0.16, s * 0.22, s * 0.92,
                (i % 2 == 0) and utils.mixHex(pal.leaf, "FFFFFF", 0.26) or pal.leaf, 240, holder)
            if b then utils.noRay(b) end
            blades[#blades + 1] = b
        end
        state.mapDecos[#state.mapDecos + 1] = {
            ctrl = holder, blades = blades, kind = "grass", phase = rnd() * 6.28, s = s,
        }
    end

    -- ★ x 落在两片果园之间（不挡节点）；y 按 t 在田里插值，越靠下越大
    -- ★ i 必须从 1 开始等比铺满整张长图，不能写 i + 5 之类的偏移：
    --   一偏移，前几个缺口就没有装饰，而可视窗口恰好停在第 1 片果园附近 →
    --   风车/小草一个都看不见（踩过）。要错开各类装饰，用 phase 挪小数部分。
    local function decoX(i, total, phase)
        local f = ((i - 1) + (phase or 0)) / math.max(1, total)
        local gapIdx = math.floor(f * (G.n - 1)) + 1
        if gapIdx < 1 then gapIdx = 1 end
        if gapIdx > G.n - 1 then gapIdx = G.n - 1 end
        local gx = (nodeX(G, gapIdx) + nodeX(G, gapIdx + 1)) * 0.5
        return gx + (rnd() - 0.5) * G.spacing * 0.46, gapIdx
    end

    local function decoY(t)
        return G.fieldTop + (G.fieldBottom - G.fieldTop) * utils.clamp(t, 0, 1)
    end

    local function decoScale(t)
        return 0.58 + 0.62 * utils.clamp(t, 0, 1)
    end

    local treeN = math.max(0, math.floor(config.DEFAULT_MAP_TREE_COUNT or 44))
    for i = 1, treeN do
        local t = rnd()
        placeTree(decoX(i, treeN, 0.00), decoY(t), (56 + rnd() * 26) * decoScale(t) * G.k)
    end

    local bushN = math.max(0, math.floor(config.DEFAULT_MAP_BUSH_COUNT or 34))
    for i = 1, bushN do
        local t = 0.15 + rnd() * 0.85
        placeBush(decoX(i, bushN, 0.55), decoY(t), (38 + rnd() * 20) * decoScale(t) * G.k)
    end

    local flowerN = math.max(0, math.floor(config.DEFAULT_MAP_FLOWER_COUNT or 40))
    for i = 1, flowerN do
        local t = rnd()
        placeFlower(decoX(i, flowerN, 0.30), decoY(t), (14 + rnd() * 10) * decoScale(t) * G.k)
    end

    local millN = math.max(0, math.floor(config.DEFAULT_MAP_WINDMILL_COUNT or 24))
    for i = 1, millN do
        local t = 0.25 + rnd() * 0.7
        placeWindmill(decoX(i, millN, 0.72), decoY(t), (62 + rnd() * 26) * decoScale(t) * G.k)
    end

    local grassN = math.max(0, math.floor(config.DEFAULT_MAP_GRASS_COUNT or 46))
    for i = 1, grassN do
        local t = rnd()
        placeGrassTuft(decoX(i, grassN, 0.18), decoY(t), (26 + rnd() * 14) * decoScale(t) * G.k)
    end

    -- ★ 两端收口：第 1 片果园停在正中时，它左边本来是纯空地（可视窗口就这么停的）。
    --   往两侧再撒一小圈果树 / 灌木 / 草，构图才不塌。
    --   起始点离节点留 0.95 个间距，别贴到金圈上。
    for _, dir in ipairs({ -1, 1 }) do
        local edge
        if dir < 0 then edge = nodeX(G, 1) - G.spacing * 0.95
        else edge = nodeX(G, G.n) + G.spacing * 0.95 end
        for i = 1, 4 do
            local t = 0.28 + rnd() * 0.58
            local x = edge + dir * (i - 1) * G.spacing * 0.55
            local s = (52 + rnd() * 26) * decoScale(t) * G.k
            if i % 2 == 0 then
                placeBush(x, decoY(t), s * 0.72)
            else
                placeTree(x, decoY(t), s)
            end
        end
        for i = 1, 4 do
            local t = rnd()
            placeGrassTuft(edge + dir * (i + 0.6) * G.spacing * 0.30, decoY(t),
                (28 + rnd() * 12) * decoScale(t) * G.k)
        end
        placeWindmill(edge + dir * G.spacing * 0.26, decoY(0.52),
            (62 + rnd() * 18) * decoScale(0.52) * G.k)
    end
end

-- ================================================================
-- 长图：果园节点
-- ================================================================
local function buildNodes(G)
    local pal = utils.palette()
    state.mapNodes = {}
    state.mapNodeX, state.mapNodeY = {}, {}

    for i = 1, G.n do
        local x, y = nodeX(G, i), nodeY(G, i)
        state.mapNodeX[i], state.mapNodeY[i] = x, y

        local root = utils.createContainer(state.mapWorld)
        if root then
            utils.raise(root)
            utils.setPos(root, x, y)
        end

        -- 立体投影（椭圆，压在果实下沿）
        utils.circleC(0, -G.nodeSize * 0.30, G.nodeSize * 1.00, G.nodeSize * 0.42, pal.shadow, 55, root)
        -- 果实本体：圆形模板拼出「一颗果子」（外皮 / 内芯 / 高光 / 叶子）
        local base = utils.circleC(0, 0, G.nodeSize, G.nodeSize, pal.fruit, 255, root)
        local inner = utils.circleC(0, -G.nodeSize * 0.04, G.nodeInner, G.nodeInner * 0.94, pal.fruit, 255, root)
        local shine = utils.circleC(-G.nodeSize * 0.16, G.nodeSize * 0.22,
            G.nodeInner * 0.42, G.nodeInner * 0.24, "FFFFFF", 120, root)
        local leafC = utils.circleC(G.nodeSize * 0.28, G.nodeSize * 0.44,
            17 * G.k, 9 * G.k, pal.leaf, 255, root)
        if leafC then utils.setRotationZ(leafC, -26) end
        local num = label(root, 0, 0, G.nodeSize * 1.15, 36 * G.k, string.format("%02d", i),
            pal.accentText, math.max(14, 20 * G.k))
        -- ★ 苹果下方三颗星：通关 = 金黄发亮，未通关 = 星星与苹果一起压暗（用户要求）
        --   暗星用「混色 + 高 alpha」而不是低 alpha：半透明星会淡到看不见，
        --   玩家会以为「没画星星」而不是「这关没通」。
        local starGap = G.nodeSize * 0.30
        local starS = G.nodeSize * 0.22
        local stars = {}
        for s = 1, 3 do
            local st = utils.starC((s - 2) * starGap, -G.nodeSize * 0.86, starS, starS,
                pal.gold, 255, root, true)
            if st then utils.noRay(st) end
            stars[#stars + 1] = st
        end

        -- 命中区（比节点大一圈；不放进 root，缩放动画不影响它）
        local hit = utils.createHit(x, y, G.nodeHit, G.nodeHit, state.mapWorld)
        if hit then
            utils.raise(hit)
            utils.bindPointer(hit, {
                threshold = (config.DEFAULT_MAP_DRAG_THRESHOLD or 10) * G.k,
                down = function() M.pressNode(i) end,
                drag = function(dx) M.dragBy(dx) end,
                drop = function() M.dropDrag() end,
                tap = function() M.tapNode(i) end,
            })
        end

        state.mapNodes[i] = {
            idx = i, x = x, y = y, root = root,
            base = base, inner = inner, shine = shine, leaf = leafC,
            num = num, stars = stars, hit = hit,
            s = 1, targetS = 1, pop = 1, popT = 9, prevCleared = false,
        }
    end
end

-- ================================================================
-- 当前果园的金圈：四根细条拼一个「框」
--   ★ 用框而不是整块色板：整块会在果实后面露出一圈方块，像贴了张纸；
--     细条读起来才是「圈住这一关」。
-- ================================================================
local function buildCursorRing(G)
    local pal = utils.palette()
    local parts = {}
    -- ★ 有圆环模板就用真圆环（一层呼吸光晕 + 一层实环）；
    --   没有就退回「四根细条拼的方框」——千万不能用圆形顶上，
    --   圆形是实心的，会把整个果园节点糊住。
    if (state.ringPrefabId or 0) > 0 then
        parts.glow = utils.ringShape(0, 0, G.ringSize * 1.30, G.ringSize * 1.30,
            utils.hexToColorA(pal.gold, 90), state.mapWorld)
        parts.ring = utils.ringShape(0, 0, G.ringSize, G.ringSize,
            utils.hexToColorA(pal.gold, 235), state.mapWorld)
        if parts.glow then utils.noRay(parts.glow) end
        if parts.ring then utils.noRay(parts.ring) end
        state.mapRingShape = true
    else
        local th = math.max(3, 3.4 * G.k)
        parts.top = rect(state.mapWorld, 0, 0, G.ringSize, th, pal.gold, 200)
        parts.bottom = rect(state.mapWorld, 0, 0, G.ringSize, th, pal.gold, 200)
        parts.left = rect(state.mapWorld, 0, 0, th, G.ringSize - th * 2, pal.gold, 200)
        parts.right = rect(state.mapWorld, 0, 0, th, G.ringSize - th * 2, pal.gold, 200)
        state.mapRingShape = false
    end
    state.mapRingParts = parts
    state.mapRingSize = G.ringSize * 0.5
end

-- ================================================================
-- 长图：吉祥物「小果龙」（参考图 → 96×96 纯矩形拼图）
-- ----------------------------------------------------------------
-- ★ 造型数据全在 mascot.lua（由 `_gen_mascot.py` 从参考图生成，1515 个矩形）；
--   这里只负责挂到 mapWorld 上、定位置，以及「呼吸 + 轻晃」的待机动画。
-- ★ 一帧只动一个容器（整块 setPos / setScale / setRotationZ），
--   拼图本身是死的 → 1500 多个控件也不吃帧（不参与每帧计算）。
-- ★ 只 require 一个模块，长图布局照旧：包围盒 = mascot.WIDTH 见方。
-- ================================================================
local function buildMascot(G)
    local root = mascot.build(state.mapWorld, G.k)
    if not root then return end
    utils.raise(root)
    state.mapMascot = root
    state.mapMascotParts = {}      -- 旧版「翅膀 / 尾巴 / 眼睛」部件表已作废
    state.mapMascotIdx = 0
end

-- ================================================================
-- 顶部 / 底部 UI
-- ================================================================
local function buildHUD(G)
    local pal = utils.palette()
    local k, cw, ch = G.k, G.cw, G.ch

    local titleSize = math.max(22, (config.DEFAULT_MAP_TITLE_SIZE or 42) * k)
    local textSize = math.max(12, (config.DEFAULT_MAP_TEXT_SIZE or 19) * k)
    local hintSize = math.max(11, (config.DEFAULT_MAP_HINT_SIZE or 15) * k)

    -- ★ 标题牌：圆角奶油牌（牌沿 + 牌面 + 底部金线）
    --   早期版本是铺满屏宽的半透明纱带，会在天空里留一条硬边，像没修干净的色块；
    --   圆角是用「一横一竖两条矩形 + 四角圆」拼的，任何端都成立。
    local pw = math.min(cw - 48 * k, 620 * k)
    local ph = utils.clamp(G.topReserve - 12 * k, 104 * k, 142 * k)
    local pcy = ch / 2 - G.topReserve * 0.5
    local pr = math.min(22 * k, ph * 0.24)
    -- ★ 圆角块的返回值一定要存下来！早期写成「用完就扔」，
    --   setVisible(false) 时就没人管它了 —— 进关后头顶还挂着一块奶油牌。
    state.mapHeadBandEdge = utils.roundRect(3 * k, pcy - 7 * k, pw, ph, pr, pal.line, state.containerMap)
    state.mapHeadBand = utils.roundRect(0, pcy, pw - 6 * k, ph - 6 * k, pr, pal.panel, state.containerMap)
    -- ★ 牌内三行按「字高 + 行距」硬排，别用比例：
    --   标题 30*k 实际字高约 40px，用 ph*0.24 排会和副标题叠在一起。
    local titleDY = ph * 0.22
    local subDY = -ph * 0.15
    local barDY = -ph * 0.36

    state.mapTitle = label(state.containerMap, 0, pcy + titleDY, pw, 46 * k,
        "瓦雷莎的果园救急", pal.accent, titleSize)
    state.mapSubtitle = label(state.containerMap, 0, pcy + subDY, pw, 34 * k,
        "", pal.text, textSize)
    -- 进度条：胶囊轨道 + 胶囊填充
    local barW = math.min(240 * k, cw * 0.36)
    local barH = 9 * k
    local barY = pcy + barDY
    progressBarY = barY
    state.mapProgressTrack = utils.roundRect(0, barY, barW, barH, barH * 0.5, pal.line, state.containerMap)
    state.mapProgressFill = utils.circleC(-barW / 2, barY, barH, barH, pal.ok, 255, state.containerMap)
    state.mapProgressW = barW
    state.mapProgressX = 0

    -- 底部提示（胶囊条）
    local footW = math.min(cw - 40 * k, 660 * k)
    local footH = 34 * k
    state.mapFootBand = utils.roundRect(0, -ch / 2 + 26 * k, footW, footH, footH * 0.5,
        pal.panel, state.containerMap)
    state.mapFooter = label(state.containerMap, 0, -ch / 2 + 26 * k, footW, footH,
        MAP_HINT, pal.text, hintSize)

    -- 左右箭头：圆形钮（投影 + 外沿 + 钮面）
    local ab = math.min((config.DEFAULT_MAP_BTN_W or 62), (config.DEFAULT_MAP_BTN_H or 62)) * k
    local ax = cw / 2 - ab / 2 - 16 * k
    local ay = G.bandCY

    local function makeArrow(x, text, dir)
        local btn = utils.createContainer(state.containerMap, ab + 30 * k, ab + 30 * k)
        utils.setPos(btn, x, ay)
        utils.circleC(2 * k, -6 * k, ab, ab, pal.shadow, 80, btn)
        utils.circleC(0, 0, ab, ab, pal.line, 255, btn)
        utils.circleC(0, 0, ab - 5 * k, ab - 5 * k, pal.card, 255, btn)
        -- ★ 钮面顶部的白色扁椭圆高光已去掉：三层圆叠完已经够立体，
        --   再加一个椭圆只会多出一团白斑（同 guide / winUI / hud 的按钮）
        local lab = label(btn, 0, 0, ab, ab, text, pal.accent, math.max(20, 30 * k))
        local hit = utils.createHit(x, ay, ab + 18 * k, ab + 18 * k, state.containerMap)
        if hit then
            utils.raise(hit)
            utils.bindPointer(hit, {
                threshold = (config.DEFAULT_MAP_DRAG_THRESHOLD or 10) * k,
                tap = function()
                    if state.guideOpen or state.winOpen then return end
                    audio.playClick()
                    M.moveCursor(dir)
                end,
            })
        end
        utils.bindHover(hit,
            function() utils.setScale(btn, 1.10) end,
            function() utils.setScale(btn, 1.0) end)
        return { bg = btn, label = lab, hit = hit }
    end

    state.mapArrowL = makeArrow(-ax, "←", -1)
    state.mapArrowR = makeArrow(ax, "→", 1)

    -- 底部两个按钮（圆角胶囊）
    local hbw = (config.DEFAULT_MAP_HANDBOOK_BTN_W or 148) * k
    local hbh = (config.DEFAULT_MAP_HANDBOOK_BTN_H or 46) * k
    local ebw = (config.DEFAULT_MAP_ENTER_BTN_W or 214) * k
    local ebh = (config.DEFAULT_MAP_ENTER_BTN_H or 56) * k
    local by = -ch / 2 + 88 * k
    local margin = 26 * k

    local function makeButton(x, w, h, text, fillHex, rimHex, textHex, onTap)
        local btn = utils.createContainer(state.containerMap, w + 28 * k, h + 28 * k)
        utils.setPos(btn, x, by)
        -- ★ 三块圆角矩形要把句柄留下来：按钮本体是容器，容器改色无效，
        --   只能对 roundBox 用 utils.setBoxColor（「进入果园」按钮切未解锁态要用）。
        -- ★ 三块圆角矩形要用 roundBox（带 parts 句柄）而不是 roundRect：
        --   roundRect 只返回容器、拿不到零件，改色时 setBoxColor 静默失败，
        --   表现就是「未解锁」文案换了、按钮还是红的。
        local rim = utils.roundBox(2 * k, -6 * k, w, h, h * 0.40, rimHex, btn)
        local face = utils.roundBox(0, 0, w - 5 * k, h - 5 * k, (h - 5 * k) * 0.40, fillHex, btn)
        local gloss = utils.roundBox(0, (h - 5 * k) * 0.5 - 9 * k, w - 34 * k, 6 * k, 3 * k,
            utils.mixHex(fillHex, "FFFFFF", 0.55), btn)
        local lab = label(btn, 0, 0, w - 6 * k, h, text, textHex, math.max(12, 18 * k))
        local hit = utils.createHit(x, by, w + 8 * k, h + 8 * k, state.containerMap)
        if hit then
            utils.raise(hit)
            utils.bindPointer(hit, {
                threshold = (config.DEFAULT_MAP_DRAG_THRESHOLD or 10) * k,
                tap = function()
                    if state.guideOpen or state.winOpen then return end
                    audio.playClick()
                    fx.spawn(x, by, { n = 8, keys = { "juice1", "juice4" },
                        speed = 190, life = 0.42, size = 7 })
                    onTap()
                end,
            })
            utils.bindHover(hit,
                function() utils.setScale(btn, 1.06) end,
                function() utils.setScale(btn, 1.0) end)
        end
        return { bg = btn, rim = rim, face = face, gloss = gloss,
                 label = lab, hit = hit, w = w, h = h, x = x, y = by }
    end

    state.mapHandBtn = makeButton(-cw / 2 + margin + hbw / 2, hbw, hbh,
        "教程", pal.card, pal.line, pal.text,
        function() if M.actions.onTutorial then M.actions.onTutorial() end end)
    local ebx = cw / 2 - margin - ebw / 2
    state.mapEnterBtn = makeButton(ebx, ebw, ebh,
        "进入果园 →", pal.accent, utils.mixHex(pal.accent, pal.shadow, 0.42), pal.accentText,
        function() M.enterCursor() end)

    -- ============================================================
    -- ★★ 「点这里」引导层：序章读完 → 把「进入果园」按钮点亮
    -- ------------------------------------------------------------
    --   用户要求：删掉序章里「怎么挑果园」那一页，改成关掉序章后
    --   **在真按钮上**引导玩家点一下。比看示意图更直接。
    --
    --   三层结构：
    --     ① 两条光圈（四根细条拼框，**互不相交** → 不会有叠色接缝）；
    --        内圈常驻呼吸，外圈一边放大一边收 alpha（"ping" 效果）；
    --     ② 气泡（深色外沿 + 浅色牌面两块**不透明**圆角块）+ 文字；
    --     ③ 指向按钮的三角（上下轻跳）。
    --   ★ 圆角块 alpha 只能给 255（半透明会在拼接处露十字接缝），
    --     所以气泡的层次靠「外沿 / 牌面两块实色」而不是透明度。
    --   ★ 整层塞进 state.mapGuideRoot 一个容器：显隐只动根，不会漏层。
    --   ★ 光圈画在按钮外侧（外扩 GUIDE_PAD），不压按钮面 → 不影响按钮原配色。
    -- ============================================================
    local gpad = (config.DEFAULT_MAP_GUIDE_PAD or 16) * k
    local gbw = (config.DEFAULT_MAP_GUIDE_BUBBLE_W or 186) * k
    local gbh = (config.DEFAULT_MAP_GUIDE_BUBBLE_H or 40) * k
    local gts = math.max(13, (config.DEFAULT_MAP_GUIDE_TEXT_SIZE or 16) * k)
    local ehw, ehh = ebw * 0.5 + gpad, ebh * 0.5 + gpad
    local gth = math.max(3, 3.2 * k)
    local arrowW, arrowH = 22 * k, 12 * k
    -- ★ 三角要落在光圈**上沿之外**（不是压在框上）：光圈上沿已经比按钮高出 gpad，
    --   再留 6k 的空，读数才是「三角指着这个按钮」而不是「按钮上长了个尖」。
    local arrowY = by + ebh * 0.5 + gpad + 6 * k + arrowH * 0.5
    local bubY = arrowY + arrowH * 0.5 + 4 * k + gbh * 0.5
    state.mapGuideArrowX, state.mapGuideArrowY = ebx, arrowY

    state.mapGuideRoot = utils.createContainer(state.containerMap)
    if state.mapGuideRoot then
        utils.setPos(state.mapGuideRoot, 0, 0)
        for i = 1, 2 do
            local ring = utils.createContainer(state.mapGuideRoot, ehw * 2 + 40 * k, ehh * 2 + 40 * k)
            if ring then
                utils.setPos(ring, ebx, by)
                state.mapGuideRing[i] = ring
                -- 竖条长度要扣掉两条横条的厚度，四条才拼成一个闭合且不重叠的框
                local runL = ehh * 2 - gth * 2
                local bars = {
                    rect(ring, 0, ehh - gth * 0.5, ehw * 2, gth, pal.accent, 200),
                    rect(ring, 0, -ehh + gth * 0.5, ehw * 2, gth, pal.accent, 200),
                    rect(ring, -ehw + gth * 0.5, 0, gth, runL, pal.accent, 200),
                    rect(ring, ehw - gth * 0.5, 0, gth, runL, pal.accent, 200),
                }
                for j = 1, #bars do
                    if bars[j] then
                        state.mapGuideBars[#state.mapGuideBars + 1] = { ctrl = bars[j], ring = i }
                    end
                end
            end
        end
        state.mapGuideBubble = utils.roundBox(ebx, bubY, gbw + 6 * k, gbh + 6 * k,
            (gbh + 6 * k) * 0.44, utils.mixHex(pal.accent, pal.shadow, 0.34), state.mapGuideRoot)
        state.mapGuideBubbleFace = utils.roundBox(ebx, bubY, gbw, gbh, gbh * 0.44,
            pal.panel, state.mapGuideRoot)
        state.mapGuideText = label(state.mapGuideRoot, ebx, bubY, gbw - 8 * k, gbh,
            ENTER_HINT, pal.accent, gts)
        -- 三角默认朝上（风车叶片 / 草叶都是这个朝向）→ 转 180° 才是「指向下方按钮」
        state.mapGuideArrow = utils.triangleC(ebx, arrowY, arrowW, arrowH,
            pal.accent, 235, state.mapGuideRoot)
        if state.mapGuideArrow then
            utils.noRay(state.mapGuideArrow)
            utils.setRotationZ(state.mapGuideArrow, 180)
        end
        utils.setVisible(state.mapGuideRoot, false)
    end
end

-- ================================================================
-- 刷新：节点外观 / 进度 / 按钮文案
-- ================================================================
local function refreshNode(i)
    local nd = state.mapNodes[i]
    if not nd then return end
    local pal = utils.palette()
    local base, inner, labelHex, starA, cleared, unlocked, cursor = nodeColors(i)
    local G = geom()

    -- 配色全部由 nodeColors 决定（含光标提亮 / 未解锁压暗），这里直接套用。
    utils.setColor(nd.base, base, 255)
    utils.setColor(nd.inner, inner, 255)
    utils.setTextColor(nd.num, labelHex, unlocked and 255 or 180)
    -- ★ 叶子一律用绿色（用户要求）：红苹果也配绿叶，不再用金色叶；
    --   未解锁的果子整体压暗，叶子也跟着暗下去。
    utils.setColor(nd.leaf, pal.leaf, unlocked and 230 or 120)
    -- 未解锁：整体压暗一点（用高光透明度表达）
    utils.setColor(nd.shine, "FFFFFF", unlocked and 120 or 46)

    -- ★ 三颗星（用户要求）：
    --   通关          → 三颗【亮黄】星；
    --   已解锁未通关  → 暗金（看得出有三颗星，但一眼就知道没亮）；
    --   未解锁        → 【黑色】星。
    --   全部用 alpha 255 + 实色，不用低透明度：半透明星会淡到看不见，
    --   玩家会以为「根本没画星星」而不是「这关没通」。
    local starHex
    if cleared then
        starHex = pal.star or pal.gold
    elseif unlocked then
        starHex = pal.starDim or utils.mixHex(pal.gold, pal.locked, 0.55)
    else
        starHex = pal.starOff or "1F1F1F"
    end
    for s = 1, 3 do
        local st = nd.stars and nd.stars[s]
        if st then
            utils.setColor(st, starHex, 255)
            utils.setVisible(st, true)
        end
    end
    nd.prevCleared = cleared
end

local progressBarY = 0

local function refreshProgress()
    local total = math.max(1, config.getLevelCount())
    local done = clearedCount()
    local pal = utils.palette()
    local G = geom()
    local w = state.mapProgressW or 1
    local fillW = math.max(2, w * done / total)
    local x = (state.mapProgressX or 0) - w / 2 + fillW / 2
    utils.setSize(state.mapProgressFill, fillW, 9 * G.k)
    utils.setPos(state.mapProgressFill, x, progressBarY)
    utils.setColor(state.mapProgressFill, pal.ok, 255)
    utils.setText(state.mapSubtitle,
        string.format("已还原 %d / %d 片果园", done, total))
    utils.setTextColor(state.mapSubtitle, pal.text, 240)
    -- ★ 底部提示条每次刷新都写回「操作方法」：
    --   保证不管前面发生过什么，玩家看到的永远是这一句（见文件顶 MAP_HINT 注释）。
    if state.mapFooter then
        utils.setText(state.mapFooter, MAP_HINT)
        utils.setTextColor(state.mapFooter, pal.text, 255)
    end
    -- 进关按钮：未解锁时改文案 + 降到灰色，别让人以为点得进去（实际也进不去，
    -- 见 M.enterSelected / game.lua 的解锁判断）
    local cur = state.mapCursor or 1
    local ok = isUnlocked(cur)
    local btn = state.mapEnterBtn
    if btn then
        utils.setText(btn.label,
            ok and string.format("进入果园 %02d →", cur)
               or string.format("第 %02d 片 · 未解锁", cur))
        utils.setTextColor(btn.label, ok and pal.accentText or pal.dim, 255)
        local fillHex = ok and pal.accent or pal.locked
        local rimHex = ok and utils.mixHex(pal.accent, pal.shadow, 0.42)
                          or utils.mixHex(pal.locked, pal.shadow, 0.26)
        utils.setBoxColor(btn.face, fillHex, 255)
        utils.setBoxColor(btn.rim, rimHex, 255)
        utils.setBoxColor(btn.gloss, utils.mixHex(fillHex, "FFFFFF", 0.55), 255)
    end
end

-- ================================================================
-- 选中 / 进入
-- ================================================================
local function setCursor(i, animate)
    local G = geom()
    i = math.floor(tonumber(i) or 1)
    if i < 1 then i = 1 end
    if i > G.n then i = G.n end
    if state.mapCursor ~= i then
        state.mapCursor = i
        for k = 1, G.n do refreshNode(k) end
        refreshProgress()
    end
    M.scrollToLevel(i, animate)
end

function M.scrollToLevel(i, animate)
    local G = geom()
    local target = scrollOfLevel(i)
    state.mapTarget = target
    if not animate or not state.mapOpen then
        state.mapScroll = target
        state.mapScrollFrom = target
        state.mapScrollDur = 0
        state.mapScrollT = 0
        if state.mapWorld then
            utils.setPos(state.mapWorld, target, 0)
        end
        return
    end
    state.mapScrollFrom = state.mapScroll
    state.mapScrollDur = config.DEFAULT_MAP_STEP_TIME or 0.34
    state.mapScrollT = 0
    state.mapVel = 0
end

function M.pressNode(i)
    if state.guideOpen or state.winOpen then return end
    state.mapDragging = true
    state.mapMoved = 0
    armDragSound()
    -- 按在别的果园上时先选中它（不滚动，避免拖拽时打架）
    if i and i >= 1 and state.mapCursor ~= i then
        local G = geom()
        state.mapCursor = i
        for k = 1, G.n do refreshNode(k) end
        refreshProgress()
    end
end

function M.dragBy(dx)
    if state.guideOpen or state.winOpen then return end
    if not state.mapDragging then state.mapDragging = true end
    state.mapScrollDur = 0
    state.mapScrollT = 0
    state.mapVel = (dx / math.max(0.008, state.lastDt or 0.016)) * 0.55
    state.mapScroll = clampScroll(state.mapScroll + dx)
    if state.mapWorld then utils.setPos(state.mapWorld, state.mapScroll, 0) end

    -- ★ 拖动音效：第一次真拖动（越过点击阈值）响一声；之后每跨过一片果园响一声
    if dragSndArmed then
        dragSndArmed = false
        playDragTick(true)
    end
    local idx = nearestIndexForScroll(state.mapScroll)
    if idx ~= dragSndIdx then
        dragSndIdx = idx
        playDragTick(false)
    end
end

function M.dropDrag()
    if not state.mapDragging then return end
    state.mapDragging = false
    dragSndArmed = false
    local G = geom()
    -- 惯性：按预测落点找最近的果园，直接吸附过去（比纯物理更好控）
    local pred = state.mapScroll + state.mapVel / math.max(1, config.DEFAULT_MAP_FRICTION or 3.4)
    pred = clampScroll(pred)
    local idx = nearestIndexForScroll(pred)
    state.mapCursor = idx
    for k = 1, G.n do refreshNode(k) end
    refreshProgress()
    state.mapScrollFrom = state.mapScroll
    state.mapTarget = scrollOfLevel(idx)
    state.mapScrollDur = config.DEFAULT_MAP_SNAP_TIME or 0.26
    state.mapScrollT = 0
    state.mapVel = 0
end

function M.tapNode(i)
    if state.guideOpen or state.winOpen then return end
    state.mapCursor = i
    for k = 1, math.max(1, config.getLevelCount()) do refreshNode(k) end
    refreshProgress()
    audio.playClick()
    if isUnlocked(i) then
        M.enterLevel(i)
    else
        -- ★ 未解锁：只给一点「碰不动」的粒子反馈，**不再改底部提示条**。
        --   旧版这里会把提示条换成「这片果园还锁着 —— 先把前面的果园还原了」，
        --   且没有还原的时机 —— 操作方法就被这句红字永久顶掉了。
        fx.spawn(state.mapNodeX[i] + state.mapScroll, state.mapNodeY[i],
            { n = 10, keys = { "juice1", "dim" }, speed = 170, life = 0.45, size = 7 })
    end
end

function M.enterLevel(i)
    if not config.getLevelConfig(i) then return false end
    if not isUnlocked(i) then return false end
    M.guideEnter(false)          -- 进关了，引导自然结束（点按钮 / 空格 / 点果实都走这里）
    if M.actions.onEnter then M.actions.onEnter(i) end
    return true
end

function M.enterCursor()
    M.enterLevel(state.mapCursor or 1)
end

-- ================================================================
-- ★★ 「点这里」引导：开 / 关（唯一入口，别在别处直接改 state.mapGuide）
-- ----------------------------------------------------------------
--   开：game.lua 每帧检查 state.prologueGuidePending（序章被关掉时由 guide 置位），
--       确认「还在地图页 + 教程已关」就调一次 M.guideEnter(true)；
--   关：进关成功 / 地图收起（setVisible(false)）→ 自动关。
--   ★ 只影响自己的引导层，不碰底部提示条 —— 提示条永远写 MAP_HINT
--     （以前有过「临时文案把操作方法永久顶掉」的坑，见文件顶注释）。
-- ================================================================
function M.guideEnter(on)
    on = on and true or false
    -- ★ 关掉就等于「这件事结束了」：连排队中的待触发一起清掉，
    --   否则进关后 pending 还挂着，下次回地图会冒出一条过期引导。
    if not on then state.prologueGuidePending = false end
    if state.mapGuide == on then return end
    state.mapGuide = on
    state.mapGuideT = 0
    utils.setVisible(state.mapGuideRoot, on)
    if not on or not state.mapGuideRoot then return end
    -- 亮起来的那一下给一把果汁，玩家余光也能注意到右下角
    local G = geom()
    local ebw = (config.DEFAULT_MAP_ENTER_BTN_W or 214) * G.k
    local margin = 26 * G.k
    fx.spawn(G.cw / 2 - margin - ebw * 0.5, -G.ch / 2 + 88 * G.k,
        { n = 14, keys = { "juice1", "juice4", "star" },
          speed = 210 * G.k, life = 0.55, size = 8 * G.k })
end

-- ================================================================
-- 坐标系校准：三种候选，取落在「地图带」里的那个
-- ================================================================
local function toLocal(px, py)
    local G = geom()
    local cw, ch = G.cw, G.ch
    local cands = {
        { px, py },                  -- 已经是居中坐标（y 向上）
        { px - cw / 2, py - ch / 2 },-- 左上原点，y 向上
        { px - cw / 2, ch / 2 - py },-- 左上原点，y 向下
    }
    local pick = state.mapPointerMap or 0
    if pick >= 1 and pick <= 3 then
        local c = cands[pick]
        return c[1], c[2]
    end
    for i = 1, 3 do
        local x, y = cands[i][1], cands[i][2]
        if math.abs(x) <= cw / 2 + 4 and math.abs(y) <= ch / 2 + 4
            and math.abs(y - G.bandCY) <= G.bandH / 2 + 60 then
            state.mapPointerMap = i
            return x, y
        end
    end
    state.mapPointerMap = 2
    return cands[2][1], cands[2][2]
end

-- 拖动区的点击：按坐标找最近的果园（兜底路径，真机一般走节点命中区）
local function tapAtScreen(px, py)
    if state.guideOpen or state.winOpen then return end
    local lx, ly = toLocal(px, py)
    local G = geom()
    local best, bestD = nil, math.huge
    for i = 1, G.n do
        local sx = (state.mapNodeX[i] or 0) + state.mapScroll
        local sy = state.mapNodeY[i] or 0
        local d = (sx - lx) * (sx - lx) + (sy - ly) * (sy - ly)
        if d < bestD then best, bestD = i, d end
    end
    local radius = G.nodeHit / 2 + 10
    if best and bestD <= radius * radius then
        M.tapNode(best)
    end
end

-- ================================================================
-- 初始化
-- ================================================================
function M.init()
    if state.mapWorld then return true end
    if not state.containerMap then return false end
    if not state.rectPrefabId or state.rectPrefabId <= 0 then return false end

    local G = geom()

    -- ① 地图拖动 / 点击区（放在 mapWorld 之下：节点命中区优先）
    state.mapDragHit = utils.createHit(0, G.bandCY, G.cw + 60, G.bandH + 60, state.containerMap)
    if state.mapDragHit then
        utils.bindPointer(state.mapDragHit, {
            threshold = (config.DEFAULT_MAP_DRAG_THRESHOLD or 10) * G.k,
            down = function() state.mapDragging = true; state.mapMoved = 0; armDragSound() end,
            drag = function(dx) M.dragBy(dx) end,
            drop = function() M.dropDrag() end,
            tap = function(px, py) tapAtScreen(px, py) end,
        })
    end

    -- ② 长图
    state.mapWorldW = G.worldW
    state.mapMaxScroll = G.maxScroll
    state.mapWorld = utils.createContainer(state.containerMap, G.worldW + 400, G.ch * 2)
    if not state.mapWorld then return false end
    utils.raise(state.mapWorld)
    utils.setPos(state.mapWorld, 0, 0)

    buildPath(G)
    buildDecos(G)
    buildNodes(G)
    buildCursorRing(G)
    buildMascot(G)

    -- ③ 顶部 / 底部
    buildHUD(G)

    recomputeUnlock()
    state.mapCursor = math.max(1, math.min(G.n, state.currentLevelIndex or 1))
    for i = 1, G.n do refreshNode(i) end
    refreshProgress()
    M.scrollToLevel(state.mapCursor, false)

    utils.setVisible(state.mapWorld, false)
    M.setVisible(false)
    return true
end

-- ================================================================
-- 显隐
-- ================================================================
local function allNodes()
    local list = { state.mapDragHit, state.mapHeadBandEdge, state.mapHeadBand,
        state.mapTitle, state.mapSubtitle,
        state.mapProgressTrack, state.mapProgressFill, state.mapFootBand, state.mapFooter,
        state.mapArrowL and state.mapArrowL.bg, state.mapArrowL and state.mapArrowL.label,
        state.mapArrowL and state.mapArrowL.hit,
        state.mapArrowR and state.mapArrowR.bg, state.mapArrowR and state.mapArrowR.label,
        state.mapArrowR and state.mapArrowR.hit,
        state.mapHandBtn and state.mapHandBtn.bg, state.mapHandBtn and state.mapHandBtn.label,
        state.mapHandBtn and state.mapHandBtn.hit,
        state.mapEnterBtn and state.mapEnterBtn.bg, state.mapEnterBtn and state.mapEnterBtn.label,
        state.mapEnterBtn and state.mapEnterBtn.hit,
    }
    return list
end

function M.setVisible(v)
    state.mapOpen = v and true or false
    utils.setVisibleAll(allNodes(), v)
    utils.setVisible(state.mapWorld, v)
    -- ★ 引导层不进 allNodes()：它的显隐只能由 guideEnter 控制，
    --   否则「地图收起又回来」会让一条过期引导重新冒出来。
    if not v then M.guideEnter(false) end
    if v then
        recomputeUnlock()
        for i = 1, math.max(1, config.getLevelCount()) do refreshNode(i) end
        refreshProgress()
        state.mapAnimT = 0
        state.mapIntroDone = false
        local G = geom()
        local cursor = state.mapCursor or 1
        state.mapScroll = scrollOfLevel(cursor)
        state.mapScrollFrom = state.mapScroll
        state.mapScrollDur = 0
        if state.mapWorld then utils.setPos(state.mapWorld, state.mapScroll, 0) end
        M.applyIntro(0)
        -- 入场时在标题附近撒一把果汁
        fx.spawn(0, G.ch / 2 - 70 * G.k,
            { n = 16, keys = { "juice1", "juice2", "juice4" }, dir = 270, spread = 140,
              speed = 260, life = 0.65, size = 9 })
    else
        fx.cancelAll()
    end
end

function M.isVisible()
    return state.mapOpen == true
end

-- ================================================================
-- 入场：长图从下方浮起 + 节点按「离当前果园的距离」依次弹出
-- ================================================================
function M.applyIntro(k)
    k = utils.clamp(k, 0, 1)
    local G = geom()
    local e = 1 - (1 - k) * (1 - k)
    if state.mapWorld then
        utils.setPos(state.mapWorld, state.mapScroll, -46 * G.k * (1 - e))
    end
    local cursor = state.mapCursor or 1
    for i, nd in ipairs(state.mapNodes) do
        local d = math.abs(i - cursor)
        local delay = math.min(0.55, d * 0.022)
        local t = (k - delay) / math.max(0.001, 1 - delay)
        t = utils.clamp(t, 0, 1)
        local s = 0.55 + 0.45 * (1 - (1 - t) * (1 - t) * (1 - t))
        utils.setScale(nd.root, s)
        nd.s = s
    end
end

-- ================================================================
-- 每帧
-- ================================================================
function M.update(dt)
    dt = tonumber(dt) or 0
    if dt <= 0 then return end
    if not state.mapOpen then return end
    local G = geom()
    local t = state.fxTime or 0

    -- 入场
    if not state.mapIntroDone then
        state.mapAnimT = (state.mapAnimT or 0) + dt
        local dur = config.DEFAULT_MAP_INTRO_TIME or 0.46
        local k = state.mapAnimT / dur
        if k >= 1 then
            k = 1
            state.mapIntroDone = true
        end
        M.applyIntro(k)
    end

    -- 平滑滚动（箭头 / 吸附）
    local introY = 0
    if not state.mapIntroDone then
        local ik = utils.clamp((state.mapAnimT or 0) / (config.DEFAULT_MAP_INTRO_TIME or 0.46), 0, 1)
        introY = -46 * G.k * (1 - (1 - (1 - ik) * (1 - ik)))
    end
    if not state.mapDragging and (state.mapScrollDur or 0) > 0 then
        state.mapScrollT = (state.mapScrollT or 0) + dt
        local k = utils.clamp(state.mapScrollT / state.mapScrollDur, 0, 1)
        local e = 1 - (1 - k) * (1 - k) * (1 - k)
        state.mapScroll = state.mapScrollFrom + (state.mapTarget - state.mapScrollFrom) * e
        if k >= 1 then
            state.mapScroll = state.mapTarget
            state.mapScrollDur = 0
        end
        if state.mapWorld then
            utils.setPos(state.mapWorld, state.mapScroll, introY)
        end
    elseif state.mapWorld and not state.mapDragging then
        utils.setPos(state.mapWorld, state.mapScroll + 0, introY)
    end

    -- 当前果园：金圈呼吸 + 果实轻微心跳
    local cn = state.mapNodes[state.mapCursor]
    if cn then
        local pulse = 0.5 + 0.5 * math.sin(t * 3.2)
        utils.setScale(cn.root, (cn.s or 1) * (1 + 0.035 * pulse))
    end

    -- 金圈：跟着当前节点，呼吸 + 轻微放大
    local rp = state.mapRingParts
    if rp then
        local pulse2 = 0.5 + 0.5 * math.sin(t * 3.2)
        local cx = (state.mapNodeX[state.mapCursor] or 0)
        local cy = (state.mapNodeY[state.mapCursor] or 0)
        if state.mapRingShape and rp.ring then
            local s2 = 1 + 0.035 * pulse2
            utils.setPos(rp.ring, cx, cy)
            utils.setScale(rp.ring, s2)
            utils.setColor(rp.ring, utils.palette().gold, 190 + 60 * pulse2)
            if rp.glow then
                utils.setPos(rp.glow, cx, cy)
                utils.setScale(rp.glow, s2 * (1.02 + 0.05 * pulse2))
                utils.setColor(rp.glow, utils.palette().gold, 45 + 55 * pulse2)
            end
        elseif rp.top then
            local half = G.ringSize * 0.5 * (1 + 0.03 * pulse2)
            local a = 150 + 90 * pulse2
            utils.setPos(rp.top, cx, cy + half)
            utils.setPos(rp.bottom, cx, cy - half)
            utils.setPos(rp.left, cx - half, cy)
            utils.setPos(rp.right, cx + half, cy)
            for _, key in ipairs({ "top", "bottom", "left", "right" }) do
                utils.setColor(rp[key], utils.palette().gold, a)
            end
        end
    end

    -- 已还原节点的星星闪烁（只算视野内的，省性能）
    local viewL = state.mapScroll - G.cw / 2 - G.spacing
    local viewR = state.mapScroll + G.cw / 2 + G.spacing
    for i = 1, G.n do
        local x = state.mapNodeX[i] or 0
        if x >= viewL and x <= viewR then
            local nd = state.mapNodes[i]
            if nd and state.clearedLevels[i] then
                local a = 170 + 85 * math.sin(t * 3.0 + i * 0.7)
                utils.setTextColor(nd.star, utils.palette().star, a)
            end
        end
    end

    -- 土路石子：一道光沿着路往前跑（只算视野内的）
    local pal = utils.palette()
    for i = 1, #state.mapDots do
        local d = state.mapDots[i]
        if d.x >= viewL and d.x <= viewR then
            local w = 0.5 + 0.5 * math.sin(t * 3.0 - d.x * 0.012)
            utils.setColor(d.ctrl, utils.mixHex(pal.soil, pal.star, w * 0.55), 190 + 60 * w)
        end
    end

    -- 装饰动效：风车自转 / 小草顺风摆 / 树与灌木轻晃
    for i = 1, #state.mapDecos do
        local d = state.mapDecos[i]
        if d.ctrl then
            if d.kind == "windmill" then
                if d.head then utils.setRotationZ(d.head, t * (d.spin or 120) + d.phase) end
            elseif d.kind == "grass" then
                local sw = 10 * math.sin(t * 2.1 + d.phase)
                for j, b in ipairs(d.blades or {}) do
                    utils.setRotationZ(b, sw * (0.7 + j * 0.28))
                end
            else
                utils.setRotationZ(d.ctrl, 2.0 * math.sin(t * 1.2 + d.phase))
            end
        end
    end

    -- 吉祥物：滑向当前果园（弹簧跟随）+ 悬停呼吸 + 轻晃
    if state.mapMascot then
        local tx = (state.mapNodeX[state.mapCursor] or 0)
        local ty = (state.mapNodeY[state.mapCursor] or 0) + G.nodeSize * 0.92 + 48 * G.k
        if state.mapMascotIdx ~= state.mapCursor then
            state.mapMascotIdx = state.mapCursor
            if state.mapMascotX == 0 and state.mapMascotY == 0 then
                state.mapMascotX, state.mapMascotY = tx, ty
            end
        end
        local lerp = math.min(1, dt * 7.5)
        state.mapMascotX = state.mapMascotX + (tx - state.mapMascotX) * lerp
        state.mapMascotY = state.mapMascotY + (ty - state.mapMascotY) * lerp
        -- 待机：上下浮 + 呼吸缩放 + 左右轻晃（整块容器一起动，不碰子控件）
        local bob = 5 * G.k * math.sin(t * 2.4)
        utils.setPos(state.mapMascot, state.mapMascotX, state.mapMascotY + bob)
        utils.setScale(state.mapMascot, 1 + 0.035 * math.sin(t * 2.4 + 0.6))
        utils.setRotationZ(state.mapMascot, 1.8 * math.sin(t * 1.35))
    end

    -- 箭头：到头了变淡
    local pal2 = utils.palette()
    if state.mapArrowL then
        local on = state.mapCursor > 1
        utils.setColor(state.mapArrowL.bg, on and pal2.card or pal2.panelDeep, on and 235 or 120)
        utils.setTextColor(state.mapArrowL.label, on and pal2.text or pal2.line, 255)
    end
    if state.mapArrowR then
        local on = state.mapCursor < G.n
        utils.setColor(state.mapArrowR.bg, on and pal2.card or pal2.panelDeep, on and 235 or 120)
        utils.setTextColor(state.mapArrowR.label, on and pal2.text or pal2.line, 255)
    end

    -- ★★ 引导层：内圈常驻呼吸 + 外圈扩散消散 + 三角轻跳
    --   ★ 只用 setColor / setScale / setPos 三种「便宜」的写操作，不新建控件；
    --     一帧最多改 4+4 条细条的颜色 + 1 个三角的 y，不吃帧。
    if state.mapGuide and state.mapGuideRoot then
        state.mapGuideT = (state.mapGuideT or 0) + dt
        local period = math.max(0.4, config.DEFAULT_MAP_GUIDE_PULSE or 1.4)
        local ph = (state.mapGuideT % period) / period
        local aInner = 140 + 90 * (0.5 + 0.5 * math.sin(state.mapGuideT * 3.6))
        local aOuter = 230 * (1 - ph)
        local ring1, ring2 = state.mapGuideRing[1], state.mapGuideRing[2]
        if ring1 then utils.setScale(ring1, 1) end
        if ring2 then utils.setScale(ring2, 1 + 0.11 * ph) end
        for i = 1, #state.mapGuideBars do
            local b = state.mapGuideBars[i]
            if b.ctrl then
                utils.setColor(b.ctrl, pal.accent, (b.ring == 1) and aInner or aOuter)
            end
        end
        if state.mapGuideArrow then
            local bob = 3 * G.k * math.sin(state.mapGuideT * 5.4)
            utils.setPos(state.mapGuideArrow, state.mapGuideArrowX, state.mapGuideArrowY + bob)
        end
    end
end

-- ================================================================
-- 对外
-- ================================================================
function M.refresh()
    if not state.mapWorld then return end
    recomputeUnlock()
    local G = geom()
    for i = 1, G.n do refreshNode(i) end
    refreshProgress()
end

function M.markCleared(idx, stars)
    idx = math.floor(tonumber(idx) or 0)
    if idx < 1 then return end
    state.clearedLevels[idx] = true
    state.levelStars[idx] = math.max(1, math.min(3, math.floor(tonumber(stars) or 3)))
    recomputeUnlock()
    local G = geom()
    for i = 1, G.n do refreshNode(i) end
    refreshProgress()
    -- 通关后把光标推到下一片
    if idx < G.n then
        setCursor(idx + 1, true)
    else
        setCursor(idx, false)
    end
end

-- ================================================================
-- ★ 「服客同步存档信息」：用服务器存档覆盖本地进度
--   latestCleared : 已通关的最新关卡序号（1 基；0 / nil = 一片都没通关）
--   返回          : 对齐后的光标位置
-- ----------------------------------------------------------------
-- ★ 存档的唯一真相在服务器：这里直接**覆盖**本地，不做「取并集」，
--   否则服务器回档了客户端还留着旧进度，两端口径永远对不上。
-- ★ 协议只给一个数（已通关到第几片），因为通关是一条直线：
--   「已通关 N」⇒ 1..N 全通关，解锁上限 = N + LOCK_AHEAD（N=0 时仍只有第 1 片）。
-- ================================================================
function M.applySave(latestCleared)
    local total = math.max(1, config.getLevelCount())
    local n = math.floor(tonumber(latestCleared) or 0)
    if n < 0 then n = 0 end
    if n > total then n = total end

    -- ① 通关表 / 星级：清空后按「1..N 全部通关」重建（协议里没有星级，通关即满星）
    for k in pairs(state.clearedLevels) do state.clearedLevels[k] = nil end
    for k in pairs(state.levelStars) do state.levelStars[k] = nil end
    for i = 1, n do
        state.clearedLevels[i] = true
        state.levelStars[i] = 3
    end

    -- ② 解锁上限：服务器说通关到第 N 片 ⇒ 可挑战到第 N + ahead 片
    local ahead = math.max(1, math.floor(config.DEFAULT_MAP_LOCK_AHEAD or 1))
    state.mapUnlockHint = utils.clamp(n + ahead, 1, total)

    recomputeUnlock()

    -- ③ 光标对齐「刚解锁的那一片」（不是最新通关的那一片 ——
    --    通关后玩家想点的正是刚解锁的下一片）
    local cursor = utils.clamp(state.mapUnlockMax or 1, 1, total)
    state.mapCursor = cursor

    if state.mapWorld then
        for i = 1, total do refreshNode(i) end
        refreshProgress()
    end
    -- 选关页上就平滑滑过去（看得见「自动对齐」）；入场动画还没完 / 不在选关页时直接就位，
    -- 免得和 applyIntro 每帧写 mapWorld 的位置打架。
    if state.mapOpen and state.mapIntroDone then
        M.scrollToLevel(cursor, true)
    else
        M.scrollToLevel(cursor, false)
    end
    return cursor
end

function M.moveCursor(dx)
    if not state.mapOpen then return end
    local G = geom()
    local i = utils.clamp((state.mapCursor or 1) + (dx or 0), 1, G.n)
    if i == state.mapCursor then
        -- 到头了：晃一下地图，给个「走不动」的反馈
        local shake = (dx or 1) * 6 * G.k
        if state.mapWorld then utils.setPos(state.mapWorld, state.mapScroll + shake, 0) end
        return
    end
    setCursor(i, true)
    audio.playClick()
end

function M.confirm()
    M.enterCursor()
end

function M.getCursor()
    return state.mapCursor or 1
end

function M.setActions(t)
    if type(t) == "table" then M.actions = t end
end

function M.isUnlocked(i)
    return isUnlocked(math.floor(tonumber(i) or 0))
end

return M
