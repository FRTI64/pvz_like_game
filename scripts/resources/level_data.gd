class_name LevelData
extends Resource

@export var level_id: int = 1
@export var level_name: String = "Day Level 1"
@export var initial_sun: int = 150
@export var natural_sun_interval: float = 8.0 # Seconds between falling suns
@export var initial_delay: float = 12.0 # Preparation time before wave 1

# List of available plant types for this level
@export var available_plants: Array[PlantData] = []

# Wave data: Array of wave dictionaries
# Each entry: { "delay": float, "is_huge": bool, "spawns": [ { "zombie": ZombieData, "lane": int, "offset": float } ] }
@export var waves: Array[Dictionary] = []

