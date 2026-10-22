-- ================================================================
-- 瓦雷莎的果园救急 · 参数真源
-- ================================================================
-- ★ 本文件里的 DEFAULT_* 是全部可调参数的「唯一真源」。
-- ★ 分工：客户端只做 UI（果园地图选关 / 教学卡 / 游玩 HUD / 结算），
--   3D 果园棋盘与点击判定在服务器节点图里，两边用 signal.lua 的 4+2 条信号对接。
-- ★ 关卡数据 M.LEVELS 由 _gen_levels.py 覆盖（见文件末尾的标记区）。
-- ================================================================

---@diagnostic disable: undefined-global

local M = {}

-- ================================================================
-- ★ 棋盘几何（固定 5 行 × 6 列 = 30 个点位）
--   idx = 行 * 6 + 列（行 0..4 从上往下，列 0..5 从左往右）
--   踩一个点位：自身 + 上下左右一起「水果 ↔ 果汁」翻转，越界忽略。
-- ================================================================
M.DEFAULT_ROWS = 5
M.DEFAULT_COLS = 6

-- ================================================================
-- ★ 视口
-- ================================================================
M.DEFAULT_VIEW_WIDTH = 800
M.DEFAULT_VIEW_HEIGHT = 600

-- ================================================================
-- ★ 黑幕过渡
-- ================================================================
M.DEFAULT_FADE_IN_TIME = 0.20
M.DEFAULT_FADE_HOLD_TIME = 0.34
M.DEFAULT_FADE_OUT_TIME = 0.24
M.DEFAULT_FADE_MAX_ALPHA = 255

-- ================================================================
-- ★ 转场（transition 模块）：两种形态的节奏（秒）
--   fade  = 黑幕淡入淡出  —— 重玩 / 关卡之间换片
--   split = 天地撕开      —— 选关 ↔ 游玩
--     进入果园：天空向上移出屏幕 + 地面向下移出屏幕（只有 SPLIT_OPEN 一段）
--     返回选关：天空从上方、地面从下方合拢 → 停一下 → 整体淡出
-- ================================================================
M.DEFAULT_TRANS_FADE_IN = 0.18
M.DEFAULT_TRANS_FADE_HOLD = 0.04
M.DEFAULT_TRANS_FADE_OUT = 0.22
M.DEFAULT_TRANS_HOLD = 0.04
M.DEFAULT_TRANS_SPLIT_OPEN = 0.42     -- 进入果园：板分开的总时长（0.5s 以内）
M.DEFAULT_TRANS_SPLIT_MERGE = 0.24    -- 返回选关：天空 / 地面滑入合拢
M.DEFAULT_TRANS_SPLIT_FADE = 0.16     -- 返回选关：合拢后整体淡出

-- ================================================================
-- ★★ 果园地图选关（map 模块）
--   50 片果园沿一条蜿蜒土路横向排开；地图整条长图可拖动 / 点左右箭头平移。
--   · 节点状态：未解锁（青果）/ 可挑战（熟果）/ 已还原（彩色 + 星）
--   · 当前节点：金圈 + 小龙站台 + 呼吸脉动
--   · 尺寸都以「设计基准 800×600」为 1，按画布等比放大（k）
-- ================================================================
M.DEFAULT_MAP_NODE_SPACING = 196      -- 相邻果园的水平间距
M.DEFAULT_MAP_EDGE_PAD = 300          -- 首尾留白（第一片/最后一片离地图端点）
M.DEFAULT_MAP_WAVE_AMP = 62           -- 土路上下起伏幅度
M.DEFAULT_MAP_WAVE_PHASE = 0.62       -- 每前进一片果园的相位增量（弧度）
M.DEFAULT_MAP_NODE_SIZE = 66          -- 果实节点外框边长
M.DEFAULT_MAP_NODE_INNER = 52         -- 果实节点内芯边长
M.DEFAULT_MAP_NODE_HIT = 92           -- 节点命中区边长（要比节点大一圈）
M.DEFAULT_MAP_CURSOR_RING = 98        -- 当前节点的金圈边长
M.DEFAULT_MAP_DOT_SIZE = 10           -- 土路上的小石子边长
M.DEFAULT_MAP_DOT_STEP = 46           -- 相邻石子间距
M.DEFAULT_MAP_TOP_RATIO = 0.17        -- 顶部标题区占画布高比例
M.DEFAULT_MAP_BOTTOM_RATIO = 0.20     -- 底部操作区占画布高比例
M.DEFAULT_MAP_TITLE_SIZE = 30
M.DEFAULT_MAP_TEXT_SIZE = 19
M.DEFAULT_MAP_HINT_SIZE = 15
M.DEFAULT_MAP_BTN_W = 62              -- 左右箭头宽
M.DEFAULT_MAP_BTN_H = 96              -- 左右箭头高
M.DEFAULT_MAP_ENTER_BTN_W = 214       -- 「进入果园」按钮宽
M.DEFAULT_MAP_ENTER_BTN_H = 56
M.DEFAULT_MAP_HANDBOOK_BTN_W = 148    -- 「教程」按钮宽（键名沿用旧拼写，编辑器 DEFAULTS 靠它对齐）
M.DEFAULT_MAP_HANDBOOK_BTN_H = 46
M.DEFAULT_MAP_STEP_TIME = 0.34        -- 箭头平移一段用时（秒）
M.DEFAULT_MAP_SNAP_TIME = 0.26        -- 松手后吸附到最近节点用时（秒）
M.DEFAULT_MAP_FRICTION = 3.4          -- 拖拽松手后的惯性衰减（每秒）
M.DEFAULT_MAP_INERTIA_MIN = 60        -- 惯性初速低于它就不飞了
M.DEFAULT_MAP_DRAG_THRESHOLD = 10     -- 位移小于它算点击，否则算拖拽
M.DEFAULT_MAP_DRAG_SOUND_GAP = 0.09   -- 拖动音效最小间隔（秒）：防止快速滑动时连成机关枪
M.DEFAULT_MAP_LOCK_AHEAD = 1          -- 解锁进度：已还原 + N 片可挑战
M.DEFAULT_MAP_TREE_COUNT = 44         -- 土路两旁的果树数量
M.DEFAULT_MAP_BUSH_COUNT = 34         -- 灌木数量
M.DEFAULT_MAP_FLOWER_COUNT = 40       -- 小花数量
M.DEFAULT_MAP_INTRO_TIME = 0.46       -- 地图整体入场时长

-- ---- ★ 序章读完后的「点这里」引导（光圈 + 气泡 + 指示三角）----
--   触发：地图首屏自动弹的序章被关掉那一刻（game.lua → map.guideEnter(true)）；
--   消失：进关成功 / 离开选关页。只出现这一次，不打扰老玩家。
M.DEFAULT_MAP_GUIDE_PAD = 16          -- 光圈比「进入果园」按钮外扩多少像素
M.DEFAULT_MAP_GUIDE_PULSE = 1.4       -- 光圈扩散一圈的周期（秒）；越小越急促
M.DEFAULT_MAP_GUIDE_TEXT_SIZE = 16    -- 气泡文字字号
M.DEFAULT_MAP_GUIDE_BUBBLE_W = 186    -- 气泡宽（够放 7 个汉字）
M.DEFAULT_MAP_GUIDE_BUBBLE_H = 40     -- 气泡高（★ 别低于 36：文本框最小高度）

-- ================================================================
-- ★★ 教学卡 / 玩法手册（guide 模块）
--   前 5 片果园是教程关：进关时弹一张「一课一图两句话」的小卡片，
--   不再一上来就摊开一整本图册。
-- ================================================================
M.DEFAULT_GUIDE_OVERLAY_ALPHA = 192
M.DEFAULT_GUIDE_PANEL_W = 640
M.DEFAULT_GUIDE_PANEL_H = 470
M.DEFAULT_GUIDE_TITLE_SIZE = 27
M.DEFAULT_GUIDE_TEXT_SIZE = 18
M.DEFAULT_GUIDE_HINT_SIZE = 15
M.DEFAULT_GUIDE_CELL = 44             -- 示意图单格边长
M.DEFAULT_GUIDE_GAP = 8
M.DEFAULT_GUIDE_BTN_W = 152
M.DEFAULT_GUIDE_BTN_H = 46
M.DEFAULT_GUIDE_AUTO_SHOW = 1         -- 教程关进关自动弹教学卡：1=自动 / 0=只从按钮打开
-- ★ 首屏序章要等服务器存档（「服客同步存档信息」）到了再决定弹不弹：
--   已通关 > 0 的老玩家不该再看一遍。这个值是**最多等多久**（秒）——
--   等不到就当新玩家直接弹（节点图没接存档也不会卡在空地图上）。
M.DEFAULT_PROLOGUE_WAIT = 0.6

-- ================================================================
-- ★ 游玩期 HUD（3D 棋盘由节点图渲染，客户端**不压任何常驻信息与按钮**）
-- ================================================================
-- ★ 已删除的参数（游玩界面去按钮，连同对应的控件一起删）：
--   DEFAULT_HUD_BTN_W / DEFAULT_HUD_BTN_H    —— 「教程」「回果园」按钮尺寸
--   DEFAULT_HUD_JUICE_W / DEFAULT_HUD_JUICE_H —— 「还剩 N 格果汁」胶囊尺寸
--   回果园改由服务器信号「服客进入选关」驱动，客户端不再提供返回按钮。
M.DEFAULT_HUD_HINT_SIZE = 15
M.DEFAULT_HUD_MARGIN = 30
M.DEFAULT_HUD_BAR_W = 500
M.DEFAULT_HUD_BAR_H = 72
-- ★ 左上角临时提示开关（默认 0 = 完全干净）：
--   1 = 「小龙正在摆果园…」这类临时状态时出现一条提示（加载态，防玩家以为卡死）；
--   0 = 连临时提示也不显示，左上角永远空。
M.DEFAULT_HUD_TRANSIENT_HINT = 0

-- ================================================================
-- ★ 胜利结算
-- ================================================================
M.DEFAULT_WIN_OVERLAY_ALPHA = 168
M.DEFAULT_WIN_PANEL_W = 680
M.DEFAULT_WIN_PANEL_H = 462
M.DEFAULT_WIN_TITLE_SIZE = 44
M.DEFAULT_WIN_TEXT_SIZE = 21
M.DEFAULT_WIN_BTN_W = 160   -- 上限；面板窄时 winUI 会按 4 等分自适应收窄
M.DEFAULT_WIN_BTN_H = 54
M.DEFAULT_WIN_BTN_GAP = 14
M.DEFAULT_WIN_ANIM_CELL = 30
M.DEFAULT_WIN_ANIM_GAP = 9
M.DEFAULT_WIN_ANIM_STEP = 0.10
M.DEFAULT_WIN_ANIM_HOLD = 1.20
M.DEFAULT_WIN_AUTO_SHOW = 1
M.DEFAULT_WIN_STAR_SIZE = 58
M.DEFAULT_WIN_STAR_GAP = 82
M.DEFAULT_WIN_STAR_Y = 84
M.DEFAULT_WIN_STAR_INTERVAL = 0.22
M.DEFAULT_WIN_STAR_BURST = 12

-- ================================================================
-- ★ 触屏
-- ================================================================
M.DEFAULT_TOUCH_BTN_SIZE = 88
M.DEFAULT_TOUCH_BTN_ALPHA = 110
M.DEFAULT_TOUCH_BTN_MARGIN = 60

-- ================================================================
-- ★ 果园背景（scene 模块）：天空 / 远山 / 草坡 / 果树 / 云 / 飘叶
-- ================================================================
M.DEFAULT_SCENE_HILL_H = 150           -- 远山参考高（实际由方块边长决定）
M.DEFAULT_SCENE_GROUND_H = 310         -- 近处草坡带高（山脚/地平线由它反推）
M.DEFAULT_SCENE_SUN_SIZE = 104         -- 太阳边长
M.DEFAULT_SCENE_CLOUD_COUNT = 5         -- 云朵数量（挂在最底层，被地图 UI 盖住）
M.DEFAULT_SCENE_WIND_COUNT = 9         -- 风的线条数量（半透明细椭圆，横向飘）
M.DEFAULT_SCENE_WIND_SPEED = 130       -- 风的线条速度（像素/秒）
M.DEFAULT_SCENE_WIND_ALPHA = 62        -- 风的线条透明度
M.DEFAULT_SCENE_SUN_PULSE = 1          -- 太阳光晕呼吸：1=开 / 0=关
M.DEFAULT_MAP_WINDMILL_COUNT = 24      -- 田里的风车数量（三角形叶片，会转）
M.DEFAULT_MAP_GRASS_COUNT = 46         -- 随风摆动的小草丛数量

-- ================================================================
-- ★ 粒子 / 补间（fx 模块）
-- ================================================================
M.DEFAULT_FX_COUNT = 84
M.DEFAULT_FX_LIFE = 0.72
M.DEFAULT_FX_SPEED = 340
M.DEFAULT_FX_SPREAD = 150
M.DEFAULT_FX_GRAVITY = 1500
M.DEFAULT_FX_SIZE = 9
M.DEFAULT_FX_DAMP = 0.90
M.DEFAULT_ANIM_POP_TIME = 0.34
M.DEFAULT_ANIM_SLIDE_TIME = 0.28
M.DEFAULT_ANIM_HOVER_SCALE = 1.07
M.DEFAULT_ANIM_PRESS_SINK = 3

-- ================================================================
-- ★ 配色：果园 —— 奶油纸底 + 苹果红 + 果汁橙 + 叶绿
--   ★ 键名是全工程共用的「语义色」，改色只改这里。
-- ================================================================
M.DEFAULT_PALETTE = {
    bg         = "F7EBCF",   -- 全屏兜底底色（奶油麦田）
    sky        = "D9F2FF",   -- 天空带
    skyTop     = "B7E6FB",   -- 天空更深一层
    skyDeep    = "8FD3E8",   -- 远山后的雾气
    hill       = "A8D96B",   -- 远山 / 草坡
    grass      = "8FCB62",   -- 近处草地
    soil       = "C98B4B",   -- 土路
    sand       = "F1D79A",   -- 土路高光
    wave       = "FFFFFF",   -- 云 / 高光
    overlay    = "FFF7E6",   -- 全屏遮罩（奶油玻璃）
    panel      = "FFFBF0",   -- 面板底
    panelDeep  = "F6E7C8",   -- 面板内嵌凹槽
    card       = "FFFDF6",   -- 卡片 / 按钮底
    line       = "E8CFA4",   -- 描边 / 分隔
    text       = "4A3423",   -- 主文字（深咖啡）
    dim        = "8B7864",   -- 次要文字
    accent     = "E4572E",   -- 高亮 / 当前（苹果红）
    accentText = "FFF8EC",   -- 压在高亮块上的文字
    fruit      = "EE6A5B",   -- 水果（好的状态）/ 选关：已通关的苹果
    juice      = "FFB03B",   -- 果汁（要还原的状态）
    leaf       = "6FBF57",   -- 叶子
    grape      = "8E5BC7",   -- 葡萄（紫）
    grapeDeep  = "6E3FA8",   -- 葡萄暗面
    pear       = "C6D94A",   -- 青梨
    cream      = "FFF3DC",   -- 云朵亮部（比 wave 暖一点）
    lit        = "FFB03B",   -- 亮格（沿用旧键名：结算跑马灯用）
    unlit      = "EE6A5B",   -- 暗格
    glow       = "FFD27A",   -- 连带翻转 / 光晕
    ok         = "4FB477",   -- 已还原（青翠）
    danger     = "D64545",   -- 警告
    gold       = "E8B53A",   -- 金圈 / 星
    wood       = "A9713F",   -- 树干 / 木牌
    ringBlue   = "2E9BFF",   -- 教程示意图：亮蓝色环框（要点这个点位）
    guideFruit = "F5B21F",   -- 教程示意图：水果（黄）
    guideJuice = "DA3B2B",   -- 教程示意图：果汁（红）
    -- ★ 用户指定：示意图里「黄 = 水果、红 = 果汁」——
    --   故意不复用 fruit / juice 两个键：那两个在别处是「已通关苹果 / 果汁粒子」的用色，
    --   语义不同，混用会让示意图和盘面越改越乱。
    locked     = "AFC2A2",   -- 未解锁（青果）
    lockedDeep = "93A88A",
    juice1     = "FFB03B",   -- 粒子：橙汁
    juice2     = "EE6A5B",   -- 粒子：果肉
    juice3     = "8FD35B",   -- 粒子：青柠
    juice4     = "FFD65A",   -- 粒子：柠檬
    star       = "FFC93C",   -- 星级（金黄）
    starEdge   = "FFEFC2",   -- 星级光晕
    starOff    = "1F1F1F",   -- 未解锁关的三颗星（用户要求：黑色）
    starDim    = "A98A3C",   -- 已解锁未通关：暗金（看得出有三颗星，但不是「亮了」）
    shadow     = "6B4A2F",   -- 投影 / 立体下沿
}

-- ================================================================
-- ★ 关卡数据结构
--   name  : 显示名（"果园 01"）
--   steps : 需要踩的点位数（也是难度标签）
--   flips : 解序列 —— 0 基下标数组；按这串点位各踩一次即全部还原
--   tip   : 可选，一行提示（教程关 / 少数关卡用）
--   ★ 初始盘面不写进配置：由「从全水果开始，依次踩 flips」反推得到。
--     5×6 满秩 ⇒ 解唯一，steps 就是最小步数。
-- ================================================================

-- >>> LEVELS_BEGIN
M.LEVELS = {
    -- ===== 第01片果园（教程 · 1 步）=====
    {
        name = "果园 01",
        steps = 1,
        tip = "点一格，十字五格一起翻",
        flips = {19},
    },
    -- ===== 第02片果园（教程 · 2 步）=====
    {
        name = "果园 02",
        steps = 2,
        tip = "靠边少翻一格，靠角少两格",
        flips = {1, 24},
    },
    -- ===== 第03片果园（教程 · 2 步）=====
    {
        name = "果园 03",
        steps = 2,
        tip = "对角两点，重叠两格白翻",
        flips = {13, 20},
    },
    -- ===== 第04片果园（教程 · 3 步）=====
    {
        name = "果园 04",
        steps = 3,
        tip = "三点叠加，先算重叠",
        flips = {7, 14, 21},
    },
    -- ===== 第05片果园（教程 · 4 步）=====
    {
        name = "果园 05",
        steps = 4,
        tip = "先定边角，再往里推",
        flips = {1, 13, 19, 22},
    },
    -- ===== 第06片果园（挑战 · 5 步）=====
    {
        name = "果园 06",
        steps = 5,
        flips = {3, 6, 10, 18, 23},
    },
    -- ===== 第07片果园（挑战 · 5 步）=====
    {
        name = "果园 07",
        steps = 5,
        flips = {8, 9, 15, 17, 22},
    },
    -- ===== 第08片果园（挑战 · 5 步）=====
    {
        name = "果园 08",
        steps = 5,
        flips = {0, 4, 11, 17, 23},
    },
    -- ===== 第09片果园（挑战 · 5 步）=====
    {
        name = "果园 09",
        steps = 5,
        flips = {8, 9, 14, 17, 20},
    },
    -- ===== 第10片果园（挑战 · 6 步）=====
    {
        name = "果园 10",
        steps = 6,
        flips = {2, 8, 10, 12, 20, 28},
    },
    -- ===== 第11片果园（挑战 · 6 步）=====
    {
        name = "果园 11",
        steps = 6,
        flips = {2, 5, 7, 10, 12, 14},
    },
    -- ===== 第12片果园（挑战 · 6 步）=====
    {
        name = "果园 12",
        steps = 6,
        flips = {0, 8, 10, 17, 21, 27},
    },
    -- ===== 第13片果园（挑战 · 6 步）=====
    {
        name = "果园 13",
        steps = 6,
        flips = {3, 5, 11, 18, 24, 26},
    },
    -- ===== 第14片果园（挑战 · 6 步）=====
    {
        name = "果园 14",
        steps = 6,
        flips = {0, 1, 12, 18, 19, 24},
    },
    -- ===== 第15片果园（挑战 · 6 步）=====
    {
        name = "果园 15",
        steps = 6,
        flips = {10, 11, 15, 18, 22, 27},
    },
    -- ===== 第16片果园（挑战 · 7 步）=====
    {
        name = "果园 16",
        steps = 7,
        flips = {8, 9, 10, 17, 19, 22, 28},
    },
    -- ===== 第17片果园（挑战 · 7 步）=====
    {
        name = "果园 17",
        steps = 7,
        flips = {2, 3, 4, 15, 21, 22, 25},
    },
    -- ===== 第18片果园（挑战 · 7 步）=====
    {
        name = "果园 18",
        steps = 7,
        flips = {1, 6, 7, 9, 11, 12, 23},
    },
    -- ===== 第19片果园（挑战 · 7 步）=====
    {
        name = "果园 19",
        steps = 7,
        flips = {1, 7, 18, 22, 24, 28, 29},
    },
    -- ===== 第20片果园（挑战 · 7 步）=====
    {
        name = "果园 20",
        steps = 7,
        flips = {3, 8, 10, 12, 22, 23, 27},
    },
    -- ===== 第21片果园（挑战 · 7 步）=====
    {
        name = "果园 21",
        steps = 7,
        flips = {0, 5, 12, 16, 18, 21, 24},
    },
    -- ===== 第22片果园（挑战 · 8 步）=====
    {
        name = "果园 22",
        steps = 8,
        flips = {2, 6, 8, 9, 10, 16, 27, 28},
    },
    -- ===== 第23片果园（挑战 · 8 步）=====
    {
        name = "果园 23",
        steps = 8,
        flips = {3, 5, 9, 10, 15, 20, 22, 28},
    },
    -- ===== 第24片果园（挑战 · 8 步）=====
    {
        name = "果园 24",
        steps = 8,
        flips = {6, 8, 10, 18, 19, 23, 26, 29},
    },
    -- ===== 第25片果园（挑战 · 8 步）=====
    {
        name = "果园 25",
        steps = 8,
        flips = {1, 8, 10, 12, 17, 23, 25, 27},
    },
    -- ===== 第26片果园（挑战 · 8 步）=====
    {
        name = "果园 26",
        steps = 8,
        flips = {4, 10, 14, 17, 20, 22, 25, 27},
    },
    -- ===== 第27片果园（挑战 · 8 步）=====
    {
        name = "果园 27",
        steps = 8,
        flips = {2, 6, 9, 13, 14, 15, 16, 23},
    },
    -- ===== 第28片果园（挑战 · 9 步）=====
    {
        name = "果园 28",
        steps = 9,
        flips = {0, 2, 4, 6, 7, 8, 11, 18, 26},
    },
    -- ===== 第29片果园（挑战 · 9 步）=====
    {
        name = "果园 29",
        steps = 9,
        flips = {3, 4, 6, 7, 8, 9, 25, 26, 28},
    },
    -- ===== 第30片果园（挑战 · 9 步）=====
    {
        name = "果园 30",
        steps = 9,
        flips = {5, 6, 10, 17, 19, 22, 23, 26, 27},
    },
    -- ===== 第31片果园（挑战 · 9 步）=====
    {
        name = "果园 31",
        steps = 9,
        flips = {0, 3, 5, 14, 15, 16, 20, 25, 26},
    },
    -- ===== 第32片果园（挑战 · 9 步）=====
    {
        name = "果园 32",
        steps = 9,
        flips = {0, 1, 9, 11, 19, 20, 24, 25, 26},
    },
    -- ===== 第33片果园（挑战 · 9 步）=====
    {
        name = "果园 33",
        steps = 9,
        flips = {0, 2, 3, 13, 15, 19, 21, 27, 29},
    },
    -- ===== 第34片果园（挑战 · 10 步）=====
    {
        name = "果园 34",
        steps = 10,
        flips = {1, 4, 13, 15, 17, 21, 22, 23, 24, 29},
    },
    -- ===== 第35片果园（挑战 · 10 步）=====
    {
        name = "果园 35",
        steps = 10,
        flips = {5, 6, 8, 10, 14, 16, 17, 19, 24, 28},
    },
    -- ===== 第36片果园（挑战 · 10 步）=====
    {
        name = "果园 36",
        steps = 10,
        flips = {5, 10, 11, 14, 17, 18, 22, 26, 28, 29},
    },
    -- ===== 第37片果园（挑战 · 10 步）=====
    {
        name = "果园 37",
        steps = 10,
        flips = {0, 3, 5, 6, 7, 16, 19, 20, 27, 29},
    },
    -- ===== 第38片果园（挑战 · 10 步）=====
    {
        name = "果园 38",
        steps = 10,
        flips = {1, 4, 7, 10, 16, 19, 20, 25, 27, 29},
    },
    -- ===== 第39片果园（挑战 · 10 步）=====
    {
        name = "果园 39",
        steps = 10,
        flips = {1, 2, 3, 9, 12, 15, 18, 21, 24, 25},
    },
    -- ===== 第40片果园（挑战 · 10 步）=====
    {
        name = "果园 40",
        steps = 10,
        flips = {1, 3, 5, 9, 13, 14, 15, 16, 21, 27},
    },
    -- ===== 第41片果园（挑战 · 11 步）=====
    {
        name = "果园 41",
        steps = 11,
        flips = {5, 6, 8, 9, 13, 19, 21, 22, 23, 25, 26},
    },
    -- ===== 第42片果园（挑战 · 11 步）=====
    {
        name = "果园 42",
        steps = 11,
        flips = {8, 9, 11, 14, 15, 16, 19, 20, 22, 25, 28},
    },
    -- ===== 第43片果园（挑战 · 11 步）=====
    {
        name = "果园 43",
        steps = 11,
        flips = {1, 3, 5, 6, 10, 18, 21, 24, 25, 26, 28},
    },
    -- ===== 第44片果园（挑战 · 11 步）=====
    {
        name = "果园 44",
        steps = 11,
        flips = {0, 10, 11, 14, 16, 18, 19, 23, 25, 27, 29},
    },
    -- ===== 第45片果园（挑战 · 11 步）=====
    {
        name = "果园 45",
        steps = 11,
        flips = {0, 4, 6, 9, 10, 13, 16, 17, 21, 22, 28},
    },
    -- ===== 第46片果园（挑战 · 11 步）=====
    {
        name = "果园 46",
        steps = 11,
        flips = {1, 2, 3, 6, 7, 8, 11, 14, 22, 24, 25},
    },
    -- ===== 第47片果园（挑战 · 12 步）=====
    {
        name = "果园 47",
        steps = 12,
        flips = {3, 6, 9, 13, 14, 16, 18, 21, 22, 23, 26, 29},
    },
    -- ===== 第48片果园（挑战 · 12 步）=====
    {
        name = "果园 48",
        steps = 12,
        flips = {0, 1, 2, 5, 8, 9, 12, 17, 18, 21, 22, 24},
    },
    -- ===== 第49片果园（挑战 · 12 步）=====
    {
        name = "果园 49",
        steps = 12,
        flips = {0, 8, 10, 13, 15, 16, 18, 19, 21, 22, 23, 24},
    },
    -- ===== 第50片果园（挑战 · 12 步）=====
    {
        name = "果园 50",
        steps = 12,
        flips = {0, 3, 4, 6, 8, 11, 12, 13, 23, 26, 28, 29},
    },
}
-- <<< LEVELS_END

-- ================================================================
-- ★★ 序章 + 教程（前 5 片果园）
-- ================================================================
-- ★ 文案原则（用户要求：新手看得懂 + 结合背景设定）：
--   · 一页只讲一件事，正文一行不超过 30 个字
--     （正文框宽 580px、字号 18、adaptiveFontSize=false，多出来的字会被裁掉）；
--   · 讲的是游戏里正在发生的事，不是规则说明书：
--     小突角龙想帮瓦雷莎采果，可它们不会说话、力气也收不住，把熟果撞成了果汁；
--     你是懂龙族语的旅行者，魂附小龙替它们看准落点；
--   · 序章在地图首屏自动展开 **2 页**：为什么果园成了这样 → 你是谁（魂附小龙）；
--   · ★「怎么挑果园」不再占一页（用户要求删掉）：序章关掉后，地图上的
--     「进入果园」按钮会亮起来（光圈 + 气泡 + 指示三角）引导玩家点 ——
--     这比在教程里看一段示意图更直接（见 map.guideEnter / state.prologueGuidePending）；
--   · 第 1 课用 3 页把「目标 / 操作 / 过关长什么样」讲透；第 2–5 课各 1 页讲更深的机制。
--
-- 一页的结构：
--   title   标题（≤ 16 字）
--   lines   正文两行（每行 ≤ 30 字）
--   caption 图注（≤ 34 字）
--   art     示意图
--     .rings  { {行, 列}, ... }（1 起始）= 这一页要你点的点位，套亮蓝环框
--     .flips  只用来「算盘面颜色」，不画框（不写就退回用 rings 算）
--     .map    直接写盘面："." 水果（黄）/ "o" 果汁（红）/ 其它字符 不画
--             ★ 只有「示意用」的页才写 map。教程关的盘面一律由 rings 现算，
--               保证「示意图 == 该关真实盘面」（手写迟早写错，踩过）。
--             ★ 目前**没有页在用 map**（原「三颗果实 = 三片果园」那页已删），
--               能力保留：以后要画非 5×6 的示意盘面，还得靠它。
-- ================================================================
M.PROLOGUE = {
    pages = {
        -- ① 背景：果园为什么成了这样
        {
            title = "序章 · 小龙闯祸了",
            lines = {
                "小突角龙想帮瓦雷莎采果子，可它们总是帮倒忙",
                "本来只想清理一块坏掉的果子，却不小心把好几个果子撞碎",
            },
            caption = "黄格 = 水果 · 红格 = 被撞成的果汁",
            art = { flips = { { 2, 2 }, { 3, 3 } } },
        },
        -- ② 你是谁：懂龙族语的旅行者，魂附小龙（序章只有这 2 页，第 3 页「怎么挑果园」已删）
        {
            title = "序章 · 魂附指挥",
            lines = {
                "魂附一只小突角龙并指挥他们",
                "你指哪一格，小龙就前往哪一格帮忙",
            },
            caption = "小龙帮忙的时候周围十字区域也会影响哦",
            art = { flips = { { 2, 2 }, { 3, 3 } }, rings = { { 3, 2 } } },
        },
    },
}

M.LESSONS = {
    -- ===== 第 1 课（3 页）：目标 → 操作 → 过关长什么样 =====
    {
        pages = {
            {
                title = "第 1 课 · 先把果汁认出来",
                lines = {
                    "红格就是被小龙撞出来的果汁，一格都不能剩。",
                    "黄格是好果子，撞成红的就要多清一格。",
                },
                caption = "这一片被撞出了五格果汁，全都要清掉",
                art = { flips = { { 4, 2 } } },
            },
            {
                title = "第 1 课 · 点一格，撞五格",
                lines = {
                    "点蓝框那一格，小龙就跳过去清理",
                    "对应格子连着上下左右，五格一起翻",
                },
                caption = "蓝框 = 接下来需要让你点的格子",
                art = { rings = { { 4, 2 } } },
            },
            {
                title = "第 1 课 · 全部变黄就救回来了",
                lines = {
                    "水果撞一下变果汁，果汁再清理一下就可以继续码放水果",
                    "整片只剩水果（黄格），这片果园就算救回来了",
                },
                caption = "清完的样子：一格红都不剩",
                art = {},
            },
        },
    },
    -- ===== 第 2 课：边与角波及得少 =====
    {
        pages = {
            {
                title = "第 2 课 · 边上的格少",
                lines = {
                    "靠边的格子没有外侧邻居，只会翻转 4 格",
                    "角上的只会翻转 3 格",
                },
                caption = "上面是边（4 格）· 左下是角（3 格）",
                art = { rings = { { 1, 2 }, { 5, 1 } } },
            },
        },
    },
    -- ===== 第 3 课：重叠 = 白撞 =====
    {
        pages = {
            {
                title = "第 3 课 · 连翻两次",
                lines = {
                    "两个点挨得近，两个十字会压到同一格。",
                    "那格被翻两次，就回到了被清理干净的状态",
                },
                caption = "中间那两格被撞了两次，所以又变回黄的",
                art = { rings = { { 3, 2 }, { 4, 3 } } },
            },
        },
    },
    -- ===== 第 4 课：三个点一起算 =====
    {
        pages = {
            {
                title = "第 4 课 · 三个点要一起算",
                lines = {
                    "点一多，十字会两两重叠，越叠越难算",
                    "先圈出重叠的格子，再决定撞哪几个点",
                },
                caption = "斜着排的三个点：相邻两个各重叠两格",
                art = { rings = { { 2, 2 }, { 3, 3 }, { 4, 4 } } },
            },
        },
    },
    -- ===== 第 5 课：从边角往里推 + 卡住就重来 =====
    {
        pages = {
            {
                title = "第 5 课 · 从边上往里推",
                lines = {
                    "先在边上定一两个点，剩下的会自己露出来",
                    "卡住就重来 —— 每片果园只有一个最小答案",
                },
                caption = "游玩时右上角最小步数会提示你每一步是否正确哦",
                art = { rings = { { 1, 2 }, { 3, 2 }, { 4, 2 }, { 4, 5 } } },
            },
        },
    },
}

-- ================================================================
-- ★ 取关卡（1 起始）
-- ================================================================
function M.getLevelConfig(index)
    local idx = tonumber(index)
    if not idx then return nil end
    idx = math.floor(idx)
    if idx < 1 or idx > #M.LEVELS then return nil end
    return M.LEVELS[idx]
end

function M.getLevelCount()
    return #M.LEVELS
end

function M.getLevelSteps(index)
    local d = M.getLevelConfig(index)
    if not d then return 0 end
    return math.floor(tonumber(d.steps) or 0)
end

function M.getMaxSteps()
    local n = 1
    for i = 1, #M.LEVELS do
        local s = math.floor(tonumber(M.LEVELS[i].steps) or 0)
        if s > n then n = s end
    end
    return n
end

-- 解序列副本（一律返回新表：会被直接交给 AddIntList）
function M.getLevelFlips(index)
    local out = {}
    local d = M.getLevelConfig(index)
    if not d or type(d.flips) ~= "table" then return out end
    for i = 1, #d.flips do
        out[i] = math.floor(tonumber(d.flips[i]) or -1)
    end
    return out
end

-- 某一课的「一组页」（没有就返回 nil）
-- ★ 返回值是 { pages = { 页1, 页2, ... } }：一课可以有多页（第 1 课就拆成 3 页）。
function M.getLesson(index)
    return M.LESSONS[math.floor(tonumber(index) or 0)]
end

-- 某一课的页数组（没有就返回空表，调用方不用判空）
function M.getLessonPages(index)
    local d = M.getLesson(index)
    if not d or type(d.pages) ~= "table" then return {} end
    return d.pages
end

function M.isTutorialLevel(index)
    return M.getLesson(index) ~= nil
end

-- 教程课数（前 5 关）
function M.getLessonCount()
    return #M.LESSONS
end

-- 序章（地图首屏 / 完整图册的第 1..N 页）
function M.getProloguePages()
    local p = M.PROLOGUE
    if not p or type(p.pages) ~= "table" then return {} end
    return p.pages
end

return M
