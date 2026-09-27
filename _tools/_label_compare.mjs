// 把「平台熄灭态 / 亮起态」两张截图按同一世界坐标区域裁切、放大并拼成对比图。
// 用法: node _tools/_label_compare.mjs <熄灭态png> <亮起态png> <输出png>
import { pathToFileURL } from 'node:url';
import { existsSync } from 'node:fs';

const MOD = 'C:/Users/JingSu/.workbuddy/binaries/node/workspace/node_modules/@napi-rs/canvas/index.js';
const { createCanvas, loadImage, GlobalFonts } = await import(pathToFileURL(MOD).href);

for (const f of ['C:/Windows/Fonts/msyh.ttc', 'C:/Windows/Fonts/msyhbd.ttc', 'C:/Windows/Fonts/simhei.ttf']) {
  if (existsSync(f)) { try { GlobalFonts.registerFromPath(f, 'CN'); } catch { /* ignore */ } }
}

const [ghostFile, litFile, out] = process.argv.slice(2);
const SRC = '/C:/Users/JingSu/.workbuddy/binaries/node/workspace/node_modules/@napi-rs/canvas/index.js';
void SRC;

// 关注区域（世界坐标，中心原点、Y 向上）→ 画布坐标
const WX0 = 70, WX1 = 300, WY0 = -205, WY1 = -115;
const SCALE = 2.6, PAD = 14, TITLE = 34;

const imgs = [];
for (const f of [ghostFile, litFile]) {
  const img = await loadImage(f);
  const cx = img.width / 2, cy = img.height / 2;
  imgs.push({
    img,
    sx: Math.round(cx + WX0), sy: Math.round(cy - WY1),
    sw: Math.round(WX1 - WX0), sh: Math.round(WY1 - WY0),
  });
}

const cw = Math.round(imgs[0].sw * SCALE) + PAD * 2;
const chRow = Math.round(imgs[0].sh * SCALE);
const canvas = createCanvas(cw, (chRow + TITLE) * 2 + PAD * 3);
const ctx = canvas.getContext('2d');

ctx.fillStyle = '#1b1b24';
ctx.fillRect(0, 0, canvas.width, canvas.height);

const captions = ['平台熄灭（tick=9）· 标签用 labelGhost 浅色', '平台亮起（tick=4）· 标签用 label 深色'];
imgs.forEach((it, i) => {
  const y = PAD + i * (chRow + TITLE + PAD);
  ctx.fillStyle = '#E8E8F0';
  ctx.font = '17px CN';
  ctx.fillText(captions[i], PAD, y + 22);
  const top = y + TITLE;
  ctx.imageSmoothingEnabled = false;
  ctx.drawImage(it.img, it.sx, it.sy, it.sw, it.sh, PAD, top, it.sw * SCALE, it.sh * SCALE);
  ctx.imageSmoothingEnabled = true;
  ctx.strokeStyle = '#4a4a5e';
  ctx.strokeRect(PAD + 0.5, top + 0.5, it.sw * SCALE - 1, it.sh * SCALE - 1);
});

const { writeFileSync } = await import('node:fs');
writeFileSync(out, canvas.toBuffer('image/png'));
console.log('已生成对比图:', out, `${canvas.width}x${canvas.height}`);
