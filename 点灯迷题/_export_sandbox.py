# -*- coding: utf-8 -*-
"""导出《点灯迷题》的「千星沙箱导入包」。

为什么需要这个脚本
------------------
千星沙箱的「导入文件」把每个脚本注册在虚拟根 `default_import_file/` 下，
工程里写的 `require("default_import_file/config")` 才能解析。

★ 千万不要拿「模拟器试玩存档」里导出的脚本去挂沙箱：
  `_tools/qxqy_websave.mjs` 为了让浏览器试玩能跑，会给**入口脚本**追加一段
  模拟器专属补丁（脚本参数兜底 + 容器层级修正）。那段补丁在真机上会：
    · `isMine[c.Id] = true` → 控件没有 Id 字段时直接抛 `table index is nil`（每帧一次）
    · 参数兜底会把 rectPrefabId 回退成模拟器模板 guid(2000001)，真机上是别的元件
  本脚本只从**工程源文件**复制，并逐项自检，确保导入包永远干净。

用法
----
    python 点灯迷题/_export_sandbox.py          # 导出 + 自检
    python 点灯迷题/_export_sandbox.py --check  # 只自检，不写文件

产出
----
    点灯迷题/_sandbox/default_import_file/*.lua   ← 整目录导入沙箱
    点灯迷题/_sandbox/导入清单.md

退出码：0 = 全部通过；1 = 有自检项失败（不会留下半成品）
"""

from __future__ import annotations

import argparse
import re
import shutil
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
OUT_DIR = HERE / "_sandbox"
DST_DIR = OUT_DIR / "default_import_file"

# 交付的 14 个脚本，顺序即建议的导入顺序（入口在前，便于对照）
MODULES: list[tuple[str, str]] = [
    ("game.lua",       "主入口。OnStart 建 7 层容器与全部 UI，OnUpdate 推动效，收/发 4 条信号"),
    ("config.lua",     "参数唯一真源：DEFAULT_* 可调项 + 夏日配色 + 50 关 LEVELS 数据"),
    ("state.lua",      "全部运行期状态字段（容器引用、面板控件、当前关卡…）"),
    ("utils.lua",      "颜色/文本/透明度工具 + createControl/createText + createHit（可点击区域）"),
    ("fx.lua",         "果汁粒子池（矩形粒子）+ 通用补间 fx.to + 缓动，全部动效的底座"),
    ("bg.lua",         "夏日背景：天空/海面/沙滩/波浪/柔光 + 上升气泡"),
    ("signal.lua",     "与节点图对接的唯一接口：4 条信号的名字、参数打包与解析"),
    ("puzzle.lua",     "点灯棋盘纯计算（5×6、idx=行*6+列、按下翻转自身+四邻）"),
    ("menu.lua",       "选关界面：分页卡片 + 难度条 + 光标 + 翻页 + 弹入动效"),
    ("tutorial.lua",   "图文教程：5 页，用基础图元拼棋盘示意，翻页滑入"),
    ("hud.lua",        "游玩期极简 HUD：左上信息条（滑入）+ 右下「教程/退出」"),
    ("winUI.lua",      "胜利结算：三星逐颗弹出 + 果汁迸溅 + 12 格跑马灯"),
    ("fadeScreen.lua", "黑幕过渡（切场景时压黑→峰值回调→散开）"),
    ("audio.lua",      "音效播放封装（click/open/win 三个脚本参数）"),
]

MODULE_COUNT = len(MODULES)

# 模拟器注入痕迹：出现任意一个就说明这份文件不是纯工程源文件
FORBIDDEN = [
    "[SIM_ONLY]",
    "[SIM_ZFIX]",
    "qxqy_websave",
    "qxqy_mount",
    "__simFallback",
    "containerPlayer",   # TickHop 的容器名，点灯迷题里不该出现
    "containerPlatform",
    "buildParamShim",
    "buildZOrderFix",
]

# 沙箱里 require 必须带导入根前缀
REQUIRE_RE = re.compile(r'require\s*\(\s*"([^"]+)"\s*\)')
REQUIRE_PREFIX = "default_import_file/"


def read(p: Path) -> str:
    return p.read_text(encoding="utf-8")


def main() -> int:
    ap = argparse.ArgumentParser(description="导出《点灯迷题》千星沙箱导入包")
    ap.add_argument("--check", action="store_true", help="只自检，不写文件")
    args = ap.parse_args()

    problems: list[str] = []
    sources: dict[str, str] = {}

    print("=" * 60)
    print("《点灯迷题》千星沙箱导入包 · 导出与自检")
    print("=" * 60)

    # ---- 1) 收集源文件 ----
    print("\n[1/4] 收集工程源文件")
    for name, _desc in MODULES:
        p = HERE / name
        if not p.exists():
            problems.append(f"缺少源文件：{name}")
            print(f"      ✘ {name} 不存在")
            continue
        sources[name] = read(p)
        print(f"      ✔ {name:<18} {len(sources[name].splitlines()):>4} 行")

    lua_files = sorted(p.name for p in HERE.glob("*.lua"))
    extra = [n for n in lua_files if n not in sources]
    if extra:
        problems.append(f"目录里有多余的 .lua 未纳入交付：{', '.join(extra)}")
        print(f"      ✘ 未纳入交付的 .lua：{', '.join(extra)}")

    # ---- 2) 自检 ----
    print("\n[2/4] 自检")
    for name, src in sources.items():
        hits = [t for t in FORBIDDEN if t in src]
        if hits:
            problems.append(f"{name} 含模拟器注入痕迹：{', '.join(hits)}")
            print(f"      ✘ {name} 含注入痕迹 {hits}")
    if not problems:
        print(f"      ✔ {MODULE_COUNT} 个文件均无模拟器注入痕迹")

    # require 前缀
    bad_req: list[tuple[str, str]] = []
    for name, src in sources.items():
        for m in REQUIRE_RE.finditer(src):
            target = m.group(1)
            if not target.startswith(REQUIRE_PREFIX):
                bad_req.append((name, target))
    if bad_req:
        for n, t in bad_req:
            problems.append(f'{n} 的 require 缺少导入根前缀：require("{t}")')
            print(f'      ✘ {n}: require("{t}") 应写成 require("{REQUIRE_PREFIX}{t}")')
    else:
        print(f'      ✔ 所有 require 均带 "{REQUIRE_PREFIX}" 前缀')

    # 入口参数占位
    entry = sources.get("game.lua", "")
    for param in ("rectPrefabId", "textPrefabId", "cursorPrefabId"):
        if param not in entry:
            problems.append(f"game.lua 里找不到脚本参数 {param}")
    print("      ✔ 入口脚本参数：rectPrefabId(必填) / textPrefabId(可选) / "
          "cursorPrefabId(必填·否则鼠标点不动) 已就位")

    if problems:
        print("\n自检未通过，已中止（不写任何文件）：")
        for p in problems:
            print("  ·", p)
        return 1

    if args.check:
        print("\n--check：自检全部通过。")
        return 0

    # ---- 3) 写出 ----
    print("\n[3/4] 写出导入包")
    if DST_DIR.exists():
        shutil.rmtree(DST_DIR)
    DST_DIR.mkdir(parents=True)
    for name in sources:
        (DST_DIR / name).write_text(sources[name], encoding="utf-8", newline="\n")
    print(f"      ✔ {DST_DIR}")

    # ---- 4) 导入清单 ----
    print("\n[4/4] 写出导入清单")
    lines = [
        "# 《点灯迷题》千星沙箱导入清单",
        "",
        "> 由 `_export_sandbox.py` 自动生成，请勿手改；改工程源文件后重跑本脚本。",
        "",
        "## 一、把以下 " + str(MODULE_COUNT) + " 个文件导入沙箱的 `default_import_file/`",
        "",
        "| 顺序 | 文件 | 作用 |",
        "|---|---|---|",
    ]
    for i, (name, desc) in enumerate(MODULES, 1):
        lines.append(f"| {i} | `{name}` | {desc} |")
    lines += [
        "",
        "导入后到沙箱里请核对：脚本注册路径是 `default_import_file/<文件名>`。",
        "工程里 require 写的正是这个前缀，路径不一致会报 `failed to load script`。",
        "",
        "## 二、把入口脚本挂到「控件容器节点」上",
        "",
        "- 挂载对象：**控件容器节点**（`script.object` 不能为 nil，否则报错）。",
        "- 入口脚本：`game.lua`。其余 " + str(MODULE_COUNT - 1) + " 个由它 require，**不要**重复挂载。",
        "",
        "## 三、入口脚本参数",
        "",
        "| 参数名 | 必填 | 说明 |",
        "|---|---|---|",
        "| `rectPrefabId` | **是** | 纯白底图元件。面板/卡片/按钮/灯格/难度条/粒子全部由它染色 |",
        "| `cursorPrefabId` | **是** | **光标检测区域**元件。所有卡片/按钮的点击都靠它 —— 见下方说明 |",
        "| `textPrefabId` | 否 | 文本框元件。不填则无文字 |",
        "| `clickAudioId` | 否 | 点击音效 |",
        "| `openAudioId` | 否 | 打开面板音效 |",
        "| `winAudioId` | 否 | 通关音效 |",
        "",
        "> 参数名后缀 `prefabId` / `AudioId` **不能改名**，改名后读不到。",
        "",
        "### 为什么必须单独配一个「光标检测区域」",
        "",
        "千星里只有 **预设按钮（PresetButton）** 和 **光标检测区域（CursorEventArea）**",
        "这两类控件带 `AddCursorEventListener`；图片控件（`rectPrefabId` 那一类）**没有**",
        "这个方法。把点击监听绑在图片上会被 `pcall` 静默吞掉，真机表现就是",
        "「按钮看得见、鼠标点不动」。",
        "",
        "做法（一次性，约 1 分钟）：",
        "",
        "1. 界面控件组管理 → 新建一个客户端控件，类型选 **光标检测区域**；",
        "2. 尺寸随便（脚本会按每个按钮的实际大小 `SetSizeDelta`），位置随便（脚本会重设）；",
        "3. 记下它的 **控件模板索引 ID**（点击该控件即可看到）；",
        "4. 把这个 ID 填进 `game.lua` 的脚本参数 `cursorPrefabId`。",
        "",
        "没配也能跑：脚本会打印一条警告并退化成「键盘可操作、鼠标不可点」。",
        "",
        "## 四、信号（4 条，详见 README.md 与 signal.lua）",
        "",
        "| 方向 | 信号名 | 参数 |",
        "|---|---|---|",
        "| 出站 | `进入关卡` | `AddInt` 关卡号(1 基) + `AddIntList` 点位序列(0 基) |",
        "| 出站 | `重玩本关` | 同上 |",
        "| 入站 | `让客户端进入关卡` | `AddInt` 关卡号（可选） |",
        "| 入站 | `关卡胜利` | `AddInt` 关卡号（可选） |",
        "",
        "## 五、不要做的事",
        "",
        "- ✘ **不要**用「模拟器试玩存档」里导出的脚本挂沙箱。",
        "  那份入口脚本被 `_tools/qxqy_websave.mjs` 追加过模拟器专属补丁：",
        "  真机上 `isMine[c.Id] = true` 会抛 `table index is nil`（每帧一次）。",
        "  判据：本清单第一节的 `game.lua` 只有 "
        + str(len(sources.get("game.lua", "").splitlines())) + " 行，",
        "  被污染的那份会多出约 100+ 行（补丁段落）。",
        "- ✘ 不要把 `_shared/` 或 `_tools/` 下的文件导入游戏工程。",
        "",
    ]
    (OUT_DIR / "导入清单.md").write_text("\n".join(lines), encoding="utf-8", newline="\n")
    print(f"      ✔ {OUT_DIR / '导入清单.md'}")

    print("\n完成。整目录 `点灯迷题/_sandbox/` 即沙箱导入包。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
