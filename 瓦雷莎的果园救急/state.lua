-- ================================================================
-- 瓦雷莎的果园救急 · 状态模块（集中托管所有 state.* 字段）
--   ★ 其它模块读写的字段都必须在这里显式声明，_shared/_check_refs.py 会校验。
-- ================================================================

---@diagnostic disable: undefined-global

local M = {}

-- ================================================================
-- 画布 / 边界 / UI 缩放
-- ================================================================
M.canvasW = 0
M.canvasH = 0
M.uiScale = 1              -- 居中面板层（结算 / 教学卡）整体放大系数
M.LEFT = 0
M.RIGHT = 0
M.BOTTOM = 0
M.TOP = 0

-- ================================================================
-- 屏幕状态机
--   screen : "select"（果园地图） | "play"（3D 游玩）
--   guideOpen / winOpen 是「压在当前屏幕上的覆盖层」
-- ================================================================
M.screen = "select"
M.guideOpen = false
M.winOpen = false

-- ================================================================
-- 关卡进度
-- ================================================================
M.currentLevelIndex = 1
M.currentLevelConfig = nil
M.clearedLevels = {}       -- [关卡] = true
M.levelStars = {}          -- [关卡] = 1..3
M.tutorialSeen = false
M.lessonSeen = {}          -- [关卡] = true（本关教程本局已弹过）
M.prologueSeen = false     -- 序章本局是否已经「处理过」（弹了 / 认定老玩家跳过）—— 处理过就不再动它
M.prologueDelay = 0        -- 首屏等服务器存档的倒计时（>0 = 还没决定弹不弹序章）
M.saveSynced = false       -- 是否已收到「服客同步存档信息」（收到就立刻做序章决策）
M.latestCleared = 0        -- 服务器存档：已通关的最新关卡序号（0 = 一片都没通关）
M.pendingEnterLevel = 0
M.pendingT = 0              -- 等待服务器布置果园的计时（超时兜底）
-- ★ 待发的「客服关卡参数」关卡号：0 = 没有待发。
--   教程关进关时先记在这里，等玩家关掉教程（真正进入游玩界面）才发出去。
M.pendingLevelParams = 0
M.juiceLeft = -1           -- 服务器回传的「剩余果汁」；-1 = 未知

-- ================================================================
-- 输入
-- ================================================================
M.deviceIsTouch = false
M.lastDt = 0.016

-- ================================================================
-- 预制体 / 音效参数
-- ================================================================
M.rectPrefabId = 0
M.textPrefabId = 0
M.cursorPrefabId = 0
M.containerPrefabId = 0
-- ★ 圆形 / 圆环图元（图片元件）：用来拼云朵、果实、圆丘、太阳。
--   不配就退化成矩形（画面照常跑，只是形状变方）。
M.circlePrefabId = 0
M.ringPrefabId = 0
M.trianglePrefabId = 0
-- ★ 四角星 / 五角星图元：装饰闪光（牌面小星、结算火花）。
--   不配就退回圆形，再退回矩形。
M.star4PrefabId = 0
M.star5PrefabId = 0

M.clickAudioId = 0
M.dragAudioId = 0          -- 拖动地图音效（未配时 game.lua 自动复用 clickAudioId）
M.openAudioId = 0
M.winAudioId = 0

-- ================================================================
-- 父对象与层级容器（创建顺序即显示层级，从下到上）
--   scene → hud → map → win → guide → fx → fade
-- ================================================================
M.parent = nil
M.containerScene = nil
M.containerHud = nil
M.containerMap = nil
M.containerWin = nil
M.containerGuide = nil
M.containerFx = nil
M.containerFade = nil

-- ================================================================
-- 粒子 / 补间（fx 模块）
-- ================================================================
M.fxNodes = {}
M.fxStates = {}
M.fxTweens = {}
M.fxTime = 0
M.fxPalette = nil

-- ================================================================
-- 果园背景（scene 模块）
-- ================================================================
M.sceneNodes = {}
M.sceneLeaves = {}
M.sceneWinds = {}         -- 风的线条（半透明细椭圆）
M.sceneSunHalo = nil      -- 太阳两层光晕（每帧呼吸）
M.sceneClouds = {}
M.sceneSun = nil
M.sceneReady = false

-- ================================================================
-- ★ 果园地图选关（map 模块）
-- ================================================================
M.mapOpen = false
M.mapNodes = {}            -- 每片果园一个节点表
M.mapDots = {}             -- 土路小石子
M.mapDecos = {}            -- 装饰（果树 / 灌木 / 小花）
M.mapWorld = nil           -- 世界容器（整条长图，横向平移它）
M.mapDragHit = nil         -- 覆盖地图区的拖拽 / 点击命中区
M.mapTitle = nil
M.mapHeadBandEdge = nil    -- 标题牌外沿（圆角块）
M.mapHeadBand = nil        -- 标题牌面（圆角块）
M.mapSubtitle = nil
M.mapFootBand = nil        -- 底部提示胶囊（圆角块）
M.mapProgressTrack = nil
M.mapProgressFill = nil
M.mapProgressW = 0
M.mapProgressX = 0
M.mapFooter = nil
M.mapBanner = nil          -- 顶部信息条底
M.mapArrowL = nil
M.mapArrowR = nil
M.mapEnterBtn = nil
M.mapHandBtn = nil
M.mapCursor = 1            -- 当前选中的果园
M.mapScroll = 0            -- 长图当前横向偏移（0 = 世界原点居中）
M.mapTarget = 0            -- 平滑滚动目标
M.mapVel = 0               -- 惯性速度（像素/秒）
M.mapScrollAnim = 0        -- 平滑滚动剩余时间
M.mapScrollFrom = 0
M.mapScrollDur = 0
M.mapScrollT = 0
M.mapDragging = false
M.mapMoved = 0
M.mapAnimT = 0             -- 入场计时
M.mapWorldW = 0            -- 长图总宽
M.mapMaxScroll = 0
M.mapNodeX = {}            -- 每片果园的世界 x
M.mapNodeY = {}            -- 每片果园的世界 y
M.mapRingParts = {}        -- 当前果园金圈的四根条
M.mapRingSize = 0
M.mapRingShape = false     -- 金圈是否用真圆环模板（false = 四根细条）
M.mapMascot = nil          -- 小龙容器
M.mapMascotParts = {}      -- 小龙部件（翅膀 / 眼睛…）
M.mapMascotIdx = 0
M.mapMascotX = 0
M.mapMascotY = 0
M.mapBobT = 0
M.mapEntering = false
M.mapUnlockMax = 1         -- 已解锁到第几片
M.mapUnlockHint = 0        -- 服务器存档推出的解锁上限（「服客同步存档信息」= 已通关最新 + LOCK_AHEAD；0 = 还没收到）
M.mapIntroDone = false
M.mapPointerMap = 0        -- 光标坐标约定（0=未测, 1=居中y上, 2=左上y下, 3=左上y上）
-- ★★ 序章读完后的「点进入果园」引导（光圈 + 气泡 + 指示三角）
--   置位：state.prologueGuidePending（guide 关掉序章时置位）→ game.lua 每帧看到
--   「在地图页 + 教程已关」就调 map.guideEnter(true)，然后清零本标志。
M.prologueGuidePending = false
M.mapGuide = false         -- 引导是否正在显示
M.mapGuideRoot = nil       -- 引导整层的父容器（显隐只动它一个）
M.mapGuideRing = {}        -- 两条光圈：{ [1]=内圈容器, [2]=外圈容器 }
M.mapGuideBars = {}        -- 两条光圈的全部细条 { {ctrl=…, ring=1|2}, … }
M.mapGuideArrow = nil      -- 气泡下沿指向按钮的三角
M.mapGuideArrowX = 0       -- 三角原地（每帧按它 + 轻跳偏移重写坐标）
M.mapGuideArrowY = 0
M.mapGuideBubble = nil     -- 气泡底（圆角块：外沿）
M.mapGuideBubbleFace = nil -- 气泡底（圆角块：牌面）
M.mapGuideText = nil
M.mapGuideT = 0            -- 引导自己的计时（与 state.fxTime 无关，随时可清零）

-- ================================================================
-- ★ 教学卡 / 玩法手册（guide 模块）
-- ================================================================
M.guideNodes = {}
M.guideOverlay = nil
M.guideShadow = nil
M.guideEdge = nil
M.guidePanel = nil
M.guideStage = nil
M.guideTitle = nil
M.guideCaption = nil
M.guidePageText = nil
M.guideLines = {}
M.guideCells = {}
M.guideRings = {}          -- 示意图「亮蓝矩形环框」层（每格一个 holder + 4 根细条）
M.guideButtons = {}
M.guidePage = 1
M.guidePageCount = 0
M.guideAnimT = 0
M.guideIntroT = 0          -- 面板入场计时（与翻页计时分开）
M.guideKind = ""           -- "tutorial"（图册 / 本课）| "prologue"（地图首屏自动弹的序章）
M.guideLevel = 0
M.guidePages = {}          -- 当前打开的页数据（序章 2 页 / 第 1 课 3 页 / 第 2–5 课各 1 页）

-- ================================================================
-- 游玩 HUD（hud 模块）
-- ================================================================
M.hudNodes = {}
M.hudReady = false         -- ★ init 完成标记（原来是用 hudTitle 判空，标题已删）
M.hudBarShade = nil
M.hudBar = nil
M.hudHint = nil            -- 左上唯一一行「临时状态」文案（空 = 整条隐藏）
M.hudHintOverride = ""
-- ★ 以下字段已随「游玩界面去按钮」删除：hudTutBg / hudTutLabel / hudTutHit /
--   hudExitBg / hudExitLabel / hudExitHit / hudJuiceBg / hudJuiceLabel。
--   回果园改由服务器信号「服客进入选关」驱动，HUD 里不再有按钮与常驻信息。
M.hudSlideT = 0
M.hudSlideList = {}

-- ================================================================
-- 胜利结算（winUI 模块）
-- ================================================================
M.winNodes = {}
M.winOverlay = nil
M.winPanel = nil
M.winPanelShadow = nil
M.winPanelEdge = nil
M.winGlow = {}             -- 面板柔光：三层同心椭圆 { ctrl, base }
M.winTitle = nil
M.winSubtitle = nil
M.winStats = nil
M.winFooter = nil
M.winButtons = {}
M.winAnimCells = {}
M.winStars = {}
M.winStarGlow = nil
M.winStarT = 0
M.winAnimT = 0
M.winLevelIndex = 1

return M
