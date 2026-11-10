class_name Peashooter
extends BasePlant

## Height (local game px) the pea projectile flies at, roughly snout height.
const BULLET_HEIGHT: float = 50.0

@export var bullet_scene: PackedScene
@export var attack_rate: float = 1.4

var attack_timer: float = 0.0

func _setup() -> void:
	if bullet_scene == null:
		bullet_scene = load("res://scenes/projectiles/pea.tscn")
	# Slight random offset so all peashooters don't fire at the exact same millisecond
	attack_timer = randf_range(0.2, 0.7)

func _process(delta: float) -> void:
	if is_dead:
		return

	attack_timer -= delta
	if attack_timer <= 0.0:
		if _has_zombies_ahead():
			shoot_pea()
			attack_timer = attack_rate
		else:
			# Check again soon
			attack_timer = 0.25

func _has_zombies_ahead() -> bool:
	var zombies: Array = get_tree().get_nodes_in_group("zombies")
	for z in zombies:
		if is_instance_valid(z) and not z.get("is_dead"):
			var z_row: int = z.get("row")
			if z_row == row and z.position.x > position.x and z.position.x < 1300.0:
				return true
	return false

func shoot_pea() -> void:
	if bullet_scene == null:
		return

	var bullet: BaseProjectile = bullet_scene.instantiate() as BaseProjectile
	if bullet == null:
		return
	# Spawn slightly in front of the snout, at flight height (local game px).
	bullet.position = position + Vector3(28.0, BULLET_HEIGHT, 0.0)
	bullet.setup_projectile(row, 20, 400.0)

	get_parent().add_child(bullet)
	SoundManager.play_sound("shoot")

	# Head recoil animation (billboard local scale, anchored at the feet)
	if visual_node != null:
		var tween := create_tween()
		tween.tween_property(visual_node, "scale", Vector3(1.2, 0.8, 1.0), 0.07)
		tween.tween_property(visual_node, "scale", Vector3.ONE, 0.12)
