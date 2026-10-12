class_name ExplosionEffect
extends Node2D

var lifetime: float = 0.5
var age: float = 0.0

func _process(delta: float) -> void:
	age += delta
	queue_redraw()
	if age >= lifetime:
		queue_free()

func _draw() -> void:
	var progress: float = age / lifetime
	var alpha: float = 1.0 - progress
	var radius: float = 30.0 + progress * 90.0
	
	# Blast ring
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 32, Color(1.0, 0.4, 0.1, alpha), 8.0 * (1.0 - progress))
	# Inner flash
	if progress < 0.3:
		draw_circle(Vector2.ZERO, radius * 0.6, Color(1.0, 0.9, 0.3, (0.3 - progress) * 3.0))

