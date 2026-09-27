// qxqy_webkeys.mjs — 给模拟器 Web 试玩页补上完整键盘输入（桥接到千星按键 API）
//
// 背景（为什么需要补丁）：
//   模拟器 Web 试玩页的键盘映射函数 keyEventName()（压缩后叫 Yu）只认数字键 1–9：
//
//     function Yu(i,t){let e=i.code&&String(i.code).startsWith("Digit")?String(i.code).slice(5):"";
//                     return e&&Number(e)>=1&&Number(e)<=9?`KeyboardCraftspersonKey${e}${t}`:""}
//
//   其它物理键一律返回空串，于是在 keydown/keyup 里被直接丢弃 —— 这就是
//   「试玩检测不到 WASD」的原因（与游戏工程本身无关）。
//   上游源码 studio/play/browser-session.js 的 keyEventName 也是同样的实现，
//   属于模拟器的功能缺口，不是本工程的配置问题。
//
// 本脚本做的事：
//   把 keyEventName 换成一张完整的「物理键 code → 千星 Enum.KeyEventType 名」映射表，
//   映射依据是 _shared/Lua 客户端 UI 脚本 API.md 里 Enum.KeyEventType 的「默认物理键」列。
//   生成的事件名随后由页面既有的 act('key', ...) 发到 /editor/api/play，
//   服务端 worker 的 playKey() → runtime.injectKey(typeName) 按名字精确派发给
//   Lua 侧 AddKeyEventListener 注册的回调，链路完全走官方接口。
//
// 用法：
//   node _tools/qxqy_webkeys.mjs --check       # 查看当前是否已打补丁
//   node _tools/qxqy_webkeys.mjs --apply       # 打补丁（自动备份 .qxbak）
//   node _tools/qxqy_webkeys.mjs --restore     # 还原成原始文件
//   node _tools/qxqy_webkeys.mjs --selftest    # 校验映射表覆盖了 WASD/方向/空格等
//   node _tools/qxqy_webkeys.mjs --probe       # 对运行中的 Web 服务做端到端验证（需先 --apply）
//
//   node_modules 重装后补丁会丢失，重跑一次 --apply 即可。

import { existsSync, readFileSync, writeFileSync, copyFileSync, unlinkSync } from 'node:fs';
import path from 'node:path';

// ---------- 目标文件 ----------
const CANDIDATES = [
  process.env.QXQY_WEB_RENDERER,
  'C:/Users/JingSu/.workbuddy/binaries/node/workspace/node_modules/beyond-simulator-web/dist/public/play-renderer.js',
].filter(Boolean);

const MARKER = '__QXQY_WEBKEYMAP__';
const FN_START = 'function Yu(i,t){';
const FN_END = '}function lv(';

// ================================================================
// ★ 物理键 → 千星 KeyEventType 基名
//   取值依据：_shared/Lua 客户端 UI 脚本 API.md 的 Enum.KeyEventType 表
//   「默认物理键」一列，逐项对应，不臆造。
// ================================================================
const KEYMAP = {};
const put = (names, base) => names.forEach((n, i) => { KEYMAP[n] = base(i); });

// 奇匠按键 1–43（默认物理键：1-9 / 0 / U Z Y G H I O P J K L V / F5–F10 / ` - = [ , . / / ↑↓←→ / 右Ctrl / 右Shift / Backspace / CapsLock）
put(['Digit1', 'Digit2', 'Digit3', 'Digit4', 'Digit5', 'Digit6', 'Digit7', 'Digit8', 'Digit9'], (i) => `KeyboardCraftspersonKey${i + 1}`);
KEYMAP.Digit0 = 'KeyboardCraftspersonKey10';
put(['KeyU', 'KeyZ', 'KeyY', 'KeyG', 'KeyH', 'KeyI', 'KeyO', 'KeyP',
     'KeyJ', 'KeyK', 'KeyL', 'KeyV'], (i) => `KeyboardCraftspersonKey${11 + i}`);
put(['F5', 'F6', 'F7', 'F8', 'F9', 'F10'], (i) => `KeyboardCraftspersonKey${23 + i}`);
put(['Backquote', 'Minus', 'Equal', 'BracketLeft', 'Comma', 'Period', 'Slash'], (i) => `KeyboardCraftspersonKey${29 + i}`);
put(['ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight'], (i) => `KeyboardCraftspersonKey${36 + i}`);
KEYMAP.ControlRight = 'KeyboardCraftspersonKey40';
KEYMAP.ShiftRight = 'KeyboardCraftspersonKey41';
KEYMAP.Backspace = 'KeyboardCraftspersonKey42';
KEYMAP.CapsLock = 'KeyboardCraftspersonKey43';

// 具名动作键（默认物理键：W A S D / 左Ctrl / Space / X / Tab / F / E Q R T）
KEYMAP.KeyW = 'KeyboardMoveForwardKey';
KEYMAP.KeyA = 'KeyboardMoveLeftKey';
KEYMAP.KeyS = 'KeyboardMoveBackwardKey';
KEYMAP.KeyD = 'KeyboardMoveRightKey';
KEYMAP.ControlLeft = 'KeyboardSwitchToWalkOrRunKey';
KEYMAP.Space = 'KeyboardJumpKey';
KEYMAP.KeyX = 'KeyboardDropKey';
KEYMAP.Tab = 'KeyboardOpenShortcutWheelKey';
KEYMAP.KeyF = 'KeyboardInteractKey';
KEYMAP.KeyE = 'KeyboardCharacterSkill1Key';
KEYMAP.KeyQ = 'KeyboardCharacterSkill2Key';
KEYMAP.KeyR = 'KeyboardCharacterSkill3Key';
KEYMAP.KeyT = 'KeyboardCharacterSkill4Key';

function buildPatched() {
  const map = JSON.stringify(KEYMAP);
  const fn = `function Yu(i,t){var m=${MARKER},c=i&&i.code?String(i.code):"",b=m[c];return b?b+t:""}`;
  return `var ${MARKER}=${map};${fn}`;
}

// ---------- 命令行 ----------
const argv = process.argv.slice(2);
const want = (f) => argv.includes('--' + f);
const opt = (n, d = '') => { const i = argv.indexOf('--' + n); return i >= 0 && argv[i + 1] ? argv[i + 1] : d; };

const FILE = opt('file', '') || CANDIDATES.find((p) => existsSync(p));
if (!FILE || !existsSync(FILE)) {
  console.error('✗ 找不到 play-renderer.js。请用 --file <路径> 指定，或设置 QXQY_WEB_RENDERER。');
  console.error('  候选: ' + CANDIDATES.join(' , '));
  process.exit(2);
}
const BAK = FILE + '.qxbak';

const isPatched = (src) => src.includes(MARKER);

// ---------- check ----------
if (want('check') || argv.length === 0) {
  const src = readFileSync(FILE, 'utf8');
  console.log(`文件: ${FILE}`);
  console.log(`备份: ${existsSync(BAK) ? BAK : '(无)'}`);
  console.log(`状态: ${isPatched(src) ? '✅ 已打补丁（完整键盘映射）' : '❌ 未打补丁（只有数字键 1-9）'}`);
  process.exit(0);
}

// ---------- apply ----------
if (want('apply')) {
  let src = readFileSync(FILE, 'utf8');
  if (isPatched(src)) {
    console.log('✅ 已是打过补丁的状态，无需重复操作。');
    process.exit(0);
  }
  const a = src.indexOf(FN_START);
  const b = a < 0 ? -1 : src.indexOf(FN_END, a);
  if (a < 0 || b < 0) {
    console.error('✗ 定位 keyEventName 失败（上游 bundle 结构可能已变）。');
    console.error(`  期望片段: ${FN_START} ... ${FN_END}`);
    process.exit(3);
  }
  if (!existsSync(BAK)) copyFileSync(FILE, BAK);

  const replaced = src.slice(a, b + 1);
  src = src.slice(0, a) + buildPatched() + src.slice(b + 1);
  writeFileSync(FILE, src);
  console.log('✅ 补丁已应用');
  console.log('   替换前: ' + replaced.slice(0, 120).replace(/\n/g, ' ') + '…');
  console.log(`   映射键数: ${Object.keys(KEYMAP).length}`);
  console.log(`   备份文件: ${BAK}`);
  console.log('   浏览器请强制刷新（Ctrl+F5）后再试玩。');
  process.exit(0);
}

// ---------- restore ----------
if (want('restore')) {
  if (!existsSync(BAK)) {
    console.error('✗ 没有备份文件，无法还原: ' + BAK);
    process.exit(3);
  }
  copyFileSync(BAK, FILE);
  unlinkSync(BAK);
  console.log('✅ 已还原为原始文件，并删除备份。');
  process.exit(0);
}

// ---------- selftest ----------
if (want('selftest')) {
  const src = readFileSync(FILE, 'utf8');
  if (!isPatched(src)) {
    console.error('✗ 尚未打补丁，先跑 --apply。');
    process.exit(1);
  }
  // 取出打过补丁的 keyEventName 实现并在当前进程里执行，验证真实产物（而不是本文件的副本）
  const a = src.indexOf(`var ${MARKER}=`);
  const b = src.indexOf('function lv(', a);
  const impl = src.slice(a, b);
  // eslint-disable-next-line no-new-func
  const fn = new Function(impl + '\nreturn Yu;')();

  const cases = [
    ['KeyW', 'Down', 'KeyboardMoveForwardKeyDown'],
    ['KeyA', 'Down', 'KeyboardMoveLeftKeyDown'],
    ['KeyS', 'Up', 'KeyboardMoveBackwardKeyUp'],
    ['KeyD', 'Down', 'KeyboardMoveRightKeyDown'],
    ['Space', 'Down', 'KeyboardJumpKeyDown'],
    ['ArrowLeft', 'Down', 'KeyboardCraftspersonKey38Down'],
    ['ArrowRight', 'Up', 'KeyboardCraftspersonKey39Up'],
    ['ArrowUp', 'Down', 'KeyboardCraftspersonKey36Down'],
    ['Digit1', 'Down', 'KeyboardCraftspersonKey1Down'],
    ['Digit0', 'Down', 'KeyboardCraftspersonKey10Down'],
    ['KeyR', 'Down', 'KeyboardCharacterSkill3KeyDown'],
    ['KeyT', 'Down', 'KeyboardCharacterSkill4KeyDown'],
    ['KeyP', 'Down', 'KeyboardCraftspersonKey18Down'],
    ['KeyL', 'Down', 'KeyboardCraftspersonKey21Down'],
    ['KeyZ', 'Down', 'KeyboardCraftspersonKey12Down'],
    ['F5', 'Down', 'KeyboardCraftspersonKey23Down'],
    ['KeyM', 'Down', ''],   // 千星没有对应枚举 → 应当不映射（避免误吞按键）
  ];
  let bad = 0;
  for (const [code, phase, expect] of cases) {
    const got = fn({ code }, phase);
    const ok = got === expect;
    if (!ok) bad++;
    console.log(`  ${ok ? '✅' : '❌'} ${code.padEnd(11)} ${phase.padEnd(5)} → ${JSON.stringify(got)}${ok ? '' : `  (期望 ${JSON.stringify(expect)})`}`);
  }
  console.log(`\n${bad === 0 ? '✅ 全部通过' : `❌ ${bad} 项不符`}（共 ${cases.length} 项，映射表 ${Object.keys(KEYMAP).length} 键）`);
  process.exit(bad === 0 ? 0 : 1);
}

// ---------- probe：对运行中的 Web 服务做端到端验证 ----------
if (want('probe')) {
  const ARCHIVE = opt('archive', '_simulator/TickHop.web.save.json');
  const CANVAS = opt('canvas', 'mobile-16-9');
  const STEP = parseInt(opt('step', '25'), 10);

  // 会话 id 统一用 cli：服务端每个不同 id 占一个槽（上限 8，无 CLI 开关），
  // 用新 id 反复跑会把槽位耗尽，之后所有请求都会报 "Editor session limit reached"。
  const { BASE, api } = await import('./_webclient.mjs').then((m) => m.loadWebSession(opt('session', 'cli')));
  const call = (action, args = {}) => api('play', { action, args });
  const positions = (snap) => {
    const out = new Map();
    for (const n of (snap && snap.scene && snap.scene.nodes) || []) {
      const m = n.matrix || {};
      if (Number.isFinite(m.tx)) out.set(n.id, [m.tx, m.ty]);
    }
    return out;
  };

  try {
    console.log(`服务: ${BASE}    存档: ${ARCHIVE}    会话: ${opt('session', 'cli')}`);
    await api('load-archive', { path: ARCHIVE });
    await call('start', { canvasId: CANVAS });
    // 黑幕 + 关卡构建需要一点时间，先推进到关卡稳定
    for (let i = 0; i < STEP; i++) await call('step', { dt: 1 / 30 });
    const before = positions(await call('get', { view: true, sceneRev: 0, compact: true }));

    await call('key', { key: 'KeyboardMoveRightKeyDown' });
    for (let i = 0; i < STEP; i++) await call('step', { dt: 1 / 30 });
    const after = positions(await call('get', { view: true, sceneRev: 0, compact: true }));

    let maxDx = 0, moved = 0, best = null;
    for (const [id, [x0]] of before) {
      if (!after.has(id)) continue;
      const dx = after.get(id)[0] - x0;
      if (Math.abs(dx) > 0.5) moved++;
      if (Math.abs(dx) > Math.abs(maxDx)) { maxDx = dx; best = id; }
    }
    console.log(`场景图元 ${before.size} → ${after.size}，检测到位移的图元 ${moved} 个，最大水平位移 ${maxDx.toFixed(1)}px（id=${best}）`);
    console.log(moved > 0
      ? '✅ 网页端按键动作已被服务端接受并驱动了画面（键盘桥链路通）'
      : '⚠ 未观察到位移：确认已 --apply、浏览器强制刷新，且画面里确实是本工程（先跑 qxqy_webcheck.mjs）');
    await call('stop', {});
    process.exit(moved > 0 ? 0 : 1);
  } catch (e) {
    console.error('✗ ' + e.message);
    process.exit(1);
  }
}
