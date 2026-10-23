-- ================================================================
-- 皮耶罗：赴死 · 结算演出（动态漫画）
-- ================================================================
-- 每次穿过门（= 一次轮回的结尾）播一段分镜：
--   ① 生死之间，门开着
--   ② 把生命按在愚人之眼上
--   ③ 愚人之眼，解放！
--   ④ 若娜瓦，收下这份献祭 —— 伤害数字 3,927,698 砸下来
--
-- ★ 第一阶段（原版复刻）用【图元剪影 + 文案】占位：
--   分镜数据全部在 config.COMIC.panels，换成原神参考图时只要把 actors 的
--   shape 换成图片 prefab（或直接给 image 字段），编排代码不用动。
-- ★ 全程可点跳过。
-- ================================================================

---@diagnostic disable: undefined-global

local M = {}
local state = require("default_import_file/state")
local config = require("default_import_file/config")
local utils = require("default_import_file/utils")
local audio = require("default_import_file/audio")
local fx = require("default_import_file/fx")

local root = nil
local bg = nil
local barTop = nil
local barBot = nil
local caption = nil
local bigNum = nil
local numLabel = nil
local skipHit = nil
local panelCtrls = {}

local phase = "idle"
local t = 0
local panelIdx = 0
local panels = {}
local holdT = 0.95
local fadeT = 0.14
local numT = 1.30
local bgAlpha = 0
local dmgShown = false
local onDoneCb = nil

M.active = false

-- ================================================================
-- 图元剪影：把一个 actor 规格画成若干控件
--   spec = { shape, x, y, w, h, hex, alpha }
--   x / y 是「相对画面中心」的设计坐标
-- ================================================================
local function add(ctrl)
    if ctrl then
        panelCtrls[#panelCtrls + 1] = ctrl
        utils.raise(ctrl)
    end
    return ctrl
end

local function box(x, y, w, h, hex, alpha, rot)
    local c = utils.createControl(state.rectPrefabId, x, y, w, h,
        utils.hexToColorA(hex, alpha or 255), root)
    if c and rot and rot ~= 0 then utils.setRot(c, rot) end
    return add(c)
end

local function spawnShape(sp)
    local shape = sp.shape or "glow"
    local hex = sp.hex or utils.pal("accent")
    local a = sp.alpha or 255
    local x = sp.x or 0
    local y = sp.y or 0

    if shape == "glow" then
        box(x, y, sp.w or 300, sp.h or 300, hex, math.floor(a * 0.5), 0)
        box(x, y, (sp.w or 300) * 0.66, (sp.w or 300) * 0.66, hex, a, 0)
    elseif shape == "burst" then
        box(x, y, sp.w or 400, (sp.h or 400) * 0.16, hex, a, 0)
        box(x, y, (sp.w or 400) * 0.16, sp.h or 400, hex, a, 0)
        box(x, y, sp.w or 400, (sp.h or 400) * 0.30, hex, math.floor(a * 0.5), 45)
    elseif shape == "door" then
        local w = sp.w or 120
        local h = sp.h or 210
        -- ★ UI 坐标 y 向上：门体在中心稍下，拱顶在上方
        box(x, y - 10, w, h - 20, hex, a, 0)                       -- 门体
        box(x, y + h / 2 - 16, w - 16, 14, hex, a, 0)              -- 拱顶
        box(x + w / 2 - 14, y - 14, 8, 8, utils.pal("bg"), a, 0)   -- 把手
    elseif shape == "harlequin" then
        local h = sp.h or 170
        local w = h * 0.42
        box(x, y, w, h, hex, a, 0)                                 -- 身体
        box(x, y + h * 0.30, w * 1.46, 8, hex, a, 0)               -- 肩
        box(x - w * 0.22, y + h * 0.36, 9, 11, "ECE8DF", a, 0)     -- 左眼
        box(x + w * 0.22, y + h * 0.36, 9, 11, "ECE8DF", a, 0)     -- 右眼
        box(x, y + h * 0.60, 13, h * 0.26, hex, a, 45)             -- 帽尖
        box(x, y - h * 0.46, w * 1.5, 6, hex, a, 0)                -- 披风下摆
    elseif shape == "eye" then
        local w = sp.w or 190
        local h = sp.h or 120
        box(x, y, w * 0.78, h * 0.78, hex, a, 45)                -- 菱形眼眶
        box(x, y, w * 0.42, h * 0.42, utils.pal("bg"), a, 45)    -- 瞳孔底
        box(x, y, w * 0.10, h * 0.34, hex, a, 0)                 -- 竖瞳
        box(x, y, w * 0.20, h * 0.20, hex, math.floor(a * 0.5), 0)
    elseif shape == "zonava" then
        local w = sp.w or 230
        local h = sp.h or 250
        box(x, y, w * 0.52, h, hex, a, 0)                        -- 身躯
        box(x, y + h * 0.34, w, h * 0.26, hex, a, 0)             -- 肩
        box(x, y + h * 0.26, 14, 18, "FF7A5C", a, 0)             -- 眼
        box(x, y - h * 0.34, w * 0.72, h * 0.30, hex, a, 45)     -- 下摆
    else
        box(x, y, sp.w or 120, sp.h or 120, hex, a, 0)
    end
end

-- ================================================================
-- 面板
-- ================================================================
local function clearPanel()
    for i = 1, #panelCtrls do utils.destroy(panelCtrls[i]) end
    panelCtrls = {}
end

-- ★ 面板内的图元是后建的，会盖住黑边与字幕 —— 每建完一格必须重新把覆盖件提回来
local function raiseOverlays()
    utils.raise(barTop)
    utils.raise(barBot)
    utils.raise(caption)
    utils.raise(bigNum)
    utils.raise(numLabel)
    utils.raise(skipHit)
end

local function buildPanel(idx)
    clearPanel()
    local p = panels[idx]
    if not p then return end
    if caption then
        utils.setText(caption, p.caption or "")
        utils.setVisible(caption, true)
    end
    -- 底色（每次换格重铺一层，做出「换镜」的观感）
    local bgc = p.bg or "080A12"
    box(0, 0, 2000, 1200, bgc, 255, 0)
    local actors = p.actors or {}
    for i = 1, #actors do
        spawnShape(actors[i])
    end
    raiseOverlays()
end

-- ================================================================
local function startPanel(idx)
    panelIdx = idx
    if idx > #panels then
        phase = "number"
        t = 0
        clearPanel()
        if caption then utils.setVisible(caption, false) end
        if bigNum then
            utils.setVisible(bigNum, true)
            utils.setText(bigNum, "0")
        end
        if numLabel then
            utils.setVisible(numLabel, true)
            utils.setPos(numLabel, 0, -74)
        end
        audio.playWin()
        return
    end
    buildPanel(idx)
    audio.playPop()
    phase = "panel"
    t = 0
end

-- ================================================================
-- 对外：开始演出
-- ================================================================
function M.play(onDone)
    if not state.rectPrefabId or state.rectPrefabId <= 0 then
        if onDone then onDone() end
        return false
    end
    M.stop()

    local top = state.containerTop or state.containerScene or state.parent
    if not top then
        if onDone then onDone() end
        return false
    end

    root = utils.createContainer(top)
    if not root then
        if onDone then onDone() end
        return false
    end
    utils.raise(root)

    panels = config.comicPanels()
    holdT = config.DEFAULT_COMIC_PANEL_HOLD or 0.95
    fadeT = config.DEFAULT_COMIC_FADE or 0.14
    numT = config.DEFAULT_COMIC_NUMBER_TIME or 1.30
    onDoneCb = onDone
    panelIdx = 0
    phase = "in"
    t = 0
    bgAlpha = 0
    dmgShown = false
    panelCtrls = {}
    M.active = true

    -- 全屏黑底（先 alpha 0，靠 update 拉起来）
    bg = utils.createControl(state.rectPrefabId, 0, 0, 2600, 1600,
        utils.hexToColorA("000000", 0), root)
    utils.raise(bg)

    local lb = config.DEFAULT_COMIC_LETTERBOX or 62
    barTop = utils.createControl(state.rectPrefabId, 0, 270 - lb / 2, 2600, lb,
        utils.hexToColorA("05060A", 255), root)
    barBot = utils.createControl(state.rectPrefabId, 0, -270 + lb / 2, 2600, lb,
        utils.hexToColorA("05060A", 255), root)
    utils.raise(barTop)
    utils.raise(barBot)

    caption = utils.createText(0, -270 + lb + 22, 820, 30, "",
        utils.hexToColor(utils.pal("text")), 17, root)
    if caption then utils.raise(caption) end

    bigNum = utils.createText(0, 30, 860, 96, "",
        utils.hexToColor(utils.pal("danger")), 62, root)
    numLabel = utils.createText(0, -74, 860, 30, "对 若 娜 瓦 造 成 伤 害",
        utils.hexToColor(utils.pal("textDim")), 15, root)
    if bigNum then utils.setVisible(bigNum, false); utils.raise(bigNum) end
    if numLabel then utils.setVisible(numLabel, false); utils.raise(numLabel) end

    -- 跳过区（覆盖全屏，最上层）
    skipHit = utils.createHit(0, 0, 2600, 1600, root, true)
    if skipHit then
        utils.raise(skipHit)
        utils.onCursor(skipHit, Enum.CursorEventType.CursorClick, function()
            M.finish()
        end)
    end

    return true
end

-- ================================================================
-- 每帧
-- ================================================================
function M.update(dt)
    if not M.active or not dt or dt <= 0 then return end
    t = t + dt

    if phase == "in" then
        bgAlpha = math.min(1, t / 0.20)
        utils.setColor(bg, "000000", math.floor(255 * bgAlpha))
        if t >= 0.20 then
            bgAlpha = 1
            startPanel(1)
        end
    elseif phase == "panel" then
        local total = fadeT + holdT + fadeT
        if t >= total then startPanel(panelIdx + 1) end
    elseif phase == "number" then
        local p = math.min(1, t / numT)
        local e = utils.easeOutQuad(p)
        local v = math.floor((config.COMIC_DAMAGE or 3927698) * e + 0.5)
        utils.setText(bigNum, utils.comma(v))
        if p >= 1 and not dmgShown then
            dmgShown = true
            fx.shake(14, 0.45)
            audio.playDeath()
            utils.setTextColor(bigNum, utils.pal("accent"), 255)
        end
        if t >= numT + 0.55 then
            phase = "out"
            t = 0
        end
    elseif phase == "out" then
        local a = 1 - math.min(1, t / 0.22)
        utils.setColor(bg, "000000", math.floor(255 * a))
        if caption then utils.setVisible(caption, false) end
        if bigNum then utils.setTextColor(bigNum, utils.pal("danger"), math.floor(255 * a)) end
        if numLabel then utils.setVisible(numLabel, false) end
        if t >= 0.22 then
            M.finish()
        end
    end
end

-- ================================================================
local function teardown()
    clearPanel()
    utils.destroy(bg)
    utils.destroy(barTop)
    utils.destroy(barBot)
    utils.destroy(caption)
    utils.destroy(bigNum)
    utils.destroy(numLabel)
    utils.destroy(skipHit)
    utils.destroy(root)
    bg = nil; barTop = nil; barBot = nil
    caption = nil; bigNum = nil; numLabel = nil
    skipHit = nil; root = nil
end

-- 正常结束
function M.finish()
    if not M.active then return end
    M.active = false
    phase = "idle"
    teardown()
    local cb = onDoneCb
    onDoneCb = nil
    if cb then pcall(cb) end
end

-- 强行中断（换关 / 回菜单）
function M.stop()
    if not M.active and not root then return end
    M.active = false
    phase = "idle"
    onDoneCb = nil
    teardown()
end

function M.isActive()
    return M.active
end

return M
