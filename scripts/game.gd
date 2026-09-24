extends Node3D
## Main scene: assembles the world, runs the wave loop, owns restart.
##
## The whole scene tree is built here in code rather than stored as a .tscn. The
## project is procedural end to end (meshes from Blender scripts, audio from a
## synthesiser), so constructing the tree the same way keeps one source of truth
## and avoids brittle resource wiring.

const FINAL_WAVE := 6
const MAX_ALIVE := 6
const WAVE_BREAK := 3.4

var arena: Arena
var player: Player
var hud: Hud
var touch: TouchControls

var wave := 0
var kills := 0
var _alive := 0
var _pending := 0
var _break_t := 0.0
var _running := false
var _ending := false


func _ready() -> void:
	randomize()
	Juice.reset()

	arena = Arena.new()
	arena.name = "Arena"
	add_child(arena)

	player = Player.new()
	player.name = "Player"
	add_child(player)
	player.global_position = Vector3(0, 0.1, 0)
	player.died.connect(_on_player_died)

	hud = Hud.new()
	hud.name = "Hud"
	add_child(hud)
	hud.bind(player)

	touch = TouchControls.new()
	touch.name = "TouchControls"
	add_child(touch)

	if DisplayServer.is_touchscreen_available():
		hud.message("Left stick to move · drag to look · AIM then THROW", 7.0)
	else:
		hud.message("WASD move · mouse look · LMB attack · "
				+ "hold RMB aim · LMB throw · R recall · SPACE dodge", 8.5)

	_break_t = 2.2
	_running = true

	# Boot beacon: surfaces in the browser console, and is what the automated
	# browser smoke test waits on to confirm the WebGL build actually came up.
	print("[MidgardFury] READY | method=%s | adapter=%s | touch=%s" % [
		str(ProjectSettings.get_setting("rendering/renderer/rendering_method")),
		RenderingServer.get_video_adapter_name(),
		str(DisplayServer.is_touchscreen_available()),
	])


func _process(delta: float) -> void:
	hud.wave = wave
	hud.kills = kills
	hud.enemies_left = _alive + _pending

	if not _running:
		if Input.is_action_just_pressed("restart"):
			_restart()
		return

	if _alive + _pending == 0:
		_break_t -= delta
		if _break_t <= 0.0:
			if wave >= FINAL_WAVE:
				_win()
			else:
				_start_wave(wave + 1)


func _restart() -> void:
	Juice.reset()
	Boot.touch_move = Vector2.ZERO
	get_tree().reload_current_scene()


# ------------------------------------------------------------------ wave loop

func _start_wave(n: int) -> void:
	wave = n
	_pending = mini(2 + n, MAX_ALIVE + 2)
	hud.message("WAVE %d" % n, 2.0)
	Sfx.play_2d("roar_draugr", -6.0, 0.82)
	_spawn_batch()


func _spawn_batch() -> void:
	var room := MAX_ALIVE - _alive
	var n := mini(_pending, room)
	if n <= 0:
		return
	var pts := arena.spawn_points(n, player.global_position, 11.0)
	for i in n:
		_spawn_one(pts[i])
	_pending -= n


func _spawn_one(pos: Vector3) -> void:
	var d := Draugr.new()
	d.name = "Draugr%d" % (kills + _alive + 1)
	add_child(d)
	d.global_position = pos + Vector3.UP * 0.15
	d.set_player(player)
	d.died.connect(_on_enemy_died)
	_alive += 1
	# scale menace with the wave: later draugr are tougher
	d.health = Draugr.MAX_HEALTH * (1.0 + 0.11 * float(maxi(0, wave - 1)))


func _on_enemy_died(_d: Draugr) -> void:
	_alive = maxi(0, _alive - 1)
	kills += 1
	if _pending > 0:
		# trickle reinforcements in as space frees up
		await get_tree().create_timer(randf_range(0.5, 1.4)).timeout
		if _running:
			_spawn_batch()
	if _alive + _pending == 0:
		_break_t = WAVE_BREAK


func _on_player_died() -> void:
	if _ending:
		return
	_ending = true
	_running = false
	hud.game_over = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _win() -> void:
	if _ending:
		return
	_ending = true
	_running = false
	hud.victory = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
