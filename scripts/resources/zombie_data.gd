class_name ZombieData
extends Resource

enum ArmorType {
	NONE,
	CONE,
	BUCKET,
	SCREEN_DOOR,
	NEWSPAPER
}

@export var id: String = "normal_zombie"
@export var display_name: String = "Normal Zombie"
@export var max_health: int = 200
@export var armor_health: int = 0
@export var armor_type: ArmorType = ArmorType.NONE
@export var move_speed: float = 24.0 # Pixels per second
@export var damage_per_second: float = 100.0 # Chomps plants
@export var is_flag_bearer: bool = false

# Visual and scene bindings
@export var theme_color: Color = Color(0.45, 0.55, 0.4)
@export var zombie_scene: PackedScene

