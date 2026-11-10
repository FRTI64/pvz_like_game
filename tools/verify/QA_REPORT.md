# Independent QA report — 2D → 3D rendering conversion

Author: `verifier` (independent QA; does not implement the feature).
Date: 2026-11-10 16:26 (Asia/Singapore). Status: **FINAL PASS** (Lead-accepted limitations noted).
Spec: `docs/3d-render-spec.md` §5–§7. Scope: both deliverables — Godot `scenes/main.tscn`
and `web_preview/index.html` — plus interaction/flow parity with the original 2D version.

## Tested artifacts (final, frozen)

| Artifact | Version / hash |
|---|---|
| Git HEAD (Godot final) | `cc6ffa3` "Godot: final accepted lighting path (shadow-enabled, brighter look) and hedge cleanup" |
| `scenes/main.tscn` | md5 `8498045b0849a8be9e586e963b4bd4c6` |
| `project.godot` | md5 `eac80a2960027296d5a4f2b23770ca20` |
| `web_preview/index.html` (FROZEN by web3d) | md5 **`f237b7f58e6204e2ba90624795a01192`** (119,154 bytes, mtime 16:22); hash verified stable before/after the final run |
| `web_preview/billboard_assets.js` | md5 `ead2dafc52f841182f87439e1d50a25c` |
| `web_preview/three.module.min.js` | md5 `954c1c226c332f2aecea3d9d6fbc25d5` (three r170) |
| Reference 2D web page | `git show HEAD:web_preview/index.html` archived at `screenshots/baseline_web/index.html` |
| Browser | Windows host headless Chrome 157 over CDP `127.0.0.1:9222`; WebGL2 `ANGLE (Microsoft, Microsoft Basic Render Driver (0x0000008C) Direct3D11 vs_5_0 ps_5_0, D3D11)` |
| Godot | 4.7.2.stable.mono, `--display-driver wayland --rendering-driver opengl3`, Mesa llvmpipe 26.2.6 |

## Verdict

**PASS — no blocking defects.** Every independently-run automated suite is green against
the frozen web build (`f237b7f5…`) and Godot HEAD (`cc6ffa3`):
Godot headless logic/flow 34/34, Godot visual pixel-diff 5/5, Godot capture 8/8 clean,
web E2E interaction 26/26, web screenshot/smoke 6/6 modes, web frame rate ~52 fps,
0 page/console/network errors. The spec §7 visual bar is met in both engines; the only
§7 item outside the literal target (Godot movie-writer frame cost on llvmpipe) is an
**accepted environmental limitation by Lead decision**.

## Evidence (final screenshots, `screenshots/`)

Godot (windowed WSLg/llvmpipe, 1280x720 at HEAD cc6ffa3):
`godot_3d_gameplay.png`, `godot_3d_plants.png`, `godot_3d_zombies.png`, `godot_3d_empty.png`,
`godot_3d_pause.png`, `godot_3d_victory.png`, `godot_3d_gameover.png`, `godot_3d_menu.png`,
`godot_3d_tint_before.png` / `godot_3d_tint_before_after.png`,
`godot_3d_armor_before.png` / `godot_3d_armor_before_after.png`.
2D baseline: `godot_2d_baseline.png`, `godot_2d_baseline_empty.png`.

Web (host Chrome CDP, 1280x720 at frozen md5 `f237b7f58e6204e2ba90624795a01192`):
`web_3d_gameplay.png`, `web_3d_level3.png`, `web_3d_menu.png`, `web_3d_from_menu.png`
(menu→3D transition), `web_3d_pause.png`, `web_3d_victory.png`, `web_3d_gameover.png`,
`web_3d_interaction.png` (mid-game: 8 plant types + zombies + HUD), and
`web_3d_interaction_level3.png`.
2D baseline: `web_2d_baseline.png` (full page), `web_2d_menu_baseline.png`.

Raw evidence: `tools/verify/evidence/` — `smoke_report.json`, `visual_checks.json`,
`web_shot_final.json`, `web_shot_level3_final.json`, `web_menu_final.json`,
`web_pause_final.json`, `web_baseline2d_final.json`, `web_interact_final.json`,
`web_fps_final.json`, `godot_3d_perf.log`.

## Independent automated results

| Suite | Result | Notes |
|---|---|---|
| `tools/verify/godot_smoke.sh --frames 1800` | **34/34 PASS**, exit 0 | 1802 frames ≈ 30 s sim. 3D root; initial sun 150; click-planting via real `GameManager.select_plant` + synthetic viewport input (cost, selection, occupied-cell and insufficient-sun rejection); natural sun spawn + projected-click collect (+25) + `Sun.collect()` (+25); wave spawn/advance; zombie walks left; peashooter projectile kill; zombie eats wallnut (hp 4000→3800); lawnmower trigger; HUD pause/resume; victory/defeat HUD panels; clean log. Counters: 6 zombies spawned, 2 died, 1 mower, 9 sun-events. |
| `tools/verify/godot_visual_check.mjs` | **5/5 PASS**, exit 0 | Independent before/after pixel diff on the rendered entity region: chilled tint = `modulate (0.55,0.8,1.25)` + visible pixel change (meanAbsDiff 7.76, 15.8% pixels changed) + blue/red ratio 0.788→0.833; armor break = sheet `z_conehead`→`z_normal` + visible pixel change (meanAbsDiff 11.77, 16.6% pixels changed). Closes two items from the earlier coverage-gap list. |
| `tools/verify/godot_shot.sh` (8 normal + 2 diff setups) | **10/10 pass** | 0 `SCRIPT ERROR`, 0 unexpected `ERROR:` lines in capture logs (after filtering known sandbox llvmpipe noise). |
| `tools/verify/web_interact.mjs` (frozen build) | **26/26 PASS**, exit 0 | menu→L1 (sun 150); seed-card→canvas-click plants peashooter at (row1,col2), sun 150→50, HUD synced, cooldown; natural-sun projected click +25; all 8 plant types; cooldown re-plant blocked; shovel; projectile damages zombie (hp 200→180); lawnmower clears lane; pause modal (PAUSED)/resume; victory & defeat modals; restart; levels 2 (sun 100, 6 waves) and 3 (sun 200, 7 waves); `__pvzErrors` empty; 0 console errors/exceptions/404s. |
| `tools/verify/web_shot.mjs` modes `shot` / `menu` / `pause` / `baseline2d` + `--level 3` | **6/6 pass**, errorCount 0 | `?shot=1` preset: 15 plants / 5 zombies / 2 suns, `PLAYING`, WebGL2 true; L3 preset level=3; menu 3 cards + menu→3D transition `ready`/`PLAYING`; pause `PAUSED` with modal visible; archived 2D page baseline regenerated. |
| `tools/verify/web_fps.mjs` (frozen build) | **~52.3 fps**, PASS | 1280x720 headless host Chrome/WARP; §7 smoke target (>20 fps headless) met; 0 errors. |

## Spec §7 acceptance checklist

Gameplay parity (both versions):

| Item | Status | Evidence / notes |
|---|---|---|
| Level select from menu; starting a level enters 3D view | ✅ web E2E; ✅ Godot (owner harness + code path unchanged) | Web: menu→card click→`PLAYING` (`web_3d_from_menu.png`). Godot: menu renders (`godot_3d_menu.png`), main scene boots in every test; 2D menu→scene-change code is untouched (owner flow checks 16/16). |
| Planting via seed cards on empty cells; sun cost & cooldown | ✅ both | Web E2E real DOM card click + canvas click, 8 types, HUD sync, cooldown block. Godot smoke: click-path planting, cost/selection/occupied/insufficient-sun rejection. |
| Sun drops from sky and sunflowers; click collect +25 | ✅ sky suns both; sunflower sun covered by owner evidence | Web + Godot natural-sun collection asserted (+25 both via projected click and `Sun.collect()`); sunflower-produced sun covered by owner evidence (gap list below). |
| Projectile hit/damage, chilled slow | ✅ hit/damage both; ✅ chilled tint + slow code covered | Web hp 200→180; Godot projectile kill. Chilled: independent pixel-diff proves the tint renders (`godot_3d_tint_before_after.png`); speed multiplier verified by owner self-tests. |
| Wallnut crack stages; potato mine; cherry 3×3; chomper; 4 zombie types + armor break + flag | ✅ armor break independently; others owner-covered | All states visible in `godot_3d_plants.png` / `godot_3d_zombies.png`; cone armor break independently pixel-diff verified (`godot_3d_armor_before_after.png`, sheet swap). Remaining mechanics covered by owner evidence (see below). |
| Zombie eating plants; lawnmower triggers/clears lane | ✅ both | Godot smoke: wallnut hp drop, mower trigger + zombie removal. Web E2E: lane-4 zombie removed after mower. |
| Wave progress, huge-wave banner, victory & defeat, pause/restart/menu | ✅ web; ✅ Godot forced paths; banner owner-covered | Web: wave counts, pause/resume, restart, victory/defeat modals. Godot: pause panel, victory/defeat panels. Huge-wave banner covered by owner evidence. |
| HUD readable over 3D, sun counter updates, no layout regressions | ✅ both | Screenshots + HUD sync assertion (web) + sun labels in every capture; HUD/menu DOM unchanged 2D (spec-compliant). |

Visual:

| Item | Status | Evidence / notes |
|---|---|---|
| Clearly 3D perspective, 3D house/fence/trees/sky, lighting, blob shadows | ✅ | `godot_3d_gameplay.png`, `web_3d_gameplay.png`; lawn far edge ≈20.8% / near ≈88.9% of frame height in both (spec reference 13–20% / 88%). Final web build adds workshop-style house, picket fence + hedge, trees/hill band, verge/sidewalk/curb, brighter warm lighting to mirror the Godot board; no regression vs the earlier pass). |
| 2D-art billboards standing on lawn, animating, tinted, sensible depth order | ✅ static + tint diff; animation covered | Billboards, lane depth scaling and blob shadows verified in both engines; chilled tint and armor-break sheet swap independently pixel-diffed; three.js sheet animation/Godot `Billboard2D` observed; no z-fighting/clipping seen in captures. |
| Hover highlight + ghost preview align with clicked cell | ✅ mapping; hover visual owner-covered | Planting at projected cell centers landed in the expected cells in both engines (real clicks web, synthetic viewport input Godot) → click→cell mapping self-consistent; ghost/hover visuals covered by owner 45/45 round-trip evidence. |
| Frame rate | ✅ web 52.3 fps; ✅ Godot accepted env limitation (F1) | Web target met. Godot llvmpipe cost accepted by Lead — see F1. |
| No errors/warnings on level start and 30 s of play | ✅ | Godot: clean 1802-frame headless soak + clean capture logs. Web: 0 errors/warnings/404s across all modes and the full 26-check interaction run. |

## Findings

### F1 — [Medium, ACCEPTED ENVIRONMENTAL LIMITATION] Godot 3D render cost on llvmpipe
- **Measured (verifier):** movie-writer recording of `res://scenes/main.tscn`, 1280x720,
  100 frames: **CPU 24.0 ms/frame, GPU 25.9 ms/frame**; 2D baseline was 1.73 ms/frame.
- **Owner decomposition (godot-world, same box/stack):** windowed normal run at HEAD
  cc6ffa3 = **18.6–20.5 ms/frame (~48–54 fps)**, 1238 draw calls; shadow pass disabled
  = 8.75 ms/frame (but visibly darker/different lawn colour → rejected art-wise); board
  hidden = 2.28 ms; render-scale reduction only 10–18% → draw-call/vertex/shadow-pass
  bound, not fill-rate. Movie-writer numbers elsewhere 18.7–36 ms/frame depending on
  concurrent teammate load; verifier's 24.0/25.9 is consistent.
- **Lead decision (2026-11-10): ACCEPTED as llvmpipe/software-GL environmental
  limitation — no shadow disable, no board-mesh refactor.** §7's "<~6 ms CPU" line was a
  soft movie-maker target written against the 2D baseline and is not comparable to a real
  3D scene rendered by a CPU rasterizer; the actual GPU targets are the web build
  (~52 fps here) and real-hardware Godot/Web exports. Not a correctness defect.
- Repro (kept for the record): `tools/verify/evidence/godot_3d_perf.log`; command in
  `tools/verify/README.md` or `tools/verify/godot_shot.sh` env recipe + `--write-movie`.

### Coverage gaps — CLOSED as “covered by owner harnesses, not independently re-derived”
Lead decision: acceptable. Owner evidence provided under `.tools/shots/`:
- `gap_00..09*`, `wallnut_stages.png`, `flash_chill_compare.png`, `gap_evidence.log`
  (godot-entities gap visuals/logs: potato mine arm/detonate, cherry 3×3, chomper
  eat/chew, wallnut crack stages, huge-wave banner, sunflower sun, chilled/flash tint).
- Owner self-tests: godot-entities 34/34 + 42/42 parity + grid lifecycle 10/10;
  godot-world 53/53 + 16/16; web3d final sanity 12/12.
- Verifier independently re-derived the two cheap visual ones (chilled tint, cone armor
  break) with pixel diffs — see `godot_visual_check.mjs` results above. Remaining items
  (potato/cherry/chomper timings, huge-wave banner, sunflower sun, Godot menu→3D scene
  change, per-frame animation rate) are accepted on owner evidence.

### Observations / environmental notes (not defects)
- **O1** Local Chromium in this sandbox cannot create WebGL contexts (GPU process wedges);
  all web verification runs through the Windows host headless Chrome CDP endpoint
  (`127.0.0.1:9222`). The 2D web baseline was captured from the archived 2D page.
- **O2** Directional-light shadow maps do not render with `gl_compatibility` + llvmpipe
  (`shader_gles3.cpp:802` startup messages); blob/contact shadows are the accepted
  substitute (Lead decision).
- **O3** Sandbox environment noise filtered by `godot_smoke.sh`: `Failed to open
  'user://logs/...'`, shader-cache directory errors.
- **O4** Windows mouse cursor appears in a few modal web screenshots — capture-channel
  artifact, not present in real gameplay.
- **O5** `serve.py` must be started/stopped within the same bash invocation as the CDP
  tool (WSL network-namespace isolation); all harness tools handle this themselves.
- No 2D/3D behavior-parity regressions found: level data, costs, initial sun, wave counts,
  cooldowns and HUD values all still match the 2D baseline (asserted in the web E2E run).

## Reproduction (tools are in `tools/verify/`; see README.md)

```bash
cd /home/frti64/pvz_like_game

# Godot (windowed WSLg/llvmpipe)
./tools/verify/godot_shot.sh gameplay screenshots/godot_3d_gameplay.png 2.5
./tools/verify/godot_shot.sh pause    screenshots/godot_3d_pause.png    2.2
./tools/verify/godot_smoke.sh --frames 1800          # 34-check 30 s headless soak
node tools/verify/godot_visual_check.mjs             # chilled tint + armor-break pixel diff

# Web (host Chrome CDP; static server managed by the tools)
node tools/verify/web_shot.mjs --mode shot
node tools/verify/web_shot.mjs --mode shot --level 3 --out screenshots/web_3d_level3.png
node tools/verify/web_shot.mjs --mode menu
node tools/verify/web_shot.mjs --mode pause
node tools/verify/web_shot.mjs --mode baseline2d
node tools/verify/web_interact.mjs                   # 26-check E2E
node tools/verify/web_fps.mjs                        # rendered fps + WebGL2 probe
```

## Final verdict

**PASS.** The conversion meets the functional and visual acceptance bar in both engines
with no blocking defects. F1 is accepted as an llvmpipe environmental limitation (Lead
decision, no code change requested); coverage gaps are closed on owner evidence plus two
independently re-derived visual checks. Frozen web hash
`f237b7f58e6204e2ba90624795a01192`, Godot HEAD `cc6ffa3`.
