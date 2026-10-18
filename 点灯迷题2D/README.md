# 点灯迷题 2D · 千星奇域客户端 Lua 工程

> **纯客户端 2D 版**：棋盘、玩法、判定、动效全部在客户端 Lua 里完成，
> **不需要服务器节点图**（旧版是「客户端只做 UI + 3D 棋盘在节点图里」）。
>
> 5 行 × 6 列灯阵 · 50 关 · 点一格翻转十字五格 · 全灭即通关。

---

## 一、和旧版（`点灯迷题/`）的区别

| | 旧版 `点灯迷题/` | 本作 `点灯迷题2D/` |
| --- | --- | --- |
| 棋盘 | 3D 场景，服务器节点图绘制 | **客户端控件 2D 绘制** |
| 玩法判定 | 节点图 | **客户端 `board.lua`** |
| 信号 | 4 条（进入关卡 / 重玩 / 让客户端进入 / 关卡胜利） | 默认**不需要**；只有 `DEFAULT_SIGNAL_ENABLED=1` 时上报战绩 |
| 装一个就能跑 | 还要配节点图 | ✅ 只挂 `game.lua` + 三个模板元件 |

> ⚠️ 两个目录互不影响，可以同时存在；确认新版没问题后再决定是否删旧版。

---

## 二、玩法

- 30 盏灯，点任意一格 → **它自己 + 上下左右**一起翻转（越界忽略）。
- 全部熄灭即通关；步数越少星级越高。
- **数学性质**（本作两个功能靠它）：
  ① 同一格按两次等于没按（撤销 = 再按一次）；
  ② 按压可交换，结果只与「按过的格子集合」有关。
  ⇒ 关卡由 `flips` 从全灭盘生成，于是 **剩余解 = `flips` 集合 XOR 已按集合**，
     提示与星级判定都是**精确**的，不需要解方程。

---

## 三、动效清单（重点）

全部由 `anim.lua`（自研逐帧补间：缓动 + tag + `isBusy`）驱动，**不用引擎 Tween**，
真机与模拟器行为一致。

| 场景 | 动效 |
| --- | --- |
| 点击 | 棋盘该格立刻**横向压扁 → 展开**（翻牌，不是变色），同时从格心打出**方形冲击波** |
| 涟漪 | 十字五格按**距中心远近**错峰 32ms 依次翻转，像光波扩散；同环内带随机抖动 |
| 点亮 | 白色闪光 → 灯体换暖色 → 顶面高光冲高再回落 + **暖色粒子迸溅** |
| 熄灭 | 冒一缕**冷色轻烟**（向上飘、更快消失） |
| 呼吸 | 亮灯有**光晕呼吸**，相邻格相位错开（整屏像活的灯海）；剩 ≤3 盏时呼吸加剧 |
| 连击 | 0.62s 内连按 → 翻转时长压到 0.72 倍，手感更跟手 |
| 入场 | 灯格从「缩到 0 + 略偏下」按左上→右下错峰 `outBack` 弹出 |
| 通关 | 一道光**斜扫过棋盘** → 棋盘缩成**战利品照片**飞到左侧（微倾斜）→ 结果卡从右侧 `outBack` 滑入 → **三星逐颗弹出**（带旋转）→ 步数**滚动增长** → 三个按钮依次落位 |
| 选关 | 遮罩淡入 → 面板「由小托起」落定 → 卡片按顺序错峰弹出；翻页整页横移 |
| 数值 | 步数 / 剩余灯变化时数字**弹一下**；剩余归零瞬间转绿 |
| 输入 | 动画期间锁输入，只缓冲**最后一次**点击；解锁看门狗超时强制放行，绝不永久卡死 |

---

## 四、模块与依赖

```
game.lua          入口：生命周期 / 层级容器 / 输入 / 关卡流转 / 通关
 ├─ config.lua    ★ 全部 DEFAULT_* 参数 + 50 关数据（唯一真源）
 ├─ state.lua     ★ 所有 state.* 字段集中声明
 ├─ utils.lua     控件创建（矩形/文本/命中区）、配色、布局换算、自绘按钮
 ├─ anim.lua      逐帧补间引擎（ease / tag / isBusy）
 ├─ board.lua     灯阵模型：翻转、全灭判定、剩余解、提示（纯计算）
 ├─ view.lua      棋盘视图：灯格 / 翻牌 / 涟漪 / 呼吸 / 照片态
 ├─ fx.lua        粒子 / 轻烟 / 方形冲击波 / 飘字 / 彩带 / 震屏
 ├─ hud.lua       右侧信息栏（关卡 / 步数 / 剩余灯 / 四个按钮 / 提示）
 ├─ menu.lua      50 关选关（分页 / 星级 / 错峰入场）
 ├─ winUI.lua     通关结算（结果卡 / 三星 / 步数滚动）
 ├─ fadeScreen.lua 黑幕过渡
 ├─ audio.lua     音效（ID ≤ 0 静默跳过）
 └─ signal.lua    可选的服务端对接（默认关闭）
```

`require` **一律带导入根**：`require("default_import_file/config")`。
裸名只在旧存档兼容层有效，用编辑器的「导入文件」会直接报 `failed to load script`。

---

## 五、在千星沙箱里装配

1. **建容器**：新建一个引用「客户端控件容器」的元件实例，放到场景里。
2. **备三个模板元件**：

   | 参数名 | 元件类型 | 用途 | 必填 |
   | --- | --- | --- | --- |
   | `rectPrefabId` | 纯色矩形（图片控件） | 背景 / 面板 / 灯格 / 按钮底 / 粒子**全部**用它染色 | ★ |
   | `textPrefabId` | 文本框 | 所有文字 | ★ |
   | `cursorPrefabId` | 光标检测区域 | **所有可点区域** | ★ |

   > **为什么必须用「光标检测区域」**：`AddCursorEventListener` 只对「预设按钮 / 光标检测区域」有效，
   > 图片控件上挂会被 `pcall` **静默吞掉** → 「画得出来但点不动」。
3. **导入脚本**：把本目录 14 个 `.lua` 全部导入到 `default_import_file/`（根目录，不要建子目录）。
4. **挂脚本**：把 `game.lua` 挂到第 1 步的**容器节点**上，填三个模板索引。
   音效可选：`flipAudioId` / `clickAudioId` / `openAudioId` / `winAudioId` / `starAudioId`。
5. **试玩**：进入关卡即出现选关界面；点任意关卡开始。

### 开发用脚本参数（正式不要传）

| 参数 | 作用 |
| --- | --- |
| `autoStart` | `1` = 跳过选关直接进第 1 关（无头截图 / 冒烟测试） |
| `autoPress` | 填格子下标（0 基），1.4 秒后自动按一次，用来验证翻牌与通关链路 |

---

## 六、层级结构（从下到上）

```
容器节点（game.lua 挂这里）
└─ containerScene（整体缩放 k，自适应任意画布）
   ├─ containerBg        背景与装饰光斑
   ├─ containerBoard     棋盘根 ★ 通关时整体缩成「照片」
   │  ├─ containerBoardBg  描边 / 底板 / 30 个格位底
   │  └─ containerTile     30 个灯格（每个含 光晕/灯体/闪光/顶面高光/命中区）
   ├─ containerFx        粒子 / 冲击波 / 飘字
   ├─ containerHud       右侧信息栏
   ├─ containerMenu      选关
   ├─ containerWin       通关结算
   └─ containerFade      黑幕（永远最顶）
```

> 重排层级**只用** `SetAsFirstSibling` / `SetAsLastSibling`（两引擎一致），
> **绝不用 `SetSiblingIndex(i)`** —— 模拟器里它实际插到 `len-1-i`。

---

## 七、调参

只改 `config.lua`。常用的几组：

| 组 | 参数 |
| --- | --- |
| 手感 | `DEFAULT_ANIM_FLIP_HALF` / `DEFAULT_ANIM_FLIP_BACK` / `DEFAULT_ANIM_STAGGER` / `DEFAULT_COMBO_WINDOW` / `DEFAULT_INPUT_BUFFER` / `DEFAULT_SETTLE_GUARD` |
| 观感 | `DEFAULT_PALETTE`（配色）/ `DEFAULT_CELL` / `DEFAULT_GAP` / `DEFAULT_BREATH_*` |
| 特效 | `DEFAULT_FX_*` |
| 星级 | `DEFAULT_STAR_TWO_EXTRA`（最优步数 +N 以内得 2 星） |

---

## 八、校验与试玩

```bash
# 静态校验（看退出码，不看文案）
cd E:/千星/千星游戏
python _shared/_check_blocks.py 点灯迷题2D
python _shared/_check_refs.py   点灯迷题2D

# 无头模拟器：进第 1 关
export NODE_PATH="$HOME/.workbuddy/binaries/node/workspace/node_modules"
node _tools/qxqy_mount.mjs --game 点灯迷题2D --entry game.lua \
  --preset sim --open _simulator/sim-ready.save.json --mount n1 \
  --params '{"cursorPrefabId":2000001,"autoStart":1}' --steps 45

# 再自动按一下第 1 关的解法格（19），一路跑到结算
node _tools/qxqy_mount.mjs --game 点灯迷题2D --entry game.lua \
  --preset sim --open _simulator/sim-ready.save.json --mount n1 \
  --params '{"cursorPrefabId":2000001,"autoStart":1,"autoPress":19}' --steps 135
```

**已实测**：静态校验 0 问题；模拟器里 选关 → 进关 → 翻牌 → 全灭判定 → 通关动效 → 结算面板
全链路无报错（截图见 `_simulator/shots/`）。

> 截图里偶尔出现的「文本 / 白色大星 / 蓝色横条」是**模拟器就绪存档自带的模板节点**，
> 不是本工程的控件；真机上不存在。

---

## 九、已知边界 / 后续可做

- **没有 `编辑器.html`**：本版参数全部手改 `config.lua`。需要可视化调版式可以后补。
- **进度持久化默认关闭**：`DEFAULT_PROGRESS_SAVE` / `DEFAULT_SIGNAL_ENABLED` 为 0 时，
  通关记录只活在本次会话。要跨设备保留，见 `signal.lua` 顶部的两件事（建变量 + 写变量的节点图）。
- **没有音效资源**：只留了 ID 参数，没配就是静音。
- 灯格是纯方块（引擎无圆角），靠「外描边 + 顶面高光 + 光晕」做体积感。
