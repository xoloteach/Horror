extends Node
## Data-driven layered audio service using curated CC0 field/foley packs.
## Generated prototype clips survive only where they provide a unique tonal layer
## (recall resonance and player voice); every physical contact now includes a
## downloaded foley layer and material-specific variants.

const EVENTS := {
	"step": [
		"res://assets/production/audio/impacts/footstep_snow_000.ogg",
		"res://assets/production/audio/impacts/footstep_snow_001.ogg",
		"res://assets/production/audio/impacts/footstep_snow_002.ogg",
		"res://assets/production/audio/impacts/footstep_snow_003.ogg",
		"res://assets/production/audio/impacts/footstep_snow_004.ogg",
	],
	"step_stone": [
		"res://assets/production/audio/impacts/footstep_concrete_000.ogg",
		"res://assets/production/audio/impacts/footstep_concrete_001.ogg",
		"res://assets/production/audio/impacts/footstep_concrete_002.ogg",
		"res://assets/production/audio/impacts/footstep_concrete_003.ogg",
		"res://assets/production/audio/impacts/footstep_concrete_004.ogg",
	],
	"swing": [
		"res://assets/production/audio/swishes/swish-2.wav",
		"res://assets/production/audio/swishes/swish-4.wav",
		"res://assets/production/audio/swishes/swish-7.wav",
	],
	"swing_heavy": [
		"res://assets/production/audio/swishes/swish-10.wav",
		"res://assets/production/audio/swishes/swish-11.wav",
		"res://assets/production/audio/swishes/swish-13.wav",
	],
	"throw_release": [
		"res://assets/production/audio/swishes/swish-8.wav",
		"res://assets/production/audio/swishes/swish-12.wav",
	],
	"dodge": [
		"res://assets/production/audio/swishes/swish-1.wav",
		"res://assets/production/audio/foley/cloth2.ogg",
		"res://assets/production/audio/foley/cloth4.ogg",
	],
	"flesh_body": [
		"res://assets/production/audio/impacts/impactPunch_heavy_000.ogg",
		"res://assets/production/audio/impacts/impactPunch_heavy_001.ogg",
		"res://assets/production/audio/impacts/impactPunch_heavy_003.ogg",
	],
	"flesh_wet": [
		"res://assets/audio/hit_flesh.wav",
		"res://assets/audio/hit_flesh_alt.wav",
	],
	"stone_crack": [
		"res://assets/production/audio/impacts/impactMining_000.ogg",
		"res://assets/production/audio/impacts/impactMining_002.ogg",
		"res://assets/production/audio/impacts/impactMining_004.ogg",
	],
	"stone_debris": [
		"res://assets/production/audio/creatures/item_stone_01.ogg",
		"res://assets/production/audio/creatures/item_stone_03.ogg",
	],
	"wood_crack": [
		"res://assets/production/audio/impacts/impactWood_heavy_000.ogg",
		"res://assets/production/audio/impacts/impactWood_heavy_002.ogg",
		"res://assets/production/audio/impacts/impactWood_heavy_004.ogg",
	],
	"metal_clang": [
		"res://assets/production/audio/impacts/impactMetal_heavy_000.ogg",
		"res://assets/production/audio/impacts/impactMetal_heavy_002.ogg",
		"res://assets/production/audio/impacts/impactMetal_heavy_004.ogg",
	],
	"catch_resonance": ["res://assets/audio/catch_metal.wav"],
	"recall_whistle": ["res://assets/audio/recall_whistle.wav"],
	"grunt": [
		"res://assets/audio/grunt_1.wav", "res://assets/audio/grunt_2.wav",
		"res://assets/audio/grunt_3.wav",
	],
	"hurt_player": ["res://assets/audio/hurt_player.wav"],
	"roar": [
		"res://assets/production/audio/creatures/creature_roar_01.ogg",
		"res://assets/production/audio/creatures/creature_roar_02.ogg",
		"res://assets/production/audio/creatures/creature_roar_03.ogg",
	],
	"enemy_hurt": [
		"res://assets/production/audio/creatures/creature_hurt_01.ogg",
		"res://assets/production/audio/creatures/creature_hurt_02.ogg",
	],
	"death_draugr": ["res://assets/production/audio/creatures/creature_die_01.ogg"],
	"stagger": [
		"res://assets/production/audio/impacts/impactSoft_heavy_000.ogg",
		"res://assets/production/audio/impacts/impactSoft_heavy_003.ogg",
	],
	"ui_click": [
		"res://assets/production/audio/foley/metalClick.ogg",
		"res://assets/production/audio/foley/metalLatch.ogg",
	],
	"boon": [
		"res://assets/production/audio/creatures/spell_01.ogg",
		"res://assets/production/audio/creatures/spell_02.ogg",
	],
}

const LAYERS := {
	"flesh": ["flesh_body", "flesh_wet"],
	"embed_stone": ["stone_crack", "stone_debris"],
	"embed_wood": ["wood_crack", "stone_debris"],
	"catch_metal": ["metal_clang", "catch_resonance"],
}

const BUS_BY_EVENT := {
	"grunt": "Voice", "hurt_player": "Voice", "roar": "Voice",
	"enemy_hurt": "Voice", "death_draugr": "Voice",
	"ui_click": "UI", "boon": "UI",
}
const GAIN_BY_EVENT := {
	"flesh_wet": -4.0, "stone_debris": -5.0, "catch_resonance": -2.5,
	"step": -2.0, "step_stone": -2.0,
}

const POOL_3D := 28
const POOL_2D := 10
const TITLE_MUSIC := "res://assets/production/audio/music/title.ogg"
const BATTLE_MUSIC := "res://assets/production/audio/music/battle.ogg"
const WIND := "res://assets/production/audio/ambience/winter_wind.mp3"
const FIRE := "res://assets/production/audio/ambience/fire_crackle.ogg"

var _cache := {}
var _pool3: Array[AudioStreamPlayer3D] = []
var _pool2: Array[AudioStreamPlayer] = []
var _next3 := 0
var _next2 := 0
var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _active_music: AudioStreamPlayer
var _wind: AudioStreamPlayer
var _fire: AudioStreamPlayer
var _combat_music := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in POOL_3D:
		var player := AudioStreamPlayer3D.new()
		player.max_distance = 46.0
		player.unit_size = 7.0
		player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_SQUARE_DISTANCE
		add_child(player)
		_pool3.append(player)
	for i in POOL_2D:
		var player := AudioStreamPlayer.new()
		add_child(player)
		_pool2.append(player)
	_music_a = _loop_player("Music")
	_music_b = _loop_player("Music")
	_music_a.volume_db = -80.0
	_music_b.volume_db = -80.0
	_active_music = _music_a
	_wind = _loop_player("Ambience")
	_fire = _loop_player("Ambience")


func _loop_player(bus_name: String) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.bus = bus_name
	add_child(player)
	return player


func _stream(path: String, loop := false) -> AudioStream:
	var key := path + ("#loop" if loop else "")
	if _cache.has(key):
		return _cache[key]
	if not ResourceLoader.exists(path):
		push_warning("Sfx missing stream: %s" % path)
		_cache[key] = null
		return null
	var stream: AudioStream = load(path)
	if loop:
		stream = stream.duplicate()
		if stream is AudioStreamOggVorbis:
			(stream as AudioStreamOggVorbis).loop = true
		elif stream is AudioStreamMP3:
			(stream as AudioStreamMP3).loop = true
	_cache[key] = stream
	return stream


func _event_path(event: String) -> String:
	if not EVENTS.has(event):
		push_warning("Unknown audio event: %s" % event)
		return ""
	var variants: Array = EVENTS[event]
	return variants[randi() % variants.size()]


func play_3d(event: String, position: Vector3, volume_db := 0.0,
		pitch := 1.0, pitch_jitter := 0.055) -> void:
	if LAYERS.has(event):
		for layer in LAYERS[event]:
			_play_single_3d(str(layer), position, volume_db, pitch, pitch_jitter)
		return
	_play_single_3d(event, position, volume_db, pitch, pitch_jitter)


func _play_single_3d(event: String, position: Vector3, volume_db: float,
		pitch: float, pitch_jitter: float) -> void:
	var path := _event_path(event)
	if path.is_empty():
		return
	var stream := _stream(path)
	if stream == null:
		return
	var player := _pool3[_next3]
	_next3 = (_next3 + 1) % POOL_3D
	player.stream = stream
	player.global_position = position
	player.volume_db = volume_db + float(GAIN_BY_EVENT.get(event, 0.0))
	player.pitch_scale = maxf(0.05, pitch + randf_range(-pitch_jitter, pitch_jitter))
	player.bus = BUS_BY_EVENT.get(event, "Sfx")
	player.play()


func play_2d(event: String, volume_db := 0.0,
		pitch := 1.0, pitch_jitter := 0.045) -> void:
	if LAYERS.has(event):
		for layer in LAYERS[event]:
			_play_single_2d(str(layer), volume_db, pitch, pitch_jitter)
		return
	_play_single_2d(event, volume_db, pitch, pitch_jitter)


func _play_single_2d(event: String, volume_db: float,
		pitch: float, pitch_jitter: float) -> void:
	var path := _event_path(event)
	if path.is_empty():
		return
	var stream := _stream(path)
	if stream == null:
		return
	var player := _pool2[_next2]
	_next2 = (_next2 + 1) % POOL_2D
	player.stream = stream
	player.volume_db = volume_db + float(GAIN_BY_EVENT.get(event, 0.0))
	player.pitch_scale = maxf(0.05, pitch + randf_range(-pitch_jitter, pitch_jitter))
	player.bus = BUS_BY_EVENT.get(event, "Sfx")
	player.play()


func start_ambience() -> void:
	if not _wind.playing:
		_wind.stream = _stream(WIND, true)
		_wind.volume_db = -5.0
		_wind.play()
	if not _fire.playing:
		_fire.stream = _stream(FIRE, true)
		_fire.volume_db = -11.0
		_fire.play()
	set_combat(false, true)


func set_combat(enabled: bool, immediate := false) -> void:
	if _combat_music == enabled and _active_music.playing:
		return
	_combat_music = enabled
	var next := _music_b if _active_music == _music_a else _music_a
	next.stream = _stream(BATTLE_MUSIC if enabled else TITLE_MUSIC, true)
	next.volume_db = -80.0
	next.play()
	if immediate:
		_active_music.stop()
		next.volume_db = 0.0
	else:
		var tween := create_tween()
		tween.set_parallel(true)
		tween.tween_property(_active_music, "volume_db", -40.0, 1.25)
		tween.tween_property(next, "volume_db", 0.0, 1.25)
		tween.chain().tween_callback(_active_music.stop)
	_active_music = next


func make_loop(event: String, parent: Node3D, volume_db := -6.0) -> AudioStreamPlayer3D:
	var path := _event_path(event)
	var player := AudioStreamPlayer3D.new()
	player.stream = _stream(path, true)
	player.volume_db = volume_db
	player.max_distance = 60.0
	player.unit_size = 8.0
	player.bus = "Sfx"
	parent.add_child(player)
	return player
