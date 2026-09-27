# TickHop（滴答咔哒）· 千星奇域复刻

时间解谜平台跳跃。倒计时在走，绑定了秒数的平台只在对应的那一秒是实心的。

> 完整设计说明见 **[实现方案.md](./实现方案.md)**；本文只讲怎么跑起来、怎么改。

---

## 一、文件说明

| 文件 | 作用 |
|---|---|
| `game.lua` | **入口脚本**。生命周期、层级容器、关卡加载、输入绑定、信号注册 |
| `config.lua` | **参数真源**。全部 `DEFAULT_*` 可调参数 + `LEVELS` 关卡数据 |
| `state.lua` | 运行时状态集中声明 |
| `timeSystem.lua` | 时间内核：倒计时 / tick / 加时 / 反转 |
| `level.lua` | 关卡构建与平台实体状态刷新 |
| `menu.lua` | **选关 / 通关 / 失败**三态面板（复用同一批控件） |
| `physics.lua` | 玩家 AABB 运动与平台碰撞 |
| `utils.lua` | 控件创建、配色解析、AABB、HUD 文本 |
| `audio.lua` | 音效 |
| `signal.lua` | 出站事件 + 入站监听 |
| `fadeScreen.lua` | 关卡切换黑幕过渡 |
| `编辑器.html` | **关卡编辑器**（双击打开，零依赖） |

---

## 二、在千星沙箱里装配

1. 新建「客户端控件容器」，把 `game.lua` 挂到容器节点上。
2. 依次粘贴其余 `.lua` 模块。
3. 在脚本参数里填元件 ID：

| 参数名 | 必填 | 说明 |
|---|---|---|
| `rectPrefabId` | ✅ | 纯色矩形底图元件（游戏会染色用于背景/平台/玩家/门/道具） |
| `textPrefabId` | 建议 | 文本控件元件（倒计时 / 平台秒数 / 提示） |
| `playerPrefabId` | ✕ | 玩家外观，缺省回退 `rectPrefabId` |
| `goalPrefabId` | ✕ | 门的外观，缺省回退 `rectPrefabId` |
| `jumpAudioId` / `landAudioId` / `switchAudioId` | ✕ | 跳跃 / 落地 / 平台切换音效 |
| `pickupAudioId` / `winAudioId` / `failAudioId` | ✕ | 拾取 / 过关 / 失败音效 |

> ⚠️ 参数名后缀 `PrefabId` / `AudioId` **不能改**，否则 `script:GetParam` 读不到。

4. 运行。

---

## 三、操作

### 玩法键

| 端 | 操作 |
|---|---|
| 键鼠 | `A`/`←` 左，`D`/`→` 右，`空格`/`W`/`↑` 跳 |
| 触屏 | 左下 `← →`，右下「跳」——设备为移动端时自动创建 |

跳跃支持**土狼时间**（离地 0.1s 内仍可跳）与**跳跃缓冲**（落地前 0.12s 按跳也生效），并按按键时长决定跳跃高度。

### 面板键

面板键**始终生效**（不受「按键绑定总开关」影响），保证面板永远关得掉：

| 键 | 作用 |
|---|---|
| `L` | 开 / 关**选关菜单**（同时上报「选择关卡」信号） |
| `←` `→` | 菜单打开时移动光标 |
| `空格` / `W` | 菜单打开时确认（选关 / 点按钮） |
| `R` | 重玩本关 |
| `T` | 下一关（调试） |
| `P` | 上一关（调试） |

> `R`/`T` 在选关面板打开时让位给面板按钮；`P` 在任意面板打开时不响应。

触屏端额外在左上角常驻一个「关」按钮，点它打开选关菜单（面板内所有卡片与按钮均可点）。

---

## 三·五、选关与结算面板

`menu.lua` 用**一批一次性创建的控件**承担三种状态，切换时只改文字与显隐，不销毁重建：

| 状态 | 何时出现 | 内容 |
|---|---|---|
| `select` | 按 `L` | 关卡卡片网格（3 列 × 2 行，超出自动分页）+ 左右翻页箭头 + 底部按钮 |
| `win` | 走到终点（`AUTO_WIN=1` 时自动弹） | 「关卡完成！」+ 剩余时间 + `重玩本关` / `下一关 →` |
| `fail` | 倒计时归零 | 「时间到！」+ 失败原因 + `重玩本关` / `返回选关` |

- **卡片标记**：已通关关卡名后带 `√`；当前关为暗色（`dim`），光标所在卡片高亮为 `accent` 色。
- **最后一关通关**时没有下一关，「下一关 →」自动变「返回选关」。
- **字形选择**：界面只用中文字体必然覆盖的符号（`← → √ ★ ·`）。
  `◀ ▶ ✓`（U+25C0/U+25B6/U+2713）在雅黑/宋体/黑体里**都没有字形**，会渲染成豆腐块，已全部替换。
- **暂停**：面板打开即 `state.paused = true`，计时、物理、拾取、结束判定全部冻结；黑幕与 HUD 仍每帧推进。
- **进度**：`state.clearedLevels` 记录本次运行内已通关的关卡（不落盘，重开游戏即清空）。
- **解耦**：`menu.lua` 不 `require("game")`，靠 `game.lua` 在 `OnStart` 里调
  `menu.setActions({ onSelect = loadLevel, onReload = reloadLevel, onNext = nextLevel })` 注入回调，避免循环依赖。

面板全部尺寸/配色走 `config.lua` 的 `menu_*` 参数与 `DEFAULT_PALETTE` 里的
`overlay` / `panel` / `card` / `panelText` / `accent` / `accentText` / `dim` / `clear`。

---

## 四、改关卡

### 方式 A：用编辑器（推荐）

双击 `编辑器.html`：

1. 顶部切到要改的关卡，或「新建」
2. 左栏选工具 → 画布点击放置 → 拖动调整
3. **拖动顶部「秒数预览」滑块**，检查每一秒平台的亮/暗是否符合设计
4. 右栏改数值，点「导出」→ 复制
5. 粘贴覆盖 `config.lua` 里的 `M.LEVELS = { ... }`

「导入」可以反向把 `config.lua` 的 `LEVELS` 贴回来继续编辑。

### 方式 B：直接改 `config.lua`

```lua
{
    name = "第01关",
    time = 12.00,                                  -- 倒计时初始值（秒）
    spawn = {x = -300, y = -180},                  -- 玩家出生点
    goal  = {x = 200, y = -100, width = 56, height = 84},
    platforms = {
        {x = -200, y = -240, width = 420, height = 24, tick = -1},  -- -1 = 永驻平台
        {x = 180,  y = -160, width = 150, height = 22, tick = 4},   -- 第 4 秒亮起
    },
    pickups = {
        {x = -120, y = -80, type = "time",    value = 4.00},        -- 加时 4 秒
        {x = 40,   y = 10,  type = "reverse", value = 0},           -- 时间反转
    },
    texts = {
        {x = -140, y = 120, text = "平台上的数字 = 它会亮起的秒数"},
    },
}
```

坐标原点在画布中心，**Y 轴向上为正**。

---

## 五、改参数

所有可调参数都在 `config.lua` 的 `DEFAULT_*` 里，改了立即生效：

| 想调什么 | 改哪个 |
|---|---|
| 跳跃手感（跳多高、落多快） | `DEFAULT_JUMP_SPEED` / `DEFAULT_GRAVITY` / `DEFAULT_FALL_GRAVITY_MULT` |
| 移动手感（加速、惯性） | `DEFAULT_MOVE_SPEED` / `DEFAULT_GROUND_ACCEL` / `DEFAULT_AIR_ACCEL` |
| 操作宽容度 | `DEFAULT_COYOTE_TIME` / `DEFAULT_JUMP_BUFFER_TIME` |
| 平台虚化的可见程度 | `DEFAULT_PLATFORM_GHOST_ALPHA` |
| 整体配色 | `DEFAULT_PALETTE`（或单关 `palette` 覆盖） |
| 关卡切换黑幕时长 | `DEFAULT_FADE_IN_TIME` / `HOLD_TIME` / `OUT_TIME` |
| 面板尺寸与字号 | `DEFAULT_MENU_PANEL_W` / `PANEL_H` / `TITLE_SIZE` / `BTN_*` |
| 选关卡片布局 | `DEFAULT_MENU_CARD_W` / `CARD_H` / `CARD_GAP_X` / `CARD_GAP_Y` / `COLS` / `ROWS` |
| 到达终点自动弹窗 | `DEFAULT_MENU_AUTO_WIN`（0 = 关闭，需按 `L` 手动） |

> ⚠️ **改了 `config.lua` 的 `DEFAULT_*`，必须同步改 `编辑器.html` 顶部 `DEFAULTS` 里同名项**（key 大写即常量名）。校验脚本会检查两者是否一致。

---

## 六、静态校验

在**工作区根**执行（或在 `_shared/` 下把 `TickHop` 换成 `../TickHop`）：

```bash
python _shared/_check_blocks.py TickHop      # Lua 块平衡（function/if/for/while vs end）
python _shared/_check_refs.py  TickHop       # require 存在性 / 模块调用 / state / config / DEFAULTS 同步
python _shared/_check_editor_roundtrip.js    # 编辑器导出→解析无损
```

当前状态：**11 个文件块平衡 0 错误，引用一致性 0 问题，65 项参数全部同步，编辑器往返 PASS。**
（判定看**退出码**：两个 Python 脚本在成功时也会打印「0 处不一致」，退出码 0 才算通过。）

### 模拟器端到端验证（可选）

装了千星模拟器时，可跑面板的功能回归：

```bash
node _tools/verify_menu.mjs        # 8 场景 / 17 项检查：开选关、计时冻结、超时失败、通关弹窗、切关、进度记录
node _tools/render_scene.mjs       # 把场景矢量节点渲染成 PNG，用于核对面板布局
```

---

## 七、事件约定

| 方向 | 信号名 | 参数 |
|---|---|---|
| 出站 | `客户端事件` | `"到达终点"` / `"游戏失败"` / `"重置关卡"` / `"进入下一关"` / `"进入上一关"` / `"选择关卡"` |
| 出站 | `关卡胜利` | 关卡序号、剩余时间百分秒 |
| 入站 | `进入关卡` | 整数关卡序号（兼容 0 起始，自动 +1） |

---

## 八、扩展新机关

新机关一律走这两个落点，保持改动局部化：

- **随时间/条件切换实体状态** → 加进 `level.lua` 的 `refreshPlatforms()`，共用 `state.timeTick`
- **玩家碰到就发生的事** → 加进 `physics.lua` 的碰撞分支

可扩展清单（弹簧、移动平台、消失砖、时间门、钥匙等）见 `实现方案.md` 第十一节。
