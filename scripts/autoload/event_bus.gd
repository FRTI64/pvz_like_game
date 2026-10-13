extends Node

# --- Sun Economy Signals ---
signal sun_amount_changed(new_amount: int, delta: int)
signal sun_spawned(sun_node: Node2D)
signal sun_collected(sun_node: Node2D, amount: int)

# --- Plant Selection & Placement Signals ---
signal plant_card_selected(plant_data: PlantData)
signal plant_card_deselected()
signal plant_placed(grid_pos: Vector2i, plant: Node2D)
signal plant_removed(grid_pos: Vector2i, plant: Node2D)
signal shovel_toggled(active: bool)

# --- Zombie & Combat Signals ---
signal zombie_spawned(zombie: Node2D)
signal zombie_died(zombie: Node2D)
signal zombie_reached_house(row: int)
signal lawn_mower_triggered(row: int)

# --- Wave & Level Signals ---
signal level_started(level_data: LevelData)
signal wave_started(wave_index: int, total_waves: int, is_huge: bool)
signal wave_completed(wave_index: int)
signal huge_wave_warning()
signal final_wave_warning()

# --- Game State Signals ---
signal game_paused_toggled(is_paused: bool)
signal game_over(won: bool)
signal restart_requested()
signal return_to_main_menu_requested()

