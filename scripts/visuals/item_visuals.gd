class_name ItemVisual
extends Node2D

@export_enum("sun", "pea", "snow_pea", "lawnmower", "splat", "explosion") var item_kind: String = "sun"

var anim_phase: float = 0.0

func _process(delta: float) -> void:
	anim_phase += delta * 3.0
	queue_redraw()

func _draw() -> void:
	match item_kind:
		"sun":
			_draw_sun()
		"pea":
			_draw_pea()
		"snow_pea":
			_draw_snow_pea()
		"lawnmower":
			_draw_lawnmower()

func _draw_sun() -> void:
	# Rotating ray points
	var rays: int = 12
	for i in range(rays):
		var angle: float = (float(i) / float(rays)) * TAU + anim_phase * 0.4
		var pt := Vector2(cos(angle) * 26.0, sin(angle) * 26.0)
		draw_circle(pt, 6.0, Color(1.0, 0.85, 0.1))
	# Inner glowing sphere
	draw_circle(Vector2.ZERO, 20.0, Color(1.0, 0.95, 0.25))
	draw_circle(Vector2(-5, -5), 6.0, Color(1.0, 1.0, 0.7))

func _draw_pea() -> void:
	draw_circle(Vector2.ZERO, 9.0, Color(0.28, 0.78, 0.25))
	draw_circle(Vector2(-3, -3), 3.0, Color(0.65, 0.95, 0.55))

func _draw_snow_pea() -> void:
	draw_circle(Vector2.ZERO, 9.0, Color(0.35, 0.8, 1.0))
	draw_circle(Vector2(-3, -3), 3.5, Color.WHITE)

func _draw_lawnmower() -> void:
	# Red metal base
	draw_rect(Rect2(-24, -14, 48, 28), Color(0.85, 0.2, 0.2), true)
	# Engine box
	draw_rect(Rect2(-12, -22, 24, 10), Color(0.25, 0.25, 0.25), true)
	# Wheels
	draw_circle(Vector2(-18, 14), 7.0, Color(0.15, 0.15, 0.15))
	draw_circle(Vector2(18, 14), 7.0, Color(0.15, 0.15, 0.15))
	# Handle
	draw_line(Vector2(-20, -10), Vector2(-36, -30), Color(0.5, 0.5, 0.5), 3.5)

