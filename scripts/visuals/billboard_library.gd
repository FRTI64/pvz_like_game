class_name BillboardLibrary
extends RefCounted
## Loads the baked billboard sprite sheets (assets/billboards/) and builds
## Billboard2D nodes / blob shadows from them.
##
## The sheets are generated offline by tools/billboard_factory.tscn from the
## original 2D procedural art in scripts/visuals/*_visuals.gd.
## See docs/3d-render-spec.md §3 for the manifest contract.

const ASSET_DIR := "res://assets/billboards/"
const MANIFEST_PATH := "res://assets/billboards/manifest.json"

const PLANT_SHEETS := {
	"peashooter": "p_peashooter",
	"sunflower": "p_sunflower",
	"wallnut": "p_wallnut_0",
	"cherry_bomb": "p_cherry",
	"snow_pea": "p_snow_pea",
	"potato_mine": "p_potato_0",
	"repeater": "p_repeater",
	"chomper": "p_chomper_0",
}

const ZOMBIE_SHEETS := {
	"normal_zombie": "z_normal",
	"conehead_zombie": "z_conehead",
	"buckethead_zombie": "z_buckethead",
	"flag_zombie": "z_flag",
}

static var _manifest: Dictionary = {}
static var _textures: Dictionary = {}
static var _shadow_texture: Texture2D = null


# --- Manifest / textures -------------------------------------------------

static func manifest() -> Dictionary:
	if _manifest.is_empty():
		if not FileAccess.file_exists(MANIFEST_PATH):
			push_error("BillboardLibrary: missing manifest at " + MANIFEST_PATH)
			return {"capture_scale": 2.0, "frame_w": 256, "frame_h": 256, "sheets": {}}
		var file := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
		if file == null:
			push_error("BillboardLibrary: cannot open manifest " + MANIFEST_PATH)
			return {"sheets": {}}
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		if parsed is Dictionary:
			_manifest = parsed
		else:
			push_error("BillboardLibrary: manifest is not valid JSON")
	return _manifest


static func sheet(sheet_name: String) -> Dictionary:
	var m: Dictionary = manifest()
	var sheets: Dictionary = m.get("sheets", {})
	return sheets.get(sheet_name, {})


static func has_sheet(sheet_name: String) -> bool:
	return not sheet(sheet_name).is_empty()


static func texture(sheet_name: String) -> Texture2D:
	if _textures.has(sheet_name):
		return _textures[sheet_name] as Texture2D
	var data: Dictionary = sheet(sheet_name)
	var file_name: String = str(data.get("file", ""))
	if file_name.is_empty():
		push_error("BillboardLibrary: unknown sheet '" + sheet_name + "'")
		return null
	var path: String = ASSET_DIR + file_name
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	if tex == null:
		push_error("BillboardLibrary: could not load billboard texture " + path)
		return null
	_textures[sheet_name] = tex
	return tex


# --- Mapping helpers -----------------------------------------------------

static func sheet_for_plant(id: String) -> String:
	return str(PLANT_SHEETS.get(id, "p_peashooter"))


static func sheet_for_zombie(id: String) -> String:
	return str(ZOMBIE_SHEETS.get(id, "z_normal"))


# --- Builders ------------------------------------------------------------

## Create a camera-facing billboard anchored at the node origin.
static func make_billboard(sheet_name: String) -> Billboard2D:
	var billboard := Billboard2D.new()
	apply_sheet(billboard, sheet_name)
	return billboard


## Semi-transparent billboard used for the placement ghost preview.
static func make_ghost(sheet_name: String) -> Billboard2D:
	var billboard := make_billboard(sheet_name)
	billboard.set_alpha(0.55)
	billboard.animate_frames = true
	billboard.sprite.render_priority = 4
	return billboard


## Apply a sheet to an existing Billboard2D (also used for state changes, e.g.
## wallnut cracks, potato armed, chomper chewing, zombie armor break).
static func apply_sheet(billboard: Billboard2D, sheet_name: String) -> void:
	var data: Dictionary = sheet(sheet_name)
	if data.is_empty():
		push_error("BillboardLibrary: cannot apply unknown sheet '" + sheet_name + "'")
		return
	var tex: Texture2D = texture(sheet_name)
	if tex == null:
		return
	billboard.sheet_name = sheet_name
	billboard.frame_count = maxi(1, int(data.get("frames", 1)))
	billboard.fps = float(data.get("fps", 6.0))
	billboard._anim_t = randf() * 10.0
	var sprite: Sprite3D = billboard.sprite
	sprite.texture = tex
	sprite.hframes = billboard.frame_count
	sprite.vframes = 1
	sprite.frame = 0
	sprite.pixel_size = Billboard2D.PIXEL_SIZE
	var anchor: Array = data.get("anchor", [Billboard2D.FRAME_W * 0.5, Billboard2D.FRAME_H])
	var ax: float = float(anchor[0])
	var ay: float = float(anchor[1])
	sprite.position = Vector3(
		(Billboard2D.FRAME_W * 0.5 - ax) * Billboard2D.PIXEL_SIZE,
		(ay - Billboard2D.FRAME_H * 0.5) * Billboard2D.PIXEL_SIZE,
		0.0
	)


## Soft round blob shadow (flat quad on the ground), sized from the sheet bbox.
static func make_shadow_for(sheet_name: String) -> MeshInstance3D:
	var data: Dictionary = sheet(sheet_name)
	var bbox: Array = data.get("bbox", [0, 0, 256, 256])
	var capture_scale: float = Billboard2D.CAPTURE_SCALE
	var width_px: float = (float(bbox[2]) - float(bbox[0])) / capture_scale
	var w: float = clampf(width_px * 0.95, 18.0, 120.0)
	return make_shadow(Vector2(w, w * 0.52))


## Soft round blob shadow with explicit size in game px.
static func make_shadow(size_px: Vector2) -> MeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = size_px
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_texture = shadow_texture()
	material.albedo_color = Color(0.0, 0.0, 0.0, 1.0)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.no_depth_test = false
	quad.material = material
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "BlobShadow"
	mesh_instance.mesh = quad
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh_instance.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
	mesh_instance.position = Vector3(0.0, 0.8, 0.0)
	return mesh_instance


## Soft radial gradient used by the blob shadows (generated once).
static func shadow_texture() -> Texture2D:
	if _shadow_texture != null:
		return _shadow_texture
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	gradient.colors = PackedColorArray([
		Color(0.0, 0.0, 0.0, 0.42),
		Color(0.0, 0.0, 0.0, 0.28),
		Color(0.0, 0.0, 0.0, 0.0),
	])
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.width = 64
	tex.height = 64
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	_shadow_texture = tex
	return _shadow_texture
