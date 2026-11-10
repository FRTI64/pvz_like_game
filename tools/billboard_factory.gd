extends Node
## Offline billboard texture baker.
##
## Renders the ORIGINAL 2D procedural art (scripts/visuals/*_visuals.gd) into a
## transparent SubViewport, samples animation frames, packs each sheet
## horizontally into a PNG strip and writes assets/billboards/manifest.json.
##
## Run (windowed WSLg + llvmpipe):
##   export LD_LIBRARY_PATH="$PWD/.tools/libs/usr/lib"
##   export XKB_CONFIG_ROOT="$PWD/.tools/libs/usr/share/X11/xkb"
##   /usr/lib/godot-mono/godot.linuxbsd.editor.x86_64.mono --path . \
##       res://tools/billboard_factory.tscn \
##       --display-driver wayland --rendering-driver opengl3
##
## The script quits by itself when finished. See docs/3d-render-spec.md §3.

const FRAME_SIZE: int = 256
const CAPTURE_SCALE: float = 2.0
const OUT_DIR := "res://assets/billboards/"
## SubViewport images are vertically flipped in some Godot builds; this build
## was verified to need a flip. Re-check the baked PNGs if art appears upside down.
const FLIP_Y: bool = false

var _viewport: SubViewport
var _container: Node2D


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_setup_viewport()
	await get_tree().process_frame
	var manifest := {
		"capture_scale": CAPTURE_SCALE,
		"frame_w": FRAME_SIZE,
		"frame_h": FRAME_SIZE,
		"sheets": {},
	}
	var jobs: Array = _jobs()
	var baked: int = 0
	for job in jobs:
		var result: Dictionary = await _bake(job)
		if result.is_empty():
			push_error("Billboard factory: failed to bake " + str(job.get("sheet", "?")))
			continue
		var sheet_name: String = str(job["sheet"])
		var strip: Image = result["image"]
		var png_path := ProjectSettings.globalize_path(OUT_DIR + sheet_name + ".png")
		var err := strip.save_png(png_path)
		if err != OK:
			push_error("Billboard factory: cannot save " + png_path)
			continue
		manifest["sheets"][sheet_name] = result["entry"]
		baked += 1
		print("BAKED ", sheet_name, "  frames=", result["entry"]["frames"], "  bbox=", result["entry"]["bbox"])
	await get_tree().process_frame
	var manifest_path := ProjectSettings.globalize_path(OUT_DIR + "manifest.json")
	var file := FileAccess.open(manifest_path, FileAccess.WRITE)
	if file == null:
		push_error("Billboard factory: cannot write manifest " + manifest_path)
		get_tree().quit(1)
		return
	file.store_string(JSON.stringify(manifest, "\t"))
	file.close()
	print("DONE: ", baked, " sheets -> ", ProjectSettings.globalize_path(OUT_DIR))
	get_tree().quit(0)


func _setup_viewport() -> void:
	_viewport = SubViewport.new()
	_viewport.name = "CaptureViewport"
	_viewport.size = Vector2i(FRAME_SIZE, FRAME_SIZE)
	_viewport.transparent_bg = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	_viewport.disable_3d = true
	_viewport.msaa_2d = Viewport.MSAA_DISABLED
	add_child(_viewport)

	_container = Node2D.new()
	_container.name = "Art"
	_container.position = Vector2(FRAME_SIZE, FRAME_SIZE) * 0.5
	_container.scale = Vector2(CAPTURE_SCALE, CAPTURE_SCALE)
	_viewport.add_child(_container)


func _jobs() -> Array:
	var jobs: Array = []
	# --- plants: 6-frame idle sway (fps 4) ---
	var plants: Array = [
		["p_peashooter", "peashooter", {}, 6, 4.0],
		["p_sunflower", "sunflower", {}, 6, 4.0],
		["p_wallnut_0", "wallnut", {"crack_stage": 0}, 6, 4.0],
		["p_wallnut_1", "wallnut", {"crack_stage": 1}, 6, 4.0],
		["p_wallnut_2", "wallnut", {"crack_stage": 2}, 6, 4.0],
		["p_cherry", "cherry_bomb", {}, 6, 4.0],
		["p_snow_pea", "snow_pea", {}, 6, 4.0],
		["p_potato_0", "potato_mine", {"is_armed": false}, 6, 4.0],
		["p_potato_1", "potato_mine", {"is_armed": true}, 6, 4.0],
		["p_repeater", "repeater", {}, 6, 4.0],
		["p_chomper_0", "chomper", {"is_chewing": false}, 6, 4.0],
		["p_chomper_1", "chomper", {"is_chewing": true}, 6, 4.0],
	]
	for p in plants:
		jobs.append({
			"kind": "plant",
			"sheet": p[0],
			"plant_kind": p[1],
			"props": p[2],
			"frames": p[3],
			"fps": p[4],
			"phase_var": "anim_phase",
			"phase_span": TAU,
			"anchor_center": false,
		})
	# --- zombies: 8-frame walk cycle (fps 6.4) ---
	var zombies: Array = [
		["z_normal", "normal"],
		["z_conehead", "conehead"],
		["z_buckethead", "buckethead"],
		["z_flag", "flag"],
	]
	for z in zombies:
		jobs.append({
			"kind": "zombie",
			"sheet": z[0],
			"zombie_type": z[1],
			"props": {},
			"frames": 8,
			"fps": 6.4,
			"phase_var": "walk_cycle",
			"phase_span": TAU,
			"anchor_center": false,
		})
	# --- items: sun rays animate slowly, projectiles/mower are static ---
	jobs.append({
		"kind": "item",
		"sheet": "i_sun",
		"item_kind": "sun",
		"props": {},
		"frames": 8,
		"fps": 8.0,
		# Rays are 12-fold symmetric and rotate 0.4 rad per phase unit:
		# one visual period = TAU / (12 * 0.4) rad of phase.
		"phase_var": "anim_phase",
		"phase_span": TAU / 4.8,
		"anchor_center": true,
	})
	for item in [["i_pea", "pea"], ["i_snow_pea", "snow_pea"], ["i_mower", "lawnmower"]]:
		jobs.append({
			"kind": "item",
			"sheet": item[0],
			"item_kind": item[1],
			"props": {},
			"frames": 1,
			"fps": 1.0,
			"phase_var": "anim_phase",
			"phase_span": 0.0,
			"anchor_center": item[1] == "pea" or item[1] == "snow_pea",
		})
	return jobs


func _make_visual(job: Dictionary) -> Node2D:
	var visual: Node2D = null
	match str(job.get("kind", "")):
		"plant":
			var script: Script = load("res://scripts/visuals/plant_visuals.gd")
			visual = script.new()
			visual.set("plant_kind", str(job.get("plant_kind", "peashooter")))
		"zombie":
			var script: Script = load("res://scripts/visuals/zombie_visuals.gd")
			visual = script.new()
			visual.set("zombie_type", str(job.get("zombie_type", "normal")))
		"item":
			var script: Script = load("res://scripts/visuals/item_visuals.gd")
			visual = script.new()
			visual.set("item_kind", str(job.get("item_kind", "sun")))
	if visual == null:
		push_error("Billboard factory: unknown job kind " + str(job.get("kind", "")))
	return visual


func _bake(job: Dictionary) -> Dictionary:
	for child in _container.get_children():
		child.queue_free()
	await get_tree().process_frame
	var visual: Node2D = _make_visual(job)
	if visual == null:
		return {}
	# Variant props (crack stage / armed / chewing) must be set once the script
	# instance exists; the visuals read them from _draw().
	var props: Dictionary = job.get("props", {})
	for key in props.keys():
		visual.set(str(key), props[key])
	_container.add_child(visual)
	if visual is CanvasItem:
		visual.set_process(false)
	await get_tree().process_frame

	var frames: int = int(job.get("frames", 1))
	var phase_var: String = str(job.get("phase_var", "anim_phase"))
	var span: float = float(job.get("phase_span", TAU))
	var strip := Image.create_empty(FRAME_SIZE * frames, FRAME_SIZE, false, Image.FORMAT_RGBA8)
	var union := Rect2i()
	var has_union: bool = false

	for i in range(frames):
		var t: float = 0.0 if frames <= 1 else (float(i) / float(frames))
		visual.set(phase_var, t * span)
		visual.queue_redraw()
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var image: Image = _viewport.get_texture().get_image()
		if image == null:
			push_error("Billboard factory: no viewport image for " + str(job.get("sheet", "?")))
			continue
		if FLIP_Y:
			image.flip_y()
		image.convert(Image.FORMAT_RGBA8)
		strip.blit_rect(image, Rect2i(0, 0, FRAME_SIZE, FRAME_SIZE), Vector2i(i * FRAME_SIZE, 0))
		var used: Rect2i = image.get_used_rect()
		if used.size.x > 0 and used.size.y > 0:
			if not has_union:
				union = used
				has_union = true
			else:
				union = union.merge(used)

	if not has_union:
		push_error("Billboard factory: empty capture for " + str(job.get("sheet", "?")))
		return {}

	var anchor_y: float = FRAME_SIZE * 0.5
	if not bool(job.get("anchor_center", false)):
		anchor_y = float(union.position.y + union.size.y)
	var entry := {
		"file": str(job["sheet"]) + ".png",
		"frames": frames,
		"fps": float(job.get("fps", 1.0)),
		"anchor": [FRAME_SIZE * 0.5, anchor_y],
		"bbox": [union.position.x, union.position.y, union.position.x + union.size.x, union.position.y + union.size.y],
	}
	return {"entry": entry, "image": strip}
