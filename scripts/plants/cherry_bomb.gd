class_name CherryBomb
extends BasePlant

@export var fuse_time: float = 1.0
@export var explosion_damage: int = 1800
@export var blast_radius_cells: int = 1 # 1 cell radius = 3x3 grid

var fuse_timer: float = 0.0

func _setup() -> void:
	fuse_timer = fuse_time
	# Swelling and pulsing animation
	if visual_node != null:
		var tween := create_tween()
		tween.tween_property(visual_node, "scale", Vector2(1.35, 1.35), fuse_time * 0.7)
		tween.parallel().tween_property(visual_node, "modulate", Color(1.8, 0.4, 0.4, 1.0), fuse_time * 0.7)

func _process(delta: float) -> void:
	if is_dead:
		return
	
	fuse_timer -= delta
	if fuse_timer <= 0.0:
		_explode()

func _explode() -> void:
	SoundManager.play_sound("boom")
	
	# Blast radius: 3x3 grid around current cell
	var target_col: int = col
	var target_row: int = row
	
	var zombies: Array = get_tree().get_nodes_in_group("zombies")
	for z in zombies:
		if is_instance_valid(z) and not z.get("is_dead"):
			var z_row: int = z.get("row")
			if absi(z_row - target_row) <= blast_radius_cells:
				# Check horizontal distance (approx cell size is 98px)
				var dist_x: float = absf(z.global_position.x - global_position.x)
				if dist_x <= 150.0:
					if z.has_method("take_damage"):
						z.take_damage(explosion_damage, true) # Massive lethal explosion
	
	# Spawn explosion effect if available
	var fx_sc: PackedScene = load("res://scenes/effects/explosion_effect.tscn")
	if fx_sc != null:
		var fx: Node2D = fx_sc.instantiate()
		fx.global_position = global_position
		get_parent().add_child(fx)
	
	die()

