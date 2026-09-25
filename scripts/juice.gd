extends Node
## Global "game feel" service: hit-stop and camera trauma.
##
## Hit-stop works by collapsing Engine.time_scale for a very short real-time
## window. The restore timer must ignore time_scale, otherwise a 0.05 scale would
## stretch an 0.08s freeze into 1.6s of wall-clock and the game would feel
## broken rather than punchy.

signal trauma_added(amount: float)

## Trauma decays toward zero; shake magnitude is trauma^2 so small hits barely
## register while big ones kick hard.
const TRAUMA_DECAY := 1.9
const TRAUMA_MAX := 1.0

var trauma := 0.0
var trauma_dir := Vector3.ZERO

var _stop_token := 0
var _noise: FastNoiseLite
var _noise_t := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_noise = FastNoiseLite.new()
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise.frequency = 0.9
	_noise.seed = 1337


func _process(delta: float) -> void:
	_noise_t += delta * 34.0
	if trauma > 0.0:
		trauma = maxf(0.0, trauma - TRAUMA_DECAY * delta)
		if is_equal_approx(trauma, 0.0):
			trauma_dir = Vector3.ZERO


## Freeze time briefly. `scale` 0.05 for 0.08s is the heavy-impact default.
func hit_stop(scale: float = 0.05, duration: float = 0.08) -> void:
	if not Settings.hit_stop_enabled:
		return
	_stop_token += 1
	var token := _stop_token
	Engine.time_scale = clampf(scale, 0.01, 1.0)
	# process_always=true, process_in_physics=false, ignore_time_scale=TRUE
	await get_tree().create_timer(duration, true, false, true).timeout
	if token == _stop_token:
		Engine.time_scale = 1.0


func add_trauma(amount: float, direction: Vector3 = Vector3.ZERO) -> void:
	trauma = minf(TRAUMA_MAX, trauma + amount)
	if direction.length_squared() > 0.001:
		trauma_dir = direction.normalized()
	trauma_added.emit(amount)


## One call for "something hit something hard".
func impact(strength: float, direction: Vector3 = Vector3.ZERO,
		stop_scale: float = 0.05, stop_time: float = 0.08) -> void:
	add_trauma(strength, direction)
	if stop_time > 0.0:
		hit_stop(stop_scale, stop_time)


## Positional + rotational shake for the camera to consume each frame.
## Returns [offset: Vector3, roll: float].
func shake_sample(intensity_scale: float = 1.0) -> Array:
	if trauma <= 0.0:
		return [Vector3.ZERO, 0.0]
	var mag := trauma * trauma * intensity_scale * Settings.shake_scale
	var ox := _noise.get_noise_2d(_noise_t, 0.0)
	var oy := _noise.get_noise_2d(0.0, _noise_t)
	var oz := _noise.get_noise_2d(_noise_t, _noise_t)
	var offset := Vector3(ox, oy, oz * 0.5) * mag * 0.30
	# bias the shake along the impact direction so hits read directionally
	offset += trauma_dir * mag * 0.22
	var roll := oz * mag * 0.10
	return [offset, roll]


func reset() -> void:
	trauma = 0.0
	trauma_dir = Vector3.ZERO
	_stop_token += 1
	Engine.time_scale = 1.0
