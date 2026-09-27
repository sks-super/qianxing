// 原版《滴答咔哒 / Tick Hop》截图分析器 v2
//   目标：把扁平配色截图还原成「调色板 + 横向色带（=平台）+ 文本布局图」，
//   让无法读图的模型也能核对原版的关卡布设与配色。
// 用法: node _tools/orig_analyze.mjs <img...> [--cols 120] [--thr 30] [--minrun 60]
import { pathToFileURL } from 'node:url';

const MOD = 'C:/Users/JingSu/.workbuddy/binaries/node/workspace/node_modules/@napi-rs/canvas/index.js';
const { createCanvas, loadImage } = await import(pathToFileURL(MOD).href);

const argv = process.argv.slice(2);
const files = [];
const opt = (k, d) => { const i = argv.indexOf('--' + k); return i >= 0 ? argv[i + 1] : d; };
for (let i = 0; i < argv.length; i++) {
  if (argv[i].startsWith('--')) { i++; continue; }
  files.push(argv[i]);
}
const COLS = parseInt(opt('cols', '118'), 10);
const THR = parseInt(opt('thr', '26'), 10);        // 颜色合并阈值（欧氏距离）
const MINRUN = parseInt(opt('minrun', '70'), 10);  // 视为「色带」的最小横向长度(px)
const CHARS = '@#%&*+=~-:.oO0abcXYZ';

const hex = (r, g, b) => '#' + ((r << 16) | (g << 8) | b).toString(16).padStart(6, '0');

for (const file of files) {
  const img = await loadImage(file);
  const W = img.width, H = img.height;
  const cv = createCanvas(W, H);
  const ctx = cv.getContext('2d');
  ctx.drawImage(img, 0, 0);
  const px = ctx.getImageData(0, 0, W, H).data;

  // ---------- 1) 调色板：4x 降采样取平均后再贪心合并 ----------
  const bw = Math.ceil(W / 4), bh = Math.ceil(H / 4);
  const small = new Uint8Array(bw * bh * 3);
  for (let y = 0; y < bh; y++) for (let x = 0; x < bw; x++) {
    let r = 0, g = 0, b = 0, n = 0;
    for (let dy = 0; dy < 4; dy++) for (let dx = 0; dx < 4; dx++) {
      const sx = x * 4 + dx, sy = y * 4 + dy;
      if (sx >= W || sy >= H) continue;
      const i = (sy * W + sx) * 4; r += px[i]; g += px[i + 1]; b += px[i + 2]; n++;
    }
    const o = (y * bw + x) * 3;
    small[o] = r / n | 0; small[o + 1] = g / n | 0; small[o + 2] = b / n | 0;
  }
  const pal = [];
  const hist = new Int32Array(bw * bh);
  for (let i = 0; i < bw * bh; i++) {
    const r = small[i * 3], g = small[i * 3 + 1], b = small[i * 3 + 2];
    let best = -1, bd = 1e9;
    for (let p = 0; p < pal.length; p++) {
      const d = (pal[p].r - r) ** 2 + (pal[p].g - g) ** 2 + (pal[p].b - b) ** 2;
      if (d < bd) { bd = d; best = p; }
    }
    if (best < 0 || bd > THR * THR) { pal.push({ r, g, b, n: 0 }); best = pal.length - 1; }
    hist[i] = best; pal[best].n++;
  }
  pal.sort((a, b) => b.n - a.n);
  // 重新编号（排序后 hist 索引失效，重算）
  const pal2 = pal.slice(0, 12);
  for (let i = 0; i < bw * bh; i++) {
    const r = small[i * 3], g = small[i * 3 + 1], b = small[i * 3 + 2];
    let best = 0, bd = 1e9;
    for (let p = 0; p < pal2.length; p++) {
      const d = (pal2[p].r - r) ** 2 + (pal2[p].g - g) ** 2 + (pal2[p].b - b) ** 2;
      if (d < bd) { bd = d; best = p; }
    }
    hist[i] = best;
  }

  console.log(`\n================================================================`);
  console.log(`${file.split(/[\\/]/).pop()}   ${W}x${H}`);
  console.log('--- 调色板（4x 降采样后聚类）---');
  const total = bw * bh;
  pal2.forEach((p, i) => {
    // 该色的小图包围盒
    let minX = bw, minY = bh, maxX = -1, maxY = -1;
    for (let y = 0; y < bh; y++) for (let x = 0; x < bw; x++) if (hist[y * bw + x] === i) {
      if (x < minX) minX = x; if (x > maxX) maxX = x; if (y < minY) minY = y; if (y > maxY) maxY = y;
    }
    const lum = Math.round(0.299 * p.r + 0.587 * p.g + 0.114 * p.b);
    console.log(`  ${(CHARS[i] || '?').padEnd(2)} ${hex(p.r, p.g, p.b)}  明度${String(lum).padStart(3)}  ${(p.n / total * 100).toFixed(2).padStart(6)}%  bbox4x=[${minX * 4},${minY * 4} - ${maxX * 4 + 3},${maxY * 4 + 3}]`);
  });

  // ---------- 2) 横向色带：某调色板色在一行内连续占据 >= MINRUN 的区间 ----------
  console.log('--- 横向色带（>= ' + MINRUN + 'px，按 y 排序；这是平台/地板/危险物的候选）---');
  const bands = [];
  const isColor = (x, y, p) => {
    // 原始分辨率精确判定（对 JPEG 噪声宽容：与调色板距离 < 40）
    const i = (y * W + x) * 4;
    const dr = px[i] - pal2[p].r, dg = px[i + 1] - pal2[p].g, db = px[i + 2] - pal2[p].b;
    return dr * dr + dg * dg + db * db < 40 * 40;
  };
  for (let p = 0; p < pal2.length; p++) {
    for (let y = 0; y < H; y += 2) {
      let run = 0, x0 = 0;
      for (let x = 0; x < W; x += 2) {
        if (isColor(x, y, p)) { if (run === 0) x0 = x; run += 2; }
        else {
          if (run >= MINRUN) bands.push({ p, y, x0, x1: x0 + run, len: run });
          run = 0;
        }
      }
      if (run >= MINRUN) bands.push({ p, y, x0, x1: x0 + run, len: run });
    }
  }
  // 合并相邻行的同色带 → 矩形
  bands.sort((a, b) => a.p - b.p || a.y - b.y || a.x0 - b.x0);
  const rects = [];
  for (const b of bands) {
    const hit = rects.find((r) => r.p === b.p && b.y - r.y1 <= 3
      && Math.abs(r.x0 - b.x0) < 30 && Math.abs(r.x1 - b.x1) < 30);
    if (hit) { hit.y1 = b.y; hit.x0 = Math.min(hit.x0, b.x0); hit.x1 = Math.max(hit.x1, b.x1); hit.rows++; }
    else rects.push({ p: b.p, y0: b.y, y1: b.y, x0: b.x0, x1: b.x1, rows: 1 });
  }
  rects.sort((a, b) => (b.x1 - b.x0) * (b.y1 - b.y0 + 2) - (a.x1 - a.x0) * (a.y1 - a.y0 + 2));
  const only = opt('color', '');
  let shown = rects;
  if (only) {
    const want = only.replace('#', '').toLowerCase();
    shown = rects.filter((r) => {
      const c = pal2[r.p];
      const lum = 0.299 * c.r + 0.587 * c.g + 0.114 * c.b;
      if (want === 'white') return lum >= 200;
      if (want === 'dark') return lum <= 80;
      if (want === 'mid') return lum > 80 && lum < 200;
      const h = hex(c.r, c.g, c.b).slice(1);
      return h.startsWith(want.slice(0, 4)) || want.startsWith(h.slice(0, 4));
    });
  }
  shown = shown.slice(0, 40);
  shown.forEach((r) => {
    const w = r.x1 - r.x0, h = r.y1 - r.y0 + 2;
    const c = pal2[r.p];
    console.log(`  ${(CHARS[r.p] || '?')} ${hex(c.r, c.g, c.b)}  x=${String(r.x0).padStart(4)}..${String(r.x1).padEnd(4)} y=${String(r.y0).padStart(4)}..${String(r.y1).padEnd(4)}  ${w}x${h}  中心=(${(r.x0 + r.x1) / 2 | 0},${(r.y0 + r.y1) / 2 | 0})`);
  });

  // ---------- 3) 文本布局图 ----------
  const ROWS = Math.max(1, Math.round(COLS * (H / W) / 2.1));
  const cw = W / COLS, chh = H / ROWS;
  console.log(`--- 布局图 ${COLS}x${ROWS}（格≈${cw.toFixed(0)}x${chh.toFixed(0)}px）---`);
  const out = [];
  for (let ry = 0; ry < ROWS; ry++) {
    let line = '';
    for (let rx = 0; rx < COLS; rx++) {
      const cnt = new Int32Array(pal2.length);
      for (let y = Math.floor(ry * chh); y < Math.min(H, (ry + 1) * chh); y += 3)
        for (let x = Math.floor(rx * cw); x < Math.min(W, (rx + 1) * cw); x += 3)
          cnt[hist[(y >> 2) * bw + (x >> 2)]]++;
      let best = 0;
      for (let p = 1; p < pal2.length; p++) if (cnt[p] > cnt[best]) best = p;
      line += cnt[best] ? (CHARS[best] || '?') : ' ';
    }
    out.push(line);
  }
  console.log(out.join('\n'));
}
