-- ================================================================
-- 瓦雷莎的果园救急 · 果园背景（基础图元拼装）
-- ================================================================
-- 从下到上：天空底 → 天空更深一层 → 太阳（圆 + 双层光晕 + 光芒）
--           → 云朵（几个椭圆叠出蓬松轮廓，缓慢横移）
--           → 远山（两排扁椭圆当圆丘，山脚压在地平线上）
--           → 草坡 → 草丛（小椭圆）→ 两团柔光 → 飘叶（小椭圆缓慢下落）
-- 全部挂在 containerScene（最底层），不遮任何界面，也不吃点击。
-- ★ 游玩期必须整层收起来：它是盖满画布的**不透明**底色，
--   不收会把节点图摆出来的 3D 果园整片盖住（真机实测现象）。
-- ★ 圆形/椭圆都走 utils.circleC：没配 circlePrefabId 时退化成矩形，
--   形状会变方但画面照常跑（真机配了圆形元件才出效果）。
-- ================================================================

---@diagnostic disable: undefined-global

local M = {}
local state = require("default_import_file/state")
local config = require("default_import_file/config")
local utils = require("default_import_file/utils")

M.nodes = {}
M.ready = false

local function add(ctrl)
    if ctrl then M.nodes[#M.nodes + 1] = ctrl end
    return ctrl
end

local function rect(x, y, w, h, hex, alpha)
    local c = utils.createControl(state.rectPrefabId, x, y, w, h,
        utils.hexToColorA(hex, alpha or 255), state.containerScene)
    -- ★ 必须显式提层：两个引擎的同级叠放顺序相反（真机后建在上 / 模拟器先建在上），
    --   只有「按从下到上的顺序连续 raise()」才能两边都对齐。
    --   漏了这一步的表现：整屏只剩最先建的那块天空底色（草地、远山全被盖住）。
    if c then utils.raise(c) end
    add(c)
    return c
end

-- 椭圆（宽高不等即椭圆）；没配圆形元件时退化成矩形
local function oval(x, y, w, h, hex, alpha, par)
    local c = utils.circleC(x, y, w, h, hex, alpha or 255, par or state.containerScene)
    if c then utils.raise(c) end
    add(c)
    return c
end

-- ================================================================
-- ★ 预创建
-- ================================================================
function M.init(pal)
    if M.ready then return true end
    if not state.containerScene then return false end
    if not state.rectPrefabId or state.rectPrefabId <= 0 then return false end
    pal = pal or utils.resolvePalette(nil)

    local cw = state.canvasW or config.DEFAULT_VIEW_WIDTH or 800
    local ch = state.canvasH or config.DEFAULT_VIEW_HEIGHT or 600
    local W, H = cw + 700, ch + 700

    -- ① 天空
    rect(0, 0, W, H, pal.sky)
    rect(0, ch * 0.26, W, ch * 0.72, pal.skyTop, 255)

    -- ② 太阳：两层光晕 + 圆日面 + 高光 + 6 根慢转光芒
    --    ★ 日面原来是「旋转 45° 的方块」，看着像块饼干；圆形元件才是太阳。
    -- ★ 坐标是「以画布中心为原点」的局部坐标：x 为负才是画面左侧。
    --   早期写成 cw*0.35 当成了屏幕左侧，结果太阳跑到右上角贴着边缘。
    local sunS = config.DEFAULT_SCENE_SUN_SIZE or 104
    -- 再往左下挪一点：贴太高会和顶部标题牌打架（光芒被牌切掉半截）
    local sx, sy = -cw * 0.33, ch * 0.235
    -- 光晕不跟着转，挂在外层
    -- 三层光晕（由外到内、由淡到浓）：两层会看出一个硬边圆盘，
    -- 三层才像光在往外渗。
    local haloFar = oval(sx, sy, sunS * 3.10, sunS * 3.10, pal.starEdge, 20)
    local haloMid = oval(sx, sy, sunS * 2.42, sunS * 2.42, pal.starEdge, 30)
    local haloNear = oval(sx, sy, sunS * 1.92, sunS * 1.92, pal.starEdge, 46)
    state.sceneSunHalo = { far = haloFar, mid = haloMid, near = haloNear, size = sunS }
    -- 日面 + 光芒装进一个小容器里，整体慢转就是「光芒在转」
    local sunRoot = utils.createContainer(state.containerScene)
    add(sunRoot)
    if sunRoot then
        utils.raise(sunRoot)
        local pl = state.containerScene
        utils.setPos(sunRoot, sx, sy)
        local function sunPart(x, y, w, h, hex, alpha, rot)
            local c = utils.circleC(x, y, w, h, hex, alpha, sunRoot)
            if c then
                utils.noRay(c)
                if rot then utils.setRotationZ(c, rot) end
            end
            return c
        end
        local rays = {}
        local rayD = sunS * 0.96
        for i = 1, 8 do
            local a = (i - 1) * 45
            local ax = math.cos(math.rad(a)) * rayD
            local ay = math.sin(math.rad(a)) * rayD
            rays[#rays + 1] = sunPart(ax, ay, sunS * 0.72, sunS * 0.10, pal.star, 150, a)
        end
        local sun = sunPart(0, 0, sunS, sunS, pal.star, 255)
        sunPart(0, 0, sunS * 0.62, sunS * 0.62, "FFF6D8", 215)
        state.sceneSun = { core = sun, rays = rays, root = sunRoot, size = sunS,
            halo = state.sceneSunHalo }
    end

    -- ③ 云朵：5 个椭圆叠出蓬松轮廓（上白下奶油，底部压平）
    --    ★ 云会横移过整屏，它挂在 containerScene，会被地图 UI 盖住，不抢视线。
    local cn = math.max(0, math.floor(config.DEFAULT_SCENE_CLOUD_COUNT or 5))
    for i = 1, cn do
        local holder = utils.createContainer(state.containerScene)
        if holder then utils.raise(holder) end
        add(holder)
        if holder then
            local s = 44 + (i % 3) * 15
            local y = ch * 0.10 + ((i * 37) % 100) / 100 * ch * 0.20
            -- ★ 云必须用「不透明」的同色圆叠：半透明会在一块云内部露一圈圈
            --   圆盘轮廓（像三张饼摞在一起），远看很脏。
            --   顺序 = 从下到上：底部奶油暗面 → 左右两团 → 中间大团 → 顶部小团。
            local parts = {
                { 0, -s * 0.13, s * 2.02, s * 0.40, pal.cream, 255 },
                { -s * 0.46, s * 0.00, s * 1.04, s * 0.74, pal.wave, 255 },
                { s * 0.46, s * 0.02, s * 0.96, s * 0.66, pal.wave, 255 },
                { 0, s * 0.12, s * 1.42, s * 0.88, pal.wave, 255 },
                { -s * 0.03, s * 0.44, s * 0.80, s * 0.68, pal.wave, 255 },
            }
            for _, p in ipairs(parts) do
                oval(p[1], p[2], p[3], p[4], p[5], p[6], holder)
            end
            utils.setPos(holder, -cw / 2 + (i - 0.5) * (cw / cn), y)
            state.sceneClouds[i] = {
                ctrl = holder, x = -cw / 2 + (i - 0.5) * (cw / cn), y = y,
                speed = 6 + (i % 3) * 3, span = cw + 280,
            }
        end
    end

    -- ④ 远山：两排扁椭圆当圆丘
    --   ★ 山脚必须压在地平线上。以前用「旋转 45° 的方块」，900p 下山尖
    --     会浮到天空中间，看着是几座悬空的大三角。
    local gh = config.DEFAULT_SCENE_GROUND_H or 310
    local groundTop = -ch / 2 + gh * 0.88
    local hillFar = utils.mixHex(pal.hill, pal.sky, 0.46)
    for i = 1, 6 do
        local hw = 430 + (i % 3) * 150
        local hh = 140 + (i % 4) * 42
        local x = -cw * 0.56 + (i - 1) * cw * 0.225
        oval(x, groundTop - 20 - hh * 0.05, hw, hh, hillFar, 255)
    end
    for i = 1, 5 do
        local hw = 540 + (i % 3) * 170
        local hh = 168 + (i % 3) * 48
        local x = -cw * 0.60 + (i - 1) * cw * 0.30
        oval(x, groundTop - hh * 0.05, hw, hh, pal.hill, 255)
    end

    -- ⑤ 草坡：远（浅）→ 中 → 近（深）三层弧带
    --   ★ 每层都用「超宽扁椭圆」而不是矩形：矩形上沿是一条笔直横线，
    --     900p 下像一道地板缝；弧线才像坡。
    --   ★ 分层按画布高算（-ch*0.26 / -ch*0.40），按 gh 算的话 900p 的
    --     远景会占掉半屏、近景又被压在屏外看不见（踩过）。
    rect(0, -ch / 2 + gh * 0.42, W, gh * 0.92, pal.hill, 255)
    local midTop, nearTop = -ch * 0.26, -ch * 0.40
    -- 田垄：远景上几条淡淡的横向条纹（只给一点纹理，别抢戏）
    local rowHex = utils.mixHex(pal.hill, pal.leaf, 0.30)
    for i = 1, 3 do
        local yy = groundTop - (groundTop - midTop) * (i / 4)
        oval((i % 2 == 0) and cw * 0.14 or -cw * 0.18, yy, W * 0.66, gh * 0.045, rowHex, 60)
    end
    -- 中景带
    oval(0, midTop - gh * 0.55, W * 1.32, gh * 1.10,
        utils.mixHex(pal.hill, pal.grass, 0.52), 255)
    -- 近景带
    oval(0, nearTop - gh * 0.45, W * 1.24, gh * 0.90, pal.grass, 255)
    -- 草垛：近景上一撮一撮的浅色草团
    for i = 1, 16 do
        local w = 40 + (i % 4) * 20
        local x = -cw * 0.55 + ((i * 97) % 100) / 100 * cw * 1.1
        local y = nearTop - 18 - ((i * 53) % 100) / 100 * (gh * 0.14)
        oval(x, y, w, w * 0.40, pal.leaf, 55)
    end

    -- ⑥ 两团柔光
    oval(cw * 0.32, ch * 0.30, 460, 380, pal.starEdge, 46)
    oval(-cw * 0.34, -ch * 0.30, 520, 320, pal.leaf, 26)

    -- ⑦ 风的线条：半透明细椭圆横向飘过，暗示「果园里有风」
    --   ★ 比飘叶更干净：飘叶又小又会转，远看像一群飞虫/小鸟。
    local wn = math.max(0, math.floor(config.DEFAULT_SCENE_WIND_COUNT or 9))
    for i = 1, wn do
        local len = 110 + (i % 4) * 74
        local c = add(oval(0, 0, len, len * 0.052, pal.wave,
            (config.DEFAULT_SCENE_WIND_ALPHA or 62)))
        if c then utils.setRotationZ(c, -6 + (i % 3) * 5) end
        state.sceneWinds[i] = {
            ctrl = c, len = len,
            x = -cw / 2 - 100 + (cw + 200) * (((i * 41) % 100) / 100),
            y = ch * 0.02 + ((i * 59) % 100) / 100 * ch * 0.34,
            speed = (config.DEFAULT_SCENE_WIND_SPEED or 130) * (0.65 + ((i * 13) % 7) / 6),
            phase = i * 1.3,
        }
    end

    M.ready = true
    return true
end

-- ================================================================
-- ★ 显隐整层
-- ================================================================
function M.setVisible(v)
    utils.setVisibleAll(M.nodes, v and true or false)
end

-- ================================================================
-- ★ 每帧：光芒慢转 + 云横移 + 飘叶下落
-- ================================================================
function M.update(dt)
    if not M.ready then return end
    dt = tonumber(dt) or 0
    if dt <= 0 then return end
    local cw = state.canvasW or config.DEFAULT_VIEW_WIDTH or 800
    local ch = state.canvasH or config.DEFAULT_VIEW_HEIGHT or 600
    local t = state.fxTime or 0
    local pal = utils.palette()

    local sun = state.sceneSun
    if sun then
        if sun.root then utils.setRotationZ(sun.root, t * 6) end
        if sun.core then
            local k = 1 + 0.035 * math.sin(t * 1.7)
            utils.setScale(sun.core, k)
        end
        -- 光晕呼吸：两层反向缩放 + 透明度起伏，看着像光在往外扩
        local halo = sun.halo
        if halo then
            local b1 = math.sin(t * 1.5)
            local b2 = math.sin(t * 1.9 + 1.2)
            local b0 = math.sin(t * 1.2 + 2.4)
            if halo.far then
                utils.setScale(halo.far, 1 + 0.09 * b0)
                utils.setColor(halo.far, pal.starEdge, 14 + 14 * (0.5 + 0.5 * b0))
            end
            if halo.mid then
                utils.setScale(halo.mid, 1 + 0.07 * b1)
                utils.setColor(halo.mid, pal.starEdge, 22 + 18 * (0.5 + 0.5 * b1))
            end
            if halo.near then
                utils.setScale(halo.near, 1 + 0.06 * b2)
                utils.setColor(halo.near, pal.starEdge, 38 + 22 * (0.5 + 0.5 * b2))
            end
        end
    end

    -- 风的线条：向右飘，出屏后从左边回来
    for i = 1, #state.sceneWinds do
        local w = state.sceneWinds[i]
        if w and w.ctrl then
            w.x = w.x + w.speed * dt
            if w.x > cw / 2 + w.len then w.x = -cw / 2 - w.len end
            utils.setPos(w.ctrl, w.x, w.y + math.sin(t * 0.8 + w.phase) * 7)
            utils.setSize(w.ctrl, w.len * (0.85 + 0.3 * (0.5 + 0.5 * math.sin(t * 0.7 + w.phase))),
                w.len * 0.052)
        end
    end

    for i = 1, #state.sceneClouds do
        local c = state.sceneClouds[i]
        if c and c.ctrl then
            c.x = c.x + c.speed * dt
            if c.x > cw / 2 + 160 then c.x = -cw / 2 - 160 end
            utils.setPos(c.ctrl, c.x, c.y + math.sin(t * 0.6 + i) * 4)
        end
    end


end

return M
