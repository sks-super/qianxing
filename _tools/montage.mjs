// 把一批截图拼成带序号的联系表（montage），便于一眼看全原版前几关。
// 用法: node _tools/montage.mjs <outPng> <cols> <cellW> <img...> [--labelPrefix 原版]
import { pathToFileURL } from 'node:url';
import fs from 'node:fs';
import path from 'node:path';

const MOD = 'C:/Users/JingSu/.workbuddy/binaries/node/workspace/node_modules/@napi-rs/canvas/index.js';
const { createCanvas, loadImage } = await import(pathToFileURL(MOD).href);

const argv = process.argv.slice(2);
const [out, colsS, cellWS, ...rest] = argv;
const cols = parseInt(colsS, 10);
const cellW = parseInt(cellWS, 10);
const imgs = rest.filter((f) => fs.existsSync(f));
const rows = Math.ceil(imgs.length / cols);
const ar = 9 / 16;
const cellH = Math.round(cellW * ar);
const pad = 6, labelH = 26;
const W = cols * cellW + (cols + 1) * pad;
const H = rows * (cellH + labelH) + (rows + 1) * pad;

const cv = createCanvas(W, H);
const ctx = cv.getContext('2d');
ctx.fillStyle = '#14161c'; ctx.fillRect(0, 0, W, H);
ctx.textBaseline = 'middle';

for (let i = 0; i < imgs.length; i++) {
  const r = Math.floor(i / cols), c = i % cols;
  const x = pad + c * (cellW + pad), y = pad + r * (cellH + labelH + pad);
  const img = await loadImage(imgs[i]);
  // 等比放入（contain）
  const s = Math.min(cellW / img.width, cellH / img.height);
  const dw = img.width * s, dh = img.height * s;
  ctx.fillStyle = '#000'; ctx.fillRect(x, y, cellW, cellH);
  ctx.drawImage(img, x + (cellW - dw) / 2, y + (cellH - dh) / 2, dw, dh);
  const name = path.basename(imgs[i]).replace(/\.png$/, '');
  ctx.fillStyle = '#e8ecf4';
  ctx.font = 'bold 15px "Microsoft YaHei", SimHei, sans-serif';
  ctx.fillText(name.slice(0, 26), x + 2, y + cellH + labelH / 2 + 1);
}
fs.writeFileSync(out, cv.toBuffer('image/png'));
console.log(`${out}  ${W}x${H}  ${imgs.length} 张 / ${cols} 列`);
