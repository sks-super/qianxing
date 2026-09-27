-- ================================================================
-- 浮岛借木 · 工具模块
--   控件创建（纯色矩形 / 文本）、配色解析、数值夹取、缓动、HUD 消息。
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
    if #s ~= 6 then return Color.FromRGBA(255, 255, 255, math.floor(alpha or 255)) end
    local r = tonumber(s:sub(1, 2), 16) or 255
    local g = tonumber(s:sub(3, 4), 16) or 255
    local b = tonumber(s:sub(5, 6), 16) or 255
    return Color.FromRGBA(r, g, b, math.floor(alpha or 255))
end

-- ================================================================
-- ★ 合并配色：关卡 palette 覆盖 DEFAULT_PALETTE
--   保证「配色真源」只有 config 一处。
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
-- ★ 指定图片控件的图源（真机出现「?」缺失框时用）
--   ⚠️ 千星的图片控件，图源是**元件属性**：imageSource / imageId 都是只读字段，
--      脚本只能通过 SetImage(source, id) 在运行时覆盖。所以元件没配图时，
--      真机会把控件画成缺失占位框「?」（imageColor 的染色仍然生效），
--      而模拟器里看着正常 —— 因为模拟器只代理 100001–100006 六种基础图元
--      （100001 = 矩形），那只是「代理图形」，不代表官方素材，真机不认。
--   imageId <= 0 时不动，保留元件自带图源。
-- ================================================================
function M.applyImage(ctrl, imageId)
    if not ctrl or not imageId or imageId <= 0 then return false end
    -- 首选枚举写法；个别绑定只认字符串，失败后再试一次
    if pcall(function() ctrl:SetImage(Enum.ImageSource.StaticReference, imageId) end) then
        return true
    end
    return pcall(function() ctrl:SetImage("StaticReference", imageId) end)
end

-- ================================================================
-- ★ 创建「纯色底图」控件 —— 全部纯色图形的统一入口
--   首选「矩形」元件（state.rectPrefabId，自带矩形图元，真机不需要配白图）；
--   当前存档里没有它时（用户没建 / 老存档）**当场回退**「图片」元件
--   （state.imagePrefabId，官方内置，但默认不带图源，真机会画成彩色「?」）。
--   两级都拿不到 → 返回 nil，调用方自行降级（本工程不会走到这里：
--   图片元件是官方内置模板，任何存档都有）。
--
--   ★ 这里是唯一判断「该不该回退」的地方，所以其它模块**别自己裸调**
--     game.InstantiateClientUIControl 建纯色底图 —— 那样就绕过了回退。
--   ★ pcall 包住：真机遇到存档里不存在的元件索引会抛错（不是返回 nil），
--     而我们要的是「拿到 nil 就走回退」，不能让整局挂掉。
--   返回：ctrl, usedPrefabId（usedPrefabId 用于后续判断要不要补 rectImageId）
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
-- ★ 创建图片控件（parent 缺省挂根）
--   本工程所有可视对象（海面/陆地/装饰/木桩/石头/小人/HUD/黑幕）都由它创建。
--   color = nil 时**不写 imageColor** —— 保留元件自带的配色与美术素材。
--   ★ 「海水 / 草地 / 树木 / 人物」这四个素材元件必须走 color = nil 这条路：
--     一旦写 imageColor，美术素材会被乘上一遍调色板颜色（变暗、串色）。
--   imageId 缺省时，只有「纯色底图」（矩形 / 图片）会自动补上 rectImageId。
--   ★ prefabId 传 state.rectPrefabId 时，实例化失败会自动切到「图片」元件（见上）。
-- ================================================================
function M.createControl(prefabId, x, y, w, h, color, parent, imageId)
    if not prefabId or prefabId <= 0 then return nil end
    local usedPrefabId = prefabId
    local ctrl
    if prefabId == state.rectPrefabId then
        -- 纯色底图：走「矩形 → 图片」两级回退
        ctrl, usedPrefabId = M.instantiateRect(parent)
    else
        local ok
        ok, ctrl = pcall(game.InstantiateClientUIControl, prefabId, parent or state.parent)
        if not ok then ctrl = nil end
    end
    if not ctrl then return nil end
    ctrl:SetAnchorMin(0.5, 0.5)
    ctrl:SetAnchorMax(0.5, 0.5)
    ctrl:SetPivot(0.5, 0.5)
    ctrl:SetSizeDelta(w, h)
    -- 图源要**先于**染色设置：SetImage 可能清掉 tint
    if imageId == nil then
        if usedPrefabId == state.rectPrefabId or usedPrefabId == state.imagePrefabId then
            imageId = state.rectImageId
        end
    end
    M.applyImage(ctrl, imageId)
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
--   ★ 文本控件请改用 setTextColor（字色字段是 fontColor，不是 imageColor）。
-- ================================================================
function M.setAlpha(ctrl, hex, alpha)
    if not ctrl then return end
    pcall(function()
        ctrl.imageColor = M.hexToColorA(hex, alpha)
    end)
end

-- ================================================================
-- ★ 移动控件（视觉补间用）
-- ================================================================
function M.setPosition(ctrl, x, y)
    if not ctrl then return end
    pcall(function() ctrl:SetAnchoredPosition(x, y) end)
end

-- ================================================================
-- ★ 改控件尺寸（复用池里的控件、或重建关卡时改身材）
-- ================================================================
function M.setSize(ctrl, w, h)
    if not ctrl then return end
    pcall(function() ctrl:SetSizeDelta(w, h) end)
end

-- ================================================================
-- ★ 显示控件 / 隐藏控件
-- ================================================================
function M.setVisible(ctrl, visible)
    if not ctrl then return end
    pcall(function() ctrl:SetActive(visible and true or false) end)
end

-- ================================================================
-- ★ 数值夹取 / 线性插值 / 平滑插值
-- ================================================================
function M.clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

function M.lerp(a, b, t)
    return a + (b - a) * t
end

-- 平滑起止（S 形），让位移动画不那么生硬
function M.smoothstep(t)
    if t <= 0 then return 0 end
    if t >= 1 then return 1 end
    return t * t * (3 - 2 * t)
end

-- ================================================================
-- ★ 数值取整（避免像素坐标出现 0.5 引发的模糊）
-- ================================================================
function M.round(v)
    return math.floor((tonumber(v) or 0) + 0.5)
end

-- ================================================================
-- ★ HUD 消息：写入底部一次性消息文本（hudMessage）
-- ================================================================
function M.setMessage(msg)
    M.setText(state.hudMessage, msg)
end

-- ================================================================
-- ★ 动作名 → 中文描述（HUD 与消息栏共用）
-- ================================================================
function M.actionText(kind)
    local map = {
        move    = "移动",
        knock   = "撞断树木",
        push    = "推木桩",
        raise   = "木桩立起",
        fall    = "木桩倒下",
        step_on = "踩上木桩",
        blocked = "此路不通",
        water   = "前方是水",
        rock    = "石头挡住了",
        invalid = "过不去",
    }
    return map[kind] or tostring(kind or "")
end

return M
