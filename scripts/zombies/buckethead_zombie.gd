class_name BucketheadZombie
extends BaseZombie

func _on_armor_broken() -> void:
	# Swap the billboard to the hat-less zombie, drop a 3D bucket.
	set_billboard_sheet("z_normal")
	_spawn_falling_armor_prop(false)
