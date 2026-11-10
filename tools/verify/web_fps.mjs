#!/usr/bin/env node
// tools/verify/web_fps.mjs — measure real rendered FPS of the 3D web preview in the
// host headless Chrome (WARP). Usage: node tools/verify/web_fps.mjs [--url-base URL]
import { ROOT, parseArgs, writeJson } from './lib.mjs';
import { isAvailable, newTab, closeTab, connect, attachErrorCapture, evaluate, waitForExpr, CDP_HOST, CDP_HOST as H } from './cdp.mjs';

const args = parseArgs();
const BASE = (typeof args['url-base'] === 'string' ? args['url-base'] : 'http://localhost:8121').replace(/\/$/, '');
const summary = { ok: false, cdpHost: CDP_HOST, url: BASE + '/web_preview/index.html?shot=1' };
let tab = null;
let cdp = null;
try {
  if (!(await isAvailable())) throw new Error(`host Chrome CDP not reachable at ${H}`);
  tab = await newTab();
  cdp = connect(tab.webSocketDebuggerUrl);
  await cdp.ready;
  const cap = attachErrorCapture(cdp);
  await cdp.send('Runtime.enable'); await cdp.send('Log.enable'); await cdp.send('Page.enable');
  await cdp.send('Emulation.setDeviceMetricsOverride', { width: 1280, height: 720, deviceScaleFactor: 1, mobile: false });
  await cdp.send('Page.navigate', { url: summary.url });
  const ready = await waitForExpr(cdp, `new Promise(r => { if (window.__pvzReady===true) return r('ready'); let n=0; const t=setInterval(()=>{ n++; if(window.__pvzReady===true){clearInterval(t);r('ready');} else if(n>900){clearInterval(t);r('timeout');} },100); })`, 100000);
  await new Promise((r) => setTimeout(r, 800));
  const measured = await evaluate(cdp, `new Promise(resolve => { let n = 0; const t0 = performance.now(); const tick = () => { n++; if (performance.now() - t0 < 2000) requestAnimationFrame(tick); else resolve({ fps: +(n / ((performance.now()-t0)/1000)).toFixed(1), frames: n }); }; requestAnimationFrame(tick); })`);
  const gl = await evaluate(cdp, `(() => { const c = document.createElement('canvas'); const g = c.getContext('webgl2'); const d = g && g.getExtension('WEBGL_debug_renderer_info'); return g ? { webgl2: true, version: g.getParameter(g.VERSION), renderer: d ? g.getParameter(d.UNMASKED_RENDERER_WEBGL) : g.getParameter(g.RENDERER) } : { webgl2: false }; })()`);
  summary.ready = ready;
  summary.fps = measured.fps;
  summary.frames = measured.frames;
  summary.webgl = gl;
  summary.errors = { exceptions: cap.exceptions, console: cap.consoleErrors, log: cap.logErrors };
  summary.ok = ready === 'ready' && measured.fps > 20 && summary.errors.exceptions.length + summary.errors.console.length + summary.errors.log.length === 0;
  console.log(JSON.stringify(summary, null, 2));
  if (typeof args.json === 'string') writeJson(new URL(args.json, 'file://' + ROOT + '/').pathname, summary);
  process.exit(summary.ok ? 0 : 1);
} catch (e) {
  summary.fatal = String((e && e.stack) || e);
  console.error(JSON.stringify(summary, null, 2));
  process.exit(2);
} finally {
  try { if (cdp) cdp.close(); } catch { /* ignore */ }
  if (tab) await closeTab(tab.id);
}
