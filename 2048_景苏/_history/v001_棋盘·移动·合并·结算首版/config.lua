-- ================================================================
-- 2048 · 参数真源
--   ★ 本文件中的 DEFAULT_* 是全部可调参数的「唯一真源」。
--   ★ 编辑器.html 的 DEFAULTS 必须与本文件逐项数值一致
--     （改任一处要同步另一处，并用 _shared/_check_refs.py 验证）。
--   ★ 玩法内核在本文件里没有任何分支逻辑，只描述「数值」。
--
--   ★★ 版式注意：文本框有「最小高度」（utils.MIN_TEXT_H = 36），
--      真机上盒子太矮会一个字都不画。所以本文件里的每个高度都是
--      按「兜高之后」的真实盒高排的，直接改数值前请先读
--      《开发经验与避坑手册.md》的「真机 vs 模拟器」一节。
-- ================================================================

---@diagnostic disable: undefined-global

local M = {}

-- ================================================================
-- ★ 画布与自适应布局
--   所有尺寸都按「设计基准 1280×720」写死，运行时用
--   k = min(画布宽/1280, 画布高/720) 整体缩放。
--   这样 PC(1600×900 / 2100×900) 与移动端(1280×720) 共用一套排版。
-- ================================================================
M.DEFAULT_DESIGN_WIDTH = 1280         -- 设计基准宽（自适应缩放的分子）
M.DEFAULT_DESIGN_HEIGHT = 720         -- 设计基准高
M.DEFAULT_VIEW_WIDTH = 1280           -- GetUICanvasSize 失败时的兜底宽
M.DEFAULT_VIEW_HEIGHT = 720           -- 兜底高

-- ---- 棋盘几何（设计坐标）----
--   棋盘边长 = CELL * 4 + GAP * 5 = 104*4 + 12*5 = 476
--   水平：-468 … +8（左侧留 172 给背景，右侧 182 给信息列）
--   纵向：-233 … +243（上下各留 117）
M.DEFAULT_BOARD_CELL = 104            -- 单格边长
M.DEFAULT_BOARD_GAP = 12              -- 格间距（外圈留白同值）
M.DEFAULT_BOARD_CX = -230             -- 棋盘中心 x（相对画布中心，负=偏左）
M.DEFAULT_BOARD_CY = 5                -- 棋盘中心 y

-- ---- 右侧信息列（自下而上：功能按钮 → 方向键 → 说明 → 最高分 → 分数 → 标题）----
M.DEFAULT_PANEL_CX = 340              -- 右侧信息列中心 x
M.DEFAULT_TITLE_Y = 312               -- 标题「2048」y（盒高 76 → 274…350）
M.DEFAULT_TITLE_SIZE = 62             -- 标题字号
M.DEFAULT_SCORE_W = 300               -- 分数框宽
M.DEFAULT_SCORE_H = 84                -- 分数框高（小标题在上、数值在下的两段式）
M.DEFAULT_SCORE_Y = 230               -- 「分数」框 y（188…272）
M.DEFAULT_BEST_Y = 140                -- 「最高分」框 y（98…182）
M.DEFAULT_SCORE_LABEL_SIZE = 20       -- 分数框内小标题字号
M.DEFAULT_SCORE_VALUE_SIZE = 34       -- 分数数值字号
M.DEFAULT_SCORE_LABEL_DY = 23         -- 小标题相对框中心的 y 偏移
M.DEFAULT_SCORE_VALUE_DY = -21        -- 数值相对框中心的 y 偏移
M.DEFAULT_HINT_Y = 76                 -- 右侧说明文字 y（58…94）
M.DEFAULT_HINT_SIZE = 18              -- 说明文字字号

-- ---- 方向键（D-Pad）----
M.DEFAULT_DPAD_CX = 340               -- 方向键中心 x
M.DEFAULT_DPAD_CY = -48               -- 方向键中心 y
M.DEFAULT_DPAD_BTN = 60               -- 单个方向键边长
M.DEFAULT_DPAD_GAP = 6                -- 方向键之间的间隙
M.DEFAULT_DPAD_SIZE = 26              -- 方向键字形字号

-- ---- 功能按钮（重新开始 / 撤销一步 / 继续游戏）----
M.DEFAULT_FUNC_W = 300                -- 功能按钮宽
M.DEFAULT_FUNC_H = 52                 -- 功能按钮高
M.DEFAULT_FUNC_Y1 = -176              -- 第一个功能按钮 y（-202…-150）
M.DEFAULT_FUNC_Y2 = -242              -- 第二个功能按钮 y
M.DEFAULT_FUNC_Y3 = -308              -- 第三个功能按钮 y（-334…-282）
M.DEFAULT_FUNC_SIZE = 22              -- 功能按钮字号
M.DEFAULT_FUNC_TEXT_ALPHA = 255       -- 可用按钮的字色不透明度
M.DEFAULT_FUNC_DISABLED_ALPHA = 96    -- 不可用按钮的字色不透明度

-- ================================================================
-- ★ 规则
-- ================================================================
M.DEFAULT_START_TILES = 2             -- 开局随机生成几个数字
M.DEFAULT_SPAWN_2_RATIO = 90          -- 新数字为 2 的概率（百分比，其余为 4）
M.DEFAULT_WIN_VALUE = 2048            -- 达到该值判定胜利
M.DEFAULT_CONTINUE_AFTER_WIN = 1      -- 胜利后是否允许「继续游戏」：1=允许 / 0=只能重开
M.DEFAULT_UNDO_ENABLED = 1            -- 是否允许撤销：1=允许 / 0=禁用
M.DEFAULT_UNDO_DEPTH = 64             -- 撤销栈深度（记录「开始到现在每一步」的最近 N 步）
M.DEFAULT_AUTO_SETTLE = 1             -- 判定胜利/失败后是否自动弹结算面板：1=自动 / 0=手动

-- ================================================================
-- ★ 动画时长与幅度（全部为秒 / 倍率）
--   设计原则：移动要快而干脆，出现与合并且要有弹性。
-- ================================================================
M.DEFAULT_ANIM_MOVE_TIME = 0.12       -- ★ 方块平移时长（需求要求 100–150ms）
M.DEFAULT_ANIM_SPAWN_TIME = 0.16      -- 新方块从 0 放大到 1 的时长
M.DEFAULT_ANIM_SPAWN_OVERSHOOT = 1.12 -- 新方块「轻微回弹」的峰值倍率
M.DEFAULT_ANIM_MERGE_TIME = 0.14      -- 合并弹跳时长
M.DEFAULT_ANIM_MERGE_SCALE = 1.18     -- 合并先放大到的倍率（随后回弹到 1）
M.DEFAULT_ANIM_SCORE_TIME = 0.35      -- 分数滚动到新值的时长
M.DEFAULT_ANIM_SCORE_POP = 1.14       -- 分数变化时数值框的弹跳峰值
M.DEFAULT_ANIM_INPUT_LOCK_EXTRA = 0.03 -- 动画结束后额外锁输入的缓冲（防连点）
M.DEFAULT_ANIM_UNDO_TIME = 0.20       -- 撤销后整盘「呼吸」一下的时长

-- ================================================================
-- ★ 结算展示动效（「给棋盘拍张照」）
--   ① 棋盘整层缩小 + 带一点倾角飞到右侧相片位，落定后转正；
--   ② 相片框（四条边条，上/左/右窄、下宽 —— 拍立得样式）淡入；
--   ③ 左侧信息面板从屏幕左外侧滑入（带轻微过冲）；
--   ④ 分数数字滚动增长；⑤ 按钮依次出现。
-- ================================================================
M.DEFAULT_SETTLE_BOARD_TIME = 0.55    -- 棋盘飞向相片位的时长
M.DEFAULT_SETTLE_PHOTO_SCALE = 0.46   -- 棋盘最终缩放（476 → 219）
M.DEFAULT_SETTLE_PHOTO_TILT = -8      -- 飞行途中的最大倾角（度，落定时归 0）
M.DEFAULT_SETTLE_PHOTO_X = 232        -- 相片中心 x（设计坐标）
M.DEFAULT_SETTLE_PHOTO_Y = -18        -- 相片中心 y
M.DEFAULT_SETTLE_OVERLAY_TIME = 0.30  -- 背景遮罩淡入时长
M.DEFAULT_SETTLE_OVERLAY_ALPHA = 188  -- 背景遮罩不透明度
M.DEFAULT_SETTLE_PHOTO_DELAY = 0.30   -- 相框在棋盘飞到一半之后出现
M.DEFAULT_SETTLE_PHOTO_TIME = 0.30    -- 相框淡入时长
M.DEFAULT_SETTLE_FRAME_PAD = 16       -- 相框上/左/右的边宽
M.DEFAULT_SETTLE_FRAME_PAD_BOTTOM = 48 -- 相框下边宽度（拍立得留白，放说明文字）
M.DEFAULT_SETTLE_MATTE = 5            -- 相片内衬（棋盘与相框之间的深色细线）
M.DEFAULT_SETTLE_CAP_SIZE = 22        -- 相片下方说明文字字号
M.DEFAULT_SETTLE_INFO_DELAY = 0.30    -- 信息面板延后于棋盘起飞的时长
M.DEFAULT_SETTLE_INFO_TIME = 0.42     -- 信息面板滑入时长
M.DEFAULT_SETTLE_INFO_CX = -350       -- 信息面板中心 x（设计坐标）
M.DEFAULT_SETTLE_INFO_CY = 0          -- 信息面板中心 y
M.DEFAULT_SETTLE_INFO_W = 560         -- 信息面板宽（-630…-70）
M.DEFAULT_SETTLE_INFO_H = 460         -- 信息面板高（-230…230）
M.DEFAULT_SETTLE_TITLE_SIZE = 40      -- 面板大字标题字号
M.DEFAULT_SETTLE_SUB_SIZE = 20        -- 面板副标题字号
M.DEFAULT_SETTLE_SCORE_SIZE = 60      -- 结算分数数字字号
M.DEFAULT_SETTLE_STAT_SIZE = 20       -- 统计行字号
M.DEFAULT_SETTLE_COUNT_TIME = 0.75    -- 结算分数滚动增长时长
M.DEFAULT_SETTLE_BTN_W = 240          -- 面板按钮宽
M.DEFAULT_SETTLE_BTN_H = 54           -- 面板按钮高
M.DEFAULT_SETTLE_BTN_DX = 134         -- 两个按钮相对面板中心的 x 偏移
M.DEFAULT_SETTLE_BTN_Y = -178         -- 按钮相对面板中心的 y 偏移
M.DEFAULT_SETTLE_BTN_DELAY = 0.16     -- 按钮之间的出现间隔（依次出现）
M.DEFAULT_SETTLE_BTN_TIME = 0.24      -- 单个按钮出现时长

-- ================================================================
-- ★ 粒子与飘字
-- ================================================================
M.DEFAULT_FX_PARTICLE_COUNT = 12      -- 单次合并迸溅的粒子数
M.DEFAULT_FX_PARTICLE_LIFE = 0.50     -- 粒子存活时长（秒）
M.DEFAULT_FX_PARTICLE_SIZE = 12       -- 粒子初始边长
M.DEFAULT_FX_PARTICLE_SPEED = 300     -- 粒子初速度（像素/秒）
M.DEFAULT_FX_PARTICLE_GRAVITY = 1100  -- 粒子重力（像素/秒²）
M.DEFAULT_FX_PARTICLE_SPIN = 260      -- 粒子自转速度（度/秒）
M.DEFAULT_FX_PARTICLE_MAX = 160       -- 粒子上限（防止极端连击时爆量）
M.DEFAULT_FX_FLOAT_LIFE = 0.70        -- 「+分数」飘字存活时长
M.DEFAULT_FX_FLOAT_RISE = 76          -- 飘字上升高度
M.DEFAULT_FX_FLOAT_SIZE = 30          -- 飘字号

-- ================================================================
-- ★ 输入
-- ================================================================
M.DEFAULT_SWIPE_MIN_DISTANCE = 42     -- 滑动判定：位移超过该值才算一次滑动（设计像素）
M.DEFAULT_KEY_GUARD = 1               -- 键盘是否做「边沿触发」防重复：1=按住只响应一次
M.DEFAULT_SWIPE_ENABLED = 1           -- 是否允许滑动操作：1=允许 / 0=禁用

-- ================================================================
-- ★ 最高分持久化（平台存档）
--   客户端只能【读】服务器自定义变量、并【发信号】请服务器写。
--   所以：启动时读 DEFAULT_HIGHSCORE_VAR 这个全局自定义变量；
--   破纪录时发一次 DEFAULT_HIGHSCORE_SIGNAL 信号（带整型新纪录）。
-- ================================================================
M.DEFAULT_HIGHSCORE_SYNC = 1          -- 是否启用最高分同步：1=启用 / 0=仅本次会话内存
M.DEFAULT_HIGHSCORE_VAR = "2048最高分" -- 服务器全局自定义变量名（读）
M.DEFAULT_HIGHSCORE_SIGNAL = "保存最高分" -- 出站信号名（请服务器写入）

-- ================================================================
-- ★ 界面过渡黑幕
-- ================================================================
M.DEFAULT_FADE_IN_TIME = 0.18         -- 渐显时长
M.DEFAULT_FADE_HOLD_TIME = 0.24       -- 全黑维持
M.DEFAULT_FADE_OUT_TIME = 0.24        -- 渐隐时长
M.DEFAULT_FADE_MAX_ALPHA = 240        -- 峰值不透明度

-- ================================================================
-- ★ 配色
--   ★ 界面字符串请勿使用 ◀ ▶ ✓（中文字体无字形 → 豆腐块）。
--     安全：← → ↑ ↓ √ ★ ◆ · ×
-- ================================================================
M.DEFAULT_PALETTE = {
    bg          = "FAF8EF",   -- 页面底色
    boardBg     = "BBADA0",   -- 棋盘底板
    cellEmpty   = "CDC1B4",   -- 空格
    frame       = "FFFDF7",   -- 相框外圈（结算「照片」）
    frameMat    = "5A4F47",   -- 相框内衬
    textDark    = "776E65",   -- 深色文字
    textLight   = "F9F6F2",   -- 浅色文字
    box         = "BBADA0",   -- 分数框底
    boxLabel    = "EEE4DA",   -- 分数框小标题
    boxValue    = "FFFFFF",   -- 分数数值
    hud         = "776E65",   -- HUD 文字
    dim         = "9C8F86",   -- 次要文字
    accent      = "8F7A66",   -- 主按钮
    accentText  = "F9F6F2",   -- 主按钮文字
    btn         = "D6CCC2",   -- 次要按钮
    btnText     = "776E65",   -- 次要按钮文字
    panel       = "FBF9F4",   -- 结算信息面板底
    panelEdge   = "E6DFD3",   -- 结算信息面板描边
    panelText   = "5A4F47",   -- 结算信息面板文字
    panelDim    = "9C8F86",   -- 结算信息面板次要文字
    overlay     = "2B2724",   -- 结算遮罩
    win         = "EDC22E",   -- 胜利主色
    danger      = "D9534F",   -- 失败主色
}

-- 方块配色：值 → { 底, 字 }；未列出的值用 fallback
M.DEFAULT_TILE_COLORS = {
    [2]    = { "EEE4DA", "776E65" },
    [4]    = { "EDE0C8", "776E65" },
    [8]    = { "F2B179", "F9F6F2" },
    [16]   = { "F59563", "F9F6F2" },
    [32]   = { "F67C5F", "F9F6F2" },
    [64]   = { "F65E3B", "F9F6F2" },
    [128]  = { "EDCF72", "F9F6F2" },
    [256]  = { "EDCC61", "F9F6F2" },
    [512]  = { "EDC850", "F9F6F2" },
    [1024] = { "EDC53F", "F9F6F2" },
    [2048] = { "EDC22E", "F9F6F2" },
}
M.DEFAULT_TILE_FALLBACK_BG = "3C3A32" -- 超过 2048 之后的方块底色
M.DEFAULT_TILE_FALLBACK_FG = "F9F6F2"
M.DEFAULT_TILE_FONT_SIZE = 44         -- 方块数字字号（1–2 位数）
M.DEFAULT_TILE_FONT_SIZE_LONG = 32    -- 3 位数
M.DEFAULT_TILE_FONT_SIZE_LONGER = 26  -- 4 位数及以上

return M
