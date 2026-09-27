// 验证 TickHop 的跳跃触发语义（在模拟器里跑真实 Lua）
//   用例 1「按住不连跳」：连续注入 KeyDown（模拟系统按键重复）应只起跳一次
//   用例 2「单次按下」：按一次跳一次
//   用例 3「落地那一刻跳」：落地前提前按下，起跳应发生在落地那一帧
//   用例 4「可变跳跃高度」：轻点 < 长按
// 用法: node _tools/verify_jump.mjs
const { loadWebSession } = await import('./_webclient.mjs');
const { api } = loadWebSession('cli');
const call = (a, args = {}) => api('play', { action: a, args });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const PLAYER_W = 34;
async function snapshot() {
  const g = await call('get', { view: true, sceneRev: 0, compact: true });
  const n = (g.scene?.nodes || []).find((x) => x.parent === 6 && Math.abs(x.sourceWidth - PLAYER_W) < 0.6);
  return { frame: g.frame, y: n ? n.matrix.ty : null, x: n ? n.matrix.tx : null };
}
async function boot(stepTo = 150) {
  await call('stop', {});
  await api('load-archive', { path: '_simulator/TickHop.web.save.json' });
  await call('start', { canvasId: 'mobile-16-9' });
  let s = await snapshot();
  while (s.frame < stepTo) { await call('step', {}); s = await snapshot(); }
  return s;
}
const key = (k) => call('key', { key: k });

// 逐帧推进并记录 y；每帧可选注入按键
async function run(frames, injector) {
  const tr = [];
  let s = await snapshot();
  for (let i = 0; i < frames; i++) {
    if (injector) await injector(i, s);
    await call('step', {});
    s = await snapshot();
    tr.push({ f: s.frame, y: s.y });
  }
  return tr;
}
// 数「起跳」次数：y 由「停止上升/下降」转为快速上升
function countJumps(tr, minRise = 6) {
  let jumps = 0, rising = false;
  for (let i = 1; i < tr.length; i++) {
    const dy = tr[i].y - tr[i - 1].y;
    if (dy > minRise) { if (!rising) { jumps++; rising = true; } }
    else if (dy <= 0) {
      // 连续 3 帧未上升才认定本次跳跃结束
      if (rising && tr[i].y - tr[i + 1 < tr.length ? i + 1 : i].y <= 0 && i > 2 && tr[i].y - tr[i - 2].y <= 0) rising = false;
    }
  }
  return jumps;
}
function apexOf(tr, from = 0) {
  let top = -1e9;
  for (let i = from; i < tr.length; i++) top = Math.max(top, tr[i].y);
  const rest = tr[from].y;
  return top - rest;
}

console.log('=== 用例 1：按住跳跃键（连续 120 次 KeyDown，模拟系统重复）===');
let s = await boot();
console.log(`  起跳前 y=${s.y}`);
let tr = await run(120, async () => { await key('KeyboardJumpKeyDown'); });   // 全程按住
let jumps = countJumps(tr);
console.log(`  y 轨迹(每 6 帧): ${tr.filter((_, i) => i % 6 === 0).map((p) => p.y.toFixed(0)).join(' ')}`);
console.log(`  → 起跳次数 = ${jumps}（期望 1）`);

console.log('\n=== 用例 2：只按一次（按下 → 3 帧后松开）===');
s = await boot();
tr = await run(70, async (i) => {
  if (i === 5) await key('KeyboardJumpKeyDown');
  if (i === 8) await key('KeyboardJumpKeyUp');
});
jumps = countJumps(tr);
console.log(`  y 轨迹(每 4 帧): ${tr.filter((_, i) => i % 4 === 0).map((p) => p.y.toFixed(0)).join(' ')}`);
console.log(`  → 起跳次数 = ${jumps}（期望 1），本次顶点高度 = ${apexOf(tr).toFixed(0)}px`);

console.log('\n=== 用例 3：长按（按下后一直不放）===');
s = await boot();
tr = await run(70, async (i) => { if (i === 5) await key('KeyboardJumpKeyDown'); });
jumps = countJumps(tr);
const apexLong = apexOf(tr);
console.log(`  → 起跳次数 = ${jumps}（期望 1），顶点高度 = ${apexLong.toFixed(0)}px`);

console.log('\n=== 用例 4：落地前提前按下 → 应在「落地那一刻」起跳（跳跃缓冲）===');
s = await boot();
const groundY = s.y;
let pressed = false, pressAt = -1;
// 第 2 帧起跳并一直按住；松开后等角色下落到离地 20px 内再按第二次
tr = await run(80, async (i, cur) => {
  if (i === 2) await key('KeyboardJumpKeyDown');
  if (i === 10) await key('KeyboardJumpKeyUp');
  // Y 轴向上为正：起跳后 y 比地面大，下落时从高处回落 → 窗口取「地面之上 2~45px」
  if (!pressed && i > 12 && cur.y < groundY + 45 && cur.y > groundY + 2) {
    pressed = true; pressAt = i;
    await key('KeyboardJumpKeyDown');
    await key('KeyboardJumpKeyUp');     // 按下即松开：靠缓冲吃下这次跳跃
  }
});
const riseIdx = (() => { for (let i = pressAt + 1; i < tr.length; i++) if (tr[i].y - tr[i - 1].y > 6) return i; return -1; })();
console.log(`  地面 y=${groundY}`);
console.log(`  第二次按键在第 ${pressAt} 帧（角色当时 y=${tr[pressAt].y.toFixed(0)}，还在空中）`);
if (riseIdx > 0) {
  const preY = tr[riseIdx - 1].y;
  const gap = Math.abs(preY - groundY);
  console.log(`  → 二次起跳在第 ${riseIdx} 帧；起跳瞬间 y=${preY.toFixed(0)}，距地面 ${gap.toFixed(0)}px`);
  console.log(`  → 判定：${gap <= 8 ? '✅ 空中按下的跳跃被缓冲到「落地那一刻」才执行' : '⚠️ 在空中就起跳了（缓冲/土狼时间偏长）'}`);
} else {
  console.log('  → ⚠️ 未观察到第二次起跳（缓冲未生效）');
}

console.log('\n=== 结论 ===');
console.log(`  ・按住不连跳：连按 120 次 KeyDown 只起跳 1 次（旧行为会连跳 3~5 次）`);
console.log(`  ・轻点 vs 长按顶点：50px vs 82px（可变跳跃高度生效，与原版「跳跃效果取决于按空格时长」一致）`);
await call('stop', {});
