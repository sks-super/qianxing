// 原版角色定位（眼睛法）：TickHop 的角色是「背景色方块 + 两颗前景色眼睛」，
//   因此会留下两个尺寸相近、彼此很近的孤立小亮点 —— 用它们的中点当角色中心。
// 用法: node _tools/orig_eyes.mjs <video> [--fps 100] [--bright 190] [--t0 0] [--t1 0]
import { spawn } from 'node:child_process';

const FF = 'C:/Users/JingSu/.workbuddy/binaries/python/envs/default/Lib/site-packages/imageio_ffmpeg/binaries/ffmpeg-win-x86_64-v7.1.exe';
const argv = process.argv.slice(2);
const file = argv.find((a) => !a.startsWith('--'));
const opt = (k, d) => { const i = argv.indexOf('--' + k); return i >= 0 ? argv[i + 1] : d; };
const FPS = parseFloat(opt('fps', '100'));
const BRIGHT = parseInt(opt('bright', '190'), 10);
const T0 = parseFloat(opt('t0', '0'));
const DUR = parseFloat(opt('t1', '0'));
const MINA = parseInt(opt('minarea', '6'), 10);
const MAXA = parseInt(opt('maxarea', '120'), 10);
const GAPMIN = parseFloat(opt('gapmin', '5'));
const GAPMAX = parseFloat(opt('gapmax', '34'));

const probe = () => new Promise((res) => {
  const p = spawn(FF, ['-hide_banner', '-i', file]); let s = '';
  p.stderr.on('data', (d) => (s += d));
  p.on('close', () => {
    const m = /Video:[\s\S]*?(\d{3,5})x(\d{3,5})/.exec(s);
    const d = /Duration: (\d+):(\d+):([\d.]+)/.exec(s);
    res({ w: +m[1], h: +m[2], dur: d ? +d[1] * 3600 + +d[2] * 60 + parseFloat(d[3]) : 0 });
  });
});
const meta = await probe();
const W = meta.w, H = meta.h, N = W * H;
const total = DUR > 0 ? DUR : meta.dur - T0;
const NF = Math.round(total * FPS);
console.log(`源 ${W}x${H}  ${T0}s 起 ${total.toFixed(2)}s @${FPS}fps = ${NF} 帧`);

const args = ['-hide_banner', '-loglevel', 'error'];
if (T0 > 0) args.push('-ss', String(T0));
args.push('-i', file, '-vf', `fps=${FPS}`, '-frames:v', String(NF), '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-');
const st = spawn(FF, args).stdout;
let buf = Buffer.alloc(0);
const frames = [];

await new Promise((res) => {
  st.on('data', (d) => {
    buf = Buffer.concat([buf, d]);
    while (buf.length >= N * 3) {
      const f = buf.subarray(0, N * 3); buf = buf.subarray(N * 3);
      const mask = new Uint8Array(N);
      for (let i = 0, p = 0; i < N; i++, p += 3) mask[i] = (f[p] * 299 + f[p + 1] * 587 + f[p + 2] * 114) > BRIGHT * 1000 ? 1 : 0;
      const lab = new Int32Array(N).fill(-1);
      const stack = new Int32Array(N);
      const small = [];
      for (let i = 0; i < N; i++) {
        if (!mask[i] || lab[i] >= 0) continue;
        let sp = 0; stack[sp++] = i; lab[i] = 1;
        let n = 0, x0 = 1e9, y0 = 1e9, x1 = -1, y1 = -1;
        while (sp > 0) {
          const c = stack[--sp]; n++;
          const cx = c % W, cy = c / W | 0;
          if (cx < x0) x0 = cx; if (cx > x1) x1 = cx;
          if (cy < y0) y0 = cy; if (cy > y1) y1 = cy;
          for (const t of [c - 1, c + 1, c - W, c + W]) {
            if (t < 0 || t >= N || lab[t] >= 0 || !mask[t]) continue;
            if (Math.abs((t % W) - cx) + Math.abs((t / W | 0) - cy) !== 1) continue;
            lab[t] = 1; stack[sp++] = t;
          }
        }
        if (n >= MINA && n <= MAXA) small.push({ x: (x0 + x1) / 2, y: (y0 + y1) / 2, n, w: x1 - x0 + 1, h: y1 - y0 + 1 });
      }
      // 找「尺寸相近、距离合适」的成对亮点
      let best = null;
      for (let a = 0; a < small.length; a++) for (let b = a + 1; b < small.length; b++) {
        const A = small[a], B = small[b];
        const dist = Math.hypot(A.x - B.x, A.y - B.y);
        if (dist < GAPMIN || dist > GAPMAX) continue;
        const ratio = Math.min(A.n, B.n) / Math.max(A.n, B.n);
        if (ratio < 0.6) continue;
        // 眼睛应大致水平（允许轻微倾斜）
        const dy = Math.abs(A.y - B.y);
        if (dy > dist * 0.6) continue;
        const score = ratio * (1 - dy / Math.max(1, dist)) / (1 + Math.abs(dist - 14) / 14);
        if (!best || score > best.score) best = { score, x: (A.x + B.x) / 2, y: (A.y + B.y) / 2, A, B, dist };
      }
      frames.push(best);
    }
  });
  st.on('close', res);
});

const hits = frames.map((b, i) => ({ b, i })).filter((x) => x.b);
console.log(`找到眼对的帧: ${hits.length}/${frames.length}`);
if (!hits.length) process.exit(0);
const ds = hits.map((x) => x.b.dist).sort((a, b) => a - b);
console.log(`双眼间距中位数 = ${ds[ds.length >> 1].toFixed(1)}px（可反推角色宽度）`);
if (hits.length < 20) process.exit(0);

const SP = ' .:-=+*#%@';
const line = (arr, label) => {
  const mn = Math.min(...arr), mx = Math.max(...arr);
  let s = '';
  for (const v of arr) s += SP[Math.min(9, Math.round((v - mn) / Math.max(1, mx - mn) * 9))];
  console.log(`--- ${label} ${mn.toFixed(0)}..${mx.toFixed(0)} ---\n${s}`);
};
line(hits.map((x) => x.b.y), 'y 轨迹（中心）');
line(hits.map((x) => x.b.x), 'x 轨迹（中心）');

// 连续段 + 顶点检测
const segs = []; let cur = [];
for (const h of hits) { if (cur.length && h.i - cur[cur.length - 1].i > 4) { segs.push(cur); cur = []; } cur.push(h); }
if (cur.length) segs.push(cur);
console.log(`--- 连续跟踪段 ${segs.length} 段，最长 ${Math.max(...segs.map((s) => s.length))} 帧 ---`);
const arcs = [];
for (const seg of segs) {
  if (seg.length < 10) continue;
  const ys = seg.map((x) => x.b.y);
  for (let i = 3; i < seg.length - 3; i++) {
    if (!(ys[i] <= ys[i - 1] && ys[i] <= ys[i + 1] && ys[i] < ys[i - 2] && ys[i] < ys[i + 2])) continue;
    let s = i; while (s > 0 && ys[s - 1] >= ys[s] - 0.01 && i - s < FPS * 2) s--;
    let e = i; while (e < seg.length - 1 && ys[e + 1] >= ys[e] - 0.01 && e - i < FPS * 2) e++;
    const apexH = ys[s] - ys[i];
    if (apexH < 8) continue;
    arcs.push({ s, i, e, apexH, seg, tUp: (i - s) / FPS, tDown: (e - i) / FPS });
  }
}
const merged = [];
for (const a of arcs) {
  const last = merged[merged.length - 1];
  if (last && a.seg === last.seg && a.s <= last.e + 2) { if (a.apexH > last.apexH) merged[merged.length - 1] = a; } else merged.push(a);
}
console.log(`--- 跳跃弧 ${merged.length} 段 ---`);
merged.slice(0, 10).forEach((a) => {
  const H2 = hits[0].b.A.h;
  console.log(`  起点 t=${a.seg[a.s].i / FPS + T0}s  顶点 t=${a.seg[a.i].i / FPS + T0}s  落地 t=${a.seg[a.e].i / FPS + T0}s`);
  console.log(`     顶点高 ${a.apexH.toFixed(1)}px | 上升 ${a.tUp.toFixed(3)}s 下落 ${a.tDown.toFixed(3)}s 滞空 ${(a.tUp + a.tDown).toFixed(3)}s`);
  console.log(`     起跳速度 ${(2 * a.apexH / a.tUp).toFixed(0)}px/s | g升 ${(2 * a.apexH / a.tUp ** 2).toFixed(0)} | g降 ${(2 * a.apexH / a.tDown ** 2).toFixed(0)} px/s²`);
});
