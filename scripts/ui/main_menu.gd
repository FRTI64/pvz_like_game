class_name MainMenu
extends Control

@onready var btn_level_1: Button = $ContentContainer/LevelGrid/LevelCard1/StartBtn
@onready var btn_level_2: Button = $ContentContainer/LevelGrid/LevelCard2/StartBtn
@onready var btn_level_3: Button = $ContentContainer/LevelGrid/LevelCard3/StartBtn

func _ready() -> void:
	if btn_level_1 != null:
		btn_level_1.pressed.connect(func(): _start_level("res://data/levels/level_1.tres"))
	if btn_level_2 != null:
		btn_level_2.pressed.connect(func(): _start_level("res://data/levels/level_2.tres"))
	if btn_level_3 != null:
		btn_level_3.pressed.connect(func(): _start_level("res://data/levels/level_3.tres"))

func _start_level(level_path: String) -> void:
	SoundManager.play_sound("plant")
	GameManager.start_level_by_path(level_path)

func _draw() -> void:
	# Stylized lawn checkerboard background
	for x in range(0, 1280, 80):
		for y in range(0, 720, 80):
			var is_even: bool = ((x / 80) + (y / 80)) % 2 == 0
			var col: Color = Color(0.14, 0.22, 0.12) if is_even else Color(0.12, 0.18, 0.10)
			draw_rect(Rect2(x, y, 80, 80), col)
	
	# Top banner shadow
	draw_rect(Rect2(0, 0, 1280, 140), Color(0.08, 0.13, 0.07, 0.88))
	draw_line(Vector2(0, 140), Vector2(1280, 140), Color(0.35, 0.55, 0.25, 0.9), 3.0)
	
	# Bottom bar
	draw_rect(Rect2(0, 672, 1280, 48), Color(0.08, 0.13, 0.07, 0.88))
	draw_line(Vector2(0, 672), Vector2(1280, 672), Color(0.25, 0.42, 0.18, 0.7), 2.0)

