-- ================================================================
-- 皮耶罗：赴死（I wanna weigh the life）· 参数配置（唯一真源）
-- ================================================================
-- 玩法母本：level-devil（FableDevil）—— 30 关手写陷阱的「rage platformer」。
-- ★ 本工程第一阶段 = 原版逐项复刻：**关卡数据、物理常量、陷阱参数全部沿用原版数值**，
--   世界坐标系也沿用原版（960×540，y 轴向下，重力为正）。
--   渲染层只做一次坐标翻转（utils.toUIX / toUIY），所以关卡数据可以照抄，
--   不用重新换算任何一格。
-- ★ 第二阶段（原神元素 UI 包装）只改本文件里的「配色 / 文案 / COMIC 分镜」，
--   不需要动任何玩法代码。
-- ================================================================

---@diagnostic disable: undefined-global

local M = {}

-- ================================================================
-- 一、世界与画布
-- ★ 设计基准 = 世界尺寸，1 世界像素 = 1 设计像素，整层再用 k 缩放适配屏幕。
-- ================================================================
M.DEFAULT_WORLD_W = 960
M.DEFAULT_WORLD_H = 540
M.DEFAULT_DESIGN_W = 960
M.DEFAULT_DESIGN_H = 540
M.DEFAULT_MIN_SCALE = 0.50           -- 极小屏兜底（再小就整体缩，不让内容溢出）

-- ================================================================
-- 二、物理（与原版 game.js 逐项一致，单位：像素 / 秒）
-- ================================================================
M.DEFAULT_PLAYER_W = 26              -- 玩家碰撞盒
M.DEFAULT_PLAYER_H = 32
M.DEFAULT_MOVE_SPEED = 265           -- 水平最大速度
M.DEFAULT_GROUND_ACCEL = 2600        -- 地面加速度
M.DEFAULT_AIR_ACCEL = 1800           -- 空中加速度
M.DEFAULT_JUMP_SPEED = -645          -- 起跳初速（y 向下为正，故为负）
M.DEFAULT_GRAVITY = 2150
M.DEFAULT_MAX_FALL = 980             -- 最大下落速度
M.DEFAULT_JUMP_CUT = -220            -- 松手截断阈值（vy 高于此值的上升段才被削）
M.DEFAULT_COYOTE_TIME = 0.10         -- 土狼时间
M.DEFAULT_JUMP_BUFFER = 0.12         -- 跳跃输入缓冲
M.DEFAULT_PHYS_SUBSTEP = 0.0080      -- 物理子步长（原版单帧解算，这里细分以免穿透）
M.DEFAULT_CRUSH_INSET = 4            -- 被实体夹住判死的收缩量

-- ================================================================
-- 三、鬼魂模式（不死诅咒）
-- ★ 用户要求：**默认打开**。开启后玩家不会真正死亡，而是化成鬼魂，
--   可以自由漂浮，按跳跃键在当前位置复活（位置不合法则复活失败）。
-- ================================================================
M.DEFAULT_GHOST_ON = 1               -- 1 = 不死诅咒默认生效
M.DEFAULT_GHOST_SPEED = 320          -- 鬼魂漂浮速度
M.DEFAULT_GHOST_FAIL_TIME = 0.35     -- 复活失败的红闪时长
M.DEFAULT_GHOST_ALPHA = 130          -- 鬼魂本体不透明度

-- ================================================================
-- 四、门（生死之间）与关卡节奏
-- ================================================================
M.DEFAULT_DOOR_W = 38
M.DEFAULT_DOOR_H = 64
M.DEFAULT_DOOR_FLEE = 110            -- 逃避门的触发半径
M.DEFAULT_DEATH_HOLD = 0.85          -- 死亡后停留（秒）再重开
M.DEFAULT_WIN_HOLD = 0.80            -- 过关后停留（秒）再进入结算演出
M.DEFAULT_LEVEL_COUNT = 30

-- ================================================================
-- 五、陷阱默认参数（原版构造函数的缺省值）
-- ================================================================
M.DEFAULT_SPIKE_SIZE = 26
M.DEFAULT_SPIKE_SPEED = 14           -- 弹出/收回速度（倍率/秒）
M.DEFAULT_SPIKE_HOLD = 0.80          -- 周期型保持外露的时长
M.DEFAULT_COLLAPSE_SHAKE = 0.18
M.DEFAULT_FALLBLOCK_SHAKE = 0.12
M.DEFAULT_FALLBLOCK_FLOOR = 480
M.DEFAULT_CRUMBLE_DELAY = 0.35
M.DEFAULT_CRUSHER_HEAD = 46
M.DEFAULT_CRUSHER_PERIOD = 1.90
M.DEFAULT_CRUSHER_SLAM = 1500
M.DEFAULT_CRUSHER_UP = 240
M.DEFAULT_CRUSHER_HOLD = 0.32
M.DEFAULT_HOLE_Y = 480
M.DEFAULT_HOLE_H = 60
M.DEFAULT_HOLE_GAP = 92
M.DEFAULT_HOLE_SPEED = 130
M.DEFAULT_MOVER_SPEED = 80
M.DEFAULT_CONVEYOR_FORCE = 150
M.DEFAULT_SPRING_W = 50
M.DEFAULT_SPRING_H = 14
M.DEFAULT_SPRING_POWER = -980
M.DEFAULT_SAW_R = 22
M.DEFAULT_SAW_SPEED = 130
M.DEFAULT_LASER_LEN = 400
M.DEFAULT_LASER_THICK = 10
M.DEFAULT_LASER_PERIOD = 2.2
M.DEFAULT_LASER_WARN = 0.55
M.DEFAULT_LASER_FIRE = 0.50
M.DEFAULT_TELE_W = 30
M.DEFAULT_TELE_H = 48
M.DEFAULT_BUTTON_W = 44
M.DEFAULT_GATE_OPEN_SPEED = 4.0
M.DEFAULT_BLINK_PERIOD = 1.8
M.DEFAULT_BLINK_ON = 0.50
M.DEFAULT_PEND_LEN = 380
M.DEFAULT_PEND_AMP = 0.85
M.DEFAULT_PEND_SPEED = 1.6
M.DEFAULT_PEND_R = 18
M.DEFAULT_TURRET_PERIOD = 1.6
M.DEFAULT_TURRET_SPEED = 260
M.DEFAULT_TURRET_R = 7
M.DEFAULT_TURRET_BULLETS = 5

-- ================================================================
-- 六、特效
-- ================================================================
M.DEFAULT_FX_POOL = 44               -- 粒子控件池（复用，不逐次创建销毁）
M.DEFAULT_STAIN_POOL = 24            -- 血渍控件池（死亡残留，复活时清空）
M.DEFAULT_BLOOD_COUNT = 12
M.DEFAULT_DUST_COUNT = 6
M.DEFAULT_POOF_COUNT = 8
M.DEFAULT_SHAKE_DECAY = 1.0

-- ================================================================
-- 七、UI
-- ================================================================
M.DEFAULT_HUD_NAME_SIZE = 20
M.DEFAULT_HUD_SUB_SIZE = 13
M.DEFAULT_HUD_DEATH_SIZE = 18
M.DEFAULT_HUD_MSG_SIZE = 15
M.DEFAULT_DEATH_LINE_SIZE = 40
M.DEFAULT_WIN_LINE_SIZE = 34

M.DEFAULT_MENU_TITLE_SIZE = 46
M.DEFAULT_MENU_SUB_SIZE = 15
M.DEFAULT_MENU_GRID_COLS = 10
M.DEFAULT_MENU_GRID_ROWS = 3
M.DEFAULT_MENU_CELL_W = 72
M.DEFAULT_MENU_CELL_H = 52
M.DEFAULT_MENU_CELL_GAP = 10
M.DEFAULT_MENU_BTN_W = 240
M.DEFAULT_MENU_BTN_H = 52
M.DEFAULT_BTN_SIZE = 18
M.DEFAULT_BTN_PRESS = 0.96
M.DEFAULT_BTN_DISABLED_ALPHA = 70

-- ================================================================
-- 八、过渡
-- ================================================================
M.DEFAULT_FADE_IN_TIME = 0.18
M.DEFAULT_FADE_HOLD_TIME = 0.10
M.DEFAULT_FADE_OUT_TIME = 0.22
M.DEFAULT_FADE_MAX_ALPHA = 255

-- ================================================================
-- 九、结算演出（动态漫画）
-- ★ 第一阶段用「图元 + 文案」占位：分镜数据全在本节，换成原神参考图时
--   只需把 actors 的 shape 换成图片 prefab，不用改编排代码。
-- ================================================================
M.DEFAULT_COMIC_ON = 1               -- 1 = 每关过关都播（= 每次轮回的献祭）
M.COMIC_DAMAGE = 3927698             -- 愚人之眼对若娜瓦造成的伤害
M.DEFAULT_COMIC_PANEL_HOLD = 0.95    -- 单格停留
M.DEFAULT_COMIC_FADE = 0.14          -- 格间淡入淡出
M.DEFAULT_COMIC_NUMBER_TIME = 1.30   -- 伤害数字滚动时长
M.DEFAULT_COMIC_LETTERBOX = 62       -- 上下黑边高度

-- 每一格的字段：
--   caption  底部字幕（★ 控制在 30 字内，否则会被裁）
--   bg       底色
--   actors   图元剪影，见 comic.lua 的 SHAPES
M.COMIC = {
    panels = {
        {
            caption = "生死之间，门为你开着。",
            bg = "0B0E16",
            actors = {
                { shape = "door", x = 150, y = -10, w = 120, h = 210, hex = "FFB24D" },
                { shape = "harlequin", x = -190, y = -20, h = 170, hex = "2A2F3D" },
                { shape = "glow", x = 150, y = -10, w = 300, h = 300, hex = "FFB24D", alpha = 26 },
            },
        },
        {
            caption = "把生命按在愚人之眼上。",
            bg = "080A12",
            actors = {
                { shape = "eye", x = 40, y = 20, w = 190, h = 120, hex = "FFB24D" },
                { shape = "harlequin", x = -250, y = -30, h = 190, hex = "343B4C" },
                { shape = "glow", x = 40, y = 20, w = 360, h = 360, hex = "FF5D52", alpha = 22 },
            },
        },
        {
            caption = "愚人之眼，解放！",
            bg = "1A0A0C",
            actors = {
                { shape = "eye", x = 0, y = 30, w = 340, h = 220, hex = "FF7A5C" },
                { shape = "burst", x = 0, y = 30, w = 620, h = 620, hex = "FFB24D", alpha = 40 },
            },
        },
        {
            caption = "若娜瓦，收下这份献祭。",
            bg = "120610",
            actors = {
                { shape = "zonava", x = 150, y = 0, w = 230, h = 250, hex = "4A2340" },
                { shape = "burst", x = -140, y = 20, w = 420, h = 420, hex = "FF5D52", alpha = 34 },
            },
        },
    },
}

-- ================================================================
-- 十、配色（原版 dark 主题；原神包装阶段整体替换本表即可）
-- ================================================================
M.DEFAULT_PALETTE = {
    bg        = "14161D",   -- paper
    bg2       = "1C1F29",
    ink       = "ECE8DF",   -- 实体（平台 / 尖刺 / 方块）
    grid      = "1A1D26",
    danger    = "FF5D52",
    accent    = "FFB24D",
    door      = "FFB24D",
    blood     = "FF5D52",
    bloodDark = "B83A31",
    dust      = "565B69",
    metal     = "2C3140",
    crack     = "12141B",
    wipe      = "0B0C11",
    text      = "ECE8DF",
    textDim   = "8A8F9C",
    btn       = "232733",
    btnDown   = "2E3342",
    btnText   = "ECE8DF",
    locked    = "191C24",
    done      = "FFB24D",
}

-- ================================================================
-- 十一、死亡吐槽 / 总结（原版台词，全 ASCII 安全字形）
-- ================================================================
M.DEATH_LINES = {
    "OUCH.", "LOL.", "SKILL ISSUE.", "SO CLOSE.", "AGAIN?",
    "PERFECTLY PLANNED.", "YOU FELL FOR IT.", "THE DEVIL LAUGHS.",
    "CLASSIC.", "WHO PUT THAT THERE?", "OOPS.", "TRY WALKING SLOWER.",
    "THAT ONE'S ON YOU.", "HE-HE.", "NICE ONE.",
}

M.ROASTS = {
    { 0,    "一条命都没丢？不可能。" },
    { 25,   "还行，挺体面的。" },
    { 75,   "每一次死亡，丑角都笑纳了。" },
    { 150,  "你有没有考虑过不要一直冲刺？" },
    { 9999, "地板已经认识你了。" },
}

-- ================================================================
-- 十二、关卡数据（★ 与原版 LEVELS 一一对应，坐标原样照抄）
-- ================================================================
-- 方块/实体的坐标一律是「左上角 + 宽高」，y 轴向下。
-- traps 的字段名尽量贴近原版构造参数，方便对照原版 game.js 核对。

local WORLD_H = M.DEFAULT_WORLD_H

-- 实心矩形（左上角 + 宽高）
local function R(x, y, w, h) return { x = x, y = y, w = w, h = h } end
-- 地面段：从 x0 到 x1，默认顶面 y=480（与原版 floorSeg 一致）
local function F(x0, x1, y)
    y = y or 480
    return { x = x0, y = y, w = x1 - x0, h = WORLD_H - y }
end
local WALL_L = R(-40, -200, 40, 740)
local WALL_R = R(960, -200, 40, 740)
local function ROOF(h) return R(0, 0, 960, h or 30) end

M.LEVELS = {
    -- ---------------------------------------------------------- 1
    {
        name = "NOTHING TO SEE HERE",
        spawn = { x = 60, y = 440 },
        door = { { x = 876, y = 416 } },
        solids = { F(0, 400), F(500, 960), WALL_L, WALL_R },
        traps = {
            { kind = "collapse", rect = R(400, 480, 100, 60), trig = R(330, 300, 30, 180) },
            { kind = "pop", x = 760, y = 480, w = 80, trig = R(708, 330, 26, 150), delay = 0.06 },
            { kind = "note", x = 210, y = 430, text = "just walk to the door :)" },
        },
    },
    -- ---------------------------------------------------------- 2
    {
        name = "TRUST ISSUES",
        spawn = { x = 60, y = 440 },
        door = { { x = 876, y = 416 } },
        solids = { F(0, 200), F(760, 960), WALL_L, WALL_R },
        traps = {
            { kind = "crumble", rect = R(270, 408, 92, 16), delay = 0.32 },
            { kind = "crumble", rect = R(430, 360, 92, 16), delay = 0.32 },
            { kind = "crumble", rect = R(590, 408, 92, 16), delay = 0.18 },
            { kind = "fallblock", rect = R(440, 40, 70, 42), trig = R(430, 200, 92, 170), floorY = 540 },
            { kind = "pop", x = 764, y = 480, w = 70, trig = R(700, 330, 20, 150), delay = 0.02 },
            { kind = "note", x = 310, y = 380, text = "they look sturdy", angle = -0.05 },
        },
    },
    -- ---------------------------------------------------------- 3
    {
        name = "POINTY SITUATION",
        spawn = { x = 50, y = 440 },
        door = { { x = 880, y = 416 } },
        solids = { F(0, 960), WALL_L, WALL_R },
        traps = {
            { kind = "pop", x = 220, y = 480, w = 64, period = 1.70, phase = 0.00, holdOut = 0.75 },
            { kind = "pop", x = 330, y = 480, w = 64, period = 1.70, phase = 0.28, holdOut = 0.75 },
            { kind = "pop", x = 440, y = 480, w = 64, period = 1.70, phase = 0.56, holdOut = 0.75 },
            { kind = "pop", x = 550, y = 480, w = 64, period = 1.70, phase = 0.84, holdOut = 0.75 },
            { kind = "pop", x = 660, y = 480, w = 64, period = 1.70, phase = 1.12, holdOut = 0.75 },
            { kind = "pop", x = 790, y = 480, w = 76, trig = R(742, 330, 18, 150), delay = 0.05 },
            { kind = "note", x = 120, y = 420, text = "find the rhythm", angle = 0.04 },
        },
    },
    -- ---------------------------------------------------------- 4
    {
        name = "THE SKY IS FALLING",
        spawn = { x = 55, y = 440 },
        door = { { x = 876, y = 416 } },
        solids = { F(0, 960), ROOF(40), WALL_L, WALL_R },
        traps = {
            { kind = "fallblock", rect = R(200, 40, 64, 42), trig = R(180, 200, 104, 280) },
            { kind = "fallblock", rect = R(360, 40, 64, 42), trig = R(340, 200, 104, 280) },
            { kind = "fallblock", rect = R(520, 40, 64, 42), trig = R(500, 200, 104, 280) },
            { kind = "fallblock", rect = R(680, 40, 64, 42), trig = R(660, 200, 104, 280) },
            { kind = "fallblock", rect = R(820, 40, 76, 42), trig = R(770, 200, 40, 280), shakeTime = 0.04 },
            { kind = "note", x = 120, y = 100, text = "look up.", size = 14 },
        },
    },
    -- ---------------------------------------------------------- 5
    {
        name = "GOING UP?",
        spawn = { x = 60, y = 440 },
        door = { { x = 884, y = 416 } },
        solids = { F(0, 300), F(620, 960), WALL_L, WALL_R },
        traps = {
            { kind = "mover", rect = R(300, 452, 100, 16), toX = 520, speed = 95, pause = 0.5 },
            { kind = "note", x = 160, y = 430, text = "hop on. free ride :)" },
            { kind = "pop", x = 806, y = 480, w = 70, trig = R(706, 330, 18, 150), delay = 0.05 },
        },
    },
    -- ---------------------------------------------------------- 6
    {
        name = "COME BACK HERE!",
        spawn = { x = 60, y = 440 },
        door = { { x = 870, y = 416 }, { x = 470, y = 416 }, { x = 120, y = 416 }, { x = 856, y = 288 } },
        fleeDist = 105,
        solids = { F(0, 960), R(640, 420, 92, 14), R(800, 352, 160, 16), WALL_L, WALL_R },
        traps = {
            { kind = "pop", x = 652, y = 420, w = 68, trig = R(640, 320, 92, 100), delay = 0.45 },
            { kind = "note", x = 760, y = 250, text = "it just wants a hug" },
        },
    },
    -- ---------------------------------------------------------- 7
    {
        name = "TREADMILL DAY",
        spawn = { x = 150, y = 440 },
        door = { { x = 884, y = 416 } },
        solids = { F(120, 960), WALL_L, WALL_R },
        traps = {
            { kind = "conveyor", rect = R(300, 480, 320, 60), dir = -1, force = 165 },
            { kind = "note", x = 450, y = 430, text = "keep walking ->" },
            { kind = "pop", x = 812, y = 480, w = 66, trig = R(720, 330, 16, 150), delay = 0.04 },
        },
    },
    -- ---------------------------------------------------------- 8
    {
        name = "THE FLOOR HATES YOU",
        spawn = { x = 55, y = 440 },
        door = { { x = 880, y = 416 } },
        solids = { WALL_L, WALL_R },
        traps = {
            { kind = "hole", x0 = 0, x1 = 960, gapW = 96, startGap = 760, speed = 150,
              trig = R(120, 300, 20, 180) },
            { kind = "pop", x = 806, y = 480, w = 64, trig = R(756, 330, 16, 150), delay = 0.03 },
            { kind = "note", x = 420, y = 420, text = "the hole is friendly", angle = -0.03 },
        },
    },
    -- ---------------------------------------------------------- 9
    {
        name = "BOING",
        spawn = { x = 60, y = 440 },
        door = { { x = 884, y = 226 } },
        solids = { F(0, 440), R(480, 290, 480, 16), WALL_L, WALL_R },
        traps = {
            { kind = "spring", x = 360, y = 480, power = -1220 },
            { kind = "note", x = 160, y = 430, text = "trampoline time" },
            { kind = "pop", x = 700, y = 290, w = 60, trig = R(580, 200, 18, 90), delay = 0.3 },
        },
    },
    -- ---------------------------------------------------------- 10
    {
        name = "?NOISUFNOC",
        spawn = { x = 55, y = 440 },
        door = { { x = 880, y = 416 } },
        solids = { F(0, 350), F(430, 540), F(620, 960), WALL_L, WALL_R },
        traps = {
            { kind = "invert", rect = R(280, 0, 420, 480) },
            { kind = "spikes", x = 355, y = 540, w = 70, dir = "up", size = 40 },
            { kind = "spikes", x = 545, y = 540, w = 70, dir = "up", size = 40 },
            { kind = "pop", x = 700, y = 480, w = 64, trig = R(648, 330, 16, 150), delay = 0.4 },
            { kind = "note", x = 490, y = 300, text = "sdrawkcab", size = 18 },
        },
    },
    -- ---------------------------------------------------------- 11
    {
        name = "NOW YOU SEE IT",
        spawn = { x = 60, y = 440 },
        door = { { x = 884, y = 416 } },
        solids = { F(0, 250), F(740, 960), WALL_L, WALL_R },
        traps = {
            { kind = "blink", rect = R(300, 430, 96, 16), period = 1.7, onFrac = 0.62, phase = 0.00 },
            { kind = "blink", rect = R(444, 400, 96, 16), period = 1.7, onFrac = 0.62, phase = 0.34 },
            { kind = "blink", rect = R(588, 430, 96, 16), period = 1.7, onFrac = 0.62, phase = 0.68 },
            { kind = "note", x = 150, y = 430, text = "now you don't" },
            { kind = "pop", x = 806, y = 480, w = 66, trig = R(720, 330, 16, 150), delay = 0.05 },
        },
    },
    -- ---------------------------------------------------------- 12
    {
        name = "PICK A DOOR",
        spawn = { x = 55, y = 440 },
        door = { { x = 884, y = 416 } },
        solids = { F(0, 960), WALL_L, WALL_R },
        traps = {
            { kind = "fakedoor", x = 380, y = 416, label = "definitely this one" },
            { kind = "fakedoor", x = 600, y = 416, label = "or this one?" },
            { kind = "fallblock", rect = R(800, 40, 70, 42), trig = R(745, 200, 50, 280), shakeTime = 0.05 },
            { kind = "pop", x = 700, y = 480, w = 70, trig = R(560, 330, 30, 150), delay = 0.85 },
            { kind = "note", x = 903, y = 396, text = "scam", size = 13, angle = 0.06 },
        },
    },
    -- ---------------------------------------------------------- 13
    {
        name = "SAW IT COMING",
        spawn = { x = 55, y = 440 },
        door = { { x = 884, y = 416 } },
        solids = { F(0, 960), ROOF(30), WALL_L, WALL_R },
        traps = {
            { kind = "saw", path = { { x = 300, y = 444 }, { x = 640, y = 444 } }, r = 24, speed = 165 },
            { kind = "saw", path = { { x = 520, y = 90 }, { x = 520, y = 430 } }, r = 22, speed = 185 },
            { kind = "note", x = 150, y = 430, text = "perfectly safe" },
            { kind = "pop", x = 820, y = 480, w = 64, trig = R(740, 330, 16, 150), delay = 0.04 },
        },
    },
    -- ---------------------------------------------------------- 14
    {
        name = "FLAT EARTH SOCIETY",
        spawn = { x = 50, y = 440 },
        door = { { x = 880, y = 416 } },
        solids = { F(0, 960), ROOF(36), WALL_L, WALL_R },
        traps = {
            { kind = "crusher", x = 230, w = 92, topY = 36, period = 1.9, phase = 0.00 },
            { kind = "crusher", x = 450, w = 92, topY = 36, period = 1.9, phase = 0.95 },
            { kind = "crusher", x = 640, w = 92, topY = 36, period = 1.9, phase = 0.45 },
            { kind = "crusher", x = 806, w = 100, topY = 36, trig = R(770, 320, 12, 160), slamSpeed = 2100 },
            { kind = "note", x = 340, y = 110, text = "nice and flat here" },
        },
    },
    -- ---------------------------------------------------------- 15
    {
        name = "SAY CHEESE",
        spawn = { x = 55, y = 440 },
        door = { { x = 884, y = 416 } },
        solids = { F(0, 960), ROOF(30), WALL_L, WALL_R },
        traps = {
            { kind = "laser", x = 300, y = 30, len = 418, vertical = true, phase = 0.0 },
            { kind = "laser", x = 480, y = 30, len = 418, vertical = true, phase = 0.5 },
            { kind = "laser", x = 660, y = 30, len = 418, vertical = true, phase = 1.0 },
            { kind = "note", x = 150, y = 430, text = "hold still" },
            { kind = "pop", x = 820, y = 480, w = 64, trig = R(740, 330, 16, 150), delay = 0.04 },
        },
    },
    -- ---------------------------------------------------------- 16
    {
        name = "MIND THE GAP",
        spawn = { x = 55, y = 440 },
        door = { { x = 884, y = 416 } },
        solids = { F(0, 360), F(620, 960), WALL_L, WALL_R },
        traps = {
            { kind = "spikes", x = 360, y = 540, w = 260, dir = "up", size = 44 },
            { kind = "teleport", ax = 300, ay = 432, bx = 648, by = 432, twoWay = false },
            { kind = "note", x = 170, y = 430, text = "step in ->" },
            { kind = "pop", x = 806, y = 480, w = 66, trig = R(720, 330, 16, 150), delay = 0.05 },
        },
    },
    -- ---------------------------------------------------------- 17
    {
        name = "TICK TOCK",
        spawn = { x = 55, y = 440 },
        door = { { x = 884, y = 416 } },
        solids = { F(0, 960), ROOF(30), WALL_L, WALL_R },
        traps = {
            { kind = "pendulum", px = 240, py = 30, len = 400, amp = 0.85, speed = 1.6, phase = 0.0 },
            { kind = "pendulum", px = 470, py = 30, len = 400, amp = 0.85, speed = 1.6, phase = 1.1 },
            { kind = "pendulum", px = 700, py = 30, len = 400, amp = 0.85, speed = 1.6, phase = 2.2 },
            { kind = "note", x = 150, y = 430, text = "mind the swing" },
            { kind = "pop", x = 844, y = 480, w = 58, trig = R(764, 330, 14, 150), delay = 0.04 },
        },
    },
    -- ---------------------------------------------------------- 18
    {
        name = "INCOMING",
        spawn = { x = 55, y = 440 },
        door = { { x = 884, y = 416 } },
        solids = { F(0, 960), WALL_L, WALL_R },
        traps = {
            { kind = "turret", x = 942, y = 430, dir = -1, period = 1.3, speed = 300, phase = 0.0 },
            { kind = "turret", x = 942, y = 388, dir = -1, period = 1.7, speed = 250, phase = 0.6 },
            { kind = "note", x = 150, y = 430, text = "duck! (you can't)" },
            { kind = "pop", x = 300, y = 480, w = 64, period = 1.8, phase = 0, holdOut = 0.7 },
        },
    },
    -- ---------------------------------------------------------- 19
    {
        name = "PRESS TO WIN",
        spawn = { x = 55, y = 440 },
        door = { { x = 884, y = 416 } },
        solids = { F(0, 960), WALL_L, WALL_R },
        traps = {
            { kind = "button", x = 330, y = 470, key = "g" },
            { kind = "gate", rect = R(620, 300, 28, 180), key = "g" },
            { kind = "fakedoor", x = 720, y = 416, label = "this way!" },
            { kind = "pop", x = 812, y = 480, w = 66, trig = R(740, 330, 16, 150), delay = 0.05 },
            { kind = "note", x = 352, y = 440, text = "press to open the gate" },
        },
    },
    -- ---------------------------------------------------------- 20
    {
        name = "ELEVATOR ACTION",
        spawn = { x = 55, y = 440 },
        door = { { x = 884, y = 416 } },
        solids = { F(0, 300), F(660, 960), R(450, 330, 120, 16), WALL_L, WALL_R },
        traps = {
            { kind = "spikes", x = 300, y = 540, w = 360, dir = "up", size = 46 },
            { kind = "mover", rect = R(300, 452, 120, 16), toY = 320, speed = 62, pause = 0.45 },
            { kind = "mover", rect = R(560, 320, 120, 16), toY = 452, speed = 62, pause = 0.45, phase = 0.5 },
            { kind = "note", x = 150, y = 430, text = "going up" },
            { kind = "pop", x = 812, y = 480, w = 64, trig = R(740, 330, 16, 150), delay = 0.05 },
        },
    },
    -- ---------------------------------------------------------- 21
    {
        name = "RUNAWAY BELT",
        spawn = { x = 80, y = 440 },
        door = { { x = 884, y = 416 } },
        solids = { F(0, 960), ROOF(30), WALL_L, WALL_R },
        traps = {
            { kind = "conveyor", rect = R(260, 480, 420, 60), dir = 1, force = 150 },
            { kind = "crusher", x = 360, w = 90, topY = 30, period = 1.7, phase = 0.00 },
            { kind = "crusher", x = 520, w = 90, topY = 30, period = 1.7, phase = 0.85 },
            { kind = "crusher", x = 660, w = 90, topY = 30, period = 1.7, phase = 0.40 },
            { kind = "note", x = 150, y = 430, text = "belt + hammers, fun" },
            { kind = "pop", x = 812, y = 480, w = 64, trig = R(740, 330, 16, 150), delay = 0.04 },
        },
    },
    -- ---------------------------------------------------------- 22
    {
        name = "SPRING FEVER",
        spawn = { x = 60, y = 440 },
        door = { { x = 884, y = 416 } },
        solids = { F(0, 300), F(460, 650), F(790, 960), WALL_L, WALL_R },
        traps = {
            { kind = "spikes", x = 300, y = 540, w = 160, dir = "up", size = 44 },
            { kind = "spikes", x = 650, y = 540, w = 140, dir = "up", size = 44 },
            { kind = "spring", x = 250, y = 480, power = -1080 },
            { kind = "spring", x = 600, y = 480, power = -1080 },
            { kind = "note", x = 150, y = 430, text = "run and bounce ->" },
            { kind = "pop", x = 820, y = 480, w = 64, trig = R(742, 330, 16, 150), delay = 0.05 },
        },
    },
    -- ---------------------------------------------------------- 23
    {
        name = "PEEKABOO",
        spawn = { x = 55, y = 440 },
        door = { { x = 884, y = 416 } },
        solids = { F(0, 260), F(700, 960), WALL_L, WALL_R },
        traps = {
            { kind = "spikes", x = 260, y = 540, w = 440, dir = "up", size = 46 },
            { kind = "blink", rect = R(320, 420, 100, 16), period = 1.6, onFrac = 0.60, phase = 0.0 },
            { kind = "blink", rect = R(540, 420, 100, 16), period = 1.6, onFrac = 0.60, phase = 0.5 },
            { kind = "saw", path = { { x = 480, y = 150 }, { x = 480, y = 360 } }, r = 22, speed = 180 },
            { kind = "note", x = 150, y = 430, text = "time it" },
            { kind = "pop", x = 806, y = 480, w = 66, trig = R(720, 330, 16, 150), delay = 0.05 },
        },
    },
    -- ---------------------------------------------------------- 24
    {
        name = "CROSSFIRE",
        spawn = { x = 55, y = 440 },
        door = { { x = 884, y = 416 } },
        solids = { F(0, 960), ROOF(30), WALL_L, WALL_R },
        traps = {
            { kind = "turret", x = 942, y = 430, dir = -1, period = 1.2, speed = 300 },
            { kind = "laser", x = 430, y = 30, len = 418, vertical = true, period = 2.0, warn = 0.5, fire = 0.45, phase = 0.0 },
            { kind = "laser", x = 620, y = 30, len = 418, vertical = true, period = 2.0, warn = 0.5, fire = 0.45, phase = 0.5 },
            { kind = "note", x = 150, y = 430, text = "crossfire!" },
            { kind = "pop", x = 280, y = 480, w = 64, period = 1.7, phase = 0, holdOut = 0.7 },
        },
    },
    -- ---------------------------------------------------------- 25
    {
        name = "PORTAL HOPPER",
        spawn = { x = 55, y = 440 },
        door = { { x = 884, y = 196 } },
        solids = { F(0, 300), F(640, 960), R(760, 260, 200, 16), WALL_L, WALL_R },
        traps = {
            { kind = "spikes", x = 300, y = 540, w = 340, dir = "up", size = 46 },
            { kind = "mover", rect = R(320, 452, 100, 16), toX = 520, speed = 95, pause = 0.4 },
            { kind = "teleport", ax = 700, ay = 432, bx = 820, by = 222, twoWay = false },
            { kind = "note", x = 150, y = 430, text = "ride, then warp up" },
            { kind = "pop", x = 806, y = 260, w = 60, trig = R(720, 180, 16, 80), delay = 0.05 },
        },
    },
    -- ---------------------------------------------------------- 26
    {
        name = "RHYTHM HELL",
        spawn = { x = 55, y = 440 },
        door = { { x = 884, y = 416 } },
        solids = { F(0, 960), ROOF(30), WALL_L, WALL_R },
        traps = {
            { kind = "pop", x = 240, y = 480, w = 64, period = 1.5, phase = 0.0, holdOut = 0.7 },
            { kind = "pop", x = 360, y = 480, w = 64, period = 1.5, phase = 0.3, holdOut = 0.7 },
            { kind = "pop", x = 480, y = 480, w = 64, period = 1.5, phase = 0.6, holdOut = 0.7 },
            { kind = "laser", x = 600, y = 30, len = 418, vertical = true, period = 1.8, warn = 0.45, fire = 0.4, phase = 0.0 },
            { kind = "laser", x = 720, y = 30, len = 418, vertical = true, period = 1.8, warn = 0.45, fire = 0.4, phase = 0.9 },
            { kind = "note", x = 150, y = 430, text = "feel the beat" },
            { kind = "pop", x = 844, y = 480, w = 58, trig = R(770, 330, 14, 150), delay = 0.04 },
        },
    },
    -- ---------------------------------------------------------- 27
    {
        name = "KITCHEN SINK",
        spawn = { x = 55, y = 440 },
        door = { { x = 884, y = 416 } },
        solids = { F(0, 360), F(540, 960), ROOF(30), WALL_L, WALL_R },
        traps = {
            { kind = "conveyor", rect = R(120, 480, 200, 60), dir = 1, force = 120 },
            { kind = "spikes", x = 360, y = 540, w = 180, dir = "up", size = 44 },
            { kind = "mover", rect = R(360, 452, 100, 16), toX = 450, speed = 80, pause = 0.4 },
            { kind = "saw", path = { { x = 660, y = 150 }, { x = 660, y = 360 } }, r = 20, speed = 170 },
            { kind = "crusher", x = 770, w = 90, topY = 30, period = 1.8, phase = 0.3 },
            { kind = "note", x = 150, y = 430, text = "a bit of everything" },
            { kind = "pop", x = 844, y = 480, w = 58, trig = R(800, 330, 14, 150), delay = 0.04 },
        },
    },
    -- ---------------------------------------------------------- 28
    {
        name = "TRUST NOBODY",
        spawn = { x = 55, y = 440 },
        door = { { x = 884, y = 416 } },
        solids = { F(0, 620), F(770, 960), WALL_L, WALL_R },
        traps = {
            { kind = "fakedoor", x = 300, y = 416, label = "100% real" },
            { kind = "fakedoor", x = 520, y = 416, label = "trust me" },
            { kind = "collapse", rect = R(620, 480, 150, 60), trig = R(560, 300, 30, 180) },
            { kind = "button", x = 700, y = 470, key = "x" },
            { kind = "fallblock", rect = R(820, 40, 70, 42), trig = R(790, 200, 40, 280), shakeTime = 0.05 },
            { kind = "note", x = 150, y = 430, text = "trust nobody" },
        },
    },
    -- ---------------------------------------------------------- 29
    {
        name = "THE OLD GAUNTLET",
        spawn = { x = 45, y = 440 },
        door = { { x = 884, y = 416 }, { x = 70, y = 200 } },
        fleeDist = 70,
        solids = {
            F(0, 230), F(360, 960),
            R(40, 264, 130, 16), R(205, 336, 90, 14), R(330, 410, 80, 14),
            WALL_L, WALL_R,
        },
        traps = {
            { kind = "collapse", rect = R(230, 480, 130, 60), trig = R(170, 280, 24, 200) },
            { kind = "fallblock", rect = R(420, 40, 64, 42), trig = R(400, 200, 104, 280) },
            { kind = "hole", x0 = 500, x1 = 790, gapW = 88, startGap = 740, speed = 135,
              trig = R(470, 300, 20, 180) },
            { kind = "pop", x = 800, y = 480, w = 70, trig = R(750, 330, 20, 150), delay = 0.05 },
            { kind = "pop", x = 218, y = 336, w = 64, trig = R(205, 240, 90, 96), delay = 0.5 },
            { kind = "note", x = 600, y = 430, text = "almost there :)" },
            { kind = "note", x = 105, y = 240, text = "ok fine. you earned it.", size = 13 },
        },
    },
    -- ---------------------------------------------------------- 30
    {
        name = "THE FINAL FABLE",
        spawn = { x = 50, y = 440 },
        door = { { x = 884, y = 416 }, { x = 110, y = 236 } },
        fleeDist = 78,
        solids = {
            F(0, 250), F(700, 960), R(40, 300, 210, 16), ROOF(30),
            WALL_L, WALL_R,
        },
        traps = {
            { kind = "spring", x = 150, y = 480, power = -1000 },
            { kind = "mover", rect = R(280, 452, 100, 16), toX = 560, speed = 100, pause = 0.35 },
            { kind = "saw", path = { { x = 470, y = 150 }, { x = 470, y = 430 } }, r = 22, speed = 190 },
            { kind = "laser", x = 610, y = 30, len = 418, vertical = true, period = 1.9, warn = 0.45, fire = 0.4 },
            { kind = "pop", x = 806, y = 480, w = 66, trig = R(720, 330, 16, 150), delay = 0.05 },
            { kind = "spikes", x = 250, y = 540, w = 450, dir = "up", size = 44 },
            { kind = "note", x = 150, y = 250, text = "the devil's last laugh" },
        },
    },
}

-- ================================================================
-- 十三、查表
-- ================================================================
function M.levelCount()
    return #M.LEVELS
end

function M.getLevel(n)
    n = math.floor(tonumber(n) or 0)
    if n < 1 or n > #M.LEVELS then return nil end
    return M.LEVELS[n]
end

function M.comicPanels()
    return (M.COMIC and M.COMIC.panels) or {}
end

function M.roastFor(deaths)
    local d = tonumber(deaths) or 0
    for i = 1, #M.ROASTS do
        local r = M.ROASTS[i]
        if d <= r[1] then return r[2] end
    end
    return M.ROASTS[#M.ROASTS][2]
end

return M
