class_name BasePlant
extends Area3D

signal health_changed(new_hp: int, max_hp: int)
signal plant_died()

## Ground convention (spec §2 / Lead): top of the lawn slabs is local y = 0, so
## the billboard's anchor (feet) sits exactly at the entity root position.
const Z_NUDGE: float = 1.0

@export var plant_data: PlantData
@export var billboard_sheet: String = ""

var grid_pos: Vector2i = Vector2i.ZERO
var row: int = 0
var col: int = 0
var current_health: int = 300
var max_health: int = 300
var is_dead: bool = false

# Visual nodes (3D billboard + blob shadow)
var visual_node: Billboard2D = null
var shadow_node: MeshInstance3D = null
var flash_tween: Tween = null

func _ready() -> void:
	add_to_group("plants")
	collision_layer = 1 # Layer 1: Plants
	collision_mask = 2  # Layer 2: Zombies

	if plant_data != null:
		max_health = plant_data.max_health
		current_health = max_health
		if billboard_sheet.is_empty():
			billboard_sheet = BillboardLibrary.sheet_for_plant(plant_data.id)
	if billboard_sheet.is_empty():
		billboard_sheet = "p_peashooter"

	_build_visual()
	_setup()

func _build_visual() -> void:
	visual_node = BillboardLibrary.make_billboard(billboard_sheet)
	visual_node.name = "Visual"
	visual_node.position = Vector3(0.0, 0.0, Z_NUDGE)
	add_child(visual_node)
	_refresh_shadow()

func _refresh_shadow() -> void:
	if shadow_node != null and is_instance_valid(shadow_node):
		shadow_node.queue_free()
		shadow_node = null
	shadow_node = BillboardLibrary.make_shadow_for(billboard_sheet)
	if shadow_node != null:
		shadow_node.name = "Shadow"
		add_child(shadow_node)

## Swap the billboard sprite sheet (wallnut cracks, potato arm, chomper chew...).
func set_billboard_sheet(sheet: String) -> void:
	if sheet == billboard_sheet:
		return
	billboard_sheet = sheet
	if visual_node != null:
		BillboardLibrary.apply_sheet(visual_node, sheet)

func _setup() -> void:
	# Virtual method for child classes to initialize specific logic
	pass

func take_damage(amount: int) -> void:
	if is_dead:
		return

	current_health -= amount
	health_changed.emit(current_health, max_health)
	_play_hit_flash()

	if current_health <= 0:
		die()

func _play_hit_flash() -> void:
	if visual_node == null:
		return
	if flash_tween != null and flash_tween.is_valid():
		flash_tween.kill()

	visual_node.modulate = Color(2.2, 2.2, 2.2, 1.0) # Flash bright
	flash_tween = create_tween()
	flash_tween.tween_property(visual_node, "modulate", Color.WHITE, 0.12)

func heal(amount: int) -> void:
	current_health = mini(current_health + amount, max_health)
	health_changed.emit(current_health, max_health)

func die() -> void:
	if is_dead:
		return
	is_dead = true
	# Stop colliding/eating immediately, then play the 3D death animation.
	collision_layer = 0
	collision_mask = 0
	set_deferred("monitorable", false)
	set_deferred("monitoring", false)
	plant_died.emit()
	_die()
	_play_death_visual()

func _die() -> void:
	# Virtual method for custom death effects (explosion etc.)
	pass

func _play_death_visual() -> void:
	if visual_node == null:
		queue_free()
		return

	var c: Color = visual_node.modulate
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(visual_node, "modulate", Color(c.r, c.g, c.b, 0.0), 0.3)
	# Tip over toward the ground: camera-facing billboards can't rotate, so
	# squash vertically (towards the feet anchor) while sinking slightly.
	tween.tween_property(visual_node, "scale", Vector3(1.2, 0.2, 1.2), 0.3) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	if shadow_node != null and is_instance_valid(shadow_node):
		tween.tween_property(shadow_node, "scale", Vector3.ZERO, 0.2)
	tween.chain().tween_callback(queue_free)
