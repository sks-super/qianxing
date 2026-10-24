-- ================================================================
-- 伐木远征 · 运行状态
--   ★ 工程约定：**所有 state.* 字段必须在这里显式声明**（哪怕初值是 nil），
--     否则 _check_refs.py 会报「未声明的 state 字段」。
--   ★ 这里只放可变状态；配置常量一律在 config.lua。
-- ================================================================

---@diagnostic disable: undefined-global

local M = {}

-- ---------------------------------------------------------------- 运行环境
M.parent = nil                  -- 脚本挂载的根控件（容器节点）
M.canvasW = 1280
M.canvasH = 720
M.LEFT = -640
M.RIGHT = 640
M.TOP = 360
M.BOTTOM = -360

-- 元件索引（OnStart 里从脚本参数读，缺省用 config 里的官方内置模板）
M.containerPrefabId = 0
M.rectPrefabId = 0
M.imagePrefabId = 0
M.textPrefabId = 0
M.rectImageId = 0

-- 画面尺度
M.tilePx = 64                   -- 一格多少像素
M.heightPx = 9                  -- 每 1 点高度抬多少像素
M.viewZoom = 1

-- ---------------------------------------------------------------- 层级容器
M.containerBg = nil             -- 最底：整屏水色
M.containerWorld = nil          -- 世界：地块 + 实体（整体平移当镜头）
M.containerHud = nil            -- HUD：地名 / 步数 / 消息 / 滑动区
M.containerMenu = nil           -- 标题 / 选关 / 对话（盖在最上面）

-- ---------------------------------------------------------------- 画面状态
M.screen = "title"              -- "title" | "select" | "play"
M.world = nil                   -- 当前 World 实例（mexp_engine）
M.mapKey = nil                  -- 当前地图 key
M.themeKey = "meadow"
M.theme = nil                   -- 当前主题配色表
M.progress = {}                 -- 已通关的地图：{ [key] = true }
M.lastMap = "islands"           -- 上次进入的地图（「继续」用）
M.goalSigns = {}                -- 终点木牌：{ ["岛:编号"] = true }

-- ---------------------------------------------------------------- 对局
M.undo = {}                     -- 撤销栈（快照）
M.moves = 0                     -- 步数（只在局面真的变了才 +1）
M.busy = false                  -- 连锁进行中
M.stepAcc = 0                   -- 连锁计时器
M.preSnap = nil                 -- 本次移动前的快照
M.dialog = nil                  -- { pages = {...}, idx = n, goal = bool }
M.camX = 0
M.camY = 0
M.camInit = false
M.time = 0                      -- 总时长（秒）
M.msgUntil = nil                -- 临时消息的失效时刻
M.keysEnabled = false

-- ---------------------------------------------------------------- 地形窗口
M.winKey = nil                  -- 已铺开的地形窗口标识（变了才重铺）
M.winX0 = 0
M.winY0 = 0

-- ---------------------------------------------------------------- HUD
M.hudBar = nil
M.hudBarBottom = nil
M.hudRegion = nil
M.hudMoves = nil
M.hudMsg = nil
M.hudKey = nil

-- ---------------------------------------------------------------- 选关
M.menuCursor = 1                -- 选关高亮项（1 起始，与卡片顺序一致）

-- ---------------------------------------------------------------- 输入
M.heldW = false
M.heldA = false
M.heldS = false
M.heldD = false

-- ---------------------------------------------------------------- 视角
M.lookX = 0                     -- 玩家朝向（只影响眼珠）
M.lookY = 0

return M
