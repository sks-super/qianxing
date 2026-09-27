// 把过暗的模拟器截图提亮，便于肉眼检查黑幕期间/低 alpha 控件的真实内容。
// 用法: node _tools/_boost.mjs <in.png> <out.png> [gain=6]
import { pathToFileURL } from 'node:url';

const MOD = 'C:/Users/JingSu/.workbuddy/binaries/node/workspace/node_modules/@napi-rs/canvas/index.js';
const { createCanvas, loadImage } = await import(pathToFileURL(MOD).href);

const [inFile, outFile, gainArg] = process.argv.slice(2);
const gain = Number(gainArg || 6);

const img = await loadImage(inFile);
const c = createCanvas(img.width, img.height);
const ctx = c.getContext('2d');
ctx.drawImage(img, 0, 0);
const data = ctx.getImageData(0, 0, img.width, img.height);
for (let i = 0; i < data.data.length; i += 4) {
  data.data[i] = Math.min(255, data.data[i] * gain);
  data.data[i + 1] = Math.min(255, data.data[i + 1] * gain);
  data.data[i + 2] = Math.min(255, data.data[i + 2] * gain);
}
ctx.putImageData(data, 0, 0);
const { writeFileSync } = await import('node:fs');
writeFileSync(outFile, c.toBuffer('image/png'));
console.log('written', outFile, `gain=${gain}`);
