class_name SnowPeaBullet
extends BaseProjectile

@export var chill_duration: float = 5.0

func _hit_zombie(zombie: BaseZombie) -> void:
	is_destroyed = true
	zombie.take_damage(damage)
	if zombie.has_method("apply_chill"):
		zombie.apply_chill(chill_duration)
	_play_splat_effect()
	queue_free()

