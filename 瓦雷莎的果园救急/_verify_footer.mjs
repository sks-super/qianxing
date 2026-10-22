// _verify_footer.mjs — 校验「底部操作方法常驻」+「副标题不再有『小果龙待命』」
//
// 做法：载入试玩存档 → 起播 → 读一次文案 → 点一个【未解锁】的果园 → 再读一次。
//       期望：点锁定果园前后，底部提示条文字不变，副标题不含「待命」。
//
// 用法：node 瓦雷莎的果园救急/_verify_footer.mjs
// 退出码 0 = 全部通过；1 = 有失败项。

import { loadWebSession } from '../_tools/_webclient.mjs';

const ARCHIVE = '_simulator/瓦雷莎的果园救急.web.save.json';
const HINT = '拖动地图 · 点果实进入 · ← → 换果园 · 空格开始 · H 教程';

const { api } = loadWebSession('cli');
const call = (a, args = {}) => api('play', { action: a, args });
const stepN = async (n) => { for (let i = 0; i < n; i++) await call('step', { dt: 1 / 30 }); };

async function texts() {
  const st = await call('get', { view: true, sceneRev: 0, compact: true });
  const nodes = st?.scene?.nodes || [];
  const list = nodes.filter((n) => n.kind === 'textbox').map((n) => n.text || '');
  return {
    footer: list.find((s) => s.includes('拖动地图')) || '',
    lockedMsg: list.find((s) => s.includes('还锁着')) || '',
    subtitle: list.find((s) => s.includes('已还原')) || '',
    all: list,
  };
}

const fails = [];
const check = (ok, name, detail) => {
  console.log(`${ok ? '  ✅' : '  ❌'} ${name}${detail ? ' — ' + detail : ''}`);
  if (!ok) fails.push(name);
};

await api('load-archive', { path: ARCHIVE });
await call('start', { canvasId: 'mobile-16-9' });
await stepN(40);
// ★ 首屏会自动弹序章：先关掉，否则点击会落在遮罩上（而且地图被挡着看不见）
await call('key', { key: 'KeyboardCraftspersonKey21Down' });
await stepN(12);

const before = await texts();
console.log('=== 初始画面 ===');
console.log('  底部提示：', JSON.stringify(before.footer));
console.log('  副标题　：', JSON.stringify(before.subtitle));

check(before.footer === HINT, '初始底部就是操作方法全文');
check(before.subtitle.includes('已还原') && !before.subtitle.includes('待命'),
  '副标题已去掉「小果龙待命」', before.subtitle);

// 点第 3 片果园（未解锁）：1280×720 下节点 03 约在 (940, 250)，指针 y 轴向上要翻转
await call('pointer', { x: 940, y: 720 - 250, type: 'click' });
await stepN(40);

const after = await texts();
console.log('=== 点未解锁果园之后 ===');
console.log('  底部提示：', JSON.stringify(after.footer));
console.log('  锁定红字：', JSON.stringify(after.lockedMsg || '(无)'));

check(after.footer === HINT, '点未解锁果园后，底部仍是操作方法');
check(!after.lockedMsg, '「这片果园还锁着 —— 先把前面的果园还原了」已不再出现');

// 再来一次刷新（换一片果园）确认不会被顶掉
await call('pointer', { x: 80, y: 720 - 300, type: 'click' });   // 左箭头
await stepN(40);
const after2 = await texts();
check(after2.footer === HINT, '换果园后，底部仍是操作方法', JSON.stringify(after2.footer));

console.log(fails.length ? `\n失败 ${fails.length} 项` : '\n全部通过');
process.exit(fails.length ? 1 : 0);
