-- ================================================================
-- 伐木远征 · 界面层（标题 / 选关 / 对话 / HUD）
--   全部由纯色块 + 文本框拼成，没有一张图片素材。
--   ★ 三块面板各自成组，切屏时整组显隐；控件只创建一次，之后只改文字与配色，
--     避免反复 Instantiate 把控件树撑爆。
-- ================================================================

---@diagnostic disable: undefined-global

local M = {}
local state = require("state")
local config = require("config")
local utils = require("utils")

local P = config.PALETTE

-- ---------------- 本模块私有 ----------------
local titleCtrls = {}
local selectCtrls = {}
local dialogCtrls = {}
local cards = {}          -- 12 张卡片 { bg, name, en, mark, index }
local dlgLines = {}       -- 对话正文的若干行
local onPickMap = nil     -- 选关回调（由 game.lua 注入）
local onDialogNext = nil

local function push(t, c)
    if c then t[#t + 1] = c end
    return c
end

local function showGroup(group, visible)
    for _, c in ipairs(group) do utils.setVisible(c, visible) end
end

-- ================================================================
-- ★ 卡片布局：4 个区各一行，每行「主线 + 0~2 个番外」
-- ================================================================
local CARD_W, CARD_H = 222, 94
local ROW_Y = { 130, 12, -106, -224 }
local COL_X = { -158, 76, 310 }

local function cardAt(regionIdx, colIdx)
    return COL_X[colIdx] or COL_X[3], ROW_Y[regionIdx] or ROW_Y[4]
end

-- ================================================================
-- ★ 初始化：HUD + 标题 + 选关 + 对话
-- ================================================================
function M.init(opts)
    onPickMap = opts and opts.onPickMap or nil
    onDialogNext = opts and opts.onDialogNext or nil

    local cw = state.canvasW or 1280
    local ch = state.canvasH or 720

    -- ---------------- HUD ----------------
    state.hudBar = utils.createControl(0, ch / 2 - 28, cw + 80, 56,
        utils.hexToColorA(P.hudBar, 210), state.containerHud)
    state.hudRegion = utils.createText(-cw * 0.30, ch / 2 - 28, cw * 0.42, 40, "",
        P.hud, config.DEFAULT_HUD_TITLE_SIZE, state.containerHud)
    state.hudMoves = utils.createText(cw * 0.32, ch / 2 - 28, cw * 0.30, 40, "",
        P.hud, config.DEFAULT_HUD_INFO_SIZE, state.containerHud)

    state.hudBarBottom = utils.createControl(0, -ch / 2 + 32, cw + 80, 64,
        utils.hexToColorA(P.hudBar, 190), state.containerHud)
    state.hudMsg = utils.createText(-cw * 0.18, -ch / 2 + 32, cw * 0.52, 40, "",
        P.hud, config.DEFAULT_HUD_INFO_SIZE, state.containerHud)
    state.hudKey = utils.createText(cw * 0.30, -ch / 2 + 32, cw * 0.34, 40,
        "WASD/方向键 移动　Z 撤销　R 重置　F 菜单",
        P.hudDim, 18, state.containerHud)

    -- ---------------- 标题 ----------------
    push(titleCtrls, utils.createControl(0, 0, cw + 8, ch + 8,
        utils.hexToColorA("0B1519", 246), state.containerMenu))
    push(titleCtrls, utils.createText(0, 150, cw - 200, 110, "伐木远征",
        P.title, config.DEFAULT_MENU_TITLE_SIZE, state.containerMenu))
    push(titleCtrls, utils.createText(0, 78, cw - 240, 44,
        "推木 · 滚木 · 搭筏渡水", P.sub, 24, state.containerMenu))
    push(titleCtrls, utils.createText(0, -10, cw - 320, 120,
        "把木头推进水里架成桥，把两根木头拼成筏子，\n一路从沙洲走到雪山顶。\n原版是 TI-83/84 计算器上的黑白解谜游戏 MExp。",
        P.sub, 20, state.containerMenu))
    push(titleCtrls, utils.createText(0, -140, cw - 240, 46,
        "按 空格 开始　·　按 F 选地图", P.accent, 26, state.containerMenu))
    push(titleCtrls, utils.createText(0, -236, cw - 200, 40,
        "WASD / 方向键 移动　Z 撤销　R 重置　F 打开菜单",
        P.hudDim, 18, state.containerMenu))

    -- ---------------- 选关 ----------------
    push(selectCtrls, utils.createControl(0, 0, cw + 8, ch + 8,
        utils.hexToColorA("0B1519", 248), state.containerMenu))
    push(selectCtrls, utils.createText(0, 292, cw - 200, 56, "选择地图",
        P.title, 36, state.containerMenu))
    push(selectCtrls, utils.createText(0, 248, cw - 220, 34,
        "空格 进入　·　WASD/方向键 选择　·　F 返回", P.sub, 18, state.containerMenu))

    -- 区标题 + 卡片
    for ri = 1, #config.REGIONS do
        local reg = config.REGIONS[ri]
        push(selectCtrls, utils.createText(-512, ROW_Y[ri] + 14, 200, 34,
            reg.cn, P.accent, 24, state.containerMenu))
        push(selectCtrls, utils.createText(-512, ROW_Y[ri] - 18, 200, 28,
            "第 " .. ri .. " 区", P.hudDim, 16, state.containerMenu))
    end

    local idx = 0
    for ri = 1, #config.REGIONS do
        local reg = config.REGIONS[ri]
        local col = 1
        local function addCard(key, isDig, label)
            idx = idx + 1
            local x, y = cardAt(ri, col)
            col = col + 1
            local bg = push(selectCtrls, utils.createControl(x, y, CARD_W, CARD_H,
                utils.hexToColorA(P.panel, 235), state.containerMenu))
            local nm = push(selectCtrls, utils.createText(x, y + 18, CARD_W - 24, 32,
                label, P.title, 22, state.containerMenu))
            local en = push(selectCtrls, utils.createText(x, y - 18, CARD_W - 24, 26,
                isDig and "番外" or "主线", P.hudDim, 15, state.containerMenu))
            local c = { bg = bg, name = nm, sub = en, key = key, index = idx }
            cards[idx] = c
            if bg then
                pcall(function()
                    bg:AddCursorEventListener(Enum.CursorEventType.CursorDown, function()
                        if onPickMap then onPickMap(key) end
                    end)
                end)
            end
        end
        addCard(reg.key, false, reg.cn)
        for _, d in ipairs(config.DIGRESSIONS) do
            if d.parent == reg.key then addCard(d.key, true, d.cn) end
        end
    end

    -- ---------------- 对话 ----------------
    push(dialogCtrls, utils.createControl(0, 0, cw + 8, ch + 8,
        utils.hexToColorA("060E12", 170), state.containerMenu))
    push(dialogCtrls, utils.createControl(0, 10, 820, 400,
        utils.hexToColorA(P.panel, 242), state.containerMenu))
    push(dialogCtrls, utils.createControl(0, 210, 820, 3,
        utils.hexToColorA(P.accent, 220), state.containerMenu))
    for i = 1, 8 do
        dlgLines[i] = push(dialogCtrls, utils.createText(0, 150 - (i - 1) * 46, 740, 42,
            "", P.title, config.DEFAULT_DIALOG_SIZE, state.containerMenu))
    end
    local foot = push(dialogCtrls, utils.createText(0, -160, 760, 34, "",
        P.hudDim, 18, state.containerMenu))
    M._dlgFoot = foot
    local hit = push(dialogCtrls, utils.createControl(0, 10, 820, 400,
        utils.hexToColorA("000000", 0), state.containerMenu))
    if hit then
        pcall(function()
            hit:AddCursorEventListener(Enum.CursorEventType.CursorDown, function()
                if onDialogNext then onDialogNext() end
            end)
        end)
    end

    showGroup(titleCtrls, false)
    showGroup(selectCtrls, false)
    showGroup(dialogCtrls, false)
end

-- ================================================================
-- ★ 切屏
-- ================================================================
function M.showScreen(name)
    showGroup(titleCtrls, name == "title")
    showGroup(selectCtrls, name == "select")
    -- 对话只在对局里出现，切屏时一并收起
    if name ~= "play" then showGroup(dialogCtrls, false) end
    local hudOn = (name == "play")
    utils.setVisible(state.hudBar, hudOn)
    utils.setVisible(state.hudBarBottom, hudOn)
    utils.setVisible(state.hudRegion, hudOn)
    utils.setVisible(state.hudMoves, hudOn)
    utils.setVisible(state.hudMsg, hudOn)
    utils.setVisible(state.hudKey, hudOn)
end

-- ================================================================
-- ★ 选关：刷新卡片状态（配色随高亮 / 已通关变化）
-- ================================================================
function M.refreshCards()
    for i, c in ipairs(cards) do
        local done = state.progress[c.key] and true or false
        local sel = (i == (state.menuCursor or 1))
        local bgHex = sel and P.panelEdge or P.panel
        utils.setColor(c.bg, utils.hexToColorA(bgHex, sel and 255 or 225))
        utils.setTextColor(c.name, done and P.done or P.title, 255)
        if c.sub then
            local label
            if done then
                label = "√ 已通关"
            else
                local isDig = false
                for _, d in ipairs(config.DIGRESSIONS) do
                    if d.key == c.key then isDig = true break end
                end
                label = isDig and "番外" or "主线"
            end
            utils.setText(c.sub, label)
            utils.setTextColor(c.sub, done and P.done or P.hudDim, 255)
        end
    end
end

-- 按索引取地图 key
function M.cardKeyAt(i)
    local c = cards[i]
    return c and c.key or nil
end

function M.cardCount()
    return #cards
end

-- ================================================================
-- ★ HUD 文本
-- ================================================================
function M.setHud(regionName, moves, msg)
    if state.hudRegion then utils.setText(state.hudRegion, regionName or "") end
    if state.hudMoves then
        utils.setText(state.hudMoves, string.format("步数 %d", moves or 0))
    end
    if state.hudMsg and msg ~= nil then utils.setText(state.hudMsg, msg) end
end

-- ================================================================
-- ★ 对话
-- ================================================================
function M.openDialog(pages, goal)
    state.dialog = { pages = pages, idx = 1, goal = goal and true or false }
    showGroup(dialogCtrls, true)
    M.refreshDialog()
end

function M.refreshDialog()
    local d = state.dialog
    if not d then return end
    local page = d.pages[d.idx] or ""
    local lines = {}
    for line in string.gmatch(page .. "\n", "([^\n]*)\n") do
        lines[#lines + 1] = line
    end
    for i = 1, 8 do
        local c = dlgLines[i]
        if c then
            if lines[i] then
                utils.setText(c, lines[i])
                utils.setVisible(c, true)
            else
                utils.setVisible(c, false)
            end
        end
    end
    if M._dlgFoot then
        local tail = (d.idx < #d.pages) and "空格 / 点击 继续" or "空格 / 点击 关闭"
        if d.goal then tail = "已完成　·　" .. tail end
        utils.setText(M._dlgFoot, tail)
    end
end

function M.advanceDialog()
    local d = state.dialog
    if not d then return false end
    if d.idx < #d.pages then
        d.idx = d.idx + 1
        M.refreshDialog()
        return true
    end
    M.closeDialog()
    return false
end

function M.closeDialog()
    state.dialog = nil
    showGroup(dialogCtrls, false)
end

function M.dialogOpen()
    return state.dialog ~= nil
end

return M
