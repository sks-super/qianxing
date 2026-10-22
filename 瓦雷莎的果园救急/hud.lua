-- ================================================================
-- 瓦雷莎的果园救急 · 游玩期 HUD（无常驻信息、无按钮）
-- ================================================================
-- ★ 按需求：**游玩界面不显示任何常驻信息与按钮**。以下全部删除：
--     · 左上「第 03 片果园 + 难度 N 步 · 提示」卡片
--     · 右上「还剩 N 格果汁」胶囊
--     · 右下「教程」「回果园」两个按钮
--
-- ★ 回果园不再由客户端按钮触发：只认服务器信号「服客进入选关」
--   （见 game.lua 的 onServerSelect / signal.SIGNAL_S2C_SELECT）。
--   中途退出、服务器重开、结算后回地图，统统由节点图发这条信号驱动。
--   ★ 键盘 L 仍保留为**调试用**本地后门（模拟器里没有节点图可发信号），
--     正式环境请只用信号，否则客户端会与服务器状态脱节。
--
-- ★ 唯一保留：一条**临时状态**提示（左上胶囊），只在有文案时出现：
--     「小龙正在摆果园…」/「小龙重新摆这一片…」
--   它的作用不是展示信息，而是**加载态**：节点图摆盘要几秒，
--   不提示玩家会以为画面卡死。文案一清空（setHint("")）整条收回。
--   不想要这条也有开关：config.DEFAULT_HUD_TRANSIENT_HINT = 0
-- ================================================================

---@diagnostic disable: undefined-global

local M = {}
local state = require("default_import_file/state")
local config = require("default_import_file/config")
local utils = require("default_import_file/utils")

local function addNode(ctrl)
    if ctrl then state.hudNodes[#state.hudNodes + 1] = ctrl end
    return ctrl
end

-- ★ 圆角块（utils.roundBox 返回的 { root, parts }）整体登记，方便统一显隐
local function addBox(box)
    if not box then return nil end
    addNode(box.root)
    for i = 1, #box.parts do addNode(box.parts[i]) end
    return box
end

local function slide(ctrl, baseX, baseY, fromX)
    if not ctrl then return end
    state.hudSlideList[#state.hudSlideList + 1] = {
        ctrl = ctrl, baseX = baseX, baseY = baseY, fromX = fromX,
    }
end

-- ================================================================
-- 初始化
-- ================================================================
function M.init()
    if state.hudReady then return true end
    if not state.containerHud then return false end
    if not state.rectPrefabId or state.rectPrefabId <= 0 then return false end

    local pal = utils.palette()
    local cw = state.canvasW or config.DEFAULT_VIEW_WIDTH or 800
    local ch = state.canvasH or config.DEFAULT_VIEW_HEIGHT or 600
    local margin = config.DEFAULT_HUD_MARGIN or 30
    local hintSize = config.DEFAULT_HUD_HINT_SIZE or 15

    -- ★ 左上「临时状态」胶囊：常态隐藏，只有 setHint("...") 且文案非空时才滑入。
    local barW = config.DEFAULT_HUD_BAR_W or 500
    local barH = config.DEFAULT_HUD_BAR_H or 72
    local barX = -cw / 2 + margin + barW / 2
    local barY = ch / 2 - margin - barH / 2
    local fromX = barX - barW - 70

    -- ★ 信息条做成圆角奶油卡（投影 + 卡面），投影用「预混色 + 255」避免拼缝
    local br = math.min(20, barH * 0.30)
    state.hudBarShade = addBox(utils.roundBox(barX + 3, barY - 4, barW, barH, br,
        utils.mixHex(pal.panel, pal.shadow, 0.45), state.containerHud))
    state.hudBar = addBox(utils.roundBox(barX, barY, barW, barH, br, pal.panel, state.containerHud))
    -- 单行居中
    state.hudHint = addNode(utils.createText(barX, barY, barW - 40, barH, "",
        utils.hexToColor(pal.dim), hintSize + 1, state.containerHud))
    slide(state.hudBarShade.root, barX + 3, barY - 4, fromX + 3)
    slide(state.hudBar.root, barX, barY, fromX)
    slide(state.hudHint, barX, barY, fromX)

    M.setVisible(false)
    state.hudReady = true
    return true
end

-- ================================================================
-- 刷新
-- ================================================================
function M.refresh()
    if not state.hudReady then return end
    local pal = utils.palette()

    local hint = state.hudHintOverride
    if type(hint) ~= "string" then hint = "" end
    if (config.DEFAULT_HUD_TRANSIENT_HINT or 1) == 0 then hint = "" end
    local showHint = hint ~= ""
    utils.setVisible(state.hudBarShade.root, showHint)
    utils.setVisible(state.hudBar.root, showHint)
    utils.setVisible(state.hudHint, showHint)
    if showHint then
        utils.setText(state.hudHint, hint)
        utils.setTextColor(state.hudHint, pal.dim, 255)
        utils.setBoxColor(state.hudBar, pal.panel, 255)
    end
end

function M.setHint(text)
    state.hudHintOverride = tostring(text or "")
    M.refresh()
end

-- ★ 保留 API 只为兼容既有调用点：游玩界面已不显示「剩余果汁」。
--   服务器若日后回传这个数值，接回显示只改这里（数值本身仍然记在 state 里）。
function M.setJuice(n)
    n = tonumber(n)
    state.juiceLeft = n and math.floor(n) or -1
end

-- ================================================================
-- 每帧：滑入
-- ================================================================
function M.update(dt)
    if state.screen ~= "play" then return end
    if #state.hudSlideList == 0 then return end
    dt = tonumber(dt) or 0
    if dt <= 0 then return end
    local dur = config.DEFAULT_ANIM_SLIDE_TIME or 0.28
    if (state.hudSlideT or 0) >= dur then return end
    state.hudSlideT = (state.hudSlideT or 0) + dt
    local k = math.min(1, (state.hudSlideT or 0) / dur)
    local e = 1 - (1 - k) * (1 - k) * (1 - k)
    for i = 1, #state.hudSlideList do
        local it = state.hudSlideList[i]
        if it.ctrl then
            utils.setPos(it.ctrl, it.fromX + (it.baseX - it.fromX) * e, it.baseY)
        end
    end
end

-- ================================================================
-- 显隐
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

return M
