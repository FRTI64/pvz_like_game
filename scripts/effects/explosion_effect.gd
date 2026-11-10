class_name ExplosionEffect
extends Node3D
## 3D explosion used by cherry bomb / potato mine: orange particle burst, an
## expanding flat ground ring, a bright fireball flash and a brief warm light.
##
## Particles are camera-facing Sprite3D dots (Godot particle systems ignore the
## WorldRoot 1/45 scale for particle mesh sizes). Ground ring / fireball are
## plain meshes, which scale correctly under WorldRoot.

const LIFETIME: float = 0.55
const GROUND_Y: float = 1.2
const PARTICLE_COUNT: int = 30
const GRAVITY: float = -360.0
const DOT_TEX_SIZE: int = 32

static var _dot_texture: Texture2D = null

var age: float = 0.0
var _particles: Array = []
var _ring: MeshInstance3D = null
var _ring_material: StandardMaterial3D = null
var _fireball: MeshInstance3D = null
var _fireball_material: StandardMaterial3D = null
var _light: OmniLight3D = null

static func dot_texture() -> Texture2D:
	if _dot_texture != null:
		return _dot_texture
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	gradient.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 1.0),
		Color(1.0, 1.0, 1.0, 0.8),
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
	_build_particles()
	_build_ring()
	_build_fireball()
	_build_light()

func _build_particles() -> void:
	for i in range(PARTICLE_COUNT):
		var sprite := Sprite3D.new()
		var size_px: float = randf_range(14.0, 24.0)
		sprite.texture = dot_texture()
		sprite.pixel_size = size_px / float(DOT_TEX_SIZE)
		sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		sprite.transparent = true
		sprite.shaded = false
		sprite.no_depth_test = false
		sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		sprite.position = Vector3(
			randf_range(-10.0, 10.0),
			12.0 + randf_range(-4.0, 8.0),
			randf_range(-8.0, 8.0)
		)
		var warm: float = randf()
		sprite.modulate = Color(1.0, lerpf(0.9, 0.45, warm), lerpf(0.38, 0.05, warm), 1.0)
		add_child(sprite)

		var angle: float = randf() * TAU
		var elevation: float = randf_range(0.05, 1.0)
		var horizontal: float = sqrt(maxf(0.0, 1.0 - elevation * elevation))
		var direction := Vector3(cos(angle) * horizontal, elevation, sin(angle) * horizontal)
		_particles.append({
			"node": sprite,
			"velocity": direction.normalized() * randf_range(110.0, 320.0),
			"start_scale": randf_range(0.8, 1.4),
		})

func _build_ring() -> void:
	_ring_material = StandardMaterial3D.new()
	_ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ring_material.albedo_color = Color(1.0, 0.42, 0.08, 0.9)

	var torus := TorusMesh.new()
	torus.inner_radius = 24.0
	torus.outer_radius = 40.0
	torus.rings = 24
	torus.ring_segments = 8
	torus.material = _ring_material

	_ring = MeshInstance3D.new()
	_ring.name = "GroundRing"
	_ring.mesh = torus
	_ring.position = Vector3(0.0, GROUND_Y, 0.0)
	_ring.scale = Vector3(0.3, 1.0, 0.3)
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)

func _build_fireball() -> void:
	_fireball_material = StandardMaterial3D.new()
	_fireball_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_fireball_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_fireball_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_fireball_material.albedo_color = Color(1.0, 0.62, 0.15, 0.85)

	var sphere := SphereMesh.new()
	sphere.radius = 10.0
	sphere.height = 20.0
	sphere.radial_segments = 16
	sphere.rings = 8
	sphere.material = _fireball_material

	_fireball = MeshInstance3D.new()
	_fireball.name = "Fireball"
	_fireball.mesh = sphere
	_fireball.position = Vector3(0.0, 20.0, 0.0)
	_fireball.scale = Vector3.ONE * 0.4
	_fireball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_fireball)

func _build_light() -> void:
	_light = OmniLight3D.new()
	_light.name = "Flash"
	_light.light_color = Color(1.0, 0.65, 0.25)
	_light.light_energy = 3.0
	_light.omni_range = 220.0
	_light.position = Vector3(0.0, 40.0, 0.0)
	_light.shadow_enabled = false
	add_child(_light)

func _process(delta: float) -> void:
	age += delta
	var progress: float = clampf(age / LIFETIME, 0.0, 1.0)

	for p in _particles:
		var node: Sprite3D = p["node"]
		var velocity: Vector3 = p["velocity"]
		velocity.y += GRAVITY * delta
		p["velocity"] = velocity
		node.position += velocity * delta
		node.scale = Vector3.ONE * (p["start_scale"] as float) * (1.0 - 0.35 * progress)
		var c: Color = node.modulate
		node.modulate = Color(c.r, c.g, c.b, 1.0 - progress)

	if _ring != null:
		var ring_scale: float = 0.3 + progress * 2.7
		_ring.scale = Vector3(ring_scale, 1.0, ring_scale)
	if _ring_material != null:
		_ring_material.albedo_color = Color(1.0, 0.42, 0.08, (1.0 - progress) * 0.9)

	if _fireball != null:
		var fireball_scale: float = 0.5 + minf(progress * 3.4, 1.6)
		_fireball.scale = Vector3.ONE * fireball_scale
	if _fireball_material != null:
		_fireball_material.albedo_color = Color(1.0, 0.62, 0.15, maxf(0.0, 1.0 - progress * 2.4))

	if _light != null:
		_light.light_energy = 3.0 * (1.0 - progress)

	if age >= LIFETIME:
		queue_free()
