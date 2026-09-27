// 诊断2：找出原始帧流里"真正发生变化"的帧位置，判断有效帧率。
// 用法: node _tools/_probe_static.mjs <rawFile> <W> <H>
import fs from 'node:fs';
const [raw, ws, hs] = process.argv.slice(2);
const W = +ws, H = +hs, FS = W * H * 3;
const F = Math.floor(fs.statSync(raw).size / FS);
const fd = fs.openSync(raw, 'r');
const buf = Buffer.allocUnsafe(FS);
const lum = new Float32Array(W * H);
const prev = new Float32Array(W * H);
function read(i) {
  fs.readSync(fd, buf, 0, FS, i * FS);
  for (let p = 0, q = 0; p < W * H; p++, q += 3) lum[p] = 0.299 * buf[q] + 0.587 * buf[q + 1] + 0.114 * buf[q + 2];
}
read(0); prev.set(lum);
const changedAt = [];
let cums = [];
for (let i = 1; i < F; i++) {
  read(i);
  let c = 0, s = 0;
  for (let p = 0; p < W * H; p++) { const d = Math.abs(lum[p] - prev[p]); if (d > 25) { c++; s += d; } }
  prev.set(lum);
  if (c > W * H * 0.0005) changedAt.push(i);
  cums.push(c);
}
console.log(`frames=${F}  变化帧数=${changedAt.length}  有效帧率≈${(changedAt.length / (F / 100)).toFixed(1)} fps`);
console.log('变化帧索引:', changedAt.slice(0, 80).join(' '));
const gaps = [];
for (let i = 1; i < changedAt.length; i++) gaps.push(changedAt[i] - changedAt[i - 1]);
gaps.sort((a, b) => a - b);
if (gaps.length) console.log(`间隔中位=${gaps[(gaps.length - 1) >> 1]}  最小=${gaps[0]}  最大=${gaps[gaps.length - 1]}`);
