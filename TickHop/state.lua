-- ================================================================
-- TickHop 状态模块：统一管理所有运行时状态
--   ★ 所有被其它模块读写的 state.* 字段都必须在此显式声明
--     （Lua 动态建字段不会报错，但会绕开集中约定，_check_refs.py 也会报未定义）。
-- ================================================================

---@diagnostic disable: undefined-global

local M = {}

-- ================================================================
-- 画布与边界（OnStart 读取 GetUICanvasSize 后写入）
-- ================================================================
M.canvasW = 0
M.canvasH = 0
M.LEFT = 0
M.RIGHT = 0
M.BOTTOM = 0
M.TOP = 0

-- ================================================================
-- 遍历用的关卡包围盒（用于「掉出关卡」判定）
-- ================================================================
M.stageLeft = 0
M.stageRight = 0
M.stageBottom = 0
M.stageTop = 0

-- ================================================================
-- 关卡对象
-- ================================================================
M.player = nil            -- 玩家 {x, y, vx, vy, halfW, halfH, ctrl, onGround}
M.platforms = {}          -- 平台列表 {x, y, halfW, halfH, tick, solid, ctrl, label}
M.pickups = {}            -- 道具列表 {x, y, kind, value, taken, ctrl}
M.goal = nil              -- 终点门 {x, y, halfW, halfH, ctrl}
M.texts = {}              -- 关卡提示文本 {x, y, ctrl}
M.bgCtrl = nil            -- 背景矩形控件

-- ================================================================
-- 时间系统快照（真值由 timeSystem 模块持有，这里仅存只读镜像以便其它模块读取）
-- ================================================================
M.timeNow = 0             -- 当前剩余时间（秒）
M.timeLimit = 0           -- 本关初始时间
M.timeDirection = -1      -- -1=递减 / +1=递增
M.timeTick = 0            -- floor(timeNow)，平台实体判定依据
M.timeRunning = false     -- 计时是否推进中

-- ================================================================
-- 物理参数（OnStart / 关卡加载时由 config 的 DEFAULT_* 覆盖）
-- ================================================================
M.GRAVITY = 1600
M.FALL_GRAVITY_MULT = 1.35
M.MAX_FALL_SPEED = 1000
M.MOVE_SPEED = 260
M.GROUND_ACCEL = 2600
M.GROUND_FRICTION = 3200
M.AIR_ACCEL = 1500
M.AIR_FRICTION = 300
M.JUMP_SPEED = 520
M.JUMP_CUT_MULT = 0.45
M.JUMP_EDGE_TRIGGER = 1
M.COYOTE_TIME = 0.10
M.JUMP_BUFFER_TIME = 0.12
M.PHYSICS_SUBSTEPS = 4

-- ================================================================
-- 输入状态
-- ================================================================
M.keyLeft = false         -- 左方向键是否按住
M.keyRight = false        -- 右方向键是否按住
M.keyJump = false         -- 跳跃键是否按住（用于「按下的那一刻」判定 + 可变跳跃高度）
M.jumpBufferTimer = 0     -- 跳跃缓冲计时
M.jumpCutDone = false     -- 本次跳跃是否已执行「松手截断」（保证只截断一次，不逐帧削速）
M.coyoteTimer = 0         -- 土狼时间计时
M.deviceIsTouch = false   -- 触屏设备标志（game.GetDevice()）
M.keysEnabled = true      -- 按键/触屏输入总开关

-- ================================================================
-- 触屏虚拟按钮
-- ================================================================
M.touchButtons = {}       -- { {ctrl, key}, ... }，key = "left"/"right"/"jump"

-- ================================================================
-- HUD 控件
-- ================================================================
M.timerText = nil         -- 倒计时数字
M.messageText = nil       -- 提示消息（失败/过关提示）
M.hintText = nil          -- 关卡内配置的提示文本容器（由 texts 逐条创建）

-- ================================================================
-- 游戏状态
-- ================================================================
M.gameWon = false         -- 已到达终点
M.gameFailed = false      -- 时间耗尽 / 掉出关卡
M.paused = false
M.currentLevelIndex = 1
M.currentLevelConfig = nil
M.lastDt = 0.016

-- 结束原因与「只处理一次」标记（避免每帧重复播报 / 重复发信号）
M.failReason = nil        -- "time_out"（时间耗尽） / "fall_out"（掉出关卡）
M.failHandled = false     -- 失败流程是否已执行
M.winHandled = false      -- 通关流程是否已执行
M.justSwitchedTick = false -- 本帧平台秒数是否发生切换（供音效使用）
M.pendingStart = false    -- 关卡已重建、等待黑幕散尽后再启动计时

-- ================================================================
-- 菜单 / 结算面板（menu.lua）
--   三态复用同一批控件；打开时冻结玩法并接管输入（keysEnabled=false）。
-- ================================================================
M.menuOpen = false        -- 面板是否打开
M.menuMode = nil          -- "select"（选关） / "win"（通关） / "fail"（失败）
M.menuPage = 1            -- 选关当前页（1 起始）
M.menuCursor = 1          -- 选关高亮项（1 起始，值是关卡序号）
M.menuNodes = {}          -- 面板全部控件（统一显隐用）
M.menuOverlay = nil       -- 全屏遮罩
M.menuPanel = nil         -- 中央面板底
M.menuTitle = nil         -- 标题
M.menuSubtitle = nil      -- 副标题
M.menuFooter = nil        -- 底部操作提示
M.menuCards = {}          -- 选关卡片 { {bg, label, index}, ... }
M.menuButtons = {}        -- 底部按钮 { {bg, label, action}, ... }
M.menuPagePrev = nil      -- 上一页箭头 { bg, label }
M.menuPageNext = nil      -- 下一页箭头 { bg, label }
M.menuEntryButton = nil   -- 触屏常驻「选关」入口按钮 { bg, label }
M.clearedLevels = {}      -- 已通关关卡集合 [关卡序号] = true
M.winTimeLeft = 0         -- 通关瞬间的剩余时间（供结算展示）

-- ================================================================
-- 冷却计时
-- ================================================================
M.switchCooldown = 0      -- 平台切换音效冷却
M.landCooldown = 0        -- 落地音效冷却
M.lastWasOnGround = false

-- ================================================================
-- 预制体 ID（OnStart 读取脚本变量后写入）
-- ================================================================
M.rectPrefabId = 0        -- ★ 必填：纯色矩形底图（背景/平台/玩家/门/道具均用它染色）
M.textPrefabId = 0        -- 可选：文本控件模板（倒计时 / 平台秒数 / 提示）
M.playerPrefabId = 0      -- 可选：玩家外观模板，0 时回退 rectPrefabId
M.goalPrefabId = 0        -- 可选：终点门模板，0 时回退 rectPrefabId

-- ================================================================
-- 音效预设 ID（OnStart 读取脚本变量后写入；<=0 表示不播放）
-- ================================================================
M.jumpAudioId = 0
M.landAudioId = 0
M.switchAudioId = 0
M.pickupAudioId = 0
M.winAudioId = 0
M.failAudioId = 0

-- ================================================================
-- 父对象与层级容器
--   OnStart 一次性创建，创建顺序即显示层级（从下到上）：
--   bg → platform → goal → pickup → player → hud → menu → fade
-- ================================================================
M.parent = nil

M.containerBg       = nil   -- ① 背景
M.containerPlatform = nil   -- ② 计时平台 + 秒数标签
M.containerGoal     = nil   -- ③ 终点门
M.containerPickup   = nil   -- ④ 道具
M.containerPlayer   = nil   -- ⑤ 玩家
M.containerHud      = nil   -- ⑥ HUD（倒计时 / 提示 / 虚拟按钮）
M.containerMenu     = nil   -- ⑦ 菜单 / 结算面板（覆盖 HUD，但位于黑幕之下）
M.containerFade     = nil   -- ⑧ 黑幕过渡（最顶）

return M
