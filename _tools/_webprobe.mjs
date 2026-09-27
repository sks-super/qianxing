// _webprobe.mjs — Web 试玩端到端探针
//
// 用命令行驱动 beyond-simulator-web，验证两件事：
//   1) 平台秒数标签在「亮起 / 熄灭」两态下是否反色
//   2) 键盘动作（key）能否被服务端接受并真正驱动游戏里的玩家
//
// 用法: node _tools/_webprobe.mjs
import { loadWebSession } from './_webclient.mjs';

const { api } = loadWebSession('cli'); // 统一复用会话槽，避免耗尽（上限 8）
const call = (action, args = {}) => api('play', { action, args });
const step = async (n) => { for (let i = 0; i < n; i++) await call('step', { dt: 1 / 30 }); };

const hex = (v) => '#' + ((v ?? 0) >>> 0).toString(16).padStart(8, '0');
const argb = (v) => {
  const h = ((v ?? 0) >>> 0).toString(16).padStart(8, '0');
  return `a=${parseInt(h.slice(0, 2), 16)} rgb=#${h.slice(2)}`;
};

await api('load-archive', { path: '_simulator/TickHop.web.save.json' });
await call('start', { canvasId: 'mobile-16-9' });

const snap = () => call('get', { view: true, sceneRev: 0, compact: true });
const nodes = (g) => g?.scene?.nodes || [];

// 字段样例（确认坐标字段名）
{
  const g = await snap();
  const n = nodes(g).find((x) => x.kind === 'image' && x.imageColor === 0xfff2f2f2);
  console.log('节点字段样例:', n ? Object.keys(n).join(',') : '(未找到)');
  if (n) console.log('  样例:', JSON.stringify(n));
}

// ---------- 1) 标签反色 ----------
console.log('\n=== 1) 平台秒数标签反色 ===');
const labelOf = (g) => nodes(g).find((x) => x.kind === 'textbox' && String(x.text || '') === '4');
const target = parseInt(process.env.QXQY_LIT_FRAME || '250', 10);

let g = await snap();
while (g.frame < 200) { await step(1); g = await snap(); }
const off = labelOf(g);
console.log(`熄灭态 f=${g.frame}  标签色 ${hex(off?.fontColor)}  ${argb(off?.fontColor)}  text=${JSON.stringify(off?.text)}`);

while (g.frame < target) { await step(1); g = await snap(); }
const on = labelOf(g);
console.log(`亮起态 f=${g.frame}  标签色 ${hex(on?.fontColor)}  ${argb(on?.fontColor)}  text=${JSON.stringify(on?.text)}`);
console.log(off && on && off.fontColor !== on.fontColor
  ? '✅ 两态颜色不同（已反色）'
  : '❌ 两态颜色相同（未反色）');

// ---------- 2) 键盘驱动玩家 ----------
console.log('\n=== 2) 键盘 → 玩家位移 ===');
const posMap = (g) => {
  const m = new Map();
  for (const n of nodes(g)) {
    const x = n.x ?? n.matrix?.tx, y = n.y ?? n.matrix?.ty;
    if (Number.isFinite(x) && Number.isFinite(y)) m.set(n.id, [x, y, n.imageColor]);
  }
  return m;
};

const before = posMap(await snap());
const KEY = process.env.QXQY_KEY || 'KeyboardMoveRightKeyDown';
console.log(`注入 ${KEY} …`);
// 注意：Web 端 play 动作读的是 args.key（worker 里 `Y.playKey(t.key)`），
// 不是 typeName —— 名字写错会被 String(undefined) 吞掉，静默不生效。
await call('key', { key: KEY });
await step(20);
const after = posMap(await snap());

let best = null;
for (const [id, [x0, y0]] of before) {
  const a = after.get(id);
  if (!a) continue;
  const d = Math.hypot(a[0] - x0, a[1] - y0);
  if (!best || d > best.d) best = { id, d, from: [x0, y0], to: [a[0], a[1]], color: a[2] };
}
if (best) {
  console.log(`位移最大图元 id=${best.id} color=${hex(best.color)}  (${best.from[0]},${best.from[1]}) → (${best.to[0]},${best.to[1]})  Δ=${best.d.toFixed(1)}px`);
  console.log(best.d > 2 ? '✅ 按键已驱动画面' : '⚠ 未见明显位移');
} else {
  console.log('⚠ 场景里没有可追踪坐标的图元');
}

await call('stop', {});
