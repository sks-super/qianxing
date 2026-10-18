-- ================================================================
-- 2048 · 工具模块
--   控件创建（纯色矩形 / 文本 / 命中区）、配色解析、布局换算、几何与文本工具。
--   本模块不做玩法推进，只提供无副作用的构建与查询能力。
--
--   ★★ 两条真机踩过的坑，已在本文件里根治：
--     ① 文本框不设 bgColor 会带出预制体底色 → 变成实心色块盖住下方内容
--        （模拟器忽略该字段，所以本地看不出来）→ 统一走 setTextBgTransparent()。
--     ② 文本框有最小高度，盒子太矮（< 约 30px）一个字都不画 → MIN_TEXT_H 兜高
--        + 显式 adaptiveFontSize = false。
-- ================================================================

---@diagnostic disable: undefined-global

local M = {}
local state = require("default_import_file/state")
local config = require("default_import_file/config")

-- ★ 文本框最小高度（绝对下限）。真机实测：高 56/54/30 正常、26/22 完全空白。
--   对外暴露：布局必须按「兜高之后的盒子」排，否则会和隔壁打架。
M.MIN_TEXT_H = 36

-- ★★ 文本行高系数：真机文本框还有第二条隐藏规则 ——
--    盒高必须 ≥ 字号 × 该系数，否则【一个字都不画】（控件在、位置对、就是空白）。
--    ★ 这条规则以前被误当成「固定 30px 下限」，于是出现「盒子明明很高却没字」：
--      标题 62 号字塞进 76 高的盒子（需 ≈87）→ 空白；
--      分数数值 34 号字塞进 46 高的盒子（需 ≈48）→ 空白；
--      而 20 号字 / 36 高、44 号字 / 104 高都正常 → 看着像「大字号失灵」。
--    系数由真机实测定标：字号 20 时「高 30 正常、26 空白」→ 阈值落在 26~30，
--    即 1.3~1.5 之间。取 1.45 偏保守（宁可盒子略大，也不让字消失）：
--    文本框不裁剪内容、pivot 居中，所以兜高只会让盒子上下各扩一点，字的位置不变。
M.TEXT_LINE_RATIO = 1.45

-- ★ 文本盒子的实际高度（调用方与布局自检都应该用它，而不是自己写死）
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
    if #s ~= 6 then return Color.FromRGBA(255, 255, 255, a) end
    local r = tonumber(s:sub(1, 2), 16) or 255
    local g = tonumber(s:sub(3, 4), 16) or 255
    local b = tonumber(s:sub(5, 6), 16) or 255
    return Color.FromRGBA(r, g, b, a)
end

-- 拆出 RGB（用于「保留色相、只改 alpha」的逐帧淡出）
function M.hexToRGB(hex)
    local s = tostring(hex or ""):gsub("#", "")
    if #s ~= 6 then return 255, 255, 255 end
    return tonumber(s:sub(1, 2), 16) or 255,
           tonumber(s:sub(3, 4), 16) or 255,
           tonumber(s:sub(5, 6), 16) or 255
end

-- 调色板（当前只有 config 一处真源，函数保留是为了将来接入主题覆盖）
function M.palette()
    return config.DEFAULT_PALETTE or {}
end

function M.pal(key, fallback)
    local p = config.DEFAULT_PALETTE or {}
    local v = p[key]
    if type(v) == "string" then return v end
    return fallback or "FFFFFF"
end

-- 方块取值配色：{ bg, fg }，未列出的值用 fallback（超过 2048 之后）
function M.tileColor(value)
    local v = math.floor(tonumber(value) or 0)
    local t = (config.DEFAULT_TILE_COLORS or {})[v]
    if t then return t[1], t[2] end
    return config.DEFAULT_TILE_FALLBACK_BG or "3C3A32",
           config.DEFAULT_TILE_FALLBACK_FG or "F9F6F2"
end

-- 方块数字字号：位数越多越小（避免长数字溢出格子）
function M.tileFontSize(value)
    local n = #tostring(math.floor(tonumber(value) or 0))
    if n <= 2 then return config.DEFAULT_TILE_FONT_SIZE or 44 end
    if n == 3 then return config.DEFAULT_TILE_FONT_SIZE_LONG or 32 end
    return config.DEFAULT_TILE_FONT_SIZE_LONGER or 26
end

-- ================================================================
-- 布局换算
--   所有排版都按「设计基准 1280×720」写死，运行时整层缩放 k。
--   scene 容器承载 SetLocalScale(k)，因此子控件坐标直接用设计坐标。
-- ================================================================
function M.computeLayout()
    local cw = state.canvasW or config.DEFAULT_VIEW_WIDTH or 1280
    local ch = state.canvasH or config.DEFAULT_VIEW_HEIGHT or 720
    local dw = config.DEFAULT_DESIGN_WIDTH or 1280
    local dh = config.DEFAULT_DESIGN_HEIGHT or 720
    local k = math.min(cw / dw, ch / dh)
    if not k or k <= 0 then k = 1 end
    state.k = k
    state.LEFT = -cw / 2
    state.RIGHT = cw / 2
    state.BOTTOM = -ch / 2
    state.TOP = ch / 2

    -- 棋盘几何（设计坐标）
    local cell = config.DEFAULT_BOARD_CELL or 104
    local gap = config.DEFAULT_BOARD_GAP or 12
    local board = cell * 4 + gap * 5
    local bx = config.DEFAULT_BOARD_CX or -230
    local by = config.DEFAULT_BOARD_CY or 5
    state.boardCX = bx
    state.boardCY = by
    return {
        k = k,
        cell = cell,
        gap = gap,
        board = board,
        bx = bx,
        by = by,
    }
end

-- 设计坐标 → 场景容器局部坐标（scene 已整体缩放，所以就是原值）
function M.dx(x) return x end

-- 棋盘外框（含外圈留白）的边长
function M.boardSize()
    local cell = config.DEFAULT_BOARD_CELL or 104
    local gap = config.DEFAULT_BOARD_GAP or 12
    return cell * 4 + gap * 5
end

-- 棋盘静止时的中心（设计坐标）
function M.boardCenter()
    return config.DEFAULT_BOARD_CX or -230, config.DEFAULT_BOARD_CY or 5
end

-- ★ 第 (r,c) 格中心坐标（1 起始）—— 【相对棋盘中心】的局部坐标！
--   之所以不返回场景坐标：整块棋盘在结算时会被 containerBoard 整体
--   缩放 / 旋转 / 平移。只有当子控件以「棋盘中心」为原点摆放时，
--   容器的轴心才正好落在棋盘中心，缩放与旋转才不会带着平移跑偏。
function M.cellCenter(r, c)
    local cell = config.DEFAULT_BOARD_CELL or 104
    local gap = config.DEFAULT_BOARD_GAP or 12
    local board = M.boardSize()
    local x0 = -board / 2 + gap + cell / 2
    local y0 = board / 2 - gap - cell / 2
    return x0 + (c - 1) * (cell + gap), y0 - (r - 1) * (cell + gap)
end

-- ★ 棋盘局部坐标 → 场景设计坐标（加上棋盘中心）
--   ★★ 易踩的坑：棋盘相关的子控件都挂在 containerBoard 里、用「棋盘中心」当原点；
--      但 containerFx（粒子/飘字）、containerHud（提示）挂在 containerScene 上、
--      用的是「场景原点」。两套坐标系差一个 (BOARD_CX, BOARD_CY)，
--      把 cellCenter() 的结果直接喂给 fx 就会整体偏掉一个棋盘中心。
--      一律用本函数显式换算，别靠心算。
function M.boardToScene(x, y)
    local bx, by = M.boardCenter()
    return (x or 0) + bx, (y or 0) + by
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

-- ================================================================
-- ★ 透明容器父节点
--   容器只用来分组，绝不能裁剪子控件（显式关掉遮罩，否则子控件会被整片裁掉）。
--   定位于场景原点，所以子控件的坐标就是场景坐标。
-- ================================================================
function M.createContainer(parent)
    local pid = state.rectPrefabId or 0
    if pid <= 0 then return nil end
    local ok, c = pcall(game.InstantiateClientUIControl, pid, parent or state.parent)
    if not ok or not c then return nil end
    pcall(function()
        c:SetAnchorMin(0.5, 0.5)
        c:SetAnchorMax(0.5, 0.5)
        c:SetPivot(0.5, 0.5)
        c:SetAnchoredPosition(0, 0)
        c:SetSizeDelta(1, 1)
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

-- ★ 把控件沉到同级最下层
function M.sink(ctrl)
    if not ctrl then return end
    pcall(function() ctrl:SetAsFirstSibling() end)
end

-- ================================================================
-- ★ 按给定顺序重排同层控件（list 从「最下层」到「最上层」）
--   只用 SetAsFirstSibling / SetAsLastSibling —— 这两个在真机与模拟器里
--   效果一致；SetSiblingIndex(i) 在模拟器里实际插到 len-1-i，绝对不要用。
--   典型用法：结算时把「棋盘根」抬到结算面板之上（要做相片），
--             回到游戏时再按同一张表把顺序还原。
-- ================================================================
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

-- ★ 纯色矩形（图片控件）：棋盘底板 / 方块 / 按钮底 / 背景都用它染色
function M.createControl(prefabId, x, y, w, h, color, parent)
    if not prefabId or prefabId <= 0 then return nil end
    local ok, ctrl = pcall(game.InstantiateClientUIControl, prefabId, parent or state.parent)
    if not ok or not ctrl then return nil end
    local okSet = pcall(function()
        applyTransform(ctrl, x, y, w, h)
        ctrl.enableMask = false          -- ★ 不裁剪子控件
        pcall(function() ctrl.raycastTarget = false end)
        if color then ctrl.imageColor = color end
    end)
    if not okSet then return nil end
    ctrl:SetActive(true)
    return ctrl
end

-- ★ 把文本控件的底色置为透明（不设就会被预制体底色当成实心色块画出来）
function M.setTextBgTransparent(ctrl)
    if not ctrl then return end
    pcall(function() ctrl.bgColor = Color.FromRGBA(0, 0, 0, 0) end)
end

function M.setTextColor(ctrl, hex, alpha)
    if not ctrl then return end
    local c = M.hexToColorA(hex, alpha or 255)
    pcall(function() ctrl.fontColor = c end)
end

-- ★ 文本控件
--   align: "left" / "right" / "center"（缺省居中）
function M.createText(x, y, w, h, text, color, fontSize, parent, align)
    local pid = state.textPrefabId or 0
    if pid <= 0 then return nil end
    -- ★ 按「字号 × 行高系数」与绝对下限双重兜高（见 TEXT_LINE_RATIO 注释）
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
        ctrl.adaptiveFontSize = false                 -- ★ 显式关掉，否则矮盒子会缩字
        pcall(function() ctrl.minimumFontSize = 8 end)
        pcall(function() ctrl.horizontalAlignment = halign end)
        pcall(function() ctrl.verticalAlignment = Enum.TextVerticalAlignment.Middle end)
        if text ~= nil then ctrl.text = text end
        if fontSize and fontSize > 0 then ctrl.fontSize = math.floor(fontSize) end
        if color then ctrl.fontColor = color end
    end)
    ctrl:SetActive(true)
    return ctrl
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

-- 图片控件换色（保留 alpha 与否由调用方决定）
function M.setColor(ctrl, hex, alpha)
    if not ctrl then return end
    pcall(function() ctrl.imageColor = M.hexToColorA(hex, alpha or 255) end)
end

function M.setVisible(ctrl, visible)
    -- ★ 自绘按钮是 { base, label, hit } 三件套，必须整组显隐，
    --   否则会出现「底图藏了、命中区还在」这种点得到看不见的幽灵按钮。
    if type(ctrl) == "table" then
        M.setVisible(ctrl.base, visible)
        M.setVisible(ctrl.label, visible)
        M.setVisible(ctrl.hit, visible)
        return
    end
    if not ctrl then return end
    pcall(function() ctrl:SetActive(visible and true or false) end)
end

function M.setScale(ctrl, s)
    -- 自绘按钮整组缩放（结算里「按钮错峰弹出」用得到）
    if type(ctrl) == "table" then
        M.setScale(ctrl.base, s)
        M.setScale(ctrl.label, s)
        M.setScale(ctrl.hit, s)
        return
    end
    if not ctrl then return end
    pcall(function() ctrl:SetLocalScale(s, s, 1) end)
end

function M.setPos(ctrl, x, y)
    if not ctrl then return end
    pcall(function() ctrl:SetAnchoredPosition(x, y) end)
end

function M.setSize(ctrl, w, h)
    if not ctrl then return end
    pcall(function() ctrl:SetSizeDelta(w, h) end)
end

function M.setRotationZ(ctrl, deg)
    if not ctrl then return end
    pcall(function() ctrl:SetLocalRotation(0, 0, deg) end)
end

function M.destroy(ctrl)
    if not ctrl then return end
    pcall(function() game.DestroyClientUIControl(ctrl) end)
end

-- ================================================================
-- ★ 命中区（可点 / 可拖）
--   ★★ 真机铁律：AddCursorEventListener 只对「预设按钮」与「光标检测区域」有效，
--      图片控件上没有这个能力，用 pcall 包着会【静默失败】→「按钮画得出来但点不动」。
--      所以这里按 buttonPrefabId → cursorPrefabId → 图片兜底 的顺序取控件；
--      模拟器对图片控件的光标事件是放行的，所以兜底在本地仍能点。
-- ================================================================
function M.createHit(x, y, w, h, parent, preferCursor)
    local cands = preferCursor
        and { state.cursorPrefabId, state.buttonPrefabId }
        or { state.buttonPrefabId, state.cursorPrefabId }
    local ctrl = nil
    for _, pid in ipairs(cands) do
        if ctrl then break end
        if pid and pid > 0 then
            local ok, c = pcall(game.InstantiateClientUIControl, pid, parent or state.parent)
            if ok and c then ctrl = c end
        end
    end
    if not ctrl then
        ctrl = M.createControl(state.rectPrefabId, x, y, w, h,
            M.hexToColorA("FFFFFF", 0), parent)
    end
    if not ctrl then return nil end
    pcall(function()
        applyTransform(ctrl, x, y, w, h)
        pcall(function() ctrl.raycastTarget = true end)
        pcall(function() ctrl.enableMask = false end)
        -- ★★ 命中区必须【自身不可见】。光标检测区域的预制体可能带底色，
        --    不显式置透明，真机上就会变成一块色块压在按钮的图和字上面
        --    （模拟器对 imageColor 的处理不同，本地完全看不出来）。
        pcall(function() ctrl.imageColor = Color.FromRGBA(255, 255, 255, 0) end)
        pcall(function() ctrl:SetActive(true) end)
    end)
    return ctrl
end

-- 注册光标事件（pcall 保护：控件不支持时静默降级，不影响主流程）
function M.onCursor(ctrl, eventType, fn)
    if not ctrl or not fn then return false end
    local ok = pcall(function() ctrl:AddCursorEventListener(eventType, fn) end)
    return ok == true
end

-- ================================================================
-- ★★ 自绘按钮 = 图片底（rect） + 文本（text） + 命中区（光标检测区域）
--
--   为什么不再用「预设按钮」：
--     预设按钮要靠脚本参数 buttonPrefabId 指定模板。没配时 Instantiate 返回 nil，
--     而旧写法把「文字」也建在 `if hit then` 里面 → 按钮和文字【一起消失】，
--     且不会报错，只留一句 "点不动" 的警告，极难定位。
--   → 现在外观完全由自己画：不依赖任何按钮模板，两个引擎表现一致，
--     按下时换色 + 微缩给出反馈，命中交给光标检测区域（cursorPrefabId）。
--
--   opts = {
--     text, fontSize, textColor, bg, bgDown, alpha, onClick
--   }
--   返回 table：{ base, label, hit, bg, fg, enabled, x, y, w, h }
--   ★ 传入 table 的控件要交给 setVisible / setButtonEnabled / onClick 统一处理，
--     不要在调用处直接对 .base / .hit 逐个操作。
function M.createButton(x, y, w, h, parent, opts)
    opts = opts or {}
    local par = parent or state.containerHud or state.parent
    if not par then return nil end
    if not state.rectPrefabId or state.rectPrefabId <= 0 then return nil end

    local bgHex   = opts.bg or M.pal("btn", "D6CCC2")
    local downHex = opts.bgDown or M.pal("btnDown", "C4B8AC")
    local fgHex   = opts.textColor or M.pal("btnText", "776E65")
    local size    = opts.fontSize or config.DEFAULT_BTN_SIZE or 22
    local alpha   = opts.alpha or 255
    local press   = config.DEFAULT_BTN_PRESS or 0.96

    -- ① 底图
    local base = M.createControl(state.rectPrefabId, x, y, w, h,
        M.hexToColorA(bgHex, alpha), par)
    if not base then return nil end
    -- ★ 底图也必须显式提层：它通常是「父容器里最后一个创建的」，
    --   而模拟器是「先创建在上」—— 不提层就会被同容器里先建的面板底板盖住
    --   （表现为「只有文字、没有按钮底」）。三层的相对顺序靠下面两次 raise 保证：
    --   base（最下） → label → hit（最上）。
    M.raise(base)

    -- ② 文字（压在底图之上）
    local label = M.createText(x, y, w, h, opts.text or "",
        M.hexToColorA(fgHex, 255), size, par)
    M.raise(label)

    -- ③ 命中区（最上层，本身透明）
    local hit = M.createHit(x, y, w, h, par, true)
    M.raise(hit)

    local btn = {
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
            restore()   -- 拖动后抬起可能收不到 CursorUp，这里补一次
        end)
        if opts.onClick then M.onClick(btn, opts.onClick) end
    end

    return btn
end

-- ★ 按钮可用性（btn 是 createButton 返回的 table）
--   不可用 = 底图与文字一起变淡 + 命中区不再接收光标事件
function M.setButtonEnabled(btn, enabled)
    if type(btn) ~= "table" then return end
    btn.enabled = enabled and true or false
    local a = btn.enabled and (btn.alpha or 255)
                         or (config.DEFAULT_BTN_DISABLED_ALPHA or 110)
    M.setColor(btn.base, btn.bg, a)
    M.setTextColor(btn.label, btn.fg or "776E65", a)
    if btn.hit then pcall(function() btn.hit.raycastTarget = btn.enabled end) end
    return btn.enabled
end

-- 点击回调：用 CursorClick —— 只有「按下 + 抬起」都落在控件上才算一次点击
--   btn 可以是 createButton 返回的 table，也可以直接是控件
function M.onClick(btn, fn)
    local target = (type(btn) == "table") and btn.hit or btn
    if not target or not fn then return false end
    local ok = pcall(function()
        target:AddCursorEventListener(Enum.CursorEventType.CursorClick, function() fn() end)
    end)
    return ok == true
end

-- ================================================================
-- 从 CursorEventData 里安全取坐标（不同运行时字段可用性不一，全部 pcall）
--   kind: "pos" 当前点 / "press" 按下点 / "delta" 本次位移
-- ================================================================
function M.cursorPos(data, kind)
    if not data then return nil, nil end
    local x, y
    pcall(function()
        if kind == "press" and data.GetPressUIPos then
            x, y = data:GetPressUIPos()
        elseif kind == "delta" and data.GetUIPosDelta then
            x, y = data:GetUIPosDelta()
        elseif data.GetUIPos then
            x, y = data:GetUIPos()
        end
    end)
    if type(x) ~= "number" or type(y) ~= "number" then return nil, nil end
    return x, y
end

-- ================================================================
-- 数值工具
-- ================================================================
function M.clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

function M.lerp(a, b, t) return a + (b - a) * t end

-- 千分位（分数显示："12,345"）
function M.comma(n)
    local s = tostring(math.floor(tonumber(n) or 0))
    local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    out = out:gsub("^,", "")
    return out
end

-- 秒 → "mm:ss"
function M.mmss(sec)
    local v = math.max(0, math.floor(tonumber(sec) or 0))
    return string.format("%02d:%02d", math.floor(v / 60), v % 60)
end

return M
