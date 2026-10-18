-- ================================================================
-- 2048 · 状态模块
--   ★ 所有被其它模块读写的 state.* 字段都必须在此显式声明。
--     Lua 动态建字段不会报错，但会绕开集中约定，_check_refs.py 也会报未定义。
-- ================================================================

---@diagnostic disable: undefined-global

local M = {}

-- ================================================================
-- 画布与自适应
-- ================================================================
M.parent = nil            -- 挂载点（客户端控件容器的容器节点）
M.canvasW = 0             -- 画布宽（GetUICanvasSize）
M.canvasH = 0             -- 画布高
M.k = 1                   -- 自适应比例 = min(画布宽/设计宽, 画布高/设计高)
M.LEFT = 0                -- 画布左边界（-canvasW/2）
M.RIGHT = 0
M.BOTTOM = 0
M.TOP = 0
M.boardCX = 0             -- 棋盘静止时的中心 x（config.DEFAULT_BOARD_CX）
M.boardCY = 0             -- 棋盘静止时的中心 y

-- ================================================================
-- 预制体 / 音效 ID（OnStart 从脚本变量读入）
-- ================================================================
M.rectPrefabId = 0        -- ★ 必填：纯色矩形（图片控件），棋盘/方块/背景都用它染色
M.textPrefabId = 0        -- 建议：文本框（数字 / 分数 / 提示）
M.cursorPrefabId = 0      -- 建议：光标检测区域（滑动面）；取不到时回退图片控件
M.buttonPrefabId = 0      -- 可选的「预设按钮」模板：自绘按钮已不再依赖它（留作备用）

M.moveAudioId = 0         -- 滑动音效
M.mergeAudioId = 0        -- 合并音效
M.spawnAudioId = 0        -- 新方块出现音效
M.undoAudioId = 0         -- 撤销音效
M.winAudioId = 0          -- 达成 2048
M.failAudioId = 0         -- 无路可走
M.clickAudioId = 0        -- 按钮点击

-- ================================================================
-- 棋盘数据（board.lua 持有真值，这里只是同一张表的引用 + 镜像字段）
-- ================================================================
M.tiles = {}              -- 方块数组 { {id=, r=, c=, value=}, ... }
M.score = 0               -- 当前分数
M.best = 0                -- 最高分
M.steps = 0               -- 有效移动步数
M.nextTileId = 1          -- 方块自增 id
M.undoStack = {}          -- 撤销栈（快照数组）
M.maxReached = 0          -- 历史最大方块值（用于「最大方块」展示）

-- ================================================================
-- 玩法状态机
--   playing  正常游戏中
--   settled  已弹出结算面板（棋盘定格在相片位）
-- ================================================================
M.phase = "playing"
M.won = false             -- 本局是否已达成目标值（只播报一次）
M.winHandled = false
M.dead = false            -- 本局是否已无路可走
M.deadHandled = false
M.paused = false          -- 结算面板打开时冻结玩法
M.animating = false       -- ★ 动画进行中：锁输入，防止重复触发
M.lockTimer = 0           -- 动画结束后的额外输入锁（秒）
M.keysEnabled = true      -- 玩法输入总开关

-- ================================================================
-- 输入
-- ================================================================
M.deviceIsTouch = false   -- 触屏设备
M.swipeStartX = 0         -- 滑动起点（UI 坐标）
M.swipeStartY = 0
M.swiping = false         -- 是否已开始滑动
M.swipeConsumed = false   -- 本次滑动是否已消费（一次触摸只触发一次移动）

-- ================================================================
-- 层级容器（OnStart 一次性创建；见 game.lua 的 LAYER_ORDER）
--   ★ containerScene 是「设计空间根」：SetLocalScale(k) 挂在它身上，
--     于是下面所有子控件都能直接用设计坐标（1280×720 基准）写字。
--   ★ containerBoard 是「棋盘根」：棋盘全体子控件都在它下面，
--     结算时对它整体 SetLocalScale / SetLocalRotation / SetAnchoredPosition，
--     就能一次性把整块棋盘「拍成照片」飞到相片位。
-- ================================================================
M.containerScene = nil    -- ⓪ 设计空间根（承载自适应缩放 k）
M.containerBg = nil       -- ① 背景
M.containerBoard = nil    -- ② 棋盘根（自带位移/缩放/旋转，结算动效作用于它）
M.containerBoardBg = nil  -- ②-a 棋盘底板与空格（containerBoard 的子节点）
M.containerTile = nil     -- ②-b 方块（containerBoard 的子节点，必须在底板之上）
M.containerFx = nil       -- ③ 特效（粒子 / 飘字）
M.containerHud = nil      -- ④ HUD（滑动面 / 分数 / 方向键 / 功能按钮）
M.containerMenu = nil     -- ⑤ 结算面板
M.containerInfo = nil     -- ⑤-a 结算「信息面板」分组（整组滑入靠它）
M.containerFade = nil     -- ⑥ 黑幕（最顶）

M.bgCtrl = nil            -- 背景矩形

-- ================================================================
-- 视图对象（view.lua）
-- ================================================================
M.cellBacks = {}          -- 16 个空格底板控件
M.tileViews = {}          -- 方块视图 { {root, img, label, id, value, r, c}, ... }
M.boardFrame = nil        -- 棋盘外框

-- ================================================================
-- HUD 对象（hud.lua）
-- ================================================================
M.titleText = nil
M.scoreBox = nil          -- { bg, label, value }
M.bestBox = nil           -- { bg, label, value }
M.hintText = nil
M.scoreShown = 0          -- 分数当前显示值（滚动动画用）
M.bestShown = 0           -- 最高分当前显示值
M.dpad = {}               -- 方向键 { {btn, dir}, ... }（btn = createButton 返回的自绘按钮）
M.funcButtons = {}        -- 功能按钮 { {btn, action, enabled}, ... }
M.swipeArea = nil         -- 滑动命中区（containerHud 的第一个子控件）
M.toastText = nil         -- 右下角临时提示
M.toastTimer = 0          -- 剩余显示时长

-- ================================================================
-- 结算面板（menu.lua）
-- ================================================================
M.menuOpen = false
M.menuMode = nil          -- "win" | "dead"
M.menuNodes = {}          -- 面板全部控件（统一显隐）
M.menuOverlay = nil       -- 全屏遮罩
M.menuPhotoBars = {}      -- 相框四条边条 { {ctrl, w, h, x, y}, ... }
M.menuPhotoMatte = nil    -- 相片内衬（棋盘与相框之间的深色细线）
M.menuPhotoCap = nil      -- 相片下方说明文字
M.menuInfoPanel = nil     -- 左侧信息面板底
M.menuInfoEdge = nil      -- 左侧信息面板描边
M.menuTitle = nil         -- 大字标题
M.menuSubtitle = nil      -- 副标题
M.menuScoreLabel = nil    -- 「本次得分」小标题
M.menuScoreValue = nil    -- 结算分数数字（滚动增长）
M.menuStatMax = nil       -- 统计行：最大方块
M.menuStatBest = nil      -- 统计行：最高分
M.menuStatSteps = nil     -- 统计行：步数
M.menuButtons = {}        -- 面板按钮 { {hit, label, action, enabled}, ... }
M.menuScoreShown = 0      -- 结算分数当前显示值（滚动增长）
M.menuFinalScore = 0
M.menuFinalMax = 0
M.menuFinalSteps = 0

-- ================================================================
-- 特效对象（fx.lua）
-- ================================================================
M.particles = {}          -- 粒子池 { {ctrl, r,g,b, x, y, vx, vy, t, life, spin, rot}, ... }
M.floaters = {}           -- 飘字池 { {ctrl, r,g,b, x, y, t, life, rise}, ... }

-- ================================================================
-- 最高分（signal.lua）
-- ================================================================
M.highScoreLoaded = false -- 是否已从服务器读到过最高分
M.highScoreSent = 0       -- 已经上报过的纪录值（避免重复发信号）

-- ================================================================
-- 其它
-- ================================================================
M.lastDt = 0.016
M.pendingRestart = false  -- 需要重建棋盘（黑幕散尽后执行）
M.ready = false           -- 初始化完成（容器与 HUD 都建好了）

return M
