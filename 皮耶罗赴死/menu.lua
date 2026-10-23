-- ================================================================
-- 皮耶罗：赴死 · 主菜单（标题 + 30 关选关格 + 不死诅咒开关）
--   控件只建一次，进度变化靠 menu.refresh() 改颜色与可用性。
-- ================================================================

---@diagnostic disable: undefined-disable
---@diagnostic disable: undefined-global

local M = {}
local state = require("default_import_file/state")
local config = require("default_import_file/config")
local utils = require("default_import_file/utils")
local audio = require("default_import_file/audio")

M.open = false
M.cells = {}
M.cb = nil
M.title = nil
M.sub = nil
M.hint = nil
M.stat = nil
M.ghostBtn = nil
M.startBtn = nil

local function gridGeom()
    local cols = math.floor(config.DEFAULT_MENU_GRID_COLS or 10)
    local cw = config.DEFAULT_MENU_CELL_W or 72
    local ch = config.DEFAULT_MENU_CELL_H or 52
    local gap = config.DEFAULT_MENU_CELL_GAP or 10
    local totalW = cols * cw + (cols - 1) * gap
    return cols, cw, ch, gap, totalW
end

-- 第 i 个格子的中心（UI 坐标）
local function cellPos(i)
    local cols, cw, ch, gap, totalW = gridGeom()
    local r = math.floor((i - 1) / cols)
    local c = (i - 1) % cols
    local x = -totalW / 2 + cw / 2 + c * (cw + gap)
    local y = 56 - r * (ch + gap)
    return x, y
end

-- ================================================================
function M.init(cb)
    M.cb = cb or {}
    local par = state.containerMenu
    if not par then return false end
    if M.title then return true end

    M.title = utils.createText(0, 186, 900, 72, "皮耶罗：赴死",
        utils.hexToColor(utils.pal("accent")), config.DEFAULT_MENU_TITLE_SIZE, par)
    M.sub = utils.createText(0, 146, 900, 26, "I WANNA WEIGH THE LIFE",
        utils.hexToColor(utils.pal("textDim")), config.DEFAULT_MENU_SUB_SIZE, par)
    M.hint = utils.createText(0, 120, 900, 24,
        "← → / A D 移动    ·    ↑ / W / 空格 跳跃    ·    R 重来",
        utils.hexToColor(utils.pal("textDim")), 13, par)

    -- 选关格
    local n = math.min(config.levelCount(), 30)
    for i = 1, n do
        local x, y = cellPos(i)
        local cols, cw, ch = gridGeom()
        local btn = utils.createButton(x, y, cw, ch, par, {
            text = tostring(i),
            fontSize = 20,
            bg = utils.pal("btn"),
            bgDown = utils.pal("btnDown"),
            textColor = utils.pal("textDim"),
            onClick = function()
                if M.cb.onStart then M.cb.onStart(i) end
            end,
        })
        if btn then M.cells[i] = btn end
    end

    M.ghostBtn = utils.createButton(0, -126, 300, 42, par, {
        text = "",
        fontSize = 17,
        bg = utils.pal("btn"),
        bgDown = utils.pal("btnDown"),
        textColor = utils.pal("text"),
        onClick = function()
            audio.playClick()
            if M.cb.onToggleGhost then M.cb.onToggleGhost() end
        end,
    })

    M.startBtn = utils.createButton(0, -188, 300, 52, par, {
        text = "开始赴死",
        fontSize = 22,
        bg = utils.pal("accent"),
        bgDown = utils.pal("btnDown"),
        textColor = "1A1206",
        onClick = function()
            audio.playClick()
            local lv = state.unlocked or 1
            if lv > config.levelCount() then lv = config.levelCount() end
            if M.cb.onStart then M.cb.onStart(lv) end
        end,
    })

    M.stat = utils.createText(0, -244, 900, 24, "",
        utils.hexToColor(utils.pal("textDim")), 13, par)

    M.refresh()
    return true
end

-- ================================================================
function M.refresh()
    if not M.title then return end
    local n = math.min(config.levelCount(), 30)
    for i = 1, n do
        local btn = M.cells[i]
        if btn then
            local unlocked = i <= (state.unlocked or 1)
            local done = (state.done or {})[i] and true or false
            utils.setButtonEnabled(btn, unlocked)
            if done then
                utils.setColor(btn.base, utils.pal("btn"), 255)
                utils.setTextColor(btn.label, utils.pal("accent"), 255)
            elseif unlocked then
                utils.setColor(btn.base, utils.pal("btn"), 255)
                utils.setTextColor(btn.label, utils.pal("text"), 255)
            else
                utils.setColor(btn.base, utils.pal("locked"), 255)
                utils.setTextColor(btn.label, utils.pal("textDim"), 90)
            end
        end
    end

    if M.ghostBtn then
        if state.ghostOn then
            utils.setText(M.ghostBtn.label, "不死诅咒：开（鬼魂模式）")
            utils.setTextColor(M.ghostBtn.label, utils.pal("accent"), 255)
        else
            utils.setText(M.ghostBtn.label, "不死诅咒：关")
            utils.setTextColor(M.ghostBtn.label, utils.pal("textDim"), 255)
        end
    end

    local doneCount = 0
    for i = 1, n do
        if (state.done or {})[i] then doneCount = doneCount + 1 end
    end
    utils.setText(M.stat, string.format("已穿过 %d / %d 道门     累计死亡 %d",
        doneCount, n, math.floor(state.deaths or 0)))
end

-- ================================================================
function M.setVisible(v)
    M.open = v and true or false
    if not M.title then return end
    utils.setVisible(M.title, v)
    utils.setVisible(M.sub, v)
    utils.setVisible(M.hint, v)
    utils.setVisible(M.stat, v)
    utils.setVisible(M.ghostBtn, v)
    utils.setVisible(M.startBtn, v)
    for i = 1, #M.cells do
        utils.setVisible(M.cells[i], v)
    end
    if v then M.refresh() end
end

return M
