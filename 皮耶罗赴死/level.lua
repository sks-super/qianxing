-- ================================================================
-- 皮耶罗：赴死 · 关卡构建
--   ★ build(def)  依据 config.LEVELS[n] 重建一层关卡（控件每次重建，换关即销毁）
--   ★ update(dt)  推进陷阱与门
--   ★ collectSolids() / collectKills()  汇总本帧的实心体与致死区
--   ★ 全部坐标都是世界坐标（960×540，y 向下）
-- ================================================================

---@diagnostic disable: undefined-global

local M = {}
local state = require("default_import_file/state")
local config = require("default_import_file/config")
local utils = require("default_import_file/utils")
local trap = require("default_import_file/trap")
local audio = require("default_import_file/audio")
local fx = require("default_import_file/fx")

local solidsBuf = {}
local killsBuf = {}

-- ================================================================
-- 门（生死之间）
--   原版可「逃走」：玩家靠近到一定距离就瞬移到下一个位置，最后一格才真的能进。
-- ================================================================
local function buildDoor(def)
    local w = config.DEFAULT_DOOR_W or 38
    local h = config.DEFAULT_DOOR_H or 64
    local positions = def.door or { { x = 880, y = 416 } }
    local d = {
        w = w, h = h,
        positions = {},
        i = 1,
        fleeDist = def.fleeDist or config.DEFAULT_DOOR_FLEE or 110,
        poofT = 0,
    }
    for i = 1, #positions do
        d.positions[i] = { x = positions[i].x, y = positions[i].y }
    end
    local p0 = d.positions[1]
    d.body = utils.createRectWorld(p0.x, p0.y + 14, w, h - 14, utils.pal("door"), 255, state.containerWorld)
    d.cap = utils.createRectWorld(p0.x + 3, p0.y + 3, w - 6, 14, utils.pal("door"), 255, state.containerWorld)
    d.capTop = utils.createRectWorld(p0.x + 8, p0.y, w - 16, 5, utils.pal("door"), 255, state.containerWorld)
    d.knob = utils.createRectAtWorld(p0.x + w - 9, p0.y + h / 2 + 4, 7, 7,
        utils.pal("bg"), 255, state.containerWorld)
    state.door = d
    return d
end

local function doorPos(d)
    local p = d.positions[d.i]
    if p then return p end
    return d.positions[1]
end

local function doorUpdate(d, dt)
    if not d then return end
    if d.poofT > 0 then d.poofT = math.max(0, d.poofT - dt) end
    local n = #d.positions
    if d.i < n then
        local p = state.player
        if p then
            local cur = doorPos(d)
            local dx = (p.x + p.w / 2) - (cur.x + d.w / 2)
            local dy = (p.y + p.h / 2) - (cur.y + d.h / 2)
            local dist = math.sqrt(dx * dx + dy * dy)
            if dist < d.fleeDist then
                fx.poof(cur.x + d.w / 2, cur.y + d.h / 2)
                d.i = d.i + 1
                d.poofT = 0.25
                local nx = doorPos(d)
                fx.poof(nx.x + d.w / 2, nx.y + d.h / 2)
                audio.playPop()
                if d.i >= n then audio.playDeath() end
            end
        end
    end
end

local function doorSync(d)
    if not d or not d.body then return end
    local p = doorPos(d)
    utils.setPos(d.body, utils.toUIX(p.x + d.w / 2), utils.toUIY(p.y + 14 + (d.h - 14) / 2))
    utils.setPos(d.cap, utils.toUIX(p.x + d.w / 2), utils.toUIY(p.y + 3 + 7))
    utils.setPos(d.capTop, utils.toUIX(p.x + d.w / 2), utils.toUIY(p.y + 2.5))
    utils.setPos(d.knob, utils.toUIX(p.x + d.w - 9), utils.toUIY(p.y + d.h / 2 + 4))
    local s = 1
    if d.poofT > 0 then s = 1 + d.poofT * 1.2 end
    utils.setScale(d.body, s)
    utils.setScale(d.cap, s)
    utils.setScale(d.capTop, s)
    utils.setScale(d.knob, s)
end

function M.doorWin(d)
    if not d then return false end
    local p = state.player
    if not p then return false end
    if d.i < #d.positions then return false end
    local c = doorPos(d)
    return utils.aabb(p.x, p.y, p.w, p.h,
        c.x + 6, c.y + 6, d.w - 12, d.h - 6)
end

-- ================================================================
-- 静态实体可视化（只有画在屏内的才建控件；
--   左右墙在原版里本来就被裁在画布外，但依然参与碰撞）
-- ================================================================
local solidCtrls = {}

local function buildSolids(list)
    for i = 1, #list do
        local s = list[i]
        if s.x + s.w > 0 and s.x < 960 and s.y + s.h > 0 and s.y < 540 then
            local c = utils.createRectWorld(s.x, s.y, s.w, s.h, utils.pal("ink"), 255,
                state.containerWorld)
            if c then solidCtrls[#solidCtrls + 1] = c end
        end
    end
end

local function destroySolids()
    for i = 1, #solidCtrls do utils.destroy(solidCtrls[i]) end
    solidCtrls = {}
end

-- ================================================================
-- ★ 清场
-- ================================================================
function M.clear()
    trap.destroyAll()
    destroySolids()
    if state.door then
        utils.destroy(state.door.body)
        utils.destroy(state.door.cap)
        utils.destroy(state.door.capTop)
        utils.destroy(state.door.knob)
        state.door = nil
    end
    state.solids = {}
    state.flags = {}
    state.traps = {}
end

-- ================================================================
-- ★ 建关
-- ================================================================
function M.build(def)
    M.clear()
    if not def then return false end

    state.levelDef = def
    state.levelName = def.name or ""
    state.flags = {}

    -- 静态实体
    state.solids = def.solids or {}
    buildSolids(state.solids)

    -- 门
    buildDoor(def)

    -- 陷阱
    local specs = def.traps or {}
    state.traps = {}
    for i = 1, #specs do
        local ins = trap.create(specs[i])
        if ins then state.traps[#state.traps + 1] = ins end
    end
    trap.buildAll()
    trap.resetAll()
    trap.syncAll()

    -- ★ 显式定序：门（最下）→ 实体 → 陷阱（最上）
    if state.door then
        utils.raise(state.door.body)
        utils.raise(state.door.cap)
        utils.raise(state.door.capTop)
        utils.raise(state.door.knob)
    end
    for i = 1, #solidCtrls do utils.raise(solidCtrls[i]) end
    trap.raiseAll()

    doorSync(state.door)
    return true
end

-- ================================================================
-- ★ 每帧
-- ================================================================
function M.update(dt)
    state.invertNow = false
    trap.updateAll(dt)
    doorUpdate(state.door, dt)
    trap.syncAll()
    doorSync(state.door)
end

-- 只同步外观、不推进逻辑（过关停顿期间用：陷阱应该定格）
function M.syncOnly()
    trap.syncAll()
    doorSync(state.door)
end

-- ================================================================
-- ★ 汇总实心体 / 致死区（返回复用表，调用方不要长期持有）
-- ================================================================
function M.collectSolids()
    local out = solidsBuf
    for i = #out, 1, -1 do out[i] = nil end
    local base = state.solids or {}
    for i = 1, #base do out[#out + 1] = base[i] end
    trap.collectSolids(out)
    return out
end

function M.collectKills()
    local out = killsBuf
    for i = #out, 1, -1 do out[i] = nil end
    trap.collectKills(out)
    return out
end

return M
