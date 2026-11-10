class_name Sun
extends Node3D
## Collectible sun. Floats at ~95 game px height, falls along +Z from the top of
## the screen (game y = -40) to its target game y, bobs/blinks, and flies to the
## HUD sun counter when collected. Sun picking is done by GridManager via screen
## projection (see spec §4.4), so this node needs no input/Area3D.

const SUN_HEIGHT: float = 95.0
const GROUND_SHADOW_Y: float = 0.8
const FALL_START_Z: float = -40.0
const Z_NUDGE: float = 8.0
const SHADOW_SIZE: Vector2 = Vector2(56.0, 30.0)
const COLLECT_TIME: float = 0.45
## HUD sun-counter screen position (matches the original 2D hud_target).
const HUD_TARGET_SCREEN: Vector2 = Vector2(85.0, 45.0)
## Depth (world units in front of the camera) the sun flies into.
const COLLECT_END_DEPTH: float = 2.5
## Flower-produced suns settle a bit lower and slightly towards the camera so
## they read as "popped out in front of the sunflower" instead of covering its
## face when seen from the 58-degree camera.
const FLOWER_DROP_HEIGHT: float = 58.0
const FLOWER_DROP_Z_OFFSET: float = 20.0

@export var billboard_sheet: String = "i_sun"
@export var value: int = 25
@export var fall_speed: float = 90.0

var target_z: float = 300.0
var is_falling: bool = false
var is_collected: bool = false
var lifetime: float = 11.0
var bob_offset: float = 0.0

var _visual: Billboard2D = null
var _shadow: MeshInstance3D = null
var _drop_tween: Tween = null
var _collect_t: float = 0.0
var _collect_global_start: Vector3 = Vector3.ZERO
var _collect_target_world: Vector3 = Vector3.ZERO
var _collect_start_depth: float = 0.0
var _collect_alpha: float = 1.0

func _ready() -> void:
	add_to_group("suns")

	_visual = BillboardLibrary.make_billboard(billboard_sheet)
	_visual.name = "Visual"
	_visual.position = Vector3(0.0, 0.0, Z_NUDGE)
	add_child(_visual)

	# Floating item: faint blob shadow on the lawn below the sun.
	_shadow = BillboardLibrary.make_shadow(SHADOW_SIZE)
	if _shadow != null:
		_shadow.name = "Shadow"
		_add_faded_shadow(_shadow)
		add_child(_shadow)
		_update_shadow_height()

	EventBus.sun_spawned.emit(self)

func _add_faded_shadow(mesh: MeshInstance3D) -> void:
	var quad := mesh.mesh as QuadMesh
	if quad == null:
		return
	var mat := quad.material as StandardMaterial3D
	if mat != null:
		mat.albedo_color = Color(0.0, 0.0, 0.0, 0.6)

func _update_shadow_height() -> void:
	if _shadow == null:
		return
	# The shadow is a child of this node: counter the flight height so the quad
	# stays on the lawn (local y = 0.8 in game-px space).
	_shadow.position = Vector3(0.0, GROUND_SHADOW_Y - position.y, Z_NUDGE)

func setup_falling(dest_y: float) -> void:
	## `dest_y` is the target game y (falls along +Z). Kept 2D-compatible.
	target_z = dest_y
	is_falling = true
	if position.y < 50.0:
		position.y = SUN_HEIGHT
	if position.z > target_z:
		position.z = FALL_START_Z
	_update_shadow_height()

func setup_flower_drop(dest_pos: Vector2) -> void:
	is_falling = false
	var start := position
	if start.y < 50.0:
		start.y = SUN_HEIGHT
		position = start
	var dest := Vector3(dest_pos.x, FLOWER_DROP_HEIGHT, dest_pos.y + FLOWER_DROP_Z_OFFSET)
	# Arc upwards then drop to the target 2D position (original 2D behaviour).
	var mid := (start + dest) * 0.5 + Vector3(0.0, 40.0, 0.0)
	if _drop_tween != null and _drop_tween.is_valid():
		_drop_tween.kill()
	_drop_tween = create_tween()
	_drop_tween.tween_property(self, "position", mid, 0.25) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_drop_tween.tween_property(self, "position", dest, 0.35) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

func _process(delta: float) -> void:
	if is_collected:
		_process_collect(delta)
		return

	_update_shadow_height()

	if is_falling:
		position.z += fall_speed * delta
		if position.z >= target_z:
			position.z = target_z
			is_falling = false
			_update_shadow_height()
	else:
		# Gentle bobbing animation
		bob_offset += delta * 3.0
		if _visual != null:
			_visual.position = Vector3(
				sin(bob_offset * 0.8) * 2.5,
				sin(bob_offset) * 4.5,
				Z_NUDGE
			)

		lifetime -= delta
		if lifetime <= 2.0:
			# Blink before disappearing
			var a: float = clampf(0.4 + sin(lifetime * 16.0) * 0.4, 0.0, 1.0)
			var c: Color = _visual.modulate
			_visual.modulate = Color(c.r, c.g, c.b, a)
		if lifetime <= 0.0:
			queue_free()

func collect() -> void:
	if is_collected:
		return
	is_collected = true
	remove_from_group("suns")
	SoundManager.play_sound("sun")

	var camera: Camera3D = get_viewport().get_camera_3d()
	_collect_target_world = global_position
	_collect_start_depth = 0.0
	if camera != null:
		_collect_target_world = WorldSpace.screen_point_world(camera, Vector2(85.0, 45.0), 2.5)
		var forward: Vector3 = -camera.global_transform.basis.z
		_collect_start_depth = maxf(1.0, (global_position - camera.global_position).dot(forward))
	_collect_global_start = global_position
	_collect_alpha = _visual.modulate.a if _visual != null else 1.0
	if _shadow != null:
		var tween := create_tween()
		tween.tween_property(_shadow, "scale", Vector3.ZERO, 0.2)
	_collect_t = 0.0

func _process_collect(delta: float) -> void:
	_collect_t += delta
	var progress: float = clampf(_collect_t / COLLECT_TIME, 0.0, 1.0)
	# Ease-out flight to the HUD counter.
	var eased: float = 1.0 - pow(1.0 - progress, 2.0)

	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera != null and _visual != null and _collect_start_depth > 0.0:
		# Interpolate in SCREEN space so the sun visibly flies towards the HUD
		# counter, then place it on that screen ray at a shrinking camera depth.
		# This keeps its apparent size ~constant instead of ballooning as it
		# approaches the near-camera target point.
		var start_screen: Vector2 = camera.unproject_position(_collect_global_start)
		var desired_screen: Vector2 = start_screen.lerp(HUD_TARGET_SCREEN, eased)
		var depth: float = lerpf(_collect_start_depth, COLLECT_END_DEPTH, eased)
		global_position = WorldSpace.screen_point_world(camera, desired_screen, depth)
		_visual.scale = Vector3.ONE * clampf(depth / _collect_start_depth, 0.04, 1.0)
		var c: Color = _visual.modulate
		var alpha: float = _collect_alpha * (1.0 - smoothstep(0.62, 1.0, progress))
		_visual.modulate = Color(c.r, c.g, c.b, alpha)
	else:
		global_position = _collect_global_start.lerp(_collect_target_world, eased)

	if progress >= 1.0:
		_on_collect_finished()

func _on_collect_finished() -> void:
	GameManager.add_sun(value)
	EventBus.sun_collected.emit(self, value)
	queue_free()
