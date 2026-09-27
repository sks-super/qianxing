// _glyphtest.mjs — 临时：用「位图比对私用区码位」判定字体是否真的缺字（可靠版）
import { pathToFileURL } from 'node:url';
const MOD = 'C:/Users/JingSu/.workbuddy/binaries/node/workspace/node_modules/@napi-rs/canvas/index.js';
const { createCanvas } = await import(pathToFileURL(MOD).href);

const cv = createCanvas(80, 80);
const ctx = cv.getContext('2d');
const S = 64;

function ink(font, ch) {
  ctx.clearRect(0, 0, 80, 80);
  ctx.font = `${S}px "${font}"`;
  ctx.fillStyle = '#fff';
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  ctx.fillText(ch, 40, 40);
  const d = ctx.getImageData(0, 0, 80, 80).data;
  return Array.from({ length: 80 * 80 }, (_, i) => (d[i * 4 + 3] > 32 ? 1 : 0)).join('');
}

const chars = ['◀', '▶', '✓', '√', '→', '←', '↑', '★', '◆', '·', '×', '关', '跳', '左'];
const fonts = ['Microsoft YaHei', 'SimSun', 'SimHei', 'Segoe UI Symbol'];
const NOTDEF = '\uE000'; // 私用区，任何字体都无字形

for (const f of fonts) {
  const nd = ink(f, NOTDEF);
  const row = chars.map((c) => (ink(f, c) === nd ? '缺' : '有'));
  console.log(f.padEnd(18) + chars.map((c, i) => `${c}=${row[i]}`).join('  '));
}
