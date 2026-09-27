// 从原版玩法短片的「原始帧流」中追踪玩家，拟合跳跃抛物线，反推重力与起跳速度。
//   方法：时间均值背景差分
//     1) 背景 = 逐像素时间均值（玩家只在某像素短暂停留，均值≈背景色）
//     2) mask = |亮度 - 均值| > DIFF（绝对值，明底暗底通吃）
//     3) 跳过淡入/淡出帧（mask 覆盖率异常高者）
//     4) 连通域 → 取面积最大的"会动"团块为玩家，最近邻连续跟踪
//     5) y(t) 求导 → 起跳/顶点/落地；分段最小二乘拟合二次曲线 → 加速度 & 初速度
// 用法: node _tools/orig_jump.mjs <rawFile> <W> <H> <FPS> [--out csv] [--debug]
//        [--diff 60] [--from 0] [--to 999999]
import fs from 'node:fs';

const args = process.argv.slice(2);
const rawPath = args[0];
const W = +args[1], H = +args[2], FPS = +args[3];
const outCsv = args.includes('--out') ? args[args.indexOf('--out') + 1] : null;
const DEBUG = args.includes('--debug');
const DIFF = args.includes('--diff') ? +args[args.indexOf('--diff') + 1] : 60;
const FROM = args.includes('--from') ? +args[args.indexOf('--from') + 1] : 0;
const TO = args.includes('--to') ? +args[args.indexOf('--to') + 1] : 1e9;
const MINA = args.includes('--mina') ? +args[args.indexOf('--mina') + 1] : 450;

const FS = W * H * 3;
const F = Math.floor(fs.statSync(rawPath).size / FS);
console.log(`# ${rawPath}  frames=${F}  ${W}x${H} @${FPS}fps  (${(F / FPS).toFixed(2)}s)  diff=${DIFF}`);

const fd = fs.openSync(rawPath, 'r');
const frame = Buffer.allocUnsafe(FS);
const lum = new Float32Array(W * H);
const sum = new Float64Array(W * H);

function readFrame(i) {
  fs.readSync(fd, frame, 0, FS, i * FS);
  for (let p = 0, q = 0; p < W * H; p++, q += 3) {
    lum[p] = 0.299 * frame[q] + 0.587 * frame[q + 1] + 0.114 * frame[q + 2];
  }
}

// ---- pass 1: 时间均值背景 ----
for (let i = 0; i < F; i++) {
  readFrame(i);
  for (let p = 0; p < W * H; p++) sum[p] += lum[p];
}
const mean = new Float32Array(W * H);
for (let p = 0; p < W * H; p++) mean[p] = sum[p] / F;

// ---- pass 2: 逐帧差分 + 连通域 ----
const label = new Int32Array(W * H);
const stack = new Int32Array(W * H);
const MARGIN = 2;

function components(mask) {
  label.fill(0);
  const comps = [];
  for (let p = 0; p < W * H; p++) {
    if (!mask[p] || label[p]) continue;
    let sp = 0;
    stack[sp++] = p; label[p] = comps.length + 1;
    let area = 0, minx = W, maxx = -1, miny = H, maxy = -1, sx = 0, sy = 0;
    while (sp > 0) {
      const q = stack[--sp];
      const x = q % W, y = (q - x) / W;
      area++; sx += x; sy += y;
      if (x < minx) minx = x; if (x > maxx) maxx = x;
      if (y < miny) miny = y; if (y > maxy) maxy = y;
      if (x > 0 && mask[q - 1] && !label[q - 1]) { label[q - 1] = comps.length + 1; stack[sp++] = q - 1; }
      if (x < W - 1 && mask[q + 1] && !label[q + 1]) { label[q + 1] = comps.length + 1; stack[sp++] = q + 1; }
      if (y > 0 && mask[q - W] && !label[q - W]) { label[q - W] = comps.length + 1; stack[sp++] = q - W; }
      if (y < H - 1 && mask[q + W] && !label[q + W]) { label[q + W] = comps.length + 1; stack[sp++] = q + W; }
    }
    comps.push({
      area, minx, maxx, miny, maxy,
      w: maxx - minx + 1, h: maxy - miny + 1,
      cx: sx / area, cy: sy / area,
      border: minx <= MARGIN || miny <= MARGIN || maxx >= W - 1 - MARGIN || maxy >= H - 1 - MARGIN,
    });
  }
  return comps;
}

const mask = new Uint8Array(W * H);
const traj = [];
let prev = null;
let skipped = 0;

// 在候选团块的包围盒内找「内嵌暗块」—— 玩家是「亮身体 + 两只暗眼睛」，
// 眼睛是身体上的固定参考点，不受下方拖影/与计时数字合并的影响。
function eyeInfo(comp) {
  const bw = comp.w, bh = comp.h, N = bw * bh;
  const local = new Uint8Array(N);
  let darkCount = 0;
  for (let y = comp.miny; y <= comp.maxy; y++) {
    const row = y * W;
    for (let x = comp.minx; x <= comp.maxx; x++) {
      if (lum[row + x] < 130) { local[(y - comp.miny) * bw + (x - comp.minx)] = 1; darkCount++; }
    }
  }
  if (darkCount === 0 || darkCount > N * 0.35) return null;
  const seen = new Uint8Array(N);
  const st = new Int32Array(N);
  const cl = [];
  for (let p = 0; p < N; p++) {
    if (!local[p] || seen[p]) continue;
    let sp = 0; st[sp++] = p; seen[p] = 1;
    let a = 0, sx = 0, sy = 0, mnX = 1e9, mxX = -1, mnY = 1e9, mxY = -1;
    while (sp > 0) {
      const q = st[--sp];
      const lx = q % bw, ly = (q - lx) / bw;
      a++; sx += lx; sy += ly;
      if (lx < mnX) mnX = lx; if (lx > mxX) mxX = lx;
      if (ly < mnY) mnY = ly; if (ly > mxY) mxY = ly;
      for (let d = 0; d < 4; d++) {
        const nx = lx + (d === 0 ? 1 : d === 1 ? -1 : 0), ny = ly + (d === 2 ? 1 : d === 3 ? -1 : 0);
        if (nx < 0 || ny < 0 || nx >= bw || ny >= bh) continue;
        const nq = ny * bw + nx;
        if (local[nq] && !seen[nq]) { seen[nq] = 1; st[sp++] = nq; }
      }
    }
    // 只保留「内嵌」团块：圆角处露出的背景会贴边，眼睛不会
    const touch = mnX <= 1 || mxX >= bw - 2 || mnY <= 1 || mxY >= bh - 2;
    if (!touch) cl.push({ a, cx: comp.minx + sx / a, cy: comp.miny + sy / a, w: mxX - mnX + 1, h: mxY - mnY + 1, mnX, mxX, mnY, mxY, bw, bh });
  }
  return cl;
}

for (let i = FROM; i < Math.min(TO, F); i++) {
  readFrame(i);
  let nset = 0;
  for (let p = 0; p < W * H; p++) {
    const d = Math.abs(lum[p] - mean[p]);
    if (d > DIFF) { mask[p] = 1; nset++; } else mask[p] = 0;
  }
  if (nset > W * H * 0.25) { // 淡入/淡出/整屏切换帧
    traj.push({ i, x: NaN, y: NaN, w: 0, h: 0, area: 0 });
    prev = null; skipped++;
    continue;
  }
  const comps = components(mask);
  const cand = comps.filter((c) =>
    c.area >= MINA && c.area <= 12000 && !c.border &&
    c.w >= 10 && c.h >= 10 && c.w < W * 0.5 && c.h < H * 0.6 &&
    c.w / c.h >= 0.35 && c.w / c.h <= 2.4
  );
  // 双目筛选：包围盒内恰好两小块内嵌暗色，且尺寸/间距合理
  const eyes = [];
  for (const c of cand) {
    const cl = eyeInfo(c);
    if (!cl || cl.length !== 2) continue;
    const [e1, e2] = cl;
    if (e1.a > 90 || e2.a > 90) continue;
    if (e1.w > 14 || e2.w > 14 || e1.h > 14 || e2.h > 14) continue;
    const dx = Math.abs(e1.cx - e2.cx), dy = Math.abs(e1.cy - e2.cy);
    if (dx < 4 || dx > 32 || dy > 12) continue;
    eyes.push({ ...c, ex: (e1.cx + e2.cx) / 2, ey: (e1.cy + e2.cy) / 2, eyeA: e1.a + e2.a });
  }
  if (DEBUG && i < FROM + 3) {
    console.log(`frame ${i} set=${nset} 候选 ${cand.length} 双目 ${eyes.length}:`,
      eyes.map((c) => `(${c.ex.toFixed(0)},${c.ey.toFixed(0)} ${c.w}x${c.h} a=${c.area} eye=${c.eyeA})`).join(' '));
  }
  let pick = null;
  if (prev) {
    let best = 1e9;
    for (const c of eyes) {
      const d = Math.hypot(c.ex - prev.ex, c.ey - prev.ey);
      if (d < best) { best = d; pick = c; }
    }
    if (best > 150) pick = null;
  }
  if (!pick) for (const c of eyes) if (!pick || c.eyeA > pick.eyeA) pick = c;
  if (pick) { traj.push({ i, x: pick.ex, y: pick.ey, w: pick.w, h: pick.h, area: pick.area }); prev = pick; }
  else { traj.push({ i, x: NaN, y: NaN, w: 0, h: 0, area: 0 }); prev = null; }
}
fs.closeSync(fd);
console.log(`# 跳过整屏切换帧 ${skipped}`);

// ---- 平滑 & 速度 ----
const n = traj.length;
const dt = 1 / FPS;
const ys = traj.map((t) => t.y);
function med(arr, i, r) {
  const s = [];
  for (let k = Math.max(0, i - r); k <= Math.min(n - 1, i + r); k++) if (Number.isFinite(arr[k])) s.push(arr[k]);
  if (!s.length) return NaN;
  s.sort((a, b) => a - b);
  return s[(s.length - 1) >> 1];
}
const ysm = ys.map((_, i) => med(ys, i, 2));
const vy = ysm.map((_, i) => {
  if (i === 0 || i === n - 1) return NaN;
  if (!Number.isFinite(ysm[i - 1]) || !Number.isFinite(ysm[i + 1])) return NaN;
  return (ysm[i + 1] - ysm[i - 1]) / (2 * dt);
});

const tracked = traj.filter((t) => t.area > 0);
const hsArr = tracked.map((t) => t.h).sort((a, b) => a - b);
const wsArr = tracked.map((t) => t.w).sort((a, b) => a - b);
const playerHpx = hsArr.length ? hsArr[(hsArr.length - 1) >> 1] : NaN;
const playerWpx = wsArr.length ? wsArr[(wsArr.length - 1) >> 1] : NaN;

// ---- 弧段检测 ----
const arcs = [];
for (let i = 2; i < n - 3; i++) {
  const a = vy[i - 1], b = vy[i];
  if (!Number.isFinite(a) || !Number.isFinite(b)) continue;
  if (a >= -15 && b < -50) {
    let apex = -1;
    for (let k = i + 1; k < n - 2; k++) {
      if (!Number.isFinite(vy[k]) || !Number.isFinite(vy[k + 1])) break;
      if (vy[k] < 0 && vy[k + 1] >= 0) { apex = k + 1; break; }
    }
    if (apex < 0) continue;
    let land = -1;
    for (let k = apex + 1; k < n - 2; k++) {
      if (!Number.isFinite(vy[k]) || !Number.isFinite(vy[k + 1])) break;
      if (vy[k] > 50 && vy[k + 1] <= 50) { land = k + 1; break; }
    }
    if (land < 0) land = Math.min(n - 1, apex + Math.round((apex - i) * 1.5));
    arcs.push({ takeoff: i, apex, land });
    i = apex;
  }
}

function fitQuad(i0, i1) {
  let S = [0, 0, 0, 0, 0], B = [0, 0, 0], cnt = 0;
  for (let i = i0; i <= i1; i++) {
    if (!Number.isFinite(ysm[i])) continue;
    const t = (i - i0) * dt, y = ysm[i];
    S[0] += t ** 4; S[1] += t ** 3; S[2] += t ** 2; S[3] += t; S[4] += 1;
    B[0] += y * t * t; B[1] += y * t; B[2] += y;
    cnt++;
  }
  if (cnt < 4) return null;
  const A = [[S[0], S[1], S[2]], [S[1], S[2], S[3]], [S[2], S[3], S[4]]];
  const b = [B[0], B[1], B[2]];
  for (let c = 0; c < 3; c++) {
    let p = c;
    for (let r = c + 1; r < 3; r++) if (Math.abs(A[r][c]) > Math.abs(A[p][c])) p = r;
    [A[c], A[p]] = [A[p], A[c]]; [b[c], b[p]] = [b[p], b[c]];
    if (Math.abs(A[c][c]) < 1e-12) return null;
    for (let r = 0; r < 3; r++) {
      if (r === c) continue;
      const f = A[r][c] / A[c][c];
      for (let k = c; k < 3; k++) A[r][k] -= f * A[c][k];
      b[r] -= f * b[c];
    }
  }
  return { c2: b[0] / A[0][0], c1: b[1] / A[1][1], c0: b[2] / A[2][2] };
}

console.log(`\n# 玩家尺寸(px, 中位) = ${playerWpx}x${playerHpx}   跟踪率 ${(tracked.length / n * 100).toFixed(0)}%`);
console.log(`# 检测到 ${arcs.length} 段跳跃\n`);
console.log('idx   t起(s)  上升(s)  上升高(px)  空中(s)  净抬升(px)   a_rise(px/s²)  v0_rise(px/s)  a_fall(px/s²)');
const rows = [];
arcs.forEach((A, k) => {
  const t0 = A.takeoff * dt;
  const riseT = (A.apex - A.takeoff) * dt;
  const riseH = (ysm[A.takeoff] ?? NaN) - (ysm[A.apex] ?? NaN);
  const airT = (A.land - A.takeoff) * dt;
  const netH = (ysm[A.takeoff] ?? NaN) - (ysm[A.land] ?? NaN);
  const fr = fitQuad(A.takeoff, A.apex);
  const ff = fitQuad(A.apex, A.land);
  const aR = fr ? 2 * fr.c2 : NaN, vR = fr ? -fr.c1 : NaN;
  const aF = ff ? 2 * ff.c2 : NaN;
  rows.push({ idx: k, t0, riseT, riseH, airT, netH, aR, vR, aF });
  console.log(
    `${String(k).padStart(3)}  ${t0.toFixed(2).padStart(6)}  ${riseT.toFixed(3).padStart(6)}  ` +
    `${riseH.toFixed(1).padStart(9)}  ${airT.toFixed(3).padStart(6)}  ${netH.toFixed(1).padStart(10)}  ` +
    `${aR.toFixed(0).padStart(12)}  ${vR.toFixed(0).padStart(12)}  ${aF.toFixed(0).padStart(12)}`);
});

const good = rows.filter((r) => r.riseH > 15 && r.riseT > 0.06 && r.airT > 0.15 && r.riseT < 1.2 && r.netH > -25);
if (good.length) {
  good.sort((a, b) => b.riseH - a.riseH);
  const top = good.slice(0, Math.max(1, Math.ceil(good.length / 3)));
  const avg = (f) => top.reduce((s, r) => s + f(r), 0) / top.length;
  const Hpx = avg((r) => r.riseH), Trise = avg((r) => r.riseT), aR = avg((r) => r.aR), vR = avg((r) => r.vR), aF = avg((r) => r.aF);
  console.log(`\n# 满跳样本 ${top.length}/${good.length} 段（按上升高度取前 1/3）`);
  console.log(`#   平均上升高度 = ${Hpx.toFixed(1)} px = ${(Hpx / playerHpx).toFixed(2)} 个玩家高`);
  console.log(`#   平均上升耗时 = ${Trise.toFixed(3)} s`);
  console.log(`#   上升加速度   = ${aR.toFixed(0)} px/s²`);
  console.log(`#   下落加速度   = ${aF.toFixed(0)} px/s²`);
  console.log(`#   起跳初速度   = ${vR.toFixed(0)} px/s`);
  if (Number.isFinite(playerHpx)) {
    const s = 44 / playerHpx;
    console.log(`\n# ★ 换算到工程（玩家 44 高）: 上升重力 ≈ ${(aR * s).toFixed(0)}  下落重力 ≈ ${(aF * s).toFixed(0)}  ` +
      `起跳 ≈ ${(vR * s).toFixed(0)}  跳高 ≈ ${(Hpx * s).toFixed(0)} px`);
  }
}

if (outCsv) {
  const lines = ['frame,t,x,y,w,h,area,vy'];
  for (let i = 0; i < n; i++) lines.push(`${traj[i].i},${(traj[i].i * dt).toFixed(3)},${traj[i].x.toFixed(1)},${traj[i].y.toFixed(1)},${traj[i].w},${traj[i].h},${traj[i].area},${Number.isFinite(vy[i]) ? vy[i].toFixed(1) : ''}`);
  fs.writeFileSync(outCsv, lines.join('\n'));
  console.log(`\n# 轨迹已写入 ${outCsv}`);
}

// ---- 可视化核对：把检测框画回指定帧 ----
const ovIdx = args.indexOf('--overlay');
if (ovIdx >= 0) {
  const list = args[ovIdx + 1].split(',').map(Number).filter(Number.isFinite);
  const dir = args.includes('--outdir') ? args[args.indexOf('--outdir') + 1] : '_simulator/orig/check';
  const { pathToFileURL } = await import('node:url');
  const MOD = 'C:/Users/JingSu/.workbuddy/binaries/node/workspace/node_modules/@napi-rs/canvas/index.js';
  const { createCanvas } = await import(pathToFileURL(MOD).href);
  fs.mkdirSync(dir, { recursive: true });
  const fd2 = fs.openSync(rawPath, 'r');
  for (const fi of list) {
    const k = fi - FROM;
    if (k < 0 || k >= n) continue;
    fs.readSync(fd2, frame, 0, FS, fi * FS);
    const cv = createCanvas(W, H);
    const ctx = cv.getContext('2d');
    const id = ctx.createImageData(W, H);
    for (let p = 0, q = 0; p < W * H; p++, q += 3) {
      id.data[p * 4] = frame[q]; id.data[p * 4 + 1] = frame[q + 1]; id.data[p * 4 + 2] = frame[q + 2]; id.data[p * 4 + 3] = 255;
    }
    ctx.putImageData(id, 0, 0);
    // 轨迹尾迹
    ctx.strokeStyle = 'rgba(0,200,255,0.85)'; ctx.lineWidth = 1; ctx.beginPath();
    let started = false;
    for (let j = Math.max(0, k - 120); j <= k; j++) {
      if (!Number.isFinite(traj[j].x)) { started = false; continue; }
      if (!started) { ctx.moveTo(traj[j].x, traj[j].y); started = true; } else ctx.lineTo(traj[j].x, traj[j].y);
    }
    ctx.stroke();
    // 当前框
    const t = traj[k];
    if (t.area > 0) {
      ctx.strokeStyle = '#ff3355'; ctx.lineWidth = 2;
      ctx.strokeRect(t.x - t.w / 2, t.y - t.h / 2, t.w, t.h);
      ctx.fillStyle = '#ff3355'; ctx.font = 'bold 14px monospace';
      ctx.fillText(`${fi} a=${t.area} ${t.w}x${t.h}`, Math.min(t.x - t.w / 2, W - 160), Math.max(14, t.y - t.h / 2 - 4));
    }
    fs.writeFileSync(`${dir}/chk_${String(fi).padStart(4, '0')}.png`, cv.toBuffer('image/png'));
  }
  fs.closeSync(fd2);
  console.log(`# 核对图已写入 ${dir}/`);
}
