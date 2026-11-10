class_name BaseProjectile
extends Area3D
## Pea / snow pea projectile.
##
## The entity root is a floating point: its position is the 3D point where the
## sprite center should be (flight height ~50 game px), see spec §3.3. Gameplay
## movement is still pixel based and happens on the root's x axis.

const Z_NUDGE: float = 4.0
const GROUND_SHADOW_Y: float = 0.8

@export var speed: float = 400.0
@export var damage: int = 20
@export var row: int = 0
@export var billboard_sheet: String = "i_pea"

var is_destroyed: bool = false
var visual_node: Billboard2D = null
var shadow_node: MeshInstance3D = null

func _ready() -> void:
	collision_layer = 4 # Layer 3: Projectiles
	collision_mask = 2  # Layer 2: Zombies

	visual_node = BillboardLibrary.make_billboard(billboard_sheet)
	visual_node.name = "Visual"
	visual_node.position = Vector3(0.0, 0.0, Z_NUDGE)
	add_child(visual_node)

	# Floating items get a faint ground blob shadow placed under the flight
	# point: counter the root's flight height so the quad lies on the lawn.
	shadow_node = BillboardLibrary.make_shadow_for(billboard_sheet)
	if shadow_node != null:
		shadow_node.name = "Shadow"
		shadow_node.position = Vector3(0.0, GROUND_SHADOW_Y - position.y, Z_NUDGE)
		_fade_shadow(shadow_node)
		add_child(shadow_node)

	area_entered.connect(_on_area_entered)

func _fade_shadow(mesh: MeshInstance3D) -> void:
	# Floating-item shadows are fainter than ground-unit ones.
	var quad := mesh.mesh as QuadMesh
	if quad == null:
		return
	var mat := quad.material as StandardMaterial3D
	if mat != null:
		mat.albedo_color = Color(0.0, 0.0, 0.0, 0.6)

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

func _on_area_entered(area: Area3D) -> void:
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
		var splat: Node3D = splat_sc.instantiate()
		get_parent().add_child(splat)
		splat.position = position
