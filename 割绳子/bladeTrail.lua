-- ================================================================
-- 刀光拖尾模块
-- ================================================================
-- 鼠标左键按住并移动时，沿鼠标轨迹生成一连串细长图片片段，
-- 通过 imageColor alpha 淡出与宽度收缩模拟刀光拖尾。
-- 如需示例图中“两头尖”的笔刷感，可为 bladePrefabId 配置一张
-- 中间粗、两头尖的白色刀光贴图；未配置时回退到 fruitPrefabId
-- 的白色方块，呈现基础光带效果。
--
-- ★ 需求对应说明：
--    1) 所有刀光片段统一挂在“一个父容器节点 bladeContainer”下，
--       层级关系稳定，初始创建后永不销毁、不重排；
--    2) 只要刀光存在并显示，淡出每帧都推进——即使游戏胜利/失败
--       也不卡住（由 game.lua 在“提前 return”之前调用本模块保证）；
--    3) 鼠标按住即显示一个最小长度的“头部刀光”（head blade），
--       即使完全不移动也展示，刀光因此具有最小长度。

---@diagnostic disable: undefined-global

local M = {}
local state = require("state")
local config = require("config")

-- ================================================================
-- 默认参数（可在 config.lua 中覆盖）
-- ================================================================
local BLADE_WIDTH        = config.DEFAULT_BLADE_WIDTH        or 12     -- 刀光基础宽度（像素）
local BLADE_LIFE         = config.DEFAULT_BLADE_LIFE         or 0.25   -- 单个片段存活时间（秒）
local BLADE_MIN_DIST     = config.DEFAULT_BLADE_MIN_DIST     or 6      -- 连续采样点最小间距（用于生成拖尾）
local BLADE_MAX_SEGMENTS = config.DEFAULT_BLADE_MAX_SEGMENTS or 64     -- 同时存在最大片段数（=预创建节点数）
local BLADE_MIN_LENGTH   = config.DEFAULT_BLADE_MIN_LENGTH   or 24     -- 按住不动时刀光仍保持的最小长度

-- ================================================================
-- 内部状态（模块局部，不依赖 state 表，避免层级/生命周期混乱）
-- ================================================================
local pool           = {}   -- 预创建的片段节点（固定顺序，挂在 bladeContainer 下，永不销毁）
local poolUsed       = {}   -- 与 pool 平行的占用标记
local segments       = {}   -- 当前活动片段（含头部刀光 headSeg）
local headSeg        = nil  -- 按住期间始终存在的“头部刀光”，松开/游戏结束后随淡出自然消失
local bladeContainer = nil  -- 唯一父容器节点，承载所有刀光片段
local initialized    = false
local lastX, lastY   = 0, 0   -- 上次采样点（仅用于生成新段）
local lastAngle      = 90     -- 上次刀光朝向（按住静止时沿用）

-- 该模板控件是否支持 imageColor 染色（自定义刀光模板可能无此字段）
local supportsColor = false

-- 预创建一个父容器 + 全部刀光片段节点（仅一次，顺序固定，层级稳定）
local function ensurePool()
    if initialized then return end
    initialized = true

    local pid = state.bladePrefabId or 0
    if pid <= 0 then pid = state.fruitPrefabId or 0 end
    if pid <= 0 then return end

    -- ① 先创建唯一的父容器节点（容纳所有刀光片段），挂到刀光容器 containerBlade
    local c = game.InstantiateClientUIControl(pid, state.containerBlade or state.parent)
    if c then
        c:SetAnchorMin(0.5, 0.5)
        c:SetAnchorMax(0.5, 0.5)
        c:SetPivot(0.5, 0.5)
        c:SetAnchoredPosition(0, 0)   -- 容器定位于世界原点，子节点坐标即世界坐标
        c:SetSizeDelta(1, 1)          -- 自身不占可视面积
        -- 探测是否支持染色（自定义模板可能无 imageColor 字段），用 pcall 防止崩溃
        local ok = pcall(function()
            c.imageColor = Color.FromRGBA(255, 255, 255, 0)
        end)
        supportsColor = ok
        c:SetActive(true)
        bladeContainer = c
    else
        bladeContainer = state.containerBlade or state.parent   -- 兜底：直接挂到根
    end

    -- ② 预创建片段节点，作为 bladeContainer 的子节点
    for i = 1, BLADE_MAX_SEGMENTS do
        local ctrl = game.InstantiateClientUIControl(pid, bladeContainer)
        if ctrl then
            ctrl:SetAnchorMin(0.5, 0.5)
            ctrl:SetAnchorMax(0.5, 0.5)
            ctrl:SetPivot(0.5, 0.5)
            ctrl:SetSizeDelta(1, BLADE_WIDTH)
            ctrl:SetActive(false)
            table.insert(pool, ctrl)
            table.insert(poolUsed, false)
        end
    end
end

-- 从池中取一个空闲节点（不新建控件，稳定性优先）
local function acquireSegmentCtrl()
    for i = #pool, 1, -1 do
        if not poolUsed[i] then
            poolUsed[i] = true
            pool[i]:SetActive(true)
            return pool[i]
        end
    end
    return nil  -- 池满：不再新增控件，避免层级变动
end

-- 回收控件：仅隐藏（“删除内容”），节点保留在池中
local function releaseSegmentCtrl(ctrl)
    if not ctrl then return end
    for i = 1, #pool do
        if pool[i] == ctrl then
            poolUsed[i] = false
            break
        end
    end
    ctrl:SetActive(false)
end

-- ================================================================
-- 模块接口
-- ================================================================

-- 预创建节点池（OnStart 调用，使刀光父容器与片段节点在场景初始层级中就位）
function M.init()
    ensurePool()
end

-- 开始产生刀光拖尾：记录起点（是否真正生成由 updateTrail 的 spawn 标志决定）
function M.startTrail(x, y)
    ensurePool()
    lastX, lastY = x, y
    lastAngle = 90
end

-- 停止（保留接口；新架构下生成由 updateTrail 每帧的 spawn 标志控制，此函数可留空）
function M.stopTrail()
    -- 空实现：淡出持续推进，鼠标松开后已存在片段自然消散
end

-- 强制清理所有现存片段（切关/重置时调用）：仅隐藏，不销毁节点
function M.clearTrail()
    for i = 1, #pool do
        poolUsed[i] = false
        pool[i]:SetActive(false)
    end
    segments = {}
    headSeg = nil
end

-- 更新刀光：
--   1) 每次调用都推进淡出（无论是否按住、是否游戏结束）；
--   2) 仅当 spawn 为真时，刷新“头部刀光”并（移动时）生成拖尾。
function M.updateTrail(x, y, dt, spawn)
    ensurePool()

    -- 1) 生命周期推进（淡出）：任何情况下都执行
    for i = #segments, 1, -1 do
        local seg = segments[i]
        seg.age = seg.age + dt
        if seg.age >= seg.life then
            if seg == headSeg then headSeg = nil end
            releaseSegmentCtrl(seg.ctrl)
            table.remove(segments, i)
        else
            local t = seg.age / seg.life
            local alpha = math.floor(255 * (1 - t))
            -- 宽度从 startWidth 收缩到 0，模拟消散；长度保持避免接缝断裂
            local width = seg.startWidth * (1 - t)
            if supportsColor then
                seg.ctrl.imageColor = Color.FromRGBA(255, 255, 255, alpha)
            end
            seg.ctrl:SetSizeDelta(seg.len, width)
        end
    end

    -- 2) 仅在“按住且非拖拽”时刷新头部刀光并生成拖尾
    if not spawn then return end

    local dx = x - lastX
    local dy = y - lastY
    local dist = math.sqrt(dx * dx + dy * dy)
    local angle = lastAngle
    if dist > 0.001 then
        angle = math.atan(dy, dx) * 180 / math.pi
        lastAngle = angle
    end

    -- 头部刀光：按住期间始终存在，最小长度 BLADE_MIN_LENGTH，方向跟随移动
    if not headSeg then
        local ctrl = acquireSegmentCtrl()
        if ctrl then
            headSeg = {
                ctrl = ctrl,
                age = 0,
                life = BLADE_LIFE,
                startWidth = BLADE_WIDTH,
                len = BLADE_MIN_LENGTH,
            }
            table.insert(segments, headSeg)
        end
    end
    if headSeg then
        headSeg.age = 0                  -- 按住期间保持满亮度，不淡出
        headSeg.len = BLADE_MIN_LENGTH
        headSeg.ctrl:SetAnchoredPosition(x, y)
        headSeg.ctrl:SetSizeDelta(BLADE_MIN_LENGTH, BLADE_WIDTH)
        headSeg.ctrl:SetLocalRotation(0, 0, angle)
        if supportsColor then
            headSeg.ctrl.imageColor = Color.FromRGBA(255, 255, 255, 255)
        end
        headSeg.ctrl:SetActive(true)
    end

    -- 拖尾：移动足够距离时，生成一段会淡出的尾迹（comet tail）
    if dist >= BLADE_MIN_DIST then
        local ctrl = acquireSegmentCtrl()
        if ctrl then
            local midX = (lastX + x) / 2
            local midY = (lastY + y) / 2
            ctrl:SetAnchoredPosition(midX, midY)
            ctrl:SetSizeDelta(dist, BLADE_WIDTH)
            ctrl:SetLocalRotation(0, 0, angle)
            if supportsColor then
                ctrl.imageColor = Color.FromRGBA(255, 255, 255, 255)
            end
            ctrl:SetActive(true)
            table.insert(segments, {
                ctrl = ctrl,
                age = 0,
                life = BLADE_LIFE,
                startWidth = BLADE_WIDTH,
                len = dist,
            })
        end
        lastX, lastY = x, y
    end
end

return M
