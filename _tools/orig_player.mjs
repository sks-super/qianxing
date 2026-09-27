// 原版《滴答咔哒》角色定位 + 跳跃弧实测
//   平台会随时间闪烁 → 帧差法失效；改为「形状识别」：
//   角色是画面里唯一的大号实心方块（白/亮色），平台是细长线，文字是破碎笔画。
// 用法: node _tools/orig_player.mjs <video> [--fps 100] [--bright 190] [--t0 0] [--t1 0] [--minarea 300] [--maxarea 6000]
import { pathToFileURL } from 'node:url';
import { spawn } from 'node:child_process';

const MOD = 'C:/Users/JingSu/.workbuddy/binaries/node/workspace/node_modules/@napi-rs/canvas/index.js';
const { createCanvas, loadImage } = await import(pathToFileURL(MOD).href);
const FF = 'C:/Users/JingSu/.workbuddy/binaries/python/envs/default/Lib/site-packages/imageio_ffmpeg/binaries/ffmpeg-win-x86_64-v7.1.exe';

const argv = process.argv.slice(2);
const file = argv.find((a) => !a.startsWith('--'));
const opt = (k, d) => { const i = argv.indexOf('--' + k); return i >= 0 ? argv[i + 1] : d; };
const FPS = parseFloat(opt('fps', '100'));
const BRIGHT = parseInt(opt('bright', '190'), 10);
const T0 = parseFloat(opt('t0', '0'));
const DUR = parseFloat(opt('t1', '0'));
const MINA = parseInt(opt('minarea', '300'), 10);
const MAXA = parseInt(opt('maxarea', '6000'), 10);
const SHOW = argv.includes('--show');

function probe() {
  return new Promise((res) => {
    const p = spawn(FF, ['-hide_banner', '-i', file]);
    let s = '';
    p.stderr.on('data', (d) => (s += d));
    p.on('close', () => {
      const m = /Video:[\s\S]*?(\d{3,5})x(\d{3,5})/.exec(s);
      const d = /Duration: (\d+):(\d+):([\d.]+)/.exec(s);
      res({ w: +m[1], h: +m[2], dur: d ? (+d[1]) * 3600 + (+d[2]) * 60 + parseFloat(d[3]) : 0 });
    });
  });
}
const meta = await probe();
const total = DUR > 0 ? DUR : meta.dur - T0;
const NF = Math.round(total * FPS);
const W = meta.w, H = meta.h;
const N = W * H;
console.log(`源 ${W}x${H}  分析 ${T0}s 起 ${total.toFixed(2)}s @${FPS}fps = ${NF} 帧`);

const args = ['-hide_banner', '-loglevel', 'error'];
if (T0 > 0) args.push('-ss', String(T0));
args.push('-i', file, '-vf', `fps=${FPS}`, '-frames:v', String(NF), '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-');
const st = spawn(FF, args).stdout;
let buf = Buffer.alloc(0);

const comps = [];
const run = () => new Promise((res) => {
  st.on('data', (d) => {
    buf = Buffer.concat([buf, d]);
    while (buf.length >= N * 3) {
      const f = buf.subarray(0, N * 3); buf = buf.subarray(N * 3);
      // 亮像素掩码（只做 1 次扫描）
      const mask = new Uint8Array(N);
      for (let i = 0, p = 0; i < N; i++, p += 3) {
        mask[i] = (f[p] * 299 + f[p + 1] * 587 + f[p + 2] * 114) > BRIGHT * 100000 ? 1 : 0;
      }
      const lab = new Int32Array(N).fill(-1);
      const stack = new Int32Array(N);
      const list = [];
      for (let i = 0; i < N; i++) {
        if (!mask[i] || lab[i] >= 0) continue;
        let sp = 0; stack[sp++] = i; lab[i] = list.length;
        let n = 0, x0 = 1e9, y0 = 1e9, x1 = -1, y1 = -1;
        while (sp > 0) {
          const c = stack[--sp]; n++;
          const cx = c % W, cy = c / W | 0;
          if (cx < x0) x0 = cx; if (cx > x1) x1 = cx;
          if (cy < y0) y0 = cy; if (cy > y1) y1 = cy;
          const nb = [c - 1, c + 1, c - W, c + W];
          for (const t of nb) {
            if (t < 0 || t >= N || lab[t] >= 0 || !mask[t]) continue;
            if (Math.abs((t % W) - cx) + Math.abs((t / W | 0) - cy) !== 1) continue;
            lab[t] = lab[i]; stack[sp++] = t;
          }
        }
        const w = x1 - x0 + 1, h = y1 - y0 + 1;
        const fill = n / (w * h);
        if (n >= MINA && n <= MAXA) list.push({ x0, y0, x1, y1, w, h, n, fill });
      }
      comps.push(list);
    }
  });
  st.on('close', res);
});
await run();

console.log(`共 ${comps.length} 帧，平均断点 ${(comps.reduce((a, b) => a + b.length, 0) / Math.max(1, comps.length)).toFixed(1)} 个候选`);
// 角色评分：方形（w≈h）+ 高填充率
const score = (c) => {
  const sq = Math.min(c.w, c.h) / Math.max(c.w, c.h);
  return sq * c.fill * Math.sqrt(c.n);
};
const trace = [];
comps.forEach((list, i) => {
  if (!list.length) return;
  let best = null, bs = -1;
  for (const c of list) { const s = score(c); if (s > bs) { bs = s; best = c; } }
  if (best && bs > 0.45) {
    trace.push({ f: i, t: T0 + i / FPS, x: (best.x0 + best.x1) / 2, y: (best.y0 + best.y1) / 2, w: best.w, h: best.h, fill: best.fill, s: bs });
  }
});
console.log(`判定为角色的帧: ${trace.length}/${comps.length}`);
if (!trace.length) process.exit(0);
const sizes = new Map();
for (const p of trace) sizes.set(`${p.w}x${p.h}`, (sizes.get(`${p.w}x${p.h}`) || 0) + 1);
console.log('--- 尺寸分布 top6（像素，原分辨率）---');
[...sizes.entries()].sort((a, b) => b[1] - a[1]).slice(0, 6).forEach(([k, v]) => console.log(`  ${k}  ${v} 帧`));
const hArr = trace.map((p) => p.h).sort((a, b) => a - b);
const PH = hArr[hArr.length >> 1];
console.log(`角色高度中位数 = ${PH}px`);

if (SHOW) {
  const ys = trace.map((p) => p.y);
  const yMin = Math.min(...ys), yMax = Math.max(...ys);
  const SP = ' .:-=+*#%@';
  let line = '';
  for (const y of ys) line += SP[Math.min(9, Math.round((y - yMin) / Math.max(1, yMax - yMin) * 9))];
  console.log(`--- y 轨迹 ${yMin.toFixed(0)}..${yMax.toFixed(0)} ---`);
  console.log(line);
  console.log('--- x 轨迹 ---');
  const xs = trace.map((p) => p.x);
  const xMin = Math.min(...xs), xMax = Math.max(...xs);
  let l2 = '';
  for (const x of xs) l2 += SP[Math.min(9, Math.round((x - xMin) / Math.max(1, xMax - xMin) * 9))];
  console.log(l2);
}

// ---------- 跳跃弧检测（只取连续跟踪段）----------
const segs = [];
let cur = [];
for (let i = 0; i < trace.length; i++) {
  if (cur.length && trace[i].f - cur[cur.length - 1].f > 3) { segs.push(cur); cur = []; }
  cur.push(trace[i]);
}
if (cur.length) segs.push(cur);
console.log(`--- 连续跟踪段: ${segs.length} 段 ---`);
const arcs = [];
for (const seg of segs) {
  if (seg.length < 8) continue;
  const ys = seg.map((p) => p.y);
  for (let i = 3; i < seg.length - 3; i++) {
    if (!(ys[i] <= ys[i - 1] && ys[i] < ys[i + 1] && ys[i] < ys[i - 2] && ys[i] < ys[i + 2])) continue;
    let s = i;
    while (s > 0 && ys[s - 1] > ys[s] && i - s < FPS * 2) s--;
    let e = i;
    while (e < seg.length - 1 && ys[e + 1] > ys[e] && e - i < FPS * 2) e++;
    const apexH = ys[s] - ys[i];
    if (apexH < PH * 0.5) continue;
    arcs.push({ s, i, e, apexH, seg, tUp: (i - s) / FPS, tDown: (e - i) / FPS });
  }
}
const merged = [];
for (const a of arcs) {
  const last = merged[merged.length - 1];
  if (last && a.seg === last.seg && a.s <= last.e + 2) { if (a.apexH > last.apexH) merged[merged.length - 1] = a; }
  else merged.push(a);
}
console.log(`--- 检测到 ${merged.length} 段跳跃弧（角色高 ${PH}px 为尺度）---`);
merged.slice(0, 10).forEach((a) => {
  const gUp = 2 * a.apexH / (a.tUp * a.tUp);
  const gDn = 2 * a.apexH / (a.tDown * a.tDown);
  console.log(`  t=${a.seg[a.s].t.toFixed(2)}s  顶点=${a.seg[a.i].t.toFixed(2)}s  落地=${a.seg[a.e].t.toFixed(2)}s`);
  console.log(`     顶点高 ${a.apexH.toFixed(1)}px = ${(a.apexH / PH).toFixed(2)} 角色高 | 上升 ${a.tUp.toFixed(3)}s 下落 ${a.tDown.toFixed(3)}s 总滞空 ${(a.tUp + a.tDown).toFixed(3)}s`);
  console.log(`     起跳速度 ${(gUp * a.tUp).toFixed(0)} px/s | g升 ${gUp.toFixed(0)} | g降 ${gDn.toFixed(0)} px/s² | 降/升比 ${(gDn / gUp).toFixed(2)}`);
  console.log(`     水平位移 ${(a.seg[a.e].x - a.seg[a.s].x).toFixed(0)}px = ${((a.seg[a.e].x - a.seg[a.s].x) / PH).toFixed(2)} 角色高`);
});
