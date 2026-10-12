class_name PlantVisual
extends Node2D

@export_enum("peashooter", "sunflower", "wallnut", "cherry_bomb", "snow_pea", "potato_mine", "repeater", "chomper") var plant_kind: String = "peashooter"

var crack_stage: int = 0
var is_armed: bool = false
var is_chewing: bool = false
var anim_phase: float = 0.0

func _ready() -> void:
	anim_phase = randf() * 10.0

func _process(delta: float) -> void:
	anim_phase += delta * 4.0
	queue_redraw()

func set_crack_stage(stage: int) -> void:
	crack_stage = stage
	queue_redraw()

func set_armed(armed: bool) -> void:
	is_armed = armed
	queue_redraw()

func set_chewing(chewing: bool) -> void:
	is_chewing = chewing
	queue_redraw()

func _draw() -> void:
	match plant_kind:
		"peashooter":
			_draw_peashooter()
		"sunflower":
			_draw_sunflower()
		"wallnut":
			_draw_wallnut()
		"cherry_bomb":
			_draw_cherry_bomb()
		"snow_pea":
			_draw_snow_pea()
		"potato_mine":
			_draw_potato_mine()
		"repeater":
			_draw_repeater()
		"chomper":
			_draw_chomper()

func _draw_peashooter() -> void:
	var sway: float = sin(anim_phase) * 2.0
	# Stem
	draw_line(Vector2(0, 32), Vector2(sway, 0), Color(0.2, 0.6, 0.25), 6.0)
	# Base leaves
	draw_circle(Vector2(-16, 28), 10.0, Color(0.18, 0.55, 0.22))
	draw_circle(Vector2(16, 28), 10.0, Color(0.18, 0.55, 0.22))
	# Head
	draw_circle(Vector2(sway, -2), 22.0, Color(0.32, 0.78, 0.35))
	# Snout
	draw_rect(Rect2(sway + 10, -10, 16, 16), Color(0.28, 0.7, 0.3), true)
	draw_circle(Vector2(sway + 26, -2), 8.0, Color(0.2, 0.5, 0.2))
	# Eye
	draw_circle(Vector2(sway + 4, -8), 6.0, Color.BLACK)
	draw_circle(Vector2(sway + 6, -9), 2.0, Color.WHITE)
	# Rear leaf
	draw_circle(Vector2(sway - 22, 0), 7.0, Color(0.25, 0.65, 0.28))

func _draw_sunflower() -> void:
	var bob: float = sin(anim_phase) * 1.5
	# Stem
	draw_line(Vector2(0, 32), Vector2(0, bob), Color(0.2, 0.6, 0.25), 6.0)
	draw_circle(Vector2(-14, 26), 9.0, Color(0.18, 0.55, 0.22))
	draw_circle(Vector2(14, 26), 9.0, Color(0.18, 0.55, 0.22))
	# Petals radiating
	var petal_count: int = 12
	for i in range(petal_count):
		var angle: float = (float(i) / float(petal_count)) * TAU
		var p_pos := Vector2(cos(angle) * 23.0, sin(angle) * 23.0 + bob)
		draw_circle(p_pos, 8.0, Color(0.98, 0.82, 0.15))
	# Center face
	draw_circle(Vector2(0, bob), 18.0, Color(0.65, 0.42, 0.18))
	# Eyes
	draw_circle(Vector2(-6, -4 + bob), 4.0, Color.BLACK)
	draw_circle(Vector2(6, -4 + bob), 4.0, Color.BLACK)
	draw_circle(Vector2(-5, -5 + bob), 1.5, Color.WHITE)
	draw_circle(Vector2(7, -5 + bob), 1.5, Color.WHITE)
	# Smile
	draw_arc(Vector2(0, 3 + bob), 7.0, 0.2, PI - 0.2, 8, Color(0.3, 0.18, 0.08), 2.0)

func _draw_wallnut() -> void:
	var wobble: float = sin(anim_phase * 0.5) * 0.8
	# Rounded body
	draw_circle(Vector2(wobble, -6), 24.0, Color(0.68, 0.48, 0.26))
	draw_circle(Vector2(wobble, 10), 22.0, Color(0.68, 0.48, 0.26))
	# Eyes
	draw_circle(Vector2(wobble + 6, -10), 5.5, Color.BLACK)
	draw_circle(Vector2(wobble + 6, -11), 1.8, Color.WHITE)
	draw_circle(Vector2(wobble + 14, -10), 5.0, Color.BLACK)
	draw_circle(Vector2(wobble + 14, -11), 1.6, Color.WHITE)
	# Cracks
	if crack_stage >= 1:
		draw_line(Vector2(wobble - 12, -18), Vector2(wobble - 6, -6), Color(0.35, 0.22, 0.1), 2.5)
		draw_line(Vector2(wobble - 6, -6), Vector2(wobble - 14, 4), Color(0.35, 0.22, 0.1), 2.0)
	if crack_stage >= 2:
		draw_line(Vector2(wobble + 4, 2), Vector2(wobble + 12, 16), Color(0.35, 0.22, 0.1), 3.0)
		draw_line(Vector2(wobble - 4, 12), Vector2(wobble + 4, 20), Color(0.35, 0.22, 0.1), 2.5)

func _draw_cherry_bomb() -> void:
	var pulse: float = sin(anim_phase * 2.0) * 1.5
	# Green stem connecting
	draw_line(Vector2(-14, 0), Vector2(0, -26), Color(0.2, 0.55, 0.2), 3.5)
	draw_line(Vector2(14, 0), Vector2(0, -26), Color(0.2, 0.55, 0.2), 3.5)
	# Spark on top
	draw_circle(Vector2(0, -28), 4.0 + pulse, Color(1.0, 0.8, 0.1))
	# Left Cherry
	draw_circle(Vector2(-14, 6), 16.0, Color(0.85, 0.15, 0.18))
	draw_circle(Vector2(-18, 3), 4.0, Color.BLACK)
	draw_circle(Vector2(-10, 3), 4.0, Color.BLACK)
	# Right Cherry
	draw_circle(Vector2(14, 6), 16.0, Color(0.85, 0.15, 0.18))
	draw_circle(Vector2(10, 3), 4.0, Color.BLACK)
	draw_circle(Vector2(18, 3), 4.0, Color.BLACK)

func _draw_snow_pea() -> void:
	var sway: float = sin(anim_phase) * 2.0
	# Stem
	draw_line(Vector2(0, 32), Vector2(sway, 0), Color(0.2, 0.6, 0.25), 6.0)
	# Base leaves
	draw_circle(Vector2(-16, 28), 10.0, Color(0.18, 0.55, 0.22))
	draw_circle(Vector2(16, 28), 10.0, Color(0.18, 0.55, 0.22))
	# Frosty head
	draw_circle(Vector2(sway, -2), 22.0, Color(0.35, 0.78, 0.95))
	# Snout
	draw_rect(Rect2(sway + 10, -10, 16, 16), Color(0.25, 0.68, 0.88), true)
	draw_circle(Vector2(sway + 26, -2), 8.0, Color(0.18, 0.52, 0.75))
	# Ice crystals at back
	draw_polygon(PackedVector2Array([Vector2(sway - 22, -6), Vector2(sway - 34, -14), Vector2(sway - 22, 2)]), [Color(0.8, 0.95, 1.0)])
	draw_polygon(PackedVector2Array([Vector2(sway - 22, 4), Vector2(sway - 32, 10), Vector2(sway - 18, 12)]), [Color(0.8, 0.95, 1.0)])
	# Eye
	draw_circle(Vector2(sway + 4, -8), 6.0, Color.BLACK)
	draw_circle(Vector2(sway + 6, -9), 2.0, Color.WHITE)

func _draw_potato_mine() -> void:
	if not is_armed:
		# Mound of dirt
		draw_arc(Vector2(0, 20), 18.0, PI, TAU, 16, Color(0.5, 0.35, 0.2), 8.0, true)
		# Antenna with blinking red light
		var blink: Color = Color.RED if int(anim_phase * 2.0) % 2 == 0 else Color(0.4, 0.1, 0.1)
		draw_line(Vector2(0, 12), Vector2(0, -6), Color.GRAY, 2.5)
		draw_circle(Vector2(0, -8), 4.5, blink)
	else:
		# Armed potato face popped up
		draw_circle(Vector2(0, 8), 18.0, Color(0.72, 0.55, 0.32))
		# Big open eyes
		draw_circle(Vector2(-6, 2), 5.5, Color.BLACK)
		draw_circle(Vector2(6, 2), 5.5, Color.BLACK)
		draw_circle(Vector2(-5, 0), 2.0, Color.WHITE)
		draw_circle(Vector2(7, 0), 2.0, Color.WHITE)

func _draw_repeater() -> void:
	var sway: float = sin(anim_phase) * 2.0
	# Stem
	draw_line(Vector2(0, 32), Vector2(sway, 0), Color(0.18, 0.5, 0.2), 6.0)
	draw_circle(Vector2(-16, 28), 10.0, Color(0.15, 0.45, 0.18))
	draw_circle(Vector2(16, 28), 10.0, Color(0.15, 0.45, 0.18))
	# Head (darker green)
	draw_circle(Vector2(sway, -2), 22.0, Color(0.24, 0.65, 0.28))
	# Elongated double snout
	draw_rect(Rect2(sway + 10, -11, 20, 18), Color(0.2, 0.55, 0.24), true)
	draw_circle(Vector2(sway + 30, -2), 8.5, Color(0.15, 0.42, 0.18))
	# Double rear leaves
	draw_circle(Vector2(sway - 24, -6), 8.0, Color(0.2, 0.55, 0.24))
	draw_circle(Vector2(sway - 22, 6), 7.0, Color(0.2, 0.55, 0.24))
	# Eye
	draw_circle(Vector2(sway + 4, -8), 6.0, Color.BLACK)
	draw_circle(Vector2(sway + 6, -9), 2.0, Color.WHITE)

func _draw_chomper() -> void:
	var bite_bob: float = sin(anim_phase) * 2.0
	# Thick vine stem
	draw_line(Vector2(0, 32), Vector2(0, 4), Color(0.3, 0.55, 0.2), 8.0)
	if is_chewing:
		# Chewing closed mouth with swollen cheeks
		draw_circle(Vector2(0, -6 + bite_bob), 24.0, Color(0.6, 0.2, 0.65))
		draw_circle(Vector2(-6, -10 + bite_bob), 4.0, Color.BLACK)
		draw_circle(Vector2(6, -10 + bite_bob), 4.0, Color.BLACK)
	else:
		# Open toothy Venus flytrap jaws
		draw_circle(Vector2(0, -6 + bite_bob), 22.0, Color(0.65, 0.22, 0.7))
		# Red mouth cavity
		draw_circle(Vector2(6, -6 + bite_bob), 14.0, Color(0.85, 0.25, 0.35))
		# White sharp teeth
		draw_polygon(PackedVector2Array([Vector2(8, -18 + bite_bob), Vector2(14, -12 + bite_bob), Vector2(4, -12 + bite_bob)]), [Color.WHITE])
		draw_polygon(PackedVector2Array([Vector2(14, 4 + bite_bob), Vector2(18, -4 + bite_bob), Vector2(8, -2 + bite_bob)]), [Color.WHITE])

