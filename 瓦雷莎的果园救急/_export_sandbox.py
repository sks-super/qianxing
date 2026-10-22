# -*- coding: utf-8 -*-
"""导出《瓦雷莎的果园救急》的「千星沙箱导入包」。

为什么需要这个脚本
------------------
千星沙箱的「导入文件」把每个脚本注册在虚拟根 `default_import_file/` 下，
工程里写的 `require("default_import_file/config")` 才能解析。

★ 千万不要拿「模拟器试玩存档」里导出的脚本去挂沙箱：
  试玩链路会给入口脚本追加一段模拟器专属补丁（参数兜底 + 层级修正），
  那段补丁在真机上会抛 `table index is nil`，且会把 rectPrefabId 回退成模拟器模板。
  本脚本只从**工程源文件**复制，并逐项自检。

用法
----
    python 瓦雷莎的果园救急/_export_sandbox.py          # 导出 + 自检
    python 瓦雷莎的果园救急/_export_sandbox.py --check  # 只自检，不写文件

产出
----
    瓦雷莎的果园救急/_sandbox/default_import_file/*.lua
    瓦雷莎的果园救急/_sandbox/导入清单.md

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

# 交付脚本（顺序即建议的导入顺序）
MODULES: list[tuple[str, str]] = [
    ("game.lua",       "主入口：7 层容器、屏幕状态机、信号收发、按键"),
    ("config.lua",     "参数唯一真源：DEFAULT_* + 果园配色 + 50 关 + 5 张教学卡 + 3 页手册"),
    ("state.lua",      "全部运行期状态字段"),
    ("utils.lua",      "控件 / 容器 / 文本 / 命中区 / 拖拽绑定 + 自动提层"),
    ("anim.lua",       "逐帧补间引擎（缓动 / tag / isBusy）"),
    ("fx.lua",         "果汁粒子池 + 补间 + 缓动"),
    ("scene.lua",      "果园背景：天空 / 远山 / 草坡 / 太阳 / 飘叶"),
    ("map.lua",        "★ 果园地图选关：横向长图、拖拽、箭头、金圈、吉祥物"),
    ("mascot.lua",     "★ 吉祥物「小果龙」：96×96 纯矩形拼图（_gen_mascot.py 生成）"),
    ("guide.lua",      "★ 教学卡与玩法手册（一图两句话）"),
    ("hud.lua",        "游玩期极简 HUD"),
    ("winUI.lua",      "胜利结算演出：暗星 → 魔环点亮 → 闪光 + 彩带 / 星尘"),
    ("signal.lua",     "★ 与节点图对接的唯一接口（服客 4 条 + 客服 1 条）"),
    ("puzzle.lua",     "5×6 棋盘纯计算（校验 / 调试对账用）"),
    ("fadeScreen.lua", "黑幕过渡（淡入淡出）"),
    ("transition.lua", "★ 全屏转场：天地撕开（天空向上 / 地面向下）"),
    ("audio.lua",      "音效封装"),
]

MODULE_COUNT = len(MODULES)

FORBIDDEN = [
    "[SIM_ONLY]",
    "[SIM_ZFIX]",
    "qxqy_websave",
    "qxqy_mount",
    "__simFallback",
    "buildParamShim",
    "buildZOrderFix",
    "containerPlayer",
    "containerPlatform",
]

REQUIRE_RE = re.compile(r'require\s*\(\s*"([^"]+)"\s*\)')
REQUIRE_PREFIX = "default_import_file/"


def read(p: Path) -> str:
    return p.read_text(encoding="utf-8")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true", help="只自检，不写文件")
    args = ap.parse_args()

    problems: list[str] = []
    files: list[str] = []

    for name, _desc in MODULES:
        p = HERE / name
        if not p.exists():
            problems.append(f"缺文件：{name}")
            continue
        src = read(p)
        files.append(name)
        for bad in FORBIDDEN:
            if bad in src:
                problems.append(f"{name} 含有模拟器注入痕迹：{bad}")
        for m in REQUIRE_RE.finditer(src):
            mod = m.group(1)
            if not mod.startswith(REQUIRE_PREFIX):
                problems.append(f'{name} 的 require("{mod}") 缺导入根前缀 {REQUIRE_PREFIX}')
            elif not (HERE / (mod.split("/")[-1] + ".lua")).exists():
                problems.append(f'{name} require("{mod}") 指向的文件不存在')

    # 额外的 Lua 文件（工程里没登记的）也算问题，避免漏交
    extra = sorted(p.name for p in HERE.glob("*.lua") if p.name not in dict(MODULES))
    if extra:
        problems.append("工程里有未登记进导入清单的脚本：" + ", ".join(extra))

    print(f"=== 导入包自检（{len(files)}/{MODULE_COUNT} 个脚本）===")
    if problems:
        for p in problems:
            print("  [失败] " + p)
        print(f"\n合计 {len(problems)} 处，未写出任何文件。")
        return 1
    print("  全部通过：无注入残留 / require 前缀齐全 / 文件齐全")

    if args.check:
        return 0

    if DST_DIR.exists():
        shutil.rmtree(DST_DIR)
    DST_DIR.mkdir(parents=True, exist_ok=True)
    for name in files:
        shutil.copy2(HERE / name, DST_DIR / name)

    lines = ["# 导入清单 · 瓦雷莎的果园救急", "",
             "把 `_sandbox/default_import_file/` 整个目录导入沙箱（保持目录名）。", "",
             "| # | 脚本 | 作用 |", "|---|---|---|"]
    for i, (name, desc) in enumerate(MODULES, start=1):
        lines.append(f"| {i} | `{name}` | {desc} |")
    lines += [
        "",
        "## 挂载与参数",
        "",
        "1. `game.lua` 挂在**客户端控件容器**的容器节点上；",
        "2. 脚本参数：`rectPrefabId`（必填）、`cursorPrefabId`（必填）、"
        "`textPrefabId`（可选）、`containerPrefabId`（建议填）、"
        "`circlePrefabId`（强烈建议：云朵 / 果实 / 太阳 / 圆角四角，不配全变方块）、"
        "`ringPrefabId` / `trianglePrefabId` / `star4PrefabId` / `star5PrefabId`（可选，"
        "金圈 / 风车叶片与小草 / 装饰星）、三个音效 ID（可选）；",
        "3. 节点图侧实现 `信号协议.md` 里的 6 条信号。",
    ]
    (OUT_DIR / "导入清单.md").write_text("\n".join(lines), encoding="utf-8")
    print(f"  已写出：{DST_DIR}（{len(files)} 个 .lua）")
    print(f"  已写出：{OUT_DIR / '导入清单.md'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
