class_name PotatoMine
extends BasePlant

@export var arming_time: float = 14.0
@export var damage: int = 1800

var is_armed: bool = false
var arm_timer: float = 0.0

func _setup() -> void:
	arm_timer = arming_time
	is_armed = false
	if visual_node != null and visual_node.has_method("set_armed"):
		visual_node.set_armed(false)

func _process(delta: float) -> void:
	if is_dead:
		return
	
	if not is_armed:
		arm_timer -= delta
		if arm_timer <= 0.0:
			_arm_mine()
	else:
		_check_for_stepping_zombie()

func _arm_mine() -> void:
	is_armed = true
	if visual_node != null and visual_node.has_method("set_armed"):
		visual_node.set_armed(true)
	
	# Small bounce popup
	if visual_node != null:
		var tween := create_tween()
		tween.tween_property(visual_node, "position", Vector2(0, -10), 0.15)
		tween.tween_property(visual_node, "position", Vector2.ZERO, 0.1)

func _check_for_stepping_zombie() -> void:
	var zombies: Array = get_tree().get_nodes_in_group("zombies")
	for z in zombies:
		if is_instance_valid(z) and not z.get("is_dead"):
			var z_row: int = z.get("row")
			if z_row == row:
				var dist_x: float = absf(z.global_position.x - global_position.x)
				if dist_x < 45.0: # Zombie stepped on it!
					_detonate_mine(z)
					return

func _detonate_mine(_target_zombie: Node2D) -> void:
	SoundManager.play_sound("boom")
	
	# Deal massive damage to all zombies very close to the mine
	var zombies: Array = get_tree().get_nodes_in_group("zombies")
	for z in zombies:
		if is_instance_valid(z) and not z.get("is_dead") and z.get("row") == row:
			var dist: float = absf(z.global_position.x - global_position.x)
			if dist < 65.0 and z.has_method("take_damage"):
				z.take_damage(damage, true)
	
	# Spawn explosion effect
	var fx_sc: PackedScene = load("res://scenes/effects/explosion_effect.tscn")
	if fx_sc != null:
		var fx: Node2D = fx_sc.instantiate()
		fx.global_position = global_position
		get_parent().add_child(fx)
		
	die()

