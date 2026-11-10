extends Node
## Independent verification capture harness — owned by `verifier`, NOT production code.
##
## Instantiates res://scenes/main.tscn, plants a deterministic set of plants via
## GridManager.place_plant(), spawns zombies via WaveManager._spawn_zombie(), adds
## suns via SunManager.spawn_natural_sun(), waits for the requested game time, then
## saves a PNG of the root viewport and quits.
##
## Run through tools/verify/godot_shot.sh (WSLg wayland + llvmpipe recipe from
## docs/3d-render-spec.md §6). Direct form:
##
##   godot --path . tools/verify/capture_godot.tscn \
##     --display-driver wayland --rendering-driver opengl3 -- \
##     --setup gameplay --out screenshots/godot_3d_gameplay.png --wait 2.5
##
## --setup: empty | plants | zombies | suns | gameplay | pause
## Prints `VERIFY_CAPTURE_OK <json>` on success, `VERIFY_CAPTURE_FAIL: <reason>` on failure.
## Exit code 0 = captured OK, 1 = failure.

const PLANT_DATA_PATHS := {
	"peashooter": "res://data/plants/peashooter.tres",
	"sunflower": "res://data/plants/sunflower.tres",
	"wallnut": "res://data/plants/wallnut.tres",
	"cherry_bomb": "res://data/plants/cherry_bomb.tres",
	"snow_pea": "res://data/plants/snow_pea.tres",
	"potato_mine": "res://data/plants/potato_mine.tres",
	"repeater": "res://data/plants/repeater.tres",
	"chomper": "res://data/plants/chomper.tres",
}

const ZOMBIE_DATA_PATHS := {
	"normal": "res://data/zombies/normal_zombie.tres",
	"conehead": "res://data/zombies/conehead_zombie.tres",
	"buckethead": "res://data/zombies/buckethead_zombie.tres",
	"flag": "res://data/zombies/flag_zombie.tres",
}

const SETUPS := ["empty", "plants", "zombies", "suns", "gameplay", "pause", "victory", "gameover", "menu", "tintdiff", "armordiff"]

var setup_name: String = "gameplay"
var out_rel: String = ""
var wait_seconds: float = 2.5

var _main: Node = null
var _grid: Node = null
var _wave: Node = null
var _sun: Node = null
var _hud: Node = null
var _planted: int = 0
var _zombie_count: int = 0
var _sun_count: int = 0
var _warnings: Array[String] = []
var _failed: bool = false

func _ready() -> void:
	_parse_args()
	if _failed:
		return
	if not SETUPS.has(setup_name):
		_fail("unknown --setup '%s' (expected one of %s)" % [setup_name, ", ".join(SETUPS)])
		return
	if out_rel.is_empty():
		out_rel = "screenshots/godot_3d_%s.png" % setup_name
	await _frames(2)
	await _run()

# ---------------------------------------------------------------------------
# argument parsing / exit helpers
# ---------------------------------------------------------------------------
func _parse_args() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var i: int = 0
	while i < args.size():
		var key: String = args[i]
		var val: String = args[i + 1] if i + 1 < args.size() else ""
		match key:
			"--setup":
				setup_name = val
				i += 2
			"--out":
				out_rel = val
				i += 2
			"--wait":
				wait_seconds = float(val)
				i += 2
			_:
				_warn("ignoring unknown capture arg: %s" % key)
				i += 1

func _warn(msg: String) -> void:
	_warnings.append(msg)
	print("VERIFY_CAPTURE_WARN: ", msg)

func _fail(reason: String) -> void:
	if _failed:
		return
	_failed = true
	printerr("VERIFY_CAPTURE_FAIL: ", reason)
	print("VERIFY_CAPTURE_FAIL: ", reason)
	get_tree().quit(1)

func _finish_ok(path: String, size: Vector2i) -> void:
	print("VERIFY_CAPTURE_OK ", JSON.stringify({
		"ok": true,
		"setup": setup_name,
		"path": path,
		"size": [size.x, size.y],
		"plants": _planted,
		"zombies": _zombie_count,
		"suns": _sun_count,
		"warnings": _warnings,
	}))
	get_tree().quit(0)

# ---------------------------------------------------------------------------
# tiny async helpers
# ---------------------------------------------------------------------------
func _frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func _seconds(t: float) -> void:
	# process_always=true: keeps elapsing while the tree is paused (pause setup).
	if t > 0.0:
		await get_tree().create_timer(t, true).timeout

# ---------------------------------------------------------------------------
# property helpers that work on both the old 2D and the new 3D entity classes
# ---------------------------------------------------------------------------
func _has_prop(obj: Object, prop: String) -> bool:
	if obj == null:
		return false
	for p in obj.get_property_list():
		if String(p.get("name", "")) == prop:
			return true
	return false

func _try_set(obj: Object, prop: String, value: Variant) -> bool:
	if _has_prop(obj, prop):
		obj.set(prop, value)
		return true
	return false

func _try_props(obj: Object, pairs: Array) -> bool:
	var done: bool = false
	for pair in pairs:
		if _try_set(obj, String(pair[0]), pair[1]):
			done = true
	return done

func _is_vec3(v: Variant) -> bool:
	return typeof(v) == TYPE_VECTOR3

# ---------------------------------------------------------------------------
# scene construction
# ---------------------------------------------------------------------------
func _run() -> void:
	var scene_path: String = "res://scenes/main.tscn"
	if setup_name == "menu":
		scene_path = "res://scenes/main_menu.tscn"
	var packed: PackedScene = load(scene_path) as PackedScene
	if packed == null:
		_fail("cannot load " + scene_path)
		return
	_main = packed.instantiate()
	if _main == null:
		_fail("main.tscn instantiate returned null")
		return
	add_child(_main)
	await _frames(4)

	if setup_name == "menu":
		await _seconds(maxf(wait_seconds, 1.0))
		await _capture_and_quit()
		return

	_grid = _main.find_child("GridManager", true, false)
	_wave = _main.find_child("WaveManager", true, false)
	_sun = _main.find_child("SunManager", true, false)
	_hud = _main.find_child("HUD", true, false)
	if _grid == null:
		_fail("GridManager node not found under main.tscn")
		return
	if _hud == null:
		_warn("HUD node not found (2D CanvasLayer expected)")

	# Force the capture window to the canonical 1280x720 project viewport.
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_size(Vector2i(1280, 720))

	match setup_name:
		"empty":
			pass
		"plants":
			_setup_plants()
		"zombies":
			_setup_zombies()
		"suns":
			_setup_suns()
		"gameplay":
			_setup_plants()
			_setup_zombies()
			_setup_suns()
		"pause":
			_setup_plants()
			_setup_zombies()
			_setup_suns()
		"victory", "gameover":
			_setup_plants()
			_setup_zombies()
		"tintdiff", "armordiff":
			await _run_diff_setup()
			return
		_:
			_fail("unhandled setup " + setup_name)
			return

	if _failed:
		return
	await _seconds(wait_seconds)

	if setup_name == "pause":
		_open_pause()
		await _frames(6)
	elif setup_name == "victory":
		EventBus.game_over.emit(true)
		await _seconds(1.2)
	elif setup_name == "gameover":
		EventBus.game_over.emit(false)
		await _seconds(1.2)

	if _failed:
		return
	await _capture_and_quit()

func _capture_and_quit() -> void:
	var abs_path: String = ProjectSettings.globalize_path("res://").path_join(out_rel)
	var size: Vector2i = await _save_viewport_to(abs_path)
	if _failed:
		return
	_finish_ok(abs_path, size)

## Save the current root viewport to an absolute PNG path (creates parent dirs).
func _save_viewport_to(abs_path: String) -> Vector2i:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	if img == null or img.is_empty():
		_fail("viewport image is empty")
		return Vector2i.ZERO
	var dir: String = abs_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		var mk: Error = DirAccess.make_dir_recursive_absolute(dir)
		if mk != OK:
			_fail("cannot create output directory " + dir)
			return Vector2i.ZERO
	var err: Error = img.save_png(abs_path)
	if err != OK:
		_fail("save_png failed (%s) for %s" % [str(err), abs_path])
		return Vector2i.ZERO
	return img.get_size()

func _with_suffix(path: String, suffix: String) -> String:
	var base: String = path.get_basename()
	var ext: String = path.get_extension()
	if ext.is_empty():
		return base + suffix
	return base + suffix + "." + ext

## Entity billboard screen region (for before/after pixel-diff visual checks).
func _entity_region(node: Node) -> Dictionary:
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null or not (node is Node3D):
		return {}
	var z3: Node3D = node as Node3D
	var feet: Vector3 = z3.global_position
	var head: Vector3 = feet + Vector3(0.0, 128.0 / 45.0, 0.0) # billboard is 128 game px tall
	var sf: Vector2 = cam.unproject_position(feet)
	var sh: Vector2 = cam.unproject_position(head)
	var span: float = maxf(absf(sh.y - sf.y), 20.0)
	var w: float = maxf(span * 1.5, 36.0)
	var h: float = maxf(span * 1.6, 48.0)
	var x0: int = int(clampf(sf.x - w * 0.5, 0.0, 1276.0))
	var y0: int = int(clampf(sf.y - h * 1.05, 0.0, 716.0))
	var x1: int = int(clampf(sf.x + w * 0.5, float(x0 + 4), 1280.0))
	var y1: int = int(clampf(sf.y + h * 0.25, float(y0 + 4), 720.0))
	return {"x": x0, "y": y0, "w": x1 - x0, "h": y1 - y0, "feet": [sf.x, sf.y], "span": span}

func _finish_ok_multi(path: String, extra: Dictionary) -> void:
	var payload := {
		"ok": true,
		"setup": setup_name,
		"path": path,
		"warnings": _warnings,
	}
	payload.merge(extra, true)
	print("VERIFY_CAPTURE_OK ", JSON.stringify(payload))
	get_tree().quit(0)

## Visual before/after check: chilled tint (zombie-modulate) or cone armor break
## (billboard sheet swap + falling 3D prop). Saves <out> and <out>_after.png plus
## the billboard screen region for tools/verify/godot_visual_check.mjs.
func _run_diff_setup() -> void:
	if _wave == null:
		_fail("WaveManager missing for " + setup_name)
		return
	var zid: String = "normal" if setup_name == "tintdiff" else "conehead"
	var zombie: Node = _spawn_zombie_at(zid, 2, 800.0)
	if zombie == null:
		_fail("could not spawn zombie for " + setup_name)
		return
	await _seconds(1.2)
	var region: Dictionary = _entity_region(zombie)
	if region.is_empty():
		_fail("cannot compute entity screen region")
		return
	var sheet_before: String = String(zombie.get("billboard_sheet"))
	var abs_before: String = ProjectSettings.globalize_path("res://").path_join(out_rel)
	var size: Vector2i = await _save_viewport_to(abs_before)
	if _failed:
		return
	var abs_after: String = _with_suffix(abs_before, "_after")
	if setup_name == "tintdiff":
		if zombie.has_method("apply_chill"):
			zombie.call("apply_chill", 60.0)
		else:
			_try_props(zombie, [["is_chilled", true], ["chilled", true], ["chill_timer", 60.0]])
	else:
		if zombie.has_method("take_damage"):
			zombie.call("take_damage", 400) # conehead armor = 370 -> breaks
		else:
			_fail("zombie has no take_damage()")
			return
	await _seconds(0.25)
	var sheet_after: String = String(zombie.get("billboard_sheet"))
	var tint: Variant = null
	if setup_name == "tintdiff":
		var vn: Variant = zombie.get("visual_node")
		if vn != null:
			tint = str(vn.get("modulate"))
	await _save_viewport_to(abs_after)
	if _failed:
		return
	_finish_ok_multi(abs_before, {
		"size": [size.x, size.y],
		"after_path": abs_after,
		"region": region,
		"sheet_before": sheet_before,
		"sheet_after": sheet_after,
		"visual_modulate": tint,
	})

# ---------------------------------------------------------------------------
# deterministic setups
# ---------------------------------------------------------------------------
func _plant_data(id: String) -> PlantData:
	var path: String = PLANT_DATA_PATHS.get(id, "")
	if path.is_empty():
		return null
	return load(path) as PlantData

func _place_plant(id: String, col: int, row: int, visual_state: String = "") -> Node:
	var data: PlantData = _plant_data(id)
	if data == null:
		_warn("plant data missing for " + id)
		return null
	var cell := Vector2i(col, row)
	var plant: Node = null
	if _grid.has_method("place_plant"):
		plant = _grid.place_plant(cell, data)
	if plant == null:
		_warn("place_plant failed for %s at %s" % [id, str(cell)])
		return null
	_planted += 1
	match visual_state:
		"armed":
			# potato mine: let it arm on the next process tick
			_try_props(plant, [["arm_timer", 0.05], ["is_armed", true]])
		"cracked":
			# wallnut crack stage (spec §3.2): damage it after it is in the tree
			plant.call_deferred("take_damage", 2100)
		"cracked_heavy":
			plant.call_deferred("take_damage", 3100)
		"frozen_fuse":
			_try_props(plant, [["fuse_timer", 3600.0]])
	return plant

func _zombie_data(id: String) -> ZombieData:
	var path: String = ZOMBIE_DATA_PATHS.get(id, "")
	if path.is_empty():
		return null
	return load(path) as ZombieData

func _spawn_zombie_at(id: String, lane: int, x: float, extra: Dictionary = {}) -> Node:
	var zdata: ZombieData = _zombie_data(id)
	if zdata == null:
		_warn("zombie data missing for " + id)
		return null
	var zombie: Node = null
	if _wave != null and _wave.has_method("_spawn_zombie"):
		_wave._spawn_zombie(zdata, lane)
		var list: Array = _wave.get("alive_zombies")
		if list != null and list.size() > 0:
			zombie = list[list.size() - 1]
	if zombie == null:
		_warn("could not spawn zombie " + id)
		return null
	_set_ground_position(zombie, x, 175.0 + lane * 108.0)
	for key in extra.keys():
		_try_set(zombie, String(key), extra[key])
	_zombie_count += 1
	return zombie

## Put an entity root on the ground plane at game-px (x, y_game).
## Old 2D scene: position is Vector2. Converted 3D scene: local position is
## Vector3(game_x, 0, game_y) under WorldRoot (spec §2.1).
func _set_ground_position(node: Node, x: float, y_game: float) -> void:
	var p: Variant = node.get("position")
	if _is_vec3(p):
		node.set("position", Vector3(x, 0.0, y_game))
	else:
		node.set("position", Vector2(x, y_game))

func _setup_plants() -> void:
	# all 8 plant types spread out; deterministic visual states for the QA shot
	_place_plant("peashooter", 1, 2)
	_place_plant("sunflower", 2, 2)
	_place_plant("wallnut", 3, 1)
	_place_plant("snow_pea", 1, 3)
	_place_plant("repeater", 2, 0)
	_place_plant("chomper", 4, 2)
	_place_plant("cherry_bomb", 5, 1, "frozen_fuse")
	_place_plant("potato_mine", 1, 4, "armed")
	_place_plant("wallnut", 4, 1, "cracked")
	_place_plant("wallnut", 5, 4, "cracked_heavy")

func _setup_zombies() -> void:
	_spawn_zombie_at("normal", 2, 760.0)
	_spawn_zombie_at("conehead", 1, 820.0)
	_spawn_zombie_at("buckethead", 3, 880.0)
	_spawn_zombie_at("flag", 0, 840.0)
	# one chilled zombie for the tint check (property differs between 2D/3D)
	var z: Node = _spawn_zombie_at("normal", 4, 900.0)
	if z != null:
		_try_props(z, [["is_chilled", true], ["chilled", true], ["chill_timer", 30.0]])

func _setup_suns() -> void:
	if _sun == null:
		_warn("SunManager node not found")
		return
	for i in range(2):
		_sun.spawn_natural_sun()
		await _frames(1)
		var suns: Array = _sun.get("active_suns")
		if suns == null or suns.size() == 0:
			continue
		var s: Node = suns[suns.size() - 1]
		if s == null:
			continue
		var p: Variant = s.get("position")
		if _is_vec3(p):
			s.set("position", Vector3(560.0 + i * 180.0, 95.0, 300.0 + i * 120.0))
		else:
			s.set("position", Vector2(560.0 + i * 180.0, 300.0 + i * 120.0))
		_sun_count += 1

func _open_pause() -> void:
	if _hud == null:
		_warn("cannot open pause: HUD missing")
		return
	var btn: Button = _hud.get_node_or_null("MenuButton") as Button
	if btn != null:
		btn.pressed.emit()
	else:
		_warn("HUD MenuButton not found; pausing tree directly")
		get_tree().paused = true
	await _frames(2)
	if not get_tree().paused:
		_warn("pause did not set get_tree().paused")
