-- ================================================================
-- 点灯迷题 游玩期极简 HUD（夏日版）
-- ================================================================
-- 3D 棋盘由服务器节点图渲染，客户端只在屏幕角落压一层信息：
--   左上：奶油白卡片式的「第 NN 关」+ 难度提示（左侧一条橙汁竖条当吸管）
--   右下：「教程」「退出」两个软糖按钮
-- ★ 分层：本模块**只用 containerHud 一个容器**，容器内按
--   「投影 → 底图 → 文字 → 点击区域」的创建顺序摆放，所以文字永远压在底图之上。
-- ★ 点击：一律用 utils.createHit（光标检测区域元件）承接 —— 图片控件没有
--   AddCursorEventListener，把监听绑在底图上真机是点不动的。
-- ================================================================

---@diagnostic disable: undefined-global

local M = {}
local state = require("default_import_file/state")
local config = require("default_import_file/config")
local utils = require("default_import_file/utils")
local fx = require("default_import_file/fx")

-- 由 game.lua 注入：{ onTutorial = f(), onExit = f() }
M.actions = {}

local function addNode(ctrl)
    if ctrl then
        state.hudNodes[#state.hudNodes + 1] = ctrl
    end
    return ctrl
end

-- 记一条滑入动效：从 fromX 滑到 baseX（y 保持不变）
local function slide(ctrl, baseX, baseY, fromX)
    if not ctrl then return end
    state.hudSlideList[#state.hudSlideList + 1] = {
        ctrl = ctrl, baseX = baseX, baseY = baseY, fromX = fromX,
    }
end

-- ================================================================
-- ★ 预创建（OnStart 调用一次）
-- ================================================================
function M.init()
    if state.hudTitle then return true end
    if not state.containerHud then return false end
    if not state.rectPrefabId or state.rectPrefabId <= 0 then return false end

    local pal = utils.resolvePalette(state.currentLevelConfig)
    local cw = state.canvasW or config.DEFAULT_VIEW_WIDTH or 800
    local ch = state.canvasH or config.DEFAULT_VIEW_HEIGHT or 600
    local margin = config.DEFAULT_HUD_MARGIN or 34
    local textSize = config.DEFAULT_HUD_TEXT_SIZE or 26
    local hintSize = config.DEFAULT_HUD_HINT_SIZE or 16
    local bw = config.DEFAULT_HUD_BTN_W or 116
    local bh = config.DEFAULT_HUD_BTN_H or 50

    -- ---- 左上信息条 ----
    local barW = config.DEFAULT_HUD_BAR_W or 470
    local barH = config.DEFAULT_HUD_BAR_H or 66
    local barX = -cw / 2 + margin + barW / 2
    local barY = ch / 2 - margin - barH / 2
    local barFromX = barX - barW - 60
    local shade = addNode(utils.createControl(state.rectPrefabId, barX + 3, barY - 4, barW, barH,
        utils.hexToColorA(pal.shadow, 70), state.containerHud))          -- 投影
    state.hudBgBar = addNode(utils.createControl(state.rectPrefabId, barX, barY, barW, barH,
        utils.hexToColorA(pal.panel, 236), state.containerHud))          -- 卡片底
    local straw = addNode(utils.createControl(state.rectPrefabId, barX - barW / 2 + 7, barY, 9, barH - 18,
        utils.hexToColor(pal.accent), state.containerHud))               -- 吸管
    state.hudTitle = addNode(utils.createText(
        barX + 14, barY + 15, barW - 44, 32, "第 01 关",
        utils.hexToColor(pal.accent), textSize, state.containerHud))
    state.hudHint = addNode(utils.createText(
        barX + 14, barY - 15, barW - 44, 26, "",
        utils.hexToColor(pal.dim), hintSize, state.containerHud))
    slide(shade, barX + 3, barY - 4, barFromX + 3)
    slide(state.hudBgBar, barX, barY, barFromX)
    slide(straw, barX - barW / 2 + 7, barY, barFromX - barW / 2 + 7)
    slide(state.hudTitle, barX + 14, barY + 15, barFromX + 14)
    slide(state.hudHint, barX + 14, barY - 15, barFromX + 14)

    -- ---- 右下两个软糖按钮：教程 / 退出 ----
    local by = -ch / 2 + margin + bh / 2
    local exitX = cw / 2 - margin - bw / 2
    local tutX = exitX - bw - 14

    local function makeHudButton(x, text, onPress)
        local fromX = x + bw + 60
        local sh = addNode(utils.createControl(state.rectPrefabId, x + 2, by - 4, bw, bh,
            utils.hexToColorA(pal.shadow, 70), state.containerHud))      -- 投影
        local bg = addNode(utils.createControl(state.rectPrefabId, x, by, bw, bh,
            utils.hexToColor(pal.card), state.containerHud))             -- 底
        local label = addNode(utils.createText(x, by, bw, bh, text,
            utils.hexToColor(pal.accentText), hintSize + 2, state.containerHud))
        local hit = utils.createHit(x, by, bw, bh, state.containerHud, nil, bg)
        if hit then
            state.hudNodes[#state.hudNodes + 1] = hit
            utils.bindHover(hit,
                function()
                    pcall(function() bg:SetSizeDelta(bw + 6, bh + 6) end)
                end,
                function()
                    pcall(function() bg:SetSizeDelta(bw, bh) end)
                end)
            pcall(function()
                hit:AddCursorEventListener(Enum.CursorEventType.CursorDown, function()
                    if state.screen ~= "play" or state.tutorialOpen or state.winOpen then return end
                    fx.spawn(x, by, { n = 8, keys = { "juice1", "juice4" },
                                      speed = 200, life = 0.45, size = 7 })
                    onPress()
                end)
            end)
        end
        slide(sh, x + 2, by - 4, fromX + 2)
        slide(bg, x, by, fromX)
        slide(label, x, by, fromX)
        slide(hit, x, by, fromX)
        return bg, label, hit
    end

    state.hudTutBg, state.hudTutLabel, state.hudTutHit =
        makeHudButton(tutX, "教程", function()
            if M.actions.onTutorial then M.actions.onTutorial() end
        end)
    state.hudExitBg, state.hudExitLabel, state.hudExitHit =
        makeHudButton(exitX, "退出", function()
            if M.actions.onExit then M.actions.onExit() end
        end)

    M.setVisible(false)
    return true
end

-- ================================================================
-- ★ 刷新（进入某关 / 服务器确认后调用）
-- ================================================================
function M.refresh()
    if not state.hudTitle then return end
    local pal = utils.resolvePalette(state.currentLevelConfig)
    local idx = math.floor(tonumber(state.currentLevelIndex) or 1)
    local steps = config.getLevelSteps(idx)
    utils.setText(state.hudTitle, string.format("第 %02d 关", idx))
    utils.setTextColor(state.hudTitle, pal.accent, 255)
    -- 提示行优先级：临时覆盖（如「正在加载关卡…」）> 教程关的 tip > 默认难度行
    local hint = state.hudHintOverride
    local d = config.getLevelConfig(idx)
    if not hint or hint == "" then
        if d and type(d.tip) == "string" and d.tip ~= "" then
            hint = string.format("难度 %d 步 · %s", steps, d.tip)
        else
            hint = string.format("难度 %d 步 · 全部熄灭即过关", steps)
        end
    end
    utils.setText(state.hudHint, hint)
    utils.setTextColor(state.hudHint, pal.dim, 255)
    utils.setTextColor(state.hudExitLabel, pal.accentText, 255)
    utils.setTextColor(state.hudTutLabel, pal.accentText, 255)
    utils.setAlpha(state.hudExitBg, pal.card, 255)
    utils.setAlpha(state.hudTutBg, pal.card, 255)
end

-- ================================================================
-- ★ 状态行覆盖（"" 表示恢复默认难度行）
-- ================================================================
function M.setHint(text)
    state.hudHintOverride = tostring(text or "")
    M.refresh()
end

-- ================================================================
-- ★ 每帧：滑入动效（只在游玩屏推进）
-- ================================================================
function M.update(dt)
    if state.screen ~= "play" then return end
    if not state.hudSlideList or #state.hudSlideList == 0 then return end
    dt = tonumber(dt) or 0
    if dt <= 0 then return end
    local dur = config.DEFAULT_ANIM_SLIDE_TIME or 0.28
    state.hudSlideT = (state.hudSlideT or 0) + dt
    local k = state.hudSlideT / dur
    if k > 1 then k = 1 end
    local u = 1 - k
    local e = 1 - u * u * u
    for i = 1, #state.hudSlideList do
        local it = state.hudSlideList[i]
        if it.ctrl then
            utils.setPos(it.ctrl, it.fromX + (it.baseX - it.fromX) * e, it.baseY)
        end
    end
end

-- ================================================================
-- ★ 显隐
-- ================================================================
function M.setVisible(v)
    utils.setVisibleAll(state.hudNodes, v)
    if v then
        state.hudSlideT = 0
        M.refresh()
        for i = 1, #state.hudSlideList do
            local it = state.hudSlideList[i]
            if it.ctrl then utils.setPos(it.ctrl, it.fromX, it.baseY) end
        end
    end
end

-- ================================================================
-- ★ 注入动作回调（由 game.lua 调用，避免与 game.lua 循环依赖）
-- ================================================================
function M.setActions(t)
    if type(t) == "table" then M.actions = t end
end

return M
