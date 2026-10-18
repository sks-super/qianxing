-- ================================================================
-- 点灯迷题 2D · 右侧信息栏
--   关卡名 / 最优步数 / 两步数统计（步数·剩余灯）/ 四个功能按钮 / 关卡提示
--
--   动效：数值变化时数字「弹一下 + 变一次色」；剩余灯归零瞬间转绿并闪一下。
-- ================================================================

---@diagnostic disable: undefined-global

local M = {}

local state = require("default_import_file/state")
local config = require("default_import_file/config")
local utils = require("default_import_file/utils")
local anim = require("default_import_file/anim")

local TAG_NUM = "hud:num"

local actions = {}

function M.setActions(a)
    actions = a or {}
end

-- ================================================================
-- 建（只建一次）
-- ================================================================
function M.init()
    local par = state.containerHud
    if not par or (state.rectPrefabId or 0) <= 0 then return false end

    local pal = config.DEFAULT_PALETTE or {}
    local X = config.DEFAULT_HUD_X or 340
    local W = config.DEFAULT_HUD_W or 360
    local H = config.DEFAULT_HUD_H or 566
    local statW = config.DEFAULT_HUD_STAT_W or 148
    local statH = config.DEFAULT_HUD_STAT_H or 92
    local statGap = config.DEFAULT_HUD_STAT_GAP or 16
    local btnW = config.DEFAULT_BTN_W or 148
    local btnH = config.DEFAULT_BTN_H or 52

    -- 面板：外描边 + 内面板（纯矩形靠「大一圈的深色」模拟边框）
    M.edge = utils.createControl(state.rectPrefabId, X, 0, W + 4, H + 4,
        utils.hexToColor(pal.panelEdge or "1E2A47"), par)
    M.panel = utils.createControl(state.rectPrefabId, X, 0, W, H,
        utils.hexToColor(pal.panel or "121A2E"), par)
    utils.raise(M.panel)

    -- 标题
    M.title = utils.createText(X, H / 2 - 62, W - 40, 56, "第01关",
        utils.hexToColor(pal.text or "E9F0FF"), config.DEFAULT_HUD_TITLE_SIZE or 34, par)
    utils.raise(M.title)

    M.sub = utils.createText(X, H / 2 - 112, W - 40, 30, "最优 1 步",
        utils.hexToColor(pal.textDim or "8296B8"), config.DEFAULT_HUD_SUB_SIZE or 18, par)
    utils.raise(M.sub)

    -- 两个统计小卡
    local sy = 62
    local function statCard(cx, label)
        local base = utils.createControl(state.rectPrefabId, cx, sy, statW, statH,
            utils.hexToColor(pal.btn or "1C2740"), par)
        utils.raise(base)
        local lb = utils.createText(cx, sy + statH / 2 - 24, statW - 16, 24, label,
            utils.hexToColor(pal.textDim or "8296B8"), config.DEFAULT_HUD_STAT_LABEL_SIZE or 16, par)
        utils.raise(lb)
        local num = utils.createText(cx, sy - 14, statW - 16, 48, "0",
            utils.hexToColor(pal.text or "E9F0FF"), config.DEFAULT_HUD_STAT_SIZE or 34, par)
        utils.raise(num)
        return base, num
    end
    local lx = X - (statW + statGap) / 2
    local rx = X + (statW + statGap) / 2
    M.statMovesBg, M.statMoves = statCard(lx, "步数")
    M.statLitBg, M.statLit = statCard(rx, "剩余灯")

    -- 2×2 功能按钮
    local by1, by2 = -34, -34 - (btnH + config.DEFAULT_BTN_GAP or 18)
    M.btnHint = utils.createButton(lx, by1, btnW, btnH, par, {
        text = "提示", fontSize = config.DEFAULT_BTN_SIZE or 21,
        bg = pal.btn, bgDown = pal.btnDown, textColor = pal.accent,
        onClick = function() if actions.onHint then actions.onHint() end end,
    })
    M.btnUndo = utils.createButton(rx, by1, btnW, btnH, par, {
        text = "撤销", fontSize = config.DEFAULT_BTN_SIZE or 21,
        bg = pal.btn, bgDown = pal.btnDown, textColor = pal.btnText,
        onClick = function() if actions.onUndo then actions.onUndo() end end,
    })
    M.btnReset = utils.createButton(lx, by2, btnW, btnH, par, {
        text = "重玩", fontSize = config.DEFAULT_BTN_SIZE or 21,
        bg = pal.btn, bgDown = pal.btnDown, textColor = pal.btnText,
        onClick = function() if actions.onReset then actions.onReset() end end,
    })
    M.btnSelect = utils.createButton(rx, by2, btnW, btnH, par, {
        text = "选关", fontSize = config.DEFAULT_BTN_SIZE or 21,
        bg = pal.btn, bgDown = pal.btnDown, textColor = pal.btnText,
        onClick = function() if actions.onSelect then actions.onSelect() end end,
    })

    -- 关卡提示
    M.tip = utils.createText(X, by2 - 82, W - 56, 76, "",
        utils.hexToColor(pal.textDim or "8296B8"), config.DEFAULT_HUD_TIP_SIZE or 17, par)
    utils.raise(M.tip)

    M.footer = utils.createText(X, -H / 2 + 24, W - 40, 24, "点格子 · 十字五格一起翻转",
        utils.hexToColorA(pal.textDim or "8296B8", 150), 14, par)
    utils.raise(M.footer)

    return true
end

-- ================================================================
-- ★ 数字弹跳
-- ================================================================
local function popNumber(ctrl)
    if not ctrl then return end
    anim.clear(TAG_NUM)
    anim.tween(config.DEFAULT_ANIM_NUMBER_TIME or 0.24, function(p)
        local k = 1 + ((config.DEFAULT_ANIM_NUMBER_POP or 1.22) - 1) * anim.Ease.pulse(p)
        pcall(function() ctrl:SetLocalScale(k, k, 1) end)
    end, { ease = "linear", tag = TAG_NUM })
end

-- ================================================================
-- ★ 刷新（进关 / 每步之后调用）
--   cfg   : 关卡配置（name / steps / tip）
--   moves : 已用步数
--   lit   : 剩余亮灯数
-- ================================================================
function M.refresh(index, cfg, moves, lit)
    if not M.title then return end
    local pal = config.DEFAULT_PALETTE or {}
    cfg = cfg or {}
    local name = cfg.name or ("第" .. string.format("%02d", index or 1) .. "关")
    local best = math.floor(tonumber(cfg.steps) or 0)

    utils.setText(M.title, name)
    utils.setText(M.sub, best > 0 and ("最优 " .. best .. " 步") or "")
    utils.setText(M.tip, cfg.tip or "")
    M.setMoves(moves or 0)
    M.setLit(lit or 0)
    M.setHoverState(moves or 0, lit or 0)
end

function M.setMoves(n)
    if not M.statMoves then return end
    utils.setText(M.statMoves, tostring(math.floor(tonumber(n) or 0)))
end

function M.setLit(n)
    if not M.statLit then return end
    local pal = config.DEFAULT_PALETTE or {}
    utils.setText(M.statLit, tostring(math.floor(tonumber(n) or 0)))
    local v = math.floor(tonumber(n) or 0)
    if v == 0 then
        utils.setTextColor(M.statLit, pal.good or "5BE7A9", 255)
    else
        utils.setTextColor(M.statLit, pal.text or "E9F0FF", 255)
    end
end

-- 数值变化时的强调（由 game 在真实变化后调用）
function M.popMoves()
    popNumber(M.statMoves)
end

function M.popLit()
    popNumber(M.statLit)
end

-- ================================================================
-- ★ 按钮可用性
--   moves=0 时撤销不可用；已全灭时提示不可用
-- ================================================================
function M.setHoverState(moves, lit)
    if M.btnUndo then
        utils.setButtonEnabled(M.btnUndo, (moves or 0) > 0)
    end
    if M.btnHint then
        utils.setButtonEnabled(M.btnHint, (lit or 0) > 0)
    end
end

function M.setVisible(v)
    local par = state.containerHud
    if par then utils.setVisible(par, v) end
end

-- ================================================================
-- ★ 通关时的信息栏淡出（让棋盘飞出去时画面干净）
-- ================================================================
function M.fadeOut(onDone)
    if not M.panel then return end
    local pal = config.DEFAULT_PALETTE or {}
    anim.tween(0.22, function(p)
        local a = math.floor(255 * (1 - p))
        utils.setColor(M.panel, pal.panel or "121A2E", a)
        utils.setColor(M.statMovesBg, pal.btn or "1C2740", a)
        utils.setColor(M.statLitBg, pal.btn or "1C2740", a)
        utils.setTextColor(M.title, pal.text or "E9F0FF", a)
        utils.setTextColor(M.sub, pal.textDim or "8296B8", a)
        utils.setTextColor(M.tip, pal.textDim or "8296B8", a)
        utils.setTextColor(M.footer, pal.textDim or "8296B8", math.floor(a * 0.6))
        utils.setTextColor(M.statMoves, pal.text or "E9F0FF", a)
        utils.setTextColor(M.statLit, pal.good or "5BE7A9", a)
    end, { ease = "outQuad", tag = TAG_NUM, onDone = onDone })
end

function M.restore()
    local pal = config.DEFAULT_PALETTE or {}
    if not M.panel then return end
    utils.setColor(M.panel, pal.panel or "121A2E", 255)
    utils.setColor(M.statMovesBg, pal.btn or "1C2740", 255)
    utils.setColor(M.statLitBg, pal.btn or "1C2740", 255)
    utils.setTextColor(M.title, pal.text or "E9F0FF", 255)
    utils.setTextColor(M.sub, pal.textDim or "8296B8", 255)
    utils.setTextColor(M.tip, pal.textDim or "8296B8", 255)
    utils.setTextColor(M.footer, pal.textDim or "8296B8", 150)
    utils.setTextColor(M.statMoves, pal.text or "E9F0FF", 255)
    M.setLit(state.litCount or 0)
end

return M
