class_name Wallnut
extends BasePlant

enum CrackStage {
	INTACT,
	SLIGHTLY_CRACKED,
	HEAVILY_CRACKED
}

var current_stage: CrackStage = CrackStage.INTACT

func _setup() -> void:
	max_health = 4000
	current_health = max_health

func take_damage(amount: int) -> void:
	super.take_damage(amount)
	_update_crack_stage()

func _update_crack_stage() -> void:
	var ratio: float = float(current_health) / float(max_health)
	var new_stage: CrackStage = CrackStage.INTACT
	
	if ratio < 0.33:
		new_stage = CrackStage.HEAVILY_CRACKED
	elif ratio < 0.66:
		new_stage = CrackStage.SLIGHTLY_CRACKED
	
	if new_stage != current_stage:
		current_stage = new_stage
		if visual_node != null and visual_node.has_method("set_crack_stage"):
			visual_node.set_crack_stage(int(current_stage))

