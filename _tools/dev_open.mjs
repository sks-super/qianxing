#!/usr/bin/env node
// dev_open.mjs — 一键准备并打开「千星沙箱模拟器（Web 版）」
//
// 双击 `启动千星模拟器.bat` 会走到这里。它按顺序做五件事，全部幂等，可反复运行：
//   1) 检查运行环境   —— 定位 beyond-simulator-web/dist/server.js
//   2) 准备键盘映射   —— 上游只映射数字键 1-9，用 qxqy_webkeys.mjs 打补丁（重装 node_modules 后自动补回）
//   3) 准备试玩存档   —— 缺失或 Lua 有改动时自动重建 <游戏>.web.save.json
//   4) 启动 Web 服务  —— 已在跑则复用；--restart 可强制重启（也能清掉 session 槽上限）
//   5) 打开界面       —— 默认模拟器工作台 /editor，加 play 参数则直开试玩页
//
// 用法：
//   node _tools/dev_open.mjs                # 工作台
//   node _tools/dev_open.mjs play           # 直接试玩
//   node _tools/dev_open.mjs --restart      # 先关掉旧服务再起（清 session 槽）
//   node _tools/dev_open.mjs --rebuild      # 强制重建试玩存档
//   node _tools/dev_open.mjs --game 割绳子   # 换游戏
//   node _tools/dev_open.mjs --port 4180 --no-open
//
// 环境变量：QXQY_WORKSPACE 覆盖工作区根（默认取本文件的上级目录）
//
// ★★ 不要改回 spawnSync / execSync（2026-10-13 踩过）：
//   本机环境下 Node 的**同步**子进程 API 会直接抛 `EBUSY`（连 `cmd /c echo hi` 都跑不起来，
//   而异步 spawn/execFile 完全正常）。症状是第 2、3 步都报失败，但那两条失败是「优雅降级」，
//   脚本仍会继续往下跑 —— 于是"改了 Lua 但试玩页还是旧代码"这种问题极难被发现。
//   所以这里一律用 `promisify(execFile)`。

import {
  existsSync, statSync, readdirSync, mkdirSync, openSync, closeSync, readFileSync,
} from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { spawn, execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { fileURLToPath } from 'node:url';

// ---------------------------------------------------------------- 基础

const HERE = path.dirname(fileURLToPath(import.meta.url));
const WORKSPACE = process.env.QXQY_WORKSPACE || path.resolve(HERE, '..');
const SIM = path.join(WORKSPACE, '_simulator');
const NODE = process.execPath;
const run = promisify(execFile);   // ← 唯一允许的子进程执行方式（见文件头说明）

const argv = process.argv.slice(2);
const has = (f) => argv.includes('--' + f);
const opt = (n, d) => {
  const i = argv.indexOf('--' + n);
  return i >= 0 && argv[i + 1] && !argv[i + 1].startsWith('--') ? argv[i + 1] : d;
};

const PORT = parseInt(opt('port', '4173'), 10);
const GAME = opt('game', 'TickHop');
const MODE = has('play') ? 'play' : 'editor';
const NO_OPEN = has('no-open');
const REBUILD = has('rebuild');
const RESTART = has('restart');
const VERBOSE = has('verbose') || !!process.env.QXQY_VERBOSE;
const BASE = `http://127.0.0.1:${PORT}`;
const TAG = GAME.toLowerCase();

const log = (m = '') => console.log(m);
const line = () => log('─'.repeat(58));
const step = (n, m) => log(`\n[${n}/5] ${m}`);
const ok = (m) => log(`      ✅ ${m}`);
const warn = (m) => log(`      ⚠  ${m}`);
const bad = (m) => log(`      ❌ ${m}`);
const info = (m) => log(`      ·  ${m}`);

const wait = (ms) => new Promise((r) => setTimeout(r, ms));
const rel = (p) => path.relative(WORKSPACE, p).split(path.sep).join('/');

function tailLog(p, n = 10) {
  try {
    const t = readFileSync(p, 'utf8').trim();
    if (!t) return '     (日志为空)';
    return t.split(/\r?\n/).slice(-n).map((s) => '     ' + s).join('\n');
  } catch {
    return '     (读不到日志)';
  }
}

/** 统一的子进程捕获（异步；返回 { code, text }） */
async function capture(cmd, args, opts = {}) {
  try {
    const { stdout, stderr } = await run(cmd, args, {
      cwd: WORKSPACE, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024, windowsHide: true, ...opts,
    });
    return { code: 0, text: String(stdout || '') + String(stderr || '') };
  } catch (e) {
    return {
      code: typeof e.code === 'number' ? e.code : 1,
      text: String(e.stdout || '') + String(e.stderr || ''),
    };
  }
}

// ---------------------------------------------------------------- 1 环境

function findServerJs() {
  const home = os.homedir();
  const cands = [
    process.env.QXQY_WEB_SERVER,
    path.join(WORKSPACE, 'node_modules', 'beyond-simulator-web', 'dist', 'server.js'),
    path.join(home, '.workbuddy', 'binaries', 'node', 'workspace', 'node_modules',
      'beyond-simulator-web', 'dist', 'server.js'),
    path.join(HERE, 'miliastra-beyond-simulator', 'web', 'dist', 'server.js'),
  ].filter(Boolean);
  return cands.find((p) => existsSync(p)) || null;
}

// ---------------------------------------------------------------- 2 键盘补丁

async function ensureKeyPatch() {
  const f = path.join(HERE, 'qxqy_webkeys.mjs');
  if (!existsSync(f)) { warn('找不到 qxqy_webkeys.mjs，跳过（试玩页将只有数字键可用）'); return; }

  const chk = await capture(NODE, [f, '--check']);
  if (/已打补丁/.test(chk.text)) {
    ok('键盘映射：已就绪（WASD / 空格 / 方向键 / R / T）');
    return;
  }
  const ap = await capture(NODE, [f, '--apply']);
  if (ap.code === 0 && /补丁已应用|无需重复/.test(ap.text)) {
    ok('键盘映射：已自动修复（上游只映射数字键 1-9）');
    info('浏览器首次需 Ctrl+F5 强制刷新');
  } else {
    warn('键盘映射补丁失败，试玩页键盘可能无反应');
    info('可手工重跑：node _tools/qxqy_webkeys.mjs --check');
    if (VERBOSE) info(ap.text.trim());
  }
}

// ---------------------------------------------------------------- 3 存档

function newestMtime(dir, ext) {
  let newest = 0;
  const walk = (d) => {
    let entries;
    try { entries = readdirSync(d, { withFileTypes: true }); } catch { return; }
    for (const e of entries) {
      // ★ 跳过 node_modules / 隐藏目录 / 下划线开头的派生目录（_sandbox、_tools…）：
      //   这些目录里的 .lua 是副本或工具，拿它们判断「Lua 有改动」会永远为真 → 每次启动都重建存档。
      if (e.name === 'node_modules' || e.name.startsWith('.') || e.name.startsWith('_')) continue;
      const p = path.join(d, e.name);
      if (e.isDirectory()) walk(p);
      else if (e.name.endsWith(ext)) {
        try { newest = Math.max(newest, statSync(p).mtimeMs); } catch { /* ignore */ }
      }
    }
  };
  if (existsSync(dir)) walk(dir);
  return newest;
}

async function runNode(args, label) {
  const { code, text } = await capture(NODE, args);
  const out = text.trim();
  if (code !== 0) {
    bad(`${label} 失败（exit ${code}）`);
    if (out) log(out.split(/\r?\n/).slice(-12).map((s) => '         ' + s).join('\n'));
    return false;
  }
  ok(label);
  if (VERBOSE && out) log(out.split(/\r?\n/).map((s) => '         ' + s).join('\n'));
  return true;
}

async function ensureArchive() {
  mkdirSync(SIM, { recursive: true });

  const webSave = path.join(SIM, `${GAME}.web.save.json`);
  const simReady = path.join(SIM, 'sim-ready.save.json');
  const rawSave = path.join(SIM, `${GAME}.save.json`);

  // 底层两份存档只在缺失时生成：它们描述「工程结构」，与 Lua 内容无关
  if (!existsSync(rawSave) || !existsSync(simReady)) {
    info('首次运行，从工程生成模拟器存档（约 10 秒）…');
    if (!await runNode([path.join(HERE, 'qxqy_mount.mjs'), '--game', GAME,
      '--entry', 'game.lua', '--steps', '1', '--save', rel(rawSave)], '生成工程存档')) return false;
    if (!await runNode([path.join(HERE, 'qxqy_simsave.mjs'), '--src', rel(rawSave),
      '--out', rel(simReady)], '改造为「模拟器就绪」存档')) return false;
  }

  // 试玩存档内嵌 Lua，所以 Lua 一改就必须重建
  const luaNew = newestMtime(path.join(WORKSPACE, GAME), '.lua');
  const saveNew = existsSync(webSave) ? statSync(webSave).mtimeMs : 0;
  const missing = !existsSync(webSave);
  const stale = missing || REBUILD || luaNew > saveNew + 1000;

  if (!stale) {
    ok(`试玩存档：${path.basename(webSave)}（最新）`);
    return true;
  }

  info(`重建试玩存档（${missing ? '缺失' : REBUILD ? '--rebuild' : 'Lua 有改动'}）…`);
  return runNode([path.join(HERE, 'qxqy_websave.mjs'), '--game', GAME,
    '--src', rel(simReady), '--out', rel(webSave),
    '--name', `${GAME} 试玩`], '生成「浏览器试玩就绪」存档');
}

// ---------------------------------------------------------------- 4 服务

async function health() {
  try {
    const r = await fetch(`${BASE}/health`, { signal: AbortSignal.timeout(2500) });
    if (!r.ok) return false;
    const j = await r.json().catch(() => null);
    return !!(j && j.status === 'ok');
  } catch {
    return false;
  }
}

/** 杀掉占用 PORT 的监听进程（Windows: netstat + taskkill） */
async function killPort() {
  const ns = await capture('netstat', ['-ano', '-p', 'TCP']);
  if (ns.code !== 0) return 0;
  const pids = new Set();
  for (const raw of ns.text.split(/\r?\n/)) {
    const c = raw.trim().split(/\s+/);
    if (c.length >= 5 && c[0].toUpperCase() === 'TCP' && c[3].toUpperCase() === 'LISTENING'
      && c[1].endsWith(':' + PORT)) pids.add(c[4]);
  }
  let killed = 0;
  for (const pid of pids) {
    const r = await capture('taskkill', ['/PID', String(pid), '/T', '/F']);
    if (r.code === 0) killed++;
  }
  return killed;
}

function startServer(serverJs) {
  const logPath = path.join(SIM, '_web-server.log');
  mkdirSync(SIM, { recursive: true });
  const fd = openSync(logPath, 'a');
  const child = spawn(NODE, [serverJs, '--workspace', WORKSPACE, '--port', String(PORT)], {
    cwd: WORKSPACE,
    detached: true,
    stdio: ['ignore', fd, fd],
    windowsHide: true,
  });
  child.unref();
  closeSync(fd);   // 子进程已持有副本，父进程这个句柄可以放掉
  return { pid: child.pid, logPath };
}

async function ensureServer(serverJs) {
  if (await health()) {
    if (!RESTART) {
      ok(`服务已在运行，直接复用（${BASE}）`);
      return true;
    }
    info('--restart：关闭旧服务…');
    const n = await killPort();
    info(`已结束 ${n} 个监听进程`);
    for (let i = 0; i < 20 && (await health()); i++) await wait(200);
  }

  const { pid, logPath } = startServer(serverJs);
  info(`后台启动中（pid ${pid}）…`);
  for (let i = 0; i < 75; i++) {
    await wait(400);
    if (await health()) {
      ok(`服务就绪（日志：${rel(logPath)}）`);
      return true;
    }
  }
  bad('服务启动超时');
  log('     ─── 日志末尾 ───');
  log(tailLog(logPath));
  return false;
}

// ---------------------------------------------------------------- 5 浏览器

function openBrowser(url) {
  try {
    let cmd, args;
    if (process.platform === 'win32') {
      cmd = 'cmd.exe';
      args = ['/c', 'start', '""', url];
    } else if (process.platform === 'darwin') {
      cmd = 'open'; args = [url];
    } else {
      cmd = 'xdg-open'; args = [url];
    }
    spawn(cmd, args, { detached: true, stdio: 'ignore', windowsHide: true }).unref();
    return true;
  } catch {
    return false;
  }
}

// ---------------------------------------------------------------- main

async function main() {
  log('');
  line();
  log('  千星沙箱模拟器 · 一键启动');
  line();
  log(`  工作区  ${WORKSPACE}`);
  log(`  端口    ${PORT}`);
  log(`  模式    ${MODE === 'play' ? '直接试玩' : '模拟器工作台'}`);

  // ---- 1
  step(1, '检查运行环境');
  const serverJs = findServerJs();
  if (!serverJs) {
    bad('找不到 beyond-simulator-web/dist/server.js');
    info('安装：cd "' + path.join(os.homedir(), '.workbuddy', 'binaries', 'node', 'workspace') + '"');
    info('      npm i beyond-simulator-web beyond-simulator-mcp');
    log('');
    process.exit(1);
  }
  ok('模拟器本体：' + serverJs.replace(os.homedir(), '~'));
  if (!existsSync(path.join(WORKSPACE, GAME))) {
    bad(`游戏目录不存在：${GAME}`);
    process.exit(1);
  }

  // ---- 2
  step(2, '准备键盘映射');
  await ensureKeyPatch();

  // ---- 3
  step(3, '准备试玩存档');
  const archiveOk = await ensureArchive();
  if (!archiveOk) info('存档准备失败，将尝试用现有存档继续');

  // ---- 4
  step(4, '启动 Web 服务');
  const serverOk = await ensureServer(serverJs);
  if (!serverOk) {
    log('');
    log('  服务没起来，界面无法打开。可尝试：');
    log(`    1) 换端口：node _tools/dev_open.mjs --port 4180`);
    log(`    2) 看日志：${rel(path.join(SIM, '_web-server.log'))}`);
    log('');
    process.exit(1);
  }

  // ---- 5
  step(5, '打开界面');
  const playUrl = `${BASE}/editor/play#${TAG}`;
  const editorUrl = `${BASE}/editor`;
  const url = MODE === 'play' ? playUrl : editorUrl;
  if (NO_OPEN) {
    info('--no-open：跳过打开浏览器');
  } else if (openBrowser(url)) {
    ok('已在默认浏览器打开');
  } else {
    warn('自动打开失败，请手动访问下面的地址');
  }

  log('');
  line();
  log('  界面地址');
  log(`    模拟器工作台   ${editorUrl}`);
  log(`    试玩页         ${playUrl}`);
  log('');
  log('  操作');
  log('    A / D（或 ←/→）移动      W / 空格 跳跃');
  log('    R 重载关卡               T 下一关');
  log('');
  log('  提示');
  log('    · 试玩页左上角若没自动载入，先在「工作台」下拉里选中');
  log(`      「${GAME} 试玩」再点启动`);
  log('    · 键盘无反应 → 浏览器按 Ctrl+F5 强制刷新（补丁写的是磁盘文件）');
  log('    · 反复试玩报「session limit reached」→ 重跑本脚本加 --restart');
  log('    · 改完 Lua 直接重跑本脚本，会自动重建存档，无需手工三步');
  line();
  log('');
}

main().catch((e) => {
  console.error('\n[FATAL] ' + (e && e.stack ? e.stack : e));
  process.exit(1);
});
