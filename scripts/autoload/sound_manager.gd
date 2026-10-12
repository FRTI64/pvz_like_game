extends Node

# SoundManager handles sound playback and web audio unlock.
# Includes procedural synthesizers so no external audio files are required!

var is_audio_unlocked: bool = false
var audio_players: Array[AudioStreamPlayer] = []
const POOL_SIZE: int = 12

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Create pool of players for polyphonic sounds
	for i in range(POOL_SIZE):
		var player := AudioStreamPlayer.new()
		player.bus = "Master"
		add_child(player)
		audio_players.append(player)

func _input(event: InputEvent) -> void:
	if not is_audio_unlocked:
		if event is InputEventMouseButton or event is InputEventKey or event is InputEventScreenTouch:
			is_audio_unlocked = true
			# In HTML5 exports, this first user gesture permits web audio context
			AudioServer.set_bus_mute(0, false)

func play_sound(sound_type: String) -> void:
	var stream: AudioStream = _get_or_generate_sound(sound_type)
	if stream == null:
		return
	
	# Find free player in pool
	for player in audio_players:
		if not player.playing:
			player.stream = stream
			player.play()
			return
	
	# If all busy, reuse the first one
	audio_players[0].stream = stream
	audio_players[0].play()

# Procedurally generate audio streams for iconic PVZ sound effects
func _get_or_generate_sound(type: String) -> AudioStream:
	match type:
		"shoot":
			return _generate_tone_sweep(480.0, 240.0, 0.09, 0.25)
		"splat":
			return _generate_noise_burst(0.08, 0.22)
		"sun":
			return _generate_chime_chord([523.25, 659.25, 783.99, 1046.5], 0.25)
		"plant":
			return _generate_tone_sweep(160.0, 80.0, 0.12, 0.35)
		"chomp":
			return _generate_tone_sweep(280.0, 140.0, 0.1, 0.3)
		"boom":
			return _generate_explosion(0.6, 0.5)
		"lawnmower":
			return _generate_engine_hum(1.0)
		"huge_wave":
			return _generate_siren(0.8)
		"win":
			return _generate_fanfare()
		"lose":
			return _generate_tone_sweep(220.0, 55.0, 1.2, 0.4)
		_:
			return null

# Procedural synthesis helpers using AudioStreamWAV
func _generate_tone_sweep(start_freq: float, end_freq: float, duration: float, volume: float) -> AudioStreamWAV:
	var sample_rate: int = 22050
	var total_samples: int = int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(total_samples)
	
	var phase: float = 0.0
	for i in range(total_samples):
		var t: float = float(i) / float(total_samples)
		var freq: float = lerp(start_freq, end_freq, t)
		phase += 2.0 * PI * freq / float(sample_rate)
		var env: float = (1.0 - t) * volume
		var val: float = sin(phase) * env
		var byte_val: int = clampi(int((val + 1.0) * 127.5), 0, 255)
		data[i] = byte_val
		
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_8_BITS
	wav.mix_rate = sample_rate
	wav.data = data
	return wav

func _generate_noise_burst(duration: float, volume: float) -> AudioStreamWAV:
	var sample_rate: int = 22050
	var total_samples: int = int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(total_samples)
	
	for i in range(total_samples):
		var t: float = float(i) / float(total_samples)
		var env: float = (1.0 - t) * volume
		var noise: float = (randf() * 2.0 - 1.0) * env
		var byte_val: int = clampi(int((noise + 1.0) * 127.5), 0, 255)
		data[i] = byte_val
		
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_8_BITS
	wav.mix_rate = sample_rate
	wav.data = data
	return wav

func _generate_chime_chord(frequencies: Array, duration: float) -> AudioStreamWAV:
	var sample_rate: int = 22050
	var total_samples: int = int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(total_samples)
	
	for i in range(total_samples):
		var t: float = float(i) / float(total_samples)
		var sum: float = 0.0
		for freq in frequencies:
			sum += sin(2.0 * PI * float(freq) * (float(i) / float(sample_rate)))
		sum = (sum / float(frequencies.size())) * (1.0 - t * 0.8) * 0.35
		var byte_val: int = clampi(int((sum + 1.0) * 127.5), 0, 255)
		data[i] = byte_val
		
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_8_BITS
	wav.mix_rate = sample_rate
	wav.data = data
	return wav

func _generate_explosion(duration: float, volume: float) -> AudioStreamWAV:
	var sample_rate: int = 22050
	var total_samples: int = int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(total_samples)
	
	var low_phase: float = 0.0
	for i in range(total_samples):
		var t: float = float(i) / float(total_samples)
		var env: float = pow(1.0 - t, 2.0) * volume
		low_phase += 2.0 * PI * 65.0 / float(sample_rate)
		var val: float = (randf() * 1.5 - 0.75 + sin(low_phase) * 0.8) * env
		var byte_val: int = clampi(int((val + 1.0) * 127.5), 0, 255)
		data[i] = byte_val
		
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_8_BITS
	wav.mix_rate = sample_rate
	wav.data = data
	return wav

func _generate_engine_hum(duration: float) -> AudioStreamWAV:
	var sample_rate: int = 22050
	var total_samples: int = int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(total_samples)
	
	var phase: float = 0.0
	for i in range(total_samples):
		var t: float = float(i) / float(total_samples)
		var freq: float = 120.0 + sin(float(i) * 0.05) * 30.0
		phase += 2.0 * PI * freq / float(sample_rate)
		var val: float = (sin(phase) + (randf() * 0.4 - 0.2)) * 0.25
		var byte_val: int = clampi(int((val + 1.0) * 127.5), 0, 255)
		data[i] = byte_val
		
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_8_BITS
	wav.mix_rate = sample_rate
	wav.data = data
	return wav

func _generate_siren(duration: float) -> AudioStreamWAV:
	var sample_rate: int = 22050
	var total_samples: int = int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(total_samples)
	
	var phase: float = 0.0
	for i in range(total_samples):
		var t: float = float(i) / float(total_samples)
		var freq: float = 350.0 + sin(t * PI * 6.0) * 150.0
		phase += 2.0 * PI * freq / float(sample_rate)
		var val: float = sin(phase) * 0.28
		var byte_val: int = clampi(int((val + 1.0) * 127.5), 0, 255)
		data[i] = byte_val
		
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_8_BITS
	wav.mix_rate = sample_rate
	wav.data = data
	return wav

func _generate_fanfare() -> AudioStreamWAV:
	return _generate_chime_chord([440.0, 554.37, 659.25, 880.0], 1.0)

