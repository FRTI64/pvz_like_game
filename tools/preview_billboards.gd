extends Node3D
## Lead-only foundation smoke test: renders the baked billboards on a simple 3D
## lawn with the default camera, saves a screenshot and quits.
## Run:
##   export LD_LIBRARY_PATH="$PWD/.tools/libs/usr/lib"
##   export XKB_CONFIG_ROOT="$PWD/.tools/libs/usr/share/X11/xkb"
##   godot --path . res://tools/preview_billboards.tscn \
##       --display-driver wayland --rendering-driver opengl3

const SHEETS: Array[String] = [
	"p_peashooter", "p_sunflower", "p_wallnut_0", "p_cherry", "p_snow_pea",
	"p_potato_0", "p_potato_1", "p_repeater", "p_chomper_0", "p_chomper_1",
	"z_normal", "z_conehead", "z_buckethead", "z_flag",
	"i_sun", "i_pea", "i_snow_pea", "i_mower",
]

const OUT_PATH := "res://.tools/shots/foundation_preview.png"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.tools/shots/"))
	_build_world()
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png(ProjectSettings.globalize_path(OUT_PATH))
	print("PREVIEW SAVED: ", ProjectSettings.globalize_path(OUT_PATH))
	get_tree().quit(0)


func _build_world() -> void:
	# Camera
	var camera := Camera3D.new()
	camera.fov = WorldSpace.CAMERA_FOV
	camera.near = 0.1
	camera.far = 500.0
	add_child(camera)
	camera.position = WorldSpace.default_camera_position()
	camera.look_at(WorldSpace.CAMERA_TARGET, Vector3.UP)

	# Sun + environment
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-52.0, -28.0, 0.0)
	light.light_color = Color(1.0, 0.95, 0.84)
	light.light_energy = 1.35
	light.shadow_enabled = false
	add_child(light)

	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.557, 0.788, 0.91)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.82, 0.88, 1.0)
	environment.ambient_light_energy = 0.6
	var world_env := WorldEnvironment.new()
	world_env.environment = environment
	add_child(world_env)

	# World root (game px space)
	var world_root := Node3D.new()
	world_root.name = "WorldRoot"
	add_child(world_root)
	WorldSpace.setup_world_root(world_root)

	# Base ground slab
	var base_mesh := MeshInstance3D.new()
	var base_box := BoxMesh.new()
	base_box.size = Vector3(2600.0, 10.0, 1800.0)
	base_mesh.mesh = base_box
	var base_mat := StandardMaterial3D.new()
	base_mat.albedo_color = Color(0.2, 0.28, 0.16)
	base_mesh.material_override = base_mat
	base_mesh.position = Vector3(640.0, -8.0, 360.0)  # top at y=-3 (avoid coplanar z-fighting)
	world_root.add_child(base_mesh)

	# Patio + street
	for spec in [
		[Vector3(132.5, -2.0, 360.0), Vector3(265, 4.0, 720.0), Color(0.42, 0.3, 0.2)],
		[Vector3(1222.5, -2.0, 360.0), Vector3(115, 4.0, 720.0), Color(0.34, 0.36, 0.38)],
	]:
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = spec[1]
		mesh.mesh = box
		var mat := StandardMaterial3D.new()
		mat.albedo_color = spec[2]
		mesh.material_override = mat
		mesh.position = spec[0]
		world_root.add_child(mesh)

	# Lawn checkerboard (top of every slab = local y 0)
	for row in range(5):
		for col in range(9):
			var tile := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(96.0, 3.0, 106.0)
			tile.mesh = box
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.337, 0.639, 0.29) if (row + col) % 2 == 0 else Color(0.294, 0.58, 0.254)
			tile.material_override = mat
			tile.position = Vector3(
				275.0 + col * 98.0 + 49.0,
				-1.5,
				125.0 + row * 108.0 + 54.0
			)
			world_root.add_child(tile)

	# One billboard per sheet, arranged in rows.
	var x := 150.0
	var z := 200.0
	for sheet in SHEETS:
		var billboard := BillboardLibrary.make_billboard(sheet)
		billboard.position = WorldSpace.game2_to_local(x, z, 0.0)
		world_root.add_child(billboard)
		var shadow := BillboardLibrary.make_shadow_for(sheet)
		shadow.position = WorldSpace.game2_to_local(x, z, 0.0)
		world_root.add_child(shadow)
		x += 60.0
		if x > 1180.0:
			x = 150.0
			z += 120.0
