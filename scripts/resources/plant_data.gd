class_name PlantData
extends Resource

enum PlantType {
	ATTACKER,
	PRODUCER,
	DEFENDER,
	EXPLOSIVE,
	SLOW,
	SPECIAL
}

@export var id: String = "peashooter"
@export var display_name: String = "Peashooter"
@export_multiline var description: String = "Shoots peas at incoming zombies."
@export var sun_cost: int = 100
@export var cooldown: float = 7.5
@export var max_health: int = 300
@export var plant_type: PlantType = PlantType.ATTACKER

# Combat properties
@export var attack_damage: int = 20
@export var attack_interval: float = 1.4
@export var projectile_speed: float = 400.0

# Producer properties
@export var sun_production_interval: float = 24.0
@export var sun_production_amount: int = 25

# Visual and scene bindings
@export var theme_color: Color = Color(0.25, 0.75, 0.3)
@export var plant_scene: PackedScene

