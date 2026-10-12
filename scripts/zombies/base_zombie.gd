class_name BaseZombie
extends Area2D

signal zombie_damaged(current_hp: int, max_hp: int)
signal zombie_died()

enum State {
	WALKING,
	EATING,
	DYING
}

@export var zombie_data: ZombieData

var row: int = 0
var current_health: int = 200
var max_health: int = 200
var armor_health: int = 0
var max_armor_health: int = 0
var base_speed: float = 24.0
var damage_rate: float = 100.0 # Damage per second to plants

var current_state: State = State.WALKING
var is_dead: bool = false
var eating_target: BasePlant = null
var eat_damage_timer: float = 0.0

# Chilled / Slow debuff
var is_chilled: bool = false
var chill_timer: float = 0.0
const CHILL_SPEED_MULTIPLIER: float = 0.5

var visual_node: Node2D = null

func _ready() -> void:
	add_to_group("zombies")
	collision_layer = 2 # Layer 2: Zombies
	collision_mask = 1  # Layer 1: Plants
	
	visual_node = get_node_or_null("Visual")
	
	if zombie_data != null:
		setup_zombie(zombie_data, row)
	
	area_entered.connect(_on_area_entered)
	area_exited.connect(_on_area_exited)

func setup_zombie(data: ZombieData, lane_idx: int) -> void:
	zombie_data = data
	row = lane_idx
	max_health = data.max_health
	current_health = max_health
	max_armor_health = data.armor_health
	armor_health = max_armor_health
	base_speed = data.move_speed
	damage_rate = data.damage_per_second

func _process(delta: float) -> void:
	if is_dead:
		return
	
	_update_chill_status(delta)
	
	match current_state:
		State.WALKING:
			_process_walking(delta)
		State.EATING:
			_process_eating(delta)
		State.DYING:
			pass

func _update_chill_status(delta: float) -> void:
	if is_chilled:
		chill_timer -= delta
		if chill_timer <= 0.0:
			is_chilled = false
			if visual_node != null:
				visual_node.modulate = Color.WHITE

func apply_chill(duration: float = 5.0) -> void:
	is_chilled = true
	chill_timer = maxf(chill_timer, duration)
	if visual_node != null:
		visual_node.modulate = Color(0.4, 0.7, 1.0, 1.0) # Frosty blue tint

func _process_walking(delta: float) -> void:
	var speed: float = base_speed * (CHILL_SPEED_MULTIPLIER if is_chilled else 1.0)
	position.x -= speed * delta
	
	# House reach check (Game Over threshold)
	if position.x < 180.0:
		EventBus.zombie_reached_house.emit(row)
		EventBus.game_over.emit(false) # Game Over!

func _process_eating(delta: float) -> void:
	# If target is invalid or dead, resume walking
	if eating_target == null or not is_instance_valid(eating_target) or eating_target.get("is_dead"):
		eating_target = null
		current_state = State.WALKING
		return
	
	eat_damage_timer -= delta
	if eat_damage_timer <= 0.0:
		var dps_mult: float = 0.5 if is_chilled else 1.0
		var damage_tick: int = int(damage_rate * 0.5 * dps_mult)
		eating_target.take_damage(damage_tick)
		SoundManager.play_sound("chomp")
		eat_damage_timer = 0.5
		
		# Chomping animation
		if visual_node != null:
			var tween := create_tween()
			tween.tween_property(visual_node, "position:x", -6.0, 0.08)
			tween.tween_property(visual_node, "position:x", 0.0, 0.08)

func take_damage(amount: int, is_instant_kill: bool = false) -> void:
	if is_dead:
		return
	
	if is_instant_kill:
		die(true)
		return
	
	SoundManager.play_sound("splat")
	_play_hit_flash()
	
	# Armor takes damage first
	if armor_health > 0:
		armor_health -= amount
		if armor_health <= 0:
			var leftover: int = absi(armor_health)
			armor_health = 0
			_on_armor_broken()
			current_health -= leftover
	else:
		current_health -= amount
	
	zombie_damaged.emit(current_health, max_health)
	
	if current_health <= 0:
		die(false)

func _play_hit_flash() -> void:
	if visual_node == null:
		return
	var orig_color: Color = visual_node.modulate
	visual_node.modulate = Color(1.8, 1.8, 1.8, 1.0)
	var tween := create_tween()
	var return_color: Color = Color(0.4, 0.7, 1.0, 1.0) if is_chilled else Color.WHITE
	tween.tween_property(visual_node, "modulate", return_color, 0.1)

func _on_armor_broken() -> void:
	# Virtual method for conehead / buckethead to drop armor visually
	pass

func die(_was_instant_kill: bool = false) -> void:
	if is_dead:
		return
	is_dead = true
	current_state = State.DYING
	zombie_died.emit()
	EventBus.zombie_died.emit(self)
	
	# Death animation (head pop or fall over + fade)
	if visual_node != null:
		var tween := create_tween()
		tween.tween_property(visual_node, "modulate:a", 0.0, 0.4)
		tween.tween_callback(queue_free)
	else:
		queue_free()

func _on_area_entered(area: Area2D) -> void:
	if is_dead:
		return
	if area is BasePlant and not area.get("is_dead"):
		# Check if plant is in the same row
		if area.get("row") == row:
			eating_target = area
			current_state = State.EATING
			eat_damage_timer = 0.2

func _on_area_exited(area: Area2D) -> void:
	if area == eating_target:
		eating_target = null
		if current_state == State.EATING:
			current_state = State.WALKING

