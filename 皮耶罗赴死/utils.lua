-- ================================================================
-- 皮耶罗：赴死 · 工具模块
--   控件创建（矩形 / 文本 / 命中区）、配色、世界坐标 → UI 坐标换算、
--   几何与数值工具、自绘按钮。
--   本模块不做玩法推进，只提供无副作用的构建与查询能力。
--
--   ★★ 三条真机踩过的坑（沿用 点灯迷题2D 的根治方案）：
--     ① 文本框不设 bgColor 会带出预制体底色 → 变成实心色块盖住下方内容
--        （模拟器忽略该字段）→ 统一走 setTextBgTransparent()。
--     ② 文本框有最小高度 + 「盒高 ≥ 字号 × 1.45」双门槛 → 不够高就一个字不画
--        → textBoxHeight() 双重兜高 + 显式 adaptiveFontSize = false。
--     ③ 图片控件没有 AddCursorEventListener → 可点区域一律用「光标检测区域」。
--   ★ 叠放顺序：模拟器与真机相反，必须显式 raise 定序，不能依赖创建顺序。
-- ================================================================

---@diagnostic disable: undefined-global

local M = {}
local state = require("default_import_file/state")
local config = require("default_import_file/config")

M.MIN_TEXT_H = 36            -- 文本框绝对最小高度（真机实测：26/22 完全空白）
M.TEXT_LINE_RATIO = 1.45     -- 盒高 / 字号 的最小比

-- ================================================================
-- 文本盒实际高度
-- ================================================================
function M.textBoxHeight(h, fontSize)
    local need = M.MIN_TEXT_H
    local fs = tonumber(fontSize)
    if fs and fs > 0 then
        local fit = math.ceil(fs * M.TEXT_LINE_RATIO)
        if fit > need then need = fit end
    end
    if (h or 0) < need then return need end
    return h
end

-- ================================================================
-- 配色
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
    local a = math.floor(alpha or 255)
    if a < 0 then a = 0 end
    if a > 255 then a = 255 end
    if #s ~= 6 then return Color.FromRGBA(255, 255, 255, a) end
    local r = tonumber(s:sub(1, 2), 16) or 255
    local g = tonumber(s:sub(3, 4), 16) or 255
    local b = tonumber(s:sub(5, 6), 16) or 255
    return Color.FromRGBA(r, g, b, a)
end

function M.hexToRGB(hex)
    local s = tostring(hex or ""):gsub("#", "")
    if #s ~= 6 then return 255, 255, 255 end
    return tonumber(s:sub(1, 2), 16) or 255,
           tonumber(s:sub(3, 4), 16) or 255,
           tonumber(s:sub(5, 6), 16) or 255
end

function M.pal(key, fallback)
    local p = config.DEFAULT_PALETTE or {}
    local v = p[key]
    if type(v) == "string" then return v end
    return fallback or "FFFFFF"
end

-- ================================================================
-- ★★ 世界坐标（960×540，y 向下）→ 场景设计坐标（原点在画布中心，y 向上）
--   关卡数据照抄原版，只在这里做一次翻转，其它模块不需要关心。
-- ================================================================
function M.toUIX(x)
    return (x or 0) - (config.DEFAULT_WORLD_W or 960) / 2
end

function M.toUIY(y)
    return (config.DEFAULT_WORLD_H or 540) / 2 - (y or 0)
end

-- 世界矩形（左上角 + 宽高）→ UI 中心点坐标
function M.rectCenter(x, y, w, h)
    return M.toUIX(x + w / 2), M.toUIY(y + h / 2)
end

-- ================================================================
-- 布局：整层缩放 k（scene 容器承载 SetLocalScale(k)）
-- ================================================================
function M.computeLayout()
    local cw = state.canvasW or 960
    local ch = state.canvasH or 540
    local dw = config.DEFAULT_DESIGN_W or 960
    local dh = config.DEFAULT_DESIGN_H or 540
    local k = math.min(cw / dw, ch / dh)
    if not k or k <= 0 then k = 1 end
    local minK = config.DEFAULT_MIN_SCALE or 0.5
    if k < minK then k = minK end
    state.k = k
    state.LEFT = -cw / 2
    state.RIGHT = cw / 2
    state.BOTTOM = -ch / 2
    state.TOP = ch / 2
    return k
end

-- ================================================================
-- 控件创建
-- ================================================================
local function applyTransform(ctrl, x, y, w, h)
    ctrl:SetAnchorMin(0.5, 0.5)
    ctrl:SetAnchorMax(0.5, 0.5)
    ctrl:SetPivot(0.5, 0.5)
    ctrl:SetSizeDelta(w, h)
    ctrl:SetAnchoredPosition(x, y)
end

-- ★ 透明容器父节点：只分组，不裁剪（显式关掉遮罩，否则子控件会被整片裁掉）
function M.createContainer(parent)
    local pid = state.containerPrefabId or 0
    if pid <= 0 then pid = state.rectPrefabId or 0 end
    if pid <= 0 then return nil end
    local ok, c = pcall(game.InstantiateClientUIControl, pid, parent or state.parent)
    if not ok or not c then return nil end
    -- ★ 容器尺寸必须足够大：模拟器的命中测试是逐层「点在不在矩形内」，
    --   1×1 的父容器会让子控件整片不可达。
    local w = (state.canvasW or 960) / (state.k or 1) + 240
    local h = (state.canvasH or 540) / (state.k or 1) + 240
    pcall(function()
        c:SetAnchorMin(0.5, 0.5)
        c:SetAnchorMax(0.5, 0.5)
        c:SetPivot(0.5, 0.5)
        c:SetAnchoredPosition(0, 0)
        c:SetSizeDelta(w, h)
        c.imageColor = Color.FromRGBA(255, 255, 255, 0)
        c.enableMask = false
        c.raycastTarget = false
    end)
    c:SetActive(true)
    return c
end

-- ★ 把控件提到同级最上层（真机与模拟器效果一致，是唯一可靠的提层手段）
function M.raise(ctrl)
    if not ctrl then return end
    pcall(function() ctrl:SetAsLastSibling() end)
end

function M.sink(ctrl)
    if not ctrl then return end
    pcall(function() ctrl:SetAsFirstSibling() end)
end

-- ★ 按给定顺序重排同层控件（list 从「最下层」到「最上层」）
function M.applyLayerOrder(list)
    if type(list) ~= "table" then return end
    for i = 1, #list do
        local c = list[i]
        if c then
            if i == 1 then
                pcall(function() c:SetAsFirstSibling() end)
            else
                pcall(function() c:SetAsLastSibling() end)
            end
        end
    end
end

-- ★ 纯色矩形（图片控件）
function M.createControl(prefabId, x, y, w, h, color, parent)
    if not prefabId or prefabId <= 0 then return nil end
    local ok, ctrl = pcall(game.InstantiateClientUIControl, prefabId, parent or state.parent)
    if not ok or not ctrl then return nil end
    local okSet = pcall(function()
        applyTransform(ctrl, x, y, w, h)
        ctrl.enableMask = false
        pcall(function() ctrl.raycastTarget = false end)
        if color then ctrl.imageColor = color end
    end)
    if not okSet then return nil end
    ctrl:SetActive(true)
    return ctrl
end

-- ★★ 世界矩形 → 矩形控件（陷阱 / 平台 / 玩家全用它，省掉到处换算）
function M.createRectWorld(x, y, w, h, hex, alpha, parent)
    local cx, cy = M.rectCenter(x, y, w, h)
    return M.createControl(state.rectPrefabId, cx, cy, w, h,
        M.hexToColorA(hex, alpha or 255), parent)
end

-- 世界坐标点 → 建一个 w×h 的矩形（中心落在该点）
function M.createRectAtWorld(wx, wy, w, h, hex, alpha, parent)
    return M.createControl(state.rectPrefabId, M.toUIX(wx), M.toUIY(wy), w, h,
        M.hexToColorA(hex, alpha or 255), parent)
end

-- ================================================================
-- 文本
-- ================================================================
function M.setTextBgTransparent(ctrl)
    if not ctrl then return end
    pcall(function() ctrl.bgColor = Color.FromRGBA(0, 0, 0, 0) end)
end

function M.setTextColor(ctrl, hex, alpha)
    if not ctrl then return end
    pcall(function() ctrl.fontColor = M.hexToColorA(hex, alpha or 255) end)
end

function M.createText(x, y, w, h, text, color, fontSize, parent, align)
    local pid = state.textPrefabId or 0
    if pid <= 0 then return nil end
    local hh = M.textBoxHeight(h, fontSize)
    local ok, ctrl = pcall(game.InstantiateClientUIControl, pid, parent or state.parent)
    if not ok or not ctrl then return nil end
    local halign = Enum.TextHorizontalAlignment.Middle
    if align == "left" then
        halign = Enum.TextHorizontalAlignment.Left
    elseif align == "right" then
        halign = Enum.TextHorizontalAlignment.Right
    end
    pcall(function()
        applyTransform(ctrl, x, y, w, hh)
        M.setTextBgTransparent(ctrl)
        ctrl.adaptiveFontSize = false
        pcall(function() ctrl.minimumFontSize = 8 end)
        pcall(function() ctrl.horizontalAlignment = halign end)
        pcall(function() ctrl.verticalAlignment = Enum.TextVerticalAlignment.Middle end)
        pcall(function() ctrl.raycastTarget = false end)
        if text ~= nil then ctrl.text = text end
        if fontSize and fontSize > 0 then ctrl.fontSize = math.floor(fontSize) end
        if color then ctrl.fontColor = color end
    end)
    ctrl:SetActive(true)
    return ctrl
end

-- 世界坐标处的文本
function M.createTextWorld(wx, wy, w, h, text, hex, fontSize, parent, align)
    return M.createText(M.toUIX(wx), M.toUIY(wy), w, h, text,
        M.hexToColor(hex), fontSize, parent, align)
end

function M.setText(ctrl, text)
    if not ctrl then return end
    pcall(function() ctrl.text = text end)
end

function M.setFontSize(ctrl, size)
    if not ctrl then return end
    pcall(function()
        if size and size > 0 then ctrl.fontSize = math.floor(size) end
    end)
end

-- ================================================================
-- 通用属性
-- ================================================================
function M.setColor(ctrl, hex, alpha)
    if not ctrl then return end
    pcall(function() ctrl.imageColor = M.hexToColorA(hex, alpha or 255) end)
end

function M.setVisible(ctrl, visible)
    if type(ctrl) == "table" and ctrl.__group then
        M.setVisible(ctrl.base, visible)
        M.setVisible(ctrl.label, visible)
        M.setVisible(ctrl.hit, visible)
        return
    end
    if not ctrl then return end
    pcall(function() ctrl:SetActive(visible and true or false) end)
end

function M.setScale(ctrl, s)
    if type(ctrl) == "table" and ctrl.__group then
        M.setScale(ctrl.base, s); M.setScale(ctrl.label, s); M.setScale(ctrl.hit, s)
        return
    end
    if not ctrl then return end
    pcall(function() ctrl:SetLocalScale(s, s, 1) end)
end

function M.setScaleXY(ctrl, sx, sy)
    if not ctrl then return end
    pcall(function() ctrl:SetLocalScale(sx, sy, 1) end)
end

function M.setPos(ctrl, x, y)
    if not ctrl then return end
    pcall(function() ctrl:SetAnchoredPosition(x, y) end)
end

function M.setSize(ctrl, w, h)
    if not ctrl then return end
    pcall(function() ctrl:SetSizeDelta(w, h) end)
end

function M.setRot(ctrl, deg)
    if not ctrl then return end
    pcall(function() ctrl:SetLocalRotation(0, 0, deg) end)
end

function M.destroy(ctrl)
    if type(ctrl) == "table" and ctrl.__group then
        M.destroy(ctrl.base); M.destroy(ctrl.label); M.destroy(ctrl.hit)
        return
    end
    if not ctrl then return end
    pcall(function() game.DestroyClientUIControl(ctrl) end)
end

-- ================================================================
-- 命中区（可点）
--   ★ 真机铁律：AddCursorEventListener 只对「预设按钮」与「光标检测区域」有效。
-- ================================================================
function M.createHit(x, y, w, h, parent, preferCursor)
    local cands
    if preferCursor then
        cands = { state.cursorPrefabId, state.buttonPrefabId }
    else
        cands = { state.buttonPrefabId, state.cursorPrefabId }
    end
    local ctrl = nil
    for i = 1, 2 do
        local pid = cands[i]
        if not ctrl and pid and pid > 0 then
            local ok, c = pcall(game.InstantiateClientUIControl, pid, parent or state.parent)
            if ok and c then ctrl = c end
        end
    end
    if not ctrl then
        ctrl = M.createControl(state.rectPrefabId, x, y, w, h, M.hexToColorA("FFFFFF", 0), parent)
    end
    if not ctrl then return nil end
    pcall(function()
        applyTransform(ctrl, x, y, w, h)
        pcall(function() ctrl.raycastTarget = true end)
        pcall(function() ctrl.enableMask = false end)
        pcall(function() ctrl.imageColor = Color.FromRGBA(255, 255, 255, 0) end)
        pcall(function() ctrl:SetActive(true) end)
    end)
    return ctrl
end

function M.onCursor(ctrl, eventType, fn)
    if not ctrl or not fn then return false end
    local ok = pcall(function() ctrl:AddCursorEventListener(eventType, fn) end)
    return ok == true
end

-- ================================================================
-- ★ 自绘按钮 = 图片底 + 文本 + 命中区
--   opts = { text, fontSize, textColor, bg, bgDown, alpha, onClick }
-- ================================================================
function M.createButton(x, y, w, h, parent, opts)
    opts = opts or {}
    local par = parent or state.parent
    if not par then return nil end
    if not state.rectPrefabId or state.rectPrefabId <= 0 then return nil end

    local bgHex = opts.bg or M.pal("btn", "232733")
    local downHex = opts.bgDown or M.pal("btnDown", "2E3342")
    local fgHex = opts.textColor or M.pal("btnText", "ECE8DF")
    local size = opts.fontSize or config.DEFAULT_BTN_SIZE or 18
    local alpha = opts.alpha or 255
    local press = config.DEFAULT_BTN_PRESS or 0.96

    local base = M.createControl(state.rectPrefabId, x, y, w, h,
        M.hexToColorA(bgHex, alpha), par)
    if not base then return nil end
    M.raise(base)

    local label = M.createText(x, y, w, h, opts.text or "",
        M.hexToColorA(fgHex, 255), size, par)
    M.raise(label)

    local hit = M.createHit(x, y, w, h, par, true)
    M.raise(hit)

    local btn = {
        __group = true,
        base = base, label = label, hit = hit,
        bg = bgHex, fg = fgHex, alpha = alpha,
        x = x, y = y, w = w, h = h,
        enabled = true,
    }

    if hit then
        local function restore()
            M.setColor(base, bgHex, alpha)
            M.setScale(base, 1)
            M.setScale(label, 1)
        end
        M.onCursor(hit, Enum.CursorEventType.CursorDown, function()
            if not btn.enabled then return end
            M.setColor(base, downHex, alpha)
            M.setScale(base, press)
            M.setScale(label, press)
        end)
        M.onCursor(hit, Enum.CursorEventType.CursorUp, function()
            if not btn.enabled then return end
            restore()
        end)
        M.onCursor(hit, Enum.CursorEventType.CursorClick, function()
            restore()
        end)
        if opts.onClick then M.onClick(btn, opts.onClick) end
    end

    return btn
end

function M.setButtonEnabled(btn, enabled)
    if type(btn) ~= "table" or not btn.__group then return end
    btn.enabled = enabled and true or false
    local a = btn.enabled and (btn.alpha or 255)
                         or (config.DEFAULT_BTN_DISABLED_ALPHA or 70)
    M.setColor(btn.base, btn.bg, a)
    M.setTextColor(btn.label, btn.fg or "ECE8DF", a)
    if btn.hit then pcall(function() btn.hit.raycastTarget = btn.enabled end) end
    return btn.enabled
end

function M.onClick(btn, fn)
    local target = (type(btn) == "table" and btn.__group) and btn.hit or btn
    if not target or not fn then return false end
    local ok = pcall(function()
        target:AddCursorEventListener(Enum.CursorEventType.CursorClick, function()
            if type(btn) == "table" and btn.enabled == false then return end
            fn()
        end)
    end)
    return ok == true
end

-- ================================================================
-- 数值 / 几何
-- ================================================================
function M.clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

function M.lerp(a, b, t) return a + (b - a) * t end

-- 世界矩形 AABB（左上角 + 宽高）
function M.aabb(ax, ay, aw, ah, bx, by, bw, bh)
    return ax < bx + bw and ax + aw > bx and ay < by + bh and ay + ah > by
end

-- 两个 rect 表之间的 AABB
function M.rectsHit(a, b)
    if not a or not b then return false end
    return M.aabb(a.x, a.y, a.w, a.h, b.x, b.y, b.w, b.h)
end

-- 千分位
function M.comma(n)
    local s = tostring(math.floor(tonumber(n) or 0))
    local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    out = out:gsub("^,", "")
    return out
end

-- 缓动
function M.easeInOut(t)
    if t < 0.5 then return 2 * t * t end
    local u = -2 * t + 2
    return 1 - (u * u) / 2
end

function M.easeOutQuad(t) return 1 - (1 - t) * (1 - t) end

return M
