-- ================================================================
-- 关卡配置模块
-- ================================================================

local M = {}

-- ================================================================
-- 关卡级默认参数（游戏创建关卡时，Levels 中未配置的项用以下默认值覆盖）
-- ================================================================
M.DEFAULT_GRAVITY = 800
M.DEFAULT_CANDY_DAMPING = 0.9983          -- 阻尼（允许 6 位小数精度）
M.DEFAULT_CONSTRAINT_ITERATIONS = 20
M.DEFAULT_SUB_STEPS = 8
M.DEFAULT_MAX_DRAG_FACTOR = 1.0

-- ================================================================
-- 外观参数（渲染尺寸 / 数量 / 透明度）
-- ================================================================
M.NODE_RADIUS = 2                         -- 绳子中间节点半径
M.FIXED_POINT_RADIUS = 12                 -- 固定点(绳桩)半径
M.CANDY_RADIUS = 18                       -- 糖果半径
M.DOT_RADIUS = 2                          -- 未连接虚线圆点半径
M.DOT_COUNT = 24                          -- 未连接虚线圆点数量
M.UNCONNECTED_ALPHA = 0.6                 -- 未连接虚线圆点透明度
M.ROPE_THICKNESS = 4                      -- 绳子线段厚度
M.SPLINE_SUBDIVISIONS = 6                 -- 样条每两点间细分段数
M.STAR_RADIUS = 15                        -- 星星半径
M.COLLECT_DIST = 35                       -- 星星收集判定半径

-- ================================================================
-- 泡泡默认参数
-- ================================================================
M.DEFAULT_BUBBLE_RADIUS = 28
M.DEFAULT_UPWARD_GRAVITY = 250
M.DEFAULT_BUBBLE_ALPHA = 0.5

-- ★ 泡泡模板（用户自制）：元件 ID 由 game 脚本变量 bubblePrefabId 传入，
--    OnStart 时由 game.lua 读取并写回本字段，创建泡泡时优先使用；未配置(=0)则回退 fruitPrefabId。
M.bubblePrefabId = 0

-- ★ 绳桩（锚点）模板：容器节点模板元件 ID 由 game 脚本变量 anchorPrefabId 传入，
--    OnStart 时由 game.lua 读取并写回本字段，创建固定点(绳桩)时优先使用；
--    未配置(=0)则回退 fruitPrefabId 并把固定点染成红色（保持旧行为）。
--    注意：使用专用模板时不再染色（color 传 nil），保留模板自身外观；
--    渲染尺寸仍由 FIXED_POINT_RADIUS 控制（直径 = FIXED_POINT_RADIUS*2）。
M.anchorPrefabId = 0

-- ================================================================
-- ★ 尖刺默认参数（尖刺为矩形：width 宽 / length 长 / rotation 旋转°，角度为绕中心逆时针）
-- ================================================================
M.DEFAULT_SPIKE_WIDTH = 24
M.DEFAULT_SPIKE_LENGTH = 40
M.DEFAULT_SPIKE_ROTATION = 0

-- ================================================================
-- ★ 文本框默认参数（文本框为矩形：width 宽 / length 长 / rotation 旋转°）
--    text          : 显示文本（字符串，缺省为空）
--    font_size     : 字号（像素，缺省 DEFAULT_TEXT_FONT_SIZE）
--    min_font_size : 字号自适应下限（缺省不开启自适应；>0 时开启 adaptiveFontSize）
-- ================================================================
M.DEFAULT_TEXT_WIDTH = 200
M.DEFAULT_TEXT_LENGTH = 60
M.DEFAULT_TEXT_ROTATION = 0
M.DEFAULT_TEXT_FONT_SIZE = 30
M.DEFAULT_TEXT_MIN_FONT_SIZE = 10

-- ================================================================
-- ★ 木板（矩形障碍）默认参数（木板为矩形：width 宽 / length 长 / rotation 旋转°）
--    木板固定不动，糖果与其发生物理碰撞（推出 + 反弹）。
-- ================================================================
M.DEFAULT_BOARD_WIDTH = 160
M.DEFAULT_BOARD_LENGTH = 24
M.DEFAULT_BOARD_ROTATION = 0
-- 木板反弹系数（0=不反弹仅贴附，1=完全弹性反弹），与绳边反弹同语义
M.DEFAULT_BOARD_BOUNCE_FACTOR = 0.3

-- ================================================================
-- ★ 刀光拖尾默认参数
--    width        : 光带基础宽度（像素）
--    life         : 单个片段从生成到完全消失的时间（秒）
--    min_dist     : 相邻采样点最小间距，越小越平滑但片段越多
--    min_length   : 按住不动时刀光仍保持的最小长度（保证“按下即见光”）
--    max_segments : 同时存在的最大片段数，用于性能保护
-- ================================================================
M.DEFAULT_BLADE_WIDTH = 12
M.DEFAULT_BLADE_LIFE = 0.25
M.DEFAULT_BLADE_MIN_DIST = 6
M.DEFAULT_BLADE_MAX_SEGMENTS = 64
M.DEFAULT_BLADE_MIN_LENGTH = 12

-- ★ 刀光模板（用户自制）：元件 ID 由 game 脚本变量 bladePrefabId 传入，
--    OnStart 时由 game.lua 读取并写回本字段；创建刀光片段时优先使用。
--    未配置(=0)则回退 fruitPrefabId 的白色方块，呈现基础光带。
--    提示：要接近示例图中“两头尖”的笔刷感，建议配置一张中间粗两头尖的白色刀光贴图。
M.bladePrefabId = 0

-- ★ 星星模板（用户自制）：元件 ID 由 game 脚本变量 starPrefabId 传入，
--    OnStart 时由 game.lua 读取并写回本字段；创建星星时优先使用（保留模板外观，不染色）。
--    未配置(=0)则回退 fruitPrefabId 并染成黄色（保持旧行为）。
M.starPrefabId = 0

-- ★ 尖刺模板（用户自制）：元件 ID 由 game 脚本变量 spikePrefabId 传入，
--    OnStart 时由 game.lua 读取并写回本字段；创建尖刺时优先使用（保留模板外观，
--    再按关卡参数 width/length/rotation 设置尺寸与旋转）。
--    未配置(=0)则回退 fruitPrefabId 并染黑（保持旧行为）。
M.spikePrefabId = 0

-- ★ 文本框模板（用户自制）：元件 ID 由 game 脚本变量 textboxPrefabId 传入，
--    OnStart 时由 game.lua 读取并写回本字段；创建文本框时优先使用（保留模板外观，
--    按关卡参数 text/fontSize/min_font_size/width/length/rotation 设置）。
--    未配置(=0)则文本框不显示。
M.textboxPrefabId = 0

-- ★ 木板（矩形障碍）模板（用户自制）：元件 ID 由 game 脚本变量 boardPrefabId 传入，
--    OnStart 时由 game.lua 读取并写回本字段；创建木板时优先使用（保留模板外观，
--    按关卡参数 width/length/rotation 设置尺寸与旋转）。木板为固定障碍，糖果可碰撞。
--    未配置(=0)则回退 fruitPrefabId 并染棕。
M.boardPrefabId = 0

-- ★ 音效预设 ID（由 game 脚本变量传入，OnStart 写回本字段；<=0 表示不播放对应音效）
--    cutAudioId    : 切割音效（切断绳子触发）
--    bubbleAudioId : 戳破泡泡（泡泡破裂触发）
--    winAudioId    : 胜利音效（蛋糕投喂成功触发）
--    failAudioId   : 失败音效（糖果出界或碰到尖刺触发）
--    tenseAudioId  : 绷直音效（绳子由松弛变为绷直状态时触发，上升沿 + 冷却防抖）
--    starAudioId   : 收集星星音效（糖果收集星星时触发）
M.cutAudioId = 0
M.bubbleAudioId = 0
M.winAudioId = 0
M.failAudioId = 0
M.tenseAudioId = 0
M.starAudioId = 0

-- ★ 绷直音效冷却（秒）：同一条绳子在冷却窗口内重复绷直只播一次，避免持续绷着时连续播放
M.DEFAULT_ROPE_TENSE_COOLDOWN = 0.2
-- ★ 绷直音效触发阈值（比例）：本帧 dist >= L 且 上一帧 dist < ratio * L 时触发
--    ratio=0.98 表示需从“明显松弛”状态拉满才触发，避免小幅抖动反复播
M.DEFAULT_ROPE_TENSE_RATIO = 0.9999

-- ================================================================
-- ★ 绳边反弹（糖果被绷紧绳子约束时的径向反弹）
--    约束点 = 固定点(圆心)，(nx,ny) 是 固定点→糖果 的径向单位向量，
--    vn = v·n 是糖果 沿远离圆心方向的速度分量(vn>0 表示糖果正被绳子拽住)。
--
--    DEFAULT_CANDY_BOUNCE_MIN_VEL : 最小反弹速度（像素/秒）。
--        vn < MIN_VEL 时不反弹（径向速度置 0，与旧版一致）
--        vn >= MIN_VEL 时按 BOUNCE_FACTOR 反弹
--    DEFAULT_CANDY_BOUNCE_FACTOR : 反弹系数，通常 0.0~1.0
--        0.0 = 完全无反弹（等价于旧版）
--        0.4 = 弹回去 40%（默认，像橡皮筋轻回弹）
--        1.0 = 完全弹性反弹（全部反弹）
-- ================================================================
M.DEFAULT_CANDY_BOUNCE_MIN_VEL = 20
M.DEFAULT_CANDY_BOUNCE_FACTOR = 0.4

-- ★ 开挂模式弹性碰撞衰减系数（0.0~1.0，越大越弹）
--   仅在开挂模式（state.cheatMode = true）下生效：糖果触碰边界/尖刺不再失败，
--   而是沿法线反弹并按该系数衰减径向速度。
M.DEFAULT_CHEAT_BOUNCE_FACTOR = 0.8

-- ================================================================
-- ★ 关卡切换黑幕过渡默认参数（fadeScreen 模块）
--    顶层显示 3000x3000 黑色矩形，透明度 0 → max_alpha 渐显，
--    维持 hold_time 后 100 → 0 渐隐；渐隐前完成关卡加载。
--    max_alpha 为 0-255 不透明度值（100 ≈ 39% 不透明；
--    若需完全遮住画面请改为 255）。
-- ================================================================
M.DEFAULT_FADE_IN_TIME = 0.2     -- 渐显时长（秒）
M.DEFAULT_FADE_HOLD_TIME = 0.5   -- 全黑维持时长（秒）
M.DEFAULT_FADE_OUT_TIME = 0.2    -- 渐隐时长（秒）
M.DEFAULT_FADE_MAX_ALPHA = 255   -- 渐显峰值不透明度（0-255）

-- ================================================================
-- ★ 绳子默认参数
--    注意：trigger_radius（触发半径）已合并进 total_length（绳长），
--          即“绳长”一个参数即可，触发半径恒等于绳长，不再单独配置。
--    total_length / seg_length 在 Levels 各绳未配置时使用以下默认。
-- ================================================================
M.DEFAULT_ROPE_TOTAL_LENGTH = 200
M.DEFAULT_ROPE_SEG_LENGTH = 10

--[[
-- ★ Levels 数据结构示例（字段说明）
--    name            : 关卡名（字符串，必填，无默认值选项）
--    candy_position  : 糖果起点 {x, y}
--    target          : 目标区域 {x, y, width, height}
--    stars           : 星星数组，每项为 {x, y}
--    bubbles         : 泡泡数组，每项为 {x, y, radius, upward_gravity, alpha}
--    spikes          : 尖刺数组，每项为矩形 {x, y, width, length, rotation}
--    texts           : 文本框数组，每项为 {x, y, width, length, rotation, font_size, min_font_size, text}
--    boards          : 木板(矩形障碍)数组，每项为 {x, y, width, length, rotation}
--    ropes           : 绳子数组，每项为 {fixed = {x, y}, total_length, seg_length}
--                      其中 total_length 为“绳长”（同时是连接触发半径），seg_length 为分段长
--    gravity / candy_damping / constraint_iterations / sub_steps / max_drag_factor
--                    : 关卡级参数，未配置时由上方 DEFAULT_* 覆盖
M.LEVELS = {
    {
        name = "示例关",
        candy_position = {x = 0, y = 0},
        target = {x = 150, y = -80, width = 100, height = 50},
        stars = {
            {x = -50, y = 20},
            {x = 50, y = -10},
        },
        bubbles = {
            {x = -30, y = 30, radius = 28, upward_gravity = 400},
        },
        -- ★ 尖刺（矩形）：width 宽 / length 长 / rotation 旋转°
        spikes = {
            {x = -200, y = -70, width = 24, length = 40, rotation = 0},
        },
        -- ★ 文本框：x,y 位置 / width,length 宽高 / rotation 旋转° / font_size 字号 / min_font_size 自适应最小字号 / text 文本
        texts = {
            {x = 0, y = 120, width = 240, length = 60, rotation = 0, font_size = 32, text = "拖动糖果进绳子"},
        },
        -- ★ 木板（矩形障碍）：width 宽 / length 长 / rotation 旋转°（糖果可碰撞）
        boards = {
            {x = 80, y = -40, width = 200, length = 24, rotation = 0},
        },
        ropes = {
            -- 仅 total_length（绳长=触发半径），不再写 trigger_radius
            {fixed = {x = -80, y = 60}, total_length = 200, seg_length = 10},
            {fixed = {x = 80, y = 60}, total_length = 200, seg_length = 10},
        },
    },
}
--]]

-- 割绳子关卡配置（由关卡编辑器导出，可直接覆盖 config.lua 的 LEVELS 表）
-- 字段说明: name 关卡名 / candy_position 糖果起点 / target 目标 / stars 星星 / bubbles 泡泡 / spikes 尖刺(矩形) / texts 文本框 / boards 木板(矩形障碍) / ropes 绳子
-- 非位置参数若使用默认值则省略（游戏自动用 config.lua 的 DEFAULT_* 覆盖）
M.LEVELS = {
    -- ===================== 关卡: 关卡1 =====================
    {
        name = "关卡1",  -- 关卡名（必填，无默认选项）
        candy_position = {x = -1, y = 74},  -- 糖果起点
        target = {x = 2, y = -280, width = 100, height = 50},  -- 目标区域(宽,高)
        stars = {
            {x = -1, y = -51},
            {x = -2, y = -116},
            {x = -2, y = -179},
        },
        texts = {  -- 文本框: x,y 位置 / width,length 宽高 / rotation 旋转° / font_size 字号 / min_font_size 自适应最小字号 / text 文本
            {x = 1, y = 220, text = "按住鼠标左键/手指滑过割断绳子"},
        },
        ropes = {  -- 绳子: total_length 绳长(=连接触发半径) / seg_length 分段长（均可勾选默认，未配置时省略用 config 默认）
            {fixed = {x = 1, y = 158}, total_length = 150, seg_length = 10},
        },
    },
    -- ===================== 关卡: 关卡2 =====================
    {
        name = "关卡2",  -- 关卡名（必填，无默认选项）
        candy_position = {x = -180, y = 259},  -- 糖果起点
        target = {x = 160, y = -145, width = 100, height = 50},  -- 目标区域(宽,高)
        stars = {
            {x = -83, y = 120},
            {x = 80, y = 118},
            {x = -84, y = 9},
        },
        texts = {  -- 文本框: x,y 位置 / width,length 宽高 / rotation 旋转° / font_size 字号 / min_font_size 自适应最小字号 / text 文本
            {x = -141, y = -238, text = "如果蛋糕掉到地上（出界）芙芙就会哈气，不要浪费食物哦", width = 400},
        },
        ropes = {  -- 绳子: total_length 绳长(=连接触发半径) / seg_length 分段长（均可勾选默认，未配置时省略用 config 默认）
            {fixed = {x = 0, y = 300}, total_length = 200, seg_length = 10},
            {fixed = {x = -150, y = 300}, total_length = 100, seg_length = 10},
            {fixed = {x = 150, y = 300}, total_length = 370, seg_length = 10},
        },
    },
    -- ===================== 关卡: 关卡3 =====================
    {
        name = "关卡3",  -- 关卡名（必填，无默认选项）
        candy_position = {x = 35, y = 154},  -- 糖果起点
        target = {x = 1, y = -262, width = 100, height = 50},  -- 目标区域(宽,高)
        stars = {
            {x = -161, y = 79},
            {x = -161, y = -126},
            {x = -23, y = -181},
        },
        ropes = {  -- 绳子: total_length 绳长(=连接触发半径) / seg_length 分段长（均可勾选默认，未配置时省略用 config 默认）
            {fixed = {x = -80, y = 200}, total_length = 150, seg_length = 10},
            {fixed = {x = 80, y = 200}, total_length = 90, seg_length = 10},
            {fixed = {x = -77, y = 21}, total_length = 170, seg_length = 10},
        },
    },
    -- ===================== 关卡: 关卡4 =====================
    {
        name = "关卡4",  -- 关卡名（必填，无默认选项）
        candy_position = {x = 0, y = 227},  -- 糖果起点
        target = {x = 122, y = -220, width = 100, height = 50},  -- 目标区域(宽,高)
        stars = {
            {x = -198, y = 41},
            {x = 0, y = -153},
            {x = 0, y = 88},
        },
        ropes = {  -- 绳子: total_length 绳长(=连接触发半径) / seg_length 分段长（均可勾选默认，未配置时省略用 config 默认）
            {fixed = {x = -150, y = 200}, total_length = 170, seg_length = 10},
            {fixed = {x = 150, y = 200}, total_length = 170, seg_length = 10},
            {fixed = {x = 1, y = 46}, total_length = 200, seg_length = 10},
            {fixed = {x = 0, y = 319}, total_length = 140, seg_length = 10},
        },
    },
    -- ===================== 关卡: 关卡5 =====================
    {
        name = "关卡5",  -- 关卡名（必填，无默认选项）
        candy_position = {x = -153, y = 97},  -- 糖果起点
        target = {x = -1, y = -208, width = 100, height = 50},  -- 目标区域(宽,高)
        stars = {
            {x = -154, y = 22},
            {x = 1, y = -80},
            {x = 0, y = 192},
        },
        bubbles = {  -- 泡泡: radius 半径 / upward_gravity 上浮力 / alpha 透明度
            {x = -153, y = -81, upward_gravity = 400},
        },
        texts = {  -- 文本框: x,y 位置 / width,length 宽高 / rotation 旋转° / font_size 字号 / min_font_size 自适应最小字号 / text 文本
            {x = -217, y = -169, text = "泡泡可以让蛋糕漂浮，滑过泡泡即可戳破泡泡", width = 250, length = 100},
        },
        ropes = {  -- 绳子: total_length 绳长(=连接触发半径) / seg_length 分段长（均可勾选默认，未配置时省略用 config 默认）
            {fixed = {x = -155, y = 199}, total_length = 120, seg_length = 10},
            {fixed = {x = 0, y = 56}, total_length = 200, seg_length = 10},
        },
    },
    -- ===================== 关卡: 关卡6 =====================
    {
        name = "关卡6",  -- 关卡名（必填，无默认选项）
        candy_position = {x = 0, y = -9},  -- 糖果起点
        target = {x = 0, y = -240, width = 100, height = 50},  -- 目标区域(宽,高)
        stars = {
            {x = 1, y = -165},
            {x = 2, y = -98},
            {x = 0, y = 167},
        },
        bubbles = {  -- 泡泡: radius 半径 / upward_gravity 上浮力 / alpha 透明度
            {x = 2, y = -97, upward_gravity = 400},
        },
        ropes = {  -- 绳子: total_length 绳长(=连接触发半径) / seg_length 分段长（均可勾选默认，未配置时省略用 config 默认）
            {fixed = {x = 0, y = 56}, total_length = 80, seg_length = 10},
        },
    },
    -- ===================== 关卡: 关卡7 =====================
    {
        name = "关卡7",  -- 关卡名（必填，无默认选项）
        candy_position = {x = 4, y = 166},  -- 糖果起点
        target = {x = 0, y = -203, width = 100, height = 50},  -- 目标区域(宽,高)
        stars = {
            {x = -216, y = 78},
            {x = -97, y = -113},
            {x = 2, y = 87},
        },
        ropes = {  -- 绳子: total_length 绳长(=连接触发半径) / seg_length 分段长（均可勾选默认，未配置时省略用 config 默认）
            {fixed = {x = -121, y = 218}, total_length = 170, seg_length = 10},
            {fixed = {x = 121, y = 223}, total_length = 170, seg_length = 10},
            {fixed = {x = -91, y = 53}, total_length = 170, seg_length = 10},
            {fixed = {x = 1, y = 304}, total_length = 170, seg_length = 10},
            {fixed = {x = 100, y = 57}, total_length = 170, seg_length = 10},
        },
    },
    -- ===================== 关卡: 关卡 8 =====================
    {
        name = "关卡 8",  -- 关卡名（必填，无默认选项）
        candy_position = {x = 157, y = 224},  -- 糖果起点
        target = {x = 0, y = -185, width = 100, height = 50},  -- 目标区域(宽,高)
        stars = {
            {x = 102, y = -63},
            {x = -106, y = -68},
            {x = 0, y = 292},
        },
        bubbles = {  -- 泡泡: radius 半径 / upward_gravity 上浮力 / alpha 透明度
            {x = 101, y = -61},
        },
        texts = {  -- 文本框: x,y 位置 / width,length 宽高 / rotation 旋转° / font_size 字号 / min_font_size 自适应最小字号 / text 文本
            {x = 273, y = 28, text = "当蛋糕进入虚线范围时会被绑住"},
        },
        ropes = {  -- 绳子: total_length 绳长(=连接触发半径) / seg_length 分段长（均可勾选默认，未配置时省略用 config 默认）
            {fixed = {x = 1, y = 231}, total_length = 170},
            {fixed = {x = 3, y = 16}, total_length = 140},
            {fixed = {x = 265, y = 225}, total_length = 130},
        },
    },
    -- ===================== 关卡: 关卡 9 =====================
    {
        name = "关卡 9",  -- 关卡名（必填，无默认选项）
        candy_position = {x = 0, y = 0},  -- 糖果起点
        target = {x = 2, y = 243, width = 100, height = 50},  -- 目标区域(宽,高)
        stars = {
            {x = -1, y = -201},
            {x = -70, y = -6},
            {x = -2, y = 92},
        },
        bubbles = {  -- 泡泡: radius 半径 / upward_gravity 上浮力 / alpha 透明度
            {x = -1, y = -201, upward_gravity = 200},
        },
        ropes = {  -- 绳子: total_length 绳长(=连接触发半径) / seg_length 分段长（均可勾选默认，未配置时省略用 config 默认）
            {fixed = {x = 1, y = 199}, total_length = 320},
            {fixed = {x = 82, y = -58}, total_length = 170},
            {fixed = {x = -122, y = -142}, total_length = 160},
        },
    },
    -- ===================== 关卡: 关卡 10 =====================
    {
        name = "关卡 10",  -- 关卡名（必填，无默认选项）
        candy_position = {x = -122, y = 209},  -- 糖果起点
        target = {x = 80, y = -188, width = 100, height = 50},  -- 目标区域(宽,高)
        stars = {
            {x = -28, y = 0},
            {x = 47, y = -118},
            {x = -16, y = -120},
        },
        ropes = {  -- 绳子: total_length 绳长(=连接触发半径) / seg_length 分段长（均可勾选默认，未配置时省略用 config 默认）
            {fixed = {x = -64, y = 58}, total_length = 70},
            {fixed = {x = -121, y = 180}, total_length = 70},
            {fixed = {x = 10, y = -56}, total_length = 70},
        },
    },
    -- ===================== 关卡: 关卡 11 =====================
    {
        name = "关卡 11",  -- 关卡名（必填，无默认选项）
        candy_position = {x = 0, y = 263},  -- 糖果起点
        target = {x = 0, y = -282, width = 100, height = 50},  -- 目标区域(宽,高)
        stars = {
            {x = -200, y = 3},
            {x = -73, y = -160},
            {x = 80, y = -163},
        },
        ropes = {  -- 绳子: total_length 绳长(=连接触发半径) / seg_length 分段长（均可勾选默认，未配置时省略用 config 默认）
            {fixed = {x = -199, y = 100}, total_length = 110},
            {fixed = {x = 203, y = 96}, total_length = 110},
            {fixed = {x = 5, y = 355}, total_length = 130},
            {fixed = {x = -99, y = 265}, total_length = 110},
            {fixed = {x = 100, y = 260}, total_length = 110},
            {fixed = {x = 1, y = -77}, total_length = 130},
        },
    },
    -- ===================== 关卡: 关卡 12 =====================
    {
        name = "关卡 12",  -- 关卡名（必填，无默认选项）
        candy_position = {x = -182, y = 38},  -- 糖果起点
        target = {x = -82, y = 258, width = 100, height = 50},  -- 目标区域(宽,高)
        stars = {
            {x = 80, y = -57},
            {x = 1, y = -162},
            {x = -81, y = 97},
        },
        bubbles = {  -- 泡泡: radius 半径 / upward_gravity 上浮力 / alpha 透明度
            {x = -78, y = -158},
            {x = 1, y = -163},
            {x = 80, y = -153},
        },
        ropes = {  -- 绳子: total_length 绳长(=连接触发半径) / seg_length 分段长（均可勾选默认，未配置时省略用 config 默认）
            {fixed = {x = -83, y = 176}, total_length = 380},
            {fixed = {x = 2, y = 177}, total_length = 260},
        },
    },
    -- ===================== 关卡: 关卡 13 =====================
    {
        name = "关卡 13",  -- 关卡名（必填，无默认选项）
        candy_position = {x = -76, y = -100},  -- 糖果起点
        target = {x = 160, y = 177, width = 100, height = 50},  -- 目标区域(宽,高)
        stars = {
            {x = -76, y = -191},
            {x = 116, y = 31},
            {x = -69, y = 35},
        },
        bubbles = {  -- 泡泡: radius 半径 / upward_gravity 上浮力 / alpha 透明度
            {x = 114, y = 32},
            {x = -75, y = -191},
        },
        ropes = {  -- 绳子: total_length 绳长(=连接触发半径) / seg_length 分段长（均可勾选默认，未配置时省略用 config 默认）
            {fixed = {x = -78, y = -57}, total_length = 70},
            {fixed = {x = 27, y = 101}, total_length = 120},
        },
    },
    -- ===================== 关卡: 关卡 14 =====================
    {
        name = "关卡 14",  -- 关卡名（必填，无默认选项）
        candy_position = {x = -287, y = 143},  -- 糖果起点
        target = {x = 141, y = -171, width = 100, height = 50},  -- 目标区域(宽,高)
        stars = {
            {x = 41, y = -109},
            {x = -210, y = 70},
            {x = -85, y = -18},
        },
        ropes = {  -- 绳子: total_length 绳长(=连接触发半径) / seg_length 分段长（均可勾选默认，未配置时省略用 config 默认）
            {fixed = {x = -88, y = 36}, total_length = 60},
            {fixed = {x = 37, y = -57}, total_length = 60},
            {fixed = {x = -361, y = 141}, total_length = 80},
            {fixed = {x = -213, y = 141}, total_length = 80},
        },
    },
    -- ===================== 关卡: 关卡 15 =====================
    {
        name = "关卡 15",  -- 关卡名（必填，无默认选项）
        candy_position = {x = -91, y = 141},  -- 糖果起点
        target = {x = 64, y = -164, width = 100, height = 50},  -- 目标区域(宽,高)
        stars = {
            {x = -59, y = 61},
            {x = -6, y = 13},
            {x = 38, y = -77},
        },
        spikes = {  -- 尖刺(矩形): width 宽 / length 长 / rotation 旋转°(绕中心逆时针)
            {x = 88, y = 83, width = 60, length = 20},
        },
        texts = {  -- 文本框: x,y 位置 / width,length 宽高 / rotation 旋转° / font_size 字号 / min_font_size 自适应最小字号 / text 文本
            {x = 162, y = 137, text = "蛋糕碰到脏东西（尖刺）就不能吃了"},
        },
        ropes = {  -- 绳子: total_length 绳长(=连接触发半径) / seg_length 分段长（均可勾选默认，未配置时省略用 config 默认）
            {fixed = {x = 0, y = 140}, total_length = 100},
            {fixed = {x = -185, y = 146}, total_length = 100},
        },
    },
    -- ===================== 关卡: 关卡 16 =====================
    {
        name = "关卡 16",  -- 关卡名（必填，无默认选项）
        candy_position = {x = -102, y = 215},  -- 糖果起点
        target = {x = 1, y = -138, width = 100, height = 50},  -- 目标区域(宽,高)
        stars = {
            {x = 77, y = 176},
            {x = 80, y = 48},
            {x = -72, y = 42},
        },
        spikes = {  -- 尖刺(矩形): width 宽 / length 长 / rotation 旋转°(绕中心逆时针)
            {x = 0, y = 96, width = 80, length = 20},
            {x = -1, y = -28, width = 80, length = 20},
        },
        ropes = {  -- 绳子: total_length 绳长(=连接触发半径) / seg_length 分段长（均可勾选默认，未配置时省略用 config 默认）
            {fixed = {x = -121, y = 299}, total_length = 100},
            {fixed = {x = -3, y = 300}, total_length = 150},
            {fixed = {x = -2, y = 174}, total_length = 150},
            {fixed = {x = -1, y = 55}},
        },
    },
    -- ===================== 关卡: 关卡 17 =====================
    {
        name = "关卡 17",  -- 关卡名（必填，无默认选项）
        candy_position = {x = -138, y = 225},  -- 糖果起点
        target = {x = 124, y = -108, width = 100, height = 50},  -- 目标区域(宽,高)
        stars = {
            {x = -139, y = 149},
            {x = -3, y = 88},
            {x = 0, y = -66},
        },
        spikes = {  -- 尖刺(矩形): width 宽 / length 长 / rotation 旋转°(绕中心逆时针)
            {x = 127, y = 115, width = 80, length = 20, rotation = 90},
        },
        ropes = {  -- 绳子: total_length 绳长(=连接触发半径) / seg_length 分段长（均可勾选默认，未配置时省略用 config 默认）
            {fixed = {x = -140, y = 260}, total_length = 50},
            {fixed = {x = 121, y = 258}, total_length = 350},
            {fixed = {x = -3, y = 264}, total_length = 180},
            {fixed = {x = -75, y = 128}, total_length = 150},
        },
    },
    -- ===================== 关卡: 关卡 18 =====================
    {
        name = "关卡 18",  -- 关卡名（必填，无默认选项）
        candy_position = {x = -2, y = 234},  -- 糖果起点
        target = {x = 5, y = -190, width = 100, height = 50},  -- 目标区域(宽,高)
        stars = {
            {x = 79, y = 140},
            {x = 80, y = 1},
            {x = -83, y = -99},
        },
        spikes = {  -- 尖刺(矩形): width 宽 / length 长 / rotation 旋转°(绕中心逆时针)
            {x = 1, y = 98, width = 50, length = 20, rotation = -90},
            {x = 0, y = 21, width = 50, length = 20},
        },
        ropes = {  -- 绳子: total_length 绳长(=连接触发半径) / seg_length 分段长（均可勾选默认，未配置时省略用 config 默认）
            {fixed = {x = -88, y = 259}, total_length = 120},
            {fixed = {x = 81, y = 258}, total_length = 120},
            {fixed = {x = 79, y = 179}, total_length = 180},
            {fixed = {x = 79, y = 99}},
            {fixed = {x = -84, y = 97}},
        },
    },
    -- ===================== 关卡: 关卡 19 =====================
    {
        name = "关卡 19",  -- 关卡名（必填，无默认选项）
        candy_position = {x = 202, y = 214},  -- 糖果起点
        target = {x = -82, y = -66, width = 100, height = 50},  -- 目标区域(宽,高)
        stars = {
            {x = 126, y = -153},
            {x = -6, y = 246},
            {x = -83, y = 83},
        },
        bubbles = {  -- 泡泡: radius 半径 / upward_gravity 上浮力 / alpha 透明度
            {x = 125, y = -152},
        },
        spikes = {  -- 尖刺(矩形): width 宽 / length 长 / rotation 旋转°(绕中心逆时针)
            {x = 130, y = 101, width = 150, length = 30, rotation = 90},
            {x = -78, y = 277, width = 50, length = 20, rotation = 90},
        },
        ropes = {  -- 绳子: total_length 绳长(=连接触发半径) / seg_length 分段长（均可勾选默认，未配置时省略用 config 默认）
            {fixed = {x = -79, y = 181}, total_length = 100},
            {fixed = {x = 128, y = -54}, total_length = 100},
            {fixed = {x = 200, y = 261}, total_length = 80},
        },
    },
    -- ===================== 关卡: 关卡 20 =====================
    {
        name = "关卡 20",  -- 关卡名（必填，无默认选项）
        candy_position = {x = 0, y = 254},  -- 糖果起点
        target = {x = -1, y = -211, width = 100, height = 50},  -- 目标区域(宽,高)
        stars = {
            {x = 0, y = 106},
            {x = 1, y = 24},
            {x = -2, y = -92},
        },
        spikes = {  -- 尖刺(矩形): width 宽 / length 长 / rotation 旋转°(绕中心逆时针)
            {x = -154, y = 45, width = 250, length = 40, rotation = 60},
            {x = 153, y = 46, width = 250, length = 40, rotation = -60},
        },
        ropes = {  -- 绳子: total_length 绳长(=连接触发半径) / seg_length 分段长（均可勾选默认，未配置时省略用 config 默认）
            {fixed = {x = -82, y = 3}, total_length = 130},
            {fixed = {x = 81, y = 1}, total_length = 130},
            {fixed = {x = -121, y = 300}, total_length = 150},
            {fixed = {x = 116, y = 300}, total_length = 150},
        },
    },
}

M.CURRENT_LEVEL = 1

function M.getLevelConfig(index)
    local level = M.LEVELS[index]
    if not level then return nil end
    local config = {}
    for k, v in pairs(level) do
        config[k] = v
    end
    -- 关卡级参数：缺失时使用默认配置参数覆盖
    config.gravity = config.gravity or M.DEFAULT_GRAVITY
    config.candy_damping = config.candy_damping or M.DEFAULT_CANDY_DAMPING
    config.constraint_iterations = config.constraint_iterations or M.DEFAULT_CONSTRAINT_ITERATIONS
    config.sub_steps = config.sub_steps or M.DEFAULT_SUB_STEPS
    config.max_drag_factor = config.max_drag_factor or M.DEFAULT_MAX_DRAG_FACTOR
    -- 泡泡参数：缺失时使用默认配置参数覆盖
    config.bubbles = config.bubbles or {}
    for _, b in ipairs(config.bubbles) do
        b.radius = b.radius or M.DEFAULT_BUBBLE_RADIUS
        b.upward_gravity = b.upward_gravity or M.DEFAULT_UPWARD_GRAVITY
        if b.alpha == nil then b.alpha = M.DEFAULT_BUBBLE_ALPHA end
    end
    -- 尖刺参数：缺失时使用默认配置参数覆盖（矩形：width / length / rotation）
    config.spikes = config.spikes or {}
    for _, s in ipairs(config.spikes) do
        s.width = s.width or M.DEFAULT_SPIKE_WIDTH
        s.length = s.length or M.DEFAULT_SPIKE_LENGTH
        s.rotation = s.rotation or M.DEFAULT_SPIKE_ROTATION
    end
    -- 文本框参数：缺失时使用默认配置参数覆盖
    config.texts = config.texts or {}
    for _, t in ipairs(config.texts) do
        t.width = t.width or M.DEFAULT_TEXT_WIDTH
        t.length = t.length or M.DEFAULT_TEXT_LENGTH
        t.rotation = t.rotation or M.DEFAULT_TEXT_ROTATION
        t.font_size = t.font_size or M.DEFAULT_TEXT_FONT_SIZE
        -- text / min_font_size 可选，不强制覆盖
    end
    -- 木板参数：缺失时使用默认配置参数覆盖（矩形：width / length / rotation）
    config.boards = config.boards or {}
    for _, b in ipairs(config.boards) do
        b.width = b.width or M.DEFAULT_BOARD_WIDTH
        b.length = b.length or M.DEFAULT_BOARD_LENGTH
        b.rotation = b.rotation or M.DEFAULT_BOARD_ROTATION
    end
    -- 绳子参数：缺失时使用默认配置参数覆盖。
    -- total_length 同时作为“连接触发半径”（trigger_radius 已合并，不再单独配置）。
    config.ropes = config.ropes or {}
    for _, rope in ipairs(config.ropes) do
        rope.total_length = rope.total_length or M.DEFAULT_ROPE_TOTAL_LENGTH
        rope.seg_length = rope.seg_length or M.DEFAULT_ROPE_SEG_LENGTH
        -- trigger_radius 恒等于 total_length（兼容旧数据：若显式给出则忽略，统一取绳长）
        rope.trigger_radius = rope.total_length
    end
    config.stars = config.stars or {}
    return config
end

function M.getLevelCount()
    return #M.LEVELS
end

_G.getLevelConfig = M.getLevelConfig
_G.getLevelCount = M.getLevelCount

function OnStart()
    print("config模块已加载")
end

return M
