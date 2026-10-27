// 第 45 批 · 把四张「线稿像素」**像素数据**转成 heroArt.lua（纯色矩形像素画）
//   用法：node _tools/make_hero_lineart.mjs [COLS] [ROWS] [out.lua] [preview.png]
//   源：…/lineart/pixel6/extracted/0X_xxx_像素数据.txt（170×255，一行一排、`#` = 墨、`.` = 底）
//   输出格式与老 heroArt.lua 完全一致：{ x, y, w, h, 颜色索引 }，左上原点、y 向下。
//   ★ 为什么不是直接引用 PNG：千星脚本没有「画一张图」的接口，
//     图片控件要图库 ID，而且会丢掉像素风。像素画 = 几百块纯色矩形，最稳。
import fs from 'node:fs'
import { pathToFileURL } from 'node:url'

const MOD = 'C:/Users/lenovo/.workbuddy/binaries/node/workspace/node_modules/@napi-rs/canvas/index.js'
const { createCanvas, loadImage } = await import(pathToFileURL(MOD).href)

const COLS = Number(process.argv[2] || 40)
const ROWS = Number(process.argv[3] || 60)
const OUT = process.argv[4] || '浮岛借木/heroArt.lua'
const PREVIEW = process.argv[5] || '_tmp/b45_hero_preview.png'

const DIR = 'C:/Users/lenovo/WorkBuddy/2026-10-21-21-32-48/generated-images/lineart/pixel6/extracted/'
// ★ 用**逐像素的文本数据**（`#` = 墨 / `.` = 底），不再去采样 PNG：
//   PNG 版（`_1x`）是白底不透明的，按 alpha 取覆盖率会把整块画布当成纸面 → 一张白卡片；
//   透明版虽然能取到轮廓，但内部是镂空的，还得靠形态学补。文本数据是**逐像素精确**的，
//   采样时一格里有多少墨就是多少，没有任何抗锯齿干扰。
const SRC = [
  ['S', '01_正面_像素数据.txt', '正面'],
  ['W', '02_背面_像素数据.txt', '背面'],
  ['A', '03_侧面朝左_像素数据.txt', '侧面朝左'],
  ['D', '04_侧面朝右_像素数据.txt', '侧面朝右'],
]

// 5 档灰：0 = 墨线，4 = 纸白
const GRAYS = [0x16, 0x16, 0x6E, 0x6E, 0xFF]
const hex = n => n.toString(16).padStart(2, '0')
const COLORS = GRAYS.map(v => `${hex(v)}${hex(v)}${hex(v)}`)

// 求「人物内部」的掩码（= 纸面）
//   ★ 源图的纸面是**透明**的，只有墨线不透明。而这是手绘线稿，线条有断口，
//     直接对透明像素做洪水填充会从断口漏进去 → 内部一个都填不到（小人变「空心线人」）。
//   做法：先**膨胀**墨线把断口堵上（R=3 源像素），再洪水填充求外部，最后**腐蚀**回来。
function fillInside(w, h, srcMask) {
  const R = 3
  const ink = srcMask
  const dil = new Uint8Array(w * h)
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      if (!ink[y * w + x]) continue
      for (let dy = -R; dy <= R; dy++) {
        const yy = y + dy
        if (yy < 0 || yy >= h) continue
        for (let dx = -R; dx <= R; dx++) {
          const xx = x + dx
          if (xx < 0 || xx >= w) continue
          dil[yy * w + xx] = 1
        }
      }
    }
  }
  const outside = new Uint8Array(w * h)
  const stack = []
  const push = (x, y) => {
    if (x < 0 || y < 0 || x >= w || y >= h) return
    const i = y * w + x
    if (outside[i] || dil[i]) return
    outside[i] = 1
    stack.push(i)
  }
  for (let x = 0; x < w; x++) { push(x, 0); push(x, h - 1) }
  for (let y = 0; y < h; y++) { push(0, y); push(w - 1, y) }
  while (stack.length) {
    const i = stack.pop()
    const x = i % w, y = (i - x) / w
    push(x - 1, y); push(x + 1, y); push(x, y - 1); push(x, y + 1)
  }
  // 腐蚀：把膨胀时吃掉的边还回去，恢复真正的剪影
  const inside = new Uint8Array(w * h)
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      if (outside[y * w + x]) continue
      let keep = 1
      for (let dy = -R; dy <= R && keep; dy++) {
        const yy = y + dy
        if (yy < 0 || yy >= h) continue
        for (let dx = -R; dx <= R; dx++) {
          const xx = x + dx
          if (xx < 0 || xx >= w) continue
          if (outside[yy * w + xx]) { keep = 0; break }
        }
      }
      if (keep) inside[y * w + x] = 1
    }
  }
  // 墨线本身也算「实心」
  for (let i = 0; i < w * h; i++) if (ink[i]) inside[i] = 1
  return inside
}

const SPRITES = {}
const stats = {}

// ① 读四份「像素数据」文本（170×255，`#` = 墨 / `.` = 底），求**并集**边界。
//    四视角必须共用同一个框，否则换朝向时脚底 / 头会跳（第 26 批换素材踩过）。
const IMGS = []
let BX0 = 1e9, BY0 = 1e9, BX1 = -1e9, BY1 = -1e9
for (const [key, file, label] of SRC) {
  const rows = fs.readFileSync(DIR + file, 'utf8').split(/\r?\n/).filter(l => l.length > 0)
  const h = rows.length
  const w = rows[0].length
  const mask = new Uint8Array(w * h)
  for (let y = 0; y < h; y++) {
    const line = rows[y]
    if (line.length !== w) throw new Error(`${file} 第 ${y + 1} 行长度 ${line.length}，应为 ${w}`)
    for (let x = 0; x < w; x++) {
      if (line[x] === '#') {
        mask[y * w + x] = 1
        if (x < BX0) BX0 = x
        if (x > BX1) BX1 = x
        if (y < BY0) BY0 = y
        if (y > BY1) BY1 = y
      } else if (line[x] !== '.') {
        throw new Error(`${file} 出现未知字符 ${JSON.stringify(line[x])}`)
      }
    }
  }
  const inside = fillInside(w, h, mask)
  IMGS.push({ key, label, w, h, mask, inside })
}
const BW = BX1 - BX0 + 1, BH = BY1 - BY0 + 1
console.log(`并集边界 ${BX0},${BY0} → ${BX1},${BY1}（${BW}×${BH}） 网格 ${COLS}×${ROWS}`)

for (const { key, label, w, h, mask, inside } of IMGS) {

  const grid = []          // grid[y][x] = 颜色索引 或 -1（空）
  const cw = BW / COLS, ch = BH / ROWS
  for (let gy = 0; gy < ROWS; gy++) {
    const row = []
    for (let gx = 0; gx < COLS; gx++) {
      // 4×4 子采样：这一格里「墨 / 内部纸面 / 外部」各占多少
      //   ★ 不能只看平均色：2px 的线摊到一整格里会被稀释成浅灰，量化后轮廓就没了。
      let n = 0, ink = 0, paper = 0
      for (let sy = 0; sy < 4; sy++) {
        for (let sx = 0; sx < 4; sx++) {
          const x = Math.min(w - 1, Math.max(0, Math.floor(BX0 + gx * cw + (sx + 0.5) * cw / 4)))
          const y = Math.min(h - 1, Math.max(0, Math.floor(BY0 + gy * ch + (sy + 0.5) * ch / 4)))
          const i = y * w + x
          if (mask[i]) ink++          // 逐像素数据：`#` 就是墨，没有任何抗锯齿干扰
          else if (inside[i]) paper++
          n++
        }
      }
      const solid = (ink + paper) / n
      if (solid < 0.30) { row.push(-1); continue }   // 大半是背景 → 不画
      // ★ 用「这一格的平均调子」定灰阶，而不是「有多少墨就压多黑」：
      //   线稿是密密麻麻的细线，一格里有 40% 墨时原图在 111px 下看起来是中灰，
      //   按阈值直接判黑会整片糊成墨块（对比图里一眼能看出差多少）。
      // ★ 1-bit：像素数据本来就只有「墨 / 纸」两种，中间调只会让 111px 的小人显脏。
      //   一格 2.9px、线宽 2px：斜线约有 1/3 格是墨 → 阈值 0.18 能把连续笔触留住。
      const inkF = ink / n
      if (inkF > 0.42) row.push(0)                    // 实墨（密排的排线 / 粗轮廓）
      else if (inkF > 0.10) row.push(2)               // 中灰（单根细线）
      else row.push(4)                                // 纸
    }
    grid.push(row)
  }

  // ①-a 去噪：8 邻域里一个墨点都没有的孤立刻 = 笔触上的小毛刺，
  //    1 格 ≈ 1.3px 的时候它们只会让小人看起来「脏」，直接抹成纸面。
  for (let pass = 0; pass < 2; pass++) {
    const kill = []
    for (let y = 0; y < ROWS; y++) {
      for (let x = 0; x < COLS; x++) {
        if (grid[y][x] < 0 || grid[y][x] > 1) continue
        let nb = 0
        for (let dy = -1; dy <= 1; dy++) {
          for (let dx = -1; dx <= 1; dx++) {
            if (!dx && !dy) continue
            const v = grid[y + dy]?.[x + dx]
            if (v !== undefined && v >= 0 && v <= 1) nb++
          }
        }
        if (nb === 0) kill.push([x, y])
      }
    }
    for (const [x, y] of kill) grid[y][x] = 2
  }

  // ①-b 轮廓强化：贴着背景的格子（4 邻域里有空格）且不是纯纸 → 压成墨。
  //     源图的墨线正好压在剪影边上，被 5:1 采样稀释后常常只剩中灰，
  //     少了这一圈，小人在草地上就是「白纸剪影」，看不出是线稿。
  for (let y = 0; y < ROWS; y++) {
    for (let x = 0; x < COLS; x++) {
      if (grid[y][x] < 0 || grid[y][x] === 4) continue
      const near =
        (grid[y - 1]?.[x] ?? -1) < 0 || (grid[y + 1]?.[x] ?? -1) < 0 ||
        (grid[y]?.[x - 1] ?? -1) < 0 || (grid[y]?.[x + 1] ?? -1) < 0
      if (near) grid[y][x] = 0
    }
  }

  // ① 横向合并同色连续格
  const rowsOut = []
  for (let y = 0; y < ROWS; y++) {
    const runs = []
    let x = 0
    while (x < COLS) {
      const v = grid[y][x]
      if (v < 0) { x++; continue }
      let e = x + 1
      while (e < COLS && grid[y][e] === v) e++
      runs.push({ x, w: e - x, c: v })
      x = e
    }
    rowsOut.push(runs)
  }
  // ② 纵向合并：上下两行 x/w/颜色完全一样的块并成一块
  const blocks = []
  const live = rowsOut.map(r => r.map(o => ({ ...o, h: 1, dead: false })))
  for (let y = 0; y < ROWS; y++) {
    for (const o of live[y]) {
      if (o.dead) continue
      let yy = y
      while (yy + 1 < ROWS) {
        const nxt = live[yy + 1].find(q => !q.dead && q.x === o.x && q.w === o.w && q.c === o.c)
        if (!nxt) break
        nxt.dead = true
        o.h++
        yy++
      }
      blocks.push({ x: o.x, y, w: o.w, h: o.h, c: o.c })
    }
  }
  SPRITES[key] = blocks
  stats[key] = { label, blocks: blocks.length, ink: blocks.filter(b => b.c <= 1).length }
  console.log(`${key} ${label}：${blocks.length} 块（其中墨色 ${stats[key].ink} 块）`)
}

// 预览图（把四张并排画出来，看有没有画歪 / 糊成一片）
{
  const Z = 3
  const pw = COLS * Z, ph = ROWS * Z
  const c = createCanvas(pw * 4 + 3 * 12, ph + 8)
  const ctx = c.getContext('2d')
  ctx.fillStyle = '#6DB03C'; ctx.fillRect(0, 0, c.width, c.height)   // 用草地绿当背景，模拟游戏里
  SRC.forEach(([key], k) => {
    const ox = k * (pw + 12)
    for (const b of SPRITES[key]) {
      ctx.fillStyle = '#' + COLORS[b.c]
      ctx.fillRect(ox + b.x * Z, 4 + b.y * Z, b.w * Z, b.h * Z)
    }
  })
  fs.writeFileSync(PREVIEW, c.toBuffer('image/png'))
  console.log(`预览：${PREVIEW}（每格 ${Z}px，背景用草地绿）`)
}

// 写 Lua
const lines = []
lines.push('-- ================================================================')
lines.push('-- 浮岛借木 · 小人的「线稿像素画」数据（第 45 批，由 _tools/make_hero_lineart.mjs 生成，别手改）')
lines.push('--')
lines.push('-- 源：四张「线稿 · 像素 6×6」PNG（正面 / 背面 / 侧面朝左 / 侧面朝右，170×255）')
lines.push(`-- 网格：${COLS} × ${ROWS}（每格 ≈ ${(170 / COLS).toFixed(2)} 源像素），对齐后正好 1 格高`)
lines.push('--')
lines.push('-- ★ 为什么是「灰度 5 档」而不是原色：源图就是黑白线稿（墨线 + 纸白），')
lines.push('--   取色不看平均色、而是数「这一格里有多少墨」：实心墨 #111 / 主线 #555 /')
lines.push('--   细线 #9E / 亮灰 #D8 / 纸白 #FFF。平均色会把 2px 的线稀释成浅灰 → 轮廓消失。')
lines.push('-- ★ 贴着背景的一圈格子强制压成墨（源图的墨线正好压在剪影边上），')
lines.push('--   少了这一圈，小人在草地上就是「白纸剪影」，看不出是线稿。')
lines.push('-- ★ 覆盖率 < 30% 的格子直接不画（背景），剩下的白格是角色的「纸面」，必须画 ——')
lines.push('--   不然草地会从角色身体里透出来。')
lines.push('--')
lines.push('-- RECT 项 = { x, y, w, h, c }：左上角格坐标 + 宽高（格）+ 调色板索引；y 从上往下。')
lines.push('-- ================================================================')
lines.push('')
lines.push('local M = {}')
lines.push('')
lines.push(`M.COLS = ${COLS}`)
lines.push(`M.ROWS = ${ROWS}`)
lines.push('')
lines.push('-- 调色板（0 = 最深的墨线，4 = 纸白）')
lines.push('M.COLORS = {')
COLORS.forEach((c, i) => lines.push(`    "${c}",   -- ${i}`))
lines.push('}')
lines.push('')
lines.push('M.SPRITES = {')
for (const [key, , label] of SRC) {
  const bs = SPRITES[key]
  lines.push(`    ${key} = {   -- ${label}，${bs.length} 块`)
  let buf = '       '
  for (const b of bs) {
    const item = ` {${b.x},${b.y},${b.w},${b.h},${b.c}},`
    if (buf.length + item.length > 110) { lines.push(buf); buf = '       ' }
    buf += item
  }
  if (buf.trim()) lines.push(buf)
  lines.push('    },')
}
lines.push('}')
lines.push('')
lines.push('return M')
lines.push('')
fs.writeFileSync(OUT, lines.join('\n'), 'utf8')
console.log(`写出 ${OUT}（${(fs.statSync(OUT).size / 1024).toFixed(1)} KB）`)
