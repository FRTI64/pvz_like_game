class_name Chomper
extends BasePlant

@export var digest_time: float = 30.0
@export var bite_range: float = 130.0

var is_chewing: bool = false
var chew_timer: float = 0.0

func _setup() -> void:
	is_chewing = false
	set_billboard_sheet("p_chomper_0")

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
			if z_row == row and z.position.x > position.x:
				var dist: float = z.position.x - position.x
				if dist <= bite_range:
					_chomp_zombie(z)
					return

func _chomp_zombie(prey: Node3D) -> void:
	SoundManager.play_sound("chomp")
	is_chewing = true
	chew_timer = digest_time

	# Eliminate the target zombie
	if prey.has_method("die"):
		prey.die(false)
	else:
		prey.queue_free()

	set_billboard_sheet("p_chomper_1")

func _finish_digesting() -> void:
	is_chewing = false
	set_billboard_sheet("p_chomper_0")
