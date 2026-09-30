// _sim_common.mjs — 模拟器驱动脚本的共享定义
//
// 被 qxqy_mount.mjs（MCP 驱动）与 qxqy_websave.mjs（Web 存档生成）共同引用，
// 保证两边的模板 guid 与参数兜底写法永远一致。

import { readdirSync, readFileSync, statSync } from 'node:fs';
import path from 'node:path';

// 模拟器就绪存档里的模板 guid（与 qxqy_simsave.mjs 保持一致）
//
// ★ 这些值刻意使用「真机编辑器内置模板的元件索引」，而不是自造的 2000001/2000002：
//   模拟器注册模板的规则是 registerTemplate(prefabIndex = node.guid)，所以 guid 一旦与
//   真机索引同源，游戏里 config.DEFAULT_PREFAB_* 的回退值就能在两边同时命中 →
//   「模拟器里跑通」与「搬进真机跑通」之间不再有参数错位。
//   索引来源见 _shared/编辑器元件索引.md
//   （容器节点 1073741876，内部名 SoloTurnPoolHost；游戏的 7 个分层容器由它创建）
//
// ★ water / land / tree / player 是「美术素材元件」：
//   真机上它们自带美术素材，游戏**不写 imageColor**（一写就把素材乘上去了）。
//   模拟器没有真机素材，所以 qxqy_simsave.mjs 把对应模板的 imageColor 预置成代表色 ——
//   游戏不写 color，预置色就留在控件上，于是模拟器里照样有可见画面、截图可比对。
//   这四个 key 只有 浮岛借木 在用；其余工程传进来也无害（不读就不用）。
export const SIM_TEMPLATE_GUIDS = {
  rectPrefabId: 1073741894,
  imagePrefabId: 1073741870,
  textPrefabId: 1073741868,
  containerPrefabId: 1073741876,
  waterPrefabId: 1073741879,
  landPrefabId: 1073741881,
  treePrefabId: 1073741883,
  playerPrefabId: 1073741886,
};

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
-- ===== [SIM_ZFIX] 第 ${frame} 帧还原容器层级 + 容器内部顺序（由 ${origin} 注入） =====
do
    local __zFrame = 0
    local __zLifted = -1
    local __zSeq = {}        -- 控件 -> 创建序号（越大越晚创建 = 真机上越靠上）；用控件本身当键
    local __zSeqNext = 0
    local __zCtrls = {}      -- 游戏自己的容器在 state 里的键名（如 containerBg）
    local __zCount = {}      -- 上次整理时各容器的子节点数（只在结构变化时重排）
    -- 同级最上层 / 最下层（这两个便捷方法的效果与真机一致，见文件顶部说明）
    local function __lift(c)
        if c then pcall(function() c:SetAsLastSibling() end) end
    end
    local function __sink(c)
        if c then pcall(function() c:SetAsFirstSibling() end) end
    end
    -- ★ 认定「游戏自己的控件」一律用**引用相等**，不依赖 .Id ——
    --   模拟器的 Control 没有 Id 字段（实测 cw.Id == nil），按字段名认会全部落空。
    local function __isObj(v)
        local t = type(v)
        return t == "table" or t == "userdata"
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

            -- ① 给整棵树按「数组顺序」编创建序号。
            --    此刻还没有动过任何兄弟顺序，而 Control.children 是创建顺序 push 的，
            --    所以数组顺序 == 创建顺序 == 真机的由底到顶。
            local function __seed(n)
                if __zSeq[n] == nil then
                    __zSeqNext = __zSeqNext + 1
                    __zSeq[n] = __zSeqNext
                end
                for _, ch in ipairs(n:GetChildren() or {}) do __seed(ch) end
            end
            __seed(root)

            -- ② 认准「游戏自己的容器」：state 里名为 container* 的字段。
            --    ★ 不再写死容器名 —— 每个游戏的分层命名不同（本工程用
            --      containerWater/Sand/World/Props/Player/Hud/Menu/Fade）。
            local mineList, ctrlRefs = {}, {}
            for k, v in pairs(state) do
                if __isObj(v) then
                    mineList[#mineList + 1] = v
                    if type(k) == "string" and k:sub(1, 9) == "container" then
                        ctrlRefs[#ctrlRefs + 1] = v
                        __zCtrls[#__zCtrls + 1] = k
                    end
                end
            end
            local function __isMine(ch)
                for i = 1, #mineList do if mineList[i] == ch then return true end end
                return false
            end
            local function __isCtrl(ch)
                for i = 1, #ctrlRefs do if ctrlRefs[i] == ch then return true end end
                return false
            end

            -- ③ 容器按创建顺序（由底到顶）逐个置到最顶层。
            --    模拟器里 SetAsLastSibling 会落到数组下标 0 = 最后绘制 = 最上层，
            --    于是数组最终背面朝上，绘制顺序与真机一致。该操作幂等。
            local moved = 0
            for _, ch in ipairs(kids or {}) do
                if __isCtrl(ch) then
                    if pcall(function() ch:SetAsLastSibling() end) then moved = moved + 1 end
                end
            end

            -- ④ 隐藏工程自带脚手架（与游戏无关），但绝不碰游戏自己的控件
            local hidden = 0
            for _, ch in ipairs(root:GetChildren() or {}) do
                if not __isMine(ch) then
                    pcall(function() ch:SetVisible(false) end)
                    pcall(function() ch:SetActive(false) end)
                    hidden = hidden + 1
                end
            end
            printerr("[Z] 容器归位 total=" .. tostring(total) .. " moved=" .. tostring(moved)
                .. " 隐藏脚手架=" .. tostring(hidden)
                .. " 识别容器=" .. table.concat(__zCtrls, ","))
        end

        -- ⑤ 每帧幂等：容器「内部」同样是反的 —— 同级的兄弟绘制顺序与真机相反，
        --    后创建的（真机上更靠上）反而先画、被压在底下。
        --    做法：按创建序号升序逐个 SetAsLastSibling()，序号最大的落到数组下标 0
        --    = 最后绘制 = 最上层。排序键固定，所以重复执行结果不变（幂等）；
        --    池子后来才扩建的控件在这里补号，天然排到最后 = 置顶，与真机一致。
        --    只在某容器的子节点数变化时重排，避免每帧对数百个格槽做无用功。
        --
        -- ★ 例外：state.selfOrderedContainers 里点名的容器**跳过**。
        --   工程在这些容器里自己按「由底到顶」调 SetAsLastSibling（见 level.lua 的
        --   restack），引擎语义两边一致，比这里按创建序猜更可靠。
        --   这里这套启发式本身有个坑：__zSeq 是「按当时的数组顺序」补号的，
        --   而对象池复用会打乱数组顺序 —— 于是每次子节点数变化都会把整段顺序
        --   翻转一次，最终朝向取决于翻转次数的奇偶（实测：对象层被翻反，
        --   树干盖住树冠、石头顶面消失）。所以凡是工程能自己点名的，一律让它自己管。
        if __zFrame >= ${frame} then
            local __selfOrdered = state.selfOrderedContainers
            for _, key in ipairs(__zCtrls) do
                local c = state[key]
                local skip = (type(__selfOrdered) == "table") and (__selfOrdered[key] == true)
                if c and not skip then
                    local chs = c:GetChildren() or {}
                    local n = #chs
                    for i = 1, n do
                        if __zSeq[chs[i]] == nil then
                            __zSeqNext = __zSeqNext + 1
                            __zSeq[chs[i]] = __zSeqNext
                        end
                    end
                    if n ~= (__zCount[key] or -1) then
                        __zCount[key] = n
                        table.sort(chs, function(a, b)
                            return (__zSeq[a] or 0) < (__zSeq[b] or 0)
                        end)
                        for i = 1, n do pcall(function() chs[i]:SetAsLastSibling() end) end
                    end
                end
            end
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
