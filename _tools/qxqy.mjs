// qxqy.mjs — 千星沙箱模拟器（beyond-simulator-mcp）命令行驱动器
// 让 Agent 在 MCP 尚未被信任/接入前，直接通过 stdio 驱动模拟器。
//
// 用法：
//   node qxqy.mjs list
//   node qxqy.mjs call <toolName> '<jsonArgs>'
//   node qxqy.mjs run <script.json>      // 顺序执行 [{ "tool": "...", "args": {...} }, ...]
//
// 环境变量：
//   QXQY_WORKSPACE  工作区绝对路径（默认 E:/千星/千星游戏）
//   QXQY_OUTDIR     截图输出目录（默认工作区下 _simulator/shots）

import { spawn } from 'node:child_process';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';

const MCP_ENTRY = process.env.QXQY_MCP_ENTRY
  || 'C:/Users/JingSu/.workbuddy/binaries/node/workspace/node_modules/beyond-simulator-mcp/dist/index.js';
const WORKSPACE = process.env.QXQY_WORKSPACE || 'E:/千星/千星游戏';
const OUTDIR = process.env.QXQY_OUTDIR || path.join(WORKSPACE, '_simulator', 'shots');

// ---------- 极简 MCP stdio 客户端 ----------
class McpClient {
  constructor() {
    this.child = spawn(process.execPath, [MCP_ENTRY, '--workspace', WORKSPACE], { stdio: ['pipe', 'pipe', 'pipe'] });
    this.buf = '';
    this.pending = new Map();
    this.stderr = '';
    this.nextId = 1;
    this.child.stdout.on('data', d => this._onData(d));
    this.child.stderr.on('data', d => { this.stderr += d; });
  }

  _onData(d) {
    this.buf += d;
    let i;
    while ((i = this.buf.indexOf('\n')) >= 0) {
      const line = this.buf.slice(0, i).trim();
      this.buf = this.buf.slice(i + 1);
      if (!line) continue;
      let msg;
      try { msg = JSON.parse(line); } catch { continue; }
      if (msg.id != null && this.pending.has(msg.id)) {
        const { resolve, reject } = this.pending.get(msg.id);
        this.pending.delete(msg.id);
        if (msg.error) reject(new Error(JSON.stringify(msg.error)));
        else resolve(msg.result);
      }
    }
  }

  request(method, params = {}) {
    const id = this.nextId++;
    return new Promise((resolve, reject) => {
      this.pending.set(id, { resolve, reject });
      this.child.stdin.write(JSON.stringify({ jsonrpc: '2.0', id, method, params }) + '\n');
      setTimeout(() => {
        if (this.pending.has(id)) { this.pending.delete(id); reject(new Error('timeout: ' + method)); }
      }, 60000);
    });
  }

  async init() {
    await this.request('initialize', {
      protocolVersion: '2025-06-18',
      capabilities: {},
      clientInfo: { name: 'workbuddy-qxqy-driver', version: '1.0' },
    });
    this.child.stdin.write(JSON.stringify({ jsonrpc: '2.0', method: 'notifications/initialized' }) + '\n');
  }

  callTool(name, args) {
    return this.request('tools/call', { name, arguments: args || {} });
  }

  close() { try { this.child.kill(); } catch { /* ignore */ } }
}

// ---------- 输出处理 ----------
function renderResult(name, result) {
  const parts = [];
  for (const c of (result && result.content) || []) {
    if (c.type === 'text') parts.push(c.text);
    else if (c.type === 'image') {
      mkdirSync(OUTDIR, { recursive: true });
      const stamp = new Date().toISOString().replace(/[:.]/g, '-');
      const file = path.join(OUTDIR, `${name}_${stamp}.png`);
      writeFileSync(file, Buffer.from(c.data, 'base64'));
      parts.push(`[image saved] ${file} (${c.mimeType || 'image/png'})`);
    } else parts.push(`[${c.type}]`);
  }
  return parts.join('\n') || JSON.stringify(result);
}

// ---------- 主流程 ----------
const [cmd, ...rest] = process.argv.slice(2);
const client = new McpClient();
await client.init();

try {
  if (cmd === 'list') {
    const r = await client.request('tools/list', {});
    for (const t of r.tools || []) console.log('-', t.name);
  } else if (cmd === 'call') {
    const [tool, rawArgs] = rest;
    const args = rawArgs ? JSON.parse(rawArgs) : {};
    const r = await client.callTool(tool, args);
    console.log(renderResult(tool, r));
  } else if (cmd === 'run') {
    const script = JSON.parse(readFileSync(rest[0], 'utf8'));
    for (const step of script) {
      const label = step.label || step.tool;
      console.log('\n===== ' + label + ' =====');
      try {
        let args = step.args || {};
        if (typeof args === 'string') args = JSON.parse(args);
        const r = await client.callTool(step.tool, args);
        const txt = renderResult(step.tool, r);
        console.log(step.save ? txt.replace(/\[image saved\][^\n]*/g, '') : txt);
      } catch (e) {
        console.log('[ERROR] ' + e.message);
      }
    }
  } else {
    console.log('用法: node qxqy.mjs list | call <tool> \'<json>\' | run <script.json>');
  }
} finally {
  client.close();
}
