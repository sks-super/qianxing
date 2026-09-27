// _sim_common.mjs — 模拟器驱动脚本的共享定义
//
// 被 qxqy_mount.mjs（MCP 驱动）与 qxqy_websave.mjs（Web 存档生成）共同引用，
// 保证两边的模板 guid 与参数兜底写法永远一致。

import { readdirSync, readFileSync, statSync } from 'node:fs';
import path from 'node:path';

// 模拟器就绪存档里的模板 guid（与 qxqy_simsave.mjs 保持一致）
export const SIM_TEMPLATE_GUIDS = { rectPrefabId: 2000001, textPrefabId: 2000002 };

// Web 端的存档扫描标记：文件内容必须含这个子串才会出现在存档下拉里
// （见 beyond-simulator-web/dist/server.js 的 ia()：u.includes("qxqy-simulator-save")）
export const SAVE_MARKER = 'qxqy-simulator-save';

// 工程类型常量（与 studio/index.js 保持一致）
export const SERVER_ASSET = 'server-control-template';
export const CLIENT_ASSET = 'client-control-template';

// ---------- 试玩场景根 ----------
// ★ 关键：studio 的 playStart 是 startPlay(projects.server, { templatesProject: projects.client })，
//   即「场景根取自 server 工程，client 工程只当可实例化模板库」。
//   复刻 authoring.js 的 clientRoot()：server.root 是 server-container，
//   所以真正的场景根是它 children 里第一个 kind==='container' 的节点。
//
// ★ 脚本挂载的坑：resolveScriptTarget 在 controlAsset 为空时按 [server, client] 顺序
//   查同 id 节点，先命中 server。但若显式写 controlAsset='client-control-template'，
//   脚本会被挂到 client 的模板根上 —— 而模板根永远不会被实例化，脚本就永不执行，
//   试玩画面只剩 server 工程自带的脚手架。所以入口脚本必须挂 SERVER_ASSET。
export function sceneRootOf(serverProject) {
  const root = serverProject.root;
  if (root.kind === 'container') return root;
  return (root.children || []).find((c) => c.kind === 'container')
    || (root.children || [])[0] || root;
}

// ---------- 脚本参数兜底 ----------
// 模拟器的 params 链路是三处断开的：
//   studio 的 addScript 丢弃 op.params → compileProject 不带 params → mountSpecScripts 不转发，
// 于是 script:GetParam() / getParamNumber() 恒为 null。
//
// 尝试过的落点：
//   · 覆写 script.GetParam —— 不行。script 带 Script metatable，禁止写同名字段
//     （报 "cannot set GetParam, no such field"）。
//   · 覆写工程的 getParamNumber —— 可行。它是脚本环境里的普通全局函数，
//     在入口脚本「末尾」追加一段覆盖即可（OnStart 由引擎在 chunk 执行完后才调用，
//     所以此时覆盖已经生效）。
// 只在模拟器内注入，工程 .lua 源文件保持原样。
export function buildParamShim(params, origin = '_tools/qxqy_mount.mjs') {
  const keys = Object.keys(params || {});
  if (!keys.length) return '';
  const lines = keys
    .map((k) => `        [${JSON.stringify(k)}] = ${JSON.stringify(params[k])},`)
    .join('\n');
  return `
-- ===== [SIM_ONLY] 模拟器脚本参数兜底（由 ${origin} 注入，工程源文件未改动） =====
do
    local __simFallback = {
${lines}
    }
    if type(getParamNumber) == "function" then
        local __simOrig = getParamNumber
        getParamNumber = function(name, default)
            local v = __simOrig(name, default)
            if v == nil or v == 0 or v == default then
                local f = __simFallback[name]
                if f ~= nil then return f end
            end
            return v
        end
    end
end
-- ===== [/SIM_ONLY] =====
`;
}

// ---------- 容器层级修正（抵消模拟器渲染器的 z 序反置） ----------
// 宿主渲染器按「同级数组下标降序」绘制（下标越小越靠上、越晚画），而 Control.children
// 是创建顺序 push 的 → 最先创建的 containerBg 被画到最顶层，把平台/玩家/HUD 全盖住。
//
// 关键：模拟器里 `SetSiblingIndex(i)` 实际插到数组下标 `len-1-i`，但
// `SetAsFirstSibling()` / `SetAsLastSibling()` 两个便捷方法的效果**与真机一致**
// （first = 数组末尾 = 最先绘制 = 最底层；last = 数组下标 0 = 最后绘制 = 最顶层）。
// 所以这里全部用这两个方法，不直接碰 SetSiblingIndex。
//
// 依次把 8 个容器 SetAsFirstSibling（= 从顶层往底层排），最终数组顺序即
// [fade, menu, hud, player, pickup, goal, platform, bg]，绘制顺序随之变成
// bg → platform → … → hud → menu → fade，与真机一致。
//
// ⚠️ 只修容器还不够：**容器内部**同样反置。platform 容器里子节点顺序是
//    [平台1本体, 平台2本体, 平台2标签]，反置后标签被自己的平台本体压在最下面
//    （熄灭态本体 alpha=40 还能透出来，亮起态 alpha=255 就完全看不见数字了）。
//    真机里后创建的在上面，所以这里对每个平台标签 SetAsLastSibling() 补回来。
//    注意平台是在黑幕散尽后才建的（晚于容器），所以这一步必须**每帧幂等执行**，
//    不能只在修正帧做一次。
//
// 该段追加在入口脚本末尾，与工程共享同一个 chunk，因此能直接读到 game.lua 的
// local state；OnUpdate 是引擎调用的全局函数，覆写即生效。
export function buildZOrderFix(frame, origin = '_tools/qxqy_mount.mjs') {
  return `
-- ===== [SIM_ZFIX] 第 ${frame} 帧反转容器兄弟顺序（由 ${origin} 注入） =====
do
    local __zFrame = 0
    local __zLifted = -1
    -- 同级最上层 / 最下层（这两个便捷方法的效果与真机一致，见文件顶部说明）
    local function __lift(c)
        if c then pcall(function() c:SetAsLastSibling() end) end
    end
    local function __sink(c)
        if c then pcall(function() c:SetAsFirstSibling() end) end
    end
    local __origOnUpdate = OnUpdate
    OnUpdate = function(dt)
        if __origOnUpdate then __origOnUpdate(dt) end
        __zFrame = __zFrame + 1
        if __zFrame == ${frame} then
            local root = script.object
            if not root then printerr("[Z] root 为 nil") return end
            local kids = root:GetChildren()
            local total = kids and #kids or 0
            -- 顶层往下层排：先 fade（最终 index 0 = 最上），最后 bg（index 最大 = 最下）
            local pushOrder = { "containerFade", "containerMenu", "containerHud", "containerPlayer", "containerPickup", "containerGoal", "containerPlatform", "containerBg" }
            local moved = 0
            for _, k in ipairs(pushOrder) do
                local c = state[k]
                if c then
                    local ok = pcall(function() c:SetAsFirstSibling() end)
                    if ok then moved = moved + 1 end
                end
            end
            -- 顺带隐藏场景工程自带的脚手架节点，它们与游戏无关
            local isMine = {}
            for _, k in ipairs(pushOrder) do
                local c = state[k]
                if c then isMine[c.Id] = true end
            end
            local hidden = 0
            for _, ch in ipairs(root:GetChildren() or {}) do
                if not isMine[ch.Id] then
                    pcall(function() ch:SetVisible(false) end)
                    pcall(function() ch:SetActive(false) end)
                    hidden = hidden + 1
                end
            end
            printerr("[Z] 容器层级已反转 total=" .. tostring(total) .. " moved=" .. tostring(moved)
                .. " 隐藏脚手架=" .. tostring(hidden))
        end
        -- 每帧幂等：把平台秒数标签提到同级最上层（平台建得比容器晚，必须持续做）
        if __zFrame >= ${frame} and state.platforms then
            local lifted = 0
            for _, p in ipairs(state.platforms) do
                if p and p.label then
                    if pcall(function() p.label:SetAsLastSibling() end) then
                        lifted = lifted + 1
                    end
                end
            end
            if lifted ~= __zLifted then
                __zLifted = lifted
                printerr("[Z] 平台标签提升到顶层: " .. tostring(lifted) .. " 个")
            end
        end
        -- 每帧幂等：菜单容器的「内部」同样被反置
        --   ① 文字类要提到最上层，否则会被自己的底色盖住（卡片 / 按钮 / 箭头）；
        --   ② 面板底与遮罩要沉到最下层，且必须「先面板后遮罩」——
        --      这样遮罩落在最底，盖住游戏画面却不盖住面板。
        --   （真机上创建顺序天然正确，所以这是模拟器专属修正，工程源文件未改。）
        if __zFrame >= ${frame} and state.menuPanel then
            for _, card in ipairs(state.menuCards or {}) do __lift(card.label) end
            for _, btn in ipairs(state.menuButtons or {}) do __lift(btn.label) end
            if state.menuPagePrev then __lift(state.menuPagePrev.label) end
            if state.menuPageNext then __lift(state.menuPageNext.label) end
            __lift(state.menuTitle)
            __lift(state.menuSubtitle)
            __lift(state.menuFooter)
            __sink(state.menuPanel)
            __sink(state.menuOverlay)
        end
        -- 每帧幂等：containerHud 内部同样被反置 —— 触屏虚拟按钮 / 「关」入口按钮
        --   底图先建、标签后建，反置后标签被底图盖住 → 只剩空方块。
        --   HUD 内没有任何控件需要盖住文字，故把所有「有文字的文本控件」提到最上层。
        if __zFrame >= ${frame} and state.containerHud then
            local liftedHud = 0
            for _, ch in ipairs(state.containerHud:GetChildren() or {}) do
                local txt = nil
                pcall(function() txt = ch.text end)
                if txt and txt ~= "" then
                    __lift(ch)
                    liftedHud = liftedHud + 1
                end
            end
        end
    end
end
-- ===== [/SIM_ZFIX] =====
`;
}

// ---------- 收集游戏目录下的 Lua ----------
// 返回 [{ name, full, source }]，已排除引擎类型桩 miliastra*.lua
export function collectLua(dir) {
  const out = [];
  for (const name of readdirSync(dir)) {
    if (!name.endsWith('.lua')) continue;
    if (/^miliastra/i.test(name)) continue;
    const full = path.join(dir, name);
    if (!statSync(full).isFile()) continue;
    out.push({ name, full, source: readFileSync(full, 'utf8') });
  }
  return out;
}
