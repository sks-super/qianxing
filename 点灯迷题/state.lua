-- ================================================================
-- 点灯迷题 状态模块：统一管理所有运行时状态
--   ★ 所有被其它模块读写的 state.* 字段都必须在此显式声明
--     （Lua 动态建字段不会报错，但会绕开集中约定，_shared/_check_refs.py 也会报未定义）。
-- ================================================================

---@diagnostic disable: undefined-global

local M = {}

-- ================================================================
-- 画布与边界（OnStart 读取 GetUICanvasSize 后写入）
-- ================================================================
M.canvasW = 0
M.canvasH = 0
-- ★ 居中面板层（教程 / 结算）的整体放大系数：画布 > 设计基准时整层放大。
--   这两层里 fx.spawn 的坐标要乘它（粒子挂在未放大的 containerFx 上）。
--   由 game.lua 的 applyUiScale() 写入；1 = 不缩放。
M.uiScale = 1
M.LEFT = 0
M.RIGHT = 0
M.BOTTOM = 0
M.TOP = 0

-- ================================================================
-- ★ 屏幕状态机
--   screen      : "select"（选关，默认） | "play"（3D 游玩 HUD）
--   tutorialOpen: 教程覆盖层（可从任一处打开，关闭后回到原屏幕）
--   winOpen     : 胜利结算覆盖层
--   ★ 三者互不排斥：结算/教程都是「压在当前屏幕之上的覆盖层」，
--     这样打开时底下的选关界面仍然可见，比硬弹窗自然。
-- ================================================================
M.screen = "select"
M.tutorialOpen = false
M.winOpen = false

-- ================================================================
-- 关卡进度
-- ================================================================
M.currentLevelIndex = 1        -- 当前关卡序号（1 起始）
M.currentLevelConfig = nil     -- 当前关卡配置表
M.clearedLevels = {}           -- 已通关关卡集合 [关卡序号] = true
M.tutorialSeen = false         -- 是否已看过教程（首次进第 1 关自动弹一次）
M.pendingEnterLevel = 0        -- 已发「进入关卡」信号、等服务器确认的关卡号（0=无）

-- ================================================================
-- 输入
-- ================================================================
M.deviceIsTouch = false        -- 触屏设备标志（game.GetDevice()）
M.keysEnabled = true           -- 菜单 / 结算按键总开关
M.lastDt = 0.016

-- ================================================================
-- 预制体 ID（OnStart 读取脚本变量后写入）
-- ================================================================
M.rectPrefabId = 0             -- ★ 必填：纯色矩形底图（面板 / 卡片 / 按钮 / 灯格全部用它染色）
M.textPrefabId = 0             -- 可选：文本控件模板（缺省则界面无文字，仅剩色块）
-- ★★ 必填（否则鼠标点不动）：【光标检测区域】元件。
--   千星里只有「预设按钮」和「光标检测区域」这两类控件带 AddCursorEventListener，
--   图片控件没有这个方法 —— 所以把点击绑在底图上会被 pcall 静默吞掉，
--   表现为「按钮看得见、点不动」。所有可点区域都改由这个元件代劳。
M.cursorPrefabId = 0

-- ================================================================
-- 音效预设 ID（OnStart 读取脚本变量后写入；<=0 表示不播放）
-- ================================================================
M.clickAudioId = 0
M.openAudioId = 0
M.winAudioId = 0

-- ================================================================
-- 父对象与层级容器
--   OnStart 一次性创建，创建顺序即显示层级（从下到上）：
--   bg → hud → menu → win → tutorial → fx → fade
--
--   ★★ 分层模型与 TickHop 完全一致：**一个图层只用一个容器**，
--      容器内的叠放完全交给「创建顺序」（真机 = 后创建的在上）。
--      不再设「图片组 / 文字组」二级容器 —— 那会让「文字是否压在同层底图之上」
--      取决于两个兄弟容器谁在后面，一旦兄弟顺序不是预期值，整层文字都会被遮住、
--      且全屏遮罩会盖住面板把点击一起吃掉。
--      改法：同一屏里每个组件都按「底图 → 文字 → 点击区域」的顺序创建，
--      于是「文字压在底图上」由创建顺序天然保证，不依赖任何重排调用。
-- ================================================================
M.parent = nil

M.containerBg       = nil   -- ① 夏日背景（天空 / 沙滩 / 波浪 / 气泡）
M.containerHud      = nil   -- ② 游玩期极简 HUD
M.containerMenu     = nil   -- ③ 选关界面
M.containerWin      = nil   -- ④ 胜利结算（覆盖 HUD / 选关）
M.containerTutorial = nil   -- ⑤ 图文教程（覆盖一切面板）
M.containerFx       = nil   -- ⑥ 果汁粒子（溅在所有面板之上，位于黑幕之下）
M.containerFade     = nil   -- ⑦ 黑幕过渡（最顶）

-- ================================================================
-- ★ 果汁粒子 / 补间动效（fx 模块）
--   粒子池一次性建好放进 containerFx，之后只改位置 / 尺寸 / 颜色 / 显隐。
-- ================================================================
M.fxNodes = {}             -- 粒子池控件
M.fxStates = {}            -- 每颗粒子的运行态 { active, x, y, vx, vy, life, age, size, hex }
M.fxBubbles = {}           -- 背景上升气泡 { ctrl, x, y, speed, size, phase }
M.fxTweens = {}            -- 活跃补间列表
M.fxTime = 0               -- 全局时间（秒），供呼吸 / 漂浮等周期动效取相位
M.fxPalette = nil          -- 粒子取色用的配色表（由 game.lua 注入）

-- ================================================================
-- 选关界面（menu 模块）
-- ================================================================
M.menuOpen = false        -- 兼容旧写法的语义位：等价于 screen == "select"
M.menuNodes = {}          -- 面板全部控件（统一显隐用）
M.menuOverlay = nil       -- 全屏遮罩
M.menuPanel = nil         -- 中央面板底
M.menuPanelShadow = nil   -- 面板投影（立体感）
M.menuPanelEdge = nil     -- 面板外圈描边（浅色遮罩下靠它把面板“框”出来）
M.menuTitle = nil         -- 标题
M.menuSubtitle = nil      -- 副标题
M.menuFooter = nil        -- 底部操作提示
M.menuCards = {}          -- 选关卡片 { {bg, label, sub, barTrack, barFill, hit, ...}, ... }
M.menuButtons = {}        -- 底部按钮 { {bg, label, hit, ...}, ... }
M.menuPagePrev = nil      -- 上一页箭头 { bg, label, hit }
M.menuPageNext = nil      -- 下一页箭头 { bg, label, hit }
M.menuTutorialBtn = nil   -- 「教程」按钮 { bg, label, hit }
M.menuCursor = 1          -- 选关高亮项（1 起始，值是关卡序号）
M.menuPage = 1            -- 选关当前页（1 起始）
M.selectGrid = nil        -- 网格布局缓存 { cols, rows, perPage, pages, cardW, cardH, gx, gy }
M.menuAnimT = 0           -- 选关面板入场计时（秒）

-- ================================================================
-- 图文教程（tutorial 模块）
-- ================================================================
M.tutNodes = {}            -- 全部控件（统一显隐用）
M.tutOverlay = nil
M.tutPanel = nil           -- 面板底
M.tutStage = nil           -- 示意图区凹槽底
M.tutTitle = nil           -- 页标题
M.tutLines = {}            -- 正文行 { ctrl, ... }
M.tutCaption = nil         -- 示意图下方的小注解
M.tutFooter = nil          -- 页脚提示（页码 + 操作）
M.tutPrev = nil            -- 上一页文字
M.tutPrevBg = nil          -- 上一页底
M.tutPrevHit = nil         -- 上一页点击区
M.tutClose = nil           -- 关闭文字
M.tutCloseBg = nil
M.tutCloseHit = nil
M.tutNext = nil            -- 下一页文字
M.tutNextBg = nil
M.tutNextHit = nil
M.tutCells = {}            -- 示意图格子 { ctrl, ... }（复用同一批色块画不同页）
M.tutAnns = {}             -- 示意图上的文字注解（如两图之间的「→」）
M.tutStageCY = 80          -- 示意图区中心的 y
M.tutPage = 1
M.tutPageCount = 0
M.tutAnimT = 0             -- 翻页动效计时（秒）
M.tutArtDX = 0             -- 翻页时示意图的水平偏移（像素）
M.tutPanelShadow = nil
M.tutPanelEdge = nil

-- ================================================================
-- 游玩期极简 HUD（hud 模块）
-- ================================================================
M.hudNodes = {}
M.hudTitle = nil           -- 「第 NN 关」
M.hudHint = nil            -- 状态 / 提示文本
M.hudExitBg = nil          -- 「退出」按钮底
M.hudExitLabel = nil       -- 「退出」按钮字
M.hudExitHit = nil         -- 「退出」点击区
M.hudTutBg = nil           -- 「教程」按钮底
M.hudTutLabel = nil        -- 「教程」按钮字
M.hudTutHit = nil          -- 「教程」点击区
M.hudHintOverride = ""     -- 状态行临时覆盖文本（"" 表示用默认难度行）
M.hudBgBar = nil           -- 左上信息条底
M.hudSlideT = 0            -- 滑入动效计时（秒）
M.hudSlideList = {}        -- 滑入动效条目 { {ctrl, baseX, fromX}, ... }

-- ================================================================
-- 胜利结算（winUI 模块）
-- ================================================================
M.winNodes = {}
M.winOverlay = nil
M.winPanel = nil
M.winPanelShadow = nil
M.winPanelEdge = nil
M.winGlow = nil            -- 面板外圈的脉动光晕
M.winTitle = nil
M.winSubtitle = nil
M.winStats = nil
M.winFooter = nil
M.winButtons = {}          -- { {bg, label, hit, action, ...}, ... }
M.winAnimCells = {}        -- 跑马灯小灯格 { {ctrl, order} , ... }（三星全部弹出后开始跑）
M.winStars = {}            -- 三星 { {ctrl, baseX, baseY, order, size, burst}, ... }
M.winStarGlow = nil        -- 三星背后的柔光底
M.winStarT = 0             -- 三星弹出计时（秒）
M.winAnimT = 0             -- 动效计时（秒）
M.winLevelIndex = 1        -- 结算对应关卡

return M
