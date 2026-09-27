# 千星奇域小游戏工作区 · 长期记忆

> 工具细节看 `_tools/README.md`；引擎 API 唯一权威来源是 `_shared/Lua 客户端 UI 脚本 API.md`。

## 目录（按游戏隔离）
`_shared/` 公共层（API 文档、miliastra_lib.lua 类型桩、三个校验器）；`割绳子/`、`TickHop/`
各自自包含全部 `.lua` + `编辑器.html`；`_tools/`（模拟器+驱动）与 `_simulator/`（存档截图）**非交付物**。

## 静态校验（无 Lua 解释器，用 Python；在工作区根执行）
- `python _shared/_check_blocks.py TickHop` —— 词法级块平衡（自动排除 miliastra_lib.lua）
- `python _shared/_check_refs.py TickHop` —— require 目标存在 / `mod.fn()` 已定义 / `state.x` 已声明 /
  `config.<大写常量>` 已定义 / **编辑器 DEFAULTS ↔ config DEFAULT_\* 逐项同步**
- `node _shared/_check_editor_roundtrip.js` —— TickHop「导出→解析」无损（含 labelGhost）
- 编辑器内嵌 JS：抽出 `<script>` 后 `node --check`
- **判定看退出码，不看文案**（refs 成功时也打印“0 处不一致”）

## 参数真源
`config.lua` 的 `DEFAULT_*` 是唯一真源，`编辑器.html` 的 `DEFAULTS` 必须逐项一致（key 大写即常量名，
历史特例由 `_check_refs.py` 内 `SPECIAL` 表兜底）；改一处必须同步另一处。
`state.lua` 必须显式声明所有 `state.*` 字段。

## TickHop（时间状态机 + AABB 平台跳跃）
- 模块：game / config / state / timeSystem / level / **menu** / physics / utils / audio / signal / fadeScreen
- `state.timeTick = floor(now)`；平台 `tick == timeTick` 或 `tick == -1`（永驻）为实体，否则虚化不可碰撞。
  **只改颜色 alpha，不销毁重建控件**。
- 坐标：原点在画布中心、**Y 向上为正**、坐标为**中心点**；编辑器与运行时同一套。
- **8 层容器**：bg → platform → goal → pickup → player → hud → **menu** → fade
  （menu 压 HUD、在黑幕之下）。
- 黑幕后重建关卡时先 `setRunning(false)` + `pendingStart = true`，等黑幕散尽再计时。
- 编辑器顶部**秒数预览滑块**（验证时间窗可行性的核心工具）。
- 脚本变量 `rectPrefabId`(必填) / `textPrefabId` / 各 `*AudioId` —— **后缀不能改名**。
- 扩展落点：随时间/条件切实体 → `level.refreshPlatforms()`；碰到才发生的事 → `physics.step()`。
- **标签两态反色**：实体→`palette.label`（深）压亮平台；虚化→`palette.labelGhost`（浅）+
  `DEFAULT_PLATFORM_LABEL_GHOST_ALPHA`(130) 压暗平台。文本框改字色**必须用 `fontColor`**。
- 关卡导出落盘：`node _tools/apply_levels.mjs TickHop.levels.lua`（大括号配平替换 + 自动校验）。

### 选关 / 结算面板（`menu.lua`）
- **一批控件扛三态**（`select` 选关 / `win` 通关 / `fail` 失败），只改文字 + `SetActive`，切换零分配。
  卡片含 `√` 通关标记；光标 `accent` 高亮、当前关 `dim`；末关通关时「下一关 →」自动变「返回选关」。
- 分页 `gridLayout()` 由 `COLS × ROWS` 推 `perPage/pages`，两侧 `← →` 方形箭头。
  `state.menuCursor` 存**可玩关序号**（非页内下标），跨页自动 `setPage` → 光标与页码永远自洽。
- **暂停**：`open()` 置 `state.paused=true`；`OnUpdate` 首行早退（只跑 `updateTimerDisplay` + `fadeScreen.update`）
  → 冻玩法但黑幕/HUD 仍推进。
- **输入三类**：`bindPair`（玩法，`menuOpen`/`keysEnabled` 拦截）/ `bindMenuKey`（`←→` 光标、`空格` 确认，
  仅 `menuOpen` 生效）/ `bindGlobal`（`R`/`T`/`P`/`L`，**绕过 `keysEnabled`**）。
  ★ `L` 必须绕开总开关，否则面板打开后关不掉。
- **解耦**：`menu.lua` 不 require `game`，由 `OnStart` 注入 `menu.setActions({onSelect,onReload,onNext})`。
- 参数 21 项 `DEFAULT_MENU_*` + 配色 `overlay/panel/card/panelText/accent/accentText/dim/clear`。
- 端到端回归：`node _tools/verify_menu.mjs`（8 场景 17 项）；
  截图核对：`node _tools/render_scene.mjs --scenario select|win|fail|cleared`。

### 原版对照（详见 `TickHop/原版对照.md`）
- 原版 = **《滴答咔哒 / Tick Hop》Steam AppID 3419780**；素材在 `_simulator/orig/`。
- 换算：`world_x = (px-639.5)*0.625`，`world_y = (360-py)*0.625`（原版 1280×720 → 800×450 居中）。
- **跳跃参数是「关卡硬约束倒推」而非视频拟合**：原版第02关必须一次跃过 150 世界像素落差，
  据此定 `JUMP_SPEED=1450 / GRAVITY=6000 / MOVE_SPEED=520`（跳高 175px = 3.98 身位，上升 0.242s）。
  这是大幅手感变更，回退表见对照文档第 5 节。
- 前 3 关已按原版第01/02/03关复刻（原版白框=墙+地面，拆成 4 块 `tick=-1`；
  原版配色 `bg 000000 / platform FFFFFF / ghost B4B4B4 / 两态标签均深色`）。
- 新工具：`orig_jump.mjs`（追踪+弧拟合）、`orig_scan.mjs`（几何行程扫描）、`orig_grid.mjs`（坐标网格）、
  `check_jump_feasible.mjs`（**用工程 physics 代码核算可通性，不依赖模拟器/真机**）。
- **拆分矩形陷阱**：把一整块连通区拆成多个 AABB 矩形时，相邻矩形顶面**不要齐平**（留 3~5px），
  否则会把玩家挤开或顶上去。

## 割绳子
- 关卡加载：`loadLevel` →（fadeScreen 黑幕）→ `onPeak` → `doLoadLevel`。
  8 个层级容器由 `ensureContainers()` 管理，可随时补建（容器缺失＝关卡不显示的高频原因）。
- `signal.lua`：出站 `send`/`sendLevelWin`；入站 `register`/`getIntParam`/`getStringParam`。
  失败=「游戏失败」，星星上报=「客户端信号 / 收集到星星」。
- 已加：开挂模式（拖拽糖果 + 边界/尖刺弹性反弹，靠「服务器事件」开关）、「文本显/隐」
  「按键绑定开/关」、手机端切割适配（`GetDevice()` 分流：键鼠轮询光标；触屏用
  `CursorDown/CursorDrag` 坐标 + `activeTouchId` 单指锁）。
- 像素资源：`_gen_pixels.py` 生成 60×60 网格；输出 `{GRID, FRAME_MS, PALETTE, FRAMES, ANCHOR_X, ANCHOR_Y}`，
  锚点为 1-based，缺省 `GRID/2`。`objectUI` 提供 `createPixelSequence`（同级）/`createPixelObject`
  （挂容器下），默认 `perFrame=true` 预建每帧控件、只切 `SetActive`。
  `像素编辑器.html` 可涂改/调中心/增删行列/多帧/撤销并导出压缩脚本。详见割绳子 README.MD。

## 模拟器 / Web 试玩（细节见 `_tools/README.md`）
**★ 一键入口**：双击工作区根 `启动千星模拟器.bat`（→ `_tools/dev_open.mjs`），
幂等五步：查环境 → 补键盘映射 → 按 Lua mtime 重建试玩存档 → 起/复用 Web 服务 → 开浏览器。
参数 `play` / `--restart` / `--rebuild` / `--game` / `--port` / `--no-open`。
bat 必须保持**纯 ASCII**（路径含中文，cmd 按本地代码页读 bat 文件），逻辑只放 `.mjs`。

MCP 服务名 `qxqy-simulator`（**需在连接器管理点「信任」**才进会话；未信任时用 `_tools/qxqy*.mjs`
直接驱动，功能等价）。模块来自存档脚本表的 `path`+`source`，故 `path` 必须是**裸文件名**。

三个必须绕开的模拟器缺陷（详见 `_tools/README.md`）：
1. **params 链路断**（`addScript` 丢 `op.params`）→ 在入口脚本**末尾**覆盖 `getParamNumber`
   （覆写 `script.GetParam` 不行，Script metatable 禁写）；`--preset sim` 自动注入。
2. **UI 模板缺失** → `qxqy_simsave.mjs` 补 `guid=2000001`(可染色 `rect` 原语) 与 `guid=2000002`(textbox)。
3. **⚠️ 渲染器 z 序反置** → 最先创建的背景被画在最顶层盖住一切，必须加 `--fix-zorder <帧>`。
   兄弟顺序**只用 `SetAsFirstSibling()`/`SetAsLastSibling()`**（两者效果与真机一致：
   first=最先绘制=最底，last=最后绘制=最顶）；**别碰 `SetSiblingIndex(i)`**，它实际插到 `len-1-i`。
   **容器内部同样反置** —— 平台容器子节点为 `[本体1, 本体2, 标签]`，标签被压在下面，
   熄灭态 alpha=40 还能透出、亮起态 alpha=255 就完全看不见数字。所以 `--fix-zorder`
   会**每帧幂等**对每个平台标签 `SetAsLastSibling()`（平台建得比容器晚，只做一次不够）。
   Web 端共用同一 bundle，同样反置。
   **`containerMenu` 同样反置**：最先建的遮罩盖住整个面板、卡片文字被自己底色压住 →
   每帧 `lift` 卡片/按钮/箭头 label 与 title/subtitle/footer，`sink` **先 `menuPanel` 再 `menuOverlay`**
   （遮罩要盖游戏画面但不能盖面板）。
   **`containerHud` 同样反置**：触屏按钮是「先建底图后建标签」→ 标签被压住只剩空方块 →
   每帧把 HUD 里**所有 `text` 非空的控件** `SetAsLastSibling()`（`text` 是属性字段，
   图片控件读它进 `pcall` error 分支，安全）。
   > 规律：真机「后创建的在上面」，模拟器整个反过来。凡「底图 + 覆盖其上的文字」都要显式提升文字。

Web 通道与 MCP 是**两套独立实例**（Web 从磁盘读存档 JSON，Lua 须预先写进 `assets.scripts`）：
- 存档下拉只列**内容含 `qxqy-simulator-save`** 的 `.json`。
- **★ 入口脚本必须挂 server 侧**：`startPlay(projects.server, {templatesProject: projects.client})`
  ——场景根取自 server、client 只作模板库；写成 `client-control-template` 会让脚本挂到永不实例化的
  节点上**静默不执行**。
- `play` 的按键动作读 **`args.key`**（不是 `typeName`），写错会被静默吞掉。
- **会话槽上限 8 个且无 CLI 开关**；命令行工具统一用 `sid='cli'`，撞上限就重启 Web 服务。
- 页面：`/` 三栏预览、`/editor` 编辑工作台（「试玩」开新标签页可能被拦，可直连
  `/editor/play#<任意字符串>`）、`/health`。
- 试玩页键盘上游**只映射数字键 1–9** → WASD 失效。`_tools/qxqy_webkeys.mjs` 把
  `play-renderer.js` 的映射函数换成 56 键完整表（依 API 文档 Enum.KeyEventType「默认物理键」列）；
  改磁盘即生效，浏览器需 Ctrl+F5。**`node_modules` 重装后要重跑 `--apply`**。

排障：`--probe`/`--probe-walk`/`--probe-timeline`/`--scene`/`--probe-player`、`_px.mjs`（采像素）、
`_boost.mjs`（提亮暗图）、`_label_probe.mjs`（区域对比度）、`_webprobe.mjs`（Web 标签反色+按键位移）、
`verify_menu.mjs`（面板功能回归）、`render_scene.mjs`（`scene.nodes` → PNG 核对布局）。

**`render_scene.mjs` 两个坑**：① 节点 `matrix.tx/ty` 是**相对父节点**偏移，必须沿 `parent` 链累加
再 `W/2+x, H/2-y`；② 图片色值字段是 **`imageColor`**（文本才是 `fontColor`）。
**隐藏控件（`SetActive(false)`）不出现在 `scene.nodes` 里** → 只能靠文本有无验证显隐。

边界：**模拟器通过 ≠ 真机通过**；服务端薄模拟、不含官方节点图；图片只代理 `100001–100006`；
上游 GPL-3.0-only；已装的是**发布 bundle**，行为**以 bundle 为准**。
割绳子暂不可试玩：`OnStart` 要求根下存在具名控件 `DropArea`/`MessageText`/`ScoreText`。

## 通用陷阱
- **Lua 前置声明**：顶部 `local foo` 之后，实现处必须写 `foo = function() end`；
  写 `local function foo()` 会新建 local 遮蔽前置声明 → 闭包拿到 nil。
- **文本框字色字段是 `fontColor`**（`imageColor` 只属图片控件，写错会被 pcall 吞掉）。
- 变量名后缀 `prefabId` / `AudioId` **不能改**。
- **★ 界面字符串别用 `◀ ▶ ✓`**：雅黑/宋体/黑体**都没有** U+25C0/U+25B6/U+2713 的字形 → 真机会画成豆腐块。
  安全的：`← → ↑`(2190/2192/2191)、`√`(221A)、`★`(2605)、`◆`(25C6)、`·`(B7)、`×`(D7)。
  新增符号前跑 `node _tools/glyph_check.mjs`（位图比对私用区码位，比「比宽度」可靠）。
- 同一文件的多处改动**不要并行下发 Edit**：会互相覆盖，出现「报成功但磁盘没变」的静默失败 → 改完必须复核。

## 版本管理（Git / GitHub）
- 工作区根即仓库根，分支 `main`；协作说明见根目录 `版本管理与协作指南.md`。
- **★ 2026-09-27 工作区已改名**：`E:\千星\千星割绳子游戏` → `E:\千星\千星游戏`。
  硬编码旧路径已同步（`_tools/qxqy.mjs`/`qxqy_mount.mjs`/`qxqy_simsave.mjs`/`qxqy_websave.mjs`
  默认值、`割绳子/_*.py`、各 README）；`启动千星模拟器.bat` 用 `%~dp0` 无需改；
  `~/.workbuddy/mcp.json` 的 `qxqy-simulator` 两处路径已同步。
- **Git 已正式安装**：`D:\git\Git\cmd\git.exe`（2.55.0.windows.5，静默装：
  `/DIR='D:\git\Git' /o:PathOption=Cmd /o:UseCredentialManager=Enabled /o:CRLFOption=CRLFCommitAsIs`）。
  旧的无 git 状态已解除；`~/.workbuddy/binaries/PortableGit/versions/1.2.0/cmd/git.exe` 仍可备用。
- 全局身份：`sks-super <sks.super@outlook.com>`（写于 `~/.gitconfig`）。
- **★ `dubious ownership`**：E 盘目录 owner SID 与当前账户不一致，所有 git 命令会失败。
  `safe.directory` 已覆盖 `E:/千星/*` 与新旧两条具体路径。换机器要重设。
- **★ GitHub 认证只能用 PAT**：账号密码自 2021-08-13 起对 Git 操作完全失效，
  用户提供的密码**不能用于 push**，也不要再索要；需 classic PAT（scope `repo`）。
- **★ 沙箱到 github.com 的 TLS 被本地代理中间人**：`http.schannelCheckRevoke=false` 无效，
  OpenSSL 后端报 `unable to get local issuer certificate`；
  只有 `GIT_SSL_NO_VERIFY=true git ...` 能通（`git ls-remote` 已验证成功）。
  属沙箱代理特性，用户本机与 GitHub Desktop 不受影响。
  下载走 `https://ghfast.top/https://github.com/...`（release 资产）与
  `https://registry.npmmirror.com/-/binary/git-for-windows/<tag>/`。
- 仓库本地配置：`core.longpaths=true`（本工程嵌套目录深，**必须**）、`core.quotepath=false`（中文名）、
  `core.autocrlf=false`（换行交给 `.gitattributes` 的 `* text=auto eol=crlf`）。
- `.gitignore` 三块重点：`_simulator/`（**773MB** 截图/录像/原版素材，机器本地）、
  `_tools/miliastra-beyond-simulator/`（**独立上游 git 仓库**，直接 add 会变成空壳子模块 →
  需 `git clone https://github.com/1475505/miliastra-beyond-simulator.git`，本机固定 d5e1663）、`node_modules/`。
- `_shared/千星沙箱客户端脚本使用指南.docx` 10.7MB 已入库（占比最大），是双机都要的权威参考。
- 提交历史：`fba63e2` 初始化（92 文件/31695 行）、`c6394da` 记录踩坑，其后为改名同步提交。
- **Windows 版 curl 不认 `/d/git` 这类 MSYS 路径**，`-o` 必须写 `D:/git/...`（否则报 No such file）。
- 本会话 Bash 工具 PATH 会丢失（`ls`/`head` 找不到），需先 `export PATH="/c/Windows/System32:/usr/bin:/bin"`。
