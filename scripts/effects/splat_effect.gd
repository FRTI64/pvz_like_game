class_name SplatEffect
extends Node2D

var particles: Array[Dictionary] = []
var lifetime: float = 0.25
var age: float = 0.0

func _ready() -> void:
	for i in range(7):
		var angle: float = randf() * TAU
		var spd: float = randf_range(60.0, 160.0)
		particles.append({
			"pos": Vector2.ZERO,
			"vel": Vector2(cos(angle), sin(angle)) * spd,
			"radius": randf_range(2.5, 4.5),
			"color": Color(0.4, 0.85, 0.3)
		})

func _process(delta: float) -> void:
	age += delta
	for p in particles:
		p["pos"] += p["vel"] * delta
	queue_redraw()
	
	if age >= lifetime:
		queue_free()

func _draw() -> void:
	var alpha: float = 1.0 - (age / lifetime)
	for p in particles:
		var c: Color = p["color"]
		c.a = alpha
		draw_circle(p["pos"], p["radius"], c)

