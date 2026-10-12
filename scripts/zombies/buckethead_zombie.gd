class_name BucketheadZombie
extends BaseZombie

var bucket_node: Node2D = null

func _ready() -> void:
	super._ready()
	bucket_node = get_node_or_null("Visual/Bucket")

func _on_armor_broken() -> void:
	if bucket_node != null:
		var tween := create_tween()
		tween.tween_property(bucket_node, "position", Vector2(-30, 60), 0.3)
		tween.parallel().tween_property(bucket_node, "modulate:a", 0.0, 0.3)
		tween.tween_callback(bucket_node.queue_free)

