-- ================================================================
-- TickHop 工具模块
--   控件创建（纯色矩形 / 文本）、配色解析、AABB 判定、HUD 消息。
--   本模块不参与玩法状态推进，只提供无副作用的构建与查询能力。
-- ================================================================

---@diagnostic disable: undefined-global

local M = {}
local state = require("state")
local config = require("config")

-- ================================================================
-- ★ 配色：十六进制 RGB 字符串 → Color
--   支持 "RRGGBB" / "#RRGGBB"；解析失败回退白色。
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

-- 同上，但带独立透明度（0-255）
function M.hexToColorA(hex, alpha)
    local s = tostring(hex or ""):gsub("#", "")
    if #s ~= 6 then return Color.FromRGBA(255, 255, 255, alpha or 255) end
    local r = tonumber(s:sub(1, 2), 16) or 255
    local g = tonumber(s:sub(3, 4), 16) or 255
    local b = tonumber(s:sub(5, 6), 16) or 255
    return Color.FromRGBA(r, g, b, math.floor(alpha or 255))
end

-- ================================================================
-- ★ 合并配色：关卡 palette 覆盖 DEFAULT_PALETTE
--   level.lua 与 menu.lua 共用，保证「配色真源」只有 config 一处。
-- ================================================================
function M.resolvePalette(data)
    local out = {}
    for k, v in pairs(config.DEFAULT_PALETTE or {}) do out[k] = v end
    if type(data) == "table" and type(data.palette) == "table" then
        for k, v in pairs(data.palette) do out[k] = v end
    end
    return out
end

-- ================================================================
-- ★ 创建纯色矩形控件（parent 缺省挂根）
--   所有可视对象（背景/平台/玩家/门/道具/虚拟按钮）都由它创建。
-- ================================================================
function M.createControl(prefabId, x, y, w, h, color, parent)
    if not prefabId or prefabId <= 0 then return nil end
    local ctrl = game.InstantiateClientUIControl(prefabId, parent or state.parent)
    if not ctrl then return nil end
    ctrl:SetAnchorMin(0.5, 0.5)
    ctrl:SetAnchorMax(0.5, 0.5)
    ctrl:SetPivot(0.5, 0.5)
    ctrl:SetSizeDelta(w, h)
    if color then ctrl.imageColor = color end
    ctrl:SetAnchoredPosition(x, y)
    ctrl:SetActive(true)
    return ctrl
end

-- ================================================================
-- ★ 设置文本控件颜色
--   ★ 文本框控件（ClientUITextBoxControl）的字色字段是 fontColor；
--     imageColor 只属于图片控件。两者都尝试，既能用于文本框模板，
--     也能兼容「拿图片元件当文本底」的自定义模板。
-- ================================================================
function M.setTextColor(ctrl, hex, alpha)
    if not ctrl then return end
    local c = M.hexToColorA(hex, alpha)
    pcall(function() ctrl.fontColor = c end)
    pcall(function() ctrl.imageColor = c end)
end

-- ================================================================
-- ★ 创建文本控件（需已配置 textPrefabId，否则返回 nil，调用方自行降级）
--   color: Color（缺省不改，保留模板颜色）
-- ================================================================
function M.createText(x, y, w, h, text, color, fontSize, parent)
    local pid = state.textPrefabId or 0
    if pid <= 0 then return nil end
    local ctrl = game.InstantiateClientUIControl(pid, parent or state.parent)
    if not ctrl then return nil end
    ctrl:SetAnchorMin(0.5, 0.5)
    ctrl:SetAnchorMax(0.5, 0.5)
    ctrl:SetPivot(0.5, 0.5)
    ctrl:SetSizeDelta(w, h)
    ctrl:SetAnchoredPosition(x, y)
    pcall(function() if text ~= nil then ctrl.text = text end end)
    pcall(function() if fontSize and fontSize > 0 then ctrl.fontSize = fontSize end end)
    if color then
        pcall(function() ctrl.fontColor = color end)
        pcall(function() ctrl.imageColor = color end)
    end
    ctrl:SetActive(true)
    return ctrl
end

-- ================================================================
-- ★ 更新文本控件内容（pcall 保护：模板字段缺失不影响主流程）
-- ================================================================
function M.setText(ctrl, text)
    if not ctrl then return end
    pcall(function() ctrl.text = text end)
end

-- ================================================================
-- ★ 设置【图片控件】不透明度（保留原色相，仅替换 alpha）
--   平台在「实体 / 虚化」之间切换时复用同一控件，不做销毁重建。
--   ★ 文本控件请改用 setTextColor（字色字段是 fontColor，不是 imageColor）。
-- ================================================================
function M.setAlpha(ctrl, hex, alpha)
    if not ctrl then return end
    pcall(function()
        ctrl.imageColor = M.hexToColorA(hex, alpha)
    end)
end

-- ================================================================
-- ★ 显示控件 / 隐藏控件
-- ================================================================
function M.setVisible(ctrl, visible)
    if not ctrl then return end
    pcall(function() ctrl:SetActive(visible and true or false) end)
end

-- ================================================================
-- ★ AABB 重叠判定（中心点 + 半宽半高）
-- ================================================================
function M.aabbOverlap(ax, ay, ahw, ahh, bx, by, bhw, bhh)
    return math.abs(ax - bx) < (ahw + bhw) and math.abs(ay - by) < (ahh + bhh)
end

-- ================================================================
-- ★ 数值夹取
-- ================================================================
function M.clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

-- ================================================================
-- ★ HUD 消息：写入底部提示文本（messageText）
-- ================================================================
function M.setMessage(msg)
    M.setText(state.messageText, msg)
end

-- ================================================================
-- ★ 时间格式化：秒 → "秒.百分秒"（如 9.01）
--   与 TickHop 原作的倒计时显示格式一致；负数按 0 处理。
-- ================================================================
function M.formatTime(sec)
    local v = tonumber(sec) or 0
    if v < 0 then v = 0 end
    local whole = math.floor(v)
    local frac = math.floor((v - whole) * 100 + 0.5)
    if frac >= 100 then
        whole = whole + 1
        frac = 0
    end
    return string.format("%d.%02d", whole, frac)
end

return M
