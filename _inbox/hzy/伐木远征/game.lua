-- ================================================================
-- 伐木远征（MExp）主脚本 · 千星奇域客户端 UI Lua
--   玩法：一步一格。推木头、滚木、把木头推进水里搭桥、两根木头拼成木筏渡水，
--         读木牌看进度，一路走到各区终点。
--   规则内核在 mexp_engine.lua（逐条移植自原版计算器的移动状态机），
--   地图数据在 mexp_maps.lua（自原版 .8xv 世界文件解析而来）。
--
--   ★ 挂载位置：客户端控件容器的「容器节点」上（script.object 即父节点）。
--   ★ 本脚本只用「矩形 / 圆 / 三角 / 文本 / 容器节点」五类控件，不需要任何图片素材。
--
--   操作：WASD / 方向键 移动　Z 撤销　R 重置　F 地图　空格 确认/翻页
-- ================================================================

---@diagnostic disable: undefined-global

-- ================================================================
-- ★★ 模块自检（真机白屏的第一号成因）★★
--   千星的规则是：**只有在「客户端脚本资源管理器」里建立了脚本映射的 .lua 才会被
--   打包上传**。少导一个文件，加载阶段的那句 require 就抛错 —— 整份脚本中止，
--   `OnStart` 一行都不会执行，画面上什么都不出现，日志里也只有一条
--   `module 'xxx' not found`。这种「静默空白」最难查，所以这里逐个数 pcall：
--   缺哪个就把名字写在屏幕上，让人不用去翻日志。
--   ⚠️ 每个 require 都写成字面量（不是查表），静态校验器要按字面量抓依赖关系。
-- ================================================================
local MOD, MISSING = {}, {}
local function tryRequire(name, loader)
    local ok, m = pcall(loader)
    if ok and type(m) == "table" then
        MOD[name] = m
    else
        MISSING[#MISSING + 1] = name
    end
end
tryRequire("config",      function() return require("config") end)
tryRequire("state",       function() return require("state") end)
tryRequire("utils",       function() return require("utils") end)
tryRequire("mexp_engine", function() return require("mexp_engine") end)
tryRequire("mexp_maps",   function() return require("mexp_maps") end)
tryRequire("mexp_render", function() return require("mexp_render") end)
tryRequire("mexp_ui",     function() return require("mexp_ui") end)

local BUILD = "mexp-03"

-- 缺模块时的兜底画面：只用官方内置元件，不依赖任何业务模块
--   ⚠️ 这里**不能**读 config（config 本身可能就是缺的那个），所以索引写成字面量；
--     但已把两代编号都列上 —— 兜底画面本来就是为了「什么都不知道时也能看见字」。
local BOOT_RECT_IDS = { 1073741859, 1073741894 }   -- 矩形图片 / 矩形
local BOOT_TEXT_IDS = { 1073741857, 1073741868 }   -- 文本框（新 / 旧）

local function bootMake(ids, parent)
    for i = 1, #ids do
        local ok, c = pcall(game.InstantiateClientUIControl, ids[i], parent)
        if ok and c then return c end
    end
    return nil
end

local function bootDiag(missing)
    printerr("[伐木远征] " .. BUILD .. " 启动失败：缺少脚本模块 " ..
        table.concat(missing, ", ") .. "（请为这些 .lua 建立脚本映射并挂到同一个客户端控件容器）")
    local root = script.object
    if not root then
        printerr("[伐木远征] script.object 为 nil：脚本没有挂在【客户端控件容器】的容器节点上")
        return
    end
    local w, h = 1280, 720
    pcall(function()
        local cw, chh = game.GetUICanvasSize()
        if type(cw) == "number" and cw > 0 then w = cw end
        if type(chh) == "number" and chh > 0 then h = chh end
    end)
    local bg = bootMake(BOOT_RECT_IDS, root)
    if bg then
        pcall(function()
            bg:SetAnchorMin(0.5, 0.5); bg:SetAnchorMax(0.5, 0.5); bg:SetPivot(0.5, 0.5)
            bg:SetSizeDelta(w * 0.86, 260)
            bg:SetAnchoredPosition(0, 0)
            bg.imageColor = Color.FromRGBA(26, 12, 12, 240)
            bg:SetAsLastSibling(); bg:SetActive(true)
        end)
    end
    local t = bootMake(BOOT_TEXT_IDS, root)
    if t then
        pcall(function()
            t:SetAnchorMin(0.5, 0.5); t:SetAnchorMax(0.5, 0.5); t:SetPivot(0.5, 0.5)
            t:SetSizeDelta(w * 0.86 - 48, 210)
            t:SetAnchoredPosition(0, 0)
            t.text = "【伐木远征】启动失败\n\n缺少脚本模块：" ..
                table.concat(missing, "、") ..
                "\n\n请到「客户端脚本资源管理器」为这些 .lua 建立脚本映射，\n并把它们全部挂到同一个客户端控件容器上。"
            t.fontSize = 22
            t.fontColor = Color.FromRGBA(255, 208, 120, 255)
            t:SetAsLastSibling(); t:SetActive(true)
        end)
    end
end

if #MISSING > 0 then
    function OnStart() bootDiag(MISSING) end
    function OnUpdate(dt) end
    return
end

local config = MOD["config"]
local state = MOD["state"]
local utils = MOD["utils"]
local eng = MOD["mexp_engine"]
local maps = MOD["mexp_maps"]
local render = MOD["mexp_render"]
local ui = MOD["mexp_ui"]

-- ★ 前置声明：下面这些函数互相调用，必须先声明 local 再赋值实现
local startMap, finishMove, tryMove, toMenu, toTitle, openSign

local THEME_OF = {}     -- 地图 key -> 主题名
local NAME_OF = {}      -- 地图 key -> 中文名
local ORDER = {}        -- 选关顺序（与 ui 里的卡片顺序一致）

-- ================================================================
-- ★ 读脚本参数
--   ⚠️ 真机「没填」的数字参数返回 0（不是 nil），而 getParamNumber 的默认值只对
--      「非数字」生效 → 所有「默认开」的开关都会被判成假。故约定：
--        · 开关：**-1 = 明确关闭**；0 / 空 = 没配 = 用 config 默认
--        · 索引：0 / 空 = 无效 = 用 config 默认（0 从来不是合法元件索引）
-- ================================================================
local function getParamNumber(name, default)
    local ok, v = pcall(function() return script:GetParam(name) end)
    if not ok then return default end
    if type(v) == "number" then return v end
    if type(v) == "string" then
        local n = tonumber(v)
        if n then return n end
    end
    return default
end

local function paramId(name, dflt)
    local v = getParamNumber(name, dflt)
    if v == nil or v <= 0 then return tonumber(dflt) or 0 end
    return v
end

-- ================================================================
-- ★ 透明容器父节点（定位于世界原点，子控件坐标即世界坐标）
--   挂的是「容器节点」元件（新 1073741860 / 旧 1073741876）：不绘制、不需图源，只用来分层。
-- ================================================================
local function createContainer()
    if not state.parent then return nil end
    local c = utils.instantiate("container", state.parent)
    if c then
        pcall(function()
            c:SetAnchorMin(0.5, 0.5)
            c:SetAnchorMax(0.5, 0.5)
            c:SetPivot(0.5, 0.5)
            c:SetAnchoredPosition(0, 0)
            c:SetSizeDelta(1, 1)
            c:SetActive(true)
        end)
        return c
    end
    -- 兜底：真机若连容器节点都拿不到，退成「图片·矩形」元件（透明、1×1）
    local r = utils.instantiateRect(state.parent)
    if not r then return nil end
    pcall(function()
        r:SetAnchorMin(0.5, 0.5)
        r:SetAnchorMax(0.5, 0.5)
        r:SetPivot(0.5, 0.5)
        r:SetAnchoredPosition(0, 0)
        r:SetSizeDelta(1, 1)
        r.imageColor = Color.FromRGBA(255, 255, 255, 0)
        r:SetActive(true)
    end)
    return r
end

local function ensureContainers()
    local order = { "containerBg", "containerWorld", "containerHud", "containerMenu" }
    local okAll = true
    for _, key in ipairs(order) do
        if not state[key] then
            state[key] = createContainer()
            if not state[key] then okAll = false end
        end
    end
    return okAll
end

-- ================================================================
-- ★ 木牌文案：英文原文 → 中文
-- ================================================================
local function unflow(page)
    local s = tostring(page or "")
    local lines = {}
    local i = 1
    while i <= #s do
        lines[#lines + 1] = s:sub(i, math.min(i + 15, #s))
        i = i + 16
    end
    local out = {}
    for k = 1, #lines do
        local ln = lines[k]
        if k > 1 then
            local prev = lines[k - 1]
            if #prev == 16 and not prev:match("%s$") and ln:match("%S") then
                out[#out + 1] = " "
            end
        end
        out[#out + 1] = ln
    end
    local txt = table.concat(out)
    txt = txt:gsub("%s%s%s+", "\n")
    txt = txt:gsub("%s%s+", " ")
    txt = txt:gsub("{ALPHA}", "Z"):gsub("{2ND}", "R"):gsub("{CLEAR}", "F")
    txt = txt:gsub("{ENTER}", "空格"):gsub("{%+}", "+"):gsub("{%-}", "-")
    txt = txt:gsub("^%s+", ""):gsub("%s+$", "")
    return txt
end

local function isGoalString(s)
    if type(s) ~= "table" then return false end
    local raw = table.concat(s, " ")
    return raw:find("You win!", 1, true) ~= nil or raw:find("Congratulations", 1, true) ~= nil
end

local function openSign(ip)
    local w = state.world
    if not w or not ip then return end
    local raw = w.strings[ip]
    local key = state.mapKey
    local pages = nil
    local table0 = config.TEXTS[key]
    if table0 and table0[ip] then pages = table0[ip] end
    if not pages and config.DIGRESSION_TEXT[key] then
        local info = config.DIGRESSION_TEXT[key]
        if isGoalString(raw) then
            pages = { "你赢了！\n" .. info[1] .. " · 碎片 " .. info[2] }
        else
            pages = { "番外谜题\n" .. info[1] }
        end
    end
    if not pages then
        pages = {}
        if type(raw) == "table" then
            for i = 1, #raw do pages[i] = unflow(raw[i]) end
        else
            pages[1] = unflow(raw)
        end
    end
    local goal = isGoalString(raw)
    ui.openDialog(pages, goal)
    if goal and not state.progress[key] then
        state.progress[key] = true
        state.msgUntil = (state.time or 0) + 2.4
        ui.setHud(NAME_OF[key] or "", state.moves, "「" .. (NAME_OF[key] or "") .. "」已完成")
    end
end

-- ================================================================
-- ★ 开一局
-- ================================================================
local function collectGoalSigns(w)
    local set = {}
    for i = 1, #w.islands do
        local isl = w.islands[i]
        for _, e in ipairs(isl.entities) do
            if e.type == 8 then
                local s = w.strings[e.eb1 or 1]
                if isGoalString(s) then
                    local islId = e.isl or i
                    set[islId .. ":" .. e.num] = true
                end
            end
        end
    end
    return set
end

startMap = function(key)
    local data = maps.MAPS[key]
    if not data then
        utils.setText(state.hudMsg, "没有这张地图：" .. tostring(key))
        return
    end
    local w = eng.newWorld(data)
    state.mapKey = key
    state.world = w
    state.undo = {}
    state.moves = 0
    state.busy = false
    state.stepAcc = 0
    state.preSnap = nil
    state.camInit = false
    state.lookX, state.lookY = 0, 0
    state.lastMap = key
    state.goalSigns = collectGoalSigns(w)
    state.screen = "play"
    state.keysEnabled = true

    render.setWorld(w, THEME_OF[key] or config.DEFAULT_THEME)
    ui.showScreen("play")
    ui.setHud(NAME_OF[key] or key, 0, "")
    ui.closeDialog()
end

-- ================================================================
-- ★ 走一步
-- ================================================================
tryMove = function(dx, dy)
    if state.screen ~= "play" then return end
    if not state.keysEnabled then return end
    if state.busy then return end
    if state.dialog then return end
    local w = state.world
    if not w then return end

    -- 先转身（撞墙也会转头，否则按了方向人还朝着原方向，显得不受控）
    state.lookX, state.lookY = dx, dy

    state.preSnap = w:snapshot()
    w.IT, w.IP = 0, 0
    w:beginMove(w.player, dx, dy, 0)
    state.busy = true
    state.stepAcc = 0
end

finishMove = function()
    local w = state.world
    if not w then state.busy = false return end
    local after = w:sig(w:snapshot())
    if state.preSnap and after ~= w:sig(state.preSnap) then
        state.undo[#state.undo + 1] = state.preSnap
        if #state.undo > config.DEFAULT_UNDO_MAX then table.remove(state.undo, 1) end
        state.moves = (state.moves or 0) + 1
    end
    state.preSnap = nil
    state.busy = false
    ui.setHud(NAME_OF[state.mapKey] or "", state.moves, nil)
    if w.IT ~= 0 then
        local ip = w.IP
        w.IT, w.IP = 0, 0
        openSign(ip)
    end
end

-- ================================================================
-- ★ 撤销 / 重置
-- ================================================================
local function undo()
    if state.screen ~= "play" or state.busy or state.dialog then return end
    local w = state.world
    if not w or #state.undo == 0 then return end
    w:restore(table.remove(state.undo))
    state.moves = math.max(0, (state.moves or 1) - 1)
    ui.setHud(NAME_OF[state.mapKey] or "", state.moves, "")
end

local function resetIsland()
    if state.screen ~= "play" or state.busy or state.dialog then return end
    local w = state.world
    if not w then return end
    local p = w.player
    local isl = w:islandAt(p.x, p.y)
    if isl == 0 then isl = 1 end
    state.undo[#state.undo + 1] = w:snapshot()
    w:resetIsland(isl)
    ui.setHud(NAME_OF[state.mapKey] or "", state.moves, "已重置当前岛屿")
end

-- ================================================================
-- ★ 切屏
-- ================================================================
toMenu = function()
    if state.dialog then ui.closeDialog() end
    state.screen = "select"
    state.keysEnabled = false
    state.menuCursor = state.menuCursor or 1
    ui.showScreen("select")
    ui.refreshCards()
end

toTitle = function()
    state.screen = "title"
    state.keysEnabled = false
    ui.showScreen("title")
end

-- ================================================================
-- ★ 输入
-- ================================================================
local function confirm()
    if state.dialog then
        ui.advanceDialog()
        return
    end
    if state.screen == "title" then
        local key = state.lastMap
        if not maps.MAPS[key] then key = config.REGIONS[1].key end
        startMap(key)
    elseif state.screen == "select" then
        local key = ui.cardKeyAt(state.menuCursor or 1)
        if key then startMap(key) end
    end
end

local function back()
    if state.dialog then
        ui.closeDialog()
        return
    end
    if state.screen == "play" then
        toMenu()
    elseif state.screen == "select" then
        toTitle()
    elseif state.screen == "title" then
        toMenu()   -- 标题页的提示写的就是「按 F 选地图」
    end
end

local function moveCursor(delta)
    if state.screen ~= "select" then return end
    local n = ui.cardCount()
    if n <= 0 then return end
    local i = (state.menuCursor or 1) + delta
    if i < 1 then i = 1 end
    if i > n then i = n end
    state.menuCursor = i
    ui.refreshCards()
end

local function bindKeys(root)
    local K = Enum.KeyEventType

    -- 方向键 / WASD：一步一格
    local function bindMove(downEvt, upEvt, dx, dy, field)
        if not downEvt then return end
        pcall(function()
            root:AddKeyEventListener(downEvt, function()
                if state[field] then return true end
                state[field] = true
                if state.dialog then
                    ui.advanceDialog()
                elseif state.screen == "play" then
                    tryMove(dx, dy)
                elseif state.screen == "select" then
                    if dx ~= 0 then moveCursor(dx) else moveCursor(dy * 3) end
                else
                    confirm()
                end
                return true
            end)
        end)
        if upEvt then
            pcall(function()
                root:AddKeyEventListener(upEvt, function()
                    state[field] = false
                    return true
                end)
            end)
        end
    end

    bindMove(K.KeyboardMoveForwardKeyDown, K.KeyboardMoveForwardKeyUp, 0, -1, "heldW")
    bindMove(K.KeyboardMoveBackwardKeyDown, K.KeyboardMoveBackwardKeyUp, 0, 1, "heldS")
    bindMove(K.KeyboardMoveLeftKeyDown, K.KeyboardMoveLeftKeyUp, -1, 0, "heldA")
    bindMove(K.KeyboardMoveRightKeyDown, K.KeyboardMoveRightKeyUp, 1, 0, "heldD")
    bindMove(K.KeyboardCraftspersonKey36Down, K.KeyboardCraftspersonKey36Up, 0, -1, "heldW")
    bindMove(K.KeyboardCraftspersonKey37Down, K.KeyboardCraftspersonKey37Up, 0, 1, "heldS")
    bindMove(K.KeyboardCraftspersonKey38Down, K.KeyboardCraftspersonKey38Up, -1, 0, "heldA")
    bindMove(K.KeyboardCraftspersonKey39Down, K.KeyboardCraftspersonKey39Up, 1, 0, "heldD")

    local function bindGlobal(evt, fn)
        if not evt then return end
        pcall(function()
            root:AddKeyEventListener(evt, function()
                fn()
                return true
            end)
        end)
    end

    -- 空格：确认 / 翻页（Esc 在千星里没有对应枚举，返回统一用 F）
    bindGlobal(K.KeyboardJumpKeyDown, confirm)
    -- F：返回 / 打开地图
    bindGlobal(K.KeyboardInteractKeyDown, back)
    -- Z：撤销（奇匠 12 = 物理键 Z）
    bindGlobal(K.KeyboardCraftspersonKey12Down, function()
        if state.dialog then return end
        undo()
    end)
    -- R：重置当前岛（角色技能 3 = 物理键 R）
    bindGlobal(K.KeyboardCharacterSkill3KeyDown, function()
        if state.dialog then return end
        if state.screen == "play" then resetIsland() else confirm() end
    end)
end

-- ================================================================
-- ★ 触屏：全屏滑动 + 左下角方向键
-- ================================================================
local function createSwipeArea()
    local cw = state.canvasW or 1280
    local ch = state.canvasH or 720
    local area = utils.createControl(0, 0, cw + 8, ch + 8,
        Color.FromRGBA(0, 0, 0, 1), state.containerHud)
    if not area then return end
    utils.toFirst(area)
    local pressX, pressY = 0, 0
    pcall(function()
        area:AddCursorEventListener(Enum.CursorEventType.CursorDown, function(ev)
            local okx, x, y = pcall(function() return ev:GetPressUIPos() end)
            if okx then pressX, pressY = x, y end
        end)
    end)
    pcall(function()
        area:AddCursorEventListener(Enum.CursorEventType.CursorUp, function(ev)
            local okx, x, y = pcall(function() return ev:GetUIPos() end)
            if not okx then return end
            local dx, dy = x - pressX, y - pressY
            if math.abs(dx) < 40 and math.abs(dy) < 40 then return end
            if state.dialog then
                ui.advanceDialog()
                return
            end
            if state.screen ~= "play" then return end
            if math.abs(dx) > math.abs(dy) then
                tryMove(dx > 0 and 1 or -1, 0)
            else
                tryMove(0, dy > 0 and -1 or 1)
            end
        end)
    end)
end

local function detectTouchDevice()
    local ok, dev = pcall(function() return game.GetDevice() end)
    if not ok then return false end
    return dev == Enum.Device.Mobile or dev == Enum.Device.MobileController
end

-- ================================================================
-- ★ 生命周期
-- ================================================================
function OnStart()
    printerr("[伐木远征] " .. BUILD .. " OnStart 开始")
    local root = script.object
    if not root then
        printerr("错误：script.object 为 nil，请把本脚本挂在【客户端控件容器】的容器节点上")
        return
    end
    state.parent = root

    -- ★★ 元件索引一律取 config.PREFAB（官方两代编号的有序候选），**不读脚本参数** ★★
    --   真机「面板没填的数字参数返回 0」会把元件整个换掉 —— 第 10 批「小人变橙色块」
    --   就是这么来的。实际用的是哪个候选，由 utils.instantiate() 现场探测，见文末日志。
    -- 图源编号仍可由参数覆盖（只在退到「图片」元件时才用得到，默认 0 = 不设）
    state.rectImageId = getParamNumber("rectImageId", 0)

    local vz = getParamNumber("viewZoom", config.DEFAULT_VIEW_ZOOM)
    if vz == nil or vz <= 0 then vz = config.DEFAULT_VIEW_ZOOM end
    state.viewZoom = utils.clamp(vz, 0.5, 3)
    state.tilePx = paramId("tileSize", config.DEFAULT_TILE)
    state.heightPx = paramId("heightPx", config.DEFAULT_HEIGHT_PX)

    -- 画布尺寸
    local okSize, w, h = pcall(function() return game.GetUICanvasSize() end)
    if okSize and type(w) == "number" and w > 0 then state.canvasW = w end
    if okSize and type(h) == "number" and h > 0 then state.canvasH = h end
    state.LEFT = -state.canvasW / 2
    state.RIGHT = state.canvasW / 2
    state.BOTTOM = -state.canvasH / 2
    state.TOP = state.canvasH / 2

    -- 地图元信息
    ORDER = {}
    for _, r in ipairs(config.REGIONS) do
        THEME_OF[r.key] = r.theme
        NAME_OF[r.key] = r.cn
        ORDER[#ORDER + 1] = r.key
    end
    for _, d in ipairs(config.DIGRESSIONS) do
        THEME_OF[d.key] = d.theme
        NAME_OF[d.key] = d.cn
    end

    -- ★ 版本戳 + 画布：真机「改了没生效」时，先看这一行对不对。
    --   同时走 print（普通日志）与 printerr（错误日志）—— 有些客户端只默认展开后者。
    local bootLine = string.format(
        "[伐木远征] %s 启动 | 画布 %dx%d | zoom=%s tile=%s | 图元 %s/%s",
        BUILD, state.canvasW, state.canvasH,
        tostring(state.viewZoom), tostring(state.tilePx),
        tostring(config.PRIM.rect), tostring(config.PRIM.circle))
    if type(print) == "function" then pcall(print, bootLine) end
    printerr(bootLine)

    -- ★ 宿主节点体检：本工程所有坐标都以宿主中心为原点，它必须铺满屏幕且居中。
    --   缩在角落 / 只有一小块 → 整幅画面偏移。这一行是「画面歪了 / 只看见一角」的定位依据。
    --   ⚠️ 每个取值单独 pcall：少一个接口只丢那一项，不能整行都打不出来。
    do
        local parts = {}
        local function grab(label, fn)
            local ok, a, b = pcall(fn)
            if ok and type(a) == "number" then
                parts[#parts + 1] = string.format("%s=(%.1f,%.1f)", label, a,
                    (type(b) == "number") and b or 0)
            else
                parts[#parts + 1] = label .. "=?"
            end
        end
        grab("锚点min", function() return root:GetAnchorMin() end)
        grab("锚点max", function() return root:GetAnchorMax() end)
        grab("位置", function() return root:GetAnchoredPosition() end)
        grab("尺寸", function() return root:GetSizeDelta() end)
        printerr("[伐木远征] 宿主节点 " .. table.concat(parts, " "))

        -- ⚠️ 判据要分两种：锚点 (0,0)-(1,1) 的「拉伸铺满」型节点 sizeDelta 恒为 (0,0)，
        --    那是正常的，不能当「比画布小」报 —— 否则真机上会跳一条假警。
        local okA, aminx, aminy = pcall(function() return root:GetAnchorMin() end)
        local okB, amaxx, amaxy = pcall(function() return root:GetAnchorMax() end)
        local stretched = okA and okB and type(aminx) == "number" and type(amaxx) == "number"
            and (amaxx - aminx) > 0.9 and (amaxy - (aminy or 0)) > 0.9
        local okP, px, py = pcall(function() return root:GetAnchoredPosition() end)
        if okP and type(px) == "number" and (math.abs(px) > 2 or math.abs(py or 0) > 2) then
            printerr("[伐木远征] ⚠️ 宿主节点位置不是 (0,0) → 画面会整体偏移")
        end
        if not stretched then
            local okS, sw, sh = pcall(function() return root:GetSizeDelta() end)
            if okS and type(sw) == "number" and
                (sw < state.canvasW * 0.9 or (sh or 0) < state.canvasH * 0.9) then
                printerr("[伐木远征] ⚠️ 宿主节点没铺满画布 " .. tostring(state.canvasW) .. "x" ..
                    tostring(state.canvasH) .. "（尺寸 " .. tostring(sw) .. "x" .. tostring(sh) ..
                    "）→ 建议锚点设成左上 (0,0) / 右下 (1,1) 拉伸铺满屏幕")
            end
        end
    end

    script:EnableUpdate(true)

    if not ensureContainers() then
        printerr("错误：容器创建失败 —— 容器节点候选 " ..
            table.concat(config.PREFAB.container, " / ") ..
            " 没有一个能造出控件（这个客户端的容器节点索引可能又变了）")
        return
    end

    render.init()
    ui.init({
        onPickMap = function(key) startMap(key) end,
        onDialogNext = function() ui.advanceDialog() end,
    })

    if detectTouchDevice() then
        createSwipeArea()
    else
        createSwipeArea()   -- 桌面上鼠标拖动同样可用
    end

    bindKeys(root)
    toTitle()

    -- ★ 挂靠结果：**实际用到的**索引（探测之后的真值，不是候选表里的第一个）。
    --   没试过的用途打 "-" —— 别让「候选首选」冒充命中。
    --   真机「画面出来了但很怪」时，先确认这几行与编辑器里看到的一致。
    local function idText(kind)
        local v = utils.prefabResolved(kind)
        return v and tostring(v) or "-"
    end
    state.containerPrefabId = utils.prefabResolved("container") or 0
    state.rectPrefabId = utils.prefabResolved("rect") or 0
    state.imagePrefabId = utils.prefabResolved("image") or 0
    state.textPrefabId = utils.prefabResolved("text") or 0
    printerr("[伐木远征] 控件挂靠 container=" .. idText("container") ..
        " rect=" .. idText("rect") ..
        " image=" .. idText("image") ..
        " text=" .. idText("text"))

    printerr("[伐木远征] " .. BUILD .. " 就绪：4 层容器已建、标题页已显示（画布 " ..
        tostring(state.canvasW) .. "x" .. tostring(state.canvasH) .. "）")
end

function OnUpdate(dt)
    if dt > 0.05 then dt = 0.05 end

    if state.screen == "play" and state.world then
        -- 连锁推进：木筏一格一格漂、滚木一格一格滚
        if state.busy then
            state.stepAcc = (state.stepAcc or 0) + dt
            local guard = 0
            while state.busy and state.stepAcc >= config.DEFAULT_STEP_TIME and guard < 64 do
                guard = guard + 1
                state.stepAcc = state.stepAcc - config.DEFAULT_STEP_TIME
                local more = state.world:stepFrame()
                if not more then finishMove() end
            end
        end
        render.update(dt)
        if state.msgUntil and state.time > state.msgUntil then
            state.msgUntil = nil
            ui.setHud(NAME_OF[state.mapKey] or "", state.moves, "")
        end
    else
        state.time = (state.time or 0) + dt
    end
end

function OnDestroy()
    -- 控件随容器一并释放，无需额外清理
end
