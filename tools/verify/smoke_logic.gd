extends Node
## tools/verify/smoke_logic.gd — independent headless logic/flow smoke test (verifier-owned).
##
## Scene-based runner (NOT `extends SceneTree --script`, which breaks autoload compile
## order in this project): instantiates res://scenes/main.tscn as a child, plants via
## real GridManager + synthetic viewport input, spawns zombies via WaveManager, and
## asserts gameplay invariants. Writes a JSON report and exits nonzero on failure.
##
## Run through tools/verify/godot_smoke.sh, or directly:
##   godot --headless --fixed-fps 60 --path . tools/verify/smoke_logic.tscn \
##     -- --frames 600 --out tools/verify/tmp/smoke_report.json
##
## Exit code: 0 = all required checks pass, 1 = check failure, 2 = setup failure.

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
const CELL_SIZE := Vector2(98.0, 108.0)
const GRID_ORIGIN := Vector2(275.0, 125.0)

var frames_budget: int = 600
var level_path: String = "res://data/levels/level_1.tres"
var report_path: String = "tools/verify/tmp/smoke_report.json"
var strict: bool = false

var checks: Array = []
var warnings: Array[String] = []
var counters: Dictionary = {
	"zombie_spawned": 0, "zombie_died": 0, "huge_wave": 0,
	"sun_amount_events": 0, "plant_died": 0, "mower_triggered": 0,
}
var frames_run: int = 0
var _main: Node = null
var _grid: Node = null
var _wave: Node = null
var _sun: Node = null
var _hud: Node = null
var _is_3d: bool = false
var _level: LevelData = null
var _start_sun: int = 0

func _ready() -> void:
	_parse_args()
	_level = load(level_path) as LevelData
	if _level == null:
		_fatal("cannot load level " + level_path)
		return
	_connect_counters()
	await _frames(2)
	await _run()

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------
func _parse_args() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var i: int = 0
	while i < args.size():
		var key: String = args[i]
		var val: String = args[i + 1] if i + 1 < args.size() else ""
		match key:
			"--frames": frames_budget = int(val); i += 2
			"--level": level_path = val; i += 2
			"--out": report_path = val; i += 2
			"--strict": strict = true; i += 1
			_: i += 1

func _connect_counters() -> void:
	EventBus.zombie_spawned.connect(func(_z): counters.zombie_spawned += 1)
	EventBus.zombie_died.connect(func(_z): counters.zombie_died += 1)
	EventBus.huge_wave_warning.connect(func(): counters.huge_wave += 1)
	EventBus.sun_amount_changed.connect(func(_a, _d): counters.sun_amount_events += 1)
	EventBus.lawn_mower_triggered.connect(func(_row): counters.mower_triggered += 1)

func _check(name: String, ok: bool, detail: Variant = null, required: bool = true) -> bool:
	checks.append({"name": name, "ok": ok, "required": required, "detail": detail})
	print(("PASS " if ok else "FAIL ") + name + ("" if detail == null else " :: " + str(detail)))
	if not ok and required:
		warnings.append("FAILED: " + name)
	return ok

func _warn(msg: String) -> void:
	warnings.append(msg)
	print("WARN " + msg)

func _fatal(msg: String) -> void:
	printerr("VERIFY_SMOKE_FATAL: " + msg)
	print("VERIFY_SMOKE_FATAL: " + msg)
	get_tree().quit(2)

func _frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame
		frames_run += 1

func _seconds(t: float) -> void:
	await get_tree().create_timer(t, true).timeout

func _plant_data(id: String) -> PlantData:
	var p: String = PLANT_DATA_PATHS.get(id, "")
	return load(p) as PlantData if not p.is_empty() else null

func _zombie_data(id: String) -> ZombieData:
	var p: String = ZOMBIE_DATA_PATHS.get(id, "")
	return load(p) as ZombieData if not p.is_empty() else null

func _cell_center(cell: Vector2i) -> Vector2:
	return GRID_ORIGIN + Vector2(cell.x * CELL_SIZE.x + CELL_SIZE.x * 0.5, cell.y * CELL_SIZE.y + CELL_SIZE.y * 0.5)

## Game-px point -> viewport screen point for synthetic input.
func _game_to_screen(game: Vector2, height_px: float = 0.0) -> Vector2:
	if not _is_3d:
		return game
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return game
	var grid_3d: Node3D = _grid as Node3D
	var local := Vector3(game.x, height_px, game.y)
	var world: Vector3 = grid_3d.global_transform * local if grid_3d != null else local
	return cam.unproject_position(world)

func _push_mouse_button(screen: Vector2, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.position = screen
	ev.global_position = screen
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	get_viewport().push_input(ev, true)

func _click_at(screen: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = screen
	motion.global_position = screen
	get_viewport().push_input(motion, true)
	await _frames(1)
	_push_mouse_button(screen, true)
	await _frames(1)
	_push_mouse_button(screen, false)
	await _frames(2)

func _click_cell(cell: Vector2i) -> void:
	var gp: Vector2 = _cell_center(cell)
	await _click_at(_game_to_screen(gp, 0.0))

func _plant_via_click(id: String, cell: Vector2i) -> Node:
	var data: PlantData = _plant_data(id)
	if data == null:
		_warn("missing plant data " + id)
		return null
	GameManager.select_plant(data)
	await _frames(1)
	await _click_cell(cell)
	return _grid.get_plant(cell)

func _ground_x(node: Node) -> float:
	var p: Variant = node.get("position")
	if typeof(p) == TYPE_VECTOR3:
		return float(p.x)
	if typeof(p) == TYPE_VECTOR2:
		return float(p.x)
	return 0.0

# ---------------------------------------------------------------------------
# main flow
# ---------------------------------------------------------------------------
func _run() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn") as PackedScene
	if packed == null:
		_fatal("cannot load res://scenes/main.tscn")
		return
	_main = packed.instantiate()
	if _main == null:
		_fatal("main.tscn instantiate failed")
		return
	add_child(_main)
	await _frames(4)

	_grid = _main.find_child("GridManager", true, false)
	_wave = _main.find_child("WaveManager", true, false)
	_sun = _main.find_child("SunManager", true, false)
	_hud = _main.find_child("HUD", true, false)
	_is_3d = _main is Node3D

	_check("main scene loaded (3D root)", _main != null && _is_3d, {"root": _main.get_class()})
	_check("GridManager/SunManager/WaveManager found", _grid != null and _sun != null and _wave != null)
	if _grid == null or _sun == null or _wave == null:
		_finalize()
		return
	_check("HUD (CanvasLayer) found", _hud != null)
	_check("GameManager state PLAYING", GameManager.current_state == GameManager.GameState.PLAYING, {"state": GameManager.current_state})
	_start_sun = GameManager.current_sun
	_check("initial sun == level initial_sun", _start_sun == _level.initial_sun, {"sun": _start_sun, "expected": _level.initial_sun})
	var cells: Dictionary = _grid.get("grid_cells")
	_check("grid starts empty", cells != null and cells.size() == 0, {"cells": cells.size() if cells != null else null})
	var wave_idx_initial: int = int(_wave.get("current_wave_idx"))

	# --- real input: select card (GameManager API) + synthetic viewport click ---
	var peashooter: Node = await _plant_via_click("peashooter", Vector2i(2, 1))
	_check("click plants peashooter at cell (col2,row1)", peashooter != null, {"plant": peashooter != null})
	_check("sun spent 100 by planting", GameManager.current_sun == _start_sun - 100, {"sun": GameManager.current_sun})
	_check("selection cleared after planting", GameManager.selected_plant_data == null)

	# occupied cell must not be overwritten and must not spend sun
	var sun_before := GameManager.current_sun
	var cells_before: int = _grid.get("grid_cells").size()
	await _plant_via_click("sunflower", Vector2i(2, 1))
	var still_peashooter: bool = _grid.get_plant(Vector2i(2, 1)) == peashooter
	var cells_after: int = _grid.get("grid_cells").size()
	_check("occupied cell rejects planting", still_peashooter and cells_after == cells_before, {"cells_before": cells_before, "cells_after": cells_after, "still_peashooter": still_peashooter})
	_check("occupied-cell rejection did not spend sun", GameManager.current_sun == sun_before, {"sun": GameManager.current_sun})

	# insufficient funds must not plant
	GameManager.current_sun = 10
	var poor_plant: Node = await _plant_via_click("repeater", Vector2i(0, 4))
	_check("insufficient sun rejects planting", poor_plant == null, {"planted": poor_plant != null})
	GameManager.add_sun(1000)
	_check("GameManager.add_sun works", GameManager.current_sun == 1010, {"sun": GameManager.current_sun})

	# plant remaining types through the same real click path
	for pair in [["sunflower", Vector2i(3, 1)], ["wallnut", Vector2i(4, 2)], ["snow_pea", Vector2i(2, 3)], ["chomper", Vector2i(3, 0)]]:
		var id: String = pair[0]
		var cell: Vector2i = pair[1]
		var pl: Node = await _plant_via_click(id, cell)
		_check("click plants %s at %s" % [id, str(cell)], pl != null, {"plant": pl.get("plant_data").id if pl != null else null})
	var planted_count: int = _grid.get("grid_cells").size()
	_check("5 plants placed via input", planted_count >= 5, {"plants": planted_count})

	# --- sun economy: natural sun spawns; projected-click collects it ---
	var suns: Array = _sun.get("active_suns")
	var waited: int = 0
	while (suns == null or suns.size() == 0) and waited < 900:
		await _frames(15)
		waited += 15
		suns = _sun.get("active_suns")
	_check("natural sun spawns", suns != null and suns.size() > 0, {"waited_frames": waited, "suns": suns.size() if suns != null else null})
	if suns != null and suns.size() > 0:
		var sun_node: Node = suns[0]
		var cam2: Camera3D = get_viewport().get_camera_3d()
		var sun_screen: Vector2 = Vector2(-1000, -1000)
		# Wait until the sun has fallen onto the lawn and is not behind the HUD strip
		# (HUD Control overlays the top ~98 px and eats clicks there).
		var settle_wait: int = 0
		while settle_wait < 600:
			if _is_3d and sun_node is Node3D:
				var sp3: Vector3 = (sun_node as Node3D).position
				var target_z: float = float(sun_node.get("target_z"))
				if absf(sp3.z - target_z) < 3.0 and cam2 != null:
					sun_screen = cam2.unproject_position((sun_node as Node3D).global_position)
			else:
				sun_screen = sun_node.get("position")
			if sun_screen.y > 150.0 and sun_screen.x > 20.0 and sun_screen.x < 1260.0:
				break
			await _frames(10)
			settle_wait += 10
		var sun_before_click := GameManager.current_sun
		await _click_at(sun_screen)
		await _frames(60)
		_check("clicking projected sun screen position adds +25", GameManager.current_sun == sun_before_click + 25, {"before": sun_before_click, "after": GameManager.current_sun, "screen": sun_screen})
		# fallback path (Lead-requested): direct collect() on a second sun
		var suns2: Array = _sun.get("active_suns")
		_sun.call("spawn_natural_sun")
		await _frames(5)
		suns2 = _sun.get("active_suns")
		if suns2.size() > 0:
			var s2: Node = suns2[suns2.size() - 1]
			if s2.has_method("collect"):
				var before2 := GameManager.current_sun
				s2.call("collect")
				await _frames(40)
				_check("Sun.collect() adds +25", GameManager.current_sun == before2 + 25, {"before": before2, "after": GameManager.current_sun})

	# --- wave spawn through the real wave manager ---
	_wave.set("wave_timer", 0.02)
	var spawn_wait := 0
	while counters.zombie_spawned == 0 and spawn_wait < 300:
		await _frames(5)
		spawn_wait += 5
	_check("wave spawns zombies (zombie_spawned signal)", counters.zombie_spawned > 0, {"spawned": counters.zombie_spawned, "waited_frames": spawn_wait})
	var waves: Array = _wave.get("alive_zombies")
	_check("alive_zombies populated", waves != null and waves.size() > 0, {"alive": waves.size() if waves != null else null})
	_check("wave index advanced", int(_wave.get("current_wave_idx")) > wave_idx_initial, {"wave": _wave.get("current_wave_idx"), "initial": wave_idx_initial})

	# --- zombies walk left ---
	if waves != null and waves.size() > 0:
		var z: Node = waves[0]
		var x0 := _ground_x(z)
		await _frames(30)
		var x1 := _ground_x(z)
		_check("zombie walks left (position.x decreases)", x1 < x0 - 3.0, {"x0": x0, "x1": x1, "dx": x1 - x0})

	# --- projectile damage: low-hp zombie in peashooter lane dies ---
	var zd: ZombieData = _zombie_data("normal")
	if zd != null:
		_wave.call("_spawn_zombie", zd, 1)
		await _frames(2)
		var alive: Array = _wave.get("alive_zombies")
		if alive.size() > 0:
			var test_z: Node = alive[alive.size() - 1]
			if _is_3d:
				(test_z as Node3D).position = Vector3(560.0, 0.0, 175.0 + 1 * 108.0)
			else:
				(test_z as Node2D).position = Vector2(560.0, 175.0 + 1 * 108.0)
			# low hp so a couple of peas kill it (projectile/damage path still real)
			for prop in ["current_health", "health"]:
				if _has_prop(test_z, prop):
					test_z.set(prop, 25)
					break
			var death_wait := 0
			var died: int = int(counters.zombie_died)
			while counters.zombie_died == died and death_wait < 480:
				await _frames(10)
				death_wait += 10
			_check("peashooter projectile kills zombie", counters.zombie_died > died, {"waited_frames": death_wait, "deaths": counters.zombie_died})

	# --- zombie eating: plant health drops ---
	var wallnut_plant: Node = _grid.get_plant(Vector2i(4, 2))
	if wallnut_plant != null and _wave != null:
		var hp0: int = wallnut_plant.get("current_health")
		var zdata: ZombieData = _zombie_data("normal")
		_wave.call("_spawn_zombie", zdata, 2)
		await _frames(2)
		var alive2: Array = _wave.get("alive_zombies")
		if alive2.size() > 0:
			var eater: Node = alive2[alive2.size() - 1]
			# place the zombie right on the wallnut so it starts eating
			var wn_x := _ground_x(wallnut_plant)
			if _is_3d:
				(eater as Node3D).position = Vector3(wn_x + 8.0, 0.0, 175.0 + 2 * 108.0)
			else:
				(eater as Node2D).position = Vector2(wn_x + 8.0, 175.0 + 2 * 108.0)
			await _frames(120)
			var hp1: int = wallnut_plant.get("current_health") if is_instance_valid(wallnut_plant) else -1
			_check("zombie eats plant (plant health decreases)", hp1 < hp0, {"hp_before": hp0, "hp_after": hp1})

	# --- lawnmower clears a lane ---
	var mowers: Node = _main.find_child("LawnMowers", true, false)
	if mowers != null and mowers.get_child_count() > 0:
		var mower_node: Node = mowers.get_child(0)
		var lane: int = int(mower_node.get("row"))
		var zdata2: ZombieData = _zombie_data("normal")
		_wave.call("_spawn_zombie", zdata2, lane)
		await _frames(2)
		var alive3: Array = _wave.get("alive_zombies")
		if alive3.size() > 0:
			var mz: Node = alive3[alive3.size() - 1]
			var mower_x := _ground_x(mower_node)
			if _is_3d:
				(mz as Node3D).position = Vector3(mower_x + 10.0, 0.0, 175.0 + lane * 108.0)
			else:
				(mz as Node2D).position = Vector2(mower_x + 10.0, 175.0 + lane * 108.0)
			var mow_wait := 0
			while counters.mower_triggered == 0 and mow_wait < 240:
				await _frames(10)
				mow_wait += 10
			_check("lawnmower triggers on approaching zombie", counters.mower_triggered > 0, {"waited_frames": mow_wait})
	else:
		_check("LawnMowers node exists", false)

	# --- pause/resume via HUD button signal ---
	if _hud != null:
		var btn: Button = _hud.get_node_or_null("MenuButton") as Button
		if btn != null:
			btn.pressed.emit()
			await _frames(3)
			_check("HUD pause button pauses tree", get_tree().paused == true)
			var panel: Control = _hud.get_node_or_null("PauseMenuPanel") as Control
			_check("pause panel visible", panel != null and panel.visible)
			btn.pressed.emit()
			await _frames(3)
			_check("second press resumes", get_tree().paused == false)
		else:
			_check("HUD MenuButton found", false)

	# --- victory/defeat HUD paths ---
	if _hud != null:
		EventBus.game_over.emit(true)
		await _frames(10)
		var victory_panel: Control = _hud.get_node_or_null("VictoryPanel") as Control
		_check("victory: GameManager VICTORY + panel visible",
			GameManager.current_state == GameManager.GameState.VICTORY and victory_panel != null and victory_panel.visible,
			{"state": GameManager.current_state})
		EventBus.game_over.emit(false)
		await _frames(10)
		var over_panel: Control = _hud.get_node_or_null("GameOverPanel") as Control
		_check("defeat: GameManager GAME_OVER + panel visible",
			GameManager.current_state == GameManager.GameState.GAME_OVER and over_panel != null and over_panel.visible,
			{"state": GameManager.current_state})

	# --- run out the remaining frame budget (soak) ---
	while frames_run < frames_budget:
		await _frames(10)
	_check("ran >= %d physics frames" % frames_budget, frames_run >= frames_budget, {"frames": frames_run})

	_finalize()

func _has_prop(obj: Object, prop: String) -> bool:
	if obj == null:
		return false
	for p in obj.get_property_list():
		if String(p.get("name", "")) == prop:
			return true
	return false

func _finalize() -> void:
	var required_failed: Array = []
	var optional_failed: Array = []
	for c in checks:
		if not c.ok:
			if c.required:
				required_failed.append(c.name)
			else:
				optional_failed.append(c.name)
	var ok: bool = required_failed.is_empty()
	var report := {
		"ok": ok,
		"checks": checks,
		"required_failed": required_failed,
		"optional_failed": optional_failed,
		"warnings": warnings,
		"counters": counters,
		"frames_run": frames_run,
		"is_3d": _is_3d,
		"level": level_path,
		"passed": checks.size() - required_failed.size() - optional_failed.size(),
		"total": checks.size(),
	}
	var abs_path: String = ProjectSettings.globalize_path("res://").path_join(report_path)
	DirAccess.make_dir_recursive_absolute(abs_path.get_base_dir())
	var f := FileAccess.open(abs_path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(report, "  "))
		f.close()
	print("VERIFY_SMOKE_RESULT ", JSON.stringify({"ok": ok, "passed": report.passed, "total": report.total, "required_failed": required_failed, "warnings": warnings}))
	get_tree().quit(0 if ok else 1)
