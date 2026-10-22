// ================================================================
// _verify_levels.mjs —— 果园 50 关的独立交叉校验
// ================================================================
// 用另一套实现（JS，和 _gen_levels.py 完全独立）复算 config.lua 的 M.LEVELS：
//   ① 每关 flips 下标合法（0..29）、无重复、个数 == steps
//   ② 按 flips 反推的初始盘面非空
//   ③ 该盘面的唯一解 == flips（5×6 满秩 ⇒ 解唯一且最优）
//   ④ 50 个盘面两两不同；steps 单调不减
//   ⑤ 前 5 关必须是教程关（带 tip），且 1..4 关的解与教学卡示意图一致
//
// 用法：node _verify_levels.mjs
// ================================================================

import { readFileSync } from 'node:fs';
import process from 'node:process';

const ROWS = 5, COLS = 6, N = ROWS * COLS;
const src = readFileSync('config.lua', 'utf8');

// ---------- 独立实现：棋盘模型 ----------
const PRESS = [];
for (let r = 0; r < ROWS; r++) {
    for (let c = 0; c < COLS; c++) {
        let m = 1 << (r * COLS + c);
        for (const [dr, dc] of [[-1, 0], [1, 0], [0, -1], [0, 1]]) {
            const nr = r + dr, nc = c + dc;
            if (nr >= 0 && nr < ROWS && nc >= 0 && nc < COLS) m |= 1 << (nr * COLS + nc);
        }
        PRESS.push(m);
    }
}
const bit = (i) => 1 << i;
const popcount = (m) => { let n = 0; while (m) { m &= m - 1; n++; } return n; };
const bitsOf = (m) => { const o = []; for (let i = 0; i < N; i++) if (m & bit(i)) o.push(i); return o; };
const boardOf = (flips) => flips.reduce((b, i) => b ^ PRESS[i], 0);

// GF(2) 高斯消元：返回 null（无解）或 { free, solution }
function solveBoard(board) {
    const rows = [];
    for (let i = 0; i < N; i++) rows.push({ mask: PRESS[i], rhs: (board >> i) & 1 });
    const pivot = new Array(N).fill(-1);
    let pr = 0;
    for (let col = 0; col < N && pr < N; col++) {
        let sel = -1;
        for (let i = pr; i < N; i++) if (rows[i].mask & bit(col)) { sel = i; break; }
        if (sel < 0) continue;
        [rows[pr], rows[sel]] = [rows[sel], rows[pr]];
        for (let i = 0; i < N; i++) {
            if (i !== pr && (rows[i].mask & bit(col))) {
                rows[i].mask ^= rows[pr].mask;
                rows[i].rhs ^= rows[pr].rhs;
            }
        }
        pivot[col] = pr++;
    }
    for (let i = pr; i < N; i++) if (rows[i].mask === 0 && rows[i].rhs === 1) return null;
    const free = pivot.filter((p) => p < 0).length;
    const solution = new Array(N).fill(0);
    for (let col = N - 1; col >= 0; col--) {
        const p = pivot[col];
        if (p < 0) continue;
        let v = rows[p].rhs;
        let m = rows[p].mask & ~bit(col);
        while (m) {
            const b = m & -m;
            const j = Math.log2(b) | 0;
            v ^= solution[j];
            m ^= b;
        }
        solution[col] = v;
    }
    return { free, solution };
}

// ---------- 解析 config.lua ----------
const block = src.split('-- >>> LEVELS_BEGIN')[1]?.split('-- <<< LEVELS_END')[0] ?? '';
const levels = [];
const re = /name\s*=\s*"([^"]+)"[\s\S]*?steps\s*=\s*(\d+)\s*,[\s\S]*?(?:tip\s*=\s*"([^"]*)"\s*,[\s\S]*?)?flips\s*=\s*\{([^}]*)\}/g;
let m;
while ((m = re.exec(block)) !== null) {
    levels.push({
        name: m[1],
        steps: Number(m[2]),
        tip: m[3] || '',
        flips: m[4].split(',').map((s) => Number(s.trim())).filter((v) => Number.isFinite(v)),
    });
}

const problems = [];
const boards = new Map();
let prevSteps = 0;

if (levels.length !== 50) problems.push(`关卡数 = ${levels.length}，应为 50`);

levels.forEach((lv, i) => {
    const n = i + 1;
    if (lv.flips.length !== lv.steps) problems.push(`第${n}片：steps=${lv.steps} 但 flips 有 ${lv.flips.length} 个`);
    if (new Set(lv.flips).size !== lv.flips.length) problems.push(`第${n}片：flips 有重复点位`);
    for (const f of lv.flips) {
        if (!Number.isInteger(f) || f < 0 || f >= N) problems.push(`第${n}片：非法下标 ${f}`);
    }
    const board = boardOf(lv.flips);
    if (board === 0) problems.push(`第${n}片：盘面为空（等于不用玩）`);
    if (boards.has(board)) problems.push(`第${n}片：盘面与第${boards.get(board)}片重复`);
    boards.set(board, n);

    const s = solveBoard(board);
    if (!s) {
        problems.push(`第${n}片：盘面无解`);
    } else {
        if (s.free !== 0) problems.push(`第${n}片：核空间维数 ${s.free}（不应发生）`);
        const got = bitsOf(s.solution.reduce((acc, v, idx) => (v ? acc | bit(idx) : acc), 0));
        const want = [...lv.flips].sort((a, b) => a - b);
        if (got.join(',') !== want.join(',')) {
            problems.push(`第${n}片：最优解 ${got.join(',')} ≠ flips ${want.join(',')}`);
        }
    }

    if (lv.steps < prevSteps) problems.push(`第${n}片：难度 ${lv.steps} 比上一关 ${prevSteps} 还低`);
    prevSteps = lv.steps;

    if (n <= 5 && !lv.tip) problems.push(`第${n}片：教程关缺少 tip`);
});

// ---------- 教程示意图 vs 真实盘面（1..5 关，全是教程关） ----------
// config.lua 里只写 art.rings = { {行, 列}, ... }（1 起始）= 这一课「需要点击」的点位；
// 盘面由 guide.lua 按「被十字覆盖的奇偶」现算（奇 = 红果汁，偶 = 黄水果）。
// 这里独立复算两件事，任何一条不成立就说明教程在骗人：
//   ① rings 展开成的下标集合 == 该关的真实解序列；
//   ② 由 rings 反推出的盘面 == 该关进关时的真实盘面（boardOf(flips)）。
const lessons = {};
{
    // ★ 结构已改成「一课多页」：M.LESSONS = { { pages = { … }, }, … }
    //   所以先按大括号把每一课切出来，再把这一课所有页里的 rings 点位取并集。
    //   （第 1 课有 3 页：第 1 页只讲盘面用 art.flips、第 2 页才是 rings、第 3 页空盘。）
    const sliceBraces = (text, openIdx) => {
        let depth = 0;
        for (let i = openIdx; i < text.length; i++) {
            if (text[i] === '{') depth++;
            else if (text[i] === '}') { depth--; if (depth === 0) return text.slice(openIdx + 1, i); }
        }
        return '';
    };
    const start = src.indexOf('M.LESSONS');
    const blocks = [];
    if (start >= 0) {
        const open = src.indexOf('{', start);
        let depth = 0, blockStart = -1;
        for (let i = open; i < src.length; i++) {
            const ch = src[i];
            if (ch === '{') {
                depth++;
                if (depth === 2 && blockStart < 0) blockStart = i;
            } else if (ch === '}') {
                if (depth === 2 && blockStart >= 0) { blocks.push(src.slice(blockStart, i + 1)); blockStart = -1; }
                depth--;
                if (depth === 0) break;
            }
        }
    }
    blocks.forEach((block, bi) => {
        const taps = [];
        let at = block.indexOf('rings');
        while (at >= 0) {
            const open = block.indexOf('{', at);
            const body = sliceBraces(block, open);
            for (const m of body.matchAll(/\{\s*(\d+)\s*,\s*(\d+)\s*\}/g)) {
                taps.push((Number(m[1]) - 1) * COLS + (Number(m[2]) - 1));
            }
            at = block.indexOf('rings', open + 1);
        }
        lessons[bi + 1] = { taps: [...new Set(taps)] };
    });
}

for (const n of [1, 2, 3, 4, 5]) {
    const L = lessons[n];
    if (!L) { problems.push(`第${n}片：没解析到教程蓝框（art.rings）`); continue; }
    const want = [...levels[n - 1].flips].sort((a, b) => a - b);
    const got = [...L.taps].sort((a, b) => a - b);
    if (got.join(',') !== want.join(',')) {
        problems.push(`第${n}片教程蓝框点位 ${got.join(',')} ≠ 解序列 ${want.join(',')}`);
    }
    // ② 由蓝框反推的盘面必须等于该关真实盘面
    const derived = boardOf(L.taps);
    const real = boardOf(levels[n - 1].flips);
    if (derived !== real) {
        const missing = bitsOf(derived & ~real);
        const extra = bitsOf(real & ~derived);
        problems.push(`第${n}片教程盘面 ≠ 真实盘面（多绿 ${missing.join(',') || '无'} / 少绿 ${extra.join(',') || '无'}）`);
    }
    // ③ 蓝框坐标必须落在 5×6 内（越界会让环框画到棋盘外）
    for (const i of L.taps) if (i < 0 || i >= N) problems.push(`第${n}片教程蓝框下标越界：${i}`);
}

// ---------- 状态数组（「客服关卡参数」第 4 参）自检 ----------
// 语义：从「全水果」出发，依次踩 flips → 得到的盘面就是初始棋盘；
//       返回 30 项，1 = 水果 / -1 = 果汁，第 k 项对应 idx = k - 1。
// 这里独立复算三件事（客户端侧由 puzzle.initStatesFromFlips 实现）：
//   ① 长度 = 30，取值只有 ±1；
//   ② 不是全水果 / 全果汁（否则这关没得玩）；
//   ③ 照 flips 再踩一遍必须回到「全水果」。
const FULL = (1 << N) - 1;
const stateSummary = [];
levels.forEach((lv, i) => {
    const n = i + 1;
    const init = FULL ^ boardOf(lv.flips);
    const states = [];
    for (let k = 0; k < N; k++) states.push(init & bit(k) ? 1 : -1);
    if (states.length !== N) problems.push(`第${n}片：状态数组长度 ${states.length}，应为 ${N}`);
    if (states.some((v) => v !== 1 && v !== -1)) problems.push(`第${n}片：状态数组出现 1/-1 以外的值`);
    if (states.every((v) => v === 1)) problems.push(`第${n}片：状态数组全水果（等于不用玩）`);
    if (states.every((v) => v === -1)) problems.push(`第${n}片：状态数组全果汁`);
    let b2 = init;
    for (const f of lv.flips) b2 ^= PRESS[f];
    if (b2 !== FULL) problems.push(`第${n}片：照 flips 再踩一遍没回到全水果`);

    const fruit = states.filter((v) => v === 1).length;
    stateSummary.push(`${fruit}/${N - fruit}`);
});

// ---------- 输出 ----------
console.log('关卡数：', levels.length);
console.log('难度曲线：', levels.map((l) => l.steps).join(' '));
console.log('状态数组（水果/果汁）：', stateSummary.slice(0, 8).join('  '), '…');
if (problems.length) {
    console.log('\n发现问题：');
    for (const p of problems) console.log('  -', p);
    process.exit(1);
}
console.log('\n全部通过：下标合法 / 解唯一且最优 / 盘面不重复 / 难度单调 / 教程蓝框与解序列+真实盘面一致 / 状态数组可回到全水果');
