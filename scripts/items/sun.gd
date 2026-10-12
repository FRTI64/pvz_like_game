class_name Sun
extends Area2D

@export var value: int = 25
@export var fall_speed: float = 90.0

var target_y: float = 300.0
var is_falling: bool = false
var is_collected: bool = false
var lifetime: float = 11.0
var bob_offset: float = 0.0

func _ready() -> void:
	collision_layer = 8 # Layer 4: Collectibles
	collision_mask = 0
	input_pickable = true
	input_event.connect(_on_input_event)
	EventBus.sun_spawned.emit(self)

func setup_falling(dest_y: float) -> void:
	target_y = dest_y
	is_falling = true

func setup_flower_drop(dest_pos: Vector2) -> void:
	is_falling = false
	var tween := create_tween()
	# Arc upwards then drop to target
	var mid_pos := Vector2((position.x + dest_pos.x) * 0.5, position.y - 40.0)
	tween.tween_property(self, "position", mid_pos, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "position", dest_pos, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

func _process(delta: float) -> void:
	if is_collected:
		return
	
	if is_falling:
		position.y += fall_speed * delta
		if position.y >= target_y:
			position.y = target_y
			is_falling = false
	else:
		# Gentle bobbing animation
		bob_offset += delta * 3.0
		rotation = sin(bob_offset) * 0.1
		
		lifetime -= delta
		if lifetime <= 2.0:
			# Blink before disappearing
			modulate.a = 0.4 + sin(lifetime * 16.0) * 0.4
		if lifetime <= 0.0:
			queue_free()

func _on_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if is_collected:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		collect()
	elif event is InputEventScreenTouch and event.pressed:
		collect()

func collect() -> void:
	if is_collected:
		return
	is_collected = true
	SoundManager.play_sound("sun")
	
	# Fly to Sun counter at top-left
	var hud_target := Vector2(85.0, 45.0)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "global_position", hud_target, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(self, "scale", Vector2(0.5, 0.5), 0.45)
	
	tween.chain().tween_callback(func():
		GameManager.add_sun(value)
		EventBus.sun_collected.emit(self, value)
		queue_free()
	)

