// 采样某个「世界坐标矩形」内的像素亮度分布，用来验证平台秒数标签的对比度。
// 用法: node _tools/_label_probe.mjs <png> <worldX> <worldY> <halfW> <halfH> [标签名]
//   世界坐标 → 画布坐标：cx = W/2 + wx，cy = H/2 - wy（原点在画布中心，Y 向上）
import { pathToFileURL } from 'node:url';

const MOD = 'C:/Users/JingSu/.workbuddy/binaries/node/workspace/node_modules/@napi-rs/canvas/index.js';
const { createCanvas, loadImage } = await import(pathToFileURL(MOD).href);

const [file, wx, wy, hw, hh, name] = process.argv.slice(2);
const img = await loadImage(file);
const c = createCanvas(img.width, img.height);
const ctx = c.getContext('2d');
ctx.drawImage(img, 0, 0);

const cx = Math.round(img.width / 2 + Number(wx));
const cy = Math.round(img.height / 2 - Number(wy));
const w = Math.round(Number(hw) * 2), h = Math.round(Number(hh) * 2);
const x0 = Math.max(0, Math.min(img.width - 1, cx - Math.round(hw)));
const y0 = Math.max(0, Math.min(img.height - 1, cy - Math.round(hh)));
const data = ctx.getImageData(x0, y0, Math.min(w, img.width - x0), Math.min(h, img.height - y0)).data;

let minL = 999, maxL = -1, minC = null, maxC = null;
const hist = new Map();
for (let i = 0; i < data.length; i += 4) {
  const r = data[i], g = data[i + 1], b = data[i + 2];
  const l = Math.round(0.2126 * r + 0.7152 * g + 0.0722 * b);
  if (l < minL) { minL = l; minC = [r, g, b]; }
  if (l > maxL) { maxL = l; maxC = [r, g, b]; }
  const key = ((r >> 4) << 8) | ((g >> 4) << 4) | (b >> 4);
  hist.set(key, (hist.get(key) || 0) + 1);
}
const top = [...hist.entries()].sort((a, b) => b[1] - a[1]).slice(0, 3).map(([k, n]) => {
  const r = ((k >> 8) & 15) * 17, g = ((k >> 4) & 15) * 17, b = (k & 15) * 17;
  return `#${((r << 16) | (g << 8) | b).toString(16).padStart(6, '0')}×${n}`;
});
const hex = (c) => '#' + ((c[0] << 16) | (c[1] << 8) | c[2]).toString(16).padStart(6, '0');

console.log(`${file.split(/[\\/]/).pop()}  ${name || ''}  画布(${cx},${cy}) 区域${w}×${h}`);
console.log(`  对比度: 最暗 ${minL} ${hex(minC)}  ←→  最亮 ${maxL} ${hex(maxC)}   (差 ${maxL - minL})`);
console.log(`  主要颜色: ${top.join('  ')}`);

// ASCII 位图：把区域按亮度画出来。
// 只看 minL/maxL 会被「平台之外的背景像素」骗到（背景天生很暗，看起来像有深色字符），
// 所以必须肉眼看一眼形状——数字会是一个明显的块状图案。
const cols = Math.min(w, 60), rows = Math.min(h, 30);
const sx = Math.max(1, Math.floor(w / cols)), sy = Math.max(1, Math.floor(h / rows));
// 用中位数亮度做阈值，避免被极端值主导
const lum = [];
for (let i = 0; i < data.length; i += 4) lum.push(0.2126 * data[i] + 0.7152 * data[i + 1] + 0.0722 * data[i + 2]);
const sorted = [...lum].sort((a, b) => a - b);
const mid = sorted[Math.floor(sorted.length / 2)];
console.log(`  亮度中位数 ${mid.toFixed(0)}（阈值取此值，亮=█ 暗=·）：`);
for (let y = 0; y < rows; y++) {
  let line = '';
  for (let x = 0; x < cols; x++) {
    const px = Math.min(w - 1, x * sx), py = Math.min(h - 1, y * sy);
    const o = (py * w + px) * 4;
    const l = 0.2126 * data[o] + 0.7152 * data[o + 1] + 0.0722 * data[o + 2];
    line += l >= mid ? '█' : '·';
  }
  console.log('    ' + line);
}
