class_name FlagZombie
extends BaseZombie

# Flag zombie moves slightly faster and leads large waves
func setup_zombie(data: ZombieData, lane_idx: int) -> void:
	super.setup_zombie(data, lane_idx)
	base_speed = data.move_speed * 1.25

