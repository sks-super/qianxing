// _verify_ui.mjs — 三项 UI 改动的无头验收
//   ① 教程示意图：所有黄/红方格必须完整落在「凹槽（圆角矩形）」内部，且留出边距
//   ② 游玩界面左上角：不能残留「第 01 片果园 / 难度 N 步 …」这类信息
//   ③ 地图底部提示常驻操作方法（回归）
//   ④ 序章删掉「怎么挑果园」那页后：关掉序章必须点亮「进入果园」按钮并引导点击
//
// 用法：node 瓦雷莎的果园救急/_verify_ui.mjs
// 退出码 0 = 全过；1 = 有失败项

import { loadWebSession } from '../_tools/_webclient.mjs';

const ARCHIVE = '_simulator/瓦雷莎的果园救急.web.save.json';
const HINT = '拖动地图 · 点果实进入 · ← → 换果园 · 空格开始 · H 教程';
const ENTER_GUIDE = '点这里开始救援';
// ★ 示意图两色（用户指定：黄 = 水果、红 = 果汁），取自 config 调色板 guideFruit / guideJuice
const HEX = { panelDeep: 'F6E7C8', guideFruit: 'F5B21F', guideJuice: 'DA3B2B' };
const argb = (hex) => (0xff000000 | parseInt(hex, 16)) >>> 0;

const { api } = loadWebSession('cli');
const call = (a, args = {}) => api('play', { action: a, args });
const stepN = async (n) => { for (let i = 0; i < n; i++) await call('step', { dt: 1 / 30 }); };

const fails = [];
const ok = (cond, name, detail) => {
  console.log(`${cond ? '  ✅' : '  ❌'} ${name}${detail ? ' — ' + detail : ''}`);
  if (!cond) fails.push(name);
};

async function snapshot() {
  const st = await call('get', { view: true, sceneRev: 0, compact: true });
  const nodes = st?.scene?.nodes || [];
  const root = nodes.find((n) => n.parent === null) || nodes[0] || {};
  const W = Math.round((root?.matrix?.tx || 640) * 2);
  const H = Math.round((root?.matrix?.ty || 360) * 2);
  const byId = new Map(nodes.map((n) => [n.id, n]));
  const mat = (n) => {
    const m = n.matrix || {};
    return { a: m.a ?? 1, b: m.b || 0, c: m.c || 0, d: m.d ?? 1, tx: m.tx || 0, ty: m.ty || 0 };
  };
  const absM = (n) => {
    const l = mat(n);
    const p = n.parent === null || n.parent === undefined ? null : byId.get(n.parent);
    if (!p) return { a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0 };
    const pm = absM(p);
    return {
      a: pm.a * l.a + pm.c * l.b, b: pm.b * l.a + pm.d * l.b,
      c: pm.a * l.c + pm.c * l.d, d: pm.b * l.c + pm.d * l.d,
      tx: pm.a * l.tx + pm.c * l.ty + pm.tx,
      ty: pm.b * l.tx + pm.d * l.ty + pm.ty,
    };
  };
  const rect = (n) => {
    const m = absM(n);
    const w = (n.sourceWidth || 0) * Math.abs(m.a || 1);
    const h = (n.sourceHeight || 0) * Math.abs(m.d || 1);
    return { x0: m.tx - w / 2, x1: m.tx + w / 2, y0: m.ty - h / 2, y1: m.ty + h / 2, w, h, cx: m.tx, cy: m.ty };
  };
  const texts = nodes.filter((n) => n.kind === 'textbox' && n.text).map((n) => ({ text: n.text, ...rect(n) }));
  const color = (hex) => nodes.filter((n) => n.kind === 'image' && (n.imageColor >>> 0) === argb(hex));
  return { nodes, W, H, rect, texts, color };
}

await api('load-archive', { path: ARCHIVE });
await call('start', { canvasId: 'mobile-16-9' });
await stepN(40);

// ---------------------------------------------------------------
console.log('=== ⓪ 序章：地图首屏自动展开（背景 + 你是谁，共 2 页）===');
{
  const s = await snapshot();
  const title = s.texts.find((t) => t.text.includes('序章'));
  ok(!!title, '首屏自动弹出序章', title?.text || '(没有)');
  const pager = s.texts.find((t) => /^\d+\s*\/\s*\d+$/.test(t.text.trim()));
  ok(pager?.text.trim() === '1 / 2', '序章共 2 页（「怎么挑果园」那页已删），停在第 1 页',
    pager?.text || '(没有页码)');
  ok(s.texts.some((t) => t.text.includes('闯祸')), '第 1 页讲的是小龙闯祸（背景）', '');
  ok(!s.texts.some((t) => t.text.includes('先挑一片果园')), '「怎么挑果园」那一页已删除');
}
// ★ 序章是「每次进游戏只弹一次」的，先关掉才能继续验后面的界面
await call('key', { key: 'KeyboardCraftspersonKey21Down' });    // L：关序章
await stepN(12);

// ---------------------------------------------------------------
console.log('=== ⓪b 序章关掉 → 点亮「进入果园」按钮并引导点击 ===');
{
  const s = await snapshot();
  const tip = s.texts.find((t) => t.text === ENTER_GUIDE);
  ok(!!tip, '出现「点这里开始救援」气泡', tip?.text || '(没有)');
  const btn = s.texts.find((t) => t.text.startsWith('进入果园'));
  ok(!!btn, '「进入果园」按钮仍在', btn?.text || '(没有)');
  if (tip && btn) {
    ok(Math.abs(tip.cx - btn.cx) < 4, '气泡与按钮同一条竖轴（正指着它）',
      `气泡 cx=${tip.cx.toFixed(1)} / 按钮 cx=${btn.cx.toFixed(1)}`);
    ok(tip.cy > btn.y1, '气泡在按钮上方', `气泡 cy=${tip.cy.toFixed(1)} / 按钮顶 ${btn.y1.toFixed(1)}`);
  }
  // 光圈：按钮四周应当有一圈 accent 色的细条（内圈 4 根 + 外圈 4 根）
  //   ★ 只认「细条」（横条的 sourceHeight / 竖条的 sourceWidth < 10），
  //     否则会把同样 accent 色的按钮面一起算进去；
  //   ★ imageColor 是 ARGB，光圈带透明度（alpha 200）→ 只比 RGB 三位；
  //   ★ 还要限定在按钮周围那一小片，别把地图里 accent 色的装饰算进来。
  const ACCENT_RGB = 0xe4572e;
  const nearBtn = (r) => Math.abs(r.cx - btn.cx) < 220 && Math.abs(r.cy - btn.cy) < 70;
  const bars = s.nodes.filter((n) => n.kind === 'image'
    && ((n.imageColor >>> 0) & 0xffffff) === ACCENT_RGB
    && ((n.sourceWidth || 0) < 10 || (n.sourceHeight || 0) < 10))
    .map(s.rect).filter(nearBtn);
  ok(bars.length >= 8, '按钮四周有 accent 光圈细条（≥8 根）', `${bars.length} 根`);
}

// ---------------------------------------------------------------
console.log('=== ① 地图首屏（回归）===');
{
  const s = await snapshot();
  const footer = s.texts.find((t) => t.text.includes('拖动地图'));
  const sub = s.texts.find((t) => t.text.includes('已还原'));
  ok(!!footer && footer.text === HINT, '底部是操作方法全文', footer?.text);
  ok(!!sub && !sub.text.includes('待命'), '副标题无「小果龙待命」', sub?.text);
}

// ---------------------------------------------------------------
console.log('=== ② 教程示意图：格子是否越出圆角矩形 ===');
await call('key', { key: 'KeyboardCharacterSkill2KeyDown' });   // H：打开图册（从序章开始）
await stepN(36);
{
  const first = await snapshot();
  const pager = first.texts.find((t) => /^\d+\s*\/\s*\d+$/.test(t.text.trim()));
  ok(pager?.text.trim() === '1 / 5', '图册 = 序章 2 页 + 第 1 课 3 页（存档只解锁到第 1 片）',
    pager?.text || '(没有页码)');
}
for (let i = 0; i < 2; i++) {                                   // →→：序章只有 2 页，翻 2 次就到第 1 课第 1 页
  await call('key', { key: 'KeyboardMoveRightKeyDown' });
  await stepN(12);
}
{
  const s = await snapshot();
  const pager = s.texts.find((t) => /^\d+\s*\/\s*\d+$/.test(t.text.trim()));
  ok(pager?.text.trim() === '3 / 5', '连按 2 次翻到第 1 课第 1 页', pager?.text || '(没有页码)');
  ok(s.texts.some((t) => t.text.includes('第 1 课')), '第 1 课开始讲「认果汁」',
    s.texts.find((t) => t.text.includes('第 1 课'))?.text || '');

  const stageParts = s.color(HEX.panelDeep).map(s.rect).filter((r) => r.cy > -100);  // 排掉「关闭」按钮面（同色，但 y 在 -250 附近）
  ok(stageParts.length > 0, '找到凹槽（panelDeep）', `${stageParts.length} 块拼片`);
  const stage = stageParts.reduce((a, r) => ({
    x0: Math.min(a.x0, r.x0), x1: Math.max(a.x1, r.x1),
    y0: Math.min(a.y0, r.y0), y1: Math.max(a.y1, r.y1),
  }), { x0: 1e9, x1: -1e9, y0: 1e9, y1: -1e9 });
  console.log(`     凹槽 rect: x ${stage.x0.toFixed(1)}..${stage.x1.toFixed(1)}  y ${stage.y0.toFixed(1)}..${stage.y1.toFixed(1)}`);

  const cells = [...s.color(HEX.guideFruit), ...s.color(HEX.guideJuice)]
    .map(s.rect)
    .filter((r) => r.w > 4 && r.w < 120);          // 排掉整屏遮罩类大块
  ok(cells.length >= 25, '找到示意图方格', `${cells.length} 个`);

  let worst = 1e9, worstCell = null;
  for (const r of cells) {
    const m = Math.min(r.x0 - stage.x0, stage.x1 - r.x1, r.y0 - stage.y0, stage.y1 - r.y1);
    if (m < worst) { worst = m; worstCell = r; }
  }
  console.log(`     最小边距 ${worst.toFixed(1)}px（方格 ${worstCell.w.toFixed(1)}×${worstCell.h.toFixed(1)}）`);
  ok(worst >= 8, '每个方格都在凹槽内部且留出 ≥8px 边距', `最小 ${worst.toFixed(1)}px`);

  // 网格整体居中：上下边距应当接近（差值 < 4px），左右同理
  const gx0 = Math.min(...cells.map((r) => r.x0)), gx1 = Math.max(...cells.map((r) => r.x1));
  const gy0 = Math.min(...cells.map((r) => r.y0)), gy1 = Math.max(...cells.map((r) => r.y1));
  const dTop = gy1 - stage.y1, dBot = stage.y0 - gy0;
  const dL = gx0 - stage.x0, dR = stage.x1 - gx1;
  console.log(`     边距 上${dTop.toFixed(1)} 下${dBot.toFixed(1)} 左${dL.toFixed(1)} 右${dR.toFixed(1)}`);
  ok(Math.abs(dTop - dBot) < 4 && Math.abs(dL - dR) < 4, '网格在凹槽里居中');
  ok(Math.min(dL, dR) >= 8, '左右也留出边距（不会被圆角切到）');
}

// ---------------------------------------------------------------
console.log('=== ③ 游玩界面：不能有任何常驻信息 / 按钮 ===');
await call('key', { key: 'KeyboardCraftspersonKey21Down' });    // L：关教程
await stepN(12);
await call('key', { key: 'KeyboardJumpKeyDown' });              // 空格：进第 1 片
await stepN(60);
{
  // 第 1 课必须是「多张图」：目标 → 操作 → 过关
  const s = await snapshot();
  const pager = s.texts.find((t) => /^\d+\s*\/\s*\d+$/.test(t.text.trim()));
  ok(pager?.text.trim() === '1 / 3', '第 1 课自动展开 3 页',
    pager?.text || '(没有页码)');
}
await call('key', { key: 'KeyboardCraftspersonKey21Down' });    // L：教程关会自动弹教学卡，先关掉
await stepN(210);                                               // 等 7s（进关兜底 4s 之后）
{
  const s = await snapshot();
  // ★ 判定标准：游玩态只剩 3D（节点图渲染，模拟器里看不到），
  //   客户端不应再画出任何文字 —— 按钮文字、果汁计数、关卡信息都算失败。
  const allTexts = s.texts.map((t) => t.text);
  ok(allTexts.length === 0, '游玩界面文字数为 0（无按钮 / 无果汁 / 无关卡信息）',
    allTexts.join(' | ') || '(无)');

  const BANNED = [/教程/, /回果园/, /果汁/, /第\s*\d+\s*片果园/, /难度/, /目标：/];
  const bad = allTexts.filter((t) => BANNED.some((re) => re.test(t)));
  ok(bad.length === 0, '没有「教程 / 回果园 / 还剩 N 格果汁」等残留', bad.join(' | ') || '(无)');

  // 也不该再有任何可点区域贴在四角（按钮的命中区已随按钮一起删除）
  const hits = s.nodes.filter((n) => n.kind === 'cursor');
  console.log(`     游玩界面纯光标控件数: ${hits.length}`);
}

// ---------------------------------------------------------------
console.log('=== ④ 返回地图只认服务器信号「服客进入选关」 ===');
{
  await call('serverSend', { target: 'PlayerSelf', name: '服客进入选关', params: [] });
  await stepN(60);
  const s = await snapshot();
  const footer = s.texts.find((t) => t.text.includes('拖动地图'));
  ok(!!footer, '收到信号后回到果园地图', footer?.text || '(没回去)');
  ok(!s.texts.some((t) => t.text === ENTER_GUIDE), '回到地图不会再冒出过期的引导气泡');
}

// ---------------------------------------------------------------
console.log('=== ⑤ 结算面板不受影响（它的按钮是「面板」的一部分，不是游玩 HUD）===');
{
  await call('serverSend', { target: 'PlayerSelf', name: '服客关卡胜利', params: [1] });
  await stepN(120);
  const s = await snapshot();
  const list = s.texts.map((t) => t.text);
  ok(list.some((t) => t.includes('这片果园救回来了')), '弹出结算标题');
  ok(list.some((t) => t.includes('回果园地图')), '结算里的「回果园地图」按钮仍在',
    list.join(' | '));
  const hudLeak = list.filter((t) => /还剩\s*\d+\s*格果汁|^教程$|^回果园$/.test(t));
  ok(hudLeak.length === 0, '结算时没有游玩 HUD 的按钮/果汁计数漏出来', hudLeak.join(' | ') || '(无)');
}

console.log(fails.length ? `\n失败 ${fails.length} 项` : '\n全部通过');
process.exit(fails.length ? 1 : 0);
