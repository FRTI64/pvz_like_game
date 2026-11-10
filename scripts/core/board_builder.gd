class_name BoardBuilder
extends RefCounted
## Builds the whole 3D "diorama" board seen behind the gameplay from 3D
## primitives (see docs/3d-render-spec.md §2.3).
##
## Everything here lives under `WorldRoot` and therefore uses LOCAL GAME PIXEL
## coordinates:  local position = Vector3(game_x, height_px, game_y).
## Ground convention (Lead-locked): every walkable surface top is local y = 0;
## slabs extend downward (negative y).  Props may rise above y = 0.
##
## Camera: fixed at WorldSpace.default_camera_position() (D=23, elev 58, fov 40).
## Reference framing (validated): lawn far edge ~22.9% screen height, near edge
## ~80%, bottom of frame = game y ~800.
##
## Diorama concept: the base ground ends at BACK_EDGE_Y (game y = -60 / local
## z = -60); above that edge line the screen shows the environment BG color
## (sky).  Directly in front of it a wooden fence + hedge + trees form the
## background band that the player sees above the lawn.  Nothing below y = 0 is
## coplanar with a walkable top (no z-fighting).

# --- Lawn grid (must match GridManager) ----------------------------------
const GRID_ORIGIN := Vector2(275.0, 125.0)
const CELL := Vector2(98.0, 108.0)
const ROWS := 5
const COLS := 9
const LAWN_X0 := 275.0
const LAWN_Y0 := 125.0
const LAWN_X1 := 1157.0  # LAWN_X0 + COLS * CELL.x
const LAWN_Y1 := 665.0   # LAWN_Y0 + ROWS * CELL.y

# --- Board extents (local game px) ---------------------------------------
const BACK_EDGE_Y := -60.0    # far edge of the base ground / diorama backdrop
const FRONT_EDGE_Y := 900.0   # near edge (off the bottom of the frame)
const BASE_X0 := -700.0
const BASE_X1 := 2300.0

# --- Palette -------------------------------------------------------------
const C_SOIL := Color("#46603a")
const C_SOIL_DARK := Color("#3a5030")
const C_GRASS_A := Color("#58a94c")
const C_GRASS_B := Color("#47903e")
const C_SEAM := Color("#2f6b2c")
const C_WOOD := Color("#6b4a2e")
const C_WOOD_LIGHT := Color("#7d5836")
const C_WOOD_DARK := Color("#513522")
const C_PATIO := Color("#6f4e35")
const C_PATIO_ALT := Color("#7a583c")
const C_PATIO_SEAM := Color("#4c3423")
const C_WALL := Color("#cba87a")
const C_WALL_SHADE := Color("#b08d61")
const C_ROOF := Color("#7c3b2c")
const C_ROOF_DARK := Color("#683027")
const C_DOOR := Color("#5a3a26")
const C_WINDOW := Color("#9fd4e8")
const C_WINDOW_FRAME := Color("#e8dfc8")
const C_SIDEWALK := Color("#8c8778")
const C_SIDEWALK_JOINT := Color("#736e60")
const C_CURB := Color("#847f70")
const C_STREET := Color("#4f5359")
const C_STREET_LINE := Color("#c9c4b4")
const C_HEDGE := Color("#3f7a35")
const C_HEDGE_LIGHT := Color("#4c8c3e")
const C_HEDGE_DARK := Color("#356b2d")
const C_TRUNK := Color("#6b4a2e")
const C_LEAF_A := Color("#4e8a3f")
const C_LEAF_B := Color("#5fa04a")
const C_LEAF_C := Color("#427a36")
const C_LEAF_BG := Color("#3e6e37")
const C_SHUTTER := Color("#4f6b3c")
const C_TRIM := Color("#e6dcc4")
const C_FENCE_POST := Color("#5d4028")
const C_STONE := Color("#827d6f")
const C_STONE_LIGHT := Color("#989182")
const C_FRONT_GRASS := Color("#4f8f44")
const C_FLOWER_RED := Color("#e4574a")
const C_FLOWER_YELLOW := Color("#f2c94c")
const C_FLOWER_PINK := Color("#e88bc4")
const C_FLOWER_WHITE := Color("#f5f0e2")

var root: Node3D
var _mats: Dictionary = {}


# === Public entry point ==================================================

func build(target: Node3D) -> void:
	root = target
	_build_ground()
	_build_lawn()
	_build_patio()
	_build_house()
	_build_right_side()
	_build_backyard()
	_build_trees()
	_build_foreground()


# === Infrastructure ======================================================

func _mat(color: Color, opts: Dictionary = {}) -> StandardMaterial3D:
	var key := "%s|%s" % [color.to_html(), str(opts)]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = float(opts.get("roughness", 0.95))
	m.metallic = float(opts.get("metallic", 0.0))
	m.metallic_specular = float(opts.get("specular", 0.12))
	if bool(opts.get("unshaded", false)):
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if bool(opts.get("no_shadow", false)):
		m.disable_receive_shadows = true
	_mats[key] = m
	return m


func _group(name: String) -> Node3D:
	var n := Node3D.new()
	n.name = name
	root.add_child(n)
	return n


func _mesh_node(parent: Node3D, name: String, mesh: Mesh, pos: Vector3,
		color: Color, cast_shadow: bool = true, opts: Dictionary = {}) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = mesh
	mi.material_override = _mat(color, opts)
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadow \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


## Axis-aligned box whose CENTER is game px (x, height, z = game_y).
func _box(parent: Node3D, name: String, center: Vector3, size: Vector3,
		color: Color, cast_shadow: bool = true, opts: Dictionary = {}) -> MeshInstance3D:
	var box := BoxMesh.new()
	box.size = size
	return _mesh_node(parent, name, box, center, color, cast_shadow, opts)


## Box given by its footprint rect in game px and its vertical range (px).
func _slab(parent: Node3D, name: String, rect: Rect2, top: float, bottom: float,
		color: Color, cast_shadow: bool = false, opts: Dictionary = {}) -> MeshInstance3D:
	var size := Vector3(rect.size.x, top - bottom, rect.size.y)
	var center := Vector3(rect.position.x + rect.size.x * 0.5,
			(top + bottom) * 0.5, rect.position.y + rect.size.y * 0.5)
	return _box(parent, name, center, size, color, cast_shadow, opts)


func _sphere(parent: Node3D, name: String, center: Vector3, radius: float,
		color: Color, squash: Vector3 = Vector3.ONE, cast_shadow: bool = true,
		opts: Dictionary = {}, segments: int = 12, rings: int = 7) -> MeshInstance3D:
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	sm.radial_segments = segments
	sm.rings = rings
	var mi := _mesh_node(parent, name, sm, center, color, cast_shadow, opts)
	mi.scale = squash
	return mi


func _cone(parent: Node3D, name: String, center: Vector3, bottom_r: float,
		height: float, color: Color, cast_shadow: bool = true,
		opts: Dictionary = {}, segments: int = 9) -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0
	cm.bottom_radius = bottom_r
	cm.height = height
	cm.radial_segments = segments
	cm.rings = 1
	return _mesh_node(parent, name, cm, center, color, cast_shadow, opts)


func _cylinder(parent: Node3D, name: String, center: Vector3, top_r: float,
		bottom_r: float, height: float, color: Color, cast_shadow: bool = true,
		opts: Dictionary = {}, segments: int = 8) -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.top_radius = top_r
	cm.bottom_radius = bottom_r
	cm.height = height
	cm.radial_segments = segments
	cm.rings = 1
	return _mesh_node(parent, name, cm, center, color, cast_shadow, opts)


## Soft fake contact shadow (blob quad on the ground).  Directional shadow maps
## do not render in the gl_compatibility + llvmpipe screenshot environment, so
## 3D props are grounded with these cheap unshaded quads instead.
func _contact_shadow(parent: Node3D, name: String, ground_center: Vector3,
		size_px: Vector2, alpha: float = 1.0, lift: float = 0.35) -> MeshInstance3D:
	var shadow: MeshInstance3D = BillboardLibrary.make_shadow(size_px)
	if shadow == null:
		return null
	shadow.name = name
	# BillboardLibrary.make_shadow puts the quad 0.8px above its node origin.
	shadow.position = Vector3(ground_center.x,
			ground_center.y + lift - 0.8, ground_center.z)
	if alpha < 1.0:
		var quad := shadow.mesh as QuadMesh
		if quad != null:
			var base_mat := quad.material as StandardMaterial3D
			if base_mat != null:
				var mat := base_mat.duplicate() as StandardMaterial3D
				mat.albedo_color = Color(0.0, 0.0, 0.0, alpha)
				quad.material = mat
	parent.add_child(shadow)
	return shadow


# === Ground / base =======================================================

func _build_ground() -> void:
	var g := _group("Ground")
	# Large base ground: dark grass/soil.  Top is at y = -2, strictly below the
	# walkable surfaces (top y = 0) so there is never coplanar z-fighting.
	_slab(g, "BaseGround",
			Rect2(BASE_X0, BACK_EDGE_Y, BASE_X1 - BASE_X0, FRONT_EDGE_Y - BACK_EDGE_Y),
			-2.0, -80.0, C_SOIL)
	# Darker soil strip between the back fence and the lawn border (slightly
	# beyond the lawn width) so the lawn platform reads as a raised lawn.
	_slab(g, "BackMargin",
			Rect2(LAWN_X0 - 46.0, BACK_EDGE_Y + 2.0,
					(LAWN_X1 - LAWN_X0) + 92.0, LAWN_Y0 - BACK_EDGE_Y - 2.0),
			-1.7, -14.0, C_SOIL_DARK)
	# A few flat soil/gravel patches for texture variation on the margins.
	var rng := RandomNumberGenerator.new()
	rng.seed = 20240321
	for i in 8:
		var x := rng.randf_range(LAWN_X0 - 40.0, LAWN_X1 + 30.0)
		var z := rng.randf_range(BACK_EDGE_Y + 6.0, LAWN_Y0 - 14.0)
		var w := rng.randf_range(38.0, 120.0)
		var d := rng.randf_range(6.0, 13.0)
		_slab(g, "BackPatch%d" % i, Rect2(x, z, w, d), -1.6, -2.0, C_SEAM)
	for i in 10:
		var x := rng.randf_range(BASE_X0 + 60.0, LAWN_X0 - 80.0)
		var z := rng.randf_range(BACK_EDGE_Y + 40.0, 760.0)
		var w := rng.randf_range(24.0, 60.0)
		var d := rng.randf_range(8.0, 22.0)
		_slab(g, "SidePatch%d" % i, Rect2(x, z, w, d), -1.6, -2.0, C_SOIL)


# === Lawn ================================================================

func _build_lawn() -> void:
	var lawn := _group("Lawn")

	# Dark green platform under the checker tiles; the recessed gaps between the
	# tiles read as the thin grid seams (#2f6b2c per spec).
	var plat_rect := Rect2(LAWN_X0 - 8.0, LAWN_Y0 - 8.0,
			(LAWN_X1 - LAWN_X0) + 16.0, (LAWN_Y1 - LAWN_Y0) + 16.0)
	_slab(lawn, "LawnPlatform", plat_rect, -1.0, -18.0, C_SEAM)

	# 5 x 9 raised checker tiles: TOP = local y 0 (the walkable surface).
	var inset := 1.6
	for row in ROWS:
		for col in COLS:
			var rect := Rect2(
					LAWN_X0 + col * CELL.x + inset,
					LAWN_Y0 + row * CELL.y + inset,
					CELL.x - inset * 2.0,
					CELL.y - inset * 2.0)
			var color: Color = C_GRASS_A if (row + col) % 2 == 0 else C_GRASS_B
			_slab(lawn, "Tile_%d_%d" % [row, col], rect, 0.0, -1.0, color)

	# Wooden border frame around the lawn (top 10 px above the tiles -> strong 3D
	# depth cue, spec §2.3).  Four non-overlapping beams.
	var bw := 13.0
	var border_top := 10.0
	var border_bottom := -24.0
	var outer := Rect2(LAWN_X0 - 22.0, LAWN_Y0 - 22.0,
			(LAWN_X1 - LAWN_X0) + 44.0, (LAWN_Y1 - LAWN_Y0) + 44.0)
	var inner := Rect2(outer.position.x + bw, outer.position.y + bw,
			outer.size.x - bw * 2.0, outer.size.y - bw * 2.0)
	_slab(lawn, "BorderBack", Rect2(outer.position.x, outer.position.y, outer.size.x, bw),
			border_top, border_bottom, C_WOOD_LIGHT, true)
	_slab(lawn, "BorderFront", Rect2(outer.position.x, inner.position.y + inner.size.y,
			outer.size.x, bw), border_top, border_bottom, C_WOOD_LIGHT, true)
	_slab(lawn, "BorderLeft", Rect2(outer.position.x, inner.position.y, bw, inner.size.y),
			border_top, border_bottom, C_WOOD, true)
	_slab(lawn, "BorderRight", Rect2(inner.position.x + inner.size.x, inner.position.y,
			bw, inner.size.y), border_top, border_bottom, C_WOOD, true)
	# Sunlit rim strips along the back and left top edges of the frame.
	_slab(lawn, "BorderBackRim",
			Rect2(outer.position.x, outer.position.y - 1.0, outer.size.x, 3.0),
			border_top + 0.6, border_top, C_WOOD_LIGHT)
	_slab(lawn, "BorderLeftRim",
			Rect2(outer.position.x - 1.0, inner.position.y, 3.0, inner.size.y),
			border_top + 0.6, border_top, C_WOOD_LIGHT)
	# Soft AO from the raised frame onto the lawn (sun comes from the +X/+Z side,
	# so the near and right edges read darker).
	_contact_shadow(lawn, "BorderShadowRight",
			Vector3(LAWN_X1 - 16.0, 0.0, (LAWN_Y0 + LAWN_Y1) * 0.5),
			Vector2(80.0, LAWN_Y1 - LAWN_Y0), 0.5, 0.45)
	_contact_shadow(lawn, "BorderShadowNear",
			Vector3((LAWN_X0 + LAWN_X1) * 0.5, 0.0, LAWN_Y1 - 14.0),
			Vector2(LAWN_X1 - LAWN_X0, 70.0), 0.45, 0.45)


# === Patio (left strip) ==================================================

func _build_patio() -> void:
	var patio := _group("Patio")
	# The patio runs under the house as well; only x in [88, 257] is visible.
	var rect := Rect2(-360.0, BACK_EDGE_Y, 257.0 + 360.0, FRONT_EDGE_Y - BACK_EDGE_Y)
	_slab(patio, "PatioBase", rect, -1.4, -24.0, C_PATIO_SEAM)
	# Warm planks running along X (screen horizontal), darker seam gaps between.
	var z := BACK_EDGE_Y + 2.0
	var idx := 0
	while z < FRONT_EDGE_Y:
		var depth := 46.0
		if z + depth > FRONT_EDGE_Y:
			depth = FRONT_EDGE_Y - z
		var color: Color = C_PATIO if idx % 2 == 0 else C_PATIO_ALT
		_slab(patio, "Plank%d" % idx, Rect2(-360.0, z, 257.0 + 360.0, depth),
				0.0, -1.4, color)
		z += depth + 3.0
		idx += 1
	# Edge beam where the patio meets the lawn border.
	_slab(patio, "PatioEdge", Rect2(250.0, BACK_EDGE_Y, 7.0, FRONT_EDGE_Y - BACK_EDGE_Y),
			1.5, -24.0, C_WOOD_DARK)
	# A couple of potted plants on the patio for charm.
	_build_pot(patio, Vector3(150.0, 0.0, 300.0), 1.0)
	_build_pot(patio, Vector3(196.0, 0.0, 470.0), 0.85)


func _build_pot(parent: Node3D, base: Vector3, s: float) -> void:
	_cylinder(parent, "Pot", base + Vector3(0.0, 17.0 * s, 0.0), 15.0 * s, 11.0 * s,
			34.0 * s, Color("#b5623e"), true, {}, 10)
	_sphere(parent, "PotBush", base + Vector3(0.0, 48.0 * s, 0.0), 20.0 * s,
			C_HEDGE_LIGHT, Vector3(1.0, 0.85, 1.0), true, {}, 9, 5)
	_sphere(parent, "PotFlowerA", base + Vector3(10.0 * s, 58.0 * s, 6.0 * s), 5.5 * s,
			C_FLOWER_YELLOW, Vector3.ONE, false, {}, 8, 5)
	_sphere(parent, "PotFlowerB", base + Vector3(-8.0 * s, 62.0 * s, -5.0 * s), 5.0 * s,
			C_FLOWER_RED, Vector3.ONE, false, {}, 8, 5)


# === House facade (left) =================================================

func _build_house() -> void:
	var house := _group("House")
	var wall_x := 72.0         # the visible (+X facing) wall face
	var wall_left := -520.0
	var wall_z0 := BACK_EDGE_Y
	var wall_z1 := FRONT_EDGE_Y + 140.0
	var wall_h := 310.0

	# Main wall slab.
	_box(house, "Wall", Vector3((wall_left + wall_x) * 0.5, wall_h * 0.5,
			(wall_z0 + wall_z1) * 0.5),
			Vector3(wall_x - wall_left, wall_h, wall_z1 - wall_z0), C_WALL, true)
	# Wainscot / foundation strip at the bottom of the wall.
	_slab(house, "Foundation", Rect2(wall_left, wall_z0, wall_x - wall_left, wall_z1 - wall_z0),
			30.0, -2.0, C_WALL_SHADE, true)
	# Subtle vertical shading panels on the big wall.
	for i in 6:
		var z := wall_z0 + 60.0 + i * 170.0
		_slab(house, "WallPanel%d" % i, Rect2(wall_x - 1.0, z, 1.2, 110.0),
				wall_h - 20.0, 34.0, C_WALL_SHADE)
	# Horizontal siding grooves make the big wall read as timber cladding
	# instead of a flat plane (visible at this oblique camera angle).
	var siding_y := 26.0
	var s_idx := 0
	while siding_y < wall_h - 12.0:
		if absf(siding_y - 138.0) > 10.0:  # keep the trim band clear
			_box(house, "Siding%d" % s_idx, Vector3(wall_x + 0.4, siding_y, (wall_z0 + wall_z1) * 0.5),
					Vector3(1.4, 2.6, wall_z1 - wall_z0), C_WALL_SHADE, false)
		siding_y += 30.0
		s_idx += 1
	# Cream trim band + vertical corner boards articulate the big wall.
	_box(house, "TrimBand", Vector3(wall_x + 0.9, 138.0, (wall_z0 + wall_z1) * 0.5),
			Vector3(3.6, 13.0, wall_z1 - wall_z0), C_TRIM, true)
	for i in 6:
		var tz := wall_z0 + 40.0 + i * 172.0
		_box(house, "TrimBoard%d" % i, Vector3(wall_x + 0.9, wall_h * 0.5, tz),
				Vector3(3.0, wall_h, 9.0), C_TRIM, true)

	# Windows: frame + glass, slightly proud of the wall so they read from the
	# camera (the camera is to the right of the wall, seeing its +X face).
	var window_zs := [150.0, 390.0, 640.0, 860.0]
	for i in window_zs.size():
		var z: float = window_zs[i]
		var win_h := 96.0
		var win_w := 74.0
		var cy := 180.0
		_box(house, "WinFrame%d" % i, Vector3(wall_x + 2.0, cy, z),
				Vector3(4.0, win_h + 10.0, win_w + 10.0), C_WINDOW_FRAME, true)
		_box(house, "WinGlass%d" % i, Vector3(wall_x + 4.2, cy, z),
				Vector3(2.0, win_h, win_w), C_WINDOW, false,
				{"roughness": 0.25, "metallic": 0.15, "specular": 0.5})
		_box(house, "WinSill%d" % i, Vector3(wall_x + 4.0, cy - win_h * 0.5 - 8.0, z),
				Vector3(7.0, 6.0, win_w + 14.0), C_WINDOW_FRAME, true)
		_box(house, "WinBarV%d" % i, Vector3(wall_x + 5.4, cy, z),
				Vector3(1.2, win_h, 4.0), C_WINDOW_FRAME, false)
		_box(house, "WinBarH%d" % i, Vector3(wall_x + 5.4, cy, z),
				Vector3(1.2, 4.0, win_w), C_WINDOW_FRAME, false)
		# Painted shutters on both sides of every window.
		_box(house, "ShutterA%d" % i, Vector3(wall_x + 3.4, cy, z - win_w * 0.5 - 11.0),
				Vector3(2.8, win_h + 8.0, 16.0), C_SHUTTER, true)
		_box(house, "ShutterB%d" % i, Vector3(wall_x + 3.4, cy, z + win_w * 0.5 + 11.0),
				Vector3(2.8, win_h + 8.0, 16.0), C_SHUTTER, true)
		# Window flower box under the two middle windows.
		if i == 1 or i == 2:
			_box(house, "FlowerBox%d" % i, Vector3(wall_x + 9.0, cy - win_h * 0.5 - 20.0, z),
					Vector3(14.0, 16.0, win_w + 16.0), C_WOOD, true)
			for f in 4:
				_sphere(house, "BoxFlower%d_%d" % [i, f], Vector3(wall_x + 13.0,
						cy - win_h * 0.5 - 10.0, z - 30.0 + f * 20.0), 7.0,
						C_FLOWER_RED if f % 2 == 0 else C_FLOWER_YELLOW, Vector3.ONE, false)

	# Door with a frame and a little stone step.
	var door_z := 780.0
	_box(house, "DoorFrame", Vector3(wall_x + 2.0, 82.0, door_z),
			Vector3(5.0, 164.0, 96.0), C_WOOD_LIGHT, true)
	_box(house, "Door", Vector3(wall_x + 4.6, 78.0, door_z),
			Vector3(2.4, 156.0, 84.0), C_DOOR, false)
	_sphere(house, "DoorKnob", Vector3(wall_x + 6.6, 78.0, door_z + 30.0), 3.6,
			Color("#e8c76a"), Vector3.ONE, false)
	_box(house, "DoorStep", Vector3(wall_x + 14.0, 5.0, door_z),
			Vector3(28.0, 10.0, 120.0), C_STONE, true)
	# Porch light above the door (unshaded -> glows a little).
	_box(house, "PorchLight", Vector3(wall_x + 6.0, 180.0, door_z),
			Vector3(8.0, 16.0, 10.0), Color("#ffe27a"), false, {"unshaded": true})
	# Fake AO contact shadow along the base of the wall on the patio.
	_contact_shadow(house, "WallShadow",
			Vector3(wall_x + 46.0, 0.0, (wall_z0 + wall_z1) * 0.5),
			Vector2(150.0, 1500.0), 0.8)

	# Eave overhang + gable roof.  The camera looks down at ~58 deg, so the roof
	# slope facing the lawn is visible: it is the main warm accent on the left.
	_box(house, "Eave", Vector3(-60.0, wall_h + 7.0, (wall_z0 + wall_z1) * 0.5),
			Vector3(320.0, 14.0, wall_z1 - wall_z0 + 6.0), C_WOOD_LIGHT, true)
	# Fake AO shadow line on the wall just under the eave.
	_box(house, "EaveShadow", Vector3(wall_x + 0.6, wall_h - 9.0, (wall_z0 + wall_z1) * 0.5),
			Vector3(1.4, 18.0, wall_z1 - wall_z0), Color("#8f6f4a"), false)
	# Two sloped roof panels (boxes rotated about Z) forming a ridge along Z.
	# The panels are split into shingle bands (alternating tones) so the large
	# roof surface the camera sees is not one flat orange slab.
	var ridge_y := wall_h + 140.0
	var half_span := 205.0
	var rise := 140.0
	var panel_len := sqrt(half_span * half_span + rise * rise)
	var angle := atan2(rise, half_span)
	for side in [-1, 1]:
		var band_z := wall_z0 - 20.0
		var band := 0
		while band_z < wall_z1 + 20.0:
			var depth := minf(78.0, wall_z1 + 20.0 - band_z)
			var tone: Color = C_ROOF if (band + (0 if side > 0 else 1)) % 2 == 0 else C_ROOF_DARK
			var panel := _box(house, "RoofPanel%s_%d" % [side, band],
					Vector3(-60.0 + side * half_span * 0.5,
							(wall_h + 7.0 + ridge_y) * 0.5, band_z + depth * 0.5),
					Vector3(panel_len, 10.0, depth - 2.0), tone, true)
			panel.rotation.z = -side * angle
			band_z += depth
			band += 1
	# Ridge cap.
	_box(house, "RoofRidge", Vector3(-60.0, ridge_y, (wall_z0 + wall_z1) * 0.5),
			Vector3(16.0, 10.0, wall_z1 - wall_z0 + 50.0), C_ROOF_DARK, true)
	# Chimney.
	_box(house, "Chimney", Vector3(-170.0, ridge_y + 60.0, 300.0),
			Vector3(52.0, 110.0, 52.0), Color("#a26a58"), true)
	_box(house, "ChimneyCap", Vector3(-170.0, ridge_y + 118.0, 300.0),
			Vector3(62.0, 10.0, 62.0), Color("#8a5647"), true)


# === Right side: sidewalk / curb / street ================================

func _build_right_side() -> void:
	var rs := _group("RightSide")
	var sx0 := LAWN_X1 + 42.0      # 1199
	var sx1 := 1310.0
	var street_x1 := 2260.0

	# Grass verge between the lawn frame and the sidewalk.
	_slab(rs, "Verge", Rect2(LAWN_X1 + 18.0, BACK_EDGE_Y, 24.0, FRONT_EDGE_Y - BACK_EDGE_Y),
			-0.8, -16.0, C_FRONT_GRASS, false)
	# Sidewalk slab with expansion joints.
	_slab(rs, "Sidewalk", Rect2(sx0, BACK_EDGE_Y, sx1 - sx0, FRONT_EDGE_Y - BACK_EDGE_Y),
			0.0, -16.0, C_SIDEWALK, false)
	var z := BACK_EDGE_Y + 8.0
	var ji := 0
	while z < FRONT_EDGE_Y:
		_slab(rs, "Joint%d" % ji, Rect2(sx0 + 4.0, z, sx1 - sx0 - 8.0, 2.4),
				0.35, 0.0, C_SIDEWALK_JOINT)
		z += 62.0
		ji += 1
	# Curb between sidewalk and street.
	_slab(rs, "Curb", Rect2(sx1, BACK_EDGE_Y, 15.0, FRONT_EDGE_Y - BACK_EDGE_Y),
			9.0, -22.0, C_CURB, true)
	_slab(rs, "CurbTop", Rect2(sx1 - 1.0, BACK_EDGE_Y, 17.0, FRONT_EDGE_Y - BACK_EDGE_Y),
			9.6, 8.6, C_STONE_LIGHT)
	# Street.
	_slab(rs, "Street", Rect2(sx1 + 15.0, BACK_EDGE_Y, street_x1 - sx1 - 15.0,
			FRONT_EDGE_Y - BACK_EDGE_Y), -0.4, -24.0, C_STREET, false)
	# Dashed centre line down the street.
	var lz := BACK_EDGE_Y + 30.0
	var li := 0
	while lz < FRONT_EDGE_Y:
		_slab(rs, "LaneDash%d" % li, Rect2(1640.0, lz, 8.0, 52.0), 0.2, -0.4, C_STREET_LINE)
		lz += 118.0
		li += 1
	# Street props on the sidewalk.
	_build_mailbox(rs, Vector3(1226.0, 0.0, 520.0))
	_build_hydrant(rs, Vector3(1250.0, 0.0, 330.0))


func _build_mailbox(parent: Node3D, base: Vector3) -> void:
	_cylinder(parent, "MailPost", base + Vector3(0.0, 40.0, 0.0), 4.0, 5.0, 80.0,
			C_WOOD, true, {}, 6)
	_box(parent, "MailBox", base + Vector3(0.0, 88.0, 0.0),
			Vector3(30.0, 20.0, 42.0), Color("#b8452f"), true)
	_box(parent, "MailFlag", base + Vector3(19.0, 96.0, 0.0),
			Vector3(3.0, 18.0, 3.0), C_FLOWER_YELLOW, false)
	_box(parent, "MailFlagTop", base + Vector3(15.0, 104.0, 0.0),
			Vector3(12.0, 3.0, 3.0), C_FLOWER_YELLOW, false)


func _build_hydrant(parent: Node3D, base: Vector3) -> void:
	_cylinder(parent, "HydrantBody", base + Vector3(0.0, 18.0, 0.0), 8.0, 9.0, 36.0,
			Color("#c8452f"), true, {}, 10)
	_sphere(parent, "HydrantTop", base + Vector3(0.0, 38.0, 0.0), 8.0,
			Color("#b03d29"), Vector3.ONE, true, {}, 8, 5)
	_box(parent, "HydrantCap", base + Vector3(0.0, 26.0, 0.0),
			Vector3(20.0, 5.0, 5.0), Color("#d4d0c4"), false)


# === Backyard: fence / hedge along the far edge ==========================

func _build_backyard() -> void:
	var by := _group("Backyard")
	var fence_z := 58.0
	var fx0 := 96.0
	var fx1 := 2260.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 7712

	# Trimmed hedge behind the fence: a solid green backdrop seen between the
	# pickets (cleaner than a row of balls).
	_slab(by, "HedgeBody", Rect2(fx0 - 50.0, 20.0, (fx1 - fx0) + 100.0, 34.0),
			54.0, -2.0, C_HEDGE_DARK, true)
	_slab(by, "HedgeTop", Rect2(fx0 - 50.0, 16.0, (fx1 - fx0) + 100.0, 42.0),
			62.0, 52.0, C_HEDGE, true)
	# Slightly bumpy top edge (small blobs), kept below the fence tops.
	var hx := fx0 - 40.0
	var hi := 0
	while hx < fx1 + 40.0:
		_sphere(by, "HedgeBump%d" % hi, Vector3(hx, 62.0, 34.0),
				15.0 + rng.randf_range(-2.0, 3.0), C_HEDGE_LIGHT,
				Vector3(1.3, 0.6, 1.0), true, {}, 8, 5)
		hx += 32.0
		hi += 1

	# Horizontal rails.
	_slab(by, "FenceRailLow", Rect2(fx0, fence_z - 2.0, fx1 - fx0, 5.0), 30.0, 22.0, C_FENCE_POST, true)
	_slab(by, "FenceRailHigh", Rect2(fx0, fence_z - 2.0, fx1 - fx0, 5.0), 62.0, 54.0, C_FENCE_POST, true)
	# Pickets.
	var x := fx0
	var pi := 0
	while x < fx1:
		var h := 70.0 + rng.randf_range(-2.5, 3.0)
		var color: Color = C_WOOD_LIGHT if pi % 3 == 0 else C_WOOD
		_box(by, "Picket%d" % pi, Vector3(x + 8.0, h * 0.5, fence_z),
				Vector3(14.0, h, 4.0), color, true)
		_cone(by, "PicketCap%d" % pi, Vector3(x + 8.0, h + 3.0, fence_z),
				9.5, 6.0, color, true, {}, 4)
		x += 28.0
		pi += 1
	# Posts, slightly taller than the pickets.
	var px := fx0
	var post_i := 0
	while px <= fx1:
		_box(by, "Post%d" % post_i, Vector3(px, 46.0, fence_z),
				Vector3(15.0, 92.0, 15.0), C_FENCE_POST, true)
		_box(by, "PostCap%d" % post_i, Vector3(px, 96.0, fence_z),
				Vector3(19.0, 8.0, 19.0), C_FENCE_POST, true)
		px += 146.0
		post_i += 1


	# Fake contact shadows along the fence + hedge base.
	_contact_shadow(by, "FenceShadow", Vector3(1180.0, -2.0, 80.0), Vector2(2250.0, 110.0), 0.85)
	_contact_shadow(by, "HedgeShadow", Vector3(1180.0, -2.0, 34.0), Vector2(2250.0, 90.0), 0.55)


# === Trees ===============================================================

func _build_trees() -> void:
	var tg := _group("Trees")
	# A few background trees rooted on the base ground behind the hedge.  Kept
	# sparse and separate so sky shows between the canopies (through the HUD
	# gaps above the board) instead of forming a wall of green.
	var back_specs := [
		{"x": 200.0, "z": -24.0, "h": 240.0, "r": 74.0},
		{"x": 540.0, "z": -40.0, "h": 300.0, "r": 90.0},
		{"x": 880.0, "z": -16.0, "h": 215.0, "r": 66.0},
		{"x": 1210.0, "z": -34.0, "h": 280.0, "r": 84.0},
		{"x": 1580.0, "z": -20.0, "h": 235.0, "r": 72.0},
		{"x": 1960.0, "z": -30.0, "h": 260.0, "r": 78.0},
	]
	for i in back_specs.size():
		_make_tree(tg, "BackTree%d" % i, back_specs[i])
	_make_conifer(tg, "ConiferA", Vector3(390.0, 0.0, -34.0), 225.0)
	_make_conifer(tg, "ConiferB", Vector3(1050.0, 0.0, -26.0), 250.0)
	# A foreground tree on the right, in front of the street: strong depth cue
	# and a natural frame for the right edge (it cannot cover the lawn).
	_make_tree(tg, "FrontTree", {"x": 1660.0, "z": 760.0, "h": 320.0, "r": 112.0})


func _make_tree(parent: Node3D, name: String, s: Dictionary) -> void:
	var node := Node3D.new()
	node.name = name
	node.position = Vector3(float(s["x"]), -2.0, float(s["z"]))
	parent.add_child(node)
	var h := float(s["h"])
	var r := float(s["r"])
	# Trunk rooted on the base ground (top = -2), rising into the canopy.
	_cylinder(node, "Trunk", Vector3(0.0, h * 0.30, 0.0), r * 0.11, r * 0.18, h * 0.60,
			C_TRUNK, true, {}, 7)
	# Layered canopy blobs (slightly flattened, low-poly look).
	var leaf_cols := [C_LEAF_A, C_LEAF_B, C_LEAF_C]
	for i in 3:
		var cy := h * 0.56 + i * h * 0.14
		var cr := r * (1.0 - i * 0.18)
		_sphere(node, "Canopy%d" % i, Vector3(0.0, cy, 0.0), cr,
				leaf_cols[i % leaf_cols.size()], Vector3(1.0, 0.86, 1.0), true, {}, 10, 6)
	_sphere(node, "CanopySideA", Vector3(r * 0.5, h * 0.60, r * 0.1), r * 0.48,
			C_LEAF_B, Vector3.ONE, true, {}, 9, 5)
	_sphere(node, "CanopySideB", Vector3(-r * 0.45, h * 0.68, -r * 0.1), r * 0.44,
			C_LEAF_C, Vector3.ONE, true, {}, 9, 5)
	# Blob contact shadow on the ground under the canopy.
	_contact_shadow(parent, name + "Shadow", Vector3(float(s["x"]), -2.0, float(s["z"])),
			Vector2(r * 1.7, r * 1.05), 0.8)


func _make_conifer(parent: Node3D, name: String, base: Vector3, h: float) -> void:
	var node := Node3D.new()
	node.name = name
	node.position = Vector3(base.x, -2.0, base.z)
	parent.add_child(node)
	_cylinder(node, "Trunk", Vector3(0.0, h * 0.2, 0.0), 5.0, 7.0, h * 0.4, C_TRUNK, true, {}, 6)
	for i in 3:
		var cy := h * 0.30 + i * h * 0.22
		var cr := h * (0.19 - i * 0.05)
		_cone(node, "Needles%d" % i, Vector3(0.0, cy + h * 0.16, 0.0), cr, h * 0.34,
				Color("#356b35").lerp(Color("#2c5a2c"), float(i) * 0.3), true, {}, 8)


# === Foreground apron ====================================================

func _build_foreground() -> void:
	var fg := _group("Foreground")
	# Front lawn strip in front of the wooden border (bottom of the frame is
	# game y ~800 there): keeps the bottom edge full of ground, never void.
	_slab(fg, "FrontLawn",
			Rect2(60.0, LAWN_Y1 + 6.0, 1160.0, FRONT_EDGE_Y + 40.0 - (LAWN_Y1 + 6.0)),
			-0.6, -8.0, C_FRONT_GRASS)
	# Patio continuation on the left of the front lawn.
	_slab(fg, "FrontPatio", Rect2(-300.0, LAWN_Y1 + 6.0, 360.0, 240.0),
			0.0, -12.0, C_PATIO)
	for i in 5:
		_slab(fg, "FrontPatioSeam%d" % i, Rect2(-300.0, LAWN_Y1 + 20.0 + i * 46.0, 360.0, 3.0),
				-0.5, -1.2, C_PATIO_SEAM)
	# Subtle mowing stripes so the foreground apron is not a flat green band.
	for i in 5:
		_slab(fg, "FrontLawnStripe%d" % i,
				Rect2(70.0 + i * 230.0, LAWN_Y1 + 8.0, 112.0, FRONT_EDGE_Y - LAWN_Y1),
				-0.25, -0.9, Color("#549747"))
	# Contact shadow cast by the raised lawn border onto the front lawn.
	_contact_shadow(fg, "BorderShadow", Vector3(716.0, -0.6, 700.0),
			Vector2(980.0, 70.0), 0.7)
	# A few stepping stones leading off the bottom of the frame.
	for i in 3:
		_slab(fg, "SteppingStone%d" % i, Rect2(700.0 + i * 24.0, 748.0 + i * 40.0, 52.0, 28.0),
				0.4, -2.0, C_STONE_LIGHT)
	# Sparse flower accent only on the patio/house side (the lawn stays dominant).
	var flower_cols := [C_FLOWER_RED, C_FLOWER_YELLOW, C_FLOWER_PINK, C_FLOWER_WHITE]
	for i in 10:
		var fx := 108.0 + i * 14.0
		var fz := 792.0 + (i % 3) * 10.0 + float(i / 3) * 16.0
		_cylinder(fg, "BedStem%d" % i, Vector3(fx, 12.0, fz), 1.2, 1.6, 24.0,
				C_LEAF_C, false, {}, 4)
		_sphere(fg, "BedFlower%d" % i, Vector3(fx, 26.0, fz), 6.0,
				flower_cols[i % flower_cols.size()], Vector3.ONE, false, {}, 8, 5)
	# Two rounded bushes framing the very bottom corners (below any gameplay
	# cell, so they can never hide the board).
	_sphere(fg, "CornerBushL", Vector3(150.0, 2.0, 812.0), 32.0, C_HEDGE_LIGHT,
			Vector3(1.3, 0.9, 1.0), true, {}, 10, 6)
	_sphere(fg, "CornerBushR", Vector3(1210.0, 2.0, 826.0), 34.0, C_HEDGE,
			Vector3(1.3, 0.9, 1.0), true, {}, 10, 6)
	_contact_shadow(fg, "CornerBushLShadow", Vector3(150.0, -0.6, 812.0), Vector2(90.0, 56.0), 0.7)
	_contact_shadow(fg, "CornerBushRShadow", Vector3(1210.0, -0.6, 826.0), Vector2(96.0, 60.0), 0.7)
