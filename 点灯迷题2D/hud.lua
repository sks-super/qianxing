-- ================================================================
-- 点灯迷题 16 · 顶部信息条 + 拼图槽 + 底部按钮
-- ================================================================
--  左上：大关名 + 当前小关
--  中上：四个拼图槽（完成一块亮一块）
--  右上：模式切换 + 步数
--  底部：撤销 / 重置 / 提示 / 换大关
-- ================================================================

---@diagnostic disable: undefined-global

local state = require("default_import_file/state")
local config = require("default_import_file/config")
local utils = require("default_import_file/utils")
local anim = require("default_import_file/anim")

local M = {}

local TAG_NUM = "hud:num"
local actions = {}

function M.setActions(a)
    actions = a or {}
end

function M.init()
    local par = state.containerHud
    if not par or (state.rectPrefabId or 0) <= 0 then return false end
    local pal = config.DEFAULT_PALETTE or {}

    M.title = utils.createText(-416, 300, 380, 44, "", utils.hexToColor(pal.text or "E9F0FF"),
        config.DEFAULT_HUD_TITLE_SIZE or 30, par, "left")
    M.sub = utils.createText(-416, 268, 380, 26, "", utils.hexToColor(pal.textDim or "8296B8"),
        config.DEFAULT_HUD_SUB_SIZE or 15, par, "left")

    M.modeBtn = utils.createButton(432, 300, config.DEFAULT_MODE_BTN_W or 122,
        config.DEFAULT_MODE_BTN_H or 38, par, {
        text = "找不同", fontSize = 17,
        bg = pal.btn, bgDown = pal.btnDown, textColor = pal.accent,
        onClick = function() if actions.onMode then actions.onMode() end end,
    })

    M.steps = utils.createText(228, 300, 260, 40, "步数 0 / 最优 0",
        utils.hexToColor(pal.text or "E9F0FF"), 20, par, "right")

    -- 四个拼图槽
    local size = config.DEFAULT_CHIP or 46
    local gap = config.DEFAULT_CHIP_GAP or 8
    local total = size * 4 + gap * 3
    local y = config.DEFAULT_CHIP_Y or 258
    M.chipBase, M.chipText = {}, {}
    for i = 1, 4 do
        local x = -total / 2 + size / 2 + (i - 1) * (size + gap)
        local base = utils.createControl(state.rectPrefabId, x, y, size, size,
            utils.hexToColor(pal.btn or "1C2740"), par)
        local txt = utils.createText(x, y, size, size, tostring(i),
            utils.hexToColor(pal.textDim or "8296B8"), 18, par)
        utils.raise(base)
        utils.raise(txt)
        M.chipBase[i], M.chipText[i] = base, txt
    end

    -- 底部按钮
    local bw = config.DEFAULT_BTN_W or 132
    local bh = config.DEFAULT_BTN_H or 48
    local bgap = 12
    local bx = -((bw + bgap) * 3) / 2
    M.btnUndo = utils.createButton(bx, -300, bw, bh, par, {
        text = "撤销", fontSize = config.DEFAULT_BTN_SIZE or 18,
        bg = pal.btn, bgDown = pal.btnDown, textColor = pal.btnText,
        onClick = function() if actions.onUndo then actions.onUndo() end end,
    })
    M.btnReset = utils.createButton(bx + bw + bgap, -300, bw, bh, par, {
        text = "重置", fontSize = config.DEFAULT_BTN_SIZE or 18,
        bg = pal.btn, bgDown = pal.btnDown, textColor = pal.btnText,
        onClick = function() if actions.onReset then actions.onReset() end end,
    })
    M.btnHint = utils.createButton(bx + (bw + bgap) * 2, -300, bw, bh, par, {
        text = "提示", fontSize = config.DEFAULT_BTN_SIZE or 18,
        bg = pal.btn, bgDown = pal.btnDown, textColor = pal.accent,
        onClick = function() if actions.onHint then actions.onHint() end end,
    })
    M.btnChapter = utils.createButton(bx + (bw + bgap) * 3, -300, bw, bh, par, {
        text = "换大关", fontSize = config.DEFAULT_BTN_SIZE or 18,
        bg = pal.btn, bgDown = pal.btnDown, textColor = pal.btnText,
        onClick = function() if actions.onChapter then actions.onChapter() end end,
    })

    return true
end

-- ================================================================
-- 刷新
-- ================================================================
function M.refresh()
    local ch = config.getChapter(state.chapterIndex)
    local piece = config.PIECES[state.pieceIndex] or {}
    local pal = config.DEFAULT_PALETTE or {}

    utils.setText(M.title, (ch and ch.name or "") .. " · " .. (piece.name or ""))
    utils.setText(M.sub, "第 " .. state.chapterIndex .. "/" .. config.chapterCount()
        .. " 大关 · 第 " .. state.pieceIndex .. "/4 块 · 最优 " .. (state.bestSteps or 0) .. " 步")
    if M.modeBtn then
        utils.setText(M.modeBtn.label, (state.mode == 1) and "找不同" or "无参照")
    end
    M.setSteps(state.moves or 0)

    for i = 1, 4 do
        local done = state.slotDone[i]
        local base, txt = M.chipBase[i], M.chipText[i]
        if base then
            utils.setColor(base, done and (pal.accentSoft or "1E4A63") or (pal.btn or "1C2740"), 255)
        end
        if txt then
            utils.setText(txt, done and "★" or tostring(i))
            utils.setTextColor(txt, done and (pal.star or "FFD166") or (pal.textDim or "8296B8"), 255)
        end
    end
    M.setButtons()
end

function M.setSteps(n)
    if not M.steps then return end
    utils.setText(M.steps, "步数 " .. math.floor(tonumber(n) or 0)
        .. " / 最优 " .. (state.bestSteps or 0))
end

function M.popSteps()
    if not M.steps then return end
    anim.clear(TAG_NUM)
    anim.tween(config.DEFAULT_ANIM_NUMBER_TIME or 0.24, function(p)
        local k = 1 + ((config.DEFAULT_ANIM_NUMBER_POP or 1.2) - 1) * anim.Ease.pulse(p)
        pcall(function() M.steps:SetLocalScale(k, k, 1) end)
    end, { ease = "linear", tag = TAG_NUM })
end

function M.setButtons()
    local playing = (state.phase == "play")
    if M.btnUndo then utils.setButtonEnabled(M.btnUndo, playing and #state.history > 0) end
    if M.btnHint then utils.setButtonEnabled(M.btnHint, playing) end
    if M.btnReset then utils.setButtonEnabled(M.btnReset, playing) end
    if M.btnChapter then utils.setButtonEnabled(M.btnChapter, state.phase ~= "finish") end
end

function M.setChipDone(i)
    local pal = config.DEFAULT_PALETTE or {}
    if M.chipBase[i] then
        anim.tween(0.2, function(p)
            local k = 1 + 0.35 * anim.Ease.pulse(p)
            pcall(function() M.chipBase[i]:SetLocalScale(k, k, 1) end)
        end, { ease = "linear", tag = TAG_NUM })
        utils.setColor(M.chipBase[i], pal.accentSoft or "1E4A63", 255)
    end
    if M.chipText[i] then
        utils.setText(M.chipText[i], "★")
        utils.setTextColor(M.chipText[i], pal.star or "FFD166", 255)
    end
end

function M.setVisible(v)
    if state.containerHud then utils.setVisible(state.containerHud, v) end
end

return M
