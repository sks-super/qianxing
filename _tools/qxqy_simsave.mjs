// qxqy_simsave.mjs — 把工程存档改造成「模拟器就绪」存档
//
// 背景：
//   千星工程的正式控件（DropArea / MessageText / 各 prefab）只存在于官方编辑器里，
//   模拟器存档没有对应控件树，于是 game.InstantiateClientUIControl(prefabId) 全部返回 nil，
//   试玩画面必然是空的。而模拟器的 prefab 注册规则是：
//     registerTemplate(prefabIndex = node.guid)   ← 取自 client 工程 root.children
//   所以只要在存档里补一套「扁平、可染色」的模板节点，并把这些 guid 作为脚本参数喂进去，
//   工程就能在模拟器里真正跑起来。
//
// 做法（不改动任何 .lua 源文件）：
//   1. 从工程存档里克隆一份 image 节点和一个 textbox 节点作为模板原型；
//   2. image 原型换成 100001（rect 纯色矩形原语），可被 imageColor 染色；
//   3. 以固定 guid 挂到 client 工程 root.children 下，从而被注册为可实例化模板；
//   4. 清空模板根 n1 的装饰性子节点，留出干净的试玩画面。
//
// 用法：
//   node _tools/qxqy_simsave.mjs --src _simulator/TickHop.save.json --out _simulator/sim-ready.save.json
//
// 输出末尾会打印模板 guid 映射，直接给 qxqy_mount.mjs 的 --preset sim 使用。

import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';

const WORKSPACE = process.env.QXQY_WORKSPACE || 'E:/千星/千星游戏';

const argv = process.argv.slice(2);
const opt = (name, dflt) => {
  const i = argv.indexOf('--' + name);
  return i >= 0 && argv[i + 1] ? argv[i + 1] : dflt;
};

const SRC = opt('src', '_simulator/TickHop.save.json');
const OUT = opt('out', '_simulator/sim-ready.save.json');

// 模板固定 guid —— 与 _tools/qxqy_mount.mjs 的 sim 预设保持一致
const GUID_RECT = 2000001;
const GUID_TEXT = 2000002;
const IMAGE_RECT_PRIMITIVE = 100001;

const abs = (p) => (path.isAbsolute(p) ? p : path.resolve(WORKSPACE, p));

function findFirst(node, pred) {
  if (pred(node)) return node;
  for (const c of node.children || []) {
    const hit = findFirst(c, pred);
    if (hit) return hit;
  }
  return null;
}

function eachNode(node, fn) {
  fn(node);
  for (const c of node.children || []) eachNode(c, fn);
}

const srcPath = abs(SRC);
if (!existsSync(srcPath)) {
  console.error(`[FATAL] 源存档不存在: ${srcPath}`);
  console.error('       先跑一次 qxqy_mount.mjs --save 生成它。');
  process.exit(1);
}

const save = JSON.parse(readFileSync(srcPath, 'utf8'));
const client = save.assets?.client;
if (!client?.root) {
  console.error('[FATAL] 存档里没有 assets.client.root');
  process.exit(1);
}
if (client.meta?.assetType !== 'client-control-template') {
  console.error(`[FATAL] client.meta.assetType = ${client.meta?.assetType}，模板注册要求 client-control-template`);
  process.exit(1);
}

// ---- 1) 找原型节点 ----
const protoImage = findFirst(client.root, (n) => n.kind === 'image');
const protoText = findFirst(client.root, (n) => n.kind === 'textbox');
if (!protoImage || !protoText) {
  console.error(`[FATAL] 存档里缺少原型节点（image=${!!protoImage} textbox=${!!protoText}）`);
  process.exit(1);
}

// ---- 2) 克隆并改造成扁平模板 ----
function makeTemplate(proto, { id, guid, name, size }) {
  const node = JSON.parse(JSON.stringify(proto));
  node.id = id;
  node.guid = guid;
  node.name = name;
  node.children = [];
  node.scriptMappingIds = [];
  node.giaRelatedGuids = [];
  node.giaInfoIndex = undefined;
  delete node.giaInfoIndex;
  for (const rt of Object.values(node.transformByPlatform || {})) {
    rt.offset = { x: 0, y: 0 };
    rt.anchorMin = { x: 0.5, y: 0.5 };
    rt.anchorMax = { x: 0.5, y: 0.5 };
    rt.pivot = { x: 0.5, y: 0.5 };
    rt.size = { x: size.x, y: size.y };
    rt.scale = { x: 1, y: 1, z: 1 };
    rt.rotation = { x: 0, y: 0, z: 0 };
  }
  return node;
}

const tRect = makeTemplate(protoImage, {
  id: 'tsRect',
  guid: GUID_RECT,
  name: 'SIM_纯色矩形',
  size: { x: 100, y: 100 },
});
// 换成 rect 原语，保证是一张可被 imageColor 染色的纯色底图
tRect.imageSource = 'StaticReference';
tRect.imageId = IMAGE_RECT_PRIMITIVE;
tRect.imageColor = 4294967295; // 不透明白，交给运行时染色
tRect.enableMask = false;
tRect.enableFill = false;
tRect.fillType = 'Unused';
tRect.raycastTarget = false;

const tText = makeTemplate(protoText, {
  id: 'tsText',
  guid: GUID_TEXT,
  name: 'SIM_文本',
  size: { x: 240, y: 48 },
});
tText.text = '';
tText.fontSize = 28;
tText.adaptiveFontSize = false;
tText.horizontalAlignment = 'Middle';
tText.verticalAlignment = 'Middle';

// ---- 3) 挂到 client root.children 下，成为可实例化模板 ----
const root = client.root;
root.children = (root.children || []).filter((n) => n.id !== 'tsRect' && n.id !== 'tsText');
root.children.push(tRect, tText);

// ---- 4) 清空模板根 n1 的装饰子节点，留出干净试玩画面 ----
const templateRoot = root.children.find((n) => n.kind === 'container');
if (templateRoot) {
  templateRoot.children = [];
  for (const rt of Object.values(templateRoot.transformByPlatform || {})) {
    rt.offset = { x: 0, y: 0 };
    rt.anchorMin = { x: 0.5, y: 0.5 };
    rt.anchorMax = { x: 0.5, y: 0.5 };
    rt.pivot = { x: 0.5, y: 0.5 };
    rt.size = { x: 200, y: 200 };
  }
}

// ---- 5) 清空脚本表：由挂载驱动重新灌入，避免重复注册 ----
save.assets.scripts = [];
if (templateRoot) delete templateRoot.scriptMappingIds;
eachNode(root, (n) => { n.scriptMappingIds = []; });

const outPath = abs(OUT);
mkdirSync(path.dirname(outPath), { recursive: true });
writeFileSync(outPath, JSON.stringify(save, null, 2), 'utf8');

console.log(`# 已生成模拟器就绪存档: ${outPath}`);
console.log(`# 模板根控件: ${templateRoot ? templateRoot.id + '(' + templateRoot.kind + ', guid=' + templateRoot.guid + ')' : '(无)'}`);
console.log('# 可实例化模板:');
eachNode(root, (n) => {
  if (root.children.includes(n)) console.log(`#   guid=${n.guid}  ${n.kind.padEnd(8)} ${n.name}`);
});
console.log(`# 脚本参数建议: {"rectPrefabId":${GUID_RECT},"textPrefabId":${GUID_TEXT}}`);
