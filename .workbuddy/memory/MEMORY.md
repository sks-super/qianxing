# 千星奇域小游戏工作区 · 长期记忆

> **细节一律查文档**：`_tools/README.md`（模拟器/试玩）、各游戏 `README.md`、
> `TickHop/原版对照.md`、`版本管理与协作指南.md`、`_shared/Lua 客户端 UI 脚本 API.md`（引擎 API 唯一权威）。
> **本文件只留跨游戏结论与坑**（单游戏细节都写进了各自的 README）。

## 游戏索引（每个目录自包含 `.lua` + `编辑器.html` + `README.md`，**细节看它**）
- `点灯迷题/` Lights Out，**客户端只做 UI**；5×6=30 满秩；7 个平铺容器
- `点灯迷题2D/` 同玩法**纯客户端 2D 重制**（14 个 .lua，**暂无 编辑器.html**）；
  动效母本是 `2048_景苏` 的 `anim.lua`/`utils.lua`；剩余解 = flips XOR 已按集合
- `TickHop/` 时间状态机 + AABB 跳跃；8 层容器；纵向相机（原版还原另见 `原版对照.md`）
- `割绳子/` 绳/刀/糖果，关卡显示靠 `ensureContainers()`；`浮岛借木/` hzy 第 1 批
- `瓦雷莎的果园救急/` 3D 点灯（客户端纯 UI + 服务器摆棋盘）；别名 `orchard`，
  根目录 `启动-果园救急.bat`；试玩存档 `_simulator/瓦雷莎的果园救急.web.save.json`
- `MExp复刻/` **不是千星工程**：JosCla/MExp 的浏览器复刻（纯静态 HTML/JS，双击即玩）；
  关卡顺序 沙洲群岛→草地丘陵→花之湖→雪之尖塔；引擎测试 `node tests/run_tests.js` 60/60
- `皮耶罗赴死/` **level-devil（FableDevil）复刻**：30 关 / 21 种陷阱 / 全图元，
  纯客户端 14 个 .lua；别名 `piero`，根目录 `启动-皮耶罗赴死.bat`；
  **保留原版 960×540 y 向下的世界坐标，只在渲染层翻一次**（关卡数据可逐字照抄原版）；
  鬼魂模式（不死诅咒）默认开；过关播 4 格「献祭」漫画 + 伤害数字 3,927,698。
  细节见其 README。下一阶段 = 原神元素 UI 包装（只改 config 的配色/文案/COMIC）。
- `MExp复刻2D/` 同一工程的**纯平面 2D 版**：engine.js/maps.js/tests 与 3D 版 **cmp 逐字节相同**，
  只重写 render.js + 视图 UI；高度靠「高程着色 + 崖影 + 每格数字」三条平面线索；
  `node tests/render_smoke.js` 桩 canvas 跑 8208 帧。细节见其 README。

`_shared/` = API 文档 + `miliastra_lib.lua` 类型桩 + 三个校验器；`_tools/`、`_simulator/`（运行产物，
已 gitignore）**非交付物**。**★ 只改当前在做的游戏**（顺手改别的会版本漂移、连锁报错）。

## ★★ 真机 vs 模拟器：四处「模拟器看不出来」的坑
1. **文本框 `bgColor`** 不设就带预制体底色 → **实心色块盖住下方内容**（模拟器忽略该字段）。
   已用 `utils.setTextBgTransparent()` 根治。
2. **★★ 文本框有最小高度**：盒子太矮（< 约 30px）**一个字都不画** —— 实测同一套代码真机
   高 56/54/30 正常、**26/22 完全空白**。已用 `utils.MIN_TEXT_H = 36` 兜高 +
   显式 `adaptiveFontSize = false` 根治。**布局必须按「兜高后的盒子」排**
   （故 `MIN_TEXT_H` 对外暴露；`menu.lua` 的难度条 y 由它反推），否则会出现
   「按自报高度排的版、实际盒子被撑高后和隔壁打架」。
3. **容器 `enableMask`**：底图预制体若带遮罩，容器只有 1×1 → 子控件被整片裁掉。已显式设 false。
4. **★★ 叠放顺序（2026-10-19 挖到引擎源码，结论已定）**：`beyond-simulator-web` 的
   `server.js` 是「按 z 升序排好、再从数组尾部倒着画」⇒ **z 大的先画 = 落在下层**，
   而 z = 同级创建序号。所以「后创建在上」只对**真机**成立，模拟器正好相反。
   `SetAsLastSibling()` = `SetSiblingIndex(len-1)`，但模拟器的 `SetSiblingIndex(i)` 实际插到
   `len-1-i`（= 插到 0 = 最上层）→ **按「下→上」顺序连续调 `utils.raise()`，两引擎都对齐**。
   **凡同一父节点下元素重叠，必须显式 raise 定序**，别指望创建顺序（范例：`utils.createButton`）。

- **★ 不透明底色会盖住 3D**：铺满画布的纯色背景**即使在最底层也要按屏切换显隐**
  （`bg.setVisible(name ~= "play")`），否则真机就是「进了关还是一片沙滩」。
- **★ `AddCursorEventListener` 只挂在「预设按钮」/「光标检测区域」上**，图片控件没有 → 用 pcall 包着
  **静默失败** → 「按钮画得出来但点不动」。所有可点区域一律走 `utils.createHit` + `cursorPrefabId`。
- **★ 自适应尺寸**：面板 = 画布 × RATIO（再由 MAX 封顶），`k` = 面板高 / 设计基准；
  卡片尺寸由**可用空间反推**（矮了减行、窄了减列，且有硬下界，别写死尺寸）。
  **居中的面板可以整层 `SetLocalScale(k)`，贴边的 HUD 不行**（会被推出屏外）；
  **粒子挂在未缩放的 `containerFx`** → 坐标若在缩放容器里要乘 `utils.uiScale()`。

## ★★★ 第五到第九条（2026-10-24，做 `皮耶罗赴死` 时挖到，全部是「不报错但不对」）
5. **★ 入口脚本末尾不能写 `return`**：网页存档会把参数兜底等补丁**追加到入口脚本末尾**，
   `return` 之后不允许再有语句 → 整份脚本报 `<eof> expected near 'do'`，
   症状是 `mountError` 有值、`scene.nodes` 全空。入口文件的最后一行别放 `return`。
6. **★★ 同一个复合控件的多个部件必须显式 raise**：玩家 = 身体 + 两只眼睛，
   眼睛后创建 → 模拟器「后创建更靠下」→ **眼睛被身体盖住**（真机会正常）。
   凡是「一个角色/一个按钮由几个控件叠出来」，建完一律按「下→上」连续 `utils.raise`。
7. **★★ 状态流转函数必须先离开当前状态再启动过渡**：
   `advance()` 里若只 `fadeScreen.start(...)` 而不改 `state.state`，
   OnUpdate 的 `win` 分支每帧都会再调一次 → **反复重启黑幕，`onPeak` 永远等不到**
   （表现为「过关后卡住不换关、也没有报错」）。先 `state.state="wait"` 再起过渡。
8. **★★ 每帧同步 `sync()` 别只写在分支里**：`player.update()` 只在鬼魂分支调了 `M.sync()`，
   普通分支忘了 → 「走路/跳跃画面完全不动，但鬼魂态会动」，极易误判成「跳跃代码坏了」。
9. **★ HUD 文字压不住浅色实体**：本作实体色是浅色（ink），关卡顶部又常常就是一块实体，
   浅字压浅底直接看不见。**HUD 一律加一条半透明深色底条**（`hud.bar`），别指望改字色。
10. **★ 网页模拟器的 `step` 与它自己的实时循环叠加**：`play/step` 只是额外推进帧，
    整体时间轴比 1/30 秒/帧快（实测约 2×）。**用它验「逻辑对不对」，不要用它验「几秒」**；
    要卡时间的断言（跳跃峰值、动画时长）不能靠帧号。

## ★★ 「图元复刻」的通用套路（`皮耶罗赴死` 沉淀）
- **坐标系别逆着原版改**：原版 y 向下的就把世界坐标原样搬过来，只在渲染层翻一次；
  否则 30 关关卡数据全要重算，错一格就没人能对回原版。
- 三角形 → 45° 旋转的小方块（菱形），**底角对齐基准线**（中心 = 基准 − 半对角线×out），
  这样「长出来」的动画和原版一致。
- 圆/圆弧 → 两层菱形（外壳半透明 + 内芯实色）比矩形更像圆。
- 长条（摆锤绳 / 指针）→ **不改 pivot**，每帧把中心放在两端中点、再 `SetLocalRotation`；
  改 pivot 在两种引擎里表现不一致。
- 粒子/血渍要**控件池**（一次建好、反复 SetActive），别逐次 Instanced/Destroy。
- 每个陷阱写 `update/sols/kills/sync/reset` 五件套：逻辑只算世界坐标矩形，
  `sync` 才碰控件，且**只在值变化时真的动控件**（`ins.lastY` 之类的脏标记）。

## 工程约定（跨游戏）
- `config.lua` 的 `DEFAULT_*` 是**参数唯一真源**；`编辑器.html` 的 `DEFAULTS` 必须逐项一致
  （key = 常量名去 `DEFAULT_` 小写）。**★ 校验器只单向查（编辑器→config）**，
  config 新增项漏同步是查不出来的。`state.lua` 要显式声明所有 `state.*` 字段。
- **★ `require` 一律带导入根**：`require("default_import_file/config")`。裸名只在旧存档兼容层有效，
  用编辑器「导入文件」会直接报 `failed to load script`；导入到子目录时前缀跟着变。
- **Lua 前置声明**：顶部 `local foo` 之后，实现处必须写 `foo = function() end`；
  写 `local function foo()` 会新建 local 遮蔽前置声明 → 闭包拿到 nil。
- 变量名后缀 `prefabId` / `AudioId` **不能改名**；文本框字色字段是 **`fontColor`**
  （`imageColor` 只属图片控件，写错被 pcall 吞）。
- **★ 界面字符串别用 `◀ ▶ ✓`**（无字形 → 豆腐块）。安全：`← → ↑`、`√ ★ ◆ · ×`。
  新增符号前跑 `_tools/glyph_check.mjs`。
- 同一文件的多处改动**不要并行下发 Edit**（会互相覆盖，报成功但磁盘没变）→ 改完必须复核；
  含大量中文 + 全角空格的旧段落 Edit 易匹配失败 → 改用 Python 脚本定点插入更稳。
- **★★ 棋类示意图别手写盘面**：教程/预览里的「盘面」一律由**解**反推
  （翻格子游戏 = 十字逐格 XOR：覆盖奇数次翻、偶数次不变）。手写必错在「重叠处」，
  且改名/改解后没人会记得回来改图。范例：`瓦雷莎的果园救急/guide.lua` 的 `deriveArt()`
  + `_verify_levels.mjs` 的「推出盘面 == 真实盘面」双保险。
- **★★ 教程文案有字数上限**：文本框 `adaptiveFontSize=false`，正文框 580px / 字号 18
  → 一行超过约 **30 字就被裁**（图注 15 号约 34 字）。写文案先数字数；
  一页只讲一件事，讲不下就**拆页**（`config.M.LESSONS[i].pages` 是一课多页）。
  范例：`瓦雷莎的果园救急` 教程 = 序章 3 页（背景 + 选关）+ 第 1 课 3 页（目标/操作/过关）+ 第 2–5 课各 1 页。
- **★ 教程示意图配色单独开键**：`guideFruit`（黄 = 水果）/ `guideJuice`（红 = 果汁），
  **不要复用 `pal.fruit` / `pal.juice`** —— 那两个在选关苹果、粒子、结算里另有语义。
- **★ 单位/句柄**：一次性装饰用 `roundRect`（只给容器）；**需要后续改色改尺寸**必须用
  `roundBox`（返回 `.parts`），否则 `setBoxColor` / `setBoxSize` 静默失败
  （症状：文字变了、底色没变）。

## 校验与回归（无 Lua 解释器，用 Python/Node；**看退出码不看文案**）
- 工作区根：`_shared/_check_blocks.py <游戏>`、`_check_refs.py <游戏>`
  （require / 模块函数 / `state.x` / `config.大写常量` / DEFAULTS 同步）、`_check_editor_roundtrip.js`。
- **在游戏目录内**（脚本用 `process.cwd()`）：`node _verify_levels.mjs`、`python _export_sandbox.py`。
- `_tools/check_jump_feasible.mjs`（可通性，**满跳 + 轻点小跳都要测**）、`_tools/render_levels.py`
  （离线渲染 + 原版叠图）、`_simulator/diag/layout_check.py`（离线复算多画布布局，报越界/重叠）。

## 模拟器 / Web 试玩（**细节全在 `_tools/README.md`**）
- 一键入口双击 `启动千星模拟器.bat` → `_tools/dev_open.mjs`。**bat 必须纯 ASCII**（路径含中文）。
- **★ 换机器三件事**：装 `node_modules`（在 `%HOME%\.workbuddy\binaries\node\workspace`）；
  `_tools/*.mjs` 路径一律用 `HOME` 解析（早期硬编码用户名会导致「键盘补丁失败」+`timeout: initialize`）；
  打完键盘补丁**必须重启 Web 服务**（渲染器启动时读进内存）。
- **★★ 本环境 Node 的「同步」子进程 API（`spawnSync`/`execSync`）一律抛 `EBUSY`** →
  只用异步 `spawn` / `execFile`。
- **★★ 模拟器存档里的脚本 ≠ 交付脚本**：入口脚本会被追加 `[SIM_ONLY]`/`[SIM_ZFIX]` 上百行补丁，
  真机报 `table index is nil` → 交付一律用**工程源文件**（范例 `点灯迷题/_export_sandbox.py`）。
- **★ 试玩页 `#` 是 sessionId 不是选档**；**Web 与 MCP 是两套独立实例**；**入口脚本必须挂 server 侧**；
  `play` 按键读 `args.key`；**会话槽上限 8 且无 CLI 开关**；键盘上游只映射数字键 1–9
  （`qxqy_webkeys.mjs` 换 56 键表，`node_modules` 重装后要重跑 `--apply`）。
  ★ 因此所有 `_verify_*.mjs` 必须**复用同一个固定 sessionId**（如 `'cli'`），
  每次 `loadWebSession('新名字')` 都会新建会话，堆到第 9 个就 `Editor session limit reached`。
- **★ 无头运行时验证**：把调试 Lua 追加到存档 `assets.scripts[].source`（找 `path == "game.lua"`）末尾，
  再把**真值**写进 HUD 文本 → 探针从 `scene.nodes` 读真值（自己猜计时一定会算错）。
  `qxqy_mount.mjs` 开关：`--key 名字@帧`、`--signal-at <帧>`、`--steps-after <n>`、
  **`--canvas <预设 id>`**（`pc-16-9` 1600×900 / `mobile-16-9` 1280×720…，验证自适应布局必备）、
  `--scene`、`--tree`（**客户端→服务器记在 `inbound`**，注意方向命名）。
- **★★ `--fix-zorder 3` 会整屏变空（`nodes=0`），不加才正常**（2026-10-19）。排查顺序：
  先用一个已知能跑的工程对照跑一遍，**它也是 0 就说明是工具/环境，不是自己的 Lua**。另 `--restart`
  起的服务是 detached、会被回收 → 用托管后台任务起 `node …/beyond-simulator-web/dist/server.js
  --workspace <工作区> --port 4173`。
- `render_scene.mjs`：`matrix.tx/ty` 是**相对父节点**偏移（须沿 `parent` 链累加）；图片色值字段是
  **`imageColor`**（文本才是 `fontColor`）；**隐藏控件不会出现在 `scene.nodes` 里**。
- **★★ 「下拉里看不到自己的工作区」= 端口被别的工作区占了**（4173 只能挂一个 workspace）。
  唯一可靠确认：`GET /api/state` 的 `workspace` 字段。`dev_open --restart` 抢回端口；
  但 `detached spawn` 的服务在本环境会被回收 → 用**托管后台任务**起 `server.js --workspace …`。
- **★ 存档命名约定**（写 JSON 顶层 `name`，网页按 mtime 排序显示）：
  `★ …`=当前在做、`（底稿）…`=mount 产出的工程档、`（工具）…`=sim-ready 模板（别选）。
- **★ 中文游戏名不进 `.bat`**：bat 内容保持纯 ASCII，名字写在 `_tools/game_alias.json`，
  启动传 `--alias deng2d`。范例根目录 `启动-点灯迷题2D.bat`。
- **★★ 模拟器里「点得动但没反应」的三个真因**（`AddCursorEventListener` 会静默成功，pcall 拦不住）：
  ① 祖先容器必须 `showCursor=true`（`buildCursorShim()` 补）；② 命中区必须挂在**真容器**链下
  （命中测试只下钻 container/grid/textwindow/reference/button，图片当父节点则子孙不可达 →
  工程加 `containerPrefabId`，sim 传 `1073742100`）；③ 别全局 `raycastTarget=true`（底板会吞点击）。

- **★★★ 第 0 条（2026-10-19 真因，最容易被误判）**：命中测试 `cn()` **逐层**判定 ——
  每个控件先算 `Ae(父矩形, 本控件)`，点不在矩形内就 `return null` **且不再下钻子节点**。
  挂载节点默认「锚点居中 + 尺寸 0」→ 矩形退化成中心一个点 ⇒ 整棵子树命中区全部不可达，
  症状是「点哪都没反应、不报错、只有正中心能点中」（很容易误以为是坐标映射错）。
  `buildCursorShim()` 已在 `OnStart` **之前**把挂载节点改成铺满画布（锚点 0,0→1,1，size 0，
  中心不变故不影响排版）。**`play` 的 `pointer` 坐标点击现已可用**（x 右增、**y 从下往上增**——2026-10-19 实测更正：屏 303 传 y=460、屏 660 传 y=60）。
  另：命中区尺寸要比格子大一圈（+gap），否则 5px 缝隙点不中。
- 边界：**模拟器通过 ≠ 真机通过**；图片只代理 `100001–100006`；上游 GPL-3.0-only。

## 本机环境 / 版本管理（Git）
- **★ 本会话 Bash 的 PATH 会丢** → 命令前 `export PATH=/usr/bin:/bin:/c/Windows/System32`
  （**`/usr/bin` 在前**，否则 `find`/`sort`/`file` 被 Windows 同名程序抢走）；node 也要写**绝对路径**。
  Python 用 `~\.workbuddy\binaries\python\envs\default\Scripts\python.exe`
  （**装了 pillow/numpy/imageio_ffmpeg**，可直接抽帧）；base 3.13.12 没有这些包。
- 远程 `github.com/sks-super/qianxing`（public）；`main` 只归 sks-super；**所有合并由 sks-super 做**；
  协作者产出放 `_inbox/<用户名>/`；**认证只能用 PAT**；完整流程见 `版本管理与协作指南.md`。
- **★ 本机 git** 在 `~\.workbuddy\binaries\PortableGit\versions\1.2.0\cmd\git.exe`（不是旧记忆里的
  `D:\git\...`）；换机器必做 `git config --global --add safe.directory 'E:/千星/千星游戏'`。
- **★★ 本环境对 `.git` 写入不可靠**（loose ref 随时消失，严重时 `.git` 整个不见）→ **push 是唯一保险**，
  重活优先让用户在 GitHub Desktop 做。**★ 沙箱到 github.com 的 TLS 被中间人**：
  只有 `GIT_SSL_NO_VERIFY=true git ...` 能通。仓库配置 `core.longpaths=true`（**必须**）、
  `quotepath=false`、`autocrlf=false`；`.gitignore` 重点 `_simulator/`、`node_modules/`；
  **别用 `rebase --exec`**（曾致 `.git` 损坏）。
