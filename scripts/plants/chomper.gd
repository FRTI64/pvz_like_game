class_name Chomper
extends BasePlant

@export var digest_time: float = 30.0
@export var bite_range: float = 130.0

var is_chewing: bool = false
var chew_timer: float = 0.0

func _setup() -> void:
	is_chewing = false
	if visual_node != null and visual_node.has_method("set_chewing"):
		visual_node.set_chewing(false)

func _process(delta: float) -> void:
	if is_dead:
		return
	
	if is_chewing:
		chew_timer -= delta
		if chew_timer <= 0.0:
			_finish_digesting()
	else:
		_check_for_prey()

func _check_for_prey() -> void:
	var zombies: Array = get_tree().get_nodes_in_group("zombies")
	for z in zombies:
		if is_instance_valid(z) and not z.get("is_dead"):
			var z_row: int = z.get("row")
			if z_row == row and z.global_position.x > global_position.x:
				var dist: float = z.global_position.x - global_position.x
				if dist <= bite_range:
					_chomp_zombie(z)
					return

func _chomp_zombie(prey: Node2D) -> void:
	SoundManager.play_sound("chomp")
	is_chewing = true
	chew_timer = digest_time
	
	# Eliminate the target zombie
	if prey.has_method("die"):
		prey.die(false)
	else:
		prey.queue_free()
	
	if visual_node != null and visual_node.has_method("set_chewing"):
		visual_node.set_chewing(true)

func _finish_digesting() -> void:
	is_chewing = false
	if visual_node != null and visual_node.has_method("set_chewing"):
		visual_node.set_chewing(false)

