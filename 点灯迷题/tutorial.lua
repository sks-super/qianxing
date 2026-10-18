-- ================================================================
-- 点灯迷题 图文教程（夏日版）
-- ================================================================
-- ★ 不做「生硬的纯文字弹窗」：整本教程是用基础图元（纯色矩形 + 文本）
--   在面板里拼出来的 2D 图文页 —— 每页上半是棋盘示意图（真的用色块画棋盘），
--   下半是讲解文字，5 页逐层引入规则。
--
--   示意图的数据结构（art）：
--     map    —— 逐行字符串，每个字符是一个格子（空格 = 该位置不放格子）
--     legend —— 字符 → 配色键（unlit / lit / accent / glow ...）
--     cell / gap —— 单格边长与间距
--   30 个色块控件一次性建好，翻页时只改「位置 / 大小 / 颜色 / 显隐」。
--
-- ★★ 分层（与 TickHop 一致）：**只用 containerTutorial 一个容器**，容器内按
--    「遮罩 → 面板 → 示意图凹槽 → 文字 → 色块 → 按钮底 → 按钮字 → 点击区」创建。
--    ★ 特别注意：按钮底必须建在按钮字之前，否则底图会把按钮字压住。
-- ================================================================

---@diagnostic disable: undefined-global

local M = {}
local state = require("default_import_file/state")
local config = require("default_import_file/config")
local utils = require("default_import_file/utils")
local fx = require("default_import_file/fx")

-- ★ 最多用到的示意图格子数 = 5 行 × 6 列（两幅小图并排时为 3 行 × 7 列 = 21）
local MAX_CELLS = 30
local MAX_ANNS = 3
local PAGE_ANIM = 0.24        -- 翻页动效时长（秒）

-- ================================================================
-- ★ 教程页数据（改文案 / 改示意图只动这里）
-- ================================================================
local LEGEND_STD = { ["."] = "unlit", ["o"] = "lit", ["X"] = "accent", ["+"] = "glow" }

local PAGES = {
    -- ① 目标 --------------------------------------------------------
    {
        title = "① 目标：把所有灯熄灭",
        lines = {
            "棋盘是 5 行 6 列，一共 30 盏灯。",
            "点亮的灯发黄光，熄灭的灯是暗的。",
            "把 30 盏灯全部熄灭 —— 就过关。",
        },
        caption = "开局长这样：几盏灯亮着，其余是暗的",
        art = {
            map = {
                "......",
                "......",
                ".o....",
                "ooo...",
                ".o....",
            },
            legend = LEGEND_STD,
        },
        anns = {},
    },
    -- ② 规则 --------------------------------------------------------
    {
        title = "② 点一颗灯，牵动五格",
        lines = {
            "点一颗灯：它自己 + 上下左右四格一起翻转。",
            "亮变灭、灭变亮，一按就是一下。",
            "边缘和角上的灯牵动更少（角上只有 3 格）。",
        },
        caption = "黄色 = 你点的灯；橙色 = 被它连带翻转的邻居",
        art = {
            map = {
                "......",
                "..+...",
                ".+X+..",
                "..+...",
                "......",
            },
            legend = LEGEND_STD,
        },
        anns = {},
    },
    -- ③ 抵消 --------------------------------------------------------
    {
        title = "③ 同一颗灯点两次 = 没点",
        lines = {
            "对同一颗灯点两次，它和邻居一起翻了两次，回到原样。",
            "所以解法就是「找出该点哪几颗灯」，每颗只点一次。",
            "关卡难度 = 需要点的灯的颗数（1 ~ 12 颗）。",
        },
        caption = "左边是点过一次的样子，再点同一颗就回到右边的全灭",
        art = {
            map = {
                ".o. ...",
                "oXo ...",
                ".o. ...",
            },
            legend = LEGEND_STD,
        },
        anns = {
            { x = 0, y = 0, text = "→", size = 30, colorKey = "dim" },
        },
    },
    -- ④ 思路 --------------------------------------------------------
    {
        title = "④ 从角落开始推",
        lines = {
            "角上的灯只牵动 3 格，最容易推断该不该点。",
            "定下一颗，再顺着它影响到的邻居往外推，一层层解开。",
            "实在卡住就退回选关换一关，或重看这本教程。",
        },
        caption = "角上的灯只牵动 3 格，是最好下手的突破口",
        art = {
            map = {
                "X+....",
                "+.....",
                "......",
                "......",
                "......",
            },
            legend = LEGEND_STD,
        },
        anns = {},
    },
    -- ⑤ 流程 --------------------------------------------------------
    {
        title = "⑤ 操作与流程",
        lines = {
            "选关界面点一张卡片（或按空格）进入关卡。",
            "关卡里的棋盘是 3D 的，用光标点击方块翻转灯光。",
            "全灭即通关，弹出结算面板 —— 可重玩 / 下一关 / 返回选关。",
        },
        caption = "全部熄灭的瞬间，服务器判定过关并弹出结算",
        art = {
            map = {
                "......",
                "......",
                "......",
                "......",
                "......",
            },
            legend = LEGEND_STD,
        },
        anns = {},
    },
}

-- ================================================================
-- 布局
-- ================================================================
local function panelSize()
    local cw = state.canvasW or config.DEFAULT_VIEW_WIDTH or 800
    local ch = state.canvasH or config.DEFAULT_VIEW_HEIGHT or 600
    local pw = math.min(config.DEFAULT_TUTORIAL_PANEL_W or 740, cw - 32)
    local ph = math.min(config.DEFAULT_TUTORIAL_PANEL_H or 548, ch - 32)
    if pw < 300 then pw = cw end
    if ph < 240 then ph = ch end
    return pw, ph
end

local function addNode(ctrl)
    if ctrl then
        state.tutNodes[#state.tutNodes + 1] = ctrl
    end
    return ctrl
end

-- ================================================================
-- ★ 预创建（OnStart 调用一次）
-- ================================================================
function M.init()
    if state.tutPanel then return true end
    if not state.containerTutorial then return false end
    if not state.rectPrefabId or state.rectPrefabId <= 0 then return false end

    local pal = utils.resolvePalette(state.currentLevelConfig)
    local pw, ph = panelSize()
    local cw = state.canvasW or config.DEFAULT_VIEW_WIDTH or 800
    local ch = state.canvasH or config.DEFAULT_VIEW_HEIGHT or 600
    local titleSize = config.DEFAULT_TUTORIAL_TITLE_SIZE or 34
    local textSize = config.DEFAULT_TUTORIAL_TEXT_SIZE or 21
    local hintSize = config.DEFAULT_TUTORIAL_HINT_SIZE or 16

    -- ① 全屏遮罩 → 面板投影 → 面板底 → 示意图凹槽
    state.tutOverlay = addNode(utils.createControl(state.rectPrefabId, 0, 0, cw + 500, ch + 500,
        utils.hexToColorA(pal.overlay, config.DEFAULT_TUTORIAL_OVERLAY_ALPHA or 170),
        state.containerTutorial))
    state.tutPanelShadow = addNode(utils.createControl(state.rectPrefabId, 6, -8, pw, ph,
        utils.hexToColorA(pal.shadow, 120), state.containerTutorial))
    state.tutPanelEdge = addNode(utils.createControl(state.rectPrefabId, 0, 0, pw + 12, ph + 12,
        utils.hexToColor(pal.line), state.containerTutorial))
    state.tutPanel = addNode(utils.createControl(state.rectPrefabId, 0, 0, pw, ph,
        utils.hexToColor(pal.panel), state.containerTutorial))
    addNode(utils.createControl(state.rectPrefabId, 0, ph / 2 - 9, pw - 40, 10,
        utils.hexToColor(pal.accent), state.containerTutorial))          -- 顶部橙汁横带
    state.tutStageCY = 80
    state.tutStage = addNode(utils.createControl(state.rectPrefabId, 0, state.tutStageCY, pw - 80, 220,
        utils.hexToColor(pal.panelDeep), state.containerTutorial))

    -- ② 文字（标题 / 页码 / 图注 / 正文）
    state.tutTitle = addNode(utils.createText(0, ph / 2 - 46, pw - 60, 44, "",
        utils.hexToColor(pal.text), titleSize, state.containerTutorial))
    state.tutFooter = addNode(utils.createText(-(pw / 2 - 62), ph / 2 - 46, 90, 30, "",
        utils.hexToColor(pal.dim), hintSize, state.containerTutorial))
    state.tutCaption = addNode(utils.createText(0, state.tutStageCY - 132, pw - 80, 28, "",
        utils.hexToColor(pal.dim), hintSize, state.containerTutorial))
    for i = 1, 3 do
        state.tutLines[i] = addNode(utils.createText(
            0, -94 - (i - 1) * 34, pw - 80, 30, "",
            utils.hexToColor(pal.text), textSize, state.containerTutorial))
    end

    -- ③ 示意图格子池 + 注解
    local cs = config.DEFAULT_TUTORIAL_CELL or 34
    for i = 1, MAX_CELLS do
        state.tutCells[i] = addNode(utils.createControl(state.rectPrefabId, 0, 0, cs, cs,
            utils.hexToColor(pal.unlit), state.containerTutorial))
    end
    for i = 1, MAX_ANNS do
        state.tutAnns[i] = addNode(utils.createText(0, 0, 120, 40, "",
            utils.hexToColor(pal.dim), 24, state.containerTutorial))
    end

    -- ④ 底部按钮：先底、再字、最后点击区（顺序不能反，否则底图压住字）
    local bw = config.DEFAULT_TUTORIAL_BTN_W or 150
    local bh = config.DEFAULT_TUTORIAL_BTN_H or 50
    local by = -ph / 2 + 52

    local function makeTutButton(x, text, keyHex, boxW)
        local bg = addNode(utils.createControl(state.rectPrefabId, x, by, boxW, bh,
            utils.hexToColor(keyHex), state.containerTutorial))
        local label = addNode(utils.createText(x, by, boxW, bh, text,
            utils.hexToColor(pal.text), hintSize + 2, state.containerTutorial))
        local hit = utils.createHit(x, by, boxW, bh, state.containerTutorial, nil, bg)
        if hit then
            state.tutNodes[#state.tutNodes + 1] = hit
            utils.bindHover(hit,
                function() pcall(function() bg:SetSizeDelta(boxW + 6, bh + 6) end) end,
                function() pcall(function() bg:SetSizeDelta(boxW, bh) end) end)
        end
        return bg, label, hit
    end

    local gap = 20
    local prevX = -(bw + gap)
    local nextX = (bw + gap)
    state.tutPrevBg, state.tutPrev, state.tutPrevHit =
        makeTutButton(prevX, "← 上一页", pal.panelDeep, bw)
    state.tutCloseBg, state.tutClose, state.tutCloseHit =
        makeTutButton(0, "关闭", pal.panelDeep, bw)
    state.tutNextBg, state.tutNext, state.tutNextHit =
        makeTutButton(nextX, "下一页 →", pal.accent, bw)

    local function bind(hit, fn)
        if not hit then return end
        pcall(function()
            hit:AddCursorEventListener(Enum.CursorEventType.CursorDown, function()
                if state.tutorialOpen then fn() end
            end)
        end)
    end
    bind(state.tutPrevHit, function() M.prev() end)
    bind(state.tutCloseHit, function() M.close() end)
    bind(state.tutNextHit, function() M.next() end)

    state.tutPageCount = #PAGES
    M.setVisible(false)
    return true
end

-- ================================================================
-- ★ 画示意图（dx = 翻页动效的水平偏移）
-- ================================================================
local function renderArt(page, pal, dx)
    dx = dx or 0
    local art = page.art or {}
    local cs = (art.cell and art.cell > 0) and art.cell
        or (config.DEFAULT_TUTORIAL_CELL or 34)
    local gap = (art.gap and art.gap >= 0) and art.gap or (config.DEFAULT_TUTORIAL_GAP or 6)
    local map = art.map or {}
    local legend = art.legend or {}

    local rows = #map
    local maxLen = 0
    for _, line in ipairs(map) do
        if #line > maxLen then maxLen = #line end
    end
    local totalW = maxLen * cs + math.max(0, maxLen - 1) * gap
    local totalH = rows * cs + math.max(0, rows - 1) * gap
    local cy = state.tutStageCY or 0

    local used = 0
    for r = 1, rows do
        local line = map[r]
        for c = 1, maxLen do
            local ch = line:sub(c, c)
            local key = legend[ch]
            if key and used < MAX_CELLS then
                used = used + 1
                local ctrl = state.tutCells[used]
                if ctrl then
                    local x = -totalW / 2 + cs / 2 + (c - 1) * (cs + gap) + dx
                    local y = cy + totalH / 2 - cs / 2 - (r - 1) * (cs + gap)
                    utils.setSize(ctrl, cs, cs)
                    utils.setPos(ctrl, x, y)
                    utils.setAlpha(ctrl, pal[key] or pal.unlit, 255)
                    utils.setVisible(ctrl, true)
                end
            end
        end
    end
    for i = used + 1, MAX_CELLS do
        utils.setVisible(state.tutCells[i], false)
    end

    local anns = page.anns or {}
    for i = 1, MAX_ANNS do
        local a = anns[i]
        if a then
            local ctrl = state.tutAnns[i]
            if ctrl then
                utils.setSize(ctrl, math.max(120, cs * 3), cs + 10)
                utils.setPos(ctrl, (a.x or 0) + dx, cy + (a.y or 0))
                utils.setText(ctrl, a.text or "")
                utils.setTextColor(ctrl, pal[a.colorKey or "dim"] or pal.dim, 235)
                utils.setFontSize(ctrl, a.size or 24)
                utils.setVisible(ctrl, true)
            end
        else
            utils.setVisible(state.tutAnns[i], false)
        end
    end
end

-- ================================================================
-- ★ 刷新当前页
-- ================================================================
function M.refresh()
    if not state.tutPanel then return end
    local pal = utils.resolvePalette(state.currentLevelConfig)
    local count = math.max(1, state.tutPageCount or #PAGES)
    local page = math.floor(tonumber(state.tutPage) or 1)
    if page < 1 then page = 1 elseif page > count then page = count end
    state.tutPage = page

    local data = PAGES[page] or PAGES[1]
    utils.setText(state.tutTitle, data.title or "")
    utils.setTextColor(state.tutTitle, pal.text, 255)
    utils.setText(state.tutFooter, string.format("%d / %d", page, count))
    utils.setTextColor(state.tutFooter, pal.dim, 235)
    utils.setText(state.tutCaption, data.caption or "")
    utils.setTextColor(state.tutCaption, pal.dim, 235)

    local lines = data.lines or {}
    for i = 1, 3 do
        local ctrl = state.tutLines[i]
        if ctrl then
            utils.setText(ctrl, lines[i] or "")
            utils.setTextColor(ctrl, pal.text, 245)
        end
    end

    renderArt(data, pal, state.tutArtDX or 0)

    -- 按钮：首页禁用「上一页」；末页「下一页」变「知道了」
    utils.setText(state.tutPrev, "← 上一页")
    utils.setTextColor(state.tutPrev, page > 1 and pal.text or pal.line, 255)
    utils.setAlpha(state.tutPrevBg, pal.panelDeep, page > 1 and 255 or 130)
    utils.setText(state.tutNext, (page < count) and "下一页 →" or "知道了")
    utils.setTextColor(state.tutNext, pal.accentText, 255)
    utils.setAlpha(state.tutNextBg, pal.accent, 255)
    utils.setText(state.tutClose, "关闭")
    utils.setTextColor(state.tutClose, pal.text, 255)
    utils.setAlpha(state.tutCloseBg, pal.panelDeep, 255)
    utils.setAlpha(state.tutPanel, pal.panel, 255)
    utils.setAlpha(state.tutPanelEdge, pal.line, 255)
    utils.setAlpha(state.tutPanelShadow, pal.shadow, 120)
    utils.setAlpha(state.tutStage, pal.panelDeep, 255)
end

-- ================================================================
-- ★ 每帧：翻页时示意图从右侧滑入
-- ================================================================
function M.update(dt)
    if not state.tutPanel or not state.tutorialOpen then return end
    if (state.tutAnimT or 0) >= PAGE_ANIM then return end
    dt = tonumber(dt) or 0
    if dt <= 0 then return end
    state.tutAnimT = math.min(PAGE_ANIM, (state.tutAnimT or 0) + dt)
    local k = state.tutAnimT / PAGE_ANIM
    local u = 1 - k
    local e = 1 - u * u * u
    state.tutArtDX = 30 * u                     -- 示意图水平滑入
    local pal = utils.resolvePalette(state.currentLevelConfig)
    renderArt(PAGES[state.tutPage] or PAGES[1], pal, state.tutArtDX)
    -- 文字同向滑入并淡入
    local _, ph = panelSize()
    local dx = 26 * u
    local a = 255 * (0.25 + 0.75 * e)
    utils.setPos(state.tutTitle, dx, ph / 2 - 46)
    utils.setTextColor(state.tutTitle, pal.text, a)
    for i = 1, 3 do
        local c = state.tutLines[i]
        if c then
            utils.setPos(c, dx, -94 - (i - 1) * 34)
            utils.setTextColor(c, pal.text, a * 0.96)
        end
    end
end

-- ================================================================
-- ★ 显隐
-- ================================================================
function M.setVisible(v)
    state.tutorialOpen = v and true or false
    utils.setVisibleAll(state.tutNodes, v)
end

-- ================================================================
-- ★ 开关 / 翻页
-- ================================================================
function M.open(page)
    if not state.tutPanel and not M.init() then return false end
    state.tutPage = page or state.tutPage or 1
    state.tutAnimT = PAGE_ANIM          -- 直接落在稳定态，避免打开时就滑动
    state.tutArtDX = 0
    M.setVisible(true)
    M.refresh()
    return true
end

function M.close()
    M.setVisible(false)
end

function M.isOpen()
    return state.tutorialOpen == true
end

function M.setPage(p)
    if not state.tutorialOpen then return end
    local count = math.max(1, state.tutPageCount or #PAGES)
    local np = math.floor(tonumber(p) or 1)
    if np < 1 then np = 1 elseif np > count then np = count end
    if np == state.tutPage then return end
    state.tutPage = np
    state.tutAnimT = 0                  -- 触发一次翻页滑入
    local us = utils.uiScale()          -- ★ 本层容器整体放大过，粒子世界坐标要跟着乘
    fx.spawn(0, (state.tutStageCY or 0) * us,
        { n = 14, keys = { "juice1", "juice3", "juice4" }, spread = 360,
          speed = 260 * us, life = 0.55, size = 8 * us, gravity = 500 * us })
    M.refresh()
end

function M.next()
    local count = math.max(1, state.tutPageCount or #PAGES)
    if (state.tutPage or 1) >= count then
        M.close()
        return
    end
    M.setPage((state.tutPage or 1) + 1)
end

function M.prev()
    M.setPage((state.tutPage or 1) - 1)
end

return M
