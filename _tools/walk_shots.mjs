// 从攻略视频缩略图里自动切分「关卡场景」，输出场景清单，
// 并把每关代表帧按原分辨率抽出来裁掉黑边，存成可直接查看的截图。
// 用法: node _tools/walk_shots.mjs <thumbDir> <video> <outDir> [--minsec 1.5] [--max 24]
import { pathToFileURL } from 'node:url';
import { spawn } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

const MOD = 'C:/Users/JingSu/.workbuddy/binaries/node/workspace/node_modules/@napi-rs/canvas/index.js';
const { createCanvas, loadImage } = await import(pathToFileURL(MOD).href);
const FF = 'C:/Users/JingSu/.workbuddy/binaries/python/envs/default/Lib/site-packages/imageio_ffmpeg/binaries/ffmpeg-win-x86_64-v7.1.exe';

const argv = process.argv.slice(2);
const pos = argv.filter((a) => !a.startsWith('--'));
const opt = (k, d) => { const i = argv.indexOf('--' + k); return i >= 0 ? argv[i + 1] : d; };
const [thumbDir, video, outDir] = pos;
const MIN_SEC = parseFloat(opt('minsec', '1.5'));
const MAXN = parseInt(opt('max', '24'), 10);
const FPS_THUMB = parseFloat(opt('fps', '2'));
const FROM = parseFloat(opt('from', '0'));
fs.mkdirSync(outDir, { recursive: true });

const files = fs.readdirSync(thumbDir).filter((f) => f.endsWith('.png'))
  .filter((f) => (parseInt(f, 10) - 1) / FPS_THUMB >= FROM).sort();
const W = 480, H = 270;
const cv = createCanvas(W, H); const ctx = cv.getContext('2d');
const scenes = [];
let prevSig = null;
for (const f of files) {
  const img = await loadImage(path.join(thumbDir, f));
  ctx.clearRect(0, 0, W, H); ctx.drawImage(img, 0, 0, W, H);
  const d = ctx.getImageData(0, 0, W, H).data;
  // 主色签名：4bit 量化取前二
  const m = new Map();
  let minX = W, minY = H, maxX = -1, maxY = -1;
  for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
    const i = (y * W + x) * 4;
    const g = (d[i] * 77 + d[i + 1] * 151 + d[i + 2] * 28) >> 8;
    if (g > 24) {                       // 非黑区域 = 游戏画面
      if (x < minX) minX = x; if (x > maxX) maxX = x;
      if (y < minY) minY = y; if (y > maxY) maxY = y;
    }
    const k = ((d[i] >> 4) << 8) | ((d[i + 1] >> 4) << 4) | (d[i + 2] >> 4);
    m.set(k, (m.get(k) || 0) + 1);
  }
  const top2 = [...m.entries()].sort((a, b) => b[1] - a[1]).slice(0, 2).map((e) => e[0]);
  const sig = top2.join('_');
  const t = (parseInt(f, 10) - 1) / FPS_THUMB;
  const bbox = maxX < 0 ? null : [minX, minY, maxX, maxY];
  if (!prevSig || sig !== prevSig) scenes.push({ sig, t0: t, t1: t, frames: [f], bbox });
  else { const s = scenes[scenes.length - 1]; s.t1 = t; s.frames.push(f); s.bbox = bbox; if (bbox) s.bbox2 = bbox; }
  prevSig = sig;
}
const use = scenes.filter((s) => s.t1 - s.t0 >= MIN_SEC);
console.log(`共 ${scenes.length} 个场景，稳定(>=${MIN_SEC}s)的 ${use.length} 个`);
console.log('--- 场景清单 ---');
use.slice(0, MAXN + 8).forEach((s, i) => {
  const mid = s.frames[Math.floor(s.frames.length / 2)];
  console.log(`  #${String(i).padStart(2)} t=${s.t0.toFixed(1)}~${s.t1.toFixed(1)}s  ${(s.t1 - s.t0).toFixed(1)}s  代表帧=${mid}  内容框=${s.bbox ? s.bbox.join(',') : 'n/a'}`);
});

// 抽取代表帧（原分辨率）并按内容框裁剪
const outList = [];
const pick = [];
for (let i = 0; i < Math.min(use.length, MAXN); i++) {
  const s = use[i];
  const mid = s.frames[Math.floor(s.frames.length / 2)];
  const t = (parseInt(mid, 10) - 1) / FPS_THUMB;
  pick.push({ i, t, sig: s.sig, dur: s.t1 - s.t0, bbox: s.bbox2 || s.bbox });
}
const VIDEO_W = 1280, VIDEO_H = 720;
const SC = VIDEO_W / W;
for (const p of pick) {
  const raw = path.join(outDir, `_raw_${p.i}.png`);
  await new Promise((res) => {
    const pr = spawn(FF, ['-hide_banner', '-loglevel', 'error', '-ss', String(p.t), '-i', video, '-frames:v', '1', '-y', raw]);
    pr.on('close', res);
  });
  if (!fs.existsSync(raw)) continue;
  const img = await loadImage(raw);
  const [x0, y0, x1, y1] = p.bbox || [0, 0, W - 1, H - 1];
  const cx = Math.max(0, Math.floor(x0 * SC) - 8), cy = Math.max(0, Math.floor(y0 * SC) - 8);
  const cw = Math.min(img.width - cx, Math.ceil((x1 - x0 + 1) * SC) + 16);
  const chh = Math.min(img.height - cy, Math.ceil((y1 - y0 + 1) * SC) + 16);
  const c2 = createCanvas(cw, chh); const g2 = c2.getContext('2d');
  g2.drawImage(img, cx, cy, cw, chh, 0, 0, cw, chh);
  const name = `L${String(p.i + 1).padStart(2, '0')}_t${p.t.toFixed(1)}s.png`;
  fs.writeFileSync(path.join(outDir, name), c2.toBuffer('image/png'));
  fs.unlinkSync(raw);
  outList.push({ name, t: p.t, dur: p.dur, sig: p.sig, crop: [cx, cy, cw, chh] });
}
console.log('--- 已导出截图 ---');
outList.forEach((o) => console.log(`  ${o.name}  t=${o.t}s  持续=${o.dur.toFixed(1)}s  裁剪=${o.crop.join('x')}`));
