class_name GridManager
extends Node2D

const ROWS: int = 5
const COLS: int = 9

@export var cell_size: Vector2 = Vector2(98, 108)
@export var grid_origin: Vector2 = Vector2(275, 125)

# Map from Vector2i(col, row) to BasePlant
var grid_cells: Dictionary = {}
var hovered_cell: Vector2i = Vector2i(-1, -1)
var is_hovering_lawn: bool = false

# Ghost preview plant node
var ghost_preview: Node2D = null

func _ready() -> void:
	EventBus.plant_card_selected.connect(_on_plant_card_selected)
	EventBus.plant_card_deselected.connect(_on_plant_card_deselected)
	EventBus.shovel_toggled.connect(_on_shovel_toggled)

func _process(_delta: float) -> void:
	queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_handle_mouse_motion(event.position)
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_handle_left_click(event.position)
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_handle_right_click()

func _handle_mouse_motion(mouse_pos: Vector2) -> void:
	var cell: Vector2i = world_to_grid(mouse_pos)
	if is_cell_valid(cell):
		hovered_cell = cell
		is_hovering_lawn = true
		if ghost_preview != null:
			ghost_preview.visible = true
			ghost_preview.position = grid_to_world(cell)
	else:
		hovered_cell = Vector2i(-1, -1)
		is_hovering_lawn = false
		if ghost_preview != null:
			ghost_preview.visible = false

func _handle_left_click(click_pos: Vector2) -> void:
	var cell: Vector2i = world_to_grid(click_pos)
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
	plant_instance.position = grid_to_world(cell)
	
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

func _on_plant_card_selected(plant_data: PlantData) -> void:
	_update_ghost_preview(plant_data)

func _on_plant_card_deselected() -> void:
	if ghost_preview != null:
		ghost_preview.queue_free()
		ghost_preview = null

func _on_shovel_toggled(_active: bool) -> void:
	if ghost_preview != null:
		ghost_preview.queue_free()
		ghost_preview = null

func _update_ghost_preview(plant_data: PlantData) -> void:
	if ghost_preview != null:
		ghost_preview.queue_free()
		ghost_preview = null
	
	ghost_preview = Node2D.new()
	ghost_preview.modulate = Color(1.0, 1.0, 1.0, 0.6)
	ghost_preview.visible = false
	
	# Draw simple preview circle if no scene
	var preview_drawing := Node2D.new()
	preview_drawing.script = load("res://scripts/plants/preview_drawer.gd")
	preview_drawing.set("color", plant_data.theme_color)
	ghost_preview.add_child(preview_drawing)
	
	add_child(ghost_preview)

func _draw() -> void:
	# Draw subtle lawn tiles / checkerboard
	for r in range(ROWS):
		for c in range(COLS):
			var cell_rect := Rect2(
				grid_origin.x + c * cell_size.x,
				grid_origin.y + r * cell_size.y,
				cell_size.x,
				cell_size.y
			)
			var is_even: bool = (r + c) % 2 == 0
			var grass_color: Color = Color(0.24, 0.52, 0.22) if is_even else Color(0.21, 0.47, 0.19)
			draw_rect(cell_rect, grass_color)
			# Subtle border
			draw_rect(cell_rect, Color(0.18, 0.42, 0.16, 0.4), false, 1.0)
	
	# Draw hover cell highlight if active
	if is_hovering_lawn and is_cell_valid(hovered_cell):
		var hl_rect := Rect2(
			grid_origin.x + hovered_cell.x * cell_size.x,
			grid_origin.y + hovered_cell.y * cell_size.y,
			cell_size.x,
			cell_size.y
		)
		if GameManager.is_shovel_active:
			if is_cell_occupied(hovered_cell):
				draw_rect(hl_rect, Color(0.9, 0.2, 0.2, 0.4)) # Red highlight for digging
		elif GameManager.selected_plant_data != null:
			if not is_cell_occupied(hovered_cell):
				draw_rect(hl_rect, Color(0.2, 0.9, 0.3, 0.45)) # Green highlight for planting
			else:
				draw_rect(hl_rect, Color(0.9, 0.3, 0.2, 0.4)) # Occupied

