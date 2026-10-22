-- ================================================================
-- 瓦雷莎的果园救急 · 教程（原「教学卡 / 玩法手册」，用户要求改名）
-- ================================================================
-- ★ 设计原则（用户要求）：
--   · 进前 5 片果园先弹本关教程，且可往前翻看之前各关的教程；
--   · 教程按钮（原「手册」）从第 1 页开始，可一直翻到当前关的教程；
--   · 示意图只保留「黄 / 红」两色矩形方格（黄 = 水果、红 = 果汁），
--     「需要点击来复原的点位」用亮蓝色矩形环框框住，不再靠颜色区分。
--   · 一课一图两句话，不摊开整本图册。
--
-- ★ 分层：只用 containerGuide 一个容器，创建顺序
--   「遮罩 → 投影 → 描边 → 面板 → 凹槽 → 标题/页码 → 图注/正文
--    → 格子 → 蓝环框 → 按钮底 → 按钮字 → 点击区」。
-- ================================================================

---@diagnostic disable: undefined-global

local M = {}
local state = require("default_import_file/state")
local config = require("default_import_file/config")
local utils = require("default_import_file/utils")
local fx = require("default_import_file/fx")
local audio = require("default_import_file/audio")

local MAX_CELLS = 30
local PAGE_ANIM = 0.22
local INTRO = 0.20

local LEGEND = {
    ["."] = "guideFruit",   -- 黄色方格 = 水果（好果子）
    ["o"] = "guideJuice",   -- 红色方格 = 果汁（待清理）
}

local function addNode(ctrl)
    if ctrl then
        state.guideNodes[#state.guideNodes + 1] = ctrl
    end
    return ctrl
end

-- ★ 圆角块（utils.roundBox 返回的 { root, parts }）整体登记，方便统一显隐
local function addBox(box)
    if not box then return nil end
    addNode(box.root)
    for i = 1, #box.parts do addNode(box.parts[i]) end
    return box
end

local function panelSize()
    local cw = state.canvasW or config.DEFAULT_VIEW_WIDTH or 800
    local ch = state.canvasH or config.DEFAULT_VIEW_HEIGHT or 600
    local pw = math.min(config.DEFAULT_GUIDE_PANEL_W or 640, cw - 40)
    local ph = math.min(config.DEFAULT_GUIDE_PANEL_H or 452, ch - 40)
    if pw < 300 then pw = cw end
    if ph < 280 then ph = ch end
    return pw, ph
end

-- ================================================================
-- ★★ 示意图排版：格子边长从「凹槽可用空间」反推（用户反馈格子戳出圆角矩形）
-- ================================================================
-- 旧算法有两个错，叠在一起才让四角露出来：
--   ① 网格高 = 5*44 + 4*8 = 252，凹槽高 256 —— 上下只留 2px，**小于圆角半径 14**，
--      四角的方格正好压在圆弧上，看着就是「方格超出了圆角矩形」；
--   ② gap 又乘了一次 uiScale，而 containerGuide 整层已经被 uiScale 缩放过 ——
--      1088 宽下 gap 变 8*1.27=10.1，网格高 260.5 > 256，真的溢出。
-- 现在：先按「行数/列数 + 最小边距 pad」反推格子边长，再由格子反推凹槽尺寸，
--      网格与凹槽永远留出 pad（> 圆角半径）的边距；gap 不再二次缩放。
local CELL = 44          -- 单格边长（init 里按空间反推后覆盖）
local GAP = 8            -- 格间距
local STAGE_W = 300      -- 凹槽宽
local STAGE_H = 250      -- 凹槽高
local STAGE_CY = 44      -- 凹槽中心 y
local STAGE_R = 14       -- 凹槽圆角半径

local function computeArtLayout(pw)
    local rows = config.DEFAULT_ROWS or 5
    local cols = config.DEFAULT_COLS or 6
    GAP = config.DEFAULT_GUIDE_GAP or 8
    local pad = math.max(STAGE_R + 2, 16)          -- 网格离凹槽边的最小距离
    local maxW = math.min(pw - 84, 360)
    local maxH = 256
    local csH = math.floor((maxH - pad * 2 - (rows - 1) * GAP) / rows)
    local csW = math.floor((maxW - pad * 2 - (cols - 1) * GAP) / cols)
    CELL = math.max(18, math.min(config.DEFAULT_GUIDE_CELL or 44, csH, csW))
    STAGE_W = cols * CELL + (cols - 1) * GAP + pad * 2
    STAGE_H = rows * CELL + (rows - 1) * GAP + pad * 2
end

-- ================================================================
-- 初始化
-- ================================================================
function M.init()
    if state.guidePanel then return true end
    if not state.containerGuide then return false end
    if not state.rectPrefabId or state.rectPrefabId <= 0 then return false end

    local pal = utils.palette()
    local pw, ph = panelSize()
    local cw = state.canvasW or config.DEFAULT_VIEW_WIDTH or 800
    local ch = state.canvasH or config.DEFAULT_VIEW_HEIGHT or 600
    local titleSize = config.DEFAULT_GUIDE_TITLE_SIZE or 27
    local textSize = config.DEFAULT_GUIDE_TEXT_SIZE or 18
    local hintSize = config.DEFAULT_GUIDE_HINT_SIZE or 15

    -- ★ 先算「格子多大 / 凹槽多大」，后面建格子、建蓝环框、画示意图全用同一套数字
    computeArtLayout(pw)

    state.guideOverlay = addNode(utils.createControl(state.rectPrefabId, 0, 0, cw + 520, ch + 520,
        utils.hexToColorA(pal.overlay, config.DEFAULT_GUIDE_OVERLAY_ALPHA or 150), state.containerGuide))
    -- ★ 面板三层全部圆角（投影 → 牌沿 → 牌面），用 roundBox 才能改尺寸做入场缩放。
    --   ★ 半透明会露「拼接缝」（重叠处被盖两次更实），所以投影改成
    --     「预混色 + alpha 255」——混的是遮罩色，视觉上和 42% 深的投影一样。
    local pr = math.min(26, ph * 0.09)
    state.guideShadow = addBox(utils.roundBox(7, -9, pw, ph, pr,
        utils.mixHex(pal.overlay, pal.shadow, 0.42), state.containerGuide))
    state.guideEdge = addBox(utils.roundBox(0, 0, pw + 12, ph + 12, pr + 4, pal.line, state.containerGuide))
    state.guidePanel = addBox(utils.roundBox(0, 0, pw, ph, pr, pal.panel, state.containerGuide))
    -- ★ 原来标题上方横着一条「超宽扁椭圆」（pw-40 × 9）当装饰横带：
    --   椭圆两端是圆弧、中间就成了一条粗线，实拍像一道画歪的刷痕 → 已有用户反馈太丑，去掉。
    --   （同款横带在 winUI.lua 也删了，两处保持一致）
    -- 顶部两颗小装饰：一颗果子（圆）+ 一颗小星（五角星模板）
    addNode(utils.circleC(-pw / 2 + 38, ph / 2 - 30, 16, 16, pal.fruit, 210, state.containerGuide))
    addNode(utils.starC(-pw / 2 + 58, ph / 2 - 24, 14, 14, pal.star, 210, state.containerGuide, true))

    -- ★ 凹槽尺寸由网格反推（见 computeArtLayout）：网格四边各留 pad 的边距，
    --   圆角半径永远小于 pad，所以格子不会再压在圆弧上。
    state.guideStage = addBox(utils.roundBox(0, STAGE_CY, STAGE_W, STAGE_H, STAGE_R,
        pal.panelDeep, state.containerGuide))

    state.guideTitle = addNode(utils.createText(0, ph / 2 - 38, pw - 56, 38, "",
        utils.hexToColor(pal.text), titleSize, state.containerGuide))
    state.guidePageText = addNode(utils.createText(pw / 2 - 52, ph / 2 - 38, 74, 26, "",
        utils.hexToColor(pal.dim), hintSize, state.containerGuide))
    state.guideCaption = addNode(utils.createText(0, -102, pw - 60, 26, "",
        utils.hexToColor(pal.dim), hintSize, state.containerGuide))
    for i = 1, 2 do
        state.guideLines[i] = addNode(utils.createText(0, -134 - (i - 1) * 34, pw - 60, 32, "",
            utils.hexToColor(pal.text), textSize, state.containerGuide))
    end

    local cs = CELL
    -- ★ 示意图格子是「矩形方格」：用户明确要求「黄 / 红」两色矩形，
    --   圆形果子挪到游戏地图上去了，这里要保持「棋盘格」的可读性。
    for i = 1, MAX_CELLS do
        state.guideCells[i] = addNode(utils.createControl(state.rectPrefabId, 0, 0, cs - 2, cs - 2,
            utils.hexToColor(pal.guideFruit), state.containerGuide))
    end
    -- ★ 亮蓝色矩形环框层：每格一个 holder + 4 根细条。
    --   语义 = 「这一课里需要点击来复原的点位」，和格子颜色解耦
    --   （同一批格子既可能是水果也可能是果汁，所以环必须单独一层）。
    -- ★★ 四根条必须按「外框内嵌」算位，不能各自压在格子中线上：
    --   横条中心 = ±(S/2 - th/2)，竖条中心 = ±(S/2 - th/2)，竖条高 = S - 2*th。
    --   原来横条 y=±S/2、竖条 x=±S/2 且高 = S-2*th 是从中心算的 →
    --   框的四个角各缺一块、两侧还探出半根厚度，放大看是个破框（踩过）。
    local th = math.max(3, 3.2 * utils.uiScale())
    local S = cs - 2
    local half = S * 0.5
    local edge = half - th * 0.5          -- 条子中心到格子中心的距离
    local runL = S - th * 2               -- 竖条长度（扣掉两条横条的厚度）
    for i = 1, MAX_CELLS do
        local holder = addNode(utils.createContainer(state.containerGuide, cs, cs))
        if holder then
            utils.setPos(holder, 0, 0)
            local c = utils.hexToColor(pal.ringBlue)
            local t1 = addNode(utils.createControl(state.rectPrefabId, 0,  edge, S, th, c, holder))
            local t2 = addNode(utils.createControl(state.rectPrefabId, 0, -edge, S, th, c, holder))
            local t3 = addNode(utils.createControl(state.rectPrefabId, -edge, 0, th, runL, c, holder))
            local t4 = addNode(utils.createControl(state.rectPrefabId,  edge, 0, th, runL, c, holder))
            state.guideRings[i] = { root = holder, parts = { t1, t2, t3, t4 } }
        end
    end

    -- 按钮：底 → 字 → 点击区（顺序不能反）
    -- ★ 圆角胶囊：外沿 + 钮面 + 顶部高光，装在一个容器里，hover 整块放大
    local bw = config.DEFAULT_GUIDE_BTN_W or 152
    local bh = config.DEFAULT_GUIDE_BTN_H or 50
    local by = -210
    local function makeBtn(x, fillHex)
        local btn = addNode(utils.createContainer(state.containerGuide, bw + 28, bh + 28))
        utils.setPos(btn, x, by)
        addBox(utils.roundBox(2, -6, bw, bh, bh * 0.42,
            utils.mixHex(fillHex, pal.shadow, 0.34), btn))
        local face = addBox(utils.roundBox(0, 0, bw - 6, bh - 6, (bh - 6) * 0.42, fillHex, btn))
        -- ★ 按钮面上原来还压了一个白色扁椭圆当「高光」，胶囊本身已经很圆润，
        --   再加一个椭圆就多出一团白斑（用户反馈的「三个椭圆」之一）→ 去掉。
        local lab = addNode(utils.createText(0, 0, bw, bh, "",
            utils.hexToColor(pal.text), textSize, btn))
        local hit = utils.createHit(x, by, bw + 10, bh + 10, state.containerGuide)
        if hit then
            state.guideNodes[#state.guideNodes + 1] = hit
            utils.bindHover(hit,
                function() utils.setScale(btn, 1.06) end,
                function() utils.setScale(btn, 1.0) end)
        end
        return { bg = face, label = lab, hit = hit, root = btn }
    end

    state.guideButtons[1] = makeBtn(-(bw + 18) / 2, pal.panelDeep)
    state.guideButtons[2] = makeBtn((bw + 18) / 2, pal.accent)

    -- 点击区绑定具体动作
    local function bindTap(btn, fn)
        if btn and btn.hit then
            pcall(function()
                btn.hit:AddCursorEventListener(Enum.CursorEventType.CursorDown, function()
                    if not state.guideOpen then return end
                    audio.playClick()
                    fn()
                end)
            end)
        end
    end
    bindTap(state.guideButtons[1], function() M.onLeft() end)
    bindTap(state.guideButtons[2], function() M.onRight() end)

    M.setVisible(false)
    return true
end

-- ================================================================
-- 由「要点的点位」反推盘面
-- ================================================================
-- ★★ 这条是硬规则（用户指出过）：一格的最终颜色只由「被十字覆盖的次数的奇偶」决定 ——
--   覆盖奇数次 = 翻过 = 果汁（红），偶数次（含 0 次、被两个十字同时覆盖） = 原样 = 水果（黄）。
--   手写示意图迟早出错（叠加处忘了变回红），所以这里**不再允许手写 map**：
--   盘面一律从 art.rings 现算，蓝框点哪儿、盘面就是点完之后的真实结果。
--   ★★ 新增 art.flips：只参与「算盘面」、不画蓝框。
--      用途 = 「先看清果汁长什么样」这类页：盘面要和本关一样，但这一页还不用点。
local function deriveArt(art)
    local rows = config.DEFAULT_ROWS or 5
    local cols = config.DEFAULT_COLS or 6
    local flip = {}
    for r = 1, rows do
        flip[r] = {}
        for c = 1, cols do flip[r][c] = false end
    end
    for _, p in ipairs(art.flips or art.rings or {}) do
        local r, c = math.floor(tonumber(p[1]) or 0), math.floor(tonumber(p[2]) or 0)
        local cross = { { r, c }, { r - 1, c }, { r + 1, c }, { r, c - 1 }, { r, c + 1 } }
        for _, q in ipairs(cross) do
            local rr, cc = q[1], q[2]
            if rr >= 1 and rr <= rows and cc >= 1 and cc <= cols then
                flip[rr][cc] = not flip[rr][cc]   -- XOR：同一个格子被翻两次就变回原样
            end
        end
    end
    local map = {}
    for r = 1, rows do
        local line = ""
        for c = 1, cols do
            line = line .. (flip[r][c] and "o" or ".")
        end
        map[r] = line
    end
    return map
end

-- ================================================================
-- 画示意图
-- ================================================================
local function renderArt(page, pal, dx)
    dx = dx or 0
    local art = page.art or {}
    local rings = art.rings or {}
    local map = art.map or deriveArt(art)
    local cs = CELL
    -- ★ gap 不再乘 uiScale：containerGuide 这一层已经被 SetLocalScale(uiScale) 缩放过，
    --   再乘一次等于放大平方 —— 大画布上网格会胖出凹槽（user 反馈的溢出就是这么来的）。
    local gap = GAP

    local rows = #map
    local maxLen = 0
    for _, line in ipairs(map) do
        if #line > maxLen then maxLen = #line end
    end
    local totalW = maxLen * cs + math.max(0, maxLen - 1) * gap
    local totalH = rows * cs + math.max(0, rows - 1) * gap
    local cy = STAGE_CY

    -- ★ 凹槽跟着内容收缩：序章「三颗果实 = 三片果园」这类示意页只有一行方格，
    --   若仍按 5×6 的满槽画，中间会空一大片、像坏了。这里按内容留 pad 收缩，
    --   但最小不低于「3 行 / 3 列」的观感尺寸（再小就像个标签而不是棋盘了）。
    do
        local pad = math.max(STAGE_R + 2, 16)
        local minW = math.min(STAGE_W, cs * 3 + gap * 2 + pad * 2)
        local minH = math.min(STAGE_H, cs * 3 + gap * 2 + pad * 2)
        local sw = math.max(minW, math.min(STAGE_W, totalW + pad * 2))
        local sh = math.max(minH, math.min(STAGE_H, totalH + pad * 2))
        utils.setBoxSize(state.guideStage, sw, sh)
        utils.setPos(state.guideStage.root, 0, cy)
    end

    -- 格子：黄 = 水果 / 红 = 果汁（只此两色）
    local used = 0
    for r = 1, rows do
        local line = map[r]
        for c = 1, maxLen do
            local ch = line:sub(c, c)
            local key = LEGEND[ch]
            if key and used < MAX_CELLS then
                used = used + 1
                local ctrl = state.guideCells[used]
                if ctrl then
                    local x = -totalW / 2 + cs / 2 + (c - 1) * (cs + gap) + dx
                    local y = cy + totalH / 2 - cs / 2 - (r - 1) * (cs + gap)
                    utils.setSize(ctrl, cs - 2, cs - 2)
                    utils.setPos(ctrl, x, y)
                    utils.setColor(ctrl, key, 255)
                    utils.setVisible(ctrl, true)
                end
            end
        end
    end
    for i = used + 1, MAX_CELLS do
        utils.setVisible(state.guideCells[i], false)
        utils.setVisible(state.guideRings[i] and state.guideRings[i].root, false)
    end

    -- 亮蓝矩形环框：art.rings = { {行, 列}, ... }（1 起始）
    for i = 1, MAX_CELLS do
        local ring = state.guideRings[i]
        local pos = rings[i]
        if ring and pos and pos[1] and pos[2] then
            local x = -totalW / 2 + cs / 2 + (pos[2] - 1) * (cs + gap) + dx
            local y = cy + totalH / 2 - cs / 2 - (pos[1] - 1) * (cs + gap)
            utils.setPos(ring.root, x, y)
            utils.setVisible(ring.root, true)
        elseif ring then
            utils.setVisible(ring.root, false)
        end
    end
end

-- ================================================================
-- 刷新当前页
-- ================================================================
function M.refresh()
    if not state.guidePanel then return end
    local pal = utils.palette()
    local pages = state.guidePages or {}
    local count = math.max(1, #pages)
    local p = utils.clamp(math.floor(tonumber(state.guidePage) or 1), 1, count)
    state.guidePage = p
    local data = pages[p] or {}

    utils.setText(state.guideTitle, data.title or "")
    utils.setTextColor(state.guideTitle, pal.text, 255)
    utils.setText(state.guidePageText, count > 1 and string.format("%d / %d", p, count) or "")
    utils.setTextColor(state.guidePageText, pal.dim, 230)
    utils.setText(state.guideCaption, data.caption or "")
    utils.setTextColor(state.guideCaption, pal.dim, 235)

    local lines = data.lines or {}
    for i = 1, 2 do
        local ctrl = state.guideLines[i]
        if ctrl then
            utils.setText(ctrl, lines[i] or "")
            utils.setTextColor(ctrl, pal.text, 245)
        end
    end

    renderArt(data, pal, 0)

    -- 按钮文案：教程 = [关闭] [下一页 / 知道了]（原 lesson 的「跳过 / 开始指挥」已并入）
    local b1, b2 = state.guideButtons[1], state.guideButtons[2]
    utils.setText(b1.label, "关闭")
    utils.setText(b2.label, (p < count) and "下一页 →" or "知道了")
    utils.setBoxColor(b1.bg, pal.panelDeep, 255)
    utils.setBoxColor(b2.bg, pal.accent, 255)
    utils.setTextColor(b1.label, pal.text, 255)
    utils.setTextColor(b2.label, pal.accentText, 255)

    utils.setBoxColor(state.guidePanel, pal.panel, 255)
    utils.setBoxColor(state.guideEdge, pal.line, 255)
    utils.setBoxColor(state.guideShadow, utils.mixHex(pal.overlay, pal.shadow, 0.42), 255)
    utils.setBoxColor(state.guideStage, pal.panelDeep, 255)
end

-- ================================================================
-- 打开
-- ================================================================
-- ★★ 页簿怎么拼（一课可以有多页；序章单独一组）：
--   collectPages(uptoLevel, withPrologue) → pages, starts
--     pages  = 拼好的整叠页（序章在最前，然后第 1..uptoLevel 课的页顺序摊开）
--     starts = starts[lv] 第 lv 课的第一页在整叠里的下标
--   ★ 为什么不是「一课一页」了：新手反馈原来的两句文言文看不懂，
--     第 1 课要先把「目标 / 操作 / 过关」分开讲，于是一课拆成多页。
-- ================================================================
local function collectPages(uptoLevel, withPrologue)
    local pages, starts = {}, {}
    if withPrologue then
        local pro = config.getProloguePages()
        for i = 1, #pro do pages[#pages + 1] = pro[i] end
    end
    for lv = 1, uptoLevel do
        local list = config.getLessonPages(lv)
        starts[lv] = #pages + 1
        for i = 1, #list do pages[#pages + 1] = list[i] end
    end
    return pages, starts
end

-- 真正把一叠页摊到面板上（其它 openXxx 都走这里）
local function openPages(pages, start, level)
    if not state.guidePanel and not M.init() then return false end
    if not pages or #pages == 0 then return false end
    state.guideKind = "tutorial"
    state.guideLevel = level or 0
    state.guidePages = pages
    state.guidePage = utils.clamp(math.floor(tonumber(start) or 1), 1, #pages)
    M.setVisible(true)
    return true
end

-- 只看「第 level 课」，但可以往前翻到第 1 课（进关自动弹的就是这个）
function M.openLevelLessons(level)
    local total = math.max(1, config.getLessonCount())
    local n = utils.clamp(math.floor(tonumber(level) or total), 1, total)
    local pages, starts = collectPages(n, false)
    return openPages(pages, starts[n] or 1, n)
end

-- 完整图册：序章 + 第 1..level 课，从第 1 页（序章）开始
function M.openHandbook(level)
    local total = math.max(0, config.getLessonCount())
    local n = utils.clamp(math.floor(tonumber(level) or total), 0, total)
    local pages = collectPages(n, true)
    return openPages(pages, 1, n)
end

-- 只摊开序章（地图首屏第一次进来时自动弹）
--   ★★ 这是**唯一**把 guideKind 设成 "prologue" 的地方：只有它被关掉，
--      才触发地图上「进入果园」按钮的点灯引导（见 M.setVisible 的 else 分支）。
--      图册（H / 教程按钮）里虽然也含序章页，但 kind 是 "tutorial"，不会触发。
function M.openPrologue()
    local pages = {}
    local pro = config.getProloguePages()
    for i = 1, #pro do pages[i] = pro[i] end
    if not openPages(pages, 1, 0) then return false end
    state.guideKind = "prologue"
    return true
end

-- 兼容旧调用：openTutorial(from, upto) = 整叠拼到第 upto 课，从第 from 课的第一页开始
function M.openTutorial(from, upto)
    local total = math.max(1, config.getLessonCount())
    local hi = utils.clamp(math.floor(tonumber(upto) or total), 1, total)
    local lo = utils.clamp(math.floor(tonumber(from) or hi), 1, hi)
    local pages, starts = collectPages(hi, false)
    return openPages(pages, starts[lo] or 1, lo)
end

-- 兼容旧调用：等价于只看这一课
function M.openLesson(level)
    return M.openLevelLessons(level)
end

function M.close()
    M.setVisible(false)
end

function M.isOpen()
    return state.guideOpen == true
end

-- ================================================================
-- 翻页 / 按钮
-- ================================================================
function M.setPage(p)
    local count = math.max(1, #(state.guidePages or {}))
    local np = utils.clamp(math.floor(tonumber(p) or 1), 1, count)
    if np == state.guidePage then return end
    state.guidePage = np
    state.guideAnimT = 0
    local us = utils.uiScale()
    fx.spawn(0, 44 * us, { n = 12, keys = { "juice1", "juice3", "juice4" },
        spread = 360, speed = 240 * us, life = 0.5, size = 8 * us, gravity = 500 * us })
    M.refresh()
end

function M.next()
    local count = math.max(1, #(state.guidePages or {}))
    if (state.guidePage or 1) >= count then
        M.close()
        return
    end
    M.setPage((state.guidePage or 1) + 1)
end

function M.prev()
    M.setPage((state.guidePage or 1) - 1)
end

function M.onLeft()
    if (state.guidePage or 1) > 1 then
        M.prev()
    else
        M.close()
    end
end

function M.onRight()
    if (state.guidePage or 1) < #(state.guidePages or {}) then
        M.next()
    else
        M.close()
    end
end

-- ================================================================
-- 显隐 / 入场
-- ================================================================
function M.setVisible(v)
    state.guideOpen = v and true or false
    utils.setVisibleAll(state.guideNodes, v)
    if v then
        state.guideAnimT = PAGE_ANIM        -- 翻页动效先落在稳定态
        state.guideIntroT = 0               -- 面板入场从头播
        M.applyIntro(0)
        M.refresh()
        local pw, ph = panelSize()
        local us = utils.uiScale()
        fx.spawn(0, (ph / 2 - 24) * us, { n = 14, keys = { "juice1", "juice2", "juice4" },
            dir = 270, spread = 150, speed = 300 * us, life = 0.6, size = 9 * us })
    else
        -- ★★ 序章被关掉（关闭 / 知道了 / 翻到末页 / L / H 都汇到这里）：
        --   置位 pending，交给 game.lua 下一帧在地图上点亮「进入果园」按钮。
        --   只认 "prologue"：图册关掉不该再引导（那时玩家早就进过关了）。
        if state.guideKind == "prologue" then
            state.prologueGuidePending = true
            state.guideKind = ""
        end
        fx.cancelAll()
    end
end

function M.applyIntro(k)
    k = utils.clamp(k, 0, 1)
    local pal = utils.palette()
    local pw, ph = panelSize()
    local e = k * k * (3 - 2 * k)
    local s = 0.92 + 0.08 * e
    utils.setSize(state.guideOverlay, (state.canvasW or 800) + 520, (state.canvasH or 600) + 520)
    utils.setColor(state.guideOverlay, pal.overlay, (config.DEFAULT_GUIDE_OVERLAY_ALPHA or 150) * e)
    utils.setBoxSize(state.guidePanel, pw * s, ph * s)
    utils.setBoxSize(state.guideEdge, (pw + 12) * s, (ph + 12) * s)
    utils.setBoxSize(state.guideShadow, pw * s, ph * s)
    -- ★ 圆角块是 { root, parts }，位移 / 缩放一律作用在 .root 上
    utils.setPos(state.guidePanel.root, 0, -18 * (1 - e))
    utils.setPos(state.guideEdge.root, 0, -18 * (1 - e))
    utils.setPos(state.guideShadow.root, 7, -9 - 18 * (1 - e))
    utils.setTextColor(state.guideTitle, pal.text, 255 * e)
    utils.setTextColor(state.guideCaption, pal.dim, 235 * e)
    for i = 1, 2 do
        utils.setTextColor(state.guideLines[i], pal.text, 245 * e)
    end
end

-- ================================================================
-- 每帧：入场 + 翻页滑入
-- ================================================================
function M.update(dt)
    if not state.guideOpen or not state.guidePanel then return end
    dt = tonumber(dt) or 0
    if dt <= 0 then return end
    local pal = utils.palette()

    if (state.guideIntroT or 0) < INTRO then
        state.guideIntroT = (state.guideIntroT or 0) + dt
        M.applyIntro(utils.clamp(state.guideIntroT / INTRO, 0, 1))
    end

    -- 翻页时示意图与文字从右侧滑入
    if (state.guideAnimT or 0) < PAGE_ANIM then
        state.guideAnimT = (state.guideAnimT or 0) + dt
        local pk = utils.clamp((state.guideAnimT or 0) / PAGE_ANIM, 0, 1)
        local dx = 26 * (1 - pk)
        local a = 255 * (0.35 + 0.65 * pk)
        local pw, ph = panelSize()
        local page = (state.guidePages or {})[state.guidePage or 1]
        if page then renderArt(page, pal, dx) end
        utils.setPos(state.guideTitle, dx, ph / 2 - 38)
        utils.setTextColor(state.guideTitle, pal.text, a)
        utils.setPos(state.guideCaption, dx, -102)
        utils.setTextColor(state.guideCaption, pal.dim, a * 0.9)
        for i = 1, 2 do
            utils.setPos(state.guideLines[i], dx, -134 - (i - 1) * 34)
            utils.setTextColor(state.guideLines[i], pal.text, a * 0.96)
        end
    end
end

return M
