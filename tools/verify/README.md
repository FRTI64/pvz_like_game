# tools/verify — independent verification harness (owner: verifier)

Self-contained tools used to independently verify the 3D conversion of both playable
deliverables (`scenes/main.tscn` Godot project and `web_preview/index.html`).
Nothing here is production code; nothing here is loaded by the game.

**Final verified artifacts:** Godot HEAD `cc6ffa3` (`scenes/main.tscn` md5
`8498045b0849a8be9e586e963b4bd4c6`), frozen web build `web_preview/index.html` md5
**`f237b7f58e6204e2ba90624795a01192`** (`billboard_assets.js` md5
`ead2dafc52f841182f87439e1d50a25c`, `three.module.min.js` md5
`954c1c226c332f2aecea3d9d6fbc25d5`). Full QA verdict: `QA_REPORT.md`.

## Contents

| File | Purpose |
|---|---|
| `lib.mjs` | shared helpers: project root, port probing, `python3 serve.py` server management, ffmpeg image statistics, screenshot helpers, arg parsing |
| `cdp.mjs` | minimal raw Chrome DevTools Protocol client for the **host** headless Chrome (`http://127.0.0.1:9222`): `newTab/connect/evaluate/snap/waitForExpr/attachErrorCapture` |
| `web_shot.mjs` | screenshots + smoke checks for the web preview (3D gameplay/menu/pause/levels + archived 2D baseline) |
| `web_interact.mjs` | scripted end-to-end interaction test of the 3D web preview (26 checks) |
| `web_fps.mjs` | rendered FPS + WebGL2 probe of the 3D web preview (~52 fps on the frozen build) |
| `capture_godot.gd/.tscn` | windowed Godot capture runner: instantiates `main.tscn`, plants a deterministic layout, spawns zombies/suns, saves viewport PNGs (setups incl. `tintdiff`/`armordiff` before-after captures) |
| `godot_shot.sh` | wrapper: runs `capture_godot.tscn` with the WSLg wayland + llvmpipe recipe (spec §6) |
| `smoke_logic.gd/.tscn` | headless logic/flow smoke test (34 checks, 1800-frame/30 s soak), writes the JSON report |
| `godot_smoke.sh` | wrapper: runs the headless smoke test and fails on `SCRIPT ERROR` / unexpected `ERROR:` lines |
| `godot_visual_check.mjs` | independent pixel-diff checks: chilled tint + cone armor-break sheet swap (5 checks) |
| `QA_REPORT.md` | final QA verdict, spec §7 pass/fail, findings, accepted limitations |
| `evidence/` | kept raw evidence referenced by `QA_REPORT.md` (JSON reports, perf log) |

## Web preview (3D) — host Chrome CDP is required

The sandbox's local Chromium cannot create a working GPU process/WebGL context
(`GPU process wedges`), and Playwright launch/navigation hangs here. The **Windows host**
headless Chrome is exposed at `http://127.0.0.1:9222` with real WebGL2 (ANGLE/D3D11 WARP).
All web tools drive that browser over raw CDP; the static server is started by the tool
itself inside the same process, so WSL network-namespace isolation does not matter.

Requirements: Windows host Chrome running headless with `--remote-debugging-port=9222`
(already running in this environment; override with `PVZ_CDP_HOST`). `python3 serve.py`
is auto-started by the tools (first free port from 8123). The page URL handed to the
browser uses `localhost` (WSL localhost forwarding). `serve.py` must run in the same
bash invocation/process namespace as the driver — the tools do this themselves; never
reuse a server across separate bash tool calls.

### Screenshots / smoke checks

```bash
cd /home/frti64/pvz_like_game

node tools/verify/web_shot.mjs                    # ?shot=1&level=1 -> screenshots/web_3d_gameplay.png
node tools/verify/web_shot.mjs --mode menu        # -> web_3d_menu.png + menu->3D web_3d_from_menu.png
node tools/verify/web_shot.mjs --mode pause       # -> web_3d_pause.png
node tools/verify/web_shot.mjs --mode baseline2d  # archived 2D page -> web_2d_baseline.png
node tools/verify/web_shot.mjs --level 3 --out screenshots/web_3d_level3.png
node tools/verify/web_shot.mjs --url 'http://localhost:8121/web_preview/index.html?shot=1'
```

Exit codes: `0` pass, `1` page/logic errors or not ready (JSON summary on stdout),
`2` harness/setup failure. `--json out.json` writes the full summary (errors, `__pvz`
counts, WebGL2 flag, image stats, timings).
Options: `--mode shot|menu|pause|baseline2d`, `--level N`, `--out PATH`, `--out2 PATH`,
`--port N`, `--settle MS`, `--timeout MS`, `--via-menu`, `--json PATH`, `--keep-server`,
`--no-analyze`.

### Interaction test / FPS

```bash
node tools/verify/web_interact.mjs    # 26 E2E checks; starts the server itself
node tools/verify/web_fps.mjs         # rendered FPS + WebGL2 renderer string
```
`web_interact.mjs` checks: menu→level, seed-card click → canvas-click planting (correct
cell, sun cost, HUD sync, cooldown), natural-sun projected click +25, all 8 plant types,
cooldown block, shovel, projectile damage, lawnmower lane clear, pause/resume, forced
victory/defeat modals, restart, levels 2/3, `__pvzErrors` empty and zero console
errors/exceptions/404s. Its screenshot output is the mid-game state
(`screenshots/web_3d_interaction.png`) plus a level-3 state
(`web_3d_interaction_level3.png`).

## Godot (native)

### Screenshots (windowed, WSLg wayland + llvmpipe)

```bash
cd /home/frti64/pvz_like_game
tools/verify/godot_shot.sh gameplay screenshots/godot_3d_gameplay.png 2.5
tools/verify/godot_shot.sh plants   screenshots/godot_3d_plants.png    2.2
tools/verify/godot_shot.sh zombies  screenshots/godot_3d_zombies.png   2.2
tools/verify/godot_shot.sh empty    screenshots/godot_3d_empty.png     2.2
tools/verify/godot_shot.sh pause    screenshots/godot_3d_pause.png     2.2
tools/verify/godot_shot.sh victory  screenshots/godot_3d_victory.png   2.5
tools/verify/godot_shot.sh gameover screenshots/godot_3d_gameover.png  2.5
tools/verify/godot_shot.sh menu     screenshots/godot_3d_menu.png      1.5
```
Each run prints `VERIFY_CAPTURE_OK {json}` and `SHOT_OK <png>`; it fails on
`SCRIPT ERROR` in the capture log. Setups: `empty | plants | zombies | suns | gameplay |
pause | victory | gameover | menu | tintdiff | armordiff`.

### Headless logic/flow smoke test

```bash
tools/verify/godot_smoke.sh --frames 1800        # 30 s of game time at fixed 60 fps
```
Runs `--headless --fixed-fps 60`, instantiates `main.tscn` in a **scene-based runner**
(a `--script`/SceneTree runner breaks autoload compile order in this project), plants
through real `GameManager.select_plant` + synthetic `get_viewport().push_input()` clicks,
and asserts: 3D root, initial sun, empty grid, click-planting/cost/selection, occupied and
insufficient-sun rejection, natural sun spawn + projected-click collect + `Sun.collect()`,
wave spawn/advance, zombie walk, projectile kill, zombie eating, lawnmower trigger,
HUD pause/resume, victory/defeat HUD panels, and a clean log. Exit code 0/1/2; full report
in `tools/verify/tmp/smoke_report.json` (or `--report PATH`).

### Visual pixel-diff checks (chilled tint / armor break)

```bash
node tools/verify/godot_visual_check.mjs --json tools/verify/evidence/visual_checks.json
```
Runs the `tintdiff`/`armordiff` capture setups (windowed, llvmpipe), crops the entity
screen region, and compares raw RGB via ffmpeg: chilled tint must visibly shift blue
(`modulate (0.55,0.8,1.25)`), cone armor break must swap `z_conehead`→`z_normal` and
change the rendered pixels. Writes `screenshots/godot_3d_{tint,armor}_before*.png`.

## Environment notes (not game defects)

- Local Chromium: no WebGL (GPU process wedges in the sandbox); use the host CDP channel.
  `--disable-gpu --disable-software-rasterizer` only allows non-WebGL pages.
- Godot on llvmpipe: directional-light shadow maps do not render
  (`shader_gles3.cpp:802` startup errors are environmental); blob/contact shadows are the
  accepted substitute. 3D render cost on llvmpipe (24 ms CPU/frame in movie-writer) is an
  **accepted environmental limitation** (Lead decision) — see `QA_REPORT.md` F1.
- Godot logs `Failed to open 'user://logs/...'` / shader-cache errors in this sandbox;
  `godot_smoke.sh` filters those known-noise lines.

## Verified artifact hashes (frozen final)

```
web_preview/index.html             f237b7f58e6204e2ba90624795a01192
web_preview/billboard_assets.js    ead2dafc52f841182f87439e1d50a25c
web_preview/three.module.min.js    954c1c226c332f2aecea3d9d6fbc25d5
scenes/main.tscn                   8498045b0849a8be9e586e963b4bd4c6  (git HEAD cc6ffa3)
project.godot                      eac80a2960027296d5a4f2b23770ca20
```
