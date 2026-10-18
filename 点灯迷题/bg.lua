-- ================================================================
-- 点灯迷题 夏日背景（纯基础图元）
-- ================================================================
-- 从下到上依次画：天空底 → 海面 → 沙滩 → 波浪高光 → 两团柔光 → 上升气泡。
-- 全部挂在 containerBg（最底层），不遮挡任何界面元素，也不吃点击。
-- 气泡是唯一每帧动的部分：缓慢上浮 + 横向正弦摇摆，出顶后从底部循环。
-- ================================================================

---@diagnostic disable: undefined-global

local M = {}
local state = require("default_import_file/state")
local config = require("default_import_file/config")
local utils = require("default_import_file/utils")

M.nodes = {}
M.ready = false

local function addNode(ctrl)
    if ctrl then
        M.nodes[#M.nodes + 1] = ctrl
    end
    return ctrl
end

-- ================================================================
-- ★ 预创建（OnStart 调用一次）
-- ================================================================
function M.init(pal)
    if M.ready then return true end
    if not state.containerBg then return false end
    if not state.rectPrefabId or state.rectPrefabId <= 0 then return false end
    pal = pal or utils.resolvePalette(nil)

    local cw = state.canvasW or config.DEFAULT_VIEW_WIDTH or 800
    local ch = state.canvasH or config.DEFAULT_VIEW_HEIGHT or 600
    local W = cw + 600                      -- 一律画得比画布大，避免边缘露缝
    local H = ch + 600

    -- ① 天空底（整屏）
    addNode(utils.createControl(state.rectPrefabId, 0, 0, W, H,
        utils.hexToColor(pal.sky), state.containerBg))

    -- ② 海面：下半屏（地平线放在画面正中，沙滩再压在海面之上）
    addNode(utils.createControl(state.rectPrefabId, 0, -ch / 4, W, ch / 2 + 40,
        utils.hexToColor(pal.skyDeep), state.containerBg))

    -- ③ 沙滩：画面下沿一条厚带
    local sandH = config.DEFAULT_BG_SAND_H or 190
    addNode(utils.createControl(state.rectPrefabId, 0, -ch / 2 + sandH / 2, W, sandH,
        utils.hexToColor(pal.sand), state.containerBg))

    -- ④ 波浪高光：压在海面与沙滩交界的几条细带
    local waveN = math.max(0, math.floor(config.DEFAULT_BG_WAVE_COUNT or 4))
    local waveA = config.DEFAULT_BG_WAVE_ALPHA or 56
    for i = 1, waveN do
        local w = W * (0.42 + 0.16 * ((i * 7) % 3))
        local x = ((i % 2 == 0) and -1 or 1) * W * (0.06 + 0.05 * i)
        local y = -ch / 2 + sandH + 6 + (i - 1) * 11
        addNode(utils.createControl(state.rectPrefabId, x, y, w, 5,
            utils.hexToColorA(pal.wave, waveA), state.containerBg))
    end

    -- ⑤ 两团柔光：右上角暖阳、左下角水汽（大块低透明矩形，够柔和）
    addNode(utils.createControl(state.rectPrefabId, cw * 0.30, ch * 0.30, 420, 420,
        utils.hexToColorA(pal.juice4, 44), state.containerBg))
    addNode(utils.createControl(state.rectPrefabId, -cw * 0.30, -ch * 0.34, 460, 300,
        utils.hexToColorA(pal.juice2, 26), state.containerBg))

    -- ⑥ 上升气泡池（在上面一切背景元素之上）
    --   每 4 颗里混 1 颗粉色（花瓣/果汁泡），亮背景上更有夏日感
    local bn = math.max(0, math.floor(config.DEFAULT_BG_BUBBLE_COUNT or 14))
    local bsz = config.DEFAULT_BG_BUBBLE_SIZE or 14
    local balpha = config.DEFAULT_BG_BUBBLE_ALPHA or 96
    for i = 1, bn do
        local size = bsz * (0.5 + ((i * 13) % 7) / 6)
        local key = (i % 4 == 0) and pal.juice2 or pal.wave
        local c = utils.createControl(state.rectPrefabId,
            -cw / 2 + (cw + 80) * (((i * 37) % 100) / 100), 0, size, size,
            utils.hexToColorA(key, balpha), state.containerBg)
        state.fxBubbles[i] = {
            ctrl = c,
            size = size,
            x = -cw / 2 + (cw + 80) * (((i * 37) % 100) / 100),
            y = -ch / 2 + (ch + 120) * (((i * 53) % 100) / 100),
            speed = (config.DEFAULT_BG_BUBBLE_SPEED or 34) * (0.6 + ((i * 11) % 5) / 5),
            phase = i * 1.7,
            sway = 16 + (i % 4) * 7,
        }
    end

    M.ready = true
    return true
end

-- ================================================================
-- ★★ 显隐整层背景
--   ★ 游玩期必须把它收掉：这是一整块盖满画布的**不透明**夏日底色，
--     不收就会把节点图摆出来的 3D 棋盘整个盖住（真机实测就是这个现象）。
--     只有选关 / 教程 / 结算这类「客户端自己的画面」才需要它当底。
-- ================================================================
function M.setVisible(v)
    utils.setVisibleAll(M.nodes, v and true or false)
end

-- ================================================================
-- ★ 每帧：气泡上浮 + 横向摇摆
-- ================================================================
function M.update(dt)
    if not M.ready then return end
    dt = tonumber(dt) or 0
    if dt <= 0 then return end
    local ch = state.canvasH or config.DEFAULT_VIEW_HEIGHT or 600
    local top = ch / 2 + 40
    local t = state.fxTime or 0
    for i = 1, #state.fxBubbles do
        local b = state.fxBubbles[i]
        if b and b.ctrl then
            b.y = b.y + b.speed * dt
            if b.y > top then
                b.y = -ch / 2 - 40
                b.phase = b.phase + 2.3
            end
            utils.setPos(b.ctrl, b.x + math.sin(t * 0.9 + b.phase) * b.sway, b.y)
        end
    end
end

return M
