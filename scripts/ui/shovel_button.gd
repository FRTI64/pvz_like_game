class_name ShovelButton
extends Button

@onready var highlight_rect: ReferenceRect = get_node_or_null("Highlight")

func _ready() -> void:
	pressed.connect(_on_pressed)
	EventBus.shovel_toggled.connect(_on_shovel_toggled)

func _on_pressed() -> void:
	GameManager.set_shovel_active(not GameManager.is_shovel_active)

func _on_shovel_toggled(active: bool) -> void:
	if highlight_rect != null:
		highlight_rect.visible = active

