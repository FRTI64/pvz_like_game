class_name Billboard2D
extends Node3D
## A camera-facing billboard displaying 2D procedural art in the 3D world.
##
## The node origin is the billboard anchor: the feet/ground contact point for
## standing units, or the sprite center for floating items (projectiles, sun).
## Local coordinates are game pixels (the node lives under WorldRoot), so
## callers may tween position/scale/modulate naturally.
##
## Usage:
##   var vis := BillboardLibrary.make_billboard("p_peashooter")
##   add_child(vis)
##   vis.modulate = Color(1.2, 1.2, 1.2)
##   vis.position = Vector3(0, 10, 0)   # local game px offset (up)

const FRAME_W: float = 256.0
const FRAME_H: float = 256.0
const CAPTURE_SCALE: float = 2.0
const PIXEL_SIZE: float = 1.0 / CAPTURE_SCALE

var sprite: Sprite3D = null
var sheet_name: String = ""
var frame_count: int = 1
var fps: float = 6.0
var animate_frames: bool = true

var _anim_t: float = 0.0

## Modulate (tint) the billboard art. Tweenable: tween_property(vis, "modulate", ...).
var modulate: Color:
	get:
		return sprite.modulate if sprite != null else Color.WHITE
	set(value):
		if sprite != null:
			sprite.modulate = value


func _init() -> void:
	sprite = Sprite3D.new()
	sprite.name = "Sprite"
	sprite.centered = true
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	sprite.pixel_size = PIXEL_SIZE
	sprite.transparent = true
	sprite.shaded = false
	sprite.no_depth_test = false
	sprite.double_sided = true
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sprite)


func _process(delta: float) -> void:
	if not animate_frames or frame_count <= 1:
		return
	_anim_t += delta
	sprite.frame = int(_anim_t * fps) % frame_count


## Configure/replace the sheet shown by this billboard.
func set_sheet(name: String) -> void:
	BillboardLibrary.apply_sheet(self, name)


func set_alpha(alpha: float) -> void:
	var c: Color = sprite.modulate
	sprite.modulate = Color(c.r, c.g, c.b, alpha)


func get_alpha() -> float:
	return sprite.modulate.a
