class_name SnowPea
extends BasePlant

@export var bullet_scene: PackedScene
@export var attack_rate: float = 1.4

var attack_timer: float = 0.0

func _setup() -> void:
	if bullet_scene == null:
		bullet_scene = load("res://scenes/projectiles/snow_pea_bullet.tscn")
	attack_timer = randf_range(0.2, 0.7)

func _process(delta: float) -> void:
	if is_dead:
		return
	
	attack_timer -= delta
	if attack_timer <= 0.0:
		if _has_zombies_ahead():
			shoot_ice_pea()
			attack_timer = attack_rate
		else:
			attack_timer = 0.25

func _has_zombies_ahead() -> bool:
	var zombies: Array = get_tree().get_nodes_in_group("zombies")
	for z in zombies:
		if is_instance_valid(z) and not z.get("is_dead"):
			var z_row: int = z.get("row")
			if z_row == row and z.global_position.x > global_position.x and z.global_position.x < 1300.0:
				return true
	return false

func shoot_ice_pea() -> void:
	if bullet_scene == null:
		return
	
	var bullet: Node2D = bullet_scene.instantiate()
	bullet.global_position = global_position + Vector2(28.0, -12.0)
	if bullet.has_method("setup_projectile"):
		bullet.setup_projectile(row, 20, 400.0)
	
	get_parent().add_child(bullet)
	SoundManager.play_sound("shoot")
	
	if visual_node != null:
		var tween := create_tween()
		tween.tween_property(visual_node, "scale", Vector2(1.2, 0.8), 0.07)
		tween.tween_property(visual_node, "scale", Vector2(1.0, 1.0), 0.12)

