-- ================================================================
-- 浮岛借木 · 玩法内核（纯逻辑，不碰任何控件）
-- ================================================================
-- 规则（与 _tmp/verify3.py 的定版参考实现逐条一致，三关解法均已验证）：
--
--   单位：1 格。小岛地面 = 0；小人高 2 格；树木高 2.5 格。
--   小人每次只能向上跨 DEFAULT_MAX_STEP（0.5 格），下落不限高度。
--
--   ① 撞树      小人朝树木移动 → 树木朝该方向倒下，横躺两格，原地留 0.5 格树根。
--               倒下位置（第 2、3 格）被占或越界时撞不动。
--   ② 踩木桩    木桩顶面 - 小人脚下高度 ≤ 0.5 时可以走上去。
--               木桩整根压在陆地上 → 顶面 1.0 格（跨不上去，得先踩树根再上）；
--               木桩任意一端在水上 → 浮在水面，顶面 0.0 格（与岛面齐平，直接走）。
--   ③ 立起      站在木桩某一端外侧、朝木桩方向推 → 木桩绕另一端立起（1×1 占地，2 格高）。
--   ④ 倒下      朝立起的木桩推 → 木桩朝该方向横躺到前方两格。
--   ⑤ 石头      不可移动、不可攀爬，挡住去路。
--   ⑥ 胜利      小人所在格 == 终点格。
--
--   ★ 「木桩优先于树根」：撞断树木后木桩立刻占住原格，所以树根本身被压在
--     木桩底下，踩不到 —— 只有把木桩推走（立起）之后，树根才露出来可以踩。
-- ================================================================

---@diagnostic disable: undefined-global

local M = {}
local state = require("state")
local config = require("config")

local EPS = 1e-9

-- 方向表：W 上 / S 下 / A 左 / D 右（行号从上往下递增，所以 W 是 r-1）
M.DIRS = {
    W = { 0, -1 },
    S = { 0,  1 },
    A = { -1, 0 },
    D = { 1,  0 },
}

-- ================================================================
-- ★ 基础查询
-- ================================================================
function M.inBounds(c, r)
    return c >= 1 and c <= (state.mapCols or 0)
       and r >= 1 and r <= (state.mapRows or 0)
end

-- 该格是否是陆地（越界视为水）
function M.landAt(c, r)
    if not M.inBounds(c, r) then return false end
    local row = state.land[r]
    return (row ~= nil) and (row[c] == true)
end

-- 列表查找小工具：在 list 中找 c/r 同时相等的项
local function findCell(list, c, r)
    for i = 1, #list do
        local it = list[i]
        if it.c == c and it.r == r then return i, it end
    end
    return nil, nil
end

function M.treeIndexAt(c, r)  return findCell(state.trees, c, r) end
function M.stumpIndexAt(c, r) return findCell(state.stumps, c, r) end
function M.rootIndexAt(c, r)  return findCell(state.roots, c, r) end

-- 石头：返回高度（1 / 2），没有则 nil
function M.rockAt(c, r)
    local i, it = findCell(state.rocks, c, r)
    if i then return it.h end
    return nil
end

-- 木桩：返回所在下标（木桩占两格，命中任一端都算）
function M.logIndexOf(c, r)
    for i = 1, #state.logs do
        local lg = state.logs[i]
        if (lg.c1 == c and lg.r1 == r) or (lg.c2 == c and lg.r2 == r) then
            return i, lg
        end
    end
    return nil, nil
end

-- 木桩是否整根都在陆地上
function M.logOnLand(log)
    if not log then return false end
    return M.landAt(log.c1, log.r1) and M.landAt(log.c2, log.r2)
end

-- 木桩顶面高度：压陆地 1.0 格 / 浮水 0.0 格
function M.logHeight(log)
    if M.logOnLand(log) then
        return config.DEFAULT_H_LOG_LAND
    end
    return config.DEFAULT_H_LOG_FLOAT
end

-- ================================================================
-- ★ 该格「脚踩上去的顶面高度」
--   返回 nil 表示不可站立（水 / 被占）。
--   ★ 判定顺序必须是：障碍物 → 木桩 → 树根 → 陆地。木桩排在树根前面，
--     这样「撞断树木后木桩压住原格」才会自然成立。
-- ================================================================
function M.heightAt(c, r)
    if not M.inBounds(c, r) then return nil end
    if M.treeIndexAt(c, r) then return nil end
    if M.stumpIndexAt(c, r) then return nil end
    if M.rockAt(c, r) then return nil end
    local _, log = M.logIndexOf(c, r)
    if log then return M.logHeight(log) end
    if M.rootIndexAt(c, r) then return config.DEFAULT_H_ROOT end
    if M.landAt(c, r) then return 0.0 end
    return nil
end

-- ================================================================
-- ★ 该格是否空着（用于判断树 / 木桩能否倒下去）
--   只看「有没有东西占着」，不看是水还是陆地 —— 木桩可以倒进水里。
-- ================================================================
function M.isFree(c, r)
    if not M.inBounds(c, r) then return false end
    if M.treeIndexAt(c, r) then return false end
    if M.stumpIndexAt(c, r) then return false end
    if M.rockAt(c, r) then return false end
    if M.logIndexOf(c, r) then return false end
    return true
end

-- ================================================================
-- ★ 统计：该格上的「可视物体」类型（渲染层用，一个格最多一个）
-- ================================================================
function M.occupantAt(c, r)
    if M.treeIndexAt(c, r) then return "tree" end
    if M.stumpIndexAt(c, r) then return "stump" end
    if M.rockAt(c, r) then return "rock" end
    if M.logIndexOf(c, r) then return "log" end
    if M.rootIndexAt(c, r) then return "root" end
    return nil
end

-- ================================================================
-- ★ 载入关卡数据（深拷贝，绝不改动 config.LEVELS 里的表）
-- ================================================================
function M.load(data)
    if type(data) ~= "table" then return false end

    -- ① 地图字符画 → land[r][c]
    state.land = {}
    local map = data.map or {}
    state.mapRows = #map
    state.mapCols = 0
    for r = 1, #map do
        local line = map[r]
        local len = #line
        if len > state.mapCols then state.mapCols = len end
    end
    for r = 1, #map do
        local line = map[r]
        local row = {}
        for c = 1, state.mapCols do
            row[c] = (line:sub(c, c) == "#")
        end
        state.land[r] = row
    end

    -- ② 物体（逐项复制成新表，避免影响 config 的原始数据）
    local function copyList(src, fields)
        local out = {}
        for _, it in ipairs(src or {}) do
            local t = {}
            for _, f in ipairs(fields) do t[f] = it[f] end
            out[#out + 1] = t
        end
        return out
    end

    state.trees  = copyList(data.trees,  { "c", "r" })
    state.stumps = copyList(data.stumps, { "c", "r" })
    state.roots  = copyList(data.roots,  { "c", "r" })
    state.rocks  = copyList(data.rocks,  { "c", "r", "h" })
    state.logs   = copyList(data.logs,   { "c1", "r1", "c2", "r2" })

    -- ③ 石头高度缺省补齐
    for _, rock in ipairs(state.rocks) do
        rock.h = tonumber(rock.h) or config.DEFAULT_H_ROCK1
    end

    -- ④ 小人与终点
    state.player = {
        c = (data.spawn and data.spawn.c) or 1,
        r = (data.spawn and data.spawn.r) or 1,
        h = 0,
    }
    state.goal = {
        c = (data.goal and data.goal.c) or 1,
        r = (data.goal and data.goal.r) or 1,
    }
    local h0 = M.heightAt(state.player.c, state.player.r)
    state.player.h = h0 or 0

    -- ⑤ 关卡几何
    state.levelConfig = data
    local cell = state.cellSize or config.DEFAULT_CELL_SIZE
    state.boardW = state.mapCols * cell
    state.boardH = state.mapRows * cell

    -- ⑥ 进展复位
    state.steps = 0
    state.won = false
    state.winHandled = false
    state.lastAction = ""
    return true
end

-- ================================================================
-- ★ 胜利判定
-- ================================================================
function M.isWin()
    return state.player.c == state.goal.c and state.player.r == state.goal.r
end

-- ================================================================
-- ★ 走一步（唯一的规则入口）
--   返回 action 表：
--     kind   : "move" | "knock" | "step_on" | "raise" | "fall"
--              | "blocked" | "rock" | "water" | "invalid"
--     ok     : 是否成功
--     moved  : 小人是否换了格（表现层据此播位移动画）
--     changed: 世界是否发生结构变化（表现层据此重建物体层）
--     c, r   : 动作发生的目标格（涟漪特效定位用）
--     msg    : 中文描述（HUD 一次性消息）
-- ================================================================
function M.step(key)
    local d = M.DIRS[key]
    if not d then
        return { kind = "invalid", ok = false, moved = false, msg = "无效方向" }
    end

    local pc, pr = state.player.c, state.player.r
    local hp = M.heightAt(pc, pr)
    if hp == nil then
        return { kind = "invalid", ok = false, moved = false, msg = "当前格不可站立" }
    end

    local qc, qr = pc + d[1], pr + d[2]
    local base = { c = qc, r = qr, moved = false, changed = false }

    -- ① 目标是树木 → 撞断它
    local ti = M.treeIndexAt(qc, qr)
    if ti then
        local fc1, fr1 = qc + d[1], qr + d[2]
        local fc2, fr2 = qc + 2 * d[1], qr + 2 * d[2]
        if not (M.isFree(fc1, fr1) and M.isFree(fc2, fr2)) then
            base.kind = "blocked"
            base.ok = false
            base.msg = "树倒不下去：后面被挡住了"
            return base
        end
        table.remove(state.trees, ti)
        state.logs[#state.logs + 1] = { c1 = qc, r1 = qr, c2 = fc1, r2 = fr1 }
        state.roots[#state.roots + 1] = { c = qc, r = qr }
        base.kind = "knock"
        base.ok = true
        base.changed = true
        base.msg = "撞断树木 → 木桩朝前横躺两格，原地留下树根"
        -- 木桩落下后可能正好压在树根上（顶面 1 格）→ 一般跨不上去，小人不移动
        local h2 = M.heightAt(qc, qr)
        if h2 ~= nil and h2 - hp <= config.DEFAULT_MAX_STEP + EPS then
            state.player.c, state.player.r, state.player.h = qc, qr, h2
            base.moved = true
        end
        return base
    end

    -- ② 目标格上有倒地木桩
    local li, log = M.logIndexOf(qc, qr)
    if li then
        local h = M.logHeight(log)
        if h - hp <= config.DEFAULT_MAX_STEP + EPS then
            state.player.c, state.player.r, state.player.h = qc, qr, h
            base.kind = "step_on"
            base.ok = true
            base.moved = true
            base.msg = "踩上木桩"
            return base
        end
        -- 踩不上去 → 只有站在端面外侧才算「推」，木桩才会立起来
        local ax, ar = log.c2 - log.c1, log.r2 - log.r1
        local sc = nil
        if d[1] == ax and d[2] == ar and pc == log.c1 - d[1] and pr == log.r1 - d[2] then
            sc = { c = log.c2, r = log.r2 }
        elseif d[1] == -ax and d[2] == -ar and pc == log.c2 - d[1] and pr == log.r2 - d[2] then
            sc = { c = log.c1, r = log.r1 }
        end
        if not sc then
            base.kind = "blocked"
            base.ok = false
            base.msg = "木桩横在这儿：踩不上去，也不是从端面推"
            return base
        end
        table.remove(state.logs, li)
        state.stumps[#state.stumps + 1] = sc
        base.kind = "raise"
        base.ok = true
        base.changed = true
        base.msg = "从端面一推 → 木桩立了起来（1 格宽、2 格高）"
        return base
    end

    -- ③ 目标格上是立起的木桩 → 推倒
    local si = M.stumpIndexAt(qc, qr)
    if si then
        local fc1, fr1 = qc + d[1], qr + d[2]
        local fc2, fr2 = qc + 2 * d[1], qr + 2 * d[2]
        if not (M.isFree(fc1, fr1) and M.isFree(fc2, fr2)) then
            base.kind = "blocked"
            base.ok = false
            base.msg = "木桩倒不下去：前面被挡住了"
            return base
        end
        table.remove(state.stumps, si)
        state.logs[#state.logs + 1] = { c1 = fc1, r1 = fr1, c2 = fc2, r2 = fr2 }
        base.kind = "fall"
        base.ok = true
        base.changed = true
        base.msg = "推倒立起的木桩 → 朝前横跨两格"
        return base
    end

    -- ④ 石头
    local rh = M.rockAt(qc, qr)
    if rh then
        base.kind = "rock"
        base.ok = false
        base.msg = "石头挡住了去路（" .. tostring(math.floor(rh)) .. " 格高），换个方向吧"
        return base
    end

    -- ⑤ 普通一格
    local h = M.heightAt(qc, qr)
    if h == nil then
        base.kind = "water"
        base.ok = false
        base.msg = "前方是水 —— 先想办法把路铺过去"
        return base
    end
    if h - hp > config.DEFAULT_MAX_STEP + EPS then
        base.kind = "invalid"
        base.ok = false
        base.msg = "这个台阶比半格高，跨不上去"
        return base
    end
    state.player.c, state.player.r, state.player.h = qc, qr, h
    base.kind = "move"
    base.ok = true
    base.moved = true
    base.msg = "移动"
    return base
end

-- ================================================================
-- ★ 关卡数值一览（README / 调试用）
-- ================================================================
function M.describe()
    local p = state.player
    return string.format("小人(%d,%d,%.1f) 步数%d 树%d 木桩%d 立桩%d 树根%d",
        p.c, p.r, p.h or 0, state.steps or 0,
        #state.trees, #state.logs, #state.stumps, #state.roots)
end

return M
