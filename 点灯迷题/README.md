# 点灯迷题（Lights Out）· 客户端 UI 工程

千星沙箱客户端 Lua 工程。**棋盘与玩法在服务器节点图里，本工程只做 UI**，
两边通过 4 条信号对接。行数固定 5、列数固定 6，共 50 关（前 5 关为教程关）。

---

## 一、分工与边界

| 归属 | 负责内容 |
|---|---|
| **本工程（客户端）** | 选关界面、图文教程、游玩期极简 HUD、胜利结算（带动效）、黑幕过渡、输入与信号收发 |
| **千星沙箱节点图（服务器）** | 3D 棋盘与点击交互、判定是否全部熄灭、按关卡号摆出初始盘面、进度与存档 |

客户端**不做任何棋盘计算**：它只把「关卡号 + 点位序列」发给节点图，等节点图回话。

---

## 二、交付物清单

| 文件 | 行数 | 说明 |
|---|---|---|
| `game.lua` | 533 | 入口：生命周期、**7 层容器**、`raiseLayers()`、键位、入站信号、场景切换 |
| `config.lua` | 566 | **参数唯一真源**（全部 `DEFAULT_*`）+ `M.LEVELS` 50 关数据 + 夏日配色 |
| `state.lua` | 192 | 集中托管所有 `state.*` 字段 |
| `utils.lua` | 288 | 控件/文本创建、配色解析、显隐透明度、**`createHit` 光标检测区工厂**、`bindHover` |
| `fx.lua` | 365 | **矩形粒子池 + 通用补间**（果汁迸溅 / 按钮弹动 / 缓动函数集） |
| `bg.lua` | 120 | **夏日背景**：天空带 + 海面 + 沙滩 + 波浪高光 + 上升气泡池 |
| `puzzle.lua` | 166 | 纯计算：一维下标 ↔ 行列、按下掩码、盘面推演（供校验用） |
| `signal.lua` | 204 | **与节点图唯一的对接面**（4 条信号 + 参数提取） |
| `menu.lua` | 544 | 选关界面：5×4/页 × 3 页、难度条、通关标记、翻页、卡片弹入 |
| `tutorial.lua` | 465 | 图文教程：5 页，基础图元真画出棋盘示意图，翻页左右滑动 |
| `hud.lua` | 213 | 游玩期 HUD：左上信息条 + 右下「教程 / 退出」，滑入 + 悬停放大 |
| `winUI.lua` | 385 | 胜利结算：**三星逐颗弹出（每颗迸溅果汁）** + 12 格跑马灯 + 3 按钮 |
| `audio.lua` | 53 | 音效（点击 / 开关 / 胜利） |
| `fadeScreen.lua` | 146 | 黑幕过渡，在 `onPeak` 里切场景 |
| `编辑器.html` | — | **可视化关卡编辑器**（离线可用，可改盘面 / 导出 Lua） |
| `_gen_levels.py` | 311 | 关卡数据生成器（可复现，纯标准库） |
| `_sync_editor_levels.py` | — | 把 `_levels.json` 内嵌进 `编辑器.html` |
| `_verify_levels.mjs` | 204 | 独立交叉校验（换一套 JS 实现复算 50 关） |
| `_export_sandbox.py` | — | **导出「千星沙箱导入包」**（含注入残留自检），见第五章 A.0 |
| `启动试玩.bat` | — | 双击起模拟器并打开本游戏试玩页（纯 ASCII，游戏名按文件夹名推导） |

> `_levels.json` 是生成器的中间产物，可随时重生成。
> `_sandbox/` 是 `_export_sandbox.py` 的产物（沙箱导入包），也在 `.gitignore` 里。

### ★ 分层模型（与 TickHop 一致：一层一容器）

真机上「控件被遮住 / 点不动」几乎都源于**多级子容器 + 渲染顺序**，本工程已按 TickHop 的做法重构：

- **只用 7 个平铺容器**，由 `game.lua` 的 `LAYER_ORDER` 从底到顶排列：
  `containerBg → containerHud → containerMenu → containerWin → containerTutorial → containerFx → containerFade`。
- **容器内部不再套子容器**（旧版 `XxxImage` / `XxxText` 二级容器已全部删除）——
  层级**完全靠创建顺序**：同一容器里**后创建的在上**（真实机）。
  因此每个组件的创建顺序一律是「**底图 → 文字 → 点击区域**」。
- 模拟器渲染器的同级顺序**与真机相反**（它是「先创建的在上」），
  所以 `game.lua` 每帧调 `raiseLayers()` 按 `LAYER_ORDER` 从底到顶逐层 `SetAsLastSibling()`
  （`SetAsLastSibling` 两引擎效果一致，是唯一可靠的提层手段）。
  **不要把 `SetSiblingIndex(i)` 当索引用** —— 它实际插到 `len-1-i`。
- 背景（`bg.lua`）与粒子（`fx.lua`）各占一层，**HUD / 菜单 / 教程 / 结算 / 黑幕固定屏幕坐标**，
  不受任何相机影响。

### ★ 自适应尺寸：界面随画布放大，卡片尺寸由「可用空间」反推

原来面板是**写死 700×500** 的，画布一大四周全是空白（真机 1600×900 上尤其明显）。
现在所有界面都按「比例 + 可用空间」算：

- **放大系数 `k`** = `面板高 / DEFAULT_SELECT_PANEL_H(500)`，夹在 `0.8 ~ 2.4`；
  标题 / 字号 / 按钮 / 图标全部乘 `k`。面板本身 = `画布 × RATIO`，再由 `MAX_W / MAX_H` 封顶。
- **画布尺寸**取自 `GetUICanvasSize()`（失败才回退 `DEFAULT_VIEW_WIDTH/HEIGHT`），
  存进 `state.canvasW/canvasH`；另有 `state.uiScale` 供粒子坐标换算。
- **选关网格不再写死卡片尺寸**：`卡片高 = (可用高 - 行距) / 行数`，
  可用高 = `面板高 × (1 - TOP_RATIO - BOTTOM_RATIO)`。
  - 卡片**矮于 `CARD_PREF_H` 就少一行**（舒适优先，但不会缩到 3 行以下）；
    再低于 `CARD_MIN_H`（硬下界，见下节）继续减行；**窄于 `CARD_MIN_W` 就少一列**。
  - 结果：1280×720 与 1600×900 **都是 5×3 = 15 关/页（共 4 页）**，
    卡片分别 156.9×104.2 与 177.3×123.2 —— 已用离线复算脚本逐一核对，**不越界、不重叠**。
- **教程 / 结算面板**用容器整体缩放（`containerTutorial` / `containerWin` 的 `SetLocalScale(k)`）；
  **这两层是居中的**，缩放不会跑偏。**HUD 是贴边布局、不能整体缩放**（会被推出屏外），
  HUD 的尺寸仍由自身的 `hud_*` 参数控制。
- ★ **粒子坐标要乘 `utils.uiScale()`**：`fx` 粒子挂在**不缩放的** `containerFx` 上，
  而调用点给的坐标常在**已缩放**的容器里 → 不换算就是「面板放大了、果汁还在原地爆」。

### ★★ 真机文本框有「最小高度」：盒子太矮一个字都不画

这是「选关界面文字被盖住」的真正根因 —— **不是** z 序，也不是遮罩。
对真机截图逐像素对账后发现：卡片内部是**一整块纯色、一个文字像素都没有**。
同一套代码里：

| 文本框高度 | 真机表现 |
|---|---|
| 56 / 54 / 30 px | **正常显示** |
| 26 / 22 px（卡片关卡名 / 难度行 / 页脚） | **完全空白** |

文本框预制体有个下限，**低于它整段文字都不绘制**；而模拟器照画不误
（又一个「模拟器对、真机错」）。修复：`utils.createText` 把每个盒子高度兜到
**`MIN_TEXT_H = 36`** 以上，并显式 `adaptiveFontSize = false`
（预制体若开了字号自适应，矮盒子会把字号一路缩到画不出来）。

> `MIN_TEXT_H` 已暴露为 `utils.MIN_TEXT_H`：布局模块必须按**兜高后的盒子**排版，
> 否则会出现「按自己给的高度排的版、实际盒子被撑高后和隔壁打架」。
> `menu.lua` 的难度条 y 就是这么取的 —— 在 `-0.44h` 与「步数行盒子下沿再留 2」
> 之间取更靠下的一个。

> 结论：**卡片高度不是「好看就行」，而是有硬下界** —— 底边至少要容得下两行 36px 文本框，
> 故 `CARD_MIN_H = 84`（≈ 两行 36 + 间距 + 难度条）。

### ★ 游玩期要把夏日背景收起来

`bg.lua` 是一整块**不透明**、盖满画布的夏日底色。它虽然在最底层，
但**不透明 = 照样把 3D 棋盘盖住**（真机就是「进了关还是一片沙滩」）。
修复：`game.setScreen` 里一句 `bg.setVisible(name ~= "play")` ——
**选关 / 教程 / 结算显示背景，游玩期收起**，画面让给 3D。

### ★ 为什么所有可点区域必须用「光标检测区域」元件

这是本次「按钮全部点不动」的**根因**：`AddCursorEventListener`（鼠标 / 触摸事件）
**只挂在 `ClientUIPresetButtonControl`（预设按钮）和 `ClientUICursorEventAreaControl`（光标检测区域）上**，
`ClientUIImageControl`（图片控件）**没有**这个 API —— 代码里用 `pcall` 包着，
调用失败会被**静默吞掉**，于是「按钮画得出来、就是点不动」。

为此新增脚本参数 **`cursorPrefabId`（必填）**：一个「光标检测区域」元件模板。
`utils.createHit(x, y, w, h, parent, onDown, fallback)` 用它生成透明点击区；
所有可点元素（选关卡片 / 翻页箭头 / 三个主按钮 / HUD 两个按钮 / 结算三按钮 / 教程三按钮）
都走这个工厂。**不配这个参数 → 鼠标点击全部失效**（`utils` 会打一次警告）。

> 「光标检测区域」模板建议**无底图 / 或底图全透明**。
> `createHit` 会主动把它的 `imageColor` 置成全透明（逐属性 `pcall`，不会被其它字段带崩）。

### 夏日视觉与动效一览

| 位置 | 效果 |
|---|---|
| 背景 `bg.lua` | 天空带 → 海面 → 沙滩 → 4 条波浪高光 → 两团柔光 → 14 颗上升气泡（含粉色花瓣泡） |
| 选关 `menu.lua` | 面板带橙色描边 + 顶带，卡片逐张**弹出**（`pop` 缓动），难度条逐格充能，翻页滑动 |
| 教程 `tutorial.lua` | 面板描边 + 翻页时构图**左右滑动**，换页迸溅果汁 |
| HUD `hud.lua` | 信息条与按钮**滑入**，悬停放大 1.07 倍并下沉 3px，按下迸溅果汁 |
| 结算 `winUI.lua` | **三颗 ★ 逐颗弹出**（超出到 1.55 倍再回落，每颗弹出瞬间迸溅一把果汁）→ 星下 12 格跑马灯开始走灯 |
| 通用 | `fx.lua` 提供矩形粒子池 + 补间（`linear/out/in/back/elastic`），全部由**纯色矩形**拼出，无贴图依赖 |

---

## 三、关卡数据格式

棋盘：**5 行 × 6 列 = 30 格**。一维下标 **从 0 记**，`idx = 行 * 6 + 列`
（行从上往下 `0..4`，列从左往右 `0..5`）。

按下 `idx` 会**同时翻转它自己 + 上下左右四个邻居**（越界忽略）；目标是让 30 盏灯全部熄灭。

```lua
{
    name  = "第01关",
    steps = 1,          -- = #flips，即本关难度（最少需要按几次）
    tip   = "点一格，连上下左右一起翻转",   -- 仅教程关有；HUD 显示用，≤14 汉字
    flips = {19},       -- ★ 点位序列：0 基下标数组，就是本关的（唯一）最优解
}
```

**`flips` 的语义（关键约定）**：它是**解法序列** —— 在「全灭盘面」上依次按下 `flips` 里的每一格，
得到的就是本关的**初始盘面**。所以节点图摆盘面时：

```
board = 全灭
for idx in flips:  board 翻转 (idx 及其上下左右)
```

反过来，玩家在游戏里只要把 `flips` 里的格子各按一次，就必然全灭通关。

> 为什么可以直接把解法当数据用：**5×6 的点灯棋盘是满秩的（核空间维数 = 0）**，
> 即每个盘面的解唯一且必为最优解（`_gen_levels.py` 与 `_verify_levels.mjs` 都独立复算确认）。

**难度曲线**（`steps`）：

```
1 2 3 4 5  5 5 5 6 6 6 6 6 6 7 7 7 7 7 7 7 8 8 8 8 8 8
9 9 9 9 9 9 10 10 10 10 10 10 10 11 11 11 11 11 11 12 12 12 12
```

前 5 关为教程关（`tip` 有值，1→5 步逐步引入）；之后按用户要求平滑递增到 12。

---

## 四、★ 信号协议（客户端 ↔ 节点图）

> 全部信号名与发送逻辑集中在 `signal.lua`，改名字只动 `signal.lua` 顶部的常量即可。

### 4.1 出站 · 客户端 → 服务器（2 条）

| # | 信号名 | 参数（按顺序） | 客户端发出时机 |
|---|---|---|---|
| ① | **`进入关卡`** | `AddInt` 关卡号（**从 1 记**）<br>`AddIntList` 点位序列（0 基下标数组） | 玩家在选关界面点卡片 / 按空格 / 点「进入关卡 →」；黑幕盖住屏幕后发出 |
| ② | **`重玩本关`** | 同上（参数完全一致） | 玩家在结算面板点「重玩本关」/ 按 `R`；黑幕盖住屏幕后发出 |

两条信号参数一致，**节点图可以复用同一个处理逻辑**；若「重玩本关」只需关卡号，忽略第 2 个参数即可。

节点图侧建议：

```
收到「进入关卡」(levelIndex, flips) →
    1) 清空当前棋盘
    2) board = 全灭；for i in flips: 翻转 (i 及其上下左右)
    3) 用 levelIndex 布置 3D 场景 / 计时 / 提示
    4) 一切就绪后，回发「让客户端进入关卡」(levelIndex)

收到「重玩本关」(levelIndex, flips) → 同 1)~2)，然后回发「让客户端进入关卡」
```

### 4.2 入站 · 服务器 → 客户端（2 条）

| # | 信号名 | 参数（按顺序） | 客户端动作 |
|---|---|---|---|
| ③ | **`让客户端进入关卡`** | `AddInt` 关卡号（**可选**，从 1 记） | 收掉教程/结算覆盖层 → 切到游玩 HUD → 清掉「正在加载关卡…」提示 |
| ④ | **`关卡胜利`** | `AddInt` 关卡号（**可选**，从 1 记） | 记通关 → 放胜利音效 → 弹出结算面板（带入场动效 + 跑马灯） |

- 关卡号**省略或不合法**时，客户端回退用「当前所在关卡号」，所以最简用法就是不带参数发空信号。
- 判定由服务器做：**3D 端确认全部熄灭后**再发 `关卡胜利`，客户端不猜。

### 4.3 一次完整进关的时序

```
玩家点卡片
   └─ 客户端：黑幕渐显 → 切到游玩画面 → 发「进入关卡」(关卡号, 点位序列)
        └─ 节点图：按点位序列摆出初始盘面 + 布置 3D 场景
             └─ 节点图：发「让客户端进入关卡」(关卡号)
                  └─ 客户端：HUD 提示由「正在加载关卡…」变为难度/提示行，可以开始操作
                       └─ 玩家把灯全部熄灭
                            └─ 节点图：发「关卡胜利」(关卡号)
                                 └─ 客户端：弹结算面板（重玩本关 / 下一关 / 返回选关）
```

### 4.4 参数读取（客户端侧已做兼容）

`signal.getIntParam(params, i)` / `getIntListParam` / `getStringParam` 同时兼容
「整包即标量」「Lua 数组」「数字字符串」「带 Get/Count 的 userdata」四种形态，
节点图怎么包都不会读崩。

---

## 五、★ 需要在千星沙箱补全的内容

### A. 必做（否则客户端起不来）

0. **导入 14 个脚本**（★ 别用模拟器导出的版本）

   先跑一次导出器，得到干净的导入包：

   ```bash
   python 点灯迷题/_export_sandbox.py
   ```

   把 `点灯迷题/_sandbox/default_import_file/` 下的 **14 个 `.lua`** 全部导入沙箱。
   文件必须落在 `default_import_file/` 下 —— 工程里写的是
   `require("default_import_file/config")`，路径不对会报 `failed to load script`。
   导入清单见 `点灯迷题/_sandbox/导入清单.md`。

   > ⚠️ **不要**把「模拟器试玩存档」里导出的脚本拿去挂沙箱。
   > `_tools/qxqy_websave.mjs` 为了让浏览器试玩能跑，会给**入口脚本**追加一段
   > **模拟器专属补丁**（参数兜底 + TickHop 专用 z 序修正，合计 116 行）。
   > 它在真机上会每帧抛错：
   >
   > ```
   > default_import_file/game:614: table index is nil
   > stack traceback:
   >     default_import_file/game:614: in function 'OnUpdate'
   > ```
   >
   > 第 614 行正是 `isMine[c.Id] = true` —— 真机控件没有 `Id` 字段；
   > 而且那段用的 `containerPlayer` / `containerPlatform` 是 TickHop 的容器名。
   >
   > **一眼判据**：本目录的 `game.lua` 是 **533 行**；被污染的那份会多出**上百行**模拟器补丁。
   > `_export_sandbox.py` 已内置这项自检（含 `[SIM_ONLY]` / `[SIM_ZFIX]` 等痕迹扫描）。

1. **控件容器 + 挂脚本**
   `game.lua` 挂在一个 **「客户端控件容器」节点**上（代码会读 `script.object` 作父节点）。
   若报 `script.object 为 nil`，就是这个节点没配对。

2. **三个控件模板（脚本参数）**

   | 参数名 | 必填 | 元件类型 | 用途 |
   |---|---|---|---|
   | `rectPrefabId` | **是** | 图片（纯色矩形） | 面板 / 遮罩 / 卡片 / 按钮 / 灯格 / 粒子 / 背景**全部**由它染色而来 |
   | `textPrefabId` | 否 | 文本 | 不填则界面只剩色块、没有文字 |
   | `cursorPrefabId` | **是** | **光标检测区域** | 所有可点区域的点击判定。**不配 → 鼠标点不动任何按钮**（详见第二章末） |

   - **矩形模板**用**纯白**底图（客户端用 `imageColor` 染色），且 **不要带遮罩**。
   - **文本模板**必须支持 `text` / `fontSize` / `fontColor` / `bgColor` 四个字段
     （`bgColor` 客户端会主动置透明，避免真机上文本块变成实心色块盖住下方内容）。
   - **光标检测区域模板**：底图留空或全透明即可，尺寸会被 `createHit` 逐次改写。

3. **节点图侧实现 4 条信号的收发**（见第四节）。信号名必须与 `signal.lua` 完全一致：
   `进入关卡` / `重玩本关` / `让客户端进入关卡` / `关卡胜利`。

4. **3D 棋盘与点击交互**：30 格的翻转规则、全灭判定、通关后发 `关卡胜利`。

### B. 按需（不填也不报错）

| 参数名 | 用途 |
|---|---|
| `clickAudioId` | 界面点击音 |
| `openAudioId` | 进入关卡 / 打开面板音 |
| `winAudioId` | 通关音 |

### C. 需要节点图/会话负责的状态

- **`已通关 N 关`**：客户端只在**本次会话内**记忆通关（`state.clearedLevels`），
  重启后从 0 开始。若要做**持久进度**，得由节点图把自己记录的通关关卡号回传给客户端。
  目前没有这条信号 —— 需要的话告诉我，我加一条入站 `同步进度`（`AddIntList` 已通关列表）。

---

## 六、客户端脚本参数一览

| 参数 | 类型 | 必填 | 默认 | 说明 |
|---|---|---|---|---|
| `rectPrefabId` | number | **是** | 0 | 纯色矩形底图元件 ID（面板 / 粒子 / 背景全靠它） |
| `cursorPrefabId` | number | **是** | 0 | **「光标检测区域」元件 ID**；不填则所有鼠标点击失效 |
| `textPrefabId` | number | 否 | 0 | 文本元件 ID（不填只有色块没有字） |
| `clickAudioId` | number | 否 | 0 | 点击音 |
| `openAudioId` | number | 否 | 0 | 打开 / 进关音 |
| `winAudioId` | number | 否 | 0 | 通关音 |

所有可调参数（面板尺寸、字号、卡片间距、动效时长、粒子数量、夏日配色…）都在 `config.lua` 的
`DEFAULT_*` 里，**改那一个文件就够**；`编辑器.html` 的 `DEFAULTS` 必须同步（有校验器兜底）。
本次新增的可调项：

| 前缀 | 用途 |
|---|---|
| `bg_*` | 夏日背景：天空带高 / 沙滩带高 / 波浪条数·透明度 / 气泡数量·速度·边长·透明度 |
| `fx_*` | 粒子：单次数量 / 存活 / 速度 / 张角 / 重力 / 边长 / 阻尼 |
| `anim_*` | 通用动效：弹出时长 / 滑入时长 / 悬停放大 / 按下下沉 |
| `win_star_*` | 三星：边长 / 间距 / 高度 / 逐颗间隔 / 每颗迸溅粒子数 |
| `select_*` | 选关自适应：面板 `RATIO`/`MAX`、网格占宽 `GRID_W_RATIO`、上下留白 `GRID_TOP/BOTTOM_RATIO`、卡片 `CARD_MIN_W/CARD_MIN_H/CARD_PREF_H`、行×列、间距、翻页箭头与底部按钮尺寸 |
| `*_overlay_alpha` | 三个面板的遮罩浓度（选关 140 / 教程 165 / 结算 130） |

> ★ `select_card_w/h` 现在只是**参数表基准**（尺寸由可用空间反推），
> 真正决定观感的是 `select_panel_*_ratio / max_*`、`select_grid_*_ratio` 与
> `select_card_min_* / select_card_pref_h`。

---

## 七、操作说明

| 场景 | 键 / 操作 |
|---|---|
| 选关 | `← → ↑ ↓`（或 A/D/W/S）移动光标（左右循环、上下到边界停住）、`空格`/`W` 进入、`T` 打开教程、点击卡片直接进入 |
| 教程 | `← →` 翻页、`空格` 下一页、`T` / `L` 关闭 |
| 游玩 | `T` 教程、`R` 重玩本关、`L` 返回选关；**方向键与空格刻意不占用**，留给 3D 玩法 |
| 结算 | `空格`/`W` 下一关、`R` 重玩本关、`L` 返回选关，或直接点按钮 |

> 三个功能键（`R`/`T`/`L`）**绕过** UI 总开关：面板关不掉、游玩期回不去的问题不会发生。
> 键盘事件回调用「返回值」表示是否消费按键 —— 游玩期按方向键不会被 UI 吞掉。

---

## 八、关卡编辑器（`编辑器.html`）

双击用浏览器打开，**完全离线**，与 `puzzle.lua` 同构的 JS 棋盘模型 + GF(2) 高斯消元。

- 点格子 → 增 / 删该格在解序列里的位置（格内显示**按下顺序 + 0 基下标**）
- 实时难度条 + 校验徽标：`✔ 解正确且最优` / `✘`（点一下可一键改为最优解）
- 「随机生成」「求最优解」「清空」「复制解序列」「导入 / 导出」
- 顶部 `const INIT_LEVELS` 内嵌了 50 关，改完用「导出」覆盖 `config.lua` 的 `M.LEVELS` 区段

**改完关卡的标准流程**（保证三处数据不漂移）：

```bash
python _gen_levels.py --write config.lua --json _levels.json   # 真源：config.lua 标记区
python _sync_editor_levels.py                                  # 同步进 编辑器.html 内嵌
node   _verify_levels.mjs                                      # 交叉校验：一致 + 最优 + 单调
```

---

## 九、本地校验与模拟器验证

在工作区根目录（`E:\千星\千星游戏`）执行：

```bash
# 1) 静态校验（看退出码）
python _shared/_check_blocks.py 点灯迷题      # 词法级块平衡
python _shared/_check_refs.py 点灯迷题        # require / 模块函数 / state 字段 / DEFAULTS 同步

cd 点灯迷题
node _verify_levels.mjs                        # 50 关：数据一致 / 解最优唯一 / 盘面唯一 / 难度单调 / 导出导入无损
python _export_sandbox.py --check              # 沙箱导入包自检：无模拟器注入残留 + require 前缀齐全
```

模拟器端到端（无头，会出截图到 `_simulator/shots/`）：

```bash
cd E:/千星/千星游戏

# 首次 / 改完工程后：重造「模拟器就绪」存档
node _tools/qxqy_mount.mjs --game 点灯迷题 --entry game.lua --steps 1 --save _simulator/deng.save.json
node _tools/qxqy_simsave.mjs --src _simulator/deng.save.json --out _simulator/deng.sim-ready.save.json

# ★ 模拟器里没有「光标检测区域」模板，就复用图片模板 2000001 顶上（真机必须用真的光标检测区域）
P='{"rectPrefabId":2000001,"textPrefabId":2000002,"cursorPrefabId":2000001}'

# 选关界面（L 关掉自动弹出的教程）
node _tools/qxqy_mount.mjs --game 点灯迷题 --entry game.lua \
     --open _simulator/deng.sim-ready.save.json --preset sim --steps 60 --params "$P" \
     --key KeyboardCraftspersonKey21Down@10

# ★ 换画布验证「自适应布局」：--canvas 取 pc-16-9(1600×900) / mobile-16-9(1280×720) …
node _tools/qxqy_mount.mjs --game 点灯迷题 --entry game.lua \
     --open _simulator/deng.sim-ready.save.json --preset sim --canvas pc-16-9 --steps 60 --params "$P" \
     --key KeyboardCraftspersonKey21Down@10

# ★ 通关标记：先下发「关卡胜利」把第 12 关记成已通关，再按 L 返回选关看绿色卡片
node _tools/qxqy_mount.mjs --game 点灯迷题 --entry game.lua \
     --open _simulator/deng.sim-ready.save.json --preset sim --steps 50 --params "$P" \
     --signal 关卡胜利 --signal-str 12 --signal-at 5 --key KeyboardCraftspersonKey21Down@28

# 出站信号：进入关卡 / 重玩本关（看输出里的 inbound 列表）
node _tools/qxqy_mount.mjs --game 点灯迷题 --entry game.lua \
     --open _simulator/deng.sim-ready.save.json --preset sim --steps 80 --params "$P" \
     --key KeyboardCraftspersonKey21Down@10 --key KeyboardJumpKeyDown@10 \
     --key KeyboardCharacterSkill3KeyDown@55

# 入站信号：让客户端进入关卡 → 游玩 HUD
node _tools/qxqy_mount.mjs --game 点灯迷题 --entry game.lua \
     --open _simulator/deng.sim-ready.save.json --preset sim --steps 15 --params "$P" \
     --signal 让客户端进入关卡 --signal-str 1 --steps-after 6

# 入站信号：关卡胜利 → 三星结算面板（--steps-after 12 抓「星星逐颗弹出」的中间帧，
#                                        20+ 抓稳定态）
node _tools/qxqy_mount.mjs --game 点灯迷题 --entry game.lua \
     --open _simulator/deng.sim-ready.save.json --preset sim --steps 12 --params "$P" \
     --signal 关卡胜利 --signal-str 12 --steps-after 12
```

> `_tools/qxqy_mount.mjs` 为本工程扩了四个开关（不影响 TickHop）：
> `--key 名字@帧`（逐键指定帧）、`--signal-at <帧>`（边推进边下发信号，之后还能注入按键）、
> `--steps-after <n>`（信号后继续推进，观察动效稳定态）、
> `--canvas <预设 id>`（切换画布尺寸，用来验证自适应布局）；
> 收尾还会打印服务器侧的收发信号记录。

---

## 十、已知限制 / 可选扩展

1. **通关进度不持久**：见第五节 C。需要持久化就加一条入站 `同步进度`。
2. **结算面板的「下一关」直接发 `进入关卡`**：不经过选关界面，也不会自动标记当前关已通关
   （标记由 `关卡胜利` 完成）。若希望「点下一关也算通关」，得由节点图补发 `关卡胜利`。
3. **`flips` 只按「解法序列」用**：盘面上的初始灯态由节点图推演得出。若节点图想直接拿到
   **初始亮灯列表**，`_levels.json` 里每关都带 `board` 字段（亮灯下标数组），也可以加进信号。
4. **字体**：界面只用中文字体确实有字形的符号（`√ ← → ↑ · ★ ◆`）。
   新增符号前先跑 `node _tools/glyph_check.mjs`，`◀ ▶ ✓` 会渲染成豆腐块。
5. **选关默认 15 关/页（共 4 页）**：这是「卡片要放得下两行 36px 文本框」的必然结果。
   想回到 20 关/页（3 页），把 `select_card_pref_h` 调到 84 以下即可 ——
   代价是 1600×900 上两行文字会贴得很近（框间隙只剩 1.7）。
6. **极小画布会自动减列**：`GetUICanvasSize` 失败时按 800×600 兜底，
   此时网格会退成 4 列 × 3 行（12 关/页），这是刻意为之 ——
   宁可多分一页，也不让卡片窄到文字被截。
7. **尺寸改了要同步的地方**：`menu.lua` 的版式常量（卡片内 `±0.24h / -0.18h / -0.44h` 等）
   与 `utils.MIN_TEXT_H` 是**耦合**的 —— 改卡片版式后请重跑
   `_simulator/diag/layout_check.py`（离线复算多种画布，直接报「越界 / 重叠」）。
