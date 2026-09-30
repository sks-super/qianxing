#!/usr/bin/env bash
# 浮岛借木 · 端到端复验（模拟器）
#
#   覆盖：第01关（素材路径）→ 第01关（useArt=0 回退路径）→ 第02关 → 第03关（连跳两关）→ 提示显示
#
#   用法（在 千星割绳子游戏/ 下任意位置）：
#       bash _tools/e2e_浮岛借木.sh
#
#   ⚠️ 脚本只能报「有没有挂载错误」和截图路径。
#      步数 / (已通关) 只画在画布 HUD 上，挂载日志里没有，
#      必须人眼看截图核对（第01关应为 步数 14 已通关，第02关 17，第03关 15 + 「全部通关！」）。
#      ★ 口令与期望步数来自 _tools/solve_浮岛借木.py 的「最短解」（改关卡后必须同步）。
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

NODE="${NODE:-C:/Users/lenovo/.workbuddy/binaries/node/versions/22.22.2-3/node.exe}"
GAME=浮岛借木
SAVE="_simulator/$GAME.sim-ready.save.json"
OUT="_tmp/e2e"
mkdir -p "$OUT"

# 把口令转成 --key 参数；$1=口令  $2=起始帧  $3=每步间隔帧
# 口令字母：W 上 / S 下 / A 左 / D 右（对应引擎的 Forward/Backward/Left/Right）
mkseq() {
  local seq="$1" f="$2" gap="$3"
  local out="" i c DN UP
  for ((i=0; i<${#seq}; i++)); do
    c=${seq:$i:1}
    case $c in
      S) DN=KeyboardMoveBackwardKeyDown; UP=KeyboardMoveBackwardKeyUp ;;
      D) DN=KeyboardMoveRightKeyDown;    UP=KeyboardMoveRightKeyUp ;;
      A) DN=KeyboardMoveLeftKeyDown;     UP=KeyboardMoveLeftKeyUp ;;
      W) DN=KeyboardMoveForwardKeyDown;  UP=KeyboardMoveForwardKeyUp ;;
      *) continue ;;
    esac
    out="$out --key $DN@$f --key $UP@$((f+1))"
    f=$((f+gap))
  done
  echo "$out"
}

run_game() {
  local name="$1"; shift
  local log="$OUT/run_$name.txt"
  "$NODE" _tools/qxqy_mount.mjs --game "$GAME" --entry game.lua --open "$SAVE" \
    --preset sim --fix-zorder 3 "$@" > "$log" 2>&1
  local p err
  p=$(grep -o "[^ ]*shots.shot_[0-9TZ:-]*\.png" "$log" | tail -1)
  err=$(grep -c '"mountError": null' "$log")
  echo "[$name] 挂载无错快照: $err"
  echo "[$name] 截图: ${p:-<未产出，检查 $log>}"
}

echo "===== 浮岛借木 端到端复验 ====="
echo

# ---- 第01关（素材路径）· 最短解 14 步：撞倒树 → 树干落进水道 → 踩树干 → 到右岛 ----
run_game L1art --steps 115 $(mkseq "DDDDDDDSSSDDDD" 30 4)
# ---- 第01关（回退路径：四类全部退回纯色矩形）----
run_game L1rect --steps 115 --params '{"useArt":0}' $(mkseq "DDDDDDDSSSDDDD" 30 4)
# ---- 第02关（T 换关 + 17 步：侧面推 3 次把树干滑进水道）----
run_game L2 --steps 150 \
  --key KeyboardCharacterSkill4KeyDown@25 --key KeyboardCharacterSkill4KeyUp@26 \
  $(mkseq "SDDDDDDDDDDSSDDDD" 60 4)
# ---- 第03关（连跳两关 + 15 步：正面推让树干立起来，再撞倒它）----
run_game L3 --steps 190 \
  --key KeyboardCharacterSkill4KeyDown@25 --key KeyboardCharacterSkill4KeyUp@26 \
  --key KeyboardCharacterSkill4KeyDown@70 --key KeyboardCharacterSkill4KeyUp@71 \
  $(mkseq "SDDDDDDDDSSDDDD" 105 4)
# ---- 提示显示（F）----
run_game HINT --steps 75 --key KeyboardInteractKeyDown@40

# ---- 纯色底图：确认默认走「矩形」，并压测回退到「图片」 ----
#   纯色底图是两个模板交替的（GUID_RECT=矩形 / GUID_IMAGE=图片_回退），
#   两者的**渲染完全一样**，只有模板名不同 —— 所以只能靠 --probe-walk 的控件快照分辨。
#   期望：默认 N×SIM_矩形；把 rectPrefabId 填成一个不存在的索引后 N×SIM_图片_回退，
#   且**两边的控件总数完全相同**（回退是平替，不是少几个）。
#   ⚠️ N 随画面复杂度变化，别写死：2.5D 之后每个陆地格有 3 个装饰控件
#      （落水投影 / 厚度侧面 / 沙滩描边）+ 全屏水面网格线 → N 从 201 涨到 517；
#      关卡改版（物体数量变了）后这个数也会变，以两侧**总数相同**为准。
#   （这不是「回归判据」，是「回退链路确实通」的证据；画面本身应当两者一致。）
probe_templates() {
  local name="$1"; shift
  local log="$OUT/probe_$name.txt"
  "$NODE" _tools/qxqy_mount.mjs --game "$GAME" --entry game.lua --open "$SAVE" \
    --preset sim --fix-zorder 3 --steps 60 --probe-walk 45 "$@" > "$log" 2>&1
  echo "[$name] 控件模板计数:"
  grep -ao 'SIM_[^ ]*' "$log" | sort | uniq -c | sed 's/^/    /'
}
probe_templates 底图_默认
probe_templates 底图_回退 --params '{"rectPrefabId":999999}'

echo
echo "===== 请打开上面截图核对 HUD ====="
echo "  期望：第01关 步数 14 (已通关) / 第02关 步数 17 (已通关) / 第03关 步数 15 (已通关) + 「全部通关！按 R 重玩本关」"
echo "        HINT 应为 步数 0 且显示三行操作提示"
echo "  L1art 与 L1rect 的画面差异 = 美术素材 vs 纯色回退（草地：平铺色块 vs 绿棋盘格；"
echo "  树：1 块深绿 1×1 格 vs 树冠+树干 2 块；小人：1 块橙 1 格 vs 橙身+黑头 0.94 格）"
echo "  底图_默认 应为 N×SIM_矩形；底图_回退 应为 N×SIM_图片_回退，两边总数必须相同"
echo "            （本版实测：517 SIM_矩形 / 517 SIM_图片_回退 + 139 SIM_草地 + 1 SIM_海水"
echo "              + 1 SIM_树木 + 1 SIM_人物 + 8 SIM_文本 + 5 SIM_容器节点 = 672 两边一致）"
