-- ================================================================
-- 浮岛借木 · 全屏黑幕过渡模块
--   关卡切换时在 UI 最顶层显示覆盖全屏的矩形，
--   透明度 0 → maxAlpha 渐显 → 维持 holdTime → 渐隐回 0。
--   在渐显转渐隐的峰值处（onPeak 回调）完成关卡重建，
--   新关卡在黑幕掩护下就位，再渐隐露出。
--   节点在 OnStart 预创建一次（隐藏、alpha=0），过渡期间复用不销毁。
-- ================================================================

---@diagnostic disable: undefined-global

local M = {}
local state = require("state")
local config = require("config")
local utils = require("utils")

M.ctrl = nil        -- 黑幕控件
M.alpha = 0         -- 当前不透明度（0 ~ maxAlpha）
M.maxAlpha = 255
M.active = false
M.phase = "idle"    -- idle | fadeIn | hold | fadeOut
M.timer = 0
M.fadeInTime = 0.2
M.holdTime = 0.4
M.fadeOutTime = 0.2
M.onPeak = nil      -- 渐显完成、渐隐开始前的回调（在此重建关卡）
M.colorHex = "000000"

local function applyAlpha()
    if not M.ctrl then return end
    pcall(function()
        local s = M.colorHex
        local r = tonumber(s:sub(1, 2), 16) or 0
        local g = tonumber(s:sub(3, 4), 16) or 0
        local b = tonumber(s:sub(5, 6), 16) or 0
        M.ctrl.imageColor = Color.FromRGBA(r, g, b, math.floor(M.alpha))
    end)
end

-- ================================================================
-- ★ OnStart 调用：预创建黑幕节点（初始隐藏）
-- ================================================================
function M.init()
    if M.ctrl then return end
    if not state.containerFade and not state.parent then return end
    -- ★ 走 utils 的两级回退（矩形 → 图片），别裸调 InstantiateClientUIControl：
    --   否则存档里没有「矩形」元件时，黑幕就整个建不出来。
    local ctrl = utils.instantiateRect(state.containerFade or state.parent)
    if not ctrl then return end
    -- 图源要补，否则（回退到「图片」元件时）真机上黑幕会渲染成一个大号「?」而不是纯黑
    utils.applyImage(ctrl, state.rectImageId)
    ctrl:SetAnchorMin(0.5, 0.5)
    ctrl:SetAnchorMax(0.5, 0.5)
    ctrl:SetPivot(0.5, 0.5)
    ctrl:SetSizeDelta(3000, 3000)   -- 覆盖全屏（远超画布）
    ctrl:SetAnchoredPosition(0, 0)
    pcall(function()
        ctrl.imageColor = Color.FromRGBA(0, 0, 0, 0)
    end)
    ctrl:SetActive(false)
    M.ctrl = ctrl
end

-- ================================================================
-- ★ 启动过渡
--   opts = { fadeInTime, holdTime, fadeOutTime, maxAlpha, colorHex, onPeak }
--   黑幕不可用时同步执行 onPeak（退化为无过渡直切），返回 false。
-- ================================================================
function M.start(opts)
    opts = opts or {}
    if not M.ctrl then M.init() end
    if not M.ctrl then
        if opts.onPeak then pcall(opts.onPeak) end
        return false
    end
    M.fadeInTime  = opts.fadeInTime  or config.DEFAULT_FADE_IN_TIME  or 0.2
    M.holdTime    = opts.holdTime    or config.DEFAULT_FADE_HOLD_TIME or 0.4
    M.fadeOutTime = opts.fadeOutTime or config.DEFAULT_FADE_OUT_TIME or 0.2
    M.maxAlpha    = opts.maxAlpha    or config.DEFAULT_FADE_MAX_ALPHA or 255
    M.colorHex    = opts.colorHex    or "000000"
    M.onPeak      = opts.onPeak
    M.alpha = 0
    M.timer = 0
    M.phase = "fadeIn"
    M.active = true
    M.ctrl:SetActive(true)
    applyAlpha()
    return true
end

-- ================================================================
-- ★ 每帧推进（在 OnUpdate 末尾调用；黑幕容器层级最靠后，天然最顶）
-- ================================================================
function M.update(dt)
    if not M.active or not M.ctrl then return end
    if not dt or dt <= 0 then return end

    if M.phase == "fadeIn" then
        M.timer = M.timer + dt
        local t = M.timer / M.fadeInTime
        if t > 1 then t = 1 end
        M.alpha = t * M.maxAlpha
        applyAlpha()
        if t >= 1 then
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
            M.ctrl:SetActive(false)
        end
    end
end

-- ================================================================
-- ★ 立即完成过渡（重开本关等需要瞬间切换的场景）
-- ================================================================
function M.finish()
    M.active = false
    M.phase = "idle"
    M.alpha = 0
    M.onPeak = nil
    if M.ctrl then
        applyAlpha()
        M.ctrl:SetActive(false)
    end
end

return M
