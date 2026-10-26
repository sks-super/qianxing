-- ================================================================
-- 浮岛借木 · 玩法内核（MExp 机制版）
-- ================================================================
-- ★ 本文件是一台**移动状态机**，逐条移植自《怪兽远征》网页复刻的 engine.js，
--   而 engine.js 本身是原版 TI-83/84 计算器 Axe 源码（MVEN/MVER/MVET/MVEF
--   + MEEUTL + MERSTI）的翻译。所以这里的每条规则都能对得上原版。
--
-- ★ 和老版（0.25 格跨步 + 单层高度）相比，**机制层面变了五件事**：
--   ① 世界有了 z 轴：一格上可以叠好几件东西，人也站在"顶面"上。
--      z 的单位是「半格」（见 config.DEFAULT_Z_VIS），地面顶面 = 1。
--   ② 木头会**滚**：沿垂直自己轴线的方向推，它会一直滚到撞墙 / 进水才停，
--      不是只滑一格。
--   ③ 两根木头叠在同一格 → 自动合成**木筏**（type 5/6）；人站在木筏上
--      朝东西方向推，木筏朝**反方向**漂（撑筏）。
--   ④ **水不能走**。要过水只能踩在漂在水上的木头 / 木筏上，
--      而且必须先从别处爬到 z=2 才够得着（见 ⑥）。
--   ⑤ 石头改成地图上的「不可通行」属性位，不可移动也不可攀爬。
--
-- ★ 实体类型（type，与原版一一对应）：
--      0 小人   1 立木（无叶树干）  2 立树（有叶子）
--      3 横木（东西躺）  4 竖木（南北躺）  5 横筏  6 竖筏
--   高度表 ENTH：立木 / 立树 / 人都 2，躺着的木头 / 木筏都 1。
--   ★ 所以「人比躺着的木头高一级」—— 想踩上去必须先在 z=2 上。
--
-- ★ 碰撞类型（gect 出来的）：0 人 1 立木 2 立树 3 滚木 4 竖木 5 木筏 6 不可动
--   动作编码：0 停 1 走 2 推 3 推着走 4 推着爬 5 走两步 6 拒绝 7 交互
--
-- ★ 一条最实用的经验（写关卡时靠它）：
--   目标实体的顶面 **高于** max(我的 z, 那格地面) → 走「推」表（EITA）；
--   否则走「爬」表（EITB）。所以从地面永远爬不上躺着的木头（顶上差一级），
--   只能推它；但推不动的时候（F=4 且目标在顶上）会**改成踩到它上面** ——
--   这就是「把木头顶到墙边，然后就爬上去了」的来历。
-- ================================================================

---@diagnostic disable: undefined-global

local M = {}

local state = require("state")
local config = require("config")

-- ★ 可选依赖：12 张**真实地图**（MExp 原版的 .8xv 世界文件解析而来）。
--   有它就以它为关卡库；万一没导进工程，自动退回 config.LEVELS 的三关教程，
--   任何路径都不会「一进去就是空白」。
local okMaps, mapsMod = pcall(require, "mexp_maps")
if not okMaps or type(mapsMod) ~= "table" or type(mapsMod.MAPS) ~= "table" then
    mapsMod = nil
end
M.maps = mapsMod

-- 地图 key → 中文名（HUD 显示）
M.MAP_NAMES = {
    islands = "沙洲群岛", ["log-maze"] = "滚木迷宫", ["raft-ejection"] = "甩筏滩",
    foothills = "山麓", ["the-rescue"] = "营救", ["obscured-mirror"] = "镜中迷雾",
    lake = "静湖", ["icy-lake"] = "冰湖", ["caustic-bluff"] = "蚀崖",
    cliffs = "峭壁", ["big-scalar"] = "大尺度", ["whimsy-raft"] = "奇想木筏",
}

M.R_OK, M.R_BLOCKED, M.R_PUSH, M.R_QUEUED, M.R_REFUSED = 0, 1, 2, 3, 4

-- ================================================================
-- ★ 木牌（sign）—— MExp 的「通关」不是走到某一格，而是**读到那块牌子**
--   · 牌子的正文在 strings[i] 里，一页固定 16 字符宽（原版计算器屏幕宽度），
--     所以要先把定宽文本流拆行、再去重空格，才读得成句子。
--   · 原版里 "You win!" / "Congratulations..." 就是**本图的终点牌**，
--     番外图（Digression）还会附一枚密码碎片。
-- ================================================================
-- 定宽文本流 → 自然段落（复刻 伐木远征 的同名函数）
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
        if k > 1 then
            local prev = lines[k - 1]
            if #prev == 16 and not prev:match("%s$") and lines[k]:match("%S") then
                out[#out + 1] = " "
            end
        end
        out[#out + 1] = lines[k]
    end
    local txt = table.concat(out)
    txt = txt:gsub("%s%s%s+", "\n")
    txt = txt:gsub("%s%s+", " ")
    txt = txt:gsub("{ALPHA}", "Z"):gsub("{2ND}", "R"):gsub("{CLEAR}", "F")
    txt = txt:gsub("{ENTER}", "空格"):gsub("{%+}", "+"):gsub("{%-}", "-")
    txt = txt:gsub("^%s+", ""):gsub("%s+$", "")
    return txt
end

local function rawOf(pages)
    if type(pages) ~= "table" then return "" end
    return table.concat(pages, " ")
end

-- 这块牌子是不是「终点牌」
local function isGoalString(pages)
    local raw = rawOf(pages)
    return raw:find("You win!", 1, true) ~= nil
        or raw:find("Congratulations", 1, true) ~= nil
end
M.isGoalString = isGoalString

-- ================================================================
-- ★ 牌子的字串索引
--   ⚠️ 坑：8 张番外图的数据里，「You win! Fragment N」那张字串**没有挂在任何
--      一块牌子上**（原版 .8xv 解析时把那两块牌子丢了，网页复刻也一样）。
--      于是这些图在数据层面「没有终点牌」，永远打不通。
--      处理办法（不改编数据、也不改实体字段）：
--        没有终点牌的地图 → 把那张没被引用的「你赢了」字串，
--        挂到**离出生点最远的那块牌子**上（玩家一路推过去，最后读到的就是它）。
--   ★ 用一张独立的覆盖表（state.signIdx）而不是改 e.ebIsl：
--      改了字段会让「与已验收内核逐帧差分」在 ebIsl 上出现假差异。
-- ================================================================
local function signKey(e)
    return tostring(e.isl) .. ":" .. tostring(e.num)
end

local function signIdxOf(e)
    local i = (state.signIdx or {})[signKey(e)]
    if i then return i end
    return e.ebIsl or 1
end

-- 扫一遍地图，必要时生成覆盖表
local function buildSignIdx(md)
    local over = {}
    local used = {}
    local hasGoal = false
    local spawn = nil
    for i = 1, #md.islands do
        local isl = md.islands[i]
        if isl.initial then spawn = isl.respawn end
        for _, oe in ipairs(isl.entities or {}) do
            if oe.type == 8 then
                used[oe.eb1 or 1] = true
                if isGoalString((md.strings or {})[oe.eb1 or 1]) then hasGoal = true end
            end
        end
    end
    if hasGoal then return over end

    -- 找一张没被任何牌子引用、内容又是「你赢了」的字串
    local free = nil
    for idx = 1, #(md.strings or {}) do
        if not used[idx] and isGoalString(md.strings[idx]) then
            free = idx
            break
        end
    end
    if not free then return over end

    -- 挑离出生点最远的那块牌子
    local sx, sy = (spawn and spawn[1]) or 0, (spawn and spawn[2]) or 0
    local best, bestD, bestIsl = nil, -1, nil
    for i = 1, #md.islands do
        for _, oe in ipairs(md.islands[i].entities or {}) do
            if oe.type == 8 then
                local d = math.abs(oe.x - sx) + math.abs(oe.y - sy)
                if d > bestD then best, bestD, bestIsl = oe, d, i end
            end
        end
    end
    if best then
        over[bestIsl .. ":" .. best.num] = free
    end
    return over
end

-- 番外图的密码碎片："Fragment 3:     LZQ3"
local function fragmentOf(pages)
    local raw = rawOf(pages)
    local tag, code = raw:match("Fragment%s*(%d+)%s*:%s*(%u%u%u%u)")
    if tag then return tonumber(tag), code end
    return nil
end

-- 地图序号 → key / 中文名（越界返回 nil）
function M.mapCount()
    local order = M.maps and M.maps.ORDER
    if type(order) == "table" and #order > 0 then return #order end
    return 0
end

function M.mapKeyAt(i)
    local order = M.maps and M.maps.ORDER
    local idx = math.floor(tonumber(i) or 0)
    if type(order) == "table" and idx >= 1 and idx <= #order then return order[idx] end
    return nil
end

function M.mapIndex(key)
    local order = M.maps and M.maps.ORDER
    if type(order) ~= "table" then return nil end
    for i = 1, #order do
        if order[i] == key then return i end
    end
    return nil
end

function M.mapName(key)
    return M.MAP_NAMES[key] or tostring(key or "?")
end

-- ================================================================
-- ★ 静态表（原版 doc/MESTAT.txt，0 起始）
-- ================================================================
-- 各实体类型的高度
local ENTH = { [0] = 2, [1] = 2, [2] = 2, [3] = 1, [4] = 1, [5] = 1, [6] = 1, [7] = 2, [8] = 2 }
-- 各碰撞类型最多能爬多高
local MEAH = { [0] = 1, [1] = 1, [2] = 1, [3] = 0, [4] = 1, [5] = 0, [6] = 0 }
-- 各碰撞类型能不能爬梯子
local CCLL = { [0] = 1, [1] = 0, [2] = 0, [3] = 0, [4] = 0, [5] = 0, [6] = 0 }
-- 各碰撞类型能不能离开木筏
local CMOR = { [0] = 0, [1] = 1, [2] = 1, [3] = 1, [4] = 0, [5] = 0, [6] = 0 }
-- 踩在滚木上「站不稳」时的动作降级
local PIRD = { [0] = 6, [1] = 6, [2] = 2, [3] = 2, [4] = 6, [5] = 6, [6] = 6, [7] = 6 }

local EITA = {
    [0] = { [0] = 0, [1] = 3, [2] = 3, [3] = 3, [4] = 3, [5] = 4, [6] = 7, [7] = 0,
            [8] = 0, [9] = 2, [10] = 2, [11] = 2, [12] = 2, [13] = 2, [14] = 0, [15] = 0 },
    [1] = { [0] = 0, [1] = 3, [2] = 0, [3] = 3, [4] = 0, [5] = 1, [6] = 0, [7] = 0,
            [8] = 0, [9] = 3, [10] = 0, [11] = 3, [12] = 0, [13] = 0, [14] = 0, [15] = 0 },
    [2] = { [0] = 0, [1] = 3, [2] = 0, [3] = 3, [4] = 0, [5] = 1, [6] = 0, [7] = 0,
            [8] = 0, [9] = 3, [10] = 0, [11] = 3, [12] = 0, [13] = 0, [14] = 0, [15] = 0 },
    [3] = { [0] = 0, [1] = 2, [2] = 0, [3] = 2, [4] = 0, [5] = 0, [6] = 0, [7] = 0,
            [8] = 0, [9] = 2, [10] = 0, [11] = 2, [12] = 0, [13] = 0, [14] = 0, [15] = 0 },
    [4] = { [0] = 0, [1] = 3, [2] = 0, [3] = 3, [4] = 0, [5] = 1, [6] = 0, [7] = 0,
            [8] = 0, [9] = 3, [10] = 0, [11] = 3, [12] = 0, [13] = 0, [14] = 0, [15] = 0 },
    [5] = { [0] = 0, [1] = 3, [2] = 0, [3] = 3, [4] = 0, [5] = 0, [6] = 0, [7] = 0,
            [8] = 0, [9] = 3, [10] = 0, [11] = 3, [12] = 0, [13] = 0, [14] = 0, [15] = 0 },
    [6] = { [0] = 0, [1] = 0, [2] = 0, [3] = 0, [4] = 0, [5] = 0, [6] = 0, [7] = 0,
            [8] = 0, [9] = 0, [10] = 0, [11] = 0, [12] = 0, [13] = 0, [14] = 0, [15] = 0 },
}
local EITB = {
    [0] = { [0] = 0, [1] = 3, [2] = 3, [3] = 3, [4] = 1, [5] = 1, [6] = 7, [7] = 0,
            [8] = 0, [9] = 6, [10] = 6, [11] = 6, [12] = 1, [13] = 1, [14] = 0, [15] = 0 },
    [1] = { [0] = 0, [1] = 1, [2] = 0, [3] = 5, [4] = 1, [5] = 1, [6] = 0, [7] = 0,
            [8] = 0, [9] = 1, [10] = 0, [11] = 1, [12] = 1, [13] = 1, [14] = 0, [15] = 0 },
    [2] = { [0] = 0, [1] = 1, [2] = 0, [3] = 5, [4] = 1, [5] = 1, [6] = 0, [7] = 0,
            [8] = 0, [9] = 1, [10] = 0, [11] = 1, [12] = 1, [13] = 1, [14] = 0, [15] = 0 },
    [3] = { [0] = 0, [1] = 3, [2] = 0, [3] = 3, [4] = 1, [5] = 1, [6] = 0, [7] = 0,
            [8] = 0, [9] = 1, [10] = 0, [11] = 1, [12] = 1, [13] = 1, [14] = 0, [15] = 0 },
    [4] = { [0] = 0, [1] = 1, [2] = 0, [3] = 3, [4] = 1, [5] = 1, [6] = 0, [7] = 0,
            [8] = 0, [9] = 1, [10] = 0, [11] = 1, [12] = 1, [13] = 1, [14] = 0, [15] = 0 },
    [5] = { [0] = 0, [1] = 1, [2] = 0, [3] = 1, [4] = 1, [5] = 1, [6] = 0, [7] = 0,
            [8] = 0, [9] = 1, [10] = 0, [11] = 1, [12] = 1, [13] = 1, [14] = 0, [15] = 0 },
    [6] = { [0] = 0, [1] = 0, [2] = 0, [3] = 0, [4] = 0, [5] = 0, [6] = 0, [7] = 0,
            [8] = 0, [9] = 0, [10] = 0, [11] = 0, [12] = 0, [13] = 0, [14] = 0, [15] = 0 },
}

-- ================================================================
-- ★ 方向表：W 上 / S 下 / A 左 / D 右
--   关卡坐标 (c, r) 与内核坐标 (x, y) 只差 1：x = c-1, y = r-1。
--   两者都是「行号从上往下递增」，所以方向向量完全一致。
-- ================================================================
M.DIRS = {
    W = { 0, -1 },
    S = { 0,  1 },
    A = { -1, 0 },
    D = { 1,  0 },
}

-- 方向 → 轴向：0 = 南北（竖着躺）/ 1 = 东西（横着躺）
M.AXIS = { W = 0, S = 0, A = 1, D = 1 }

-- 实体类型 → 躺向（渲染层用）
local TYPE_DIR = { [3] = "D", [4] = "W", [5] = "D", [6] = "W" }

-- ================================================================
-- ★ 属性位判断（omap 低 4 位：1 梯子 / 2 水 / 4 树桩 / 8 不可通行）
-- ================================================================
local function hasBit(v, bit)
    return (v % (bit * 2)) >= bit
end
M.hasBit = hasBit

local function ci(w, x, y)
    return y * w.W + x + 1
end

-- z 从高到低；z 相同则保持加入顺序（mver 靠「是不是最后一个」判断整栈是否搬空）
local function sortDescZ(list)
    table.sort(list, function(a, b)
        if a.z ~= b.z then return a.z > b.z end
        return a._i < b._i
    end)
end

-- 半格可视刻度：z 差 1 = 屏幕上差半格
local function zVis()
    return tonumber(config.DEFAULT_Z_VIS) or 0.5
end
M.zVis = zVis

-- ================================================================
-- ★ World：一张地图的全部运行状态
-- ================================================================
local World = {}
World.__index = World
M.World = World

local function newWorld(mapData)
    local w = setmetatable({}, World)
    w.W = mapData.width
    w.H = mapData.height
    w.imap = mapData.imap
    w.hmap = mapData.hmap
    w.omap = mapData.omap
    w.islands = mapData.islands
    w.strings = mapData.strings or {}
    w.queue = {}
    w.IT = 0
    w.IP = 0
    w.lastT = M.R_OK
    w.entities = {}
    w.emap = {}
    w:loadSpawn()
    return w
end

function World:inBounds(x, y)
    return x >= 0 and y >= 0 and x < self.W and y < self.H
end

function World:props(x, y)
    if not self:inBounds(x, y) then return 0 end
    return self.omap[ci(self, x, y)] or 0
end

function World:ghat(x, y)
    if not self:inBounds(x, y) then return 0 end
    return self.hmap[ci(self, x, y)] or 0
end

-- 地块表面 z（本作地图是平的，恒为 1）
function World:ground(x, y)
    return self:ghat(x, y) + 1
end

function World:islandAt(x, y)
    if not self:inBounds(x, y) then return 0 end
    return self.imap[ci(self, x, y)] or 0
end

function World:emapAt(x, y)
    if not self:inBounds(x, y) then return 0 end
    return self.emap[ci(self, x, y)] or 0
end

function World:loadSpawn()
    self.entities = {}
    self.emap = {}
    for i = 1, #self.islands do
        for _, oe in ipairs(self.islands[i].entities) do
            self:addEnt(oe, i)
        end
    end
    local init = 1
    for i = 1, #self.islands do
        if self.islands[i].initial then init = i break end
    end
    local r = self.islands[init].respawn
    local p = {
        isl = 0, num = 0, type = 0,
        x = r[1], y = r[2], z = r[3],
        ebIsl = 0, ebNum = 0, owner = init,
    }
    self.entities[#self.entities + 1] = p
    self.emap[ci(self, p.x, p.y)] = init
    self.player = p
    self.queue = {}
end

function World:byId(isl, num)
    for _, e in ipairs(self.entities) do
        if e.isl == isl and e.num == num then return e end
    end
    return nil
end

function World:entitiesAt(x, y)
    local list = {}
    for i, e in ipairs(self.entities) do
        if e.x == x and e.y == y then
            e._i = i
            list[#list + 1] = e
        end
    end
    if #list > 1 then sortDescZ(list) end
    return list
end

-- 严格低于 z 的最高实体
function World:gheb(x, y, z)
    local best = nil
    for _, e in ipairs(self.entities) do
        if e.x == x and e.y == y and e.z < z and (not best or e.z > best.z) then best = e end
    end
    return best
end

-- 严格高于 z 的最低实体
function World:glea(x, y, z)
    local best = nil
    for _, e in ipairs(self.entities) do
        if e.x == x and e.y == y and e.z > z and (not best or e.z < best.z) then best = e end
    end
    return best
end

-- 高于 z 的最低「能离开木筏」的实体
function World:glma(x, y, z, dx, dy)
    local best = nil
    for _, e in ipairs(self.entities) do
        if e.x == x and e.y == y and e.z > z then
            if CMOR[self:gect(e.type, dx, dy)] == 1 and (not best or e.z < best.z) then best = e end
        end
    end
    return best
end

-- ⚠️ 参数名不能叫 type：那会把全局函数 type() 遮住，
--    而本文件上面（地图工具函数）还要用 type(...) 判类型。
function World:gect(tp, dx, dy)
    if tp < 3 then return tp end
    if tp == 5 or tp == 6 then return 5 end
    if tp > 6 then return 6 end
    if dx ~= 0 then return tp == 3 and 4 or 3 end
    if dy ~= 0 then return tp end
    return 6
end

-- 0 不在水上 / 1 在水上移动 / 2 踩在滚木上
function World:imow(x, y, z, dx, dy)
    if not hasBit(self:props(x, y), 2) then return 0 end
    local G = self:gheb(x, y, z)
    if G then
        if self:gect(G.type, dx, dy) ~= 3 then return 0 end
        return 2
    end
    return 1
end

function World:removeEnt(e)
    for i = 1, #self.entities do
        if self.entities[i] == e then
            table.remove(self.entities, i)
            break
        end
    end
    local rest = self:entitiesAt(e.x, e.y)
    self.emap[ci(self, e.x, e.y)] = (#rest > 0) and rest[1].owner or 0
end

function World:addEnt(oe, d)
    local e = {
        isl = oe.isl or d,
        num = oe.num, type = oe.type,
        x = oe.x, y = oe.y, z = oe.z,
        ebIsl = oe.eb1 or oe.ebIsl or 0,
        ebNum = oe.eb2 or oe.ebNum or 0,
        owner = d,
    }
    self.entities[#self.entities + 1] = e
    self.emap[ci(self, e.x, e.y)] = d
    return e
end

-- 改类型，并把骑在它上面的东西一起抬高 / 降低
function World:chet(A, newType)
    local oldH = ENTH[A.type]
    A.type = newType
    local dh = ENTH[newType] - oldH
    if dh ~= 0 then
        local G = self:glea(A.x, A.y, A.z)
        if G then self:mver(G, G.x, G.y, G.z + dh) end
    end
end

-- 合成木筏：下面那根 G 吞掉上面那根 A
function World:mkrf(G, A)
    G.type = (G.type == 4) and 6 or 5
    G.ebIsl = A.isl
    G.ebNum = A.num
    local above = self:glea(A.x, A.y, A.z)
    self:removeEnt(A)
    if above then
        local dz = G.z + ENTH[G.type] - above.z
        if dz ~= 0 then self:mver(above, above.x, above.y, above.z + dz) end
    end
end

function World:queueHas(e)
    for _, m in ipairs(self.queue) do
        if m.isl == e.isl and m.num == e.num then return true end
    end
    return false
end

function World:queuePush(e, dx, dy, layers)
    self.queue[#self.queue + 1] = { isl = e.isl, num = e.num, dx = dx, dy = dy, layers = layers }
end

-- ================================================================
-- ★ MVER：原样搬动（骑在它上面的一整摞也跟着动）
-- ================================================================
function World:mver(A, tx, ty, tz)
    local dz = tz - A.z
    local sx, sy = A.x, A.y
    local E = self:emapAt(sx, sy)
    local F = self:islandAt(tx, ty)
    if F == 0 then F = self:emapAt(tx, ty) end
    if F == 0 then F = E end
    local list = self:entitiesAt(sx, sy)
    local movedAll = false
    for i = 1, #list do
        local d = list[i]
        d.x, d.y = tx, ty
        d.z = d.z + dz
        if E ~= F then d.owner = F end
        if d == A then
            movedAll = (i == #list)
            break
        end
    end
    if movedAll then self.emap[ci(self, sx, sy)] = 0 end
    self.emap[ci(self, tx, ty)] = F
end

-- ================================================================
-- ★ MVEN：移动状态机（一次动作）
--   layers = 传递层数：人直接推是 0，隔着东西推是 1、2…
-- ================================================================
function World:mven(A, dx, dy, layers)
    local T = M.R_OK
    local B = nil
    local D, E = A.x + dx, A.y + dy

    if not self:inBounds(D, E) then
        self.lastT = M.R_REFUSED
        return M.R_REFUSED
    end

    local currP = self:props(A.x, A.y)
    local targP = self:props(D, E)
    local preIMOW = self:imow(A.x, A.y, A.z, dx, dy)

    -- 站在水上、层数 1：把动作交给脚下的木筏
    if layers == 1 and hasBit(currP, 2) then
        local G = self:glea(A.x, A.y, 0)
        if G and G ~= A and self:gect(G.type, dx, dy) == 5 then
            T = self:mven(G, dx, dy, layers + 1)
            if T == M.R_OK then
                self.lastT = T
                return T
            end
        end
    end

    local C = self:gect(A.type, dx, dy)
    local F = 0
    local isBottom, isTop = false, false
    local Sz = 0
    local Sz11 = 0
    local rockBlock = false

    if hasBit(targP, 8) then
        -- 不可通行的石头：原版是 Goto MVENA，**连玩家降级判断都跳过**
        F = 0
        rockBlock = true
    else
        Sz = self:ground(D, E)
        local Grel = Sz - A.z
        if MEAH[C] >= Grel or (hasBit(targP, 1) and CCLL[C] == 1 and dy < 0) then
            local list = self:entitiesAt(D, E)
            if #list > 0 then
                local I = math.max(A.z, Sz)
                local Jax = 0
                for j = 1, #list do
                    B = list[j]
                    Jax = j
                    if B.z <= I then break end
                end
                isTop = (Jax == 1)
                isBottom = (Jax == #list)
                local G2 = self:gect(B.type, dx, dy)
                local Hb = self:gheb(B.x, B.y, B.z)
                local Jw = (hasBit(targP, 2) and not Hb) and 1 or 0
                Sz11 = B.z
                local SzAbove = ENTH[B.type] + B.z
                if SzAbove > I then
                    F = EITA[C][Jw * 8 + G2]
                else
                    F = EITB[C][Jw * 8 + G2]
                end
                local Gup = SzAbove - A.z
                if MEAH[C] < Gup then
                    if F == 1 then F = 0 elseif F == 4 then F = 3 end
                end
                Sz = SzAbove
            else
                F = 1
            end
        else
            F = 0
        end
    end

    -- 玩家专属降级（撞石头那条路已经跳过了）
    if not rockBlock and A.type == 0 then
        if hasBit(targP, 2) and not B then
            F = 6                       -- 不能走进水里
        elseif preIMOW == 2 then
            F = PIRD[F]                 -- 踩在滚木上站不稳
        end
    end

    -- ---- 动作段 ----
    if F == 2 or F == 3 or F == 4 then
        T = self:mven(B, dx, dy, layers + 1)
    end

    -- 撑筏：站在水上、想推东西 → 其实是在把筏子蹬向反方向
    local skipMove = false
    if layers == 0 and hasBit(currP, 2) and F ~= 1 and F < 5 then
        local G = self:glea(A.x, A.y, 0)
        if G and self:gect(G.type, dx, dy) == 5 then
            local savedT = T
            local Tra = self:mven(G, -dx, -dy, layers + 2)
            if Tra == M.R_OK then
                T = M.R_REFUSED
                skipMove = true
            else
                T = savedT
            end
        end
    end

    if not skipMove then
        if F == 0 then
            T = M.R_BLOCKED
        elseif F == 1 then
            if (not B) or isTop then
                self:mver(A, D, E, Sz)
                T = M.R_OK
            else
                T = M.R_BLOCKED
            end
        elseif F == 2 then
            T = M.R_PUSH
        elseif F == 3 or F == 4 then
            if T == M.R_OK then
                if isBottom then
                    self:mver(A, D, E, Sz11)
                    T = M.R_OK
                else
                    self:queuePush(A, dx, dy, layers)
                    T = M.R_QUEUED
                end
            else
                if T == M.R_BLOCKED and F == 4 and isTop then
                    self:mver(A, D, E, Sz)   -- 推不动就改踩到它顶上
                    T = M.R_OK
                end
            end
        elseif F == 5 then
            self:mver(A, D, E, Sz)
            self:queuePush(A, dx, dy, layers + 1)   -- 走两步
            T = M.R_OK
        elseif F == 6 then
            T = M.R_REFUSED
        elseif F == 7 then
            self.IT = B.type
            self.IP = signIdxOf(B)
            T = M.R_REFUSED
        end
    end

    -- ---- 走完之后的自带行为 ----
    if T == M.R_OK then
        if C == 1 or C == 2 then
            self:chet(A, (dx ~= 0) and 3 or 4)        -- 立木 / 立树倒下
        elseif C == 4 then
            if self:imow(A.x, A.y, A.z, dx, dy) == 0 then self:chet(A, 1) end   -- 竖木在旱地上立起来
        elseif C == 3 then
            if self:imow(A.x, A.y, A.z, dx, dy) == 0 then
                self:queuePush(A, dx, dy, layers + 1)  -- 继续滚
            end
        elseif C == 5 then
            if self:imow(A.x, A.y, A.z, dx, dy) == 1 and preIMOW == 1 then
                self:queuePush(A, dx, dy, layers + 1)  -- 筏子继续漂
            end
        end
        T = M.R_OK
    else
        if C == 2 then
            self:chet(A, 1)                            -- 立树推不动也照样掉叶子
        elseif C == 5 and layers > 2 then
            local G = self:glma(A.x, A.y, A.z, dx, dy)
            if G then
                local keepT = T
                self:mven(G, dx, dy, layers + 1)
                T = keepT
            end
        end
    end

    -- ---- 木筏合成 ----
    if A.type == 1 or A.type == 3 or A.type == 4 then
        local G = self:gheb(A.x, A.y, A.z)
        if G and (G.type == 3 or G.type == 4) then
            if self:queueHas(A) or self:queueHas(G) then
                self.lastT = T
                return T
            end
            if A.type == 1 then
                -- 立木只有在下面积木正漂在水上时才会合成
                if self:imow(G.x, G.y, G.z, dx, dy) ~= 1 then
                    self.lastT = T
                    return T
                end
            end
            self:mkrf(G, A)
        end
    end

    self.lastT = T
    return T
end

-- ================================================================
-- ★ MVET / MVEF：把连锁队列一帧一帧跑完
-- ================================================================
function World:beginMove(A, dx, dy, layers)
    self.queue = {}
    self:mven(A, dx, dy, layers or 0)
end

function World:stepFrame()
    if #self.queue == 0 then return false end
    local frame = self.queue
    self.queue = {}
    for _, m in ipairs(frame) do
        local e = self:byId(m.isl, m.num)
        if e then self:mven(e, m.dx, m.dy, m.layers) end
    end
    return #self.queue > 0
end

function World:busy()
    return #self.queue > 0
end

function World:mvef(A, dx, dy, layers, onFrame)
    self:beginMove(A, dx, dy, layers)
    if onFrame then onFrame() end
    local guard = 0
    while #self.queue > 0 and guard < 1000 do
        guard = guard + 1
        self:stepFrame()
        if onFrame then onFrame() end
    end
end

-- 带交互的移动
function World:mvei(A, dx, dy, layers, onFrame)
    self.IT = 0
    self.IP = 0
    self:mvef(A, dx, dy, layers, onFrame)
    return { IT = self.IT, IP = self.IP, T = self.lastT }
end

-- ================================================================
-- ★ RMER / RSTI：还原与整岛复位
-- ================================================================
function World:rmer(isl, num)
    local e = self:byId(isl, num)
    if e then
        if (e.type == 5 or e.type == 6) and e.ebIsl and e.ebIsl ~= 0 then
            e.isl = e.ebIsl
            e.num = e.ebNum
            e.type = e.type - 2
            e.ebIsl = 0
            e.ebNum = 0
        else
            self:removeEnt(e)
        end
    else
        for _, r in ipairs(self.entities) do
            if (r.type == 5 or r.type == 6) and r.ebIsl == isl and r.ebNum == num then
                r.type = r.type - 2
                r.ebIsl = 0
                r.ebNum = 0
                break
            end
        end
    end
end

function World:resetIsland(d)
    if not d or d == 0 then return false end
    local orig = self.islands[d]
    if not orig then return false end
    -- ★ 必须先拷一份实体列表再逐个删：removeEnt 会改动 entities，
    --   而且它顺手把该格的 emap 改成「剩下最上面那个的归属或 0」——
    --   批量过滤（不调 removeEnt）会留下脏归属。
    local snapshotList = {}
    for i = 1, #self.entities do snapshotList[i] = self.entities[i] end
    for _, e in ipairs(snapshotList) do
        if e.type ~= 0 and self:islandAt(e.x, e.y) == d then self:removeEnt(e) end
    end
    for c = 1, #orig.entities do self:rmer(d, c) end
    for _, oe in ipairs(orig.entities) do self:addEnt(oe, d) end
    local p = self.player
    local rest = {}
    for _, e in ipairs(self:entitiesAt(p.x, p.y)) do
        if e ~= p then rest[#rest + 1] = e end
    end
    if #rest == 0 then self.emap[ci(self, p.x, p.y)] = 0 end
    local r = orig.respawn
    p.x, p.y, p.z = r[1], r[2], r[3]
    self.emap[ci(self, p.x, p.y)] = d
    self.queue = {}
    return true
end

-- ================================================================
-- ★ 快照 / 回滚（撤销栈用）
-- ================================================================
function World:snapshot()
    local flat = {}
    local n = 0
    for _, e in ipairs(self.entities) do
        n = n + 1
        local b = (n - 1) * 9
        flat[b + 1] = e.isl
        flat[b + 2] = e.num
        flat[b + 3] = e.type
        flat[b + 4] = e.x
        flat[b + 5] = e.y
        flat[b + 6] = e.z
        flat[b + 7] = e.ebIsl
        flat[b + 8] = e.ebNum
        flat[b + 9] = e.owner
    end
    local chars = {}
    for i = 1, self.W * self.H do
        chars[i] = string.char((self.emap[i] or 0) + 48)
    end
    return { flat = flat, n = n, emap = table.concat(chars) }
end

function World:sig(snap)
    return table.concat(snap.flat, ",") .. "|" .. snap.emap
end

function World:restore(snap)
    self.entities = {}
    for i = 0, snap.n - 1 do
        local b = i * 9
        self.entities[i + 1] = {
            isl = snap.flat[b + 1], num = snap.flat[b + 2], type = snap.flat[b + 3],
            x = snap.flat[b + 4], y = snap.flat[b + 5], z = snap.flat[b + 6],
            ebIsl = snap.flat[b + 7], ebNum = snap.flat[b + 8], owner = snap.flat[b + 9],
        }
    end
    self.emap = {}
    for i = 1, #snap.emap do
        self.emap[i] = snap.emap:byte(i) - 48
    end
    self.player = self:byId(0, 0)
    self.queue = {}
end

-- ================================================================
-- ★ 关卡数据 → 内核地图
--   data.map 的字符含义（**高度直接写在地图上**）：
--       '.'  水（可以漂木头 / 木筏，人不能走）
--       '#'  陆地，和以前一样在第 0 层
--       '1'~'9'  陆地，抬到第 N 层（1 层 = 半格高）
--   ★ 为什么要高度：内核的「爬」只能往上够 1 层，而水面上漂的木头
--     顶面比地面高 1 层 —— 站在平地上永远踩不到它。
--     所以过水必须先走上一级台阶（'1'），那才是 MExp 的原味。
--   石头写成 omap 的「不可通行」位，所以它既挡人又挡木头。
-- ================================================================
local function cellHeight(ch)
    if ch == "#" then return 0 end
    local n = tonumber(ch)
    if n and n >= 0 and n <= 9 then return math.floor(n) end
    return nil                    -- 水
end

local function buildMapData(data)
    local art = data.map or {}
    local H = #art
    local W = 0
    for r = 1, H do
        local len = #art[r]
        if len > W then W = len end
    end
    if W <= 0 or H <= 0 then return nil end

    local imap, hmap, omap = {}, {}, {}
    local land = {}
    for y = 0, H - 1 do
        local line = art[y + 1] or ""
        local row = {}
        for x = 0, W - 1 do
            local ch = line:sub(x + 1, x + 1)
            local h = cellHeight(ch)
            row[x + 1] = h             -- nil = 水
            local idx = y * W + x + 1
            if h then
                imap[idx] = 1
                omap[idx] = 0
                hmap[idx] = h
            else
                imap[idx] = 0
                omap[idx] = 2          -- 水
                hmap[idx] = 0
            end
        end
        land[y + 1] = row
    end

    -- 石头 → 不可通行位
    for _, rk in ipairs(data.rocks or {}) do
        local x, y = (rk.c or 0) - 1, (rk.r or 0) - 1
        if x >= 0 and y >= 0 and x < W and y < H then
            local idx = y * W + x + 1
            omap[idx] = omap[idx] + 8
            imap[idx] = 1          -- 石头上算陆地（不影响通行，只影响归属）
        end
    end

    -- 实体：立树 / 立木 / 躺着的木头 / 木筏
    local ents = {}
    local num = 0
    local function push(tp, c, r, z)
        num = num + 1
        ents[#ents + 1] = { isl = 1, num = num, type = tp,
                            x = c - 1, y = r - 1, z = z, eb1 = 0, eb2 = 0 }
    end
    local function groundZ(c, r)
        local x, y = c - 1, r - 1
        if x < 0 or y < 0 or x >= W or y >= H then return 1 end
        return 1 + (hmap[y * W + x + 1] or 0)
    end

    for _, tr in ipairs(data.trees or {}) do
        -- bare = true → 无叶树干（type 1）；否则是有叶子的立树（type 2）
        push(tr.bare and 1 or 2, tr.c, tr.r, groundZ(tr.c, tr.r))
    end
    for _, lg in ipairs(data.logs or {}) do
        local alongX = (M.AXIS[lg.dir] == 1)
        push(alongX and 3 or 4, lg.c, lg.r, groundZ(lg.c, lg.r))
    end
    for _, rf in ipairs(data.rafts or {}) do
        local alongX = (M.AXIS[rf.dir] == 1)
        push(alongX and 5 or 6, rf.c, rf.r, groundZ(rf.c, rf.r))
    end

    local sp = data.spawn or { c = 1, r = 1 }
    return {
        width = W, height = H,
        imap = imap, hmap = hmap, omap = omap,
        islands = {
            {
                initial = true,
                respawn = { (sp.c or 1) - 1, (sp.r or 1) - 1, groundZ(sp.c or 1, sp.r or 1) },
                entities = ents,
            },
        },
        strings = {},
        land = land,
    }
end

-- ================================================================
-- ★ 当前世界（模块内唯一实例）
-- ================================================================
local w = nil
M.undoStack = {}

-- ================================================================
-- ★ 把内核里的实体同步成「渲染层看得懂的四张表」
--   state.trees / state.logs / state.rafts / state.signs（石头是静态的，不动）
--   ★ 每项都带 z：渲染层据此把它画在第几层上（z 差 1 = 半格高）。
-- ================================================================
function M.syncView()
    if not w then return end
    state.trees = {}
    state.logs = {}
    state.rafts = {}
    state.signs = {}
    for _, e in ipairs(w.entities) do
        if e.type == 1 or e.type == 2 then
            state.trees[#state.trees + 1] = {
                c = e.x + 1, r = e.y + 1, z = e.z,
                bare = (e.type == 1) or nil,
            }
        elseif e.type == 3 or e.type == 4 then
            state.logs[#state.logs + 1] = {
                c = e.x + 1, r = e.y + 1, z = e.z, dir = TYPE_DIR[e.type] or "D",
            }
        elseif e.type == 5 or e.type == 6 then
            state.rafts[#state.rafts + 1] = {
                c = e.x + 1, r = e.y + 1, z = e.z, dir = TYPE_DIR[e.type] or "D",
            }
        elseif e.type == 8 then
            local pages = w.strings and w.strings[signIdxOf(e)]
            state.signs[#state.signs + 1] = {
                c = e.x + 1, r = e.y + 1, z = e.z,
                goal = isGoalString(pages) or nil,
            }
        end
    end
    local p = w.player
    if p then
        state.player.c = p.x + 1
        state.player.r = p.y + 1
        -- h 仍然是「高出最低地块的脚线几格」，按 z 层刻度换算（渲染层直接乘格宽）
        state.player.h = (p.z - 1 - (state.baseH or 0)) * zVis()
        state.player.z = p.z
    end
end

-- ================================================================
-- ★ 真正开一局：地图数据 + 地块高度表 + 石头表 → 内核世界
--   ★ 真实地图（mexp_maps）与编辑器自制关（config.LEVELS）都走这一条，
--     差别只在「地块高度表怎么来」。
-- ================================================================
-- 从 imap/hmap/omap 三张表里还原「渲染层要的地块高度」
--   land[r][c] = 抬高层数（0 = 与水面基准齐平）；nil = 水
local function landTableFromMap(md)
    local land = {}
    for y = 0, md.height - 1 do
        local row = {}
        for x = 0, md.width - 1 do
            local idx = y * md.width + x + 1
            if not hasBit(md.omap[idx] or 0, 2) then
                row[x + 1] = md.hmap[idx] or 0
            end
        end
        land[y + 1] = row
    end
    return land
end

-- ================================================================
-- ★ 外海（第 24 批）：和地图四边**连通**的水格才算「海」
--
--   为什么要这个：岛的内部也有水缝（原版地图里岛中间会有一格水洼 / 一道
--   缝隙）。旧代码的岛缘描边只判「邻格是不是水」—— 于是这些内部水缝四周的
--   陆地各画一条沙滩描边，把水缝的**内轮廓**勾了出来，看着就像岛内部凭空
--   多出一条条边框（用户第 24 批报的「内轮廓」）。
--
--   现在改成：只有临**外海**的那一侧才画描边 —— 描出来的是岛的**外轮廓**。
--   判定用一次洪水填充（从地图四边所有水格出发、四邻扩散），地图最大的
--   一张是 52×38 = 1976 格，一次性算完存表，运行期只查表。
-- ================================================================
local function outerWaterFromMap(md)
    local W, H = md.width, md.height
    local isWater = function(x, y)
        return hasBit(md.omap[y * W + x + 1] or 0, 2)
    end
    local out = {}
    local stack = {}
    local function push(x, y)
        if x < 0 or y < 0 or x >= W or y >= H then return end
        if not isWater(x, y) then return end
        local row = out[y]
        if not row then row = {}; out[y] = row end
        if row[x] then return end
        row[x] = true
        stack[#stack + 1] = (y * W + x)
    end
    for x = 0, W - 1 do push(x, 0); push(x, H - 1) end
    for y = 0, H - 1 do push(0, y); push(W - 1, y) end
    local i = 1
    while i <= #stack do
        local v = stack[i]; i = i + 1
        local x, y = v % W, math.floor(v / W)
        push(x - 1, y); push(x + 1, y); push(x, y - 1); push(x, y + 1)
    end
    -- 转成 1 起始的二维表，和 state.land 同一套下标
    local res = {}
    for y = 0, H - 1 do
        local src, row = out[y], {}
        if src then for x = 0, W - 1 do if src[x] then row[x + 1] = true end end end
        res[y + 1] = row
    end
    return res
end

-- omap 的「不可通行」位 → 渲染层的石头表（石头是**静态地形属性**，不进内核）
local function rocksFromMap(md)
    local rocks = {}
    local h = tonumber(config.DEFAULT_H_ROCK1) or 1
    for y = 0, md.height - 1 do
        for x = 0, md.width - 1 do
            if hasBit(md.omap[y * md.width + x + 1] or 0, 8) then
                rocks[#rocks + 1] = { c = x + 1, r = y + 1, h = h }
            end
        end
    end
    return rocks
end

-- omap 的「树桩」位 → 渲染层的树桩表
--   ★ 原版语义：**树桩位是地块属性，不是实体**。hmap 里那一格的高度**已经含了桩子
--     那一层**（render.js: `ghat(x,y) - (stump?1:0)`），树站着时桩子被树干挡住不画；
--     树被推倒以后本体挪走，桩子就露出来了 —— 所以砍完树原地一定有一截树桩。
--   ★ 我们这边同理：树的位置不记在树桩表里，树桩表只在**载入时**从 omap 取一次，
--     运行时不变；「这一格还有没有立着的树」由渲染层查 state.trees 判断。
local function stumpsFromMap(md)
    local out, at = {}, {}
    for y = 0, md.height - 1 do
        for x = 0, md.width - 1 do
            local v = md.omap[y * md.width + x + 1] or 0
            if hasBit(v, 4) and not hasBit(v, 2) then      -- 有桩位、且不是水
                out[#out + 1] = { c = x + 1, r = y + 1 }
                at[(x + 1) .. ":" .. (y + 1)] = true
            end
        end
    end
    return out, at
end

local function beginSession(md, landTable, rocks, name, mapKey)
    state.land = landTable or {}
    -- ★ 外海判定表（第 24 批）：岛缘描边只认外海，见 outerWaterFromMap
    state.outerWater = outerWaterFromMap(md)
    state.islandBoxCache = {}
    state.mapRows = md.height
    state.mapCols = md.width
    state.roots = {}          -- ★ 老版「预置树根」通道，新规则下恒为空
    -- ★ 树桩（地块属性，见 stumpsFromMap 的说明）：列表给渲染层逐块画，
    --   哈希表给「这一格地表要不要减一层」这种逐格查询用（地形每格都问一次）。
    state.stumps, state.stumpAt = stumpsFromMap(md)

    -- ★ 渲染基准层（脚线）：取**陆地最低那一层**，不是整张图的最低层。
    --
    --   第 31 批改的：以前取整张图最低层（= 水面 0），于是最矮的岛（hmap=1）
    --   也被抬高 (1-0)×0.15 = 0.15 格 ≈ 10px —— 岛顶面整体浮在格子线上面，
    --   和用户连报三轮的「岛屿边缘要和黑线对齐、边框不能超过黑线」直接冲突。
    --   改成以陆地最低层为基准后，最矮那一层岛的地块矩形正好压在格子线上；
    --   更高的台地照旧按 0.15 格/层往上抬（2.5D 的层次感不受影响）。
    --   水面网格线本来就画在平铺位置（不参与 z 抬升），所以两边从此对齐。
    local lo = nil
    for i = 1, md.width * md.height do
        local h = md.hmap[i] or 0
        if not lo or h < lo then lo = h end
    end
    local loLand = nil
    if landTable then
        for r = 1, md.height do
            local row = landTable[r]
            if row then
                for c = 1, md.width do
                    local h = row[c]
                    if h ~= nil and (not loLand or h < loLand) then loLand = h end
                end
            end
        end
    end
    state.baseH = loLand or lo or 0

    -- 石头是**静态**的（不进内核，写在地图的「不可通行」属性位里），
    -- 但渲染层还在按 state.rocks 逐块画它，所以这里单独拷一份。
    state.rocks = rocks or {}

    w = newWorld(md)
    M.world = w
    M.undoStack = {}
    state.undoCount = 0
    state.mapKey = mapKey
    state.mapName = name or ""

    -- 牌子字串覆盖表（见 buildSignIdx 的说明），必须在 syncView 之前设好
    state.signIdx = buildSignIdx(md)

    -- 终点牌集合："isl:num"
    state.goalSigns = {}
    for i = 1, #md.islands do
        for _, oe in ipairs(md.islands[i].entities or {}) do
            if oe.type == 8 then
                local idx = state.signIdx[(oe.isl or i) .. ":" .. oe.num] or oe.eb1 or 1
                if isGoalString((md.strings or {})[idx]) then
                    state.goalSigns[(oe.isl or i) .. ":" .. oe.num] = true
                end
            end
        end
    end

    state.player = state.player or { c = 1, r = 1, h = 0, z = 1 }
    M.syncView()

    local cell = state.cellSize or config.DEFAULT_CELL_SIZE
    state.boardW = state.mapCols * cell
    state.boardH = state.mapRows * cell

    state.steps = 0
    state.won = false
    state.winHandled = false
    state.wonSign = false
    state.signOpen = false
    state.signPages = nil
    state.goal = nil            -- 真实地图没有「终点格」，终点是那块牌子
    state.lastAction = ""
    return true
end

-- ================================================================
-- ★ 载入一张**真实地图**（key 见 M.MAP_NAMES / M.maps.ORDER）
-- ================================================================
function M.loadMap(key)
    local data = M.maps and M.maps.MAPS and M.maps.MAPS[key]
    if not data then return false end
    local name = M.mapName(key)
    local ok = beginSession(data, landTableFromMap(data), rocksFromMap(data), name, key)
    if ok then
        state.levelConfig = {
            name = name,
            mapKey = key,
            palette = (config.MAP_THEMES or {})[key] or nil,
        }
    end
    return ok
end

-- ================================================================
-- ★ 载入编辑器关卡（config.LEVELS 的字符画地图；保留给老存档 / 自制关）
-- ================================================================
function M.load(data)
    if type(data) ~= "table" then return false end
    local md = buildMapData(data)
    if not md then return false end
    local ok = beginSession(md, md.land, rocksFromMap(md), data.name, data.mapKey)
    if not ok then return false end

    state.goal = {
        c = (data.goal and data.goal.c) or 1,
        r = (data.goal and data.goal.r) or 1,
    }
    state.levelConfig = data
    return true
end

-- ================================================================
-- ★ 胜利判定：读到「终点牌」即通过（MExp 原味）
--   state.wonSign 由 M.step 在读牌时置位，撤销 / 重开 / 换图都会复位。
-- ================================================================
function M.isWin()
    return state.wonSign == true
end

-- ================================================================
-- ★ 基础查询（渲染层 / 关卡编辑器用）
-- ================================================================
function M.inBounds(c, r)
    return c >= 1 and c <= (state.mapCols or 0)
       and r >= 1 and r <= (state.mapRows or 0)
end

function M.landAt(c, r)
    if not M.inBounds(c, r) then return false end
    local row = state.land[r]
    return (row ~= nil) and (row[c] ~= nil)
end

-- 这一格是不是「外海」（和地图四边连通的水）—— 岛缘描边只画在临外海的一侧
--   ★ 岛内部的封闭水缝不算：否则会勾出水缝的**内轮廓**（第 24 批修的就是这个）
function M.isOuterWater(c, r)
    if not M.inBounds(c, r) then return false end
    local row = state.outerWater and state.outerWater[r]
    return (row ~= nil) and (row[c] == true)
end

-- 玩家所在的岛号（0 = 站在水上 / 木筏上）
function M.playerIsland()
    if not w then return 0 end
    local p = w.player
    if not p then return 0 end
    return w:islandAt(p.x, p.y) or 0
end

-- 某座岛的格子包围盒（返回 c0, r0, c1, r1；查不到返回 nil）
--   ★ 岛屿归属看 imap 的值（resetIsland 用的也是同一套编号）。
--     结果按岛号缓存 —— 地图载入后地形不再变，算一次就够。
function M.islandBox(d)
    local id = math.floor(tonumber(d) or 0)
    if id < 1 then return nil end
    local cache = state.islandBoxCache
    if not cache then cache = {}; state.islandBoxCache = cache end
    local hit = cache[id]
    if hit ~= nil then
        if hit == false then return nil end
        return hit.c0, hit.r0, hit.c1, hit.r1
    end
    local c0, r0, c1, r1 = nil, nil, nil, nil
    local md = M.maps and M.maps.MAPS and state.mapKey and M.maps.MAPS[state.mapKey]
    local W, H = state.mapCols or 0, state.mapRows or 0
    if md and W > 0 and H > 0 then
        for y = 0, H - 1 do
            for x = 0, W - 1 do
                if (md.imap[y * W + x + 1] or 0) == id then
                    if not c0 or x + 1 < c0 then c0 = x + 1 end
                    if not c1 or x + 1 > c1 then c1 = x + 1 end
                    if not r0 or y + 1 < r0 then r0 = y + 1 end
                    if not r1 or y + 1 > r1 then r1 = y + 1 end
                end
            end
        end
    end
    if not c0 then
        cache[id] = false
        return nil
    end
    cache[id] = { c0 = c0, r0 = r0, c1 = c1, r1 = r1 }
    return c0, r0, c1, r1
end

-- 该格的地面高度（层）；水返回 nil
function M.cellH(c, r)
    if not M.inBounds(c, r) then return nil end
    local row = state.land[r]
    return row and row[c] or nil
end

-- ================================================================
-- ★ 该格属于哪座岛（第 34 批；0 = 不属于任何岛）
--   岛号直接取 imap 的值 —— 和 resetIsland / islandBox 用的是同一套编号。
--   渲染层要靠它求「这座岛有多宽」，才能把岛底岩锥收成锥形。
-- ================================================================
function M.islandAtCell(c, r)
    if not M.inBounds(c, r) then return 0 end
    local md = M.maps and M.maps.MAPS and state.mapKey and M.maps.MAPS[state.mapKey]
    if not md or type(md.imap) ~= "table" then return 0 end
    local W = state.mapCols or 0
    if W <= 0 then return 0 end
    return md.imap[(r - 1) * W + (c - 1) + 1] or 0
end

-- 这一格是不是「树桩位」（地表要画出一截树桩 / 画地表时高度要减一层）
function M.hasStump(c, r)
    local at = state.stumpAt
    if not at then return false end
    return at[c .. ":" .. r] == true
end

-- 某一格的最顶面 z（没东西就是地面）
function M.topZ(c, r)
    if not w or not M.inBounds(c, r) then return 1 end
    local x, y = c - 1, r - 1
    local best = w:ground(x, y)
    for _, e in ipairs(w.entities) do
        if e.x == x and e.y == y then
            local top = e.z + (ENTH[e.type] or 1)
            if top > best then best = top end
        end
    end
    return best
end

-- ★ 躺着的木头在屏幕上要抬高多少（格）—— 渲染层专用，不是规则高度。
--   贴地一根 = 0.5；压在另一根上 = +0.5；漂在水里 = 0.25（半浸）。
function M.logHeightAt(c, r, z)
    local base = M.landAt(c, r) and 0.5 or 0.25
    local dz = ((tonumber(z) or 1) - 1) * zVis()
    return base + dz
end

-- 该格是否还空着（判断「木头能不能落到那里」）
function M.isFree(c, r)
    if not w or not M.inBounds(c, r) then return false end
    if hasBit(w:props(c - 1, r - 1), 8) then return false end
    for _, e in ipairs(w.entities) do
        if e.x == c - 1 and e.y == r - 1 then return false end
    end
    return true
end

-- 该格上的可视物体类型（编辑器预览用）
function M.occupantAt(c, r)
    if not w then return nil end
    for _, e in ipairs(state.trees or {}) do
        if e.c == c and e.r == r then return "tree" end
    end
    for _, e in ipairs(state.logs or {}) do
        if e.c == c and e.r == r then return "log" end
    end
    for _, e in ipairs(state.rafts or {}) do
        if e.c == c and e.r == r then return "raft" end
    end
    for _, e in ipairs(state.rocks or {}) do
        if e.c == c and e.r == r then return "rock" end
    end
    return nil
end

-- ================================================================
-- ★ 走一步（唯一的规则入口）
--   ★ 内核是「连锁队列」：一次动作可能要跑好几帧（滚木 / 筏子漂 / 挤出去）。
--     本作是时间驱动（没有逐帧规则），所以这里**一次跑完**，
--     把「跑了几个连锁帧」放进 act.frames 交给表现层决定动画长短。
--   返回 act:
--     kind   : "move" 走 / "climb" 爬到东西上 / "push" 只推人不动
--              "knock" 立树倒地 / "raise" 躺木立起 / "slide" 木头滑/滚一格
--              "roll" 木头连滚多格 / "raft" 合成木筏 / "sail" 撑筏
--              "blocked" 挡住 / "water" 前面是水 / "rock" 石头 / "invalid"
--     ok / moved / changed / c / r / msg / frames
--     animFrom / animTo : 那一根木头的起止形态（表现层做补间）
-- ================================================================
local function ekey(e)
    return tostring(e.isl) .. ":" .. tostring(e.num)
end

-- 记下所有实体的位置 / 类型，供动作分类用
local function capture()
    local t = {}
    for _, e in ipairs(w.entities) do
        t[ekey(e)] = { x = e.x, y = e.y, z = e.z, type = e.type }
    end
    return t
end

-- 把「躺着的木头」的 dir 从类型推出来（3/5 = 东西躺，4/6 = 南北躺）
local function dirOfType(tp)
    return TYPE_DIR[tp] or "D"
end

function M.step(key)
    local d = M.DIRS[key]
    if not d then
        return { kind = "invalid", ok = false, moved = false, changed = false, msg = "无效方向" }
    end
    if not w then
        return { kind = "invalid", ok = false, moved = false, changed = false, msg = "关卡还没载入" }
    end

    local p = w.player
    local px, py, pz = p.x, p.y, p.z
    local before = capture()

    w.IT, w.IP = 0, 0
    w:beginMove(p, d[1], d[2], 0)
    local frames = 1
    local guard = 0
    while w:busy() and guard < 64 do
        guard = guard + 1
        w:stepFrame()
        frames = frames + 1
    end

    -- 推出界 / 目标格是石头 —— 先记下来，后面给中文提示用
    local tc, tr = (px + d[1]) + 1, (py + d[2]) + 1
    local blockedByRock = hasBit(w:props(px + d[1], py + d[2]), 8)

    M.syncView()

    local moved = (p.x ~= px) or (p.y ~= py) or (p.z ~= pz)
    local climbed = moved and p.z > pz

    -- ---- 分类：找出「这一趟里动了 / 变了形态」的非玩家实体 ----
    local from, to, kindOfEnt = nil, nil, nil
    local raftMade = false
    for _, e in ipairs(w.entities) do
        if e.type ~= 0 then
            local b = before[ekey(e)]
            if b then
                local movedEnt = (b.x ~= e.x) or (b.y ~= e.y) or (b.z ~= e.z)
                local reType = (b.type ~= e.type)
                if reType and (e.type == 5 or e.type == 6) then raftMade = true end
                if movedEnt or reType then
                    if not from then
                        if (b.type == 1 or b.type == 2) and (e.type == 3 or e.type == 4) then
                            kindOfEnt = "knock"
                            from = { c = b.x + 1, r = b.y + 1, z = b.z, stand = true }
                            to   = { c = e.x + 1, r = e.y + 1, z = e.z, dir = dirOfType(e.type) }
                        elseif b.type == 4 and e.type == 1 then
                            kindOfEnt = "raise"
                            from = { c = b.x + 1, r = b.y + 1, z = b.z, dir = "W" }
                            to   = { c = e.x + 1, r = e.y + 1, z = e.z, stand = true }
                        elseif movedEnt then
                            local steps = math.abs(e.x - b.x) + math.abs(e.y - b.y)
                            kindOfEnt = (steps >= 2) and "roll" or "slide"
                            from = { c = b.x + 1, r = b.y + 1, z = b.z, dir = dirOfType(e.type) }
                            to   = { c = e.x + 1, r = e.y + 1, z = e.z, dir = dirOfType(e.type) }
                        end
                    end
                end
            elseif e.type ~= 0 then
                kindOfEnt = kindOfEnt or "slide"   -- 新出现的东西（理论上不会有）
            end
        end
    end

    local changed = (kindOfEnt ~= nil) or raftMade or (frames > 1)

    local act = {
        c = tc, r = tr, ok = true, moved = moved, changed = changed,
        frames = frames, animFrom = from, animTo = to,
    }

    -- ---- 定性 + 中文提示 ----
    if raftMade then
        act.kind = "raft"
        act.msg = "两根木头叠在一起 —— 它们结成了一张木筏"
    elseif kindOfEnt == "knock" then
        act.kind = "knock"
        act.msg = "推倒了立木 · 它整根朝前躺下，占了前面那一格"
    elseif kindOfEnt == "raise" then
        act.kind = "raise"
        act.msg = "南北向的木头被顶到实地上 · 它立了起来"
    elseif kindOfEnt == "roll" then
        act.kind = "roll"
        act.msg = "木头滚了出去 —— 一路滚到撞上东西才停"
    elseif kindOfEnt == "slide" then
        act.kind = "slide"
        act.msg = "木头被推着挪了一格"
    elseif climbed then
        act.kind = "climb"
        act.msg = "踩到了木头上面"
    elseif moved then
        act.kind = "move"
        act.msg = "移动"
    elseif frames > 1 then
        act.kind = "sail"
        act.msg = "撑了一下 —— 木筏朝反方向漂走了"
    else
        act.ok = false
        act.changed = false
        if blockedByRock then
            act.kind = "rock"
            act.msg = "石头挡着，推不动也爬不上去"
        elseif w.lastT == M.R_PUSH then
            act.kind = "push"
            act.ok = true
            act.msg = "推了一下"
        elseif hasBit(w:props(px + d[1], py + d[2]), 2) then
            act.kind = "water"
            act.msg = "前方是水 —— 光靠脚走不过去，得先有木头漂在那儿"
        else
            act.kind = "blocked"
            act.msg = "过不去"
        end
    end

    -- ★ 交互：本作只有木牌（type 8）。读到「终点牌」= 通关。
    if w.IT == 8 then
        act.interact = 8
        act.signPages = M.signPages(w.IP)
        act.signGoal = isGoalString(w.strings and w.strings[w.IP or 1])
        if act.signGoal then
            state.wonSign = true
            local n, code = fragmentOf(w.strings and w.strings[w.IP or 1])
            if n then
                state.fragments = state.fragments or {}
                state.fragments[n] = code
            end
        end
    elseif w.IT ~= 0 then
        act.interact = w.IT
    end

    return act
end

-- ================================================================
-- ★ 木牌正文（优先用 config.SIGN_TEXTS 里的中文，缺了才显示原文）
-- ================================================================
function M.signPages(ip)
    local idx = math.floor(tonumber(ip) or 0)
    if idx < 1 then idx = 1 end
    local cn = (config.SIGN_TEXTS or {})[state.mapKey or ""]
    if type(cn) == "table" and type(cn[idx]) == "table" then
        return cn[idx]
    end
    local pages = {}
    local raw = w and w.strings and w.strings[idx]
    if type(raw) == "table" then
        for i = 1, #raw do pages[i] = unflow(raw[i]) end
    elseif raw then
        pages[1] = unflow(raw)
    end
    if #pages == 0 then pages[1] = "（牌子上的字已经看不清了）" end
    return pages
end

-- ================================================================
-- ★ 撤销：回退一步（快照栈由 game.lua 在每步之前压入）
-- ================================================================
function M.pushUndo()
    if not w then return end
    local snap = w:snapshot()
    local sig = w:sig(snap)
    local n = #M.undoStack
    if n > 0 and M.undoStack[n].sig == sig then return end
    M.undoStack[n + 1] = { snap = snap, sig = sig }
    if #M.undoStack > 200 then table.remove(M.undoStack, 1) end
    state.undoCount = #M.undoStack
end

function M.canUndo()
    return #M.undoStack > 0
end

function M.undo()
    local n = #M.undoStack
    if n == 0 then return false end
    local item = M.undoStack[n]
    M.undoStack[n] = nil
    state.undoCount = n - 1
    w:restore(item.snap)
    M.syncView()
    state.steps = math.max(0, (state.steps or 0) - 1)
    state.won = false
    state.winHandled = false
    state.wonSign = false
    state.signOpen = false
    return true
end

function M.clearUndo()
    M.undoStack = {}
    state.undoCount = 0
end

-- ================================================================
-- ★ 整张图复位：重新从地图数据开一局
--   ★ 第 24 批之后玩家按 R 走的是 M.resetIsland（只重置脚下那座岛）；
--     这个「整图重开」保留给需要彻底重来的场景（调试 / 换图）。
-- ================================================================
function M.resetWorld()
    if not w then return false end
    if state.mapKey and M.loadMap(state.mapKey) then return true end
    local ok = w:resetIsland(1)
    M.syncView()
    return ok
end

-- ================================================================
-- ★ 单岛复位（第 24 批 · R 键）：只把**玩家脚下的那座岛**还原到开局状态
--   语义与 MExp 原版 RSTI 一致（见 World:resetIsland）：
--     该岛实体全部还原、玩家回到该岛的出生点、木筏「推动队列」清空。
--   ★ 其它岛不动、全局步数不动 —— 所以「按 R」不等于「重开本关」。
--   ★ 撤销栈必须清空：栈里的快照记的是复位前的布局，退回去会和现状打架。
-- ================================================================
function M.resetIsland(d)
    if not w then return false end
    local id = math.floor(tonumber(d) or 0)
    if id <= 0 then return false end          -- 提示文案交给 game.lua（本文件不依赖 utils）
    local ok = w:resetIsland(id)
    if not ok then return false end
    M.clearUndo()
    state.wonSign = false
    state.won = false
    state.winHandled = false
    M.syncView()
    return true
end

-- ================================================================
-- ★ 关卡数值一览（README / 调试用）
-- ================================================================
function M.describe()
    local p = state.player
    local nTree, nBare, nLog, nRaft = 0, 0, 0, 0
    for _, e in ipairs(state.trees or {}) do
        if e.bare then nBare = nBare + 1 else nTree = nTree + 1 end
    end
    nLog = #(state.logs or {})
    nRaft = #(state.rafts or {})
    return string.format("小人(%d,%d,z%s) 步数%d 树%d 立木%d 躺木%d 筏%d",
        p.c, p.r, tostring(p.z or 1), state.steps or 0, nTree, nBare, nLog, nRaft)
end

return M
