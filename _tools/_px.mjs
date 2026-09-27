// 采样 PNG 像素，用于核对模拟器截图的真实配色（排查「到底哪一层盖住了画面」）。
// 用法: node _tools/_px.mjs <png> [png...]
import { pathToFileURL } from 'node:url';

const MOD = 'C:/Users/JingSu/.workbuddy/binaries/node/workspace/node_modules/@napi-rs/canvas/index.js';
const { createCanvas, loadImage } = await import(pathToFileURL(MOD).href);

const pts = [[5, 5], [320, 80], [540, 310], [800, 283], [100, 100], [640, 600], [640, 60], [250, 560]];

for (const f of process.argv.slice(2)) {
  const img = await loadImage(f);
  const c = createCanvas(img.width, img.height);
  const ctx = c.getContext('2d');
  ctx.drawImage(img, 0, 0);
  const out = pts.map(([x, y]) => {
    const d = ctx.getImageData(Math.min(x, img.width - 1), Math.min(y, img.height - 1), 1, 1).data;
    const hex = ((d[0] << 16) | (d[1] << 8) | d[2]).toString(16).padStart(6, '0');
    return `${x},${y}=#${hex}/${d[3]}`;
  });
  console.log(f.split(/[\\/]/).pop(), `${img.width}x${img.height}`, out.join('  '));
}
