-- ================================================================
-- 皮耶罗：赴死 · 全屏黑幕过渡
--   透明度 0 → maxAlpha 渐显 → hold → 渐隐回 0；
--   在渐显完成、渐隐开始前（onPeak）完成场景切换。
--   节点 OnStart 预创建一次，之后复用不销毁。
-- ================================================================

---@diagnostic disable: undefined-global

local M = {}
local state = require("default_import_file/state")
local config = require("default_import_file/config")

M.ctrl = nil
M.alpha = 0
M.maxAlpha = 255
M.active = false
M.phase = "idle"
M.timer = 0
M.fadeInTime = 0.18
M.holdTime = 0.10
M.fadeOutTime = 0.22
M.onPeak = nil
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

function M.init()
    if M.ctrl then return end
    local pid = state.rectPrefabId or 0
    if pid <= 0 then return end
    local par = state.containerFade or state.parent
    if not par then return end
    local ctrl = game.InstantiateClientUIControl(pid, par)
    if not ctrl then return end
    ctrl:SetAnchorMin(0.5, 0.5)
    ctrl:SetAnchorMax(0.5, 0.5)
    ctrl:SetPivot(0.5, 0.5)
    ctrl:SetSizeDelta(4000, 4000)
    ctrl:SetAnchoredPosition(0, 0)
    pcall(function()
        ctrl.imageColor = Color.FromRGBA(0, 0, 0, 0)
        ctrl.raycastTarget = false
    end)
    ctrl:SetActive(false)
    M.ctrl = ctrl
end

function M.start(opts)
    opts = opts or {}
    if not M.ctrl then M.init() end
    if not M.ctrl then
        if opts.onPeak then pcall(opts.onPeak) end
        return false
    end
    M.fadeInTime = opts.fadeInTime or config.DEFAULT_FADE_IN_TIME or 0.18
    M.holdTime = opts.holdTime or config.DEFAULT_FADE_HOLD_TIME or 0.10
    M.fadeOutTime = opts.fadeOutTime or config.DEFAULT_FADE_OUT_TIME or 0.22
    M.maxAlpha = opts.maxAlpha or config.DEFAULT_FADE_MAX_ALPHA or 255
    M.colorHex = opts.colorHex or "000000"
    M.onPeak = opts.onPeak
    M.alpha = 0
    M.timer = 0
    M.phase = "fadeIn"
    M.active = true
    M.ctrl:SetActive(true)
    applyAlpha()
    return true
end

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
