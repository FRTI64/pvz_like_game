#!/usr/bin/env node
// tools/verify/web_shot.mjs — screenshot + smoke-check the PVZ web preview via the
// HOST headless Chrome CDP endpoint (the only WebGL2-capable browser here).
//
// Modes:
//   shot       ?shot=1 deterministic 3D gameplay preset      -> screenshots/web_3d_gameplay.png
//   menu       main menu + menu->level transition            -> screenshots/web_3d_menu.png (+ web_3d_from_menu.png)
//   pause      gameplay then click the HUD menu button       -> screenshots/web_3d_pause.png
//   baseline2d archived ORIGINAL 2D page (git HEAD copy)      -> screenshots/web_2d_baseline.png
//
// Usage:
//   node tools/verify/web_shot.mjs                            # shot mode, level 1
//   node tools/verify/web_shot.mjs --mode menu
//   node tools/verify/web_shot.mjs --mode pause
//   node tools/verify/web_shot.mjs --mode baseline2d
//   node tools/verify/web_shot.mjs --level 3 --out screenshots/web_3d_level3.png
//   node tools/verify/web_shot.mjs --url 'http://localhost:8123/web_preview/index.html?shot=1'
//
// Options:
//   --mode shot|menu|pause|baseline2d   (default shot)
//   --level N          level id for ?shot=1
//   --out PATH         screenshot path (default per mode)
//   --out2 PATH        second screenshot (menu mode: from-menu gameplay)
//   --url URL          explicit page URL (must be reachable from the browser side)
//   --port N           static server port to try first (default 8123)
//   --settle MS        settle before screenshot (default 900)
//   --timeout MS       readiness timeout (default 120000)
//   --via-menu         shot mode: start from menu and click level 1 instead of ?shot=1
//   --json PATH        also write the JSON summary to PATH
//   --keep-server      leave the managed python3 serve.py running
//   --no-analyze       skip ffmpeg image stats
//
// Requirements: host Chrome CDP at 127.0.0.1:9222 (env PVZ_CDP_HOST overrides),
// python3 serve.py (auto-started unless --url is given). Exit codes:
//   0 = pass, 1 = page/logic errors or not ready, 2 = harness/setup failure.
import path from 'node:path';
import {
  ROOT, SCREENSHOTS_DIR, parseArgs, sleep, mkdirp,
  ensureServer, probeUrl, isPortFree, takeShot, analyzeImage,
  writeJson, finish,
} from './lib.mjs';
import {
  isAvailable, hostVersion, newTab, closeTab, connect, attachErrorCapture,
  evaluate, snap, waitForExpr, CDP_HOST,
} from './cdp.mjs';

const READY_EXPR = (timeoutMs) => `new Promise(resolve => {
  if (window.__pvzReady === true) return resolve('ready');
  let n = 0;
  const max = ${Math.max(20, Math.ceil(timeoutMs / 100))};
  const t = setInterval(() => {
    n++;
    if (window.__pvzReady === true) { clearInterval(t); resolve('ready'); }
    else if ((window.__pvzErrors || []).length > 0) { clearInterval(t); resolve('errors'); }
    else if (n > max) { clearInterval(t); resolve('timeout'); }
  }, 100);
})`;

const MENU_EXPR = `new Promise(resolve => {
  let n = 0;
  const t = setInterval(() => {
    n++;
    const m = document.getElementById('main-menu-screen');
    const vis = !!m && getComputedStyle(m).display !== 'none';
    if (vis && document.querySelectorAll('.level-card-btn').length >= 3) { clearInterval(t); resolve('menu'); }
    else if (n > 400) { clearInterval(t); resolve('timeout'); }
  }, 100);
})`;

const DEFAULT_OUT = {
  shot: 'screenshots/web_3d_gameplay.png',
  baseline2d: 'screenshots/web_2d_baseline.png',
  menu: 'screenshots/web_3d_menu.png',
  pause: 'screenshots/web_3d_pause.png',
};

const LEGACY_2D_SETUP = `(() => {
  const out = { ok: false };
  try {
    if (typeof grid === 'undefined' || typeof spawnZombie !== 'function') {
      out.reason = 'legacy 2D globals not found (page is not the archived 2D version)';
      return out;
    }
    const place = (id, row, col, extra = {}) => {
      const def = PLANT_DEFS.find((d) => d.id === id);
      if (!def) return;
      grid[row][col] = {
        def, row, col,
        x: GRID_X + col * CELL_W + CELL_W / 2,
        y: GRID_Y + row * CELL_H + CELL_H / 2,
        hp: def.hp, maxHp: def.hp,
        attackTimer: 0.5, produceTimer: 7.0, fuseTimer: 1.0,
        armed: false, armTimer: 14.0, chewing: false, chewTimer: 0,
        ...extra,
      };
    };
    place('peashooter', 2, 1); place('sunflower', 2, 2); place('wallnut', 1, 3);
    place('snow_pea', 3, 1); place('chomper', 0, 2); place('potato_mine', 4, 2, { armed: true });
    for (const [type, lane, x] of [['normal', 2, 830], ['conehead', 1, 900], ['buckethead', 3, 960], ['flag', 0, 870]]) {
      spawnZombie(type, lane);
      const z = zombies[zombies.length - 1];
      if (z) z.x = x;
    }
    sunItems.push({ x: 640, y: 300, targetY: 300, lifetime: 60, bobOffset: 0 });
    sunItems.push({ x: 520, y: 430, targetY: 430, lifetime: 60, bobOffset: 0 });
    gameState = 'PLAYING';
    out.ok = true;
    out.plants = grid.flat().filter(Boolean).length;
    out.zombies = zombies.length;
    return out;
  } catch (e) {
    out.reason = String((e && e.stack) || e);
    return out;
  }
})()`;

function toBrowserBase(base) {
  // The browser runs on the Windows host: WSL localhost forwarding works for
  // 127.0.0.1 servers, but 'localhost' is the safest hostname for it.
  return base.replace('127.0.0.1', 'localhost');
}

async function pickServer(args) {
  const start = Number(args.port || 8123);
  const proto = '/web_preview/index.html';
  for (let port = start; port < start + 15; port++) {
    const free = await isPortFree(port);
    if (free) {
      const srv = await ensureServer({ port });
      return srv;
    }
    // Port busy: reuse it only if it already serves the preview page.
    if (await probeUrl(`http://127.0.0.1:${port}${proto}`)) {
      return { base: `http://127.0.0.1:${port}`, pageUrl: `http://127.0.0.1:${port}${proto}`, started: false, port, stop: async () => {} };
    }
  }
  throw new Error(`no free/HTTP port in range ${start}..${start + 14}`);
}

function pageUrlFor(server, mode, args) {
  if (typeof args.url === 'string') return args.url;
  const base = toBrowserBase(server.base);
  if (mode === 'shot' || mode === 'pause') {
    let u = `${base}/web_preview/index.html?shot=1`;
    if (args.level !== undefined && args.level !== true) u += `&level=${encodeURIComponent(args.level)}`;
    if (args['via-menu']) u = `${base}/web_preview/index.html`;
    return u;
  }
  if (mode === 'baseline2d') return `${base}/screenshots/baseline_web/index.html`;
  return `${base}/web_preview/index.html`;
}

async function snapshot(cdp) {
  try {
    return await evaluate(cdp, `(() => {
      const p = window.__pvz || null;
      const dbg = window.__pvzDebug || null;
      const out = {
        hasPvz: !!p,
        hasPvzDebug: !!dbg,
        ready: window.__pvzReady === true,
        pvzErrors: Array.isArray(window.__pvzErrors) ? window.__pvzErrors.slice(0, 20) : null,
      };
      if (p) {
        try { out.state = p.state; out.sun = p.sun; out.level = p.level; } catch (e) { out.stateErr = String(e); }
        try {
          const g = p.getGrid ? p.getGrid() : null;
          out.counts = {
            plants: Array.isArray(g) ? g.flat().filter(Boolean).length : null,
            zombies: (p.getZombies ? p.getZombies() : []).length,
            suns: (p.getSuns ? p.getSuns() : []).length,
          };
        } catch (e) { out.countsErr = String(e); }
      }
      const sunEl = document.getElementById('sun-count');
      out.hudSun = sunEl ? sunEl.textContent.trim() : null;
      const menu = document.getElementById('main-menu-screen');
      out.menuVisible = menu ? getComputedStyle(menu).display !== 'none' : null;
      const pause = document.getElementById('pause-modal');
      out.pauseVisible = pause ? getComputedStyle(pause).display !== 'none' : null;
      out.webgl2 = (() => { try { return !!document.createElement('canvas').getContext('webgl2'); } catch (e) { return false; } })();
      return out;
    })()`);
  } catch (e) {
    return { error: String((e && e.message) || e).slice(0, 1500) };
  }
}

function finalize(summary) {
  const assessed = summary.pvz && Array.isArray(summary.pvz.pvzErrors) ? summary.pvz.pvzErrors : [];
  const errs = summary.errors || {};
  const total = (errs.exceptions || []).length + (errs.console || []).length + (errs.log || []).length
    + (errs.crashes || []).length + assessed.length;
  summary.errorCount = total;
  return total;
}

async function main() {
  const args = parseArgs();
  const mode = args.mode || 'shot';
  if (!Object.prototype.hasOwnProperty.call(DEFAULT_OUT, mode)) {
    console.error(`unknown --mode ${mode}; expected one of ${Object.keys(DEFAULT_OUT).join(', ')}`);
    process.exit(2);
  }
  const out = path.isAbsolute(args.out || DEFAULT_OUT[mode]) ? (args.out || DEFAULT_OUT[mode]) : path.join(ROOT, args.out || DEFAULT_OUT[mode]);
  const out2Default = path.join(SCREENSHOTS_DIR, 'web_3d_from_menu.png');
  const out2 = path.isAbsolute(args.out2 || out2Default) ? (args.out2 || out2Default) : path.join(ROOT, args.out2 || out2Default);
  const settleMs = args.settle !== undefined ? Number(args.settle) : 900;
  const timeoutMs = args.timeout !== undefined ? Number(args.timeout) : 120000;
  const startedAt = Date.now();
  const warnings = [];
  const summary = { ok: false, mode, out: path.relative(ROOT, out), startedAt: new Date().toISOString(), cdpHost: CDP_HOST };

  let server = null;
  let tab = null;
  let cdp = null;
  let exitCode = 1;
  let capture = null;

  try {
    if (!(await isAvailable())) {
      throw new Error(`host Chrome CDP not reachable at ${CDP_HOST}. Start it on the Windows host with --remote-debugging-port=9222 (see tools/verify/README.md).`);
    }
    summary.host = await hostVersion();
    server = await pickServer(args);
    summary.server = { base: server.base, startedByHarness: !!server.started };

    tab = await newTab();
    summary.tabId = tab.id;
    cdp = connect(tab.webSocketDebuggerUrl);
    await cdp.ready;
    capture = attachErrorCapture(cdp);
    await cdp.send('Runtime.enable');
    await cdp.send('Log.enable');
    await cdp.send('Page.enable');
    await cdp.send('Emulation.setDeviceMetricsOverride', { width: 1280, height: 720, deviceScaleFactor: 1, mobile: false });

    const url = pageUrlFor(server, mode, args);
    summary.url = url;
    const navStart = Date.now();
    await cdp.send('Page.navigate', { url });
    await sleep(500);
    summary.navMs = Date.now() - navStart;

    if (mode === 'baseline2d') {
      const ready = await waitForExpr(cdp, MENU_EXPR, 30000);
      if (ready !== 'menu') throw new Error(`archived 2D page did not show the main menu (${ready})`);
      await sleep(400);
      const menuShot = await snap(cdp, path.join(SCREENSHOTS_DIR, 'web_2d_menu_baseline.png'));
      await evaluate(cdp, `document.querySelector('.level-card-btn').click()`);
      await sleep(600);
      const setup = await evaluate(cdp, LEGACY_2D_SETUP);
      summary.baseline = { menuShot: path.relative(ROOT, menuShot.path), menuBytes: menuShot.bytes, setup };
      await sleep(Math.max(1200, settleMs + 1000));
      const shot = await snap(cdp, out);
      summary.png = { bytes: shot.bytes };
      if (!args['no-analyze']) {
        summary.imageStats = analyzeImage(shot.path);
        summary.menuImageStats = analyzeImage(menuShot.path);
      }
      summary.ok = !!(setup && setup.ok);
      if (!summary.ok) summary.error = `legacy 2D setup failed: ${setup && setup.reason}`;
      exitCode = summary.ok ? 0 : 1;
    } else if (mode === 'menu') {
      const menuReady = await waitForExpr(cdp, MENU_EXPR, 30000);
      if (menuReady !== 'menu') throw new Error(`main menu did not render (${menuReady})`);
      await sleep(settleMs);
      const shot = await snap(cdp, out);
      summary.png = { bytes: shot.bytes };
      if (!args['no-analyze']) summary.imageStats = analyzeImage(shot.path);
      // Transition test: click the first level card, expect the 3D level to boot.
      await evaluate(cdp, `document.querySelector('.level-card-btn').click()`);
      const t = Date.now();
      const ready = await waitForExpr(cdp, READY_EXPR(timeoutMs), timeoutMs + 8000);
      await sleep(settleMs);
      const pvz = await snapshot(cdp);
      summary.transition = { ready: ready === 'ready', result: ready, waitedMs: Date.now() - t, pvz };
      const shot2 = await snap(cdp, out2);
      summary.out2 = path.relative(ROOT, shot2.path);
      summary.png2 = { bytes: shot2.bytes };
      if (!args['no-analyze']) summary.imageStats2 = analyzeImage(out2);
      summary.ok = ready === 'ready' && pvz.state === 'PLAYING';
      if (ready !== 'ready') warnings.push(`level did not become ready within ${timeoutMs}ms after clicking the level card (${ready})`);
      if (pvz.state !== 'PLAYING') warnings.push(`unexpected game state after level select: ${pvz.state}`);
      exitCode = summary.ok ? 0 : 1;
    } else if (mode === 'pause') {
      const ready = await waitForExpr(cdp, READY_EXPR(timeoutMs), timeoutMs + 8000);
      summary.ready = ready === 'ready';
      await sleep(settleMs);
      await evaluate(cdp, `(() => { const b = document.getElementById('hud-menu-btn'); if (b) b.click(); return true; })()`);
      await sleep(600);
      const pvz = await snapshot(cdp);
      summary.pvz = pvz;
      summary.pauseState = { modalVisible: pvz.pauseVisible, state: pvz.state };
      const shot = await snap(cdp, out);
      summary.png = { bytes: shot.bytes };
      if (!args['no-analyze']) summary.imageStats = analyzeImage(shot.path);
      // resume so the tab is left in a sane state
      await evaluate(cdp, `(() => { if (typeof resumeGame === 'function') resumeGame(); return window.gameState; })()`).catch(() => {});
      summary.ok = ready === 'ready' && pvz.pauseVisible === true;
      if (ready !== 'ready') warnings.push(`__pvzReady never became true (${ready})`);
      if (pvz.pauseVisible !== true) warnings.push('pause modal did not open after clicking #hud-menu-btn');
      exitCode = summary.ok ? 0 : 1;
    } else {
      // shot mode
      if (args['via-menu']) {
        const menuReady = await waitForExpr(cdp, MENU_EXPR, 30000);
        if (menuReady !== 'menu') throw new Error('main menu did not render');
        await evaluate(cdp, `document.querySelector('.level-card-btn').click()`);
      }
      const ready = await waitForExpr(cdp, READY_EXPR(timeoutMs), timeoutMs + 8000);
      summary.ready = ready === 'ready';
      await sleep(settleMs);
      const pvz = await snapshot(cdp);
      summary.pvz = pvz;
      const shot = await snap(cdp, out);
      summary.png = { bytes: shot.bytes };
      if (!args['no-analyze']) summary.imageStats = analyzeImage(shot.path);
      if (ready !== 'ready') warnings.push(`window.__pvzReady not set within ${timeoutMs}ms (${ready})`);
      if (!pvz.hasPvz) warnings.push('window.__pvz test API is missing (spec §5 requires it)');
      else if (!Array.isArray(pvz.pvzErrors)) warnings.push('window.__pvzErrors array is missing (spec §5 requires it)');
      summary.ok = ready === 'ready' && !!pvz.hasPvz && pvz.state === 'PLAYING';
      exitCode = summary.ok ? 0 : 1;
    }

    summary.errors = {
      exceptions: capture.exceptions,
      console: capture.consoleErrors,
      log: capture.logErrors,
      crashes: capture.crashes,
    };
    summary.consoleWarnings = capture.consoleWarnings.slice(0, 20);
    const errCount = finalize(summary);
    if (errCount > 0) {
      warnings.push(`${errCount} page error(s) captured (see summary.errors)`);
      summary.ok = false;
      exitCode = 1;
    }
    if (summary.imageStats && summary.imageStats.likelyBlank) {
      warnings.push('screenshot appears blank/black');
      summary.ok = false;
      exitCode = 1;
    }
  } catch (e) {
    summary.fatal = String((e && e.stack) || e);
    warnings.push(`harness failure: ${summary.fatal}`);
    exitCode = 2;
  } finally {
    try { if (cdp) cdp.close(); } catch { /* ignore */ }
    if (tab) await closeTab(tab.id);
    if (server && server.started && !args['keep-server']) await server.stop();
  }

  summary.warnings = warnings;
  summary.elapsedMs = Date.now() - startedAt;
  if (typeof args.json === 'string') writeJson(path.resolve(ROOT, args.json), summary);
  process.exit(finish(summary, exitCode));
}

main().catch((e) => {
  console.error('FATAL', e);
  process.exit(2);
});
