// verify_menu.mjs — 在 Web 模拟器里端到端验证「选关 / 通关 / 失败」三套面板
//
// 判定依据：隐藏的控件不会出现在 scene.nodes 里（渲染器只收集 active 节点），
//          所以「面板是否打开」= 面板专属文本是否出现在场景中。
//
// 用法：
//   node _tools/verify_menu.mjs                 # 用默认 Web 存档
//   node _tools/verify_menu.mjs --archive x.json
//
// 前置：Web 服务已在跑，且 _simulator/TickHop.web.save.json 是最新（dev_open.mjs 会自动重建）

import { loadWebSession } from './_webclient.mjs';

const argv = process.argv.slice(2);
const opt = (n, d) => { const i = argv.indexOf('--' + n); return i >= 0 && argv[i + 1] ? argv[i + 1] : d; };

const ARCHIVE = opt('archive', '_simulator/TickHop.web.save.json');
const CANVAS = opt('canvas', 'mobile-16-9');
const { api, BASE } = loadWebSession('cli');

const call = (action, args = {}) => api('play', { action, args });
const stepN = async (n) => { for (let i = 0; i < n; i++) await call('step', { dt: 1 / 30 }); };
const snap = () => call('get', { view: true, sceneRev: 0, compact: true });
const nodesOf = (s) => (s && s.scene && s.scene.nodes) || [];
const textsOf = (s) => nodesOf(s).filter((n) => n.text).map((n) => n.text);
const has = (arr, sub) => arr.some((t) => String(t).includes(sub));
const hasExact = (arr, v) => arr.some((t) => String(t) === v);
// 倒计时文本形如 "8.40"
const timerOf = (s) => {
  const n = nodesOf(s).find((x) => /^\d+\.\d\d$/.test(String(x.text || '')));
  return n ? parseFloat(n.text) : null;
};

let fails = 0;
const check = (label, ok, extra = '') => {
  console.log(`  ${ok ? '✅' : '❌'} ${label}${extra ? `   ${extra}` : ''}`);
  if (!ok) fails++;
};
const section = (n, title) => console.log(`\n[${n}] ${title}`);

try {
  console.log(`服务 ${BASE}  ·  存档 ${ARCHIVE}`);
  await api('load-archive', { path: ARCHIVE });
  await call('start', { canvasId: CANVAS });
  await stepN(70);                       // 黑幕散尽 + 关卡构建完成

  // ---------- 1) 初始态 ----------
  let s = await snap();
  let t = textsOf(s);
  section(1, `关卡就绪   文本=${JSON.stringify(t)}`);
  check('第01关的提示文本在', has(t, '门'));
  check('菜单初始不可见', !has(t, '选择关卡') && !has(t, '重玩本关'));
  check('触屏「选关」入口常驻', hasExact(t, '关'));
  check('倒计时在走', timerOf(s) !== null && timerOf(s) < 10, `剩余 ${timerOf(s)}s`);

  // ---------- 2) L 键打开选关面板 ----------
  await call('key', { key: 'KeyboardCraftspersonKey21Down' });
  await stepN(4);
  s = await snap(); t = textsOf(s);
  section(2, `按 L 打开选关   文本=${JSON.stringify(t)}`);
  check('标题「选择关卡」出现', has(t, '选择关卡'));
  check('副标题含关数统计', has(t, '已通关'));
  check('三关卡片都在', has(t, '第01关') && has(t, '第02关') && has(t, '第03关'));
  check('底部按钮「继续游戏 / 重玩本关」', has(t, '继续游戏') && has(t, '重玩本关'));
  check('操作提示含「空格进入」', has(t, '空格进入'));

  const timerOpen = timerOf(s);
  await stepN(30);                        // 面板打开时应冻结计时
  const timerAfter = timerOf(await snap());
  check('面板打开时计时已冻结', timerOpen === timerAfter, `${timerOpen} → ${timerAfter}`);

  // ---------- 3) 再按 L 关闭 ----------
  await call('key', { key: 'KeyboardCraftspersonKey21Down' });
  await stepN(4);
  t = textsOf(await snap());
  section(3, `再按 L 关闭   文本=${JSON.stringify(t)}`);
  check('面板已收起', !has(t, '选择关卡'));
  check('回到关卡画面', has(t, '门'));

  // ---------- 4) 等倒计时归零 → 失败面板 ----------
  await stepN(330);                       // 10s 关卡 + 余量
  s = await snap(); t = textsOf(s);
  section(4, `时间耗尽   文本=${JSON.stringify(t)}`);
  check('失败面板自动弹出（标题「时间到！」）', has(t, '时间到'));
  check('失败面板按钮齐全', has(t, '重玩本关') && has(t, '返回选关'));

  // ---------- 5) 按 R 重玩本关 ----------
  await call('key', { key: 'KeyboardCharacterSkill3KeyDown' });
  await stepN(80);                        // 黑幕往返 + 关卡重建
  s = await snap(); t = textsOf(s);
  section(5, `按 R 重玩   文本=${JSON.stringify(t)}`);
  check('失败面板已收起', !has(t, '时间到'));
  check('回到第01关', has(t, '门'));
  check('倒计时已重置', (timerOf(s) || 0) > 8, `剩余 ${timerOf(s)}s`);

  // ---------- 6) 一路向右走进门 → 通关面板 ----------
  await call('key', { key: 'KeyboardMoveRightKeyDown' });
  await stepN(140);
  s = await snap(); t = textsOf(s);
  section(6, `走到终点   文本=${JSON.stringify(t)}`);
  check('通关面板自动弹出（标题「关卡完成！」）', has(t, '关卡完成'));
  check('显示剩余时间', has(t, '剩余'));
  check('按钮「重玩本关 / 下一关」', has(t, '重玩本关') && has(t, '下一关'));

  // ---------- 7) 按 T 进入下一关 ----------
  await call('key', { key: 'KeyboardCharacterSkill4KeyDown' });
  await stepN(90);
  s = await snap(); t = textsOf(s);
  section(7, `按 T 下一关   文本=${JSON.stringify(t)}`);
  check('通关面板已收起', !has(t, '关卡完成'));
  check('已切到第02关', has(t, '右上角高台'), JSON.stringify(t));

  // ---------- 8) 选关面板应记下第01关已通关 ----------
  await call('key', { key: 'KeyboardCraftspersonKey21Down' });
  await stepN(4);
  t = textsOf(await snap());
  section(8, `查看选关进度   文本=${JSON.stringify(t)}`);
  check('第01关带通关标记', has(t, '第01关 √'), JSON.stringify(t));
  check('第02关卡片仍在', has(t, '第02关'));

  await call('stop', {});
  console.log(`\n${fails === 0 ? '✅ 全部通过' : `❌ ${fails} 项未通过`}`);
  process.exit(fails === 0 ? 0 : 1);
} catch (e) {
  console.error('\n✗ 验证中断: ' + (e && e.message ? e.message : e));
  process.exit(1);
}
