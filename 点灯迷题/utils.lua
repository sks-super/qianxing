-- ================================================================
-- 点灯迷题 工具模块
--   控件创建（纯色矩形 / 文本）、配色解析、显隐与透明度、小工具函数。
--   本模块不持有游戏状态，只提供无副作用的构建与查询能力。
-- ================================================================

---@diagnostic disable: undefined-global

local M = {}
local state = require("default_import_file/state")
local config = require("default_import_file/config")

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
-- ★ 创建纯色矩形控件（parent 缺省挂根）
--   面板 / 遮罩 / 卡片 / 按钮底 / 灯格 / 粒子全部由它创建。
--   ★ 叠放完全靠「创建顺序」：同一容器里后创建的在上（真机渲染规则），
--     所以每个组件都按「底图 → 文字 → 点击区域」的顺序建。
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
-- ★★ 创建「可点击区域」（光标检测区域元件）
--   ★ 为什么必须单独建一个控件：
--     千星里只有 ClientUIPresetButtonControl（预设按钮）与
--     ClientUICursorEventAreaControl（光标检测区域）带 AddCursorEventListener。
--     图片控件（rectPrefabId 那一类）根本没有这个方法 —— 直接绑在底图上
--     会被 pcall 静默吞掉，真机表现就是「按钮看得见、鼠标点不动」。
--   ★ 回退：未配置 cursorPrefabId 时，退化为「把监听直接绑在传入的 fallback 控件上」，
--     并只提示一次 —— 这样老工程不会因为缺参数而直接崩，只是仍然点不动。
-- ================================================================
local warnedHit = false
function M.createHit(x, y, w, h, parent, onDown, fallback)
    local pid = state.cursorPrefabId or 0
    local ctrl
    if pid > 0 then
        local ok, c = pcall(function()
            return game.InstantiateClientUIControl(pid, parent or state.parent)
        end)
        if ok then ctrl = c end
    end
    if not ctrl then
        -- 回退路径：能力不足，尽量把监听绑在底图上（老版本行为）
        if fallback and onDown then
            pcall(function()
                fallback:AddCursorEventListener(Enum.CursorEventType.CursorDown, function()
                    onDown()
                end)
            end)
        end
        if not warnedHit then
            warnedHit = true
            printerr("警告：未配置 cursorPrefabId（光标检测区域元件），鼠标点击将无法生效。" ..
                     "请在沙箱里新增一个「光标检测区域」客户端控件并把它填进脚本参数。")
        end
        return nil
    end
    -- ★ 每个属性各自 pcall：任何一个字段在某种控件类型上不存在，
    --   都不能连累后面的赋值（尤其是置透明 —— 漏了它，点击区域会变成
    --   一块不透明色块，把刚建好的文字整个盖住）。
    pcall(function() ctrl.imageColor = Color.FromRGBA(255, 255, 255, 0) end)
    pcall(function() ctrl:SetAnchorMin(0.5, 0.5) end)
    pcall(function() ctrl:SetAnchorMax(0.5, 0.5) end)
    pcall(function() ctrl:SetPivot(0.5, 0.5) end)
    pcall(function() ctrl:SetSizeDelta(w, h) end)
    pcall(function() ctrl:SetAnchoredPosition(x, y) end)
    pcall(function() ctrl.raycastTarget = true end)   -- 保证能被光标射线命中
    pcall(function() ctrl.interactable = true end)
    if onDown then
        pcall(function()
            ctrl:AddCursorEventListener(Enum.CursorEventType.CursorDown, function()
                onDown()
            end)
        end)
    end
    ctrl:SetActive(true)
    return ctrl
end

-- ================================================================
-- ★ 给可点击区域补「悬停 / 移出 / 抬起」动效
--   onEnter / onExit 可为 nil（触屏设备不会触发，属正常）。
-- ================================================================
function M.bindHover(hit, onEnter, onExit, onUp)
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
    if onUp then
        pcall(function()
            hit:AddCursorEventListener(Enum.CursorEventType.CursorUp, function() onUp() end)
        end)
    end
end

-- ================================================================
-- ★ 位置 / 尺寸的便捷写手（每帧动效会被调用很多次，统一走 pcall 保护）
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


-- ================================================================
-- ★ 把文本控件的底色置为【透明】
--   ★★ 真机 ClientUITextBoxControl 有独立的 bgColor（背景色）字段，
--      不显式设置就沿用预制体的默认底色 —— 于是界面里所有文本块都会
--      渲染成实心色块，把它们本该压着的色块 / 灯格整个盖住。
--      模拟器忽略该字段，所以本地怎么看都是对的（「模拟器对、真机错」的典型）。
--   ★ imageColor 不是文本框的字段（设了无效），别再靠它取巧。
-- ================================================================
function M.setTextBgTransparent(ctrl)
    if not ctrl then return end
    pcall(function() ctrl.bgColor = Color.FromRGBA(0, 0, 0, 0) end)
end

-- ================================================================
-- ★ 设置文本控件颜色
--   文本框的字色字段是 fontColor；imageColor 只属于图片控件。
--   两者都尝试，既能用于文本框模板，也兼容「拿图片元件当文本底」的自定义模板。
-- ================================================================
function M.setTextColor(ctrl, hex, alpha)
    if not ctrl then return end
    local c = M.hexToColorA(hex, alpha)
    pcall(function() ctrl.fontColor = c end)
    pcall(function() ctrl.imageColor = c end)
end

-- ================================================================
-- ★★ 文本控件的「最小可用高度」（真机实测结论，2026-10-13 逐像素对账确认）
--   文本框预制体有一个下限：**盒子太矮时一个字都不画**。
--   实测同一套代码在真机上的表现：
--     · 高 56 / 54 / 30 的文本框 —— 正常显示
--     · 高 26 / 22 的文本框（卡片关卡名、难度行、页脚）—— **完全空白**
--   模拟器照画不误，所以本地怎么看都是对的（又一个「模拟器对、真机错」）。
--   → 这里把每个文本盒子的高度兜到 MIN_TEXT_H 以上。文字是垂直居中的，
--     加高盒子不会改变文字的视觉位置，只是给它留够可绘制空间。
-- ================================================================
local MIN_TEXT_H = 36
-- ★ 对外暴露：布局模块（menu/tutorial/winUI）要按它算「文字盒子实际占多高」，
--   否则会出现「按自己给的高度排的版，实际盒子被兜高后和隔壁打架」。
M.MIN_TEXT_H = MIN_TEXT_H

-- ================================================================
-- ★ 创建文本控件（需已配置 textPrefabId，否则返回 nil，调用方自行降级）
-- ================================================================
function M.createText(x, y, w, h, text, color, fontSize, parent)
    local pid = state.textPrefabId or 0
    if pid <= 0 then return nil end
    local ctrl = game.InstantiateClientUIControl(pid, parent or state.parent)
    if not ctrl then return nil end
    local boxH = tonumber(h) or 0
    if boxH < MIN_TEXT_H then boxH = MIN_TEXT_H end     -- ★ 见上方说明
    ctrl:SetAnchorMin(0.5, 0.5)
    ctrl:SetAnchorMax(0.5, 0.5)
    ctrl:SetPivot(0.5, 0.5)
    ctrl:SetSizeDelta(w, boxH)
    ctrl:SetAnchoredPosition(x, y)
    M.setTextBgTransparent(ctrl)     -- ★ 底色透明：不设就会被预制体底色盖住别人
    -- ★ 显式关掉「字号自适应」：预制体若开了它，矮盒子会把字号一路缩到画不出来。
    pcall(function() ctrl.adaptiveFontSize = false end)
    pcall(function() ctrl.horizontalAlignment = Enum.TextHorizontalAlignment.Middle end)
    pcall(function() ctrl.verticalAlignment = Enum.TextVerticalAlignment.Middle end)
    pcall(function() ctrl.raycastTarget = false end)     -- 文本不该吃光标
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
-- ★ 更新文本内容（pcall 保护：模板字段缺失不影响主流程）
-- ================================================================
function M.setText(ctrl, text)
    if not ctrl then return end
    pcall(function() ctrl.text = text end)
end

-- ================================================================
-- ★ 设置【图片控件】不透明度（保留原色相，仅替换 alpha）
--   灯格在「亮 / 灭」之间切换时复用同一控件，不做销毁重建。
-- ================================================================
function M.setAlpha(ctrl, hex, alpha)
    if not ctrl then return end
    pcall(function()
        ctrl.imageColor = M.hexToColorA(hex, alpha)
    end)
end

-- ================================================================
-- ★ 显示 / 隐藏控件
-- ================================================================
function M.setVisible(ctrl, visible)
    if not ctrl then return end
    pcall(function() ctrl:SetActive(visible and true or false) end)
end

-- ================================================================
-- ★ 批量设置显隐
-- ================================================================
function M.setVisibleAll(list, visible)
    for _, c in ipairs(list or {}) do M.setVisible(c, visible) end
end

-- ================================================================
-- ★ 居中面板层的整体放大系数（由 game.lua 按画布大小算好写进 state.uiScale）
--   ★ 教程 / 结算两层的容器被整体 SetLocalScale 放大，容器内的坐标系也随之放大；
--     而粒子（fx）挂在**没有**被放大的 containerFx 上、用的是世界坐标 ——
--     所以这两层里每一次 fx.spawn 的坐标与粒子尺寸都要乘这个系数，否则
--     粒子会错位到面板的左上方。
-- ================================================================
function M.uiScale()
    local k = state.uiScale
    if type(k) ~= "number" or k <= 0 then return 1 end
    return k
end

-- ================================================================
-- ★ 设置字号（动效里会用到，统一 pcall 保护）
-- ================================================================
function M.setFontSize(ctrl, size)
    if not ctrl or not size or size <= 0 then return end
    pcall(function() ctrl.fontSize = size end)
end

-- ================================================================
-- ★ 文本描边（让文字压在花哨背景上也读得清；模板不支持就静默跳过）
-- ================================================================
function M.setTextOutline(ctrl, hex, width)
    if not ctrl then return end
    pcall(function() ctrl.enableOutline = true end)
    pcall(function() ctrl.outlineColor = M.hexToColor(hex or "FFFFFF") end)
    pcall(function() if width then ctrl.outlineWidth = width end end)
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
-- ★ 线性插值（0-255 用）
-- ================================================================
function M.lerp(a, b, t)
    return a + (b - a) * t
end

return M
