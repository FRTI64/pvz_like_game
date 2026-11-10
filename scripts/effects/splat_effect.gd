class_name SplatEffect
extends Node3D
## 3D one-shot green particle burst used when a pea hits a zombie.
##
## Uses small camera-facing Sprite3D dots (not CPUParticles3D): Godot particle
## systems ignore the WorldRoot 1/45 scale for particle mesh sizes, which makes
## them render gigantic here. Sprite3D billboards scale correctly.
## Spawned as a child of the projectile's parent; positioned in local game px.

const LIFETIME: float = 0.4
const PARTICLE_COUNT: int = 12
const GRAVITY: float = -340.0
const DOT_TEX_SIZE: int = 32

static var _dot_texture: Texture2D = null

var age: float = 0.0
var _particles: Array = []

static func dot_texture() -> Texture2D:
	if _dot_texture != null:
		return _dot_texture
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	gradient.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 1.0),
		Color(1.0, 1.0, 1.0, 0.75),
		Color(1.0, 1.0, 1.0, 0.0),
	])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = DOT_TEX_SIZE
	texture.height = DOT_TEX_SIZE
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	_dot_texture = texture
	return _dot_texture

func _ready() -> void:
	for i in range(PARTICLE_COUNT):
		var sprite := Sprite3D.new()
		var size_px: float = randf_range(7.0, 12.0)
		sprite.texture = dot_texture()
		sprite.pixel_size = size_px / float(DOT_TEX_SIZE)
		sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		sprite.transparent = true
		sprite.shaded = false
		sprite.no_depth_test = false
		sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		sprite.position = Vector3(randf_range(-5.0, 5.0), randf_range(-5.0, 5.0), 0.0)
		# >1 channel values brighten the unshaded sprite so the burst pops
		# against the green lawn / green zombie art.
		sprite.modulate = Color(
			randf_range(1.2, 1.8),
			randf_range(1.6, 2.2),
			randf_range(0.5, 0.9),
			1.0
		)
		add_child(sprite)

		# Random direction in the upper hemisphere, like a splash.
		var angle: float = randf() * TAU
		var elevation: float = randf_range(-0.35, 1.0)
		var horizontal: float = sqrt(maxf(0.0, 1.0 - elevation * elevation))
		var direction := Vector3(cos(angle) * horizontal, elevation, sin(angle) * horizontal)
		_particles.append({
			"node": sprite,
			"velocity": direction.normalized() * randf_range(60.0, 180.0),
			"start_scale": randf_range(0.8, 1.3),
		})

func _process(delta: float) -> void:
	age += delta
	var progress: float = clampf(age / LIFETIME, 0.0, 1.0)
	for p in _particles:
		var node: Sprite3D = p["node"]
		var velocity: Vector3 = p["velocity"]
		velocity.y += GRAVITY * delta
		p["velocity"] = velocity
		node.position += velocity * delta
		node.scale = Vector3.ONE * (p["start_scale"] as float) * (1.0 - 0.45 * progress)
		var c: Color = node.modulate
		node.modulate = Color(c.r, c.g, c.b, 1.0 - progress)

	if age >= LIFETIME:
		queue_free()
