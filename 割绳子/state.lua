-- ================================================================
-- 状态模块：统一管理所有运行时状态
-- ================================================================

local M = {}

-- 画布边界
M.canvasW = 0
M.canvasH = 0
M.LEFT = 0
M.RIGHT = 0
M.BOTTOM = 0
M.TOP = 0

-- 游戏对象
M.ropes = {}
M.candyNode = nil
M.target = nil
M.stars = {}
M.bubbles = {}
M.spikes = {}          -- ★ 尖刺列表
M.texts = {}           -- ★ 文本框列表
M.boards = {}          -- ★ 木板（矩形障碍）列表

-- 糖果包裹状态
M.candyWrapped = false
M.wrappedGravity = 0

-- 物理参数
M.GRAVITY = 800
M.CANDY_DAMPING = 0.998
M.CONSTRAINT_ITERATIONS = 20
M.SUB_STEPS = 8
M.MAX_DRAG_FACTOR = 1.0

-- 交互状态
M.isMouseDown = false
M.lastMouseX = 0
M.lastMouseY = 0
M.isDragging = false

-- ★ 输入设备与触屏单指切割状态
M.deviceIsTouch = false   -- 触屏设备标志（game.GetDevice()==Mobile / MobileController 时为 true）
M.activeTouchId = nil     -- 触屏当前“切割手指”的触点 ID：只认第一根按下到抬起的手指，其余触点忽略
M.curUX = nil             -- 当前活动光标/触点的 UI 坐标（触屏由 Down/Drag 事件写入；键鼠由 OnUpdate 轮询刷新）
M.curUY = nil

M.cheatMode = false        -- ★ 开挂模式：默认关闭；开启后可拖拽糖果，边界/尖刺改为弹性碰撞
M.hintTextVisible = false   -- ★ 代码提示文本显隐（MessageText 控件；由“文本显/隐”信号切换，config 关卡消息框不受影响）
M.keysEnabled = false       -- ★ 键盘按键绑定开关（由“按键绑定开/关”信号切换）
M.lastDt = 0.016

-- 游戏状态
M.gameWon = false
M.gameFailed = false      -- ★ 失败标志
M.messageText = nil
M.currentLevelIndex = 1
M.currentLevelConfig = nil

-- 得分
M.score = 0
M.scoreText = nil

-- 预制体ID
M.fruitPrefabId = 0

-- ★ 刀光拖尾模板 ID（game.lua OnStart 读取脚本变量 bladePrefabId 写入）
M.bladePrefabId = 0

-- ★ 音效预设 ID（game.lua OnStart 读取脚本变量写入；<=0 表示不播放对应音效）
M.cutAudioId = 0
M.bubbleAudioId = 0
M.winAudioId = 0
M.failAudioId = 0
M.tenseAudioId = 0
M.starAudioId = 0

-- ★ 泡泡模板 ID（game.lua OnStart 读取脚本变量 bubblePrefabId 写入，并写回 config.bubblePrefabId）
M.bubblePrefabId = 0

-- ★ 绳桩（锚点）模板 ID（game.lua OnStart 读取脚本变量 anchorPrefabId 写入，并写回 config.anchorPrefabId）
M.anchorPrefabId = 0

-- ★ 星星模板 ID（game.lua OnStart 读取脚本变量 starPrefabId 写入）
M.starPrefabId = 0

-- ★ 尖刺模板 ID（game.lua OnStart 读取脚本变量 spikePrefabId 写入）
M.spikePrefabId = 0

-- ★ 文本框模板 ID（game.lua OnStart 读取脚本变量 textboxPrefabId 写入）
M.textboxPrefabId = 0

-- ★ 木板模板 ID（game.lua OnStart 读取脚本变量 boardPrefabId 写入）
M.boardPrefabId = 0

-- 父对象
M.parent = nil

-- ★ 容器父节点（OnStart 一次性创建，创建顺序即显示层级，从下到上：
--   rope → board → world → candy → target → text → blade → fade）
--   游玩阶段只操作容器内的子节点，父节点本身不移动、不重排。
M.containerRope   = nil   -- ① 绳子：绳桩/中间节点/虚线点/样条线段
M.containerBoard  = nil   -- ② 木板（固定障碍，糖果可碰撞）
M.containerWorld  = nil   -- ③ 关卡物件：星星/泡泡/尖刺
M.containerCandy  = nil   -- ④ 糖果：糖果容器（蛋糕像素挂糖果下）
M.containerTarget = nil   -- ⑤ 人物：吃糖小怪兽（等待投喂/吞食动画）
M.containerText   = nil   -- ⑥ 文本框
M.containerBlade  = nil   -- ⑦ 刀光拖尾
M.containerFade   = nil   -- ⑧ 黑幕过渡（最顶）

-- ★ 刀光拖尾的节点池与运行时状态由 bladeTrail 模块内部维护（预创建、隐藏复用、不重排）

return M