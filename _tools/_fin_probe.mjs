// _fin_probe.mjs — 打印通关演出某一帧的场景节点概况（排查渲染缺内容）
import { pathToFileURL } from 'node:url';
import { loadWebSession } from './_webclient.mjs';

const argv = process.argv.slice(2);
const opt = (n, d) => { const i = argv.indexOf('--' + n); return i >= 0 && argv[i + 1] ? argv[i + 1] : d; };
const ARCHIVE = opt('archive', '_simulator/_finale.web.save.json');
const FRAME = parseInt(opt('frame', '700'), 10);

const { api } = loadWebSession('finale');
const call = (a, args = {}) => api('play', { action: a, args });

await api('load-archive', { path: ARCHIVE });
await call('start', { canvasId: 'mobile-16-9' });
let frame = 0;
while (frame < FRAME) { await call('step', { dt: 1 / 30 }); frame++; }

const st = await call('get', { view: true, sceneRev: 0, compact: true });
const nodes = (st && st.scene && st.scene.nodes) || [];
console.log('总节点', nodes.length);
const byId = new Map(nodes.map((n) => [n.id, n]));
const root = nodes.find((n) => n.parent === null) || nodes[0];

const kids = new Map();
for (const n of nodes) {
  if (n.parent === null || n.parent === undefined) continue;
  if (!kids.has(n.parent)) kids.set(n.parent, []);
  kids.get(n.parent).push(n);
}
function dump(id, depth) {
  for (const k of (kids.get(id) || [])) {
    const m = k.matrix || {};
    console.log(`${'  '.repeat(depth)}id=${k.id} kind=${k.kind} name=${k.name || '-'} tx=${(m.tx||0).toFixed(0)} ty=${(m.ty||0).toFixed(0)} a=${(m.a||1).toFixed(2)} d=${(m.d||1).toFixed(2)} sw=${k.sourceWidth||0} sh=${k.sourceHeight||0} col=${k.imageColor!==undefined?k.imageColor.toString(16):'-'} vis=${k.visible!==false} kids=${(kids.get(k.id)||[]).length}`);
    if (depth < 3) dump(k.id, depth + 1);
  }
}
dump(root.id, 0);
await call('stop', {});
process.exit(0);
