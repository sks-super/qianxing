# _tools — 千星沙箱模拟器（本地 Lua 试玩/调试环境）

把千星奇域客户端 Lua 工程放到本地跑起来，**不依赖真机和官方编辑器**即可验证脚本、
复现「服务器→客户端」信号、读日志、给画面截图。

## 为什么需要它

本工作区的两个游戏（`割绳子/`、`TickHop/`）都是千星客户端 Lua 工程。
在真机上调试一条链路要反复开游戏，而**入站信号（服务器→客户端）在预览环境里根本收不到**，
导致长时间无法定位问题。模拟器把这整条链路搬到了本地。

## 目录

| 路径 | 说明 |
|---|---|
| `miliastra-beyond-simulator/` | 上游源码（浅克隆，GPL-3.0-only）。文档看 `README.md`、`AGENTS.md`、`skill/SKILL.md`、`mcp/README.md` |
| `dev_open.mjs` | ★ **一键启动**：查环境 → 补键盘映射 → 重建试玩存档 → 起 Web 服务 → 开浏览器。由工作区根的 `启动千星模拟器.bat` 调用（双击即用）。参数：`play` / `--restart` / `--rebuild` / `--game` / `--port` / `--no-open` |
| `qxqy.mjs` | 通用驱动：`list` / `call <工具> '<json>'` / `run <script.json>` |
| `qxqy_mount.mjs` | 把一个游戏目录的全部 Lua 灌入模拟器并试玩（支持参数注入、控件树探针、层级纠正） |
| `qxqy_simsave.mjs` | 把工程存档改造成「模拟器就绪」存档（补一套可实例化的扁平模板） |
| `qxqy_websave.mjs` | 生成「**浏览器**试玩就绪」存档（内嵌 Lua + 参数兜底 + 层级修正 + 存档标记） |
| `qxqy_webcheck.mjs` | 命令行验证 Web 试玩链路（载入→启动→推进→打印日志与场景节点） |
| `qxqy_webkeys.mjs` | **给 Web 试玩页补上完整键盘映射**（WASD/方向键/空格…→ 千星按键事件），支持 `--apply/--check/--restore/--selftest/--probe` |
| `_sim_common.mjs` | 驱动脚本共享定义（模板 guid、参数兜底、层级修正、Lua 收集） |
| `_webclient.mjs` | Web 模拟器的极小 HTTP 客户端 |
| `_webprobe.mjs` | Web 端综合探针：同时验证「平台标签两态反色」与「键盘驱动玩家位移」 |
| `apply_levels.mjs` | **把编辑器导出的关卡 Lua 落进 `config.lua`**（大括号配平精确替换 + 自动跑两道静态校验），`--extract` 可反向导出 |
| `verify_menu.mjs` | Web 端端到端回归 **选关 / 通关 / 失败** 三套面板（8 场景 25 项） |
| `render_scene.mjs` | 把 `scene.nodes` 矢量数据渲染成 PNG 核对 UI 布局。场景 `none/select/win/fail/cleared` |
| `glyph_check.mjs` | **字形覆盖检测**：用「位图比对私用区码位」判断某字体是否真的有某符号（避免豆腐块） |
| `_px.mjs` | 采样 PNG 像素（核对截图真实配色，判断「哪一层盖住了画面」） |
| `_label_probe.mjs` | 采样某个「世界坐标矩形」并打印 **ASCII 位图**，核对平台秒数标签是否真的画出来了 |
| `_label_compare.mjs` | 把「熄灭态 / 亮起态」两张截图按同一区域裁切放大拼成对比图 |
| `_boost.mjs` | 提亮过暗截图（黑幕期间/低 alpha 控件肉眼检查用） |
| `examples/signal-probe.json` | 信号链路验证用例（注册并接收 `测试`/`进入关卡`/`服务器事件`） |

### 浮岛借木 专用工具（与该游戏同批归集）

| 路径 | 说明 |
|---|---|
| `solve_浮岛借木.py` | ★ **定版规则的 Python 参考实现 + IDA\* 求最短解**。打印高度模型、每关概览、内置口令自检、地图字符画；`--trace <口令>` 逐步回放。改关卡 / 改规则后**必跑**（会报「内置口令步数 ≠ 最短解步数」） |
| `preview_art_浮岛借木.py` | ★ **离线素材预览**：用真美术 + 与 `level.lua` 逐项一致的几何渲染第 N 关 → `浮岛借木/预览_素材路径_第NN关.png`。模拟器只代理 6 种基础图元、画不出真美术，贴合只能离线看。⚠️ 改 `level.lua` 几何后必须同步它 |
| `e2e_浮岛借木.sh` | 端到端一条命令 7 轮（三关解法 + 素材 / 回退 A/B + 提示 + 底图模板探针）。⚠️ 只报「有没有挂载错误」，**步数与「已通关」只画在画布 HUD 上，必须人眼看图** |
| `check_lua_scoping.py` | **Lua 局部变量「先用后声明」检查**。`local` 写在文件底部、被上面的函数提前引用时，Lua 会把名字当**全局**读成 `nil`，不报错、跑起来才炸 —— 这个检查专门抓它（附带死代码提示） |
| `test_editor_roundtrip.mjs` | `编辑器.html` 的 `generateLua()` → `parseLuaLevels()` **往返无损**自检 + `config.lua` 的 `M.LEVELS` ↔ 编辑器内置关卡**逐项比对**。用极薄 DOM 桩子在 Node 里跑页面里的 `<script>` |
| `make_grass_tile.py` | 程序化生成方形顶面草地素材（自带平铺自检：格内亮度极差 < 8，防瓦片自带渐变变成条纹） |
| `make_compare_浮岛借木.py` | 把两张截图拼成 A/B 对照图（左素材路径 / 右纯色回退） |

## 浏览器试玩（Web 模拟器）

Web 版与 MCP 版是**两套独立实例**：Web 从磁盘直接读存档 JSON 试玩，不走 `addScript`，
所有 Lua 必须预先写进存档的 `assets.scripts` 里。

> ★ 日常使用别手敲下面这四步——直接双击工作区根的 `启动千星模拟器.bat`，
> 或跑 `node _tools/dev_open.mjs`。它会自动完成 1)~3) 并打开浏览器，且**幂等**：
> 服务在跑就复用、Lua 改过就重建存档、键盘补丁丢了就补回。下面保留手工分步供排障。

```bash
# 1) 启动 Web 服务（后台常驻，改存档后网页会自动重载）
node "C:/Users/lenovo/.workbuddy/binaries/node/workspace/node_modules/beyond-simulator-web/dist/server.js" \
     --workspace "C:/Users/lenovo/Desktop/千星游戏/千星割绳子游戏" --port 4173

# 2) 生成「浏览器试玩就绪」存档（依赖上一步的 sim-ready.save.json）
node _tools/qxqy_websave.mjs --game TickHop \
     --src _simulator/sim-ready.save.json \
     --out _simulator/TickHop.web.save.json --name "TickHop 试玩"

# 3) 命令行验证（不开浏览器也能确认脚本真的跑了）
node _tools/qxqy_webcheck.mjs

# 4) 浏览器打开
#    http://127.0.0.1:4173/          三栏静态预览
#    http://127.0.0.1:4173/editor    编辑工作台（「试玩」会开新标签页）
```

### 存档下拉的筛选规则

网页顶部的「工作区存档」不是「打开任意文件」，它扫描工作区下所有 `.json` 并筛选
（见 `beyond-simulator-web/dist/server.js` 的 `ia()`）：跳过 `node_modules/.git/dist/.dsh/coverage`、
大小限 20B~8MB、且**文件内容必须含子串 `qxqy-simulator-save`**。
`qxqy_websave.mjs` 会写入顶层 `kind` 字段来满足这个标记，同时写 `name` 作为显示名。

### ★ 入口脚本必须挂在 server 侧

studio 的试玩入口是：

```js
startPlay(projects.server, { templatesProject: projects.client, ... })
```

即**场景根取自 server 工程，client 工程只作为可实例化模板库**。
而 `resolveScriptTarget()` 在 `controlAsset` **为空**时按 `[server, client]` 顺序查找同 id 节点，
先命中 server；若显式写成 `client-control-template`，脚本会被挂到 **client 的模板根**上——
那个节点永远不会被实例化，于是**脚本静默不执行**，试玩画面只剩 server 工程自带的脚手架
（一个「文本」、一个蓝色「预设按钮」、一个「★」图片）。这正是 `qxqy_websave.mjs`
把入口挂成 `SERVER_ASSET` 的原因。

### 浏览器拦截弹窗

`/editor` 页的「试玩」按钮用 `window.open('about:blank')` 开新标签页，被拦截时会提示
「浏览器阻止了试玩标签页…」。两个办法：

1. 允许该站点弹出窗口（地址栏右侧的弹窗拦截图标）；
2. 直接访问试玩页：`http://127.0.0.1:4173/editor/play#<任意字符串>`
   （sessionId 由服务端懒创建，新 session 会自动载入最新存档）。

### ★ 网页端键盘输入：模拟器只映射了数字键（已打补丁）

**现象**：试玩页能跑，但按 WASD / 方向键 / 空格毫无反应。

**根因**：试玩页的按键映射函数只认数字键 1–9，其余物理键一律返回空串后在
`keydown/keyup` 里被丢弃（原始实现，压缩后是 `function Yu(i,t){…startsWith("Digit")…}`）：

```js
// studio/play/browser-session.js → keyEventName()
const digit = event.code?.startsWith('Digit') ? event.code.slice(5) : ''
if (digit && +digit >= 1 && +digit <= 9) return `KeyboardCraftspersonKey${digit}${phase}`
return ''
```

上游源码与已安装 bundle 都是这个实现，属**模拟器功能缺口**，与游戏工程无关。
好在服务端并不限制按键名：`playKey(typeName)` → `runtime.injectKey(typeName)` 是**按名字精确派发**，
只要 Lua 侧 `AddKeyEventListener` 注册过同名事件就能收到。

**修复**：`qxqy_webkeys.mjs` 把该函数替换成一张完整的
「物理键 `event.code` → 千星 `Enum.KeyEventType` 基名」映射表（56 个键，逐项取自
`_shared/Lua 客户端 UI 脚本 API.md` 的 Enum.KeyEventType「默认物理键」列）：

```bash
node _tools/qxqy_webkeys.mjs --check      # 当前状态
node _tools/qxqy_webkeys.mjs --apply      # 打补丁（自动备份 .qxbak）
node _tools/qxqy_webkeys.mjs --selftest   # 校验真实产物里 WASD/方向/空格等的映射结果
node _tools/qxqy_webkeys.mjs --probe      # 走 Web 接口端到端验证按键真的驱动了画面
node _tools/qxqy_webkeys.mjs --restore    # 还原
```

覆盖：WASD→移动、Space→跳跃、↑↓←→→奇匠 36–39、1/0/字母/F 键→奇匠 1–43、
E Q R T→角色技能 1–4、F→交互、X→落下、Tab→快捷轮盘、左Ctrl→切换行走/奔跑。
没有对应枚举的键（如 M）不映射，避免误吞浏览器快捷键。

打完补丁 **服务端无需重启**（静态资源每次请求都从磁盘读），但浏览器要 **Ctrl+F5 强制刷新**。

> `node_modules` 重装后补丁会丢失，重跑一次 `--apply` 即可。

#### 命令行驱动按键时的字段名（易踩）

Web 服务的 play 动作读的是 **`args.key`**，不是 `typeName`：

```js
// beyond-simulator-web/dist/worker.js
if (e === 'key') return Y.playKey(t.key, { observe: !1 }), Xe(t)
```

写成 `typeName` 会被 `String(undefined)` 吞掉、**静默不报错**（`autotest` 事件格式里才叫 `typeName`，
两套格式不同）。正确调用：

```bash
curl -s -X POST http://127.0.0.1:4173/editor/api/play \
  -H 'content-type: application/json' \
  -d '{"sessionId":"cli","action":"play","args":{"action":"key","args":{"key":"KeyboardMoveRightKeyDown"}}}'
```

#### ⚠️ 会话槽上限 8 个

`EditorSessionManager` 的 `maxSessions` 默认 **8**，**没有 CLI 开关可调**；每用一个**新的**
`sessionId` 就占一个槽，耗尽后所有请求都返回
`Editor session limit reached; save your work and restart the server`。

所有命令行工具因此统一复用 `sid = 'cli'`；一旦真的撞到上限，重启 Web 服务即可清空。

验证记录（2026-09-25）：

| 验证 | 命令 | 结果 |
|---|---|---|
| 映射表自检 | `--selftest` | 17/17 通过（含 `KeyM → ""` 不误映射） |
| 运行时链路（MCP） | `--key KeyboardMoveRightKeyDown --key-at 20 --probe-player 40` | 玩家 `x: -300 → -129.9`，`vx` 到上限 260 |
| 运行时链路（MCP，跳） | `--key KeyboardJumpKeyDown` | `vy` 由 0 → +466 后自由落体 |
| Web 端到端 | `--probe` | 场景 25 图元，3 个（玩家本体+双眼）发生位移，最大 213.4px |

### 平台秒数标签两态反色

平台亮起时底色变成亮色（`platform`），原来固定的深色标签会糊在一起。`level.refreshPlatforms()`
现在同时切换标签颜色：

| 平台状态 | 平台底色 | 标签色 | 来源 |
|---|---|---|---|
| 实体 / 亮起 | `palette.platform`（亮） | `palette.label`（深） | `DEFAULT_PLATFORM_ALPHA` = 255 |
| 虚化 / 熄灭 | `palette.ghost`（暗） | `palette.labelGhost`（浅） | `DEFAULT_PLATFORM_LABEL_GHOST_ALPHA` = 130 |

> ⚠️ 文本框控件要用 **`fontColor`** 改字色，写 `imageColor` 无效
> （见 `_shared/Lua 客户端 UI 脚本 API.md`）。`utils.setTextAlpha()` 负责「保留色相、只换 alpha」。

命令行核对（`_webprobe.mjs` / `_label_probe.mjs`）：

```
熄灭态 f=200  标签色 #829aa0ae  a=130 rgb=#9aa0ae   ← 浅灰蓝字 + 暗底
亮起态 f=250  标签色 #ff111114  a=255 rgb=#111114   ← 深字 + 亮底（#F2F2F2 平台）
✅ 两态颜色不同（已反色）
```

### 关卡导出 → 千星可直接执行

编辑器「导出」产出的是 `M.LEVELS = { … }` 片段（工程既定约定，见 `config.lua` 顶部注释）。
手工粘贴容易粘坏，用 `apply_levels.mjs` 一步落盘并自动校验：

```bash
# 编辑器下载 TickHop.levels.lua 后（在工作区根执行）
node _tools/apply_levels.mjs TickHop.levels.lua        # 替换 config.lua 的 LEVELS + 跑校验
node _tools/apply_levels.mjs TickHop.levels.lua --dry  # 只看摘要不落盘
node _tools/apply_levels.mjs --extract                 # 反向：导出 config.lua 现有的 LEVELS
```

替换按**大括号配平**扫描（跳过字符串与 `--[[ ]]` 注释里的花括号），不是正则找行，
所以片段里有嵌套表、注释、多行文本都安全；写盘前自动备份为 `config.lua.levels.bak`，
之后依次跑 `_check_blocks.py` 与 `_check_refs.py`（**按退出码判定**，不看文案——
`_check_refs.py` 成功时也会打印「0 处不一致」）。

编辑器侧已有 `_shared/_check_editor_roundtrip.js` 保证「导出 → 解析」无损（含 `labelGhost`），
两者合起来覆盖了「编辑器里看到的 = 千星里跑的」。

## 安装位置（已就绪）

- MCP：`C:\Users\lenovo\.workbuddy\binaries\node\workspace\node_modules\beyond-simulator-mcp`
- Web：`C:\Users\lenovo\.workbuddy\binaries\node\workspace\node_modules\beyond-simulator-web`
- MCP 配置：`C:\Users\lenovo\.workbuddy\mcp.json`（服务名 `qxqy-simulator`，工作区指向本仓库根）
  → 需在 WorkBuddy「连接器管理」里对该服务点「信任」后，工具才会出现在会话中。
  （未信任时用下面的 `qxqy*.mjs` 直接驱动即可，不依赖 MCP。）

## 快速开始（TickHop，已验证可跑通完整玩法）

```bash
# 1) 生成工程存档（仅首次 / 工程改动后需要重跑）
node _tools/qxqy_mount.mjs --game TickHop --entry game.lua --steps 1 --save _simulator/TickHop.save.json

# 2) 改造成「模拟器就绪」存档（补可染色模板 + 清掉装饰节点）
node _tools/qxqy_simsave.mjs --src _simulator/TickHop.save.json --out _simulator/sim-ready.save.json

# 3) 试玩（参数兜底 + 层级纠正 + 截图）
node _tools/qxqy_mount.mjs --game TickHop --entry game.lua \
     --open _simulator/sim-ready.save.json --preset sim \
     --steps 40 --fix-zorder 3
```

`--fix-zorder 3` 是**必须**的，原因见下节「模拟器渲染器 z 序反置」。

## qxqy_mount.mjs 参数

| 参数 | 说明 |
|---|---|
| `--game <目录>` | 工作区下的游戏目录（`TickHop` / `割绳子`） |
| `--entry <文件>` | 入口脚本，挂载到控件上（其余脚本仅注册为 require 模块） |
| `--mount <id>` | 挂载目标控件，默认自动挑第一个容器 |
| `--open <存档>` | 打开已有存档；省略则新建空工程 |
| `--save <路径>` | 保存存档 |
| `--steps <n>` | 试玩推进帧数（每帧 1/30 秒） |
| `--preset sim` | 注入模拟器就绪存档的模板 guid 作为脚本参数 |
| `--params '<json>'` | 手动指定/覆盖脚本参数 |
| `--fix-zorder <帧>` | 抵消模拟器渲染器的 z 序反置 + 把平台标签提到最上层 + 隐藏默认工程脚手架 |
| `--signal <名> [--signal-str <值>]` | 模拟服务器下发一个客户端信号 |
| `--key <Enum.KeyEventType 名>` | 可重复；配合 `--key-at <帧>` 在第 N 帧注入按键事件。也可写 `--key Name@45` 逐键指定帧号（多键接力必备，如先空格进建造、再 F 放置） |
| `--key-at <帧号>` | `--key` 未写 `@帧号` 时的默认注入帧 |
| `--no-freeze` | 不冻结模拟器实时钟。默认**会**先 `pause` 掉那路 33ms 自动推进，使「`--steps n` 帧」==「引擎 frame n 帧」；见「注入帧号漂移」 |
| `--probe-player <帧数>` | 逐帧打印玩家位姿 `x/y/vx/vy` + 输入链路（`keys`/`kR`/`ix`）+ 世界摘要（`mat`/`land`/`star`）+ `build`/`cur`/`won`/`mode`/`face`，并附 `[K]` 引擎派发打点 |
| `--teleport-goal <帧号>` | 在第 N 帧把玩家直接放到星门格，验证 `checkGoal` → 结算面板（免去把整关建造编排硬编码进命令行） |
| `--probe <帧>` / `--probe start` | 用 `game.PrintClientUITree()` 转储控件树（进 logs） |
| `--probe-walk <帧>` | 逐控件打印 `act/vis/pos/size/color`（可定位「存在但不显示」） |
| `--probe-timeline <帧>` | 逐帧打印黑幕 alpha 与各容器子节点数 |
| `--scene` | 转储截图渲染真正消费的 `scene.nodes` |
| `--tree` | 打印 play `get` 返回的 state 概览 |
| `--stretch <帧>` / `--hide-bg <帧>` | 诊断用：撑大 / 隐藏指定容器 |

## ⚠️ 注入帧号漂移：「第 N 圈循环」≠「引擎第 N 帧」

**现象**：`--key KeyboardMoveRightKeyDown --key-at 20` 有时玩家纹丝不动，有时却能动，
而且改个 `--steps` 结果又不一样，看起来像「按键随机失灵」。

**根因**：模拟器 worker 里除了我们显式调用的 `step`，还有一个**独立的实时钟**在推进帧
（`studio/host/worker.js`）：

```js
const CLOCK_INTERVAL_MS = 33
const clockTimer = setInterval(tickClock, CLOCK_INTERVAL_MS)   // 按墙钟时间补帧
function tickClock() {
  const status = studio.playStatus()
  if (!status.running || status.paused) { lastTick = 0; accumulator = 0; return }
  accumulator += Math.min(0.25, Math.max(0, (now - lastTick) / 1000))
  while (accumulator >= FIXED_DT && steps < MAX_CATCHUP_STEPS) { studio.playStep(FIXED_DT, …) }
}
```

于是 `qxqy_mount.mjs` 的循环圈数（每次 `await` 一轮 MCP 往返）与引擎真实帧号会脱钩，
**偏移量随往返耗时在 10~20 帧之间漂移**。实测对照（同一个 `--key-at 20`，`--probe-player` 里的 `[K]` 打点）：

```
# 引擎第 20 帧注入按键        ← 挂载循环自报的帧号
[K] 引擎派发 … @f=30 keys=true kR=false   ← 引擎真实帧号是 30（漂了 10 帧）
```

**为什么以前没被发现**：`--probe-player` 的探针带 `__pFrame <= maxFrame` 截断，
而调用时 `maxFrame` 恰好等于 `--steps`，多出来的帧**不会打印**，
`grep -c` 出来的行数永远等于 `--steps`，看起来时序完全确定。

**规避**（`qxqy_mount.mjs` 已内置）：推进前先 `action: 'pause'`。
它只置 `session.debugPaused`，切掉上面那路自动推进；**显式 `step` 仍会正常调用
`OnUpdate` / `OnLevelUpdate`**（`clock.paused` 是另一条由 Lua `SetLevelTimePaused` 控制的开关，
`pause` 不会碰它）。冻结后：

```
引擎第 40 帧注入按键
[K] 引擎派发 … @f=39 keys=true
# 推进结束：引擎 frame=90 time=3.000s     ← 与 --steps 严格相等
```

于是 `--key-at` 变成**可精确复现的引擎帧号**。用 `--no-freeze` 可退回旧行为。

### ⚠️ 配合它一起踩到的坑：黑幕过渡期会吞掉按键

冻结帧号后暴露出来的真实行为——`loadLevel()` 会 `fadeScreen.start()` 并显式置
`state.keysEnabled = false`，**待黑幕散尽（约 23 帧 ≈ 0.75s）才在 `OnUpdate` 里放开**：

```
f=26 keys=true        ← 黑幕散尽，开始接受操作
f=20 注入 → keys=false → 监听器 return false → 被丢弃，玩家全程静止（正确行为）
f=40 注入 → keys=true  → kR=true → vx 0→201.6 px/s，x 240→513.6（正确驱动）
```

所以**任何「按键没反应」的排查都要先看注入帧是否落在过渡期里**——
`--probe-player` 的 `keys=` 列和 `[K]` 打点就是为这个加的。

## 已解决：原「两个能力缺口」

### 1. 脚本参数不传递 → 用参数兜底解决（不改工程源码）

模拟器的 params 链路在三处断掉：`studio` 的 `addScript` 丢弃 `op.params` →
`compileProject` 不带 `params` → `mountSpecScripts` 不转发，于是 `script:GetParam()` 恒为 `nil`，
工程里「必填参数没配」的校验会把整局挡在 `OnStart` 之外。

**两条路都试过**：

- ❌ 覆写 `script.GetParam` —— 不行。`script` 带 `Script` metatable，禁止写同名字段
  （报 `cannot set GetParam, no such field`）。
- ✅ 覆写工程的 `getParamNumber` —— 可行。它是脚本环境里的普通全局函数，在入口脚本**末尾**
  追加一段覆盖即可（`OnStart` 由引擎在 chunk 执行完后才调用，此时覆盖已生效）。

`qxqy_mount.mjs` 的 `--params` / `--preset sim` 就是干这个的：只在模拟器内注入，**`.lua` 源文件一行未动**。

### 2. UI 控件树不存在 → 用「模拟器就绪」存档解决

模拟器的 prefab 注册规则是 `registerTemplate(prefabIndex = node.guid)`，取自 **client 工程
`root.children`**。所以 `qxqy_simsave.mjs` 在存档里补两个模板节点：

| guid | kind | 用途 |
|---|---|---|
| 1073741870 | image（`imageId: 100001` = `rect` 原语） | 可被 `imageColor` 染色的纯色底图 → `rectPrefabId` |
| 1073741868 | textbox | 文本 → `textPrefabId` |

> ★ 这两个 guid **刻意与真机编辑器内置模板的元件索引同源**（原来的自造值 2000001/2000002
> 已废弃）。这样游戏里 `config.DEFAULT_PREFAB_*` 的回退值在模拟器和真机**两边都能命中**，
> 不会再出现「模拟器跑通、搬进真机还要另填参数」的错位。
> 索引来源见 `_shared/编辑器元件索引.md`。
> 改 guid 要同时改 `_sim_common.mjs` 的 `SIM_TEMPLATE_GUIDS` 与 `qxqy_simsave.mjs` 的两个
> `GUID_*` 常量（前者的值会经 `--preset sim` 灌进参数兜底，两者必须一致），然后重新生成存档。

> ⚠️ **别把「模拟器画面」当「真机画面」的担保。** 模拟器**只代理** `100001–100006` 六种
> 基础图元（`100001` 矩形 / `100002` 圆 / `100003` 等腰三角 / `100004` 四角星 /
> `100005` 五角星 / `100006` 圆环），其余 `imageId` 一律画成缺失框。这里
> `imageId: 100001` 就是拿矩形代理替身，**不是官方素材 ID**，真机不认。
> 所以「模拟器里格子是漂亮的纯色矩形」推不出「真机也是」——
> 真机那边图片元件没配图的话，画面会是满屏彩色的 **`?`**。
> 排查与修法见 `_shared/编辑器元件索引.md` 第二节。

原型节点直接克隆存档里已有的 image / textbox 节点，保证 `giaRaw`、`transformByPlatform`
等结构合法；再清空模板根 `n1` 的装饰子节点、清空脚本表（由挂载驱动重新灌入）。

## ⚠️ 模拟器缺陷：宿主截图渲染器 z 序反置

**现象**：工程逻辑完全正确（倒计时在走、关卡已建成），但截图里只剩一片背景色。

**根因**（`dist/index.js`，`Rs` 收集 + `Bs` 排序绘制）：

- `Rs` 里 `z: r` = 节点在**父节点 children 数组中的下标**（`a(m[g], c.Id, p, g)`）；
- `Bs` 里 `for(let s=c.length-1; s>=0; s-=1)` —— 按 **z 降序**入队，而 `Us` 顺序绘制，
  于是**下标越小越靠上**；
- 但 `Control.children` 是按创建顺序 `push` 的，且 `GetSiblingIndex()` 返回 `len-1-数组下标`、
  `SetSiblingIndex(t)` 实际插到 `len-1-t` —— 即模拟器内部约定「数组下标 0 = 最上层」。

三者叠加的后果：**工程里第一个创建的背景容器排在下标较小处 → 被画到最顶层 → 盖住平台/玩家/HUD**；
而默认工程的脚手架（下标更小）反而露在外面，极具误导性。

对照实验（`_px.mjs` 采样）：frame12 整屏 `#111114`，正是工程背景色 `0xFF111114`。

**规避**：`--fix-zorder <帧>` 在模拟器内把 7 个容器依次 `SetAsFirstSibling()` 送到数组末尾，
使绘制顺序变成 `bg → platform → goal → pickup → player → hud → fade`，与真机一致；
顺带隐藏默认工程自带的脚手架节点（文本框/预设按钮/图片…）。**工程源码未改**。

### 兄弟顺序：用 `SetAsFirstSibling` / `SetAsLastSibling`，别碰 `SetSiblingIndex`

`SetSiblingIndex(i)` 在模拟器里是**反的**——它实际插到数组下标 `len-1-i`：

```js
// client/lua-runtime/src/scene.js
SetSiblingIndex(index) { const arr = this._parent.children; const i = arr.indexOf(this);
  const max = arr.length - 1; arr.splice(i, 1); arr.splice(max - index, 0, this); }
SetAsFirstSibling() { return this.SetSiblingIndex(0) }                 // → 落到数组末尾
SetAsLastSibling()  { return this.SetSiblingIndex(arr.length - 1) }    // → 落到数组下标 0
```

好消息是两个便捷方法的**实际效果与真机一致**：`SetAsFirstSibling()` = 最先绘制 = 最底层，
`SetAsLastSibling()` = 最后绘制 = 最顶层。所以只用这两个，不要自己算索引。

### ⚠️ 容器内部同样反置：亮起的平台会盖住它自己的秒数标签

`containerPlatform` 的子节点是按创建顺序 push 的 `[平台1本体, 平台2本体, 平台2标签]`。
真机里后创建的在上面，所以工程代码是对的；但模拟器反置后，**标签被压在两个本体下面**——
熄灭态本体 `alpha=40` 还能透出来，**亮起态本体 `alpha=255` 就把数字完全盖住**，
看起来像「标签没画」。

`--fix-zorder` 现在会**每帧幂等**地对每个平台标签调用 `SetAsLastSibling()`。
必须每帧做，不能只在修正帧做一次：平台是黑幕散尽后才建的，比容器晚得多。

### ⚠️ 同样反置的还有两处（已一并修正）

| 容器 | 症状 | 修正（每帧幂等） |
|---|---|---|
| `containerMenu` | 最先建的**遮罩盖住整个面板**；卡片文字被自己的底色压住 | `lift` 卡片/按钮/箭头 label 与 title/subtitle/footer；`sink` **先 `menuPanel` 再 `menuOverlay`**（遮罩要盖游戏画面，但不能盖面板） |
| `containerHud` | 触屏虚拟按钮（`← → 跳`）与「关」入口按钮是「先建底图、后建标签」→ 标签被底图盖住，**只剩空方块** | 把 HUD 里**所有有文字的文本控件**提到最上层（`text` 是属性字段，图片控件读它进 `pcall` 的 error 分支，安全跳过）。HUD 内没有任何控件需要盖住文字 |

> 规律：**真机上「后创建的在上」，模拟器里整个反过来**。凡是「底图 + 覆盖其上的文字」这种
> 两节点组合，都要显式 `SetAsLastSibling()` 把文字提上来。新增任何容器/覆盖式 UI 时先想这一条。

> 排查提示：`_label_probe.mjs` 会打印所采区域的 **ASCII 位图**。
> 只看「最暗/最亮对比度」会被平台之外的背景像素骗到（背景本来就暗，看起来像有深色字符），
> 必须肉眼看形状——数字会是一个明显的块状图案。

> 注意：`beyond-simulator-web` 的 `dist/worker.js` 与 MCP 是同一份 bundle，
> 所以 **Web 编辑器的试玩预览也是同样的反置**，不是本工程的问题。

## ⚠️ 中文字体字形覆盖：别用 `◀` `▶` `✓`

引擎 UI 用的是中文字体，而**中文字体对「几何图形 / 装饰符号」区段的覆盖很差**。
实测（`glyph_check.mjs`，位图比对私用区码位，可靠）：

| 符号 | U+ | 雅黑 | 宋体 | 黑体 |
|---|---|---|---|---|
| `◀` `▶` | 25C0 / 25B6 | 缺 | 缺 | 缺 |
| `✓` | 2713 | 缺 | 缺 | 缺 |
| `←` `→` `↑` | 2190 / 2192 / 2191 | 有 | 有 | 有 |
| `√` `★` `◆` `·` `×` | 221A / 2605 / 25C6 / B7 / D7 | 有 | 有 | 有 |

缺字形会渲染成**豆腐块**。所以界面文本一律只用第二组：

- 触屏按钮 `◀ ▶` → `← →`
- 翻页箭头 `◀ ▶` → `← →`
- 「下一关 `▶`」 → 「下一关 `→`」
- 通关标记 `✓` → `√`

新增任何符号前，先跑 `node _tools/glyph_check.mjs` 确认覆盖。
（`★` 在 `.lua` 注释里大量使用，注释不渲染所以无所谓，但**字符串里要小心**。）

## 已知缺口（剩余）

1. **割绳子暂不可试玩**：其 `OnStart` 需要根节点下存在具名控件 `DropArea` / `MessageText` /
   `ScoreText`（真机编辑器里配置的），模拟器存档没有 → 报「未找到 DropArea」。
   要跑通需在就绪存档里补这三个具名节点。
2. 图片只代理 `100001–100006`（`rect/circle/triangle/fourstar/fivestar/ring`）；
   服务端不含官方节点图；**模拟器通过 ≠ 真机通过**。
3. 上游为发布的 bundle（`dist/index.js` + `dist/worker.js`），与仓库源码版本可能不一致；
   排查行为时**以 bundle 为准**。
4. 键盘映射已由 `qxqy_webkeys.mjs` 在本地补丁修复（见上节），但这是**对第三方包的改动**，
   升级/重装 `beyond-simulator-web` 后需重跑 `--apply`；上游若要彻底解决，
   应修改 `studio/play/browser-session.js` 的 `keyEventName()`。

## Web 编辑器

```bash
node "C:/Users/lenovo/.workbuddy/binaries/node/workspace/node_modules/beyond-simulator-web/dist/server.js" \
     --workspace "C:/Users/lenovo/Desktop/千星游戏/千星割绳子游戏" --port 4173
```

- `http://127.0.0.1:4173/` 只读预览工作区存档（配合 MCP 时自动刷新）
- `http://127.0.0.1:4173/editor` 可视化编辑 UI / Lua / 服务端逻辑并试玩
- `http://127.0.0.1:4173/health` 存活检查
