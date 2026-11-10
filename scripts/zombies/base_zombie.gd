class_name BaseZombie
extends Area3D

signal zombie_damaged(current_hp: int, max_hp: int)
signal zombie_died()

enum State {
	WALKING,
	EATING,
	DYING
}

## Sprites are nudged slightly toward the camera so they sort in front of plants
## standing in the same lane (spec §3.3). Gameplay position is NOT changed.
const Z_NUDGE: float = 2.0
## Chilled tint (spec §3.2)
const CHILL_TINT: Color = Color(0.55, 0.8, 1.25, 1.0)
const FLASH_TINT: Color = Color(2.2, 2.2, 2.2, 1.0)

@export var zombie_data: ZombieData
@export var billboard_sheet: String = ""

var row: int = 0
var current_health: int = 200
var max_health: int = 200
var armor_health: int = 0
var max_armor_health: int = 0
var base_speed: float = 24.0
var damage_rate: float = 100.0 # Damage per second to plants

var current_state: State = State.WALKING
var is_dead: bool = false
var eating_target: BasePlant = null
var eat_damage_timer: float = 0.0
var flash_tween: Tween = null
var eat_tween: Tween = null

# Chilled / Slow debuff
var is_chilled: bool = false
var chill_timer: float = 0.0
const CHILL_SPEED_MULTIPLIER: float = 0.5

# 3D visual nodes
var visual_node: Billboard2D = null
var shadow_node: MeshInstance3D = null

func _ready() -> void:
	add_to_group("zombies")
	collision_layer = 2 # Layer 2: Zombies
	collision_mask = 1  # Layer 1: Plants

	if billboard_sheet.is_empty():
		if zombie_data != null:
			billboard_sheet = BillboardLibrary.sheet_for_zombie(zombie_data.id)
		else:
			billboard_sheet = "z_normal"

	_build_visual()

	if zombie_data != null:
		setup_zombie(zombie_data, row)

	area_entered.connect(_on_area_entered)
	area_exited.connect(_on_area_exited)

func _build_visual() -> void:
	visual_node = BillboardLibrary.make_billboard(billboard_sheet)
	visual_node.name = "Visual"
	visual_node.position = Vector3(0.0, 0.0, Z_NUDGE)
	add_child(visual_node)
	_refresh_shadow()

func _refresh_shadow() -> void:
	if shadow_node != null and is_instance_valid(shadow_node):
		shadow_node.queue_free()
		shadow_node = null
	shadow_node = BillboardLibrary.make_shadow_for(billboard_sheet)
	if shadow_node != null:
		shadow_node.name = "Shadow"
		add_child(shadow_node)

## Swap billboard sheet (armor break: z_conehead / z_buckethead -> z_normal).
func set_billboard_sheet(sheet: String) -> void:
	if sheet == billboard_sheet:
		return
	billboard_sheet = sheet
	if visual_node != null:
		BillboardLibrary.apply_sheet(visual_node, sheet)
		visual_node.modulate = _base_tint()

func setup_zombie(data: ZombieData, lane_idx: int) -> void:
	zombie_data = data
	row = lane_idx
	max_health = data.max_health
	current_health = max_health
	max_armor_health = data.armor_health
	armor_health = max_armor_health
	base_speed = data.move_speed
	damage_rate = data.damage_per_second

func _process(delta: float) -> void:
	if is_dead:
		return

	_update_chill_status(delta)

	match current_state:
		State.WALKING:
			_process_walking(delta)
		State.EATING:
			_process_eating(delta)
		State.DYING:
			pass

func _update_chill_status(delta: float) -> void:
	if is_chilled:
		chill_timer -= delta
		if chill_timer <= 0.0:
			is_chilled = false
			if visual_node != null:
				visual_node.modulate = Color.WHITE

func apply_chill(duration: float = 5.0) -> void:
	is_chilled = true
	chill_timer = maxf(chill_timer, duration)
	if visual_node != null:
		visual_node.modulate = CHILL_TINT

func _process_walking(delta: float) -> void:
	var speed: float = base_speed * (CHILL_SPEED_MULTIPLIER if is_chilled else 1.0)
	position.x -= speed * delta

	# House reach check (Game Over threshold)
	if position.x < 180.0:
		EventBus.zombie_reached_house.emit(row)
		EventBus.game_over.emit(false) # Game Over!

func _process_eating(delta: float) -> void:
	# If target is invalid or dead, resume walking
	if eating_target == null or not is_instance_valid(eating_target) or eating_target.get("is_dead"):
		eating_target = null
		current_state = State.WALKING
		return

	eat_damage_timer -= delta
	if eat_damage_timer <= 0.0:
		var dps_mult: float = 0.5 if is_chilled else 1.0
		var damage_tick: int = int(damage_rate * 0.5 * dps_mult)
		eating_target.take_damage(damage_tick)
		SoundManager.play_sound("chomp")
		eat_damage_timer = 0.5

		# Chomping animation (billboard lunges forward in local game px)
		if visual_node != null:
			if eat_tween != null and eat_tween.is_valid():
				eat_tween.kill()
			eat_tween = create_tween()
			eat_tween.tween_property(visual_node, "position:x", -6.0, 0.08)
			eat_tween.tween_property(visual_node, "position:x", 0.0, 0.08)

func take_damage(amount: int, is_instant_kill: bool = false) -> void:
	if is_dead:
		return

	if is_instant_kill:
		die(true)
		return

	SoundManager.play_sound("splat")
	_play_hit_flash()

	# Armor takes damage first
	if armor_health > 0:
		armor_health -= amount
		if armor_health <= 0:
			var leftover: int = absi(armor_health)
			armor_health = 0
			_on_armor_broken()
			current_health -= leftover
	else:
		current_health -= amount

	zombie_damaged.emit(current_health, max_health)

	if current_health <= 0:
		die(false)

func _base_tint() -> Color:
	return CHILL_TINT if is_chilled else Color.WHITE

func _play_hit_flash() -> void:
	if visual_node == null:
		return
	if flash_tween != null and flash_tween.is_valid():
		flash_tween.kill()
	visual_node.modulate = FLASH_TINT
	flash_tween = create_tween()
	flash_tween.tween_property(visual_node, "modulate", _base_tint(), 0.1)

func _on_armor_broken() -> void:
	# Virtual method for conehead / buckethead to drop armor visually
	pass

## Spawns a small falling 3D prop (traffic cone / bucket) for the armor break.
func _spawn_falling_armor_prop(is_cone: bool) -> void:
	var prop := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	var mat := StandardMaterial3D.new()
	var start_y: float
	if is_cone:
		cylinder.top_radius = 0.0
		cylinder.bottom_radius = 14.0
		cylinder.height = 28.0
		start_y = 42.0
		mat.albedo_color = Color(0.95, 0.45, 0.1)
	else:
		cylinder.top_radius = 15.0
		cylinder.bottom_radius = 13.0
		cylinder.height = 24.0
		start_y = 40.0
		mat.albedo_color = Color(0.7, 0.72, 0.75)
	cylinder.radial_segments = 12
	prop.mesh = cylinder
	mat.roughness = 0.8
	prop.material_override = mat
	prop.position = Vector3(0.0, start_y, Z_NUDGE + 4.0)
	prop.rotation_degrees = Vector3(0.0, 0.0, -8.0)
	add_child(prop)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(prop, "position", Vector3(-36.0, 8.0, 30.0), 0.35) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(prop, "rotation_degrees", Vector3(0.0, 40.0, -140.0), 0.35)
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.35)
	tween.chain().tween_callback(prop.queue_free)

func die(_was_instant_kill: bool = false) -> void:
	if is_dead:
		return
	is_dead = true
	current_state = State.DYING
	collision_layer = 0
	collision_mask = 0
	set_deferred("monitorable", false)
	set_deferred("monitoring", false)
	zombie_died.emit()
	EventBus.zombie_died.emit(self)

	# Death animation: fade out while toppling over (squash toward the ground).
	if visual_node != null:
		var c: Color = visual_node.modulate
		var tween := create_tween()
		tween.set_parallel(true)
		tween.tween_property(visual_node, "modulate", Color(c.r, c.g, c.b, 0.0), 0.4)
		tween.tween_property(visual_node, "scale", Vector3(1.25, 0.2, 1.25), 0.4) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		if shadow_node != null and is_instance_valid(shadow_node):
			tween.tween_property(shadow_node, "scale", Vector3.ZERO, 0.25)
		tween.chain().tween_callback(queue_free)
	else:
		queue_free()

func _on_area_entered(area: Area3D) -> void:
	if is_dead:
		return
	if area is BasePlant and not area.get("is_dead"):
		# Check if plant is in the same row
		if area.get("row") == row:
			eating_target = area
			current_state = State.EATING
			eat_damage_timer = 0.2

func _on_area_exited(area: Area3D) -> void:
	if area == eating_target:
		eating_target = null
		if current_state == State.EATING:
			current_state = State.WALKING
