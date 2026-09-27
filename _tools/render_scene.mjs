// render_scene.mjs — 把 Web 模拟器的 scene.nodes 渲染成 PNG，用于视觉核对 UI 布局
//
// 为什么不用截图：Web 通道没有截图接口，但它把每帧的控件树以矢量数据暴露出来
// （kind / matrix / sourceWidth / color / text / fontSize），足够离线复现画面。
//
// 用法：
//   node _tools/render_scene.mjs --scenario select --out _simulator/shots/menu_select.png
//   node _tools/render_scene.mjs --scenario win    --out _simulator/shots/menu_win.png
//   node _tools/render_scene.mjs --scenario fail   --out _simulator/shots/menu_fail.png
//
// scenario: none（纯关卡） / select（选关面板） / win（通关面板） / fail（失败面板）
//           cleared（通关第01关后再开选关，用于核对卡片上的通关标记）

import { pathToFileURL } from 'node:url';
import fs from 'node:fs';
import path from 'node:path';
import { loadWebSession } from './_webclient.mjs';

const MOD = 'C:/Users/JingSu/.workbuddy/binaries/node/workspace/node_modules/@napi-rs/canvas/index.js';
const { createCanvas } = await import(pathToFileURL(MOD).href);

const argv = process.argv.slice(2);
const opt = (n, d) => { const i = argv.indexOf('--' + n); return i >= 0 && argv[i + 1] ? argv[i + 1] : d; };

const OUT = opt('out', '_simulator/shots/scene.png');
const CANVAS_ID = opt('canvas', 'mobile-16-9');
const ARCHIVE = opt('archive', '_simulator/TickHop.web.save.json');
const SCENARIO = opt('scenario', 'select');
const FRAMES = parseInt(opt('frames', '80'), 10);

const { api } = loadWebSession('cli');
const call = (a, args = {}) => api('play', { action: a, args });
const stepN = async (n) => { for (let i = 0; i < n; i++) await call('step', { dt: 1 / 30 }); };

// 0xAARRGGBB → rgba()；alpha=0 视为透明
function css(v) {
  const n = (Number(v) || 0) >>> 0;
  const a = ((n >>> 24) & 255) / 255;
  const r = (n >>> 16) & 255, g = (n >>> 8) & 255, b = n & 255;
  return `rgba(${r},${g},${b},${a.toFixed(3)})`;
}

await api('load-archive', { path: ARCHIVE });
await call('start', { canvasId: CANVAS_ID });
await stepN(FRAMES);

if (SCENARIO === 'select') {
  await call('key', { key: 'KeyboardCraftspersonKey21Down' });
  await stepN(4);
} else if (SCENARIO === 'fail') {
  await stepN(340);
} else if (SCENARIO === 'win') {
  await call('key', { key: 'KeyboardMoveRightKeyDown' });
  await stepN(150);
} else if (SCENARIO === 'cleared') {
  // 走到终点通关 → T 进下一关 → L 开选关：此时第01关卡片应带通关标记
  await call('key', { key: 'KeyboardMoveRightKeyDown' });
  await stepN(150);
  await call('key', { key: 'KeyboardCharacterSkill4KeyDown' });   // T
  await stepN(90);
  await call('key', { key: 'KeyboardCraftspersonKey21Down' });    // L
  await stepN(4);
}

const st = await call('get', { view: true, sceneRev: 0, compact: true });
const nodes = (st && st.scene && st.scene.nodes) || [];
const root = nodes.find((n) => n.parent === null) || nodes[0];
const W = Math.round((root.matrix.tx || 640) * 2);
const H = Math.round((root.matrix.ty || 360) * 2);

const cv = createCanvas(W, H);
const ctx = cv.getContext('2d');
ctx.fillStyle = '#20242c';
ctx.fillRect(0, 0, W, H);
ctx.textAlign = 'center';
ctx.textBaseline = 'middle';

// ---- 坐标：节点矩阵是「相对父节点」的偏移，需要沿父链累积 ----
// 根节点（parent=null）的 matrix 就是画布中心，因此累积时跳过它，
// 再统一做 X 加半宽 / Y 用半高减（世界 Y 向上为正，屏幕 Y 向下为正）。
const byId = new Map(nodes.map((n) => [n.id, n]));
function absOf(n) {
  let x = 0, y = 0, cur = n;
  while (cur && cur.parent !== null && cur.parent !== undefined) {
    const m = cur.matrix || {};
    x += m.tx || 0;
    y += m.ty || 0;
    cur = byId.get(cur.parent);
  }
  return { x: W / 2 + x, y: H / 2 - y };
}

// ---- 绘制顺序：父先子后；同级按 z 降序（模拟器渲染器即如此：z 小 = 后画 = 更靠上）----
const childrenOf = new Map();
for (const n of nodes) {
  if (n.parent === null || n.parent === undefined) continue;
  if (!childrenOf.has(n.parent)) childrenOf.set(n.parent, []);
  childrenOf.get(n.parent).push(n);
}
const ordered = [];
(function walk(id) {
  for (const k of (childrenOf.get(id) || []).slice().sort((a, b) => b.z - a.z)) {
    ordered.push(k);
    walk(k.id);
  }
})(root.id);

let drawn = 0;
for (const n of ordered) {
  const { x, y } = absOf(n);
  if (!Number.isFinite(x) || !Number.isFinite(y)) continue;
  const m = n.matrix || {};
  const sx = Math.abs(m.a || 1) || 1;
  const sy = Math.abs(m.d || 1) || 1;
  const w = (n.sourceWidth || 0) * sx;
  const h = (n.sourceHeight || 0) * sy;

  if (n.kind === 'image' && w > 0 && h > 0) {
    // ★ 图片控件的色值字段是 imageColor（文本控件才是 fontColor）
    const c = css(n.imageColor);
    if (c.endsWith('0.000)')) continue;          // 全透明（容器占位）
    ctx.fillStyle = c;
    ctx.fillRect(x - w / 2, y - h / 2, w, h);
    drawn++;
  } else if (n.kind === 'textbox' && n.text) {
    const size = (n.fontSize || 24) * sy;
    ctx.font = `${Math.round(size)}px "Microsoft YaHei", SimHei, sans-serif`;
    ctx.fillStyle = css(n.fontColor === undefined ? 0xffffffff : n.fontColor);
    ctx.fillText(String(n.text), x, y);
    drawn++;
  }
}

// 画布边界参考线
ctx.strokeStyle = 'rgba(255,120,120,0.55)';
ctx.lineWidth = 2;
ctx.strokeRect(1, 1, W - 2, H - 2);

fs.mkdirSync(path.dirname(OUT), { recursive: true });
fs.writeFileSync(OUT, cv.toBuffer('image/png'));
console.log(`${OUT}  ${W}x${H}  场景节点 ${nodes.length} 个，绘制 ${drawn} 个`);
await call('stop', {});
