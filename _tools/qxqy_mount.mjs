// qxqy_mount.mjs — 把一个千星 Lua 游戏工程整体灌入模拟器并试玩
//
// 用法：
//   node qxqy_mount.mjs --game TickHop [--entry game.lua] [--mount n1]
//                       [--save _simulator/tickhop.save.json] [--steps 2] [--signal 名称] [--signal-str 值]
//
// 说明：
//   --game   工作区下的游戏目录名（如 TickHop / 割绳子）
//   --entry  入口脚本文件名，会被挂载到控件上（其余脚本仅作为 require 模块注册）
//   --mount  挂载目标控件 id（默认自动挑选第一个可用客户端容器）
//   --save   可选，失焦保存到工作区相对路径
//   --steps  试玩推进的帧数（每帧 1/30 秒）
//   --signal / --signal-str  试玩启动后模拟服务器下发一个客户端信号（验证入站通道）
//   --key <Enum.KeyEventType 名>  [--key-at 帧号]  可重复；在第 N 帧注入按键事件
//                              （例：--key KeyboardMoveRightKeyDown --key-at 20）
//   --probe-player <帧数>    逐帧打印玩家位姿，验证输入是否真的驱动了角色
//   --probe-walk <帧号> / --probe <帧号|start> / --probe-timeline <帧数>
//   --scene / --tree / --fix-zorder <帧> / --hide-bg <帧> / --stretch <帧>

import { spawn } from 'node:child_process';
import { mkdirSync, readdirSync, readFileSync, writeFileSync, statSync } from 'node:fs';
import path from 'node:path';
import { SIM_TEMPLATE_GUIDS, buildParamShim, buildZOrderFix, collectLua } from './_sim_common.mjs';

const MCP_ENTRY = process.env.QXQY_MCP_ENTRY
  || 'C:/Users/JingSu/.workbuddy/binaries/node/workspace/node_modules/beyond-simulator-mcp/dist/index.js';
const WORKSPACE = process.env.QXQY_WORKSPACE || 'E:/千星/千星游戏';
const OUTDIR = process.env.QXQY_OUTDIR || path.join(WORKSPACE, '_simulator', 'shots');

// ---------- 参数解析 ----------
const argv = process.argv.slice(2);
const opt = (name, dflt) => {
  const i = argv.indexOf('--' + name);
  return i >= 0 && argv[i + 1] ? argv[i + 1] : dflt;
};
const GAME = opt('game', 'TickHop');
const ENTRY = opt('entry', 'game.lua');
const MOUNT = opt('mount', '');
const SAVE = opt('save', '');
const STEPS = parseInt(opt('steps', '2'), 10);
const SIGNAL = opt('signal', '');
const SIGNAL_STR = opt('signal-str', '');
const OPEN = opt('open', '');          // 打开已有存档（相对工作区），默认新建空工程
const PRESET = opt('preset', '');      // sim = 使用 qxqy_simsave.mjs 生成的模板 guid
const PARAMS_RAW = opt('params', '');  // 额外/覆盖的脚本参数 JSON

// ---------- 试玩期按键注入（可重复 --key） ----------
// 传给引擎的就是 Enum.KeyEventType 的名字（如 KeyboardMoveRightKeyDown）；
// 运行时按名字精确匹配 AddKeyEventListener 注册的事件，因此这里也是
// 「网页端键盘桥」所依赖的同一条链路，可用来做端到端验证。
const KEYS = [];
for (let i = 0; i < argv.length; i++) {
  if (argv[i] === '--key' && argv[i + 1]) KEYS.push(argv[i + 1]);
}
const KEY_AT = parseInt(opt('key-at', String(Math.max(1, STEPS - 10))), 10);

// 模板 guid 与参数兜底的实现统一放在 _sim_common.mjs（与 qxqy_websave.mjs 共用）
let PARAMS = {};
if (PRESET === 'sim') PARAMS = { ...SIM_TEMPLATE_GUIDS };
if (PARAMS_RAW) Object.assign(PARAMS, JSON.parse(PARAMS_RAW));

// ---------- MCP 客户端 ----------
class McpClient {
  constructor() {
    this.child = spawn(process.execPath, [MCP_ENTRY, '--workspace', WORKSPACE], { stdio: ['pipe', 'pipe', 'pipe'] });
    this.buf = ''; this.pending = new Map(); this.stderr = ''; this.nextId = 1;
    this.child.stdout.on('data', d => this._onData(d));
    this.child.stderr.on('data', d => { this.stderr += d; });
  }
  _onData(d) {
    this.buf += d;
    let i;
    while ((i = this.buf.indexOf('\n')) >= 0) {
      const line = this.buf.slice(0, i).trim(); this.buf = this.buf.slice(i + 1);
      if (!line) continue;
      let msg; try { msg = JSON.parse(line); } catch { continue; }
      if (msg.id != null && this.pending.has(msg.id)) {
        const { resolve, reject } = this.pending.get(msg.id); this.pending.delete(msg.id);
        if (msg.error) reject(new Error(JSON.stringify(msg.error))); else resolve(msg.result);
      }
    }
  }
  request(method, params = {}) {
    const id = this.nextId++;
    return new Promise((resolve, reject) => {
      this.pending.set(id, { resolve, reject });
      this.child.stdin.write(JSON.stringify({ jsonrpc: '2.0', id, method, params }) + '\n');
      setTimeout(() => { if (this.pending.has(id)) { this.pending.delete(id); reject(new Error('timeout: ' + method)); } }, 90000);
    });
  }
  async init() {
    await this.request('initialize', { protocolVersion: '2025-06-18', capabilities: {}, clientInfo: { name: 'wb-qxqy-mount', version: '1' } });
    this.child.stdin.write(JSON.stringify({ jsonrpc: '2.0', method: 'notifications/initialized' }) + '\n');
  }
  async call(name, args) { return this.request('tools/call', { name, arguments: args || {} }); }
  close() { try { this.child.kill(); } catch { /* ignore */ } }
}

function textOf(result) {
  const parts = [];
  for (const c of (result && result.content) || []) {
    if (c.type === 'text') parts.push(c.text);
    else if (c.type === 'image') {
      mkdirSync(OUTDIR, { recursive: true });
      const file = path.join(OUTDIR, `shot_${new Date().toISOString().replace(/[:.]/g, '-')}.png`);
      writeFileSync(file, Buffer.from(c.data, 'base64'));
      parts.push(`[截图] ${file}`);
    }
  }
  return parts.join('\n');
}

// 脚本参数注入：见 _sim_common.mjs 的 buildParamShim（已 import）
// 结论回顾：覆写 script.GetParam 不行（Script metatable 禁止写字段），
// 改在入口脚本末尾覆盖工程自己的 getParamNumber 全局函数即可生效。

// ---------- 控件树探针 ----------
// 模拟器的 play get 不返回运行期控件树（tree/paint 恒为空），但引擎暴露了
// game.PrintClientUITree()，会把整棵树打进 logs。包一层 OnUpdate 在指定帧触发。
function buildTreeProbe(frame, atStart) {
  return `
-- ===== [SIM_PROBE] 第 ${frame} 帧转储控件树（由 _tools/qxqy_mount.mjs 注入） =====
do
    ${atStart ? 'pcall(function() game.PrintClientUITree() end)' : `
    local __simOrigOnUpdate = OnUpdate
    local __simFrame = 0
    OnUpdate = function(dt)
        if __simOrigOnUpdate then __simOrigOnUpdate(dt) end
        __simFrame = __simFrame + 1
        if __simFrame == ${frame} then
            pcall(function() game.PrintClientUITree() end)
        end
    end`}
end
-- ===== [/SIM_PROBE] =====
`;
}

// 详细遍历：PrintClientUITree 只有名字和类型，定位「平台为什么没渲染」需要
// active / visible / 坐标 / 尺寸 / 颜色，用 Control:GetChildren() 递归打印。
function buildWalkProbe(frame) {
  return `
-- ===== [SIM_WALK] 第 ${frame} 帧遍历控件属性（由 _tools/qxqy_mount.mjs 注入） =====
do
    local __walkFrame = 0
    local function __fmt(c, depth)
        local pad = string.rep("  ", depth)
        local seg = { pad .. tostring(c.name), "act=" .. tostring(c.active), "vis=" .. tostring(c.visible) }
        local okp, px, py = pcall(function() return c.anchoredPositionX, c.anchoredPositionY end)
        if okp then seg[#seg + 1] = "pos=(" .. tostring(px) .. "," .. tostring(py) .. ")" end
        local oks, sx, sy = pcall(function() return c.sizeDeltaX, c.sizeDeltaY end)
        if oks then seg[#seg + 1] = "size=(" .. tostring(sx) .. "," .. tostring(sy) .. ")" end
        local okc, col = pcall(function() return c.imageColor end)
        if okc and col ~= nil then seg[#seg + 1] = "color=" .. tostring(col) end
        printerr("[W] " .. table.concat(seg, " "))
        local okg, kids = pcall(function() return c:GetChildren() end)
        if okg and kids then
            for _, ch in ipairs(kids) do __fmt(ch, depth + 1) end
        end
    end
    local __origOnUpdate = OnUpdate
    OnUpdate = function(dt)
        if __origOnUpdate then __origOnUpdate(dt) end
        __walkFrame = __walkFrame + 1
        if __walkFrame == ${frame} then
            local root = script.object
            printerr("[W] ---- frame " .. tostring(__walkFrame) .. " root=" .. tostring(root ~= nil))
            if root then
                local ok, err = pcall(function() __fmt(root, 0) end)
                if not ok then printerr("[W] walk error: " .. tostring(err)) end
            end
        end
    end
end
-- ===== [/SIM_WALK] =====
`;
}

// 验证「子节点被父容器矩形裁剪」假设：把 7 个 1×1 容器撑大到全屏，看内容是否出现。
function buildStretch(frame, size) {
  return `
-- ===== [SIM_STRETCH] 第 ${frame} 帧把容器撑大到 ${size}（验证裁剪假设） =====
do
    local __stFrame = 0
    local __origOnUpdate = OnUpdate
    OnUpdate = function(dt)
        if __origOnUpdate then __origOnUpdate(dt) end
        __stFrame = __stFrame + 1
        if __stFrame == ${frame} then
            local keys = { "containerBg", "containerPlatform", "containerGoal", "containerPickup", "containerPlayer", "containerHud", "containerFade" }
            for _, k in ipairs(keys) do
                local c = state[k]
                if c then
                    local ok, err = pcall(function() c:SetSizeDelta(${size}, ${size}) end)
                    printerr("[S] stretch " .. k .. " ok=" .. tostring(ok) .. (ok and "" or (" err=" .. tostring(err))))
                end
            end
        end
    end
end
-- ===== [/SIM_STRETCH] =====
`;
}

// 逐帧时间线：每帧打印黑幕透明度与各容器子节点数，用来看「什么时候开始不对」。
function buildTimeline(maxFrame) {
  return `
-- ===== [SIM_TL] 逐帧时间线（由 _tools/qxqy_mount.mjs 注入） =====
do
    local __tlFrame = 0
    local function __alpha(c)
        if not c then return "-" end
        local ok, col = pcall(function() return c.imageColor end)
        if not ok or col == nil then return "?" end
        return tostring(math.floor(col / 16777216) % 256)
    end
    local function __kids(c)
        if not c then return -1 end
        local ok, k = pcall(function() return c:GetChildren() end)
        if not ok or not k then return -1 end
        return #k
    end
    local keys = { "containerBg", "containerPlatform", "containerGoal", "containerPickup", "containerPlayer", "containerHud", "containerFade" }
    local __origOnUpdate = OnUpdate
    OnUpdate = function(dt)
        if __origOnUpdate then __origOnUpdate(dt) end
        __tlFrame = __tlFrame + 1
        if __tlFrame <= ${maxFrame} then
            local seg = {}
            for _, k in ipairs(keys) do seg[#seg + 1] = k:sub(11) .. "=" .. __kids(state[k]) end
            local fade = state.containerFade
            local fc = nil
            if fade then
                local ok, k = pcall(function() return fade:GetChildren() end)
                if ok and k and k[1] then fc = k[1] end
            end
            printerr(string.format("[T] f=%d time=%s tick=%s pending=%s | %s | fade.act=%s fadeA=%s fadeChild.act=%s",
                __tlFrame, tostring(state.timeNow), tostring(state.timeTick), tostring(state.pendingStart),
                table.concat(seg, " "),
                tostring(fade and fade.active), __alpha(fc), tostring(fc and fc.active)))
        end
    end
end
-- ===== [/SIM_TL] =====
`;
}

// 玩家轨迹：每帧打印 state.player 的位置与速度，用来验证「按键是否真的驱动了角色」。
function buildPlayerProbe(maxFrame) {
  return `
-- ===== [SIM_PLAYER] 逐帧打印玩家位姿（由 _tools/qxqy_mount.mjs 注入） =====
do
    local __pFrame = 0
    local __origOnUpdate = OnUpdate
    OnUpdate = function(dt)
        if __origOnUpdate then __origOnUpdate(dt) end
        __pFrame = __pFrame + 1
        if __pFrame <= ${maxFrame} then
            local p = state.player
            if p then
                printerr(string.format("[P] f=%d x=%.1f y=%.1f vx=%.1f vy=%.1f ground=%s",
                    __pFrame, p.x, p.y, p.vx or 0, p.vy or 0, tostring(p.onGround)))
            else
                printerr("[P] f=" .. tostring(__pFrame) .. " player=nil")
            end
        end
    end
end
-- ===== [/SIM_PLAYER] =====
`;
}

// 反证用：在第 N 帧隐藏某个容器，看被它盖住的内容是否露出来。
function buildHide(frame, key) {
  return `
-- ===== [SIM_HIDE] 第 ${frame} 帧隐藏 ${key} =====
do
    local __hdFrame = 0
    local __origOnUpdate = OnUpdate
    OnUpdate = function(dt)
        if __origOnUpdate then __origOnUpdate(dt) end
        __hdFrame = __hdFrame + 1
        if __hdFrame == ${frame} then
            local c = state["${key}"]
            if c then pcall(function() c.visible = false end) end
            printerr("[H] hide ${key} ok=" .. tostring(c ~= nil))
        end
    end
end
-- ===== [/SIM_HIDE] =====
`;
}

// ---------- 层级顺序纠正（模拟器宿主渲染器 z 序相反） ----------
// 宿主截图渲染器（Bs/Us）按同级索引「降序」入队绘制，即索引越小越靠上，
// 与真实引擎（Unity 语义：后创建者在上）相反。后果：工程里第一个创建的
// 背景容器被画到最顶层，把平台/玩家/HUD 全部盖住，画面只剩一片背景色。
//
// 这里在模拟器内把 7 个容器的兄弟顺序倒过来，使「绘制顺序 = bg→fade」，
// 从而在截图里得到与真机一致的分层。只影响模拟器存档里的运行时顺序，
// 工程源码一行未动。
// buildZOrderFix 已移到 _sim_common.mjs（与 qxqy_websave.mjs 共用）

const PROBE_AT = opt('probe', '');
const PROBE_WALK = opt('probe-walk', '');
const PROBE_TL = opt('probe-timeline', '');
const PROBE_PLAYER = opt('probe-player', '');
const STRETCH_AT = opt('stretch', '');
const PARAM_SHIM = buildParamShim(PARAMS)
  + (PROBE_AT ? buildTreeProbe(parseInt(PROBE_AT, 10) || 0, PROBE_AT === 'start') : '')
  + (PROBE_WALK ? buildWalkProbe(parseInt(PROBE_WALK, 10) || 0) : '')
  + (PROBE_TL ? buildTimeline(parseInt(PROBE_TL, 10) || 0) : '')
  + (PROBE_PLAYER ? buildPlayerProbe(parseInt(PROBE_PLAYER, 10) || 0) : '')
  + (STRETCH_AT ? buildStretch(parseInt(STRETCH_AT, 10) || 0, opt('stretch-size', '4000')) : '')
  + (opt('hide-bg', '') ? buildHide(parseInt(opt('hide-bg', ''), 10) || 0, 'containerBg') : '')
  + (opt('fix-zorder', '') ? buildZOrderFix(parseInt(opt('fix-zorder', ''), 10) || 0) : '');

// collectLua 已移到 _sim_common.mjs（与 qxqy_websave.mjs 共用）

// ---------- 主流程 ----------
const log = (...a) => console.log(...a);
const client = new McpClient();
await client.init();

try {
  // 1) 新建工程 / 打开已有存档
  const opened = JSON.parse(textOf(await client.call('qxqy_project_open', OPEN ? { path: OPEN } : {})));
  const handle = opened.handle;
  log(`# 工程句柄 ${handle}，工作区 ${opened.workspace}${OPEN ? `，存档 ${OPEN}` : '（新建空工程）'}`);
  if (PARAM_SHIM) log(`# 注入脚本参数兜底: ${JSON.stringify(PARAMS)}`);

  // 2) 取快照，挑挂载目标
  let snap = JSON.parse(textOf(await client.call('qxqy_studio_get', { handle })));
  let revision = snap.version ?? snap.revision ?? 1;
  const flat = [];
  const walk = (nodes, depth) => (nodes || []).forEach(n => { flat.push({ ...n, depth }); walk(n.children, depth + 1); });
  walk(snap.tree, 0);
  log('# 控件候选: ' + flat.filter(n => n.kind !== 'server-container').map(n => `${n.id}(${n.kind})`).join(', '));

  let mountId = MOUNT;
  if (!mountId) {
    const cand = flat.find(n => n.kind === 'container') || flat.find(n => n.kind !== 'server-container');
    mountId = cand ? cand.id : '';
  }
  log(`# 挂载目标控件: ${mountId}`);

  // 3) 逐个灌入脚本
  const gameDir = path.join(WORKSPACE, GAME);
  const files = collectLua(gameDir);
  log(`# 待灌入 Lua: ${files.length} 个（${GAME}）`);

  for (const f of files) {
    // 关键：本工程的 Lua 用裸 require（require("config")），
    // 因此注册路径必须是裸文件名，才能被 require 解析到。
    const rel = f.name;
    const isEntry = f.name === ENTRY;
    // 入口脚本注入参数兜底，其余模块保持原样
    const source = isEntry && PARAM_SHIM ? f.source + PARAM_SHIM : f.source;
    const op = { op: 'addScript', path: rel, source, expectedRevision: revision };
    if (isEntry && mountId) { op.controlId = mountId; op.controlAsset = 'client'; }
    try {
      const r = JSON.parse(textOf(await client.call('qxqy_studio_patch', { handle, op })));
      revision = r.version ?? (revision + 1);
    } catch (e) {
      log(`  [挂入失败] ${rel}: ${e.message}`);
      // 挂载校验失败时退化为不挂载重试
      if (isEntry && mountId) {
        const r2 = JSON.parse(textOf(await client.call('qxqy_studio_patch', { handle, op: { op: 'addScript', path: rel, source, expectedRevision: revision } })));
        revision = r2.version ?? (revision + 1);
      }
    }
  }

  // 4) 保存
  if (SAVE) {
    const r = JSON.parse(textOf(await client.call('qxqy_project_save', { handle, path: SAVE })));
    log(`# 已保存: ${JSON.stringify(r)}`);
  }

  // 5) 试玩
  log('\n===== 启动试玩 =====');
  log(textOf(await client.call('qxqy_studio_play', { handle, action: 'start', args: { canvasId: 'mobile-16-9' } })));
  for (let i = 0; i < STEPS; i++) {
    const frame = i + 1;
    if (KEYS.length && frame === KEY_AT) {
      for (const k of KEYS) {
        await client.call('qxqy_studio_play', { handle, action: 'key', args: { key: k } });
      }
      log(`# 第 ${frame} 帧注入按键: ${KEYS.join(', ')}`);
    }
    await client.call('qxqy_studio_play', { handle, action: 'step', args: { dt: 1 / 30 } });
  }

  if (SIGNAL) {
    log(`\n===== 模拟服务器下发信号: ${SIGNAL} =====`);
    const params = SIGNAL_STR ? [SIGNAL_STR] : [];
    log(textOf(await client.call('qxqy_studio_play', { handle, action: 'serverSend', args: { target: 'PlayerSelf', name: SIGNAL, params } })));
    await client.call('qxqy_studio_play', { handle, action: 'step', args: { dt: 1 / 30 } });
  }

  log('\n===== 试玩状态 =====');
  const st = JSON.parse(textOf(await client.call('qxqy_studio_play', { handle, action: 'get' })));
  log(JSON.stringify({
    frame: st.frame, time: st.time, mountError: st.mountError,
    logs: (st.logs || []).map(l => (typeof l === 'string' ? l : (l.text || l.message || JSON.stringify(l)))),
  }, null, 2));

  // --scene: 转储截图渲染真正消费的 scene.nodes，排查「控件存在但没画出来」
  if (argv.includes('--scene')) {
    const sv = JSON.parse(textOf(await client.call('qxqy_studio_play', { handle, action: 'get', args: { view: true } })));
    const sc = sv.scene;
    log('\n===== scene =====');
    if (!sc) log('(scene 为 null)');
    else {
      const nodes = sc.nodes || [];
      log(`scene 键: ${Object.keys(sc).join(', ')} | nodes=${nodes.length}`);
      const byKind = {};
      for (const n of nodes) byKind[n.kind] = (byKind[n.kind] || 0) + 1;
      log('按 kind 统计: ' + JSON.stringify(byKind));
      for (const n of nodes.slice(0, 40)) {
        const m = n.matrix || {};
        log(`  id=${n.id} parent=${n.parent} kind=${n.kind} z=${n.z} m=(${m.a},${m.b},${m.c},${m.d},${m.tx},${m.ty}) src=${n.sourceWidth}x${n.sourceHeight}`);
      }
    }
  }

  // --tree: 转储运行期控件树，排查「节点没被创建 / 被隐藏 / 顺序不对」
  if (argv.includes('--tree')) {
    const lines = [];
    const paint = (n, d) => {
      const bits = [`${'  '.repeat(d)}${n.id ?? '?'} <${n.kind ?? n.type ?? '?'}>`];
      if (n.name) bits.push(`name=${n.name}`);
      if (n.active === false) bits.push('active=false');
      if (n.visible === false) bits.push('visible=false');
      if (n.sizeDeltaX != null) bits.push(`size=${Math.round(n.sizeDeltaX)}x${Math.round(n.sizeDeltaY)}`);
      if (n.imageColor != null) bits.push(`color=${n.imageColor}`);
      lines.push(bits.join(' '));
      for (const c of n.children || []) paint(c, d + 1);
    };
    lines.push('state 键: ' + Object.keys(st).join(', '));
    if ((st.tree || []).length) (st.tree || []).forEach((n) => paint(n, 0));
    else lines.push('(tree 为空) raw=' + JSON.stringify(st.tree ?? null).slice(0, 300));
    log('\n===== 控件树 =====\n' + lines.join('\n'));
    log('\npaint 条目: ' + (st.paint || []).length);
  }

  log('\n===== 试玩截图 =====');
  log(textOf(await client.call('qxqy_studio_play_screenshot', { handle })));

  await client.call('qxqy_studio_play', { handle, action: 'stop', args: {} });
} catch (e) {
  log('[FATAL] ' + e.message);
  if (client.stderr) log('--- stderr ---\n' + client.stderr.slice(0, 1500));
} finally {
  client.close();
}
