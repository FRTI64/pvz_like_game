extends Node2D

var color: Color = Color(0.2, 0.8, 0.2, 0.7)

func _draw() -> void:
	draw_circle(Vector2.ZERO, 30.0, color)
	draw_circle(Vector2.ZERO, 30.0, Color.WHITE, false, 2.0)

