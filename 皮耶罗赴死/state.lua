-- ================================================================
-- 皮耶罗：赴死 · 运行时状态
--   ★ 所有被其它模块读写的 state.* 字段必须在此显式声明
--     （写法必须是 M.foo = ...，_shared/_check_refs.py 只认这个）
-- ================================================================

---@diagnostic disable: undefined-global

local M = {}

-- ---------------- 脚本参数 ----------------
M.parent = nil
M.rectPrefabId = 0
M.textPrefabId = 0
M.cursorPrefabId = 0
M.containerPrefabId = 0
M.buttonPrefabId = 0

-- ---------------- 画布与缩放 ----------------
M.canvasW = 960
M.canvasH = 540
M.k = 1
M.LEFT = -480
M.RIGHT = 480
M.BOTTOM = -270
M.TOP = 270

-- ---------------- 层级容器 ----------------
M.containerScene = nil
M.containerBg = nil
M.containerStain = nil     -- 血渍（压在实体之下）
M.containerWorld = nil     -- 门 / 实体 / 陷阱
M.containerPlayer = nil
M.containerFx = nil        -- 粒子
M.containerHud = nil
M.containerMenu = nil
M.containerTop = nil       -- 结算演出
M.containerFade = nil      -- 黑幕（最顶）

-- ---------------- 关卡 ----------------
M.levelIndex = 0
M.levelName = ""
M.levelDef = nil
M.solids = {}              -- 本关静态实体（世界坐标 rect）
M.traps = {}               -- 陷阱实例
M.door = nil               -- 门实例
M.flags = {}               -- 按钮 / 闸门共享开关

-- ---------------- 玩家 ----------------
M.player = nil
M.ghost = false
M.ghostFailT = 0
M.jumpBuffer = 0
M.invertNow = false        -- 本帧是否处于「反向操作」区域
M.deaths = 0
M.deathLine = ""

-- ---------------- 流程 ----------------
M.state = "boot"           -- boot | menu | play | dead | win | comic | end
M.stateT = 0               -- 当前状态已持续秒数
M.ghostOn = true           -- 不死诅咒（鬼魂模式）
M.ghostParam = 1           -- 脚本参数 ghost（0 = 关）
M.done = {}                -- done[i] = true 表示第 i 关已通过
M.unlocked = 1             -- 已解锁到第几关
M.comicOn = true
M.endRoast = ""

-- ---------------- 输入 ----------------
M.keyLeft = false
M.keyRight = false
M.keyUp = false
M.keyDown = false
M.keyJump = false
M.keysEnabled = false

-- ---------------- 时间 ----------------
M.time = 0
M.lastDt = 0

-- ---------------- 特效 ----------------
M.particles = {}           -- 活动粒子
M.stains = {}              -- 血渍环形缓冲
M.stainIdx = 0
M.shakeAmt = 0
M.shakeT = 0

-- ---------------- 音效 ----------------
M.clickAudioId = 0
M.jumpAudioId = 0
M.deathAudioId = 0
M.winAudioId = 0
M.popAudioId = 0
M.openAudioId = 0

-- ---------------- 调试 ----------------
M.devAuto = ""             -- "next" 自动过关等（开发用）
M.devWin = 0               -- >0：进关后第 N 秒自动过关（跑穿演出用）
M.devNear = 0              -- >0：进关时把玩家直接放到门前（验证过关链路用）

return M
