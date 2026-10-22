-- ================================================================
-- 瓦雷莎的果园救急 · 工具模块
--   控件创建（纯色矩形 / 容器 / 文本 / 命中区）、配色解析、显隐与呼吸、
--   拖拽绑定、小工具函数。本模块不持有游戏状态。
-- ================================================================

---@diagnostic disable: undefined-global

local M = {}
local state = require("default_import_file/state")
local config = require("default_import_file/config")

-- ================================================================
-- ★ 配色
-- ================================================================
function M.hexToColor(hex)
    local s = tostring(hex or ""):gsub("#", "")
    if #s ~= 6 then return Color.FromRGB(255, 255, 255) end
    local r = tonumber(s:sub(1, 2), 16)
    local g = tonumber(s:sub(3, 4), 16)
    local b = tonumber(s:sub(5, 6), 16)
    if not r or not g or not b then return Color.FromRGB(255, 255, 255) end
    return Color.FromRGB(r, g, b)
end

function M.hexToColorA(hex, alpha)
    local s = tostring(hex or ""):gsub("#", "")
    if #s ~= 6 then return Color.FromRGBA(255, 255, 255, alpha or 255) end
    local r = tonumber(s:sub(1, 2), 16) or 255
    local g = tonumber(s:sub(3, 4), 16) or 255
    local b = tonumber(s:sub(5, 6), 16) or 255
    return Color.FromRGBA(r, g, b, math.floor(alpha or 255))
end

-- 两色插值（"RRGGBB" → "RRGGBB"），用于「未通关/已通关」之间的过渡
function M.mixHex(a, b, t)
    local function c(h, i) return tonumber(tostring(h):sub(i, i + 1), 16) or 0 end
    local r = c(a, 1) + (c(b, 1) - c(a, 1)) * t
    local g = c(a, 3) + (c(b, 3) - c(a, 3)) * t
    local bl = c(a, 5) + (c(b, 5) - c(a, 5)) * t
    return string.format("%02X%02X%02X",
        math.floor(r + 0.5), math.floor(g + 0.5), math.floor(bl + 0.5))
end

-- 合并配色：关卡 palette 覆盖 DEFAULT_PALETTE（配色真源只有 config 一处）
function M.resolvePalette(data)
    local out = {}
    for k, v in pairs(config.DEFAULT_PALETTE or {}) do out[k] = v end
    if type(data) == "table" and type(data.palette) == "table" then
        for k, v in pairs(data.palette) do out[k] = v end
    end
    return out
end

-- 取当前配色
function M.palette()
    return M.resolvePalette(state.currentLevelConfig)
end

-- ================================================================
-- ★ 纯色矩形（图片控件）
-- ================================================================
function M.createControl(prefabId, x, y, w, h, color, parent)
    if not prefabId or prefabId <= 0 then return nil end
    local ok, ctrl = pcall(game.InstantiateClientUIControl, prefabId, parent or state.parent)
    if not ok or not ctrl then return nil end
    pcall(function() ctrl:SetAnchorMin(0.5, 0.5) end)
    pcall(function() ctrl:SetAnchorMax(0.5, 0.5) end)
    pcall(function() ctrl:SetPivot(0.5, 0.5) end)
    pcall(function() ctrl:SetSizeDelta(w, h) end)
    if color then pcall(function() ctrl.imageColor = color end) end
    pcall(function() ctrl:SetAnchoredPosition(x, y) end)
    pcall(function() ctrl:SetActive(true) end)
    -- ★★ 建完就 raise 到同级末位：真机「后建在上」，模拟器「先建在上」，
    --    只有按「从下到上」的创建顺序连续 raise() 才能两边都对齐。
    --    这是本工程唯一可靠的叠放手段（漏掉的表现：整屏只剩最先建的那块）。
    M.raise(ctrl)
    return ctrl
end

-- ================================================================
-- ★ 圆形 / 椭圆
--   用「圆形模板」+ 非正方形宽高就是椭圆（宽高各自拉伸）。
--   没配 circlePrefabId 时退化成矩形：形状变方，但画面照常跑。
-- ================================================================
function M.circle(x, y, w, h, color, parent)
    local pid = (state.circlePrefabId or 0) > 0 and state.circlePrefabId or state.rectPrefabId
    return M.createControl(pid, x, y, w, h, color, parent)
end

-- ★ 圆环模板（100006）：光晕 / 光环。没配就退回圆形，再退回矩形。
function M.ringShape(x, y, w, h, color, parent)
    local pid = state.ringPrefabId or 0
    if pid <= 0 then pid = state.circlePrefabId or 0 end
    if pid <= 0 then pid = state.rectPrefabId or 0 end
    return M.createControl(pid, x, y, w, h, color, parent)
end

-- 走配色键或色值
function M.circleC(x, y, w, h, keyOrHex, alpha, parent)
    local pal = M.palette()
    local hex = pal[keyOrHex] or keyOrHex
    return M.circle(x, y, w, h, M.hexToColorA(hex, alpha or 255), parent)
end

-- ★ 三角形（100003）：风车叶片 / 草叶 / 山尖。没配就退回圆形，再退回矩形。
function M.triangle(x, y, w, h, color, parent)
    local pid = state.trianglePrefabId or 0
    if pid <= 0 then pid = state.circlePrefabId or 0 end
    if pid <= 0 then pid = state.rectPrefabId or 0 end
    return M.createControl(pid, x, y, w, h, color, parent)
end

function M.triangleC(x, y, w, h, keyOrHex, alpha, parent)
    local pal = M.palette()
    local hex = pal[keyOrHex] or keyOrHex
    return M.triangle(x, y, w, h, M.hexToColorA(hex, alpha or 255), parent)
end

-- ================================================================
-- ★ 圆角矩形（9 宫格拼法：一横一竖两条矩形 + 四角圆）
--   只用「矩形 + 圆形」两种基础模板就能拼出任意圆角，任何端都成立。
--   ★ alpha 必须 255：半透明的几块叠在一起，拼接处会露出接缝。
--   返回一个透明容器（可直接 setPos / setScale 做动效）。
-- ================================================================
function M.roundRect(x, y, w, h, r, keyOrHex, parent)
    if not w or not h or w <= 0 or h <= 0 then return nil end
    r = math.max(0, math.min(r or 0, w / 2, h / 2))
    local pal = M.palette()
    local hex = pal[keyOrHex] or keyOrHex
    local col = M.hexToColorA(hex, 255)
    local holder = M.createContainer(parent, w, h)
    if not holder then return nil end
    M.setPos(holder, x, y)
    if r <= 0.6 then
        M.createControl(state.rectPrefabId, 0, 0, w, h, col, holder)
        return holder
    end
    -- 十字主体
    M.createControl(state.rectPrefabId, 0, 0, w, h - r * 2, col, holder)
    M.createControl(state.rectPrefabId, 0, 0, w - r * 2, h, col, holder)
    -- 四角
    local d = r * 2
    local cx, cy = (w - d) / 2, (h - d) / 2
    local pid = (state.circlePrefabId or 0) > 0 and state.circlePrefabId or state.rectPrefabId
    M.createControl(pid, -cx, cy, d, d, col, holder)
    M.createControl(pid, cx, cy, d, d, col, holder)
    M.createControl(pid, -cx, -cy, d, d, col, holder)
    M.createControl(pid, cx, -cy, d, d, col, holder)
    return holder
end

-- ================================================================
-- ★ 圆角矩形（可改色 / 可改尺寸版）
--   同样是 9 宫格拼法，但把 6 块记下来，之后可以整体改色 / 改尺寸：
--     · 面板入场要缩放（setBoxSize）
--     · 按钮要在几套配色之间切换（setBoxColor）
--   返回 { root = 容器, parts = {…}, w, h, r }。
--   ★★ alpha 别用低于 255 的值：拼接处被盖了两次会更实，露出「十字接缝」。
--     面板淡入请走「遮罩淡入 + 面板缩放」，不要改面板本身的透明度。
-- ================================================================
function M.roundBox(x, y, w, h, r, keyOrHex, parent)
    if not w or not h or w <= 0 or h <= 0 then return nil end
    r = math.max(0, math.min(r or 0, w / 2, h / 2))
    local box = { w = w, h = h, r = r, parts = {} }
    box.root = M.createContainer(parent, w, h)
    if not box.root then return nil end
    M.setPos(box.root, x, y)
    if r <= 0.6 then
        box.parts[1] = M.createControl(state.rectPrefabId, 0, 0, w, h, nil, box.root)
    else
        -- 横条 + 竖条 + 四角圆（顺序无所谓，同色同 alpha 看不出拼缝）
        box.parts[1] = M.createControl(state.rectPrefabId, 0, 0, w, h - r * 2, nil, box.root)
        box.parts[2] = M.createControl(state.rectPrefabId, 0, 0, w - r * 2, h, nil, box.root)
        local pid = (state.circlePrefabId or 0) > 0 and state.circlePrefabId or state.rectPrefabId
        local d = r * 2
        box.parts[3] = M.createControl(pid, 0, 0, d, d, nil, box.root)
        box.parts[4] = M.createControl(pid, 0, 0, d, d, nil, box.root)
        box.parts[5] = M.createControl(pid, 0, 0, d, d, nil, box.root)
        box.parts[6] = M.createControl(pid, 0, 0, d, d, nil, box.root)
    end
    M.setBoxSize(box, w, h)
    M.setBoxColor(box, keyOrHex, 255)
    return box
end

-- 改尺寸：把 6 块按新宽高重排（面板入场缩放用）
function M.setBoxSize(box, w, h)
    if not box or not box.parts then return end
    if not w or not h or w <= 0 or h <= 0 then return end
    box.w, box.h = w, h
    M.setSize(box.root, w, h)
    if #box.parts < 6 then
        M.setSize(box.parts[1], w, h)
        return
    end
    local r = math.max(0, math.min(box.r or 0, w / 2, h / 2))
    M.setSize(box.parts[1], w, h - r * 2)
    M.setPos(box.parts[1], 0, 0)
    M.setSize(box.parts[2], w - r * 2, h)
    M.setPos(box.parts[2], 0, 0)
    local d = r * 2
    local cx, cy = (w - d) / 2, (h - d) / 2
    M.setSize(box.parts[3], d, d) M.setPos(box.parts[3], -cx, cy)
    M.setSize(box.parts[4], d, d) M.setPos(box.parts[4], cx, cy)
    M.setSize(box.parts[5], d, d) M.setPos(box.parts[5], -cx, -cy)
    M.setSize(box.parts[6], d, d) M.setPos(box.parts[6], cx, -cy)
end

-- 改色：6 块一起写（配色键或色值）
function M.setBoxColor(box, keyOrHex, alpha)
    if not box or not box.parts then return end
    local pal = M.palette()
    local hex = pal[keyOrHex] or keyOrHex
    local col = M.hexToColorA(hex, alpha or 255)
    for i = 1, #box.parts do
        local p = box.parts[i]
        if p then pcall(function() p.imageColor = col end) end
    end
end

-- 星形（100004 四角星 / 100005 五角星）：装饰闪光。没配就退回圆形，再退回矩形。
function M.star4(x, y, w, h, color, parent)
    local pid = state.star4PrefabId or 0
    if pid <= 0 then pid = state.circlePrefabId or 0 end
    if pid <= 0 then pid = state.rectPrefabId or 0 end
    return M.createControl(pid, x, y, w, h, color, parent)
end

function M.star5(x, y, w, h, color, parent)
    local pid = state.star5PrefabId or 0
    if pid <= 0 then pid = state.circlePrefabId or 0 end
    if pid <= 0 then pid = state.rectPrefabId or 0 end
    return M.createControl(pid, x, y, w, h, color, parent)
end

function M.starC(x, y, w, h, keyOrHex, alpha, parent, five)
    local pal = M.palette()
    local hex = pal[keyOrHex] or keyOrHex
    local col = M.hexToColorA(hex, alpha or 255)
    if five then return M.star5(x, y, w, h, col, parent) end
    return M.star4(x, y, w, h, col, parent)
end

-- ================================================================
-- ★ 透明容器
--   ★★ 尺寸必须是「整块画布」（或世界尺寸），不能是 1×1：
--      模拟器的命中测试按「锚点 + 尺寸」逐层算矩形，1×1 的父容器会把
--      所有子控件的命中矩形缩到原点附近 → 点哪都对不上（2D 版踩过）。
--   ★ 优先用真容器模板 containerPrefabId（模拟器只下钻真容器）。
-- ================================================================
function M.createContainer(parent, w, h)
    local pid = state.containerPrefabId or 0
    if pid <= 0 then pid = state.rectPrefabId or 0 end
    if pid <= 0 then return nil end
    local ok, c = pcall(game.InstantiateClientUIControl, pid, parent or state.parent)
    if not ok or not c then return nil end
    pcall(function()
        c:SetAnchorMin(0.5, 0.5)
        c:SetAnchorMax(0.5, 0.5)
        c:SetPivot(0.5, 0.5)
        c:SetAnchoredPosition(0, 0)
        c:SetSizeDelta(w or state.canvasW or 1280, h or state.canvasH or 720)
        c.imageColor = Color.FromRGBA(255, 255, 255, 0)
        c.enableMask = false          -- ★ 绝不裁剪子控件
        c.raycastTarget = false       -- ★ 容器本身不吃光标
    end)
    pcall(function() c:SetActive(true) end)
    M.raise(c)
    return c
end

-- ================================================================
-- ★ 命中区（光标检测区域元件）
--   千星里只有「预设按钮 / 光标检测区域」带 AddCursorEventListener；
--   图片控件没有 → 绑在底图上会被 pcall 静默吞掉（按钮看得见、点不动）。
-- ================================================================
local warnedHit = false
function M.createHit(x, y, w, h, parent, fallback)
    local pid = state.cursorPrefabId or 0
    local ctrl
    if pid > 0 then
        local ok, c = pcall(game.InstantiateClientUIControl, pid, parent or state.parent)
        if ok then ctrl = c end
    end
    if not ctrl then
        if not warnedHit then
            warnedHit = true
            printerr("警告：未配置 cursorPrefabId（光标检测区域）—— 鼠标点击与拖拽将不可用。")
        end
        return nil
    end
    pcall(function() ctrl.imageColor = Color.FromRGBA(255, 255, 255, 0) end)
    pcall(function() ctrl:SetAnchorMin(0.5, 0.5) end)
    pcall(function() ctrl:SetAnchorMax(0.5, 0.5) end)
    pcall(function() ctrl:SetPivot(0.5, 0.5) end)
    pcall(function() ctrl:SetSizeDelta(w, h) end)
    pcall(function() ctrl:SetAnchoredPosition(x, y) end)
    pcall(function() ctrl.raycastTarget = true end)
    pcall(function() ctrl.interactable = true end)
    pcall(function() ctrl:SetActive(true) end)
    M.raise(ctrl)
    return ctrl
end

-- ================================================================
-- ★ 悬停 / 移出（触屏设备不会触发，属正常）
-- ================================================================
function M.bindHover(hit, onEnter, onExit)
    if not hit then return end
    if onEnter then
        pcall(function()
            hit:AddCursorEventListener(Enum.CursorEventType.CursorEnter, function() onEnter() end)
        end)
    end
    if onExit then
        pcall(function()
            hit:AddCursorEventListener(Enum.CursorEventType.CursorExit, function() onExit() end)
        end)
    end
end

-- ================================================================
-- ★★ 统一的光标交互绑定：按下 / 拖拽 / 抬起 → 点击 or 拖拽
--   h = {
--     down = fun()             按下（可选）
--     drag = fun(dx, dy)       拖拽增量（可选）
--     drop = fun(vx, vy)       抬起（可选，带估算速度）
--     tap  = fun()             位移小于阈值时算点击（可选）
--     threshold = number       点击判定阈值（缺省 DEFAULT_MAP_DRAG_THRESHOLD）
--   }
--   ★ 回调收到的 CursorEventData 可能为 nil（不同引擎版本），一律 pcall 兜住；
--     位移优先用 GetUIPosDelta()，取不到时用 GetUIPos() 的差值兜底。
-- ================================================================
function M.bindPointer(hit, h)
    if not hit or type(h) ~= "table" then return end
    local threshold = h.threshold or (config.DEFAULT_MAP_DRAG_THRESHOLD or 10)
    local pressed, moved = false, 0
    local lastX, lastY = 0, 0
    local pressX, pressY = 0, 0
    local lastT = 0

    local function pos(data)
        local x, y
        pcall(function() x, y = data:GetUIPos() end)
        if type(x) ~= "number" or type(y) ~= "number" then
            pcall(function() x, y = game.GetCursorUIPos() end)
        end
        if type(x) ~= "number" then x = 0 end
        if type(y) ~= "number" then y = 0 end
        return x, y
    end

    local function delta(data)
        local dx, dy
        pcall(function() dx, dy = data:GetUIPosDelta() end)
        if type(dx) ~= "number" or type(dy) ~= "number" then dx, dy = 0, 0 end
        return dx, dy
    end

    local function listen(evt, fn)
        pcall(function()
            hit:AddCursorEventListener(evt, function(data) fn(data) end)
        end)
    end

    listen(Enum.CursorEventType.CursorDown, function(data)
        pressed, moved = true, 0
        lastX, lastY = pos(data)
        pressX, pressY = lastX, lastY
        lastT = state.fxTime or 0
        if h.down then pcall(h.down) end
    end)

    local function onMove(data)
        if not pressed then return end
        local dx, dy = delta(data)
        if dx == 0 and dy == 0 then
            local x, y = pos(data)
            dx, dy = x - lastX, y - lastY
            lastX, lastY = x, y
        end
        moved = moved + math.abs(dx) + math.abs(dy)
        if h.drag then pcall(h.drag, dx, dy) end
    end
    listen(Enum.CursorEventType.CursorDrag, onMove)

    local function finish()
        if not pressed then return end
        pressed = false
        if h.drop then pcall(h.drop) end
        if moved <= threshold and h.tap then pcall(h.tap, pressX, pressY) end
    end
    listen(Enum.CursorEventType.CursorEndDrag, finish)
    listen(Enum.CursorEventType.CursorUp, finish)
end

-- ================================================================
-- ★ 基础属性写手（每帧动效会调用很多次，统一 pcall）
-- ================================================================
function M.setPos(ctrl, x, y)
    if not ctrl then return end
    pcall(function() ctrl:SetAnchoredPosition(x, y) end)
end

function M.setSize(ctrl, w, h)
    if not ctrl then return end
    pcall(function() ctrl:SetSizeDelta(w, h) end)
end

function M.setScale(ctrl, s)
    if not ctrl then return end
    pcall(function() ctrl:SetLocalScale(s, s, 1) end)
end

function M.setScaleXY(ctrl, sx, sy)
    if not ctrl then return end
    pcall(function() ctrl:SetLocalScale(sx, sy, 1) end)
end

function M.setRotationZ(ctrl, deg)
    if not ctrl then return end
    pcall(function() ctrl:SetLocalRotation(0, 0, deg) end)
end

function M.setAlpha(ctrl, hex, alpha)
    if not ctrl then return end
    pcall(function() ctrl.imageColor = M.hexToColorA(hex, alpha) end)
end

-- 同 setAlpha，但接受配色键（"accent"）或色值（"E4572E"）
function M.setColor(ctrl, keyOrHex, alpha)
    if not ctrl then return end
    local pal = M.palette()
    local hex = pal[keyOrHex] or keyOrHex
    M.setAlpha(ctrl, hex, alpha)
end

function M.setVisible(ctrl, visible)
    if not ctrl then return end
    pcall(function() ctrl:SetActive(visible and true or false) end)
end

function M.setVisibleAll(list, visible)
    for _, c in ipairs(list or {}) do M.setVisible(c, visible) end
end

function M.destroy(ctrl)
    if not ctrl then return end
    pcall(function() game.DestroyClientUIControl(ctrl) end)
end

-- ★ 关掉控件的射线命中：纯装饰（土路石子 / 果树 / 节点底图…）不该吃点击，
--   否则它们会挡在命中区上面，把点击与拖拽一起吞掉。
function M.noRay(ctrl)
    if not ctrl then return end
    pcall(function() ctrl.raycastTarget = false end)
end

function M.raise(ctrl)
    if not ctrl then return end
    pcall(function() ctrl:SetAsLastSibling() end)
end

function M.sink(ctrl)
    if not ctrl then return end
    pcall(function() ctrl:SetAsFirstSibling() end)
end

-- ================================================================
-- ★ 文本：底色透明（真机不设就会被预制体底色盖住下方内容）
-- ================================================================
function M.setTextBgTransparent(ctrl)
    if not ctrl then return end
    pcall(function() ctrl.bgColor = Color.FromRGBA(0, 0, 0, 0) end)
end

-- 文本框的字色字段是 fontColor；imageColor 只属于图片控件
function M.setTextColor(ctrl, hex, alpha)
    if not ctrl then return end
    local pal = M.palette()
    local v = pal[hex] or hex
    local c = M.hexToColorA(v, alpha)
    pcall(function() ctrl.fontColor = c end)
    pcall(function() ctrl.imageColor = c end)
end

-- ★★ 真机文本框有最小高度：盒子太矮一个字都不画（实测 26/22px 全空）。
local MIN_TEXT_H = 36
M.MIN_TEXT_H = MIN_TEXT_H

-- align: "left" | "middle" | "right"（缺省居中）
function M.createText(x, y, w, h, text, color, fontSize, parent, align)
    local pid = state.textPrefabId or 0
    if pid <= 0 then return nil end
    local ok, ctrl = pcall(game.InstantiateClientUIControl, pid, parent or state.parent)
    if not ok or not ctrl then return nil end
    local boxH = tonumber(h) or 0
    if boxH < MIN_TEXT_H then boxH = MIN_TEXT_H end
    pcall(function() ctrl:SetAnchorMin(0.5, 0.5) end)
    pcall(function() ctrl:SetAnchorMax(0.5, 0.5) end)
    pcall(function() ctrl:SetPivot(0.5, 0.5) end)
    pcall(function() ctrl:SetSizeDelta(w, boxH) end)
    pcall(function() ctrl:SetAnchoredPosition(x, y) end)
    M.setTextBgTransparent(ctrl)
    pcall(function() ctrl.adaptiveFontSize = false end)
    local halign = Enum.TextHorizontalAlignment.Middle
    if align == "left" then halign = Enum.TextHorizontalAlignment.Left
    elseif align == "right" then halign = Enum.TextHorizontalAlignment.Right end
    pcall(function() ctrl.horizontalAlignment = halign end)
    pcall(function() ctrl.verticalAlignment = Enum.TextVerticalAlignment.Middle end)
    pcall(function() ctrl.raycastTarget = false end)
    pcall(function() if text ~= nil then ctrl.text = text end end)
    pcall(function() if fontSize and fontSize > 0 then ctrl.fontSize = fontSize end end)
    if color then
        pcall(function() ctrl.fontColor = color end)
        pcall(function() ctrl.imageColor = color end)
    end
    pcall(function() ctrl:SetActive(true) end)
    M.raise(ctrl)
    return ctrl
end

function M.setText(ctrl, text)
    if not ctrl then return end
    pcall(function() ctrl.text = text end)
end

function M.setFontSize(ctrl, size)
    if not ctrl or not size or size <= 0 then return end
    pcall(function() ctrl.fontSize = size end)
end

-- ================================================================
-- ★ 居中面板层的整体放大系数（game.lua 按画布写入 state.uiScale）
--   这两层里 fx.spawn 的坐标要乘它（粒子挂在未放大的 containerFx 上）。
-- ================================================================
function M.uiScale()
    local k = state.uiScale
    if type(k) ~= "number" or k <= 0 then return 1 end
    return k
end

-- ================================================================
-- ★ 数值小工具
-- ================================================================
function M.clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

function M.lerp(a, b, t)
    return a + (b - a) * t
end

return M
