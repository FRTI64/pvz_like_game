class_name BasePlant
extends Area2D

signal health_changed(new_hp: int, max_hp: int)
signal plant_died()

@export var plant_data: PlantData

var grid_pos: Vector2i = Vector2i.ZERO
var row: int = 0
var col: int = 0
var current_health: int = 300
var max_health: int = 300
var is_dead: bool = false

# Visual nodes
var visual_node: Node2D = null
var flash_tween: Tween = null

func _ready() -> void:
	add_to_group("plants")
	collision_layer = 1 # Layer 1: Plants
	collision_mask = 2  # Layer 2: Zombies
	
	if plant_data != null:
		max_health = plant_data.max_health
		current_health = max_health
	
	# Try to find visual child or create default
	visual_node = get_node_or_null("Visual")
	_setup()

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
	
	visual_node.modulate = Color(1.8, 1.8, 1.8, 1.0) # Flash bright
	flash_tween = create_tween()
	flash_tween.tween_property(visual_node, "modulate", Color.WHITE, 0.12)

func heal(amount: int) -> void:
	current_health = mini(current_health + amount, max_health)
	health_changed.emit(current_health, max_health)

func die() -> void:
	if is_dead:
		return
	is_dead = true
	plant_died.emit()
	_die()
	queue_free()

func _die() -> void:
	# Virtual method for custom death effects
	pass

