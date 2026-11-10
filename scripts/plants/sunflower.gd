class_name Sunflower
extends BasePlant

@export var production_interval: float = 24.0
@export var initial_warmup: float = 7.0

var produce_timer: float = 0.0

func _setup() -> void:
	produce_timer = initial_warmup

func _process(delta: float) -> void:
	if is_dead:
		return

	produce_timer -= delta

	# Glow pulse before producing
	if produce_timer <= 1.2 and produce_timer > 0.0:
		if visual_node != null:
			var pulse: float = 1.0 + sin(produce_timer * 15.0) * 0.25
			visual_node.modulate = Color(pulse, pulse, pulse * 0.8, 1.0)

	if produce_timer <= 0.0:
		_produce_sun()
		produce_timer = production_interval
		if visual_node != null:
			visual_node.modulate = Color.WHITE

func _produce_sun() -> void:
	# Bounce animation
	if visual_node != null:
		var tween := create_tween()
		tween.tween_property(visual_node, "scale", Vector3(1.25, 1.25, 1.0), 0.15)
		tween.tween_property(visual_node, "scale", Vector3.ONE, 0.2)

	# 2D game coordinates of this plant (local px: x, z)
	var game_2d := Vector2(position.x, position.z)

	# Find sun manager in tree or spawn directly
	var sun_manager: SunManager = get_tree().root.find_child("SunManager", true, false) as SunManager
	if sun_manager != null:
		sun_manager.spawn_sunflower_sun(game_2d)
	else:
		var sun_sc: PackedScene = load("res://scenes/items/sun.tscn")
		if sun_sc != null:
			var sun: Node3D = sun_sc.instantiate()
			sun.position = Vector3(game_2d.x, 95.0, game_2d.y)
			get_parent().add_child(sun)
			if sun.has_method("setup_flower_drop"):
				sun.setup_flower_drop(game_2d + Vector2(randf_range(-25.0, 25.0), 25.0))
