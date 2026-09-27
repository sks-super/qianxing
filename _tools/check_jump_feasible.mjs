// 可行性核算：用与 physics.lua 完全相同的积分方式模拟一次满跳，
// 验证复刻后的关卡在现有物理参数下确实可通（不依赖真机/模拟器）。
// 用法: node _tools/check_jump_feasible.mjs
import fs from 'node:fs';
import path from 'node:path';

const ROOT = process.cwd();
const cfg = fs.readFileSync(path.join(ROOT, 'TickHop/config.lua'), 'utf8');

// ---- 读 DEFAULT_* ----
const D = {};
for (const m of cfg.matchAll(/M\.DEFAULT_([A-Z_]+)\s*=\s*(-?[\d.]+)/g)) D[m[1]] = parseFloat(m[2]);

// ---- 读 LEVELS（按 name = " 切块，再逐块取字段，避免大正则漏配）----
const body = cfg.slice(cfg.indexOf('M.LEVELS = {'));
const chunks = body.split(/name\s*=\s*"/).slice(1);
const levels = [];
for (const ch of chunks) {
  const name = ch.slice(0, ch.indexOf('"'));
  const num = (re) => { const m = ch.match(re); return m ? parseFloat(m[1]) : null; };
  const spawn = ch.match(/spawn\s*=\s*\{x\s*=\s*(-?[\d.]+)\s*,\s*y\s*=\s*(-?[\d.]+)/);
  const goal = ch.match(/goal\s*=\s*\{x\s*=\s*(-?[\d.]+)\s*,\s*y\s*=\s*(-?[\d.]+)\s*,\s*width\s*=\s*(-?[\d.]+)\s*,\s*height\s*=\s*(-?[\d.]+)/);
  const pblock = ch.slice(ch.indexOf('platforms'), ch.indexOf('pickups'));
  const platforms = [];
  for (const pm of pblock.matchAll(/\{x\s*=\s*(-?[\d.]+)\s*,\s*y\s*=\s*(-?[\d.]+)\s*,\s*width\s*=\s*(-?[\d.]+)\s*,\s*height\s*=\s*(-?[\d.]+)\s*,\s*tick\s*=\s*(-?[\d.]+)\s*\}/g)) {
    platforms.push({ x: +pm[1], y: +pm[2], w: +pm[3], h: +pm[4], tick: +pm[5] });
  }
  if (!spawn || !goal) { console.log('!! 解析失败', name); continue; }
  levels.push({ name, spawn: { x: +spawn[1], y: +spawn[2] }, goal: { x: +goal[1], y: +goal[2], w: +goal[3], h: +goal[4] }, platforms });
}
const P = {
  W: D.PLAYER_WIDTH, H: D.PLAYER_HEIGHT, SPEED: D.MOVE_SPEED,
  GACC: D.GROUND_ACCEL, GFRIC: D.GROUND_FRICTION, AACC: D.AIR_ACCEL, AFRIC: D.AIR_FRICTION,
  JUMP: D.JUMP_SPEED, GRAV: D.GRAVITY, FALLM: D.FALL_GRAVITY_MULT, MAXF: D.MAX_FALL_SPEED,
  SUB: D.PHYSICS_SUBSTEPS || 4,
};
console.log('# 物理参数', P);

const flat = levels.flatMap((l) => l.platforms.map((p) => ({ ...p, halfW: p.w / 2, halfH: p.h / 2, solid: true })));
function solidsOf(level) { return level.platforms.map((p) => ({ ...p, halfW: p.w / 2, halfH: p.h / 2, solid: true })); }
function approach(cur, target, d) { return cur < target ? Math.min(cur + d, target) : Math.max(cur - d, target); }

// 从 (x,y) 起跳（水平方向 dir），返回轨迹；solid 平台集合可给
function jumpSim(level, x, y, dir) {
  const hw = P.W / 2, hh = P.H / 2;
  const plats = solidsOf(level);
  let vx = dir * P.SPEED, vy = P.JUMP, onGround = false;
  const dt = 1 / 60, sub = Math.max(1, Math.floor(P.SUB)), sd = dt / sub;
  const traj = [];
  for (let f = 0; f < 180; f++) {
    for (let s = 0; s < sub; s++) {
      const acc = onGround ? P.GACC : P.AACC, fric = onGround ? P.GFRIC : P.AFRIC;
      vx = dir !== 0 ? approach(vx, dir * P.SPEED, acc * sd) : approach(vx, 0, fric * sd);
      let g = P.GRAV; if (vy < 0) g *= P.FALLM;
      vy -= g * sd;
      if (vy < -P.MAXF) vy = -P.MAXF;
      x += vx * sd;
      for (const p of plats) {
        if (Math.abs(x - p.x) < hw + p.halfW && Math.abs(y - p.y) < hh + p.halfH) {
          if (vx > 0) x = p.x - p.halfW - hw; else if (vx < 0) x = p.x + p.halfW + hw;
          vx = 0;
        }
      }
      const was = onGround;
      y += vy * sd; onGround = false;
      for (const p of plats) {
        if (Math.abs(x - p.x) < hw + p.halfW && Math.abs(y - p.y) < hh + p.halfH) {
          if (vy <= 0) { y = p.y + p.halfH + hh; vy = 0; onGround = true; }
          else { y = p.y - p.halfH - hh; vy = 0; }
        }
      }
      if (onGround && !was) traj.push({ x, y, landed: true });
    }
    traj.push({ x, y, vy, onGround });
    if (onGround && f > 3) break;
  }
  return traj;
}

function canReach(level, from, to, dir) {
  // from: 起跳平台（取朝 to 方向的那一侧边缘）
  const traj = jumpSim(level, from, dir);
  const hw = P.W / 2;
  const targetTop = to.y + to.h / 2;
  for (const t of traj) {
    if (!t.landed) continue;
    if (Math.abs(t.x - to.x) < hw + to.w / 2 && Math.abs(t.y - (targetTop + P.H / 2)) < 0.6) return { ok: true, t };
  }
  return { ok: false, traj };
}

function topOf(p) { return p.y + p.h / 2; }
function platformByTick(lv, tick) { return lv.platforms.find((p) => p.tick === tick); }
function findPlatAt(lv, x, y) { return lv.platforms.find((p) => Math.abs(x - p.x) <= p.w / 2 && Math.abs(y - (p.y + p.h / 2) + P.H / 2) < 3); }

// ---- 理论包络 ----
{
  const H = P.JUMP ** 2 / (2 * P.GRAV);
  const tr = P.JUMP / P.GRAV, tf = Math.sqrt(2 * H / (P.GRAV * P.FALLM));
  console.log(`\n# 满跳理论: 跳高 ${H.toFixed(1)} px (${(H / P.H).toFixed(2)} 个身位)  上升 ${tr.toFixed(3)}s  下落 ${tf.toFixed(3)}s  水平全距 ${(P.SPEED * (tr + tf)).toFixed(0)} px`);
}

// ---- 逐关检查 ----
for (const lv of levels) {
  console.log(`\n===== ${lv.name} =====`);
  const feetY = lv.spawn.y - P.H / 2;
  const floorBelowSpawn = lv.platforms.filter((p) => p.tick === -1 && Math.abs(lv.spawn.x - p.x) <= p.w / 2 + P.W / 2 && p.y + p.h / 2 <= feetY + 1)
    .sort((a, b) => (b.y + b.h / 2) - (a.y + a.h / 2))[0];
  console.log(`  出生点 (${lv.spawn.x}, ${lv.spawn.y}) → 脚下平台: ${floorBelowSpawn ? `top=${topOf(floorBelowSpawn).toFixed(0)} x∈[${(floorBelowSpawn.x - floorBelowSpawn.w / 2).toFixed(0)},${(floorBelowSpawn.x + floorBelowSpawn.w / 2).toFixed(0)}]` : '⚠ 无'}`);
  const goalTop = lv.goal.y - lv.goal.h / 2;
  console.log(`  门底 y=${goalTop.toFixed(0)}  x∈[${(lv.goal.x - lv.goal.w / 2).toFixed(0)},${(lv.goal.x + lv.goal.w / 2).toFixed(0)}]`);
  const goalPlat = lv.platforms.filter((p) => p.tick === -1 && Math.abs(goalTop - topOf(p)) < 2).sort((a, b) => Math.abs(lv.goal.x - a.x) - Math.abs(lv.goal.x - b.x))[0];
  console.log(`  门所在平台: ${goalPlat ? `top=${topOf(goalPlat).toFixed(0)} x∈[${(goalPlat.x - goalPlat.w / 2).toFixed(0)},${(goalPlat.x + goalPlat.w / 2).toFixed(0)}]` : '⚠ 无（门悬空）'}`);
  // 可跳到的候选
  const standables = lv.platforms.filter((p) => p.h <= 40);
  for (const from of standables) {
    const dirs = [-1, 1];
    for (const d of dirs) {
      const edgeX = from.x + d * (from.w / 2 + P.W / 2 - 1);
      const startY = topOf(from) + P.H / 2;
      const traj = jumpSim(lv, edgeX, startY, d);
      const hits = new Set();
      for (const t of traj) {
        if (!t.landed) continue;
        for (const to of lv.platforms) {
          if (to === from) continue;
          if (Math.abs(t.x - to.x) < P.W / 2 + to.w / 2 && Math.abs(t.y - (topOf(to) + P.H / 2)) < 0.6) {
            hits.add(`${to.tick >= 0 ? `[tick${to.tick}]` : ''}top=${topOf(to)}`);
          }
        }
      }
      if (hits.size) console.log(`    ${d > 0 ? '→右' : '←左'} 从 top=${topOf(from)} x=${edgeX.toFixed(0)} 起跳 可落到: ${[...hits].join(' , ')}`);
    }
  }
}
