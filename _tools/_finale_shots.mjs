// _finale_shots.mjs — 一次会话里渲染通关演出的多个时刻（省 session 槽 + 省时间）
// 用法: node _tools/_finale_shots.mjs --frames 560,575,590,610,650,700 --prefix fin
import { pathToFileURL } from 'node:url';
import fs from 'node:fs';
import path from 'node:path';
import { loadWebSession } from './_webclient.mjs';

const HOME = process.env.USERPROFILE || process.env.HOME || '';
const MOD = `${HOME}/.workbuddy/binaries/node/workspace/node_modules/@napi-rs/canvas/index.js`;
const { createCanvas } = await import(pathToFileURL(MOD).href);

const argv = process.argv.slice(2);
const opt = (n, d) => { const i = argv.indexOf('--' + n); return i >= 0 && argv[i + 1] ? argv[i + 1] : d; };

const ARCHIVE = opt('archive', '_simulator/_finale.web.save.json');
const CANVAS_ID = opt('canvas', 'mobile-16-9');
const FRAMES = opt('frames', '560,575,590,610,650,700').split(',').map((s) => parseInt(s, 10));
const PREFIX = opt('prefix', 'fin');
// 只画某个容器子树（默认画通关面板 287）——根层的背景容器模拟器 z 语义相反，
// 整树渲染会被背景盖黑；验证美术只需面板子树。
const ONLY = parseInt(opt('only', '-1'), 10);
const SKIP = new Set(opt('skip', '').split(',').filter(Boolean).map(Number));
// --click 563,301@25  → 在第 25 帧前点一次
// --click 563,301@25        单次点击
// --clicks 563,460@26;856,60@110   多次点击（分号分隔）
const CLICKS = (() => {
  const raw = opt('clicks', '') || opt('click', '');
  if (!raw) return [];
  return raw.split(';').map((s) => s.trim()).filter(Boolean).map((s) => {
    const [xy, f] = s.split('@');
    const [x, y] = xy.split(',').map(Number);
    return { x, y, frame: f ? parseInt(f, 10) : 0 };
  }).sort((a, b) => a.frame - b.frame);
})();

const { api } = loadWebSession('finale');
const call = (a, args = {}) => api('play', { action: a, args });

function css(v) {
  const n = (Number(v) || 0) >>> 0;
  const a = ((n >>> 24) & 255) / 255;
  const r = (n >>> 16) & 255, g = (n >>> 8) & 255, b = n & 255;
  return `rgba(${r},${g},${b},${a.toFixed(3)})`;
}

await api('load-archive', { path: ARCHIVE });
await call('start', { canvasId: CANVAS_ID });

let frame = 0;
for (const target of FRAMES) {
  while (frame < target) {
    for (const c of CLICKS) {
      if (c.frame === frame + 1 && !c.done) {
        await call('pointer', { x: c.x, y: c.y, type: 'click' });
        c.done = true;
      }
    }
    await call('step', { dt: 1 / 30 });
    frame++;
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
  const byId = new Map(nodes.map((n) => [n.id, n]));
  // ★ 必须累乘整条父链的仿射矩阵：容器被 SetLocalScale 缩放（翻页压扁、飞行块缩放）
  //   时，只加 tx/ty 会把子控件画到错位置、且尺寸不变 → 预览误判成「没缩放」。
  const matOf = (n) => {
    const m = n.matrix || {};
    return {
      a: m.a === undefined ? 1 : m.a, b: m.b || 0,
      c: m.c || 0, d: m.d === undefined ? 1 : m.d,
      tx: m.tx || 0, ty: m.ty || 0,
    };
  };
  const ABS = new Map();
  const absMatrix = (n) => {
    if (ABS.has(n.id)) return ABS.get(n.id);
    const l = matOf(n);
    const p = (n.parent === null || n.parent === undefined) ? null : byId.get(n.parent);
    // ★ 根节点自己的矩阵就是「画布中心」，absOf 里已用 W/2、H/2 顶上 → 根按单位阵处理
    const r = p ? (() => {
      const pm = absMatrix(p);
      return {
        a: pm.a * l.a + pm.c * l.b,
        b: pm.b * l.a + pm.d * l.b,
        c: pm.a * l.c + pm.c * l.d,
        d: pm.b * l.c + pm.d * l.d,
        tx: pm.a * l.tx + pm.c * l.ty + pm.tx,
        ty: pm.b * l.tx + pm.d * l.ty + pm.ty,
      };
    })() : { a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0 };
    ABS.set(n.id, r);
    return r;
  };
  const absOf = (n) => {
    const m = absMatrix(n);
    return { x: W / 2 + m.tx, y: H / 2 - m.ty, m };
  };

  const childrenOf = new Map();
  for (const n of nodes) {
    if (n.parent === null || n.parent === undefined) continue;
    if (!childrenOf.has(n.parent)) childrenOf.set(n.parent, []);
    childrenOf.get(n.parent).push(n);
  }
  const ordered = [];
  (function walk(id) {
    // ★ 引擎实际是：按 z 升序排好、再从后往前画（= z 大的先画 = 在下层）。
    //   所以预览必须按 z 降序，才和真机/模拟器一致。
    for (const k of (childrenOf.get(id) || []).slice().sort((a, b) => b.z - a.z)) {
      if (SKIP.has(k.id)) continue;
      ordered.push(k);
      walk(k.id);
    }
  })(ONLY > 0 ? ONLY : root.id);

  let drawn = 0;
  for (const n of ordered) {
    const { x, y, m } = absOf(n);
    if (!Number.isFinite(x) || !Number.isFinite(y)) continue;
    const sx = Math.hypot(m.a, m.b);
    const sy = Math.hypot(m.c, m.d);
    const w = (n.sourceWidth || 0) * sx;
    const h = (n.sourceHeight || 0) * sy;
    if (w <= 0.4 || h <= 0.4) continue;

    if (n.kind === 'image') {
      const c = css(n.imageColor);
      if (c.endsWith('0.000)')) continue;
      ctx.save();
      ctx.translate(x, y);
      // 设计坐标 y 向上、屏幕 y 向下 → 角度取反
      ctx.rotate(-Math.atan2(m.b, m.a));
      ctx.fillStyle = c;
      ctx.fillRect(-w / 2, -h / 2, w, h);
      ctx.restore();
      drawn++;
    } else if (n.kind === 'textbox' && n.text) {
      const size = (n.fontSize || 24) * sy;
      if (size < 2) continue;
      // ★ 引擎的文本框有 horizontalAlignment，预览要跟它走，否则左对齐的标题会画错位置
      const align = n.horizontalAlignment || 'Middle';
      let ax = 0, ta = 'center';
      if (align === 'Left') { ax = -w / 2; ta = 'left'; }
      else if (align === 'Right') { ax = w / 2; ta = 'right'; }
      ctx.save();
      ctx.translate(x, y);
      ctx.rotate(-Math.atan2(m.b, m.a));
      ctx.textAlign = ta;
      ctx.font = `${Math.round(size)}px "Microsoft YaHei", SimHei, sans-serif`;
      ctx.fillStyle = css(n.fontColor === undefined ? 0xffffffff : n.fontColor);
      ctx.fillText(String(n.text), ax, 0);
      ctx.restore();
      drawn++;
    }
  }

  const out = `_simulator/shots/${PREFIX}_${target}.png`;
  fs.mkdirSync(path.dirname(out), { recursive: true });
  fs.writeFileSync(out, cv.toBuffer('image/png'));
  console.log(`${out}  节点 ${nodes.length} 绘制 ${drawn}`);
}
await call('stop', {});
process.exit(0);
