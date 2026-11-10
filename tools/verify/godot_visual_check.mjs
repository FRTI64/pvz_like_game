#!/usr/bin/env node
// tools/verify/godot_visual_check.mjs — independent pixel-diff visual checks (Godot, windowed):
//   (1) chilled tint:  same zombie before/after apply_chill() must visibly shift blue;
//   (2) armor break:   conehead before/after armor damage must swap billboard sheet and
//                      change the entity's screen pixels (cone prop + sprite swap).
//
// Runs capture_godot.tscn with the tintdiff/armordiff setups, crops the entity screen
// region reported by the capture scene, and compares raw RGB via ffmpeg (no image deps).
//
// Usage: node tools/verify/godot_visual_check.mjs [--json tools/verify/evidence/visual_checks.json]
// Exit: 0 = both checks pass, 1 = failure, 2 = harness failure.
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { ROOT, SCREENSHOTS_DIR, parseArgs, mkdirp, writeJson } from './lib.mjs';

const GODOT = process.env.GODOT || '/usr/lib/godot-mono/godot.linuxbsd.editor.x86_64.mono';
const args = parseArgs();
const evidenceDir = path.join(ROOT, 'tools/verify/evidence');
mkdirp(evidenceDir);
const results = [];
const check = (name, ok, detail) => {
  results.push({ name, ok: !!ok, detail });
  console.log(`${ok ? 'PASS' : 'FAIL'} ${name}${detail !== undefined ? ' :: ' + JSON.stringify(detail).slice(0, 500) : ''}`);
};

function runCapture(setup, out) {
  const env = {
    ...process.env,
    LD_LIBRARY_PATH: `${ROOT}/.tools/libs/usr/lib` + (process.env.LD_LIBRARY_PATH ? ':' + process.env.LD_LIBRARY_PATH : ''),
    XKB_CONFIG_ROOT: `${ROOT}/.tools/libs/usr/share/X11/xkb`,
  };
  const res = spawnSync(GODOT, [
    '--path', ROOT, 'tools/verify/capture_godot.tscn',
    '--display-driver', 'wayland', '--rendering-driver', 'opengl3',
    '--', '--setup', setup, '--out', out, '--wait', '1.0',
  ], { cwd: ROOT, env, encoding: 'utf8', timeout: 180000, maxBuffer: 32 * 1024 * 1024 });
  if (res.status !== 0) throw new Error(`capture ${setup} exit ${res.status}\n${(res.stdout || '').slice(-2000)}\n${(res.stderr || '').slice(-2000)}`);
  const lines = (res.stdout || '').split('\n').filter((l) => l.startsWith('VERIFY_CAPTURE_OK '));
  if (lines.length === 0) throw new Error(`capture ${setup} produced no VERIFY_CAPTURE_OK line`);
  return JSON.parse(lines[lines.length - 1].slice('VERIFY_CAPTURE_OK '.length));
}

function rawCrop(file, region) {
  const vf = `crop=${region.w}:${region.h}:${region.x}:${region.y},format=rgb24`;
  const res = spawnSync('ffmpeg', ['-v', 'error', '-i', file, '-vf', vf, '-f', 'rawvideo', '-'], { maxBuffer: 64 * 1024 * 1024 });
  if (res.status !== 0 || !res.stdout) throw new Error(`ffmpeg crop failed for ${file}: ${res.stderr}`);
  return res.stdout;
}

function stats(buf) {
  const n = buf.length / 3;
  let r = 0, g = 0, b = 0;
  for (let i = 0; i < buf.length; i += 3) { r += buf[i]; g += buf[i + 1]; b += buf[i + 2]; }
  return { meanR: r / n, meanG: g / n, meanB: b / n, px: n };
}

function diffStats(a, b) {
  if (a.length !== b.length) throw new Error('crop size mismatch');
  let sum = 0, changed = 0, max = 0;
  for (let i = 0; i < a.length; i += 3) {
    const d = (Math.abs(a[i] - b[i]) + Math.abs(a[i + 1] - b[i + 1]) + Math.abs(a[i + 2] - b[i + 2])) / 3;
    sum += d;
    if (d > 8) changed++;
    if (d > max) max = d;
  }
  const n = a.length / 3;
  return { meanAbsDiff: +(sum / n).toFixed(2), fracChanged: +(changed / n).toFixed(4), maxAbsDiff: +max.toFixed(1) };
}

function main() {
  const summary = { ok: false, startedAt: new Date().toISOString(), checks: results };
  try {
    // ---- chilled tint ----
    const tintOut = path.join(SCREENSHOTS_DIR, 'godot_3d_tint_before.png');
    const tint = runCapture('tintdiff', tintOut);
    const tA = stats(rawCrop(tint.path, tint.region));
    const tB = stats(rawCrop(tint.after_path, tint.region));
    const tDiff = diffStats(rawCrop(tint.path, tint.region), rawCrop(tint.after_path, tint.region));
    const ratioA = tA.meanB / Math.max(1, tA.meanR);
    const ratioB = tB.meanB / Math.max(1, tB.meanR);
    check('chilled tint: visual_modulate is CHILL_TINT (r<g<b)',
      typeof tint.visual_modulate === 'string' && /0\.55/.test(tint.visual_modulate) && /1\.25/.test(tint.visual_modulate),
      { modulate: tint.visual_modulate });
    check('chilled tint: entity pixels change visibly', tDiff.meanAbsDiff > 4 && tDiff.fracChanged > 0.04, tDiff);
    check('chilled tint: blue/red ratio increases (cooler look)', ratioB > ratioA * 1.05,
      { before: { meanR: +tA.meanR.toFixed(1), meanB: +tA.meanB.toFixed(1), bOverR: +ratioA.toFixed(3) }, after: { meanR: +tB.meanR.toFixed(1), meanB: +tB.meanB.toFixed(1), bOverR: +ratioB.toFixed(3) } });

    // ---- armor break ----
    const armorOut = path.join(SCREENSHOTS_DIR, 'godot_3d_armor_before.png');
    const armor = runCapture('armordiff', armorOut);
    const aDiff = diffStats(rawCrop(armor.path, armor.region), rawCrop(armor.after_path, armor.region));
    check('armor break: billboard sheet swaps z_conehead -> z_normal',
      armor.sheet_before === 'z_conehead' && armor.sheet_after === 'z_normal',
      { before: armor.sheet_before, after: armor.sheet_after });
    check('armor break: entity pixels change visibly (cone removed/prop falling)', aDiff.meanAbsDiff > 5 && aDiff.fracChanged > 0.05, aDiff);

    const ok = results.every((r) => r.ok);
    summary.ok = ok;
    summary.tint = { sheet_before: tint.sheet_before, sheet_after: tint.sheet_after, region: tint.region, diff: tDiff };
    summary.armor = { sheet_before: armor.sheet_before, sheet_after: armor.sheet_after, region: armor.region, diff: aDiff };
    summary.elapsedMs = Date.now() - new Date(summary.startedAt).getTime();
    console.log(`\nSUMMARY ${JSON.stringify({ ok, passed: results.filter((r) => r.ok).length, total: results.length })}`);
    if (typeof args.json === 'string') writeJson(path.resolve(ROOT, args.json), summary);
    process.exit(ok ? 0 : 1);
  } catch (e) {
    summary.fatal = String((e && e.stack) || e);
    console.error('FATAL', summary.fatal);
    if (typeof args.json === 'string') writeJson(path.resolve(ROOT, args.json), summary);
    process.exit(2);
  }
}

main();
