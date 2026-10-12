extends Node

enum GameState {
	READY,
	PLAYING,
	PAUSED,
	GAME_OVER,
	VICTORY
}

var current_state: GameState = GameState.READY
var selected_plant_data: PlantData = null
var is_shovel_active: bool = false
var current_sun: int = 150

func _ready() -> void:
	EventBus.plant_card_selected.connect(_on_plant_card_selected)
	EventBus.plant_card_deselected.connect(_on_plant_card_deselected)
	EventBus.shovel_toggled.connect(_on_shovel_toggled)
	EventBus.sun_amount_changed.connect(_on_sun_changed)
	EventBus.game_over.connect(_on_game_over)
	EventBus.restart_requested.connect(_on_restart_requested)

func start_game(initial_sun_val: int = 150) -> void:
	current_state = GameState.PLAYING
	current_sun = initial_sun_val
	selected_plant_data = null
	is_shovel_active = false
	EventBus.sun_amount_changed.emit(current_sun, 0)

func select_plant(plant_data: PlantData) -> void:
	if is_shovel_active:
		set_shovel_active(false)
	selected_plant_data = plant_data
	EventBus.plant_card_selected.emit(plant_data)

func deselect_plant() -> void:
	selected_plant_data = null
	EventBus.plant_card_deselected.emit()

func set_shovel_active(active: bool) -> void:
	if active and selected_plant_data != null:
		deselect_plant()
	is_shovel_active = active
	EventBus.shovel_toggled.emit(active)

func can_afford(cost: int) -> bool:
	return current_sun >= cost

func spend_sun(cost: int) -> bool:
	if can_afford(cost):
		current_sun -= cost
		EventBus.sun_amount_changed.emit(current_sun, -cost)
		return true
	return false

func add_sun(amount: int) -> void:
	current_sun += amount
	EventBus.sun_amount_changed.emit(current_sun, amount)

func _on_plant_card_selected(plant_data: PlantData) -> void:
	selected_plant_data = plant_data

func _on_plant_card_deselected() -> void:
	selected_plant_data = null

func _on_shovel_toggled(active: bool) -> void:
	is_shovel_active = active

func _on_sun_changed(new_amount: int, _delta: int) -> void:
	current_sun = new_amount

func _on_game_over(won: bool) -> void:
	current_state = GameState.VICTORY if won else GameState.GAME_OVER
	if won:
		SoundManager.play_sound("win")
	else:
		SoundManager.play_sound("lose")

func _on_restart_requested() -> void:
	get_tree().reload_current_scene()

