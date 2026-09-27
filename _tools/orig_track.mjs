// 原版《滴答咔哒 / Tick Hop》跳跃参数实测工具
//   思路：镜头固定 → 用「逐像素中值」建背景 → 帧差 + 连通域找出运动的角色
//   → 取 y 轨迹 → 自动识别「先升后降」的抛物线弧 → 拟合得到
//     起跳速度 v0、重力 g、顶点高度 apex（均以像素为单位），
//   再以「角色自身高度」为尺度归一化（跨引擎可迁移）。
// 用法: node _tools/orig_track.mjs <video> [--fps 50] [--w 400] [--t0 0] [--t1 0] [--bgwin 0.4]
import { spawn } from 'node:child_process';

const FF = 'C:/Users/JingSu/.workbuddy/binaries/python/envs/default/Lib/site-packages/imageio_ffmpeg/binaries/ffmpeg-win-x86_64-v7.1.exe';
const argv = process.argv.slice(2);
const file = argv.find((a) => !a.startsWith('--'));
const opt = (k, d) => { const i = argv.indexOf('--' + k); return i >= 0 ? argv[i + 1] : d; };
const FPS = parseFloat(opt('fps', '50'));
const W = parseInt(opt('w', '400'), 10);
const T0 = parseFloat(opt('t0', '0'));
const DUR = parseFloat(opt('t1', '0'));   // 0 = 全片

function probe() {
  return new Promise((res) => {
    const p = spawn(FF, ['-hide_banner', '-i', file]);
    let s = '';
    p.stderr.on('data', (d) => (s += d));
    p.on('close', () => {
      const m = /Video:[\s\S]*?(\d{3,5})x(\d{3,5})/.exec(s);
      const d = /Duration: (\d+):(\d+):([\d.]+)/.exec(s);
      const fps = /,\s([\d.]+) fps/.exec(s);
      res({ w: +m[1], h: +m[2], dur: d ? (+d[1]) * 3600 + (+d[2]) * 60 + parseFloat(d[3]) : 0, fps: fps ? +fps[1] : 0 });
    });
  });
}

const meta = await probe();
const srcH = Math.round(W * meta.h / meta.w);
const total = DUR > 0 ? DUR : (meta.dur - T0);
const NF = Math.max(1, Math.round(total * FPS));
console.log(`源: ${meta.w}x${meta.h} @${meta.fps}fps  ${meta.dur.toFixed(2)}s`);
console.log(`分析: ${W}x${srcH} @${FPS}fps  从 ${T0}s 起 ${total.toFixed(2)}s  共 ${NF} 帧`);

function frames(t0, dur, n, scaleW) {
  const args = ['-hide_banner', '-loglevel', 'error'];
  if (t0 > 0) args.push('-ss', String(t0));
  args.push('-i', file, '-vf', `fps=${FPS},scale=${scaleW}:-1`, '-frames:v', String(n),
    '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-');
  return spawn(FF, args).stdout;
}

const N = W * srcH;
// ---------- 第一遍：逐像素中值背景 ----------
const HB = 32;                      // 灰度直方图档数
const hist = new Uint8Array(N * HB);
const st = frames(T0, total, NF, W);
let buf = Buffer.alloc(0);
let got = 0;
await new Promise((res) => {
  st.on('data', (d) => {
    buf = Buffer.concat([buf, d]);
    while (buf.length >= N * 3) {
      const f = buf.subarray(0, N * 3); buf = buf.subarray(N * 3);
      for (let i = 0, p = 0; i < N; i++, p += 3) {
        const g = (f[p] * 77 + f[p + 1] * 151 + f[p + 2] * 28) >> 8;
        hist[i * HB + (g >> 3)]++;
      }
      got++;
    }
  });
  st.on('close', res);
});
const bg = new Uint8Array(N);
for (let i = 0; i < N; i++) {
  let acc = 0, half = got / 2, k = 0;
  for (; k < HB; k++) { acc += hist[i * HB + k]; if (acc >= half) break; }
  bg[i] = (k << 3) | 4;
}
console.log(`背景建模完成（${got} 帧）`);

// ---------- 第二遍：帧差 + 连通域 ----------
const THR = 34, MINAREA = 10;
const compsPerFrame = [];
const st2 = frames(T0, total, NF, W);
buf = Buffer.alloc(0);
let fi = 0;
const mask = new Uint8Array(N);
const maskTot = new Float32Array(N);
const lab = new Int32Array(N);
const stack = new Int32Array(N);
await new Promise((res) => {
  st2.on('data', (d) => {
    buf = Buffer.concat([buf, d]);
    while (buf.length >= N * 3) {
      const f = buf.subarray(0, N * 3); buf = buf.subarray(N * 3);
      mask.fill(0);
      for (let i = 0, p = 0; i < N; i++, p += 3) {
        const g = (f[p] * 77 + f[p + 1] * 151 + f[p + 2] * 28) >> 8;
        const mv = Math.abs(g - bg[i]) > THR ? 1 : 0;
        mask[i] = mv;
        if (mv) maskTot[i]++;
      }
      lab.fill(-1);
      const list = [];
      for (let i = 0; i < N; i++) {
        if (!mask[i] || lab[i] >= 0) continue;
        let sp = 0; stack[sp++] = i; lab[i] = list.length;
        let n = 0, sMinX = 1e9, sMinY = 1e9, sMaxX = -1, sMaxY = -1, sr = 0, sg = 0, sb = 0;
        while (sp > 0) {
          const c = stack[--sp]; n++;
          const cx = c % W, cy = c / W | 0;
          if (cx < sMinX) sMinX = cx; if (cx > sMaxX) sMaxX = cx;
          if (cy < sMinY) sMinY = cy; if (cy > sMaxY) sMaxY = cy;
          sr += f[c * 3]; sg += f[c * 3 + 1]; sb += f[c * 3 + 2];
          const nb = [c - 1, c + 1, c - W, c + W];
          for (const t of nb) {
            if (t < 0 || t >= N || lab[t] >= 0 || !mask[t]) continue;
            const tx = t % W, ty = t / W | 0;
            if (Math.abs(ty - cy) + Math.abs(tx - cx) !== 1) continue;
            lab[t] = lab[i]; stack[sp++] = t;
          }
        }
        if (n >= MINAREA) list.push({ n, x0: sMinX, y0: sMinY, x1: sMaxX, y1: sMaxY, r: sr / n | 0, g: sg / n | 0, b: sb / n | 0 });
      }
      compsPerFrame.push(list);
      fi++;
    }
  });
  st2.on('close', res);
});
console.log(`逐帧连通域完成（${compsPerFrame.length} 帧）`);

// ---------- 运动热区图（跨帧累计）+ 候选物体挑选 ----------
const NC = 64, NR = 20;
const cellW = W / NC, cellH = srcH / NR;
const heat = new Float32Array(NC * NR);
for (let i = 0; i < N; i++) {
  if (!maskTot[i]) continue;
  const x = i % W, y = i / W | 0;
  heat[Math.min(NR - 1, y / cellH | 0) * NC + Math.min(NC - 1, x / cellW | 0)]++;
}
{
  const mx = Math.max(...heat);
  console.log('--- 运动热区（全窗口累计；越亮=该格变化越频繁）---');
  const CH = ' .:-=+*#%@';
  for (let r = 0; r < NR; r++) {
    let line = '';
    for (let c = 0; c < NC; c++) line += CH[Math.min(9, Math.round(heat[r * NC + c] / Math.max(1, mx) * 9))];
    console.log('  ' + line);
  }
}

const sigOf = (c) => {
  const w = c.x1 - c.x0 + 1, h = c.y1 - c.y0 + 1;
  return `${Math.round(w / 6)}_${Math.round(h / 6)}_${c.r >> 5}_${c.g >> 5}_${c.b >> 5}`;
};
const stat = new Map();
compsPerFrame.forEach((list, fi) => {
  const seen = new Set();
  for (const c of list) {
    const s = sigOf(c); if (seen.has(s)) continue; seen.add(s);
    let o = stat.get(s);
    if (!o) { o = { frames: 0, x0: 1e9, x1: -1, y0: 1e9, y1: -1, w: c.x1 - c.x0 + 1, h: c.y1 - c.y0 + 1, r: c.r, g: c.g, b: c.b }; stat.set(s, o); }
    o.frames++;
    const cx = (c.x0 + c.x1) / 2, cy = (c.y0 + c.y1) / 2;
    o.x0 = Math.min(o.x0, cx); o.x1 = Math.max(o.x1, cx);
    o.y0 = Math.min(o.y0, cy); o.y1 = Math.max(o.y1, cy);
  }
});
const NF2 = compsPerFrame.length;
console.log('--- 候选物体（出现率 + 运动幅度；★=选为角色）---');
const ranked = [...stat.entries()].map(([s, o]) => ({
  s, o, ratio: o.frames / NF2, xr: o.x1 - o.x0, yr: o.y1 - o.y0,
})).sort((a, b) => (b.ratio * (b.xr + 2 * b.yr)) - (a.ratio * (a.xr + 2 * a.yr)));
ranked.slice(0, 10).forEach((r, i) => {
  console.log(`  ${i === 0 ? '★' : ' '} ${(r.ratio * 100).toFixed(0).padStart(3)}%  ${String(r.o.w).padStart(3)}x${String(r.o.h).padEnd(3)}  RGB≈(${r.o.r},${r.o.g},${r.o.b})  x位移=${r.xr.toFixed(0)} y位移=${r.yr.toFixed(0)}  评分=${(r.ratio * (r.xr + 2 * r.yr)).toFixed(0)}`);
});
const target = ranked.length ? ranked[0].s : null;
const trace = [];
compsPerFrame.forEach((list, i) => {
  const cands = list.filter((k) => sigOf(k) === target);
  if (!cands.length) return;
  const prev = trace[trace.length - 1];
  let best = cands[0];
  if (prev) {
    let bd = 1e9;
    for (const c of cands) {
      const cx = (c.x0 + c.x1) / 2, cy = (c.y0 + c.y1) / 2;
      const d = (cx - prev.x) ** 2 + (cy - prev.y) ** 2;
      if (d < bd) { bd = d; best = c; }
    }
  }
  trace.push({ f: i, t: T0 + i / FPS, x: (best.x0 + best.x1) / 2, y: (best.y0 + best.y1) / 2, w: best.x1 - best.x0 + 1, h: best.y1 - best.y0 + 1, n: best.n });
});
console.log(`跟踪到 ${trace.length} 帧（${(trace.length / compsPerFrame.length * 100).toFixed(0)}%）`);
if (!trace.length) process.exit(0);
const ws = trace.map((p) => p.w).sort((a, b) => a - b);
const hs = trace.map((p) => p.h).sort((a, b) => a - b);
const med = (a) => a[a.length >> 1];
console.log(`角色尺寸中位数: ${med(ws)}x${med(hs)}px（半分辨率，全分辨率需 x${(meta.w / W).toFixed(2)}）`);

// ---------- y 轨迹与跳跃弧检测 ----------
const ys = trace.map((p) => p.y);
const yMin = Math.min(...ys), yMax = Math.max(...ys);
console.log(`--- y 轨迹（半分辨率像素；y 越小越高）---  范围 ${yMin.toFixed(0)}..${yMax.toFixed(0)}`);
const SPARK = ' .:-=+*#%@';
let line = '';
for (let i = 0; i < ys.length; i++) line += SPARK[Math.min(9, Math.round((ys[i] - yMin) / Math.max(1, yMax - yMin) * 9))];
console.log(line);
console.log('时间轴: ' + trace[0].t.toFixed(1) + 's → ' + trace[trace.length - 1].t.toFixed(1) + 's（每秒 ' + FPS + ' 帧）');

// 顶点检测：y 先减后增
const arcs = [];
for (let i = 3; i < ys.length - 3; i++) {
  const isApex = ys[i] <= ys[i - 1] && ys[i] < ys[i + 1] && ys[i] < ys[i - 2] && ys[i] < ys[i + 2];
  if (!isApex) continue;
  // 向左找实测起点（y 开始上升处），向右找落点（y 停止下降/持平）
  let s = i;
  while (s > 1 && ys[s - 1] >= ys[s - 2] - 0.01 && ys[s - 1] > ys[s] && i - s < FPS * 2) s--;
  let e = i;
  while (e < ys.length - 2 && ys[e + 1] < ys[e] + 0.01 && ys[e + 1] > ys[e] && e - i < FPS * 2) e++;
  const apexH = ys[s] - ys[i];
  if (apexH < 8) continue;                     // 太小的抖动忽略
  arcs.push({ s, i, e, apexH, tUp: (i - s) / FPS, tDown: (e - i) / FPS, x0: trace[s].x, x1: trace[e].x, playerH: trace[i].h });
}
// 去重：同一段只留最高的
const merged = [];
for (const a of arcs) {
  const last = merged[merged.length - 1];
  if (last && a.s <= last.e + 2) { if (a.apexH > last.apexH) merged[merged.length - 1] = a; }
  else merged.push(a);
}
console.log(`--- 检测到 ${merged.length} 段跳跃弧 ---`);
merged.slice(0, 12).forEach((a) => {
  const H = a.playerH;
  // 以角色自身高度为单位归一化
  const apexUnits = a.apexH / H;
  // 上升段: apex = 0.5*g*tUp^2 → g_up ; 起跳速度 v0 = g_up * tUp
  const gUp = 2 * a.apexH / (a.tUp * a.tUp);
  const v0 = gUp * a.tUp;
  const gDn = 2 * a.apexH / (a.tDown * a.tDown);
  console.log(`  t=${trace[a.s].t.toFixed(2)}s  顶点${trace[a.i].t.toFixed(2)}s  落地${trace[a.e].t.toFixed(2)}s`);
  console.log(`     顶点高 ${a.apexH.toFixed(0)}px = ${apexUnits.toFixed(2)} 个角色高 | 上升 ${a.tUp.toFixed(3)}s 下落 ${a.tDown.toFixed(3)}s`);
  console.log(`     起跳速度 ${v0.toFixed(0)} px/s | 上升重力 ${gUp.toFixed(0)} px/s² | 下落重力 ${gDn.toFixed(0)} px/s² | 下落/上升重力比 ${(gDn / gUp).toFixed(2)}`);
  console.log(`     水平位移 ${(a.x1 - a.x0).toFixed(0)}px（${((a.x1 - a.x0) / H).toFixed(2)} 个角色高）`);
});
