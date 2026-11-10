class_name GridManager
extends Node3D
## 3D board interaction: screen ray -> ground -> game px cell, hover highlight,
## ghost preview, sun picking (before grid clicks) and the original planting /
## shovel logic (docs/3d-render-spec.md §4.4).
##
## Lives under WorldRoot with an identity transform, so local coordinates are
## game pixels (local y = 0 is the walkable lawn surface).  Plants are added as
## children of this node, so their local positions are game px as well.

const ROWS: int = 5
const COLS: int = 9
## Sun picking tolerance in screen px (spec §4.4).
const SUN_PICK_RADIUS: float = 34.0
## Hover highlight height above the lawn (game px) — above blob shadows (0.8).
const HIGHLIGHT_Y: float = 2.0

@export var cell_size: Vector2 = Vector2(98, 108)
@export var grid_origin: Vector2 = Vector2(275, 125)

# Map from Vector2i(col, row) to BasePlant
var grid_cells: Dictionary = {}
var hovered_cell: Vector2i = Vector2i(-1, -1)
var is_hovering_lawn: bool = false

# Ghost preview plant node (Billboard2D) and hover highlight (fill + frame).
var ghost_preview: Node3D = null
var highlight: Node3D = null
var _highlight_mat: StandardMaterial3D = null
var _highlight_frame_mat: StandardMaterial3D = null


func _ready() -> void:
	EventBus.plant_card_selected.connect(_on_plant_card_selected)
	EventBus.plant_card_deselected.connect(_on_plant_card_deselected)
	EventBus.shovel_toggled.connect(_on_shovel_toggled)
	_build_highlight()


func _process(_delta: float) -> void:
	_update_highlight()


# --- Input ---------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_handle_mouse_motion(event.position)
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_handle_left_click(event.position)
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_handle_right_click()


func _camera() -> Camera3D:
	return get_viewport().get_camera_3d()


func _screen_to_game(screen_pos: Vector2) -> Vector2:
	var camera := _camera()
	if camera == null:
		return Vector2(INF, INF)
	return WorldSpace.screen_to_game(camera, screen_pos)


func _handle_mouse_motion(mouse_pos: Vector2) -> void:
	var game_pos: Vector2 = _screen_to_game(mouse_pos)
	if game_pos.x == INF:
		_clear_hover()
		return
	var cell: Vector2i = world_to_grid(game_pos)
	if is_cell_valid(cell):
		hovered_cell = cell
		is_hovering_lawn = true
		if ghost_preview != null:
			ghost_preview.visible = true
			_update_ghost_position()
	else:
		_clear_hover()


func _handle_left_click(click_pos: Vector2) -> void:
	# (1) Sun picking happens before any grid handling (spec §4.4).
	if _try_collect_sun(click_pos):
		get_viewport().set_input_as_handled()
		return

	# (2) Otherwise the existing shovel / plant click logic via ray -> cell.
	var game_pos: Vector2 = _screen_to_game(click_pos)
	if game_pos.x == INF:
		return
	var cell: Vector2i = world_to_grid(game_pos)
	if not is_cell_valid(cell):
		return

	# Shovel action
	if GameManager.is_shovel_active:
		if is_cell_occupied(cell):
			remove_plant(cell)
			SoundManager.play_sound("plant")
			GameManager.set_shovel_active(false)
		return

	# Planting action
	if GameManager.selected_plant_data != null:
		var plant_data: PlantData = GameManager.selected_plant_data
		if not is_cell_occupied(cell) and GameManager.can_afford(plant_data.sun_cost):
			if place_plant(cell, plant_data):
				GameManager.spend_sun(plant_data.sun_cost)
				GameManager.deselect_plant()
				SoundManager.play_sound("plant")


func _handle_right_click() -> void:
	if GameManager.selected_plant_data != null:
		GameManager.deselect_plant()
	if GameManager.is_shovel_active:
		GameManager.set_shovel_active(false)


## Pick the closest sun whose sprite center projects within SUN_PICK_RADIUS px of
## the click.  Returns true when a sun was collected.
func _try_collect_sun(click_pos: Vector2) -> bool:
	var camera := _camera()
	if camera == null:
		return false
	var best: Node3D = null
	var best_dist: float = SUN_PICK_RADIUS
	for node in get_tree().get_nodes_in_group("suns"):
		var sun := node as Node3D
		if sun == null or not is_instance_valid(sun):
			continue
		if sun.has_method("collect") and sun.get("is_collected") == true:
			continue
		var dist: float = WorldSpace.screen_distance_to_world(
				camera, sun.global_position, click_pos)
		if dist < best_dist:
			best_dist = dist
			best = sun
	if best == null:
		return false
	best.call("collect")
	return true


# --- Grid math (2D game px, unchanged from the 2D version) ---------------

func world_to_grid(world_pos: Vector2) -> Vector2i:
	var relative: Vector2 = world_pos - grid_origin
	if relative.x < 0 or relative.y < 0:
		return Vector2i(-1, -1)
	var col: int = int(relative.x / cell_size.x)
	var row: int = int(relative.y / cell_size.y)
	if col >= 0 and col < COLS and row >= 0 and row < ROWS:
		return Vector2i(col, row)
	return Vector2i(-1, -1)


func grid_to_world(cell: Vector2i) -> Vector2:
	return grid_origin + Vector2(
		cell.x * cell_size.x + cell_size.x * 0.5,
		cell.y * cell_size.y + cell_size.y * 0.5
	)


func is_cell_valid(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < COLS and cell.y >= 0 and cell.y < ROWS


func is_cell_occupied(cell: Vector2i) -> bool:
	return grid_cells.has(cell) and is_instance_valid(grid_cells[cell])


# --- Planting ------------------------------------------------------------

func place_plant(cell: Vector2i, plant_data: PlantData) -> BasePlant:
	if is_cell_occupied(cell) or not is_cell_valid(cell):
		return null

	var plant_instance: BasePlant = null
	if plant_data.plant_scene != null:
		plant_instance = plant_data.plant_scene.instantiate() as BasePlant
	else:
		# Fallback if scene is not yet assigned
		plant_instance = BasePlant.new()

	plant_instance.plant_data = plant_data
	plant_instance.grid_pos = cell
	plant_instance.row = cell.y
	plant_instance.col = cell.x
	var game_pos: Vector2 = grid_to_world(cell)
	plant_instance.position = WorldSpace.game2_to_local(game_pos.x, game_pos.y, 0.0)

	add_child(plant_instance)
	grid_cells[cell] = plant_instance

	# Connect death signal
	plant_instance.tree_exited.connect(func():
		if grid_cells.get(cell) == plant_instance:
			grid_cells.erase(cell)
	)

	EventBus.plant_placed.emit(cell, plant_instance)
	return plant_instance


func remove_plant(cell: Vector2i) -> bool:
	if not is_cell_occupied(cell):
		return false
	var plant: BasePlant = grid_cells[cell]
	grid_cells.erase(cell)
	if is_instance_valid(plant):
		EventBus.plant_removed.emit(cell, plant)
		plant.queue_free()
	return true


func get_plant(cell: Vector2i) -> BasePlant:
	if is_cell_occupied(cell):
		return grid_cells[cell]
	return null


func get_plants_in_row(row_idx: int) -> Array[BasePlant]:
	var result: Array[BasePlant] = []
	for col in range(COLS):
		var p: BasePlant = get_plant(Vector2i(col, row_idx))
		if p != null:
			result.append(p)
	return result


# --- Hover highlight -----------------------------------------------------

func _build_highlight() -> void:
	highlight = Node3D.new()
	highlight.name = "HoverHighlight"
	highlight.visible = false

	# Translucent additive fill over the whole cell.
	var fill := MeshInstance3D.new()
	fill.name = "Fill"
	var quad := QuadMesh.new()
	quad.size = cell_size
	_highlight_mat = StandardMaterial3D.new()
	_highlight_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_highlight_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_highlight_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_highlight_mat.albedo_color = Color(0.35, 1.0, 0.4, 0.5)
	_highlight_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_highlight_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_highlight_mat.disable_receive_shadows = true
	quad.material = _highlight_mat
	fill.mesh = quad
	fill.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	highlight.add_child(fill)

	# Bright 3px frame so the highlighted cell is readable at a glance.
	_highlight_frame_mat = StandardMaterial3D.new()
	_highlight_frame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_highlight_frame_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_highlight_frame_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_highlight_frame_mat.albedo_color = Color(0.75, 1.0, 0.8, 0.85)
	_highlight_frame_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_highlight_frame_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_highlight_frame_mat.disable_receive_shadows = true
	var bw := 4.0
	var specs := [
		[Vector2(0.0, -cell_size.y * 0.5 + bw * 0.5), Vector2(cell_size.x, bw)],
		[Vector2(0.0, cell_size.y * 0.5 - bw * 0.5), Vector2(cell_size.x, bw)],
		[Vector2(-cell_size.x * 0.5 + bw * 0.5, 0.0), Vector2(bw, cell_size.y - bw * 2.0)],
		[Vector2(cell_size.x * 0.5 - bw * 0.5, 0.0), Vector2(bw, cell_size.y - bw * 2.0)],
	]
	for i in specs.size():
		var bar := MeshInstance3D.new()
		bar.name = "Frame%d" % i
		var bq := QuadMesh.new()
		bq.size = specs[i][1]
		bq.material = _highlight_frame_mat
		bar.mesh = bq
		bar.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
		bar.position = Vector3(specs[i][0].x, 0.15, specs[i][0].y)
		bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		highlight.add_child(bar)

	add_child(highlight)


func _update_highlight() -> void:
	if highlight == null:
		return
	var show_highlight: bool = is_hovering_lawn and is_cell_valid(hovered_cell) \
			and (GameManager.is_shovel_active or GameManager.selected_plant_data != null)
	if not show_highlight:
		highlight.visible = false
		return
	var occupied: bool = is_cell_occupied(hovered_cell)
	var color: Color
	var frame_color: Color
	if GameManager.is_shovel_active:
		# Red only on diggable (occupied) cells.
		if not occupied:
			highlight.visible = false
			return
		color = Color(1.0, 0.32, 0.22, 0.42)
		frame_color = Color(1.0, 0.55, 0.4, 0.8)
	else:
		if occupied:
			color = Color(1.0, 0.35, 0.2, 0.36)
			frame_color = Color(1.0, 0.55, 0.4, 0.75)
		else:
			color = Color(0.3, 1.0, 0.35, 0.4)
			frame_color = Color(0.7, 1.0, 0.75, 0.85)
	_highlight_mat.albedo_color = color
	_highlight_frame_mat.albedo_color = frame_color
	var center: Vector2 = grid_to_world(hovered_cell)
	highlight.position = WorldSpace.game2_to_local(center.x, center.y, HIGHLIGHT_Y)
	highlight.visible = true


func _clear_hover() -> void:
	hovered_cell = Vector2i(-1, -1)
	is_hovering_lawn = false
	if ghost_preview != null:
		ghost_preview.visible = false


# --- Ghost preview -------------------------------------------------------

func _on_plant_card_selected(plant_data: PlantData) -> void:
	_update_ghost_preview(plant_data)


func _on_plant_card_deselected() -> void:
	_clear_ghost()


func _on_shovel_toggled(_active: bool) -> void:
	_clear_ghost()


func _clear_ghost() -> void:
	if ghost_preview != null and is_instance_valid(ghost_preview):
		ghost_preview.queue_free()
	ghost_preview = null


func _update_ghost_preview(plant_data: PlantData) -> void:
	_clear_ghost()
	var sheet: String = BillboardLibrary.sheet_for_plant(plant_data.id)
	var ghost: Node3D = BillboardLibrary.make_ghost(sheet)
	ghost.name = "GhostPreview"
	ghost.visible = false
	add_child(ghost)
	ghost_preview = ghost
	if is_hovering_lawn and is_cell_valid(hovered_cell):
		ghost.visible = true
		_update_ghost_position()


func _update_ghost_position() -> void:
	if ghost_preview == null or not is_instance_valid(ghost_preview):
		return
	var center: Vector2 = grid_to_world(hovered_cell)
	ghost_preview.position = WorldSpace.game2_to_local(center.x, center.y, 0.0)
