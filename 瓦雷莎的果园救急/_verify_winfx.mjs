// 实拍验证：进关转场 + 「服客关卡胜利」结算动画
// 用法: node 瓦雷莎的果园救急/_verify_winfx.mjs [--frames 4,10,17,...] [--tag win] [--canvas mobile-16-9]
// 产物: _simulator/shots/<tag>_<frame>.png
import { pathToFileURL } from 'node:url';
import fs from 'node:fs';
import path from 'node:path';
import { loadWebSession } from '../_tools/_webclient.mjs';

const HOME = process.env.USERPROFILE || process.env.HOME || '';
const MOD = `${HOME}/.workbuddy/binaries/node/workspace/node_modules/@napi-rs/canvas/index.js`;
const { createCanvas } = await import(pathToFileURL(MOD).href);

const argv = process.argv.slice(2);
const opt = (n, d) => { const i = argv.indexOf('--' + n); return i >= 0 && argv[i + 1] ? argv[i + 1] : d; };
const ARCHIVE = opt('archive', '_simulator/瓦雷莎的果园救急.web.save.json');
const CANVAS = opt('canvas', 'mobile-16-9');
const TAG = opt('tag', 'win');
const MODE = opt('mode', 'win');   // win = 结算；enter = 进关转场
const FRAMES = opt('frames', '4,10,17,24,32,40,52,70').split(',').map(Number);
const ENTER = opt('enter', '1') !== '0';

const { api } = loadWebSession('winfx');
const call = (a, args = {}) => api('play', { action: a, args });
const stepN = async (n) => { for (let i = 0; i < n; i++) await call('step', { dt: 1 / 30 }); };

function css(v) {
  const n = (Number(v) || 0) >>> 0;
  const a = ((n >>> 24) & 255) / 255;
  return `rgba(${(n >>> 16) & 255},${(n >>> 8) & 255},${n & 255},${a.toFixed(3)})`;
}

function starPath(ctx, cx, cy, r, points, inner) {
  ctx.beginPath();
  for (let i = 0; i < points * 2; i++) {
    const ang = -Math.PI / 2 + (i * Math.PI) / points;
    const rr = i % 2 === 0 ? r : r * inner;
    const x = cx + Math.cos(ang) * rr;
    const y = cy + Math.sin(ang) * rr;
    if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
  }
  ctx.closePath();
}

async function shot(tag, frame) {
  const st = await call('get', { view: true, sceneRev: 0, compact: true });
  const nodes = st?.scene?.nodes || [];
  const root = nodes.find((n) => n.parent === null) || nodes[0];
  const W = Math.round((root?.matrix?.tx || 640) * 2);
  const H = Math.round((root?.matrix?.ty || 360) * 2);
  const cv = createCanvas(W, H);
  const ctx = cv.getContext('2d');
  ctx.fillStyle = '#20242c';
  ctx.fillRect(0, 0, W, H);
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';

  const byId = new Map(nodes.map((n) => [n.id, n]));
  const matOf = (n) => {
    const m = n.matrix || {};
    return { a: m.a ?? 1, b: m.b || 0, c: m.c || 0, d: m.d ?? 1, tx: m.tx || 0, ty: m.ty || 0 };
  };
  const ABS = new Map();
  const absM = (n) => {
    if (ABS.has(n.id)) return ABS.get(n.id);
    const l = matOf(n);
    const p = n.parent == null ? null : byId.get(n.parent);
    let r;
    if (!p) r = { a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0 };
    else {
      const pm = absM(p);
      r = {
        a: pm.a * l.a + pm.c * l.b, b: pm.b * l.a + pm.d * l.b,
        c: pm.a * l.c + pm.c * l.d, d: pm.b * l.c + pm.d * l.d,
        tx: pm.a * l.tx + pm.c * l.ty + pm.tx, ty: pm.b * l.tx + pm.d * l.ty + pm.ty,
      };
    }
    ABS.set(n.id, r);
    return r;
  };

  const kids = new Map();
  for (const n of nodes) {
    if (n.parent == null) continue;
    if (!kids.has(n.parent)) kids.set(n.parent, []);
    kids.get(n.parent).push(n);
  }
  const ordered = [];
  (function walk(id) {
    for (const k of (kids.get(id) || []).slice().sort((a, b) => b.z - a.z)) {
      ordered.push(k);
      walk(k.id);
    }
  })(root.id);

  let drawn = 0;
  for (const n of ordered) {
    const m = absM(n);
    const x = W / 2 + m.tx;
    const y = H / 2 - m.ty;
    const sx = Math.hypot(m.a, m.b);
    const sy = Math.hypot(m.c, m.d);
    const w = (n.sourceWidth || 0) * sx;
    const h = (n.sourceHeight || 0) * sy;
    if (w <= 0.4 || h <= 0.4) continue;
    const rot = -Math.atan2(m.b, m.a);

    if (n.kind === 'textbox') {
      if (!n.text) continue;
      const size = (n.fontSize || 24) * sy;
      if (size < 2) continue;
      ctx.save();
      ctx.translate(x, y);
      ctx.rotate(rot);
      ctx.font = `${Math.round(size)}px "Microsoft YaHei", SimHei, sans-serif`;
      ctx.fillStyle = css(n.fontColor === undefined ? 0xffffffff : n.fontColor);
      ctx.fillText(String(n.text), 0, 0);
      ctx.restore();
      drawn++;
      continue;
    }
    if (n.kind !== 'image') continue;
    const c = css(n.imageColor);
    if (c.endsWith('0.000)')) continue;
    ctx.save();
    ctx.translate(x, y);
    ctx.rotate(rot);
    ctx.fillStyle = c;
    ctx.strokeStyle = c;
    const id = n.imageId;
    if (id === 100002) {                       // 圆 / 椭圆
      ctx.beginPath();
      ctx.ellipse(0, 0, w / 2, h / 2, 0, 0, Math.PI * 2);
      ctx.fill();
    } else if (id === 100006) {                // 圆环
      ctx.lineWidth = Math.max(1, Math.min(w, h) * 0.12);
      ctx.beginPath();
      ctx.ellipse(0, 0, w / 2, h / 2, 0, 0, Math.PI * 2);
      ctx.stroke();
    } else if (id === 100003) {                // 三角形
      ctx.beginPath();
      ctx.moveTo(0, -h / 2); ctx.lineTo(w / 2, h / 2); ctx.lineTo(-w / 2, h / 2);
      ctx.closePath(); ctx.fill();
    } else if (id === 100004) {                // 四角星
      starPath(ctx, 0, 0, Math.min(w, h) / 2, 4, 0.34); ctx.fill();
    } else if (id === 100005) {                // 五角星
      starPath(ctx, 0, 0, Math.min(w, h) / 2, 5, 0.42); ctx.fill();
    } else {
      ctx.fillRect(-w / 2, -h / 2, w, h);
    }
    ctx.restore();
    drawn++;
  }

  const out = `_simulator/shots/${tag}_${frame}.png`;
  fs.mkdirSync(path.dirname(out), { recursive: true });
  fs.writeFileSync(out, cv.toBuffer('image/png'));
  return { out, nodes: nodes.length, drawn };
}

// 按文本找控件并点它（pointer 的 y 从下往上增）
async function clickText(re, label) {
  const st = await call('get', { view: true, sceneRev: 0, compact: true });
  const nodes = st?.scene?.nodes || [];
  const target = nodes.find((n) => n.kind === 'textbox' && re.test(n.text || ''));
  if (!target) throw new Error(`找不到文本 ${re}`);
  const byId = new Map(nodes.map((n) => [n.id, n]));
  const mat = (n) => {
    const m = n.matrix || {};
    return { a: m.a ?? 1, b: m.b || 0, c: m.c || 0, d: m.d ?? 1, tx: m.tx || 0, ty: m.ty || 0 };
  };
  const absM = (n) => {
    const l = mat(n);
    const p = n.parent == null ? null : byId.get(n.parent);
    if (!p) return { a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0 };
    const pm = absM(p);
    return { a: pm.a * l.a + pm.c * l.b, b: pm.b * l.a + pm.d * l.b,
      c: pm.a * l.c + pm.c * l.d, d: pm.b * l.c + pm.d * l.d,
      tx: pm.a * l.tx + pm.c * l.ty + pm.tx, ty: pm.b * l.tx + pm.d * l.ty + pm.ty };
  };
  const root = nodes.find((n) => n.parent == null);
  const W = Math.round((root?.matrix?.tx || 640) * 2);
  const H = Math.round((root?.matrix?.ty || 360) * 2);
  const m = absM(target);
  const x = W / 2 + m.tx;
  const y = H - (H / 2 - m.ty);
  await call('pointer', { x, y, type: 'click' });
  console.log(`  点击「${label}」 (${x.toFixed(0)}, ${y.toFixed(0)})`);
}

await api('load-archive', { path: ARCHIVE });
await call('start', { canvasId: CANVAS });
await stepN(30);

// 连闯 3 关：确认结算面板的「下一片」可用（换片走黑幕，不再拍转场）
if (MODE === 'loop') {
  for (let lv = 1; lv <= 3; lv++) {
    if (lv === 1) await clickText(/进入果园/, '进入果园');
    else await clickText(/下一片/, '下一片');
    let f = 0;
    for (const target of [2, 5, 8, 11]) {
      while (f < target) { await call('step', { dt: 1 / 30 }); f++; }
      const r = await shot(`trans${lv}`, target);
      console.log(`    ${r.out}  节点=${r.nodes}`);
    }
    await stepN(40);
    await call('serverSend', { name: '服客关卡胜利', params: [lv] });
    await stepN(80);
    console.log(`  第 ${lv} 片：已结算`);
  }
  const s = await call('get', { view: true, sceneRev: 0, compact: true });
  const tx = (s?.scene?.nodes || []).filter((n) => n.kind === 'textbox' && n.text).map((n) => n.text);
  console.log('\n最终文本：', tx.join(' | '));
  process.exit(0);
}

// 「服客同步存档信息」：验证进度灌入 + 光标自动对齐最新解锁 + 星星点亮
if (MODE === 'save') {
  const dump = async (tag) => {
    const s = await call('get', { view: true, sceneRev: 0, compact: true });
    const tx = (s?.scene?.nodes || []).filter((n) => n.kind === 'textbox' && n.text).map((n) => n.text);
    const r = await shot(tag, 0);
    console.log(`  ${r.out}  节点=${r.nodes}`);
    console.log('  文本：', tx.join(' | '));
  };
  // ★ 首屏会先弹序章，盖住整张地图 —— 先按 L 关掉，后面的对比图才看得到果园节点
  await call('key', { key: 'KeyboardCraftspersonKey21Down' });
  await stepN(12);
  console.log('① 未同步（应为「只解锁第 1 片」）');
  await dump('save_before');

  // ★ 新协议：只有一个整数 —— 已通关的最新关卡序号
  const latest = Number(opt('cleared', '6'));
  console.log(`② serverSend「服客同步存档信息」(${latest}) → 1..${latest} 全通关，解锁上限 = ${latest + 1}`);
  await call('serverSend', { name: '服客同步存档信息', params: [latest] });
  await stepN(45);
  await dump('save_after');

  console.log('③ serverSend「服客同步存档信息」(0) → 一片都没通关，应退回「只解锁第 1 片」');
  await call('serverSend', { name: '服客同步存档信息', params: [0] });
  await stepN(30);
  await dump('save_reset');

  const st2 = await call('get', { view: true, sceneRev: 0, compact: true });
  const logs = (st2?.logs || []).slice(-8);
  console.log('日志：', logs.length ? logs.map((l) => (typeof l === 'string' ? l : l.text || JSON.stringify(l))).join('\n  ') : '（无）');
  process.exit(0);
}

if (ENTER) {
  // 「进入果园」按钮（pointer 的 y 从下往上增）
  await call('pointer', { x: 1120.4, y: 720 - 614.4, type: 'click' });
  if (MODE === 'enter') {
    let f = 0;
    for (const target of FRAMES) {
      while (f < target) { await call('step', { dt: 1 / 30 }); f++; }
      const r = await shot(TAG, target);
      console.log(`  ${r.out}  节点=${r.nodes} 绘制=${r.drawn}`);
    }
    const st0 = await call('get', { view: true, sceneRev: 0, compact: true });
    const tx = (st0?.scene?.nodes || []).filter((n) => n.kind === 'textbox' && n.text).map((n) => n.text);
    console.log('\n转场后可见文本：', tx.join(' | '));
    const lg = (st0?.logs || []).slice(-14);
    console.log('日志：', lg.length ? lg.map((l) => (typeof l === 'string' ? l : l.text || JSON.stringify(l))).join('\n  ') : '（无）');
    process.exit(0);
  }
  await stepN(40);
  console.log('已进关');
}

// 返回选关：进关 → 关教程 → 点 HUD「回果园」→ 拍 split close（天空自上方、地面自下方合拢 + 淡出）
if (MODE === 'back') {
  await stepN(45);
  await clickText(/^关闭$/, '关闭');
  await stepN(12);
  await clickText(/回果园/, '回果园');
  let f = 0;
  for (const target of FRAMES) {
    while (f < target) { await call('step', { dt: 1 / 30 }); f++; }
    const r = await shot('back', target);
    console.log(`  ${r.out}  节点=${r.nodes}`);
  }
  const st1 = await call('get', { view: true, sceneRev: 0, compact: true });
  const t1 = (st1?.scene?.nodes || []).filter((n) => n.kind === 'textbox' && n.text).map((n) => n.text);
  console.log('\n返回后可见文本：', t1.join(' | '));
  const lg = (st1?.logs || []).slice(-10);
  console.log('日志：', lg.length ? lg.map((l) => (typeof l === 'string' ? l : l.text || JSON.stringify(l))).join('\n  ') : '（无）');
  process.exit(0);
}

console.log('→ 服务器下发「服客关卡胜利」(1)');
await call('serverSend', { name: '服客关卡胜利', params: [1] });

let frame = 0;
for (const target of FRAMES) {
  while (frame < target) { await call('step', { dt: 1 / 30 }); frame++; }
  const r = await shot(TAG, target);
  console.log(`  ${r.out}  节点=${r.nodes} 绘制=${r.drawn}`);
}

const st = await call('get', { view: true, sceneRev: 0, compact: true });
const texts = (st?.scene?.nodes || []).filter((n) => n.kind === 'textbox' && n.text).map((n) => n.text);
console.log('\n可见文本：', texts.join(' | '));
const logs = (st?.logs || []).slice(-10);
console.log('日志：', logs.length ? logs.map((l) => (typeof l === 'string' ? l : l.text || JSON.stringify(l))).join('\n  ') : '（无）');
