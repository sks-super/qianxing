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
-- ★★ 挂靠控件：按「用途」取内置元件索引，全工程只此一处 ★★
--   kind = "host" | "container" | "rect" | "image" | "text" | "textView" | "grid"
--   config.PREFAB[kind] 是**有序候选**（新编号在前、旧编号在后）——
--   官方内置模板编号随客户端版本变，逐个试才不会「换个版本整屏空白」。
--   ★ 刻意**不读脚本参数**：真机没填的数字参数返回 0，靠参数挑元件
--     正是第 10 批「小人变橙色块」的成因。
--   ★ 第一次调用会**实测**哪个候选真能造出控件，然后记住它；同类控件以后直接复用
--     （每帧都在造控件，试错只该发生一次）。换关 / 换存档不改这套缓存。
-- ================================================================
local resolved, logged = {}, {}

local function candidates(kind)
    local t = config.PREFAB
    local v = t and t[kind]
    if type(v) == "number" then return { v } end   -- 允许退化成单个数字
    return v
end

-- 已经实测通过的那个索引；还没试过时返回候选里的第一个（= 首选）
function M.prefabId(kind)
    if resolved[kind] then return resolved[kind] end
    local list = candidates(kind)
    return (list and list[1]) or 0
end

-- **实测命中**的索引；还没造过这类控件时返回 nil。
-- 打日志用：别把「候选里的第一个」当成真值，那会把没试过的用途也打成命中。
function M.prefabResolved(kind)
    return resolved[kind]
end

-- 逐个试候选，第一个造出控件的胜出并缓存；全失败返回 nil（不抛错）
function M.instantiate(kind, parent)
    local host = parent or state.parent
    local list = candidates(kind)
    if not host or not list or #list == 0 then
        if not logged[kind] then
            logged[kind] = true
            printerr("错误：未知的控件用途 '" .. tostring(kind) .. "'（见 config.PREFAB）")
        end
        return nil, 0
    end
    -- 先试上次成功的那个：命中就 O(1) 返回，不必再走候选表
    local cached = resolved[kind]
    if cached then
        local ok, ctrl = pcall(game.InstantiateClientUIControl, cached, host)
        if ok and ctrl then return ctrl, cached end
        resolved[kind] = nil        -- 缓存的索引突然不行了 → 重新探一遍
    end
    for i = 1, #list do
        local pid = list[i]
        if type(pid) == "number" and pid > 0 then
            local ok, ctrl = pcall(game.InstantiateClientUIControl, pid, host)
            if ok and ctrl then
                resolved[kind] = pid
                if not logged[kind] then
                    logged[kind] = true
                    printerr(string.format("[伐木远征] 控件挂靠 %s → %d（候选 %d/%d）",
                        kind, pid, i, #list))
                end
                return ctrl, pid
            end
        end
    end
    if not logged[kind] then
        logged[kind] = true
        printerr("[伐木远征] ⚠️ 控件挂靠失败：" .. tostring(kind) .. " 的 " .. #list ..
            " 个候选索引都造不出控件（config.PREFAB." .. tostring(kind) .. "）")
    end
    return nil, 0
end

-- ================================================================
-- ★ 创建纯色块控件 —— 全部纯色图形的统一入口
--   config.PREFAB.rect 的候选已经把「矩形图片 → 矩形 → 图片」排好，
--   所以这里只需按用途要一个控件；返回 (控件, 实际用到的索引)。
-- ================================================================
function M.instantiateRect(parent)
    return M.instantiate("rect", parent)
end

-- ================================================================
-- ★ 创建一个控件（纯色块 / 圆）
--   imageId 传 config.PRIM.circle 就画圆（SetImage 内置圆图元），
--   传 nil 就让「矩形图片」元件用它自带的矩形图元。
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
    if imageId and imageId > 0 then
        M.applyImage(ctrl, imageId)
    elseif not (config.PREFAB_CARRIES_RECT[usedId]) then
        -- 退到了「图片」元件：它默认不带图源，不补就是真机上的彩色 ?
        M.applyImage(ctrl, state.rectImageId)
    end
    if color then pcall(function() ctrl.imageColor = color end) end
    pcall(function() ctrl:SetActive(true) end)
    return ctrl
end

-- 圆形：宽=高=直径
function M.createDisc(x, y, d, color, parent)
    local c = M.createControl(x, y, d, d, color, parent, config.PRIM.circle)
    if not c then c = M.createControl(x, y, d, d, color, parent, nil) end
    return c
end

-- ================================================================
-- ★ 创建文本控件（「文本框」元件：新 1073741857 / 旧 1073741868）
-- ================================================================
function M.createText(x, y, w, h, text, colorHex, fontSize, parent)
    local ctrl = M.instantiate("text", parent)
    if not ctrl then
        printerr("警告：文本框元件 " .. M.prefabId("text") .. " 拿不到，文字将不显示")
        return nil
    end
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
