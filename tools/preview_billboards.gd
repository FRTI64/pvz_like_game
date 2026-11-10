extends Node3D
## Lead reference scene: renders the baked billboards in a miniature 3D diorama
## (lawn board, patio, house facade, street, fence, trees, painted sky backdrop)
## and saves a screenshot. Used to validate the foundation contracts and as an
## art-direction reference for the conversion agents.
## Run:
##   export LD_LIBRARY_PATH="$PWD/.tools/libs/usr/lib"
##   export XKB_CONFIG_ROOT="$PWD/.tools/libs/usr/share/X11/xkb"
##   godot --path . res://tools/preview_billboards.tscn \
##       --display-driver wayland --rendering-driver opengl3

const OUT_PATH := "res://.tools/shots/foundation_preview.png"

const LAWN_LIGHT := Color(0.337, 0.639, 0.29)
const LAWN_DARK := Color(0.294, 0.58, 0.254)
const BOARD_FRAME := Color(0.42, 0.29, 0.18)

var _world_root: Node3D


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.tools/shots/"))
	_build_environment()
	_world_root = Node3D.new()
	_world_root.name = "WorldRoot"
	add_child(_world_root)
	WorldSpace.setup_world_root(_world_root)
	_build_board()
	_build_props()
	_build_scene_entities()
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png(ProjectSettings.globalize_path(OUT_PATH))
	print("PREVIEW SAVED: ", ProjectSettings.globalize_path(OUT_PATH))
	get_tree().quit(0)


func _build_environment() -> void:
	var camera := Camera3D.new()
	camera.fov = WorldSpace.CAMERA_FOV
	camera.near = 0.1
	camera.far = 500.0
	add_child(camera)
	# Preview variant: a slightly closer camera fills the frame better.
	var target := WorldSpace.CAMERA_TARGET
	var phi := deg_to_rad(WorldSpace.CAMERA_ELEVATION_DEG)
	var distance := 23.0
	camera.position = target + Vector3(0.0, distance * sin(phi), distance * cos(phi))
	camera.look_at(target, Vector3.UP)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-52.0, -28.0, 0.0)
	light.light_color = Color(1.0, 0.95, 0.84)
	light.light_energy = 1.35
	light.shadow_enabled = true
	light.directional_shadow_max_distance = 80.0
	add_child(light)

	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.7, 0.85, 0.95)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.82, 0.88, 1.0)
	environment.ambient_light_energy = 0.65
	var world_env := WorldEnvironment.new()
	world_env.environment = environment
	add_child(world_env)


func _box(parent: Node3D, size: Vector3, position: Vector3, color: Color, cast_shadow: bool = true) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.9
	mesh.material_override = mat
	mesh.position = position
	if cast_shadow:
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	else:
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mesh)
	return mesh


func _build_board() -> void:
	# Base ground underlay: top at y=-3 so it never z-fights with the board tops.
	_box(_world_root, Vector3(2600, 10, 1100), Vector3(640, -8, 490), Color(0.22, 0.32, 0.18))

	# Lawn tiles, top exactly at y=0.
	for row in range(5):
		for col in range(9):
			var color: Color = LAWN_LIGHT if (row + col) % 2 == 0 else LAWN_DARK
			_box(_world_root, Vector3(96, 3, 106), Vector3(
				275 + col * 98 + 49, -1.5, 125 + row * 108 + 54
			), color, false)
	# Lawn wooden border, top slightly above the lawn (visual frame).
	var border_y := -1.0
	_box(_world_root, Vector3(9 * 98 + 24, 5, 16), Vector3(275 + 9 * 98 * 0.5, border_y - 2.5, 117), BOARD_FRAME, false)
	_box(_world_root, Vector3(9 * 98 + 24, 5, 16), Vector3(275 + 9 * 98 * 0.5, border_y - 2.5, 673), BOARD_FRAME, false)
	_box(_world_root, Vector3(16, 5, 5 * 108 + 16), Vector3(267, border_y - 2.5, 125 + 5 * 108 * 0.5), BOARD_FRAME, false)
	_box(_world_root, Vector3(16, 5, 5 * 108 + 16), Vector3(1181, border_y - 2.5, 125 + 5 * 108 * 0.5), BOARD_FRAME, false)

	# Patio (left) top at y=0.
	_box(_world_root, Vector3(265, 4, 720), Vector3(132.5, -2, 360), Color(0.42, 0.3, 0.2), false)
	for y in range(0, 720, 48):
		_box(_world_root, Vector3(265, 1, 2), Vector3(132.5, 1.0, y), Color(0.34, 0.24, 0.16), false)
	# Street / pavement (right) top at y=0.
	_box(_world_root, Vector3(115, 4, 720), Vector3(1222.5, -2, 360), Color(0.34, 0.36, 0.38), false)
	for y in range(0, 720, 60):
		_box(_world_root, Vector3(115, 1, 3), Vector3(1222.5, 1.0, y), Color(0.27, 0.29, 0.31), false)


func _build_props() -> void:
	# House facade just outside the left board edge.
	_box(_world_root, Vector3(80, 380, 720), Vector3(-40, 190, 360), Color(0.78, 0.68, 0.52))
	_box(_world_root, Vector3(110, 34, 760), Vector3(-40, 397, 360), Color(0.55, 0.28, 0.22))
	for x_pos in [-64.0, -16.0]:
		_box(_world_root, Vector3(34, 86, 6), Vector3(x_pos, 240, 722), Color(0.62, 0.83, 0.91), false)
	_box(_world_root, Vector3(48, 148, 6), Vector3(-40, 76, 722), Color(0.33, 0.21, 0.14), false)

	# Background band right behind the far lawn edge: fence + hedge + low trees +
	# a couple of distant hill masses. The HUD covers the top ~120 px, so this
	# band is what the player sees above the lawn.
	_box(_world_root, Vector3(1400, 54, 26), Vector3(640, 27, 30), Color(0.22, 0.42, 0.2))
	for x in range(0, 1280, 64):
		_box(_world_root, Vector3(10, 76, 10), Vector3(x + 32, 38, 14), Color(0.42, 0.29, 0.18))
	_box(_world_root, Vector3(1400, 10, 8), Vector3(640, 60, 14), Color(0.45, 0.32, 0.2))
	for spec in [[160.0, -30.0, 210.0], [430.0, -20.0, 260.0], [820.0, -35.0, 230.0], [1120.0, -25.0, 190.0]]:
		var x: float = spec[0]
		var z: float = spec[1]
		var h: float = spec[2]
		_box(_world_root, Vector3(18, h * 0.42, 18), Vector3(x, h * 0.21, z), Color(0.3, 0.22, 0.14))
		var foliage := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 2.0
		cone.bottom_radius = h * 0.3
		cone.height = h * 0.75
		foliage.mesh = cone
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.16, 0.34, 0.16)
		foliage.material_override = mat
		foliage.position = Vector3(x, h * 0.42 + h * 0.375, z)
		_world_root.add_child(foliage)
	# Distant hills (soft dark green masses) behind the tree line.
	for hill in []:
		var hill_mesh := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = float(hill[2]) * 0.5
		sphere.height = float(hill[2])
		hill_mesh.mesh = sphere
		var hill_mat := StandardMaterial3D.new()
		hill_mat.albedo_color = Color(0.3, 0.44, 0.3)
		hill_mesh.material_override = hill_mat
		hill_mesh.position = Vector3(hill[0], -40.0, hill[1])
		_world_root.add_child(hill_mesh)

	# Foreground apron in front of the near board edge.
	_box(_world_root, Vector3(2600, 3, 260), Vector3(640, -1.5, 880), Color(0.26, 0.36, 0.2), false)


func _add_billboard(sheet: String, x: float, z: float, height_px: float = 0.0) -> void:
	var billboard := BillboardLibrary.make_billboard(sheet)
	billboard.position = WorldSpace.game2_to_local(x, z, height_px)
	_world_root.add_child(billboard)
	if height_px < 1.0:
		var shadow := BillboardLibrary.make_shadow_for(sheet)
		shadow.position = WorldSpace.game2_to_local(x, z, 0.0)
		_world_root.add_child(shadow)


func _build_scene_entities() -> void:
	# A representative battle layout: plants left/mid, zombies approaching from right.
	var plants := [
		["p_peashooter", 0, 1], ["p_peashooter", 0, 2], ["p_sunflower", 1, 0],
		["p_sunflower", 2, 1], ["p_wallnut_0", 3, 4], ["p_snow_pea", 1, 3],
		["p_repeater", 2, 3], ["p_chomper_0", 4, 2], ["p_potato_1", 3, 1],
		["p_cherry", 4, 5], ["p_wallnut_1", 0, 6],
	]
	for spec in plants:
		var row: int = spec[1]
		var col: int = spec[2]
		var x: float = 275.0 + col * 98.0 + 49.0
		var z: float = 125.0 + row * 108.0 + 54.0
		_add_billboard(str(spec[0]), x, z)

	var zombies := [
		["z_normal", 1, 7], ["z_conehead", 2, 6], ["z_buckethead", 3, 7],
		["z_flag", 4, 8], ["z_normal", 0, 8],
	]
	for spec in zombies:
		var row: int = spec[1]
		var col: int = spec[2]
		var x: float = 275.0 + col * 98.0 + 49.0
		var z: float = 125.0 + row * 108.0 + 54.0
		_add_billboard(str(spec[0]), x, z)

	# Mowers at the left edge of each lane.
	for row in range(5):
		_add_billboard("i_mower", 215.0, 175.0 + row * 108.0)

	# Floating suns and a couple of projectiles.
	_add_billboard("i_sun", 700, 380, 110.0)
	_add_billboard("i_sun", 980, 520, 130.0)
	_add_billboard("i_pea", 560, 285, 52.0)
	_add_billboard("i_snow_pea", 610, 393, 52.0)
