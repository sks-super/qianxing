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
//   1. 从工程存档里克隆一份 image 节点、一个 textbox 节点、一个 container 节点作为模板原型；
//   2. image 原型换成 100001（rect 纯色矩形原语），可被 imageColor 染色；
//   3. 以固定 guid 挂到 client 工程 root.children 下，从而被注册为可实例化模板；
//      · 纯色底图建**两个**模板：「矩形」（首选）+「图片」（回退）—— 见 GUID_RECT / GUID_IMAGE；
//      · 除纯色底图 / 文本 / 容器外，还要给「海水 / 草地 / 树木 / 人物」这四个
//        美术素材元件各建一个模板，并**预置代表色**（见 COLOR_* 注释）；
//   4. 清空模板根 n1 的装饰性子节点，留出干净的试玩画面。
//
// 用法：
//   node _tools/qxqy_simsave.mjs --src _simulator/TickHop.save.json --out _simulator/sim-ready.save.json
//
// 输出末尾会打印模板 guid 映射，直接给 qxqy_mount.mjs 的 --preset sim 使用。

import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

// 工作区默认为「本文件的上级目录」，换机器不用改（QXQY_WORKSPACE 可覆盖）
const WORKSPACE = process.env.QXQY_WORKSPACE
  || path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

const argv = process.argv.slice(2);
const opt = (name, dflt) => {
  const i = argv.indexOf('--' + name);
  return i >= 0 && argv[i + 1] ? argv[i + 1] : dflt;
};

const SRC = opt('src', '_simulator/TickHop.save.json');
const OUT = opt('out', '_simulator/sim-ready.save.json');

// 模板固定 guid —— 与 _tools/_sim_common.mjs 的 SIM_TEMPLATE_GUIDS 保持一致。
// ★ 用真机编辑器里的元件索引（矩形 1073741894 / 图片 1073741870 / 文本框 1073741868 /
//   容器节点 1073741876 / 海水 1073741879 / 草地 1073741881 / 树木 1073741883 /
//   人物 1073741886），这样模拟器与真机同源，
//   config.DEFAULT_PREFAB_* 的回退值两边都能命中。
//   见 _shared/编辑器元件索引.md
//
// ★ 纯色底图有两个模板，对应游戏里的**两级回退**：
//     首选「矩形」1073741894（用户自建，自带矩形图元，真机不需要配白图）
//     回退「图片」1073741870（官方内置；真机默认不带图源，没配白图就是彩色「?」）
//   两个都登记，游戏的两级回退在模拟器里才都走得通。
const GUID_RECT = 1073741894;
const GUID_IMAGE = 1073741870;
const GUID_TEXT = 1073741868;
const GUID_CONTAINER = 1073741876;

// ★ 美术素材元件（海水 / 草地 / 树木 / 人物）
//   真机上这几个元件自带美术素材，游戏在**素材模式下一律不写 imageColor**
//   （一写就把素材乘上去了）。模拟器没有真机素材，于是这里把模板的 imageColor
//   预置成该类的**代表色**（取自 config.DEFAULT_PALETTE）：
//   游戏不写 color，模板预置色就留在控件上 → 模拟器里照样有可见画面、截图可比对；
//   搬到真机后游戏依旧不写 color，显示的就是元件自带的美术。
const GUID_WATER = 1073741879;
const GUID_LAND = 1073741881;
const GUID_TREE = 1073741883;
const GUID_PLAYER = 1073741886;

const IMAGE_RECT_PRIMITIVE = 100001;

// 代表色（AARRGGBB，与模拟器 color.js 的 packRgba 一致；取自 config.DEFAULT_PALETTE）
const COLOR_WATER = 0xff2b8fa4;   // palette.water
const COLOR_LAND = 0xff6db03c;    // palette.land
const COLOR_TREE = 0xff2f6b3a;    // palette.treeCanopy
const COLOR_PLAYER = 0xfff2a03c;  // palette.playerBody

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
// 容器原型必须「先找、后推模板」：下面的 templateRoot 也是 kind==='container'，
// 一旦把容器模板推回 root.children，findFirst 拿到的就可能是模板自己。
const templateRoot = (client.root.children || []).find((n) => n.kind === 'container')
  || findFirst(client.root, (n) => n.kind === 'container');
if (!protoImage || !protoText || !templateRoot) {
  console.error(`[FATAL] 存档里缺少原型节点（image=${!!protoImage} textbox=${!!protoText} container=${!!templateRoot}）`);
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

// 做成「一张可染色的纯色底图」：换成 rect 原语（100001）
//   color 是模板预置色 —— 游戏在素材模式下不写 imageColor，这个预置色就会留着。
function makeRectTemplate(proto, { id, guid, name, size, color }) {
  const node = makeTemplate(proto, { id, guid, name, size });
  node.imageSource = 'StaticReference';
  node.imageId = IMAGE_RECT_PRIMITIVE;
  node.imageColor = color >>> 0;
  node.enableMask = false;
  node.enableFill = false;
  node.fillType = 'Unused';
  node.raycastTarget = false;
  return node;
}

// ---- 纯色底图：首选「矩形」，外加一个「图片」回退模板 ----
//   ⚠️ 两个模板的预置色都会被游戏覆盖（纯色底图这一路**会**写 imageColor），
//      所以颜色区分不了它们 —— 靠**模板名**区分：跑完看控件快照里的名字
//      （正常应是 SIM_矩形；若出现 SIM_图片_回退，说明走了回退路径）。
//      想要压测回退路径：--params '{"rectPrefabId":999999}'（一个不存在的索引）。
const tRect = makeRectTemplate(protoImage, {
  id: 'tsRect',
  guid: GUID_RECT,
  name: 'SIM_矩形',
  size: { x: 100, y: 100 },
  color: 0xffffffff, // 不透明白，交给运行时染色
});
const tImage = makeRectTemplate(protoImage, {
  id: 'tsImage',
  guid: GUID_IMAGE,
  name: 'SIM_图片_回退',
  size: { x: 100, y: 100 },
  color: 0xffffffff, // 同上：渲染与 tRect 完全一致，只有名字不同
});

// 美术素材元件：模板自带代表色，游戏不写 imageColor 时就会显示它
const tWater = makeRectTemplate(protoImage, {
  id: 'tsWater', guid: GUID_WATER, name: 'SIM_海水', size: { x: 100, y: 100 }, color: COLOR_WATER,
});
const tLand = makeRectTemplate(protoImage, {
  id: 'tsLand', guid: GUID_LAND, name: 'SIM_草地', size: { x: 100, y: 100 }, color: COLOR_LAND,
});
const tTree = makeRectTemplate(protoImage, {
  id: 'tsTree', guid: GUID_TREE, name: 'SIM_树木', size: { x: 100, y: 100 }, color: COLOR_TREE,
});
const tPlayer = makeRectTemplate(protoImage, {
  id: 'tsPlayer', guid: GUID_PLAYER, name: 'SIM_人物', size: { x: 100, y: 100 }, color: COLOR_PLAYER,
});

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

// 容器节点模板：本身不绘制任何图形，只用来组织子控件（游戏的分层容器由它创建）
const tContainer = makeTemplate(templateRoot, {
  id: 'tsContainer',
  guid: GUID_CONTAINER,
  name: 'SIM_容器节点',
  size: { x: 200, y: 200 },
});
tContainer.children = [];

// ---- 3) 挂到 client root.children 下，成为可实例化模板 ----
const TEMPLATE_IDS = ['tsRect', 'tsImage', 'tsText', 'tsContainer', 'tsWater', 'tsLand', 'tsTree', 'tsPlayer'];
const root = client.root;
root.children = (root.children || []).filter((n) => !TEMPLATE_IDS.includes(n.id));
root.children.push(tRect, tImage, tText, tContainer, tWater, tLand, tTree, tPlayer);

// ---- 4) 清空模板根 n1 的装饰子节点，留出干净试玩画面 ----
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
console.log(`# 脚本参数建议: {"rectPrefabId":${GUID_RECT},"imagePrefabId":${GUID_IMAGE},"textPrefabId":${GUID_TEXT},"containerPrefabId":${GUID_CONTAINER},`
  + `"waterPrefabId":${GUID_WATER},"landPrefabId":${GUID_LAND},"treePrefabId":${GUID_TREE},"playerPrefabId":${GUID_PLAYER}}`);
