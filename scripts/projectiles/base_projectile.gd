class_name BaseProjectile
extends Area2D

@export var speed: float = 400.0
@export var damage: int = 20
@export var row: int = 0

var is_destroyed: bool = false

func _ready() -> void:
	collision_layer = 4 # Layer 3: Projectiles
	collision_mask = 2  # Layer 2: Zombies
	area_entered.connect(_on_area_entered)

func setup_projectile(lane: int, dmg: int = 20, spd: float = 400.0) -> void:
	row = lane
	damage = dmg
	speed = spd

func _process(delta: float) -> void:
	if is_destroyed:
		return
	
	position.x += speed * delta
	if position.x > 1350.0:
		queue_free()

func _on_area_entered(area: Area2D) -> void:
	if is_destroyed:
		return
	
	if area is BaseZombie and not area.get("is_dead"):
		if area.get("row") == row:
			_hit_zombie(area)

func _hit_zombie(zombie: BaseZombie) -> void:
	is_destroyed = true
	zombie.take_damage(damage)
	_play_splat_effect()
	queue_free()

func _play_splat_effect() -> void:
	var splat_sc: PackedScene = load("res://scenes/effects/splat_effect.tscn")
	if splat_sc != null:
		var splat: Node2D = splat_sc.instantiate()
		splat.global_position = global_position
		get_parent().add_child(splat)

