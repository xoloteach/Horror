# AudioManager autoload: pooled 2D/3D players for the 12 synthesized SFX.
extends Node

const SOUND_NAMES: Array[String] = [
	"swing_light", "swing_heavy", "flesh_slice", "blood_impact",
	"stone_impact", "wood_impact", "recall_whistle", "catch_metal",
	"grunt_player", "roar_enemy", "footstep_heavy", "embed_thunk",
]

var sounds: Dictionary = {}
var players_2d: Array[AudioStreamPlayer] = []
var players_3d: Array[AudioStreamPlayer3D] = []
var _i2d: int = 0
var _i3d: int = 0


func _ready() -> void:
	for n in SOUND_NAMES:
		var path := "res://assets/audio/%s.wav" % n
		if ResourceLoader.exists(path):
			sounds[n] = load(path)
		else:
			push_warning("AudioManager: missing " + path)
	for i in 12:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		players_2d.append(p)
	for i in 20:
		var p3 := AudioStreamPlayer3D.new()
		p3.bus = "Master"
		p3.max_distance = 45.0
		p3.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p3.unit_size = 6.0
		add_child(p3)
		players_3d.append(p3)


func play_2d(sound_name: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if not sounds.has(sound_name):
		return
	var p := players_2d[_i2d]
	_i2d = (_i2d + 1) % players_2d.size()
	p.stream = sounds[sound_name]
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.play()


func play_3d(sound_name: String, pos: Vector3, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if not sounds.has(sound_name):
		return
	var p := players_3d[_i3d]
	_i3d = (_i3d + 1) % players_3d.size()
	p.stream = sounds[sound_name]
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.global_position = pos
	p.play()
