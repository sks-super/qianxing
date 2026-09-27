// _webclient.mjs — beyond-simulator-web 的极小 HTTP 客户端
//
// Web 模拟器的接口（见 beyond-simulator-web/dist/server.js）：
//   POST /editor/api/<action>   body: { sessionId, ...args }
//     action: get | archives | patch | export | play | load-archive | import | save ...
//   POST /api/open  { path }        打开工作区内的存档
//   POST /api/play  { action, args } 首页预览用的无 session 通道
//   GET  /api/state                 当前状态（archives / snapshot / play）
//
// sessionId 由编辑器前端生成并存在 sessionStorage['qxqy-editor-session']；
// 服务端是懒创建的——任意字符串都会新建一个 session 并自动载入 archives[0]。
// 所以命令行传一个自定义 id 即可独立操作，不影响浏览器里的会话。
//
// 注意：play 的 step 每次只推进 1 帧，推进 N 帧要循环调用 N 次。

export function loadWebSession(sessionId = 'cli') {
  const BASE = process.env.QXQY_WEB || 'http://127.0.0.1:4173';

  async function api(action, args = {}) {
    const res = await fetch(`${BASE}/editor/api/${action}`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ sessionId, ...args }),
    });
    const body = await res.json().catch(() => null);
    if (!res.ok || !body || body.ok !== true) {
      throw new Error(`${action} 失败: ${body?.error || `HTTP ${res.status}`}`);
    }
    return body.value;
  }

  async function state() {
    const res = await fetch(`${BASE}/api/state`);
    return (await res.json()).value;
  }

  return { BASE, sessionId, api, state };
}
