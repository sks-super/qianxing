// ================================================================
// 浮岛借木 · 关卡编辑器「导出 → 导入」往返自检（Node，无需浏览器）
//
// 为什么需要它：
//   _tools/e2e_浮岛借木.sh 与 _tools/solve_浮岛借木.py 都是**直接读 config.lua** 的，
//   而关卡真正的上游是编辑器（编辑器.html）里的 generateLua() / parseLuaLevels()。
//   这一对函数一旦对不上（字段改名、格式漂移），关卡就会在「导出 → 粘回文件」这一步
//   悄悄丢数据，而 Lua 侧的校验完全看不出来。
//
// 做法：
//   ① 把 编辑器.html 里 <script> 的内容抠出来，用一层极薄的 DOM 桩子在 Node 里跑起来；
//   ② 调用 generateLua() 导出，再调 parseLuaLevels() 解析回来；
//   ③ 逐关逐项比对，任何一处不一致就退出码 1。
//
// 用法：
//   node _tools/test_editor_roundtrip.mjs
// ================================================================
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, '..');
const HTML = path.join(ROOT, '浮岛借木', '编辑器.html');

const html = fs.readFileSync(HTML, 'utf8');
const m = /<script>([\s\S]*?)<\/script>/.exec(html);
if (!m) {
    console.error('★ 没在 编辑器.html 里找到 <script> 块');
    process.exit(1);
}

// ---------- 极薄 DOM 桩子：只提供脚本启动时真正会碰到的那些接口 ----------
const noop = () => {};
function mkEl() {
    const el = {
        value: '', innerHTML: '', textContent: '', style: {}, dataset: {}, width: 0, height: 0,
        classList: { toggle: noop, add: noop, remove: noop, contains: () => false },
        appendChild: noop, removeChild: noop, addEventListener: noop,
        select: noop, focus: noop, click: noop,
        getBoundingClientRect: () => ({ left: 0, top: 0, width: 0, height: 0 }),
    };
    el.getContext = () => new Proxy({}, {
        get: (t, k) => (k in t ? t[k] : noop),
        set: (t, k, v) => { t[k] = v; return true; },
    });
    return el;
}
const els = {};
globalThis.document = {
    getElementById: (id) => (els[id] || (els[id] = mkEl())),
    querySelectorAll: () => [],
    createElement: () => mkEl(),
    execCommand: noop,
    body: mkEl(),
};
globalThis.window = { addEventListener: noop, innerWidth: 1400, innerHeight: 900 };
globalThis.alert = (s) => { throw new Error('编辑器弹窗：' + s); };
globalThis.confirm = () => true;
globalThis.Blob = class { constructor() {} };
globalThis.URL = { createObjectURL: () => '', revokeObjectURL: noop };

// ---------- 把编辑器脚本跑起来，取回需要的那几个函数 ----------
const api = new Function(m[1] + '\n;return { generateLua, parseLuaLevels, levels, INITIAL_LEVELS };')();

function norm(lv) {
    return {
        name: lv.name,
        map: lv.map.slice(),
        spawn: { c: lv.spawn.c, r: lv.spawn.r },
        goal: { c: lv.goal.c, r: lv.goal.r },
        trees: lv.trees.map(o => [o.c, o.r]),
        rocks: lv.rocks.map(o => [o.c, o.r, o.h]),
        roots: lv.roots.map(o => [o.c, o.r]),
        logs: lv.logs.map(o => [o.c, o.r, o.dir]),
        hints: (lv.hints || []).slice(),
    };
}

let bad = 0;
const lua = api.generateLua();
const back = api.parseLuaLevels(lua);

console.log('编辑器内关卡数 ' + api.levels.length + ' → 导出 ' + lua.split('\n').length +
    ' 行 Lua → 解析回 ' + back.length + ' 关');
if (back.length !== api.levels.length) {
    console.error('★ 关卡数对不上');
    bad++;
}
for (let i = 0; i < Math.min(back.length, api.levels.length); i++) {
    const a = JSON.stringify(norm(api.levels[i]));
    const b = JSON.stringify(norm(back[i]));
    if (a === b) {
        console.log('  [OK ] 第' + String(i + 1).padStart(2, '0') + '关 ' + api.levels[i].name);
    } else {
        console.error('  [差异] 第' + String(i + 1).padStart(2, '0') + '关 ' + api.levels[i].name);
        console.error('    原   ' + a);
        console.error('    往返 ' + b);
        bad++;
    }
}

// ---------- ★ 再核对一次：编辑器内置关卡 == config.lua 的 M.LEVELS ----------
//   （两边是手工同步的，最容易在改关卡时只改一边）
function tableBody(src, key, from) {
    const re = new RegExp('\\b' + key + '\\s*=\\s*\\{');
    const m2 = re.exec(src.slice(from));
    if (!m2) return '';
    let depth = 1, i = from + m2.index + m2[0].length, out = '';
    while (i < src.length) {
        const ch = src[i];
        if (ch === '{') depth++;
        else if (ch === '}') { depth--; if (depth === 0) break; }
        out += ch;
        i++;
    }
    return out;
}
function parseConfigLevels(src) {
    const start = src.indexOf('M.LEVELS = {');
    if (start < 0) return [];
    let i = start + 'M.LEVELS = {'.length;
    let depth = 1;          // 已经在 M.LEVELS 那一层里
    const blocks = [];
    let cur = null;
    for (; i < src.length; i++) {
        const ch = src[i];
        if (ch === '{') {
            depth++;
            if (depth === 2) { cur = []; continue; }    // 一关开始：花括号本身不收
        } else if (ch === '}') {
            depth--;
            if (depth === 1) { blocks.push(cur.join('')); cur = null; continue; }
            if (depth === 0) break;                     // M.LEVELS 结束
        }
        if (cur) cur.push(ch);
    }
    return blocks.map(b => {
        const lv = {
            name: (/"([^"]*)"/.exec(/name\s*=\s*"[^"]*"/.exec(b)?.[0] || '""') || [])[1] || '',
            map: [...b.matchAll(/"([#.]{2,})"/g)].map(x => x[1]),
        };
        const sp = /spawn\s*=\s*\{\s*c\s*=\s*(\d+)\s*,\s*r\s*=\s*(\d+)/.exec(b);
        const gl = /goal\s*=\s*\{\s*c\s*=\s*(\d+)\s*,\s*r\s*=\s*(\d+)/.exec(b);
        lv.spawn = { c: +sp[1], r: +sp[2] };
        lv.goal = { c: +gl[1], r: +gl[2] };
        lv.trees = [...tableBody(b, 'trees', 0).matchAll(/\{\s*c\s*=\s*(\d+)\s*,\s*r\s*=\s*(\d+)\s*\}/g)]
            .map(x => ({ c: +x[1], r: +x[2] }));
        lv.rocks = [...tableBody(b, 'rocks', 0).matchAll(/\{\s*c\s*=\s*(\d+)\s*,\s*r\s*=\s*(\d+)\s*,\s*h\s*=\s*(\d+)\s*\}/g)]
            .map(x => ({ c: +x[1], r: +x[2], h: +x[3] }));
        lv.roots = [...tableBody(b, 'roots', 0).matchAll(/\{\s*c\s*=\s*(\d+)\s*,\s*r\s*=\s*(\d+)\s*\}/g)]
            .map(x => ({ c: +x[1], r: +x[2] }));
        lv.logs = [...tableBody(b, 'logs', 0).matchAll(/\{\s*c\s*=\s*(\d+)\s*,\s*r\s*=\s*(\d+)\s*,\s*dir\s*=\s*"([WSAD])"\s*\}/g)]
            .map(x => ({ c: +x[1], r: +x[2], dir: x[3] }));
        lv.hints = [...tableBody(b, 'hints', 0).matchAll(/"([^"]*)"/g)].map(x => x[1]);
        return lv;
    });
}

const cfgSrc = fs.readFileSync(path.join(ROOT, '浮岛借木', 'config.lua'), 'utf8');
const cfg = parseConfigLevels(cfgSrc);
console.log('\nconfig.lua 关卡数 ' + cfg.length + ' · 编辑器内置关卡数 ' + api.INITIAL_LEVELS.length);
if (cfg.length !== api.INITIAL_LEVELS.length) {
    console.error('★ config.lua 与编辑器的关卡数不一致');
    bad++;
}
for (let i = 0; i < Math.min(cfg.length, api.INITIAL_LEVELS.length); i++) {
    const a = JSON.stringify(norm(cfg[i]));
    const b = JSON.stringify(norm(api.INITIAL_LEVELS[i]));
    if (a === b) {
        console.log('  [OK ] 第' + String(i + 1).padStart(2, '0') + '关 ' + cfg[i].name + '（两边一致）');
    } else {
        console.error('  [差异] 第' + String(i + 1).padStart(2, '0') + '关');
        console.error('    config   ' + a);
        console.error('    编辑器   ' + b);
        bad++;
    }
}

// 顺带核对：编辑器内置关卡 == config.lua 的关卡（用 solve 工具的解析结果比对由 e2e 负责；
// 这里只做个「地图行长一致」的粗查，防止贴进去的地图行被截断）
api.levels.forEach((lv, i) => {
    const w = lv.map[0].length;
    const off = lv.map.filter(s => s.length !== w).length;
    if (off) { console.error('★ 第%02d关有 %d 行地图长度不等于 %d', i + 1, off, w); bad++; }
});

console.log(bad ? '===== 往返自检：有 ' + bad + ' 处问题 =====' : '===== 往返自检：全部通过 =====');
process.exit(bad ? 1 : 0);
