-- ================================================================
-- 伐木远征 · 工具模块
--   控件创建（纯色块 / 圆 / 三角形 / 文本）、配色运算、数值工具。
--   本模块不参与玩法推进，只提供无副作用的构建与查询能力。
-- ================================================================

---@diagnostic disable: undefined-global

local M = {}
local state = require("state")
local config = require("config")

-- ================================================================
-- ★ 颜色
-- ================================================================
function M.hex2rgb(hex)
    local s = tostring(hex or ""):gsub("#", "")
    if #s ~= 6 then return 255, 255, 255 end
    return tonumber(s:sub(1, 2), 16) or 255,
        tonumber(s:sub(3, 4), 16) or 255,
        tonumber(s:sub(5, 6), 16) or 255
end

local function clamp255(v)
    v = math.floor(v + 0.5)
    if v < 0 then return 0 end
    if v > 255 then return 255 end
    return v
end

function M.rgb2hex(r, g, b)
    return string.format("%02X%02X%02X", clamp255(r), clamp255(g), clamp255(b))
end

-- 十六进制字符串 → Color（支持独立 alpha 0-255）
function M.hexToColor(hex)
    local r, g, b = M.hex2rgb(hex)
    return Color.FromRGB(r, g, b)
end

function M.hexToColorA(hex, alpha)
    local r, g, b = M.hex2rgb(hex)
    local a = math.floor(alpha or 255)
    if a < 0 then a = 0 end
    if a > 255 then a = 255 end
    return Color.FromRGBA(r, g, b, a)
end

-- 两色线性混合，返回十六进制串
function M.mix(a, b, t)
    local ar, ag, ab = M.hex2rgb(a)
    local br, bg, bb = M.hex2rgb(b)
    return M.rgb2hex(ar + (br - ar) * t, ag + (bg - ag) * t, ab + (bb - ab) * t)
end

-- 变亮（amt>0）/ 变暗（amt<0）
function M.shade(hex, amt)
    local r, g, b = M.hex2rgb(hex)
    if amt >= 0 then
        return M.rgb2hex(r + (255 - r) * amt, g + (255 - g) * amt, b + (255 - b) * amt)
    end
    return M.rgb2hex(r * (1 + amt), g * (1 + amt), b * (1 + amt))
end

-- 色带：2 色或 3 色
function M.ramp(colors, t)
    if t < 0 then t = 0 end
    if t > 1 then t = 1 end
    local n = #colors
    if n == 1 then return colors[1] end
    if n == 2 then return M.mix(colors[1], colors[2], t) end
    if t < 0.5 then return M.mix(colors[1], colors[2], t * 2) end
    return M.mix(colors[2], colors[3], (t - 0.5) * 2)
end

-- 稳定的「每格噪声」0..1（只用于水色微变化，不需要和原版逐位一致）
function M.hash2(x, y)
    local v = math.sin(x * 12.9898 + y * 78.233) * 43758.5453
    return v - math.floor(v)
end

-- ================================================================
-- ★ 数值工具
-- ================================================================
function M.clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

function M.lerp(a, b, t)
    return a + (b - a) * t
end

function M.round(v)
    return math.floor((tonumber(v) or 0) + 0.5)
end

-- ================================================================
-- ★ 指定图片控件的图源（真机出现「?」缺失框时用）
--   元件的图源是只读属性，脚本只能用 SetImage 在运行时覆盖。
--   ★ 这是纯色块工程里唯一「可能失败」的一步 —— 一律 pcall，
--     失败就当作「画成矩形」，绝不因此中断渲染。
-- ================================================================
function M.applyImage(ctrl, imageId)
    if not ctrl or not imageId or imageId <= 0 then return false end
    if pcall(function() ctrl:SetImage(Enum.ImageSource.StaticReference, imageId) end) then
        return true
    end
    return pcall(function() ctrl:SetImage("StaticReference", imageId) end)
end

-- ================================================================
-- ★ 创建纯色块控件 —— 全部纯色图形的统一入口
--   首选「图片·矩形」元件（自带矩形图元，真机不需要配白图）；
--   拿不到时**当场回退**「图片」元件（官方内置，但默认没图源）。
--   ★ pcall 包住：真机遇到存档里不存在的元件索引会抛错（不是返回 nil）。
-- ================================================================
function M.instantiateRect(parent)
    local host = parent or state.parent
    local rectId = state.rectPrefabId or 0
    local ok, ctrl = false, nil
    if rectId > 0 then
        ok, ctrl = pcall(game.InstantiateClientUIControl, rectId, host)
        if ok and ctrl then return ctrl, rectId end
    end
    local imgId = state.imagePrefabId or 0
    if imgId > 0 and imgId ~= rectId then
        ok, ctrl = pcall(game.InstantiateClientUIControl, imgId, host)
        if ok and ctrl then return ctrl, imgId end
    end
    return nil, 0
end

-- ================================================================
-- ★ 创建一个控件
--   imageId 传 config.PRIM_CIRCLE 就画圆（SetImage 内置圆图元），
--   传 nil / config.PRIM_RECT 就画矩形。
-- ================================================================
function M.createControl(x, y, w, h, color, parent, imageId)
    local ctrl, usedId = M.instantiateRect(parent)
    if not ctrl then return nil end
    pcall(function()
        ctrl:SetAnchorMin(0.5, 0.5)
        ctrl:SetAnchorMax(0.5, 0.5)
        ctrl:SetPivot(0.5, 0.5)
        ctrl:SetSizeDelta(w, h)
        ctrl:SetAnchoredPosition(x, y)
    end)
    -- 图源先于染色：SetImage 有可能清掉 tint
    local img = imageId
    if img == nil then
        if usedId == state.rectPrefabId then
            img = config.PRIM_RECT
        end
    end
    if img and img ~= config.PRIM_RECT then
        M.applyImage(ctrl, img)
    elseif usedId ~= state.rectPrefabId then
        M.applyImage(ctrl, state.rectImageId)
    end
    if color then pcall(function() ctrl.imageColor = color end) end
    pcall(function() ctrl:SetActive(true) end)
    return ctrl
end

-- 圆形：宽=高=直径
function M.createDisc(x, y, d, color, parent)
    local c = M.createControl(x, y, d, d, color, parent, config.PRIM_CIRCLE)
    if not c then c = M.createControl(x, y, d, d, color, parent, nil) end
    return c
end

-- ================================================================
-- ★ 创建文本控件
-- ================================================================
function M.createText(x, y, w, h, text, colorHex, fontSize, parent)
    local pid = state.textPrefabId or 0
    if pid <= 0 then return nil end
    local ok, ctrl = pcall(game.InstantiateClientUIControl, pid, parent or state.parent)
    if not ok or not ctrl then return nil end
    pcall(function()
        ctrl:SetAnchorMin(0.5, 0.5)
        ctrl:SetAnchorMax(0.5, 0.5)
        ctrl:SetPivot(0.5, 0.5)
        ctrl:SetSizeDelta(w, h)
        ctrl:SetAnchoredPosition(x, y)
        if text ~= nil then ctrl.text = text end
        if fontSize and fontSize > 0 then ctrl.fontSize = fontSize end
        ctrl:SetActive(true)
    end)
    if colorHex then M.setTextColor(ctrl, colorHex, 255) end
    return ctrl
end

-- 文本框控件的字色字段是 fontColor；imageColor 是给图片控件的。
function M.setTextColor(ctrl, hex, alpha)
    if not ctrl then return end
    local c = M.hexToColorA(hex, alpha or 255)
    pcall(function() ctrl.fontColor = c end)
    pcall(function() ctrl.imageColor = c end)
end

function M.setText(ctrl, text)
    if not ctrl then return end
    pcall(function() ctrl.text = text end)
end

-- ================================================================
-- ★ 控件属性写入（一律 pcall：某些模板缺这个字段不该把整帧打断）
-- ================================================================
function M.setPosition(ctrl, x, y)
    if not ctrl then return end
    pcall(function() ctrl:SetAnchoredPosition(x, y) end)
end

function M.setSize(ctrl, w, h)
    if not ctrl then return end
    pcall(function() ctrl:SetSizeDelta(w, h) end)
end

function M.setColor(ctrl, color)
    if not ctrl then return end
    pcall(function() ctrl.imageColor = color end)
end

function M.setVisible(ctrl, visible)
    if not ctrl then return end
    pcall(function() ctrl:SetActive(visible and true or false) end)
end

function M.toLast(ctrl)
    if not ctrl then return end
    pcall(function() ctrl:SetAsLastSibling() end)
end

function M.toFirst(ctrl)
    if not ctrl then return end
    pcall(function() ctrl:SetAsFirstSibling() end)
end

return M
