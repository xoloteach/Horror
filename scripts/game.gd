extends Node3D
## Run/session coordinator and data-driven encounter director.
##
## A complete run is six authored encounters: tutorial minions, mixed melee,
## ranged pressure, a horde, an elite gauntlet, then the Bone Jarl. Three boon
## choices between encounters create a small but complete progression loop.

enum SessionState { TITLE, INTRO, INTERMISSION, PLAYING, BOON, PAUSED, VICTORY, DEFEAT, RESTARTING }

signal session_state_changed(state: SessionState)
signal encounter_started(number: int, title: String)
signal encounter_cleared(number: int)
signal boon_offered(options: Array[Dictionary])
signal boon_selected(id: StringName)

const FINAL_ENCOUNTER := 6
const MAX_ALIVE := 6
const INTERMISSION_TIME := 2.8

const ENCOUNTERS := [
	{
		"title": "THE RESTLESS DEAD",
		"subtitle": "Learn their rhythm. Break their bones.",
		"roles": [Draugr.Archetype.MINION, Draugr.Archetype.MINION, Draugr.Archetype.MINION],
	},
	{
		"title": "SHIELDS IN THE SNOW",
		"subtitle": "Warriors hold the line. A rogue hunts your flank.",
		"roles": [Draugr.Archetype.WARRIOR, Draugr.Archetype.WARRIOR, Draugr.Archetype.ROGUE],
	},
	{
		"title": "THE HEXED CHOIR",
		"subtitle": "Recall through the line. Silence the mage.",
		"roles": [Draugr.Archetype.WARRIOR, Draugr.Archetype.MAGE,
				Draugr.Archetype.ROGUE, Draugr.Archetype.MINION],
	},
	{
		"title": "BONE TIDE",
		"subtitle": "No ground. No mercy.",
		"roles": [Draugr.Archetype.MINION, Draugr.Archetype.MINION,
				Draugr.Archetype.MINION, Draugr.Archetype.MINION,
				Draugr.Archetype.ROGUE, Draugr.Archetype.ROGUE,
				Draugr.Archetype.MAGE],
	},
	{
		"title": "THE BROKEN OATH",
		"subtitle": "The dead send everything they have.",
		"roles": [Draugr.Archetype.WARRIOR, Draugr.Archetype.WARRIOR,
				Draugr.Archetype.WARRIOR, Draugr.Archetype.ROGUE,
				Draugr.Archetype.ROGUE, Draugr.Archetype.MAGE,
				Draugr.Archetype.MAGE],
	},
	{
		"title": "HROTHGAR, THE BONE JARL",
		"subtitle": "Cut the oath from his ribs.",
		"roles": [Draugr.Archetype.BOSS, Draugr.Archetype.MINION,
				Draugr.Archetype.MINION],
	},
]

const BOONS: Array[Dictionary] = [
	{
		"id": &"fury", "title": "FURY OF TYR",
		"description": "+18% axe and melee damage",
		"rune": "ᛏ",
	},
	{
		"id": &"vitality", "title": "HEART OF IDUNN",
		"description": "+28 maximum vitality and heal",
		"rune": "ᛃ",
	},
	{
		"id": &"focus", "title": "EYE OF ODIN",
		"description": "+25 maximum focus; perfect dodges restore more",
		"rune": "ᛟ",
	},
]

var arena: Arena
var player: Player
var hud: Hud
var touch: TouchControls

var session_state: SessionState = SessionState.TITLE
var wave := 0
var kills := 0
var _alive := 0
var _spawn_queue: Array[int] = []
var _intermission := 1.8
var _spawn_generation := 0
var _boss: Draugr
var _run_time := 0.0
var _boons_taken: Array[StringName] = []
var _state_before_pause: SessionState = SessionState.PLAYING


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	seed(0xB0A7) # deterministic composition/QA; gameplay variation comes from AI timing
	Juice.reset()
	Boot.reset_virtual_input()
	Sfx.start_ambience()

	arena = Arena.new()
	arena.name = "FrozenKeep"
	add_child(arena)

	player = Player.new()
	player.name = "Eirik"
	add_child(player)
	player.global_position = Vector3(0, 0.12, 5.0)
	player.died.connect(_on_player_died)

	hud = Hud.new()
	hud.name = "Hud"
	add_child(hud)
	hud.bind(player)
	hud.start_requested.connect(start_run)
	hud.boon_chosen.connect(choose_boon)
	hud.restart_requested.connect(restart_run)
	hud.pause_requested.connect(pause_run)
	hud.resume_requested.connect(resume_run)

	touch = TouchControls.new()
	touch.name = "TouchControls"
	add_child(touch)
	touch.visible = false

	if DisplayServer.is_touchscreen_available():
		hud.message("LEFT STICK MOVE  ·  DRAG LOOK  ·  AIM THEN THROW", 6.0)
	else:
		hud.message("WASD MOVE  ·  LMB COMBO  ·  F HEAVY  ·  RMB+LMB THROW  ·  R RECALL  ·  SPACE DODGE", 7.0)
	player.set_control_enabled(false)
	_set_session_state(SessionState.TITLE)
	hud.show_title()
	print("[MidgardFury] READY | method=%s | adapter=%s | touch=%s" % [
		str(ProjectSettings.get_setting("rendering/renderer/rendering_method")),
		RenderingServer.get_video_adapter_name(),
		str(DisplayServer.is_touchscreen_available()),
	])


func _process(delta: float) -> void:
	if session_state in [SessionState.PLAYING, SessionState.INTERMISSION]:
		_run_time += delta
	hud.wave = wave
	hud.kills = kills
	hud.enemies_left = _alive + _spawn_queue.size()

	match session_state:
		SessionState.TITLE, SessionState.PAUSED:
			pass
		SessionState.INTRO, SessionState.INTERMISSION:
			_intermission -= delta
			if _intermission <= 0.0:
				_start_encounter(wave + 1)
		SessionState.PLAYING:
			if _alive < MAX_ALIVE and not _spawn_queue.is_empty():
				_spawn_next_batch()
			elif _alive == 0 and _spawn_queue.is_empty():
				_clear_encounter()
		SessionState.BOON:
			_handle_boon_keys()
		SessionState.VICTORY, SessionState.DEFEAT:
			if Input.is_action_just_pressed("restart"):
				restart_run()
		_:
			pass


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if session_state == SessionState.PAUSED:
			resume_run()
		elif session_state in [SessionState.PLAYING, SessionState.INTERMISSION]:
			pause_run()
		return
	if session_state == SessionState.BOON and event is InputEventKey and event.pressed:
		var key := (event as InputEventKey).physical_keycode
		if key in [KEY_1, KEY_KP_1]:
			choose_boon(0)
		elif key in [KEY_2, KEY_KP_2]:
			choose_boon(1)
		elif key in [KEY_3, KEY_KP_3]:
			choose_boon(2)


func _handle_boon_keys() -> void:
	# _unhandled_input handles physical keyboard events; this hook exists for
	# deterministic QA, which calls choose_boon directly.
	pass


func _set_session_state(next: SessionState) -> void:
	session_state = next
	Sfx.set_combat(next == SessionState.PLAYING)
	if touch != null:
		touch.set_input_allowed(next in [SessionState.INTRO,
				SessionState.INTERMISSION, SessionState.PLAYING])
	session_state_changed.emit(next)
	if hud != null and hud.has_method("set_session_state"):
		hud.set_session_state(next)


func start_run() -> void:
	if session_state != SessionState.TITLE:
		return
	hud.hide_title()
	player.set_control_enabled(true)
	_intermission = 1.35
	_set_session_state(SessionState.INTRO)
	hud.message("THE OATHBOUND AXE AWAKENS", 1.4)


func pause_run() -> void:
	if session_state not in [SessionState.PLAYING, SessionState.INTERMISSION]:
		return
	_state_before_pause = session_state
	_set_session_state(SessionState.PAUSED)
	player.set_control_enabled(false)
	hud.show_pause(true)
	get_tree().paused = true


func resume_run() -> void:
	if session_state != SessionState.PAUSED:
		return
	get_tree().paused = false
	hud.show_pause(false)
	_set_session_state(_state_before_pause)
	player.set_control_enabled(true)


# ---------------------------------------------------------------- encounters

func _start_encounter(number: int) -> void:
	if number < 1 or number > FINAL_ENCOUNTER:
		_victory()
		return
	wave = number
	var spec: Dictionary = ENCOUNTERS[number - 1]
	_spawn_queue.clear()
	for role in spec["roles"]:
		_spawn_queue.append(int(role))
	_set_session_state(SessionState.PLAYING)
	player.set_control_enabled(true)
	hud.message("%s\n%s" % [spec["title"], spec["subtitle"]], 3.2)
	encounter_started.emit(number, spec["title"])
	Sfx.play_2d("roar_draugr", -5.0, 0.80)
	_spawn_next_batch()


func _spawn_next_batch() -> void:
	var count := mini(MAX_ALIVE - _alive, _spawn_queue.size())
	if count <= 0:
		return
	var points := arena.spawn_points(count, player.global_position, 10.0)
	for i in count:
		var role := _spawn_queue.pop_front() as Draugr.Archetype
		# The Jarl always enters alone before his minions join later.
		if role == Draugr.Archetype.BOSS and _alive > 0:
			_spawn_queue.push_front(role)
			continue
		_spawn_enemy(points[i], role)
		if role == Draugr.Archetype.BOSS:
			break


func _spawn_enemy(position: Vector3, role: Draugr.Archetype) -> void:
	var enemy := Draugr.new()
	enemy.name = "%s_%02d" % [Draugr.Archetype.keys()[role], kills + _alive + 1]
	enemy.position = position + Vector3.UP * 0.12
	enemy.configure(player, role, wave)
	add_child(enemy)
	enemy.died.connect(_on_enemy_died)
	_alive += 1
	if role == Draugr.Archetype.BOSS:
		_boss = enemy
		enemy.health_changed.connect(_on_boss_health)
		enemy.boss_phase_changed.connect(_on_boss_phase)
		if hud.has_method("show_boss"):
			hud.show_boss("HROTHGAR · THE BONE JARL", enemy.max_health)


func _on_enemy_died(enemy: Draugr) -> void:
	_alive = maxi(0, _alive - 1)
	kills += 1
	if enemy == _boss:
		_boss = null
		if hud.has_method("hide_boss"):
			hud.hide_boss()
	if session_state == SessionState.PLAYING and not _spawn_queue.is_empty():
		var generation := _spawn_generation
		await get_tree().create_timer(0.65 + randf() * 0.55).timeout
		if generation == _spawn_generation and session_state == SessionState.PLAYING:
			_spawn_next_batch()


func _clear_encounter() -> void:
	if session_state != SessionState.PLAYING:
		return
	encounter_cleared.emit(wave)
	player.heal(18.0)
	if wave >= FINAL_ENCOUNTER:
		_victory()
		return
	if wave in [1, 3, 5]:
		_offer_boon()
	else:
		_set_session_state(SessionState.INTERMISSION)
		_intermission = INTERMISSION_TIME
		hud.message("ENCOUNTER CLEARED", 1.8)


# ---------------------------------------------------------------- progression

func _offer_boon() -> void:
	_set_session_state(SessionState.BOON)
	player.set_control_enabled(false)
	boon_offered.emit(BOONS)
	if hud.has_method("show_boons"):
		hud.show_boons(BOONS)
	else:
		hud.message("CHOOSE A BOON  ·  [1] FURY  [2] VITALITY  [3] FOCUS", 30.0)


func choose_boon(index: int) -> void:
	if session_state != SessionState.BOON or index < 0 or index >= BOONS.size():
		return
	var boon: Dictionary = BOONS[index]
	var id: StringName = boon["id"]
	player.apply_upgrade(id)
	_boons_taken.append(id)
	boon_selected.emit(id)
	if hud.has_method("hide_boons"):
		hud.hide_boons()
	Sfx.play_2d("boon", -2.0, 1.02)
	_set_session_state(SessionState.INTERMISSION)
	_intermission = 1.8
	player.set_control_enabled(true)
	hud.message("%s CLAIMED" % boon["title"], 1.6)


# ---------------------------------------------------------------- end states

func _on_player_died() -> void:
	if session_state in [SessionState.DEFEAT, SessionState.VICTORY]:
		return
	_spawn_generation += 1
	_spawn_queue.clear()
	_set_session_state(SessionState.DEFEAT)
	player.set_control_enabled(false)
	_freeze_enemies()
	hud.game_over = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if hud.has_method("show_results"):
		hud.show_results(false, kills, wave, _run_time, _boons_taken)


func _victory() -> void:
	if session_state in [SessionState.DEFEAT, SessionState.VICTORY]:
		return
	_spawn_generation += 1
	_spawn_queue.clear()
	_set_session_state(SessionState.VICTORY)
	player.set_control_enabled(false)
	_freeze_enemies()
	hud.victory = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if hud.has_method("show_results"):
		hud.show_results(true, kills, wave, _run_time, _boons_taken)


func _freeze_enemies() -> void:
	for node in get_tree().get_nodes_in_group("enemy"):
		if node is Draugr:
			(node as Draugr).set_physics_process(false)


func restart_run() -> void:
	if session_state == SessionState.RESTARTING:
		return
	_set_session_state(SessionState.RESTARTING)
	get_tree().paused = false
	_spawn_generation += 1
	Juice.reset()
	Boot.reset_virtual_input()
	get_tree().reload_current_scene()


func _on_boss_health(current: float, maximum: float) -> void:
	if hud.has_method("set_boss_health"):
		hud.set_boss_health(current, maximum)


func _on_boss_phase(phase: int) -> void:
	hud.message("THE JARL BREAKS HIS CHAINS · PHASE %d" % phase, 2.2)
	if hud.has_method("boss_phase"):
		hud.boss_phase(phase)
