// 把 config.lua 的 LEVELS 按工程配色规则离线渲染成图，用于视觉核对复刻效果。
// 用法: node _tools/render_levels.mjs <outDir> [t=8]
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
const MOD = 'C:/Users/JingSu/.workbuddy/binaries/node/workspace/node_modules/@napi-rs/canvas/index.js';
const { createCanvas } = await import(pathToFileURL(MOD).href);

const ROOT = process.cwd();
const cfg = fs.readFileSync(path.join(ROOT, 'TickHop/config.lua'), 'utf8');
const D = {};
for (const m of cfg.matchAll(/M\.DEFAULT_([A-Z_]+)\s*=\s*(-?[\d.]+)/g)) D[m[1]] = parseFloat(m[2]);
const PAL = {};
for (const m of cfg.matchAll(/^\s{4}(bg|platform|ghost|label|labelGhost|player|goal|hud|pickup|reverse|danger)\s*=\s*"([0-9A-Fa-f]{6})"/gm)) PAL[m[1]] = m[2];

const body = cfg.slice(cfg.indexOf('M.LEVELS = {'));
const levels = [];
for (const ch of body.split(/name\s*=\s*"/).slice(1)) {
  const name = ch.slice(0, ch.indexOf('"'));
  const spawn = ch.match(/spawn\s*=\s*\{x\s*=\s*(-?[\d.]+)\s*,\s*y\s*=\s*(-?[\d.]+)/);
  const goal = ch.match(/goal\s*=\s*\{x\s*=\s*(-?[\d.]+)\s*,\s*y\s*=\s*(-?[\d.]+)\s*,\s*width\s*=\s*(-?[\d.]+)\s*,\s*height\s*=\s*(-?[\d.]+)/);
  const lvPal = {};
  const palBlock = ch.slice(ch.indexOf('palette'), ch.indexOf('platforms'));
  for (const pm of palBlock.matchAll(/(\w+)\s*=\s*"([0-9A-Fa-f]{6})"/g)) lvPal[pm[1]] = pm[2];
  const pblock = ch.slice(ch.indexOf('platforms'), ch.indexOf('pickups'));
  const texts = [];
  const tblock = ch.slice(ch.indexOf('texts'), ch.indexOf('texts') + 400);
  for (const tm of tblock.matchAll(/\{x\s*=\s*(-?[\d.]+)\s*,\s*y\s*=\s*(-?[\d.]+)\s*,\s*text\s*=\s*"([^"]*)"/g)) texts.push({ x: +tm[1], y: +tm[2], text: tm[3] });
  const platforms = [];
  for (const pm of pblock.matchAll(/\{x\s*=\s*(-?[\d.]+)\s*,\s*y\s*=\s*(-?[\d.]+)\s*,\s*width\s*=\s*(-?[\d.]+)\s*,\s*height\s*=\s*(-?[\d.]+)\s*,\s*tick\s*=\s*(-?[\d.]+)\s*\}/g))
    platforms.push({ x: +pm[1], y: +pm[2], w: +pm[3], h: +pm[4], tick: +pm[5] });
  levels.push({ name, spawn: { x: +spawn[1], y: +spawn[2] }, goal: { x: +goal[1], y: +goal[2], w: +goal[3], h: +goal[4] }, platforms, texts, pal: { ...PAL, ...lvPal } });
}

const outDir = process.argv[2] || '_simulator/levels_preview';
const T = process.argv[3] ? +process.argv[3] : 8;
fs.mkdirSync(outDir, { recursive: true });
const S = 1;
const W = 800 * S, H = 600 * S;
const px = (x) => (x + 400) * S;
const py = (y) => (300 - y) * S;

for (const lv of levels) {
  const cv = createCanvas(W, H);
  const g = cv.getContext('2d');
  const P = lv.pal;
  g.fillStyle = '#' + P.bg; g.fillRect(0, 0, W, H);
  const solidOf = (p) => p.tick === -1 || p.tick === Math.floor(T);
  // 平台
  for (const p of lv.platforms) {
    const solid = solidOf(p);
    g.globalAlpha = (solid ? (D.PLATFORM_ALPHA ?? 255) : (D.PLATFORM_GHOST_ALPHA ?? 40)) / 255;
    g.fillStyle = '#' + (solid ? P.platform : P.ghost);
    g.fillRect(px(p.x - p.w / 2), py(p.y + p.h / 2), p.w * S, p.h * S);
    g.globalAlpha = 1;
  }
  // 标签（压在平台中央）
  g.textAlign = 'center'; g.textBaseline = 'middle';
  for (const p of lv.platforms) {
    if (p.tick < 0) continue;
    const solid = solidOf(p);
    const size = (D.PLATFORM_LABEL_SIZE || 26) * S;
    if (!size) continue;
    g.globalAlpha = (solid ? 255 : (D.PLATFORM_LABEL_GHOST_ALPHA ?? 130)) / 255;
    g.fillStyle = '#' + (solid ? P.label : P.labelGhost);
    g.font = `bold ${size}px monospace`;
    g.fillText(String(p.tick), px(p.x), py(p.y));
    g.globalAlpha = 1;
  }
  // 门
  g.fillStyle = '#' + P.goal;
  g.globalAlpha = (D.GOAL_ALPHA ?? 255) / 255;
  g.fillRect(px(lv.goal.x - lv.goal.w / 2), py(lv.goal.y + lv.goal.h / 2), lv.goal.w * S, lv.goal.h * S);
  g.globalAlpha = 1;
  g.fillStyle = '#' + P.bg;
  g.beginPath(); g.arc(px(lv.goal.x - lv.goal.w / 2 + lv.goal.w * 0.28), py(lv.goal.y + lv.goal.h * 0.28), 5 * S, 0, 7); g.fill();
  // 玩家
  g.fillStyle = '#' + P.player;
  const pw = (D.PLAYER_WIDTH || 34) * S, ph = (D.PLAYER_HEIGHT || 44) * S;
  g.fillRect(px(lv.spawn.x) - pw / 2, py(lv.spawn.y) - ph / 2, pw, ph);
  g.fillStyle = '#111114';
  const edx = 6 * S, edy = (D.PLAYER_HEIGHT || 44) * 0.18 * S;
  g.fillRect(px(lv.spawn.x) - edx - 2 * S, py(lv.spawn.y) - edy - 2 * S, 4 * S, 4 * S);
  g.fillRect(px(lv.spawn.x) + edx - 2 * S, py(lv.spawn.y) - edy - 2 * S, 4 * S, 4 * S);
  // 提示文本
  g.fillStyle = '#' + P.hud; g.font = `bold ${18 * S}px "Microsoft YaHei", sans-serif`;
  for (const t of lv.texts) g.fillText(t.text, px(t.x), py(t.y));
  // 标题
  g.textAlign = 'left';
  g.fillStyle = '#FFD23F'; g.font = `bold ${20 * S}px "Microsoft YaHei", sans-serif`;
  g.fillText(`${lv.name}  (渲染 t=${T})`, 12, 26);
  const f = path.join(outDir, `${lv.name}.png`);
  fs.writeFileSync(f, cv.toBuffer('image/png'));
  console.log(`${f}`);
}
