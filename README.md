# 千星奇域小游戏工作区

用 Lua 驱动千星奇域客户端 UI 开发的小游戏集合。每个游戏一个独立目录，公共资产集中在 `_shared/`。

```
千星游戏/
├── README.md            ← 本文件
├── _shared/             ← 跨游戏公共层
│   ├── Lua 客户端 UI 脚本 API.md          ← 引擎 API 文档（唯一权威）
│   ├── 千星沙箱客户端脚本使用指南.docx
│   ├── miliastra_lib.lua                  ← EmmyLua 类型桩（仅提示，非 API 依据）
│   ├── _check_blocks.py                   ← Lua 块平衡检查
│   └── _check_refs.py                     ← 跨文件引用一致性检查
│
├── 割绳子/               ← 游戏一：绳索物理益智
├── TickHop/             ← 游戏二：时间解谜平台跳跃（滴答咔哒）
│
├── _tools/              ← 本地开发工具：千星沙箱模拟器 + MCP 驱动器（非交付物）
└── _simulator/          ← 模拟器存档与试玩截图（非交付物）
```

## 本地试玩与调试（千星沙箱模拟器）

用 [miliastra-beyond-simulator](https://github.com/1475505/miliastra-beyond-simulator) 在**游戏之外**
运行客户端 Lua、模拟试玩、截图，并模拟「服务器→客户端」信号——不必反复开真机。

```bash
# 把某个游戏的全部 Lua 灌入模拟器并试玩
node _tools/qxqy_mount.mjs --game TickHop --entry game.lua --steps 3

# 试玩中模拟服务器下发信号（验证入站链路）
node _tools/qxqy_mount.mjs --game TickHop --entry game.lua --signal 进入关卡 --signal-str 2

# ★ 一键启动：双击「启动千星模拟器.bat」即可，或在 shell 里跑
node _tools/dev_open.mjs          # 查环境 → 补键盘映射 → 重建存档 → 起服务 → 开浏览器
node _tools/dev_open.mjs play     # 同上，但直接打开试玩页
node _tools/dev_open.mjs --restart  # 先关掉旧服务再起（可清 session 槽上限）

# → http://127.0.0.1:4173/        存档预览
# → http://127.0.0.1:4173/editor  可视化编辑 + 试玩
```

> 一键脚本全部幂等：服务已在跑就复用，Lua 改过就自动重建试玩存档，
> `node_modules` 重装后会自动补回键盘映射补丁。重复双击是安全的。

详见 [`_tools/README.md`](./_tools/README.md)。
MCP 已配置在 `~/.workbuddy/mcp.json`（服务名 `qxqy-simulator`），需在连接器管理里点「信任」后工具才进会话。

## 游戏一览

| 目录 | 玩法 | 内核 | 文档 |
|---|---|---|---|
| `割绳子/` | 切断绳索，把糖果送进小怪兽嘴里 | 绳索约束物理 + 像素渲染 | [README](./割绳子/README.MD) |
| `TickHop/` | 倒计时中踩着按秒数亮灭的平台抵达终点 | 时间状态机 + AABB 平台跳跃 | [README](./TickHop/README.md) · [实现方案](./TickHop/实现方案.md) |

两个游戏共享同一套工程约定：`config.lua` 作参数真源、`state.lua` 集中托管状态、容器化父节点管理 UI 层级、黑幕过渡掩护关卡切换、编辑器 `DEFAULTS` 与 `config` 强制同步。

## 静态校验

改完任一游戏的代码后，在 `_shared/` 下执行（参数指向目标游戏目录）：

```bash
# Lua 块平衡：function / if / for / while / do / repeat 与 end / until 的配对
python _check_blocks.py ../割绳子
python _check_blocks.py ../TickHop

# 跨文件引用一致性：
#   ① require 目标是否存在
#   ② 模块调用 mod.fn() 是否已定义
#   ③ state.xxx 是否在 state.lua 声明
#   ④ config.<常量> 是否在 config.lua 定义
#   ⑤ 编辑器.html 的 DEFAULTS 与 config.lua 的 DEFAULT_* 是否逐项一致
python _check_refs.py ../割绳子
python _check_refs.py ../TickHop
```

两个脚本均按目录自适应（模块集合自动扫描），新增游戏目录后可直接复用。

## 编辑器的 JS 语法检查

```bash
# 抽出编辑器内嵌的 <script> 后用 node 校验
python -c "import re;open('_tmp/editor.js','w',encoding='utf-8').write(re.search(r'<script>([\s\S]*?)</script>',open('TickHop/编辑器.html',encoding='utf-8').read()).group(1))"
node --check _tmp/editor.js
```

## 新增一个游戏的推荐流程

1. 建目录（中文名或英文名均可）
2. 从 `_shared/` 取 API 文档作为唯一 API 依据，核对待用接口
3. 按分层建模块：`game` / `config` / `state` / 玩法内核 / `physics` / `utils` / `audio` / `signal` / `fadeScreen`
4. `config.lua` 只放 `DEFAULT_*` 与关卡数据，作为参数真源
5. 编辑器 `DEFAULTS` 的 key 用「`DEFAULT_*` 去掉前缀并小写」的形式，保证能被校验器机械比对
6. 跑两个校验脚本，全绿再交付
