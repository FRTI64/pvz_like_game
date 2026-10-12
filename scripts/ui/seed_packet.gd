class_name SeedPacket
extends Control

@export var plant_data: PlantData

var cooldown_timer: float = 0.0
var is_on_cooldown: bool = false
var is_selected: bool = false

@onready var cost_label: Label = $CostLabel
@onready var name_label: Label = $NameLabel
@onready var cooldown_overlay: ColorRect = $CooldownOverlay
@onready var dark_mask: ColorRect = $DarkMask
@onready var border: ReferenceRect = $Border

func _ready() -> void:
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	gui_input.connect(_on_gui_input)
	
	EventBus.sun_amount_changed.connect(_on_sun_changed)
	EventBus.plant_card_selected.connect(_on_card_selected_event)
	EventBus.plant_card_deselected.connect(_on_card_deselected_event)
	
	if plant_data != null:
		setup_packet(plant_data)

func setup_packet(data: PlantData) -> void:
	plant_data = data
	if cost_label != null:
		cost_label.text = str(data.sun_cost)
	if name_label != null:
		name_label.text = data.display_name
	
	# Start ready
	cooldown_timer = 0.0
	is_on_cooldown = false
	_update_visual_state()

func _process(delta: float) -> void:
	if plant_data == null:
		return
	
	if is_on_cooldown:
		cooldown_timer -= delta
		if cooldown_timer <= 0.0:
			cooldown_timer = 0.0
			is_on_cooldown = false
		
		# Update cooldown vertical fill
		if cooldown_overlay != null:
			var ratio: float = cooldown_timer / plant_data.cooldown
			cooldown_overlay.size.y = size.y * ratio
			cooldown_overlay.position.y = 0.0
			cooldown_overlay.visible = is_on_cooldown
	else:
		if cooldown_overlay != null:
			cooldown_overlay.visible = false
	
	_update_visual_state()

func _update_visual_state() -> void:
	if plant_data == null:
		return
	
	var can_afford: bool = GameManager.can_afford(plant_data.sun_cost)
	
	# Dark mask when unaffordable or on cooldown
	if dark_mask != null:
		dark_mask.visible = not can_afford or is_on_cooldown
	
	# Selection border
	if border != null:
		border.border_color = Color(1.0, 0.9, 0.2) if is_selected else Color(0.3, 0.2, 0.1)

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_on_clicked()

func _on_clicked() -> void:
	if plant_data == null or is_on_cooldown:
		return
	if not GameManager.can_afford(plant_data.sun_cost):
		return
	
	if is_selected:
		GameManager.deselect_plant()
	else:
		GameManager.select_plant(plant_data)

func start_cooldown() -> void:
	if plant_data == null:
		return
	cooldown_timer = plant_data.cooldown
	is_on_cooldown = true

func _on_sun_changed(_new_val: int, _delta: int) -> void:
	_update_visual_state()

func _on_card_selected_event(data: PlantData) -> void:
	is_selected = (data == plant_data)
	_update_visual_state()

func _on_card_deselected_event() -> void:
	if is_selected and plant_data != null:
		# If we just placed our plant, start cooldown!
		if GameManager.selected_plant_data == null:
			start_cooldown()
	is_selected = false
	_update_visual_state()

func _on_mouse_entered() -> void:
	if not is_on_cooldown and plant_data != null and GameManager.can_afford(plant_data.sun_cost):
		modulate = Color(1.15, 1.15, 1.15)

func _on_mouse_exited() -> void:
	modulate = Color.WHITE

