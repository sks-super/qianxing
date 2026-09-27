-- ================================================================
-- objectUI.lua  ——  物品 UI 显示模块
-- 职责：以「像素序列帧动画」的形式管理物品（糖果 / 小怪兽）的显示。
--
-- 提供两种播放模式：
--   1) 像素模式 createPixelSequence（默认，无需新 ID）
--      复用creator已配置的可染色图片控件模板（如 fruitPrefabId），
--      按 吞噬.lua 风格的像素帧数据，用图片控件重建每一帧。
--      - block 参数控制降采样倍数：block 越大控件越少、像素越粗；
--        block=1 为 吞噬.lua 原始 100x100 保真，控件最多（约 1500/帧）；
--        block=3 左右为较轻量默认（约数百控件/帧）。
--      - 采用「控件池」：按各帧最大矩形数一次性实例化，逐帧只更新
--        着色/尺寸/位置并显隐，不反复创建销毁。
--
--   2) 资源模式 createImageSequence（推荐高性能，需图片资产 ID）
--      每帧一张图片资产，仅用 1 个图片控件按帧切换 SetImage。
--      需 creator 按 README 3.1 提供每帧图片资产 ID 与来源类别，
--      并在 frameList 中给出 {source=Enum.ImageSource.*, id=资产ID}。
--
-- 所有控件由本模块统一创建与销毁；调用方只需持有返回的实例句柄。
-- 坐标约定：物品中心 (cx,cy)，显示区域 displayW x displayH，
-- 控件父级为挂载脚本的容器节点（script.object）。
-- 本文件依赖运行时 API（game / Color），仅在客户端脚本环境中可用。
-- ================================================================

---@diagnostic disable: undefined-global

local M = {}

-- 活动序列实例注册表（按 id 索引）
local instances = {}
local instanceSeq = 0

-- ---------------------------------------------------------------
-- 私有：把 吞噬.lua 风格的动画（GRID + PALETTE + FRAMES）按 block 降采样
-- 返回：frames = { 帧 -> { rect, ... } }, ng = 降采样后网格边长
-- 每个 rect = {x, y, w, h, {r, g, b, a}}，x,y 为降采样网格左上角，y 向下
-- ---------------------------------------------------------------
local function buildDownsampledFrames(anim, block)
    local g = anim.GRID
    local ng = math.ceil(g / block)
    local outFrames = {}

    for fi = 1, #anim.FRAMES do
        local frame = anim.FRAMES[fi]
        -- cells[gy][gx] = {rSum, gSum, bSum, aSum, n}
        local cells = {}

        for _, r in ipairs(frame) do
            local pal = anim.PALETTE[r[5]]   -- {r, g, b}
            local a = r[6]
            local y0, x0, h, w = r[2], r[1], r[4], r[3]
            for yy = 0, h - 1 do
                local gy = math.floor((y0 + yy) / block)
                local row = cells[gy]
                if not row then row = {}; cells[gy] = row end
                for xx = 0, w - 1 do
                    local gx = math.floor((x0 + xx) / block)
                    local c = row[gx]
                    if not c then c = {0, 0, 0, 0, 0}; row[gx] = c end
                    c[1] = c[1] + pal[1]
                    c[2] = c[2] + pal[2]
                    c[3] = c[3] + pal[3]
                    c[4] = c[4] + a
                    c[5] = c[5] + 1
                end
            end
        end

        local rects = {}
        for gy = 0, ng - 1 do
            local row = cells[gy]
            if row then
                for gx = 0, ng - 1 do
                    local c = row[gx]
                    if c and c[5] > 0 then
                        local n = c[5]
                        rects[#rects + 1] = {
                            gx, gy, 1, 1,
                            {
                                math.floor(c[1] / n),
                                math.floor(c[2] / n),
                                math.floor(c[3] / n),
                                math.floor(c[4] / n),
                            },
                        }
                    end
                end
            end
        end
        outFrames[fi] = rects
    end

    return outFrames, ng
end

-- ---------------------------------------------------------------
-- 私有：显示像素模式的某一帧（更新控件池）
-- ---------------------------------------------------------------
function M._showPixelFrame(inst, fi)
    local rects = inst.frames[fi]
    local ps = inst.pixelSize
    if not rects then return end

    for i = 1, #rects do
        local ctrl = inst.pool[i]
        if not ctrl then break end
        local r = rects[i]
        local col = r[5]
        ctrl.imageColor = Color.FromRGBA(col[1], col[2], col[3], col[4])
        local w = r[3] * ps
        local h = r[4] * ps
        ctrl:SetSizeDelta(w, h)
        local px = inst.offX + (r[1] + r[3] / 2) * ps
        local py = inst.offY - (r[2] + r[4] / 2) * ps
        ctrl:SetAnchoredPosition(px, py)
        ctrl:SetActive(inst.visible)
    end
    -- 本帧未用到的池控件全部隐藏
    for i = #rects + 1, #inst.pool do
        inst.pool[i]:SetActive(false)
    end
end

-- ---------------------------------------------------------------
-- 像素模式：用可染色图片控件重建序列帧
-- parent    : 父控件（容器节点）
-- anim      : 吞噬.lua 风格数据表 {GRID, PALETTE, FRAMES, FRAME_MS}
-- cx, cy    : 物品中心（世界坐标，画布中心为原点）
-- displayW/H: 显示区域宽高
-- opts.prefabId : 可染色图片控件模板 ID（必须，由 creator 提供，如 fruitPrefabId）
-- opts.block     : 降采样倍数（默认 3）
-- ---------------------------------------------------------------
function M.createPixelSequence(parent, anim, cx, cy, displayW, displayH, opts)
    opts = opts or {}
    local prefabId = opts.prefabId
    if not prefabId or prefabId <= 0 then
        printerr("ObjectUI.createPixelSequence: 缺少有效的图片控件模板 prefabId")
        return nil
    end
    local block = opts.block or 3
    if block < 1 then block = 1 end

    local frames, ng = buildDownsampledFrames(anim, block)
    local pixelSize = math.min(displayW, displayH) / ng
    local offX = cx - displayW / 2
    local offY = cy + displayH / 2

    local maxRects = 0
    for _, f in ipairs(frames) do
        if #f > maxRects then maxRects = #f end
    end

    -- 控件池：按最大帧矩形数一次性实例化
    local pool = {}
    for i = 1, maxRects do
        local ctrl = game.InstantiateClientUIControl(prefabId, parent)
        if not ctrl then
            printerr("ObjectUI: 实例化图片控件失败 (prefabId=" .. tostring(prefabId) .. ")")
            break
        end
        -- 设为可缩放方块：中心锚点 + 中心点，便于按像素矩形定位
        ctrl:SetAnchorMin(0.5, 0.5)
        ctrl:SetAnchorMax(0.5, 0.5)
        ctrl:SetPivot(0.5, 0.5)
        ctrl:SetActive(false)
        pool[#pool + 1] = ctrl
    end

    instanceSeq = instanceSeq + 1
    local inst = {
        _id = instanceSeq,
        kind = "pixel",
        pool = pool,
        frames = frames,
        pixelSize = pixelSize,
        offX = offX,
        offY = offY,
        frameIndex = 1,
        acc = 0,
        frameMs = anim.FRAME_MS or 40,
        nFrames = #frames,
        cx = cx, cy = cy,
        displayW = displayW, displayH = displayH,
        prefabId = prefabId,
        visible = true,
    }
    instances[inst._id] = inst
    M._showPixelFrame(inst, 1)   -- 首帧（1 下标）立即显示，单帧也能正常呈现
    return inst
end

-- ---------------------------------------------------------------
-- 私有：显示资源模式的某一帧
-- ---------------------------------------------------------------
function M._showImageFrame(inst, fi)
    local f = inst.frameList[fi]
    if f then
        inst.ctrl:SetImage(f.source, f.id)
    end
end

-- ---------------------------------------------------------------
-- 像素对象模式：把像素图作为子控件挂到调用方指定的容器节点下
-- 与 createPixelSequence 的区别：本函数不管理“容器”本身的位置，
-- 调用方（如 game.lua 里的糖果 control）每帧移动父容器，整组像素会一起跟随。
-- cx, cy 是像素图中心相对于父容器中心的偏移（通常传 0, 0）。
-- 其余参数与 createPixelSequence 一致。
-- ---------------------------------------------------------------
function M.createPixelObject(parent, anim, cx, cy, displayW, displayH, opts)
    local inst = M.createPixelSequence(parent, anim, cx, cy, displayW, displayH, opts)
    if inst then
        inst.kind = "pixelObject"
    end
    return inst
end

-- 资源模式：每帧一张图片资产，单个图片控件切换（高效）
-- parent    : 父控件
-- frameList : 帧数组，每帧 {source=Enum.ImageSource.*, id=图片资产ID}
-- cx, cy    : 物品中心
-- w, h      : 显示宽高
-- frameMs   : 每帧时长（毫秒）
-- opts.prefabId : 图片控件模板 ID（必须）
-- ---------------------------------------------------------------
function M.createImageSequence(parent, frameList, cx, cy, w, h, frameMs, opts)
    opts = opts or {}
    local prefabId = opts.prefabId
    if not prefabId or prefabId <= 0 then
        printerr("ObjectUI.createImageSequence: 缺少有效的图片控件模板 prefabId")
        return nil
    end
    if not frameList or #frameList == 0 then
        printerr("ObjectUI.createImageSequence: frameList 为空")
        return nil
    end

    local ctrl = game.InstantiateClientUIControl(prefabId, parent)
    if not ctrl then
        printerr("ObjectUI: 实例化图片控件失败 (prefabId=" .. tostring(prefabId) .. ")")
        return nil
    end
    ctrl:SetAnchorMin(0.5, 0.5)
    ctrl:SetAnchorMax(0.5, 0.5)
    ctrl:SetPivot(0.5, 0.5)
    ctrl:SetSizeDelta(w, h)
    ctrl:SetAnchoredPosition(cx, cy)
    ctrl:SetActive(true)

    -- 显示第 0 帧
    local f0 = frameList[1]
    if f0 then ctrl:SetImage(f0.source, f0.id) end

    instanceSeq = instanceSeq + 1
    local inst = {
        _id = instanceSeq,
        kind = "image",
        ctrl = ctrl,
        frameList = frameList,
        frameIndex = 1,
        acc = 0,
        frameMs = frameMs or 40,
        nFrames = #frameList,
        cx = cx, cy = cy, w = w, h = h,
        prefabId = prefabId,
        visible = true,
    }
    instances[inst._id] = inst
    return inst
end

-- ---------------------------------------------------------------
-- 推进所有活动序列（逐帧调用，dt 单位：秒）
-- 仅当实例可见且帧数 > 1 时推进
-- ---------------------------------------------------------------
function M.update(dt)
    if not dt or dt <= 0 then return end
    local ms = dt * 1000
    for _, inst in pairs(instances) do
        if inst.visible and inst.nFrames > 1 then
            inst.acc = inst.acc + ms
            if inst.acc >= inst.frameMs then
                inst.acc = inst.acc - inst.frameMs
                inst.frameIndex = (inst.frameIndex % inst.nFrames) + 1
                if inst.kind == "pixel" or inst.kind == "pixelObject" then
                    M._showPixelFrame(inst, inst.frameIndex)
                else
                    M._showImageFrame(inst, inst.frameIndex)
                end
            end
        end
    end
end

-- ---------------------------------------------------------------
-- 设置实例位置（物品中心）
-- ---------------------------------------------------------------
function M.setPosition(inst, cx, cy)
    if not inst then return end
    inst.cx = cx
    inst.cy = cy
    if inst.kind == "pixel" or inst.kind == "pixelObject" then
        inst.offX = cx - inst.displayW / 2
        inst.offY = cy + inst.displayH / 2
        M._showPixelFrame(inst, inst.frameIndex)
    else
        inst.ctrl:SetAnchoredPosition(cx, cy)
    end
end

-- ---------------------------------------------------------------
-- 设置实例可见性
-- ---------------------------------------------------------------
function M.setVisible(inst, v)
    if not inst then return end
    inst.visible = v
    if inst.kind == "pixel" or inst.kind == "pixelObject" then
        for _, c in ipairs(inst.pool) do
            c:SetActive(false)
        end
        if v then
            M._showPixelFrame(inst, inst.frameIndex)
        end
    else
        inst.ctrl:SetActive(v)
    end
end

-- ---------------------------------------------------------------
-- 销毁实例：释放其全部控件（统一由本模块管理生命周期）
-- ---------------------------------------------------------------
function M.destroy(inst)
    if not inst then return end
    if inst.kind == "pixel" or inst.kind == "pixelObject" then
        -- 只销毁本模块创建的子控件像素块；父容器由调用方自行管理
        for _, c in ipairs(inst.pool) do
            if c.alive then
                game.DestroyClientUIControl(c)
            end
        end
    else
        if inst.ctrl and inst.ctrl.alive then
            game.DestroyClientUIControl(inst.ctrl)
        end
    end
    if inst._id then
        instances[inst._id] = nil
    end
end

return M
