class_name LawnMower
extends Area3D
## Lane-clearing lawn mower. Sits at the house end of a lane (set by main.tscn /
## LawnMowers), triggers when a zombie gets close and then drives right,
## obliterating everything in its lane.

const Z_NUDGE: float = 1.0

@export var row: int = 0
@export var speed: float = 650.0
@export var billboard_sheet: String = "i_mower"

var is_active: bool = false
var has_triggered: bool = false

var visual_node: Billboard2D = null
var shadow_node: MeshInstance3D = null
var _bob_t: float = 0.0

func _ready() -> void:
	collision_layer = 16 # Layer 5: Defense devices
	collision_mask = 2   # Layer 2: Zombies

	visual_node = BillboardLibrary.make_billboard(billboard_sheet)
	visual_node.name = "Visual"
	visual_node.position = Vector3(0.0, 0.0, Z_NUDGE)
	add_child(visual_node)

	shadow_node = BillboardLibrary.make_shadow_for(billboard_sheet)
	if shadow_node != null:
		shadow_node.name = "Shadow"
		add_child(shadow_node)

	area_entered.connect(_on_area_entered)

func _process(delta: float) -> void:
	if is_active:
		position.x += speed * delta
		# Rumble while driving
		_bob_t += delta * 30.0
		if visual_node != null:
			visual_node.position = Vector3(
				0.0,
				absf(sin(_bob_t)) * 2.0,
				Z_NUDGE
			)
		_kill_zombies_in_path()
		if position.x > 1360.0:
			queue_free()
	else:
		_check_for_approaching_zombies()

## The mower triggers while already overlapping the zombie that woke it up, so
## no new area_entered event is emitted for that one. Also catch any zombie the
## mower catches up with in the same frame; kill using the existing px distance
## logic instead of relying on area events alone.
func _kill_zombies_in_path() -> void:
	var zombies: Array = get_tree().get_nodes_in_group("zombies")
	for z in zombies:
		if is_instance_valid(z) and not z.get("is_dead") and z.get("row") == row:
			if absf(z.position.x - position.x) <= 55.0 and absf(z.position.z - position.z) <= 70.0:
				z.take_damage(9999, true) # Obliterates the zombie

func _check_for_approaching_zombies() -> void:
	if has_triggered:
		return

	var zombies: Array = get_tree().get_nodes_in_group("zombies")
	for z in zombies:
		if is_instance_valid(z) and not z.get("is_dead") and z.get("row") == row:
			if z.position.x <= position.x + 30.0 and z.position.x >= position.x - 60.0:
				trigger_mower()
				return

func trigger_mower() -> void:
	if has_triggered:
		return
	has_triggered = true
	is_active = true
	SoundManager.play_sound("lawnmower")
	EventBus.lawn_mower_triggered.emit(row)

func _on_area_entered(area: Area3D) -> void:
	if not is_active:
		return
	if area is BaseZombie and not area.get("is_dead") and area.get("row") == row:
		area.take_damage(9999, true) # Obliterates the zombie
