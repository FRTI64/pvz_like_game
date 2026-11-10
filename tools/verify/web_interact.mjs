#!/usr/bin/env node
// tools/verify/web_interact.mjs — scripted end-to-end interaction test for the 3D web
// preview, driven through the HOST Chrome CDP endpoint (real WebGL2).
//
// Covers (spec §7): menu -> level select, seed card -> lawn cell planting via real
// mouse clicks (DOM card click + CDP canvas click), sun cost/cooldown, natural sun
// collection via projected screen position, all 8 plant types, shovel, projectile
// damage on a spawned zombie, lawnmower lane clear, pause/resume modal, forced
// victory/defeat modals, restart, levels 2/3 start, HUD sync, and error-free run.
//
// Usage (server must be started in the same bash invocation):
//   python3 serve.py 8121 & SRV=$!; sleep 2
//   node tools/verify/web_interact.mjs [--url-base http://localhost:8121] [--out screenshots/web_3d_interaction.png]
//   kill $SRV
//
// Exit code 0 = all checks pass, 1 = failures, 2 = harness failure.
import path from 'node:path';
import { ROOT, SCREENSHOTS_DIR, parseArgs, sleep, mkdirp, writeJson, finish } from './lib.mjs';
import { isAvailable, newTab, closeTab, connect, attachErrorCapture, evaluate, snap, waitForExpr, CDP_HOST } from './cdp.mjs';

const args = parseArgs();
const BASE = (typeof args['url-base'] === 'string' ? args['url-base'] : 'http://localhost:8121').replace(/\/$/, '');
const OUT = path.isAbsolute(args.out || 'screenshots/web_3d_interaction.png')
  ? (args.out || 'screenshots/web_3d_interaction.png')
  : path.join(ROOT, args.out || 'screenshots/web_3d_interaction.png');

const results = [];
const check = (name, ok, detail) => {
  results.push({ name, ok: !!ok, detail });
  console.log(`${ok ? 'PASS' : 'FAIL'} ${name}${detail !== undefined ? ' :: ' + JSON.stringify(detail).slice(0, 400) : ''}`);
};

const PLANT_CELLS = [
  ['peashooter', 1, 2],
  ['sunflower', 0, 1],
  ['wallnut', 1, 1],
  ['snow_pea', 2, 1],
  ['repeater', 3, 1],
  ['chomper', 0, 3],
  ['cherry_bomb', 1, 3],
  ['potato_mine', 2, 3],
];

async function main() {
  const summary = { ok: false, base: BASE, cdpHost: CDP_HOST, out: path.relative(ROOT, OUT), startedAt: new Date().toISOString() };
  let tab = null;
  let cdp = null;
  let capture = null;
  try {
    if (!(await isAvailable())) throw new Error(`host Chrome CDP not reachable at ${CDP_HOST}`);
    tab = await newTab();
    cdp = connect(tab.webSocketDebuggerUrl);
    await cdp.ready;
    capture = attachErrorCapture(cdp);
    await cdp.send('Runtime.enable');
    await cdp.send('Log.enable');
    await cdp.send('Page.enable');
    await cdp.send('Emulation.setDeviceMetricsOverride', { width: 1280, height: 720, deviceScaleFactor: 1, mobile: false });

    const mouse = async (x, y, kind = 'click') => {
      await cdp.send('Input.dispatchMouseEvent', { type: 'mouseMoved', x, y });
      await sleep(50);
      if (kind === 'click') {
        await cdp.send('Input.dispatchMouseEvent', { type: 'mousePressed', x, y, button: 'left', clickCount: 1 });
        await sleep(30);
        await cdp.send('Input.dispatchMouseEvent', { type: 'mouseReleased', x, y, button: 'left', clickCount: 1 });
      }
      await sleep(350);
    };

    await cdp.send('Page.navigate', { url: BASE + '/web_preview/index.html' });
    await sleep(500);
    const ready = await waitForExpr(cdp, `new Promise(r => { if (window.__pvzReady === true) return r('ready'); let n=0; const t=setInterval(() => { n++; if (window.__pvzReady===true){clearInterval(t);r('ready');} else if((window.__pvzErrors||[]).length){clearInterval(t);r('errors');} else if(n>900){clearInterval(t);r('timeout');} }, 100); })`, 100000);
    check('window.__pvzReady after load', ready === 'ready', { result: ready });

    // install game-px -> CSS-px projection helper (actual camera matrices, not spec math)
    await evaluate(cdp, `(() => {
      const cam = window.__pvzDebug.camera; cam.updateMatrixWorld(true);
      const e = cam.matrixWorldInverse.elements, p = cam.projectionMatrix.elements;
      const apply = (m,v) => ({x:m[0]*v.x+m[4]*v.y+m[8]*v.z+m[12], y:m[1]*v.x+m[5]*v.y+m[9]*v.z+m[13], z:m[2]*v.x+m[6]*v.y+m[10]*v.z+m[14], w:m[3]*v.x+m[7]*v.y+m[11]*v.z+m[15]});
      window.__gameToScreen = (gx, gy, h=0) => {
        const v = {x:(gx-640)/45, y:h/45, z:(gy-360)/45};
        const c = apply(p, apply(e, v));
        const rect = document.getElementById('canvas').getBoundingClientRect();
        return { x: rect.left + ((c.x/c.w)*0.5+0.5)*rect.width, y: rect.top + (-(c.y/c.w)*0.5+0.5)*rect.height };
      };
      window.__sunToScreen = (i) => {
        const sp = window.__pvzDebug.sunScreenPixel(window.__pvz.getSuns()[i]);
        const rect = document.getElementById('canvas').getBoundingClientRect();
        return { x: rect.left + sp.x / 1280 * rect.width, y: rect.top + sp.y / 720 * rect.height, gx: sp.x, gy: sp.y };
      };
      return true;
    })()`);

    // ---- menu -> level 1 ----
    const menuCards = await evaluate(cdp, `document.querySelectorAll('.level-card-btn').length`);
    check('menu shows 3 level cards', menuCards === 3, { cards: menuCards });
    await evaluate(cdp, `document.querySelectorAll('.level-card-btn')[0].click()`);
    await sleep(1500);
    let st = await evaluate(cdp, `({ state: window.__pvz.state, sun: window.__pvz.sun, level: window.__pvz.level, ready: window.__pvzReady })`);
    check('level 1 starts from menu (PLAYING, sun 150)', st.state === 'PLAYING' && st.sun === 150 && st.level === 1, st);

    // ---- seed card click -> lawn click plants ----
    const cellClick = async (row, col) => {
      const pt = await evaluate(cdp, `window.__gameToScreen(${265 + col * 100 + 50}, ${120 + row * 110 + 55}, 0)`);
      await mouse(pt.x, pt.y);
      return pt;
    };
    await evaluate(cdp, `document.getElementById('card-peashooter').click()`);
    await sleep(200);
    const selected = await evaluate(cdp, `document.getElementById('card-peashooter').classList.contains('selected')`);
    check('seed card selectable', selected === true);
    await cellClick(1, 2);
    let grid = await evaluate(cdp, `window.__pvz.getGrid()`);
    const g12 = grid[1] && grid[1][2];
    check('canvas click planted peashooter at (row1,col2)', !!g12 && g12.id === 'peashooter', g12);
    let hud = await evaluate(cdp, `({ sun: window.__pvz.sun, hud: document.getElementById('sun-count').textContent.trim(), cardDisabled: document.getElementById('card-peashooter').classList.contains('disabled') })`);
    check('sun spent 100 (150 -> 50)', hud.sun === 50, hud);
    check('HUD sun label synced', hud.hud === '50', hud);
    check('card enters cooldown/disabled after planting', hud.cardDisabled === true, hud);

    // ---- natural sun settles, click projected position collects +25 ----
    let sunHit = null;
    for (let i = 0; i < 80; i++) {
      await sleep(400);
      const info = await evaluate(cdp, `(() => { const list = window.__pvz.getSuns(); for (let i=0;i<list.length;i++){ const s=list[i]; const p=window.__pvzDebug.sunScreenPixel(s); if (Math.abs(s.y-s.targetY)<1.5 && p.y>150 && p.x>20 && p.x<1260) return {i, sp:p, y:s.y}; } return null; })()`);
      if (info) { sunHit = info; break; }
    }
    check('natural sun settled visible on lawn', !!sunHit, sunHit);
    if (sunHit) {
      const before = await evaluate(cdp, `window.__pvz.sun`);
      const sp = await evaluate(cdp, `window.__sunToScreen(${sunHit.i})`);
      await mouse(sp.x, sp.y);
      await sleep(700);
      const after = await evaluate(cdp, `window.__pvz.sun`);
      const left = await evaluate(cdp, `window.__pvz.getSuns().length`);
      check('click sun collects +25', after === before + 25, { before, after, left });
    }

    // ---- add sun + plant remaining 7 types via real clicks ----
    const added = await evaluate(cdp, `window.__pvz.addSun(2000)`);
    check('__pvz.addSun(2000)', added >= 2000, { sun: added });
    for (const [id, row, col] of PLANT_CELLS) {
      if (id === 'peashooter') continue; // already planted
      await evaluate(cdp, `document.getElementById('card-${id}').click()`);
      await sleep(120);
      await cellClick(row, col);
    }
    grid = await evaluate(cdp, `window.__pvz.getGrid()`);
    const planted = [];
    const missing = [];
    for (const [id, row, col] of PLANT_CELLS) {
      const c = grid[row] && grid[row][col];
      if (c && c.id === id) planted.push(id); else missing.push({ id, row, col, got: c ? c.id : null });
    }
    check('all 8 plant types planted in distinct cells', missing.length === 0, { planted: planted.length, missing });

    // cooldown: re-click a card that is cooling down -> no plant, no sun spend
    const beforeCd = await evaluate(cdp, `window.__pvz.sun`);
    await evaluate(cdp, `document.getElementById('card-wallnut').click()`);
    await sleep(120);
    await cellClick(4, 6);
    const afterCd = await evaluate(cdp, `({ sun: window.__pvz.sun, cell: window.__pvz.getGrid()[4][6] })`);
    check('cooldown blocks immediate re-plant', !afterCd.cell && afterCd.sun === beforeCd, afterCd);

    // ---- shovel frees a cell ----
    const cellBeforeShovel = await evaluate(cdp, `window.__pvz.getGrid()[0][1]`);
    await evaluate(cdp, `toggleShovel()`);
    await sleep(150);
    await cellClick(0, 1);
    const afterShovel = await evaluate(cdp, `({ cell: window.__pvz.getGrid()[0][1], shovel: (() => { const b = document.getElementById('shovel-btn'); return b.classList.contains('active'); })() })`);
    await evaluate(cdp, `toggleShovel()`).catch(() => {});
    check('shovel removes plant from cell', !!cellBeforeShovel && !afterShovel.cell, { before: cellBeforeShovel && cellBeforeShovel.id, after: afterShovel.cell });

    // ---- projectile hit: zombie in peashooter lane loses HP ----
    const zwave = await evaluate(cdp, `({ wave: window.__pvz.getState().wave, waves: window.__pvz.getState().waves })`);
    check('level 1 has 5 waves', zwave.waves === 5, zwave);
    await evaluate(cdp, `window.__pvz.spawnZombie('normal', 1, 560)`);
    let zombieHit = null;
    for (let i = 0; i < 40; i++) {
      await sleep(300);
      const zs = await evaluate(cdp, `window.__pvz.getZombies()`);
      const z = (zs || []).find((x) => x.row === 1);
      if (z && z.hp < 200) { zombieHit = z; break; }
    }
    check('peashooter projectile damages spawned zombie', !!zombieHit, zombieHit);

    // ---- lawnmower clears a lane ----
    await evaluate(cdp, `window.__pvz.spawnZombie('normal', 4, 210)`);
    let lane4 = [];
    let mowerCleared = false;
    for (let i = 0; i < 30; i++) {
      await sleep(300);
      lane4 = await evaluate(cdp, `window.__pvz.getZombies().filter(z => z.row === 4)`);
      if (lane4.length === 0) { mowerCleared = true; break; }
    }
    check('lawnmower clears lane (zombie removed)', mowerCleared, { lane4 });
    // Evidence: mid-game state (all 8 plant types planted, zombies present, HUD live).
    const midShot = await snap(cdp, OUT);
    summary.png = { path: path.relative(ROOT, OUT), bytes: midShot.bytes };

    // ---- pause modal via HUD button ----
    await evaluate(cdp, `document.getElementById('hud-menu-btn').click()`);
    await sleep(400);
    const pause = await evaluate(cdp, `({ state: window.__pvz.state, display: getComputedStyle(document.getElementById('pause-modal')).display })`);
    check('pause modal opens and game state PAUSED', pause.state === 'PAUSED' && pause.display !== 'none', pause);
    await snap(cdp, path.join(SCREENSHOTS_DIR, 'web_3d_pause_interact.png'));
    await evaluate(cdp, `resumeGame()`);
    await sleep(300);
    const resumed = await evaluate(cdp, `({ state: window.__pvz.state, display: getComputedStyle(document.getElementById('pause-modal')).display })`);
    check('resume returns to PLAYING', resumed.state === 'PLAYING' && resumed.display === 'none', resumed);

    // ---- forced victory / defeat paths ----
    await evaluate(cdp, `window.__pvz.gameOver(true)`);
    await sleep(600);
    const win = await evaluate(cdp, `({ state: window.__pvz.state, title: document.getElementById('modal-title').textContent, modal: getComputedStyle(document.getElementById('game-modal')).display })`);
    check('victory path shows VICTORY modal', win.state === 'VICTORY' && /VICTORY/i.test(win.title) && win.modal !== 'none', win);
    await snap(cdp, path.join(SCREENSHOTS_DIR, 'web_3d_victory.png'));
    await evaluate(cdp, `restartLevel()`);
    await sleep(1200);
    const restarted = await evaluate(cdp, `({ state: window.__pvz.state, sun: window.__pvz.sun })`);
    check('restart after victory returns to PLAYING', restarted.state === 'PLAYING', restarted);
    await evaluate(cdp, `window.__pvz.gameOver(false)`);
    await sleep(600);
    const lose = await evaluate(cdp, `({ state: window.__pvz.state, title: document.getElementById('modal-title').textContent, modal: getComputedStyle(document.getElementById('game-modal')).display })`);
    check('defeat path shows game-over modal', lose.state === 'GAME_OVER' && /BRAINS/i.test(lose.title) && lose.modal !== 'none', lose);
    await snap(cdp, path.join(SCREENSHOTS_DIR, 'web_3d_gameover.png'));

    // ---- levels 2 and 3 start ----
    await evaluate(cdp, `window.__pvz.startLevel(2)`);
    await sleep(1000);
    const l2 = await evaluate(cdp, `({ level: window.__pvz.level, sun: window.__pvz.sun, state: window.__pvz.state, waves: window.__pvz.getState().waves })`);
    check('level 2 starts (sun 100, 6 waves)', l2.level === 2 && l2.sun === 100 && l2.state === 'PLAYING' && l2.waves === 6, l2);
    await evaluate(cdp, `window.__pvz.startLevel(3)`);
    await sleep(1000);
    const l3 = await evaluate(cdp, `({ level: window.__pvz.level, sun: window.__pvz.sun, state: window.__pvz.state, waves: window.__pvz.getState().waves })`);
    check('level 3 starts (sun 200, 7 waves)', l3.level === 3 && l3.sun === 200 && l3.state === 'PLAYING' && l3.waves === 7, l3);
    await sleep(800);
    const finalShot = await snap(cdp, path.join(SCREENSHOTS_DIR, 'web_3d_interaction_level3.png'));
    summary.out = path.relative(ROOT, OUT);
    summary.outLevel3 = path.relative(ROOT, path.join(SCREENSHOTS_DIR, 'web_3d_interaction_level3.png'));
    summary.pngLevel3 = { bytes: finalShot.bytes };

    // ---- errors ----
    const pvzErrors = await evaluate(cdp, `window.__pvzErrors || []`).catch(() => ['evaluate failed']);
    check('window.__pvzErrors empty', Array.isArray(pvzErrors) && pvzErrors.length === 0, pvzErrors);
    const errs = {
      exceptions: capture.exceptions,
      console: capture.consoleErrors,
      log: capture.logErrors,
      crashes: capture.crashes,
    };
    const errorTotal = errs.exceptions.length + errs.console.length + errs.log.length + errs.crashes.length;
    check('no uncaught exceptions / console errors / 404s', errorTotal === 0, errs);
    summary.errors = errs;

    const passed = results.filter((r) => r.ok).length;
    summary.results = results;
    summary.passed = passed;
    summary.total = results.length;
    summary.ok = passed === results.length;
    summary.png = finalShot;
    summary.elapsedMs = Date.now() - new Date(summary.startedAt).getTime();
    if (typeof args.json === 'string') writeJson(path.resolve(ROOT, args.json), summary);
    console.log(`\nSUMMARY ${JSON.stringify({ passed, total: results.length, ok: summary.ok, out: summary.out })}`);
    process.exit(finish(summary, summary.ok ? 0 : 1));
  } catch (e) {
    summary.fatal = String((e && e.stack) || e);
    summary.results = results;
    const passed = results.filter((r) => r.ok).length;
    summary.passed = passed;
    summary.total = results.length;
    summary.ok = false;
    console.error('FATAL', summary.fatal);
    process.exit(finish(summary, 2));
  } finally {
    try { if (cdp) cdp.close(); } catch { /* ignore */ }
    if (tab) await closeTab(tab.id);
  }
}

main();
