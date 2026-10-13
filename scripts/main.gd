class_name Main
extends Node2D

@export var default_level: LevelData

@onready var grid_manager: GridManager = $GridManager
@onready var sun_manager: SunManager = $SunManager
@onready var wave_manager: WaveManager = $WaveManager
@onready var hud: HUD = $HUD

func _ready() -> void:
	if GameManager.selected_level_data != null:
		default_level = GameManager.selected_level_data
	elif default_level == null:
		default_level = load("res://data/levels/level_1.tres")
	
	GameManager.start_game(default_level.initial_sun)
	if sun_manager != null and default_level.natural_sun_interval > 0.0:
		sun_manager.natural_drop_interval = default_level.natural_sun_interval
	wave_manager.start_level(default_level)

func _draw() -> void:
	# Draw house patio on the left
	draw_rect(Rect2(0, 0, 260, 720), Color(0.35, 0.28, 0.22))
	# Draw patio tiles
	for y in range(0, 720, 48):
		draw_line(Vector2(0, y), Vector2(260, y), Color(0.28, 0.22, 0.16), 2.0)
	draw_line(Vector2(260, 0), Vector2(260, 720), Color(0.2, 0.15, 0.1), 4.0)
	
	# Draw right edge street / pavement
	draw_rect(Rect2(1160, 0, 120, 720), Color(0.3, 0.32, 0.35))
	for y in range(0, 720, 60):
		draw_line(Vector2(1160, y), Vector2(1280, y), Color(0.22, 0.24, 0.26), 2.0)

