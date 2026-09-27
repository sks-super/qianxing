// qxqy_webcheck.mjs — 命令行驱动 Web 模拟器试玩，验证「浏览器就绪」存档是否真的能跑
//
// 用途：
//   不开浏览器也能确认 Web 这条链路是否正常——载入存档 → 启动试玩 → 推进若干帧 →
//   打印运行日志与场景节点。场景里应出现游戏自己的容器（7 个）与控件；
//   若只有 container/textbox/button/textwindow/image 这几类零星节点，
//   说明脚本没执行（多半是入口脚本挂错了 asset，见 qxqy_websave.mjs 顶部说明）。
//
// 用法：
//   node _tools/qxqy_webcheck.mjs                              # 默认检查 TickHop
//   node _tools/qxqy_webcheck.mjs --archive _simulator/xx.json --frames 60
//
// 环境变量：
//   QXQY_WEB   Web 模拟器地址（默认 http://127.0.0.1:4173）

import { loadWebSession } from './_webclient.mjs';

const argv = process.argv.slice(2);
const opt = (name, dflt) => {
  const i = argv.indexOf('--' + name);
  return i >= 0 && argv[i + 1] ? argv[i + 1] : dflt;
};

const ARCHIVE = opt('archive', '_simulator/TickHop.web.save.json');
const FRAMES = parseInt(opt('frames', '45'), 10);
const CANVAS = opt('canvas', 'mobile-16-9');

// 注意：服务端每个不同的 sessionId 都会占一个会话槽（默认上限 8 个，无 CLI 开关可调），
// 所以命令行工具统一复用同一个 id，避免把槽位耗尽。
const { api } = loadWebSession(opt('sid', 'cli'));

console.log(`=== 1) 载入存档 ${ARCHIVE} ===`);
await api('load-archive', { path: ARCHIVE });
console.log('ok');

console.log('\n=== 2) 启动试玩 ===');
const started = await api('play', { action: 'start', args: { canvasId: CANVAS } });
console.log(JSON.stringify({
  running: started.running, frame: started.frame,
  canvas: `${started.canvasWidth}x${started.canvasHeight}`,
  mountError: started.mountError,
}));

let st = started;
while (st.frame < FRAMES) st = await api('play', { action: 'step', args: {} });
console.log(`推进到第 ${st.frame} 帧`);

console.log('\n=== 3) 运行日志 ===');
const g = await api('play', { action: 'get', args: { view: true, sceneRev: 0, compact: true } });
const logs = g?.logs || [];
if (!logs.length) console.log('（无日志）');
for (const l of logs.slice(-20)) {
  console.log('   ', typeof l === 'string' ? l : (l.text || l.message || JSON.stringify(l)));
}

console.log('\n=== 4) 场景节点 ===');
const sc = g?.scene;
if (!sc?.nodes?.length) {
  console.log('!! scene.nodes 为空 —— 没有任何控件被渲染');
  process.exitCode = 1;
} else {
  const byKind = {};
  for (const n of sc.nodes) byKind[n.kind] = (byKind[n.kind] || 0) + 1;
  const containers = sc.nodes.filter((n) => n.kind === 'container').length;
  console.log(`format=${sc.format} nodes=${sc.nodes.length} 根容器=${containers}`);
  console.log('kind 分布:', JSON.stringify(byKind));
  for (const n of sc.nodes.slice(0, 30)) {
    console.log(`   id=${n.id} ${String(n.kind).padEnd(10)} z=${n.z} parent=${n.parent} ` +
      `color=${n.imageColor ?? n.fontColor ?? ''} text=${JSON.stringify(n.text ?? '')}`);
  }
  // 判据：脚本跑起来后必然有倒计时文本（形如 "11.33"）。
  // 注意 scene 里不区分 container/image——容器节点的 kind 也会记成 image，
  // 所以不能靠数 container 来判断，认「倒计时文本」最稳。
  const hasTimer = sc.nodes.some((n) => /^\d+\.\d{2}$/.test(String(n.text || '')));
  const ok = hasTimer && (byKind.textbox || 0) >= 2;
  console.log(ok
    ? '\n结论: 脚本已执行，游戏控件正常渲染 ✅'
    : '\n结论: 画面里没有游戏内容（没找到倒计时文本），脚本很可能没跑起来 ❌');
  if (!ok) process.exitCode = 1;
}
