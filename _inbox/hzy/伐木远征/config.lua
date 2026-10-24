-- ================================================================
-- 伐木远征 · 配置真源
--   ★ 本文件的 DEFAULT_* 是唯一真源：state / render / ui 只读不写死。
--   ★ 千星元件索引（官方内置模板，任何存档都有）→ 统一放在 M.PREFAB 里按用途索引：
--       1073741876  容器节点（不绘制、不需图源，用来分层）
--       1073741894  图片 · 矩形（自带矩形图元 → 所有纯色块的构建基础）
--       1073741870  图片（无图源时真机会画彩色「?」，只作回退 / 立绘直出）
--       1073741868  文本框（字色字段是 fontColor）
--   ★ 图元（SetImage 的 StaticReference 编号）→ M.PRIM：
--       100001 矩形 / 100002 圆 / 100003 三角 …
-- ================================================================

---@diagnostic disable: undefined-global

local M = {}

-- ---------------- 元件索引（官方内置模板，任何存档都有） ----------------
M.DEFAULT_PREFAB_CONTAINER = 1073741876
M.DEFAULT_PREFAB_RECT = 1073741894
M.DEFAULT_PREFAB_IMAGE = 1073741870
M.DEFAULT_PREFAB_TEXT = 1073741868

-- ★★ 「挂靠控件」的唯一入口 ★★
-- 脚本里每造一个控件都按**用途**来这里取索引（utils.instantiate(kind)），
-- **不读脚本参数、不做「拿不到就换一个」的猜测** —— 真机没填的数字参数返回 0，
-- 靠参数挑元件正是第 10 批「小人变橙色块」的成因。
M.PREFAB = {
    container = M.DEFAULT_PREFAB_CONTAINER,   -- 容器节点：只分层，不绘制、不需图源
    rect      = M.DEFAULT_PREFAB_RECT,        -- 图片·矩形：纯色块的基础（自带矩形图元）
    image     = M.DEFAULT_PREFAB_IMAGE,       -- 图片：立绘直出 / 矩形元件拿不到时的兜底
    text      = M.DEFAULT_PREFAB_TEXT,        -- 文本框：字色字段是 fontColor
}

-- ---------------- 图元编号（SetImage 的 StaticReference） ----------------
M.PRIM_RECT = 100001
M.PRIM_CIRCLE = 100002
M.PRIM_TRIANGLE = 100003

M.PRIM = {
    rect     = M.PRIM_RECT,
    circle   = M.PRIM_CIRCLE,
    triangle = M.PRIM_TRIANGLE,
}

-- ---------------- 画布与格子 ----------------
M.DEFAULT_VIEW_WIDTH = 1280
M.DEFAULT_VIEW_HEIGHT = 720

-- 一格边长（像素）。原版网页是 44~58，这里按 1280×720 取 64：
-- 屏幕横向约 20 格、纵向约 11 格，和原版计算器 12×8 的手感接近。
M.DEFAULT_TILE = 64
-- 每 1 点高度在屏幕上抬高多少像素（原版 HZ/T = 8/58 ≈ 0.138）
M.DEFAULT_HEIGHT_PX = 9
-- 崖面最多拉多高（格数）。80 点的落差只画这么厚，避免糊掉半屏
M.DEFAULT_CLIFF_MAX = 2.1
-- 地图外圈多铺几格，避免镜头边缘露白
M.DEFAULT_WIN_MARGIN = 2
-- 上方多算几行：北边那格的高崖面会垂进可视区
M.DEFAULT_WIN_TOP_PAD = 3

-- 放大倍数（1 = 上面这个格子尺寸）
M.DEFAULT_VIEW_ZOOM = 1

-- ---------------- 节奏 ----------------
-- 连锁动作每帧推进的秒数（木筏一格一格漂就是靠它）
M.DEFAULT_STEP_TIME = 0.085
-- 屏幕实体平滑跟随速度（每帧向目标位置靠拢的比例，按 30fps 标定）
M.DEFAULT_SMOOTH = 0.55
-- 镜头跟随速度
M.DEFAULT_CAM_SMOOTH = 0.30
-- 撤销栈上限
M.DEFAULT_UNDO_MAX = 300

-- ---------------- 主题配色（逐项取自原版 render.js 的 THEMES）----------------
M.THEMES = {
    meadow = {
        water = "2C7C8D", waterVar = "3F95A5", edge = "3F6A30", beach = "CBB782",
        low = "5D9A41", mid = "87BD53", high = "C8DD92",
        wall = "6D6455", wallTop = "8A8171",
    },
    lake = {
        water = "2F8BA1", waterVar = "4AA9BD", edge = "3B6C31", beach = "D6C692",
        low = "579A43", mid = "84BF63", high = "D2E5A4",
        wall = "6E6656", wallTop = "8B8373",
    },
    sand = {
        water = "26A0B8", waterVar = "54C4D8", edge = "A8915C", beach = "F2E2B6",
        low = "D4BA7E", mid = "E8D6A4", high = "F9F0DA",
        wall = "9C8F70", wallTop = "B8AB8A",
    },
    snow = {
        water = "2F7691", waterVar = "4A9CB5", edge = "5A6672", beach = "DFE8F0", snow = true,
        low = "68805C", mid = "8B95A2", high = "F8FCFF",
        wall = "5C6670", wallTop = "77828D",
    },
}
M.DEFAULT_THEME = "meadow"

-- ---------------- 物件配色（所有主题共用）----------------
M.OBJ = {
    wood = "AD7441", woodDark = "7B4E28", woodLight = "CB945E",
    leaf = "3F8A45", leafDark = "2B6234", leafLight = "6DBA60",
    body = "F8ECCA", bodyDark = "DEC396", eye = "25292D",
    rope = "574026", stone = "9AA0A6", stoneDark = "6C737B",
    snow = "FBFDFF", snowShade = "D3E0EC", gold = "E8C15A",
    -- ★ 物件落地投影：原版 render.js 的 _shadow() 就是 rgba(10,25,30,a)，
    --   漏了这条会让 slot() 拿不到颜色 → 真机默认白 → 每个物件脚下顶一坨白斑。
    shadow = "0A191E",
}

-- ---------------- 界面配色 ----------------
M.PALETTE = {
    hudBar = "0E1A1F",
    hud = "F2F5F6",
    hudDim = "9FB2B8",
    panel = "16262C",
    panelEdge = "2E4A54",
    accent = "E8C15A",
    title = "F7FAFB",
    sub = "A9C0C7",
    done = "8FD08A",
    shadow = "0A191E",
}
M.DEFAULT_HUD_ALPHA = 190
M.DEFAULT_HUD_TITLE_SIZE = 26
M.DEFAULT_HUD_INFO_SIZE = 20
M.DEFAULT_DIALOG_SIZE = 24
M.DEFAULT_MENU_TITLE_SIZE = 54

-- ================================================================
-- ★ 地图元信息（区顺序 = 原版发行包由内向外解压的顺序）
--   blurb 是选关卡片上的一句话简介
-- ================================================================
M.REGIONS = {
    { key = "islands",   theme = "sand",   cn = "沙洲群岛", en = "Sandbank Islands", blurb = "起点。先读懂操作，再学会在沙洲之间搭筏。" },
    { key = "foothills", theme = "meadow", cn = "草地丘陵", en = "Grass Hills",      blurb = "推木、滚木，学会分辨高度与被推的力度。" },
    { key = "lake",      theme = "lake",   cn = "花之湖",   en = "Flower Lake",      blurb = "水比陆地还多，木头要拿来拼桥、拼筏。" },
    { key = "cliffs",    theme = "snow",   cn = "雪之尖塔", en = "Snow Spire",       blurb = "一路向上，山顶就是终点。" },
}
M.DIGRESSIONS = {
    { key = "log-maze",        parent = "islands",  theme = "sand",   cn = "圆木迷宫" },
    { key = "raft-ejection",   parent = "islands",  theme = "meadow", cn = "木筏弹射" },
    { key = "the-rescue",      parent = "foothills", theme = "sand",   cn = "援救木筏" },
    { key = "obscured-mirror", parent = "foothills", theme = "snow",   cn = "朦胧之镜" },
    { key = "icy-lake",        parent = "lake",     theme = "snow",   cn = "冰池" },
    { key = "caustic-bluff",   parent = "lake",     theme = "sand",   cn = "碱滩" },
    { key = "big-scalar",      parent = "cliffs",   theme = "meadow", cn = "大数字" },
    { key = "whimsy-raft",     parent = "cliffs",   theme = "lake",   cn = "奇想木筏" },
}

-- ================================================================
-- ★ 木牌文案（英文原文在 mexp_maps.lua 的 strings 里；这里是人工译文）
--   ★ 计算器键名换成了键盘键名
-- ================================================================
M.TEXTS = {
    foothills = {
        { "欢迎来到", "草地丘陵！" },
        { "恭喜你！", "你走完了草地丘陵！", "锁住文件夹的密码：", "JLSE17KA88" },
        { "关于高度的说明：", "想知道一个台子有多高，就从底往上数横杠。", "每根木头、木筏、树桩都算一个高度；立着的木头算两个高度。" },
        { "雪人递给你一张纸条：", "秘密 1", "M8D51ENVT9" },
        { "雪人递给你一张纸条：", "秘密 2", "6MXZDZ1RA5" },
        { "雪人一动不动地站着，好像在给你当模特拍照！" },
    },
    lake = {
        { "欢迎来到", "花之湖！" },
        { "恭喜你！", "你走完了花之湖！", "锁住文件夹的密码：", "HQ3XHQVFFE" },
        { "雪人递给你一张纸条：", "秘密 1", "T17ZLDCDKF" },
        { "雪人递给你一张纸条：", "秘密 2", "72P3QUG6F3" },
        { "雪人开口了：", "「哦嗨！没想到还会有客人。是什么风把你顺流吹到这儿来的？」" },
    },
    islands = {
        { "欢迎来到", "沙洲群岛！" },
        { "方向键 / WASD：移动", "Z：撤销　R：重置", "Esc：退出到地图" },
        { "如果卡住了，可以用 + / - 前后跳关。", "这些「作弊键」永远不会是解开任何谜题的必要条件！" },
        { "恭喜你！", "你走完了沙洲群岛！", "锁住文件夹的密码：", "P8WJLT8AYD" },
        { "雪人递给你一张纸条：", "秘密 1", "YCLRP3UDZS" },
        { "雪人递给你一张纸条：", "秘密 2", "XQQPKK53NT" },
    },
    cliffs = {
        { "欢迎来到", "雪之尖塔！" },
        { "恭喜你！", "你走完了雪之尖塔！", "你爬到了山顶。", "你赢了！", "锁住文件夹的密码：", "T6FHB1SEDW" },
        { "雪人递给你一张纸条：", "秘密 1", "PGC1VUTUBW" },
        { "雪人递给你一张纸条：", "秘密 2", "35Z7VEPZXE" },
    },
}
-- 番外：{ 说明, 碎片码 }
M.DIGRESSION_TEXT = {
    ["log-maze"] = { "圆木迷宫", "CC5Y" },
    ["raft-ejection"] = { "木筏弹射", "58LQ" },
    ["the-rescue"] = { "援救木筏", "LZQ3" },
    ["icy-lake"] = { "冰池", "WDE5" },
    ["obscured-mirror"] = { "朦胧之镜", "5LDM" },
    ["caustic-bluff"] = { "碱滩", "FA5Y" },
    ["big-scalar"] = { "大数字", "SFTB" },
    ["whimsy-raft"] = { "奇想木筏", "HXQR" },
}

return M
