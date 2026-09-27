// 给关卡截图叠加坐标网格，便于肉眼精确读出平台/门/出生点的像素坐标。
// 用法: node _tools/orig_grid.mjs <inPng> <outPng> [step=100]
import { pathToFileURL } from 'node:url';
const MOD = 'C:/Users/JingSu/.workbuddy/binaries/node/workspace/node_modules/@napi-rs/canvas/index.js';
const { createCanvas, loadImage } = await import(pathToFileURL(MOD).href);

const [inp, outp, stepS] = process.argv.slice(2);
const step = +(stepS || 100);
const img = await loadImage(inp);
const W = img.width, H = img.height;
const cv = createCanvas(W, H);
const ctx = cv.getContext('2d');
ctx.drawImage(img, 0, 0);
ctx.font = 'bold 16px monospace';
ctx.textBaseline = 'top';
for (let x = 0; x <= W; x += step) {
  ctx.strokeStyle = x % (step * 5) === 0 ? 'rgba(255,64,64,0.95)' : 'rgba(0,180,255,0.55)';
  ctx.lineWidth = x % (step * 5) === 0 ? 2 : 1;
  ctx.beginPath(); ctx.moveTo(x + 0.5, 0); ctx.lineTo(x + 0.5, H); ctx.stroke();
  if (x % (step * 2) === 0) {
    ctx.fillStyle = 'rgba(0,0,0,0.75)'; ctx.fillRect(x + 2, 2, 46, 20);
    ctx.fillStyle = '#ffd23f'; ctx.fillText(String(x), x + 4, 4);
  }
}
for (let y = 0; y <= H; y += step) {
  ctx.strokeStyle = y % (step * 5) === 0 ? 'rgba(255,64,64,0.95)' : 'rgba(0,180,255,0.55)';
  ctx.lineWidth = y % (step * 5) === 0 ? 2 : 1;
  ctx.beginPath(); ctx.moveTo(0, y + 0.5); ctx.lineTo(W, y + 0.5); ctx.stroke();
  if (y % (step * 2) === 0) {
    ctx.fillStyle = 'rgba(0,0,0,0.75)'; ctx.fillRect(2, y + 2, 52, 20);
    ctx.fillStyle = '#ffd23f'; ctx.fillText(String(y), 4, y + 4);
  }
}
console.log(`${outp}  ${W}x${H}  step=${step}`);
await import('node:fs').then(fs => fs.writeFileSync(outp, cv.toBuffer('image/png')));
