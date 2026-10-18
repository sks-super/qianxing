// verify_layers.mjs — 回归：核对「两层容器」结构（第一层按物品类型 / 第二层按组件类型）
//
// 为什么需要它：真机与模拟器的渲染顺序相反，真机上「文字被同层底图盖住」这类问题
// 在模拟器里看不出来。结构本身（谁是谁的子节点、文字组是否独立成组）是引擎无关的事实，
// 所以用控件树来做判据 —— 结构对了，真机的叠放关系才对。
//
// 用法: node _tools/verify_layers.mjs            # 默认查 TickHop 第04关（有秒数标签）
//       node _tools/verify_layers.mjs --level 5  # 切到第 N 关再查
import { loadWebSession } from './_webclient.mjs';

// 结构验证：确认「第一层按物品类型 / 第二层按组件类型」的容器树真的建起来了


const { api } = loadWebSession('probe-tree');
await api('load-archive', { path: '_simulator/TickHop.web.save.json' });
await api('play', { action: 'start', args: { canvasId: 'mobile-16-9' } });
const step = async (n) => { for (let i = 0; i < n; i++) await api('play', { action: 'step', args: { dt: 1 / 30 } }); };
const key = async (k) => { await api('play', { action: 'key', args: { key: k } }); };
const view = async () => api('play', { action: 'get', args: { view: true, sceneRev: 0, compact: true } });

const argv = process.argv.slice(2);
const opt = (n, d) => { const i = argv.indexOf('--' + n); return i >= 0 && argv[i + 1] ? argv[i + 1] : d; };
const LEVEL = parseInt(opt('level', '4'), 10);
for (let i = 1; i < LEVEL; i++) { await key('KeyboardCharacterSkill4KeyDown'); await step(150); }
await step(10);

const g = await view();
const nodes = g.scene.nodes;
const byId = new Map(nodes.map((n) => [n.id, n]));
const kids = new Map();
for (const n of nodes) {
  if (n.parent === null || n.parent === undefined) continue;
  if (!kids.has(n.parent)) kids.set(n.parent, []);
  kids.get(n.parent).push(n);
}
const label = (n) => {
  if (n.kind === 'textbox') return '文本"' + n.text + '"';
  return '图片';
};
const root = nodes.find((n) => n.parent === null);
console.log('根 id=' + root.id + '  子节点 ' + kids.get(root.id).length + ' 个');
for (const c of kids.get(root.id)) {
  const cc = kids.get(c.id) || [];
  const kinds = cc.map(label).join(', ');
  console.log('  容器 id=' + String(c.id).padStart(3) + '  z=' + c.z + '  子节点 ' + cc.length +
    ' 个' + (cc.length ? '  [' + kinds.slice(0, 60) + ']' : ''));
  // 再下一层（第二层容器）
  for (const gc of cc) {
    const gcc = kids.get(gc.id) || [];
    if (gcc.length) {
      const kk = {};
      for (const x of gcc) kk[label(x).replace(/".*"/, '".."')] = (kk[label(x).replace(/".*"/, '".."')] || 0) + 1;
      console.log('       └ 子容器 id=' + String(gc.id).padStart(3) + '  z=' + gc.z +
        '  装了 ' + gcc.length + ' 个 → ' + JSON.stringify(kk));
    }
  }
}

// 平台秒数的父子归属（关键判据）
const labels = nodes.filter((n) => n.kind === 'textbox' && /^[0-9]$/.test(String(n.text || '')));
const platRects = [];
for (const n of nodes) {
  if (n.kind !== 'image') continue;
  const sib = labels.find((l) => Math.abs(l.matrix.tx - n.matrix.tx) < 1 && Math.abs(l.matrix.ty - n.matrix.ty) < 1);
  if (sib) platRects.push(n);
}
console.log('\n【判据】秒数文本的父容器 = ' + [...new Set(labels.map((l) => l.parent))].join(',') +
  '   平台矩形的父容器 = ' + [...new Set(platRects.map((p) => p.parent))].join(','));
const lp = labels[0] && labels[0].parent, rp = platRects[0] && platRects[0].parent;
if (lp && rp && lp !== rp) {
  const lNode = byId.get(lp), rNode = byId.get(rp);
  console.log('  → 文本组与图片组是【不同】容器 ✓  同一父容器=' +
    (lNode.parent === rNode.parent ? '是 ' + lNode.parent : '否'));
  console.log('  → 文本组 z=' + lNode.z + ' / 图片组 z=' + rNode.z + '（真机：后创建者 z 更大 = 更靠上）');
} else {
  console.log('  ✗ 文本与图片还在同一个容器里');
}

// ---- 判定 ----
const okStruct = lp && rp && lp !== rp && byId.get(lp).parent === byId.get(rp).parent;
console.log(okStruct
  ? '\n结论: 文字组与图片组已分离且同属一个图层容器 ✅'
  : '\n结论: 层级结构不符合「两层容器」约定 ❌');
process.exitCode = okStruct ? 0 : 1;
