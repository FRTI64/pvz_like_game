class_name Main
extends Node3D
## 3D-rendered entry scene for a level (docs/3d-render-spec.md §4.1).
##
## Keeps the 2D version's level / GameManager initialisation; the presentation
## layer is a fixed perspective camera looking at a 3D diorama.  Gameplay nodes
## live under WorldRoot and keep using 2D game-pixel coordinates.

@export var default_level: LevelData

@onready var world_root: Node3D = $WorldRoot
@onready var board: Node3D = $WorldRoot/Board
@onready var grid_manager: GridManager = $WorldRoot/GridManager
@onready var sun_manager: SunManager = $WorldRoot/SunManager
@onready var wave_manager: WaveManager = $WorldRoot/WaveManager
@onready var hud: HUD = $HUD

const BoardBuilderScript := preload("res://scripts/core/board_builder.gd")

var _board_built: bool = false


func _ready() -> void:
	_setup_camera()
	_setup_lighting()
	_setup_world_root()
	_build_board()
	_init_level()


## The scene keeps real shadow mapping enabled for GPUs, but the shadow pass is
## very expensive on software rasterizers and shadow maps do not render under
## gl_compatibility + llvmpipe anyway (verified), so turn just the shadow pass
## off when running on one.  Purely a performance adaptation.
func _setup_lighting() -> void:
	var sun := get_node_or_null("Sun") as DirectionalLight3D
	if sun == null:
		return
	var adapter := RenderingServer.get_video_adapter_name().to_lower()
	if adapter.contains("llvmpipe") or adapter.contains("softpipe") \
			or adapter.contains("swiftshader") or adapter.contains("software"):
		sun.shadow_enabled = false


func _setup_camera() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	camera.fov = WorldSpace.CAMERA_FOV
	camera.position = WorldSpace.default_camera_position()
	camera.look_at(WorldSpace.CAMERA_TARGET, Vector3.UP)


func _setup_world_root() -> void:
	if world_root == null:
		return
	WorldSpace.setup_world_root(world_root)


func _build_board() -> void:
	if _board_built or board == null:
		return
	var builder: RefCounted = BoardBuilderScript.new()
	builder.call("build", board)
	_board_built = true


func _init_level() -> void:
	if GameManager.selected_level_data != null:
		default_level = GameManager.selected_level_data
	elif default_level == null:
		default_level = load("res://data/levels/level_1.tres")

	GameManager.start_game(default_level.initial_sun)
	if sun_manager != null and default_level.natural_sun_interval > 0.0:
		sun_manager.natural_drop_interval = default_level.natural_sun_interval
	wave_manager.start_level(default_level)
