# 千星奇域小游戏工作区 · 长期记忆

> 细节查阅：工具 → `_tools/README.md`；原版还原 → `TickHop/原版对照.md`；
> 协作/装环境 → `版本管理与协作指南.md`、`队友接入指南.md`；
> 引擎 API 唯一权威 → `_shared/Lua 客户端 UI 脚本 API.md`。**本文件只留结论与坑。**

## 目录与真源
- `_shared/` 公共层（API 文档、`miliastra_lib.lua` 类型桩、三个校验器）；`割绳子/`、`TickHop/`
  各自自包含全部 `.lua` + `编辑器.html`；`_tools/`（模拟器+驱动）与 `_simulator/`（运行产物）**非交付物**。
- **`config.lua` 的 `DEFAULT_*` 是参数唯一真源**，`编辑器.html` 的 `DEFAULTS` 必须逐项一致
  （key = 常量名去 `DEFAULT_` 前缀并小写；历史特例见 `_check_refs.py` 的 `SPECIAL` 表）。
  改一处必须同步另一处。`state.lua` 必须显式声明所有 `state.*` 字段。

## 静态校验（无 Lua 解释器，用 Python；在工作区根执行）
- `python _shared/_check_blocks.py TickHop` —— 词法级块平衡（排除 miliastra_lib.lua）
- `python _shared/_check_refs.py TickHop` —— require 目标 / `mod.fn()` / `state.x` /
  `config.<大写常量>` / 编辑器 DEFAULTS 同步，五项一致性
- `node _shared/_check_editor_roundtrip.js` —— TickHop「导出→解析」无损（含 labelGhost）
- 编辑器内嵌 JS：抽出 `<script>` 后 `node --check`
- **判定看退出码，不看文案**（refs 成功时也打印"0 处不一致"）

## TickHop（时间状态机 + AABB 平台跳跃）
- 模块：game / config / state / timeSystem / level / **menu** / physics / utils / audio / signal / fadeScreen
- 平台 `tick == timeTick` 或 `tick == -1`（永驻）为实体，否则虚化不可碰撞。
  **只改颜色 alpha，不销毁重建控件**。
- 坐标：原点在画布中心、**Y 向上为正**、坐标为**中心点**；编辑器与运行时同一套。
- **8 层容器**：bg → platform → goal → pickup → player → hud → **menu** → fade。
- 黑幕后重建关卡：先 `setRunning(false)` + `pendingStart = true`，等黑幕散尽再计时。
- 脚本变量 `rectPrefabId`(必填) / `textPrefabId` / 各 `*AudioId` —— **后缀不能改名**。
- 标签两态反色：实体→`palette.label`（深）压亮平台；虚化→`palette.labelGhost`（浅）+
  `DEFAULT_PLATFORM_LABEL_GHOST_ALPHA`(130) 压暗平台。文本框改字色**必须用 `fontColor`**。
- 关卡落盘：`node _tools/apply_levels.mjs TickHop.levels.lua`（大括号配平替换 + 自动校验）。
- 扩展落点：随时间/条件切实体 → `level.refreshPlatforms()`；碰到才发生的事 → `physics.step()`。

### 选关 / 结算面板（`menu.lua`）
- **一批控件扛三态**（`select`/`win`/`fail`），只改文字 + `SetActive`，切换零分配。
  **解耦**：不 require `game`，由 `OnStart` 注入 `menu.setActions({onSelect,onReload,onNext})`。
- **输入三类**：`bindPair`（玩法，受 `menuOpen`/`keysEnabled` 拦截）/ `bindMenuKey`（`←→` 光标、
  `空格` 确认，仅 `menuOpen` 生效）/ `bindGlobal`（`R`/`T`/`P`/`L`，**绕过 `keysEnabled`**）。
  ★ `L` 必须绕开总开关，否则面板打开后关不掉。
- `state.menuCursor` 存**可玩关序号**（非页内下标），跨页自动 `setPage` → 光标与页码永远自洽。
- 参数 21 项 `DEFAULT_MENU_*` + 配色 `overlay/panel/card/panelText/accent/accentText/dim/clear`。
- 回归：`node _tools/verify_menu.mjs`（8 场景 17 项）。

### 原版对照（详情见 `TickHop/原版对照.md`）
- 原版 = **《滴答咔哒 / Tick Hop》Steam AppID 3419780**；素材 `_simulator/orig/`。
- 换算：`world_x = (px-639.5)*0.625`，`world_y = (360-py)*0.625`（1280×720 → 800×450 居中）。
- **跳跃参数是「关卡硬约束倒推」而非视频拟合**：原版第02关须一次跃过 150 世界像素落差 →
  `JUMP_SPEED=1450 / GRAVITY=6000 / MOVE_SPEED=520`。回退表见对照文档第 5 节。
- **拆分矩形陷阱**：连通区拆成多个 AABB 时，相邻矩形顶面**不要齐平**（留 3~5px），否则挤开/顶起玩家。

## 割绳子
- 关卡加载：`loadLevel` →（fadeScreen 黑幕）→ `onPeak` → `doLoadLevel`。
  8 个层级容器由 `ensureContainers()` 管理，可随时补建（**容器缺失＝关卡不显示的高频原因**）。
- `signal.lua`：出站 `send`/`sendLevelWin`；入站 `register`/`getIntParam`/`getStringParam`。
- 已加：开挂模式（拖拽糖果 + 边界/尖刺弹性反弹，靠「服务器事件」开关）、文本显/隐、按键绑定开/关、
  手机端切割适配（`GetDevice()` 分流：键鼠轮询光标；触屏用 `CursorDown/CursorDrag` + `activeTouchId` 单指锁）。
- 像素资源：`_gen_pixels.py` 生成 60×60 网格，输出 `{GRID, FRAME_MS, PALETTE, FRAMES, ANCHOR_X, ANCHOR_Y}`
  （锚点 1-based，缺省 `GRID/2`）；`objectUI` 提供 `createPixelSequence`（同级）/`createPixelObject`（挂容器下），
  默认 `perFrame=true` 预建每帧控件、只切 `SetActive`。见 `像素编辑器.html`。
- 暂不可试玩：`OnStart` 要求根下存在具名控件 `DropArea`/`MessageText`/`ScoreText`。

## 模拟器 / Web 试玩（**细节全在 `_tools/README.md`，此处只留雷**）
- **★ 一键入口**：双击 `启动千星模拟器.bat`（→ `_tools/dev_open.mjs`），幂等五步。
  **bat 必须保持纯 ASCII**（路径含中文，cmd 按本地代码页读 bat），逻辑只放 `.mjs`。
- MCP 名 `qxqy-simulator`（**需在连接器管理点「信任」**）；未信任时用 `_tools/qxqy*.mjs`，功能等价。
- 三个必须绕开的缺陷：① `addScript` 丢 `op.params` → 入口脚本**末尾**覆盖 `getParamNumber`
  （覆写 `script.GetParam` 无效）；② UI 模板缺失 → `qxqy_simsave.mjs` 补 `guid=2000001/2000002`；
  ③ **⚠️ 渲染器 z 序反置**（Web 端共用同一 bundle）→ 必须 `--fix-zorder <帧>`。
- **z 序规则**：只用 `SetAsFirstSibling()`/`SetAsLastSibling()`（与真机一致：first=最底，last=最顶）；
  **别碰 `SetSiblingIndex(i)`**（实际插到 `len-1-i`）。容器内部同样反置，且要**每帧幂等**处理
  （平台建得比容器晚，只做一次不够）。凡「底图 + 覆盖其上的文字」都要显式提升文字
  （平台标签、`containerMenu` 的卡片/箭头/title、`containerHud` 里 `text` 非空的控件）。
  > 规律：真机「后创建的在上面」，模拟器整个反过来。
- Web 与 MCP 是**两套独立实例**（Web 从磁盘读存档 JSON，Lua 须预先写进 `assets.scripts`；
  存档须含标记串 `qxqy-simulator-save`）。**★ 入口脚本必须挂 server 侧**：
  `startPlay(projects.server, {templatesProject: projects.client})`，写成 `client-control-template`
  会挂到永不实例化的节点上**静默不执行**。`play` 的按键动作读 **`args.key`**。
  **会话槽上限 8 个且无 CLI 开关**（工具统一 `sid='cli'`，撞上限重启服务）。
- 试玩页键盘上游**只映射数字键 1–9** → WASD 失效；`_tools/qxqy_webkeys.mjs` 换成 56 键完整表，
  **`node_modules` 重装后要重跑 `--apply`**。
- `render_scene.mjs` 两个坑：① 节点 `matrix.tx/ty` 是**相对父节点**偏移，须沿 `parent` 链累加再
  `W/2+x, H/2-y`；② 图片色值字段是 **`imageColor`**（文本才是 `fontColor`）。
  **隐藏控件（`SetActive(false)`）不出现在 `scene.nodes` 里** → 只能靠文本有无验证显隐。
- 边界：**模拟器通过 ≠ 真机通过**；服务端薄模拟；图片只代理 `100001–100006`；上游 GPL-3.0-only；
  已装的是**发布 bundle**，行为**以 bundle 为准**。

## 通用陷阱
- **Lua 前置声明**：顶部 `local foo` 之后，实现处必须写 `foo = function() end`；
  写 `local function foo()` 会新建 local 遮蔽前置声明 → 闭包拿到 nil。
- **文本框字色字段是 `fontColor`**（`imageColor` 只属图片控件，写错会被 pcall 吞掉）。
- 变量名后缀 `prefabId` / `AudioId` **不能改**。
- **★ 界面字符串别用 `◀ ▶ ✓`**：雅黑/宋体/黑体都没有 U+25C0/U+25B6/U+2713 字形 → 真机画成豆腐块。
  安全的：`← → ↑`(2190/2192/2191)、`√`(221A)、`★`(2605)、`◆`(25C6)、`·`(B7)、`×`(D7)。
  新增符号前跑 `node _tools/glyph_check.mjs`（位图比对私用区码位，比「比宽度」可靠）。
- 同一文件的多处改动**不要并行下发 Edit**：会互相覆盖，出现「报成功但磁盘没变」的静默失败 → 改完必须复核。
- 本会话 Bash 工具 PATH 会丢（`ls`/`head` 找不到）→ 命令前先
  `export PATH="/c/Windows/System32:/usr/bin:/bin"`。

## 版本管理（Git / GitHub）
- 仓库根 = 工作区根，分支 `main`；**远程** `https://github.com/sks-super/qianxing`（public）。
- **★ 协作模型（2026-09-27 定）**：一人一分支、与 GitHub 用户名同名。
  `hzy` 归协作者 hzy（远端已建，起点 = `main`）；`main` 只归 `sks-super`。
  **所有合并由 sks-super 做**；协作者产出统一放 `_inbox/<用户名>/`（**不改仓库已有文件**），
  流程 = 留档 → 归集到 `_inbox/hzy/` → 推 `hzy` → 开 PR（不合并）→ 用户合并。
  文档：`队友接入指南.md`（开头「★ 协作铁律」= 给协作者和他的 AI 看，可直接转发）、
  `_inbox/README.md`、`版本管理与协作指南.md` §3.4~§3.7。
- **★ `main` 已在服务器端锁死**（classic 分支保护，非 rulesets）：
  `PUT /repos/{o}/{r}/branches/main/protection`，payload 关键项 =
  `required_pull_request_reviews.required_approving_review_count=1`（**审批人不能是 PR 作者**
  → 协作者无法自合并）、`dismiss_stale_reviews=true`、`allow_force_pushes=false`、
  `allow_deletions=false`、`restrictions=null`、**`enforce_admins=false`（管理员旁路，
  用户仍可直推 main）**。代价：用户自己的 PR 自己批不了，所以大改动要么直推 main、
  要么让协作者 review。**public + GitHub Free 才免费支持**；改私有则需 Pro。
  验证痕迹：管理员推送时服务器回显 `Bypassed rule violations for refs/heads/main`。
- **★ 仓库名演进**：最初由 API 建成名为 `-` 的仓库，后改名 `qianxing`（GitHub 保留旧名重定向，
  故 `-.git` 也能通）→ remote 已 `set-url` 为正名；换机后若见 `-.git` 需重设。
- **★ 工作区改名已完成**：`E:\千星\千星割绳子游戏` → `E:\千星\千星游戏`（2026-09-27）。
  当初失败是因根目录被运行中的 WorkBuddy 占用（`mv` 报 `Device or resource busy`；
  子目录/同级目录都能改，**唯工作区根不行**）→ **退出应用后再改**。
- 取 PAT：`printf 'protocol=https\nhost=github.com\n\n' | git credential fill | sed -n 's/^password=//p'`
  （可用来调 GitHub API；当前是 40 字符 classic PAT）。
- **Git 在 `D:\git\Git\cmd\git.exe`**（2.55.0.windows.5）。全局身份 `sks-super <sks.super@outlook.com>`。
- **★ GitHub 认证只能用 PAT**（账号密码自 2021-08-13 对 Git 操作完全失效，不要再索要密码）；
  凭据已存 Windows 凭据管理器（`git credential fill` 可验）。
- **★ `dubious ownership`**：E 盘目录 owner SID 与当前账户不一致 → 所有 git 命令失败。
  `safe.directory` 已覆盖 `E:/千星/*`。换机器要重设。
- **★ 沙箱到 github.com 的 TLS 被本地代理中间人**（`HTTPS_PROXY=127.0.0.1:52682`）：
  只有 **`GIT_SSL_NO_VERIFY=true git ...`** 能通，`curl` 要加 `-k`。属沙箱特性，用户本机不受影响。
- **★ 另一条沙箱怪癖：git 自己写 `refs/remotes/**` 会被静默吞掉**
  （`git fetch` 打印 `[new branch] main -> origin/main`、`update-ref` 退出码 0，但磁盘上什么也没有，
  且 git 会顺手删掉变空的 `refs/remotes/origin` 目录 → `git status` 显示 `[gone]`，`git pull` 直接失败）。
  **`refs/heads/**` 不受影响**（`git branch`/`commit` 正常），且**手工写入的 loose ref 能持久化并被 git 正确读取**。
  应急：`mkdir -p .git/refs/remotes/origin && echo <sha> > .git/refs/remotes/origin/main`。
  已如此修复过一次 `origin/main`。**换到用户本机/队友机器上不会出现**（非仓库问题）。
- 仓库配置：`core.longpaths=true`（嵌套深，**必须**）、`core.quotepath=false`、`core.autocrlf=false`
  （换行交给 `.gitattributes` 的 `* text=auto eol=crlf`）。
- `.gitignore` 三块重点：`_simulator/`、`_tools/miliastra-beyond-simulator/`（**独立上游仓库**，
  直接 add 会变空壳子模块 → 需单独 `git clone`，本机固定 d5e1663）、`node_modules/`。
- **不要在本环境用 `rebase --exec`**：曾导致 `.git` 损坏；备份在 `D:\git\_backup-dotgit-20260927`。
- **Windows 版 curl 不认 `/d/git` 这类 MSYS 路径**，`-o` 必须写 `D:/git/...`。
