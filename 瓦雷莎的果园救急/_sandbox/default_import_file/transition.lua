-- ================================================================
-- 瓦雷莎的果园救急 · 全屏转场（选关 ↔ 游玩）
-- ================================================================
-- 只用两种转场：
--
--   ① fade   淡入淡出（黑幕，fadeScreen 提供）—— 重玩 / 关卡之间换片，最快
--   ② split  ★ 天地撕开 —— 选关 ↔ 游玩，唯一的大转场
--
-- split 用两块「风格化的天地」板：
--     上半 = 天空（三段天光 + 三团云 + 远丘 / 近丘 + 远处树点 + 撕裂边）
--     下半 = 地面（受光草坡 + 小草 + 落果 + 石子 + 撕裂边）
--   配色与选关场景同族（sky / hill / grass / soil），所以板子压上去、
--   以及最后淡出时都不刺眼；两块板各带一条深色「纸厚度」，撕开时有层次。
--
--   · 进入果园（mode = "open"）0.42s
--       两块板已在屏上合拢 → 立刻切屏（3D 在板后渲染）
--       → 天空向上移出屏幕、地面向下移出屏幕 → 果园从中间的裂缝「长」出来
--
--   · 返回选关（mode = "close"）0.24 + 0.04 + 0.16 = 0.44s
--       天空从上方移入、地面从下方移入（快进慢停，像两片帘子合上）
--       → 合拢瞬间切屏 → 板整体淡出，露出选关地图
--
-- ★ 两块板各只有一个容器在动（setPos / setScaleXY），子控件全是死的 → 不吃帧。
-- ★ 所有图元都严格画在板内（容器不裁剪，溢出会盖到屏幕另一半）。
-- ★ 挂在 containerFade（7 层里最顶）之下，天然盖住地图 / HUD / 教程 / 结算。
-- ★ 拿不到模板（没配 rectPrefabId）时退化成「立刻切屏」，流程不会卡。
-- ================================================================

---@diagnostic disable: undefined-global

local M = {}

local state = require("default_import_file/state")
local config = require("default_import_file/config")
local utils = require("default_import_file/utils")
local fadeScreen = require("default_import_file/fadeScreen")

-- ================================================================
-- 对外状态
-- ================================================================
M.kind = ""            -- "" | "split"（fade 直接交给 fadeScreen，不占这里）
M.mode = "open"        -- open = 进入果园（板分开）| close = 返回选关（板合拢 + 淡出）
M.phase = "idle"       -- idle | cover | hold | reveal
M.t = 0
M.cover = 0
M.hold = 0
M.reveal = 0
M.onPeak = nil

local nodes = {}
local built = false

-- 两块板在屏幕中线处的重叠量（防取整露缝；★ 别给太大，否则合拢时两条撕裂边会互相盖住）
local OVER = 8
-- 完全移出屏幕后再多走的距离
local PAD = 30

local function cw() return state.canvasW or config.DEFAULT_VIEW_WIDTH or 800 end
local function ch() return state.canvasH or config.DEFAULT_VIEW_HEIGHT or 600 end
local function pal() return utils.palette() end

-- ================================================================
-- 缓动
-- ================================================================
-- 「丝滑」用这条：起步缓、中段快、收尾缓，没有硬拐点
local function easeInOutCubic(x)
    if x < 0.5 then return 4 * x * x * x end
    local u = -2 * x + 2
    return 1 - u * u * u / 2
end

-- 合拢用这条：一进来就快，贴到位时慢慢停 → 有「啪」地合上的手感
local function easeOutCubic(x)
    local u = 1 - x
    return 1 - u * u * u
end

-- ================================================================
-- 几何
-- ================================================================
-- 板高 = 半屏 + 重叠
local function boardH() return ch() / 2 + OVER end

-- 合拢位置：上半板中心 +H/4、下半板中心 -H/4（两块正好拼满全屏）
local function homeY(top)
    if top then return ch() / 4 end
    return -ch() / 4
end

-- 完全移出屏幕的位置（板彻底离开画布，再留 PAD 余量）
local function awayY(top)
    local d = ch() / 2 + boardH() / 2 + PAD
    if top then return d end
    return -d
end

-- ================================================================
-- 建节点（只建一次）
-- ================================================================
local function newRect(pid, x, y, w, h, keyHex, alpha, parent)
    return utils.createControl(pid, x, y, w, h, utils.hexToColorA(keyHex, alpha or 255), parent)
end

-- 记下 (句柄, 原色)，淡出时要逐个改 alpha
local function reg(list, ctrl, hex)
    if ctrl then list[#list + 1] = { ctrl = ctrl, hex = hex } end
    return ctrl
end

-- ----------------------------------------------------------------
-- 上半板：天空
--   ★ 所有圆 / 三角都让「外沿」正好落在板边上（不越界，容器不裁剪）。
-- ----------------------------------------------------------------
local function buildSky(p, pid, c)
    local bw, th = cw() + 90, boardH()
    local hh = th / 2
    local list = {}
    local root = utils.createContainer(p, bw, th)
    if not root then return nil, list end
    utils.setPos(root, 0, homeY(true))

    local function rect(x, y, w, h, hex, a)
        return reg(list, newRect(pid, x, y, w, h, hex, a or 255, root), hex)
    end
    local function circle(x, y, w, h, hex, a)
        return reg(list, utils.circleC(x, y, w, h, hex, a or 255, root), hex)
    end
    local function tri(x, y, w, h, hex, a)
        return reg(list, utils.triangleC(x, y, w, h, hex, a or 255, root), hex)
    end

    -- ① 天光：三段几乎同色，越靠地平线越亮（色差小才看不出「横带」）
    local s1 = c.skyTop
    local s2 = utils.mixHex(c.skyTop, c.sky, 0.62)
    local s3 = utils.mixHex(c.sky, c.cream, 0.20)
    rect(0, hh - th * 0.19, bw, th * 0.38 + 2, s1)
    rect(0, hh - th * 0.55, bw, th * 0.34 + 2, s2)
    rect(0, hh - th * 0.86, bw, th * 0.28 + 2, s3)

    -- ② 云：三团，每团「左肩 + 右肩 + 主峰 + 压扁的底」
    local clouds = {
        { x = -bw * 0.26, y = hh - th * 0.30, r = th * 0.076 },
        { x = bw * 0.21, y = hh - th * 0.52, r = th * 0.056 },
        { x = bw * 0.02, y = hh - th * 0.13, r = th * 0.044 },
    }
    for _, cl in ipairs(clouds) do
        local r = cl.r
        circle(cl.x - r * 0.95, cl.y - r * 0.10, r * 1.55, r * 1.55, c.wave, 210)
        circle(cl.x + r * 0.95, cl.y - r * 0.14, r * 1.30, r * 1.30, c.wave, 200)
        circle(cl.x, cl.y + r * 0.42, r * 1.85, r * 1.85, c.wave, 235)
        circle(cl.x, cl.y - r * 0.30, r * 3.30, r * 0.95, c.cream, 190)
    end

    -- ③ 远丘 / 近丘：扁椭圆，圆心贴板底 → 只露上半，正好坐在地平线上
    --   ★ 混一点天空色做「空气透视」，远丘自然退到后面去（别用纯 hill，
    --     否则和近丘一个绿，看起来就是一块大绿饼）。
    local mh = th * 0.135
    local farHill = utils.mixHex(c.hill, c.skyDeep, 0.46)
    local nearHill = utils.mixHex(c.hill, c.leaf, 0.26)
    circle(-bw * 0.27, -hh + mh * 0.95, bw * 0.68, mh * 1.90, farHill)
    circle(bw * 0.23, -hh + mh * 0.70, bw * 0.82, mh * 1.40, nearHill)

    -- ④ 远处的小树点：只当纹理，别做成「一排圆球」
    local bush = utils.mixHex(c.leaf, c.hill, 0.42)
    for i = 1, 6 do
        local x = -bw * 0.38 + (i - 1) * bw * 0.152 + ((i % 3) - 1) * bw * 0.014
        local r = th * (0.017 + 0.005 * ((i * 5) % 3))
        circle(x, -hh + r + mh * 0.46, r * 2.3, r * 1.9, bush, 225)
    end

    -- ⑤ 撕裂边：一条「纸厚度」，撕开时才看得出是两块板
    --   ★ 别压太深：mix 到 shadow 会变成一条脏黑线，在亮色插画里很扎眼。
    rect(0, -hh + 6, bw, 12, utils.mixHex(c.skyDeep, c.shadow, 0.05))

    return root, list
end

-- ----------------------------------------------------------------
-- 下半板：地面
-- ----------------------------------------------------------------
local function buildGround(p, pid, c)
    local bw, th = cw() + 90, boardH()
    local hh = th / 2
    local list = {}
    local root = utils.createContainer(p, bw, th)
    if not root then return nil, list end
    utils.setPos(root, 0, homeY(false))

    local function rect(x, y, w, h, hex, a)
        return reg(list, newRect(pid, x, y, w, h, hex, a or 255, root), hex)
    end
    local function circle(x, y, w, h, hex, a)
        return reg(list, utils.circleC(x, y, w, h, hex, a or 255, root), hex)
    end
    local function tri(x, y, w, h, hex, a)
        return reg(list, utils.triangleC(x, y, w, h, hex, a or 255, root), hex)
    end

    -- ① 草底：整体铺满，上面压一层略亮的「受光草坡」
    rect(0, 0, bw, th + 2, c.grass)
    rect(0, hh - th * 0.165, bw, th * 0.33, utils.mixHex(c.grass, c.hill, 0.42))

    -- ② 小草：每组三片（中间高、两侧矮而且更绿）
    local tufts = { -0.42, -0.26, -0.08, 0.14, 0.33, 0.45 }
    for i, fx in ipairs(tufts) do
        local x = bw * fx
        local base = hh - th * (0.30 + (i % 2) * 0.055)
        local hgt = th * 0.095
        tri(x, base + hgt * 0.50, hgt * 0.52, hgt, utils.mixHex(c.leaf, c.grass, 0.18))
        tri(x - hgt * 0.36, base + hgt * 0.34, hgt * 0.42, hgt * 0.68,
            utils.mixHex(c.leaf, c.grass, 0.52))
        tri(x + hgt * 0.38, base + hgt * 0.38, hgt * 0.40, hgt * 0.76,
            utils.mixHex(c.leaf, c.grass, 0.34))
    end

    -- ③ 落在草里的果子（红苹果 / 果汁橙各一点，呼应主玩法）
    circle(-bw * 0.30, -th * 0.300, th * 0.070, th * 0.066, c.fruit)
    circle(-bw * 0.305, -th * 0.277, th * 0.020, th * 0.016, c.cream, 175)
    circle(bw * 0.16, -th * 0.262, th * 0.056, th * 0.052, c.juice)
    circle(bw * 0.35, -th * 0.352, th * 0.048, th * 0.044, c.fruit, 235)

    -- ④ 几颗小石子
    circle(-bw * 0.11, -th * 0.392, th * 0.032, th * 0.024, c.sand, 215)
    circle(bw * 0.27, -th * 0.398, th * 0.024, th * 0.018, c.sand, 195)

    -- ⑤ 撕裂边（贴板顶）：草地的深色边
    rect(0, hh - 6, bw, 12, utils.mixHex(c.grass, c.shadow, 0.45))

    return root, list
end

function M.init()
    if built then return true end
    local p = state.containerFade or state.parent
    local pid = state.rectPrefabId or 0
    if not p or pid <= 0 then return false end

    local c = pal()
    local topRoot, topList = buildSky(p, pid, c)
    local botRoot, botList = buildGround(p, pid, c)
    nodes.top = { root = topRoot, list = topList }
    nodes.bottom = { root = botRoot, list = botList }

    if not topRoot or not botRoot then
        -- 只建出一半（模板缺失）→ 收掉，退化成淡入淡出
        if topRoot then pcall(function() topRoot:SetActive(false) end) end
        if botRoot then pcall(function() botRoot:SetActive(false) end) end
        nodes.top, nodes.bottom = {}, {}
        return false
    end

    utils.setVisible(topRoot, false)
    utils.setVisible(botRoot, false)
    built = true
    return true
end

-- ================================================================
-- 整块改 alpha（close 收尾的淡出用）
-- ================================================================
local function setBoardAlpha(a)
    for _, b in ipairs({ nodes.top, nodes.bottom }) do
        if b and b.list then
            for i = 1, #b.list do
                local it = b.list[i]
                utils.setColor(it.ctrl, it.hex, a)
            end
        end
    end
end

-- ================================================================
-- 逐帧摆放
-- ================================================================
local function applySplit(t)
    local top, bot = nodes.top, nodes.bottom
    if not top or not top.root or not bot or not bot.root then return end

    local hy, ay = homeY(true), awayY(true)
    local hb, ab = homeY(false), awayY(false)

    if M.phase == "cover" then
        -- close：从屏幕外滑入并合拢（天空自上、地面自下）
        local k = utils.clamp(t / math.max(0.01, M.cover), 0, 1)
        local e = easeOutCubic(k)
        local st = 1 + 0.030 * math.sin(k * math.pi)
        utils.setPos(top.root, 0, ay + (hy - ay) * e)
        utils.setPos(bot.root, 0, ab + (hb - ab) * e)
        utils.setScaleXY(top.root, 1, st)
        utils.setScaleXY(bot.root, 1, st)
    elseif M.mode == "open" then
        -- open：从合拢分开（天空向上出屏、地面向下出屏）
        local k = utils.clamp(t / math.max(0.01, M.reveal), 0, 1)
        local e = easeInOutCubic(k)
        -- 中途轻微拉长：像被抽走时被「带」了一下，比纯平移有质感
        local st = 1 + 0.035 * math.sin(k * math.pi)
        utils.setPos(top.root, 0, hy + (ay - hy) * e)
        utils.setPos(bot.root, 0, hb + (ab - hb) * e)
        utils.setScaleXY(top.root, 1, st)
        utils.setScaleXY(bot.root, 1, st)
    else
        -- close 的 reveal：已经合拢盖满 → 整体淡出，露出选关地图
        local k = utils.clamp(t / math.max(0.01, M.reveal), 0, 1)
        setBoardAlpha(math.floor(255 * (1 - k) + 0.5))
        utils.setPos(top.root, 0, hy)
        utils.setPos(bot.root, 0, hb)
        utils.setScaleXY(top.root, 1, 1)
        utils.setScaleXY(bot.root, 1, 1)
    end
end

function M.apply(t)
    if M.kind == "split" then applySplit(t) end
end

-- ================================================================
-- 启动
--   kind: "fade" | "split"
--   opts: { mode = "open"|"close", cover=, hold=, reveal=,
--           fadeInTime/fadeOutTime/maxAlpha/colorHex（仅 fade） }
-- ================================================================
function M.play(kind, onPeak, opts)
    opts = opts or {}
    kind = tostring(kind or "fade")

    -- ① 淡入淡出：直接交给 fadeScreen（它自带黑幕节点）
    if kind == "fade" then
        M.finish()
        return fadeScreen.start({
            onPeak = onPeak,
            fadeInTime = opts.cover or (config.DEFAULT_TRANS_FADE_IN or 0.18),
            holdTime = opts.hold or (config.DEFAULT_TRANS_FADE_HOLD or 0.04),
            fadeOutTime = opts.reveal or (config.DEFAULT_TRANS_FADE_OUT or 0.22),
            colorHex = opts.colorHex,
            maxAlpha = opts.maxAlpha,
        })
    end

    if not built and not M.init() then
        if onPeak then pcall(onPeak) end      -- 缺模板：立刻切屏，别卡流程
        return false
    end

    M.finish()                                -- 清掉可能残留的上一次
    M.kind = "split"
    M.mode = (opts.mode == "close") and "close" or "open"
    M.t = 0
    M.hold = opts.hold or (config.DEFAULT_TRANS_HOLD or 0.04)
    M.onPeak = onPeak

    setBoardAlpha(255)
    utils.setScaleXY(nodes.top.root, 1, 1)
    utils.setScaleXY(nodes.bottom.root, 1, 1)
    utils.setVisible(nodes.top.root, true)
    utils.setVisible(nodes.bottom.root, true)

    if M.mode == "open" then
        -- ★ 板先合拢盖住旧界面，紧接着立刻切屏 —— 然后板分开，露出新界面。
        --   玩家看到的顺序就是「选关画面被天地撕开，果园从缝里长出来」。
        M.cover = 0
        M.reveal = opts.reveal or (config.DEFAULT_TRANS_SPLIT_OPEN or 0.42)
        M.phase = "reveal"
        utils.setPos(nodes.top.root, 0, homeY(true))
        utils.setPos(nodes.bottom.root, 0, homeY(false))
        M.apply(0)
        if onPeak then
            M.onPeak = nil
            pcall(onPeak)
        end
    else
        M.cover = opts.cover or (config.DEFAULT_TRANS_SPLIT_MERGE or 0.24)
        M.reveal = opts.reveal or (config.DEFAULT_TRANS_SPLIT_FADE or 0.16)
        M.phase = "cover"
        utils.setPos(nodes.top.root, 0, awayY(true))
        utils.setPos(nodes.bottom.root, 0, awayY(false))
        M.apply(0)
    end
    return true
end

-- ================================================================
-- 每帧（在 OnUpdate 里调；放最后，保证盖在其他层之上）
-- ================================================================
function M.update(dt)
    if M.phase == "idle" or M.kind == "" then return end
    dt = tonumber(dt) or 0
    if dt <= 0 then return end
    M.t = M.t + dt

    if M.phase == "cover" then
        M.apply(math.min(M.t, M.cover))
        if M.t >= M.cover then
            M.phase = "hold"
            M.t = 0
            local cb = M.onPeak
            M.onPeak = nil
            if cb then pcall(cb) end
        end
    elseif M.phase == "hold" then
        if M.t >= M.hold then
            M.phase = "reveal"
            M.t = 0
        end
    else
        M.apply(math.min(M.t, M.reveal))
        if M.t >= M.reveal then M.finish() end
    end
end

-- ================================================================
-- 结束 / 立即收掉
-- ================================================================
function M.finish()
    if nodes.top and nodes.top.root then
        setBoardAlpha(255)
        utils.setScaleXY(nodes.top.root, 1, 1)
        utils.setPos(nodes.top.root, 0, awayY(true))
        utils.setVisible(nodes.top.root, false)
    end
    if nodes.bottom and nodes.bottom.root then
        utils.setScaleXY(nodes.bottom.root, 1, 1)
        utils.setPos(nodes.bottom.root, 0, awayY(false))
        utils.setVisible(nodes.bottom.root, false)
    end
    M.kind = ""
    M.phase = "idle"
    M.onPeak = nil
    M.t = 0
end

function M.isPlaying()
    return M.phase ~= "idle" and M.kind ~= ""
end

return M
