class_name ZombieVisual
extends Node2D

@export_enum("normal", "conehead", "buckethead", "flag") var zombie_type: String = "normal"

var walk_cycle: float = 0.0

func _ready() -> void:
	walk_cycle = randf() * 10.0

func _process(delta: float) -> void:
	walk_cycle += delta * 5.0
	queue_redraw()

func _draw() -> void:
	var leg_swing: float = sin(walk_cycle) * 12.0
	var head_bob: float = absf(sin(walk_cycle)) * 3.0
	
	# Legs (blue trousers)
	draw_line(Vector2(-6, 20), Vector2(-6 + leg_swing, 44), Color(0.25, 0.3, 0.45), 6.0)
	draw_line(Vector2(6, 20), Vector2(6 - leg_swing, 44), Color(0.2, 0.25, 0.4), 6.0)
	# Shoes
	draw_circle(Vector2(-6 + leg_swing, 46), 4.0, Color(0.15, 0.1, 0.1))
	draw_circle(Vector2(6 - leg_swing, 46), 4.0, Color(0.15, 0.1, 0.1))
	
	# Body / Coat (Brown)
	draw_rect(Rect2(-12, 0 + head_bob, 24, 24), Color(0.42, 0.35, 0.25), true)
	# Tie (Red)
	draw_line(Vector2(0, 4 + head_bob), Vector2(0, 16 + head_bob), Color(0.8, 0.15, 0.15), 3.0)
	
	# Arm stretching forward
	draw_line(Vector2(-8, 6 + head_bob), Vector2(-28, 4 + head_bob + sin(walk_cycle) * 4.0), Color(0.42, 0.35, 0.25), 5.0)
	draw_circle(Vector2(-30, 4 + head_bob + sin(walk_cycle) * 4.0), 4.0, Color(0.52, 0.65, 0.48)) # Green hand
	
	# Head (Sickly green-gray)
	var head_center := Vector2(0, -18 + head_bob)
	draw_circle(head_center, 18.0, Color(0.55, 0.68, 0.5))
	
	# Open mouth
	draw_arc(head_center + Vector2(-6, 8), 6.0, 0.0, PI, 6, Color(0.2, 0.1, 0.1), 3.0)
	
	# Lazy bulging eyes
	draw_circle(head_center + Vector2(-6, -2), 6.0, Color(0.95, 0.95, 0.85))
	draw_circle(head_center + Vector2(-8, -2), 2.5, Color.BLACK)
	draw_circle(head_center + Vector2(4, -4), 5.0, Color(0.95, 0.95, 0.85))
	draw_circle(head_center + Vector2(2, -4), 2.0, Color.BLACK)
	
	# Hat / Armor
	match zombie_type:
		"conehead":
			_draw_cone(head_center)
		"buckethead":
			_draw_bucket(head_center)
		"flag":
			_draw_flag(head_center)

func _draw_cone(head_pos: Vector2) -> void:
	# Orange traffic cone
	var cone_points := PackedVector2Array([
		head_pos + Vector2(0, -38),
		head_pos + Vector2(14, -10),
		head_pos + Vector2(-14, -10)
	])
	draw_polygon(cone_points, [Color(0.95, 0.45, 0.1)])
	# White reflective stripe
	draw_line(head_pos + Vector2(-8, -22), head_pos + Vector2(8, -22), Color.WHITE, 4.0)

func _draw_bucket(head_pos: Vector2) -> void:
	# Metal bucket
	var bucket_points := PackedVector2Array([
		head_pos + Vector2(-15, -34),
		head_pos + Vector2(15, -34),
		head_pos + Vector2(13, -10),
		head_pos + Vector2(-13, -10)
	])
	draw_polygon(bucket_points, [Color(0.7, 0.72, 0.75)])
	draw_line(head_pos + Vector2(-15, -34), head_pos + Vector2(15, -34), Color(0.5, 0.52, 0.55), 3.0)

func _draw_flag(_head_pos: Vector2) -> void:
	# Flag pole
	draw_line(Vector2(14, 28), Vector2(14, -42), Color(0.6, 0.4, 0.2), 3.0)
	# Red flag cloth
	var flag_points := PackedVector2Array([
		Vector2(14, -42),
		Vector2(38, -32),
		Vector2(14, -22)
	])
	draw_polygon(flag_points, [Color(0.85, 0.2, 0.2)])

