-- ================================================================
-- ★ 通关演出：四块撞击合拢 → 64×64 上色
--   ① 四块分别从上 / 右 / 下 / 左飞入，依次撞进自己的槽位（outBack 冲过头再回弹）
--   ② 落位瞬间：压扁—回弹（squash & stretch）+ 冲击环 + 镜头轻震
--   ③ 四块齐 → 白闪 → 64×64 彩图按对角线错峰淡入
--      ★ 彩图用「同色矩形合并」绘制，像素边界严格相邻并留 1px 重叠 → 中间绝不留行/列缝
-- ================================================================
doFinale = function()
    state.phase = "finish"
    state.inputReady = false
    view.setVisible(false)
    hud.setVisible(false)
    fx.clear()
    audio.playWin()

    local ch = config.getChapter(state.chapterIndex)
    local pal = config.DEFAULT_PALETTE or {}
    local accent = pal.accent or "4CC9F0"
    local cell, gap = 24, 2
    local Q = 8 * cell + 7 * gap          -- 单块边长 206
    local total = 2 * Q + gap             -- 合起来 414
    local half = total / 2
    local off = (Q + gap) / 2             -- 每块中心到整体中心的偏移 104

    local par = utils.createContainer(state.containerWin)
    if not par then return end
    finaleRoot = par

    local edge = utils.createControl(state.rectPrefabId, 0, 0, total + 30, total + 30,
        utils.hexToColor(pal.panelEdge or "1E2A47"), par)
    local paperC = utils.createControl(state.rectPrefabId, 0, 0, total + 22, total + 22,
        utils.hexToColor(pal.paper or "F7F8FA"), par)

    -- ---- 四块：各自一个容器 + 8×8 线稿 ----
    --   sx/sy = 目标槽位；fx0/fy0 = 屏外起点偏移；rot0 = 飞入时的初始角度
    local quads = {
        { ox = 0, oy = 0, sx = -off, sy =  off, fx0 =    0, fy0 =  780, rot0 =  -7 },  -- 左上 ← 上
        { ox = 8, oy = 0, sx =  off, sy =  off, fx0 =  980, fy0 =    0, rot0 =   9 },  -- 右上 ← 右
        { ox = 0, oy = 8, sx = -off, sy = -off, fx0 =    0, fy0 = -780, rot0 =   6 },  -- 左下 ← 下
        { ox = 8, oy = 8, sx =  off, sy = -off, fx0 = -980, fy0 =    0, rot0 =  -9 },  -- 右下 ← 左
    }

    for qi = 1, 4 do
        local q = quads[qi]
        local holder = utils.createContainer(par)
        q.ctrl = holder
        if holder then
            utils.setPos(holder, q.sx + q.fx0, q.sy + q.fy0)
            utils.setScaleXY(holder, 0.88, 0.88)
            utils.setRotationZ(holder, q.rot0)
            for y = 1, 8 do
                for x = 1, 8 do
                    local px = -Q / 2 + cell / 2 + (x - 1) * (cell + gap)
                    local py = Q / 2 - cell / 2 - (y - 1) * (cell + gap)
                    local v = art.at(state.pic, q.ox + x, q.oy + y)
                    utils.createControl(state.rectPrefabId, px, py, cell - gap, cell - gap,
                        utils.hexToColor(v == 1 and (pal.ink or "111318") or (pal.paper or "F7F8FA")), holder)
                end
            end
        end
    end

    -- 白闪：四块落齐时"咔嚓"一下
    local flash = utils.createControl(state.rectPrefabId, 0, 0, total + 22, total + 22,
        utils.hexToColorA("FFFFFF", 0), par)

    -- ---- 64×64 彩图：同色矩形合并后逐块建控件（初始 alpha 0）----
    local colorLayer = utils.createContainer(par)
    local colorRects = {}
    local rects, S = art.artRects(ch.key)
    S = S or 64
    local P = total / S                   -- 一个"像素"在屏幕上的边长
    if colorLayer and rects then
        for i = 1, #rects do
            local r = rects[i]
            -- ★ 宽高各 +1：相邻矩形互相压 1px，栅格化时接缝不会透出底色（这就是"中间不留缝"）
            local px = -half + (r.x + r.w / 2) * P
            local py = half - (r.y + r.h / 2) * P
            local c = utils.createControl(state.rectPrefabId, px, py,
                r.w * P + 1.0, r.h * P + 1.0, utils.hexToColorA(r.hex, 0), colorLayer)
            if c then
                colorRects[#colorRects + 1] = {
                    ctrl = c, hex = r.hex,
                    d = (r.x + r.y) / (2.0 * S),   -- 对角线归一化，用来做错峰
                }
            end
        end
    end

    -- ---- 上色 ----
    local function colorize()
        anim.tween(0.10, function(p)
            utils.setColor(flash, "FFFFFF", math.floor(160 * p))
        end, { ease = "outQuad", tag = TAG_FIN, onDone = function()
            anim.tween(0.32, function(p)
                utils.setColor(flash, "FFFFFF", math.floor(160 * (1 - p)))
            end, { ease = "inQuad", tag = TAG_FIN })
        end })

        for i = 1, #colorRects do
            local rc = colorRects[i]
            anim.delay(0.08 + rc.d * 0.34, function()
                anim.tween(0.30, function(p)
                    utils.setColor(rc.ctrl, rc.hex, math.floor(255 * p))
                end, { ease = "outQuad", tag = TAG_FIN })
            end, TAG_FIN)
        end

        -- 彩图盖满后把线稿收起来（否则两层轮廓会叠）
        anim.delay(0.52, function()
            for qi = 1, 4 do
                if quads[qi].ctrl then utils.setVisible(quads[qi].ctrl, false) end
            end
        end, TAG_FIN)

        for i = 1, 7 do
            anim.delay(0.24 + i * 0.07, function() audio.playStar() end, TAG_FIN)
        end

        anim.delay(0.62, function()
            fx.confetti()
            audio.playWin()
            hud.setVisible(true)
            hud.refresh()
            state.phase = "finish"
        end, TAG_FIN)
    end

    -- ---- 飞入 ----
    local FLY, STAG, BASE = 0.46, 0.17, 0.14
    local landed = 0

    local function impact(q)
        landed = landed + 1
        utils.setPos(q.ctrl, q.sx, q.sy)
        utils.setRotationZ(q.ctrl, 0)
        -- 压扁 → 欠阻尼回弹（振幅指数衰减 + 余弦振荡）
        anim.tween(0.62, function(p)
            local damp = (1 - p) * (1 - p)
            local a = 0.22 * damp * math.cos(p * math.pi * 6.5)
            utils.setScaleXY(q.ctrl, 1 + a, 1 - a)
        end, { ease = "linear", tag = TAG_FIN, onDone = function()
            utils.setScaleXY(q.ctrl, 1, 1)
        end })
        fx.ring(q.sx, q.sy, Q * 0.9, accent)
        fx.shake()
        audio.playStar()
        if landed >= 4 then
            anim.delay(0.28, colorize, TAG_FIN)
        end
    end

    for qi = 1, 4 do
        local q = quads[qi]
        if q.ctrl then
            anim.delay(BASE + (qi - 1) * STAG, function()
                audio.playFlip()
                anim.tween(FLY, function(p)
                    utils.setPos(q.ctrl, q.sx + q.fx0 * (1 - p), q.sy + q.fy0 * (1 - p))
                    local s = 0.88 + 0.12 * p
                    utils.setScaleXY(q.ctrl, s, s)
                    utils.setRotationZ(q.ctrl, q.rot0 * (1 - p))
                end, { ease = "outBack", tag = TAG_FIN, onDone = function() impact(q) end })
            end, TAG_FIN)
        end
    end

    -- ---- 一次性排全层：描边 → 白纸 → 四块 → 彩图 → 白闪 → 文字 ----
    local order = { edge, paperC }
    for qi = 1, 4 do
        if quads[qi].ctrl then order[#order + 1] = quads[qi].ctrl end
    end
    order[#order + 1] = colorLayer
    order[#order + 1] = flash

    local t = utils.createText(0, -half - 44, 560, 44, "「" .. (ch.name or "") .. "」完成",
        utils.hexToColor(pal.text or "E9F0FF"), 26, par)
    order[#order + 1] = t
    utils.applyLayerOrder(order)
