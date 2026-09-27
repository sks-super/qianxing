// _probe_menu.mjs — 临时探针：dump 选关面板打开后的节点层级与色值
import { loadWebSession } from './_webclient.mjs';

const { api } = loadWebSession('cli');
const call = (a, args = {}) => api('play', { action: a, args });

await api('load-archive', { path: '_simulator/TickHop.web.save.json' });
await call('start', { canvasId: 'mobile-16-9' });
for (let i = 0; i < 80; i++) await call('step', { dt: 1 / 30 });

await call('key', { key: 'KeyboardCraftspersonKey21Down' });
for (let i = 0; i < 4; i++) await call('step', { dt: 1 / 30 });

const s = await call('get', { view: true, sceneRev: 0, compact: true });
const ns = (s && s.scene && s.scene.nodes) || [];
console.log('节点总数:', ns.length);

const hex = (v) => '0x' + ((Number(v) || 0) >>> 0).toString(16).padStart(8, '0');
const byId = new Map(ns.map((n) => [n.id, n]));

// 找出「菜单容器」：持有大量子节点、且子节点里含标题文本的容器
const menu = ns.find((n) => n.kind === 'container'
  && (ns.filter((c) => c.parent === n.id).length >= 8));
console.log('疑似菜单容器 id =', menu && menu.id,
  '  子节点数 =', menu ? ns.filter((c) => c.parent === menu.id).length : 0);

console.log('\n--- 菜单容器子节点（按 z 升序）---');
if (menu) {
  const kids = ns.filter((c) => c.parent === menu.id).sort((a, b) => a.z - b.z);
  for (const k of kids) {
    console.log(`  z=${String(k.z).padStart(2)} id=${String(k.id).padStart(3)} ${k.kind.padEnd(8)} `
      + `color=${hex(k.color)} font=${hex(k.fontColor)} `
      + `${k.sourceWidth}x${k.sourceHeight} @(${Math.round(k.matrix.tx)},${Math.round(k.matrix.ty)}) `
      + `text=${JSON.stringify(k.text || '')}`);
  }
}

console.log('\n--- 全部 image 节点 ---');
for (const n of ns.filter((x) => x.kind === 'image')) {
  console.log(`  id=${String(n.id).padStart(3)} parent=${String(n.parent).padStart(3)} z=${String(n.z).padStart(2)} `
    + `color=${hex(n.color)} ${n.sourceWidth}x${n.sourceHeight} @(${Math.round(n.matrix.tx)},${Math.round(n.matrix.ty)})`);
}
await call('stop', {});
