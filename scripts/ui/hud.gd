class_name HUD
extends CanvasLayer

@onready var sun_label: Label = $SunBox/SunLabel
@onready var deck_container: HBoxContainer = $CardDeck/HBoxContainer
@onready var announcement_label: Label = $AnnouncementBanner/Label
@onready var announcement_banner: Control = $AnnouncementBanner
@onready var progress_bar: ProgressBar = $WaveProgress/ProgressBar
@onready var game_over_panel: Control = $GameOverPanel
@onready var victory_panel: Control = $VictoryPanel
@onready var pause_menu_panel: Control = $PauseMenuPanel
@onready var menu_btn: Button = $MenuButton

var seed_packet_scene: PackedScene

func _ready() -> void:
	seed_packet_scene = load("res://scenes/ui/seed_packet.tscn")
	
	EventBus.sun_amount_changed.connect(_on_sun_changed)
	EventBus.level_started.connect(_on_level_started)
	EventBus.wave_started.connect(_on_wave_started)
	EventBus.huge_wave_warning.connect(_on_huge_wave_warning)
	EventBus.game_over.connect(_on_game_over)
	
	announcement_banner.visible = false
	game_over_panel.visible = false
	victory_panel.visible = false
	if pause_menu_panel != null:
		pause_menu_panel.visible = false
	
	_update_sun_display(GameManager.current_sun)

func _update_sun_display(amount: int) -> void:
	if sun_label != null:
		sun_label.text = str(amount)

func _on_sun_changed(new_amount: int, delta: int) -> void:
	_update_sun_display(new_amount)
	if delta > 0 and sun_label != null:
		var tween := create_tween()
		tween.tween_property(sun_label, "scale", Vector2(1.25, 1.25), 0.08)
		tween.tween_property(sun_label, "scale", Vector2(1.0, 1.0), 0.1)

func _on_level_started(lvl_data: LevelData) -> void:
	# Clear deck
	for child in deck_container.get_children():
		child.queue_free()
	
	# Instantiate seed packets
	for p_data in lvl_data.available_plants:
		if seed_packet_scene != null:
			var packet := seed_packet_scene.instantiate() as SeedPacket
			deck_container.add_child(packet)
			packet.setup_packet(p_data)
	
	if progress_bar != null:
		progress_bar.max_value = float(lvl_data.waves.size())
		progress_bar.value = 0.0

func _on_wave_started(wave_idx: int, total_waves: int, _is_huge: bool) -> void:
	if progress_bar != null:
		progress_bar.max_value = float(total_waves)
		var tween := create_tween()
		tween.tween_property(progress_bar, "value", float(wave_idx + 1), 1.0)

func _on_huge_wave_warning() -> void:
	announcement_banner.visible = true
	announcement_label.text = "A Huge Wave of Zombies is Approaching!"
	announcement_banner.modulate.a = 0.0
	
	var tween := create_tween()
	tween.tween_property(announcement_banner, "modulate:a", 1.0, 0.3)
	tween.tween_interval(2.0)
	tween.tween_property(announcement_banner, "modulate:a", 0.0, 0.4)
	tween.tween_callback(func(): announcement_banner.visible = false)

func _on_game_over(won: bool) -> void:
	if won:
		victory_panel.visible = true
		victory_panel.modulate.a = 0.0
		var tween := create_tween()
		tween.tween_property(victory_panel, "modulate:a", 1.0, 0.5)
	else:
		game_over_panel.visible = true
		game_over_panel.modulate.a = 0.0
		var tween := create_tween()
		tween.tween_property(game_over_panel, "modulate:a", 1.0, 0.5)

func _on_restart_button_pressed() -> void:
	get_tree().paused = false
	EventBus.restart_requested.emit()

func _on_menu_button_pressed() -> void:
	if pause_menu_panel != null:
		var will_be_open: bool = not pause_menu_panel.visible
		pause_menu_panel.visible = will_be_open
		get_tree().paused = will_be_open

func _on_resume_button_pressed() -> void:
	if pause_menu_panel != null:
		pause_menu_panel.visible = false
	get_tree().paused = false

func _on_main_menu_button_pressed() -> void:
	get_tree().paused = false
	EventBus.return_to_main_menu_requested.emit()

