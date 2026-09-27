-- ================================================================
-- TickHop（滴答咔哒）参数真源
--   ★ 本文件中的 DEFAULT_* 是全部可调参数的「唯一真源」。
--   ★ 编辑器.html 的 DEFAULTS 必须与本文件逐项数值一致
--     （改任一处要同步另一处，并用 _check_refs.py 验证）。
--   ★ 关卡数据 LEVELS 由编辑器导出后直接覆盖本文件末尾的 LEVELS 表。
-- ================================================================

---@diagnostic disable: undefined-global

local M = {}

-- ================================================================
-- ★ 时间系统
--   倒计时从 time 递减到 0；显示格式 "秒.百分秒"（如 9.01）。
--   平台绑定秒数 tick 与 floor(当前时间) 相等时才为实体。
-- ================================================================
M.DEFAULT_TIME_LIMIT = 10.00          -- 关卡默认倒计时初始值（秒）
M.DEFAULT_TIME_DIRECTION = -1         -- 时间流向：-1=递减（常规倒计时）/ +1=递增（时间反转后）
M.DEFAULT_TIME_TICK_EPSILON = 0.0001  -- tick 取整容差，规避浮点临界抖动
M.DEFAULT_TIME_EXPIRE_FAIL = 1        -- 时间归零是否判定失败：1=失败 / 0=仅停止计时

-- ================================================================
-- ★ 玩家运动（矩形 AABB 平台跳跃）
-- ================================================================
M.DEFAULT_PLAYER_WIDTH = 34           -- 玩家碰撞盒宽
M.DEFAULT_PLAYER_HEIGHT = 44          -- 玩家碰撞盒高
-- ★ 以下 6 项按《滴答咔哒/Tick Hop》原版实测反推（详见 原版对照.md「跳跃参数」一节）：
--   原版一次满跳：跳高 ≈ 3.5 个身位、上升耗时 ≈ 0.21 s、水平位移可达 ≈ 4.5 个身位。
--   原版第02关必须一次跳起 150 世界像素才能到达终点平台，因此跳高必须 > 150。
--   反推：H = v²/(2g) = 1450²/12000 ≈ 175 px（= 4.0 个身位），上升 0.242 s。
M.DEFAULT_MOVE_SPEED = 520            -- 水平最大速度（像素/秒）
M.DEFAULT_GROUND_ACCEL = 7000         -- 地面加速度
M.DEFAULT_GROUND_FRICTION = 9000      -- 地面减速
M.DEFAULT_AIR_ACCEL = 4500            -- 空中加速度
M.DEFAULT_AIR_FRICTION = 900          -- 空中减速（保留惯性）
M.DEFAULT_JUMP_SPEED = 1450           -- 起跳初速度
M.DEFAULT_GRAVITY = 6000              -- 重力加速度
M.DEFAULT_FALL_GRAVITY_MULT = 1.20    -- 下落时重力倍率（手感更利落）
M.DEFAULT_MAX_FALL_SPEED = 1800       -- 最大下落速度（防止穿透平台）
M.DEFAULT_COYOTE_TIME = 0.10          -- 土狼时间：离地后仍可起跳的宽限
M.DEFAULT_JUMP_BUFFER_TIME = 0.12     -- 跳跃缓冲：落地前提前按跳仍然生效
M.DEFAULT_JUMP_CUT_MULT = 0.45        -- 松手截断：松开跳跃键时把上升速度乘以该倍率
                                      --   （可变跳跃高度：轻点小跳 / 长按高跳，与原版一致）
M.DEFAULT_JUMP_EDGE_TRIGGER = 1       -- 跳跃触发方式：1=只在「按下的那一刻」触发一次
                                      --   （按住不会连跳，落地瞬间不再自动起跳）
                                      --   0=按住即持续触发（旧行为，引擎按键重复时会连跳）
M.DEFAULT_PHYSICS_SUBSTEPS = 4        -- 物理子步数（越小越不易穿透）

-- ================================================================
-- ★ 计时平台
--   tick = -1 表示「永驻平台」（不参与秒数切换，始终实体）
--   tick >= 0 表示该平台仅在 floor(当前时间) == tick 时为实体
-- ================================================================
M.DEFAULT_PLATFORM_WIDTH = 120        -- 平台默认宽
M.DEFAULT_PLATFORM_HEIGHT = 22        -- 平台默认高
M.DEFAULT_PLATFORM_ALPHA = 255        -- 实体时不透明度（0-255）
M.DEFAULT_PLATFORM_GHOST_ALPHA = 40   -- 虚化时不透明度（0-255）
M.DEFAULT_PLATFORM_TICK = -1          -- 平台默认绑定秒数（-1=永驻）
M.DEFAULT_PLATFORM_LABEL_SIZE = 26    -- 平台秒数标签字号（0=不显示标签）
M.DEFAULT_PLATFORM_LABEL_GHOST_ALPHA = 130
                                      -- 虚化平台上秒数标签的不透明度（0-255）
                                      -- 与实体态的 palette.label 形成反色对比，避免亮起时看不清

-- ================================================================
-- ★ 终点门
-- ================================================================
M.DEFAULT_GOAL_WIDTH = 56             -- 门宽
M.DEFAULT_GOAL_HEIGHT = 84            -- 门高
M.DEFAULT_GOAL_ALPHA = 255            -- 门不透明度

-- ================================================================
-- ★ 道具
-- ================================================================
M.DEFAULT_PICKUP_SIZE = 30            -- 道具尺寸（正方形边长）
M.DEFAULT_PICKUP_TIME_VALUE = 3.00    -- 加时道具补充的秒数
M.DEFAULT_PICKUP_RESPAWN = 1          -- 道具拾取后是否重生：1=重生 / 0=一次性

-- ================================================================
-- ★ 音效冷却（秒）
-- ================================================================
M.DEFAULT_SWITCH_COOLDOWN = 0.06      -- 平台切换音效最小间隔，避免连续切换时爆音
M.DEFAULT_LAND_COOLDOWN = 0.10        -- 落地音效最小间隔

-- ================================================================
-- ★ 视口与边界
-- ================================================================
M.DEFAULT_VIEW_WIDTH = 800            -- 画布逻辑宽（GetUICanvasSize 失败时的兜底）
M.DEFAULT_VIEW_HEIGHT = 600           -- 画布逻辑高
M.DEFAULT_KILL_MARGIN = 260           -- 掉出关卡包围盒外多少像素判定失败

-- ================================================================
-- ★ 关卡切换黑幕过渡（fadeScreen 模块）
-- ================================================================
M.DEFAULT_FADE_IN_TIME = 0.20         -- 渐显时长（秒）
M.DEFAULT_FADE_HOLD_TIME = 0.35       -- 全黑维持时长（秒）
M.DEFAULT_FADE_OUT_TIME = 0.20        -- 渐隐时长（秒）
M.DEFAULT_FADE_MAX_ALPHA = 255        -- 渐显峰值不透明度（0-255）

-- ================================================================
-- ★ 触屏虚拟按钮
-- ================================================================
M.DEFAULT_TOUCH_BTN_SIZE = 88         -- 虚拟按钮边长
M.DEFAULT_TOUCH_BTN_ALPHA = 110       -- 虚拟按钮不透明度
M.DEFAULT_TOUCH_BTN_MARGIN = 60       -- 虚拟按钮距屏幕边缘的距离

-- ================================================================
-- ★ 菜单 / 结算面板（选关 / 通关 / 失败）
--   三种模式复用同一批控件：遮罩 + 面板 + 标题 + 副标题 + 卡片网格 + 按钮。
--   打开面板时冻结玩法（暂停计时与物理），关闭后从原状态继续。
-- ================================================================
M.DEFAULT_MENU_OVERLAY_ALPHA = 215    -- 全屏遮罩不透明度（0-255）
M.DEFAULT_MENU_PANEL_W = 600          -- 面板宽（须容下卡片网格 + 两侧翻页箭头）
M.DEFAULT_MENU_PANEL_H = 420          -- 面板高
M.DEFAULT_MENU_TITLE_SIZE = 44        -- 标题字号
M.DEFAULT_MENU_TEXT_SIZE = 24         -- 正文 / 按钮 / 卡片字号
M.DEFAULT_MENU_HINT_SIZE = 18         -- 次要提示字号（副标题、页码）
M.DEFAULT_MENU_BTN_W = 200            -- 底部按钮宽
M.DEFAULT_MENU_BTN_H = 60             -- 底部按钮高
M.DEFAULT_MENU_BTN_GAP = 24           -- 底部按钮水平间距
M.DEFAULT_MENU_CARD_W = 150           -- 选关卡片宽
M.DEFAULT_MENU_CARD_H = 62            -- 选关卡片高
M.DEFAULT_MENU_CARD_GAP_X = 18        -- 卡片水平间距
M.DEFAULT_MENU_CARD_GAP_Y = 16        -- 卡片垂直间距
M.DEFAULT_MENU_CARD_TEXT_SIZE = 20    -- 选关关卡名字号
M.DEFAULT_MENU_COLS = 3               -- 选关每行卡片数
M.DEFAULT_MENU_ROWS = 2               -- 选关每页行数（每页 = COLS × ROWS 关）
M.DEFAULT_MENU_PAGE_BTN_W = 44        -- 翻页箭头宽（置于卡片网格左右两侧）
M.DEFAULT_MENU_PAGE_BTN_H = 44        -- 翻页箭头高
M.DEFAULT_MENU_INPUT_ENABLED = 1      -- 面板内键盘操作：1=启用（←/→ 选择、空格确认）/ 0=仅点击
M.DEFAULT_MENU_AUTO_WIN = 1           -- 到达终点后自动弹出通关面板：1=自动 / 0=需自行调起

-- ================================================================
-- ★ 极简配色（十六进制 RGB 字符串，编辑器与本文件共用）
--   每关可用 palette 字段覆盖其中任意项。
-- ================================================================
M.DEFAULT_PALETTE = {
    bg       = "111114",   -- 背景
    platform = "F2F2F2",   -- 平台实体色
    ghost    = "3A3A44",   -- 平台虚化色
    label    = "111114",   -- 平台秒数标签（平台实体/亮起时，压在亮色平台上）
    labelGhost = "9AA0AE", -- 平台秒数标签（平台虚化/熄灭时，压在暗色平台上）★ 与 label 反色
    player   = "F2F2F2",   -- 玩家
    goal     = "F2F2F2",   -- 终点门
    hud      = "F2F2F2",   -- 倒计时数字
    pickup   = "7AD6A0",   -- 加时道具
    reverse  = "E0A85A",   -- 反转道具
    danger   = "E05A5A",   -- 危险/失败提示
    -- ---- 菜单 / 结算面板 ----
    overlay  = "08080C",   -- 面板全屏遮罩
    panel    = "1E1E28",   -- 面板底色
    card     = "2A2A36",   -- 选关卡片底色（未选中、未通关）
    panelText = "F2F2F2",  -- 面板主文字
    accent   = "5BC8F5",   -- 高亮 / 选中（主按钮、当前关卡卡片）
    accentText = "0A0A10", -- 压在高亮块上的文字
    dim      = "8A8A9A",   -- 次要文字（副标题、页码、未选中卡片）
    clear    = "7AD6A0",   -- 已通关标记
}

-- ================================================================
-- ★ 关卡数据结构说明
--   name       : 关卡名（字符串，必填）
--   time       : 倒计时初始值（秒，两位小数）
--   spawn      : 玩家出生点 {x, y}（中心坐标）
--   goal       : 终点门 {x, y, width, height}（中心坐标 + 尺寸）
--   palette    : 可选，覆盖 DEFAULT_PALETTE 中的任意配色项
--   platforms  : 平台数组，每项 {x, y, width, height, tick}
--                tick = -1 永驻；tick >= 0 仅在对应秒数为实体
--   pickups    : 道具数组，每项 {x, y, type, value}
--                type = "time"（加时，value 为秒数）
--                type = "reverse"（时间反转）
--   texts      : 提示文本数组，每项 {x, y, text}
-- ================================================================
-- ================================================================
-- ★ 前 3 关：按《滴答咔哒/Tick Hop》原版第01/02/03关实测复刻
--   换算：world = (原版px - {639.5, 360}) * 0.625
--   原版特征：纯黑背景 + 纯白几何（墙/地/门），计时平台熄灭时呈浅灰。
--   每关保留工程原有的教学提示文本（原版无文本）。
-- ================================================================
M.LEVELS = {
    -- ===== 第01关：黑底白框，走到右侧的门即可 =====
    {
        name = "第01关",
        time = 10.00,
        spawn = {x = -290, y = -167},
        goal = {x = 292, y = -154, width = 56, height = 70},
        palette = {
            bg = "000000", platform = "FFFFFF", ghost = "B4B4B4",
            label = "111114", labelGhost = "C8C8C8",
            player = "FFFFFF", goal = "FFFFFF", hud = "FFFFFF",
        },
        platforms = {
            -- 四面框（原版的白框既是墙也是地面）
            {x = 0, y = -199, width = 730, height = 20, tick = -1},
            {x = 0, y = 200, width = 730, height = 20, tick = -1},
            {x = -355, y = 0, width = 20, height = 400, tick = -1},
            {x = 355, y = 0, width = 20, height = 400, tick = -1},
        },
        pickups = {},
        texts = {
            {x = 0, y = 140, text = "一路向右，走进门里"},
        },
    },
    -- ===== 第02关：Z 形折线走廊，需一次跃上右上角高台 =====
    {
        name = "第02关",
        time = 10.00,
        spawn = {x = -300, y = -85},
        goal = {x = 290, y = 78, width = 56, height = 70},
        palette = {
            bg = "000000", platform = "FFFFFF", ghost = "B4B4B4",
            label = "111114", labelGhost = "C8C8C8",
            player = "FFFFFF", goal = "FFFFFF", hud = "FFFFFF",
        },
        platforms = {
            {x = 0, y = 188, width = 690, height = 20, tick = -1},     -- 顶棚
            {x = -338, y = 33, width = 20, height = 310, tick = -1},   -- 左墙
            {x = -224, y = -117, width = 240, height = 20, tick = -1}, -- 上层地面
            {x = -111, y = -150, width = 14, height = 76, tick = -1},  -- 下层台阶
            {x = -19, y = -192, width = 198, height = 20, tick = -1},  -- 下层地面
            {x = 75, y = -76, width = 20, height = 238, tick = -1},    -- 右侧立墙
            {x = 206, y = 33, width = 273, height = 20, tick = -1},    -- 右上高台
            {x = 337, y = 113, width = 20, height = 160, tick = -1},   -- 右墙
        },
        pickups = {},
        texts = {
            {x = -140, y = 150, text = "从上层地面起跳，直上右上角高台"},
        },
    },
    -- ===== 第03关：两侧平台 + 中间「5」秒计时平台 =====
    {
        name = "第03关",
        time = 10.00,
        spawn = {x = -285, y = 10},
        goal = {x = 264, y = 23, width = 56, height = 70},
        palette = {
            bg = "000000", platform = "FFFFFF", ghost = "B4B4B4",
            label = "111114", labelGhost = "C8C8C8",
            player = "FFFFFF", goal = "FFFFFF", hud = "FFFFFF",
        },
        platforms = {
            {x = -5, y = 197, width = 670, height = 20, tick = -1},    -- 顶棚
            {x = -322, y = 82, width = 20, height = 220, tick = -1},   -- 左墙
            {x = -248, y = -22, width = 164, height = 20, tick = -1},  -- 左平台（出生）
            {x = -178, y = -106, width = 20, height = 180, tick = -1}, -- 左下沉墙
            {x = 0, y = -200, width = 370, height = 20, tick = -1},    -- 底部地面
            {x = 178, y = -106, width = 20, height = 180, tick = -1},  -- 右下沉墙
            {x = 248, y = -22, width = 164, height = 20, tick = -1},   -- 右平台（终点侧）
            {x = 322, y = 82, width = 20, height = 220, tick = -1},    -- 右墙
            {x = 4, y = -18, width = 76, height = 24, tick = 5},       -- 「5」秒的中间踏板
        },
        pickups = {},
        texts = {
            {x = -40, y = 150, text = "中间的踏板只在 5 秒时亮起"},
        },
    },
}

-- ================================================================
-- ★ 取关卡配置（1 起始）；越界返回 nil
-- ================================================================
function M.getLevelConfig(index)
    local idx = tonumber(index)
    if not idx then return nil end
    idx = math.floor(idx)
    if idx < 1 or idx > #M.LEVELS then return nil end
    return M.LEVELS[idx]
end

-- ================================================================
-- ★ 关卡总数
-- ================================================================
function M.getLevelCount()
    return #M.LEVELS
end

return M
