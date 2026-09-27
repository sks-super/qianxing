// apply_levels.mjs — 把编辑器导出的关卡 Lua 落进工程 config.lua（一键可执行闭环）
//
// 为什么需要它：
//   编辑器「导出 / 下载 .lua」产出的是 `M.LEVELS = { ... }` 片段（这是工程既定约定，
//   见 config.lua 顶部注释）。手工复制粘贴容易漏括号、漏逗号，粘坏一次就整局跑不起来。
//   本工具按「大括号配平」精确替换 config.lua 里的同名片段，替换后自动跑两道静态校验，
//   保证结果就是千星沙箱里能直接 require 的合法 Lua。
//
// 用法：
//   node _tools/apply_levels.mjs <levels.lua>              # 写入 TickHop/config.lua（自动备份）
//   node _tools/apply_levels.mjs <levels.lua> --dry        # 只看 diff 摘要，不落盘
//   node _tools/apply_levels.mjs <levels.lua> --file X.lua # 写到指定 config.lua
//   node _tools/apply_levels.mjs --extract                 # 反向：把 config.lua 现有的 LEVELS 片段打印出来
//
// 退出码：0 成功；1 失败（含校验不通过）

import { readFileSync, writeFileSync, existsSync, copyFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const HERE = path.dirname(fileURLToPath(import.meta.url));   // …/_tools
const ROOT = path.resolve(HERE, '..');                       // 工作区根
const argv = process.argv.slice(2);
const opt = (n, d = '') => { const i = argv.indexOf('--' + n); return i >= 0 && argv[i + 1] ? argv[i + 1] : d; };
const want = (n) => argv.includes('--' + n);

const GAME = opt('game', 'TickHop');
const CFG = path.resolve(ROOT, opt('file', path.join(GAME, 'config.lua')));
const PY = 'C:/Users/JingSu/.workbuddy/binaries/python/versions/3.13.12/python.exe';

// ---------------------------------------------------------------
// 扫出 `M.LEVELS = { ... }` 整段：从名字后第一个 `{` 起做括号配平，
// 跳过字符串（"…" / '…'）与长括号（[[…]]）里的花括号。
// ---------------------------------------------------------------
function extractLevelsBlock(src, tag) {
  const key = /M\.LEVELS\s*=\s*\{/.exec(src);
  if (!key) return null;
  const start = src.indexOf('{', key.index);
  let depth = 0, i = start;
  while (i < src.length) {
    const c = src[i];
    if (c === '"' || c === "'") {              // 短字符串
      const qt = c; i++;
      while (i < src.length) {
        if (src[i] === '\\') { i += 2; continue; }
        if (src[i] === qt) break;
        i++;
      }
      i++; continue;
    }
    if (c === '[' && (src[i + 1] === '[' || src[i + 1] === '=')) {   // 长括号 [[..]] / [=[..]=]
      const eqs = /^\[(=*)\[/.exec(src.slice(i));
      if (eqs) {
        const close = ']' + eqs[1] + ']';
        const end = src.indexOf(close, i + eqs[0].length);
        i = end < 0 ? src.length : end + close.length;
        continue;
      }
    }
    if (c === '-' && src[i + 1] === '-') {      // 行注释
      const nl = src.indexOf('\n', i);
      i = nl < 0 ? src.length : nl + 1;
      continue;
    }
    if (c === '{') depth++;
    else if (c === '}') { depth--; if (depth === 0) return { start, end: i + 1, text: src.slice(start, i + 1) }; }
    i++;
  }
  console.error(`[FAIL] ${tag}: M.LEVELS 的大括号未配平`);
  return null;
}

// ---------------------------------------------------------------
// --extract：打印 config.lua 里现有的 LEVELS 片段
// ---------------------------------------------------------------
if (want('extract')) {
  const src = readFileSync(CFG, 'utf8');
  const blk = extractLevelsBlock(src, CFG);
  if (!blk) process.exit(1);
  process.stdout.write('M.LEVELS = ' + blk.text + '\n');
  process.exit(0);
}

// 取第一个未被 flag 消费的位置参数作为输入文件
const consumed = new Set();
for (const f of ['game', 'file', 'canvas']) {
  const i = argv.indexOf('--' + f);
  if (i >= 0 && argv[i + 1]) consumed.add(i + 1);
}
const IN = argv.find((a, i) => !a.startsWith('--') && !consumed.has(i));
if (!IN) {
  console.error('用法: node _tools/apply_levels.mjs <levels.lua> [--game TickHop] [--dry]');
  console.error('      node _tools/apply_levels.mjs --extract');
  process.exit(2);
}
const IN_FILE = path.resolve(ROOT, IN);
if (!existsSync(IN_FILE)) { console.error('[FAIL] 找不到输入文件: ' + IN_FILE); process.exit(2); }
if (!existsSync(CFG)) { console.error('[FAIL] 找不到 config.lua: ' + CFG); process.exit(2); }

// ---------------------------------------------------------------
// 1) 从导出文件里取出 LEVELS 段（允许文件里夹注释/说明）
// ---------------------------------------------------------------
const incoming = readFileSync(IN_FILE, 'utf8');
const inBlk = extractLevelsBlock(incoming, IN_FILE);
if (!inBlk) process.exit(1);

// 关卡数（数 `name = "…"` 出现次数，够用于摘要）
const countIn = (inBlk.text.match(/\bname\s*=\s*"/g) || []).length;

// ---------------------------------------------------------------
// 2) 替换 config.lua 里的同名片段
// ---------------------------------------------------------------
const cfgSrc = readFileSync(CFG, 'utf8');
const cfgBlk = extractLevelsBlock(cfgSrc, CFG);
if (!cfgBlk) process.exit(1);
const countCfg = (cfgBlk.text.match(/\bname\s*=\s*"/g) || []).length;

console.log(`输入 : ${path.relative(ROOT, IN_FILE).replace(/\\/g, '/')}   关卡数 ${countIn}   片段 ${inBlk.text.length} 字符`);
console.log(`目标 : ${path.relative(ROOT, CFG).replace(/\\/g, '/')}   现有 ${countCfg} 关，片段 ${cfgBlk.text.length} 字符`);

const out = cfgSrc.slice(0, cfgBlk.start) + inBlk.text + cfgSrc.slice(cfgBlk.end);

if (out === cfgSrc) { console.log('\n内容完全一致，无需写入。'); process.exit(0); }

if (want('dry')) {
  console.log(`\n[dry] 将用 ${countIn} 关替换 ${countCfg} 关；M.LEVELS 段 ${cfgBlk.text.length} → ${inBlk.text.length} 字符。未落盘。`);
  process.exit(0);
}

// ---------------------------------------------------------------
// 3) 落盘（先备份）+ 自动校验
// ---------------------------------------------------------------
const BAK = CFG + '.levels.bak';
copyFileSync(CFG, BAK);
writeFileSync(CFG, out);
console.log(`\n已写入 ${path.relative(ROOT, CFG).replace(/\\/g, '/')}（原文件备份为 ${path.basename(BAK)}）`);

if (want('no-check')) process.exit(0);

const shared = path.join(ROOT, '_shared');
let ok = true;
for (const script of ['_check_blocks.py', '_check_refs.py']) {
  try {
    // 校验器把参数当「相对 cwd 的游戏目录」用，故 cwd 设为工作区根、参数传游戏目录名。
    // 失败判定只看退出码（两者出错都会 return 1），不靠正则匹配文案。
    const r = execFileSync(PY, [path.join(shared, script), GAME], { cwd: ROOT, encoding: 'utf8' });
    const summary = r.trim().split('\n').filter((l) => /合计|处不一致|无问题/.test(l)).join(' / ');
    console.log(`[${script}] 通过  ${summary}`);
  } catch (e) {
    ok = false;
    const out = (e.stdout || e.message || '').toString().trim();
    console.log(`[${script}] 失败\n${out}`);
  }
}

console.log(ok
  ? '\n✅ 关卡已更新，静态校验通过 —— config.lua 可直接在千星沙箱中运行。'
  : '\n❌ 校验未通过，请检查导出内容（可用 ' + path.basename(BAK) + ' 还原）。');
process.exit(ok ? 0 : 1);
