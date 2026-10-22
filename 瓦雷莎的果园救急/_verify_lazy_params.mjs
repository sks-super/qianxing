// _verify_lazy_params.mjs — 「客服关卡参数」发送时机验收
//
// 需求：教程关进关时**先不发**信号；玩家关掉教程、真正进入游玩界面后才发。
//
// 判定依据：服务器侧的 outbound 记录（客户端 → 服务器）
//   ① 刚进第 1 片（教程还开着）→ outbound 里没有「客服关卡参数」
//   ② 关掉教程之后            → 出现一条，第 1 参 = 1
//   ③ 重玩（不再弹教程）      → 立刻多一条，不需要再关教程
//   ④ 教程里直接回果园        → 不会补发上一关的参数
//
// 用法：node 瓦雷莎的果园救急/_verify_lazy_params.mjs
// 退出码 0 = 全过

import { loadWebSession } from '../_tools/_webclient.mjs';

const ARCHIVE = '_simulator/瓦雷莎的果园救急.web.save.json';
const SIG = '客服关卡参数';

const { api } = loadWebSession('cli');   // ★ 复用固定 session（模拟器会话槽只有 8 个，每次新 id 会耗尽）
const call = (a, args = {}) => api('play', { action: a, args });
const stepN = async (n) => { for (let i = 0; i < n; i++) await call('step', { dt: 1 / 30 }); };

const fails = [];
const ok = (cond, name, detail) => {
  console.log(`${cond ? '  ✅' : '  ❌'} ${name}${detail ? ' — ' + detail : ''}`);
  if (!cond) fails.push(name);
};

// 读服务器侧的「客户端 → 服务器」信号。
// ★ 本通道把它们记在 server.inbound（客服 = 客户端发给服务器）；
//   为兼容不同版本，outbound 也一起收。
// 参数是带类型的对象 { type, value }，这里统一拍平成 value。
async function outbound() {
  const st = await call('get', {});
  const srv = st?.server || {};
  const raw = [...(srv.inbound || []), ...(srv.outbound || [])];
  return raw.map((r) => ({
    name: r.name,
    params: (r.params || []).map((p) => (p && typeof p === 'object' && 'value' in p ? p.value : p)),
  }));
}
const levelSends = (list) => list.filter((r) => r.name === SIG);
const describe = (list) => list.length ? list.map((r) => `${r.name}(${(r.params || []).slice(0, 2).join(',')}…)`).join(' + ') : '(无)';

await api('load-archive', { path: ARCHIVE });
await call('start', { canvasId: 'mobile-16-9' });
await stepN(40);
// ★ 首屏会自动弹序章（见 game.lua OnStart）：先关掉，否则空格会被当成「翻页」
await call('key', { key: 'KeyboardCraftspersonKey21Down' });
await stepN(12);

// ---------------------------------------------------------------
console.log('=== ① 进第 1 片（教程关）：教程开着时不能发信号 ===');
await call('key', { key: 'KeyboardJumpKeyDown' });      // 空格：进选中的果园
await stepN(70);                                        // 等转场揭幕 + 教程自动弹出
{
  const s = await call('get', { view: true, sceneRev: 0, compact: true });
  const texts = (s?.scene?.nodes || []).filter((n) => n.kind === 'textbox').map((n) => n.text);
  const guideOpen = texts.some((t) => /关闭|下一页|知道了/.test(t || ''));
  ok(guideOpen, '教程已经摊开（说明确实处在教程关）', texts.slice(0, 3).join(' | '));

  const sends = levelSends(await outbound());
  ok(sends.length === 0, `教程开着时没有发「${SIG}」`, describe(sends));
}

// ---------------------------------------------------------------
console.log('=== ② 关掉教程（L）：此时才允许发 ===');
await call('key', { key: 'KeyboardCraftspersonKey21Down' });   // L：关闭教程
await stepN(30);
{
  const sends = levelSends(await outbound());
  ok(sends.length === 1, `关闭教程后发了一条「${SIG}」`, describe(sends));
  const p = sends[0]?.params || [];
  ok(Number(p[0]) === 1, '第 1 参 = 关卡序号 1', `实际 ${p[0]}`);
  ok(Number(p[1]) >= 1, '第 2 参 = 最小步数', `实际 ${p[1]}`);
  ok((p[2] || []).length >= 1, '第 3 参 = 点位序列非空', `${(p[2] || []).length} 项`);
  ok((p[3] || []).length === 30, '第 4 参 = 30 格状态数组', `${(p[3] || []).length} 项`);
}

// ---------------------------------------------------------------
console.log('=== ③ 重玩（不弹教程）：应当立刻再发一条 ===');
await call('key', { key: 'KeyboardCharacterSkill3KeyDown' });   // R：重玩
await stepN(40);
{
  const sends = levelSends(await outbound());
  ok(sends.length === 2, '重玩立刻补发（不需要再关教程）', describe(sends));
}

// ---------------------------------------------------------------
console.log('=== ④ 教程开着时直接回果园：不能补发参数 ===');
await call('key', { key: 'KeyboardCharacterSkill2KeyDown' });   // H：打开教程
await stepN(20);
const before = levelSends(await outbound()).length;
await call('serverSend', { target: 'PlayerSelf', name: '服客进入选关', params: [] });
await stepN(60);
{
  const after = levelSends(await outbound()).length;
  ok(after === before, '回地图没有多出「客服关卡参数」', `前 ${before} 条 → 后 ${after} 条`);
  const s = await call('get', { view: true, sceneRev: 0, compact: true });
  const texts = (s?.scene?.nodes || []).filter((n) => n.kind === 'textbox').map((n) => n.text);
  ok(texts.some((t) => (t || '').includes('拖动地图')), '已经回到果园地图');
}

// ---------------------------------------------------------------
console.log('=== ⑤ 非教程关（第 50 片）：没有教程挡着，应当当场发 ===');
{
  // ★ 新协议：只发 1 个整数「已通关最新关卡序号」。49 ⇒ 第 50 片刚解锁、可进。
  await call('serverSend', { target: 'PlayerSelf', name: '服客同步存档信息', params: [49] });
  await stepN(20);
  const before = levelSends(await outbound()).length;
  await call('key', { key: 'KeyboardJumpKeyDown' });   // 空格：进当前光标（同步存档后对齐到第 50 片）
  await stepN(80);
  const s = await call('get', { view: true, sceneRev: 0, compact: true });
  const texts = (s?.scene?.nodes || []).filter((n) => n.kind === 'textbox').map((n) => n.text || '');
  ok(!texts.some((t) => /关闭|下一页|知道了/.test(t)), '第 50 片没有弹教程');
  const sends = levelSends(await outbound());
  ok(sends.length === before + 1, '立刻发了一条，不用等关闭教程', `${before} → ${sends.length}`);
  ok(Number(sends[sends.length - 1]?.params?.[0]) === 50, '关卡序号 = 50',
    `实际 ${sends[sends.length - 1]?.params?.[0]}`);
}

console.log(fails.length ? `\n失败 ${fails.length} 项` : '\n全部通过');
process.exit(fails.length ? 1 : 0);
