-- ================================================================
-- 伐木远征 · 玩法内核（移动状态机）
--   逐条移植自 MExp 网页复刻的 engine.js，而 engine.js 本身是原版
--   TI-83/84 计算器 Axe 源码（MVEN/MVER/MVET/MVEF + MEEUTL + MERSTI）的翻译。
--   ★ 本模块是**纯逻辑**：不碰任何千星控件 API，只吃 mexp_maps.lua 的数据。
--     所以它既能在千星里跑，也能被离线对照测试直接调用。
--
--   实体类型（type）：0 玩家 1 立木 2 立树 3 横木 4 竖木 5 横筏 6 竖筏 7 雪人 8 木牌
--   碰撞类型（gect 出来的）：0 玩家 1 立木 2 立树 3 滚木 4 竖木 5 木筏 6 不可动
--   动作编码：0 停 1 走 2 推 3 推着走 4 推着爬 5 走两步 6 拒绝 7 交互
--
--   ★ 位运算说明：Lua 5.3 有位运算符，但为兼容性统一用算术判断
--     （omap 低 4 位：1 梯子 / 2 水 / 4 树桩 / 8 石头）。见 hasBit。
-- ================================================================

local M = {}

M.R_OK, M.R_BLOCKED, M.R_PUSH, M.R_QUEUED, M.R_REFUSED = 0, 1, 2, 3, 4

-- ================================================================
-- ★ 静态表（原版 doc/MESTAT.txt，0 起始，与 JS 侧下标完全一致）
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

-- 交互表：行 = 行动者的碰撞类型；16 个格子，
-- 列 0-6 = 目标是陆地；列 8-14 = 目标是水面。
-- 取值含义见文件头部的「动作编码」。
local EITA = { -- 目标顶面 高于 我们的可及高度
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
local EITB = { -- 目标顶面 不高于 我们的可及高度
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
-- ★ 属性位判断（omap 的低 4 位）
--   bit 必须传 1 / 2 / 4 / 8 这种 2 的幂。
-- ================================================================
local function hasBit(v, bit)
    return (v % (bit * 2)) >= bit
end
M.hasBit = hasBit

-- 棋盘坐标 → 1 起始数组下标
local function ci(w, x, y)
    return y * w.W + x + 1
end

-- ================================================================
-- ★ 排序：z 从高到低；z 相同则保持「加入顺序」（与 JS 的稳定排序一致）
--   ★ 这条务必别改成裸的 z 比较：木筏叠木筏时会出现同 z 的两个实体，
--     而 mver 用「A 是不是列表最后一个」来判断整栈是否都搬走了。
-- ================================================================
local function sortDescZ(list)
    table.sort(list, function(a, b)
        if a.z ~= b.z then return a.z > b.z end
        return a._i < b._i
    end)
end

-- ================================================================
-- ★ World：一张地图的全部运行状态
-- ================================================================
local World = {}
World.__index = World
M.World = World

function M.newWorld(mapData)
    local w = setmetatable({}, World)
    w.W = mapData.width
    w.H = mapData.height
    w.imap = mapData.imap
    w.hmap = mapData.hmap
    w.omap = mapData.omap
    w.islands = mapData.islands
    w.strings = mapData.strings
    w.queue = {}      -- 本回合要执行的连锁动作
    w.IT = 0          -- 交互类型（0 = 没有）
    w.IP = 0          -- 交互参数（木牌 = 字符串编号）
    w.lastT = M.R_OK
    w.entities = {}
    w.emap = {}
    w:loadSpawn()
    return w
end

-- ---- 网格查询（MEWORL）----
function World:inBounds(x, y)
    return x >= 0 and y >= 0 and x < self.W and y < self.H
end

function World:props(x, y)
    if not self:inBounds(x, y) then return 0 end
    return self.omap[ci(self, x, y)]
end

function World:ghat(x, y)
    if not self:inBounds(x, y) then return 0 end
    return self.hmap[ci(self, x, y)]
end

-- 地块表面 z
function World:ground(x, y)
    return self:ghat(x, y) + 1
end

function World:islandAt(x, y)
    if not self:inBounds(x, y) then return 0 end
    return self.imap[ci(self, x, y)]
end

function World:emapAt(x, y)
    if not self:inBounds(x, y) then return 0 end
    return self.emap[ci(self, x, y)] or 0
end

-- ================================================================
-- ★ 出生：所有岛按数据恢复实体，玩家放到「初始岛」的重生点
-- ================================================================
function World:loadSpawn()
    self.entities = {}
    self.emap = {}
    for i = 1, #self.islands do
        local d = i
        for _, oe in ipairs(self.islands[i].entities) do
            self:addEnt(oe, d)
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
end

-- ---- 实体查询（MEEUTL / MECEUT）----
function World:byId(isl, num)
    for _, e in ipairs(self.entities) do
        if e.isl == isl and e.num == num then return e end
    end
    return nil
end

-- 某格上的全部实体，按 z 从高到低
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

-- 实体 → 碰撞类型
function World:gect(type, dx, dy)
    if type < 3 then return type end
    if type == 5 or type == 6 then return 5 end
    if type > 6 then return 6 end
    if dx ~= 0 then return type == 3 and 4 or 3 end
    if dy ~= 0 then return type end
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
    local list = self:entitiesAt(sx, sy)   -- z 从高到低
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
--   返回值：R_OK / R_BLOCKED / R_PUSH / R_QUEUED / R_REFUSED
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
    local Sz = 0        -- 要落到的 z
    local Sz11 = 0      -- 目标实体的 z
    local rockBlock = false

    if hasBit(targP, 8) then
        -- 不可通行的石头：原版是 Goto MVENA，**连玩家降级判断都跳过**
        F = 0
        rockBlock = true
    else
        Sz = self:ground(D, E)
        local Grel = Sz - A.z
        if MEAH[C] >= Grel or (hasBit(targP, 1) and CCLL[C] == 1 and dy < 0) then
            local list = self:entitiesAt(D, E)   -- z 从高到低
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
        T = self:mven(B, dx, dy, layers + 1)   -- 真的去推
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
                    self:mver(A, D, E, Sz)   -- 爬不上去就改踩到顶上
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
            self.IP = B.ebIsl        -- 字符串编号（1 起始）
            T = M.R_REFUSED
        end
    end

    -- ---- 走完之后的自带行为 ----
    if T == M.R_OK then
        if C == 1 or C == 2 then
            self:chet(A, (dx ~= 0) and 3 or 4)        -- 立木倒下
        elseif C == 4 then
            if self:imow(A.x, A.y, A.z, dx, dy) == 0 then self:chet(A, 1) end   -- 竖木立起
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
            self:chet(A, 1)                            -- 立树不管推不推得动都掉叶子
        elseif C == 5 and layers > 2 then
            -- 停住的筏子把最下面那个能动的乘客往前甩出去
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
--   beginMove 执行第一下；stepFrame 推进一帧。筏子因此是一格一格漂的。
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

-- 带交互的移动：返回 IT / IP / T
function World:mvei(A, dx, dy, layers, onFrame)
    self.IT = 0
    self.IP = 0
    self:mvef(A, dx, dy, layers, onFrame)
    return { IT = self.IT, IP = self.IP, T = self.lastT }
end

-- ================================================================
-- ★ RMER：把某个实体还原成出生状态（木筏退化 / 吸收的木头重新拆出来）
-- ================================================================
function World:rmer(isl, num)
    local e = self:byId(isl, num)
    if e then
        if (e.type == 5 or e.type == 6) and e.ebIsl and e.ebIsl ~= 0 then
            -- 这个筏子吞过另一根木头：降级，编号换成被吞的那根
            e.isl = e.ebIsl
            e.num = e.ebNum
            e.type = e.type - 2
            e.ebIsl = 0
            e.ebNum = 0
        else
            self:removeEnt(e)
        end
    else
        -- 这个编号被吞在某个筏子里：把筏子拆开，筏子保留自己的编号
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

-- ================================================================
-- ★ RSTI：整座岛回到出生状态，玩家回重生点
-- ================================================================
function World:resetIsland(d)
    if not d or d == 0 then return false end
    local orig = self.islands[d]
    if not orig then return false end
    -- ★ 必须先拷一份实体列表再逐个删：removeEnt 会改动 entities（与 JS 的 [...entities] 同理）
    --   而且 removeEnt 顺手把该格的 emap 改写成「剩下最上面那个的归属或 0」——
    --   批量过滤（不调 removeEnt）会留下脏归属，实测就是这里出现过 emap 差一格。
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
    return true
end

-- ================================================================
-- ★ 快照 / 回滚（撤销栈用）
--   实体按顺序压成扁平数字表，emap 压成字符串 —— 比逐个深拷贝省很多内存。
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

-- 快照的规范化签名：两份快照相等 ⇔ 签名相等（撤销栈据此判断「局面真的变了」）
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

return M
