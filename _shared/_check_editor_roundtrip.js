// TickHop 编辑器「导出 → 解析」往返测试
//
// 用途：改动 TickHop/编辑器.html 的 generateLua() / parseLuaLevels() 后运行，
//       验证导出的 Lua 片段能被自己完整解析回来（平台 tick、道具类型、文本、配色、起点、门尺寸）。
//
// 用法：node _shared/_check_editor_roundtrip.js
//       依赖：node（任意现代版本）
//
// 原理：从 HTML 中抽出内嵌 <script>，截取纯函数区（num / q / generateLua / parseLuaLevels），
//       连同从源码原样抽取的 DEFAULTS 一起注入 new Function 作用域，注入样例关卡后比对往返结果。
const fs = require("fs");
const path = require("path");

const ROOT = path.join(__dirname, "..");
const HTML = path.join(ROOT, "TickHop", "编辑器.html");

if (!fs.existsSync(HTML)) {
    console.log("[SKIP] 未找到", HTML);
    process.exit(0);
}

const html = fs.readFileSync(HTML, "utf8");
const sm = html.match(/<script>([\s\S]*?)<\/script>/);
if (!sm) { console.log("[FAIL] 未找到 <script> 块"); process.exit(1); }
const js = sm[1];

const i = js.indexOf("function num(v)");
const j = js.indexOf("// 初始化");
if (i < 0 || j < 0) { console.log("[FAIL] 无法定位纯函数区（num/generateLua/parseLuaLevels）"); process.exit(1); }
const core = js.slice(i, j);

// DEFAULTS 从源码原样抽取，保证与编辑器实际行为一致
const dm = js.match(/const DEFAULTS = \{[\s\S]*?\n\};/);
if (!dm) { console.log("[FAIL] 无法定位 DEFAULTS"); process.exit(1); }
const DEFAULTS = new Function(dm[0] + "\nreturn DEFAULTS;")();

// PALETTES 同样从源码原样抽取（parseLuaLevels 靠它回填预设名）
const pm = js.match(/const PALETTES = \{[\s\S]*?\n\};/);
if (!pm) { console.log("[FAIL] 无法定位 PALETTES"); process.exit(1); }
const PALETTES = new Function(pm[0] + "\nreturn PALETTES;")();

console.log("[INFO] DEFAULTS 读取成功: platform_width =", DEFAULTS.platform_width,
            ", platform_tick =", DEFAULTS.platform_tick,
            ", goal_width =", DEFAULTS.goal_width,
            ", platform_label_ghost_alpha =", DEFAULTS.platform_label_ghost_alpha);

// 每个内置配色都必须给出 labelGhost（平台熄灭时的标签色），否则熄灭态标签没法反色
let palOk = true;
for (const [name, p] of Object.entries(PALETTES)) {
    if (!p) continue;                     // "默认 · 极简黑白" 用 config 默认值
    const miss = ["bg", "platform", "ghost", "label", "labelGhost", "player", "goal", "hud", "pickup", "reverse"]
        .filter(k => !p[k]);
    if (miss.length) { console.log("[FAIL] 配色「" + name + "」缺字段:", miss.join(",")); palOk = false; }
    else if (!/^[0-9A-Fa-f]{6}$/.test(p.labelGhost) || !/^[0-9A-Fa-f]{6}$/.test(p.label)) {
        console.log("[FAIL] 配色「" + name + "」label/labelGhost 不是 6 位十六进制"); palOk = false;
    }
}
console.log("配色预设完整性:", palOk ? "[PASS]" : "[FAIL]", "共", Object.keys(PALETTES).length, "套");

// 样例关卡（覆盖：永驻平台 / 计时平台 / 加时道具 / 反转道具 / 提示文本 / 配色覆盖）
const levels = [
    {
        name: "往返-第01关", time: 12.00, palette: null, paletteKey: null,
        spawn: { x: -300, y: -180 },
        goal: { x: 200, y: -100, width: 56, height: 84 },
        platforms: [
            { x: -200, y: -240, width: 420, height: 24, tick: -1 },
            { x: 180, y: -160, width: 150, height: 22, tick: 4 },
        ],
        pickups: [],
        texts: [{ x: -140, y: 120, text: "平台上的数字 = 它会亮起的秒数" }],
    },
    {
        name: "往返-第02关", time: 8.00,
        // 用整套内置预设（含 labelGhost），验证「预设名回填 + 配色逐项无损」
        palette: JSON.parse(JSON.stringify(PALETTES["暖阳黄紫"])), paletteKey: "暖阳黄紫",
        spawn: { x: -330, y: -180 },
        goal: { x: 320, y: 60, width: 56, height: 84 },
        platforms: [
            { x: -300, y: -240, width: 200, height: 24, tick: -1 },
            { x: -120, y: -150, width: 110, height: 20, tick: 3 },
            { x: 40, y: -60, width: 110, height: 20, tick: 6 },
        ],
        pickups: [
            { x: -120, y: -80, type: "time", value: 4.00 },
            { x: 40, y: 10, type: "reverse", value: 0 },
        ],
        texts: [{ x: 0, y: 200, text: "加时道具补充时间，反转道具让时间倒流" }],
    },
];

const factory = new Function(
    "levels", "DEFAULTS", "PALETTES",
    core + "\nreturn { generateLua: generateLua, parseLuaLevels: parseLuaLevels };"
);
const { generateLua, parseLuaLevels } = factory(levels, DEFAULTS, PALETTES);

const lua = generateLua();
console.log("\n=== 生成的 Lua 片段（前 12 行）===");
console.log(lua.split("\n").slice(0, 12).join("\n"));
console.log("...");

const back = parseLuaLevels(lua);
console.log("\n=== 往返解析结果 ===");
console.log("关卡数:", back.length, "| 期望:", levels.length);

let ok = true;
levels.forEach((lv, idx) => {
    const b = back[idx];
    if (!b) { console.log("[FAIL] 缺失第", idx + 1, "关"); ok = false; return; }
    const same =
        b.name === lv.name &&
        Math.abs(b.time - lv.time) < 1e-6 &&
        b.platforms.length === lv.platforms.length &&
        b.pickups.length === lv.pickups.length &&
        b.texts.length === lv.texts.length &&
        !!b.spawn && b.spawn.x === lv.spawn.x && b.spawn.y === lv.spawn.y &&
        !!b.goal && b.goal.width === lv.goal.width && b.goal.height === lv.goal.height &&
        (!lv.palette || (!!b.palette &&
            b.palette.platform === lv.palette.platform &&
            b.palette.label === lv.palette.label &&
            b.palette.labelGhost === lv.palette.labelGhost));
    console.log(
        (same ? "[PASS] " : "[FAIL] ") + lv.name,
        "| 平台", b.platforms.length + "/" + lv.platforms.length,
        "| 道具", b.pickups.length + "/" + lv.pickups.length,
        "| 文本", b.texts.length + "/" + lv.texts.length,
        "| time", b.time,
        "| spawn.x", b.spawn ? b.spawn.x : null,
        "| goal.w", b.goal ? b.goal.width : null,
        "| palette", b.palette ? b.palette.platform : "-"
    );
    if (!same) ok = false;
});

// 平台 tick 保真（-1 与正整数都要无损）
const ticks = back[0] ? back[0].platforms.map(p => p.tick) : [];
const tickOk = ticks.length === 2 && ticks[0] === -1 && ticks[1] === 4;
console.log("平台 tick 保真:", tickOk ? "[PASS]" : "[FAIL]", JSON.stringify(ticks));
if (!tickOk) ok = false;

// 平台尺寸保真
const sizes = back[0] ? back[0].platforms.map(p => p.width + "x" + p.height) : [];
const sizeOk = sizes[0] === "420x24" && sizes[1] === "150x22";
console.log("平台尺寸保真:", sizeOk ? "[PASS]" : "[FAIL]", JSON.stringify(sizes));
if (!sizeOk) ok = false;

// 道具类型保真
const types = back[1] ? back[1].pickups.map(p => p.type) : [];
const typeOk = types[0] === "time" && types[1] === "reverse";
console.log("道具类型保真:", typeOk ? "[PASS]" : "[FAIL]", JSON.stringify(types));
if (!typeOk) ok = false;

// 预设名回填 + 配色逐项无损（labelGhost 必须一起回来，否则熄灭态标签会退回默认色）
const b2 = back[1];
const presetOk = !!b2 && b2.paletteKey === "暖阳黄紫" &&
    JSON.stringify(b2.palette) === JSON.stringify(PALETTES["暖阳黄紫"]);
console.log("配色预设往返:", presetOk ? "[PASS]" : "[FAIL]",
    "paletteKey=" + (b2 ? b2.paletteKey : null),
    "labelGhost=" + (b2 && b2.palette ? b2.palette.labelGhost : null));
if (!presetOk) ok = false;

if (!palOk) ok = false;

console.log(ok ? "\n>>> 往返测试通过" : "\n>>> 往返测试失败");
process.exit(ok ? 0 : 1);
