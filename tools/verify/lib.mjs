// tools/verify/lib.mjs — shared helpers for the PVZ 3D-conversion verification harness.
//
// Owned by: verifier. Usage: import { ... } from './lib.mjs'.
// Requires playwright-core (1.49.1) in <repo>/.tools/node_modules/playwright-core and a
// Chromium build under <repo>/.tools/browsers/chromium-1148/chrome-linux/chrome.
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import fs from 'node:fs';
import http from 'node:http';
import { spawn, execFileSync } from 'node:child_process';

export const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
export const PW_CORE = path.join(ROOT, '.tools/node_modules/playwright-core');
export const BROWSERS_PATH = path.join(ROOT, '.tools/browsers');
export const DEFAULT_BROWSER = path.join(BROWSERS_PATH, 'chromium-1148/chrome-linux/chrome');
export const SCREENSHOTS_DIR = path.join(ROOT, 'screenshots');
export const TMP_DIR = path.join(ROOT, 'tools/verify/tmp');
export const VIEWPORT = { width: 1280, height: 720 };

const requireCJS = createRequire(import.meta.url);

// ---------------------------------------------------------------------------
// small utilities
// ---------------------------------------------------------------------------
export const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

export function mkdirp(dir) {
  fs.mkdirSync(dir, { recursive: true });
}

export function nowStamp() {
  const d = new Date();
  const p = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}${p(d.getMonth() + 1)}${p(d.getDate())}-${p(d.getHours())}${p(d.getMinutes())}${p(d.getSeconds())}`;
}

export function parseArgs(argv = process.argv.slice(2)) {
  const args = { _: [] };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a.startsWith('--')) {
      const key = a.slice(2);
      const next = argv[i + 1];
      if (next === undefined || next.startsWith('--')) {
        args[key] = true;
      } else {
        args[key] = next;
        i++;
      }
    } else {
      args._.push(a);
    }
  }
  return args;
}

export function loadPlaywright() {
  process.env.PLAYWRIGHT_BROWSERS_PATH = BROWSERS_PATH;
  return requireCJS(PW_CORE);
}

// ---------------------------------------------------------------------------
// static server management (python3 serve.py, same handler as production)
// ---------------------------------------------------------------------------
export function probeUrl(url, timeoutMs = 2000) {
  return new Promise((resolve) => {
    const req = http.get(url, { timeout: timeoutMs }, (res) => {
      res.resume();
      resolve(res.statusCode !== undefined && res.statusCode < 500);
    });
    req.on('timeout', () => { req.destroy(); resolve(false); });
    req.on('error', () => resolve(false));
  });
}

export async function waitForUrl(url, timeoutMs = 20000, intervalMs = 200) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    if (await probeUrl(url)) return true;
    await sleep(intervalMs);
  }
  return false;
}

/**
 * Ensure the dev server is reachable. Starts `python3 serve.py <port>` in the repo
 * root when not already running (unless opts.url is given: then it must already be up).
 * Returns { base, pageUrl, started, stop() }.
 */
export async function ensureServer(opts = {}) {
  const port = Number(opts.port || 8123);
  const explicitUrl = opts.url || null;
  const pagePath = opts.pagePath || '/web_preview/index.html';
  let child = null;
  let started = false;
  let stopped = false;

  let base;
  let target;
  if (explicitUrl) {
    const u = new URL(explicitUrl);
    base = `${u.protocol}//${u.host}`;
    target = explicitUrl;
    if (!(await waitForUrl(target, 1500))) {
      // Allow a local URL served from the repo root: start our managed server.
      const host = u.hostname;
      const local = host === '127.0.0.1' || host === 'localhost';
      if (!local) throw new Error(`Explicit --url is not reachable: ${target}`);
      const p2 = Number(u.port || 80);
      const log = [];
      child = spawn('python3', ['serve.py', String(p2)], { cwd: ROOT, stdio: ['ignore', 'pipe', 'pipe'] });
      child.stdout.on('data', (d) => log.push(String(d)));
      child.stderr.on('data', (d) => log.push(String(d)));
      child.on('error', (e) => log.push(`spawn error: ${e}`));
      if (!(await waitForUrl(target, opts.timeoutMs || 20000))) {
        try { child.kill('SIGKILL'); } catch { /* ignore */ }
        throw new Error(`Explicit --url is not reachable and serve.py could not serve it: ${target}\nlog:\n${log.join('').slice(-3000)}`);
      }
      started = true;
    }
  } else {
    base = `http://127.0.0.1:${port}`;
    target = `${base}${pagePath}`;
    if (!(await probeUrl(target))) {
      const log = [];
      child = spawn('python3', ['serve.py', String(port)], {
        cwd: ROOT,
        stdio: ['ignore', 'pipe', 'pipe'],
      });
      child.stdout.on('data', (d) => log.push(String(d)));
      child.stderr.on('data', (d) => log.push(String(d)));
      child.on('error', (e) => log.push(`spawn error: ${e}`));
      const ok = await waitForUrl(target, opts.timeoutMs || 20000);
      if (!ok) {
        try { child.kill('SIGKILL'); } catch { /* ignore */ }
        throw new Error(`serve.py failed to start on port ${port}.\nlog:\n${log.join('').slice(-4000)}`);
      }
      started = true;
    }
  }

  const stop = async () => {
    if (stopped) return;
    stopped = true;
    if (!child || !started) return;
    try { child.kill('SIGTERM'); } catch { /* ignore */ }
    await sleep(300);
    try { child.kill('SIGKILL'); } catch { /* ignore */ }
  };
  return { base, pageUrl: target, started, port, stop };
}

// ---------------------------------------------------------------------------
// Chromium / page helpers
// ---------------------------------------------------------------------------
export function chromiumArgs(extra = []) {
  return [
    '--no-sandbox',
    '--disable-setuid-sandbox',
    '--disable-dev-shm-usage',
    '--disable-gpu-sandbox',
    // Software WebGL that works without a GPU in headless Chromium (SwiftShader).
    '--enable-unsafe-swiftshader',
    '--use-gl=angle',
    '--use-angle=swiftshader',
    '--enable-webgl',
    '--ignore-gpu-blocklist',
    '--hide-scrollbars',
    '--mute-audio',
    '--force-device-scale-factor=1',
    '--disable-background-timer-throttling',
    '--disable-renderer-backgrounding',
    '--disable-backgrounding-occluded-windows',
    ...extra,
  ];
}

export const TOOLS_LIB_DIR = path.join(ROOT, '.tools/libs/usr/lib');
export const BROWSER_HOME = path.join(ROOT, '.tools/verify-home');

function chromiumEnv() {
  // Chromium needs a few Arch libs that are not installed system-wide
  // (libatk/atspi/libcups/libXcomposite/libXdamage/libxkbcommon/libavahi);
  // they are vendored under .tools/libs (same trick the Godot recipe uses).
  const env = { ...process.env };
  if (fs.existsSync(TOOLS_LIB_DIR)) {
    const parts = (env.LD_LIBRARY_PATH || '').split(':').filter(Boolean);
    if (!parts.includes(TOOLS_LIB_DIR)) parts.unshift(TOOLS_LIB_DIR);
    env.LD_LIBRARY_PATH = parts.join(':');
  }
  // The DSH file sandbox makes $HOME read-only; Chromium's crashpad handler
  // aborts (SIGTRAP) when it cannot create its database. Give the browser a
  // writable HOME/XDG tree inside the workspace.
  mkdirp(BROWSER_HOME);
  env.HOME = BROWSER_HOME;
  env.XDG_CONFIG_HOME = path.join(BROWSER_HOME, '.config');
  env.XDG_CACHE_HOME = path.join(BROWSER_HOME, '.cache');
  env.XDG_DATA_HOME = path.join(BROWSER_HOME, '.local/share');
  env.XDG_STATE_HOME = path.join(BROWSER_HOME, '.local/state');
  for (const d of [env.XDG_CONFIG_HOME, env.XDG_CACHE_HOME, env.XDG_DATA_HOME, env.XDG_STATE_HOME]) {
    mkdirp(d);
  }
  return env;
}

export function freePort() {
  return new Promise((resolve, reject) => {
    const srv = requireCJS('node:net').createServer();
    srv.unref();
    srv.on('error', reject);
    srv.listen(0, '127.0.0.1', () => {
      const port = srv.address().port;
      srv.close(() => resolve(port));
    });
  });
}

/**
 * Launch a headless Chromium with WebGL support and return a Playwright Browser.
 *
 * Note: Playwright's own `chromium.launch()` does not work in this environment
 * (new-headless renderer never becomes responsive and page.goto() times out), so
 * we spawn Chromium manually with --remote-debugging-port and attach over CDP.
 * That path is validated here and gives WebGL2 (ANGLE / Microsoft Basic Render
 * Driver; SwiftShader flags kept as fallback).
 */
export async function launchChromium(opts = {}) {
  const pw = loadPlaywright();
  const executablePath = opts.executablePath || process.env.CHROME_BIN || DEFAULT_BROWSER;
  if (!fs.existsSync(executablePath)) {
    throw new Error(
      `Chromium binary missing: ${executablePath}\n` +
      `Download chromium 1148 into .tools/browsers (see tools/verify/README.md).`
    );
  }
  const env = chromiumEnv();
  const port = await freePort();
  const stamp = `${process.pid}-${Date.now()}`;
  const profileDir = path.join(BROWSER_HOME, 'profiles', stamp);
  mkdirp(profileDir);
  const gpuArgs = opts.software
    // Software compositing only: the GPU process is broken in the DSH bwrap
    // sandbox (hangs in early startup), but software compositing still lets
    // pages load and screenshot. WebGL is NOT available in this mode.
    ? ['--disable-gpu', '--disable-software-rasterizer']
    : chromiumArgs(opts.args || []);
  const args = [
    ...(opts.headless === false ? [] : ['--headless=new']),
    ...gpuArgs,
    `--window-size=${(opts.viewport || VIEWPORT).width},${(opts.viewport || VIEWPORT).height}`,
    `--remote-debugging-port=${port}`,
    '--remote-allow-origins=*',
    `--user-data-dir=${profileDir}`,
    'about:blank',
  ];
  const child = spawn(executablePath, args, { env, stdio: ['ignore', 'ignore', 'pipe'] });
  let stderrTail = '';
  child.stderr.on('data', (d) => { stderrTail = (stderrTail + String(d)).slice(-8000); });
  process.env.DSH_CHROME_PID = String(child.pid ?? '');

  const endpoint = `http://127.0.0.1:${port}`;
  const deadline = Date.now() + (opts.launchTimeoutMs || 40000);
  let up = false;
  while (Date.now() < deadline) {
    if (child.exitCode !== null) break;
    try {
      if (await probeUrl(`${endpoint}/json/version`, 1000)) { up = true; break; }
    } catch { /* retry */ }
    await sleep(250);
  }
  if (!up) {
    try { child.kill('SIGKILL'); } catch { /* ignore */ }
    throw new Error(`Chromium CDP endpoint did not come up on ${endpoint}.\nstderr tail:\n${stderrTail.slice(-2500)}`);
  }
  const browser = await pw.chromium.connectOverCDP(endpoint);
  const origClose = browser.close.bind(browser);
  browser.close = async () => {
    try { await origClose(); } catch { /* ignore */ }
    try { child.kill('SIGKILL'); } catch { /* ignore */ }
    try { fs.rmSync(profileDir, { recursive: true, force: true }); } catch { /* ignore */ }
  };
  return browser;
}

/**
 * Create a 1280x720 page with console/pageerror/network diagnostics attached.
 * Returns { page, diag } where diag has live arrays + a summarize() helper.
 */
export async function newDiagnosticPage(browser, opts = {}) {
  // Over CDP, creating isolated browser contexts can wedge the renderer in this
  // environment; reuse the default context (created by our chrome command line)
  // and set the viewport per page instead.
  const isolated = opts.isolatedContext === true;
  let context;
  if (!isolated) {
    const ctxs = browser.contexts();
    context = ctxs.length > 0 ? ctxs[0] : await browser.newContext({ viewport: opts.viewport || VIEWPORT });
  } else {
    context = await browser.newContext({
      viewport: opts.viewport || VIEWPORT,
      deviceScaleFactor: opts.deviceScaleFactor || 1,
      hasTouch: !!opts.hasTouch,
      isMobile: !!opts.isMobile,
      ignoreHTTPSErrors: true,
    });
  }
  const page = await context.newPage();
  try { await page.setViewportSize(opts.viewport || VIEWPORT); } catch { /* ignore */ }
  const diag = attachDiagnostics(page, opts);
  return { context, page, diag };
}

const BENIGN_URL_RE = [/favicon\.ico/i, /chrome-extension:/i];

export function attachDiagnostics(page, opts = {}) {
  const ignoreConsole = (opts.ignoreConsole || []).map(toRe);
  const ignoreUrls = (opts.ignoreUrls || []).map(toRe);
  const diag = {
    consoleErrors: [],
    consoleWarnings: [],
    pageErrors: [],
    failedRequests: [],
    requestCount: 0,
  };
  const benign = (u) => BENIGN_URL_RE.some((re) => re.test(u)) || ignoreUrls.some((re) => re.test(u));
  const keep = (txt) => !ignoreConsole.some((re) => re.test(txt));

  page.on('console', (msg) => {
    const text = msg.text();
    if (msg.type() === 'error') {
      if (keep(text)) diag.consoleErrors.push(text);
    } else if (msg.type() === 'warning') {
      diag.consoleWarnings.push(text);
    }
  });
  page.on('pageerror', (err) => {
    diag.pageErrors.push(String((err && err.stack) || err));
  });
  page.on('request', () => { diag.requestCount++; });
  page.on('requestfailed', (req) => {
    if (benign(req.url())) return;
    diag.failedRequests.push(`requestfailed ${req.method()} ${req.url()} :: ${req.failure() && req.failure().errorText}`);
  });
  page.on('response', (res) => {
    if (res.status() >= 400 && !benign(res.url())) {
      diag.failedRequests.push(`http ${res.status()} ${res.url()}`);
    }
  });
  diag.hasErrors = () => diag.consoleErrors.length + diag.pageErrors.length + diag.failedRequests.length > 0;
  return diag;
}

function toRe(v) {
  return v instanceof RegExp ? v : new RegExp(String(v));
}

/** WebGL capability probe inside the page (uses throw-away canvases). */
export async function webglInfo(page) {
  try {
    return await page.evaluate(() => {
      const probe = (kind) => {
        const c = document.createElement('canvas');
        c.width = 64; c.height = 64;
        const gl = c.getContext(kind);
        if (!gl) return { ok: false };
        const dbg = gl.getExtension('WEBGL_debug_renderer_info');
        const out = {
          ok: true,
          kind,
          version: gl.getParameter(gl.VERSION),
          shadingLanguage: gl.getParameter(gl.SHADING_LANGUAGE_VERSION),
          vendor: gl.getParameter(gl.VENDOR),
          renderer: gl.getParameter(gl.RENDERER),
          unmaskedVendor: dbg ? gl.getParameter(dbg.UNMASKED_VENDOR_WEBGL) : null,
          unmaskedRenderer: dbg ? gl.getParameter(dbg.UNMASKED_RENDERER_WEBGL) : null,
          maxTextureSize: gl.getParameter(gl.MAX_TEXTURE_SIZE),
        };
        const lose = gl.getExtension('WEBGL_lose_context');
        if (lose) lose.loseContext();
        return out;
      };
      return { webgl2: probe('webgl2'), webgl1: probe('webgl') };
    });
  } catch (e) {
    return { error: String((e && e.message) || e) };
  }
}

/**
 * Save a viewport screenshot and return { path, bytes, via }.
 *
 * In this sandbox the Chromium compositor screenshot path can hang. Fallback:
 * serialize the game <canvas> from inside the page (2D canvases always work;
 * WebGL canvases only if preserveDrawingBuffer is set). The fallback captures
 * the canvas only (no DOM HUD overlay), so callers should prefer `screenshot`.
 */
export async function takeShot(page, outPath, opts = {}) {
  mkdirp(path.dirname(outPath));
  const timeout = opts.timeoutMs || 20000;
  try {
    const p = page.screenshot({ path: outPath, type: 'png', fullPage: false, animations: 'disabled', timeout });
    await p;
    const stat = fs.statSync(outPath);
    return { path: outPath, bytes: stat.size, via: 'screenshot' };
  } catch (e) {
    if (opts.noCanvasFallback) throw e;
    const dataUrl = await page.evaluate(() => {
      const c = document.querySelector('canvas');
      if (!c) return null;
      try { return c.toDataURL('image/png'); } catch (err) { return null; }
    });
    if (!dataUrl || !dataUrl.startsWith('data:image/png;base64,')) throw e;
    const buf = Buffer.from(dataUrl.slice('data:image/png;base64,'.length), 'base64');
    fs.writeFileSync(outPath, buf);
    return { path: outPath, bytes: buf.length, via: 'canvas-fallback', screenshotError: String((e && e.message) || e) };
  }
}

/**
 * Cheap image sanity metrics via ffmpeg signalstats (no node image deps).
 * Returns null when ffmpeg is unavailable. Used to detect blank/black frames.
 */
export function analyzeImage(file) {
  try {
    const stdout = execFileSync(
      'ffmpeg',
      ['-hide_banner', '-loglevel', 'error', '-i', file,
        '-vf', 'signalstats,metadata=print:file=-', '-frames:v', '1', '-f', 'null', '-'],
      { encoding: 'utf8', timeout: 30000 }
    );
    const vals = {};
    for (const line of stdout.split('\n')) {
      const m = line.match(/^lavfi\.signalstats\.(\w+)=([\d.]+)$/);
      if (m) vals[m[1]] = Number(m[2]);
    }
    if (vals.YAVG === undefined) return null;
    return {
      yAvg: round2(vals.YAVG), yMin: vals.YMIN, yMax: vals.YMAX,
      satAvg: round2(vals.SATAVG),
      uniform: vals.YMAX - vals.YMIN < 6,
      dark: vals.YAVG < 8,
      likelyBlank: vals.YMAX - vals.YMIN < 6 || vals.YAVG < 8,
    };
  } catch {
    return null;
  }
}

function round2(n) { return Math.round(n * 100) / 100; }

/** Wait until window.__pvzReady is true. Returns { ready, waitedMs } (never throws). */
export async function waitForPvzReady(page, timeoutMs = 45000) {
  const t0 = Date.now();
  try {
    await page.waitForFunction(() => window.__pvzReady === true, null, { timeout: timeoutMs, polling: 150 });
    return { ready: true, waitedMs: Date.now() - t0 };
  } catch {
    return { ready: false, waitedMs: Date.now() - t0 };
  }
}

/** Snapshot of the page-side debug hooks + counts (all optional-safe). */
export async function pvzSnapshot(page) {
  try {
    return await page.evaluate(() => {
      const out = {
        hasPvz: typeof window.__pvz === 'object' && window.__pvz !== null,
        ready: window.__pvzReady === true,
        pvzErrors: Array.isArray(window.__pvzErrors) ? window.__pvzErrors.slice() : null,
      };
      out.keys = out.hasPvz ? Object.keys(window.__pvz) : [];
      const p = window.__pvz;
      if (p) {
        out.state = typeof p.state === 'function' ? p.state() : (p.state ?? null);
        const safe = (fn, fallback) => {
          try { return typeof fn === 'function' ? fn() : fallback; } catch (e) { return { error: String(e) }; }
        };
        const grid = safe(p.getGrid, null);
        out.counts = {
          grid: Array.isArray(grid) && Array.isArray(grid[0])
            ? grid.flat().filter(Boolean).length
            : (grid && typeof grid === 'object' ? Object.keys(grid).length : null),
          zombies: safe(p.getZombies, null),
          suns: safe(p.getSuns, null),
        };
        const z = out.counts.zombies;
        const s = out.counts.suns;
        if (Array.isArray(z)) { out.counts.zombies = z.length; out.zombieSample = z.slice(0, 5); }
        if (Array.isArray(s)) { out.counts.suns = s.length; out.sunSample = s.slice(0, 5); }
      }
      const sunEl = document.getElementById('sun-count');
      out.hudSun = sunEl ? sunEl.textContent.trim() : null;
      const menu = document.getElementById('main-menu-screen');
      out.menuVisible = menu ? getComputedStyle(menu).display !== 'none' : null;
      out.gameState = (typeof window.gameState !== 'undefined') ? window.gameState : null;
      return out;
    });
  } catch (e) {
    return { error: String((e && e.message) || e) };
  }
}

/** Aggregate console/pageerror/pvzErrors into a pass/fail assessment. */
export function assessErrors(diag, pvz) {
  const pvzErrors = (pvz && Array.isArray(pvz.pvzErrors)) ? pvz.pvzErrors : [];
  const errors = {
    console: diag.consoleErrors.slice(),
    page: diag.pageErrors.slice(),
    pvz: pvzErrors.slice(),
    requests: diag.failedRequests.slice(),
  };
  const count = Object.values(errors).reduce((n, arr) => n + arr.length, 0);
  return { errors, count, ok: count === 0 };
}

export function writeJson(file, data) {
  mkdirp(path.dirname(file));
  fs.writeFileSync(file, JSON.stringify(data, null, 2) + '\n');
}

/** Print the final JSON summary to stdout and return the desired process exit code. */
export function finish(summary, code) {
  process.stdout.write(JSON.stringify(summary, null, 2) + '\n');
  return code;
}

/** True when nothing is bound to 127.0.0.1:port. */
export function isPortFree(port) {
  return new Promise((resolve) => {
    const srv = requireCJS('node:net').createServer();
    srv.once('error', () => resolve(false));
    srv.once('listening', () => srv.close(() => resolve(true)));
    srv.listen(port, '127.0.0.1');
  });
}
