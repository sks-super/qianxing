-- ================================================================
-- 点灯迷题 16 · 运行时状态
--   ★ 所有被其它模块读写的 state.* 字段必须在此显式声明
--     （写法必须是 M.foo = ...，_shared/_check_refs.py 只认这个）
-- ================================================================

---@diagnostic disable: undefined-global

local M = {}

-- 脚本参数
M.parent = nil
M.rectPrefabId = 0
M.textPrefabId = 0
M.cursorPrefabId = 0
M.containerPrefabId = 0     -- 真容器模板（可选；模拟器里必须配，否则命中测试下钻不到）
M.buttonPrefabId = 0

-- 画布
M.canvasW = 1280
M.canvasH = 720
M.LEFT = -640
M.RIGHT = 640
M.BOTTOM = -360
M.TOP = 360
M.k = 1
M.boardCX = 236
M.boardCY = -34
M.designW = 1280
M.designH = 720

-- 层级容器
M.containerScene = nil
M.containerBg = nil
M.containerBoard = nil      -- 当前盘面（右）
M.containerRef = nil        -- 目标图案（左）
M.containerFx = nil
M.containerHud = nil
M.containerChips = nil      -- 顶部拼图槽
M.containerWin = nil
M.containerBook = nil       -- 画册选关（主界面）
M.chapterDone = nil         -- 每个大关的四块通关表：{ [chIdx] = {b,b,b,b} }
M.bookBusy = false
M.containerFade = nil
M.containerTop = nil       -- 常驻浮层（结算按钮等，压着画册）
M.containerGuide = nil     -- 教程 / 引导高亮（最上层）
M.guideOpen = false
M.tutorialDone = false     -- 本次会话是否看过教程
M.tutorialHint = false     -- 是否处于「跟着高亮走」的引导模式
M.playTime = 0             -- 本次小关已游玩秒数（结算倒计时用）
M.settleSec = -1           -- 上一帧显示的倒计时整数秒（变化时才刷文本）
M.settling = false         -- 正在结算 / 已结算
M.achDone = {}             -- 已经发过成就的大关（防重复）

-- 章节 / 小关
M.chapterIndex = 1
M.pieceIndex = 1
M.mode = 1                  -- 1=找不同 / 2=无参照
M.phase = "pick"            -- pick | play | finish
M.pieceOpen = false

-- 图案与盘面
M.pic = {}                  -- 16×16（0/1）
M.quadTarget = {}           -- 当前小关的 8×8 目标（二维，供参考图用）
M.targetBoard = {}          -- 同一目标的 1..64 一维盘面（供判定用）
M.board = {}                -- 当前 8×8 盘面（1..64）
M.aSet = {}                 -- 生成用的 A（0 基下标 → true）
M.moves = 0
M.history = {}              -- 玩家按过的下标（0 基）
M.bestSteps = 0             -- = #A

-- 四块进度
M.slotDone = { false, false, false, false }
M.slotStars = { 0, 0, 0, 0 }

-- 视图
M.refCells = {}             -- 左侧目标的 64 个格子
M.playCells = {}            -- 右侧盘面的 64 个格子
M.chipViews = {}            -- 顶部四个拼图槽
M.playContainer = nil
M.refContainer = nil

-- 输入 / 时间
M.inputReady = true
M.pendingPress = nil
M.time = 0
M.lastDt = 0
M.hintIndex = -1
M.hintUntil = 0

-- 特效
M.particles = {}
M.floaters = {}
M.rings = {}
M.shakeT = 0

-- 音效
M.clickAudioId = 0
M.flipAudioId = 0
M.winAudioId = 0
M.starAudioId = 0
M.openAudioId = 0        -- 进入关卡音效（openAudioId）

return M
