extends Node
## Pooled audio playback with bus routing and pitch variation.
##
## Every sound is a short one-shot, so a fixed pool of players is reused instead
## of allocating a node per hit. Variant sets ("step", "grunt", ...) pick a random
## sibling sample and jitter pitch so repeated hits never sound machine-gunned.

const DIR := "res://assets/audio/"

const VARIANTS := {
	"step": ["step_1", "step_2", "step_3"],
	"grunt": ["grunt_1", "grunt_2", "grunt_3"],
	"swing": ["swing_light", "swing_light_alt"],
	"flesh": ["hit_flesh", "hit_flesh_alt"],
	"roar": ["roar_draugr", "roar_draugr_alt"],
}

## name -> bus. Anything unlisted routes to "Sfx".
const BUSES := {
	"grunt_1": "Voice", "grunt_2": "Voice", "grunt_3": "Voice",
	"hurt_player": "Voice", "roar_draugr": "Voice", "roar_draugr_alt": "Voice",
	"death_draugr": "Voice",
}

const POOL_3D := 18
const POOL_2D := 6

var _cache := {}
var _pool3: Array[AudioStreamPlayer3D] = []
var _pool2: Array[AudioStreamPlayer] = []
var _next3 := 0
var _next2 := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in POOL_3D:
		var p := AudioStreamPlayer3D.new()
		p.max_distance = 42.0
		p.unit_size = 6.0
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_SQUARE_DISTANCE
		add_child(p)
		_pool3.append(p)
	for i in POOL_2D:
		var p2 := AudioStreamPlayer.new()
		add_child(p2)
		_pool2.append(p2)


func _stream(name: String) -> AudioStream:
	if _cache.has(name):
		return _cache[name]
	var path := DIR + name + ".wav"
	if not ResourceLoader.exists(path):
		push_warning("Sfx: missing stream %s" % path)
		_cache[name] = null
		return null
	var s: AudioStream = load(path)
	_cache[name] = s
	return s


func _resolve(name: String) -> String:
	if VARIANTS.has(name):
		var list: Array = VARIANTS[name]
		return list[randi() % list.size()]
	return name


## Positional one-shot.
func play_3d(name: String, pos: Vector3, volume_db := 0.0,
		pitch := 1.0, pitch_jitter := 0.06) -> void:
	var resolved := _resolve(name)
	var s := _stream(resolved)
	if s == null:
		return
	var p := _pool3[_next3]
	_next3 = (_next3 + 1) % POOL_3D
	p.stream = s
	p.global_position = pos
	p.volume_db = volume_db
	p.pitch_scale = maxf(0.05, pitch + randf_range(-pitch_jitter, pitch_jitter))
	p.bus = BUSES.get(resolved, "Sfx")
	p.play()


## Non-positional one-shot (UI, player-centric sounds like the catch).
func play_2d(name: String, volume_db := 0.0,
		pitch := 1.0, pitch_jitter := 0.05) -> void:
	var resolved := _resolve(name)
	var s := _stream(resolved)
	if s == null:
		return
	var p := _pool2[_next2]
	_next2 = (_next2 + 1) % POOL_2D
	p.stream = s
	p.volume_db = volume_db
	p.pitch_scale = maxf(0.05, pitch + randf_range(-pitch_jitter, pitch_jitter))
	p.bus = BUSES.get(resolved, "Sfx")
	p.play()


## Returns a dedicated looping player the caller owns (used for axe flight).
func make_loop(name: String, parent: Node3D, volume_db := -6.0) -> AudioStreamPlayer3D:
	var s := _stream(name)
	var p := AudioStreamPlayer3D.new()
	p.stream = s
	p.volume_db = volume_db
	p.max_distance = 60.0
	p.unit_size = 8.0
	p.bus = "Sfx"
	parent.add_child(p)
	return p
