-- ================================================================
-- 点灯迷题 2D · 参数配置（唯一真源）
-- ================================================================
-- ★ 规则：脚本里不写魔法数字，所有可调项都放这里，命名统一 DEFAULT_*。
-- ★ 本作是【纯客户端 2D】：棋盘、玩法、判定、动效全部在客户端完成，
--   不依赖服务器节点图（旧版那 4 条信号只在 DEFAULT_SIGNAL_ENABLED=1 时上报战绩）。
--
-- 棋盘固定 5 行 × 6 列 = 30 格；下标 idx = 行*6 + 列（0 基）。
-- 按下某格会同时翻转「它自己 + 上下左右」共 5 格（越界忽略）。
-- ================================================================

---@diagnostic disable: undefined-global

local M = {}

-- ================================================================
-- 一、棋盘几何
-- ================================================================
M.DEFAULT_ROWS = 5                     -- 行数（固定，改了关卡数据也要重生成）
M.DEFAULT_COLS = 6                     -- 列数
M.DEFAULT_CELL = 100                   -- 单个灯格边长（设计坐标）
M.DEFAULT_GAP = 11                     -- 灯格间距
M.DEFAULT_CELL_INSET = 7               -- 灯体相对格子的内缩（留出缝隙感）
M.DEFAULT_BOARD_CX = -215              -- 棋盘中心 X（设计坐标，原点=画布中心）
M.DEFAULT_BOARD_CY = -18               -- 棋盘中心 Y
M.DEFAULT_BOARD_PAD = 14               -- 棋盘底板比灯阵外扩多少

-- ================================================================
-- 二、画布与自适应
-- ================================================================
M.DEFAULT_VIEW_WIDTH = 1280            -- GetUICanvasSize 失败时的兜底宽
M.DEFAULT_VIEW_HEIGHT = 720            -- 兜底高
M.DEFAULT_DESIGN_WIDTH = 1280          -- 设计基准宽（所有坐标按它写）
M.DEFAULT_DESIGN_HEIGHT = 720          -- 设计基准高
M.DEFAULT_MIN_SCALE = 0.42             -- 自适应缩放下限（再小就没法点了）

-- ================================================================
-- 三、动效时长与曲线（★ 交互手感全靠这一组）
-- ================================================================
M.DEFAULT_ANIM_PRESS_TIME = 0.085      -- 按下回弹时长
M.DEFAULT_ANIM_PRESS_SCALE = 0.90      -- 按下时缩到多少
M.DEFAULT_ANIM_FLIP_HALF = 0.072       -- 翻牌「压扁」半程
M.DEFAULT_ANIM_FLIP_BACK = 0.155       -- 翻牌「展开」半程
M.DEFAULT_ANIM_STAGGER = 0.032         -- 十字涟漪每远一环的延迟（秒）
M.DEFAULT_ANIM_SPAWN_TIME = 0.34       -- 进关时灯格入场时长
M.DEFAULT_ANIM_SPAWN_STAGGER = 0.021   -- 入场逐格错峰
M.DEFAULT_ANIM_HINT_TIME = 1.10        -- 提示高亮持续
M.DEFAULT_ANIM_HINT_PULSE = 0.46       -- 提示呼吸周期
M.DEFAULT_ANIM_NUMBER_TIME = 0.24      -- 数字变化弹跳时长
M.DEFAULT_ANIM_NUMBER_POP = 1.22       -- 数字弹跳峰值缩放
M.DEFAULT_ANIM_SHAKE = 4.0             -- 触发强翻转时的屏幕微震（像素）
M.DEFAULT_ANIM_SHAKE_TIME = 0.16

-- 光晕呼吸：亮灯不是死的，整屏像灯海在呼吸
M.DEFAULT_BREATH_SPEED = 1.25          -- 角速度（越大越快）
M.DEFAULT_BREATH_MIN = 0.42            -- 光晕最低不透明度系数
M.DEFAULT_BREATH_MAX = 1.00            -- 最高
M.DEFAULT_BREATH_PHASE = 0.55          -- 相邻格子的相位差（错开才像活的）
M.DEFAULT_NEARWIN_LIT = 3              -- 剩这么多盏时呼吸加剧
M.DEFAULT_NEARWIN_GAIN = 1.55          -- 加剧倍数

-- 输入手感
M.DEFAULT_INPUT_BUFFER = 1             -- 1=动画中只留最后一次点击并自动兑现
M.DEFAULT_COMBO_WINDOW = 0.62          -- 两次有效操作间隔小于它算连击
M.DEFAULT_COMBO_FAST = 0.72            -- 连击时翻转时长乘这个系数（更快）
M.DEFAULT_SETTLE_GUARD = 0.55          -- 解锁看门狗：超时强制放行，绝不永久锁死

-- ================================================================
-- 四、特效
-- ================================================================
M.DEFAULT_FX_PARTICLE_COUNT = 9        -- 点亮时迸溅粒子数
M.DEFAULT_FX_PARTICLE_MAX = 200        -- 同时存在的粒子上限
M.DEFAULT_FX_PARTICLE_SPEED = 250
M.DEFAULT_FX_PARTICLE_SIZE = 9
M.DEFAULT_FX_PARTICLE_LIFE = 0.46
M.DEFAULT_FX_PARTICLE_GRAVITY = 760
M.DEFAULT_FX_PARTICLE_SPIN = 240
M.DEFAULT_FX_RING_TIME = 0.40          -- 方形冲击波时长
M.DEFAULT_FX_RING_SCALE = 3.2          -- 冲击波扩散到的倍数
M.DEFAULT_FX_RING_WIDTH = 3            -- 冲击波边框粗细
M.DEFAULT_FX_FLOAT_SIZE = 26           -- 飘字字号
M.DEFAULT_FX_FLOAT_LIFE = 0.72
M.DEFAULT_FX_FLOAT_RISE = 72
M.DEFAULT_FX_CONFETTI_COUNT = 40       -- 通关彩带数量
M.DEFAULT_FX_CONFETTI_SPEED = 420
M.DEFAULT_FX_CONFETTI_LIFE = 1.30

-- ================================================================
-- 五、右侧信息栏（HUD）
-- ================================================================
M.DEFAULT_HUD_X = 340                  -- 面板中心 X
M.DEFAULT_HUD_W = 360                  -- 面板宽
M.DEFAULT_HUD_H = 566                  -- 面板高（与棋盘等高）
M.DEFAULT_HUD_TITLE_SIZE = 34          -- 关卡名字号
M.DEFAULT_HUD_SUB_SIZE = 18            -- 副标题字号
M.DEFAULT_HUD_STAT_SIZE = 34           -- 步数 / 剩余 数值字号
M.DEFAULT_HUD_STAT_LABEL_SIZE = 16     -- 数值上方小标题字号
M.DEFAULT_HUD_TIP_SIZE = 17            -- 底部提示字号
M.DEFAULT_HUD_STAT_W = 148             -- 统计小卡宽
M.DEFAULT_HUD_STAT_H = 92              -- 统计小卡高
M.DEFAULT_HUD_STAT_GAP = 16
M.DEFAULT_BTN_W = 148                  -- 功能按钮宽
M.DEFAULT_BTN_H = 52                   -- 功能按钮高
M.DEFAULT_BTN_GAP = 18
M.DEFAULT_BTN_SIZE = 21                -- 按钮字号
M.DEFAULT_BTN_PRESS = 0.94             -- 按下缩放
M.DEFAULT_BTN_DISABLED_ALPHA = 96

-- ================================================================
-- 六、选关界面
-- ================================================================
M.DEFAULT_SELECT_PANEL_W = 1040
M.DEFAULT_SELECT_PANEL_H = 640
M.DEFAULT_SELECT_COLS = 5              -- 每行卡片数
M.DEFAULT_SELECT_ROWS = 4              -- 每页行数
M.DEFAULT_SELECT_CARD_W = 150
M.DEFAULT_SELECT_CARD_H = 96
M.DEFAULT_SELECT_CARD_GAP_X = 16
M.DEFAULT_SELECT_CARD_GAP_Y = 16
M.DEFAULT_SELECT_TITLE_SIZE = 40
M.DEFAULT_SELECT_CARD_NUM_SIZE = 26
M.DEFAULT_SELECT_CARD_SUB_SIZE = 18    -- 卡片星级字号（14 太小，★ 会糊成一个点）
M.DEFAULT_SELECT_HINT_SIZE = 16
M.DEFAULT_SELECT_OVERLAY_ALPHA = 186   -- 选关时压暗游玩画面的遮罩
M.DEFAULT_SELECT_ENTER_TIME = 0.30     -- 整页入场
M.DEFAULT_SELECT_CARD_STAGGER = 0.018  -- 卡片逐张弹出
M.DEFAULT_SELECT_PAGE_TIME = 0.20      -- 翻页滑动
M.DEFAULT_SELECT_PAGE_SLIDE = 90       -- 翻页时横向位移

-- ================================================================
-- 七、通关结算
-- ================================================================
M.DEFAULT_WIN_OVERLAY_ALPHA = 172      -- 全屏遮罩
M.DEFAULT_WIN_CARD_W = 620             -- 结果卡宽
M.DEFAULT_WIN_CARD_H = 520             -- 结果卡高
M.DEFAULT_WIN_CARD_X = 250             -- 结果卡中心 X
M.DEFAULT_WIN_PHOTO_X = -330           -- 「战利品照片」（缩小的棋盘）中心 X
M.DEFAULT_WIN_PHOTO_Y = 8
M.DEFAULT_WIN_PHOTO_SCALE = 0.60       -- 棋盘缩到多大
M.DEFAULT_WIN_PHOTO_TILT = -3.5        -- 照片歪一点更好看
M.DEFAULT_WIN_PHOTO_TIME = 0.52
M.DEFAULT_WIN_CARD_TIME = 0.46
M.DEFAULT_WIN_TITLE_SIZE = 38
M.DEFAULT_WIN_STAR_SIZE = 58           -- 星号字号（用 ★ / ☆）
M.DEFAULT_WIN_STAR_GAP = 14
M.DEFAULT_WIN_STAR_TIME = 0.34
M.DEFAULT_WIN_STAR_DELAY = 0.13
M.DEFAULT_WIN_TEXT_SIZE = 20
M.DEFAULT_WIN_NUM_SIZE = 40
M.DEFAULT_WIN_BTN_W = 168
M.DEFAULT_WIN_BTN_H = 52
M.DEFAULT_WIN_WAVE_STAGGER = 0.034     -- 通关时对角波浪熄灭的错峰
M.DEFAULT_WIN_WAVE_TIME = 0.30

-- ================================================================
-- 八、黑幕过渡
-- ================================================================
M.DEFAULT_FADE_IN_TIME = 0.18
M.DEFAULT_FADE_HOLD_TIME = 0.26
M.DEFAULT_FADE_OUT_TIME = 0.20
M.DEFAULT_FADE_MAX_ALPHA = 255

-- ================================================================
-- 九、玩法与存档
-- ================================================================
M.DEFAULT_UNDO_ENABLED = 1             -- 1=允许撤销（误点救星）
M.DEFAULT_HINT_ENABLED = 1             -- 1=允许提示（钉出剩余解里的一格）
M.DEFAULT_STAR_TWO_EXTRA = 2           -- 多用 ≤ 最优步数+2 得 2 星，否则 1 星
M.DEFAULT_AUTO_ADVANCE = 0             -- 1=通关后自动进下一关（0=等玩家点）
M.DEFAULT_PROGRESS_SAVE = 1            -- 1=通关进度存服务器变量

-- ================================================================
-- 十、信号（默认全关：本作不依赖服务器节点图）
-- ================================================================
M.DEFAULT_SIGNAL_ENABLED = 0           -- 1=通关时向服务器上报
M.DEFAULT_SIGNAL_WIN = "2D关卡胜利"     -- 出站：关卡号 + 步数
M.DEFAULT_SIGNAL_VAR = "点灯迷题进度"    -- 服务器变量名（记录已通关数）

-- ================================================================
-- 十一、配色（深色霓虹：亮灯要「跳出来」）
-- ================================================================
M.DEFAULT_PALETTE = {
    bg          = "0A0E1A",   -- 全屏底色
    bgGlow      = "14224A",   -- 背景装饰光斑
    bgGlow2     = "2A1550",   -- 第二块光斑（紫）
    panel       = "121A2E",   -- 右侧信息栏 / 面板
    panelEdge   = "1E2A47",   -- 面板描边
    boardBg     = "0F1730",   -- 棋盘底板
    boardEdge   = "1B2A4A",   -- 棋盘描边（用外框矩形模拟）
    cellOff     = "1B2742",   -- 熄灭的灯（比底色亮一档，才看得出格子在）
    cellOffTop  = "2A3A60",   -- 熄灭灯的顶部高光（做出厚度）
    cellOn      = "FFCB6B",   -- 点亮的灯
    cellOnTop   = "FFE9B8",   -- 点亮灯的顶部高光
    glow        = "FFB020",   -- 光晕
    accent      = "4CC9F0",   -- 强调色（提示 / 选中）
    accentSoft  = "1E4A63",   -- 强调色底
    text        = "E9F0FF",
    textDim     = "8296B8",
    good        = "5BE7A9",
    star        = "FFD166",
    starOff     = "2A3550",
    btn         = "1C2740",
    btnDown     = "27364F",
    btnText     = "DCE7FA",
    winCard     = "101A30",
    scrim       = "05070F",
}

-- ================================================================
-- 十二、关卡数据
--   flips : 生成本关用的点位序列（0 基）——同时也是标准解
--   steps : 最优步数 = #flips
--   tip   : 关卡提示（HUD 底部显示）
--   ★ 剩余解 = flips 集合 XOR 玩家已按集合（按压可交换且按两次抵消），
--     所以提示与星级判定都是精确的，不需要解方程。
-- ================================================================

-- >>> LEVELS_BEGIN
M.LEVELS = {
    -- ===== 第01关（1 步）=====
    {
        name = "第01关",
        steps = 1,
        tip = "点一格，连上下左右一起翻转",
        flips = {19},
    },
    -- ===== 第02关（2 步）=====
    {
        name = "第02关",
        steps = 2,
        tip = "同一格按两次，等于没按",
        flips = {6,14},
    },
    -- ===== 第03关（3 步）=====
    {
        name = "第03关",
        steps = 3,
        tip = "边角牵动少，先定边角",
        flips = {18,28,29},
    },
    -- ===== 第04关（4 步）=====
    {
        name = "第04关",
        steps = 4,
        tip = "先数亮着的灯，逐个抵消",
        flips = {3,10,15,22},
    },
    -- ===== 第05关（5 步）=====
    {
        name = "第05关",
        steps = 5,
        tip = "步数更多，一层层往下推",
        flips = {1,13,19,22,26},
    },
    -- ===== 第06关（5 步）=====
    {
        name = "第06关",
        steps = 5,
        tip = "",
        flips = {7,18,23,26,28},
    },
    -- ===== 第07关（5 步）=====
    {
        name = "第07关",
        steps = 5,
        tip = "",
        flips = {0,2,7,18,23},
    },
    -- ===== 第08关（5 步）=====
    {
        name = "第08关",
        steps = 5,
        tip = "",
        flips = {3,7,17,19,26},
    },
    -- ===== 第09关（6 步）=====
    {
        name = "第09关",
        steps = 6,
        tip = "",
        flips = {4,6,14,15,23,29},
    },
    -- ===== 第10关（6 步）=====
    {
        name = "第10关",
        steps = 6,
        tip = "",
        flips = {1,4,5,7,21,27},
    },
    -- ===== 第11关（6 步）=====
    {
        name = "第11关",
        steps = 6,
        tip = "",
        flips = {10,12,18,19,23,28},
    },
    -- ===== 第12关（6 步）=====
    {
        name = "第12关",
        steps = 6,
        tip = "",
        flips = {10,13,21,22,23,24},
    },
    -- ===== 第13关（6 步）=====
    {
        name = "第13关",
        steps = 6,
        tip = "",
        flips = {15,17,18,25,28,29},
    },
    -- ===== 第14关（6 步）=====
    {
        name = "第14关",
        steps = 6,
        tip = "",
        flips = {7,9,12,13,14,23},
    },
    -- ===== 第15关（7 步）=====
    {
        name = "第15关",
        steps = 7,
        tip = "",
        flips = {0,3,4,7,13,22,26},
    },
    -- ===== 第16关（7 步）=====
    {
        name = "第16关",
        steps = 7,
        tip = "",
        flips = {1,14,19,20,21,24,28},
    },
    -- ===== 第17关（7 步）=====
    {
        name = "第17关",
        steps = 7,
        tip = "",
        flips = {2,4,14,15,16,17,29},
    },
    -- ===== 第18关（7 步）=====
    {
        name = "第18关",
        steps = 7,
        tip = "",
        flips = {0,6,13,24,25,28,29},
    },
    -- ===== 第19关（7 步）=====
    {
        name = "第19关",
        steps = 7,
        tip = "",
        flips = {1,6,7,11,22,26,27},
    },
    -- ===== 第20关（7 步）=====
    {
        name = "第20关",
        steps = 7,
        tip = "",
        flips = {1,2,6,9,15,23,27},
    },
    -- ===== 第21关（7 步）=====
    {
        name = "第21关",
        steps = 7,
        tip = "",
        flips = {4,14,16,17,23,26,29},
    },
    -- ===== 第22关（8 步）=====
    {
        name = "第22关",
        steps = 8,
        tip = "",
        flips = {2,4,11,12,20,24,25,26},
    },
    -- ===== 第23关（8 步）=====
    {
        name = "第23关",
        steps = 8,
        tip = "",
        flips = {0,17,19,20,21,22,27,28},
    },
    -- ===== 第24关（8 步）=====
    {
        name = "第24关",
        steps = 8,
        tip = "",
        flips = {2,6,14,17,18,22,27,28},
    },
    -- ===== 第25关（8 步）=====
    {
        name = "第25关",
        steps = 8,
        tip = "",
        flips = {3,12,14,18,20,23,24,28},
    },
    -- ===== 第26关（8 步）=====
    {
        name = "第26关",
        steps = 8,
        tip = "",
        flips = {9,10,11,14,15,16,18,21},
    },
    -- ===== 第27关（8 步）=====
    {
        name = "第27关",
        steps = 8,
        tip = "",
        flips = {1,6,8,12,20,21,22,26},
    },
    -- ===== 第28关（9 步）=====
    {
        name = "第28关",
        steps = 9,
        tip = "",
        flips = {7,8,9,11,17,19,21,28,29},
    },
    -- ===== 第29关（9 步）=====
    {
        name = "第29关",
        steps = 9,
        tip = "",
        flips = {5,8,11,18,20,22,23,24,26},
    },
    -- ===== 第30关（9 步）=====
    {
        name = "第30关",
        steps = 9,
        tip = "",
        flips = {6,7,8,10,18,19,23,27,28},
    },
    -- ===== 第31关（9 步）=====
    {
        name = "第31关",
        steps = 9,
        tip = "",
        flips = {0,2,3,8,10,17,22,25,26},
    },
    -- ===== 第32关（9 步）=====
    {
        name = "第32关",
        steps = 9,
        tip = "",
        flips = {5,7,11,12,14,17,22,27,29},
    },
    -- ===== 第33关（9 步）=====
    {
        name = "第33关",
        steps = 9,
        tip = "",
        flips = {0,4,10,13,19,21,25,26,28},
    },
    -- ===== 第34关（10 步）=====
    {
        name = "第34关",
        steps = 10,
        tip = "",
        flips = {2,6,10,11,12,16,18,19,23,28},
    },
    -- ===== 第35关（10 步）=====
    {
        name = "第35关",
        steps = 10,
        tip = "",
        flips = {0,2,6,10,13,16,17,21,27,29},
    },
    -- ===== 第36关（10 步）=====
    {
        name = "第36关",
        steps = 10,
        tip = "",
        flips = {1,4,12,17,20,21,23,25,26,28},
    },
    -- ===== 第37关（10 步）=====
    {
        name = "第37关",
        steps = 10,
        tip = "",
        flips = {0,7,9,10,14,17,19,22,23,26},
    },
    -- ===== 第38关（10 步）=====
    {
        name = "第38关",
        steps = 10,
        tip = "",
        flips = {3,5,7,13,16,18,19,22,23,24},
    },
    -- ===== 第39关（10 步）=====
    {
        name = "第39关",
        steps = 10,
        tip = "",
        flips = {5,7,8,10,11,12,13,23,24,27},
    },
    -- ===== 第40关（10 步）=====
    {
        name = "第40关",
        steps = 10,
        tip = "",
        flips = {0,3,8,9,14,16,17,20,22,29},
    },
    -- ===== 第41关（11 步）=====
    {
        name = "第41关",
        steps = 11,
        tip = "",
        flips = {1,2,5,7,9,11,13,14,16,22,24},
    },
    -- ===== 第42关（11 步）=====
    {
        name = "第42关",
        steps = 11,
        tip = "",
        flips = {1,2,9,15,17,19,23,24,27,28,29},
    },
    -- ===== 第43关（11 步）=====
    {
        name = "第43关",
        steps = 11,
        tip = "",
        flips = {0,1,3,9,11,14,18,19,24,27,28},
    },
    -- ===== 第44关（11 步）=====
    {
        name = "第44关",
        steps = 11,
        tip = "",
        flips = {4,10,11,14,15,17,20,21,24,25,29},
    },
    -- ===== 第45关（11 步）=====
    {
        name = "第45关",
        steps = 11,
        tip = "",
        flips = {2,5,9,12,15,16,18,21,24,25,29},
    },
    -- ===== 第46关（11 步）=====
    {
        name = "第46关",
        steps = 11,
        tip = "",
        flips = {5,7,8,9,10,14,20,22,24,26,28},
    },
    -- ===== 第47关（12 步）=====
    {
        name = "第47关",
        steps = 12,
        tip = "",
        flips = {5,7,9,11,12,14,15,18,20,22,25,28},
    },
    -- ===== 第48关（12 步）=====
    {
        name = "第48关",
        steps = 12,
        tip = "",
        flips = {3,5,7,8,10,13,16,20,21,23,25,27},
    },
    -- ===== 第49关（12 步）=====
    {
        name = "第49关",
        steps = 12,
        tip = "",
        flips = {0,1,2,10,12,14,15,16,22,23,25,26},
    },
    -- ===== 第50关（12 步）=====
    {
        name = "第50关",
        steps = 12,
        tip = "",
        flips = {2,3,8,9,10,13,16,17,18,19,20,21},
    },
}
-- <<< LEVELS_END

-- ================================================================
-- 关卡查询
-- ================================================================
function M.levelCount()
    return #M.LEVELS
end

function M.getLevel(index)
    local i = math.floor(tonumber(index) or 0)
    if i < 1 or i > #M.LEVELS then return nil end
    return M.LEVELS[i]
end

function M.getLevelFlips(index)
    local d = M.getLevel(index)
    if not d or type(d.flips) ~= "table" then return {} end
    local out = {}
    for i = 1, #d.flips do
        out[i] = math.floor(tonumber(d.flips[i]) or -1)
    end
    return out
end

-- 星级：n=实际步数，best=最优步数。3 星=最优，2 星=最优+2 以内，1 星=通关
function M.starsFor(index, n)
    local d = M.getLevel(index)
    local best = d and math.floor(tonumber(d.steps) or 0) or 0
    local used = math.floor(tonumber(n) or 0)
    if best <= 0 then return 1 end
    if used <= best then return 3 end
    if used <= best + (M.DEFAULT_STAR_TWO_EXTRA or 2) then return 2 end
    return 1
end

return M
