# PVZ "3D-rendered 2D" Conversion Spec (HD-2D / 2.5D)

Status: authoritative technical contract for the 3D conversion workstream.
Owner: Lead. Read this fully before coding. Ask the Lead if a contract is unclear.

## 1. Goal

Convert **both** playable deliverables of this repo from flat 2D rendering to
**3D rendering of the same 2D game**:

1. `scenes/main.tscn` + `scripts/` — the native **Godot 4.7.2** project
   (`gl_compatibility` renderer, Web export target).
2. `web_preview/index.html` — the instant-play **web preview** (now Canvas2D).

Interpretation: **gameplay stays 2D** (the same 5x9 grid, lanes, pixel-space
logic, numbers, waves, balance). **Rendering becomes 3D**: perspective camera,
real 3D ground / house / fence / props, 2D-procedural-art characters rendered
as camera-facing billboards ("HD-2D" standees), 3D lighting, blob shadows,
depth-based scaling, 3D particle effects.

Non-goals / must NOT change:
- Gameplay rules, balance, level data (`data/**`), HUD / menu layout and logic
  (`scenes/ui/**`, `scenes/main_menu.tscn`, `scripts/ui/**` stay 2D DOM/CanvasLayer).
- Audio (`scripts/autoload/sound_manager.gd`).
- The original procedural 2D art scripts **must stay untouched**:
  `scripts/visuals/plant_visuals.gd`, `zombie_visuals.gd`, `item_visuals.gd`
  are reused by the offline billboard baker. Do not edit or delete them.
- No external art/audio assets downloaded at runtime. (Billboard PNGs are
  baked from the existing procedural art and committed.)

## 2. Core space contract (identical in Godot and Web)

- `PX = 1.0 / 45.0` — world units per 2D game pixel (1 unit = 45 game px).
- `CENTER = (640, 360)` — 2D game screen center.
- World ax es: `+X` = 2D screen right, `+Z` = 2D screen down (toward camera),
  `+Y` = up. Ground plane is `Y = 0`.
- Mapping:
  - `world = ((game_x - 640) * PX, height_px * PX, (game_y - 360) * PX)`
  - `game = (world.x / PX + 640, world.z / PX + 360)`, `height_px = world.y / PX`
- All gameplay logic keeps using **game pixel coordinates** and pixel/second
  speeds. Only the presentation layer knows about world units.
- Board extents in game px: full 2D screen rect `x:0..1280, y:0..720`.
  Lawn grid (Godot): origin `(275,125)`, cell `98x108`, 5 rows x 9 cols.
  (Web preview differs slightly: `GRID_X=265, GRID_Y=120, CELL_W=100, CELL_H=110` —
  keep each version's own existing game constants; only the presentation mapping
  is shared.)

### 2.1 Godot-specific trick: `WorldRoot`

Create `WorldRoot: Node3D` in `main.tscn` with:
`position = Vector3(-640*PX, 0, -360*PX)`, `scale = Vector3(PX, PX, PX)`.
Then every gameplay node that is a descendant of `WorldRoot` keeps working in
**local game px units**:
`local position = Vector3(game_x, height_px, game_y)`,
world speed = px/s (no conversions needed in gameplay logic), the ground is
local `Y = 0`, and `position.x` / `position.z` are the game x / game y.
All logic comparisons with pixel constants (1300, 180, 1360, 45, 130, ...) keep
working unchanged.

Rules:
- `GridManager`, `SunManager`, `WaveManager`, `LawnMowers` and all spawned
  entities live under `WorldRoot`, with identity transform on the manager nodes
  (so `position` is a common game-px space for siblings under different parents).
  **Never** use `global_position` in gameplay code (it is scaled); use
  `position.x` / `position.z` instead.
- Camera, `WorldEnvironment`, `DirectionalLight3D`, sky, and world-scale props
  are siblings of `WorldRoot` and work in **world units**.

### 2.2 Camera (initial values, then tune with screenshots)

- `Camera3D`, perspective, `fov = 40` (vertical), aspect from 1280x720 viewport,
  near 0.1, far 200.
- Target point (world): `(0, 1.2, 2.0)`.
- Camera position = target + `23.0 * (0, sin(58°), cos(58°))`
  = approx `(0.0, 20.7, 14.2)`, looking at the target.
  (`WorldSpace.CAMERA_DISTANCE = 23.0`, `CAMERA_ELEVATION_DEG = 58.0`,
  `CAMERA_FOV = 40.0`, `WorldSpace.default_camera_position()` returns this.)
  Reference framing (validated): lawn far edge at ~22% of screen height, lawn
  near edge at ~83%, lawn ~66% of screen width centered; top ~120 px is HUD.
  A validated reference render of the full diorama is
  `.tools/shots/foundation_preview.png` (Lead tool scene
  `tools/preview_billboards.tscn`).
- Use a **fixed camera** (gameplay must be readable). A very subtle mouse
  parallax (±0.3 world units) is allowed but optional.
- Web uses the exact same numbers via THREE.PerspectiveCamera.

### 2.3 Ground / environment composition (both engines)

Build from 3D primitives, flat stylized colors, no textures needed (procedural
canvas textures for grass/asphalt are allowed in web, but not required):

- Large base ground plane (dark soil-green) covering the whole camera view
  (extend beyond board so no "void" is visible at any frame edge; at least
  `x/z` of game px -300..1580 / -300..1020).
- Lawn board: 5x9 checkerboard cells (colors `#56a34a` / `#4b9441`, thin
  darker grid seams `#2f6b2c`), each cell a slightly raised flat slab
  (height ~3 game px) or one slab with grid lines. Wooden border frame
  around the lawn (color `#6b4a2e`, height ~10 game px) — gives 3D depth cue.
- Left: patio strip (game x 0..265) in warm planks `#6f4e35` with darker seams,
  plus a 3D **house facade** outside the board's left edge (wall `#d8c39c`,
  roof `#8e4a3a`, door `#5a3a26`, windows `#9fd4e8`, height ~350 game px =
  ~7.7 world units). It must not visually cover the lawn.
- Right: sidewalk `#b8b2a4` (x 1165..1280) + short stone/hedge wall / fence
  beyond the board's right edge (`#7a5a3a` wood, `#3f7a35` hedge).
- Back (far edge, game y ≈ -40..0): wooden fence / hedge row across the width,
  height ~70 game px, plus 2–4 low-poly trees (cone/sphere) behind it, so the
  sky area above the far edge looks alive. Add a distant hill silhouette if
  cheap. Sky: gradient `#8ec9e8` top → `#f8e6bd` horizon.
- Foreground apron beyond game y ≈ 780 (in front of the near board edge) so the
  bottom of the frame never shows void.
- Lighting: warm directional sun (`#fff3d6`, energy ~1.3), direction from
  upper-left-front (e.g. euler ≈ `(-52°, -28°, 0°)`), ambient/hemisphere fill
  (`#bcd9ff` sky / `#5a6b3a` ground, energy ~0.5–0.7). Cast real-time shadows
  for 3D props (house/fence/trees/border) if performance allows; characters use
  blob shadows (see 3.2), not shadow maps.
- **Background / sky (important, validated):** with this camera the horizon is
  above the frame — the top of the screen is still looking down at ~38° below
  horizontal, so the visible upper band is nearest background geometry, not
  sky. Do NOT use `Environment.BG_SKY` / `ProceduralSkyMaterial` in the
  `gl_compatibility` renderer (verified to break the render on this stack —
  the whole 3D scene disappeared). Use `Environment.BG_COLOR` (light sky blue,
  e.g. `#b3d9f2`) and design the upper band as: base-ground far edge ending at
  local z ≈ -60 (just behind the far lawn edge), a wooden fence + green hedge
  at local z ≈ 10..60 (height ~60–100 game px), and 3–5 low-poly trees rooted
  at local z ≈ -20..-40 with only canopies showing above the hedge. The HUD
  covers the top ~120 px anyway. A manual backdrop mesh (large plane with a
  gradient texture placed ~150–250 px behind the hedge) is allowed if it stays
  in front of the ground's far edge, but keep it subtle.

## 3. Billboard art contract

The existing procedural 2D art is baked **offline by the Lead** into sprite
sheets under `assets/billboards/` + `assets/billboards/manifest.json`
(generated by `tools/billboard_factory.tscn`). Both engines consume the same
PNGs so the two versions look identical. Do not hand-edit generated assets.

### 3.1 Manifest schema (`assets/billboards/manifest.json`)

```json
{
  "capture_scale": 2.0,
  "frame_w": 256,
  "frame_h": 256,
  "sheets": {
    "p_peashooter": {
      "file": "p_peashooter.png",
      "frames": 6,
      "fps": 4.0,
      "anchor": [128, 192],
      "bbox": [96, 78, 164, 192]
    }
  }
}
```

- One PNG per sheet, frames laid out **horizontally** left→right, each frame
  `frame_w x frame_h` px, RGBA, transparent background, art upright.
- Inside a frame, the billboard "origin" (2D art origin) is at
  `x = frame_w/2 = 128`; art extends up from it.
- `anchor = [x, y]` is the frame pixel that must be placed at the entity's 3D
  position (feet/ground contact point for ground units, center for floating
  items). Engines derive the sprite quad offset from `anchor`:
  - local offset (game px) from entity position to sprite **center**:
    `off_x = (frame_w/2 - anchor.x) / capture_scale`
    `off_y = (anchor.y - frame_h/2) / capture_scale` (up positive)
- `capture_scale = 2.0` → 1 texture px = 0.5 game px.
  So the billboard quad is `frame_w/capture_scale x frame_h/capture_scale`
  game px (128 x 128 game px).
- `bbox = [x0, y0, x1, y1]` union of opaque pixels over all frames (frame px);
  use it for blob-shadow size.
- Web: `web_preview/billboard_assets.js` is generated from the same manifest +
  PNGs (data URLs), by `tools/build_web_assets.mjs`.

### 3.2 Sheet catalog (authoritative names)

Plants (animated, 6 frames, fps 4):
`p_peashooter`, `p_sunflower`, `p_cherry`, `p_snow_pea`, `p_repeater`,
`p_wallnut_0` (intact), `p_wallnut_1` (cracked), `p_wallnut_2` (heavily cracked),
`p_potato_0` (unarmed), `p_potato_1` (armed),
`p_chomper_0` (idle), `p_chomper_1` (chewing).

Zombies (animated, 8 frames, fps 6):
`z_normal`, `z_conehead`, `z_buckethead`, `z_flag`.

Items:
`i_sun` (animated, 8 frames, fps 4), `i_pea`, `i_snow_pea`, `i_mower` (static).

Mapping helpers live in `BillboardLibrary.sheet_for_plant(id)` /
`sheet_for_zombie(id)` (Lead-provided foundation). Armor break: swap
`z_conehead`/`z_buckethead` → `z_normal` (a small falling 3D cone/bucket prop is
optional polish). Chilled: tint the billboard (Godot `modulate =
Color(0.55, 0.8, 1.25)`, web `material.color = 0x8cc8ff`-ish); hit flash:
brighten modulate then tween back. Death: fade out while rotating / falling
over.

Static blob shadow under every ground unit: soft radial gradient ellipse on
the ground (alpha ~0.3, diameter ≈ `bbox` width, depth ≈ 0.55 x width), placed
slightly in front of the anchor. Not needed for HUD.

### 3.3 Placement rules

- Ground units (plants, zombies, mower): world/local position is the **ground**
  point; billboard stands up from it, feet on the ground.
- Floating items (pea, snow pea, sun): position is the 3D point where the sprite
  center should be; give them a visible flight height in game px
  (peas ≈ 50 px above ground, sun ≈ 95 px) and a blob shadow on the ground
  (fainter/larger when higher).
- Draw order: billboards are transparent. Godot: `Sprite3D.billboard =
  BILLBOARD_ENABLED`, `texture_filter = LINEAR_WITH_MIPMAPS`,
  `no_depth_test = false`; if overlap artifacts appear, nudge zombie sprites
  +2 game px toward camera (`position.z += 2`) and projectiles/suns more.
  Web: `THREE.Sprite` with `depthWrite:false`, `depthTest:true`, set
  `renderOrder` by lane/role (plants 0, zombies 10, projectiles 20, suns 30) if
  sorting artifacts appear.
- Animated sheets: cycle `frame = int(t * fps) % frames` (web: texture
  offset/repeat or per-sprite canvas-less sheet offset via `texture.repeat` /
  `offset`, clone the texture per animated sprite).

## 4. Godot conversion plan (owner: godot-world + godot-entities)

### 4.1 Scene tree of `scenes/main.tscn`

```
Main (Node3D, scripts/main.gd)
├── WorldEnvironment            # sky gradient, ambient, optional glow off
├── DirectionalLight3D          # warm sun + shadows for props
├── Camera3D                    # values from 2.2
├── WorldRoot (Node3D)          # position/scale from 2.1
│   ├── Board (Node3D, runtime-built by scripts/core/board_builder.gd)
│   ├── GridManager (Node3D)
│   ├── SunManager (Node3D)
│   ├── WaveManager (Node3D)
│   └── LawnMowers (Node3D)     # 5 LawnMower instances, position = Vector3(215, 0, lane_y)
└── HUD (CanvasLayer instance of scenes/ui/hud.tscn)   # unchanged 2D UI
```

`scripts/main.gd` extends `Node3D`: keeps level/GM init logic, sets
`WorldSpace.setup_world_root(WorldRoot)`, calls `BoardBuilder.build(Board)`
(or similar), camera/direction values live in the scene file if possible.

`project.godot`: keep `gl_compatibility`; may add
`rendering/anti_aliasing/quality/msaa_3d`, shadow settings, and
`rendering/lights_and_shadows/directional_shadow/size` — keep web exportable.

### 4.2 Foundation files (Lead-provided, do not rewrite)

- `scripts/core/world_space.gd` (`class_name WorldSpace`, PX/CENTER constants,
  `local_to_world`, `world_to_game2`, `screen_to_game(camera, screen_pos)`,
  `setup_world_root`, `screen_point_world(camera, screen_pos, depth)`).
- `scripts/visuals/billboard2d.gd` (`class_name Billboard2D extends Node3D`):
  a camera-facing billboard wrapper whose node origin is the anchor. Has a
  child `Sprite3D` (`billboard`), `sheet_name`, `frame_count`, `fps`,
  `animate_frames`, a tweenable `modulate: Color` property, `set_sheet(name)`,
  `set_alpha(a)`. Frame animation runs internally.
- `scripts/visuals/billboard_library.gd` (`class_name BillboardLibrary`):
  manifest/texture cache, `make_billboard(name) -> Billboard2D`,
  `make_ghost(name) -> Billboard2D`, `apply_sheet(billboard, name)`,
  `make_shadow_for(sheet_name) -> MeshInstance3D`, `make_shadow(size_px)`,
  `sheet_for_plant(id)`, `sheet_for_zombie(id)`.
- `scripts/autoload/event_bus.gd` signal argument types changed Node2D→Node3D.

### 4.3 Entity contracts (godot-entities)

- Entity root nodes become `Area3D` (`CollisionShape3D` children). Collision
  layer/mask numbers unchanged. Shape sizes in **local game px** (e.g. zombie
  box ~`(40, 90, 80)` px centred at `y=45`; plant sphere/box ~56 px diameter;
  pea sphere r≈10 at flight height; mower box ~`(50,40,60)`).
- `BasePlant extends Area3D`, `BaseZombie extends Area3D`,
  `BaseProjectile extends Area3D`, `LawnMower extends Area3D`, `Sun extends
  Node3D` (Sun no longer needs Area2D input; sun picking is done by GridManager
  via screen projection — see 4.4).
- `visual_node` is a `Billboard2D` (Node3D) created through
  `BillboardLibrary.make_billboard(...)`; keep the API used by subclasses:
  `.modulate` (Color property), tweenable `.scale` (Vector3), tweenable
  `.position` (LOCAL px units, relative to the anchored origin!), and
  `BillboardLibrary.apply_sheet(visual_node, name)` for state sheet swaps
  (wallnut cracks / potato armed / chomper chewing / zombie armor break).
  Add the blob shadow (`BillboardLibrary.make_shadow_for(sheet)`) as a sibling
  of the billboard under the entity root. Examples: potato mine unarmed/armed,
  wallnut crack stage, chomper chewing.
- Movement code stays pixel-based: `position.x -= speed * delta` etc.
  Height-only tweens (e.g. potatomine bounce `Vector2(0,-10)` in 2D) become
  `Vector3(0, 10, 0)` (up) or `Vector3(0, y, 0)` local offsets — do not move
  the ground anchor unless intended.
- Put blob shadows as siblings of the billboard under the entity root.
- `WaveManager` spawns at `position = Vector3(1320, 0, lane_y)` where
  `lane_y = 175 + lane*108`; `SunManager` spawns suns with
  `position = Vector3(x, 95, target_game_y)` (then falls along `+Z`), and
  `spawn_sunflower_sun(source_2d: Vector2)` keeps the 2D signature
  (`Vector2(x, y2d)`), converting to Vector3 internally.
- Effects become 3D: splat = `CPUParticles3D` one-shot green burst;
  explosion = orange particle burst + expanding flat ring mesh + brief light.
  Keep scene paths `scenes/effects/*.tscn` (referenced by scripts).
- Sun collect animation: tween the sun's 3D position toward a point in front of
  the camera near the HUD counter (use
  `WorldSpace.screen_point_world(camera, Vector2(85,45), 2.5)`) while shrinking
  and fading, then `GameManager.add_sun(value)`.

### 4.4 GridManager / input (godot-world)

- Hover: `screen_to_game(camera, event.position)` → game 2D coords → existing
  `world_to_grid`/`is_cell_valid` logic. Highlight = translucent green/red quad
  mesh over the cell (`y ≈ 2 px`, unshaded, transparent, no depth write).
- Ghost preview: `BillboardLibrary.make_ghost(sheet)` at cell center with
  `modulate.a ≈ 0.55`, anchored to ground; remove on deselect.
- Click handling order: (1) if left click and any sun in group `"suns"` projects
  within ~34 screen px of the cursor (`camera.unproject_position(sun world
  pos)`), collect that sun, `get_viewport().set_input_as_handled()`, return;
  (2) otherwise existing shovel/plant logic via ray→ground→cell.
- Right click: unchanged (deselect/shovel).
- All placement must use `grid_to_world(cell)` 2D coords converted with
  `WorldSpace.game2_to_local(x, y, 0)`.

### 4.5 HUD / menus

- HUD stays a `CanvasLayer` and is untouched. Main menu stays 2D
  (`main_menu.tscn`), untouched. `GameManager` scene transitions unchanged.

## 5. Web preview conversion plan (owner: web3d)

Target: `web_preview/index.html` remains the instant-playable page served by
`serve.py`, same DOM HUD/menu, same game logic (2D px state), rendered with
**Three.js** (WebGL2).

- Vendor `three.module.min.js` locally (r170, ES module) with
  `curl -sL https://cdn.jsdelivr.net/npm/three@0.170.0/build/three.module.min.js
  -o web_preview/three.module.min.js` (Lead confirms network access).
- `web_preview/billboard_assets.js` (ES module, generated by
  `tools/build_web_assets.mjs`, which reads `assets/billboards/`): exports
  `CAPTURE_SCALE`, `FRAME_W`, `FRAME_H`, `SHEETS` where each sheet has
  `{ file, frames, fps, anchor, bbox, src }` and `src` is a base64 data URL.
- Keep the existing 2D game logic almost untouched (update()/waves/sun
  economy/HUD DOM). Replace `render()` with a 3D sync:
  - build `THREE.WebGLRenderer({canvas, antialias:true})`, `Scene`,
    `PerspectiveCamera` with 2.2 values; lights/sky/board/props from 2.3
    (build from `BoxGeometry`/`PlaneGeometry`/`ConeGeometry` etc., flat colors);
  - per entity (plants, zombies, projectiles, suns, mowers) maintain a
    `THREE.Sprite` (billboard) + ground blob shadow `Mesh`; load sheet textures
    from `billboard_assets.js`; animate frames; place with the shared mapping;
  - plants: `sprite.position` from grid game coords, bob/sway by adding small
    offsets; sprite scale in world units = `frame_w/capture_scale*PX`;
    anchor offset math from 3.1;
  - zombie chilled/hit/death tint via `material.color` + opacity tween;
  - hover highlight + ghost preview: flat `Mesh` at cell + translucent sprite;
  - particles: `THREE.Points` bursts using a generated radial-gradient canvas
    texture (pea splat green, cherry explosion orange + ground ring).
- Input: replace canvas-coord mouse handling with screen→ground unprojection
  (`Raycaster` + `Plane(y=0)` or manual math) → game 2D coords; sun picking via
  screen-projected sprite positions (< ~34 px); everything else keeps using the
  2D cell logic. Keep touch support.
- Sun collect: tween sprite toward the HUD counter screen position (or toward
  camera) + shrink/fade; keep sun value logic unchanged.
- Debug/test hooks required (verifier + screenshots depend on these):
  - `?shot=1` (optional `&level=1`): skip menu, start that level, place a
    deterministic preset of plants, spawn a deterministic group of zombies and
    clickable suns, and **freeze camera/animation tween randomness** where
    practical; expose `window.__pvzReady = true` after first rendered frame.
  - `window.__pvz` API: `{ state, startLevel(id), placePlant(id,row,col),
    spawnZombie(type,row,x), addSun(n), gameOver(won), getGrid(),
    getZombies(), getSuns() }` for automated tests.
  - `window.__pvzErrors`: array capturing `window.onerror` / unhandled
    rejections (verifier asserts empty).
- No runtime network requests; all assets local. Page must work when served by
  `python3 serve.py` (ES modules). Loading overlay text until textures ready.

## 6. Running, screenshots, verification

### Godot (WSL2 + WSLg; libxkbcommon is provided locally in `.tools/`)

```bash
cd /home/frti64/pvz_like_game
export LD_LIBRARY_PATH="$PWD/.tools/libs/usr/lib"
export XKB_CONFIG_ROOT="$PWD/.tools/libs/usr/share/X11/xkb"
GODOT=/usr/lib/godot-mono/godot.linuxbsd.editor.x86_64.mono

# Run a scene and record a movie (works with WSLg llvmpipe, ~2ms CPU/frame):
$GODOT --path . res://scenes/main.tscn \
  --display-driver wayland --rendering-driver opengl3 \
  --write-movie .tools/shots/game.avi --fixed-fps 10 --quit-after 200

# Extract a frame:
ffmpeg -y -i .tools/shots/game.avi -vf "select=eq(n\,150)" -vframes 1 .tools/shots/game.png
```

Use `read_image` on the PNG to inspect it (agents have the same tools).
Gameplay screenshots need plants/zombies: write a small capture scene
(`tools/verify/capture_game.tscn` or a `--script` runner) that instantiates
`main.tscn` and plants/spawns a fixed layout via the real APIs.

### Web

```bash
cd /home/frti64/pvz_like_game
python3 serve.py 8080 &        # or any static server with correct MIME types
# verifier provides: node tools/verify/web_shot.mjs <url> <out.png>
```

Headless Chromium (downloaded by Lead): `.tools/browsers/chromium-1148/...`;
`playwright-core` installed in `.tools/node_modules/playwright-core`.
Use `--enable-unsafe-swiftshader` args for WebGL in headless.

## 7. Acceptance checklist

Gameplay parity (both versions):
- [ ] Level select from menu works; starting a level enters 3D view.
- [ ] Planting via seed cards works on any empty lawn cell; sun cost & cooldown.
- [ ] Sun drops from sky and from sunflowers; clicking a sun collects it (+25).
- [ ] Pea/snow-pea/repeater projectile hit, damage, chilled slow.
- [ ] Wallnut crack stages; potato mine arm + detonate; cherry 3x3 explosion;
      chomper eat/chew; all 4 zombie types incl. cone/bucket armor break + flag.
- [ ] Zombie eating plants; lawnmower triggers and clears a lane.
- [ ] Wave progress, huge-wave banner, victory & defeat, pause/restart/menu.
- [ ] HUD readable over 3D, sun counter updates, no layout regressions.

Visual:
- [ ] Clearly 3D perspective (ground plane, depth scaling, 3D house/fence/
      trees/sky, directional light + shadows on props, blob shadows under units).
- [ ] Characters are 2D art billboards standing on the lawn (HD-2D look),
      animating (walk/sway), tinted correctly (chilled/flash), sensible depth
      order and no z-fighting/clipping into the ground.
- [ ] Hover highlight + ghost preview align with the actual cell under cursor
      (click→cell mapping must match visuals).
- [ ] Roughly stable frame rate (Godot movie maker CPU render < ~6 ms/frame at
      1280x720 on llvmpipe; web ~60fps on a normal GPU / >20fps in headless
      SwiftShader screenshot mode is fine as a smoke test).
- [ ] No errors/warnings in console/logs on level start and 30 s of play.

## 8. Owner / write-scope split (advisory; keep edits inside your scope)

| Owner | Files |
|---|---|
| lead | `docs/`, `tools/billboard_factory.*`, `assets/billboards/`, `scripts/core/world_space.gd`, `scripts/visuals/billboard_anim.gd`, `scripts/visuals/billboard_library.gd`, `scripts/autoload/event_bus.gd`, `README.md`, `.gitignore`, `.tools/` |
| godot-world | `project.godot`, `scenes/main.tscn`, `scripts/main.gd`, `scripts/core/grid_manager.gd`, `scripts/core/sun_manager.gd`, `scripts/core/wave_manager.gd`, `scripts/core/board_builder.gd`, `scripts/core/camera_rig.gd` |
| godot-entities | `scenes/plants/`, `scenes/zombies/`, `scenes/projectiles/`, `scenes/items/`, `scenes/effects/`, `scripts/plants/`, `scripts/zombies/`, `scripts/projectiles/`, `scripts/items/`, `scripts/effects/` |
| web3d | `web_preview/`, `tools/build_web_assets.mjs` |
| verifier | `tools/verify/`, `screenshots/` |

Do not edit files outside your scope; ask the Lead for cross-scope changes.
`scenes/ui/`, `scenes/main_menu.tscn`, `scripts/ui/`, `data/`, `scripts/autoload/`
(except event_bus by Lead), `scripts/resources/`, `scripts/visuals/*_visuals.gd`
are read-only for everyone.

## 9. Work protocol

1. Read this spec + the current 2D code before editing.
2. Code in your scope; keep the game working via `main.tscn` at all times after
   your first integration point (coordinate with Lead if the scene is mid-flight).
3. Self-test with the commands in §6: record screenshots and inspect them with
   `read_image`. Iterate until the visual bar is met. Report progress with
   concrete screenshot paths + any blocked contracts.
4. Send the Lead a concise status when: (a) first working end-to-end render,
   (b) blocked, (c) complete. Include: files changed, screenshot path, open
   issues, suggested next step.
5. The Lead runs independent verification and will report defects for a fix
   round. Do not declare done until Lead accepts.

## 10. Aesthetic reference (target mood)

Warm sunny front-yard, stylized low-poly board-game diorama seen through a
perspective camera; charming HD-2D characters standing on a crisp green
checkerboard lawn; soft shadows, bright sky, saturated but not neon. Avoid
photorealism, avoid dark/night palette (levels 1–3 all remain daytime).
