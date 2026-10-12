class_name SunManager
extends Node2D

@export var sun_scene: PackedScene
@export var natural_drop_interval: float = 9.0

var drop_timer: float = 0.0
var active_suns: Array[Node2D] = []

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
	
	var sun: Node2D = sun_scene.instantiate()
	var start_x: float = randf_range(320.0, 1100.0)
	var start_pos := Vector2(start_x, -40.0)
	var target_y: float = randf_range(160.0, 600.0)
	
	sun.position = start_pos
	add_child(sun)
	
	if sun.has_method("setup_falling"):
		sun.setup_falling(target_y)

func spawn_sunflower_sun(source_pos: Vector2) -> void:
	if sun_scene == null:
		sun_scene = load("res://scenes/items/sun.tscn")
	
	var sun: Node2D = sun_scene.instantiate()
	sun.position = source_pos
	add_child(sun)
	
	if sun.has_method("setup_flower_drop"):
		var offset := Vector2(randf_range(-30, 30), randf_range(20, 45))
		sun.setup_flower_drop(source_pos + offset)

func _on_sun_spawned(sun: Node2D) -> void:
	active_suns.append(sun)
	sun.tree_exited.connect(func(): active_suns.erase(sun))

