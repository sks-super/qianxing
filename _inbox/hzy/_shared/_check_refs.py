# -*- coding: utf-8 -*-
"""
跨文件引用一致性检查（通用版，支持多游戏目录）

用法: python _check_refs.py <游戏目录>
      例如  python _check_refs.py ../割绳子
            python _check_refs.py ../TickHop

检查项:
1. require("X") -> X.lua 是否存在
2. 模块调用 `mod.fn(` -> 该模块的 `M.fn` 是否已定义
   ★ 只检查本文件真正 require 过的模块，且先剥离注释与字符串，
     因此引擎全局 game.XXX() / script.XXX() 不会再被误报。
3. state.xxx 字段 -> 是否在 state.lua 中定义
4. config.<全大写常量> -> 是否在 config.lua 中定义
5. 编辑器.html 的 DEFAULTS <-> config.lua 的 DEFAULT_* 数值同步
   （key 与 DEFAULT_<KEY 大写> 机械对应；少数历史特例由 SPECIAL 表兜底）
6. config.DEFAULT_PREFAB_* <-> _tools/_sim_common.mjs 的 SIM_TEMPLATE_GUIDS
   <-> _tools/qxqy_simsave.mjs 的 GUID_*：真机元件索引与模拟器模板 guid 不许漂移
   （含 纯色底图两级：矩形 / 图片；以及 海水/草地/树木/人物 四个美术素材元件）
   ★ 某工程 config 里没有该常量时自动跳过，所以只有用到它的工程才需要补。
"""
import re
import os
import sys

D = sys.argv[1] if len(sys.argv) > 1 else "."

EXCLUDE_MODULES = {"miliastra_lib"}

SPECIAL = {
    "bubble_upward_gravity": "DEFAULT_UPWARD_GRAVITY",
}


def read(p):
    with open(os.path.join(D, p), "r", encoding="utf-8", errors="replace") as f:
        return f.read()


def strip_lua(src: str) -> str:
    """把注释与字符串内容替换为等长空白，保留行列结构。"""
    out = list(src)
    i, n = 0, len(src)

    def blank(a, b):
        for k in range(a, min(b, n)):
            if out[k] != "\n":
                out[k] = " "

    while i < n:
        c = src[i]
        if src.startswith("--", i):
            m = re.match(r"--\[(=*)\[", src[i:])
            if m:
                close = "]" + m.group(1) + "]"
                j = src.find(close, i + m.end())
                j = n if j < 0 else j + len(close)
            else:
                j = src.find("\n", i)
                j = n if j < 0 else j
            blank(i, j)
            i = j
            continue
        if c == "[" and re.match(r"\[(=*)\[", src[i:]):
            m = re.match(r"\[(=*)\[", src[i:])
            close = "]" + m.group(1) + "]"
            j = src.find(close, i + m.end())
            j = n if j < 0 else j + len(close)
            blank(i, j)
            i = j
            continue
        if c in "\"'":
            q = c
            j = i + 1
            while j < n:
                if src[j] == "\\":
                    j += 2
                    continue
                if src[j] == q:
                    j += 1
                    break
                if src[j] == "\n":
                    break
                j += 1
            blank(i, j)
            i = j
            continue
        i += 1
    return "".join(out)


def list_lua():
    if not os.path.isdir(D):
        print(f"[错误] 目录不存在: {D}")
        sys.exit(2)
    return sorted(f for f in os.listdir(D) if f.endswith(".lua"))


raw = {f: read(f) for f in list_lua()}
files = {f: strip_lua(s) for f, s in raw.items()}

LUA_MODS = {f[:-4] for f in files if f[:-4] not in EXCLUDE_MODULES}

problems = []

# ---------- 1. require 存在性 + 各文件的依赖集合 ----------
required_of = {}
for name, src in raw.items():
    reqs = set()
    for m in re.finditer(r'require\(\s*["\']([^"\']+)["\']\s*\)', src):
        mod = m.group(1)
        reqs.add(mod)
        if not os.path.exists(os.path.join(D, mod + ".lua")):
            problems.append(f"[{name}] require(\"{mod}\") -> 文件 {mod}.lua 不存在")
    required_of[name] = reqs


# ---------- 2. 模块函数定义收集 ----------
def defined_funcs(src, tbl="M"):
    out = set()
    out |= set(re.findall(rf'function\s+{re.escape(tbl)}[\.:](\w+)\s*\(', src))
    out |= set(re.findall(rf'{re.escape(tbl)}\.(\w+)\s*=\s*function', src))
    out |= set(re.findall(r'local\s+function\s+(\w+)\s*\(', src))
    out |= set(re.findall(r'^\s*(\w+)\s*=\s*function', src, re.M))
    out |= set(re.findall(r'^\s*function\s+(\w+)\s*\(', src, re.M))
    return out


mod_funcs = {}
for mod in LUA_MODS:
    if mod + ".lua" in files:
        mod_funcs[mod] = defined_funcs(files[mod + ".lua"])

# ---------- 3. 模块调用检查（仅限本文件 require 过的模块） ----------
for name, src in files.items():
    for mod in required_of[name]:
        if mod not in mod_funcs or name == mod + ".lua":
            continue
        funcs = mod_funcs[mod]
        for m in re.finditer(rf'(?<![A-Za-z0-9_.:]){re.escape(mod)}\.(\w+)\s*\(', src):
            called = m.group(1)
            if called not in funcs:
                line = src.count("\n", 0, m.start()) + 1
                problems.append(f"[{name}:{line}] {mod}.{called}() 未在 {mod}.lua 中定义")

# ---------- 4. state 字段检查 ----------
state_src = files.get("state.lua", "")
state_fields = set(re.findall(r'M\.(\w+)\s*=', state_src))
state_fields |= set(re.findall(r'^\s*(\w+)\s*=', state_src, re.M))
for name, src in files.items():
    if name == "state.lua":
        continue
    for m in re.finditer(r'(?<![A-Za-z0-9_.])state\.(\w+)', src):
        f = m.group(1)
        if f not in state_fields:
            line = src.count("\n", 0, m.start()) + 1
            problems.append(f"[{name}:{line}] state.{f} 未在 state.lua 中定义")

# ---------- 5. config 常量检查（仅全大写常量名） ----------
cfg_src = files.get("config.lua", "")
cfg_fields = set(re.findall(r'M\.(\w+)\s*=', cfg_src))
for name, src in files.items():
    if name == "config.lua":
        continue
    for m in re.finditer(r'(?<![A-Za-z0-9_.])config\.([A-Z][A-Z0-9_]*)', src):
        f = m.group(1)
        if f not in cfg_fields:
            line = src.count("\n", 0, m.start()) + 1
            problems.append(f"[{name}:{line}] config.{f} 未在 config.lua 中定义")

# ---------- 6. 编辑器 DEFAULTS vs config DEFAULT_* ----------
html = os.path.join(D, "编辑器.html")
if os.path.exists(html):
    hsrc = read("编辑器.html")
    m = re.search(r'const\s+DEFAULTS\s*=\s*\{(.*?)\}\s*;', hsrc, re.S)
    if m:
        ed = dict(re.findall(r'(\w+)\s*:\s*([-\d.]+)', m.group(1)))
        cfg_full = raw.get("config.lua", "")
        print("=== 编辑器 DEFAULTS vs config DEFAULT_* ===")
        diff = 0
        for k, ev in ed.items():
            ck = SPECIAL.get(k) or ("DEFAULT_" + k.upper())
            cm = re.search(rf'M\.{re.escape(ck)}\s*=\s*([-\d.]+)', cfg_full)
            if not cm:
                problems.append(f"[编辑器] DEFAULTS 的 {k} 找不到对应 config.{ck}")
                print(f"  [缺配置] {k} -> config.{ck} 不存在")
                continue
            cv = cm.group(1).rstrip(".")
            if abs(float(cv) - float(ev)) > 1e-9:
                print(f"  [不一致] {k}: 编辑器={ev}  config.{ck}={cv}")
                diff += 1
            else:
                print(f"  [一致]   {k} = {cv}")
        print(f"  -> {diff} 处不一致\n")


# ---------- 7. 真机元件索引 ↔ 模拟器模板 guid（不许漂移） ----------
#   见 _shared/编辑器元件索引.md 约定 2：
#     同一个索引要在三处同时出现 —— config.DEFAULT_PREFAB_*、_sim_common.SIM_TEMPLATE_GUIDS、
#     qxqy_simsave.GUID_*。任一处改了、别处没跟，就会出现
#     「模拟器里跑通、搬进真机要另填参数」的错位。
PREFAB_MAP = [
    # config 常量名                    模拟器参数名             simsave 常量名
    # 纯色底图有两级：首选「矩形」，拿不到控件就回退「图片」（见 utils.instantiateRect）
    ("DEFAULT_PREFAB_RECT", "rectPrefabId", "GUID_RECT"),
    ("DEFAULT_PREFAB_IMAGE", "imagePrefabId", "GUID_IMAGE"),
    ("DEFAULT_PREFAB_TEXT", "textPrefabId", "GUID_TEXT"),
    ("DEFAULT_PREFAB_CONTAINER", "containerPrefabId", "GUID_CONTAINER"),
    # 美术素材元件（海水 / 草地 / 树木 / 人物）—— 只有 浮岛借木 在用，
    # 其余工程 config 里没有这几个常量时会被下面的 `continue` 跳过。
    ("DEFAULT_PREFAB_WATER", "waterPrefabId", "GUID_WATER"),
    ("DEFAULT_PREFAB_LAND", "landPrefabId", "GUID_LAND"),
    ("DEFAULT_PREFAB_TREE", "treePrefabId", "GUID_TREE"),
    ("DEFAULT_PREFAB_PLAYER", "playerPrefabId", "GUID_PLAYER"),
]
WF = os.path.dirname(os.path.abspath(D))
sim_common_p = os.path.join(WF, "_tools", "_sim_common.mjs")
simsave_p = os.path.join(WF, "_tools", "qxqy_simsave.mjs")
cfg_full = raw.get("config.lua", "")

if not os.path.exists(sim_common_p) or not os.path.exists(simsave_p):
    print("=== 元件索引一致性（config ↔ 模拟器模板 guid） ===")
    print(f"  [跳过] 找不到 _tools/_sim_common.mjs 或 _tools/qxqy_simsave.mjs（工作区根={WF}）\n")
else:
    sim_src = open(sim_common_p, "r", encoding="utf-8", errors="replace").read()
    sv_src = open(simsave_p, "r", encoding="utf-8", errors="replace").read()
    print("=== 元件索引一致性（config ↔ 模拟器模板 guid） ===")
    checked = 0
    for cfg_name, sim_key, sv_name in PREFAB_MAP:
        cm = re.search(rf'M\.{cfg_name}\s*=\s*(\d+)', cfg_full)
        if not cm:
            continue          # 本工程没用这个元件，跳过（如 TickHop 未用容器节点）
        c_val = cm.group(1)
        sm = re.search(rf'\b{sim_key}\s*:\s*(\d+)', sim_src)
        vm = re.search(rf'\bconst\s+{sv_name}\s*=\s*(\d+)', sv_src)
        if not sm:
            problems.append(f"[索引漂移] {cfg_name}={c_val} 但 _sim_common.mjs 的 {sim_key} 未定义")
            print(f"  [缺] {cfg_name} -> _sim_common.{sim_key} 不存在")
            continue
        if not vm:
            problems.append(f"[索引漂移] {cfg_name}={c_val} 但 qxqy_simsave.mjs 的 {sv_name} 未定义")
            print(f"  [缺] {cfg_name} -> qxqy_simsave.{sv_name} 不存在")
            continue
        bad = False
        if sv_src and vm.group(1) != c_val:
            bad = True
            problems.append(
                f"[索引漂移] {cfg_name}={c_val}，但 qxqy_simsave.{sv_name}={vm.group(1)}")
        if sm.group(1) != c_val:
            bad = True
            problems.append(
                f"[索引漂移] {cfg_name}={c_val}，但 _sim_common.{sim_key}={sm.group(1)}")
        if bad:
            print(f"  [不一致] {cfg_name}={c_val} / _sim_common.{sim_key}={sm.group(1)}"
                  f" / qxqy_simsave.{sv_name}={vm.group(1)}")
        else:
            checked += 1
            print(f"  [一致]   {cfg_name} = _sim_common.{sim_key} = {sv_name} = {c_val}")

    # 同一个索引的两个名字（容器节点 / 脚本宿主）也要自洽
    host = re.search(r'M\.DEFAULT_HOST_CONTAINER\s*=\s*(\d+)', cfg_full)
    cont = re.search(r'M\.DEFAULT_PREFAB_CONTAINER\s*=\s*(\d+)', cfg_full)
    if host and cont:
        if host.group(1) != cont.group(1):
            problems.append(
                f"[索引漂移] DEFAULT_HOST_CONTAINER={host.group(1)} 与 "
                f"DEFAULT_PREFAB_CONTAINER={cont.group(1)} 不是同一个索引")
            print(f"  [不一致] DEFAULT_HOST_CONTAINER={host.group(1)} != "
                  f"DEFAULT_PREFAB_CONTAINER={cont.group(1)}")
        else:
            print(f"  [一致]   DEFAULT_HOST_CONTAINER = DEFAULT_PREFAB_CONTAINER = {cont.group(1)}")
    print(f"  -> 已核对 {checked} 个元件索引\n")

print("=== 引用一致性问题 ===")
if problems:
    for p in problems:
        print("  " + p)
    print(f"\n合计 {len(problems)} 处")
else:
    print("  无问题")
sys.exit(1 if problems else 0)
