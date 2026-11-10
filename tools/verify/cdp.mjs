// tools/verify/cdp.mjs — raw Chrome DevTools Protocol client for the HOST headless Chrome.
//
// WHY: the local Chromium in this sandbox cannot bring up its GPU process (WebGL
// dead end), and Playwright-managed navigation hangs here too. The host (Windows)
// headless Chrome exposes CDP on 127.0.0.1:9222, has working WebGL2 (ANGLE/D3D11)
// and screenshots via Page.captureScreenshot. This client is deliberately tiny:
//   newTab() -> ws url -> connect() -> send()/on() -> evaluate()/snap()
//
// Env: PVZ_CDP_HOST (default http://127.0.0.1:9222)
import fs from 'node:fs';
import path from 'node:path';

export const CDP_HOST = process.env.PVZ_CDP_HOST || 'http://127.0.0.1:9222';

export function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

/** True when the host Chrome CDP endpoint answers. */
export async function isAvailable(timeoutMs = 3000) {
  try {
    const ctrl = new AbortController();
    const t = setTimeout(() => ctrl.abort(), timeoutMs);
    const res = await fetch(`${CDP_HOST}/json/version`, { signal: ctrl.signal });
    clearTimeout(t);
    return res.ok;
  } catch {
    return false;
  }
}

export async function hostVersion() {
  const res = await fetch(`${CDP_HOST}/json/version`);
  if (!res.ok) throw new Error(`CDP version endpoint HTTP ${res.status}`);
  return res.json();
}

/** Open a new tab; returns { id, webSocketDebuggerUrl, ... }. */
export async function newTab(url = 'about:blank') {
  const res = await fetch(`${CDP_HOST}/json/new?${encodeURIComponent(url)}`, { method: 'PUT' });
  if (!res.ok) throw new Error(`CDP /json/new failed HTTP ${res.status}`);
  const tab = await res.json();
  if (!tab.webSocketDebuggerUrl) throw new Error(`CDP /json/new returned no webSocketDebuggerUrl: ${JSON.stringify(tab).slice(0, 300)}`);
  return tab;
}

export async function closeTab(id) {
  try { await fetch(`${CDP_HOST}/json/close/${id}`); } catch { /* ignore */ }
}

/**
 * Connect to a tab websocket. Returns { ready, send(method, params), on(method, cb),
 * events, close() }. `events[method]` keeps the last payload; capture errors with
 * attachErrorCapture().
 */
export function connect(wsUrl) {
  const ws = new WebSocket(wsUrl);
  let nextId = 0;
  const pending = new Map();
  const listeners = new Map();
  const events = {};
  const ready = new Promise((resolve, reject) => {
    ws.onopen = () => resolve();
    ws.onerror = (e) => reject(new Error(`CDP websocket error: ${e && (e.message || e.type)}`));
  });
  ws.onmessage = (ev) => {
    let msg;
    try { msg = JSON.parse(ev.data); } catch { return; }
    if (msg.id && pending.has(msg.id)) {
      const { resolve, reject } = pending.get(msg.id);
      pending.delete(msg.id);
      if (msg.error) reject(new Error(`CDP ${msg.error.code}: ${msg.error.message}`));
      else resolve(msg.result);
      return;
    }
    if (msg.method) {
      events[msg.method] = msg.params;
      const cbs = listeners.get(msg.method);
      if (cbs) for (const cb of cbs) { try { cb(msg.params); } catch { /* ignore */ } }
    }
  };
  const closed = new Promise((resolve) => { ws.onclose = () => resolve(); });
  return {
    ready,
    closed,
    send(method, params = {}) {
      return new Promise((resolve, reject) => {
        const id = ++nextId;
        pending.set(id, { resolve, reject });
        try { ws.send(JSON.stringify({ id, method, params })); }
        catch (e) { pending.delete(id); reject(e); }
      });
    },
    on(method, cb) {
      if (!listeners.has(method)) listeners.set(method, []);
      listeners.get(method).push(cb);
    },
    events,
    close() { try { ws.close(); } catch { /* ignore */ } },
  };
}

/**
 * Attach error collection for console errors, uncaught exceptions, log errors and
 * target crashes. Call BEFORE navigating; then `Runtime.enable` + `Log.enable`.
 */
export function attachErrorCapture(cdp) {
  const cap = {
    exceptions: [],
    consoleErrors: [],
    logErrors: [],
    crashes: [],
    consoleWarnings: [],
  };
  cdp.on('Runtime.exceptionThrown', (p) => {
    const d = p && p.exceptionDetails;
    if (!d) return;
    const desc = d.exception && (d.exception.description || d.exception.value);
    cap.exceptions.push(String(desc || d.text || 'exception').slice(0, 2000));
  });
  cdp.on('Runtime.consoleAPICalled', (p) => {
    const text = (p.args || []).map((a) => (a.value !== undefined ? a.value : (a.description || a.type))).join(' ').slice(0, 2000);
    if (p.type === 'error') cap.consoleErrors.push(text);
    else if (p.type === 'warning') cap.consoleWarnings.push(text);
  });
  cdp.on('Log.entryAdded', (p) => {
    const e = p && p.entry;
    if (!e || e.level !== 'error') return;
    const url = String(e.url || '');
    const text = String(e.text || '');
    // 404s for favicon / DevTools probes / source-map lookups are benign noise.
    if (/favicon\.ico|DevTools|Autofill|sourcemap|\.map(\?|$)/i.test(url)
      || /favicon\.ico|DevTools|Autofill/i.test(text)) return;
    cap.logErrors.push((url ? `${text} :: ${url}` : text).slice(0, 2000));
  });
  cdp.on('Inspector.targetCrashed', () => cap.crashes.push('target crashed'));
  cap.count = () => cap.exceptions.length + cap.consoleErrors.length + cap.logErrors.length + cap.crashes.length;
  return cap;
}

/** Evaluate an expression in the page; throws on page-side exception. */
export async function evaluate(cdp, expression, opts = {}) {
  const r = await cdp.send('Runtime.evaluate', {
    expression,
    returnByValue: true,
    awaitPromise: true,
    ...opts,
  });
  if (r.exceptionDetails) {
    const d = r.exceptionDetails;
    const desc = d.exception && (d.exception.description || d.exception.value);
    throw new Error(`page evaluate failed: ${desc || d.text || 'unknown'}`);
  }
  return r.result ? r.result.value : undefined;
}

/** Capture a PNG screenshot of the tab to `outPath`; returns { path, bytes }. */
export async function snap(cdp, outPath) {
  fs.mkdirSync(path.dirname(outPath), { recursive: true });
  const r = await cdp.send('Page.captureScreenshot', { format: 'png', fromSurface: true });
  if (!r || !r.data) throw new Error('Page.captureScreenshot returned no data');
  const buf = Buffer.from(r.data, 'base64');
  fs.writeFileSync(outPath, buf);
  return { path: outPath, bytes: buf.length };
}

/** Poll `expression` until it returns a truthy value (or timeout). Returns value|null. */
export async function pollValue(cdp, expression, timeoutMs = 60000, intervalMs = 500) {
  const deadline = Date.now() + timeoutMs;
  let last;
  let lastErr = null;
  while (Date.now() < deadline) {
    try {
      last = await evaluate(cdp, expression);
      if (last) return last;
    } catch (e) { lastErr = e; }
    await sleep(intervalMs);
  }
  if (lastErr) return null;
  return last || null;
}

/** Navigate the tab and wait until the page load event fired. */
export async function navigate(cdp, url, timeoutMs = 60000) {
  await cdp.send('Page.navigate', { url });
  const deadline = Date.now() + timeoutMs;
  let loaded = false;
  cdp.on('Page.loadEventFired', () => { loaded = true; });
  while (Date.now() < deadline) {
    if (loaded) break;
    try { if (await evaluate(cdp, 'document.readyState') === 'complete') { loaded = true; break; } } catch { /* navigating */ }
    await sleep(250);
  }
  return loaded;
}

/**
 * Block on a page-side promise expression (single CDP round-trip instead of
 * polling; the page's rAF loop makes per-call round-trips expensive).
 * Returns the resolved value, or null on timeout/error.
 */
export async function waitForExpr(cdp, expression, timeoutMs = 60000) {
  const timer = sleep(timeoutMs).then(() => null);
  const evalPromise = evaluate(cdp, expression, { awaitPromise: true }).catch(() => null);
  return Promise.race([evalPromise, timer]);
}

/** Pause the page's requestAnimationFrame loop (for cheap screenshots). */
export async function freezeRAF(cdp) {
  await evaluate(cdp, `(() => { window.__pvzRafOrig = window.requestAnimationFrame; window.requestAnimationFrame = () => 0; return true; })()`).catch(() => {});
}
