// ================================================================
// _verify_levels.mjs —— 点灯迷题关卡数据的独立交叉校验
// ================================================================
// 目的：用**另一套实现**（JS，跟 _gen_levels.py 完全独立）复算 50 关，
//       并顺带验证编辑器.html 的「导入 / 导出」往返是否无损。
//
// 校验项：
//   ① config.lua 的 M.LEVELS 与编辑器内嵌的 INIT_LEVELS 完全一致
//   ② 每关：按 flips 反推的初始盘面非空；该盘面的唯一解 == flips（即最优解）
//   ③ 每关：flips 个数 == steps，下标在 0..29，无重复
//   ④ 盘面两两不重复；难度步数单调不减
//   ⑤ 编辑器 generateLua() 的输出能被自己的 parseLuaLevels() 无损还原
//   ⑥ 编辑器 parseLuaLevels() 能直接解析 config.lua 里的 LEVELS 片段
//
// 用法：node _verify_levels.mjs
// ================================================================

import { readFileSync } from 'node:fs';
import process from 'node:process';

const DIR = process.cwd();
const ROWS = 5, COLS = 6, N = ROWS * COLS;

// ---------- 独立实现：棋盘模型（与 puzzle.lua 同构，但独立书写） ----------
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
const maskOf = (a) => a.reduce((x, i) => x | bit(i), 0);
const boardOf = (flips) => flips.reduce((b, i) => b ^ PRESS[i], 0);

function solveBoard(board) {
    const rows = [];
    for (let r = 0; r < N; r++) rows.push({ mask: PRESS[r], rhs: (board >> r) & 1 });
    const pivot = new Array(N).fill(-1);
    let pr = 0;
    for (let col = 0; col < N && pr < N; col++) {
        let sel = -1;
        for (let i = pr; i < N; i++) if (rows[i].mask & bit(col)) { sel = i; break; }
        if (sel < 0) continue;
        const t = rows[pr]; rows[pr] = rows[sel]; rows[sel] = t;
        for (let i = 0; i < N; i++) {
            if (i !== pr && (rows[i].mask & bit(col))) {
                rows[i].mask ^= rows[pr].mask;
                rows[i].rhs ^= rows[pr].rhs;
            }
        }
        pivot[col] = pr; pr++;
    }
    const free = pivot.filter((p) => p < 0).length;
    const sol = new Array(N).fill(0);
    for (let col = 0; col < N; col++) {
        if (pivot[col] >= 0 && rows[pivot[col]].mask === bit(col)) sol[col] = rows[pivot[col]].rhs;
    }
    return { sol, free };
}

// ---------- 从 config.lua 里抠出 LEVELS 片段 ----------
function readConfigLevels() {
    const src = readFileSync(`${DIR}/config.lua`, 'utf8');
    const m = src.match(/M\.LEVELS\s*=\s*\{([\s\S]*?)\n\}\n/);
    if (!m) throw new Error('config.lua 里找不到 M.LEVELS 表');
    const block = 'M.LEVELS = {' + m[1] + '\n}';
    const out = [];
    const re = /\{\s*name\s*=\s*"([^"]*)"\s*,\s*steps\s*=\s*(\d+)\s*,\s*(?:tip\s*=\s*"([^"]*)"\s*,\s*)?flips\s*=\s*\{([^}]*)\}\s*,?\s*\}/g;
    let mm;
    while ((mm = re.exec(block)) !== null) {
        out.push({
            name: mm[1],
            steps: parseInt(mm[2], 10),
            tip: mm[3] || '',
            flips: (mm[4].match(/-?\d+/g) || []).map(Number),
        });
    }
    return { levels: out, block };
}

// ---------- 从 编辑器.html 里抠出纯计算部分 + 生成/解析函数 ----------
function loadEditor() {
    const html = readFileSync(`${DIR}/编辑器.html`, 'utf8');
    const script = html.match(/<script>([\s\S]*?)<\/script>/)[1];
    const cut = script.indexOf('const canvas = document.getElementById("canvas");');
    if (cut < 0) throw new Error('编辑器.html 结构变了：找不到 canvas 初始化行');
    const prefix = script.slice(0, cut);

    // Lua 生成/解析是纯函数，被哨兵标记圈出，直接整段取出（避免自己写括号匹配）
    const io = script.match(/\/\/ >>> LUA_IO_BEGIN([\s\S]*?)\/\/ <<< LUA_IO_END/);
    if (!io) throw new Error('编辑器.html 结构变了：找不到 LUA_IO_BEGIN / LUA_IO_END 标记');
    const ioBlock = io[1];

    const src = [
        prefix,
        ioBlock,
        'levels = INIT_LEVELS.map((lv,i)=>({name: lv.name || ("第"+String(i+1).padStart(2,"0")+"关"), tip: lv.tip || "", flips: (lv.flips||[]).slice()}));',
        'return { DEFAULTS, ROWS, COLS, N, INIT_LEVELS, boardOf, solveBoard, popcount, maskOf, bitsOf, generateLua, parseLuaLevels };',
    ].join('\n');

    return new Function(src)();
}

// ---------- 主流程 ----------
const problems = [];
const push = (m) => problems.push(m);

const { levels: cfgLevels, block: cfgBlock } = readConfigLevels();
const E = loadEditor();
const initLevels = E.INIT_LEVELS;

console.log(`config.lua 关卡数 = ${cfgLevels.length}；编辑器内嵌 = ${initLevels.length}`);

// ① 两份数据一致
if (cfgLevels.length !== initLevels.length) {
    push(`关卡数不一致：config=${cfgLevels.length} 编辑器=${initLevels.length}`);
} else {
    cfgLevels.forEach((a, i) => {
        const b = initLevels[i];
        const sameFlips = JSON.stringify(a.flips) === JSON.stringify(b.flips || []);
        const sameName = a.name === (b.name || '');
        const sameSteps = a.steps === (b.steps ?? a.steps);
        const sameTip = (a.tip || '') === (b.tip || '');
        if (!sameFlips || !sameName || !sameSteps || !sameTip) {
            push(`第 ${i + 1} 关 config 与编辑器内嵌数据不一致`);
        }
    });
}

// ② ③ 每关独立复算
const boards = new Map();
let prevSteps = 0;
cfgLevels.forEach((lv, i) => {
    const idx = i + 1;
    if (lv.flips.length !== lv.steps) push(`第 ${idx} 关：flips 个数 ${lv.flips.length} != steps ${lv.steps}`);
    if (new Set(lv.flips).size !== lv.flips.length) push(`第 ${idx} 关：flips 有重复下标`);
    lv.flips.forEach((f) => { if (f < 0 || f >= N || !Number.isInteger(f)) push(`第 ${idx} 关：下标越界或非整数 ${f}`); });

    const board = boardOf(lv.flips);
    if (board === 0) { push(`第 ${idx} 关：初始盘面为空（解互相抵消）`); return; }
    const { sol, free } = solveBoard(board);
    if (free !== 0) push(`第 ${idx} 关：核空间非平凡（解不唯一），维数 ${free}`);
    const solList = sol.map((v, k) => (v ? k : -1)).filter((k) => k >= 0);
    const mine = [...lv.flips].sort((a, b) => a - b);
    if (JSON.stringify(solList) !== JSON.stringify(mine)) {
        push(`第 ${idx} 关：当前解不是最优/唯一解，实际唯一解 {${solList.join(',')}}`);
    }
    const key = board;
    if (boards.has(key)) push(`第 ${idx} 关：盘面与第 ${boards.get(key)} 关重复`);
    boards.set(key, idx);

    if (lv.steps < prevSteps) push(`第 ${idx} 关：步数递减 ${prevSteps} -> ${lv.steps}`);
    prevSteps = lv.steps;
});

// ④ 难度曲线预览
const curve = cfgLevels.map((l) => l.steps).join(' ');
console.log('难度曲线:', curve);
console.log(`核空间维数（全盘）: ${solveBoard(0).free}`);

// ⑤ 编辑器导出 → 自己导入，无损
const exported = E.generateLua();
const back = E.parseLuaLevels(exported);
if (back.length !== cfgLevels.length) {
    push(`编辑器导出→导入 关卡数不符：${back.length} != ${cfgLevels.length}`);
} else {
    back.forEach((lv, i) => {
        const a = cfgLevels[i];
        if (JSON.stringify(lv.flips) !== JSON.stringify([...a.flips].sort((x, y) => x - y))) {
            push(`编辑器导出→导入 第 ${i + 1} 关 flips 不一致`);
        }
        if ((lv.tip || '') !== (a.tip || '')) push(`编辑器导出→导入 第 ${i + 1} 关 tip 不一致`);
    });
}

// ⑥ 编辑器能解析 config.lua 里的 LEVELS 片段
const fromConfig = E.parseLuaLevels(cfgBlock);
if (fromConfig.length !== cfgLevels.length) {
    push(`编辑器解析 config 片段失败：${fromConfig.length} != ${cfgLevels.length}`);
} else {
    fromConfig.forEach((lv, i) => {
        const a = cfgLevels[i];
        if (JSON.stringify(lv.flips) !== JSON.stringify([...a.flips].sort((x, y) => x - y))) {
            push(`编辑器解析 config 片段 第 ${i + 1} 关 flips 不一致`);
        }
    });
}

console.log(`导出 Lua 长度 = ${exported.length} 字符；往返关卡数 = ${back.length}；解析 config 片段 = ${fromConfig.length}`);

console.log('\n=== 校验结果 ===');
if (problems.length) {
    problems.forEach((p) => console.log('  ✘ ' + p));
    console.log(`\n合计 ${problems.length} 处问题`);
    process.exit(1);
}
console.log('  ✔ 全部通过：数据一致 / 解最优唯一 / 盘面唯一 / 难度单调 / 导入导出无损');
