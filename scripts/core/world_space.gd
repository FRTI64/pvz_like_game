class_name WorldSpace
extends RefCounted
## Shared mapping between 2D game-pixel coordinates and 3D world units.
##
## Game screen space: 1280x720 px, +x right, +y down.
## 3D world space: +x right, +y up, +z toward camera (screen down).
## Under `WorldRoot` (see `setup_world_root`) gameplay nodes keep using *local*
## coordinates in game pixels: local position = Vector3(game_x, height_px, game_y).
## The ground plane is world Y = 0 (local Y = 0).

## World units per game pixel.
const PX: float = 1.0 / 45.0
## Center of the 2D game screen in game px.
const CENTER: Vector2 = Vector2(640.0, 360.0)
## Transform to apply to the WorldRoot node so children live in game px units.
const ROOT_OFFSET: Vector3 = Vector3(-640.0 * PX, 0.0, -360.0 * PX)
const ROOT_SCALE: Vector3 = Vector3(PX, PX, PX)
## Camera framing defaults (see docs/3d-render-spec.md §2.2).
const CAMERA_FOV: float = 40.0
const CAMERA_TARGET: Vector3 = Vector3(0.0, 1.2, 2.0)
const CAMERA_ELEVATION_DEG: float = 58.0
const CAMERA_DISTANCE: float = 25.0


static func setup_world_root(root: Node3D) -> void:
	root.position = ROOT_OFFSET
	root.scale = ROOT_SCALE


## Camera position for the default framing of the lawn.
static func default_camera_position() -> Vector3:
	var phi := deg_to_rad(CAMERA_ELEVATION_DEG)
	return CAMERA_TARGET + Vector3(
		0.0,
		CAMERA_DISTANCE * sin(phi),
		CAMERA_DISTANCE * cos(phi)
	)


## Local (px) -> world units.
static func local_to_world(v: Vector3) -> Vector3:
	return ROOT_OFFSET + Vector3(v.x * PX, v.y * PX, v.z * PX)


## World units -> local (px).
static func world_to_local(v: Vector3) -> Vector3:
	return Vector3(
		(v.x - ROOT_OFFSET.x) / PX,
		v.y / PX,
		(v.z - ROOT_OFFSET.z) / PX
	)


## World position -> ground-plane game 2D coordinates (px, ignores height).
static func world_to_game2(v: Vector3) -> Vector2:
	return Vector2(v.x / PX + CENTER.x, v.z / PX + CENTER.y)


## Game 2D coordinates (px) -> local Vector3 (game px units).
static func game2_to_local(x: float, y2d: float, height_px: float = 0.0) -> Vector3:
	return Vector3(x, height_px, y2d)


## Game 2D coordinates (px) -> world ground point.
static func game_to_world_ground(x: float, y2d: float) -> Vector3:
	return local_to_world(game2_to_local(x, y2d, 0.0))


## Cast a screen-space point onto the ground plane and return game 2D coords (px).
## Returns Vector2(INF, INF) when the ray does not hit the ground.
static func screen_to_game(camera: Camera3D, screen_pos: Vector2) -> Vector2:
	if camera == null:
		return Vector2(INF, INF)
	var origin := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	var plane := Plane(Vector3.UP, 0.0)
	var hit: Variant = plane.intersects_ray(origin, dir)
	if hit == null:
		return Vector2(INF, INF)
	return world_to_game2(hit)


## World point `depth` units in front of the camera along the ray through
## `screen_pos` (useful for tweens that should end near a screen position,
## e.g. flying a collected sun into the HUD corner).
static func screen_point_world(camera: Camera3D, screen_pos: Vector2, depth: float) -> Vector3:
	if camera == null:
		return Vector3.ZERO
	return camera.project_ray_origin(screen_pos) + camera.project_ray_normal(screen_pos) * depth


## Screen-space distance (px) between a world position and a screen point.
## Returns INF for positions behind the camera.
static func screen_distance_to_world(camera: Camera3D, world_pos: Vector3, screen_pos: Vector2) -> float:
	if camera == null or camera.is_position_behind(world_pos):
		return INF
	return camera.unproject_position(world_pos).distance_to(screen_pos)
