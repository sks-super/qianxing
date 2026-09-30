-- ================================================================
-- 浮岛借木 · 玩法内核（纯逻辑，不碰任何控件）
-- ================================================================
-- 规则（与 _tools/solve_浮岛借木.py 的参考实现逐条一致，三关解法均已验证）：
--
--   单位：1 格。小岛地面 = 0；小人高 1 格；立着的树高 1 格。
--   小人每次只能向上跨 DEFAULT_MAX_STEP（0.25 格），下落不限高度。
--   ★ 一切可视物体都只占**一格**（1×1）—— 没有「木桩」这个概念了，
--     立着与倒下只是同一棵树的两个状态。
--
--   ① 撞树（knock）   小人朝**立着的树**移动 → 树朝该方向倒下，
--                     落在「树原来那一格 + 前进方向」的前一格，原地留下一个树根。
--                     前方那一格被占或越界时撞不动。
--   ② 踩（move）      目标格顶面 - 小人脚下高度 ≤ 0.25 时可以走上去：
--                        · 树根                      0.25 格（能踩）
--                        · 漂在水面上的树干          0.25 格（能踩 → 这就是「桥」）
--                        · 陆地                      0
--                     压在半格高以上的东西（陆地上的树干 / 树 / 石头）都跨不上去。
--   ③ 侧面推（slide） 目标是**倒下的树**、且推动方向与它躺着的方向**垂直** →
--                     整根滑一格，躺着的样子不变。
--   ④ 正面推（raise） 目标是**倒下的树**、且推动方向与它躺着的方向**同轴** →
--                     它在「原格 + 前进方向」那一格**重新立起来**（又变回一棵树）。
--   ⑤ 石头            不可移动、不可攀爬，挡住去路。
--   ⑥ 胜利            小人所在格 == 终点格。
--
--   ★ 为什么倒下的树要有**两个**高度（见 config 的高度模型）：
--     压在陆地上 0.5 格（半格高，跨不上去 → 只能推）；
--     漂在水面上 0.25 格（半浸在水里 → 能踩上去当桥）。
--     只有一个高度的话，「推得动」和「踩得上」不可能同时成立。
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

-- 方向 → 轴向：0 = 南北（竖着躺），1 = 东西（横着躺）
--   两根树干「躺着的方向」同轴 → 正面推（立起来）；垂直 → 侧面推（滑一格）
M.AXIS = { W = 0, S = 0, A = 1, D = 1 }

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

function M.treeIndexAt(c, r) return findCell(state.trees, c, r) end
function M.rootIndexAt(c, r) return findCell(state.roots, c, r) end

-- 石头：返回高度（1 / 2），没有则 nil
function M.rockAt(c, r)
    local i, it = findCell(state.rocks, c, r)
    if i then return it.h end
    return nil
end

-- 倒下的树：返回下标与那一项（占一格，dir = 它躺着的方向）
function M.logIndexAt(c, r)
    return findCell(state.logs, c, r)
end

-- 倒下的树的顶面高度：压陆地 0.5 格 / 漂在水面 0.25 格
function M.logHeightAt(c, r)
    if M.landAt(c, r) then
        return config.DEFAULT_H_LOG_LAND
    end
    return config.DEFAULT_H_LOG_FLOAT
end

-- ================================================================
-- ★ 该格「脚踩上去的顶面高度」
--   返回 nil 表示不可站立（水 / 被占）。
--   ★ 判定顺序：障碍物（树 / 石头）→ 倒下的树 → 树根 → 陆地。
--     倒下的树排在树根前面：树根不挡路，所以树干可以直接压/滑过树根。
-- ================================================================
function M.heightAt(c, r)
    if not M.inBounds(c, r) then return nil end
    if M.treeIndexAt(c, r) then return nil end
    if M.rockAt(c, r) then return nil end
    if M.logIndexAt(c, r) then return M.logHeightAt(c, r) end
    if M.rootIndexAt(c, r) then return config.DEFAULT_H_ROOT end
    if M.landAt(c, r) then return 0.0 end
    return nil
end

-- ================================================================
-- ★ 该格是否空着（用于判断树 / 树干能否倒下去 / 滑过去）
--   只看「有没有东西占着」，不看是水还是陆地 —— 木头可以落到水里。
--   ★ 树根**不**算占位：它只有 0.25 格高，木头可以直接盖在它上面。
-- ================================================================
function M.isFree(c, r)
    if not M.inBounds(c, r) then return false end
    if M.treeIndexAt(c, r) then return false end
    if M.rockAt(c, r) then return false end
    if M.logIndexAt(c, r) then return false end
    return true
end

-- ================================================================
-- ★ 该格上的「可视物体」类型（渲染层用，一个格最多一个）
-- ================================================================
function M.occupantAt(c, r)
    if M.treeIndexAt(c, r) then return "tree" end
    if M.rockAt(c, r) then return "rock" end
    if M.logIndexAt(c, r) then return "log" end
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

    state.trees = copyList(data.trees, { "c", "r" })
    state.roots = copyList(data.roots, { "c", "r" })
    state.rocks = copyList(data.rocks, { "c", "r", "h" })
    state.logs  = copyList(data.logs,  { "c", "r", "dir" })

    -- ③ 石头高度 / 倒树躺向的缺省补齐
    for _, rock in ipairs(state.rocks) do
        rock.h = tonumber(rock.h) or config.DEFAULT_H_ROCK1
    end
    for _, log in ipairs(state.logs) do
        if not M.AXIS[log.dir] then log.dir = "D" end
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
--     kind   : "move"   走上可踩的一格（陆地 / 树根 / 漂在水面的树干）
--              "knock"  撞倒立着的树
--              "slide"  从侧面推倒下的树 → 整根滑一格
--              "raise"  从正面推倒下的树 → 在前一格重新立起来
--              | "blocked" | "rock" | "water" | "high" | "invalid"
--     ok     : 是否成功（成功 = 世界确实变了 / 小人确实动了）
--     moved  : 小人是否换了格（表现层据此播位移动画）
--     changed: 世界是否发生结构变化（表现层据此重建物体层）
--     c, r   : 动作发生的目标格（涟漪特效定位用）
--     msg    : 中文描述（HUD 一次性消息）
--
--   ★ 顺序不是随意的：「先撞树 → 再能踩就踩 → 踩不上再推」。
--     因为「倒下的树」在陆地上是 0.5 格，站得低时踩不上去、于是走到推的分支；
--     而站在树根（0.25）上时它又刚好够得着，就变成踩过去 —— 两条路都合理。
-- ================================================================
function M.step(key)
    local d = M.DIRS[key]
    if not d then
        return { kind = "invalid", ok = false, moved = false, changed = false, msg = "无效方向" }
    end

    local pc, pr = state.player.c, state.player.r
    local hp = M.heightAt(pc, pr)
    if hp == nil then
        return { kind = "invalid", ok = false, moved = false, changed = false, msg = "当前格不可站立" }
    end

    local qc, qr = pc + d[1], pr + d[2]
    local base = { c = qc, r = qr, moved = false, changed = false }

    -- ① 目标是立着的树 → 朝前倒下一格，原地留下树根
    local ti = M.treeIndexAt(qc, qr)
    if ti then
        local fc, fr = qc + d[1], qr + d[2]
        if not M.isFree(fc, fr) then
            base.kind = "blocked"
            base.ok = false
            base.msg = "树倒不下去：前面那一格被挡住了"
            return base
        end
        table.remove(state.trees, ti)
        state.logs[#state.logs + 1] = { c = fc, r = fr, dir = key }
        state.roots[#state.roots + 1] = { c = qc, r = qr }
        base.kind = "knock"
        base.ok = true
        base.changed = true
        base.msg = "撞倒树木 → 树干朝前倒下一格，原地留下树根"
        -- 树倒走后原地只剩 0.25 格树根，一般能顺势往前挪一步
        local h2 = M.heightAt(qc, qr)
        if h2 ~= nil and h2 - hp <= config.DEFAULT_MAX_STEP + EPS then
            state.player.c, state.player.r, state.player.h = qc, qr, h2
            base.moved = true
        end
        return base
    end

    -- ② 能踩就踩：顶面高度差在 0.25 之内 → 走上去
    local h = M.heightAt(qc, qr)
    if h ~= nil and h - hp <= config.DEFAULT_MAX_STEP + EPS then
        state.player.c, state.player.r, state.player.h = qc, qr, h
        base.kind = "move"
        base.ok = true
        base.moved = true
        base.msg = "移动"
        return base
    end

    -- ③ 踩不上去、目标格又正好是倒下的树 → 推它
    local li, log = M.logIndexAt(qc, qr)
    if li then
        local fc, fr = qc + d[1], qr + d[2]
        if not M.isFree(fc, fr) then
            base.kind = "blocked"
            base.ok = false
            base.msg = "树干推不动：前面那一格被挡住了"
            return base
        end
        table.remove(state.logs, li)
        if M.AXIS[log.dir] == M.AXIS[key] then
            -- 正面推（推动方向 ∥ 它躺着的方向）→ 在前一格重新立起来
            state.trees[#state.trees + 1] = { c = fc, r = fr }
            base.kind = "raise"
            base.msg = "顺着树干推 → 它在前面一格重新立了起来"
        else
            -- 侧面推（推动方向 ⊥ 它躺着的方向）→ 整根滑一格，躺向不变
            state.logs[#state.logs + 1] = { c = fc, r = fr, dir = log.dir }
            base.kind = "slide"
            base.msg = "从侧面推 → 树干整根滑了一格"
        end
        base.ok = true
        base.changed = true
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

    -- ⑤ 水 / 台阶太高
    if h == nil then
        base.kind = "water"
        base.ok = false
        base.msg = "前方是水 —— 先想办法把木头推过去搭座桥"
        return base
    end
    base.kind = "high"
    base.ok = false
    base.msg = "这里比脚下高出一大截，跨不上去 —— 撞上去试试能不能推动它"
    return base
end

-- ================================================================
-- ★ 关卡数值一览（README / 调试用）
-- ================================================================
function M.describe()
    local p = state.player
    return string.format("小人(%d,%d,%.2f) 步数%d 树%d 倒树%d 树根%d 石头%d",
        p.c, p.r, p.h or 0, state.steps or 0,
        #state.trees, #state.logs, #state.roots, #state.rocks)
end

return M
