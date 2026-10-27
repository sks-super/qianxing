// 第 45 批 · 把「超限素材组」导出的线稿角色脚本 → heroPrims.lua（图元笔触）
//   用法：node _tools/gen_hero_lineart_prims.mjs [out.lua]
//   源：C:/Users/lenovo/Downloads/0X_<视角>_像素6x6*.lua（旋转椭圆，画布宽高在 ROOT 里）
//       配套的「像素数据」文本用来求**纸面填充**（见下）。
//
//   ★ 与 _tmp/gen_hero_prims.mjs 的区别：那份是给**彩色立绘**用的，会剔「白雾 / 灰棕底衬 /
//     纯白噪点」并把 alpha ×2.2 补偿。线稿素材的每个图元都是**中性灰**（sat = 0），
//     那些判据会把整张画当成底衬剔掉 —— 所以这里一律不筛，只按「太小 / 太透明」裁。
//   ★ 也不做「脸部提权」：线稿的层次是靠 alpha 叠出来的，重排顺序会改变明暗。
//   ★ 四个视角**各自独立**找源文件：能找到就用，找不到就在文件末尾写成别名
//     （M.W = M.S 之类），level.heroPrData 也会兜底。所以第一批只导出正面也不崩。
//     补上 02/03/04 的同格式导出后，直接重跑本脚本即可补齐，不用改代码。
import fs from 'node:fs'
import path from 'node:path'

const DL = 'C:/Users/lenovo/Downloads'
const PIX_DIR = 'C:/Users/lenovo/WorkBuddy/2026-10-21-21-32-48/generated-images/lineart/pixel6/extracted'
const OUT = process.argv[2] || '浮岛借木/heroPrims.lua'

// 人物高 = 1.15 格（和旧的图元数据一致：脚底对齐 y=0，头顶多出 0.15 格）
const TARGET_H = 1.15
const MIN_SIZE = 0.010      // 缩到 1.15 格后 max(w,h) < 0.01 格（≈1px）→ 看不见，丢
const MIN_ALPHA = 20
// ★ 线稿的每个图元都是「半透明墨」叠出来的（alpha 100~210）。直接照搬在白底地图上
//   会淡成一片灰（白纸透出来）—— 这里把 alpha 抬 1.45 倍压到接近实墨，
//   小人才是「白纸上的黑线」而不是「灰雾」。
const ALPHA_GAIN = 1.45
const INK_MAX = 0x28        // 颜色比这个还深的直接定格（线稿本来就是近黑）

const JOINTS = {
  back: [0, 0.5],
  head: [0, 0.6],
  torso: [0, 0.4],
  armL: [-0.165, 0.585],
  armR: [0.165, 0.585],
  legL: [-0.07, 0.255],
  legR: [0.07, 0.255],
}
const ORDER = ['back', 'head', 'torso', 'armL', 'armR', 'legL', 'legR']

// 视角 → 素材前缀（S 正面 / W 背面 / A 朝左 / D 朝右，与 level.heroVision 一致）
const VIEWS = [
  { key: 'S', stem: '01_正面', label: '正面' },
  { key: 'W', stem: '02_背面', label: '背面' },
  { key: 'A', stem: '03_侧面朝左', label: '侧面朝左' },
  { key: 'D', stem: '04_侧面朝右', label: '侧面朝右' },
]
const PAPER_COLS = 20

// ---- 在下载目录里找 `0X_xxx_像素6x6*.lua`（多个时取 mtime 最新的）----
function findSource(stem) {
  const hits = fs.readdirSync(DL)
    .filter((f) => f.startsWith(stem + '_像素6x6') && f.endsWith('.lua'))
    .map((f) => path.join(DL, f))
    .map((p) => ({ p, t: fs.statSync(p).mtimeMs }))
    .sort((a, b) => b.t - a.t)
  return hits.length ? hits[0].p : null
}

function findPixTxt(stem) {
  const p = path.join(PIX_DIR, stem + '_像素数据.txt')
  return fs.existsSync(p) ? p : null
}

// ---- 解析「超限素材组」18 字段：asset,x,y,w,h,pivot…,scale…,rotZ,r,g,b,a ----
function parseElements(src) {
  const rootM = /local ROOT = \{\s*([\d.]+),\s*([\d.]+),\s*([\d.]+),\s*([\d.]+)/.exec(src)
  const CW = rootM ? +rootM[3] : 1020
  const CH = rootM ? +rootM[4] : 1530
  const E = []
  // 逐行取 `{...}`，按逗号拆：asset, x, y, w, h, 6 个 pivot/anchor, 2 个 scale, rotZ, r, g, b, a
  for (const m of src.matchAll(/\{([-\d.,\s]+)\}/g)) {
    const f = m[1].split(',').map((v) => v.trim()).filter((v) => v.length)
    if (f.length < 18) continue
    E.push({
      cx: +f[1], cy: +f[2], w: Math.abs(+f[3]), h: Math.abs(+f[4]),
      rot: +f[13], rgb: [+f[14], +f[15], +f[16]], a: +f[17],
    })
  }
  return { E, CW, CH }
}

// ---- 纸面：读「像素数据」文本 → 内部掩码 ----
function loadMask(file) {
  const rows = fs.readFileSync(file, 'utf8').split(/\r?\n/).filter((l) => l.length > 0)
  const h = rows.length, w = rows[0].length
  const m = new Uint8Array(w * h)
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) if (rows[y][x] === '#') m[y * w + x] = 1
  return { w, h, m }
}

// 膨胀 → 洪水填充求外部 → 腐蚀 → 内部（手绘线稿有断口，见 make_hero_lineart.mjs）
function interiorOf({ w, h, m }) {
  const R = 3
  const dil = new Uint8Array(w * h)
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    if (!m[y * w + x]) continue
    for (let dy = -R; dy <= R; dy++) for (let dx = -R; dx <= R; dx++) {
      const yy = y + dy, xx = x + dx
      if (yy >= 0 && yy < h && xx >= 0 && xx < w) dil[yy * w + xx] = 1
    }
  }
  const out = new Uint8Array(w * h)
  const st = []
  const push = (x, y) => {
    if (x < 0 || y < 0 || x >= w || y >= h) return
    const i = y * w + x
    if (out[i] || dil[i]) return
    out[i] = 1; st.push(i)
  }
  for (let x = 0; x < w; x++) { push(x, 0); push(x, h - 1) }
  for (let y = 0; y < h; y++) { push(0, y); push(w - 1, y) }
  while (st.length) {
    const i = st.pop(), x = i % w, y = (i - x) / w
    push(x - 1, y); push(x + 1, y); push(x, y - 1); push(x, y + 1)
  }
  const inside = new Uint8Array(w * h)
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    if (out[y * w + x]) continue
    let keep = 1
    for (let dy = -R; dy <= R && keep; dy++) for (let dx = -R; dx <= R; dx++) {
      const yy = y + dy, xx = x + dx
      if (yy < 0 || yy >= h || xx < 0 || xx >= w) continue
      if (out[yy * w + xx]) { keep = 0; break }
    }
    if (keep) inside[y * w + x] = 1
  }
  for (let i = 0; i < w * h; i++) if (m[i]) inside[i] = 1
  return inside
}

/** 一个视角 → { parts, n, dropped, total, CW, CH } */
function buildView(luaFile, pixFile) {
  const src = fs.readFileSync(luaFile, 'utf8')
  const { E, CW, CH } = parseElements(src)
  if (!E.length) throw new Error(`${path.basename(luaFile)}：没解析出任何图元，检查导出格式`)

  // ---- 真实包围盒：按**旋转后的外接矩形**求（只按中心点求会把人裁掉一圈）----
  let x0 = 1e9, x1 = -1e9, y0 = 1e9, y1 = -1e9
  for (const e of E) {
    const rad = e.rot * Math.PI / 180
    const cs = Math.abs(Math.cos(rad)), sn = Math.abs(Math.sin(rad))
    const hw = (e.w * cs + e.h * sn) / 2, hh = (e.w * sn + e.h * cs) / 2
    x0 = Math.min(x0, e.cx - hw); x1 = Math.max(x1, e.cx + hw)
    y0 = Math.min(y0, e.cy - hh); y1 = Math.max(y1, e.cy + hh)
  }
  const scale = TARGET_H / Math.max(1e-6, y1 - y0)
  const xc = (x0 + x1) / 2

  const parts = { back: [], head: [], torso: [], armL: [], armR: [], legL: [], legR: [] }
  let dropped = 0
  for (const e of E) {
    if (e.a < MIN_ALPHA) { dropped++; continue }
    const w = e.w * scale, h = e.h * scale
    if (Math.max(w, h) < MIN_SIZE) { dropped++; continue }
    const clamp = (v) => Math.max(0, Math.min(255, Math.round(v)))
    parts.torso.push({
      x: (e.cx - xc) * scale,
      y: (e.cy - y0) * scale,          // y 向上：脚底 = 0
      w, h, rot: e.rot,
      rgb: e.rgb.map((v) => Math.min(v, INK_MAX)),
      a: clamp(e.a * ALPHA_GAIN),
    })
  }

  // ---- 纸面（白色底衬）：导出的图元全是墨、没有身体填充 ----
  //   ★ 不铺纸面的话，地图上的格线会从角色身体里透出来（白纸地图上非常明显）。
  if (pixFile && fs.existsSync(pixFile)) {
    const mk = loadMask(pixFile)
    const ins = interiorOf(mk)
    let bx0 = 1e9, by0 = 1e9, bx1 = -1e9, by1 = -1e9
    for (let y = 0; y < mk.h; y++) for (let x = 0; x < mk.w; x++) {
      if (!ins[y * mk.w + x]) continue
      if (x < bx0) bx0 = x
      if (x > bx1) bx1 = x
      if (y < by0) by0 = y
      if (y > by1) by1 = y
    }
    const bw = bx1 - bx0 + 1, bh = by1 - by0 + 1
    const rowsN = Math.max(1, Math.round(PAPER_COLS * bh / bw))
    const cw = bw / PAPER_COLS, ch = bh / rowsN
    // 图元坐标系：x 以中线为 0、y 以脚底为 0，人物高 TARGET_H
    const toX = (mx) => ((mx - (bx0 + bx1) / 2) / bw) * (TARGET_H * bw / bh)
    const toY = (my) => (1 - (my - by0) / bh) * TARGET_H
    const cwN = (cw / bw) * (TARGET_H * bw / bh)
    const chN = (ch / bh) * TARGET_H
    for (let gy = 0; gy < rowsN; gy++) {
      for (let gx = 0; gx < PAPER_COLS; gx++) {
        let hit = 0
        for (const [fx, fy] of [[0.5, 0.5], [0.3, 0.3], [0.7, 0.3], [0.3, 0.7], [0.7, 0.7]]) {
          const mx = Math.min(mk.w - 1, Math.floor(bx0 + (gx + fx) * cw))
          const my = Math.min(mk.h - 1, Math.floor(by0 + (gy + fy) * ch))
          if (ins[my * mk.w + mx]) hit++
        }
        if (hit < 3) continue
        parts.back.push({
          x: toX(bx0 + (gx + 0.5) * cw),
          y: toY(by0 + (gy + 0.5) * ch),
          w: cwN * 1.25, h: chN * 1.25, rot: 0,
          rgb: [255, 255, 255], a: 255,
        })
      }
    }
  }
  return { parts, n: parts.torso.length, dropped, total: E.length, CW, CH, bw: x1 - x0, bh: y1 - y0 }
}

/** 数字输出：保留 4 位小数并去掉多余的 0（文件能小一半） */
function fmt(v) {
  let s = v.toFixed(4)
  if (s === '-0.0000') s = '0.0000'
  return s.replace(/0+$/, '').replace(/\.$/, '')
}

function emitViewBody(parts) {
  let out = ''
  for (const name of ORDER) {
    const arr = parts[name]
    const j = JOINTS[name]
    if (!arr.length) {
      out += `    -- ${name}: 0 个, 关节(${j[0]}, ${j[1]})\n    {${j[0]}, ${j[1]}, 0},\n`
      continue
    }
    const cells = arr.map((e) => [
      fmt(e.x - j[0]), fmt(e.y - j[1]), fmt(e.w), fmt(e.h), fmt(e.rot),
      '0x' + e.rgb.map((v) => Math.round(v).toString(16).padStart(2, '0')).join('').toUpperCase(),
      String(Math.round(e.a)),
    ].join(','))
    let buf = `    {${j[0]}, ${j[1]}, ${arr.length},`
    const perLine = 3
    for (let i = 0; i < cells.length; i++) {
      const sep = i === 0 ? '' : (i % perLine === 0 ? ',\n     ' : ',')
      buf += sep + cells[i]
    }
    buf += `},   -- ${name}`
    out += buf + '\n'
  }
  return out
}

// ---- 主流程 ----
const built = []          // [{ key, label, data }]
for (const v of VIEWS) {
  const lua = findSource(v.stem)
  if (!lua) { console.log(`· ${v.key}(${v.label})：没有 ${v.stem}_像素6x6*.lua → 回退正面`); continue }
  const pix = findPixTxt(v.stem)
  const d = buildView(lua, pix)
  console.log(`· ${v.key}(${v.label})：${path.basename(lua)} → ${d.total} 图元 / 保留 ${d.n} 笔 · 纸面 ${d.parts.back.length} 格（丢 ${d.dropped}）`)
  built.push({ key: v.key, label: v.label, file: path.basename(lua), data: d })
}
if (!built.length) throw new Error('一个视角都没找到，检查下载目录')

const primary = built.find((b) => b.key === 'S') || built[0]
const aliasOf = (key) => built.find((b) => b.key === key)

let out = `-- =================================================================
-- heroPrims.lua —— 操控小人的「图元笔触」数据（第 45 批：线稿像素小人）
--
-- 来源：用户导出的「超限素材组」脚本（旋转椭圆图元，画布宽高见各视角注释）
`
for (const b of built) {
  out += `--   ${b.key}（${b.label}） ← ${b.file}：${b.data.total} 图元 / 保留 ${b.data.n} 笔 + 纸面 ${b.data.parts.back.length} 格\n`
}
out += `--
--   ★ 这批导出是**线稿**（每个图元都是中性灰、靠 alpha 叠出深浅），所以：
--     · 不剔「白雾 / 灰棕底衬」—— 线稿的 sat 恒为 0，那套判据会把整张画剔光；
--     · 不做 alpha ×2.2 补偿 —— 线稿本身就是半透明叠出来的，抬高会糊成黑块；
--     · 不重排「脸部元素」 —— 层次全靠 alpha 叠加，顺序一改明暗就变。
--   ★ 归一化：真实包围盒（含旋转外接矩形）→ 人物高 ${TARGET_H} 格、脚底 y=0、中线 x=0。
--   ★ 缺的视角在文件末尾写成别名（M.xx = M.S 之类），level.heroPrData 也会兜底。
--     补上 0X_<视角>_像素6x6*.lua 之后重跑 _tools/gen_hero_lineart_prims.mjs 即可。
--
-- 每个视角 = 7 个部件，顺序固定（与 level.lua 的 PR_DRAW_ORDER 对应）：
--   1 back（纸面填充） / 2 head / 3 torso / 4 armL / 5 armR / 6 legL / 7 legR
-- 每个部件：{ pivotX, pivotY, n, then n × {x, y, w, h, rot, rgb, alpha} }
--   x,y : 椭圆中心，**已换算成相对关节**的偏移（单位「格」）
--   w,h : 椭圆宽高（格）；rot 度；rgb 0xRRGGBB；alpha 0-255
--
-- ★ 墨笔全部放在 torso 部件里（导出的整张画是**平的**，没有可动的关节）：
--   拆到四肢再摆臂迈腿会把线稿撕开（第 39 批「飘带」踩过同一个坑）。
--   走路的整幅起伏 / 转身压扁都在根容器上，不受影响。
--   back 只装纸面（白色底衬），不装墨 —— 否则纸面会盖住线。
-- ⚠️ 不要手改数值；换素材请重新导出后重跑 _tools/gen_hero_lineart_prims.mjs。
-- =================================================================

local M = {}

M.PARTS = { "head", "torso", "armL", "armR", "legL", "legR" }

`

for (const b of built) {
  out += `M.${b.key} = {\n` + emitViewBody(b.data.parts) + `}\n\n`
}
out += `-- ★ 缺的视角一律回退到正面（level.heroPrData 也会兜底，这里写全只是为了自检好读）\n`
for (const v of VIEWS) {
  if (aliasOf(v.key)) continue
  out += `M.${v.key} = M.${primary.key}\n`
}
out += `\nreturn M\n`

fs.writeFileSync(OUT, out)
console.log(`写出 ${OUT}（${(fs.statSync(OUT).size / 1024).toFixed(1)} KB）；实有视角 ${built.map((b) => b.key).join('/')}`)
