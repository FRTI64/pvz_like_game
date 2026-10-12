class_name WaveManager
extends Node2D

@export var level_data: LevelData
@export var grid_manager: GridManager

# Spawn X coordinate (just off the right screen edge)
const SPAWN_X: float = 1320.0

var current_wave_idx: int = -1
var total_waves: int = 0
var wave_timer: float = 0.0
var is_spawning_active: bool = false
var alive_zombies: Array[Node2D] = []
var all_waves_spawned: bool = false

# Preloaded default zombie scenes in case LevelData needs fallbacks
var default_zombie_scene: PackedScene

func _ready() -> void:
	EventBus.zombie_died.connect(_on_zombie_died)
	if level_data != null:
		start_level(level_data)

func start_level(new_level: LevelData) -> void:
	level_data = new_level
	total_waves = level_data.waves.size()
	current_wave_idx = -1
	alive_zombies.clear()
	all_waves_spawned = false
	wave_timer = level_data.initial_delay
	is_spawning_active = true
	EventBus.level_started.emit(level_data)

func _process(delta: float) -> void:
	if not is_spawning_active or GameManager.current_state != GameManager.GameState.PLAYING:
		return
	
	if current_wave_idx < total_waves - 1:
		wave_timer -= delta
		if wave_timer <= 0.0:
			_start_next_wave()
	else:
		# All waves spawned, check victory condition
		if all_waves_spawned and alive_zombies.is_empty():
			is_spawning_active = false
			EventBus.game_over.emit(true) # Player Won!

func _start_next_wave() -> void:
	current_wave_idx += 1
	var wave_info: Dictionary = level_data.waves[current_wave_idx]
	var is_huge: bool = wave_info.get("is_huge", false)
	var next_delay: float = wave_info.get("delay", 20.0)
	wave_timer = next_delay
	
	if is_huge:
		SoundManager.play_sound("huge_wave")
		EventBus.huge_wave_warning.emit()
	
	EventBus.wave_started.emit(current_wave_idx, total_waves, is_huge)
	
	# Spawn zombies defined in this wave
	var spawns: Array = wave_info.get("spawns", [])
	for spawn_def in spawns:
		var z_data: ZombieData = spawn_def.get("zombie")
		var lane: int = spawn_def.get("lane", randi() % 5)
		var offset: float = spawn_def.get("offset", 0.0)
		
		if offset > 0.0:
			get_tree().create_timer(offset).timeout.connect(func():
				_spawn_zombie(z_data, lane)
			)
		else:
			_spawn_zombie(z_data, lane)
			
	if current_wave_idx >= total_waves - 1:
		all_waves_spawned = true

func _spawn_zombie(z_data: ZombieData, lane: int) -> void:
	if z_data == null:
		return
	
	var zombie_inst: Node2D = null
	if z_data.zombie_scene != null:
		zombie_inst = z_data.zombie_scene.instantiate()
	else:
		# Fallback to base zombie
		var base_sc := load("res://scenes/zombies/normal_zombie.tscn") as PackedScene
		if base_sc != null:
			zombie_inst = base_sc.instantiate()
	
	if zombie_inst == null:
		return
		
	# Compute lane Y coordinate
	var lane_y: float = 175.0 + lane * 108.0
	zombie_inst.position = Vector2(SPAWN_X, lane_y)
	if zombie_inst.has_method("setup_zombie"):
		zombie_inst.setup_zombie(z_data, lane)
	
	add_child(zombie_inst)
	alive_zombies.append(zombie_inst)
	EventBus.zombie_spawned.emit(zombie_inst)

func _on_zombie_died(zombie: Node2D) -> void:
	alive_zombies.erase(zombie)
	if all_waves_spawned and alive_zombies.is_empty():
		is_spawning_active = false
		EventBus.game_over.emit(true)

