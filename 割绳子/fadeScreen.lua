-- ================================================================
-- 全屏黑幕过渡模块
--   用途：关卡切换时在 UI 最顶层显示 3000x3000 黑色矩形，
--         透明度 0 → maxAlpha 渐显 → 维持 holdTime → 渐隐回 0。
--         在渐隐开始前（渐显完成的瞬间，onPeak 回调）完成关卡加载，
--         使新关卡在黑幕掩护下就位，再渐隐露出。
--   节点：OnStart 预创建一次（隐藏、alpha=0），过渡期间保持最顶层，
--         过渡结束隐藏整节点（复用不销毁，符合项目“节点预创建”约定）。
-- ================================================================

---@diagnostic disable: undefined-global

local M = {}
local state = require("state")
local config = require("config")

-- 运行时状态
M.ctrl = nil        -- 黑幕控件
M.alpha = 0         -- 当前不透明度（0 ~ maxAlpha）
M.maxAlpha = 100
M.active = false
M.phase = "idle"    -- idle | fadeIn | hold | fadeOut
M.timer = 0
M.fadeInTime = 0.3
M.holdTime = 0.2
M.fadeOutTime = 0.3
M.onPeak = nil      -- 渐显完成、渐隐开始前的回调（在此完成关卡加载）

-- 把当前 alpha 写入黑幕颜色（黑色 + 透明度）
local function applyAlpha()
    if not M.ctrl then return end
    pcall(function()
        M.ctrl.imageColor = Color.FromRGBA(0, 0, 0, math.floor(M.alpha))
    end)
end

-- OnStart 调用：预创建黑幕节点（初始隐藏、alpha=0），挂到黑幕容器 containerFade
function M.init()
    if M.ctrl then return end
    local pid = state.fruitPrefabId or 0
    if pid <= 0 then return end
    if not state.containerFade and not state.parent then return end
    local ctrl = game.InstantiateClientUIControl(pid, state.containerFade or state.parent)
    if not ctrl then return end
    ctrl:SetAnchorMin(0.5, 0.5)
    ctrl:SetAnchorMax(0.5, 0.5)
    ctrl:SetPivot(0.5, 0.5)
    ctrl:SetSizeDelta(3000, 3000)   -- 3000x3000 覆盖全屏
    ctrl:SetAnchoredPosition(0, 0)  -- 画布中心
    pcall(function()
        ctrl.imageColor = Color.FromRGBA(0, 0, 0, 0)
    end)
    ctrl:SetActive(false)           -- 初始隐藏
    M.ctrl = ctrl
end

-- 启动过渡：opts = { fadeInTime, holdTime, fadeOutTime, maxAlpha, onPeak }
--   onPeak 在“渐显完成、渐隐开始前”被调用一次（用于完成关卡加载）。
--   若黑幕不可用（未创建成功），立即同步执行 onPeak，退化为无过渡直切。
--   返回值：
--     true  = 已排程过渡，onPeak 将在 fadeInTime 秒后由 M.update 触发
--     false = 黑幕不可用，onPeak 已在本函数内同步执行完毕（调用方不要再自行加载）
function M.start(opts)
    if not M.ctrl then M.init() end
    opts = opts or {}
    if not M.ctrl then
        if opts.onPeak then
            pcall(opts.onPeak)
        end
        return false
    end
    M.fadeInTime  = opts.fadeInTime  or config.DEFAULT_FADE_IN_TIME  or 0.3
    M.holdTime    = opts.holdTime    or config.DEFAULT_FADE_HOLD_TIME or 0.2
    M.fadeOutTime = opts.fadeOutTime or config.DEFAULT_FADE_OUT_TIME or 0.3
    M.maxAlpha    = opts.maxAlpha    or config.DEFAULT_FADE_MAX_ALPHA or 100
    M.onPeak      = opts.onPeak
    M.alpha = 0
    M.timer = 0
    M.phase = "fadeIn"
    M.active = true
    M.ctrl:SetActive(true)
    applyAlpha()
    return true
end

-- 每帧推进（放在 OnUpdate 末尾调用；黑幕容器创建顺序最靠后，天然在最顶，无需 SetAsLastSibling）
function M.update(dt)
    if not M.active or not M.ctrl then return end

    if M.phase == "fadeIn" then
        M.timer = M.timer + dt
        local t = M.timer / M.fadeInTime
        if t > 1 then t = 1 end
        M.alpha = t * M.maxAlpha
        applyAlpha()
        if t >= 1 then
            -- 渐显完成、渐隐开始前：执行关卡加载回调
            if M.onPeak then
                local cb = M.onPeak
                M.onPeak = nil
                pcall(cb)
            end
            M.phase = "hold"
            M.timer = 0
        end
    elseif M.phase == "hold" then
        M.timer = M.timer + dt
        if M.timer >= M.holdTime then
            M.phase = "fadeOut"
            M.timer = 0
        end
    elseif M.phase == "fadeOut" then
        M.timer = M.timer + dt
        local t = M.timer / M.fadeOutTime
        if t > 1 then t = 1 end
        M.alpha = M.maxAlpha * (1 - t)
        applyAlpha()
        if t >= 1 then
            M.alpha = 0
            M.active = false
            M.phase = "idle"
            M.ctrl:SetActive(false)   -- 隐藏黑幕（节点保留复用）
        end
    end
end

return M
