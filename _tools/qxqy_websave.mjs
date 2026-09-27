// qxqy_websave.mjs — 生成「浏览器试玩就绪」存档
//
// 背景：
//   Web 模拟器（beyond-simulator-web）不跑 MCP，也没有 addScript 这一步——它直接从磁盘
//   读存档 JSON 并试玩。而 qxqy_simsave.mjs 产出的存档里 assets.scripts 是空的
//   （脚本由 qxqy_mount.mjs 用 addScript op 在运行时灌入），所以直接丢给浏览器
//   只会得到一屏空画面。
//
//   更麻烦的是，Web 的存档下拉框不是"打开任意文件"，它有硬性筛选（见 server.js 的 ia()）：
//     · 文件名 .json，大小 20B ~ 8MB
//     · 跳过 node_modules / .git / dist / .dsh / coverage
//     · 文件内容必须包含子串 "qxqy-simulator-save"
//   所以一份能出现在网页里的存档，必须主动打上这个标记。
//
// 本脚本做的事（全程不改任何 .lua 源文件）：
//   1. 读入 qxqy_simsave.mjs 产出的模拟器就绪存档（含可实例化模板）；
//   2. 把游戏目录下的 Lua 整体写进 assets.scripts；
//   3. ★ 入口脚本挂到 **server 工程的场景根**（不是 client 模板根！见下方说明）；
//   4. 给入口脚本末尾追加两段模拟器专属补丁：参数兜底 + 容器层级修正；
//   5. 清掉 server 场景根自带的脚手架节点（文本框/预设按钮/图片…），留出干净画面；
//   6. 顶层写上 name 显示名，并把画布设为手机预设。
//
// ★ 为什么入口脚本必须挂 server 侧：
//   studio 的 playStart 是 startPlay(projects.server, { templatesProject: projects.client })，
//   场景根取自 server 工程，client 工程只提供可实例化模板。若把脚本挂到 client 的模板根，
//   那个节点永远不会被实例化 → 脚本不执行 → 画面上只剩 server 工程自带的脚手架。
//
// 用法：
//   node _tools/qxqy_websave.mjs --game TickHop \
//        --src _simulator/sim-ready.save.json \
//        --out _simulator/TickHop.web.save.json \
//        --name "TickHop 试玩"
//
// 之后浏览器打开 http://127.0.0.1:4173/ ，在「工作区存档」下拉里选中它，
// 切到「试玩」模式点启动即可。

import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import {
  SIM_TEMPLATE_GUIDS, SAVE_MARKER, SERVER_ASSET,
  buildParamShim, buildZOrderFix, collectLua, sceneRootOf,
} from './_sim_common.mjs';

const WORKSPACE = process.env.QXQY_WORKSPACE || 'E:/千星/千星游戏';
const ZFIX_FRAME = 3;   // 第几帧做容器层级反转（容器由 OnStart 一次性建好，3 帧足够）

const argv = process.argv.slice(2);
const opt = (name, dflt) => {
  const i = argv.indexOf('--' + name);
  return i >= 0 && argv[i + 1] ? argv[i + 1] : dflt;
};

const GAME = opt('game', 'TickHop');
const ENTRY = opt('entry', 'game.lua');
const SRC = opt('src', '_simulator/sim-ready.save.json');
const OUT = opt('out', '');
const NAME = opt('name', `${GAME} 试玩`);
const CANVAS = opt('canvas', 'mobile-16-9');
const PARAMS_RAW = opt('params', '');

const PARAMS = { ...SIM_TEMPLATE_GUIDS };
if (PARAMS_RAW) Object.assign(PARAMS, JSON.parse(PARAMS_RAW));

const abs = (p) => (path.isAbsolute(p) ? p : path.resolve(WORKSPACE, p));
const outPath = abs(OUT || `_simulator/${GAME}.web.save.json`);

function eachNode(node, fn) {
  fn(node);
  for (const c of node.children || []) eachNode(c, fn);
}

// ---- 1) 读入模拟器就绪存档 ----
const srcPath = abs(SRC);
if (!existsSync(srcPath)) {
  console.error(`[FATAL] 源存档不存在: ${srcPath}`);
  console.error('       先跑: node _tools/qxqy_simsave.mjs --src _simulator/<game>.save.json --out ' + SRC);
  process.exit(1);
}
const save = JSON.parse(readFileSync(srcPath, 'utf8'));
const server = save.assets?.server;
const client = save.assets?.client;
if (!server?.root || !client?.root) {
  console.error('[FATAL] 存档缺少 assets.server.root 或 assets.client.root');
  process.exit(1);
}

// ---- 2) 定位试玩场景根（= 运行时 compiled.root）----
const sceneRoot = sceneRootOf(server);
console.log(`# 试玩场景根: ${sceneRoot.id}(${sceneRoot.kind}) name=${JSON.stringify(sceneRoot.name)}`);

// ---- 3) 清空场景根自带的脚手架，避免与游戏画面重叠 ----
const scaffoldCount = (sceneRoot.children || []).length;
sceneRoot.children = [];
for (const rt of Object.values(sceneRoot.transformByPlatform || {})) {
  rt.offset = { x: 0, y: 0 };
  rt.anchorMin = { x: 0.5, y: 0.5 };
  rt.anchorMax = { x: 0.5, y: 0.5 };
  rt.pivot = { x: 0.5, y: 0.5 };
}
// selectedId 若指向被删的节点会悬空，收敛到场景根自身
server.selectedId = sceneRoot.id;

// ---- 4) 灌入 Lua ----
const gameDir = path.join(WORKSPACE, GAME);
if (!existsSync(gameDir)) {
  console.error(`[FATAL] 游戏目录不存在: ${gameDir}`);
  process.exit(1);
}
const files = collectLua(gameDir);
if (!files.length) {
  console.error(`[FATAL] ${gameDir} 下没有可用的 .lua`);
  process.exit(1);
}

const shim = buildParamShim(PARAMS, '_tools/qxqy_websave.mjs')
  + buildZOrderFix(ZFIX_FRAME, '_tools/qxqy_websave.mjs');

const scripts = files.map((f) => {
  const isEntry = f.name === ENTRY;
  return {
    // 本工程用裸 require（require("config")），模块路径必须是裸文件名
    path: f.name,
    source: isEntry ? f.source + shim : f.source,
    // ★ 入口挂 server 场景根；其余仅作为 require 模块注册
    controlId: isEntry ? sceneRoot.id : '',
    controlAsset: isEntry ? SERVER_ASSET : '',
  };
});
save.assets.scripts = scripts;

// ---- 5) 画布预设（TickHop 是手机玩法）----
server.canvasId = CANVAS;
client.canvasId = CANVAS;

// ---- 6) 打上 Web 存档标记，并让存档名可读 ----
// 重建顶层对象，把 name 放在最前——网页是取文件里第一个 "name" 字段当显示名。
const marked = { name: NAME, kind: SAVE_MARKER, ...save };

mkdirSync(path.dirname(outPath), { recursive: true });
writeFileSync(outPath, JSON.stringify(marked, null, 2), 'utf8');

const text = readFileSync(outPath, 'utf8');
const listed = text.includes(SAVE_MARKER);

console.log(`# 已生成浏览器试玩存档: ${outPath}`);
console.log(`# 存档名: ${NAME} | 画布: ${CANVAS}`);
console.log(`# 清空脚手架子节点: ${scaffoldCount} 个`);
console.log(`# 灌入 Lua: ${scripts.length} 个`);
console.log(`#   入口 ${ENTRY} → 挂载 ${sceneRoot.id} @ ${SERVER_ASSET}`);
console.log(`#   已追加: 参数兜底 ${JSON.stringify(PARAMS)} + 第 ${ZFIX_FRAME} 帧层级修正`);
console.log('# 可实例化模板:');
eachNode(client.root, (n) => {
  if ((client.root.children || []).includes(n)) console.log(`#   guid=${n.guid}  ${n.kind.padEnd(8)} ${n.name}`);
});
console.log(`# Web 存档标记 (${SAVE_MARKER}): ${listed ? '已写入，可在网页下拉中选中' : '缺失，网页不会列出！'}`);
