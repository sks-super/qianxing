// 输出关卡截图的白色（实心）结构行程，用于精确还原几何。
// 用法: node _tools/orig_scan.mjs <inPng> [step=20] [thr=128]
import { pathToFileURL } from 'node:url';
const MOD = 'C:/Users/JingSu/.workbuddy/binaries/node/workspace/node_modules/@napi-rs/canvas/index.js';
const { createCanvas, loadImage } = await import(pathToFileURL(MOD).href);

const [inp, stepS, thrS] = process.argv.slice(2);
const step = +(stepS || 20), thr = +(thrS || 128);
const img = await loadImage(inp);
const W = img.width, H = img.height;
const cv = createCanvas(W, H);
const ctx = cv.getContext('2d');
ctx.drawImage(img, 0, 0);
const d = ctx.getImageData(0, 0, W, H).data;
const lum = new Int32Array(W * H);
for (let p = 0, q = 0; p < W * H; p++, q += 4) lum[p] = (0.299 * d[q] + 0.587 * d[q + 1] + 0.114 * d[q + 2]) | 0;

function runsRow(y) {
  const out = [];
  let s = -1;
  for (let x = 0; x < W; x++) {
    const on = lum[y * W + x] >= thr;
    if (on && s < 0) s = x;
    if (!on && s >= 0) { if (x - s >= 6) out.push([s, x - 1]); s = -1; }
  }
  if (s >= 0 && W - s >= 6) out.push([s, W - 1]);
  return out;
}
console.log(`# ${inp} ${W}x${H}  thr=${thr}`);
console.log('\n## 行扫描 (y: 白段[x0..x1])');
let prevSig = '';
for (let y = 0; y < H; y += step) {
  const r = runsRow(y);
  const sig = JSON.stringify(r);
  if (sig === prevSig) continue;
  prevSig = sig;
  console.log(`${String(y).padStart(4)}: ${r.map(([a, b]) => `${a}..${b}`).join('  ')}`);
}
console.log('\n## 列扫描 (x: 白段[y0..y1])');
prevSig = '';
for (let x = 0; x < W; x += step) {
  const out = [];
  let s = -1;
  for (let y = 0; y < H; y++) {
    const on = lum[y * W + x] >= thr;
    if (on && s < 0) s = y;
    if (!on && s >= 0) { if (y - s >= 6) out.push([s, y - 1]); s = -1; }
  }
  if (s >= 0 && H - s >= 6) out.push([s, H - 1]);
  const sig = JSON.stringify(out);
  if (sig === prevSig) continue;
  prevSig = sig;
  console.log(`${String(x).padStart(4)}: ${out.map(([a, b]) => `${a}..${b}`).join('  ')}`);
}
