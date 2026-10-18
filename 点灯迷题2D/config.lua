-- ================================================================
-- 点灯迷题 16 · 参数配置（唯一真源）
-- ================================================================
-- 结构：一个大关 = 一张 16×16 勾线图 = 4 个 8×8 小关（左上/右上/左下/右下）。
-- 每个小关单独玩，4/4 才合成大图并触发上色演出。
-- ★ 8×8 十字翻转核满秩（64/64）→ 每个小盘面的解唯一，最优步数 = |A|。
-- ================================================================

---@diagnostic disable: undefined-global

local M = {}

-- ================================================================
-- 一、棋盘
-- ================================================================
M.DEFAULT_ROWS = 8                  -- 小关边长（8×8 = 64 格）
M.DEFAULT_COLS = 8
M.DEFAULT_CELL = 46                 -- 小关格子边长（设计坐标）
M.DEFAULT_GAP = 5
M.DEFAULT_BOARD_CX = 236            -- 右侧「当前盘面」中心
M.DEFAULT_BOARD_CY = -34
M.DEFAULT_REF_CX = -236             -- 左侧「目标图案」中心
M.DEFAULT_REF_CY = -34
M.DEFAULT_BOARD_PAD = 10            -- 棋盘底板外扩

-- ================================================================
-- 二、画布
-- ================================================================
M.DEFAULT_VIEW_WIDTH = 1280
M.DEFAULT_VIEW_HEIGHT = 720
M.DEFAULT_DESIGN_WIDTH = 1280
M.DEFAULT_DESIGN_HEIGHT = 720
M.DEFAULT_MIN_SCALE = 0.42

-- ================================================================
-- 三、动效
-- ================================================================
M.DEFAULT_ANIM_FLIP_HALF = 0.070    -- 翻牌压扁
M.DEFAULT_ANIM_FLIP_BACK = 0.150    -- 翻牌展开
M.DEFAULT_ANIM_STAGGER = 0.030      -- 涟漪错峰
M.DEFAULT_ANIM_INPUT_LOCK = 0.10    -- 额外锁（保证翻牌播完）
M.DEFAULT_ANIM_SLOT_FLY = 0.55      -- 小关完成 → 拼图块飞入槽位
M.DEFAULT_ANIM_ASSEMBLE = 0.60      -- 四块合拢
M.DEFAULT_ANIM_COLOR_STAGGER = 0.006
M.DEFAULT_ANIM_COLOR_TIME = 0.42
M.DEFAULT_ANIM_NUMBER_TIME = 0.24
M.DEFAULT_ANIM_NUMBER_POP = 1.20
M.DEFAULT_ANIM_HINT_TIME = 1.20
M.DEFAULT_ANIM_INTRO_TIME = 0.36
M.DEFAULT_ANIM_INTRO_STAGGER = 0.012
M.DEFAULT_ANIM_SHAKE = 3.0
M.DEFAULT_ANIM_SHAKE_TIME = 0.14
M.DEFAULT_SETTLE_GUARD = 0.55

-- ================================================================
-- 四、特效
-- ================================================================
M.DEFAULT_FX_PARTICLE_COUNT = 8
M.DEFAULT_FX_PARTICLE_MAX = 220
M.DEFAULT_FX_PARTICLE_SPEED = 220
M.DEFAULT_FX_PARTICLE_SIZE = 8
M.DEFAULT_FX_PARTICLE_LIFE = 0.42
M.DEFAULT_FX_PARTICLE_GRAVITY = 700
M.DEFAULT_FX_PARTICLE_SPIN = 200
M.DEFAULT_FX_RING_TIME = 0.36
M.DEFAULT_FX_RING_SCALE = 3.0
M.DEFAULT_FX_RING_WIDTH = 3
M.DEFAULT_FX_FLOAT_SIZE = 24
M.DEFAULT_FX_FLOAT_LIFE = 0.70
M.DEFAULT_FX_FLOAT_RISE = 62
M.DEFAULT_FX_CONFETTI_COUNT = 44
M.DEFAULT_FX_CONFETTI_SPEED = 380
M.DEFAULT_FX_CONFETTI_LIFE = 1.25

-- ================================================================
-- 五、UI
-- ================================================================
M.DEFAULT_HUD_TITLE_SIZE = 30
M.DEFAULT_HUD_SUB_SIZE = 15
M.DEFAULT_HUD_STAT_SIZE = 30
M.DEFAULT_HUD_STAT_LABEL_SIZE = 13
M.DEFAULT_BTN_W = 132
M.DEFAULT_BTN_H = 48
M.DEFAULT_BTN_SIZE = 18
M.DEFAULT_BTN_PRESS = 0.94
M.DEFAULT_BTN_DISABLED_ALPHA = 96
M.DEFAULT_CHIP = 46                 -- 顶部拼图槽单块尺寸
M.DEFAULT_CHIP_GAP = 8
M.DEFAULT_CHIP_Y = 258
M.DEFAULT_MODE_BTN_W = 122
M.DEFAULT_MODE_BTN_H = 38

-- 黑幕过渡（fadeScreen.lua 用）
M.DEFAULT_FADE_IN_TIME = 0.18
M.DEFAULT_FADE_HOLD_TIME = 0.24
M.DEFAULT_FADE_OUT_TIME = 0.20
M.DEFAULT_FADE_MAX_ALPHA = 255

-- ================================================================
-- 六、玩法
-- ================================================================
M.DEFAULT_A_BY_PIECE = { 2, 3, 3, 4 }   -- 四块小关的 |A|（左上/右上/左下/右下）
M.DEFAULT_STAR_TWO_EXTRA = 2
M.DEFAULT_HINT_ENABLED = 1
M.DEFAULT_UNDO_ENABLED = 1
M.DEFAULT_MODE = 1                  -- 1=找不同复原 / 2=无参照复原

-- ================================================================
-- 七、配色（棋盘是白纸黑线，UI 是深色，对比拉满）
-- ================================================================
M.DEFAULT_PALETTE = {
    bg        = "070A12",
    bgGlow    = "152348",
    bgGlow2   = "2A1550",
    panel     = "111A2E",
    panelEdge = "1E2A47",
    paper     = "F7F8FA",   -- 棋盘白底
    ink       = "111318",   -- 勾线
    inkDim    = "4A5266",   -- 未完成槽位的示意线
    cellOn    = "FFCB6B",
    cellOnTop = "FFE9B8",
    glow      = "FFB020",
    cellOff   = "1B2742",
    cellOffTop = "2A3A60",
    accent    = "4CC9F0",
    accentSoft = "1E4A63",
    good      = "5BE7A9",
    star      = "FFD166",
    text      = "E9F0FF",
    textDim   = "8296B8",
    btn       = "1C2740",
    btnDown   = "27364F",
    btnText   = "DCE7FA",
    scrim     = "05070F",
}

-- ================================================================
-- 八、图案（16×16 勾线；# = 黑线，. = 白底）
-- ================================================================
local CAT = {
"................",
"................",
"...#........#...",
"..#.#......#.#..",
"..#..######..#..",
"..#..........#..",
"..#..#....#..#..",
"..#..#....#..#..",
"..#....##....#..",
"..#..........#..",
"..#..........#..",
"...#........#...",
"....########....",
"................",
"................",
"................",
}

local MUSHROOM = {
"................",
"................",
"....########....",
"...##......##...",
"..##..#..#..##..",
".##..........##.",
".##############.",
".......##.......",
".......##.......",
".......##.......",
"......####......",
"................",
"................",
"................",
"................",
"................",
}

-- 每个大关：一张 16×16 图 + 主色/辅助色/高光色
M.CHAPTERS = {
    {
        key = "cat", name = "猫脸", pic = CAT,
        colors = { "B8C2CC", "E8EEF5", "FF9AA2" },
        tip = "点一格，十字五格一起黑白翻转",
    },
    {
        key = "mushroom", name = "蘑菇", pic = MUSHROOM,
        colors = { "E4572E", "F2E9D6", "FFD666" },
        tip = "把左边那条线，在右边一比一还原",
    },
}

function M.chapterCount()
    return #M.CHAPTERS
end

function M.getChapter(i)
    i = math.floor(tonumber(i) or 0)
    if i < 1 or i > #M.CHAPTERS then return nil end
    return M.CHAPTERS[i]
end

-- 四块的名称与象限原点（0 基）
M.PIECES = {
    { name = "左上", ox = 0, oy = 0 },
    { name = "右上", ox = 8, oy = 0 },
    { name = "左下", ox = 0, oy = 8 },
    { name = "右下", ox = 8, oy = 8 },
}

return M
