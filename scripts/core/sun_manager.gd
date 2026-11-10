class_name SunManager
extends Node3D
## Spawns collectible Sun billboards (docs/3d-render-spec.md §4.3).
##
## Lives under WorldRoot with an identity transform: local coordinates are game
## pixels and local y = 0 is the ground.  A natural sun appears above/behind the
## far lawn edge at game y = -40 and floats down (+Z) to a random target row.
## Sunflower suns pop up from the plant with a small upward arc.

@export var sun_scene: PackedScene
@export var natural_drop_interval: float = 9.0

## Height (game px) at which suns float.  Kept 2D-compatible: the spec uses 95.
const SUN_HEIGHT: float = 95.0
const NATURAL_SPAWN_Z: float = -40.0

var drop_timer: float = 0.0
var active_suns: Array[Node3D] = []


func _ready() -> void:
	drop_timer = natural_drop_interval * 0.5 # First sun drops early
	EventBus.sun_spawned.connect(_on_sun_spawned)


func _process(delta: float) -> void:
	if GameManager.current_state != GameManager.GameState.PLAYING:
		return

	drop_timer -= delta
	if drop_timer <= 0.0:
		spawn_natural_sun()
		drop_timer = natural_drop_interval + randf_range(-1.5, 2.5)


func spawn_natural_sun() -> void:
	if sun_scene == null:
		sun_scene = load("res://scenes/items/sun.tscn")
	var sun: Node3D = sun_scene.instantiate() as Node3D
	if sun == null:
		return
	var start_x: float = randf_range(320.0, 1100.0)
	var target_z: float = randf_range(160.0, 600.0)

	sun.position = Vector3(start_x, SUN_HEIGHT, NATURAL_SPAWN_Z)
	add_child(sun)

	if sun.has_method("setup_falling"):
		sun.call("setup_falling", target_z)


func spawn_sunflower_sun(source_pos: Vector2) -> void:
	## `source_pos` is 2D game coordinates (px) — kept from the 2D version.
	if sun_scene == null:
		sun_scene = load("res://scenes/items/sun.tscn")
	var sun: Node3D = sun_scene.instantiate() as Node3D
	if sun == null:
		return
	sun.position = Vector3(source_pos.x, SUN_HEIGHT, source_pos.y)
	add_child(sun)

	if sun.has_method("setup_flower_drop"):
		var offset := Vector2(randf_range(-30, 30), randf_range(20, 45))
		sun.call("setup_flower_drop", source_pos + offset)


func _on_sun_spawned(sun: Node3D) -> void:
	active_suns.append(sun)
	sun.tree_exited.connect(func(): active_suns.erase(sun))
