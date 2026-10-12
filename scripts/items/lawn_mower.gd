class_name LawnMower
extends Area2D

@export var row: int = 0
@export var speed: float = 650.0

var is_active: bool = false
var has_triggered: bool = false

func _ready() -> void:
	collision_layer = 16 # Layer 5: Defense devices
	collision_mask = 2   # Layer 2: Zombies
	area_entered.connect(_on_area_entered)

func _process(delta: float) -> void:
	if is_active:
		position.x += speed * delta
		if position.x > 1360.0:
			queue_free()
	else:
		_check_for_approaching_zombies()

func _check_for_approaching_zombies() -> void:
	if has_triggered:
		return
	
	var zombies: Array = get_tree().get_nodes_in_group("zombies")
	for z in zombies:
		if is_instance_valid(z) and not z.get("is_dead") and z.get("row") == row:
			if z.global_position.x <= global_position.x + 30.0 and z.global_position.x >= global_position.x - 60.0:
				trigger_mower()
				return

func trigger_mower() -> void:
	if has_triggered:
		return
	has_triggered = true
	is_active = true
	SoundManager.play_sound("lawnmower")
	EventBus.lawn_mower_triggered.emit(row)

func _on_area_entered(area: Area2D) -> void:
	if not is_active:
		return
	if area is BaseZombie and not area.get("is_dead") and area.get("row") == row:
		area.take_damage(9999, true) # Obliterates the zombie

