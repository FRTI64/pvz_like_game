class_name ConeheadZombie
extends BaseZombie

var cone_node: Node2D = null

func _ready() -> void:
	super._ready()
	cone_node = get_node_or_null("Visual/Cone")

func _on_armor_broken() -> void:
	if cone_node != null:
		# Animate cone falling off
		var tween := create_tween()
		tween.tween_property(cone_node, "position", Vector2(-30, 60), 0.3)
		tween.parallel().tween_property(cone_node, "modulate:a", 0.0, 0.3)
		tween.tween_callback(cone_node.queue_free)

