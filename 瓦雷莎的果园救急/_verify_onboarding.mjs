// _verify_onboarding.mjs — 「谁该看教程」的验收（老玩家不再被拦一次）
//
// 需求（用户原话）：
//   ① 当最新通关关卡不是 0 的时候，序章教程**重进后不应该显示**；
//   ② 已通关的关卡，教程再次进入**也不应该显示**。
//
// 四段：
//   ① 新玩家（收不到存档）        → 首屏弹序章
//   ② 老玩家（存档 = 6，一开始就到）→ 不弹序章，也不点亮「进入果园」
//   ③ 老玩家但存档来得晚          → 已经弹出来的序章要收掉（不能闪一下留着）
//   ④ 存档 = 1：进第 1 片（已通关）不弹本课；回地图再进第 2 片（未通关）照弹
//
// 用法：cd E:/千星/千星游戏 && node 瓦雷莎的果园救急/_verify_onboarding.mjs
// 退出码 0 = 全过；1 = 有失败项

import { loadWebSession } from '../_tools/_webclient.mjs';

const ARCHIVE = '_simulator/瓦雷莎的果园救急.web.save.json';
const SAVE = '服客同步存档信息';
const SELECT = '服客进入选关';

const { api } = loadWebSession('cli');   // ★ 固定 session（模拟器会话槽只有 8 个）
const call = (a, args = {}) => api('play', { action: a, args });
const stepN = async (n) => { for (let i = 0; i < n; i++) await call('step', { dt: 1 / 30 }); };

const fails = [];
const ok = (cond, name, detail) => {
  console.log(`${cond ? '  ✅' : '  ❌'} ${name}${detail ? ' — ' + detail : ''}`);
  if (!cond) fails.push(name);
};

/** 重新起一局（同一 session 内重载存档 → start） */
async function fresh(steps = 40) {
  await api('load-archive', { path: ARCHIVE });
  await call('start', { canvasId: 'mobile-16-9' });
  await stepN(steps);
}

async function texts() {
  const s = await call('get', { view: true, sceneRev: 0, compact: true });
  return (s?.scene?.nodes || []).filter((n) => n.kind === 'textbox' && n.text).map((n) => n.text);
}
const hasPrologue = (list) => list.some((t) => (t || '').includes('序章'));
const hasGuideBtns = (list) => list.some((t) => /^(关闭|下一页 →|知道了)$/.test((t || '').trim()));
const hasEnterGuide = (list) => list.some((t) => (t || '') === '点这里开始救援');
const pager = (list) => list.find((t) => /^\d+\s*\/\s*\d+$/.test((t || '').trim()));

// ---------------------------------------------------------------
console.log('=== ① 新玩家（节点图没发存档）：首屏弹序章 ===');
{
  await fresh();
  const tx = await texts();
  ok(hasPrologue(tx), '序章弹出来了', pager(tx) || '(没有页码)');
  ok((pager(tx) || '').trim() === '1 / 2', '停在序章第 1 页');
}

// ---------------------------------------------------------------
console.log('=== ② 老玩家（已通关到第 6 片）：不弹序章、不点亮「进入果园」===');
{
  await fresh(1);                                        // 只走 1 帧，赶在决策前把存档发过去
  await call('serverSend', { target: 'PlayerSelf', name: SAVE, params: [6] });
  await stepN(60);
  const tx = await texts();
  ok(!hasPrologue(tx), '没有弹序章', hasPrologue(tx) ? '仍看到序章' : '');
  ok(!hasGuideBtns(tx), '没有教程面板', hasGuideBtns(tx) ? '仍看到教程按钮' : '');
  ok(!hasEnterGuide(tx), '没有「点这里开始救援」引导（老玩家不需要）');
  ok(tx.some((t) => (t || '').includes('进入果园 07')), '光标直接对齐刚解锁的第 7 片',
    tx.find((t) => (t || '').startsWith('进入果园')) || '(没有按钮)');
  ok(tx.some((t) => (t || '').includes('已还原 6 / 50')), '进度条已按存档灌入');
}

// ---------------------------------------------------------------
console.log('=== ③ 老玩家但存档来晚了：先弹出来的序章要收掉 ===');
{
  await fresh();                                         // 等过 0.6s 的等待窗口 → 序章已弹
  const before = await texts();
  ok(hasPrologue(before), '存档没到时先按新玩家处理（弹了序章）', pager(before) || '');
  await call('serverSend', { target: 'PlayerSelf', name: SAVE, params: [6] });
  await stepN(30);
  const after = await texts();
  ok(!hasPrologue(after), '存档到了之后序章被收掉');
  ok(!hasEnterGuide(after), '也没顺手点亮「点这里开始救援」',
    hasEnterGuide(after) ? '引导漏出来了' : '');
}

// ---------------------------------------------------------------
console.log('=== ④ 已通关的关卡不弹本课；未通关的照弹 ===');
{
  await fresh(1);
  await call('serverSend', { target: 'PlayerSelf', name: SAVE, params: [1] });   // 通关到第 1 片 → 解锁到 2
  await stepN(40);
  let tx = await texts();
  ok((tx.find((t) => (t || '').startsWith('进入果园')) || '').includes('02'), '光标对齐第 2 片',
    tx.find((t) => (t || '').startsWith('进入果园')) || '');

  // 往左挪到第 1 片（已通关）再进
  await call('key', { key: 'KeyboardMoveLeftKeyDown' });
  await stepN(10);
  await call('key', { key: 'KeyboardJumpKeyDown' });      // 空格：进第 1 片
  await stepN(90);
  tx = await texts();
  ok(!hasGuideBtns(tx), '重进已通关的第 1 片：不再弹第 1 课', tx.join(' | ') || '(无文字)');

  // 回地图 → 往右挪到第 2 片（未通关，有第 2 课）→ 进
  //   ★ 回地图时光标停在「上次选的那一片」（= 1），所以要显式往右挪一格
  await call('serverSend', { target: 'PlayerSelf', name: SELECT, params: [] });
  await stepN(90);
  await call('key', { key: 'KeyboardMoveRightKeyDown' });
  await stepN(10);
  await call('key', { key: 'KeyboardJumpKeyDown' });
  await stepN(90);
  tx = await texts();
  ok(hasGuideBtns(tx), '进未通关的第 2 片：第 2 课照弹', tx.join(' | ') || '(无文字)');
  ok(tx.some((t) => (t || '').includes('第 2 课')), '摊开的确实是第 2 课',
    tx.find((t) => (t || '').includes('第 2 课')) || '(没有)');
}

console.log(fails.length ? `\n失败 ${fails.length} 项` : '\n全部通过');
process.exit(fails.length ? 1 : 0);
