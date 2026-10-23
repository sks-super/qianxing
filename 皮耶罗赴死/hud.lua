-- ================================================================
-- 皮耶罗：赴死 · HUD（顶部条 / 关卡名 / 死亡数 / 底部提示 / 死亡与过关大字）
-- ================================================================
-- ★★ 为什么顶部要有一条半透明底条：
--    本作有不少关卡顶部就是一块实体（roof），而实体的颜色是 ink（浅色），
--    HUD 的字也是浅色 —— 不加深色底条的话「关卡名」在那些关里会彻底看不见
--    （第 4/13/14/15/17/21/24/26/27/30 关都会踩到）。
-- ★ 文本框一律先置底色透明，否则真机是实心色块。
-- ================================================================

---@diagnostic disable: undefined-global

local M = {}
local state = require("default_import_file/state")
local config = require("default_import_file/config")
local utils = require("default_import_file/utils")

M.bar = nil
M.name = nil
M.deaths = nil
M.msg = nil
M.big = nil
M.bigSub = nil

local BAR_Y = 250
local BAR_H = 40

function M.init()
    if M.name then return end
    local par = state.containerHud
    if not par then return end

    M.bar = utils.createControl(state.rectPrefabId, 0, BAR_Y, 1040, BAR_H,
        utils.hexToColorA(utils.pal("wipe"), 170), par)

    M.name = utils.createText(0, BAR_Y, 640, 30, "",
        utils.hexToColor(utils.pal("text")), config.DEFAULT_HUD_NAME_SIZE, par)
    M.deaths = utils.createText(432, BAR_Y, 160, 26, "",
        utils.hexToColor(utils.pal("accent")), config.DEFAULT_HUD_DEATH_SIZE, par, "right")
    M.msg = utils.createText(0, -248, 820, 26, "",
        utils.hexToColor(utils.pal("accent")), config.DEFAULT_HUD_MSG_SIZE, par)

    M.big = utils.createText(0, 40, 860, 64, "",
        utils.hexToColor(utils.pal("danger")), config.DEFAULT_DEATH_LINE_SIZE, par)
    M.bigSub = utils.createText(0, -8, 860, 36, "",
        utils.hexToColor(utils.pal("textDim")), config.DEFAULT_HUD_MSG_SIZE, par)

    -- ★ 显式定序：模拟器「后创建 = 更靠下」，不提层底条会盖住文字
    utils.raise(M.bar)
    utils.raise(M.name)
    utils.raise(M.deaths)
    utils.raise(M.msg)
    utils.raise(M.big)
    utils.raise(M.bigSub)

    utils.setVisible(M.big, false)
    utils.setVisible(M.bigSub, false)
end

function M.setVisible(v)
    utils.setVisible(M.bar, v)
    utils.setVisible(M.name, v)
    utils.setVisible(M.deaths, v)
    utils.setVisible(M.msg, v)
    if not v then
        utils.setVisible(M.big, false)
        utils.setVisible(M.bigSub, false)
    end
end

function M.setLevel(name, idx)
    utils.setText(M.name, string.format("LEVEL %02d · %s", math.floor(idx or 1), name or ""))
end

function M.setDeaths(n)
    utils.setText(M.deaths, string.format("死亡 %d", math.floor(n or 0)))
end

function M.setMessage(s)
    utils.setText(M.msg, s or "")
end

-- 中央大字（死亡吐槽 / 过关台词）
function M.showBig(text, hex, size)
    if not M.big then return end
    utils.setText(M.big, text or "")
    utils.setTextColor(M.big, hex or utils.pal("danger"), 255)
    if size and size > 0 then utils.setFontSize(M.big, size) end
    utils.setVisible(M.big, true)
end

function M.hideBig()
    utils.setVisible(M.big, false)
end

function M.showSub(text)
    if not M.bigSub then return end
    utils.setText(M.bigSub, text or "")
    utils.setVisible(M.bigSub, true)
end

function M.hideSub()
    utils.setVisible(M.bigSub, false)
end

return M
