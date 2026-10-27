-- ================================================================
-- 浮岛借木 · 关卡视觉层
--   把 world 的网格状态画成千星图片控件：
--     ① 地形层（海面 → 水面网格线 → 岛缘投影/侧面厚度/沙滩描边 → 草地顶面）
--     ② 物体层（树根 → 倒下的树 → 石头 → 树木 → 终点旗）
--     ③ 小人层（立绘 或 身体 + 头）
--     ④ 特效层（动作涟漪）
--
--   ★★ 2.5D 视角（本文件的核心，照参考图那种「斜俯视」）
--     参考图的两个特征：
--       ① 水面网格是**屏幕水平 / 垂直**的细线 → 格子不做等距菱形旋转，仍是正交网格；
--       ② 每块地有**厚度**：草地顶面 + 一圈岛缘沙滩描边 + 侧面（土）。
--     立体感完全由「绘制顺序」给出来，而不是靠投影数学：
--       · 描边与侧面按「同层分批画」——先铺满所有描边，再盖所有顶面，
--         于是描边只露在岛的外缘，岛内相邻格之间不会出现一条条缝；
--       · **行号越大 = 越靠近镜头 = 越晚绘制**，于是近处一行的顶面天然盖住
--         远处一行露出来的侧面 —— 这就是「厚度」能看见的原因；
--       · 因此地形 / 物体 / 小人必须混在**同一个容器**里，用深度键统一排序。
--
--     深度键（见 restackWorld）：
--       0xxx 水面网格线 → 1xxx 地块装饰（投影 / 侧面 / 描边）→ 2xxx 草地顶面
--       → 3xxx 物体与小人（同格内：树根 < 倒下的树 < 石头 < 树木 < 旗 < 小人）
--     每一段都用 `行号 × 10 + 层内次序`，行号是主序。
--
--   ★ 视觉槽位（素材优先、失败当场回退）
--     每一类可视对象都先问一句「有没有专用美术素材元件」（海水/草地/树木/人物）：
--       有  → 用它，并且**绝不写 imageColor** —— 一写就把素材乘上去了（变暗、串色）
--       没有 → 退回通用矩形元件 + 调色板染色（= 加入素材之前的画面）
--     素材是 1024×1024 但内容只占中间一块，所以控件要按 config.DEFAULT_ART_FIT
--     放大，才能让「内容」严丝合缝压住格子。
--
--   所有控件都走「对象池」：一次创建、反复复用，只改位置/尺寸/显隐/颜色，
--   不在关卡切换与每次动作时反复创建销毁。
-- ================================================================

---@diagnostic disable: undefined-global

local M = {}
local state = require("state")
local config = require("config")
local utils = require("utils")
local world = require("world")

M.BUILD = "b44"   -- 版本戳：真机日志里能一眼看出用的是哪一版文件
                  --   b44 = 第 44 批：柱子遮挡改成**纯矩形相交**（小人 / 树 / 倒木 / 木筏都算遮挡物）
                  --   b43 = 第 43 批：柱子只在「同列且真的盖得住小人」时才进前层 —— 走位不再改变柱子外观
                  --   b42 = 第 42 批：石柱保真度重做（330 笔/根）+ 柱子挡角色（石头拆前后两层）
                  --   b41 = 第 41 批：石柱边缘磨平（竖条层定轮廓 + 细节笔裁进轮廓）
                  --   b40 = 第 40 批：石头换成「图腾柱」（rockPrims.lua 的图元逐笔画）
                  --   b39 = 第 39 批：侧视远臂钉在躯干上（撤掉第 38 批的飘带判定）+ 步时/转身略快

-- ★ 石头用的「图腾柱」图元数据（第 40 批）
--   用户导出的「超限素材组」脚本 1043 个旋转图元 → 归一到「高 = 1」+ 覆盖率贪心精简。
--   第 41 批起最前面还有一段**竖条层**（M.SIL_N 条）：它按「每行左右边界」铺出柱子的
--   外轮廓，边缘永远是直的 —— 细节笔都被裁到轮廓往里 1 格，不会再把角伸出去。
--   所以 BASE 的前 SIL_N 笔必须在最底下先画，别打乱顺序。
--   第 42 批把「底色 → 细节」这四段全部改成**误差贪心**（见 rockPrims.lua 头注），
--   总笔数 154 → 330 笔/根（底色 BASE 205 + 辉光 GLOW 125）。
--   ★ 没有这个模块就自动退回旧石块（两块纯色矩形），**不会白屏**；
--     真机若看到石头还是老样子，先看自检日志里的「石头=」那一段。
--   ⚠️ 新加的 .lua 必须先在「客户端脚本资源管理器」里建好映射才会被打包 ——
--     没建映射时 require 会失败，画面就退回旧石块（这也是本条用 pcall 的原因）。
local rockPrims = nil
do
    local ok, mod = pcall(require, "rockPrims")
    if ok and type(mod) == "table" and type(mod.BASE) == "table" and type(mod.GLOW) == "table" then
        rockPrims = mod
    end
end
M.ROCK_PRIMS_LOADED = (rockPrims ~= nil)

-- ★ 小人「图元笔触」数据（第 16 批）：来自「图元拟合拼图」四视角脚本，
--   已按游戏内 68px 尺度裁掉看不见的椭圆。没有这个模块就自动退回像素画/立绘。
local heroPrims = nil
do
    local ok, mod = pcall(require, "heroPrims")
    if ok and type(mod) == "table" and type(mod.S) == "table" then
        heroPrims = mod
    end
end
M.HERO_PRIMS_LOADED = (heroPrims ~= nil)

-- ★ 小人像素画数据（由 _tools/make_hero_pixels.py 从四张立绘生成）
--   ★ 这里只是「可选覆盖」：真正保底的是文件下方内联的 M.HERO_BUILTIN。
--     早期版本强依赖这个 require，真机上只要 heroArt.lua 没建 / 名字不对 / 编译失败，
--     小人就整个退回立绘，立绘元件也拿不到时再退回橙色纯色条 —— 正好是「橙色方块」。
--     现在改成：heroArt 有就用它（数据更精细），没有就用内置数据，**永远画得出像素画**。
local heroArt = nil
do
    local ok, mod = pcall(require, "heroArt")
    if ok and type(mod) == "table" and type(mod.SPRITES) == "table" then
        heroArt = mod
    end
end

M.HERO_ART_LOADED = (heroArt ~= nil)   -- 供 game.lua 打版本日志；false 也完全不影响画面

-- >>> HERO_BUILTIN BEGIN（由 _tools/emit_hero_builtin.py 生成，别手改）
-- 小人的像素画底稿：heroArt.lua 没导入时用它，保证「不引用任何脚本/图片」也能画出小人。
-- 每格一个字符（0123456789abcd），"." = 透明；行内连续同色在运行时合并成一块矩形。
M.HERO_BUILTIN_COLS = 20
M.HERO_BUILTIN_ROWS = 32
M.HERO_BUILTIN_CHARS = "0123456789abcd"
M.HERO_BUILTIN_COLORS = {
    "585D74",     -- 0
    "5779B7",     -- 1
    "7091C0",     -- 2
    "86A3C5",     -- 3
    "73B5DB",     -- 4
    "AAB4C4",     -- 5
    "A0C4DC",     -- 6
    "BEC5D4",     -- 7
    "CED4E0",     -- 8
    "DDD3D1",     -- 9
    "F2D8C4",     -- 10
    "DCE0E8",     -- 11
    "EFDFDA",     -- 12
    "EFF2F7",     -- 13
}
M.HERO_BUILTIN = {
    S = {   -- 152 块
        "....................",
        ".........44.........",
        "......4.4444........",
        "......41111114......",
        "....41111111114.....",
        "....41188888811.....",
        "...511888888881.....",
        "...1188888888888....",
        "..55188888888888....",
        "..55888888888888....",
        "..558888888888888...",
        "..558888c88888888...",
        ".555888c008800888...",
        ".55c888022cc22088...",
        ".555888c6ccccc885...",
        "..55888ccccccc885...",
        "...55888522cc588....",
        ".......8c22c........",
        "......2d22222.......",
        "......111dd411......",
        ".....31122b811......",
        "....3dd022822dd.....",
        "...33dd222dd22d3....",
        "..33ccd226dd6223....",
        "..3336646dddd6433...",
        "..336666dddddd663...",
        ".33.bbdddddddddb33..",
        "...bbbddccdd5ddbb...",
        "..bbbdddcc5555dbbb..",
        ".bbbb77588555577bbb.",
        "bbbbbb55cc5c555bbbbb",
        "........33.4........",
    },
    W = {   -- 103 块
        "....................",
        ".........44.........",
        "......4.4444........",
        "......41114114......",
        "....45111111114.....",
        "....41188888811.....",
        "....118888888811....",
        "....188888888881....",
        "....888888888888....",
        "....888888888888....",
        "....888888888888....",
        "...8888888888888....",
        "...88888888888888...",
        "..cc8888888888888...",
        "....8888888888888...",
        "....888888888888....",
        ".....88888888888....",
        ".......cc11c........",
        ".......dccccd.......",
        "......11222211......",
        "......11222211......",
        ".....dd622226dd.....",
        "....cdd222222ddc....",
        "....cc6222d2266c....",
        "....6666dddd6666....",
        "...6666ddddddd666...",
        "...6bbddddddddd86...",
        "...bbbdddddd5dd8b...",
        "..bbbdddccdc55dbbb..",
        ".bbbbd7588585577bbb.",
        "bbbbbb55cccc555bbbbb",
        "........33.3........",
    },
    A = {   -- 101 块
        "....................",
        ".......4............",
        "......44............",
        "......41148.........",
        "......1114888.......",
        ".....888111888......",
        "....88888118888.....",
        "...8888881188888....",
        "...8888888888888....",
        "...8888888888888....",
        "...8888888888888....",
        "...8800888888888....",
        "....823088cc88888...",
        "....cccc88cc88888...",
        ".....cc8888888888...",
        "......c888488888....",
        ".......821..77......",
        ".......22cd.777.....",
        "......42211.777.....",
        ".......2211.777.....",
        ".......22dd.777.....",
        "......422ddd.777....",
        "......d22ddd.777....",
        ".....6d624c66777....",
        ".....ddd666666777...",
        ".....dddd66666677...",
        ".....dddddbbbbb.7...",
        ".....555dddbbbbb....",
        "......55dddbbbbb....",
        "......55887bbbbbb...",
        ".......5c35bbbbbbbb.",
        ".......333...bbbbbb.",
    },
    D = {   -- 111 块
        "....................",
        "..........44........",
        "..........44........",
        ".......55414........",
        "......5511118.......",
        ".....554118888......",
        "....55511188888.....",
        "...5555118888888....",
        "...5555518888888....",
        "...5555588888888....",
        "...5555588888888....",
        "...5555588888888....",
        "..55555588880088....",
        "..55555c888802c.....",
        "..5555558888ccc.....",
        "...555555888ccc.....",
        ".....55558188.......",
        ".........c11........",
        "........3b222.......",
        ".......3111b4.......",
        "......3311128.......",
        ".....333dd222.......",
        "....3332dd2224......",
        "....3332cc22dd......",
        "...333366246dd......",
        "...33366666dddd.....",
        "..33.bb68dddddd.....",
        "....bbb88ddd55......",
        "...bbbb8dddc55......",
        "..bbbbb8dd8855......",
        ".bbbb88bb5cc55......",
        "..bbb88...333.......",
    },
}
-- <<< HERO_BUILTIN END

-- ================================================================
-- ★ 像素画数据源：heroArt 模块（若有）→ 内置网格
--   返回 sprites, colors, cols, rows；都拿不到才返回 nil。
--   内置网格是「每格一个字符」，这里按行做游程合并还原成矩形，
--   块数与 heroArt 的贪心合并基本持平（同色相邻格子并成一块）。
-- ================================================================
local HERO_FALLBACK = {}
local function heroBuiltinRects(key)
    if HERO_FALLBACK[key] then return HERO_FALLBACK[key] end
    local rowsSrc = (M.HERO_BUILTIN or {})[key]
    if not rowsSrc then return nil end
    local chars = M.HERO_BUILTIN_CHARS or "0123456789abc"
    local out = {}
    for y = 1, #rowsSrc do
        local line = rowsSrc[y]
        local x = 0
        local n = #line
        while x < n do
            local ch = line:sub(x + 1, x + 1)
            if ch == "." then
                x = x + 1
            else
                local j = x
                while j < n and line:sub(j + 1, j + 1) == ch do j = j + 1 end
                local ci = chars:find(ch, 1, true)
                out[#out + 1] = { x, y - 1, j - x, 1, (ci or 1) - 1 }
                x = j
            end
        end
    end
    HERO_FALLBACK[key] = out
    return out
end

-- 数据源备注（写进自检日志，一眼看出走的是哪一份）
local heroDataFrom = ""
local function heroSprite(key)
    key = key or "S"
    if heroArt then
        local sprites = heroArt.SPRITES or {}
        local sp = sprites[key] or sprites.S
        if sp and #sp > 0 then
            heroDataFrom = "heroArt 模块"
            return sp, heroArt.COLORS or {}, tonumber(heroArt.COLS) or 20, tonumber(heroArt.ROWS) or 32
        end
    end
    local sp = heroBuiltinRects(key) or heroBuiltinRects("S")
    if sp and #sp > 0 then
        heroDataFrom = "level.lua 内置"
        return sp, M.HERO_BUILTIN_COLORS or {}, M.HERO_BUILTIN_COLS or 20, M.HERO_BUILTIN_ROWS or 32
    end
    heroDataFrom = ""
    return nil
end

-- ================================================================
-- ★ 小人图元笔触数据（第 16 批）
--   每个视角一张平表，每 7 个数一个椭圆：x, y, w, h, rot, rgb, alpha
--   x,y 相对「脚底线中点」，单位 = 1 格；w,h 也是格；rot 是度。
--   ★ 缺的朝向自动回退正面（和立绘那条路一致：只给一套也能跑）。
-- ================================================================
local function heroPrData(key)
    if not heroPrims then return nil end
    local d = heroPrims[key or "S"] or heroPrims.S
    -- 第 17 批起格式为「6 个部件」：{ {px,py,n,...}, ... }
    if type(d) ~= "table" or #d < 2 then return nil end
    return d
end

-- ★ 小人纯色回退的身高（格）：素材那条路的高度由 config.DEFAULT_ART_FIT.player 说了算，
--   这里只管「没有素材时」画多高。
--   ⚠️ 必须声明在文件顶部：下面的 playerFootOffset / playerAnchor 就要用它们。
--      Lua 的 local 从**声明行**起才可见 —— 放到底部会让这几处静默读到 nil 全局。
local PLAYER_BODY_RATIO = 0.94    -- 身体矩形就是「小人全身」的高度
local PLAYER_HEAD_RATIO = 0.26    -- 头（一块深色块，压在身体上部，不是叠在上面）

-- ================================================================
-- ★ 木头「躺 / 立」两态的形状常量（同一根木头，两个状态）
--   这是「表现力」的基准：两态必须在**剪影**上就分开，否则玩家只会觉得
--   「东西转了个方向」，读不出「它倒了 / 它立起来了」。
--     躺：长而扁 —— 1.00 × 0.50 格（横向张力，像一根横梁）
--     立：窄而高 —— 0.36 × 1.00 格（竖向张力，像一截立柱）
--   ⚠️ 高度刻意与玩法高度对齐（躺 = H_LOG_LAND 0.5 / 立 = H_TREE 1.0）：
--     视觉高度 = 可读高度，玩家才不会误判「这个能不能踩」。
--   ⚠️ 三处同源：本文件 ↔ 编辑器.html 的 draw() ↔ _tools/preview_art_浮岛借木.py。
--     改这里的数字，另外两处要一起改，否则它们会「说假话」。
-- ================================================================
local LOG_THICK   = 0.50   -- 躺着的木头 · 厚度（格）
local LOG_LEN     = 1.00   -- 躺着的木头 · 长度（格）
local LOG_CAP     = 0.09   -- 躺着的木头 · 两端切口的厚度（格）
local TRUNK_W     = 0.36   -- 立着的木头 · 宽度（格）
local TRUNK_H     = 1.00   -- 立着的木头 · 高度（格）
local TRUNK_CAP   = 0.16   -- 立着的木头 · 顶端切面的厚度（格）
local TRUNK_FOOT  = 0.40   -- 立着的木头 · 根部土堆的宽度（格）

-- ================================================================
-- ★ 格子 → UI 坐标（正交网格，不做菱形投影）
--   UI 坐标原点在画布中心，Y 向上为正；row 1 在最上，row 越大越靠下 = 越靠近镜头。
-- ================================================================
local function cellCenterX(c)
    local cols = state.mapCols or 1
    return (state.boardCx or 0) + (c - (cols + 1) / 2) * (state.cellSize or 1)
end

local function cellCenterY(r)
    local rows = state.mapRows or 1
    return (state.boardCy or 0) - (r - (rows + 1) / 2) * (state.cellSize or 1)
end

-- ★ 物体的「脚线」：站立物（树 / 树干 / 石头 / 小人）踩在顶面**靠前**的位置，
--   而不是格子正中心 —— 这一点偏移就是「站在方块上面」的错觉来源。
local function cellFootY(r)
    return cellCenterY(r) - (state.cellSize or 1) * (config.DEFAULT_TILE_FOOT_RATIO or 0.18)
end

-- 素材模式下，控件中心相对「它踩的那条脚线」要抬高多少像素
--   （素材内容只占画布中间一块，脚本按 config.DEFAULT_ART_FIT.dy 补偿）
local function artFootOffset(kind)
    local fit = (config.DEFAULT_ART_FIT or {})[kind]
    local dy = (fit and fit.dy) or 0
    return dy * (state.cellSize or 1)
end

-- 小人身体当前形态的「中心 → 脚下」距离
--   ★ 像素画模式下 = 0：画布的底边本身就压着脚线，playerVisY 直接就是脚底高度。
--   ★ 图片立绘 = 半格：控件是「1 格高 × 0.62 格宽」、pivot 在中心，
--     中心离底边正好半格 —— 返回半格，playerAnchor 就直接给出控件中心。
local function playerFootOffset()
    if state.heroPr then return 0 end        -- 图元笔触：容器底边本身压着脚线
    if state.heroPixel then return 0 end
    if state.playerCtrlImg then return (state.cellSize or 1) * 0.5 end
    if state.playerCtrlArt then
        return artFootOffset("player")
    end
    local cell = state.cellSize or 1
    local bodyH = state.playerBodyH
    if not bodyH or bodyH <= 0 then
        bodyH = cell * PLAYER_BODY_RATIO
    end
    return bodyH / 2
end

-- 小人身体中心：站在高度 h（格）之上
local function playerAnchor()
    local p = state.player
    local cell = state.cellSize or 1
    local foot = cellFootY(p.r) + (p.h or 0) * cell
    return cellCenterX(p.c), foot + playerFootOffset()
end

-- ================================================================
-- ★ 几何：按画布与地图尺寸算出格子边长与棋盘中心
--   2.5D 下格子之外还多出「岛缘描边 + 侧面厚度」，一并计入可用区域，
--   否则最上 / 最下 / 最左 / 最右会被画到画布外面去。
--
--   ★ 两步走（这是「放大一倍 + 镜头跟随」的全部机关）：
--     ① 先按「整张地图塞满一屏」求一个基准边长 base（zoom = 1 时就是它）；
--     ② base × state.viewZoom 才是真正用的 cell。
--   乘上去之后地图很可能比屏幕大 —— 那不要紧，超出的部分由镜头平移补
--   （见 applyCamera / updateCamera）。
-- ================================================================
function M.computeGeometry()
    local cw = state.canvasW or config.DEFAULT_VIEW_WIDTH
    local ch = state.canvasH or config.DEFAULT_VIEW_HEIGHT
    local barH = config.DEFAULT_HUD_BAR_HEIGHT or 74
    local reserve = config.DEFAULT_HUD_BOTTOM_RESERVE or 88
    local marginX = config.DEFAULT_BOARD_MARGIN_X or 40
    local scale = config.DEFAULT_BOARD_SCALE or 0.9

    local cols = math.max(1, state.mapCols or 1)
    local rows = math.max(1, state.mapRows or 1)

    -- ① 画法决定「格子的外扩量」
    local rimRatio, sideRatio, padPx = 0, 0, 0
    if state.view25d then
        rimRatio = config.DEFAULT_TILE_RIM_RATIO or 0.17    -- 单位：格
        sideRatio = config.DEFAULT_TILE_SIDE_RATIO or 0.30  -- 单位：格
    else
        padPx = 2 * (config.DEFAULT_COAST_PAD or 5)         -- 旧画法：描边是固定像素
    end

    -- ② 求「整图一屏」的基准边长：横竖各解一遍，取小的
    local spanX = cols + 2 * rimRatio
    local spanY = rows + 2 * rimRatio + sideRatio
    local availW = (cw - marginX * 2) * scale - padPx
    local availH = (ch - barH - reserve) * scale - padPx
    local base = math.floor(math.min(availW / spanX, availH / spanY))
    base = utils.clamp(base, config.DEFAULT_CELL_MIN or 22, config.DEFAULT_CELL_MAX or 64)

    -- ③ 放大：cell = base × zoom
    --   ★ 上限单独一条（DEFAULT_CELL_MAX_ZOOM）：不能复用 base 的 64 ——
    --     否则「64 × 2」会被同一个 clamp 压回 64，放大完全失效。
    local zoom = tonumber(state.viewZoom) or 1
    if zoom <= 0 then zoom = 1 end
    local cell = math.floor(base * zoom + 0.5)
    cell = utils.clamp(cell, config.DEFAULT_CELL_MIN or 22,
                       config.DEFAULT_CELL_MAX_ZOOM or 176)

    state.cellSize = cell
    state.boardW = cols * cell
    state.boardH = rows * cell
    state.boardCx = 0
    -- 在「HUD 下沿」与「消息栏上沿」之间竖直居中。
    -- 2.5D 下棋盘的可视范围是「上方多一圈描边、下方多一圈描边 + 侧面厚度」，
    -- 所以把棋盘中心再往上抬 side/2，让多出来的那块不至于压到底部消息栏。
    local bandCy = ((ch / 2 - barH) + (-ch / 2 + reserve)) / 2
    state.boardCy = bandCy + sideRatio * cell / 2

    -- ④ 镜头要用到的两个量
    --   viewCenterY：可视区的正中心（小人就钉在这个高度）
    --   worldPxW/H：整张地图占多少像素（含外扩；用来判断「一屏到底放不放得下」）
    state.viewCenterY = bandCy
    state.worldPxW = spanX * cell + padPx
    state.worldPxH = spanY * cell + padPx
    return cell
end

-- ================================================================
-- ★ 镜头：放大后的「视野平移」
--   放大 2 倍后地图 22×13 格 = 1584×936 px，一屏（1280×720，还要扣 HUD）
--   装不下 —— 于是把**整个世界容器整体平移**，平移量正好等于小人的位移量：
--
--       世界容器位置 = -小人世界坐标 + 可视中心
--
--   于是「小人屏幕位置 + 容器偏移 = 固定值」→ 小人永远钉在屏幕中央，
--   动的是地图本身。这正是「镜头跟着角色走」的常见做法。
--
--   ★ 为什么平移容器而不是重算每个控件的坐标：
--     地形 + 物体 + 小人加起来几百个控件，逐帧重算 = 几百次 SetAnchoredPosition；
--     平移容器只有 2 次（world + fx），和小人补间同一帧完成，稳。
--     前提是「世界坐标 = 容器的子节点坐标」—— 容器的 anchoredPosition 原本是 (0,0)，
--     子控件又都是 anchor 0.5 / pivot 0.5，所以这条等式成立。
--   ★ 为什么 fx 容器也要跟着动：涟漪 / 扬尘用的是同一套世界坐标，
--     只动 world 会让特效留在原地（小人脚下踩空）。
--   ★ bg（整屏海面）与 hud **不能动**：一个要铺满屏，一个要固定在界面层。
-- ================================================================
-- ================================================================
-- ★ 当前所在岛的「视觉中心」（世界坐标）
--   第 24 批：镜头不再钉住小人，而是钉在**玩家脚下这座岛的中心** ——
--   在岛内走动时画面纹丝不动（看的是一座岛，不是一个角色），
--   只有换岛（走木筏 / 跨桥过去）才整体平移一次。
--   ★ 岛号 = imap 的值（和 resetIsland 同一套编号），bbox 由 world.islandBox 缓存。
--   ★ 站在水上 / 木筏上（岛号 0）返回 nil —— 调用方回退成「跟着小人」。
-- ================================================================
local function islandAnchor()
    local d = world.playerIsland()
    if not d or d <= 0 then return nil end
    local c0, r0, c1, r1 = world.islandBox(d)
    if not c0 then return nil end
    local cc = (c0 + c1) / 2
    local rr = (r0 + r1) / 2
    local cell = state.cellSize or 1
    -- ★ 这里只能用 world.cellH（不能用 drawH / zRise —— 它们定义在文件后面，
    --   在这里调用会读到 nil 全局：不报错、静态全绿、跑起来才炸）。
    --   所以层号→抬高的换算就地写一遍（和 zRise 同一公式）。
    local h = world.cellH(math.floor(cc + 0.5), math.floor(rr + 0.5)) or 0
    local zv = tonumber(config.DEFAULT_Z_VIS) or 0.15
    local rise = ((h + 1) - 1 - (state.baseH or 0)) * zv
    return cellCenterX(cc), cellFootY(rr) + rise * cell
end

local function camTargetFor(px, py)
    local cell = state.cellSize or 1
    local centerY = state.viewCenterY or 0
    local ix, iy = islandAnchor()
    -- ★ 第 34 批：空中岛屿主题下把岛整体**往上挪**一截。
    --   岛底还挂着一整块岩锥，海面主题那种「地面略低于屏幕中心」的构图会让岩锥
    --   整片沉到底部 HUD 下面看不见，岛看起来就变成「贴在地上的一块板」，浮不起来。
    --   ⚠️ 注意符号：控件 +y 向上，屏幕 y = 世界 y + camY；所以 camY 越大画面越**下**。
    --     想让岛「看起来更高」必须把 camY 加回去（不是减）—— 第一版把符号写反了，
    --     结果岛反而更低了。
    local dy = (state.theme == "sky") and (cell * 0.60) or (-cell * 0.45)
    if ix then
        -- 岛的**视觉重心**：地面中心再往上抬一点（岛上的树 / 小人比地面高）
        return -ix, centerY - iy + dy
    end
    -- 站在水上：退回「小人钉中央」（原逻辑）
    return -px, centerY - (py + cell * 0.5)
end

function M.applyCamera()
    local cx, cy = state.camX or 0, state.camY or 0
    -- ★ 地形层也要跟着镜头走（第 21 批拆出来的 containerGround）
    utils.setPosition(state.containerGround, cx, cy)
    utils.setPosition(state.containerWorld, cx, cy)
    utils.setPosition(state.containerFx, cx, cy)
end

-- 立刻对准（换关 / 重开 / 第一帧用，不做补间，免得从上一关的位置滑进来）
function M.snapCamera()
    local tx, ty = camTargetFor(state.playerVisX or 0, state.playerVisY or 0)
    state.camX, state.camY = tx, ty
    state.camReady = true
    M.applyCamera()
end

-- 每帧跟随：跟着**小人的补间位置**走，所以镜头与角色天然同速
local function updateCamera()
    if not state.camReady then M.snapCamera() return end
    local tx, ty = camTargetFor(state.playerVisX or 0, state.playerVisY or 0)
    local k = utils.clamp(state.camFollow or 1, 0, 1)
    if k >= 0.999 then
        state.camX, state.camY = tx, ty
    else
        state.camX = utils.lerp(state.camX, tx, k)
        state.camY = utils.lerp(state.camY, ty, k)
    end
    M.applyCamera()
end

-- ================================================================
-- ★ 深度键：2.5D 的排序依据
--   行号是主序（row 越大越靠近镜头 → 越晚绘制 → 压住后面的一切），
--   同一行内再分「层」，层内再用小数次序微调。
--
--   ★ 第 19 批改了「谁在谁上面」的**分组方式**，原因是地形长出了高度：
--     老版两张表是两个全局趟（先铺满所有地块装饰、再统一盖所有顶面），
--     只有这样才能让沙滩描边只露在岛的外缘。但一旦地块有了高低差，
--     全局趟就会让「近处一行的崖面」被「远处一行的顶面」盖掉 —— 崖面永远看不见。
--     现在改成**按行交错**：
--         同一行内：侧面(0.1) → 描边(0.4) → 顶面(0.6) → 这行的物体(0.0~0.7 见 BAND_OBJ)
--         跨 行时：第 r+1 行的一切都压住第 r 行的一切（近处压远处）
--     于是「崖面挡住后面的台地、近处的台地挡住前面的崖面」全部自动成立。
--   ★ 描边因此不再靠「铺大一圈再被邻格盖住」，改成**只在临水的边上**画（见 buildTerrain）。
-- ================================================================
local BAND_GRID = 0       -- 水面网格线（永远最底下）
local BAND_TILE = 1000    -- 地形：按行分层（行内 sub 区分 侧面 / 描边 / 顶面）
local BAND_OBJ  = 1005    -- 站位物体与小人（行内压在顶面之上、下一行地形之下）

-- ★ 注意：物体层的 sub 会被**除以 10** 压进 (0,1) 区间（见 objKey），
--   这样「本行的物体」永远落在「本行顶面」和「下一行地形」之间。
local SUB_SHADOW = 0.2
local SUB_ROOT   = 1
local SUB_LOG    = 2
-- 3 空着：老版本这里是「立起的木桩」，现在立着与倒下只是同一棵树的两个状态
local SUB_RAFT   = 3
local SUB_ROCK   = 4
local SUB_TREE   = 5
local SUB_SIGN   = 6
local SUB_GOAL   = 6.5
-- 7 空着：老版本这里是「小人」的层内次序 —— 第 22 批起小人有独立的角色层容器，
--    不再参与 restackWorld 的深度排序，这个次序键随之退役（保留编号防回填撞车）。

-- 小人纯色回退的身高常量 PLAYER_BODY_RATIO / PLAYER_HEAD_RATIO 声明在文件顶部
-- （playerFootOffset 就要用，见那里的说明）。

local function depthKey(band, r, sub)
    return band + (tonumber(r) or 0) * 10 + (tonumber(sub) or 0)
end

-- 物体层的键：sub 除以 10 压进 (0,1)；再叠一点「同格内的垫高层次」
--   stack = 它压在同格地面上方几层（0 = 贴着地面）→ 越往上越晚画。
--   ★ 一定要按 stack（相对值）而不是按绝对 z：真实地图的 z 能到 100+，
--     直接拿 z 当偏移会把键推到下一行去，排序整个错乱。
local function objKey(r, sub, stack)
    local dz = math.min(math.max(tonumber(stack) or 0, 0), 5) * 0.02
    return depthKey(BAND_OBJ, r, (tonumber(sub) or 0) / 10 + dz)
end

-- ================================================================
-- ★ 高度（内核的 z 层号）→ 屏幕上的抬高量
--   原版 HZ/T = 8/52 ≈ 0.15 格 / 层：1 层的坎「一眼看得出来」但不会顶破画面。
--   state.baseH = 整张图最低的那一层（水面），减掉它让最低的地块正好骑在脚线上。
-- ================================================================
local function zVis()
    return tonumber(config.DEFAULT_Z_VIS) or 0.15
end

-- 层号 z → 相对「最低地块的脚线」抬高多少格（y 向上为正）
local function zRise(z)
    return ((tonumber(z) or 1) - 1 - (state.baseH or 0)) * zVis()
end
M.zRise = zRise

-- 某一格顶面（站人的那条线）的屏幕 y
--
--   ★ 树桩位（MExp 的 omap bit 4）要特殊处理，见 drawH 的说明。
local function drawH(c, r)
    local h = world.cellH(c, r)
    if h == nil then return 0 end     -- 水：水面与基准齐平
    if world.hasStump and world.hasStump(c, r) then
        h = h - 1                     -- ★ 那一层是**桩子**，不是土：土要画低一层
    end
    return h
end

-- 一格「画出来的地表」顶面的屏幕 y
--   ★ 树桩格比逻辑高度低一层：hmap 里的值**已经含了桩子那一层**（原版
--     render.js 也是 `ghat(x,y) - (stump?1:0)` 之后再画地的）。桩子由
--     rebuildObjects 单独画，正好把这一层补回来 ——
--     于是「树站着」时桩子被树干挡住、「树被推倒」后原地立刻露出一截桩子，
--     而小人站上去的脚线仍然是逻辑顶面（z 是绝对层号，不随画法变）。
local function groundY(c, r)
    return cellFootY(r) + zRise(drawH(c, r) + 1) * (state.cellSize or 1)
end
M.groundY = groundY

-- ================================================================
-- ★ 视觉槽位
--   makeSlot(素材元件索引)：打算用哪个预制体 + 是否素材
--     · 总开关关掉 / 索引为 0 → 直接退回通用矩形（art = false）
--     · 索引 > 0 → art = true，真正的成败要等控件建出来才知道
-- ================================================================
local function makeSlot(prefabId)
    local pid = tonumber(prefabId) or 0
    if state.useArt and pid > 0 then
        return { prefab = pid, art = true }
    end
    return { prefab = state.rectPrefabId, art = false }
end

-- 通用矩形槽位（沙滩 / 水下网格 / 树根 / 倒下的树 / 立着的树干 / 石头 / 终点旗 …）
local function rectSlot()
    return { prefab = state.rectPrefabId, art = false }
end

-- ================================================================
-- ★ 四个固定图层的父节点（第 22 批）
--   地面（含树桩）→ 石头 → 树木 → 角色，由 game.ensureContainers 按这个顺序建容器。
--   这里只负责「取父节点」，取不到就退回世界总层（老存档 / 容器创建失败时不至于 nil）。
--   ★ 每种物体**只能**往自己那一层画：池里的控件建在哪一层就永远在哪一层，
--     所以石头池 / 木头池 / 地面物体池是三个独立的池（见 state.lua）。
-- ================================================================
local function layerGround()
    return state.containerStump or state.containerGround or state.containerWorld
end
local function layerRock()
    return state.containerRock or state.containerWorld
end
-- ★ 第 42 批：石头·前景层（在小人之**上**）—— 只装比小人更靠前的柱子（见 paintRockPillars）
local function layerRockFront()
    return state.containerRockFront or state.containerPlayer or state.containerWorld
end
local function layerTree()
    return state.containerTree or state.containerWorld
end
local function layerPlayer()
    return state.containerPlayer or state.containerWorld
end

-- 接触阴影槽位：优先「图片」元件 + 引擎内置椭圆图元（100002）
--   ★ 为什么不用矩形：矩形阴影在真机上就是脚底一个**方框**（染色没生效时还是白框）。
--     椭圆和人格的图元笔触用的是同一条路（见 heroPrims），模拟器与真机都认。
--   ★ art = false 是刻意的：它必须像纯色块一样被染色，而不是当素材立绘。
local function shadowSlot()
    local pId = tonumber(state.heroPrPrefabId) or 0
    local eId = tonumber(config.DEFAULT_HERO_PRIMS_IMAGE) or 0
    if pId > 0 and pId ~= state.rectPrefabId and eId > 0 then
        return { prefab = pId, art = false, image = eId }
    end
    return { prefab = state.rectPrefabId, art = false }
end

-- ================================================================
-- ★ 对象池：从池里取第 i 个控件，不够就新建
--   池里每一项是 { c = 控件, art = 是否素材元件 }。
--   ★ 「是不是素材」只在建出来的那一刻确定：素材元件拿不到控件就当场回退通用矩形，
--     并把 art 记为 false —— 之后这类控件一律按调色板染色。
-- ================================================================
local function poolGet(pool, i, parent, slot)
    local item = pool[i]
    if item then return item end

    -- slot.image：建的同时就把图源打上（阴影要「图片」元件 + 椭圆图元，
    -- 纯矩形在真机上是个方框；art=false 表示「这个控件照常染色」）
    local ctrl = utils.createControl(slot.prefab, 0, 0, 1, 1, nil, parent, slot.image)
    local art = (slot.art == true) and (ctrl ~= nil)
    if not ctrl then
        -- 素材元件不可用（老存档里没有这几种元件）→ 回退通用矩形元件，并恢复染色
        ctrl = utils.createControl(state.rectPrefabId, 0, 0, 1, 1, nil, parent)
        art = false
        if not ctrl then return nil end
    end

    item = { c = ctrl, art = art }
    pool[i] = item
    return item
end

local function poolTrim(pool, used)
    for i = used + 1, #pool do
        local item = pool[i]
        utils.setVisible(item and item.c, false)
    end
end

-- ================================================================
-- ★ 显式层级：按深度键把世界容器里所有控件重排一遍（由底到顶）
--   ★ 为什么不能靠创建顺序：
--     引擎的同级绘制顺序确实等于「创建顺序」（越晚创建越靠上），但
--       ① 对象池会**复用**控件 —— 树冠、石头顶面这些「同一物体里后画的那一块」
--          在池里换过位置之后，就可能反过来压住先画的那一块（树干盖住树冠）；
--       ② 2.5D 要求「近处一行盖住远处一行」「近处的树挡住后面的小人」——
--          这只能靠显式点名顺序，创建顺序给不出来。
--   ★ 用 SetAsLastSibling 而非 SetSiblingIndex：它的语义在真机与模拟器上一致
--     （移到同级末位 = 显示在最上）；反过来 SetSiblingIndex 在模拟器里方向是反的。
--   ★ 老的编辑器 / 桩里没有这个方法时 pcall 会静默失败 —— 那时退化成「按创建顺序」，
--     不会更糟。
-- ================================================================
local RESTACK_POOLS = {
    { "decoCtrls",     "decoUsed" },
    { "rimCtrls",      "rimUsed" },     -- 岛缘描边（第 21 批从 decoCtrls 拆出来，单独一层容器）
    { "landBaseCtrls", "landBaseUsed" },-- ★ 顶面底色（第 31 批）：在 containerTile 里、草地素材之下
    { "terrainCtrls",  "terrainUsed" },
    { "shadowCtrls",   "shadowUsed" },   -- 接触阴影（默认关闭）—— 地面子层
    { "objectCtrls",   "objectUsed" },   -- 树桩 / 老树根（地面子层）
    { "rockCtrls",     "rockUsed" },     -- ★ 石头层（第 22 批独立容器）
    { "rockFrontCtrls","rockFrontUsed" },-- ★ 第 42 批：石头·前景层（在小人之上，会挡住角色）
    { "logCtrls",      "logUsed" },      -- ★ 木头（倒木 / 木筏 / 立木）—— 树木层
    { "treeCtrls",     "treeUsed" },
    { "goalCtrls",     "goalUsed" },
    -- ★ 木头倒 / 立的过渡代理：它也站在世界里（要参与「近处压远处」），
    --   所以必须和物体同池排序，不能像涟漪那样丢到 fx 层去。
    { "objProxyCtrls", "objProxyUsed" },
}

-- ================================================================
-- ★ 图层顺序日志（第 22 批追加）：图层**变更**时把层级顺序打进日志
--   两类触发：
--     ① game.ensureContainers 建完容器（OnStart / 补建）→ 打完整层序；
--     ② level.build 构建完关卡 → 打完整层序（此刻地面四个子层也已建齐）；
--     ③ M.restackWorld 层内排序结果与上次**不同**（某层控件数 / 首尾深度键
--        变了）→ 打排序摘要。签名没变就闭嘴 —— 走一步会触发好几次重排，
--        不做变更检测的话日志每帧都在刷。
--   层序是**创建顺序**（自下而上），括号里是各层本帧的控件占用数。
--   通道 printerr：模拟器收进挂载日志，真机日志同样能看到。
-- ================================================================
local LAYER_LOG_SPEC = {
    -- 自下而上 = 显示层序（与 ensureContainers / ensureGroundLayers 的创建顺序一致）
    { "containerBg",     "①背景",        { { "skyCtrls", "skyUsed" } } },
    { "containerSide",   "②地面·侧面",  { { "decoCtrls",    "decoUsed" } } },
    { "containerRim",    "③地面·描边",  { { "rimCtrls",     "rimUsed" } } },
    { "containerTile",   "④地面·顶面",  { { "landBaseCtrls", "landBaseUsed" },
                                            { "terrainCtrls", "terrainUsed" } } },
    { "containerStump",  "⑤地面·树桩",  { { "objectCtrls",  "objectUsed" },
                                            { "shadowCtrls",  "shadowUsed" } } },
    { "containerRock",   "⑥石头",       { { "rockCtrls",    "rockUsed" } } },
    { "containerTree",   "⑦树木",       { { "logCtrls",     "logUsed" },
                                            { "treeCtrls",    "treeUsed" },
                                            { "goalCtrls",    "goalUsed" },
                                            { "objProxyCtrls", "objProxyUsed" } } },
    { "containerPlayer", "⑧角色",       nil },
    { "containerRockFront", "⑨石头·前景(挡角色)", { { "rockFrontCtrls", "rockFrontUsed" } } },
    { "containerFx",     "⑩特效",       nil },
    { "containerHud",    "⑪HUD",        nil },
    { "containerFade",   "⑫黑幕(顶)",   nil },
}

function M.logLayerOrder(tag)
    local parts = {}
    for _, ent in ipairs(LAYER_LOG_SPEC) do
        local piece = ent[2]
        if state[ent[1]] then
            if ent[3] then
                local n = 0
                for _, pr in ipairs(ent[3]) do n = n + (state[pr[2]] or 0) end
                piece = piece .. "(" .. tostring(n) .. ")"
            end
        else
            piece = piece .. "(未建)"
        end
        parts[#parts + 1] = piece
    end
    pcall(printerr, "[图层] " .. tostring(tag or "") .. " 自下而上: "
        .. table.concat(parts, " → "))
end

-- restackWorld 的变更签名：层内排序变了才打日志（见上方说明 ③）
local lastRestackSig = nil

function M.restackWorld()
    local list, seq = {}, 0
    for _, pair in ipairs(RESTACK_POOLS) do
        local pool = state[pair[1]]
        local used = state[pair[2]] or 0
        for i = 1, used do
            local item = pool and pool[i]
            if item and item.c then
                seq = seq + 1
                list[#list + 1] = { c = item.c, k = tonumber(item.key) or 999999, s = seq }
            end
        end
    end

    -- ★ 第 22 批：小人**不再参与**这里的排序。
    --   角色有独立的、固定最上的 containerPlayer，排序对它没有任何意义
    --   （排序只在同一父容器内生效），反而会把身体 / 头 / 像素画容器的先后搅乱。
    table.sort(list, function(a, b)
        if a.k ~= b.k then return a.k < b.k end
        return a.s < b.s
    end)
    for _, it in ipairs(list) do
        pcall(function() it.c:SetAsLastSibling() end)
    end

    -- ★ 图层变更检测：签名 = 各池 used + 排序后首/尾深度键。
    --   走一步会触发好几次 restackWorld（重铺地形 / 重画物体 / 开始移动…），
    --   但层内顺序通常没变 —— 签名一致就闭嘴，只在真正**变了**的那次打印。
    local sig = {}
    for _, pair in ipairs(RESTACK_POOLS) do
        sig[#sig + 1] = tostring(state[pair[2]] or 0)
    end
    if #list > 0 then
        sig[#sig + 1] = tostring(list[1].k)
        sig[#sig + 1] = tostring(list[#list].k)
    end
    local sigStr = table.concat(sig, ",")
    if sigStr ~= lastRestackSig then
        lastRestackSig = sigStr
        M.logLayerOrder(string.format("层内重排变更(参与排序控件 %d 个, 深度键 %s → %s)",
            #list, #list > 0 and tostring(list[1].k) or "-",
            #list > 0 and tostring(list[#list].k) or "-"))
    end
end

-- 池内第 i 个控件：摆成一块矩形
--   hex / alpha 只在**非素材**控件上生效（素材控件的配色交给元件自己）
--   key 是 2.5D 深度键，交给 restackWorld 排序用
local function paint(pool, i, parent, slot, cx, cy, w, h, hex, alpha, key)
    local item = poolGet(pool, i, parent, slot)
    if not item then return i end
    item.key = key
    utils.setVisible(item.c, true)
    utils.setSize(item.c, w, h)
    if not item.art and hex then
        utils.setAlpha(item.c, hex, alpha or 255)
    end
    utils.setPosition(item.c, cx, cy)
    return i + 1
end

-- 探一次：这个槽位在当前存档里**实际**能建成素材控件吗？
--   （素材元件实例化失败会当场回退，所以问池子里的第 1 个控件最准）
local function slotUsesArt(pool, parent, slot)
    if not slot.art then return false end
    local item = poolGet(pool, 1, parent, slot)
    return (item ~= nil) and item.art
end

-- ================================================================
-- ★ 地形层（2.5D 地块 · 逐格一次画完）
--   每格从远到近（行号递增），行内按 sub 从小到大：
--       ① 崖面 / 侧面厚度（挂在顶面**下沿**，高度 = 与南邻的高差）
--       ② 临水的沙滩描边（只画在临水的那几条边上，四条边各一条窄带）
--       ③ 草地 / 雪地顶面（素材立绘 或 纯色棋盘）
--
--   ★ 为什么不再「先铺满描边、再统一盖顶面」：
--     那个两趟画法靠「相邻顶面盖住描边」来让描边只露在岛缘。地块一旦有了高低差
--     （真实地图 cliffs 最高 100 层），崖面就会被远处一行的顶面整片盖掉 ——
--     崖面永远看不见。现在按行交错排序（见 BAND_TILE 的说明），描边直接只画在
--     临水的边上，既不依赖覆盖，也不再产生多余控件。
--   ★ 崖面为什么必然落在「本行顶面下沿 → 南邻顶面上沿」之间：
--     南邻的行号大 1，它的顶面天然低 1 格；它自己的高度再低 dh 层，于是两块的
--     缝隙正好是 dh × zVis 格 —— 那就是崖面。所以只要「行号越大越晚画」，
--     南邻的顶面永远不会盖住这条缝（它是从缝隙下沿开始画的）。
--   ★ 窗口化：真实地图最大 26×72（1872 格）。一次铺满会造上千条控件，真机扛不住。
--     只铺「当前看得见的那一窗」，窗口按 WIN_CHUNK 量化 —— 走到块边界才重铺，
--     而窗口比屏幕大几格，所以重铺发生在屏幕之外，看不见跳变。
-- ================================================================
local WIN_CHUNK = 4
local WIN_MARGIN = 2

-- ★ 地表层高不要在这里另起一个函数了：一律走 drawH（它会减掉树桩那一层）。
--   曾经这里有一个 vh(c,r) = world.cellH or 0，后来每条画地的路径都要减树桩层，
--   留着两个入口必有一条被漏改 —— 所以第 20 批把它删了，只留 drawH。

local function terrainWindow()
    local cell = state.cellSize or 1
    local cols, rows = state.mapCols or 1, state.mapRows or 1
    local cw = state.canvasW or config.DEFAULT_VIEW_WIDTH
    local ch = state.canvasH or config.DEFAULT_VIEW_HEIGHT
    local pc = (state.player and state.player.c) or 1
    local pr = (state.player and state.player.r) or 1
    -- 镜头把小人钉在屏幕中央 → 可见范围就是「小人 ± 半屏」再放宽一点
    local halfC = math.ceil(cw / 2 / cell) + WIN_MARGIN
    local halfR = math.ceil(ch / 2 / cell) + WIN_MARGIN
    local c0 = math.max(1, pc - halfC)
    local c1 = math.min(cols, pc + halfC)
    local r0 = math.max(1, pr - halfR)
    local r1 = math.min(rows, pr + halfR)
    -- 量化到块边界（向外取整，宁可多铺一点也不频繁重铺）
    c0 = math.max(1, math.floor((c0 - 1) / WIN_CHUNK) * WIN_CHUNK + 1)
    r0 = math.max(1, math.floor((r0 - 1) / WIN_CHUNK) * WIN_CHUNK + 1)
    c1 = math.min(cols, math.ceil(c1 / WIN_CHUNK) * WIN_CHUNK)
    r1 = math.min(rows, math.ceil(r1 / WIN_CHUNK) * WIN_CHUNK)
    return { c0 = c0, c1 = c1, r0 = r0, r1 = r1 }
end

-- ================================================================
-- ★ 地形子容器（第 21 批三层，第 22 批加「树桩」第四层）
--   侧面(崖面) / 岛缘描边 / 草地顶面 / 树桩 各挂一个子容器，**创建顺序即层级**：
--     containerSide → containerRim → containerTile → containerStump
--   树桩也属于「地面图层」：它必须压在草地顶面之上（否则被草地埋掉），
--   但又必须在石头 / 树木 / 角色之下 —— 放在地面层的最末一个子层正好。
--   ★ 为什么不用同级排序：真机上 SetAsLastSibling 并不可靠（池扩容时新建控件
--     默认排在同级最末 = 压在最上层）。地形和物体混在一个容器里时，这会让
--     「草地盖住小人和树」「岛内部冒出边框」。拆层之后这两件事都变成结构性保证，
--     和运行时排序 API 无关；对象池再怎么扩容也不会乱。
-- ================================================================
local function ensureGroundLayers()
    if state.containerSide and state.containerRim and state.containerTile then return true end
    local base = state.containerGround
    if not base then return false end
    local pid = state.containerPrefabId or 0
    local function mk()
        local ctrl = nil
        if pid > 0 then ctrl = utils.createControl(pid, 0, 0, 1, 1, nil, base) end
        if not ctrl then
            -- 回退：通用矩形当容器 —— 必须染成全透明，否则是一块 1px 白点
            ctrl = utils.createControl(state.rectPrefabId, 0, 0, 1, 1, nil, base)
            if ctrl then utils.setAlpha(ctrl, "000000", 0) end
        end
        return ctrl
    end
    state.containerSide = state.containerSide or mk()
    -- ★ 第 25 批：描边改成**骑在格线上**（不再是整条外移到水面），
    --   它会压住草地边缘的 rim/2，所以必须画在顶面**之上**，否则会被整格草地盖掉。
    --   层级顺序 = 侧面 → 顶面 → 描边 → 树桩（创建顺序即层级，见 ensureContainers 的说明）。
    state.containerTile = state.containerTile or mk()
    state.containerRim  = state.containerRim  or mk()
    state.containerStump = state.containerStump or mk()   -- 树桩 / 老树根 / 阴影（第 22 批）
    return (state.containerSide and state.containerRim and state.containerTile) ~= nil
end

-- 海面底 + 水面网格线（与窗口无关，只在第一次 / 换图时铺）
-- ================================================================
-- ★ 十六进制色的插值（第 34 批）
--   天空渐变要的是「两个色之间连续过渡」，而调色板存的是 "RRGGBB" 字符串；
--   引擎的 Color 对象在不同版本上取 r/g/b 字段的方式不一致（有的要 /255），
--   所以这里直接当字符串解析，不碰 Color —— 纯数字运算，模拟器与真机结果一致。
-- ================================================================
local function hex2rgb(h)
    local s = tostring(h or "FFFFFF"):gsub("#", "")
    if #s ~= 6 then return 255, 255, 255 end
    return tonumber(s:sub(1, 2), 16) or 0,
           tonumber(s:sub(3, 4), 16) or 0,
           tonumber(s:sub(5, 6), 16) or 0
end

local function rgb2hex(r, g, b)
    local function q(v)
        v = math.floor(math.max(0, math.min(255, (tonumber(v) or 0) + 0.5)))
        return string.format("%02X", v)
    end
    return q(r) .. q(g) .. q(b)
end

-- 两色插值（t = 0 → a，t = 1 → b）
local function mixHex(a, b, t)
    local ar, ag, ab = hex2rgb(a)
    local br, bg, bb = hex2rgb(b)
    t = math.max(0, math.min(1, tonumber(t) or 0))
    return rgb2hex(ar + (br - ar) * t, ag + (bg - ag) * t, ab + (bb - ab) * t)
end

-- 天空竖直渐变：t = 0（屏幕顶）→ 1（屏幕底）
--   色标是「参考图竖直扫描」的实测结果，见 config.PALETTE_SKY 的说明。
local SKY_STOPS = {
    { 0.00, "skyTop" },
    { 0.14, "skyHigh" },
    { 0.34, "skyMid" },
    { 0.52, "skyLow" },
    { 0.66, "skyHorizon" },
    { 1.00, "skyHorizon" },
}

local function skyColorAt(palette, t)
    local n = #SKY_STOPS
    local prev = SKY_STOPS[1]
    if t <= prev[1] then return palette[prev[2]] or "FFFFFF" end
    for i = 2, n do
        local cur = SKY_STOPS[i]
        if t <= cur[1] then
            local span = cur[1] - prev[1]
            local k = (span > 0) and ((t - prev[1]) / span) or 0
            return mixHex(palette[prev[2]] or "FFFFFF", palette[cur[2]] or "FFFFFF", k)
        end
        prev = cur
    end
    return palette[prev[2]] or "FFFFFF"
end

-- ================================================================
-- ★ 天空 + 云（第 34 批 · 空中岛屿主题）
--
--   画在 containerBg 上 —— 这个容器**不受镜头平移影响**（applyCamera 只动
--   containerGround / containerWorld / containerFx），所以天空天然是一块
--   「背景板」：在岛内走动时画面本来就不动，云不跟着移看不出问题；
--   而云在天上，本来也不该和地面一起平移。
--
--   ★ 为什么全部是矩形、还要分「横带」：
--     真机上没有渐变控件，也没有可用的椭圆图元（100002 只是模拟器的代理，
--     见 heroPrims 那批踩的坑）—— 渐变只能靠 N 条 1 像素级色差的横带拼；
--     云只能靠「由宽到窄的一摞白矩形」堆出蓬松的土丘轮廓，再在下面压一条
--     冷灰蓝的暗边，才有立体感。
--
--   ★ 云的位置用**固定种子的伪随机**：buildTerrain 每换一次窗口就重铺一次天空，
--     用 math.random 的话云会随机跳位置 —— 玩家看到的是「云在抖」。
--     固定种子 = 同一张画布下每次都摆在同一处。
-- ================================================================
local function buildSky(palette)
    local parent = state.containerBg or state.containerWorld
    local rect = rectSlot()
    local cw = state.canvasW or config.DEFAULT_VIEW_WIDTH
    local ch = state.canvasH or config.DEFAULT_VIEW_HEIGHT
    local top = ch / 2                      -- 屏幕坐标原点在宿主中心，y 向上为正
    local si = 1

    -- ① 天空渐变（横带）
    local n = math.max(4, math.floor(tonumber(config.DEFAULT_SKY_BANDS) or 20))
    local bandH = ch / n
    for i = 0, n - 1 do
        local t = (i + 0.5) / n
        si = paint(state.skyCtrls, si, parent, rect,
                   0, top - (i + 0.5) * bandH,
                   cw + 16, bandH + 2, skyColorAt(palette, t), 255, 0)
    end

    -- ② 云
    local count = math.max(0, math.floor(tonumber(config.DEFAULT_SKY_CLOUD_COUNT) or 6))
    local cloudHex = palette.cloud or "FFFFFF"
    local warmHex  = palette.cloudWarm or cloudHex
    local shadeHex = palette.cloudShade or "B7C8D6"
    local seed = 20261026
    local function rnd()
        seed = (seed * 1103515245 + 12345) % 2147483648
        return seed / 2147483648
    end

    local puffH = ch * 0.038
    for _ = 1, count do
        local w = cw * (0.15 + rnd() * 0.24)
        local x = (rnd() - 0.5) * (cw + w)
        local y = -ch * (0.06 + rnd() * 0.34)          -- 屏幕下半部
        local puffs = 4 + math.floor(rnd() * 3)        -- 4~6 层
        for p = 1, puffs do
            local f = 1 - (p - 1) / puffs              -- 底层最宽，往上收
            local pw = w * (0.34 + 0.66 * f)
            local py = y + (p - 1) * puffH * 0.62
            si = paint(state.skyCtrls, si, parent, rect,
                       x, py, pw, puffH, (p == 1) and warmHex or cloudHex, 244, 0)
        end
        -- 云团下沿的冷暗边：一条淡灰蓝，把「云底」压出来（否则白压白糊成一片）
        si = paint(state.skyCtrls, si, parent, rect,
                   x, y - puffH * 0.42, w * 0.92, puffH * 0.30, shadeHex, 120, 0)
    end

    -- ③ 屏幕最底下那一条「云海」（参考图整片下半部都是云）
    for k = 1, 3 do
        local wid = cw * (1.25 - 0.12 * (k - 1))
        si = paint(state.skyCtrls, si, parent, rect,
                   0, -ch * 0.5 + (k - 1) * puffH * 0.95,
                   wid, puffH * 1.6, cloudHex, 250, 0)
    end

    return si
end

local function buildSea(palette)
    -- ★ 地形层（第 21 批）：网格线 / 侧面 / 描边 / 顶面全挂在 containerGround 的三层
    --   子容器里，它们比 containerWorld 先创建 → 永远在物体与小人之下。
    local parent = state.containerSide or state.containerGround or state.containerWorld
    local cell = state.cellSize
    local cols, rows = state.mapCols or 1, state.mapRows or 1
    local rect = rectSlot()
    local waterSlot = makeSlot(state.waterPrefabId)

    -- ① 背景（★ 第 34 批：按主题分两支）
    --
    --   空中岛屿：「水面」这个底控件本身就是深青色的整屏大矩形，如果留着它
    --   会把天空整片盖掉 —— 所以这里**直接隐藏**它，改由 buildSky 铺天空与云。
    --   反过来切回海面主题时，必须把天空池清空（poolTrim 到 0）并让水面底重新可见，
    --   否则会看到「天空压在海面上」这种半新半旧的状态。
    local sky = (state.theme == "sky")
    if sky then
        if state.bgCtrl then utils.setVisible(state.bgCtrl, false) end
        local si = buildSky(palette)
        poolTrim(state.skyCtrls, si - 1)
        state.skyUsed = si - 1
    else
        poolTrim(state.skyCtrls, 0)
        state.skyUsed = 0
        if not state.bgCtrl then
            local bg = utils.createControl(waterSlot.prefab, 0, 0,
                (state.canvasW or 800) + 800, (state.canvasH or 600) + 800, nil, state.containerBg)
            state.bgCtrlArt = (bg ~= nil) and waterSlot.art
            state.bgCtrl = bg
        end
        if state.bgCtrl then
            utils.setVisible(state.bgCtrl, true)
            if not state.bgCtrlArt then
                utils.setAlpha(state.bgCtrl, palette.water, 255)   -- 回退：通用矩形 + 调色板
            end
        end
    end

    -- ② 水面细网格 —— ★ 第 32 批：用户要求「去掉地图上的格子线」，默认整段不画。
    --    开关两处同源：真机参数 `waterGridLines`（`state.waterGridLines`，0/-1 = 关）
    --    ← 默认 `config.DEFAULT_WATER_GRID_LINES`。关掉时**不建任何控件**，
    --    所以不会留下 N 个 alpha=0 的空矩形白占池子。
    --    ⚠️ 旧逻辑「关 = 画深色棋盘」已经废弃：关掉就是干净海面，不是换一种网格。
    --    ★ 第 34 批：空中岛屿主题下根本没有水面，这段直接跳过
    --      （水面格线画在 depthKey(BAND_GRID) 上，会浮在天空前面，一眼假）。
    local di = 1
    local gridOn = state.waterGridLines
    if gridOn == nil then gridOn = (tonumber(config.DEFAULT_WATER_GRID_LINES) or 0) ~= 0 end
    local alpha = tonumber(config.DEFAULT_WATER_LINE_ALPHA) or 0
    if (not sky) and gridOn and alpha > 0 then
        local lw = math.max(1, math.floor(cell * 0.035))
        local over = math.ceil((state.canvasW or config.DEFAULT_VIEW_WIDTH) / (2 * cell)) + 2
        local overY = math.ceil((state.canvasH or config.DEFAULT_VIEW_HEIGHT) / (2 * cell)) + 2
        local left = cellCenterX(1) - cell / 2 - over * cell
        local top = cellCenterY(1) + cell / 2 + overY * cell
        local spanX = (cols + over * 2) * cell
        local spanY = (rows + overY * 2) * cell
        for c = 0, (cols + over * 2) do
            di = paint(state.decoCtrls, di, parent, rect, left + c * cell, top - spanY / 2,
                       lw, spanY, palette.waterLine, alpha, depthKey(BAND_GRID, 0, 0.1))
        end
        for r = 0, (rows + overY * 2) do
            di = paint(state.decoCtrls, di, parent, rect, left + spanX / 2, top - r * cell,
                       spanX, lw, palette.waterLine, alpha, depthKey(BAND_GRID, 0, 0.2))
        end
    end
    return di
end

local function buildTerrain(palette, force)
    local win = terrainWindow()
    local key = table.concat({ win.c0, win.c1, win.r0, win.r1 }, ":")
    if not force and key == (state.terrainWinKey or "") then return false end
    state.terrainWin = win
    state.terrainWinKey = key

    -- ★ 三层子容器：侧面 / 描边 / 顶面（层级由创建顺序保证，见 ensureGroundLayers）
    ensureGroundLayers()
    local parent = state.containerSide or state.containerGround or state.containerWorld
    local parentRim = state.containerRim or parent
    local parentTile = state.containerTile or parent
    local cell = state.cellSize
    -- ★ 第 34 批：主题分支要先算出来 —— 岛缘窄边的宽度就跟着主题走
    local sky = (state.theme == "sky")
    local rim = cell * (sky and (config.DEFAULT_SKY_RIM_RATIO or 0.10)
                             or (config.DEFAULT_TILE_RIM_RATIO or 0.17))
    local sideH = cell * (config.DEFAULT_TILE_SIDE_RATIO or 0.30)
    local cliffMax = cell * (config.DEFAULT_CLIFF_MAX or 2.1)
    local zc = cell * zVis()
    local rect = rectSlot()
    local landSlot = makeSlot(state.landPrefabId)
    local landArt = (not sky) and slotUsesArt(state.terrainCtrls, parentTile, landSlot)
    -- ★★ 关键：顶面**必须换槽位**，不能只把 landArt 设成 false。
    --   原因是 paint() 只给「非素材控件」染色（`if not item.art and hex`）——
    --   而一个控件是不是素材，取决于**建它时用的槽位**，不是 landArt 这个布尔。
    --   第 34 批第一版就栽在这：landArt=false 走进 else 分支、hex 传了 palette.land，
    --   但槽位还是 landSlot → 建出来的是素材控件 → 颜色被忽略，
    --   顶面仍然是草地贴图那只绿色（真机同理会一直是草纹，改配色根本看不出）。
    local tileSlot = sky and rectSlot() or landSlot
    local fit = (config.DEFAULT_ART_FIT or {}).land or { w = 1, h = 1, dy = 0 }
    -- 空中岛屿的三个几何参数（只在 sky 主题下用）
    local skyDepth = cell * (tonumber(config.DEFAULT_SKY_DEPTH) or 2.6)
    local skySegs = math.max(1, math.floor(tonumber(config.DEFAULT_SKY_SEGMENTS) or 3))
    local gridW = math.max(1, math.floor(cell * 0.030))
    local gridAlpha = tonumber(config.DEFAULT_SKY_GRID_ALPHA) or 0
    -- ★ 第 31 批：**沙滩带 / 侧面 / 顶面一律收在格子里面，外沿正好压在格线上**。
    --   用户连报三轮「岛的边缘要和格子线（黑线）对齐、边框不能超过黑线」，
    --   到这一版才把三个越线源全部堵住：
    --     ① 第 30 批「贴草地外沿」→ 沙滩外移 edgeOver(≈4.5px)，本身就越线了；
    --     ② 草地素材控件 1.138 格（内容正好一格、四周是透明留白）—— 真机看不出，
    --        但按控件矩形取色的呈现会在沙滩外面露一圈绿边；
    --     ③ `state.baseH` 取整图最低层（水面），最矮的岛被抬 0.15 格 ≈10px，
    --        整个岛的顶面浮在格子线**上面**（这一条在真机上一样看得见）。
    --   现在：底色/沙滩/侧面/顶面全部 = 一整格，且 baseH 改成陆地最低层 → 抬升 0。

    local di = buildSea(palette)
    local ri = 1
    local ti = 1
    local bi = 1

    -- ★ 第 34 批：岛底岩锥的登记表（岛号 → 最低沿 / 列范围）
    --   skyConeIds 保序（pairs 的遍历顺序不保证 → 排序会随帧变，虽然画出来一样，
    --   但控件占位会跳，调试时很容易误判成「图层在动」）。
    local skyConeMap, skyConeIds = {}, {}

    -- ★ 地形分**两遍**铺（第 21 批）：① 全部侧面 + 岛缘描边 → ② 全部草地顶面。
    --
    --   分两遍 + 分三层容器，等于把「草地永远盖住侧面和描边」写死成结构：
    --   真机上同级 SetAsLastSibling 并不可靠（池扩容时新控件默认排在同级最末 =
    --   压在最上层），逐格交替绘制时，隔壁格的侧面/描边就会压住这一格的草地边缘
    --   —— 表现就是「岛内部凭空冒出边框 / 棕色横条」。
    --   而且分两遍不会带来遮挡损失：每格的侧面只从「自己顶面的下沿」往**下**挂，
    --   永远不会伸进上一行顶面的范围。
    for r = win.r0, win.r1 do
        for c = win.c0, win.c1 do
            if world.landAt(c, r) then
                local cx = cellCenterX(c)
                local cy = cellCenterY(r) + zRise(drawH(c, r) + 1) * cell
                local bottom = cy - cell / 2          -- 顶面的下沿
                -- ① 侧面 / 崖面：与南邻的高差
                --   ★ 第 31 批：横向**正好一格**（`cell`），左右边缘与格子线重合。
                --     上一版草稿还是 `cell + 1`（左右各 0.5px），虽然子像素级，
                --     但用户要求「一个像素都不许越线」，所以直接去掉那 1px。
                --     相邻两格各画自己那一格，边缘严丝合缝，不会露缝。
                local dh = drawH(c, r) - drawH(c, r + 1)
                local wh = sideH + math.max(0, dh) * zc
                if wh > cliffMax then wh = cliffMax end
                -- ★ 第 34 批：空中岛屿主题下这一圈读作「地壳」—— 用最亮的那档奶白，
                --   往下才是逐渐变灰的岩锥（见③）。海面主题仍然是原来的土色。
                local crustHex = sky and (palette.rockWarm or palette.soil) or palette.soil
                di = paint(state.decoCtrls, di, parent, rect, cx, bottom - wh / 2,
                           cell, wh, crustHex, 255, depthKey(BAND_TILE, r, 0.1))
                -- ② 临外海的沙滩描边（第 31 批：**整条落在格子里面**，外沿 = 格线）
                --
                --   ★ 判定的邻格必须是**外海**（world.isOuterWater），不是「不是陆地」。
                --     岛内部也有水缝，旧写法把它们也算成海 → 水缝四周各画一条沙滩带，
                --     把水缝的**内轮廓**勾了出来（第 24 批修的就是这个）。
                --   ★ 位置演进（四版，**第 31 批这版才是用户要的**，别再改回去）：
                --     第 24 批「整体外移 rim」    → 岛比一格大，水道被啃掉一大截；
                --     第 25 批「骑线」（中心线=格线）→ 沙滩一半悬在水上；
                --     第 30 批「贴草地外沿」     → 仍外扩 4.5px，用户报「边框超过黑线」；
                --     **第 31 批「整条在格内」**  → 外沿 = `cx ± cell/2` / `cy ± cell/2`，
                --     正好压在格线上：岛的外轮廓 == 格子矩形，一个像素都不越界；
                --     水道完整保留一格、水面网格线完全不被压住。
                --   ★ 长度 = cell：四条带各自盖满自己那一条边，拐角由相邻两条重叠覆盖，
                --     既没有缺口，也不会伸出格子。
                for _, e in ipairs({ { 0, -1 }, { 0, 1 }, { -1, 0 }, { 1, 0 } }) do
                    if world.isOuterWater(c + e[1], r + e[2]) then
                        local bw, bh, bx, by
                        if e[1] == 0 then
                            bw, bh = cell, rim
                            bx = cx
                            -- ★ 行号越大越靠下（屏幕 y 越小）：e[2] = -1 是北（y 更大）
                            by = cy - e[2] * (cell / 2 - rim / 2)
                        else
                            bw, bh = rim, cell
                            bx = cx + e[1] * (cell / 2 - rim / 2)
                            by = cy
                        end
                        ri = paint(state.rimCtrls, ri, parentRim, rect, bx, by,
                                   bw, bh, palette.sand, 255, depthKey(BAND_TILE, r, 0.4))
                    end
                end

                -- ③ 岛底岩锥的「采样」：这里只**登记**每座岛的列范围与最低沿，
                --   真正的岩锥在下面单独一趟画（一座岛画一次，而不是每格画一次）。
                --   ★ 为什么不在这里逐格画：逐格画只能让每一列的下垂深度不同，
                --     宽度永远是整格 —— 3~4 格宽的小岛看起来就是几根并排的柱子，
                --     不像参考图那块「越往下越尖」的岩体。逐岛画才能让**宽度也收窄**。
                --   ★ 列范围要按**所有**陆格统计（不是只统计南沿那一行）：
                --     南沿往往比岛顶窄（岛是上宽下窄的），只按南沿算会让锥体比岛还窄。
                --   ★ 也别用 imap 的 bbox：imap 会把岛内部的空洞 / 边缘也算进同一座岛，
                --     拿它当宽度会让岩锥比草地顶面还宽（第 34 批第一版就是这个问题）。
                if sky then
                    local id = world.islandAtCell(c, r)
                    if id and id > 0 then
                        local rec = skyConeMap[id]
                        if not rec then
                            rec = { y = nil, r = r, c0 = c, c1 = c }
                            skyConeMap[id] = rec
                            skyConeIds[#skyConeIds + 1] = id
                        end
                        if c < rec.c0 then rec.c0 = c end
                        if c > rec.c1 then rec.c1 = c end
                        if not world.landAt(c, r + 1) then
                            local yb = bottom - wh            -- 这一列地壳的下沿
                            if (not rec.y) or yb < rec.y then
                                rec.y = yb
                                rec.r = r
                            end
                        end
                    end
                end
            end
        end
    end

    -- ③ 岛底岩锥（★ 第 34 批 · 空中岛屿主题）
    --
    --   参考图里的岛不是「一格厚的板」，而是一整块悬在空中的岩石：顶上一片平草地，
    --   下面越收越窄、最后收成一个尖。2.5D 正交视角做不出透视，但剪影完全画得出来 ——
    --   把它当成**一摞从宽到窄的横带**：
    --
    --     k=0（贴着地壳）宽度 = 整座岛的宽      k=1（锥尖）宽度 = 28%
    --     每一带的竖向高度 = skyDepth / skySegments，颜色自上而下由亮到暗
    --
    --   ★ 一座岛**只画一次**（按 imap 岛号去重），所以控件数是「岛数 × 段数」，
    --     不是「格数 × 段数」—— 一屏里 5 座岛 × 3 段 = 15 个控件，很便宜。
    --   ★ 锥体的左右边界靠岛的真实 bbox（imap 求出来的 c0..c1）：越宽的岛锥越宽。
    for _i = 1, #skyConeIds do
        local id = skyConeIds[_i]
        local rec = skyConeMap[id]
        if rec and rec.y then
            local wid = math.max(cell, (rec.c1 - rec.c0 + 1) * cell) * 0.96
            local xMid = (cellCenterX(rec.c0) + cellCenterX(rec.c1)) / 2
            local tip = tonumber(config.DEFAULT_SKY_TIP) or 0.26
            local segH = skyDepth / skySegs
            local yCur = rec.y
            for sg = 1, skySegs do
                local kMid = ((sg - 1) + 0.5) / skySegs
                local wSeg = wid * (1 - (1 - tip) * kMid)
                local k = (skySegs > 1) and ((sg - 1) / (skySegs - 1)) or 0
                local hex
                if k <= 0.5 then
                    hex = mixHex(palette.rockWarm or palette.soil, palette.soil, k * 2)
                else
                    hex = mixHex(palette.soil, palette.rockShade or palette.soil,
                                 (k - 0.5) * 2)
                end
                di = paint(state.decoCtrls, di, parent, rect,
                           xMid, yCur - segH / 2, wSeg, segH + 1, hex, 255,
                           depthKey(BAND_TILE, rec.r, 0.12))
                -- 竖向凿痕：参考图的岩面是一道道竖的凹槽，不是一片平的奶白。
                --   横带只表达「上亮下暗」，再叠两条淡灰竖条才读得出「这是一块岩石」。
                --   ★ 必须**按本段自己的宽度**摆位（±25%·wSeg），不能按整岛宽度摆 ——
                --     锥尖那一段只有岛宽的 1/5，按整岛宽度摆的话竖条会飘到天空里。
                local fluteW = math.max(1, wSeg * 0.09)
                for _f = 1, 2 do
                    local fx = xMid + wSeg * (-0.25 + 0.50 * (_f - 1))
                    di = paint(state.decoCtrls, di, parent, rect,
                               fx, yCur - segH / 2, fluteW, segH + 1,
                               palette.rockShade or palette.soil, 58,
                               depthKey(BAND_TILE, rec.r, 0.13))
                end
                yCur = yCur - segH
            end
        end
    end

    -- ② 第二遍：草地顶面（压在上面这一整片之上）
    --
    --   ★ 第 31 批：素材路径下先铺一层**整格纯色**（landBaseCtrls），再压草地素材。
    --     草地素材的内容只占画布的 87.9%，控件缩到正好一格之后内容只剩 0.879 格
    --     → 格与格之间会露出 8px 的缝。这一层同色底把缝兜住，看起来仍是整片草地；
    --     而岛的**外轮廓**仍然是严格的格子矩形（不再被素材控件撑出去）。
    --
    --   ★ 第 34 批（空中岛屿）：这里**刻意不用草地素材**，改成整格纯色，理由有两条：
    --     ① 参考图的岛顶就是一片**平坦的亮黄绿**，没有草纹；素材那套绿色（#6DB03C）
    --        压上去反而离参考图更远；
    --     ② 用户要求「岛屿上有格子能分清角色在哪一格」——素材的草纹会把细格线
    --        啃得看不清，纯色底 + 格线才是干净的「棋盘」。
    --     海面主题不受影响，仍然照旧走素材。
    for r = win.r0, win.r1 do
        for c = win.c0, win.c1 do
            if world.landAt(c, r) then
                local cx = cellCenterX(c)
                local cy = cellCenterY(r) + zRise(drawH(c, r) + 1) * cell
                if landArt then
                    bi = paint(state.landBaseCtrls, bi, parentTile, rect,
                               cx, cy, cell, cell, palette.land, 255,
                               depthKey(BAND_TILE, r, 0.55))
                    ti = paint(state.terrainCtrls, ti, parentTile, landSlot,
                               cx, cy + (fit.dy or 0) * cell,
                               cell * (fit.w or 1), cell * (fit.h or 1), nil, nil,
                               depthKey(BAND_TILE, r, 0.6))
                else
                    local hex = palette.land
                    if (not sky) and (c + r) % 2 == 0 then hex = palette.landDark end
                    ti = paint(state.terrainCtrls, ti, parentTile, tileSlot,
                               cx, cy, cell, cell, hex, 255,
                               depthKey(BAND_TILE, r, 0.6))
                end

                -- ③ 岛面格线（★ 第 34 批 · 空中岛屿主题专属）
                --
                --   画在 **containerRim**（顶面之上、树桩之下），所以永远压在草地
                --   顶面之上、又不会盖住树 / 石头 / 小人。
                --
                --   ★ 只在「两格都是陆地」的公共边上画线：
                --     岛缘那一条已经有一圈米白窄边（rim）当边界了，再压一条深绿格线
                --     会和窄边糊成一条脏边；这样每个格子都被框住，而整岛的外轮廓
                --     仍然是那条干净的米白窄边。
                --   ★ 每格最多两条（右 + 下）：线的宽度是格宽的 3%（≈3px），
                --     太细看不见、太粗像瓷砖缝，3% 在同色草地上刚好读得出。
                if sky and gridAlpha > 0 then
                    if world.landAt(c + 1, r) then
                        ri = paint(state.rimCtrls, ri, parentRim, rect,
                                   cx + cell / 2, cy, gridW, cell,
                                   palette.tileGrid, gridAlpha,
                                   depthKey(BAND_TILE, r, 0.45))
                    end
                    if world.landAt(c, r + 1) then
                        ri = paint(state.rimCtrls, ri, parentRim, rect,
                                   cx, cy - cell / 2, cell, gridW,
                                   palette.tileGrid, gridAlpha,
                                   depthKey(BAND_TILE, r, 0.46))
                    end
                end
            end
        end
    end

    poolTrim(state.decoCtrls, di - 1)
    state.decoUsed = di - 1
    poolTrim(state.rimCtrls, ri - 1)
    state.rimUsed = ri - 1
    poolTrim(state.landBaseCtrls, bi - 1)
    state.landBaseUsed = bi - 1
    poolTrim(state.terrainCtrls, ti - 1)
    state.terrainUsed = ti - 1

    -- ★ 重铺完地形**必须**立即重排层级（见 M.restackWorld）。
    --   不加这一步的后果就是「走路时地图图层会变」：窗口一换，池里新造的控件默认
    --   排在同级最后 → 整片草地盖住小人和树；复用到的旧控件则带着上一窗的顺序。
    --   只在换窗口的那一帧跑一次（restackWorld 内部就是一次排序 + N 次提升）。
    --   （第 21 批起地形三层已经靠容器分层，这里排序只对物体/小人还有意义。）
    M.restackWorld()
    return true
end

-- 每帧调一次：镜头把小人钉在中央，所以「换窗」只可能在块边界，
-- 判定只是一次字符串比较，代价可以忽略。
function M.ensureTerrain(palette)
    if not state.cellSize then return false end
    local pal = palette or utils.resolvePalette(state.levelConfig)
    local changed = buildTerrain(pal, false)

    -- ★ 第 40 批：石头（图腾柱）和地形一样**按可视窗裁剪**。
    --   石头是「不可通行格」—— 柱子没画出来就等于一堵看不见的墙，
    --   所以窗口一变就得跟着重铺，否则走出旧窗口的石头会变成隐形的。
    --   ★ 只在换窗那一帧跑（buildTerrain 内部已经做了字符串比较），
    --     和地形重铺同一帧完成，不会出现「地动了柱子没动」的错位。
    if changed then
        -- ★ 第 43 批：换窗后**无条件**重排。柱子进哪个池取决于小人位置，换窗时
        --   「哪根柱子占哪个池槽」同样会整体挪位，只靠复用旧顺序会把柱子叠错。
        M.repaintRockPillars(pal)
        M.restackWorld()
    end
    -- ★ 第 42 批：柱子要「挡住站在它后面的角色」，所以小人换格后可能有柱子要从
    --   人后挪到人前（或反过来）。这一步是**纯算术**判定，真有柱子换边才重铺 ——
    --   见 M.ensureRockSplit 的说明（每走一步都重铺的话真机必卡）。
    M.ensureRockSplit()
    return changed
end

-- ================================================================
-- ★ 木头：同一根木头的两个状态（躺 / 立）—— 本工程「表现力」的核心
--   两态在**四个维度**上同时拉开，任何一维单独用都不够：
--     ① 剪影：躺 = 长而扁（1.00 × 0.50）  立 = 窄而高（0.36 × 1.00）
--     ② 明暗：躺 = 偏灰的旧木色 logSide    立 = 偏暖的新木色 logStandSide
--     ③ 受光：躺 = 顶面那条**横**亮边（横梁）  立 = 左侧那条**竖**亮边（立柱）
--             两者的背光侧都配一条暗边（见 shadeEdgeRect）—— 「圆木」的读法；
--             横躺时这条暗边正好落在**下沿**，于是同时兼作「贴地」的线索。
--     ④ 两端：躺 = **两**端各一个带年轮的切口（被锯断的木头）
--             立 = 根部一小撮土堆 + **上**端一圈亮切面（扎在地里、切面朝天）
--   切两态时再叠一段过渡补间（见 M.animateObject），「倒下 / 立起来」就有了过程。
-- ================================================================

-- 形态 = { c, r, cx, cy, w, h, alongX, stand, row }
--   c, r  : 所在格 —— hideAnimAt 靠它认出「终点格上那根真实木头」并跳过它
--   alongX: 1 = 横躺（受光边在上沿）/ 0 = 竖（受光边在左侧）
--   stand : 1 = 立姿 / 0 = 躺姿 —— 决定用哪一套配色与「立姿专属」的根部土堆、顶端切面
--   row   : 所在行，过渡代理要靠它算深度键（近处压远处）
-- ★ 「它踩在哪条线上」：地块顶面 + 被垫高了多少层
--   内核的 z 是绝对层号，地块顶面 = 抬高层数 + 1，两者之差就是「它压着几层东西」。
local function entBaseY(c, r, z)
    local cell = state.cellSize or 1
    local gz = drawH(c, r) + 1
    return groundY(c, r) + ((tonumber(z) or gz) - gz) * zVis() * cell
end

-- 它压在同格地面上方几层（0 = 贴着地面）—— 只用于深度排序（见 objKey）
local function stackOf(c, r, z)
    local gz = drawH(c, r) + 1
    return (tonumber(z) or gz) - gz
end

local function lyingShape(c, r, dir, z)
    local cell = state.cellSize or 1
    local thick = cell * LOG_THICK
    local h = world.logHeightAt(c, r) or config.DEFAULT_H_LOG_LAND
    local alongX = (world.AXIS[dir] == 1)
    return {
        c = c, r = r,
        cx = cellCenterX(c),
        -- 木头的**底面**落在它所在的那一层上：贴地 = 脚线，垫高 = 高半层
        cy = entBaseY(c, r, z) + (h - 0.25) * cell,
        w = alongX and cell * LOG_LEN or thick,
        h = alongX and thick or cell * LOG_LEN,
        alongX = alongX and 1 or 0,
        stand = 0,
        row = r,
    }
end

local function standingShape(c, r, z)
    local cell = state.cellSize or 1
    local w, h = cell * TRUNK_W, cell * TRUNK_H
    return {
        c = c, r = r,
        cx = cellCenterX(c),
        -- 立着的木头 / 树：底面贴在自己那一层，整个人往上长 1 格
        cy = entBaseY(c, r, z) + h / 2,
        w = w, h = h,
        alongX = 0,
        stand = 1,
        row = r,
    }
end

-- 受光的那条亮边：横躺时是上沿的横带，竖着时是左侧的竖带。
--   k 是两条带之间的融合系数（0 = 竖亮边 / 1 = 横亮边），供过渡动画用。
local function litEdgeRect(sp, k)
    local ex = utils.lerp(sp.cx - sp.w * 0.22, sp.cx, k)
    local ey = utils.lerp(sp.cy, sp.cy + sp.h * 0.26, k)
    local ew = utils.lerp(sp.w * 0.28, sp.w * 0.98, k)
    local eh = utils.lerp(sp.h * 0.94, sp.h * 0.30, k)
    return ex, ey, ew, eh
end

-- 背光的那条暗边：**永远贴在受光边的对侧**（光从左上来）。
--   ★ 这一条就是「躺平」最关键的线索：
--     横躺时它落在木头下沿 —— 正好是**贴地**的那一面，木头一下就「摁」在地上了；
--     竖躺（南北躺）时它落在右沿，和左沿的亮边配成一对，木头立刻有了圆柱感。
local function shadeEdgeRect(sp, k)
    local sx = utils.lerp(sp.cx + sp.w / 2 - sp.w * 0.13, sp.cx, k)
    local sy = utils.lerp(sp.cy, sp.cy - sp.h / 2 + sp.h * 0.13, k)
    local sw = utils.lerp(sp.w * 0.24, sp.w * 0.98, k)
    local sh = utils.lerp(sp.h * 0.94, sp.h * 0.24, k)
    return sx, sy, sw, sh
end

-- 画一截**躺着**的木头：主体 + 受光边 + 背光边 + 两端带年轮的切口
--   亮边 / 暗边成对出现是「一截圆木」的读法；两端切口是「被锯断」的读法。
local function paintLyingLog(pool, i, parent, rect, sp, palette, baseKey)
    local cell = state.cellSize or 1
    local k = utils.clamp(sp.alongX or 0, 0, 1)
    local cap = cell * LOG_CAP

    i = paint(pool, i, parent, rect, sp.cx, sp.cy, sp.w, sp.h,
              palette.logSide, 255, baseKey)
    -- 背光暗边（横躺 = 贴地那一条；竖躺 = 右侧那条）
    local sx, sy, sw, sh = shadeEdgeRect(sp, k)
    i = paint(pool, i, parent, rect, sx, sy, sw, sh,
              palette.logEnd, 190, baseKey + 0.05)
    -- 受光亮边
    local ex, ey, ew, eh = litEdgeRect(sp, k)
    i = paint(pool, i, parent, rect, ex, ey, ew, eh,
              palette.logTop, 255, baseKey + 0.1)
    -- 两端的切口：外圈深色 + 内芯年轮（一眼看出「这是被锯断的木头」）
    for _, s in ipairs({ -1, 1 }) do
        if k >= 0.5 then
            local ex2 = sp.cx + s * (sp.w / 2 - cap / 2)
            i = paint(pool, i, parent, rect, ex2, sp.cy, cap, sp.h,
                      palette.logEnd, 255, baseKey + 0.2)
            i = paint(pool, i, parent, rect, ex2, sp.cy, cap * 0.42, sp.h * 0.44,
                      palette.logTop, 255, baseKey + 0.25)
        else
            local ey2 = sp.cy + s * (sp.h / 2 - cap / 2)
            i = paint(pool, i, parent, rect, sp.cx, ey2, sp.w, cap,
                      palette.logEnd, 255, baseKey + 0.2)
            i = paint(pool, i, parent, rect, sp.cx, ey2, sp.w * 0.42, cap * 0.42,
                      palette.logTop, 255, baseKey + 0.25)
        end
    end
    return i
end

-- 画一截**立着**的无叶木头：根部土堆 + 柱身 + 竖向受光 + 顶端亮切面
--   反过来说，躺姿有的「两端切口」它一个都没有 ——
--   它只有**一端**接着地、**一端**朝天，这正是「立着」的读法。
local function paintStandingTrunk(pool, i, parent, rect, sp, palette, baseKey)
    local cell = state.cellSize or 1
    local bw, bh = sp.w, sp.h
    local footY = sp.cy - bh / 2

    -- ① 根部「扎进土里」：一小撮土堆 + 一条更暗的压边
    i = paint(pool, i, parent, rect, sp.cx, footY + cell * 0.025,
              cell * TRUNK_FOOT, cell * 0.11, palette.logStandFoot, 205, baseKey - 0.05)
    i = paint(pool, i, parent, rect, sp.cx, footY + cell * 0.075,
              bw * 1.55, cell * 0.05, palette.logStandFoot, 255, baseKey - 0.04)
    -- ② 柱身
    i = paint(pool, i, parent, rect, sp.cx, sp.cy, bw, bh,
              palette.logStandSide, 255, baseKey)
    -- ③ 竖向受光的那条窄边（柱子是竖的 → 高光也竖着，与躺姿的横亮边正好相反）
    local ex, ey, ew, eh = litEdgeRect(sp, 0)
    i = paint(pool, i, parent, rect, ex, ey, ew, eh,
              palette.logStandEdge, 255, baseKey + 0.1)
    -- ④ 背光暗边（右侧）—— 和亮边配成一对，柱子才有圆柱感
    local sx, sy, sw, sh = shadeEdgeRect(sp, 0)
    i = paint(pool, i, parent, rect, sx, sy, sw, sh,
              palette.logStandFoot, 190, baseKey + 0.12)
    -- ⑤ 顶端的新鲜切面：外圈亮 + 内芯更亮（「朝天的那一刀」）
    local capH = cell * TRUNK_CAP
    local capY = sp.cy + bh / 2 - capH / 2
    i = paint(pool, i, parent, rect, sp.cx, capY, bw, capH,
              palette.logStandEdge, 255, baseKey + 0.2)
    i = paint(pool, i, parent, rect, sp.cx, capY, bw * 0.52, capH * 0.46,
              palette.logStandCap, 255, baseKey + 0.25)
    return i
end

-- ================================================================
-- ★ 石头 → 图腾柱（第 40 批；第 42 批重做保真度 + 遮挡角色）
--   用户给了一根「图腾柱」的图元拟合导出（1043 个旋转图元），要求用它替代石头。
--   画法与小人同一套：图元 = 纯色矩形 + 染色 + 绕自身中心转 Z，全部从池子里取。
--
--   ★ 四件必须知道的事：
--     ① **笔数**：1043 笔 × 72 块石头 = 7 万多个控件，真机必崩。数据在导出时
--        就砍到 330 笔/根（见 rockPrims.lua 与 _tmp/gen_rock_prims.mjs）。
--     ② **总预算**：一屏能看见 2 ~ 34 根（中位 10 根），所以还要按
--        config.DEFAULT_PILLAR_BUDGET 摊：每根配额 = 预算 / 可见根数。
--        配额不够就先丢辉光、再丢细节；连轮廓都摊不到 → 退化成两块纯色矩形。
--     ③ **按可视窗裁剪**：柱子和地形一样只画看得见的那一窗（多留 2 格）。
--        石头是**不可通行格** —— 柱子没画出来就等于一堵看不见的墙，所以窗口一变
--        必须重铺（由 M.ensureTerrain 在换窗那一帧调 M.repaintRockPillars）。
--     ④ **只改画法**：判定还是「一格不可通行」，柱子画多高都不影响规则。
--
--   ★ 深度：每根柱子的所有笔共用一个深度键（行号），同一根内按笔画顺序排 ——
--     这样近处的柱子整根压在远处的柱子上面，不会出现「半根在后面半根在前面」。
--   ★★★ 柱子挡东西（第 42 批起；第 44 批定稿）：石头层拆成**前后两层**
--     （见 game.ensureContainers）—— 该挡东西的柱子画进 containerRockFront
--     （在树木 / 小人**之上**），其余全在 containerRock（都在下面）。
--     ★ 判据 = **纯屏幕矩形相交**（见 rockIsFront）：柱子更靠下（更近）+ 两个矩形相交。
--       所以「挡多少」天然等于「石柱轮廓 ∩ 物体轮廓」，不是「整根柱子跳出来」：
--         小人站柱子正上方一格 → 柱顶到腰，只挡下半身，头肩照常露出来；
--         木头滚到柱子正上方一格 → 柱子只啃掉它朝镜头那半条边。
--     ★ 遮挡物不只有小人：树 / 倒木 / 木筏 也各自有一条矩形（见 buildOccluders），
--       所以「树滚到柱子后面」同样会被柱子挡住。
--     ⚠️ 前层永远压在后层之上，所以「哪根柱子进前层」= 「它压到后层所有东西头上」，
--       范围必须锁死在「自己脚下 + 上方一格」。第 42 批按行号一刀切（半屏柱子一起换层），
--       用户看到的就是「所有柱子的样子都变了」。
--     ★ 只在「有东西换格 / 确有柱子会换边」时才重铺（见 M.ensureRockSplit）——
--       每走一步就重铺几千个控件，真机必卡。
-- ================================================================
local ROCK_WIN_MARGIN = 2          -- 柱子比石块高，窗口外多留一格防止「脚下那根没画」

local function rockPillarOn()
    if not rockPrims then return false end
    local v = state.rockPillar
    if v == nil then return (tonumber(config.DEFAULT_ROCK_PILLAR) or 1) > 0 end
    if v == true then return true end
    if v == false then return false end
    return (tonumber(v) or 0) > 0
end

local function rockGlowOn()
    local v = state.rockPillarGlow
    if v == nil then return (tonumber(config.DEFAULT_PILLAR_GLOW) or 1) > 0 end
    if v == true then return true end
    if v == false then return false end
    return (tonumber(v) or 0) > 0
end

local function rockOccludeOn()
    local v = state.pillarOcclude
    if v == nil then return (tonumber(config.DEFAULT_PILLAR_OCCLUDE) or 1) > 0 end
    if v == true then return true end
    if v == false then return false end
    return (tonumber(v) or 0) > 0
end

-- 一根柱子：把一组图元笔（7 个字段/笔）铺到池子里，最多铺 maxN 笔
--   单位全部是「柱高」—— nx/ny 是中心点偏移（ny 从柱脚往上），nw/nh 是尺寸
--   返回 新游标, 实际铺了几笔
local function paintPillarStrokes(pool, ri, parent, rect, cx, baseY, hpx, key, arr, maxN)
    local k, n = 1, #arr
    local left = tonumber(maxN) or n
    local used = 0
    while k + 6 <= n and used < left do
        local item = poolGet(pool, ri, parent, rect)
        if not item then return ri, used end
        local c = item.c
        item.key = key                     -- 供 restackWorld 按行号排层
        utils.setVisible(c, true)
        utils.setSize(c, arr[k + 2] * hpx, arr[k + 3] * hpx)
        utils.setPosition(c, cx + arr[k] * hpx, baseY + arr[k + 1] * hpx)
        utils.setRotation(c, arr[k + 4])
        utils.setAlpha(c, string.format("%06X", math.floor(arr[k + 5] or 0)), arr[k + 6] or 255)
        ri = ri + 1
        k = k + 7
        used = used + 1
    end
    return ri, used
end

-- ================================================================
-- ★★★ 第 44 批：柱子挡不挡东西，只看**两个屏幕矩形相不相交**。
--   柱子矩形：[脚线, 脚线 + 柱高] × [中心 ± 柱身半宽]
--   物体矩形：[脚线, 脚线 + 物体高] × [中心 ± 物体半宽]
--   条件只有两条：① 柱子**更靠下**（离镜头更近）；② 两个矩形相交。
--   于是「挡多少」天然等于「石柱轮廓 ∩ 物体轮廓」——
--     小人站在柱子正上方一格：柱顶到小人腰以上，只挡住下半身，头肩照常露出来；
--     木头滚到柱子正上方一格：柱子只啃掉它朝镜头那半条边。
--   第 42 批按「行号比小人大」一刀切（柱子整根跑前面）、第 43 批按「同列」特判，
--   都在描述「谁该挡谁」这个人肉规则；这一批改成纯几何，规则只有一条。
--
--   ★ 为什么要给每个物体配一个矩形，而不是只给小人：树木层固定在小人之下，
--     柱子要挡树就只能整根进前层 —— 但**只有真的和那棵树相交的柱子**才该进，
--     否则一根柱子跑到前面会把一整片树全压住（第 42 批的老毛病）。
--   ★ 前层永远压在后层之上，所以进前层的柱子也会压到后层里别的东西；
--     但矩形相交已经把范围锁在「自己脚下这一格 + 上方一格」，不会波及远处。
-- ================================================================
local function pillarBox(rk)
    local cell = state.cellSize or 1
    local hpx = cell * (tonumber(config.DEFAULT_PILLAR_H) or 1.9)
    local bodyW = (rockPrims and tonumber(rockPrims.BODY_W)) or 0.2564
    return cellCenterX(rk.c), groundY(rk.c, rk.r), hpx * bodyW, hpx   -- cx, foot, 半宽, 高
end

-- 收集「柱子可能挡住的东西」的屏幕矩形（小人 / 树 / 倒木 / 木筏）
--   ★ 只取**看得见的主体**，不取整个控件矩形：真树的素材控件是 1.82 格见方、
--     中间一大圈透明留白，按控件算会让两列外的柱子也翻层。
local function buildOccluders()
    if not state.cellSize then return {} end
    local cell = state.cellSize
    local list = {}
    local function add(cx, foot, w, h)
        if w and h and h > 0 then
            list[#list + 1] = { cx = cx, foot = foot, w = w, h = h }
        end
    end
    -- 小人（立绘 / 图元都用 ART_FIT.player 这套尺寸）
    local p = state.player
    if p then
        local fit = (config.DEFAULT_ART_FIT or {}).player or { w = 0.751, h = 1.126 }
        add(cellCenterX(p.c), groundY(p.c, p.r), cell * (tonumber(fit.w) or 0.751),
            cell * (tonumber(fit.h) or 1.126))
    end
    -- 树：有叶子的按树冠算（约 0.95 × 1.35 格），无叶树干按真身算
    for _, tr in ipairs(state.trees or {}) do
        local base = entBaseY(tr.c, tr.r, tr.z)
        if tr.bare then
            local sp = standingShape(tr.c, tr.r, tr.z)
            add(sp.cx, sp.cy - sp.h * 0.5, sp.w, sp.h)
        else
            add(cellCenterX(tr.c), base - cell * 0.05, cell * 0.95, cell * 1.35)
        end
    end
    -- 倒木 / 木筏：用画它们的那个形态表，矩形和画出来的一模一样
    for _, lg in ipairs(state.logs or {}) do
        local sp = lyingShape(lg.c, lg.r, lg.dir, lg.z)
        add(sp.cx, sp.cy - sp.h * 0.5, sp.w, sp.h)
    end
    for _, rf in ipairs(state.rafts or {}) do
        local sp = lyingShape(rf.c, rf.r, rf.dir, rf.z)
        add(sp.cx, sp.cy - sp.h * 0.5, sp.w, sp.h)
    end
    return list
end

-- 这根柱子要不要画进前层（挡住上面那些物体）？
local function rockIsFront(rk, occ)
    if not occ or #occ == 0 then return false end
    local cx, foot, halfW, hpx = pillarBox(rk)
    for i = 1, #occ do
        local o = occ[i]
        if foot < o.foot then                                  -- ① 柱子更靠下 = 更近
            if math.abs(cx - o.cx) < (halfW + o.w * 0.5) then   -- ② 横向相交
                if (foot < o.foot + o.h) and (o.foot < foot + hpx) then  -- ③ 纵向相交
                    return true
                end
            end
        end
    end
    return false
end

-- 「变了没」的缓存键：所有遮挡物体的矩形拼成字符串
--   ★ 比整格坐标更严：木头滚一格、树被推倒、小人换格，这里都会变。
local function occluderKey(occ)
    if not occ or #occ == 0 then return "" end
    local t = {}
    for i = 1, #occ do
        local o = occ[i]
        t[i] = string.format("%.0f,%.0f,%.0f", o.cx, o.foot, o.h)
    end
    return table.concat(t, ";")
end

-- 重铺整个石头层（自成一个函数：rebuildObjects / 换可视窗 / 小人换格 三处都要调）
local function paintRockPillars(palette)
    local pool, fpool = state.rockCtrls, state.rockFrontCtrls
    if not pool or not fpool then return false end
    local poolBefore = #pool + #fpool
    local parent, fparent = layerRock(), layerRockFront()
    local rect = rectSlot()
    local cell = state.cellSize or 1
    local rocks = state.rocks or {}
    local bi, fi = 1, 1                -- 后层 / 前景层 两个池各自的游标
    local drawn, flat, frontN = 0, 0, 0
    local sides = state.rockSideTbl or {}
    state.rockSideTbl = sides
    local occl = rockOccludeOn()
    local occ = occl and buildOccluders() or nil
    -- ★★ 第 43 批：**全部**柱子（含可视窗外的）的「前 / 后」都先算一遍。
    --   之前只在绘制循环里给窗口内那几根写 sides[]，窗口外那六十多根永远是 nil，
    --   而 M.ensureRockSplit 拿 `sides[i] ~= want` 比 → nil 和 false 不等 →
    --   小人每挪一格都判「有柱子换边」，白白重铺几千个控件。
    for i = 1, #rocks do
        sides[i] = rockIsFront(rocks[i], occ)
    end
    if rockPillarOn() then
        local R = rockPrims
        local hpx = cell * (tonumber(config.DEFAULT_PILLAR_H) or 1.9)
        local glowOn = rockGlowOn()
        local silN = R.SIL_N or 0
        local fullN = (R.BASE_N or 0) + (glowOn and (R.GLOW_N or 0) or 0)
        local win = state.terrainWin or terrainWindow()
        local c0, c1 = win.c0 - ROCK_WIN_MARGIN, win.c1 + ROCK_WIN_MARGIN
        local r0, r1 = win.r0 - ROCK_WIN_MARGIN, win.r1 + ROCK_WIN_MARGIN

        -- ① 先数一遍可视窗内有几根 —— 预算要按总量摊，所以必须两趟
        local vis = {}
        for i, rk in ipairs(rocks) do
            if rk.c >= c0 and rk.c <= c1 and rk.r >= r0 and rk.r <= r1 then
                vis[#vis + 1] = i
            end
        end
        local nVis = #vis
        -- ② 每根配额（见文件头 ②）
        local per = fullN
        local budget = tonumber(config.DEFAULT_PILLAR_BUDGET) or 0
        if nVis > 0 and budget > 0 then
            per = math.floor(budget / nVis)
            if per > fullN then per = fullN end
            if per < 0 then per = 0 end
        end

        for _, i in ipairs(vis) do
            local rk = rocks[i]
            local cx = cellCenterX(rk.c)
            local foot = groundY(rk.c, rk.r)
            local key = objKey(rk.r, SUB_ROCK)
            -- 前 / 后：见 rockIsFront（柱子的屏幕矩形和谁相交，就挡谁）
            local front = rockIsFront(rk, occ)
            local tp, tparent
            if front then
                tp, tparent = fpool, fparent
            else
                tp, tparent = pool, parent
            end
            local cur = front and fi or bi

            if per >= silN and per > 0 then
                local left = per
                local r2, used = paintPillarStrokes(tp, cur, tparent, rect, cx, foot, hpx, key, R.BASE, left)
                cur = r2
                left = left - used
                if left > 0 and glowOn then
                    local r3 = paintPillarStrokes(tp, cur, tparent, rect, cx, foot, hpx, key, R.GLOW, left)
                    cur = r3
                end
            else
                -- ③ 退化：远到预算摊不出轮廓了 → 两块纯色矩形（柱身 + 柱顶亮边）。
                --   ★ 宁可丑也不能不画：石头是不可通行格，看不见就是隐形墙。
                local bodyW = hpx * (R.BODY_W or 0.26)
                local sideHex = R.FLAT and string.format("%06X", R.FLAT) or palette.rockSide or "7F4B34"
                local topHex = R.FLAT_TOP and string.format("%06X", R.FLAT_TOP) or palette.rock1Top or "97593E"
                local r4 = paint(tp, cur, tparent, rect, cx, foot + hpx * 0.5, bodyW, hpx,
                                 sideHex, 255, key)
                cur = r4
                paint(tp, cur, tparent, rect, cx, foot + hpx * 0.94, bodyW * 0.94, hpx * 0.12,
                      topHex, 255, key)
                cur = cur + 1
                flat = flat + 1
            end

            if front then fi = cur else bi = cur end
            -- sides[i] 在函数开头已经对**全部**柱子算过了（见那里的说明），这里不再重复写
            if front then frontN = frontN + 1 end
            drawn = drawn + 1
        end
    else
        -- 旧画法（rockPillar = -1 或 rockPrims 没加载）：两块纯色矩形
        for i, rk in ipairs(rocks) do
            local hh = tonumber(rk.h) or config.DEFAULT_H_ROCK1
            local x = cellCenterX(rk.c)
            local base = groundY(rk.c, rk.r)
            local hex = (hh >= config.DEFAULT_H_ROCK2 - 0.01) and palette.rock2Top or palette.rock1Top
            bi = paint(pool, bi, parent, rect, x, base + hh * cell / 2, cell * 0.84, hh * cell,
                       palette.rockSide, 255, objKey(rk.r, SUB_ROCK))
            bi = paint(pool, bi, parent, rect, x, base + hh * cell - cell * 0.055,
                       cell * 0.68, cell * 0.11, hex, 255, objKey(rk.r, SUB_ROCK + 0.1))
            sides[i] = false
        end
        fi = 1
    end

    poolTrim(pool, bi - 1)
    state.rockUsed = bi - 1
    poolTrim(fpool, fi - 1)
    state.rockFrontUsed = fi - 1
    state.rockDrawn = drawn
    state.rockFlat = flat
    state.rockFrontDrawn = frontN
    state.rockSplitKey = occluderKey(occ)
    return (#pool + #fpool) > poolBefore   -- 池子扩容了（**不再用它决定要不要重排**，见调用处）
end

-- 换可视窗时重铺柱子（M.ensureTerrain 调；见上面 ③）
function M.repaintRockPillars(palette)
    if not state.cellSize then return false end
    return paintRockPillars(palette or utils.resolvePalette(state.levelConfig))
end

-- ================================================================
-- ★ 逐帧（纯算术，不碰控件）：小人换格 / 木头滚动 / 树被推倒之后，
--   若有柱子要「从物体前面挪到后面」（或反过来），才重铺石头层。
--   判据见 rockIsFront（纯屏幕矩形相交）。
--   ★ 为什么不每步都重铺：一次重铺 = 几百到几千次控件调用，走一步就闪一下。
--     按现在的判据，**一根柱子只有在「有东西走到它正上方那一格」时才换层** ——
--     一整张图通常一次都不会触发，所以石头层实际是「建好就不动」。
--   ★★ 第 43 批：重铺之后**必须无条件 restackWorld**。柱子进哪个池由物体位置决定，
--     一换边「哪根柱子占哪个池槽」就整体挪位；池子没扩容时不动 sibling 顺序，
--     旧顺序和新分配对不上 → 柱子互相遮挡的先后乱掉。
--     一次 restack 只是几千次 SetAsLastSibling，比重铺便宜得多。
-- ================================================================
function M.ensureRockSplit()
    if not state.cellSize or not state.rocks then return false end
    if not rockOccludeOn() or not rockPillarOn() then return false end
    local occ = buildOccluders()
    local key = occluderKey(occ)
    if state.rockSplitKey == key then return false end
    local rocks = state.rocks
    local sides = state.rockSideTbl or {}
    local changed = false
    for i = 1, #rocks do
        if sides[i] ~= rockIsFront(rocks[i], occ) then changed = true break end
    end
    if not changed then
        state.rockSplitKey = key        -- 物体挪了但没有柱子换边：只记一下，不动控件
        return false
    end
    paintRockPillars(utils.resolvePalette(state.levelConfig))
    M.restackWorld()
    return true
end

-- ================================================================
-- ★ 物体层：树根 → 倒下的树 → 石头 → 树木 → 终点旗
--   world 每次发生结构变化后重建（对象池复用，控件不销毁）。
--   2.5D 下所有物体都站在「脚线」（cellFootY）上，并且每个都带一格深度键 ——
--   同一行内由下到上排，跨行则由行号决定谁压谁（见 restackWorld）。
--   ★ 一切物体都只占一格（1×1）：立着的树 1 格高、倒下的树 0.5 格厚、
--     树根 0.25 格高 —— 身高差全部体现在「控件高度」上。
--   ★ 物体池（`state.objectCtrls`，全是纯色矩形）额外承担「被推立起来的树干」：
--     它是 runtime 才出现的形态、没有对应素材，画法与倒下的树同源（见本函数 ④）。
-- ================================================================
function M.rebuildObjects()
    local data = state.levelConfig or {}
    local palette = utils.resolvePalette(data)
    -- ★ 第 22 批：四个固定图层各画各的，池子也按层分开（混池会把控件画到别的层去）。
    local pool = state.objectCtrls                 -- 地面层：树桩 / 老树根
    local logPool = state.logCtrls                 -- 树木层：倒木 / 木筏 / 被推立的树干
    local parent = layerGround()                   -- 树桩与接触阴影的父节点
    local parentTree = layerTree()
    local li = 1                                   -- 木头池游标（石头池已独立，见 paintRockPillars）
    local rect = rectSlot()
    local treeSlot = makeSlot(state.treePrefabId)
    local cell = state.cellSize
    local shadowAlpha = config.DEFAULT_OBJ_SHADOW_ALPHA or 0
    local shadowHex = palette.shadowLand or "33421F"    -- ★ nil 会被 hexToColorA 当成纯白
    local shSlot = shadowSlot()                        -- 椭圆（拿不到就退回矩形）
    local si = 1
    local i = 1

    local function keyOf(r, sub, stack) return objKey(r, sub, stack) end

    -- 脚下的接触阴影：让物体真的「贴」在地上，而不是浮着
    --   ★ 单独一个池（state.shadowCtrls）：椭圆的图源在建控件时就要打上，
    --     和物体池的纯色矩形不是同一种控件，混在一个池里迟早画串。
    local function shadow(cx, baseY, w, r, stack)
        if shadowAlpha <= 0 then return end
        si = paint(state.shadowCtrls, si, parent, shSlot, cx, baseY - cell * 0.005,
                   w, cell * 0.16, shadowHex, shadowAlpha, keyOf(r, SUB_SHADOW, stack))
    end

    -- ★ 「倒 / 立」过渡期间，**终点格**上的那根真实木头这一帧不画：
    --   它由过渡代理逐帧画插值形态（见 M.paintObjProxy），
    --   两边同时画就会出现「两个自己叠在一起」。
    local animTo = state.objAnimActive and state.objAnimTo or nil
    local function hideAnimAt(c, r)
        return animTo ~= nil and animTo.c == c and animTo.r == r
    end

    -- ① 树桩（MExp 语义：桩子是**地块属性**，树推倒后原地露出来）
    --   ★ 判定：这一格是树桩位，且**没有立着的木头**（type 1/2）压在上面。
    --     树站着时树干正好挡住桩子 —— 原版 _hasWood() 也是这么判的。
    --   ★ 高度恒 1 层：地表已经被 drawH 减掉这一层，桩子补回来正好顶到逻辑顶面，
    --     所以小人踩上去脚不会陷进去，也不会浮空。
    --   ★ 只画可视窗附近的（整图最多 41 个桩位，隔一屏画一次，控件数可控）。
    local win = state.terrainWin or terrainWindow()
    local stumpMargin = 3
    local stumpH = zVis() * cell                       -- 树桩恒 1 层（= DEFAULT_Z_VIS）
    local stumpW = cell * (config.DEFAULT_STUMP_W or 0.34)
    local stumpTop = cell * (config.DEFAULT_STUMP_TOP or 0.05)
    local woodAt = {}
    for _, tr in ipairs(state.trees or {}) do
        woodAt[tr.c .. ":" .. tr.r] = true
    end
    for _, st in ipairs(state.stumps or {}) do
        local near = st.c >= (win.c0 - stumpMargin) and st.c <= (win.c1 + stumpMargin)
                 and st.r >= (win.r0 - stumpMargin) and st.r <= (win.r1 + stumpMargin)
        if near and not woodAt[st.c .. ":" .. st.r] then
            local bx = cellCenterX(st.c)
            local base = groundY(st.c, st.r)          -- 桩子根部 = 画出来的地表
            i = paint(pool, i, parent, rect, bx, base + stumpH * 0.5,
                      stumpW, stumpH, palette.rootRing, 255,
                      keyOf(st.r, SUB_ROOT))
            -- 受光的那条窄边（光从左上来），圆柱感
            i = paint(pool, i, parent, rect, bx - stumpW * 0.22, base + stumpH * 0.5,
                      stumpW * 0.28, stumpH * 0.92, palette.rootTop, 190,
                      keyOf(st.r, SUB_ROOT + 0.1))
            -- 锯断的切面：一圈浅色（只占顶部一点，别盖住整根）
            i = paint(pool, i, parent, rect, bx, base + stumpH - stumpTop * 0.5,
                      stumpW, stumpTop, palette.rootTop, 255,
                      keyOf(st.r, SUB_ROOT + 0.2))
        end
    end

    -- ①-b 老版「预置树根」：只有编辑器自制关的老存档才会有（真实地图恒空）
    for _, rt in ipairs(state.roots) do
        local bx, base = cellCenterX(rt.c), groundY(rt.c, rt.r)
        i = paint(pool, i, parent, rect, bx, base + cell * 0.035,
                  cell * 0.74, cell * 0.07, palette.rootRing, 255, keyOf(rt.r, SUB_ROOT))
        i = paint(pool, i, parent, rect, bx, base + cell * 0.14,
                  cell * 0.60, cell * 0.21, palette.rootTop, 255, keyOf(rt.r, SUB_ROOT + 0.1))
    end

    -- ② 躺着的木头（含「压高」的：z 比地面高就往上摞）
    --    东西躺（A/D）＝长 1 格 × 厚 0.5 格；南北躺（W/S）＝宽 0.5 格 × 长 1 格
    for _, lg in ipairs(state.logs) do
        if not hideAnimAt(lg.c, lg.r) then
            local sp = lyingShape(lg.c, lg.r, lg.dir, lg.z)
            shadow(sp.cx, entBaseY(lg.c, lg.r, lg.z), cell * 0.80, lg.r,
                   stackOf(lg.c, lg.r, lg.z))
            li = paintLyingLog(logPool, li, parentTree, rect, sp, palette,
                               keyOf(lg.r, SUB_LOG, stackOf(lg.c, lg.r, lg.z)))
        end
    end

    -- ③ 木筏（两根木头叠出来的）：一根顺着躺 + 一根横着压在上面
    --    ★ 画法必须和单根木头**一眼分得开**，否则玩家不知道「这已经能撑了」：
    --      主木顺着躺向，中间再压一根**横的短木**（略高一点），读作「捆在一起」。
    for _, rf in ipairs(state.rafts) do
        local sp = lyingShape(rf.c, rf.r, rf.dir, rf.z)
        local stack = stackOf(rf.c, rf.r, rf.z)
        shadow(sp.cx, entBaseY(rf.c, rf.r, rf.z), cell * 0.86, rf.r, stack)
        li = paintLyingLog(logPool, li, parentTree, rect, sp, palette, keyOf(rf.r, SUB_RAFT, stack))
        local crossH = cell * LOG_THICK * 0.82
        local crossW = cell * 0.94
        if sp.alongX == 1 then
            li = paint(logPool, li, parentTree, rect, sp.cx, sp.cy + cell * 0.10,
                       crossH, crossW, palette.logStandSide, 255,
                       keyOf(rf.r, SUB_RAFT + 0.2, stack))
            li = paint(logPool, li, parentTree, rect, sp.cx, sp.cy + cell * 0.10 + crossW * 0.36,
                       crossH, crossH * 0.30, palette.logStandEdge, 255,
                       keyOf(rf.r, SUB_RAFT + 0.3, stack))
        else
            li = paint(logPool, li, parentTree, rect, sp.cx, sp.cy + cell * 0.10,
                       crossW, crossH, palette.logStandSide, 255,
                       keyOf(rf.r, SUB_RAFT + 0.2, stack))
            li = paint(logPool, li, parentTree, rect, sp.cx - crossW * 0.36, sp.cy + cell * 0.10,
                       crossH * 0.30, crossH, palette.logStandEdge, 255,
                       keyOf(rf.r, SUB_RAFT + 0.3, stack))
        end
    end

    -- ④ 石头（不可通行格）：第 40 批起画成**图腾柱**（见上方 paintRockPillars）
    --   ★ 接触阴影仍然按「一格」画在脚下 —— 柱子再高，踩地的还是那一格。
    for _, rk in ipairs(state.rocks) do
        shadow(cellCenterX(rk.c), groundY(rk.c, rk.r), cell * 0.8, rk.r, 0)
    end
    paintRockPillars(palette)

    -- ⑤ 树木（真树 1 格高 / 无叶树干 1 格高）
    --    ★ 被推立起来的树干（tr.bare）**没有树冠**：它就是倒下的那根木头竖起来了，
    --      造型和 ② 的倒木同源，所以永远走**纯色池**（套素材会变回一棵假树）。
    local treeArt = slotUsesArt(state.treeCtrls, parentTree, treeSlot)
    local ti = 1
    for _, tr in ipairs(state.trees) do
        local x = cellCenterX(tr.c)
        local base = entBaseY(tr.c, tr.r, tr.z)
        local stack = stackOf(tr.c, tr.r, tr.z)
        shadow(x, base, cell * 0.72, tr.r, stack)
        if tr.bare then
            if not hideAnimAt(tr.c, tr.r) then
                li = paintStandingTrunk(logPool, li, parentTree, rect, standingShape(tr.c, tr.r, tr.z),
                                        palette, keyOf(tr.r, SUB_TREE, stack))
            end
        elseif treeArt then
            local fit = (config.DEFAULT_ART_FIT or {}).tree or { w = 1.82, h = 1.82, dy = 0.5 }
            ti = paint(state.treeCtrls, ti, parentTree, treeSlot,
                       x, base + (fit.dy or 0) * cell,
                       cell * (fit.w or 1), cell * (fit.h or 1), nil, nil,
                       keyOf(tr.r, SUB_TREE, stack))
        else
            ti = paint(state.treeCtrls, ti, parentTree, treeSlot, x, base + cell * 0.31,
                       cell * 0.22, cell * 0.62, palette.treeTrunk, 255,
                       keyOf(tr.r, SUB_TREE, stack))
            ti = paint(state.treeCtrls, ti, parentTree, treeSlot, x, base + cell * 0.72,
                       cell * 0.78, cell * 0.56, palette.treeCanopy, 255,
                       keyOf(tr.r, SUB_TREE + 0.1, stack))
        end
    end
    poolTrim(state.treeCtrls, ti - 1)
    state.treeUsed = ti - 1

    -- ⑥ 木牌（MExp 的「终点」就是一块写着 You win! 的牌子）
    --    柱 + 板；终点牌的板子换成金色，并且顶上插一面小旗 ——
    --    玩家得在很远的地方就认出「那块就是要读的」。
    local gi = 1
    for _, sg in ipairs(state.signs or {}) do
        local x = cellCenterX(sg.c)
        local base = entBaseY(sg.c, sg.r, sg.z)
        local stack = stackOf(sg.c, sg.r, sg.z)
        local sh = cell * (config.DEFAULT_SIGN_H or 0.72)
        local board = (sg.goal and palette.goalFlag) or palette.sand
        shadow(x, base, cell * 0.42, sg.r, stack)
        gi = paint(state.goalCtrls, gi, parentTree, rect, x, base + sh * 0.5,
                   cell * 0.11, sh, palette.goalPole, 255,
                   keyOf(sg.r, SUB_SIGN, stack))                       -- 柱子
        gi = paint(state.goalCtrls, gi, parentTree, rect, x + cell * 0.04, base + sh * 0.78,
                   cell * 0.46, cell * 0.30, board, 255,
                   keyOf(sg.r, SUB_SIGN + 0.1, stack))                 -- 牌子
        gi = paint(state.goalCtrls, gi, parentTree, rect, x + cell * 0.04, base + sh * 0.78,
                   cell * 0.34, cell * 0.05, palette.goalPole, 210,
                   keyOf(sg.r, SUB_SIGN + 0.2, stack))                 -- 板上的两道「字迹」
        gi = paint(state.goalCtrls, gi, parentTree, rect, x + cell * 0.04, base + sh * 0.64,
                   cell * 0.30, cell * 0.05, palette.goalPole, 210,
                   keyOf(sg.r, SUB_SIGN + 0.2, stack))
        if sg.goal then
            gi = paint(state.goalCtrls, gi, parentTree, rect, x - cell * 0.16, base + sh * 1.06,
                       cell * 0.30, cell * 0.19, palette.goalFlag, 255,
                       keyOf(sg.r, SUB_GOAL, stack))
        end
    end

    -- ⑦ 老版「终点格」的旗子：只有编辑器自制关（没有木牌）才画
    if state.goal and #(state.signs or {}) == 0 then
        local gx = cellCenterX(state.goal.c)
        local gfoot = groundY(state.goal.c, state.goal.r)
        gi = paint(state.goalCtrls, gi, parentTree, rect, gx, gfoot + cell * 0.07,
                   cell * 0.92, cell * 0.14, palette.goalFlag, 90, keyOf(state.goal.r, SUB_GOAL))
        gi = paint(state.goalCtrls, gi, parentTree, rect, gx - cell * 0.20, gfoot + cell * 0.62,
                   cell * 0.08, cell * 1.24, palette.goalPole, 255,
                   keyOf(state.goal.r, SUB_GOAL + 0.1))
        gi = paint(state.goalCtrls, gi, parentTree, rect, gx + cell * 0.08, gfoot + cell * 1.02,
                   cell * 0.50, cell * 0.32, palette.goalFlag, 255,
                   keyOf(state.goal.r, SUB_GOAL + 0.2))
    end
    poolTrim(state.goalCtrls, gi - 1)
    state.goalUsed = gi - 1

    poolTrim(pool, i - 1)
    state.objectUsed = i - 1
    -- ★ 第 40 批：石头池的收尾在 paintRockPillars 里（它两处都会被调：重建物体 / 换可视窗）
    poolTrim(logPool, li - 1)
    state.logUsed = li - 1
    poolTrim(state.shadowCtrls, si - 1)
    state.shadowUsed = si - 1

    -- ⑧ 「倒 / 立」的过渡代理（不在动画期间就自动清空自己）
    M.paintObjProxy()

    -- ⑨ 全局重排：地块 → 物体 → 小人，全部按深度键点名顺序
    M.restackWorld()
end

-- ================================================================
-- ★ 木头「倒 / 立」的过渡动画（表现层）
--   为什么非要有它：两态切换如果只是「瞬间换一张图」，玩家只会看到有东西闪了一下；
--   给它一段过程，两种动作在观感上才彻底分开 ——
--     倒下 = 靠**回弹过冲**甩过头再砸实（咚），落地补一圈大扬尘；
--     立起 = 过冲很小、稳稳顶上去（咔），根部补一圈小扬尘。
--   这就是「对比更明显」最有效的一招：**不只是长得不一样，动起来也不一样**。
--
--   做法：不碰世界里的真实木头，而是**另起一个小池**（objProxyCtrls）当「过渡代理」，
--   逐帧按插值形态画一帧木头；同时让真实木头在**终点格**上这一帧不画（hideAnimAt）。
--   动画一结束就清标志 → 下一次 rebuildObjects 恢复正式绘制。
--   ★ 代理挂在**世界容器**里（不是 fx 层）：它必须参与「近处压远处」的深度排序。
-- ================================================================

-- 回弹曲线：o = 过冲量（1 = 不过冲，退化成普通缓出）
local function easeBack(k, o)
    local c1 = ((tonumber(o) or 1) - 1) * 5
    local c3 = c1 + 1
    local t = k - 1
    return 1 + c3 * t * t * t + c1 * t * t
end

-- 倒下的「甩过头」比立起更明显 —— 两种动作的手感刻意不一样
local function animOvershoot(kind)
    if kind == "knock" then
        return tonumber(config.DEFAULT_OBJ_ANIM_OVERSHOOT) or 1.35
    end
    return 1.15
end

-- 起手式：按 world.step 给出的动作，算出这一趟从什么形态变到什么形态
function M.setObjectAnim(act)
    state.objAnimActive = false
    state.objAnimFrom, state.objAnimTo = nil, nil
    if type(act) ~= "table" then return end
    local kind = act.kind
    if kind ~= "knock" and kind ~= "raise" and kind ~= "slide" then return end
    local from, to = act.animFrom, act.animTo
    if not from or not to then return end

    local function shapeOf(spec)
        if spec.stand then return standingShape(spec.c, spec.r, spec.z) end
        return lyingShape(spec.c, spec.r, spec.dir, spec.z)
    end

    state.objAnimFrom = shapeOf(from)
    state.objAnimTo   = shapeOf(to)
    state.objAnimKind = kind
    state.objAnimT    = 0
    state.objAnimDur  = config.DEFAULT_OBJ_ANIM_TIME or 0.22
    state.objAnimActive = state.objAnimDur > 0
    if not state.objAnimActive then
        state.objAnimFrom, state.objAnimTo = nil, nil
    end
end

-- 逐帧画「过渡中的那一帧木头」：形态在起点与终点之间插值
--   配色的过渡用**盖一层**的方式（躺色打底、立色按比例盖上），
--   而不是两边各降一半透明度 —— 后者在中途会让草地从木头里透出来。
function M.paintObjProxy()
    local pool = state.objProxyCtrls
    local a, b = state.objAnimFrom, state.objAnimTo
    if not state.objAnimActive or not a or not b then
        poolTrim(pool, 0)
        state.objProxyUsed = 0
        return
    end

    local dur = state.objAnimDur or 1
    local raw = utils.clamp((state.objAnimT or 0) / (dur > 0 and dur or 1), 0, 1)
    local k = easeBack(raw, animOvershoot(state.objAnimKind))
    local sp = {
        cx    = utils.lerp(a.cx, b.cx, k),
        cy    = utils.lerp(a.cy, b.cy, k),
        w     = utils.lerp(a.w,  b.w,  k),
        h     = utils.lerp(a.h,  b.h,  k),
        alongX = utils.lerp(a.alongX or 0, b.alongX or 0, k),
        stand  = utils.lerp(a.stand  or 0, b.stand  or 0, k),
    }
    -- 深度键所在的「行」：跨行时中途跳一次，和真实物体换行时的表现一致
    local row = utils.round(utils.lerp(a.row or 1, b.row or 1, utils.clamp(raw, 0, 1)))
    -- 立姿归「立着的木头」那一层（SUB_TREE），躺姿归「倒下的木头」（SUB_LOG）
    local sub = (sp.stand >= 0.5) and SUB_TREE or SUB_LOG
    local key = depthKey(BAND_OBJ, row, sub)

    local data = state.levelConfig or {}
    local palette = utils.resolvePalette(data)
    local parent = layerTree()        -- ★ 过渡的是木头 → 固定在树木层（第 22 批）
    local rect = rectSlot()
    local cell = state.cellSize or 1
    local stand = utils.clamp(sp.stand, 0, 1)
    local aNew = math.floor(255 * stand)      -- 立姿那一套的权重
    local i = 1

    -- 躺姿柱身打底（始终不透明）→ 立姿柱身按权重盖上去
    i = paint(pool, i, parent, rect, sp.cx, sp.cy, sp.w, sp.h,
              palette.logSide, 255, key + 0.01)
    i = paint(pool, i, parent, rect, sp.cx, sp.cy, sp.w, sp.h,
              palette.logStandSide, aNew, key + 0.02)
    -- 背光暗边（位置与配色都随姿态过渡）
    local sx, sy, sw, sh = shadeEdgeRect(sp, utils.clamp(sp.alongX, 0, 1))
    i = paint(pool, i, parent, rect, sx, sy, sw, sh,
              palette.logEnd, 190, key + 0.03)
    i = paint(pool, i, parent, rect, sx, sy, sw, sh,
              palette.logStandFoot, math.floor(190 * stand), key + 0.04)
    -- 受光边：位置随 alongX 在「竖亮边 ↔ 横亮边」之间融合，配色同样盖一层
    local ex, ey, ew, eh = litEdgeRect(sp, utils.clamp(sp.alongX, 0, 1))
    i = paint(pool, i, parent, rect, ex, ey, ew, eh,
              palette.logTop, 255, key + 0.05)
    i = paint(pool, i, parent, rect, ex, ey, ew, eh,
              palette.logStandEdge, aNew, key + 0.06)
    -- 立姿专属：根部土堆（「扎进地里」）+ 顶端亮切面（「切面朝天」）
    local footY = sp.cy - sp.h / 2
    i = paint(pool, i, parent, rect, sp.cx, footY + cell * 0.05,
              cell * TRUNK_FOOT, cell * 0.11, palette.logStandFoot,
              math.floor(205 * stand), key + 0.07)
    local capH = cell * TRUNK_CAP
    i = paint(pool, i, parent, rect, sp.cx, sp.cy + sp.h / 2 - capH / 2, sp.w, capH,
              palette.logStandEdge, aNew, key + 0.08)

    poolTrim(pool, i - 1)
    state.objProxyUsed = i - 1
end

-- 每帧推进：播完了就清标志 + 重建一次，把这一格交还给「真实木头」
function M.animateObject(dt)
    if not state.objAnimActive then return end
    state.objAnimT = (state.objAnimT or 0) + (dt or 0)
    if state.objAnimT >= (state.objAnimDur or 0) then
        state.objAnimActive = false
        state.objAnimFrom, state.objAnimTo = nil, nil
        state.objAnimT = 0
        M.rebuildObjects()
        return
    end
    M.paintObjProxy()
    M.restackWorld()
end

-- ================================================================
-- ★ 朝向：逻辑朝向 vs 画面朝向（第 37 批）
--   `state.playerFacing` 是**逻辑**朝向 —— 按方向键的那一刻就改，规则 / 深度 / 音效都用它，
--   一点都不能晚（晚一帧就会「按了左键人还面朝下」）。
--   但**画在屏幕上**的那个朝向要跟着转身过渡走，所以另立 `state.heroFacing`：
--   转身的前半程仍用旧朝向，压到最窄的那一帧才换成新朝向。
--   ★ 所有「取朝向去画东西」的地方都必须读 `heroVision()`，
--     读 `state.playerFacing` 会让三套画法（图元 / 立绘 / 像素）各自错帧。
-- ================================================================
local function heroVision()
    return state.heroFacing or state.playerFacing or "S"
end

-- 当前真正在显示的那个角色根容器（图元 / 立绘 / 像素画三选一，与 buildPlayer 的优先级同源）
local function heroRootCtrl()
    if state.heroPr and state.heroPrBox then return state.heroPrBox end
    if state.playerCtrlImg and state.playerCtrl then return state.playerCtrl end
    if state.heroPixel and state.heroArtBox then return state.heroArtBox end
    return state.playerCtrl
end

-- 把转身姿态下发到根容器。
--   ★ 第 37 批只有「压扁」一个量（scaleX）；第 38 批加上纵向补高、横向漂移、倾斜 ——
--     这三个才是「像 3D 绕轴转」而不是「纸片被挤了一下」的关键。
--   ★ 图元笔触那条路的**位置**由 placeHeroPrims 每帧统一算（要合并走路起伏与倾斜），
--     这里只对它下发 scale / rotation；图片立绘与像素画没有那个合并点，位置也在这里给。
local function applyHeroTurnPose()
    local root = heroRootCtrl()
    if not root then return end
    local sx = state.heroTurnScale or 1
    local sy = state.heroTurnSY or 1
    utils.setScale(root, sx, sy)
    if root ~= state.heroPrBox then
        -- 图片立绘 / 像素画：这里就要把漂移与倾斜一起给掉
        utils.setRotation(root, state.heroTurnTilt or 0)
        utils.setPosition(root, (state.playerVisX or 0) + (state.heroTurnDX or 0), state.playerVisY or 0)
    end
end

-- 转身姿态复位（换关 / 重开 / 过渡关掉时用）：宽高归 1、漂移与倾斜归 0
local function resetHeroTurnPose()
    state.heroTurnScale = 1
    state.heroTurnSY = 1
    state.heroTurnDX = 0
    state.heroTurnTilt = 0
    state.heroTurnDir = 0
    local root = heroRootCtrl()
    if not root then return end
    utils.setScale(root, 1, 1)
    utils.setRotation(root, 0)
    if root ~= state.heroPrBox then
        utils.setPosition(root, state.playerVisX or 0, state.playerVisY or 0)
    end
end

-- ================================================================
-- ★ 小人：用纯色矩形「画」出来（不是引用图片）
--   数据在 heroArt.lua：每个朝向 = 一套矩形 { x, y, w, h, 颜色索引 }，
--   摆在一张 COLS × ROWS 的网格上，整个网格正好 1 格高。
--   于是：一块的边长 = cellSize / ROWS，格子怎么缩放都不变形（像素恒为正方形）。
--
--   ★ 为什么把整幅画装进一个容器（heroArtBox）：
--     小人每帧都在移动。若每块矩形各自 SetAnchoredPosition，一帧就是几十次调用；
--     装进容器后每帧只移动 1 个控件，像素块的坐标一次算死。
--
--   ★ 为什么换朝向要重画而不是「藏一半显示一半」：
--     四个朝向的矩形数量与形状都不同（正面 187 块 / 侧面 160 块），
--     四套全建出来常驻 = 四倍控件；而朝向变化只在按键时发生，重画一点也不亏。
--     重画走对象池，只是改颜色与坐标，不新建控件。
-- ================================================================

-- 拿一个容器当「画布」（跟着世界容器走，才能参与 2.5D 的深度排序）
-- ★ 两级回退与 game.lua 的 createContainer 保持同源：
--   ① 容器节点元件（不绘制、不需图源）
--   ② 拿不到就退回「矩形 + 全透明」—— 容器只是个坐标系宿主，看不见也没关系
--   ⚠️ 这里**不能**因为 containerPrefabId = 0 就放弃像素画：真机脚本参数面板
--      里这一项留空 / 老存档没登记时它会是 0，而世界容器自己已经回退成功了，
--      像素画却「因为要容器所以不画」→ 小人静默变立绘，最难查的一类问题。
local function ensureHeroBox()
    if state.heroArtBox then return true end
    local host = layerPlayer()        -- ★ 角色层（第 22 批）：像素画整幅挂在角色容器里
    if not host then return false end

    local c = nil
    local cid = state.containerPrefabId or 0
    if cid > 0 then
        local ok, r = pcall(game.InstantiateClientUIControl, cid, host)
        if ok then c = r end
    end
    if not c then
        c = utils.instantiateRect(host)
        if not c then return false end
        utils.applyImage(c, state.rectImageId)
        pcall(function() c.imageColor = Color.FromRGBA(255, 255, 255, 0) end)
    end

    pcall(function()
        c:SetAnchorMin(0.5, 0.5)
        c:SetAnchorMax(0.5, 0.5)
        c:SetPivot(0.5, 0.5)
        c:SetAnchoredPosition(0, 0)
        c:SetSizeDelta(1, 1)
    end)
    c:SetActive(true)
    state.heroArtBox = c
    return true
end

-- 按当前朝向重画一遍小人（换朝向 / 换关卡 / 格子边长变了都要调）
function M.repaintPlayerArt()
    if not state.heroPixel or not state.heroArtBox then return false end
    local facing = heroVision()
    local sp, colors, cols, rows = heroSprite(facing)
    if not sp then return false end
    cols = tonumber(cols) or 0
    rows = tonumber(rows) or 0
    if cols <= 0 or rows <= 0 then return false end

    local cell = state.cellSize or 1
    local px = cell / rows                  -- 一个像素格的边长
    local W, H = cols * px, rows * px
    state.heroArtW, state.heroArtH = W, H
    utils.setSize(state.heroArtBox, W, H)

    -- 每块外扩一点点：亚像素矩形挨着摆时真机会在缝里露出底色（一条条亮线）
    local grow = math.min(0.18, px * 0.14)
    colors = colors or {}
    local slot = rectSlot()
    local parent = state.heroArtBox
    local i, failRun = 0, 0

    for k = 1, #sp do
        local b = sp[k]
        local bx, by, bw, bh, ci = b[1], b[2], b[3], b[4], b[5]
        -- 网格坐标（左上原点、y 向下）→ 容器坐标（中心原点、y 向上）
        local cx = (bx + bw / 2) * px - W / 2
        local cy = (rows - by - bh / 2) * px - H / 2
        local before = i
        i = paint(state.heroBlocks, i, parent, slot,
                  cx, cy, bw * px + grow, bh * px + grow,
                  colors[ci] or "FFFFFF", 255, nil)
        if i == before then
            -- 控件建不出来（真机控件数上限 / 元件不可用）
            failRun = failRun + 1
            if failRun >= 8 then break end
        else
            failRun = 0
        end
    end

    -- ★ 画不出来就**明确认输**，交给 buildPlayer 回退立绘。
    --   否则「立绘已隐藏 + 像素块一块没有」= 小人凭空消失，比立绘更糟。
    if i <= 0 or i < #sp * 0.5 then
        poolTrim(state.heroBlocks, 0)
        state.heroBlockUsed = 0
        utils.setVisible(state.heroArtBox, false)
        return false
    end

    poolTrim(state.heroBlocks, i)
    state.heroBlockUsed = i
    state.heroDrawn = facing
    utils.setVisible(state.heroArtBox, true)
    return true
end

-- 像素画摆位：画布底边 = 脚底线
--   （像素模式下 playerFootOffset() 返回 0，所以 playerVisY 本身就是脚底线的 y）
local function placeHeroArt()
    if not state.heroPixel or not state.heroArtBox then return end
    utils.setPosition(state.heroArtBox, state.playerVisX,
                      state.playerVisY + (state.heroArtH or 0) * 0.5)
end

-- ================================================================
-- ★ 图元笔触（第 16 批）：四视角小人由几百个「旋转椭圆」画出来
--   每个椭圆 = 「图片」元件 + SetImage(静态图源 100002 = 内置椭圆)
--              + imageColor 染色 + SetLocalRotation(0,0,rot)
--   ★ 为什么不需要图库、不需要上传 PNG：
--     100001 / 100002 / 100003 是引擎**内置**的矩形 / 椭圆 / 三角形图元。
--     只要「图片」元件有图源，真机就不会画成彩色「?」——这一点和立绘那条路正相反。
--   ★ 数据单位是「格」：x/y 相对脚底线中点（x 向右、y 向上）。
--     所以容器中心摆在「脚线 + 半格」，子控件 y 再减半格 —— 正好一格高。
--   ★ 四视角图元数不同（正面最多），池只按需要增长：换到笔画少的视角时把多余控件
--     **藏起来**而不销毁，来回转身不新建控件。
-- ================================================================
local function ensureHeroPrBox()
    if state.heroPrBox then return true end
    local host = layerPlayer()        -- ★ 角色层（第 22 批）
    if not host then return false end

    local c = nil
    local cid = state.containerPrefabId or 0
    if cid > 0 then
        local ok, r = pcall(game.InstantiateClientUIControl, cid, host)
        if ok then c = r end
    end
    if not c then
        c = utils.instantiateRect(host)
        if not c then return false end
        utils.applyImage(c, state.rectImageId)
        pcall(function() c.imageColor = Color.FromRGBA(255, 255, 255, 0) end)
    end

    pcall(function()
        c:SetAnchorMin(0.5, 0.5)
        c:SetAnchorMax(0.5, 0.5)
        c:SetPivot(0.5, 0.5)
        c:SetAnchoredPosition(0, 0)
        c:SetSizeDelta(1, 1)
    end)
    c:SetActive(true)
    state.heroPrBox = c
    return true
end

-- 取 / 建池里第 i 个图元控件
-- 部件索引（与 heroPrims.lua 的 M.PARTS 顺序一致）
--   1 back（白底虚化） / 2 head / 3 torso / 4 armL / 5 armR / 6 legL / 7 legR
local PR_BACK, PR_HEAD, PR_TORSO, PR_ARM_L, PR_ARM_R, PR_LEG_L, PR_LEG_R = 1, 2, 3, 4, 5, 6, 7

-- ★ 部件之间的**绘制层次**（后面 = 盖在上面），照原脚本的顺序还原：
--     垫底白雾 → 腿（衬裙在蓝裙子后面） → 躯干（蓝裙子） → 两臂 → 头
--   ⚠️ 一开始按「头/躯干/臂/腿」的自然顺序画，腿就排到了躯干之后——
--      白色衬裙被画到蓝裙子上，看上去就像「裙子敞开」了。真机上一眼就是错的。
local PR_DRAW_ORDER = { PR_BACK, PR_LEG_L, PR_LEG_R, PR_TORSO, PR_ARM_L, PR_ARM_R, PR_HEAD }

-- 每个部件一个容器：容器中心钉在该部件的**关节**上，绕 Z 旋转 = 绕关节摆臂 / 迈腿。
--   ★ 为什么要分成 6 个容器而不是把 300 多个椭圆全平铺：
--     只有「部件」能整组旋转。旋转一个容器 = 一次 SetLocalRotation，
--     子控件一个都不用改坐标 —— 这是能不能每帧摆腿的关键。
local function heroPrPartBox(pi)
    if not state.heroPrBox then return nil end
    state.heroPrBoxes = state.heroPrBoxes or {}
    local box = state.heroPrBoxes[pi]
    if box then return box end

    local c = nil
    local cid = state.containerPrefabId or 0
    if cid > 0 then
        local ok, r = pcall(game.InstantiateClientUIControl, cid, state.heroPrBox)
        if ok then c = r end
    end
    if not c then
        c = utils.instantiateRect(state.heroPrBox)
        if not c then return nil end
        utils.applyImage(c, state.rectImageId)
        pcall(function() c.imageColor = Color.FromRGBA(255, 255, 255, 0) end)
    end
    pcall(function()
        c:SetAnchorMin(0.5, 0.5)
        c:SetAnchorMax(0.5, 0.5)
        c:SetPivot(0.5, 0.5)
        c:SetAnchoredPosition(0, 0)
        c:SetSizeDelta(1, 1)
    end)
    c:SetActive(true)
    state.heroPrBoxes[pi] = c
    return c
end

-- 取 / 建第 pi 个部件的第 i 个图元控件（每个部件一个独立池：父子关系稳定，换视角不用搬家）
local function heroPrSlot(pi, i, parent, prefabId, imageId)
    state.heroPrPools = state.heroPrPools or {}
    local pool = state.heroPrPools[pi]
    if not pool then
        pool = {}
        state.heroPrPools[pi] = pool
    end
    local item = pool[i]
    if item then return item end
    local ctrl = utils.createControl(prefabId, 0, 0, 1, 1, nil, parent, imageId)
    if not ctrl then return nil end
    pcall(function() ctrl.imageType = Enum.ImageType.Stretch end)
    item = { c = ctrl }
    pool[i] = item
    return item
end

-- ================================================================
-- ★ 画一帧小人（第 17 批：按部件画，含关节）
--   数据形如：{ {px,py,n, x,y,w,h,rot,rgb,alpha ×n}, ... 6 个部件 }
--   其中 x,y 已经是**相对关节**的偏移，所以直接贴到部件容器里就行。
-- ================================================================

-- 把 0xRRGGBB 的每个通道乘 k（k<1 变暗），再转回 "%06X"。
--   ★ 不用位运算（`>>` / `&`）：千星那套 Lua 版本不保证支持，除法取模最稳。
local function shadeRGB(rgb, k)
    local r = math.floor(rgb / 65536) % 256
    local g = math.floor(rgb / 256) % 256
    local b = rgb % 256
    r = math.floor(r * k); g = math.floor(g * k); b = math.floor(b * k)
    if r > 255 then r = 255 elseif r < 0 then r = 0 end
    if g > 255 then g = 255 elseif g < 0 then g = 0 end
    if b > 255 then b = 255 elseif b < 0 then b = 0 end
    return string.format("%02X%02X%02X", r, g, b)
end

-- ★ 第 39 批：第 38 批那两个「飘带判定」的函数（`rgbLum` / `isRibbonEl`）已经删掉。
--   它们想挑出「围巾垂在身侧的那条带子」，实际挑中的是**手和袖口的浅色笔**：
--   A 视角 armR 的 60 笔里 18 笔被判成飘带，而那 18 笔正是那只橙色手掌。
--   挪到躯干容器后，摆臂时袖子照甩、手掌留在原地 —— 身前身后各多出一块橙色
--   「领带状物」，比原来的问题更糟（用户第 39 批报的就是这个）。
--   真正的「带子」是**远侧那条被身体挡住的手臂**：它只露贴着身体边缘的一小条，
--   跟着转 30° 就扫出轮廓之外。修法见 `updateHeroWalk` 的 `DEFAULT_HERO_FAR_ARM`。

-- ★ 第 38 批 · 一个视角的「剪影宽度」（格）。
--   为什么要它：四个视角的宽度并不一样（正面 0.9 格、侧面 0.55 格），
--   转身时如果两边都按同一个缩放系数走，**换图那一帧屏幕宽度会突然变窄** ——
--   那就是「其实换了一张图」的破绽。按旧/新宽度之比补偿，宽度就连续了。
--   椭圆是旋转过的，x 方向的半宽要按 |w/2·cosθ| + |h/2·sinθ| 算。
local function heroViewWidth(view)
    if type(view) ~= "table" then return 1 end
    local lo, hi = 1e9, -1e9
    for pi = 1, #view do
        local part = view[pi]
        if type(part) == "table" and #part >= 3 then
            local px, n = part[1], part[3]
            local k = 4
            for e = 1, n do
                local ex, ew, eh, er = part[k] or 0, part[k + 2] or 0, part[k + 3] or 0, part[k + 4] or 0
                local th = math.rad(er)
                local half = math.abs(ew * 0.5 * math.cos(th)) + math.abs(eh * 0.5 * math.sin(th))
                local c = px + ex
                if c - half < lo then lo = c - half end
                if c + half > hi then hi = c + half end
                k = k + 7
            end
        end
    end
    if hi <= lo then return 1 end
    return hi - lo
end

-- 视角宽度缓存（换视角那一帧 repaint 时顺手算，之后随时可取）
local function heroViewWidthOf(facing)
    local cache = state.heroViewW
    if cache and cache[facing] then return cache[facing] end
    local view = heroPrims and heroPrims[facing]
    if type(view) ~= "table" then return 1 end
    local w = heroViewWidth(view)
    state.heroViewW = state.heroViewW or {}
    state.heroViewW[facing] = w
    return w
end

function M.repaintHeroPrims()
    if not state.heroPr or not state.heroPrBox then return false end
    local facingNow = heroVision()
    local view = (heroPrims and (heroPrims[facingNow] or heroPrims.S)) or nil
    if type(view) ~= "table" then return false end

    local cell = state.cellSize or 1
    local prefabId = state.heroPrPrefabId or 0
    if prefabId <= 0 then prefabId = config.DEFAULT_PREFAB_HERO_PRIMS end
    local imageId = state.heroPrImageId or 0
    if imageId <= 0 then imageId = config.DEFAULT_HERO_PRIMS_IMAGE end

    -- ★ 第 38 批 · 腿部加深：抬腿后露出来的那片颜色偏浅，读作「腿部变浅了」
    local legShade = tonumber(config.DEFAULT_HERO_LEG_SHADE) or 1
    if legShade <= 0 then legShade = 1 end
    -- ★ 第 38 批 · 转身明暗：整幅画按一个系数压暗（1 = 不变）。
    --   转动时朝向镜头的是背光面，这一档明暗是「像 3D」最直接的信息，
    --   而且**零额外调用** —— 反正这次 repaint 本来就要把每笔的颜色重发一遍。
    local tintK = tonumber(state.heroPrTintK) or 1
    if tintK <= 0 then tintK = 1 end

    local used, want, failRun = 0, 0, 0
    for pi = 1, #view do
        local part = view[pi]
        if type(part) == "table" and #part >= 3 then
            local px, py, n = part[1], part[2], part[3]
            local box = heroPrPartBox(pi)
            if box then
                state.heroPrPivots = state.heroPrPivots or {}
                state.heroPrPivots[pi] = { x = px, y = py }   -- 关节位置（摆腿/抬脚要用）
                -- ★ 部件容器**必须保持 1×1**，不要设成 1 格大小：
                --   容器的旋转原点跟它自身的尺寸挂钩，尺寸一大，子控件就绕着
                --   「容器左上角」转 —— 一摆臂整条胳膊会被甩出去十几像素（踩过）。
                --   1×1 时这点误差是亚像素，等于精确绕关节转。
                utils.setSize(box, 1, 1)
                utils.setPosition(box, px * cell, (py - 0.5) * cell)
                utils.setVisible(box, true)
                local k = 4
                for e = 1, n do
                    want = want + 1
                    local ex, ey = part[k] or 0, part[k + 1] or 0
                    local rgb = math.floor(part[k + 5] or 0)
                    local item = heroPrSlot(pi, e, box, prefabId, imageId)
                    if item then
                        local c = item.c
                        utils.setSize(c, part[k + 2] * cell, part[k + 3] * cell)
                        utils.setPosition(c, ex * cell, ey * cell)
                        utils.setRotation(c, part[k + 4])
                        local hex
                        local kk = 1
                        if pi == PR_LEG_L or pi == PR_LEG_R then kk = kk * legShade end
                        if tintK < 0.999 then kk = kk * tintK end
                        if kk < 0.999 then
                            hex = shadeRGB(rgb, kk)
                        else
                            hex = string.format("%06X", rgb)
                        end
                        utils.setAlpha(c, hex, part[k + 6] or 255)
                        utils.setVisible(c, true)
                        used = used + 1
                        failRun = 0
                    else
                        failRun = failRun + 1
                    end
                    k = k + 7
                end
                -- 该部件多出来的控件藏起来（换视角时数量会变）
                local pool = state.heroPrPools and state.heroPrPools[pi]
                if pool then
                    for j = n + 1, #pool do
                        utils.setVisible(pool[j] and pool[j].c, false)
                    end
                end
            end
        end
    end

    if failRun >= 6 or used < math.floor(want * 0.5) then
        utils.setVisible(state.heroPrBox, false)
        return false
    end
    -- ★ 按 PR_DRAW_ORDER 重排部件容器（SetAsLastSibling = 依次提到最上）
    for i = 1, #PR_DRAW_ORDER do
        local box = state.heroPrBoxes and state.heroPrBoxes[PR_DRAW_ORDER[i]]
        if box then pcall(function() box:SetAsLastSibling() end) end
    end

    state.heroPrUsed = used
    state.heroPrDrawn = heroVision()
    utils.setVisible(state.heroPrBox, true)
    return true
end

-- ================================================================
-- ★ 走路摆动（第 17 批）
--   ★ 相位跟着「一步」的时长走：一步 = 一个完整的前后摆（2π），
--     所以按住方向键连走时腿是连续摆的，不会一步一卡。
--   ★ 停下时振幅平滑衰减到 0，不会「腿突然弹回原位」。
--   ★ 手臂与腿**反相**：左腿前摆时右臂前摆 —— 这是人走路能读出来的关键。
-- ================================================================
local function setPartRot(pi, deg)
    local boxes = state.heroPrBoxes
    if not boxes or not boxes[pi] then return end
    utils.setRotation(boxes[pi], deg)
end

-- 把某个部件按「关节 + 前后位移 + 抬脚高度」重新摆一次
--   ★ 腿走的是**位移**（迈出去 / 抬起来），不是旋转：
--     这个角色穿长裙，腿一转就会看到裙子从腰上撕开；位移只让脚整体挪一点，剪影不裂。
--   ★ 第 36 批：`dx` / `dy` 都是**格**（相对关节的偏移），`lift` 是**像素**。
--     dy 是给「正面 / 背面视角按深度错位」留的口子，现在正面不做前后位移（见下面的说明）。
local function setPartPlace(pi, dx, dy, lift)
    local boxes = state.heroPrBoxes
    local piv = state.heroPrPivots
    if not boxes or not boxes[pi] or not piv or not piv[pi] then return end
    local cell = state.cellSize or 1
    utils.setPosition(boxes[pi],
                      (piv[pi].x + (dx or 0)) * cell,
                      (piv[pi].y - 0.5 + (dy or 0)) * cell + (lift or 0))
end

function M.updateHeroWalk(dt)
    if not state.heroPr or not state.heroPrBox then return end
    local walkOn = state.heroWalkOn
    if walkOn == nil then walkOn = (tonumber(config.DEFAULT_HERO_WALK_ON) or 1) > 0 end
    if not walkOn then return end

    local moving = (state.playerAnimT or 0) < (state.playerAnimDur or 0)
    local amp = state.heroWalkAmp or 0
    local d = tonumber(dt) or 0

    if moving then
        -- ★ 摆动周期固定（默认 0.3 秒一个来回），**不跟单步动画时长绑死**：
        --   一步只有 0.1 秒 ≈ 3 帧，绑在一步上会快到只剩闪烁。
        local period = math.max(0.12, tonumber(config.DEFAULT_HERO_WALK_PERIOD) or 0.3)
        state.heroWalkPhase = (state.heroWalkPhase or 0) + d / period * math.pi * 2
        amp = math.min(1, amp + d * 14)
    else
        amp = math.max(0, amp - d * 8)
    end
    state.heroWalkAmp = amp

    local phase = state.heroWalkPhase or 0
    local cell = state.cellSize or 1
    local sA = math.sin(phase)
    local sB = -math.sin(phase)          -- 另一条腿反相

    -- ★ 第 36 批：动作要按**角色朝向**投影到屏幕 —— 2.5D 正交视角里没有真正的 Z 轴，
    --   「前后」在两个视角家族里落在不同的屏幕上：
    --     · 侧面（A 左 / D 右）：前后 = 屏幕**左右** → 腿可以真的前后迈、手臂绕肩转
    --     · 正面 / 背面（S 南 / W 北）：前后 = 屏幕**上下（深度）**，而抬脚也是向上，
    --       两者互相抵消 → 这个视角只做「抬脚 + 重心起伏」，不做前后位移、不转腿。
    --   ⚠️ 第 17 批是一律按屏幕 x 位移的：幅度只有 0.03 格（≈2px）时看不出问题，
    --      第 36 批一放大到 0.085 格，正面视角立刻变成「两条腿左右劈叉」。
    local facing = heroVision()
    local sideView = (facing == "A" or facing == "D")
    local dirX = 0
    if facing == "D" then dirX = 1 elseif facing == "A" then dirX = -1 end

    local armA = (config.DEFAULT_HERO_WALK_ARM or 30) * math.sin(phase) * amp
    local legA = (config.DEFAULT_HERO_WALK_LEG or 8) * math.sin(phase) * amp
    local stepX = (config.DEFAULT_HERO_WALK_STEP_X or 0.06) * amp
    local liftMax = cell * (config.DEFAULT_HERO_WALK_LIFT or 0.055) * amp
    local upL = (sA > 0 and sA or 0)
    local upR = (sB > 0 and sB or 0)

    if sideView then
        -- 侧面：手臂绕肩前后摆（这是「在走路」最主要的信号），腿前后迈 + 轻微转动
        -- ★ 第 39 批 · **只摆靠近镜头的那条手臂**。
        --   另一条被身体挡住的（远侧）手臂在图里只露出贴着身体边缘的一小条，
        --   让它跟着转 30°，那一小条就扫出身体轮廓之外 —— 用户两批都报的
        --   「身前 / 身后有类似领带的带状物在动」就是它。
        --   远侧手臂干脆**钉死在身体上**（摆幅 × DEFAULT_HERO_FAR_ARM，默认 0）：
        --   它本来就被挡住，不摆也看不出少了什么；而这一钉，那条「带子」就没了。
        --   ⚠️ 别再想着「把飘带的笔画挑出来挪到躯干容器」—— 第 38 批试过，
        --      亮度判据抓走的是手和袖口的浅色笔，手掌被钉在原地后反而更花。
        local farK = tonumber(state.heroFarArm)
        if farK == nil then farK = tonumber(config.DEFAULT_HERO_FAR_ARM) or 0 end
        if farK < 0 then farK = 0 elseif farK > 1 then farK = 1 end
        local armL, armR = -armA, armA
        if facing == "A" then
            armL = armL * farK            -- A（朝左）：近镜头是 armR，armL 在远侧
        elseif facing == "D" then
            armR = armR * farK            -- D（朝右）：近镜头是 armL，armR 在远侧
        end
        setPartRot(PR_ARM_L, armL)
        setPartRot(PR_ARM_R, armR)
        setPartPlace(PR_ARM_L, 0, 0, 0)
        setPartPlace(PR_ARM_R, 0, 0, 0)
        setPartRot(PR_LEG_L, legA)
        setPartRot(PR_LEG_R, -legA)
        setPartPlace(PR_LEG_L, dirX * sA * stepX, 0, upL * liftMax)
        setPartPlace(PR_LEG_R, dirX * sB * stepX, 0, upR * liftMax)
    else
        -- 正面 / 背面：不转腿（会劈叉、会看到裙子撕开），只抬脚 —— 一条腿抬起、一条踩地，
        --   配合整幅画的上下起伏（bob）就能读出「在迈步」。
        --   ★ 手臂给一个小角度反相摆（12°）：完全不动会读成「整体滑行」，
        --     给到侧面那档 30° 又会横着张开像举双手。
        local armF = (config.DEFAULT_HERO_WALK_ARM_FRONT or 12) * math.sin(phase) * amp
        setPartRot(PR_ARM_L, -armF)
        setPartRot(PR_ARM_R, armF)
        setPartPlace(PR_ARM_L, 0, 0, 0)
        setPartPlace(PR_ARM_R, 0, 0, 0)
        setPartRot(PR_LEG_L, 0)
        setPartRot(PR_LEG_R, 0)
        setPartPlace(PR_LEG_L, 0, 0, upL * liftMax)
        setPartPlace(PR_LEG_R, 0, 0, upR * liftMax)
    end
end

local function placeHeroPrims()
    if not state.heroPr or not state.heroPrBox then return end
    local cell = state.cellSize or 1
    utils.setSize(state.heroPrBox, cell, cell)
    -- 走路时整幅画轻微上下浮动（一个步幅两次），像身体重心在起落；静止时不动
    --   ★ 第 36 批：幅度提到 config 里（`DEFAULT_HERO_WALK_BOB`），原来是硬编码 0.012 格
    --     —— 在 cell=99 时只有 1px 出头，等于没有。
    --   ★ 第 36 批再加「左右倾」（`DEFAULT_HERO_WALK_TILT`）：整幅画绕**身体中心**晃 2.5°，
    --     读作重心在两脚之间转移。这个角色长袍遮腿，正面视角光靠抬脚看不出在走，
    --     左右倾是剪影层面最有效的补偿（6 个部件都在这个容器里，一起转，不会撕裂）。
    local amp = state.heroWalkAmp or 0
    local bob = 0
    local tilt = 0
    if amp > 0.01 then
        local phase = state.heroWalkPhase or 0
        local bobRatio = tonumber(config.DEFAULT_HERO_WALK_BOB) or 0.045
        bob = cell * bobRatio * amp * math.abs(math.sin(phase * 2))
        tilt = (tonumber(config.DEFAULT_HERO_WALK_TILT) or 2.5) * amp * math.sin(phase)
    end
    -- ★ 第 38 批：转身的「立体感」三个量也在这里合并 ——
    --   纵向补高 sy 要把位置按 cell*0.5*sy 抬高，脚线才留在原地；
    --   横向漂移 dx 与倾斜 tilt 直接叠上去。
    local cellHalf = cell * (state.heroTurnSY or 1) * 0.5
    local walkTilt = tilt
    local turnTilt = state.heroTurnTilt or 0
    utils.setRotation(state.heroPrBox, walkTilt + turnTilt)
    utils.setPosition(state.heroPrBox, state.playerVisX + (state.heroTurnDX or 0),
                      state.playerVisY + cellHalf + bob)
end

-- ================================================================
-- ★ 图片立绘：按当前朝向换图源（第 15 批）
--   ★ 四向共用一个控件、只换图 —— 省控件也省内存。
--   ★ 缺的朝向自动回退正面：只填 heroImageS 也能跑，只是转身不变图。
--   ★ 换不了（ID 不存在 / 绑定不认 SetImage）时**什么都不做**：
--     宁可停在上一张，也绝不把人藏起来变成「人没了」。
-- ================================================================
function M.applyPlayerImage()
    if not state.playerCtrlImg or not state.playerCtrl then return false end
    local ids = state.heroImageIds or {}
    local id = tonumber(ids[heroVision()] or 0) or 0
    if id <= 0 then id = tonumber(ids.S or 0) or 0 end
    if id <= 0 then return false end
    return utils.applyImage(state.playerCtrl, id)
end

-- ================================================================
-- ★ 按「画面朝向」重画一次（三套画法各走各的入口）
--   ★ 换朝向只在**转身中点**发生，所以这个函数一帧最多被调一次。
-- ================================================================
function M.repaintHeroForFacing()
    if state.heroPr then
        M.repaintHeroPrims()      -- 图元笔触：换一套椭圆 = 转身
    elseif state.playerCtrlImg then
        M.applyPlayerImage()      -- 图片立绘：换一张图就是转身
    elseif state.heroPixel then
        M.repaintPlayerArt()
    end
end

-- ================================================================
-- ★ 换朝向（走一步之前调用；只换画，不碰位置）
--   ★ 只认 W/S/A/D 四个方向，别的键忽略 —— 免得把奇怪的值写进 state。
--   ★ 转身在**规则判定之前**发生：顶着墙按方向键，人也会先转过去，
--     否则会出现「按了左键，人还面朝下」的怪样子。
--   ★ 第 37 批：逻辑朝向**立刻**改（规则不能等），画面朝向交给 `updateHeroTurn`
--     走 0.2 秒的「压扁 → 换图 → 展开」过渡 —— 原来是瞬间换一套图，
--     每一次转身都是硬跳，连按转向时看着像「闪烁」而不是「转身」。
-- ================================================================
function M.setPlayerFacing(key)
    if not key or not world.DIRS[key] then return end
    if state.playerFacing == key then return end
    -- ⚠️ 先取「当前画面朝向」再改逻辑朝向：heroVision() 在 heroFacing 还没初始化时
    --   会回退到 playerFacing，先改就会取到**新**朝向，转身直接退化成瞬切。
    local cur = heroVision()
    state.playerFacing = key

    local dur = tonumber(config.DEFAULT_HERO_TURN_TIME) or 0.24
    local squash = tonumber(config.DEFAULT_HERO_TURN_SQUASH) or 0.32
    if dur <= 0.01 or squash >= 0.99 or cur == key then
        -- 过渡被关掉（时长为 0 / 压扁系数 ≥ 1）：退回瞬间换图
        state.heroFacing = key
        state.heroTurnDur = 0
        state.heroTurnT = 0
        state.heroTurnFrom = ""
        state.heroPrTintK = 1
        M.repaintHeroForFacing()
        resetHeroTurnPose()
        return
    end
    -- ★ 转身途中又按了新方向：从「当前画面朝向」重新起转，不叠加、不排队。
    --   过渡全程只有 0.24 秒，排队会让人物对着旧方向转完再转回来，像失控。
    state.heroTurnFrom = cur
    state.heroTurnT = 0
    state.heroTurnDur = dur
    state.heroTurnSquashCfg = squash

    -- ★ 第 38 批：这次转身在屏幕上是「往哪边转」—— 漂移与倾斜都朝这个方向。
    --   取两个朝向的横向分量之差：S→D = +1（向右转）、D→S = -1、A→S = +1。
    --   正面↔背面（S↔W）横向分量都是 0 → dir = 0，只压扁、不漂移（那本来就是「翻面」）。
    local function faceX(f)
        if f == "D" then return 1 elseif f == "A" then return -1 end
        return 0
    end
    local d = faceX(key) - faceX(cur)
    if d > 0 then state.heroTurnDir = 1
    elseif d < 0 then state.heroTurnDir = -1
    else state.heroTurnDir = 0 end

    -- ★ 第 38 批：宽度补偿。四个视角的剪影宽度不同（正面宽、侧面窄），
    --   换图那一帧若两边用同一个缩放系数，屏幕宽度会**突然变窄** ——
    --   一窄就露馅：读作「换了一张图」而不是「转过去了」。
    --   这里记下旧/新宽度之比，换图后先把宽度撑回去，再在剩下的半程里平滑收回 1。
    local wFrom = heroViewWidthOf(cur)
    local wTo = heroViewWidthOf(key)
    local fix = 1
    if wFrom > 0.05 and wTo > 0.05 then fix = wFrom / wTo end
    if fix > 1.6 then fix = 1.6 elseif fix < 0.7 then fix = 0.7 end
    state.heroTurnWidthFix = fix
end

-- ================================================================
-- ★ 转身过渡：压扁 → 换朝向 → 展开（每帧推进）
--   ★ 曲线用 `1 - (1-S)·sin(πp)`：
--       p=0 → 1（原宽）、p=0.5 → S（最窄）、p=1 → 1（原宽），两端导数为 0
--       —— 起步和收尾都不生硬，中段最快，正好对应「一转身就侧过去了」。
--   ★ 换朝向的那一帧放在 p=0.5（最窄处）：宽度只剩 32%，新旧两套图差什么
--     都看不出来 —— 这就是整个过渡不需要中间帧资源的原因。
--   ★ 第 38 批：同一条 sin(πp) 曲线同时驱动「纵向补高 / 横向漂移 / 倾斜」，
--     三者都在 p=0.5 到峰值、两端为 0 —— 和压扁同一个节奏，不会互相打架。
-- ================================================================
function M.updateHeroTurn(dt)
    local target = state.playerFacing or "S"

    -- 没在转身：画面朝向跟随逻辑朝向（兜底：别的入口直接改了 playerFacing）
    if (state.heroTurnDur or 0) <= 0 then
        if not state.heroFacing then state.heroFacing = target end
        if state.heroFacing ~= target then
            state.heroFacing = target
            M.repaintHeroForFacing()
        end
        -- 姿态已经是「正位」时不要每帧重复下发（每帧 3 次接口调用没必要）
        local off = math.abs((state.heroTurnScale or 1) - 1) > 0.004
                 or math.abs((state.heroTurnSY or 1) - 1) > 0.004
                 or math.abs(state.heroTurnDX or 0) > 0.01
                 or math.abs(state.heroTurnTilt or 0) > 0.01
        if off then resetHeroTurnPose() end
        -- ★ 明暗也要收尾（第 38 批）：万一在「最暗」那一帧被别的分支跳过，颜色会一直暗着
        if math.abs((state.heroPrTintK or 1) - 1) > 0.004 then
            state.heroPrTintK = 1
            M.repaintHeroForFacing()
        end
        return
    end

    local dur = state.heroTurnDur
    local t = (state.heroTurnT or 0) + (tonumber(dt) or 0)
    if t >= dur then
        -- 转完了：收尾成「新朝向 + 正位」
        state.heroTurnT = 0
        state.heroTurnDur = 0
        state.heroTurnFrom = ""
        state.heroFacing = target
        state.heroPrTintK = 1                -- 第 38 批：明暗一并回正
        M.repaintHeroForFacing()
        resetHeroTurnPose()
        return
    end

    state.heroTurnT = t
    local p = t / dur
    local k = math.sin(p * math.pi)              -- 0 → 1 → 0
    -- ★ 第 38 批 · 明暗跟随：`tintK = 1 - DIM·k`，变化超过 4% 才重绘一次。
    --   必须在「换图」判定之前更新，换图那一帧才用得上新的明暗 —— 少一次全量重绘。
    --   ⚠️ 每触发一次都是 842 笔 × 4 次接口调用，一次转身最多 4 次，别把阈值调小。
    local dim = tonumber(config.DEFAULT_HERO_TURN_DIM) or 0
    if dim > 0.001 then
        local want = 1 - dim * k
        if math.abs(want - (state.heroPrTintK or 1)) > 0.04 then
            state.heroPrTintK = want
            M.repaintHeroForFacing()
        end
    end
    if p >= 0.5 and state.heroFacing ~= target then
        state.heroFacing = target
        M.repaintHeroForFacing()
    end
    local squash = state.heroTurnSquashCfg or tonumber(config.DEFAULT_HERO_TURN_SQUASH) or 0.32
    local cell = state.cellSize or 1
    local dir = state.heroTurnDir or 0

    state.heroTurnScale = 1 - (1 - squash) * k
    -- 宽度补偿：p≥0.5 时先按「旧宽/新宽」撑回去，再在半程内平滑收回 1
    --   → 换图那一帧的**屏幕**宽度前后相等，看不出「换了一张图」。
    local fix = state.heroTurnWidthFix or 1
    if fix ~= 1 and p >= 0.5 then
        local t2 = (p - 0.5) * 2
        state.heroTurnScale = state.heroTurnScale * (fix + (1 - fix) * t2)
    end
    -- 纵向补高：压扁时投影面积要守恒，只压不长就是纸片
    state.heroTurnSY = 1 + (tonumber(config.DEFAULT_HERO_TURN_DEPTH) or 0) * k
    -- 横向漂移：绕竖轴转时剪影中心会朝转动方向挪（近侧先到镜头前）
    state.heroTurnDX = (tonumber(config.DEFAULT_HERO_TURN_DRIFT) or 0) * cell * k * dir
    -- 惯性倾斜：上半身朝转向侧偏一点
    state.heroTurnTilt = (tonumber(config.DEFAULT_HERO_TURN_TILT) or 0) * k * dir
    applyHeroTurnPose()
end

-- ================================================================
-- ★ 小人
--   素材模式：一张人物立绘（内容 1 格宽 × 1 格高），不染色
--   回退模式：身体 + 头两块纯色矩形（身体 0.94 格高就是全身，头压在身体上部）
--   两种模式都配一块脚下滑影（就是那一点点接触阴影，站在方块上才不飘）
--   ★ 控件跨关卡复用（形态在建出来的那一刻定死），否则连按 R 会留下一层层残影。
-- ================================================================
local function buildPlayer(palette)
    local cell = state.cellSize
    local slot = makeSlot(state.playerPrefabId)
    -- ★ 第 22 批：小人的所有控件（立绘 / 身体 / 头 / 像素画容器 / 图元容器 / 阴影）
    --   一律挂**角色层** containerPlayer —— 固定在最上，不再被地形或树木盖住。
    local host = layerPlayer()

    -- ★ 图元笔触路径（第 16 批）：优先级最高 —— 用户要的就是「用这套图元脚本当主角」。
    --   四道门全过才启用：开关开着 + 数据在 + 容器拿得到 + 真的画出来了。
    local prSwitch = state.heroPrSwitch
    if prSwitch == nil then
        prSwitch = (tonumber(config.DEFAULT_HERO_PRIMS_ON) or 0) > 0
    end
    local prWhy = ""
    state.heroPr = false
    local prReady = false
    if not prSwitch then
        prWhy = "脚本参数 heroPrimsOn 被关闭（填了 -1）"
    elseif not heroPrData(state.playerFacing or "S") then
        prWhy = "heroPrims.lua 没导入或数据缺失"
    elseif not ensureHeroPrBox() then
        prWhy = "图元笔触容器建不出来（世界容器缺失）"
    else
        state.heroPr = true
        state.playerBodyH = cell
        if M.repaintHeroPrims() then
            prReady = true
            prWhy = ""
        else
            state.heroPr = false
            prWhy = "图元控件一个也没建出来"
        end
    end
    state.heroPrWhy = prWhy

    -- ★ 立绘图片路径（第 15 批）：填了图库 ID 就优先用「图片」元件显示原画。
    --   比像素画清晰得多 —— 原图是平滑矢量风，压到 68px 高再像素化，侧面必糊。
    --   ⚠️ 没填 ID 时**绝不**走这条路：图片元件不带图源，真机会画成彩色「?」。
    local heroImgOn = state.heroImageOn and (state.heroImageIds.S or 0) > 0

    if not state.playerCtrl and not prReady then
        if heroImgOn then
            local ctrl = utils.createControl(
                state.heroImagePrefabId or config.DEFAULT_PREFAB_IMAGE,
                0, 0, 1, 1, nil, host)
            if ctrl then
                state.playerCtrlImg = true
                state.playerCtrlArt = true      -- 自带图源 → 不染色
                state.playerCtrl = ctrl
            end
        end
        if not state.playerCtrl then
            local ctrl = utils.createControl(slot.prefab, 0, 0, 1, 1, nil, host)
            state.playerCtrlArt = (ctrl ~= nil) and slot.art
            if not ctrl then
                ctrl = utils.createControl(state.rectPrefabId, 0, 0, 1, 1, nil, host)
                state.playerCtrlArt = false
            end
            state.playerCtrl = ctrl
            state.playerCtrlImg = false
        end
    end
    if not state.playerCtrl and not prReady then return end

    -- 脚下滑影
    --   ★ 第 21 批：**整段关掉**（config.DEFAULT_OBJ_SHADOW_ALPHA = 0）。
    --     第 20 批曾改成「图片」元件 + 内置椭圆图元 100002 —— 那是**模拟器**的代理图元，
    --     真机不认，图片控件拿不到图源就画成纯白方块，正好糊在人物脚下
    --     （用户两次反馈的「白色方块」就是这个）。
    --   → 阴影开关关掉时连控件都不建：建了也是隐藏的，留着只会再被误开。
    local shadowAlpha = config.DEFAULT_OBJ_SHADOW_ALPHA or 0
    if shadowAlpha > 0 then
        if not state.playerShadowCtrl then
            local sw = cell * (config.DEFAULT_SHADOW_W or 0.62)
            local sh = cell * (config.DEFAULT_SHADOW_H or 0.20)
            local ctrl = nil
            local eId = tonumber(config.DEFAULT_HERO_PRIMS_IMAGE) or 0
            local pId = tonumber(state.heroPrPrefabId) or 0
            if pId > 0 and pId ~= state.rectPrefabId and eId > 0 then
                ctrl = utils.createControl(pId, 0, 0, sw, sh, nil, host, eId)
            end
            state.playerShadowArt = (ctrl ~= nil)
            if not ctrl then
                ctrl = utils.createControl(state.rectPrefabId, 0, 0, sw, sh, nil, host)
            end
            state.playerShadowCtrl = ctrl
        end
        local shadowHex = palette.shadowLand or "33421F"     -- ★ 绝不能是 nil（nil → 纯白）
        utils.setSize(state.playerShadowCtrl,
                      cell * (config.DEFAULT_SHADOW_W or 0.62),
                      cell * (config.DEFAULT_SHADOW_H or 0.20))
        utils.setAlpha(state.playerShadowCtrl, shadowHex, shadowAlpha)
        utils.setVisible(state.playerShadowCtrl, true)
    else
        utils.setVisible(state.playerShadowCtrl, false)
    end

    -- ★ 像素画优先：开关开着 + 数据在 + 容器拿得到 + 真的画出来了 → 用纯色矩形画小人
    --   任何一环不满足就退回「人物」素材立绘或纯色身体矩形，绝不整片空白。
    --   ★ 四道门失败都要留下**可读的原因**（state.heroPixelWhy）：
    --     真机上「像素小人没出来」时，事后只能靠这一行定位断在哪。
    local pixelOn = state.heroPixelOn
    if pixelOn == nil then
        pixelOn = (tonumber(config.DEFAULT_HERO_PIXEL_ON) or 0) > 0
    end

    local why = ""
    state.heroPixel = false
    if prReady then
        why = "走图元笔触（heroPrims.lua）"
    elseif heroImgOn and state.playerCtrlImg then
        why = "走图片立绘（填了图库图片 ID）"
    elseif not pixelOn then
        why = "脚本参数 heroPixelOn 被关闭（填了 -1）"
    elseif not heroSprite(state.playerFacing or "S") then
        why = "像素画数据不可用（heroArt.lua 没导入，且 level.lua 内置数据缺失）"
    elseif not ensureHeroBox() then
        why = "像素画容器建不出来（世界容器缺失）"
    else
        state.heroPixel = true
        state.playerBodyH = cell          -- 概念高度：像素网格正好 1 格
        utils.setVisible(state.playerCtrl, false)      -- 立绘让位给像素画
        utils.setVisible(state.playerHeadCtrl, false)
        if not M.repaintPlayerArt() then
            state.heroPixel = false
            why = "像素块一块也没建出来（控件创建失败）"
        end
    end
    state.heroPixelWhy = why

    -- ★ 自检只打一次：真机看脚本日志就能知道小人走的是哪条路、画了多少块。
    --   print 在个别沙箱里会被裁掉 → 先确认它是个函数再调，别让自检把游戏拖崩。
    if not state.heroPixelLogged then
        state.heroPixelLogged = true
        if type(print) == "function" then
            local mode = "素材立绘/纯色"
            if state.heroPr then mode = string.format("图元笔触(%d 笔)", state.heroPrUsed or 0)
            elseif state.heroPixel then mode = "像素画"
            elseif state.playerCtrlImg then
                mode = string.format("图片立绘(元件=%s)",
                    tostring(state.heroImagePrefabId or 0))
            end
            pcall(print, string.format(
                "[浮岛借木] 小人=%s | 像素块=%d | 数据源=%s | 原因=%s | 图元: %s (建出 %d 笔)",
                mode,
                state.heroBlockUsed or 0,
                (heroDataFrom ~= "" and heroDataFrom) or "无",
                (why ~= "" and why) or "无",
                (state.heroPrWhy ~= "" and state.heroPrWhy) or "OK",
                state.heroPrUsed or 0))
        end
    end

    if prReady then
        -- 图元笔触已在上面画好：1 格高、底边压脚线，其余形态一律让位
        state.playerBodyH = cell
        utils.setVisible(state.playerCtrl, false)
        utils.setVisible(state.playerHeadCtrl, false)
        utils.setVisible(state.heroArtBox, false)
        placeHeroPrims()
    elseif state.heroPixel then
        -- 已在上面画好，这里什么都不用做（保留分支只为结构清晰）
    elseif state.playerCtrlImg then
        -- ★ 图片立绘：1 格高 × 原图宽高比，底边压脚线（playerFootOffset 返回半格）
        state.playerBodyH = cell
        utils.setSize(state.playerCtrl, cell * (config.DEFAULT_HERO_IMG_W or 0.62), cell)
        M.applyPlayerImage()
        utils.setVisible(state.playerCtrl, true)
        utils.setVisible(state.playerHeadCtrl, false)   -- 立绘自带头部
        utils.setVisible(state.heroArtBox, false)
    elseif state.playerCtrlArt then
        local fit = (config.DEFAULT_ART_FIT or {}).player or { w = 0.751, h = 1.126, dy = 0.508 }
        state.playerBodyH = cell * (fit.h or 1.126)   -- 控件的实际高度（锚点换算用得到）
        utils.setSize(state.playerCtrl, cell * (fit.w or 0.751), cell * (fit.h or 1.126))
        utils.setVisible(state.playerCtrl, true)
        utils.setVisible(state.playerHeadCtrl, false)   -- 立绘自带头部，不需要额外色块
        utils.setVisible(state.heroArtBox, false)
    else
        state.playerBodyH = cell * PLAYER_BODY_RATIO
        utils.setSize(state.playerCtrl, cell * 0.42, cell * PLAYER_BODY_RATIO)
        utils.setAlpha(state.playerCtrl, palette.playerBody, 255)
        utils.setVisible(state.playerCtrl, true)
        utils.setVisible(state.heroArtBox, false)
        if not state.playerHeadCtrl then
            state.playerHeadCtrl = utils.createControl(
                state.rectPrefabId, 0, 0, cell * 0.34, cell * PLAYER_HEAD_RATIO, nil, host)
        end
        utils.setSize(state.playerHeadCtrl, cell * 0.34, cell * PLAYER_HEAD_RATIO)
        utils.setAlpha(state.playerHeadCtrl, palette.playerHead, 255)
        utils.setVisible(state.playerHeadCtrl, true)
    end

    state.playerVisX = 0
    state.playerVisY = 0
    state.playerAnimT = 0
    state.playerAnimDur = 0
    M.syncPlayerNow()      -- 立刻吸附到出生格，别让第一帧从 (0,0) 滑进来
    M.restackWorld()       -- 首帧就要有正确的遮挡关系
end

-- ================================================================
-- ★ 涟漪特效控件（常驻隐藏，跨关卡复用）
-- ================================================================
local function buildRipple(palette)
    if not state.rippleCtrl then
        state.rippleCtrl = utils.createControl(
            state.rectPrefabId, 0, 0,
            config.DEFAULT_RIPPLE_SIZE or 70, config.DEFAULT_RIPPLE_SIZE or 70,
            utils.hexToColorA(palette.ripple or "FFFFFF", 0), state.containerFx)
    end
    state.rippleActive = false
    state.rippleT = 0
    utils.setVisible(state.rippleCtrl, false)
end

-- ================================================================
-- ★ 落地 / 立木扬尘控件（常驻隐藏，跨关卡复用）
--   和涟漪刻意分开：涟漪是「脚步」，扬尘是「砸下来」——
--   倒下时给一圈大的（咚），立起时给一圈小的（咔），两个动作的力度就分开了。
-- ================================================================
local function buildDust(palette)
    if not state.dustCtrl then
        local d = (config.DEFAULT_DUST_SIZE or 0.62) * (state.cellSize or 1)
        state.dustCtrl = utils.createControl(
            state.rectPrefabId, 0, 0, d, d * 0.45,
            utils.hexToColorA(palette.dust or "E9DCBE", 0), state.containerFx)
    end
    state.dustActive = false
    state.dustT = 0
    utils.setVisible(state.dustCtrl, false)
end

-- ================================================================
-- ★ 在某格脚下扬一圈尘（木头砸下来 / 被立起来的重量感）
--   scale：尺寸倍率 —— 撞倒 = 1.5（重），立起 = 0.85（轻）
-- ================================================================
function M.spawnDust(c, r, scale)
    if not state.dustCtrl then return end
    local cell = state.cellSize or 1
    local s = tonumber(scale) or 1
    local base = cell * (config.DEFAULT_DUST_SIZE or 0.62) * s
    state.dustX = cellCenterX(c)
    state.dustY = groundY(c, r) + cell * 0.06
    state.dustT = 0
    state.dustDur = config.DEFAULT_DUST_TIME or 0.34
    state.dustScale = s
    state.dustActive = true
    local palette = utils.resolvePalette(state.levelConfig or {})
    utils.setSize(state.dustCtrl, base, base * 0.45)
    utils.setAlpha(state.dustCtrl, palette.dust or "E9DCBE", config.DEFAULT_DUST_ALPHA or 150)
    utils.setPosition(state.dustCtrl, state.dustX, state.dustY)
    utils.setVisible(state.dustCtrl, true)
end

-- ================================================================
-- ★ 清空上一关（控件全部隐藏，池保留复用）
--   海面底（bgCtrl）跨关卡复用，不在这里处理。
-- ================================================================
function M.clear()
    lastRestackSig = nil          -- ★ 换关后第一次 restackWorld 必定要打一次层序日志
    poolTrim(state.terrainCtrls, 0)
    poolTrim(state.landBaseCtrls, 0)   -- ★ 第 31 批：顶面底色池
    poolTrim(state.skyCtrls, 0)        -- ★ 第 34 批：天空 / 云
    state.skyUsed = 0
    poolTrim(state.decoCtrls, 0)
    poolTrim(state.rimCtrls, 0)
    poolTrim(state.shadowCtrls, 0)
    poolTrim(state.objectCtrls, 0)
    poolTrim(state.rockCtrls, 0)     -- ★ 第 22 批：石头 / 木头两个新池一并清空
    poolTrim(state.rockFrontCtrls, 0)-- ★ 第 42 批：石头前景池
    state.rockSideTbl = {}           -- 分层缓存一起作废（下次 build 重新判断）
    state.rockSplitKey = nil
    poolTrim(state.logCtrls, 0)
    poolTrim(state.treeCtrls, 0)
    poolTrim(state.goalCtrls, 0)
    poolTrim(state.objProxyCtrls, 0)
    utils.setVisible(state.playerCtrl, false)
    utils.setVisible(state.playerHeadCtrl, false)
    utils.setVisible(state.playerShadowCtrl, false)
    utils.setVisible(state.heroArtBox, false)
    poolTrim(state.heroBlocks, 0)
    state.heroBlockUsed = 0
    state.heroDrawn = ""
    utils.setVisible(state.heroPrBox, false)
    if state.heroPrBoxes then
        for i = 1, #state.heroPrBoxes do
            utils.setVisible(state.heroPrBoxes[i], false)
        end
    end
    if state.heroPrPools then
        for pi = 1, #state.heroPrPools do
            local pool = state.heroPrPools[pi]
            for i = 1, #pool do
                utils.setVisible(pool[i] and pool[i].c, false)
            end
        end
    end
    state.heroPrDrawn = "" 
    utils.setVisible(state.rippleCtrl, false)
    utils.setVisible(state.dustCtrl, false)
    state.terrainUsed = 0
    state.landBaseUsed = 0
    state.decoUsed = 0
    state.terrainWinKey = ""      -- 换关 / 重开：地形窗口必须重铺
    state.objectUsed = 0
    state.rockUsed = 0
    state.logUsed = 0
    state.treeUsed = 0
    state.goalUsed = 0
    state.objProxyUsed = 0
    state.rippleActive = false
    state.dustActive = false
    -- ★ 换关 / 重开时把没播完的过渡一并丢掉：新关卡里那根木头已经不存在了
    state.objAnimActive = false
    state.objAnimFrom, state.objAnimTo = nil, nil
    state.objAnimT = 0
    -- ★ 第 37 批：转身过渡 + 步距基准也归零（否则新关卡第一帧会带着上一关的压扁系数）
    --   ★ 第 38 批：立体感的三个量（纵向补高 / 漂移 / 倾斜）一起归零，
    --     并且直接下发到根容器 —— 这里只清 state 的话，控件会停在上一关的姿态。
    state.heroTurnT = 0
    state.heroTurnDur = 0
    state.heroTurnFrom = ""
    state.heroPrTintK = 1
    resetHeroTurnPose()
    state.stepDistRef = nil
end

-- ================================================================
-- ★ 构建一关
-- ================================================================
-- 构建一张图
--   mapKey 给了就走**真实地图**（world.loadMap）；没给就走编辑器关卡（world.load）
function M.build(data, mapKey)
    if mapKey then
        if not world.loadMap(mapKey) then return false end
        data = state.levelConfig or data
    else
        if not data then return false end
        if not world.load(data) then return false end
    end

    M.computeGeometry()
    local palette = utils.resolvePalette(data)

    M.clear()                 -- 先把上一关的可见控件收起来（池子保留复用）
    buildTerrain(palette, true)
    M.rebuildObjects()
    buildPlayer(palette)
    buildRipple(palette)
    buildDust(palette)
    M.updateHudDisplay()
    -- ★ 镜头自检：真机上「地块还是原来那么大 / 走起来人物不居中」时先看这一行
    if type(print) == "function" then
        local ww, wh = math.floor(state.worldPxW or 0), math.floor(state.worldPxH or 0)
        local cw, chh = math.floor(state.canvasW or 0), math.floor(state.canvasH or 0)
        local needFollow = (ww > cw) or (wh > (chh - (config.DEFAULT_HUD_BAR_HEIGHT or 74)
            - (config.DEFAULT_HUD_BOTTOM_RESERVE or 88)))
        pcall(print, string.format(
            "[浮岛借木] 镜头 zoom=%s cell=%d 地图=%dx%d 画布=%dx%d | %s",
            tostring(state.viewZoom), math.floor(state.cellSize or 0), ww, wh, cw, chh,
            needFollow and "一屏装不下 → 镜头钉在「玩家所在岛的中心」（岛内走动画面不动，换岛才平移）"
                        or "一屏装得下 → 镜头不动"))
        -- ★ 动作节奏（第 37 批）：真机报「走得慢 / 转身没效果」时，先看这一行对不对
        local turnDur = tonumber(config.DEFAULT_HERO_TURN_TIME) or 0
        local turnSq = tonumber(config.DEFAULT_HERO_TURN_SQUASH) or 1
        pcall(print, string.format(
            "[浮岛借木] 动作 步时=%.2fs 转身=%.2fs(压到 %.0f%%) 摆动周期=%.2fs | 转身过渡=%s",
            tonumber(config.DEFAULT_STEP_ANIM_TIME) or 0, turnDur, turnSq * 100,
            tonumber(config.DEFAULT_HERO_WALK_PERIOD) or 0,
            (turnDur > 0.01 and turnSq < 0.99) and "开" or "关（瞬切）"))
        -- ★ 第 38 批：三个新增量各自生效与否，一眼能看出来（真机报「转身不立体」先看这行）
        -- ★ 第 39 批：「远侧手臂」这档取代了原来的「飘带」——
        --   报「走路时身前 / 身后还有带子在飘」先看这里是 0% 还是非 0。
        local farArm = tonumber(config.DEFAULT_HERO_FAR_ARM) or 0
        pcall(print, string.format(
            "[浮岛借木] 立体 补高=%.0f%% 漂移=%.3f格 倾斜=%.1f° | 远侧手臂=%.0f%% 腿深=%.2f | 视角宽 S=%.2f A=%.2f D=%.2f W=%.2f",
            (tonumber(config.DEFAULT_HERO_TURN_DEPTH) or 0) * 100,
            tonumber(config.DEFAULT_HERO_TURN_DRIFT) or 0,
            tonumber(config.DEFAULT_HERO_TURN_TILT) or 0,
            farArm * 100,
            tonumber(config.DEFAULT_HERO_LEG_SHADE) or 1,
            heroViewWidthOf("S"), heroViewWidthOf("A"), heroViewWidthOf("D"), heroViewWidthOf("W")))
        -- ★ 第 40 批：石头到底是柱子还是老石块 —— 真机报「没变化」先看这一行。
        --   rockPrims.lua 没在「客户端脚本资源管理器」里建映射 → 这里会是「旧石块」。
        local pillarOn = rockPillarOn()
        local glowOn = rockGlowOn()
        local fullN = pillarOn and ((rockPrims.BASE_N or 0) + (glowOn and (rockPrims.GLOW_N or 0) or 0)) or 2
        local nVis = math.max(1, state.rockDrawn or 0)
        local budget = tonumber(config.DEFAULT_PILLAR_BUDGET) or 0
        local per = fullN
        if budget > 0 then per = math.min(fullN, math.floor(budget / nVis)) end
        pcall(print, string.format(
            "[浮岛借木] 石头=%s 柱高=%.2f格 柱宽=%.2f格 轮廓=%d 辉光=%s 满配=%d笔/根"
            .. " | 可视窗 %d/%d 根 配额=%d笔 实际=%d笔 前景=%d 色块=%d 遮挡=%s",
            pillarOn and "图腾柱(图元笔触)" or (rockPrims and "旧石块(rockPillar=-1)" or "旧石块(rockPrims 未加载)"),
            tonumber(config.DEFAULT_PILLAR_H) or 0,
            -- 柱身实测宽 = rockPrims.W 里扣掉两侧边缘笔触（≈0.26）；W 本身是最外沿，别当柱宽
            (tonumber(config.DEFAULT_PILLAR_H) or 0) * (rockPrims and rockPrims.BODY_W or rockPrims and rockPrims.W or 0),
            (rockPrims and rockPrims.SIL_N) or 0,
            glowOn and "开" or "关",
            fullN,
            state.rockDrawn or 0, #(state.rocks or {}),
            per,
            (state.rockUsed or 0) + (state.rockFrontUsed or 0),
            state.rockFrontDrawn or 0,
            state.rockFlat or 0,
            rockOccludeOn() and "开" or "关"))
    end
    -- ★ 图层顺序日志：关卡构建完成时打一次完整层序（见 M.logLayerOrder）
    M.logLayerOrder("关卡构建完成")
    return (state.playerCtrl ~= nil)
        or (state.heroPr and state.heroPrBox ~= nil)
        or (state.heroPixel and state.heroArtBox ~= nil)
end

-- ================================================================
-- ★ 小人的视觉位置：立刻同步到当前格（关卡重建 / 重开时用）
-- ================================================================
function M.syncPlayerNow()
    local px, py = playerAnchor()
    state.playerVisX = px
    state.playerVisY = py
    state.playerAnimFromX = px
    state.playerAnimFromY = py
    state.playerAnimT = 0
    state.playerAnimDur = 0
    utils.setPosition(state.playerCtrl, px, py)
    placeHeroArt()                       -- 像素画：整幅画贴在脚底线上
    state.heroWalkPhase = 0              -- 换关 / 重开：摆动归零，别带着旧相位
    state.heroWalkAmp = 0
    M.updateHeroWalk(0)
    placeHeroPrims()                     -- 图元笔触：整幅画贴在脚底线上
    -- ★ 转身过渡也要归零（第 37 批）：万一是在「压扁到一半」时重开 / 换关，
    --   小人会停在 32% 宽 —— 显式复位朝向、计时与姿态，别指望控件自己回正。
    state.heroFacing = state.playerFacing or "S"
    state.heroTurnT = 0
    state.heroTurnDur = 0
    state.heroTurnFrom = ""
    state.heroPrTintK = 1
    resetHeroTurnPose()
    state.stepDistRef = nil              -- 一步的屏幕距离基准（换关 / 改缩放后必须重算）
    utils.setPosition(state.playerShadowCtrl, px, py - playerFootOffset() - (state.cellSize or 1) * 0.01)
    local cell = state.cellSize or 1
    local bodyH = state.playerBodyH
    if not bodyH or bodyH <= 0 then bodyH = cell * PLAYER_BODY_RATIO end
    utils.setPosition(state.playerHeadCtrl, px, py + bodyH * 0.5 - cell * PLAYER_HEAD_RATIO * 0.5)
    -- ★ 位置刚吸附好，镜头也立刻对准（换关 / 重开时不要让画面从上一关滑过来）
    M.snapCamera()
end

-- ================================================================
-- ★ 开始一次位移动画（从当前位置走向新位置）
--   ★ 顺手重排一次世界：小人换行之后，「前面的树挡不挡得住它」会变。
--   ★ 第 37 批：`byDistance = true` 时按**实际剩下的屏幕距离**缩放时长。
--     步时加长到 0.26 秒后，玩家连按方向键很常见 —— 上一步还没走完就被打断，
--     新的一步从半路起步、实际要走「剩余 + 1 格」。若仍给完整步时，
--     屏幕上会突然快一截（同样的 0.26 秒跑 1.6 格），读作「抽了一下」。
--     按距离同比例调时长 = 屏幕速度恒定；没被打断时系数正好是 1，一切照旧。
-- ================================================================
function M.beginPlayerMove(duration, byDistance)
    state.playerAnimFromX = state.playerVisX
    state.playerAnimFromY = state.playerVisY
    state.playerAnimT = 0
    local dur = math.max(0.001, tonumber(duration) or config.DEFAULT_STEP_ANIM_TIME or 0.1)

    if byDistance then
        local tx, ty = playerAnchor()
        local ddx = tx - state.playerAnimFromX
        local ddy = ty - state.playerAnimFromY
        local dist = math.sqrt(ddx * ddx + ddy * ddy)
        local ref = tonumber(state.stepDistRef) or 0
        -- 基准 = 观测到的最小单步距离（正常一步恒为这个值；被打断只会更大）。
        -- ⚠️ 换关 / 缩放变化时必须在 syncPlayerNow 里清掉，否则基准会过期。
        if ref <= 0 or dist < ref then
            ref = dist
            state.stepDistRef = ref
        end
        if ref > 1 and dist > 1 then
            dur = dur * utils.clamp(dist / ref, 0.55, 1.9)
        end
    end

    state.playerAnimDur = dur
    M.restackWorld()
end

-- ================================================================
-- ★ 每帧推进：小人位移补间 + 涟漪 + 木头倒/立的过渡 + 落地扬尘
-- ================================================================
function M.updateVisuals(dt)
    local cell = state.cellSize or 1
    local bodyH = state.playerBodyH
    if not bodyH or bodyH <= 0 then bodyH = cell * PLAYER_BODY_RATIO end

    -- ① 小人
    local tx, ty = playerAnchor()
    if state.playerAnimT < state.playerAnimDur then
        state.playerAnimT = state.playerAnimT + (dt or 0)
        local k = utils.smoothstep(utils.clamp(state.playerAnimT / state.playerAnimDur, 0, 1))
        state.playerVisX = utils.lerp(state.playerAnimFromX, tx, k)
        state.playerVisY = utils.lerp(state.playerAnimFromY, ty, k)
    else
        state.playerVisX = tx
        state.playerVisY = ty
    end
    utils.setPosition(state.playerCtrl, state.playerVisX, state.playerVisY)
    placeHeroArt()                       -- 像素画：每帧只移动这一个容器
    M.updateHeroTurn(dt)                 -- 转身过渡：决定这一帧画哪个朝向、压多扁
    M.updateHeroWalk(dt)                 -- 图元笔触：先更新摆臂/迈腿的角度
    placeHeroPrims()                     -- 图元笔触：每帧只移动这一个容器
    utils.setPosition(state.playerShadowCtrl, state.playerVisX,
                      state.playerVisY - playerFootOffset() - cell * 0.01)
    utils.setPosition(state.playerHeadCtrl, state.playerVisX,
                      state.playerVisY + bodyH * 0.5 - cell * PLAYER_HEAD_RATIO * 0.5)

    -- ★ ①-b 镜头：跟着**刚算出来的** playerVisX/Y 走，所以和位移补间同一曲线。
    --   顺序很关键 —— 必须在小人位姿更新之后，否则镜头会慢一帧（走起来画面会抖）。
    updateCamera()

    -- ★ ①-c 地形窗口：真实地图最大 26×72，一次铺满会造上千条控件。
    --   镜头把小人钉在屏幕中央 → 只有走到 4 格的块边界才需要重铺；
    --   判定只是一次字符串比较，逐帧调也不心疼。
    M.ensureTerrain()

    -- ② 涟漪
    if state.rippleActive and state.rippleCtrl then
        local dur = state.rippleDur or config.DEFAULT_RIPPLE_TIME or 0.45
        state.rippleT = state.rippleT + (dt or 0)
        local k = utils.clamp(state.rippleT / dur, 0, 1)
        local base = config.DEFAULT_RIPPLE_SIZE or 70
        local size = base * (1 + 0.9 * k)
        local data = state.levelConfig or {}
        local palette = utils.resolvePalette(data)
        local hex = palette.ripple or "FFFFFF"
        utils.setSize(state.rippleCtrl, size, size * 0.42)
        utils.setAlpha(state.rippleCtrl, hex, math.floor((config.DEFAULT_FX_ALPHA or 170) * (1 - k)))
        if k >= 1 then
            state.rippleActive = false
            utils.setVisible(state.rippleCtrl, false)
        end
    end

    -- ③ 木头「倒 / 立」的过渡（逐帧重画代理；播完自己收尾）
    M.animateObject(dt)

    -- ④ 落地 / 立木扬尘：先快速铺开、再减速，透明度一路衰减
    if state.dustActive and state.dustCtrl then
        local ddur = state.dustDur or config.DEFAULT_DUST_TIME or 0.34
        state.dustT = state.dustT + (dt or 0)
        local k = utils.clamp(state.dustT / ddur, 0, 1)
        local base = (state.cellSize or 1) * (config.DEFAULT_DUST_SIZE or 0.62)
                     * (state.dustScale or 1)
        local grow = 1 + 0.85 * utils.smoothstep(k)
        local palette = utils.resolvePalette(state.levelConfig or {})
        utils.setSize(state.dustCtrl, base * grow, base * grow * 0.45)
        utils.setAlpha(state.dustCtrl, palette.dust or "E9DCBE",
                       math.floor((config.DEFAULT_DUST_ALPHA or 150) * (1 - k) * (1 - k)))
        if k >= 1 then
            state.dustActive = false
            utils.setVisible(state.dustCtrl, false)
        end
    end
end

-- ================================================================
-- ★ 在某格脚下放一圈涟漪（动作反馈）
--   ⚠️ 默认**关掉**（config.DEFAULT_FX_RIPPLE_ON = 0）：
--      涟漪是一块纯白矩形（图元只有矩形，画不出圆），真机上就是小人脚下一块
--      白框，把草地和角色的脚一起糊住。控件仍然常驻创建、只是不显示，
--      所以开着它也不会改变控件总数（探针数不变）。
-- ================================================================
function M.spawnRipple(c, r)
    if (config.DEFAULT_FX_RIPPLE_ON or 0) <= 0 then return end
    if not state.rippleCtrl then return end
    local data = state.levelConfig or {}
    local palette = utils.resolvePalette(data)
    state.rippleX = cellCenterX(c)
    state.rippleY = groundY(c, r) + (state.cellSize or 1) * 0.10
    state.rippleT = 0
    state.rippleDur = config.DEFAULT_RIPPLE_TIME or 0.45
    state.rippleActive = true
    local base = config.DEFAULT_RIPPLE_SIZE or 70
    utils.setSize(state.rippleCtrl, base, base * 0.42)
    utils.setAlpha(state.rippleCtrl, palette.ripple or "FFFFFF", config.DEFAULT_FX_ALPHA or 170)
    utils.setPosition(state.rippleCtrl, state.rippleX, state.rippleY)
    utils.setVisible(state.rippleCtrl, true)
end

-- ================================================================
-- ★ 按「UTF-8 字符数」折行
--   ★ 不依赖 utf8 库（沙箱里不一定有）：靠首字节判断字符长度，
--     绝不会把一个汉字 / emoji 从中间切开。
-- ================================================================
local function charBytes(b)
    if b < 0x80 then return 1 end
    if b < 0xE0 then return 2 end
    if b < 0xF0 then return 3 end
    return 4
end

local function wrapByChars(s, width)
    local text = tostring(s or "")
    local w = tonumber(width) or 0
    if w <= 0 or #text == 0 then return text end
    local out, line, count = {}, {}, 0
    local i = 1
    while i <= #text do
        local b = text:byte(i)
        local n = charBytes(b or 0)
        -- 保护：截断处若落在半个字符上，直接收尾
        if i + n - 1 > #text then n = #text - i + 1 end
        local ch = text:sub(i, i + n - 1)
        if ch == "\n" then
            out[#out + 1] = table.concat(line)
            line, count = {}, 0
        else
            line[#line + 1] = ch
            count = count + 1
            if count >= w then
                out[#out + 1] = table.concat(line)
                line, count = {}, 0
            end
        end
        i = i + n
    end
    if #line > 0 then out[#out + 1] = table.concat(line) end
    return table.concat(out, "\n")
end

-- ================================================================
-- ★ HUD 文本刷新（关卡名 / 步数 / 状态）
-- ================================================================
function M.updateHudDisplay()
    local data = state.levelConfig or {}
    local palette = utils.resolvePalette(data)
    local alpha = config.DEFAULT_HUD_TEXT_ALPHA or 255
    local title = state.mapName
    if not title or title == "" then title = data.name or "浮岛借木" end
    local total = world.mapCount and world.mapCount() or 0
    if total > 0 and state.levelIndex then
        title = string.format("%s（%d/%d）", title, state.levelIndex, total)
    end
    utils.setText(state.hudTitle, title)
    -- ★ 禁用缺字形的符号（✓ ▶ 等）：雅黑/宋体/黑体里没有，会渲染成豆腐块
    local info = string.format("步数 %d", state.steps or 0)
    -- 番外图收集到的密码碎片（读到一块就 +1）
    local nfrag = 0
    for _ in pairs(state.fragments or {}) do nfrag = nfrag + 1 end
    if nfrag > 0 then info = info .. string.format("   碎片 %d/8", nfrag) end
    if state.won then info = info .. "   （已通关）" end
    utils.setText(state.hudInfo, info)
    utils.setTextColor(state.hudTitle, palette.hud, alpha)
    utils.setTextColor(state.hudInfo, palette.hud, alpha)
    utils.setTextColor(state.hudHint, palette.hint, alpha)
    -- 提示文本按 F 开关；每条按 DEFAULT_HINT_WRAP 字符数折行，多条各占一行
    local hintLines = data.hints or {}
    local parts = {}
    for _, line in ipairs(hintLines) do
        parts[#parts + 1] = wrapByChars(line, config.DEFAULT_HINT_WRAP)
    end
    utils.setText(state.hudHint, state.hintsOn and table.concat(parts, "\n") or "")
    utils.setVisible(state.hudHint, state.hintsOn and #hintLines > 0)
end

return M
